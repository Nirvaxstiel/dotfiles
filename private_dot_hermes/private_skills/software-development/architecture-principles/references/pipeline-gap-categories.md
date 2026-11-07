# Pipeline Gap Categories — Audit Checklist

When auditing a multi-source data pipeline, check for these gap categories.
Each category is a class of issue that tends to appear across projects.

## 1. Dead Features (Modeled but Never Computed)

Enums, fields, or computation methods defined in the domain model that are never
assigned a non-null/non-default value in any pipeline stage.

**Checklist:**
- [ ] Enum defined with 4+ values, but only the default/fallback is ever used
- [ ] Boolean field defaulted to `False` at every source entry point
- [ ] Percentile/rank field always `null` in output
- [ ] `compute_derived()` method exists but logic is `pass` or trivial
- [ ] Frontend tooltip shows the field but it's always a default/empty value

## 2. Silent Failure Modes

Code paths that return a degraded result without logging, warning, or changing
the output metadata.

**Checklist:**
- [ ] API fetch wrapped in try/except that returns `{}` on any error (no log)
- [ ] JSON file read has no schema validation — cryptic short keys could drift
- [ ] List-index access without bounds check
- [ ] Missing file silently skipped (treated as optional, not an error)
- [ ] Fallback value used without tracking which models used the fallback

## 3. Ungoverned Data Overlays

Files or code paths that can inject arbitrary data into the domain model with
no validation of keys, types, or referential integrity.

**Checklist:**
- [ ] Static JSON file can add any key to any model's meta (no allowed-keys list)
- [ ] Fields with documented units/range accept any float without checking
- [ ] Cross-source fill can overwrite with semantically different data
- [ ] Keys in overlay file are not validated against registry IDs

## 4. Normalization in Wrong Layer

When normalization (min-max scaling, percentiles, composite scores) is computed
in the frontend JS but depends on dataset-wide statistics.

**Checklist:**
- [ ] Radar chart computes `norm = (v - min) / (max - min)` in JS
- [ ] Chart uses `Math.max(...data.map(m => m.field))` for axis bounds
- [ ] Sort order or tiering depends on ranking relative to all models
- [ ] Derived metric computed identically in every viz module (code dup)

**Fix:** Compute normalization at pipeline build time, store in output data.

## 5. Missing Cross-Stage Consistency Checks

Values that should be identical across different data sources or stages but are
never verified.

**Checklist:**
- [ ] Same field from two different source files for the same model never compared
- [ ] Two pricing sources for the same model never cross-referenced
- [ ] Per-model aggregate and source totals diverge without notice
- [ ] Derived metric never ballpark-tested against a source-verified value

## 6. Data Carried but Never Used

Fields or values that are fetched, stored, passed through the entire pipeline,
but never displayed or queried.

**Checklist:**
- [ ] Field pulled from API but not stored in registry output
- [ ] Field stored in registry but not projected into dashboard rows
- [ ] Field projected into rows but not serialized in `to_dict()`
- [ ] Field serialized but not used in any viz module
- [ ] Dict key present in source data but never emitted by build script
