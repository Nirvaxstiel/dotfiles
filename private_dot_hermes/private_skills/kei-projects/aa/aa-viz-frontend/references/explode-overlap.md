# Explode-overlap technique (crossover.js scatter)

Click a crowded scatter spot → the whole stack of overlapping points fans out
into a ring so each layer is individually hoverable; click empty space → they
merge back. This note holds the reusable code + the verification harness.

## Why coordinate hit-testing (the bug that shipped)
First implementation resolved the click via `e.target.closest('circle.hit')`.
Each model draws a transparent `.hit` circle (radius `r+6`) ON TOP of the
visible dot. Render order = model order, so a LARGE single-point bubble drawn
later covers a dense stack with its invisible hit-target and **steals the
click** — only that lone bubble's (size-1) cluster reacted, the stacked points
underneath never evacuated. Symptom: "I clicked the pile but it didn't do
anything / only moved one dot."

Fix: ignore `e.target`. Convert cursor → SVG coords and test geometry.

## Coordinate conversion (SVG viewBox ≠ CSS pixels)
```js
const toSvg = e => {
  const pt = svg.createSVGPoint();
  pt.x = e.clientX; pt.y = e.clientY;
  const m = svg.getScreenCTM().inverse();
  const p = pt.matrixTransform(m);
  return { x: p.x, y: p.y };
};
```

## Click handler (explode densest cluster under cursor)
```js
svg.addEventListener('click', e => {
  const lay = container.__crossoverLayout;
  if (!lay) return;
  const { x, y } = toSvg(e);
  let best = null, bestN = 1;
  for (const g in lay.groups) {
    const members = lay.groups[g];
    if (members.length < 2) continue;
    for (const i of members) {
      const dx = lay.layout[i].cx - x, dy = lay.layout[i].cy - y;
      const grab = lay.layout[i].r + 6;
      if (dx * dx + dy * dy <= grab * grab) {
        if (members.length > bestN) { bestN = members.length; best = +g; }
        break;
      }
    }
  }
  if (best != null) { window.__explodeCluster(container, best); e.stopPropagation(); return; }
  window.__collapseAll(container);
});
```

## Explode / collapse tween (rAF, cubic ease)
```js
window.__explodeCluster = function (container, g, opts) {
  opts = opts || {};
  const lay = container.__crossoverLayout;
  const members = lay.groups[g] || [];
  if (members.length < 2) return;
  const circles = [...container.querySelectorAll(`circle.pt[data-g="${g}"], circle.hit[data-g="${g}"]`)];
  const cx0 = members.reduce((s, i) => s + lay.layout[i].cx, 0) / members.length;
  const cy0 = members.reduce((s, i) => s + lay.layout[i].cy, 0) / members.length;
  const spread = 26 + members.length * 10;
  const slugToMember = {};
  members.forEach((i, n) => { slugToMember[lay.layout[i].m.slug] = n; });
  const membersAt = n => {
    const ang = (n / members.length) * Math.PI * 2 - Math.PI / 2;
    return [cx0 + Math.cos(ang) * spread, cy0 + Math.sin(ang) * spread];
  };
  const tween = targetFor => {
    circles.forEach(c => {
      const [ex, ey] = targetFor(slugToMember[c.dataset.slug]);   // ← slug→member, NOT index
      const sx = +c.getAttribute('cx'), sy = +c.getAttribute('cy');
      const t0 = performance.now();
      const dur = opts.instant ? 0 : 320;
      const step = now => {
        const p = dur ? Math.min((now - t0) / dur, 1) : 1;
        const e = 1 - Math.pow(1 - p, 3);
        c.setAttribute('cx', sx + (ex - sx) * e);
        c.setAttribute('cy', sy + (ey - sy) * e);
        if (p < 1) requestAnimationFrame(step);
      };
      requestAnimationFrame(step);
    });
  };
  if (container.__exploded === g) {
    container.__exploded = null;
    tween(n => [lay.layout[members[n]].cx, lay.layout[members[n]].cy]);
  } else {
    container.__exploded = g;
    tween(n => membersAt(n));
  }
};
```

## Verification harness (standalone node, no deps)
Replicate the math on synthetic points; assert separation + exact return.
User prefers this over jsdom (repo has no package.json).
```js
function cluster(pts) {
  const parent = pts.map((_, i) => i);
  const find = i => { while (parent[i] !== i) { parent[i] = parent[parent[i]]; i = parent[i]; } return i; };
  for (let i = 0; i < pts.length; i++)
    for (let j = i + 1; j < pts.length; j++) {
      const dx = pts[i].cx - pts[j].cx, dy = pts[i].cy - pts[j].cy, g = pts[i].r + pts[j].r + 6;
      if (dx*dx + dy*dy <= g*g) parent[find(i)] = find(j);
    }
  const of = pts.map((_, i) => find(i)), groups = {};
  of.forEach((g, i) => (groups[g] = groups[g] || []).push(i));
  return { of, groups };
}
// two overlapping points (4.5px apart) → one cluster of 2
// explode → ring, minSepAfter ≈ 92px ; collapse → maxErr 0.000
// assert minSepAfter > minSepBefore + 5 && collapseMaxErr < 1e-3
```
Expected on the REAL data (default intel vs cost_per_task axes): only 31
points render (cost_per_task is sparse), mostly spread → just 2 clusters of 2.
Real overlap appears with `context_window` as the SIZE axis: a 4-point cluster
+ 4 pairs. So test the feature on that axis combo.
