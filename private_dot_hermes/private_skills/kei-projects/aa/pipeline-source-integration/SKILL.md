---
name: pipeline-source-integration
category: kei-projects
description: Contract-first recipe for adding a new data source (web scrape, API, or vision-transcribed chart images) to the LLM Provider Pricing Analysis repo's scrape → domain-model → registry → axes → dashboard pipeline. Use when introducing new models/metrics, onboarding a new AA chart batch, or any time a source must feed the registry without a bespoke ad-hoc script. Also covers the recurring build-invocation and projection-engine pitfalls that silently drop data.
---

# Pipeline Source Integration (contract-first)

## When to use
- A new data source must flow into `model_registry.json` → `axes_catalog.json` → `processed.js`.
- Vision-transcribing Artificial Analysis chart PNGs into per-model scalars.
- Adding metrics/axes the dashboard can later transpose.
- The user says "encode this so we don't rediscover the contract next time."

## Core principle (user-enforced)
**Step-by-step: source analysis → axis classification → data structure → pipeline handles the rest.**
Do NOT write standalone enrichment scripts or ad-hoc fixups. New fields enter at the
source-fetch stage and flow registry→dashboard automatically. The contract (which axes
exist, their source key, direction, bounds) is captured **once** in the skill / source file,
not rediscovered each session.

## 1. Analyze the source & classify every axis
For each chart/file, bucket each candidate metric into exactly one of:
- **NEW** → gets a source-key axis (`<source>.*`, e.g. `dirac.*`). Encode it.
- **Already owned by another source** — AA already owns `intel`, `cost_per_task`,
  `context_window`, `speed_tps`, `ttft`, `tokens_m`. Skip; never duplicate.
- **Not a per-model scalar** → exclude: scatter charts ("Intelligence vs X"), over-time,
  by-context-length sweeps, component-breakdown stacks (Openness Components, Evaluation
  Breakdown), and multi-benchmark matrices with unreliable vision labeling.

Only encode **per-model scalar bar charts**. This keeps the axis set honest and avoids
redundant-coverage flags.

## 2. Source-of-truth file (the "contract")
Mirror `data/sources/aa/enriched/aa_model_data.json`: a flat JSON keyed by **canonical
model id** (or, for images, by chart display name + a resolver map in `_canonical.py`).
Every value nullable; omit keys rather than null them where a model lacks the metric.
A `_meta` block documents exclusions so future sessions don't re-litigate them.

## 3. Wiring checklist (file-by-file)
1. **`data/_pull_sources.py`** — fetch the FULL source shape. Do NOT strip fields at pull time. The pull step's job is to download and store the complete API/response; the registry step transforms it. Stripping fields here (e.g. reducing 445 models to 7 fields) throws away data downstream steps need. For API sources, store raw response fields under stable keys (e.g. `benchmarks`, `design_arena`, `created`, `architecture`, `reasoning`) so the registry merge can pick what it needs.
2. **`data/_canonical.py`** — add a `x_name_to_canonical(display)` resolver map
   (display-name → canonical id). For API/scrape sources, extend `SLUG_TO_CANONICAL`.
3. **`data/_domain/_base.py`** — add `SourceKey.X = "x"` to the enum; add a frozen
   `DomainValue` type with **tight bounds** (e.g. `OmniscienceIndex` -100..100,
   `ResponseTime` s≥0). Signed stability metrics (variances) get an unbounded `AxisMetric`
   — see Pitfalls.
4. **`data/_domain/_values.py` + `_serialize.py`** — value type + a `safe_x(v)`
   constructor returning `None` on missing. Export both from `_domain/__init__.py`.
5. **`data/sources/<x>/_build.py`** — `get_x_models(base) -> dict[cid,
   {benchmarks:{x:{...}}, meta:{...}}]`. Fill nulls only; never overwrite non-null.
6. **`data/_build_registry.py`** — import + merge block (deep-merge `benchmarks.x` and
   `meta.*` into `all_models`). For API sources enriching an existing source (e.g. OpenRouter
   merging AA benchmarks into `benchmarks.aa`), use **fill-nulls only** — existing chart-scraped
   / JSON-LD values win on overlap. For genuinely new fields (e.g. `design_arena` array, 
   `release_date`, `input_modalities`), store as-is. Also see
   `references/free-endpoint-scout.md` for the endpoint availability matrix and shape mapping.
7. **`data/_build_axes.py`** — axis builders via `_build_axis(models, "x.axis", "X",
   label, type, unit, higher_is_better, desc, group, path)`. Source groups/feasibility
   derive automatically.
8. **`data/project_axes.py`** — **add `"x"` to the benchmark-routing tuple** in
   `get_value` (see Pitfalls — silent drop otherwise).
9. **`data/_domain/_projection.py`** — `ProjectionRow` field(s) (`Optional[type]=None`)
   + `FIELD_PROVENANCE` tag = `SOURCED` + entry in `to_dict` `optional_map`.
10. **`data/_build_dashboard_data.py`** — add `"x.axis"` to `ALL_AXES` + row constructor
   assignment using the `safe_x` fn.

## 3b. API enrichment pattern (when adding fields to an existing source)

When a free API mirrors or extends an existing source (e.g. OpenRouter carries AA's own
benchmark values, or adds release_date/modalities to models we already have), the enrichment
step goes in `_build_registry.py::step_<source>`, NOT in a new source step:

- **Fill-nulls only for overlapping fields:** if the API carries values for a field another
  source already owns (`benchmarks.aa.intel`, `pricing.aa.*`), merge as fill-nulls — the
  original source's values win on overlap. Never overwrite.
- **Store new fields as-is:** fields no existing source owns (`design_arena` array,
  `release_date`, `input_modalities`, `reasoning`) go directly into the model dict.
- **Pull full shape, transform in registry:** `_pull_sources.py` stores the complete API
  response; `_build_registry.py` picks what it needs. Do not strip fields at pull time.

## 4. Build & verify (invocation matters)
The pipeline is orchestrated by `data/_pipeline.py` (`Pipeline().then().run()`, monadic).
Two entrypoints:
- **Full build (network pull):** `python -m data._pipeline` (no arg → `build()` pulls
  OpenRouter/LiveBench/OpenLLM then builds).
- **Offline rebuild (uses committed sources, no network):** `build_from_cache()`.
  IMPORTANT — `python -m data._pipeline build_from_cache` from repo root FAILS with
  `ModuleNotFoundError: No module named '_result'`, because `_pipeline.py` does a BARE
  `from _result import ok` (needs `data/` on `sys.path`, not repo root). The determinism
  test works only because it does `sys.path.insert(0, DATA_DIR)` first. Correct offline run:
  ```bash
  PYTHONPATH=data python -c "import data._pipeline as p; p.build_from_cache()"
  ```
  (or `cd data && PYTHONPATH=. python -c "import _pipeline; _pipeline.build_from_cache()"`).
  After any change, run the determinism test (`tests/test_pipeline_determinism.py`) — it
  copies `data/` to a temp dir, runs `build_from_cache` twice, and asserts `model_registry.json`
  / `axes_catalog.json` / `processed.js` are byte-identical between runs. It compares two
  FRESH runs against each other, NOT against committed HEAD, so removing a source is safe
  as long as the build stays stable — but you must then REGENERATE the committed artifacts
  (`model_registry.json`, `axes_catalog.json`, `processed.js`) so the repo is consistent.

## 4b. Deletion-safety: confirm data reaches the artifact BEFORE removing a source
When removing an ingestion source, FIRST verify it actually contributes to the SHIPPED
product, or you risk deleting dead-but-harmless code OR silently dropping live data:
1. Grep the source key across `data/model_registry.json`, `data/axes_catalog.json`,
   `data/processed.js`. If it appears in the **registry** + **axes** but is **ABSENT from
   `processed.js`** and no `viz/*` references it, the source is dead ingestion — safe to
   remove (it never reached the dashboard). This is exactly what happened with `aa_img`:
   60 models carried `aa_img` benchmarks in the registry and 12 AA_IMG axes existed in
   `axes_catalog.json`, yet `processed.js` had 0 mentions and no viz used it. Removing the
   ingestion (`step_aa_img`, the axis builders, the projection lines, the canonical map,
   the `SourceKey` enum member, the source dir) + regenerating artifacts left the dashboard
   byte-identical in every field it actually rendered.
2. If the key IS present in `processed.js` / viz, the source is live — do NOT delete without
   migrating its consumers first.
Audit command (substitute the source key you're evaluating):
```bash
grep -c <source_key> data/model_registry.json data/axes_catalog.json data/processed.js
```
(registry/axes >0, processed.js 0 ⇒ dead ingestion, safe removal.)

## Pitfalls
- **`get_value` whitelist (silent data loss):** `project_axes.py` `get_value` only routes
  a `source` to the benchmark branch if `source in ("livebench","arena_text","arena_code",
  "openllm","aa_img")`. A new benchmark source NOT in that tuple → registry has the data
  but the dashboard projection returns `None` for every axis. **Add it.** Symptom: registry
  processed.js rows show {} for the source's fields, tests still pass.
- **get_value path-override crash on None intermediate (build death + stale file):**
  when a routing override walks a nested path like (pricing, aa, cost_segments,
  reasoning_usd), the loop does sec = sec.get(k, {}). If an intermediate key is None (a
  model lacking cost data -> cost_segments: None instead of a dict), sec becomes None and
  the next sec.get(...) raises AttributeError: NoneType has no attribute get. This aborts
  the entire _build_dashboard_data run, so processed.js is NEVER rewritten — a STALE
  artifact ships while pytest stays green (tests read the old file). Fix in
  project_axes.get_value: guard the walk with sec = sec.get(k, {}) if isinstance(sec, dict)
  else {}. Symptom: python -m data._build_dashboard_data exits non-zero, no Wrote N models
  line, processed.js older than model_registry.json. Always check the build output for the
  Wrote line, not just the pytest count. Any non-zero build exit is a hard failure even if
  tests pass — this is the most dangerous class of bug in the pipeline (crash -> stale
  artifact, green pytest).
- **Rigid phased TDD for source integration (user-enforced sequence):** the user expects the
  order (1) write the parser + a RED contract test first, (2) implement until GREEN,
  (3) THEN wire ingestion into get_aa_models, (4) THEN rebuild + full-suite. Do not fold
  ingestion into the same pass as the parser, and do not declare done on parser works alone
  — ingestion is a separate verified step. Write the per-chart/per-axis test plan up front
  (one assertion per chart), not after.
- **Relative-import depth:** `data/sources/aa/img/_build.py` is 4 package levels below
  repo root → `from ...._canonical import ...` (four dots), not three. Mismatch →
  `ModuleNotFoundError: No module named 'data.sources._canonical'`.
- **Signed ≠ duration:** `TimeToFirstToken` rejects negatives. `ttft_variance` etc. are
  signed stability metrics (e.g. -1.5s). Mapping them to a duration type raises
  `ValueError: Negative TTFT` and **crashes the dashboard build before writing
  processed.js** (stale file, but `pytest` still green because it reads the old file).
  Use a separate unbounded `AxisMetric` type.
- **Value-type bounds:** define validators tightly; they catch bad transcriptions at build.
- **Vision timeouts:** `vision_analyze` times out on large PNGs. Retry with a **minimal**
  prompt ("give model:number pairs") — repeating identical args triggers loop-detection
  and keeps failing. If a chart still won't read and the metric is a superset of an owned
  one, skip it and note it in `_meta.excluded_charts`.
- **Derived-guard test:** `tests/test_data_contracts.py::TestDerivedProperties` asserts the
  exact `DERIVED` field set and that every `ProjectionRow` field has provenance. Adding
  `SOURCED` fields is safe; any `DERIVED` change must update the assertion or it fails.
- **Derived metrics must be computed at TRANSFORM TIME in `_build_dashboard_data.py`** (user-enforced, twice) — NOT at source-fetch (`sources/<x>/_build.py`) and NOT in `_domain.compute_derived()`. SOURCED raw fields enter at source-fetch; cross-field DERIVED metrics (e.g. `iq_per_1k_pt`, `cost_per_iq_pt`, `reasoning_tax_pct`) are computed where the projected axes are assembled. `reasoning_tax_pct = reasoning_usd / total_cost_per_task_usd * 100` from the AA cost-segment SOURCED fields. If it is left null, the crossover "Reasoning Tax %" color mode renders EVERY point gray (`REASONING_COLORS.none = '#888'`) — a silent, confusing symptom. Populate derived fields or the viz that keys on them goes monochrome. See `aa-viz-frontend`.
- **Translation-loss trap (axis id ≠ source key):** the axis id (`aa.iq_per_dollar`)
  and the registry source key (`benchmarks.aa.iq_per_dollar`) must match exactly, and
  the enriched CSV key (`iq_per_1k`, IQ per $1k) must map to the CORRECT field with the
  RIGHT UNIT. Mapping `iq_per_1k` into `iq_per_mtok` (IQ per **million tokens**) is a
  silent unit-drift bug — downstream values look plausible but are wrong. **Verify the
  enriched key's true basis before mapping** (e.g. `iq_per_1k = intel/cost*1000` ⇒
  `iq_per_dollar = iq_per_1k/1000`). Add a per-source mapping test asserting the output
  field is populated AND within plausible bounds (IQ/$ must be < 100).
- **`params_b` plumbing trap:** in `_build_dashboard_data.py` the row constructor gets
  `meta = reg.get("meta", {})` where `reg = reg_by_id.get(mid)` and `reg_by_id` is built
  from `pe.models` (the **projected** models). Reading `a.get("meta.params_b")` (from the
  projected axes dict) returns None because `params_b` is NOT a projected axis —
  read `meta.get("params_b")` (the registry meta subdict) instead. Source fields that
  aren't projected axes must be pulled from `meta`, not `a`.
- **`processed.js` wrapper drops `meta`:** `_build_dashboard_data.py` builds `payload`
  with a full `meta` block (model_count/version/generated/sources/sources_meta) but the
  serializer may write only `{sources, sources_meta, models}`. The artifact then lacks
  self-describing count/date and the UI can't show provenance. Serialize a wrapper that
  CARRIES `meta` (the viz loader unwraps `.models`, so a dict wrapper is fine).
- **Flat-list vs wrapped source shape:** a source-of-truth file may be a flat JSON list
  (e.g. `dirac/cache_hit_rates.json`) or `{models:[...]}`. The contract test that
  validates it MUST match the actual shape the `_build.py` reads — a mismatch fails the
  test even though the pipeline runs. Prefer flat lists; iterate directly.
- **Axis id redundancy double-prefix:** when an axis id already embeds the source
  prefix (e.g. `aa.aa_coding_index`, suffix `aa_coding_index`), the `ProjectionRow`
  field is `aa_coding_index` — NOT `aa_aa_coding_index`. Deriving the output key by
  blind string-prefixing (`"aa_" + suffix`) produces `aa_aa_coding_index` and the
  test/pipeline finds nothing. Rule: if the suffix already starts with the source
  prefix (`aa_`), use it as-is; otherwise prefix. Keep axis ids suffix-only where
  possible (`aa.coding_index` not `aa.aa_coding_index`) to avoid the trap.
- **Date/non-numeric axis crashes `round()`:** `_build_axes._build_axis` computes
  `lo,hi = min(vals),max(vals)` then `round(lo, range_decimals)`. For a date or
  string axis, `round` raises `TypeError: type str doesn't define __round__` and the
  whole `_build_axes` run aborts (axis never registers). Guard: only `round` when
  `isinstance(lo,(int,float))`. Date axes (`meta.release_date`) carry `range=None`.
- **`ModelType` enum must cover real registry values + never re-instantiate at return:** `RegistryModel.from_flat` builds the enum once with a safe net — `try: model_type = ModelType(mt) except ValueError: model_type = None` — then MUST use that `model_type` variable at the `return cls(...)` call. A stray `model_type=ModelType(mt)` at the return site **re-calls the constructor and bypasses the try/except**, raising `ValueError` on the first model with an unknown type (registry carries `proprietary`=30, `open`=4) and aborting the whole build before `processed.js` is written. Widen the enum (`PROPRIETARY="proprietary"`, `OPEN="open"`) AND keep the net; never re-instantiate `ModelType(mt)` at the return site.
- **`data/` is a Python namespace package (no `__init__.py`); test imports of pipeline modules must use the `data.` prefix, not `sources.` alone.** `data/sources/aa/_build.py` does `from ..._canonical import ...` (three-dot relative, top package = `data`). So a test that does `sys.path.insert(0, REPO/"data")` then `from sources.aa._build import _load_aa_api` raises `ImportError: attempted relative import beyond top-level package` (because with `data` on the path, `sources` becomes top-level and `...` escapes it). Correct form: `sys.path.insert(0, REPO)` (repo ROOT, not `REPO/data`) then `from data.sources.aa._build import _load_aa_api`. The pipeline CLI itself uses `PYTHONPATH=data` + `python -m data._pipeline` — same root. Apply the `data.` prefix to ANY pipeline module a test imports (`data.sources.aa._parse_charts`, `data._canonical`, etc.). Discovered when `tests/test_aa_charts_parse.py::test_validated_against_live_api` failed on the `sources.aa._build` import after a refresh; fixed by switching to the `data.`-prefixed import with repo root on path.
- **`ProjectionRow` duplicate field declarations silently override:** declaring the same field twice in a `@dataclass` (e.g. `iq_per_dollar_pt` at line 52 and again at line 119) does NOT raise — the second declaration silently wins. The first declaration is dead code. Before adding a new field, grep the dataclass body for the field name to check it isn't already declared. Symptom: confusing code reviews, accidental double-provenance entries in `FIELD_PROVENANCE`, and `to_dict` `optional_map` entries that reference a field declared elsewhere. Fix: remove the duplicate, keep one declaration + one `FIELD_PROVENANCE` entry + one `optional_map` entry.
- **`_pull_sources.py` must NOT strip API response fields:** reducing a 445-model API response to 7 fields at pull time (e.g. only `id`, `name`, `pricing`, `context_length`) throws away `benchmarks`, `design_arena`, `created`, `architecture`, `reasoning` — data that downstream registry steps need but can't get back from the API without another network call. The pull step stores the full response; the registry step picks what it needs. If the stored file is missing fields the registry step expects, the registry step silently gets None and the pipeline produces incomplete output with no error. Always inspect the stored JSON shape after a pull before wiring a registry merge.
- **API pricing field names may differ from documented examples:** OpenRouter's actual pricing keys are `prompt`/`completion` (per-token floats like `0.000002`), NOT `input`/`output` (which some docs use as illustrative placeholders). Always verify the actual key names from a live API call before writing parsing code. Mapping `pricing.input` → `pricing.prompt` is a silent null bug — the field exists under a different key.
- **Repurposing orphan JSONs (no new source, just enrichment):** orphan files in
  `data/sources/<x>/` (e.g. `aa_api_live.json`, `aa_scrape_progress.json`) can enrich
  existing models without a new axis source. Pattern: add a
  `get_x_extra(base) -> dict[slug, {...}]` loader, inject into the existing
  `get_x_models` merge (release_date into `meta`, creator backfill, extra benchmark
  scores into `benchmarks.aa`, scrape-tracker slugs → `confirmed_scraped` provenance
  flag). No new `SourceKey`, no new axis group needed for provenance flags. The live
  AA API (`aa_api_live.json`, 551 models) carries `release_date` + 16 benchmark scores
  (`hle`, `aime_25`, `terminalbench_v2_1`, …) the static enriched set lacks — promote
  those to real `aa.<key>` axes (see checklist step 8/9), not just leave them orphaned.
- **`RegistryModel` dead-code repurposing (validating serializer):** the typed
  `_domain/_entities.RegistryModel` was built but never instantiated (pipeline wrote
  plain dicts). To wire it WITHOUT rewriting every source: add a `from_flat(cls, d)`
  classmethod that wraps the flat `meta` dict in `RegistryModelMeta` (typed/validated)
  while keeping `pricing`/`benchmarks` as plain dicts (the pipeline emits dicts, not
  `AAPricing`/`CostBreakdownPricing` objects — those typed wrappers stay dead). Then
  `model_registry.json` is written via `[RegistryModel.from_flat(m).to_dict() for m in
  output_models]`. Pitfalls: (a) `RegistryModel.meta` is typed `RegistryModelMeta`, so
  passing the pipeline's plain-dict meta → `to_dict` calls `.to_dict()` on a dict →
  `AttributeError`; `from_flat` must construct `RegistryModelMeta(**meta)`. (b)
 `RegistryModelMeta.to_dict` skips empty/false fields, and `RegistryModel.to_dict`
 omits empty `pricing`/`benchmarks`/`meta` sections — so a round-trip test asserting
 `out == src` fails on `{}` vs omitted. Assert semantically:
 `(out.get("pricing") or {}) == (m.get("pricing") or {})`. (c) `from_flat` must
 translate `model_type` strings → `ModelType` (with unknown→None fallback).
 - **Typed-serializer silently drops undeclared meta fields (context_window regression):** once `RegistryModel.from_flat` is the registry writer, `RegistryModelMeta.to_dict()` emits ONLY fields declared on the dataclass. Any meta key the pipeline sets but `RegistryModelMeta` doesn't declare (e.g. `context_window`) is **silently dropped for ALL models** — registry/output go from fully-populated to 0 with NO error and tests stay green. Symptom in the UI: a viz field keyed on the dropped meta (crossover `sizeAxis: 'context_window'`) renders every circle at the default size. FIX: add EVERY meta key the pipeline writes to `RegistryModelMeta` AND capture it in `from_flat`. Audit rule after wiring any typed serializer: grep the pipeline's `meta` keys (`reg["meta"]`) and diff against the serializer's declared fields — any missing key is a silent-drop landmine. Also: a `meta.<x>` axis that exists ONLY as a hand-edited entry in `axes_catalog.json` (never generated by `_build_axes.py`) is **erased the next time the catalog is regenerated** — so every axis MUST be produced by a `_build_axis(...)` call in `_build_axes.py`, never left as a sole manual catalog entry. Both `meta.context_window` and `meta.release_date` must be generated. Regression test: assert `context_window` count ≥ 50 in `processed.js` AND `"meta.context_window" in catalog axes`. Operationalize the audit: run
 `scripts/serializer_drop_audit.py` after ANY serializer change — it round-trips
 every registry model through `RegistryModel.from_flat().to_dict()` and reports any
 meta key that silently disappears.

 - **Live-API overlay is nulls-only by default → AA price CHANGES don't propagate (silent stale price).** `_overlay_aa_api(model, aa_m)` fills `pricing.aa` only when the field is `None`. If an EARLIER source (chart scrape / JSON-LD / enriched) already set a price, a later AA reprice (e.g. gpt-5-6-luna 1/6 → 0.2/1.2, gpt-5-6-terra 2.5/15 → 2/12) is silently ignored and the registry keeps the OLD price. Symptom: fresh live API shows new price, but `model_registry.json` shows old — no error, tests pass. FIX: the live API is AA's authoritative, always-current pricing source, so its `pricing.aa` values must OVERRIDE (not just fill-null). Implement in `_overlay_aa_api`: for the `pricing.aa` section, `sec[k] = v` whenever `v is not None`; for `benchmarks.aa`, keep the nulls-only fill (intel/scores don't retro-change and we must not wipe chart-sourced values). After this fix, re-pull the live API and rebuild — repriced models update. Always re-verify a known-repriced model's price after a live-API refresh (gpt-5-6-luna/terra are the canaries).
- **AA chart parser must map by TITLE, not index (AA reorders/removes charts).** `data/sources/aa/_parse_charts.py` used a hardcoded `CHART_MAP = {0:"coding_index", 1:"intel", ...}`. AA's site moved the main Intelligence Index to index 0 (was 1) and REMOVED the standalone "Coding Index" and "Cost to Run" bar charts entirely (they became scatters with 0 model `<a>` slugs). Result: the parser mis-mapped Intelligence Index → `coding_index` (polluting that key) and parsed empty scatters. FIX: renamed to `CHART_TITLE_MAP` (title-substring → logical key, matched on `spans[0]`), iterate all entries, skip charts whose parse yields 0 rows. Order-independent and removal-safe. Coding Index / Cost to Run metrics now come ONLY from JSON-LD (`aa_coding_index`, `cost_segments.*`) — when AA drops a dataset from JSON-LD too (it did, 31jul), that metric is UNSOURCEABLE (see user rule: delete, don't placeholder). The pricing-chart validation test must tolerate AA reprices since the chart is a point-in-time snapshot: validate structural correctness (all parsed prices are floats, ≥5 slugs overlap the live API) + an unchanged anchor slug (gpt-5-6-sol 5/30), and SKIP the known-repriced slugs (gpt-5-6-luna, gpt-5-6-terra-medium, gpt-oss-20b-low) rather than asserting strict chart==API equality.
- **Test-env gotchas (Windows/MSYS + uvx):** (1) Pipeline tests need `data` importable as a package → run `PYTHONPATH=data uvx pytest tests/` (NOT bare `uvx pytest`). A test that does `sys.path.insert(0, REPO/"data")` + `from sources.aa._build import ...` raises `ImportError: attempted relative import beyond top-level package` — use `sys.path.insert(0, REPO)` + `from data.sources.aa._build import ...`. (2) `tests/test_data_contracts.py::test_all_viz_files_parse` needs `jsonschema` (test-only dep, not a pipeline dep) → run `PYTHONPATH=data uvx --with jsonschema pytest tests/`. (3) `tests/test_pipeline_determinism.py` is order-dependent (passed only because a sibling test set `data` on `sys.path`); harden it by inserting BOTH `REPO` and `DATA_DIR` on `sys.path` so it runs in isolation. (4) `build_from_cache()` writes to the repo's `data/`, so verify byte-identity via the determinism test (copies `data/` to tmp, runs twice) — it compares two fresh runs, NOT vs HEAD.

## What the pipeline does for you
Once the source file + resolver + 9 wiring points exist, `registry → axes → processed.js`
is automatic. Re-run the build commands; new axes appear under their source group; dashboard
viz reads them via `project_axes` with no further changes.

## Support files
- `references/dirac-source-contract.md` — Dirac.run cache-hit-rate extraction recipe +
  join-key resolution, worked from the actual 2026 table.
- `references/aa-source-refresh-sop.md` — the AA source refresh playbook: the `svg[role]`
  scrape selector + recharts/empty-svg validation, the broken-lucide vs partial-scrape
  failure modes (both REJECTED), the correct live-API endpoint, JSON-LD backtick-strip,
  Dirac HTML-table parse, and the full refresh sequence.
- `templates/source_module_skeleton.py` — `get_x_models(base)` starter.
- `templates/source_data_skeleton.json` — keyed-by-display-name source file starter.
- `scripts/serializer_drop_audit.py` — run after any serializer change; round-trips
  every registry model through `RegistryModel.from_flat()` and reports any meta key
  silently dropped by `RegistryModelMeta` (catches the context_window regression class
  of bug before it ships).
