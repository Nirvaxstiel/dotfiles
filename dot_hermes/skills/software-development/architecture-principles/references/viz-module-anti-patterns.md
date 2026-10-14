# Viz Module Anti-Patterns

Concrete patterns found during a multi-view static dashboard refactor.

## 1. Dead Legend Variable

**Pattern:** Build a `leg` string with color dots, labels, size notes — then clear the legend div instead of assigning.

```javascript
// ❌ Dead — built but never assigned
let leg = '<strong style="color:var(--neon);">CREATOR</strong> ';
for (const c of creators) {
  const color = CREATOR_COLORS[c] || "#888";
  leg += `<span class="item"><span class="dot" style="background:${color}"></span>${c}</span>`;
}
// ... more concatenation ...
const legendEl = container.parentElement.querySelector('.viz-legend');
if (legendEl) legendEl.innerHTML = ''; // clears instead of = leg
```

**Found in:** 3 views (02, 04, 05). Each had 5-10 dead lines.

**Fix:** Either set `legendEl.innerHTML = leg` to display it, or remove the dead builder entirely.

## 2. Duplicate Filter Blocks

**Pattern:** Identical `if (window.__legendFilter) { ... }` block in multiple views.

```javascript
if (window.__legendFilter) {
  const slugOpacity = {};
  data.forEach(m => { slugOpacity[m.slug] = window.__modelOpacity(m); });
  const hideMode = window.__filterMode === 'hide';
  container.querySelectorAll('[data-slug]').forEach(el => {
    const op = slugOpacity[el.dataset.slug];
    if (op !== undefined && op < 1) {
      if (hideMode && op === 0) {
        el.style.display = 'none';
      } else {
        el.style.opacity = op;
      }
    }
  });
}
```

**Found in:** 3 views (02, 04, 05). ~13 lines × 3 = ~39 lines of identical code.

**Fix:** Extract to shared helper:
```javascript
function applyLegendFilter(container, models) {
  if (!window.__legendFilter) return;
  const slugOpacity = {};
  models.forEach(m => { slugOpacity[m.slug] = window.__modelOpacity(m); });
  const hideMode = window.__filterMode === 'hide';
  container.querySelectorAll('[data-slug]').forEach(el => {
    const op = slugOpacity[el.dataset.slug];
    if (op !== undefined && op < 1) {
      if (hideMode && op === 0) {
        el.style.display = 'none';
      } else {
        el.style.opacity = op;
      }
    }
  });
}
```

## 3. Render Parameter Name Mismatch

**Pattern:** One view's render function uses `allData` instead of the convention `data`.

```javascript
function render(container, allData) {
  // ...
  const models = buildCostData(allData);
  // ...
  renderCoverageNote(container, models.length, data.length, '...'); // ReferenceError: data is not defined
}
```

**Root cause:** Copy-paste from a shared helper call that references `data`, but this function's parameter is `allData`.

**Fix:** Standardize all render signatures as `function render(container, data)`. If a module must use a non-standard name, grep for all `data` references in that function before deploying.

**Detection:** The error trace shows `ReferenceError: data is not defined` at the render function's line. Boot code (`_boot.js:46`) passes `mod.render(container, data)` correctly — the bug is inside the module.

## 4. Legacy Shape Fallback

**Pattern:** Defensive code handling data shapes that no longer exist.

```javascript
const src = window.MODELS;
const models = Array.isArray(src) ? src : (src && src.models ? src.models : []);
```

The `src.models` branch was for an old `{ meta, models }` payload. Since `MODELS` is always an array, the fallback is unreachable.

**Fix:** Simplify to `const models = window.MODELS || [];`.

## 5. Coverage Note Inline Over Append

Coverage notes (data-gap messages) must be inlined into `innerHTML`, not appended via DOM:

```javascript
// ✅ Works
container.innerHTML = `<svg>...</svg>` + renderCoverageNote(...);

// ❌ Can be wiped by subsequent innerHTML = html or re-render
container.innerHTML = `<svg>...</svg>`;
// ... more code ...
container.appendChild(note);
```

## 6. File Naming Convention

Viz file names must match their `data-id` / tab label. Drift causes confusion:
- File: `05-speed-cost.js` with `data-id="04-speed-adjusted-cost"` → rename to `04-speed-adjusted-cost.js`
- Tab 02's file was `02-reasoning-tax.js` before the tab label "Cost Breakdown" → rename to `02-cost-breakdown.js`

When a user says "the js is named 05 but our view is 04, check that" — rename, don't justify.
