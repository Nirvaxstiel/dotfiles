---
name: aa-api-live-fill
category: kei-projects
description: "Query the Artificial Analysis (AA) live API to fill null data fields at source-fetch stage. Covers endpoint, auth, slug mapping, and the nulls-only merge pattern that respects multi-source honesty."
version: 1.0.0
---

# AA Live API — Fill Nulls from Authoritative Source

Use when a project scrapes Artificial Analysis data but has gaps (missing prices,
intel, speed) and you have an AA API key. Goal: fill blanks WITHOUT overriding
existing values (honest multi-source design — null = gap, not conflict).

## Endpoint & auth
- **Free-tier key (this project's key): use `https://artificialanalysis.ai/api/v2/language/models/free`** — the `/free` shape is the ONLY endpoint a Free key can hit. It returns `tier: "free"` and exposes headline indices, medians, input/output pricing, AND `artificial_analysis_intelligence_index_cost.cost_per_task.total_cost`.
- **Pro/Commercial key:** `https://artificialanalysis.ai/api/v2/language/models` (no `/free`). Pro adds blended pricing, percentiles, context window, params, per-benchmark scores.
- ⚠️ Endpoint caveat (corrected 2026-07): the earlier claim that `https://artificialanalysis.ai/api/v2/data/llms/models` **always 403s** is FALSE for a Pro/Commercial key. On 2026-07-13 a live `curl -H "x-api-key: $AA_API_KEY" https://artificialanalysis.ai/api/v2/data/llms/models` returned `{"status":200,"data":[572 models]}` with the user's current key. The 403 was observed on the **Free** tier. So for a Pro key, BOTH `api/v2/data/llms/models` and `api/v2/language/models` are viable. If you get a 403, check the key tier first — don't assume the path is wrong.
- **Pagination is mandatory on `/free`:** response carries `pagination: { page, page_size, total_pages, has_more }`. Loop `?page=N` until `not pagination.has_more` (or `page >= total_pages`). At 200/page there are **3 pages**; fetching only page 1 silently drops ~⅔ of models (incl. the one you need). Free tier = 100 req/day, so 3 requests/build is fine.
- Auth: header `x-api-key: <KEY>`. Free tier ~100 req/day.
- Match by `slug` (e.g. `gpt-oss-120b`). `intelligence_index_version` (e.g. `4.1`) is in the response; scores only comparable within the same major version.

## What the API does NOT expose (gotcha)

The live API has **no** raw "tokens per task" / "output tokens per task" field. Searched keys:
only `price_1m_input_tokens`, `median_output_tokens_per_second`, `median_time_to_first_token_seconds`,
benchmark scores. AA publishes "Output Tokens per Intelligence Index Task" on its website/methodology
pages, but it is **not** in the API response — it lives only in the hand-curated
`data/sources/aa/enriched/aa_model_data.csv` (38 AA models, real AA values in millions).
Do NOT expect `tokens_m` from this API fill. If you need `tokens_m` populated for more
models, the source is the AA website charts, not this endpoint.

## What the API DOES expose — `artificial_analysis_intelligence_index_cost` (per-task cost)

The endpoint carries a dedicated cost object — **this is the authoritative `cost_per_task`**,
NOT the hand-curated enriched `cost` field (which is full-output cost, see pitfalls §1).
- `artificial_analysis_intelligence_index_cost.cost_per_task.total_cost` — **FREE tier includes this.** Weighted avg USD per Intelligence Index task, segmented by token type, weighted by Intelligence Index weight. Lower is better.
- `artificial_analysis_intelligence_index_cost.total_cost` — total cost to run all Intelligence Index evals.
- Pro tier adds `input_cost`, `reasoning_cost`, `answer_cost` (both `total` and `cost_per_task` levels).

**This is priority-1 for `cost_per_task`** (see `references/aa-data-viz-pitfalls.md` §1 chain):
API `cost_per_task.total_cost` → cost-breakdown JSON `total_cost_per_task_usd` → image-derived → null.
The enriched `aa_model_data.json` `cost` field = `eff_cost_per_m × tokens_m` (full-output) must
NEVER map to `cost_per_task` (that reintroduces the $5,630 fable bug).

## Key storage (NEVER hardcode literal)
- Store in the agent secrets env file as `AA_API_KEY`.
- Read at runtime: `os.environ.get("AA_API_KEY")` OR parse the env file line
  `AA_API_KEY=...` (the shell session may not have it exported even if the file does).
- Hermes `terminal` runs in Bash; `execute_code` uses a separate Python kernel. Check the key in the process that will make the request. Print only whether it is set; never print the value.

## Field map (AA JSON → canonical)
| AA field | canonical | type |
|---|---|---|
| `pricing.price_1m_input_tokens` | `inp_price` | $/M tok |
| `pricing.price_1m_output_tokens` | `out_price` | $/M tok |
| `pricing.price_1m_blended_3_to_1` | `blended` | $/M tok |
| `median_output_tokens_per_second` | `speed_tps` | tok/s |
| `median_time_to_first_token_seconds` | `ttft` | s |
| `artificial_analysis_intelligence_index_cost.cost_per_task.total_cost` | `cost_per_task` | USD (priority-1 per-task) |
| `evaluations.artificial_analysis_intelligence_index` | `intel` | 0-100 |
| `evaluations.artificial_analysis_coding_index` | `coding_index` | 0-100 |
| `evaluations.artificial_analysis_math_index` | `math_index` | 0-100 |
| `evaluations.mmlu_pro` | `mmlu_pro` | 0-1 |
| `evaluations.gpqa` | `gpqa` | 0-1 |

## The nulls-only merge (THE pattern)
```python
def _overlay_aa_api(model, aa_m):
    ev = aa_m.get("evaluations", {}) or {}
    pr = aa_m.get("pricing", {}) or {}
    p = model.setdefault("pricing", {}).setdefault("aa", {})
    b = model.setdefault("benchmarks", {}).setdefault("aa", {})

    # Top-level creator + meta.release_date live HERE, not in pricing.aa/benchmarks.aa.
    # Chart/JSON-LD-seeded models (e.g. gpt-5-6-*) enter via Stage 0/0b and SKIP the
    # static scrape's live overlay, so this is the ONLY place that can backfill them.
    if model.get("creator") is None:
        creator = (aa_m.get("model_creator") or {}).get("name")
        if creator:
            model["creator"] = creator
    if model.get("meta", {}).get("release_date") is None:
        rd = aa_m.get("release_date")
        if rd:
            model.setdefault("meta", {})["release_date"] = rd

    fills = [
        (p, {"inp_price": pr.get("price_1m_input_tokens"), "out_price": ..., "blended": ..., "speed_tps": aa_m.get("median_output_tokens_per_second"), "ttft": aa_m.get("median_time_to_first_token_seconds")}),
        (b, {"intel": ev.get("artificial_analysis_intelligence_index"), "coding_index": ..., "math_index": ..., "mmlu_pro": ..., "gpqa": ...}),
    ]
    for sec, kv in fills:
        for k, v in kv.items():
            if v is not None and sec.get(k) is None:   # NULLS ONLY — no override
                sec[k] = v
```
**Do NOT use a dict as a loop key** (`{p: {...}}` → `unhashable type: 'dict'`).
Use a list of `(section, kv)` tuples.

## New-field checklist (when adding `ttft` or similar)
If the field is brand new (not in the existing schema), it must be threaded through ALL of:
1. Value class + `safe_*` factory in domain model (`_domain.py`)
2. `ProjectionRow` dataclass field
3. Projection mapping in `_build_dashboard_data.py` (`a.get("aa.ttft")` → `safe_ttft`) + import
4. `ALL_AXES` list in `_build_dashboard_data.py`
5. Axis definition in `_build_axes.py` (or it gets regenerated/overwritten by the catalog builder)
6. `to_dict()` optional_map in `_domain.py`

Missing any of 1-6 → field silently drops to 0/null in output.

## Pipeline rule (this project)
New fields enter at SOURCE-FETCH stage (in `_build.py`), flow
registry → dashboard. Never feed a build stage from its own output.

## Pitfalls (paid so you don't)
- **Cached-first is the safe default.** The repo ships `data/sources/aa/aa_api_live.json`
  (a gitignored workflow artifact: `{"status":200, "data":[551 models...]}` keyed by
  `slug`). Prefer reading it over a live call — it avoids burning the 100 req/day Free
  quota and sidesteps the 403 bug. `_load_aa_api(base)` should: (1) `json.load` the cached
  file, return `{m["slug"]: m for m in data if slug}`; (2) only if absent/missing, do the
  live HTTPS call against `/free` (Pro: `/language/models`). A live call that 403s/errors
  must `return {}` (failure = no fill, not a crash).
- **The repo code had the 403 bug live.** `sources/aa/_build.py::_load_aa_api` historically
  hit `https://artificialanalysis.ai/api/v2/data/llms/models` (the 403 path) and wrapped in
  `try/except: return {}` — so the live fill NEVER ran and pricing stayed at OpenRouter-only
  coverage. Fixing it to read `aa_api_live.json` first lifted `inp_price`/`out_price`/
  `blended` from 39 → 104 models. When you see thin AA pricing coverage, check whether the
  live loader is actually executing (grep the cache path in `_load_aa_api`).
- **`aa_scrape_progress.json` is a real provenance artifact** (`{scraped:[slug,...]}`).
  Wire it as a `meta.aa_img_scraped` flag in `_build_registry.py` so the UI can show which
  models were image-transcribed. Don't leave it orphaned.
- **Enabling the live API can regress `tests/test_data_contracts.py::test_aa_pricing_fully_populated`.** The live API adds `intel` (via `evaluations.artificial_analysis_intelligence_index`) to models that previously had NO intel. Those models then qualify for the test's `aa_models` filter (`intel is not None or inp_price is not None`) and expose that they have no `inp_price`/`out_price`/`blended`. If you see this, the model legitimately lacks pricing in AA — do NOT weaken the assertion casually; check whether the slug-match gap above is why pricing wasn't applied. Before this skill's endpoint fix, the API call 403'd and returned `{}`, so the overlay never ran and the test passed by accident.
- Build artifacts go stale across rebuilds: `model_registry.json` / `processed.js` on disk may reflect an OLD build. After changing `_build.py`, always run the full 3-step rebuild (`_build_registry` → `_build_axes` → `_build_dashboard_data`) before inspecting output files, or you'll chase ghosts in a stale `processed.js`.
- **`_overlay_aa_api` MUST backfill `creator` + `meta.release_date`, not just pricing/benchmarks.** A 2026-07 regression shipped an overlay that filled only `pricing.aa` and `benchmarks.aa` — so chart/JSON-LD-seeded models (gpt-5-6-sol/terra, grok-1, …) had `creator=None` and vanished from the creator legend even though the live API carried `model_creator.name="OpenAI"`. Root cause: those slugs skip the static-scrape step (only 99 models there) and enter via Stage 0/0b; `_step_live_api` finds them via `aliases.aa` and calls `_overlay_aa_api`, but the overlay silently dropped `creator`/`release_date`. Fix: add the top-level `creator` (from `model_creator.name`) + `meta.release_date` backfill with null-guards (see the nulls-only merge code block above). After fixing, assert `0` AA models with `intel` have null `creator` (was the 5.6 class). Any new creator surfaced this way must also be added to `viz/_shared.js` `CREATOR_COLORS` or `test_all_creators_have_colors` fails — runtime falls back to a hash color but the contract test wants a curated hue.
- **`_step_live_api` MUST run LAST (after `_step_enriched` AND `_step_cost_breakdown`).** A 2026-07 bug had it at Stage 1.5 (right after `_step_scraped`), so models first introduced by `_step_enriched`/`_step_cost_breakdown` (~5 models: k2-think-v2, claude-4.5-haiku-reasoning, mistral-medium-3.5, qwen3.5-397b-a17b, claude-sonnet-4.6-adaptive) were NOT in `all_models` yet when the overlay loop ran → they never got `creator`/`release_date` even though the overlay logic was correct. Symptom: `k2-think-v2` shows `creator='Google'` (from elsewhere) but `release_date=None` despite the live API carrying both. DIAGNOSIS TRICK: print `len(all_models)` inside `_step_live_api` and compare to the final registry count — if it's lower (e.g. 113 vs 118), late-added models are being skipped. Fix: move the `_step_live_api(all_models, base)` call to the very end of `get_aa_models`, after cost_breakdown. Verify with a null-audit: after rebuild, `AA models with null release_date` should be `0`.
- **Re-pull the live API to source `creator`/`release_date` for brand-new models.** The committed `aa_api_live.json` can be stale; a model launched that day (e.g. `kimi-k3`, 2026-07-16) may be ABSENT from the committed pull (572 models) but PRESENT in a fresh pull (579 models) the same day — with `model_creator.name` + `release_date` populated. When a JSON-LD-only model (no OpenRouter/Arena vendor, not in the committed live pull) needs a sourced `creator`, re-run the curl and overwrite `aa_api_live.json` BEFORE the build. Don't wing the vendor name from memory — the live API is the sourced path. After re-pull, assert the slug now resolves in `_load_aa_api`. (See also aa-data-acquisition Pitfalls: JSON-LD export often arrives Markdown-fence-wrapped.)
- **JSON-LD export often arrives Markdown-fence-wrapped.** A console `copy(JSON.stringify(out))` can land in the file as `` `[{...}]` `` (leading+trailing backtick) instead of bare JSON. `json.load` on that raises `Extra data` (the trailing backtick). Strip BOTH ends before parsing: `raw.strip().strip("`")`. The committed `aa_jsonld_export.json` must be valid JSON (the loader does `json.load` directly) — so when copying a fresh export, strip the fences and pretty-print (`json.dump(indent=2)`) so the file is diff-readable. A 23jul2026 export had exactly this; the first `json.load` attempt threw `Extra data: line 1 column 37697` until both backticks were stripped.
- **Validate scraped source SHAPES before ingesting — a broken scrape silently degrades the dashboard.** A 2026-07 ingestion pulled `13jul2026_svg_scraped.json` that looked like a valid AA SVG export (16 entries of `{svg, spans}`) but every `svg` was a `lucide` UI icon (`<svg class="lucide lucide-...">`), NOT the recharts chart surface (`<svg class="recharts-surface" width="2276">`) the parser needs. Overwriting `aa_charts_export.json` with it would have wiped ALL AA chart metrics. Check: count entries whose `svg` contains `recharts-surface` vs `lucide` — if 0 recharts, the scrape is garbage, KEEP the old file. The JSON-LD sibling (`13jul2026_jsonld.json`) was valid (11 datasets, all with data arrays). Always diff shape/count vs the committed file before `cp`. This recurred on 23jul2026 with the SAME lucide-icon failure — the SVG scrape method is fragile; treat any SVG export with 0 `recharts-surface` as broken and ask the user to re-scrape (the valid committed `aa_charts_export.json` from an earlier good scrape is the source of truth to keep).

## Verification
- Rebuild, then count non-null in `processed.js` for the new fields.
- Add a contract test asserting AA models have the populated fields.
- `pytest tests/ -q` must stay green.
