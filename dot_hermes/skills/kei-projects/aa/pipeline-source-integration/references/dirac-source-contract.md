# Dirac.run Cache Hit Rate — Source Contract

Source of truth: `https://dirac.run/posts/cache-hit-rates-agents#the-full-table`
(OpenRouter "Effective Pricing" hourly snapshots; the page renders 398 data points).

## What the table actually is
Columns: `Model | Provider | Eff. Input Price | Eff. Output Price | Cache Hit Rate`.
- **Cache Hit Rate** = the OBSERVED % of input tokens served from the prefix cache,
  per model+provider, from OpenRouter's Effective Pricing page. It is a *real-world
  utilization* metric — NOT a theoretical discount.
- Semantically DISTINCT from AA's `cache_hit_price` ($/Mtok read price). The radar's
  `cache_eff` axis is computed from AA's price discount only; Dirac's % is a separate
  namespace and must never feed `cache_eff`.

## Extraction recipe (re-run next time)
1. `web_extract` the URL; the cached `.md` lands in `~/.hermes/cache/web/`.
2. Parse ONLY the `#the-full-table` section (strip summary rows where the Provider
   column holds a count like "10" or "Total Providers").
3. Each row: `Model = "Vendor_Model"` (e.g. `DeepSeek_DeepSeek_V4_Pro`), `Provider`,
   `Eff.Input/Output Price` ($), `Cache Hit Rate` (%).
4. Join key: Dirac uses OpenRouter **model-page names**, not our canonical slugs.
   Resolve `Vendor_Model` → OpenRouter API id (`vendor/model`) → canonical via
   `openrouter_id_to_canonical` in `_canonical.py`. Build/extend `DIRAC_NAME_MAP`
   for the `Vendor_Model` strings that resolve.
5. Persist flat list `data/sources/dirac/cache_hit_rates.json` (one row per
   model+provider observation). Do NOT wrap in `{"models":[...]}` — `_build.py`
   iterates the list directly.

## Resolution reality check
- ~276 real rows after stripping summaries; ~50 fail to resolve (non-canonical /
  future model-page names). Only resolved rows enter the registry.
- Expose `cache_hit_rate_max` (max observed across providers) as the primary axis —
  the achievable ceiling for an agentic workload. Carry per-provider rows in
  `meta.dirac_cache_hit_rates` for UI tooltips.
- 15 models resolve to the registry; ~11 surface in the 104-model AA-centric output.

## Wiring (see SKILL.md checklist)
- `DIRAC_NAME_MAP` + `dirac_name_to_canonical` in `_canonical.py`
- `data/sources/dirac/_build.py` (`get_dirac_models(base)`)
- `SourceKey.DIRAC` in `_domain/_base.py`
- merge block in `_build_registry.py`
- `project_axes.py` whitelist MUST include `"dirac"` (benchmark-route) or it silently drops
- `ProjectionRow.cache_hit_rate_max` (SOURCED) + axis `dirac.cache_hit_rate_max`
- `ALL_AXES` entry + row constructor `safe_cache(a.get("dirac.cache_hit_rate_max"))`
