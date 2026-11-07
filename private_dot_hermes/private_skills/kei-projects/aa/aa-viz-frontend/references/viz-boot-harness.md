# Viz boot harness — verify dashboard render WITHOUT a browser

The dashboard's `_boot.js` calls `boot()` synchronously at script parse, building the
shell + rendering the first viz. A real browser isn't available in this env, but a stub
DOM (no jsdom — user prefers not to add deps) is enough to prove the boot path + that
every viz renders. Catch: the stub must model the few APIs the viz code touches.

## What a stub must provide
- `document.getElementById(id)` → return a fresh stub element for ANY id (real boot mounts
  into `#mount-<id>` which exists in the browser; the stub must return something non-null).
- `document.querySelector` / `querySelectorAll` → return a stub element / `[]`.
- `document.createElement(tag)` → stub element (with `.style`, `.classList`, `.innerHTML=`,
  `.appendChild`, `.setAttribute`, `.dataset`, `.addEventListener`).
- `document.createElementNS(ns, tag)` → stub (SVG build paths may hit it).
- `Node.prototype.cloneNode` → return a fresh stub; if the code sets `newEl.style.display`
  after cloning, the returned stub must carry that (a no-op clone that resets `style={}`
  will hide the assertion).
- `window` global with `PROCESSED_DATA`, `VIZ_REGISTRY`, `VIZ_HELPERS`, `RADAR_AXES`,
  `VIZ_NUM`, `SKU_PATTERNS`, `creatorColor` all defined (load the real `processed.js` →
  `_result.js` → `_domain.js` → `_shared.js` → each `viz/*.js` → `_boot.js` in order).
- `requestAnimationFrame`, `setTimeout` (boot reschedules if globals missing — provide them).

## Loading order (matches dashboard.html)
`processed.js` → `_result.js` → `_domain.js` → `_shared.js` → `crossover.js` →
`cost-breakdown.js` → `provider-archetypes.js` → `cost-per-iq.js` → `data-table.js` →
`_boot.js`. Read each file and eval/require in this order; `global.window = {}` first.

## What to assert
- After boot, `VIZ_REGISTRY.length === 5`.
- Each viz `v.render(mount, models)` runs without throwing and produces non-trivial
  `mount.innerHTML` (crossover ~54KB, cost-breakdown ~36KB, provider-archetypes ~69KB,
  cost-per-iq ~23KB, data-table ~1.7KB).
- Creator legend: after boot, `#creator-legend` innerHTML populated AND the live clone has
  `style.display === 'flex'` (it starts `display:none` inline in dashboard.html and is only
  un-hidden by `__renderCreatorLegend` setting `newEl.style.display='flex'`).

## Latent gotchas the harness surfaces
- `provider-archetypes.js` line ~274 did `container.parentElement.querySelector('.viz-legend')`
  with NO null guard → throws if a viz is ever rendered into a container without a parent.
  A detached stub mount (no parent) reproduces the throw; the browser survives (real mount has
  a parent) — so the harness catches a FRAGILE pattern, not necessarily a live bug. Fix: guard
  `const parent = container.parentElement; const el = parent ? parent.querySelector(...) : null;`.
  (crossover.js already guards its two `parentElement` sites with `parent &&`.)
- `Pipeline.run()` (in `_result.js`) CATCHES step exceptions and returns early with
  `_failed_step` set — so a throwing viz silently blanks the page in-browser with only a red
  error box. Do NOT paper over this with a per-viz try/catch "safeRender" band-aid (the user
  rejected that — it masks the real cause). Find the actual throw instead.

## Stub must return indexed SVG stubs, not []

Viz code that pairs charts to elements (`container.querySelectorAll('svg')[i]`) throws
`Cannot read properties of undefined (reading 'getAttribute')` when the stub's
`querySelectorAll` returns `[]`. Give the stub container
`querySelectorAll: sel => sel === 'svg' ? [stubEl(), stubEl(), stubEl()] : []` and return
`[]` for attribute-driven selectors (`'.cb-provider-chips [data-provider]'`) — a generic
stub element there makes the filter loop read `undefined.dataset` and throw.
Assert chart count with `html.split('<svg').length - 1`, and assert bar count with
`(html.match(/<g data-slug="/g) || []).length` against the pure transform's row count —
that catches a chart-order/rows mismatch without a browser.

## Path note (NixOS/Linux)
Python, bash builtins and git all share the same POSIX filesystem — `/home/kei/...`
paths work everywhere. Prefer absolute paths or `os.path.join`; there is no
drive-letter/MSYS split to work around.