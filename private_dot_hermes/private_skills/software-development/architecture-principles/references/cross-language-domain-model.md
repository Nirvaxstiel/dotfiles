# Cross-Language Domain Model Harmonization (Python ⟷ JS)

## The Pattern

```
Python _domain.py (rich dataclasses + typed constructors)
  → to_dict() / to_primitive() → flat JSON
    → JS _domain.js (class wrapping raw JSON with Object.assign + computed getters)
```

## Checklist

### Python side (`_domain.py`)
- [ ] Dataclasses with validated `__post_init__` or factory constructors
- [ ] Typed value objects (`PricePerMToken`, `CostPerTask`, etc.) not bare floats
- [ ] `to_dict()` / `to_primitive()` serialization producing flat flat JSON
- [ ] Enums: `Archetype`, `ModelType`, `SourceKey`

### JS side (`_domain.js`)
- [ ] Class wrapping raw JSON: `Object.assign(this, raw)` — all raw fields accessible as `.field`
- [ ] Computed getters for frontend-specific derived properties (e.g. `reasoningBucket`, `hasIntel`)
- [ ] Static helpers (e.g. `paretoFrontier()`) — not duplicated across viz scripts
- [ ] Parallel `MODELS` array (don't mutate `PROCESSED_DATA` in-place)
- [ ] Self-executing wrap block: `window.MODELS = raw.map(r => new ProjectionRow(r))`

### Integration
- [ ] Load domain module in HTML after data, before viz scripts
- [ ] `_boot.js` references `MODELS` with fallback to `PROCESSED_DATA`
- [ ] Check all viz script `render(mount, data)` calls pass `MODELS`
- [ ] Verify contract tests still pass (they check field counts, file existence)

### Adding a New Field: 5 Touchpoints

When extending the domain model with a new field (e.g. `context_window`), touch every layer in order:

  1. **Python value object** — `_domain.py`: frozen dataclass with validation + DomainValue base class
  2. **Python safe constructor** — `_domain.py`: `safe_*()` function that returns `None` for missing/invalid input
  3. **Entity field** — `ProjectionRow` dataclass: add `Optional[NewValueObject] = None` in correct position (after all required fields)
  4. **Serialization** — `to_dict()` in `ProjectionRow`: add to `optional_map` dict so it serializes via `as_primitive()`
  5. **JS getter** — `viz/_domain.js` `ProjectionRow` class: add computed getter + `has*` boolean getter

Additionally for fields from **non-axis sources** (enrichment files, not ProjectionEngine):
  - Pipeline script (`_build_dashboard_data.py`) loads the enrichment file and injects via the constructor call
  - The enrichment data lives in `data/sources/<source>/enriched/` as a flat JSON file
  - No addition to `axes_catalog.json` or `ALL_AXES` — enrichment bypasses the projection engine

**Verification after adding a new field:** Rebuild, check N models have the field, confirm tests pass.

## Pitfalls

### Derived fields silently lost during extraction
When extracting a domain model from inline pipeline code (e.g. `_build_dashboard_data.py` → `_domain.py`), **derived/computed fields are the most common casualty**. Inline code often computes them mid-pipeline via a `for m in models: m["field"] = ...` loop that's easy to miss during extraction.

Symptoms: a dashboard tab goes blank because every model has `null` for a field the viz filters on. All source-supplied fields pass through fine — only the computed ones vanish.

Mitigation:
1. Before extraction, list ALL fields in the serialized output and annotate each as *source-supplied* or *computed*.
2. Audit `compute_derived()` (or equivalent) in the old code for every computation step.
3. For each computed field, add the computation to `compute_derived()` in the new domain class.
4. Verify post-extraction: compare field-value counts between old and new output (not just schema).

### Other
- JS `for...in` over `ProjectionRow` instances enumerates computed getters — avoid unless wanted.
- `Object.assign(this, raw)` copies all source fields, including `null` — no implicit defaults.

## Key Decisions

| Question | Decision |
|----------|----------|
| Re-validate on JS side? | No — pipeline already guarantees shape. JS adds accessors only. |
| Modify raw data in-place? | No — keep `PROCESSED_DATA` untouched, add `MODELS` parallel array. |
| Use Proxy vs Object.assign? | `Object.assign` — simpler, debuggable, no prototype edge cases. |
| Compute derived fields on which side? | Pipeline (Python) for universal ones (iq/mtok, cost/IQ). JS for frontend-specific (reasoning buckets, Pareto status). |
