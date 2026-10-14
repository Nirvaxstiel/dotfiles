# AA JSON-LD Acquisition — field map & integration recipe

The authoritative AA data source is NOT the website's chart-image download (broken:
visible-viewport only, ignores scroll). It is the **JSON-LD `Dataset` array** the AA
comparison pages embed. The user runs a console query on the page, which returns an
array of `Dataset` objects, saved INSIDE the repo as `data/sources/aa/aa_jsonld_export.json`
(renamed from the ad-hoc `jsonified-artificialanalysis-data.json`). Copy a fresh export
there on each refresh.

## File shape
Top-level: list of 11–12 objects. Each `{"@type": "Dataset", "name": "<chart>", "data": [...]}`.
The LAST element is `{"@type": "FAQPage", "data": []}` — skip it (don't assert all are Dataset).
Each `data[]` entry: `{"label": "GPT-5.6 Sol (max)", "detailsUrl": "/models/gpt-5-6-sol", <metric fields>}`.
`detailsUrl` → slug (already tier-aware: `gpt-5-6-sol-medium`). Resolve via `resolve_from_slug`.

## 11 datasets → `aa.*` field map
| Dataset `name` | Entry field(s) | → registry path |
|---|---|---|
| Intelligence | `artificialAnalysisIntelligenceIndex` | benchmarks.aa.intel |
| Artificial Analysis Intelligence Index by Open Weights / Proprietary | `intelligenceIndex` | benchmarks.aa.intel (SUPERSET — use this one) |
| Speed | `medianOutputSpeed` | pricing.aa.speed_tps |
| Cost per Task | `costPerIntelligenceIndexTask` | pricing.aa.cost_per_task |
| Artificial Analysis Coding Index | `codingIndex` | benchmarks.aa.aa_coding_index |
| AA-Omniscience Hallucination Rate | `omniscienceHallucinationRate` | benchmarks.aa.omniscience_hallucination_rate |
| AA-Briefcase Analytical Quality & Presentation Elo | `aaBriefcaseQualityElos[]` (PropertyValue list; take `analyticalQuality mid` / `presentation mid`) | benchmarks.aa.briefcase_analytical_quality_elo / briefcase_presentation_elo |
| Time per Intelligence Index Task | `timePerTask` | benchmarks.aa.time_per_task |
| Cost to Run Artificial Analysis Intelligence Index | `answerCost`, `reasoningCost`, `cacheWriteCost`, `cacheReadCost`, `nonCacheInputCost` | pricing.aa.cost_segments.* |
| Pricing: Cache Hit, Input, and Output | `pricing[]` (PropertyValue list; `inputPrice` / `outputPrice`) | pricing.aa.inp_price / out_price |

Note: `aaBriefcaseQualityElos` and `pricing` are **lists of `{name,value}` PropertyValues**,
not flat fields — extract with `prop_vals(e, field)` → `{name: value}`.

## Two Intelligence datasets — dedup rule
Intelligence (`artificialAnalysisIntelligenceIndex`) and Open-Weights/Proprietary
(`intelligenceIndex`) are VALUE-IDENTICAL on shared slugs (verified: 4 shared, 0 diffs).
Use ONLY the Open-Weights/Proprietary superset (20 entries vs 11) for `intel`. Do not
double-count. Assert value-identity before collapsing — never collapse blindly.
This is the user's hard rule: *dedup only after proving values are genuinely different.*

## Integration (in `data/sources/aa/_build.py`)
- `get_aa_jsonld_models(aa_dir)` → dict[cid, record]. Called as Step 0 inside
  `get_aa_models`, BEFORE the scraped loop. Seeds brand-new slugs (gpt-5-6-*) as full
  records and enriches existing ones fill-nulls-only. `aa_dir` = `data/sources/aa`;
  loader resolves `os.path.join(aa_dir, "aa_jsonld_export.json")`.
- **Seed NEW models with the FULL schema (all keys None), not a partial dict.** The
  `ensure(slug)` helper must initialize `pricing.aa` and `benchmarks.aa` with EVERY key
  the downstream overlays (`_overlay_enriched`, `_overlay_aa_api`) touch, set to None —
  those do direct `p["cache_hit_price"]` key access and KeyError on a partial dict.
  Corollary: after pre-populating, any `if key not in dict` "unset" guard must become
  `if dict.get(key) is None`, else it never fires and silently drops the JSON-LD value
  (this bit Briefcase: `if dst not in b` → `if b.get(dst) is None`).
- **Scraped loop must MERGE, not overwrite** (see aa-data-acquisition Pitfalls). Add
  `_merge_fill_nulls(existing, scraped)` so JSON-LD-only fields survive on existing models.
  The pre-fix bug: `all_models[cid] = {...}` hard-replaced the JSON-LD-seeded record,
  wiping `omniscience_hallucination_rate` etc. on existing models.
- File location: `data/sources/aa/aa_jsonld_export.json` (inside the repo). Loader
  resolves `os.path.join(aa_dir, "aa_jsonld_export.json")`.

## New axes wired this session (add to _build_axes / ALL_AXES / ProjectionRow / provenance)
`aa.omniscience_hallucination_rate`, `aa.briefcase_analytical_quality_elo`,
`aa.briefcase_presentation_elo`, `aa.time_per_task`. Output key for time_per_task is
`aa_time_per_task` (not `time_per_task`) — verify against the actual serialized dict key
when writing tests; the test's `m.get("time_per_task")` will silently read None.

## Known gaps (gpt-5.6 variant batch)
- The gpt-5.6 variants are NOT in the JSON-LD **Pricing** dataset (0 entries) → they have
  `intel`/benchmarks but no `inp_price`/`out_price`/`blended`. The contract test
  `test_aa_pricing_fully_populated` fails for them unless the console query is re-run
  with the Pricing chart selected, or the test is scoped to exclude no-pricing models.
- Omniscience dataset has 0 gpt-5.6 entries → omniscience axis populated only for older
  models (grok-4-3 etc.), not the new variants.
