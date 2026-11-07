# Circular Pipeline Dependency Recovery

Worked example from the LLM Pricing Dashboard pipeline refactoring.

## Symptoms

- Pipeline output dropped from 85 → 54 models between runs
- No code changes to the registry builder or dashboard builder
- Each pipeline run made the problem slightly worse
- The creator filter bar in the UI lost ~half its entries

## Root Cause

`_build_registry.py` read AA (primary source) data from `processed.js` — which was the OUTPUT of `_build_dashboard_data.py`, a LATER pipeline stage:

```
Current run of _build_dashboard_data.py → writes processed.js (54 models)
Next run of _build_registry.py          → reads processed.js (54 AA models)
                                        → writes model_registry.json (54 AA models)
Next run of _build_dashboard_data.py   → reads model_registry.json (54 AA models)
                                        → writes processed.js (54 models)
```

Once a filter reduced the curated count, the next pipeline run had fewer starting models and could never recover.

## Why It Wasn't Noticed Before

The initial `processed.js` was manually curated (85 models). The pipeline then self-sustained at 85 because filtering was inclusive. The domain model refactoring introduced stricter validation that excluded some models — and the circular dep locked in the smaller count.

## Investigation Path

1. **Git bisect** — diff HEAD vs current `processed.js` to see model count difference:
   ```bash
   git show HEAD:data/processed.js | python -c "import sys,json,re; d=json.loads(re.search(r'window\\.PROCESSED_DATA\\s*=\\s*(\\[.*?\\])\\s*;', sys.stdin.read(), re.DOTALL).group(1)); print(len(d))"
   ```

2. **Compare registry counts** — check AA coverage in committed vs current registry:
   ```python
   old_aa = sum(1 for m in old_reg['models'] if 'aa' in m.get('pricing',{}) or 'aa' in m.get('benchmarks',{}))
   cur_aa = sum(1 for m in cur_reg['models'] if 'aa' in m.get('pricing',{}) or 'aa' in m.get('benchmarks',{}))
   ```

3. **Map data sources per stage** — who reads what? The culprit was `_build_registry.py` line 139 reading `processed.js`.

## Fix — Two Phases

### Phase 1: Break the circular dependency

Switch the registry builder's AA source from `processed.js` to `aa_models_scraped.json`:

```python
# Before — reading curated output (CIRCULAR)
aa_js = Path(BASE, "data", "processed.js").read_text()

# After — reading raw source
scraped_path = os.path.join(BASE, "data", "sources", "aa", "raw", "aa_models_scraped.json")
with open(scraped_path) as f:
    scraped_models = json.load(f)
```

**Result:** 97 models, 23 creators. But Mistral was missing and the scraped data lacks enriched fields (blended pricing, cost_per_task, tokens_m, iq_per_mtok, iq_per_mtokdollar, useful_cost, cost segments). The user noticed the data loss immediately.

### Phase 2: Merge all AA data sources, don't rely on one

Reading from scraped data alone fixed the circular dep but lost features the old pipeline had because `aa_model_data.json` (38 enriched models) and `aa_cost_breakdown.json` (cost segments) were being read as a thin overlay onto processed.js — not as standalone sources.

The correct approach: **collect every AA data file and merge them.** Each contributes what it has:

```python
# 1) Build base entries from raw scraped data (99 models, basic pricing/intel/speed)
for m in scraped_models: ...

# 2) Enrich from aa_model_data.json (38 models)
#    - Overlay enriched fields: tokens_m, blended, useful_cost, iq_per_mtok onto overlapping models
#    - ADD models only in model_data not in scraped (eg Mistral Medium 3.5)
for slug, raw in aa_raw.items():
    if cid not in all_models:
        all_models[cid] = new_entry_from(raw)  # add model_data-only model
    else:
        overlay_enriched_fields(all_models[cid], raw)

# 3) Inject cost segments from aa_cost_breakdown.json (name-based fuzzy match)
for entry in cb_data.get("models", []):
    cid = match_name_to_cid(entry["name"])
    all_models[cid]["pricing"]["aa"]["cost_segments"] = extract_segments(entry)
```

The key insight: **don't replace one source with another. Merge them.** Each AA data file covers a different set of models and fields. The pipeline needs all of them.

**Name-based fuzzy matching for cost breakdown:** The cost breakdown uses display names ("DeepSeek V4 Flash (max)") while the registry uses canonical slugs ("deepseek-v4-flash"). Strip parentheticals, lowercase, hyphenate, then match against known IDs with substring fallback:

```python
cleaned = re.sub(r'\s*\(.*?\)\s*', '', src_name).strip().lower().replace(' ', '-')
# Exact match first, then substring
if known_slug == cleaned_name: ...
elif cleaned_name in known_slug or known_slug in cleaned_name: ...
```

### Field Mapping: aa_model_data.json → registry

| model_data field | Registry path | Notes |
|---|---|---|
| `inp` | pricing.aa.inp_price | input $/Mtok |
| `out` | pricing.aa.out_price | output $/Mtok |
| `blended` | pricing.aa.blended | blended $/Mtok |
| `cache` | pricing.aa.cache_hit_price | cache-hit $/Mtok |
| `cost` | pricing.aa.cost_per_task | cost per standard task |
| `tokens_m` | pricing.aa.tokens_m | tokens per task (millions) |
| `spd` | pricing.aa.speed_tps | tokens per second |
| `eff_cost_per_m` | pricing.aa.useful_cost | effective $/Mtok after reasoning tax |
| `intel` | benchmarks.aa.intel | intelligence score |
| `iq_per_1k` | benchmarks.aa.iq_per_mtok | IQ per thousand tokens (stored as per-M) |
| `cost_per_iq` | benchmarks.aa.iq_per_mtokdollar | cost per IQ point |

## Recovery Result (after both phases)

| Metric | Broken | Phase 1 only | Phase 2 (final) | Old baseline |
|--------|--------|-------------|-----------------|--------------|
| Curated models | 54 | 97 | **101** | 85 |
| Creators | ~15 | 23 | **24** (Mistral restored) | 24 |
| With AA intel | 81 | 93 | **98** | 81 |
| With pricing | 52 | 59 | **69** | 28 |
| With cost_per_task | 24 | 0 | **30** | 24 |
| With iq_per_mtok | 28 | 0 | **29** | 28 |
| With cost segments | 24 | 0 | **29** | 24 |

The Phase-2 merge strictly outperforms the old baseline on every metric.

## Prevention

- **Map data sources for every pipeline stage.** If any stage reads a file that another stage writes, you have a circular dependency.
- **Raw source beats curated output.** Always prefer the raw upstream data file over the pipeline's own output.
- **Merge, don't replace.** When switching data sources, collect all available files and merge them — each may cover different models/fields.
- **Test model count stability.** After pipeline refactoring, run twice and verify the count doesn't shrink.
- **Also test enriched field coverage.** Count more than just models — verify per-field coverage matches or exceeds the old baseline. `cost_per_task`, `tokens_m`, and `iq_per_mtok` are the most commonly dropped.

## File Structure (post-restructuring)

```
data/
  sources/
    aa/
      raw/
        aa_models_scraped.json    ← raw scraped AA data (99 models, basic pricing/intel/speed)
      enriched/
        aa_model_data.json        ← enriched AA data (38 models, blended/tokens_m/iq/etc)
        aa_cost_breakdown.json    ← cost segments (30 models, fuzzy-named)
      _build.py                   ← get_aa_models() merges all AA sources → domain entries
  processed.js                  ← output of _build_dashboard_data.py (101 curated models)
  model_registry.json           ← output of _build_registry.py (merged from ALL sources)
  _build_registry.py            ← calls sources.aa._build.get_aa_models() + other sources
  _build_dashboard_data.py      ← reads model_registry.json + axes_catalog.json
```
