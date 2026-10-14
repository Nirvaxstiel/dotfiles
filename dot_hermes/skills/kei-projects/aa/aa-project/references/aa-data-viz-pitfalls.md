# AA Data & Viz Pitfalls (session-hardened)

Reusable failure modes in the `LLM Provider Pricing Analysis` pipeline + dashboard.
Symptom → root cause → fix. Trace root cause at the DATA-PIPELINE layer first, then
the VIZ-RENDER layer — most "weird viz" bugs are bad source data.

## 1. `cost_per_task` is $1K–$6K (cost-per-IQ shows thousands/point)

- **Symptom:** `cost_per_iq = cost_per_task / intel` huge (fable `$5630.52 / 60 = $93.84`).
- **Root cause:** `data/sources/aa/enriched/aa_model_data.json` `cost` = total cost to emit
  a full `tokens_m` (e.g. 87M) output = `eff_cost_per_m × tokens_m`. NOT per-task.
  `data/sources/aa/_build.py` mapped it into `cost_per_task` as a fallback when breakdown
  data was missing (`if p["cost_per_task"] is None: p["cost_per_task"] = raw.get("cost")`).
- **Valid per-task sources (priority chain for `cost_per_task`):**
  1. **AA live API** `artificial_analysis_intelligence_index_cost.cost_per_task.total_cost`
     (FREE tier includes it — pre-calculated weighted-avg per Intelligence Index task).
     See `aa-api-live-fill` skill; NOT yet wired into `_overlay_aa_api` as of this write.
  2. **Cost-breakdown JSON** (`aa_cost_breakdown.json` → `total_cost_per_task_usd`),
     values $0.02–$2.29. Currently the only wired source.
  3. **Image-derived** (`aa_img` source `cost_per_task`, when the "Cost per Intelligence Index
     Task" chart is transcribed into `aa_img_models.json`). Plumbed with null-guard in
     `_build_registry.py` image merge, but the chart is currently untranscribed → empty tier.
  4. **null** — no synthetic/fallback.
- **Fix applied:** removed `cost`→`cost_per_task` link (initial-set + fallback in `_build.py`).
  Wired image `cost_per_task` as tier-3 fallback (null-guard, never overrides tiers 1-2).
  User explicitly chose NOT to re-enable enriched `cost` (that = the $5,630 bug).
- **Trace:** processed.js → worst `cost_per_iq` → check `cost_per_task`+`tokens_m` → divide
  → cross-check `aa_model_data.json` `cost` vs `aa_cost_breakdown.json`
  `total_cost_per_task_usd`. `tokens_m` (output tokens in M) is legit; only the mapping was wrong.

## 2. `reasoning_tax_pct` null everywhere → crossover "Reasoning Tax %" all gray

- **Symptom:** switching crossover color mode to Reasoning Tax → everything `#888`
  (the `none` fallback in `reasoningColor(null)`).
- **Root cause:** only sourced from `aa.reasoning_tax_pct` (hardcoded `None` in AA source);
  cost segments (`cost_seg_reasoning`, `cost_seg_total`) populated (28 models) but % never derived.
- **Fix (derived from SOURCED fields — allowed):** in `_build.py` breakdown overlay,
  `aa["reasoning_tax_pct"] = round(reasoning_usd / total_cost_per_task_usd * 100, 1)`
  when both exist and total > 0. → 28 models, spread low/mid/high.
- **Note:** no-breakdown models stay gray in reasoning mode = correct (no data), not a bug.

## 3. Viz tooltip silently missing (e.g. cost-breakdown)

- **Symptom:** a viz shows no tooltip though others do.
- **Root cause:** viz referenced `window.getTooltipEl()` — a global removed during tooltip
  consolidation → returned `null` → whole tooltip block skipped.
- **Fix:** use `document.getElementById('tooltip')` (canonical element in `dashboard.html`,
  what `wireTooltips` uses). Bespoke viz must too; others go through `wireTooltips`/`buildTooltip`.

## 4. Viz init defaults scattered / first-load mismatch

- **Symptom:** control renders one default, picker highlights another (crossover sized by
  Context Window while Size picker showed Output Tokens).
- **Fix pattern:** all per-viz init selections in ONE `window.VIZ_DEFAULTS` (in
  `viz/_shared.js`, loaded before viz scripts), keyed by viz
  (`crossover`/`costBreakdown`/`dataTable`/`legend`). Every read:
  `container.__x || window.VIZ_DEFAULTS.<viz>.<field>`. Render + picker + toggle read the
  SAME entry → can't drift.
- **Display order:** tab number + `<h2>` number from registry ARRAY POSITION (`${i+1}` in
  `_boot.js`), NOT hardcoded `id`. Viz `id` = stable slug (`crossover`, `cost-breakdown`, …)
  for `data-viz`/`mount-*`/DOM ids only. `_boot.js` does NOT sort by id — order in
  `dashboard.html` = tab order.

## 5. Provider repricing (cache-hit-rate provider → cost breakdown)

- **Never reconstruct per-task token volumes from AA cost segments.** `cost_seg_*` dollars
  ÷ the model's AA list prices does NOT reproduce `tokens_m` — measured spread 0.08×–17.8×
  (deepseek-v4-pro: 10.1k out tokens vs `tokens_m` 180; nemotron-3-super-120b: 1.30M in
  tokens vs 110; gpt-5.5-medium 164k in vs 21). The segments were priced on a different
  basis than the list prices the registry holds, and `tokens_m` is a separate measurement.
  Any "reprice at AA token volumes" design is therefore fabrication — reject it.
- **Recoverable provider model instead:** keep AA per-task segments, scale each *side* by the
  provider's observed effective rate ÷ AA list rate (`eff_input_price / inp_price` for
  input+cache_hit+cache_write, `eff_output_price / out_price` for answer+reasoning). The
  cached/uncached proportion stays AA's; the provider's cache effect is already inside its
  effective input price. Requires `inp_price > 0` and `out_price > 0` on the model.
- **Two row classes, never silently merged.** Only 7 models have AA segments ∩ provider rows
  (28 have segments, 74 have provider rows, 19 have provider prices). Segment-less models get
  a reference-workload block (1M input + 1M output at effective $/M) that must be labelled
  `NOT $/task` — the unit differs, so it cannot share the per-task axis.
- **A total-preserving recompute cannot produce "savings".** The retired
  `applyExternalCache` resplit the input side while keeping the total, so its header figure
  `savings = inputTotal − total` was always negative (`-Σ(answer+reasoning)`). If a headline
  is derived from a redistribution, it is arithmetically dead — show the delta against a
  baseline (AA list vs provider effective) instead.
- **Hardcoded cache price ratios are the smell.** The retired path used
  `CACHE_PRICE_RATIO = 0.1` for every model; per-provider observed effective rates replace it.
- **Sourced-only contract:** the removed `window.CACHE_HIT_RATES` map in `_shared.js` was a
  hand-transcribed duplicate of `dirac_cache_hit_rates` (deepseek-v4-pro 0.879 vs sourced
  89.8). Per-provider rates live in the data (`model.dirac_cache_hit_rates`); viz code reads
  them, never a hardcoded table.

## Rebuild + verify loop (after any data-layer change)
```
python -m data._build_registry && python -m data._build_axes && python -m data._build_dashboard_data
python -m pytest tests/ -q
```
Sanity-check `data/processed.js`: json.loads the `window.PROCESSED_DATA = ...;` wrapper
(strip prefix + trailing `;`). Confirm test loaders unwrap `.models`.
