# AA Viz Architecture — session detail

Companion to `aa-viz-frontend` SKILL.md. Captures the concrete fixes and invariants
found while working the dashboard render layer.

## Load order = tab order (no numeric ids)
- `dashboard.html` lists viz scripts in the order tabs should appear. `_boot.js` does
  **not** sort `VIZ_REGISTRY` — it preserves insertion order. The tab number is
  `i + 1` (array index), nothing else.
- Each viz `id` is a stable slug (`crossover`, `cost-breakdown`, `provider-archetypes`,
  `cost-per-iq`, `data-table`). Used for `data-viz` + `mount-<id>`.
- Changing order = reorder `<script>` tags. Filename numeric prefixes are cosmetic and
  were removed; they do NOT affect numbering.

## Tooltip: single `#tooltip` element
- `dashboard.html` has `<div class="tooltip" id="tooltip">`.
- `wireTooltips(container, data, selectors)` (in `_shared.js`) reads it via
  `document.getElementById('tooltip')` and renders `buildTooltip(m)`.
- `cost-breakdown.js` uses a BESPOKE tooltip (mousemove→row-index, multi-segment
  content) and must reference the same element: `document.getElementById('tooltip')`.
- DEAD GLOBAL: `window.getTooltipEl()` was removed in commit
  `0299df9` ("externalize inline CSS, boot init, and tooltip builder; drop dead template").
  Any viz still calling it gets `tt = null` → tooltip block silently skipped → "hover
  popup missing". Grep for `getTooltipEl` first when a popup is absent.

## Reasoning-tax coloring (crossover.js)
- `reasoningColor(pct)`: `null` → `#888888` (gray); `<20` → `#b6ff3c` (green/low);
  `20-50` → `#ff6a00` (orange/mid); `>50` → `#ff3366` (red/high).
- ALL-GRAY symptom = `reasoning_tax_pct` is null for every model. It is a DERIVED field,
  never sourced directly. The pipeline must derive it at transform time:
  `reasoning_tax_pct = round(reasoning_usd / total_cost_per_task_usd * 100, 1)`
  from the AA cost-segment SOURCED fields. (Added in `sources/aa/_build.py` cost-breakdown
  overlay.) Without it, the "Reasoning Tax %" color mode shows a uniformly gray scatter.
- As of last build: 28/104 models carry `reasoning_tax_pct` (buckets low 10 / mid 8 /
  high 10). The other 76 have no cost-breakdown data → correctly gray in reasoning mode.

## Verification checklist (no browser needed for static)
- `node --check viz/*.js` — syntax.
- Build + `pytest tests/ -q` — green signals are registry byte-size, axis count, "18 passed".
- Open `dashboard.html`: tabs 1..n positional; crossover color toggle → real colors;
  cost-breakdown hover → popup appears.
