# Field Propagation Chain — Worked Example (`cache_hit_price`)

Source repo: LLM Provider Pricing Analysis dashboard (multi-stage Python pipeline → vanilla-JS viz).

## Symptom
CACHE EFF radar axis showed 0% for **every** creator, even though AA provides `cache_hit_price` per model. The axis was dead.

## Pipeline layers (where the value must live)
```
source (aa_cost_breakdown / OR API)
  -> model_registry.json        (pricing.aa.cache_hit_price)   present (59 models)
  -> axes_catalog.json          (axes[].id == "aa.cache_hit_price")  MISSING
  -> project_axes.py get_value  (resolves "aa.cache_hit_price")     works IF catalog has it
  -> _build_dashboard_data.py
       ALL_AXES list            (must include "aa.cache_hit_price")  MISSING
       projection a.get(...)    (safe_ppm(a.get("aa.cache_hit_price")))  added
  -> ProjectionRow (_domain.py)  (cache_hit_price field)             MISSING
  -> ProjectionRow.to_dict()     (optional_map entry)               MISSING
  -> processed.js                (cache_hit_price per model)        was 0 hits
  -> viz/_domain.js getter       (ModelRow.cache_hit_price)         downstream of above
```

## Root cause (4-layer drop)
1. `ProjectionRow` dataclass had no `cache_hit_price` field.
2. `ALL_AXES` referenced a dead `aa.cache` axis (not `aa.cache_hit_price`).
3. `_build_axes.py` emitted `aa.cache` (placeholder, 0 models) -> `axes_catalog.json` never had `aa.cache_hit_price`.
4. `to_dict()` `optional_map` omitted `cache_hit_price`, so even if carried it was never serialized.

## Fix (patched in order)
1. `_domain.py`: added `cache_hit_price: Optional[PricePerMToken] = None` to `ProjectionRow` + `"cache_hit_price": self.cache_hit_price` to `to_dict()` optional_map.
2. `_build_dashboard_data.py`: replaced `"aa.cache"` with `"aa.cache_hit_price"` in `ALL_AXES`; added `cache_hit_price=safe_ppm(a.get("aa.cache_hit_price"))` to the constructor call.
3. `_build_axes.py`: changed the pricing-axis tuple from `("aa.cache", ..., ["cache"])` to `("aa.cache_hit_price", ..., ["cache_hit_price"])`.
4. Clean rebuild: `rm -f axes_catalog.json model_registry.json processed.js && python -m data._pipeline build`.
5. Verified: `grep -c cache_hit_price data/processed.js` -> 59 models.

## Key lessons
- `axes_catalog.json` is GENERATED, not edited. Hand-edits vanish on rebuild. Always patch `_build_axes.py`.
- `to_dict()` is the serialization gate. A field can exist on the dataclass and still never reach JSON if absent from `optional_map`.
- One field = up to 7 touch points. Add a checklist; grep the final output to confirm (0 hits = gap in the chain, not a viz bug).

## Companion bug (same session): `cost_per_task` inflated 1000x-4000x
- `enriched.cost` ($29.87, $72.42) was corrupt — reconstructing from `tokens_m` x blended gives ~$2; needs ~15x token inflation.
- Step 2 set `cost_per_task = enriched.cost`; step 3 only overrode `if cost_per_task is None` -> authoritative breakdown `total` ($0.02) blocked.
- Fix: step 3 now uses `if m.get("total_cost_per_task_usd") is not None: aa["cost_per_task"] = total` (later authoritative source wins, inverted guard).
- Discipline: when two sources disagree, `if target is None` makes first-loader-win. Invert the guard when a later, better source should win.
