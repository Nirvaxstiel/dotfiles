# Data Pipeline: Loop Extraction & Boilerplate Reduction

## The Pattern: Repetitive Axis/Stub Blocks

Data pipelines often define axes or merge sources in groups. Each group has:

1. A list of tuples (axis ID, label, type, unit, ...)
2. A loop over models counting non-null values + collecting range
3. A dict-building append to the output list

When 6 groups repeat the same ~25-line loop structure, extract a helper.

## Helper Function Template for Axis Building

```python
def _build_axis(models, axis_id, source, label, type_, unit, hib, desc, group,
                path, key=None, range_decimals=None):
    count = 0
    vals = []
    for m in models:
        sec = m
        for k in path:
            sec = sec.get(k, {})
        if not sec:
            continue
        v = sec.get(key or axis_id.split(".")[-1])
        if v is not None:
            count += 1
            vals.append(v)
    rng = None
    if vals:
        lo, hi = min(vals), max(vals)
        if range_decimals is not None:
            lo, hi = round(lo, range_decimals), round(hi, range_decimals)
        rng = [lo, hi]
    return {
        "id": axis_id, "label": label, "source": source, "type": type_,
        "unit": unit, "higher_is_better": hib, "description": desc,
        "models_have": count, "range": rng, "group": group,
    }
```

Then each axis is one call:
```python
ba("aa.inp_price", "AA", "Input Price ($/Mtok)", "pricing", "$/M tok", False,
   "description", "Pricing", ["pricing", "aa"], range_decimals=4)
```

### When to extract:
- 5+ blocks of the same shape (6 axis groups, 5 source stubs)
- NOT for 2-3 repetitions — those are fine as-is

### When NOT to extract:
- Each block has fundamentally different logic (CSV vs JSON parsing)
- The extraction would require complex `**kwargs` or callable parameters that obscure the intent

## Stub-Creation Helper (Registry Build)

When merging N sources into a registry dict, each source starts with:

```python
if cid not in all_models:
    all_models[cid] = {"id": cid, "name": ..., "meta": {}, "pricing": {}, ...}
```

Extract:

```python
def _ensure(all_models, cid, **overrides):
    if cid not in all_models:
        all_models[cid] = {
            "id": cid, "name": None, "creator": None, "model_type": None,
            "meta": {}, "pricing": {}, "benchmarks": {}, "aliases": {},
            **overrides,
        }
    return all_models[cid]
```

**CRITICAL:** Never use `MODEL_STUB = {"meta": {}, ...}` as a module-level constant and spread with `**MODEL_STUB` — the SAME empty `{}` references are shared across every model. Subsequent `model["aliases"]["x"] = y` sets it on ALL models. Inline the dict literals.

**overrides only apply to new entries** — existing models are never modified by _ensure (unlike the mutable-MODEL_STUB bug which was an actual regression).

Same example: `_ensure` replaces a 10-line stub with one line while guaranteeing identical shape for all sources.

## Package Extraction for 700+ Line Files

When a file uses section banners (`# ═══════`, `// ────`) to organize internal structure,
it's a sign the file should be a package.

### Boundary identification:
1. **Enums/base** — DomainValue marker, all enums (ModelType, Provenance, Archetype, etc.)
2. **Value objects** — scalar typed wrappers with validation (PricePerMToken, IntelligenceScore, etc.)
3. **Entities** — compound objects with relationships (Axis, AAPricing, RegistryModel, etc.)
4. **Projection** — the main output entity (ProjectionRow + Meta + provenance + serialization)
5. **Safe constructors** — boundary-safe factories for nullable/NaN source data

### Dependency chain (must be acyclic):
```
_base (enums) → _values → _entities → _projection
                                          ↓
                                     _serialize (safe_*)
```

`_serialize` depends on `_values` and `_base` but not on `_entities` or `_projection`.

### `__init__.py` re-exports:
```
from ._base import DomainValue, Archetype, ModelType, ...
from ._values import PricePerMToken, IntelligenceScore, ...
from ._entities import Axis, AAPricing, RegistryModel, ...
from ._projection import ProjectionRow, ProjectionRowMeta
from ._serialize import safe_ppm, safe_intel, ...
```

Keep importers unchanged — `from _domain import ProjectionRow, Archetype` still works.

### Verification:
```bash
python -m py_compile data/_domain/_base.py
python -m py_compile data/_domain/_values.py
... (every submodule)
python -m data._build_dashboard_data
python -m pytest tests/ -v
```
