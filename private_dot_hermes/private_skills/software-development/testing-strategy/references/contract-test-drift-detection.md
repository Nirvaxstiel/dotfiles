# Contract Test: Drift Detection Between JS Axis Config & Pipeline Data

## Pattern

Validate schema integrity between a JavaScript source-of-truth config (e.g. `window.RADAR_AXES` in `_shared.js`) and the actual data output (`processed.json`). Catches when:

- A new axis is added to the viz but its underlying field doesn't exist in the data
- A field name changes in the pipeline but the viz dependency mapping isn't updated
- A data field becomes dead (no viz references it)
- The axis definition is restructured in JS but the test dependency map is stale

## Architecture

```
JS (viz/_shared.js)             Python (test_drift_detection.py)
┌─────────────────────┐         ┌──────────────────────────────┐
│ RADAR_AXES = [       │  parse  │ parse_radar_axes() via regex │
│   {key:'avgIQ',...}  │ ──────→ │                              │
│   {key:'avgSpeed',..}│         │ AXIS_FIELD_DEPENDENCIES map  │
│ ]                    │         │   avgIQ    → ["intel"]       │
└─────────────────────┘         │   avgSpeed → ["speed_tps"]   │
                                │   costEff  → ["cost_per_task"]│
processed.json                  └──────────────────────────────┘
┌────────────┐                          │
│ models[]   │  test_axis_dependency_   │
│ {intel,    │  fields_exist checks     │
│  speed_tps,│  every dep field present  │
│  ...}      │←─────────────────────────┘
└────────────┘
```

## Concrete Example

From the [LLM Provider Pricing Analysis](..) repo — full file at `tests/test_drift_detection.py`.

### 1. Parse JS axis definitions with regex

```python
import re

RADAR_AXES_PATH = "viz/_shared.js"

def parse_radar_axes() -> list[dict]:
    with open(RADAR_AXES_PATH, encoding="utf-8") as f:
        content = f.read()

    match = re.search(
        r"window\.RADAR_AXES\s*=\s*\[(.*?)\];",
        content,
        re.DOTALL,
    )
    axes: list[dict] = []
    block = match.group(1)
    for obj_match in re.finditer(
        r"\{\s*key:\s*'([^']+)'\s*,\s*label:\s*'([^']+)'\s*",
        block,
    ):
        axes.append({"key": obj_match.group(1), "label": obj_match.group(2)})
    return axes
```

**Why regex instead of a JS parser:** The axis array is a simple literal — no nested expressions, no computed keys. A regex is fast, zero-dependency, and fails loudly if the format changes (which is exactly what we want).

### 2. Explicit dependency map for computed axes

Not all axis keys are literal data fields. `avgIQ` is computed from `m.intel`, `costEff` from `1 / avg(m.cost_per_task)`. The dependency map makes this explicit:

```python
AXIS_FIELD_DEPENDENCIES: dict[str, list[str]] = {
    "avgIQ":       ["intel"],                 # m.intel average
    "avgSpeed":    ["speed_tps"],             # m.speed_tps average
    "tokenEff":    ["tokens_m"],              # 1 / avg(m.tokens_m)
    "avgCacheEff": ["cache_hit_price", "inp_price"],  # avg(1 - cache_hit/inp)
    "costEff":     ["cost_per_task"],         # 1 / avg(m.cost_per_task)
}
```

Tests:
- **Every axis has a dependency entry** — adding a new axis to JS forces updating this map
- **Every dependency field exists in data** — a renaming in the pipeline is caught immediately
- **Computed axes are reported** (informational) alongside direct-field axes

### 3. Soft warnings for unreferenced data fields

Hard failures for missing dependency fields. Soft warnings (via `warnings.warn`) for data fields that no axis references — candidates for removal:

```python
VIZ_KNOWN_FIELDS: set[str] = {
    # All fields touched by ANY viz script (not just RADAR_AXES)
    ...
}

unreferenced = data_fields - referenced
if unreferenced:
    warnings.warn(
        f"Fields in processed.json NOT referenced by any RADAR_AXIS "
        f"or VIZ_KNOWN_FIELDS ({len(unreferenced)}):\n"
        + "  " + ", ".join(sorted(unreferenced))
    )
```

This means CI stays green for these but surfaces them in logs.

## Real Drift Caught

The first run of this test on 2026-07-07 detected:

```
✗ Axis 'avgCacheEff' (label='CACHE EFF') depends on field 'cache_hit_price'
  which is MISSING from processed.json
```

`cache_hit_price` is referenced by `03-provider-archetypes.js` line 44 but does **not** exist in any of the 81 `processed.json` models. The viz will silently produce zero/incorrect cache efficiency values for the radar chart. The data pipeline needs to either:
- Add `cache_hit_price` to the output
- Or rename `inp_price`/`openrouter_cache_read_price_per_m` if those are the intended fields.

## Variation: Cross-Layer Colour Mapping Test

A companion pattern — test that `CREATOR_COLORS` in JS covers every `creator` value in `processed.json`:

```python
def test_creator_colors_cover_all_creators(processed_models, shared_js):
    """Test missing colour = broken viz. Hard fail."""
    creators_js = parse_creator_colors(shared_js)  # extract from JS
    creators_data = {m["creator"] for m in processed_models if m.get("creator")}
    uncovered = creators_data - set(creators_js.keys())
    assert not uncovered, f"Creators missing colour mapping: {uncovered}"
```

## Variation: FIELD_LABELS Contract Test

A two-directional contract that validates `FIELD_LABELS` (display names for table columns) against actual model fields in the data. Catches:

- **Dead labels** — a label in FIELD_LABELS whose key doesn't exist in the data (the viz will render an empty column)
- **Unlabeled display fields** — a user-facing field in the data that has no FIELD_LABELS entry (the viz can't show it with a human-readable name)
- **Label-to-string type** — every label value is a non-empty string (no accidental numbers or `null`)

### Parsing FIELD_LABELS from JS

```python
def _extract_field_labels(js_text):
    """Extract window.FIELD_LABELS = { key: 'Label', ... } via regex."""
    match = re.search(r"window\.FIELD_LABELS\s*=\s*\{", js_text)
    if not match:
        pytest.fail("Could not find window.FIELD_LABELS in _shared.js")

    # Track brace depth to find the closing }
    start = match.end() - 1  # point at the opening {
    depth = 0
    in_str = False
    sc = None
    end = start
    for i in range(start, len(js_text)):
        ch = js_text[i]
        if in_str:
            if ch == "\\": i += 1; continue
            if ch == sc: in_str = False
            continue
        if ch in ("'", '"', "`"): in_str = True; sc = ch; continue
        if ch == "{": depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0: end = i; break

    body = js_text[start + 1 : end]

    # Extract each identifier: 'single-quoted value' pair
    labels = {}
    pair_re = re.compile(
        r"(?P<key>[a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*'(?P<value>(?:[^'\\]|\\.)*)'\s*,?\s*"
    )
    for m in pair_re.finditer(body):
        labels[m.group("key")] = m.group("value")
    return labels
```

### Test: Hard Fail for Dead Labels

```python
def test_all_field_labels_exist_in_data(field_labels, model_fields):
    """Every FIELD_LABELS key must exist as a field on processed.json models."""
    missing = {k: v for k, v in field_labels.items() if k not in model_fields}
    assert not missing, (
        f"{len(missing)} FIELD_LABELS keys reference fields NOT in data:\n"
        + "\n".join(f"  {k!r}  →  '{v}'" for k, v in missing.items())
        + "\nEither add the field or remove the label."
    )
```

### Soft Warning for Unlabeled Display Fields (Advisory)

Use `warnings.warn` (not `logger.warning`) so pytest surfaces the advisory in its warnings summary:

```python
# Fields that are clearly user-facing table-column candidates
DISPLAY_CANDIDATES = {
    "intel", "cost_per_task", "tokens_m", "speed_tps",
    "inp_price", "out_price", "reasoning_tax_pct",
    "livebench_average", "arena_code_elo",
    "openrouter_inp_price_per_m", "params_b",
    ...
}

def test_unlabeled_display_fields(field_labels, model_fields):
    """Warn about user-facing fields that have no FIELD_LABELS entry."""
    known_labels = set(field_labels.keys())
    unlabeled = (DISPLAY_CANDIDATES & model_fields) - known_labels
    if unlabeled:
        warnings.warn(
            "Model fields that look user-facing but lack FIELD_LABELS:\n"
            + "\n".join(f"  {f!r}" for f in sorted(unlabeled))
            + "\n(Advisory — consider adding labels in viz/_shared.js)"
        )
    # Always passes — advisory only
```

### Test: All Labels Are Strings

```python
def test_field_labels_are_strings(field_labels):
    """Every FIELD_LABELS value must be a non-empty string."""
    bad = {k: v for k, v in field_labels.items()
           if not isinstance(v, str) or not v.strip()}
    assert not bad, (
        f"{len(bad)} entries have non-string or empty values:\n"
        + "\n".join(f"  {k!r}  →  {v!r}" for k, v in bad.items())
    )
```

### Practical tips

- Keep `DISPLAY_CANDIDATES` and `NON_DISPLAY_FIELDS` (internal/metadata fields that never need labels) as class constants so they're easy to audit.
- Add a `test_known_fields_exhaustive` that checks every model field is classified into one of the two sets — flags new unclassified fields for triage.
- The "unlabeled display fields" test is advisory, not a hard gate. A field may intentionally lack a label (e.g. it's shown via another mechanism like COST_SEGMENTS).

## Key Distinctions

| What | How | Why |
|------|-----|-----|
| **Direct-field axis** | Key matches data field literally | Add to dependency map with key as its own dep |
| **Computed axis** | Key is computed from 1+ raw fields | Add to dependency map with its real field deps |
| **Missing dependency** | `pytest.fail()` | Viz will silently produce wrong values |
| **Unreferenced field** | `warnings.warn()` | Candidate for removal, not a blocking bug |
| **Dead FIELD_LABELS key** | `pytest.fail()` | Viz renders an empty column |
| **Unlabeled display field** | `warnings.warn()` | Advisory — viz can't show a human-readable column name |
| **JS parse failure** | `pytest.fail()` | Config format changed — test must be updated |
