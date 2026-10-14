---
name: aa-viz-frontend
category: kei-projects
description: The dashboard.html + viz/* zero-build rendering layer for the LLM Provider Pricing Analysis repo. Covers the VIZ_REGISTRY/id contract (slugs, not numbers), positional tab numbering from script load order, the single #tooltip system (wireTooltips vs the removed getTooltipEl), and the crossover creator/reasoning color modes. Load when editing any viz/*.js, dashboard.html script order, tooltips, color toggles, or shared UI controls (search boxes, view/options buttons).
---

# AA Viz Frontend — dashboard.html + viz/* rendering layer

Zero-build vanilla JS dashboard. `dashboard.html` loads `processed.js` (data) then `viz/*.js` in order; each viz registers into `window.VIZ_REGISTRY`; `viz/_boot.js` assembles tabs/panels and lazy-renders. No framework, no build step.

## File map
- `dashboard.html` — script load order = **tab order**. Holds the tooltip element `<div class="tooltip" id="tooltip">`.
- `viz/_domain.js` — typed model wrappers (`ProjectionRow.load`), unwraps `PROCESSED_DATA.models`.
- `viz/_shared.js` — `CREATOR_COLORS` palette (curated; expanded until every registry creator has a color), `creatorColor(name)` golden-angle HSL generator (fallback for any creator NOT in the curated map — deterministic per name, high-contrast, never flat `#888`), `CREATOR_BORDER`, `wireTooltips`, `VIZ_NUM` formatters, `renderEmptyState`, `renderCoverageNote`, `applyLegendFilter`, `searchBox` (shared search-row builder). Helpers are ALSO exported on `window.VIZ_HELPERS` — that is the call surface other vizes use.
- `viz/_boot.js` — registry assembly, **positional numbering**, tab/panel generation, banner stats, legend wiring, `navigateTable`.
- `viz/crossover.js`, `cost-breakdown.js`, `provider-archetypes.js`, `cost-per-iq.js`, `data-table.js` — one viz each, pushes to `VIZ_REGISTRY`.

## Registry contract — ids are SLUGS, not numbers
Each viz ends with:
```js
window.VIZ_REGISTRY = window.VIZ_REGISTRY || [];
window.VIZ_REGISTRY.push({ id: 'crossover', name: 'The Crossover', subtitle: '…', render });
```
- `id` = stable **slug** (`crossover`, `cost-breakdown`, `provider-archetypes`, `cost-per-iq`, `data-table`). Used for `data-viz` attrs and `mount-<id>` DOM ids. Never numeric.
- `_boot.js` does **NOT sort** the registry — it keeps registration order, which equals the `dashboard.html` script order. The displayed tab number is `i + 1` (array index), derived purely from position.
- **To reorder tabs:** reorder the `<script>` tags in `dashboard.html`. Never hardcode numbers in a viz file. The filename prefix (e.g. `01-`) is cosmetic only and was removed; order comes from the script tag sequence.

## Merging or renaming vizes — discipline

When folding a viz function into another file (e.g. merging a provider toggle into a multi-view table):

- **Rename happens in the registry, not in `dashboard.html`.** The tab label is the `VIZ_REGISTRY` entry `name` (and `subtitle`). To rename: edit the `name`/`subtitle` in the viz's `VIZ_REGISTRY.push(...)` call. Do NOT touch `dashboard.html` for a name change. To change tab order: only reorder the `<script>` tags.
- **Deleting a merged viz requires two removals:** (1) the `.js` file, and (2) its `<script src="...">` tag from `dashboard.html`. Removing only the file leaves a broke `<script src>` that fails silently (no error on the page, just a missing tab). Removing only the tag leaves a dead file on disk.
- **After removing a `<script>` tag, re-run `node --check` on the remaining files** and rebuild `processed.js` + run the test suite. The registry changes — a deleted viz's id no longer appears in `VIZ_REGISTRY`, which shifts tab numbering by one.
- **CSS for new UI elements reuses existing design tokens.** Before adding new button/table styles, grep `dashboard.css` for the existing class pattern (e.g. `.dt-view-btn`, `.viz-search`). Reuse the same `.active`, `:hover`, neon-border pattern. Only add new classes for structurally different elements (e.g. an options bar that wraps differently than a view bar).

## Tooltip system — one shared element
- Single tooltip element: `#tooltip` in `dashboard.html`.
- Standard path: `wireTooltips(container, data, '.bar, .val-label')` (in `_shared.js`) reads `document.getElementById('tooltip')` and uses `buildTooltip(m)` for content. Use for per-element hover.
- **cost-breakdown.js uses a BESPOKE tooltip** (mousemove → row-index lookup, custom multi-segment content). It must reference the same `#tooltip` element directly:
  ```js
  const tt = document.getElementById('tooltip');
  ```
- GOTCHA — `window.getTooltipEl()`: this global was **removed** during the tooltip consolidation (commit `0299df9 "externalize inline CSS, boot init, and tooltip builder; drop dead template"`). Any viz still calling `window.getTooltipEl()` gets `tt = null` and silently renders **no tooltip** (the whole block is skipped). If a hover popup is missing, grep for `getTooltipEl` first. Fix = `document.getElementById('tooltip')`. (This bit cost-breakdown's tooltip for the whole session until caught — it predated the renumbering work and was NOT caused by id/slug changes.)

## Color modes (crossover.js)
`colorMode` toggles between:
- `'creator'` → `window.creatorColor(m.creator)`. This resolves `CREATOR_COLORS[m.creator]` if present, else a deterministic golden-angle HSL (`hue = hash(name)*137.508 % 360`, lightness 52–80%, sat 72–90%) — so ANY creator (incl. new OSS labs / SKU variants) gets a distinct, separable color. **Never fall back to flat `#888` for a missing creator** — `creatorColor` replaces that pattern. All five consumers (legend, radar, cost-per-iq, crossover, data-table) now call `window.creatorColor(...)`.
- `'reasoning'` → `reasoningColor(m.reasoning_tax_pct)`:
  ```js
  REASONING_COLORS = { low:'#b6ff3c', mid:'#ff6a00', high:'#ff3366', none:'#888888' };
  // low <20%, mid 20–50%, high >50%, null → none (gray)
  ```
- GOTCHA — all gray in reasoning mode: `reasoningColor(null)` returns `#888888`. If `reasoning_tax_pct` is null for every model (it is a **derived** field, not sourced directly), every point is gray. The pipeline MUST derive it: `reasoning_tax_pct = reasoning_usd / total_cost_per_task_usd * 100` from the AA cost-segment SOURCED fields (`cost_seg_reasoning`, `cost_seg_total`). See `pipeline-source-integration` (derived-metric rule) for where this belongs. Symptom of omission = crossover "Reasoning Tax %" color mode shows a uniformly gray scatter.

## Creator color contrast
- The curated `CREATOR_COLORS` map was rebuilt to avoid hue collisions (four near-identical blues, purple clashes, invisible greys/near-whites) and to remove duplicate hexes. If you ADD a creator, pick a hue far from existing entries; run `node -e` to grep the map for duplicate `#xxxxxx` before committing.
- `creatorColor(name)` is the canonical fallback — wire EVERY color lookup through it (it's on `window`). Do NOT reintroduce `CREATOR_COLORS[x] || '#888'`; that's the old pattern that collapsed unknown creators to indistinguishable grey.
- Curated-map entries must stay readable on the dark panel bg (`--panel #111`) — prefer lightness ≥ 50% and saturation ≥ 70%.

## Per-point hover on radial / non-model elements
- `wireTooltips(container, data, selectors)` is **slug-based** (`data-slug` + `buildTooltip(model)`) — it fits model rows/bars, NOT radar vertices (which are creator×axis aggregates, no single slug).
- For per-point hovers where there is no model slug (e.g. each radar vertex in `provider-archetypes.js`), write a **bespoke handler** that reuses the SAME `#tooltip` element directly: give each `<circle>` `data-creator`/`data-axis`/`data-tip` attrs, then on `mouseenter` set `tt.innerHTML` to a small `<div class="tt-name">` + `<div class="tt-row">` and `tt.style.display='block'`; `mousemove` repositions (clamp to viewport); `mouseleave` hides. This reuses the shared tooltip styling without the slug lookup.
Keep the bottom stats row as the single copy-pasteable summary; the hover shows the precise per-point value. Both coexist.

## Shared table infrastructure across vizes

When two or more vizes share the same control pattern (view/tab buttons, multi-column sort with shift+click, search box, table-header sort indicators, row rendering with legend-filter dimming), do NOT write a second file that copy-pastes the wiring. Instead:

1. Define a `VIEWS` registry object at module scope. Each view is:
   ```js
   {
     label: 'View Name',
     defaultSort: [{ key: 'field', dir: 'desc' }],
     buildRows(data, opts) { /* return row[] */ },
     cols: [
       { key: 'field', label: 'DISPLAY', render: (row, idx) => html, cls: 'num' },
     ],
     options?: {  // optional — only for views that need a secondary selector
       key: 'provider',          // drives container.__<key> state
       label: 'SELECTOR LABEL',
       build(data) { /* return [{name, count}, ...] */ },
     },
   }
   ```
2. Write ONE `buildShell(container, view, viewKey, data)` that builds: view buttons for ALL views + optional options bar (only rendered when `view.options` exists and is relevant to the active view) + search box + table header. Wire all events here.
3. Write ONE `patchControls(container, view, viewKey, sortSpec, filteredCount, total)` that toggles active states on view buttons, options buttons (if the active view has options), and sort indicators.
4. Write ONE `patchTable(container, view, sortSpec, rows)` that renders rows with legend-filter dimming via `window.__modelOpacity`.
5. The `render(container, data)` entry point picks the active view from `container.__view`, calls `view.buildRows(data, { [view.options?.key]: container.__opt })`, applies search filtering, sorts, and delegates to the three shared functions.

This is what `data-table.js` does with 5 views (Model Detail, Provider Rollup, LiveBench, Cost Efficiency, Provider Data — the last folded in from the old `cache-hit-rates.js`). The `options` field drives the provider button row that only appears when `Provider Data` is the active view.

Pitfall — options state on view switch: when the user switches away from a view that has `options`, clear `container.__opt` (set to `null`). When switching back, the options bar rebuilds with the default selection. Don't carry stale `__opt` into a view that doesn't use it — reset it alongside `__sort` and `__search` on view change.

**Rule — a control used by two or more vizes is built by ONE helper in `_shared.js` (exported on `window.VIZ_HELPERS`) and styled by ONE shared class.** Canonical case: `VIZ_HELPERS.searchBox({ placeholder, rowStyle })` emits the search row + input + live count badge; the data table and the creator legend both call it, and the input styles live once in `dashboard.css` under `.viz-search` (renamed from `.dt-search`; the badge class went `.dt-count` → `.viz-search-count`). Before hand-rolling a control into a second viz, grep `_shared.js` for an existing builder. A copy-paste variant is a hack job the user rejects on sight, and it drifts visually — a hand-rolled legend search with a new `.lg-search` class had zero CSS rules and rendered as a bare browser input beside the styled table search. If the control differs structurally, add options to the shared builder; do not fork it.

## Cost Breakdown provider mode (cost-breakdown.js)

One `render()` → `sourceBarHtml(source, options)` + `body.note` + `body.html`, where `body` comes from
`aaBody(container, allData)` or `providerBody(allData, provider)`. Both return `{ note, html, charts }`;
`charts[i]` maps to the i-th `<svg>` in `html`, so `wireBarTooltip(svgs[i], chart.rows, chart.contentFor)`
stays a single code path (no per-mode tooltip duplication).

- `container.__cacheSource` = `'aa'` | provider name (default `VIZ_DEFAULTS.costBreakdown.cacheSource`).
- Provider chips are `.cache-toggle-btn` (existing style) inside `.cb-provider-chips`; the shared
  `VIZ_HELPERS.searchBox` filters them IN PLACE (`applyProviderFilter`) — never re-render on `input`,
  or the caret dies after one keystroke. Query survives rebuilds via `container.__providerQuery`.
- **Active state needs an attribute-scoped CSS rule.** `dashboard.css` styles `.active` only for
  `[data-source="aa"]` / `[data-source="external"]`; a chip carrying `data-provider` renders with NO
  selection feedback until `.cache-toggle-btn[data-provider].active` exists. Symptom: the chart says
  `// Morph · observed cache hit rates…` while every chip looks unselected.
- Two row classes: `providerTaskRow` (AA segments scaled by provider effective/list rate ratios) and
  `providerRateRow` (1M in + 1M out at effective $/M, unit labelled `NOT $/task`). Never put both on one axis.
- Pure transforms are exported on `window.COST_BREAKDOWN` (`buildCostData`, `providerOptions`,
  `providerView`, `providerTaskRow`, `providerRateRow`, `axisFor`) for `tests/test_viz_cost_js.js`.
- `axisFor(values)` picks log ticks bracketing the data (`first ladder tick >= lo*0.75` back one step,
  `last >= hi`); AA mode keeps its fixed 0.01–3 ticks so its chart never shifts.

## Pitfalls
- **JS temporal dead zone (TDZ):** a `const`/`let` function/var cannot be *called* before its declaration line, even inside the same function. Symptoms: `Uncaught ReferenceError: can't access lexical declaration 'X' before initialization` at render. Fix: declare helper functions (e.g. `fmtRaw`) ABOVE the loop that uses them, or hoist them to the top of `render`. This bit `provider-archetypes.js` when a hover edit referenced `fmtRaw` from inside the circle loop while `fmtRaw` was declared later.
- **Block-scoped `const`/`let` escaping its block (TDZ's sibling):** a `const` declared inside an `if` block is invisible after that block closes, so a later read throws `ReferenceError: X is not defined` (data-table.js `defaultOpt` — declared inside `if (viewDef.options) {`, read outside). Fix = move WHERE the declaration lives (`let defaultOpt = '';` at function scope, assigned inside the block), never reshape the guard at the read site. Procedure for any `X is not defined`: `grep -n '\bX\b' file` and classify EVERY reference by the lexical block containing it (which `if`/function holds the declaration vs each use) BEFORE patching. A guard reshuffle (ternary ↔ if/else) is a no-op — never ship it as a fix.
- **Bare `N` outside formatter scope:** `N` is only in-scope INSIDE the `fmtRaw`/`fmtApex` arrow bodies (each declares `const N = window.VIZ_NUM`). Referencing `N.fmtUSD(...)` / `N.DASH` from a render loop (outside those arrows) throws `Uncaught ReferenceError: N is not defined`. This bit `provider-archetypes.js` twice — first as TDZ (`fmtRaw` above its decl), then as bare `N` in the cost-axis tip string. Fix: in any code OUTSIDE the formatter arrows, use `window.VIZ_NUM.fmtUSD(...)` / `window.VIZ_NUM.DASH` directly. After editing a `viz/*.js` file, run `node --check` AND grep for `\bN\.` to confirm every `N.` reference sits inside a `fmt* = (...) => { const N = window.VIZ_NUM; ... }` arrow body.
- **Radial cost axis semantics:** a radial graph reads "higher = better" on every axis. For cost, invert so cheaper = larger radius, and label the apex with the **normalized efficiency score (0–100)**, not the raw `$/task` (a tiny `$0.02` at the edge fights the "higher=better" read). Keep the real `$/task` in the panel stats row (`$X/task (NN eff)`) for grounding. The raw `$/task` is still the source of truth.
- **Inline `style` beats a CSS class — always.** A dashboard element with a CSS rule `display:flex` will STILL stay hidden if its HTML carries `style="display:none"` inline, because inline wins over the stylesheet. The creator legend (`#creator-legend`) is exactly this: `.creator-legend{display:flex}` in dashboard.css but `style="display:none"` in dashboard.html:33, so it was permanently hidden until `__renderCreatorLegend` set `newEl.style.display='flex'` on the cloned node (and boot called it on load). Rule: when you add/hide a toggleable element, drive visibility from JS (`el.style.display = ...`), never rely on a class overriding an inline `none`. Same trap bit `parentElement.querySelector` sites.
- **Never rebuild a container from an `input` handler — filter in place.** Calling a full render function from a search input's `input` event destroys the focused `<input>` node on every keystroke, so the caret dies after the first character (typing `gpt` registers only `g`). Toggle matches in place (`chip.style.display = match ? '' : 'none'`), update the count badge, keep the input node alive — mirror the data table, which patches controls + tbody instead of re-running `buildShell`. Persist the query (`window.__legendSearch`) and restore it (`searchInput.value = …` plus re-apply the filter) after rebuilds, or tab switches silently drop the filter text. Full pattern: `references/legend-search.md`.
- **Do NOT add silent-catch "safeRender" band-aids.** When a viz/page "doesn't render," the user wants the ROOT CAUSE found, not a try/catch wrapper that swallows the throw so one broken viz can't blank the rest. `Pipeline.run()` (`_result.js`) already catches step exceptions and short-circuits — papering over it with per-viz try/catch hides the real bug and the user explicitly rejected that approach ("revert and try again"). Trace the actual throw (use the node stub-DOM boot harness in `references/viz-boot-harness.md`) instead of masking it. Related: the top error banner only reflects pipeline-step failures (`_failed_step`) — a synchronous throw inside a tab's `render()` is uncaught, reaches only the browser console, and banner silence does NOT mean no error.
- Grep discipline: never leave `window.getTooltipEl`; ids are slugs; number = array position only.
- **Line-length limit is not universal — check the repo first.** Before imposing a wrap on long lines in a viz/script file, run `awk 'length > N {print FILENAME": "NR": "length" chars"}' viz/*.js` (or the file's own tree) to see what the codebase actually tolerates. This repo has no consistent 120-char convention — other viz files routinely run 230–275 chars per line. If the codebase is inconsistent, match the file's neighbours rather than an arbitrary number. Only enforce a limit when there is a documented standard (AGENTS.md / .cursorrules).

- **Patch hunks in `viz/*.js` fail on escape mismatches — probe raw bytes before rewriting.** These files mix backslash-escaped quotes inside backtick template literals with plain quotes in single-quoted strings (plus CRLF endings); when an `old_string` refuses to match, dump the exact region (`python -c "print(ascii(open(f).read()[a:b]))"` or `cat -A`) and rebuild it from the real bytes instead of guessing.

## Exploding overlapping scatter points (crossover.js)
When many bubbles pile up at one pixel spot, a click should "evacuate" the whole stack so each layer is individually hoverable. Pattern (see `references/explode-overlap.md` for full code + repro):
- **Cluster detection:** union-find over model positions; two points cluster if center distance ≤ `r1 + r2 + 6` (the `+6` = grab padding). Transitive, so A-B-C chains group even if A and C don't directly touch. Cache `container.__crossoverLayout = { layout, clusterOf, groups, W, H }` so the click handler can read positions without recomputing. Full code + repro harness: `references/explode-overlap.md`.
- **Render:** each model → a visible `<circle class="pt" data-slug data-g>` PLUS a transparent `<circle class="hit" data-slug data-g>` hit-target (radius `r+6`) on top. Both carry `data-g` (group) and `data-slug` (so `wireTooltips(container, data, '.pt, .hit, .label')` shows the right model on hover of either).
- **Click = COORDINATE hit-test, NOT element-target.** Do NOT resolve the click via `e.target.closest('circle.hit')` — a large single-point bubble drawn later sits on top and its transparent hit-target steals the click, so the dense stack underneath never evacuates (this was the shipped bug). Instead convert the cursor to SVG space with `svg.getScreenCTM().inverse()` + `createSVGPoint`, then find every cluster with a member within `r+6` of the click and explode the **densest** one. Click on empty space (svg bg / a `<rect>`) → `__collapseAll`.
- **Animation:** rAF tween of `cx`/`cy` attributes, cubic ease `e = 1 - (1-p)^3`, ~320ms. Explode fans members to a ring around the cluster centroid (`spread = 26 + n*10`, angle = `n/N*2π − π/2`). Collapse tweens back to `lay.layout[i].cx/cy`.
- **CRITICAL slug→member mapping:** the matched `circles` NodeList is `[pt0, hit0, pt1, hit1, …]` (pt then hit per member, in doc order). If you tween by circle *index*, each member's pt and hit fly to DIFFERENT ring slots and the hit area drifts off its dot. Build `slugToMember[slug] = n` and tween by `slugToMember[c.dataset.slug]`, so pt and hit of the same model land on the SAME slot.
- Overlap is axis-dependent: `context_window` as size axis yields a 4-point cluster + 4 pairs on the default quality/cost axes; `tokens_m`/`params_b` stay sparse. The feature only has something to do where bubbles actually pile up.

## Verification without node/jsdom
- Pure-JS geometry checks run fine as a standalone `node script.js` (no deps, no `npm install`): replicate the cluster union-find + explode-target math on a few synthetic points, assert `minSepAfter > minSepBefore + 5` and `collapseMaxErr < 1e-3`. The user explicitly prefers this over pulling in jsdom. See `references/explode-overlap.md` for the harness shape. (Repo has NO pyproject/package.json — deps are ad-hoc; don't add jsdom just to test DOM logic when the math is separable.)

## Verification
- `node --check viz/*.js` for syntax (no browser needed for a static check).
- Open `dashboard.html`: tabs numbered 1..n by position; toggle crossover color mode → real green/orange/red; hover a cost-breakdown bar → popup appears (not silent); hover a radar vertex → per-point value popup; unknown creator → distinct generated color (not grey).
- Search boxes (data table + creator legend): identical styling; typing keeps focus for every character; the count badge updates; switching tabs preserves the query.
- Grep discipline: never leave `window.getTooltipEl`; ids are slugs; number = array position only.
- **Line-length limit is not universal — check the repo first.** Before imposing a wrap on long lines in a viz/script file, run `awk 'length > N {print FILENAME": "NR": "length" chars"}' viz/*.js` (or the file's own tree) to see what the codebase actually tolerates. This repo has no consistent 120-char convention — other viz files routinely run 230–275 chars per line. If the codebase is inconsistent, match the file's neighbours rather than an arbitrary number. Only enforce a limit when there is a documented standard (AGENTS.md / .cursorrules).

## Related
- Umbrella: `aa-project`. Data side: `pipeline-source-integration`, `aa-image-charts-pipeline`, `aa-api-live-fill`.
- Detail/transcripts: `references/viz-architecture.md`.
- Legend search: shared `searchBox` builder + in-place chip filtering — `references/legend-search.md`.
