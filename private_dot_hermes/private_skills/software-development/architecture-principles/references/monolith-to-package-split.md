# Monolith-to-Package Split: `_domain.py` → `_domain/` Package

**Context:** LLM Pricing Dashboard — `_domain.py` was 1050 lines containing enums, value objects, entities, and safe constructors. Too large to navigate without section banners (which the user forbids). Split into a 5-file package.

## When to apply

Any Python file that:
- Exceeds ~400 lines AND
- Has multiple conceptual sections (enums, value objects, entities, helpers) AND
- Currently uses `# ═══════` banner dividers or `# ── Section ──` comments to organize

The banner dividers are a signal: the file is trying to be a package, not a module.

## Package structure

```
data/_domain.py              ← DELETE (was 1050 lines)
data/_domain/                ← CREATE
  __init__.py                ← re-exports everything consumers need
  _base.py                   ← DomainValue marker + ALL enums (ModelType, Provenance, etc.)
  _values.py                 ← ALL scalar value objects (PricePerMToken through Count)
  _entities.py               ← Entity dataclasses (Axis, AAPricing, RegistryModel, etc.)
  _projection.py             ← ProjectionRow + Meta + FIELD_PROVENANCE + to_dict()
  _serialize.py              ← to_primitive + safe_* + try_* constructors
```

## Dependency chain (acyclic — must be one-way)

```
_base.py
   ↓
_values.py  (imports from _base)
   ↓
_entities.py  (imports from _base, _values)
   ↓
_projection.py  (imports from _base, _values)
   ↓
_serialize.py  (imports from _base, _values)
```

No circular deps. `_projection` and `_serialize` are leaf modules.

## Importers to update

Only 2 files import from `_domain`:
- `data/_build_dashboard_data.py` — `from _domain import ProjectionRow, Archetype, ...`
- `tests/test_data_contracts.py` — `from _domain import ProjectionRow, Provenance`

Both continue to work because `__init__.py` re-exports everything. No consumer code changes needed.

## `__init__.py` pattern

```python
from ._base import (DomainValue, ModelType, Provenance, ...)
from ._values import (PricePerMToken, PricePerToken, ...)
from ._entities import (Axis, AAPricing, RegistryModel, ...)
from ._projection import ProjectionRowMeta, ProjectionRow
from ._serialize import (to_primitive, safe_ppm, safe_intel, ..., try_archetype)
```

## Pitfalls

- **Missing `DomainValue` import in `_projection.py`:** The `to_dict()` method uses `isinstance(val, DomainValue)` but this was only imported in the monolith via the shared header. Each submodule must import its own dependencies.
- **`from __future__ import annotations` removal:** The monolith had it for `str | None` syntax. The package split didn't need it (Python 3.11+ supports `X | None` in `Optional[X]` contexts without it). Test with `python -m py_compile`.
- **Delete the old file before testing:** If both `_domain.py` and `_domain/` exist, Python prefers the file over the package on some import paths. `rm data/_domain.py` first.
- **`__init__.py` is the API boundary:** Don't export internal helpers (like `_hyphens_to_dots`). Only export what consumers use. Keeps refactoring freedom inside the package.

## Verification

```bash
cd data && python -c "from _domain import ProjectionRow, Archetype, safe_ppm; print('ok')"
python -m data._build_dashboard_data
python -m pytest tests/ -v
```
