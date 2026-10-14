# Context Window Pipeline Integration

*Adding any new external-data field to a multi-stage data pipeline: source → registry → dashboard. No standalone enrichment steps.*

## Architecture

```
_pull_sources.py
  └─ OR API: fetch context_length alongside pricing
  └─ → data/sources/openrouter_models.json (field added to output dict)

_build_registry.py
  └─ _resolve_or_context(): OR context_length → meta.context_window
  └─   3-tier resolution: OR_ID_MAP → direct canonical → suffix stripping
  └─ reads data/sources/misc.json (per-model records, any field)
  └─ → model_registry.json (context_window in meta)

_build_dashboard_data.py
  └─ reads meta.context_window from registry → safe_ctx_window()
  └─ → processed.js (context_window on every ProjectionRow)

viz/_domain.js
  └─ contextWindow getter (int) + hasContext (bool)
```

## 3-Tier Context Resolution

Applied in `_build_registry.py` during OR processing:

1. **OR_ID_MAP** — explicit slug→OR-ID overrides for tricky crosswalks (suffix mismatches like `-it`, `:free`, effort tiers)
2. **Direct canonical** — OR ID stripped of vendor prefix → direct match to our slug
3. **Suffix stripping** — strip `-thinking`, `-high`, `-low`, `:free`, `-it` etc. from our slug, retry match

Fallback after all 3: `data/sources/misc.json` — per-model records with any field. File under `data/sources/`, loaded generically by the registry build stage. Covering non-API models from provider docs/blogs.

## Implementation Pattern

### 1. Source Level (`_pull_sources.py`)

Add field to existing source output dict — no new fetch needed:

```python
out.append({
    "id": pid,
    "name": m.get("name", pid),
    "vendor": pid.split("/")[0] if "/" in pid else "",
    "input_price": pr.get("prompt"),
    "output_price": pr.get("completion"),
    "cache_read_price": pr.get("input_cache_read"),
    "context_length": m.get("context_length"),  # ← NEW
})
```

### 2. Registry Level (`_build_registry.py`)

Crosswalk helpers + resolution function:

```python
OR_SUFFIXES = ["-thinking", "-high", "-low", "-medium", "-xhigh",
               "-preview", "-reasoning", "-non-thinking", "-it", ":free"]

OR_ID_MAP = {
    "claude-opus-4-7": "anthropic/claude-opus-4",
    "gpt-5.5-xhigh": "openai/gpt-5.5",
    "gemma-4-31b": "google/gemma-4-31b-it",
    # our_slug → OR ID for non-trivial crosswalks
}

def _resolve_or_context(all_models, or_models):
    or_ctx = {}
    for m in or_models:
        canonical = openrouter_id_to_canonical(m["id"])
        ctx = m.get("context_length")
        if ctx is not None and isinstance(ctx, (int, float)) and ctx > 0:
            or_ctx[canonical] = int(ctx)

    for our_slug, or_id in OR_ID_MAP.items():
        if our_slug in all_models:
            canonical = openrouter_id_to_canonical(or_id)
            if canonical in or_ctx:
                all_models[our_slug]["meta"]["context_window"] = or_ctx[canonical]

    for cid in all_models:
        if "context_window" not in all_models[cid].get("meta", {}):
            if cid in or_ctx:
                all_models[cid]["meta"]["context_window"] = or_ctx[cid]
                continue
            for suffix in OR_SUFFIXES:
                stripped = cid.removesuffix(suffix)
                if stripped in or_ctx:
                    all_models[cid]["meta"]["context_window"] = or_ctx[stripped]
                    break
```

Then apply after OR processing, before name-map build:

```python
_resolve_or_context(all_models, or_models)

misc_path = os.path.join(SRC, "misc.json")
if os.path.exists(misc_path):
    with open(misc_path) as f:
        misc = json.load(f)
    for cid, record in misc.items():
        if cid not in all_models:
            continue
        meta = all_models[cid].setdefault("meta", {})
        for key, val in record.items():
            if key not in meta or meta[key] is None:
                meta[key] = val
```

**misc.json** (per-model records, flat under `data/sources/`):

```json
{
  "qwen3-6-plus": { "context_window": 1000000 },
  "nova-2.0-pro-reasoning-medium": { "context_window": 1000000 },
  "gemini-3-pro": { "context_window": 65536 }
}
```

Records can grow new fields (`params_b`, `arch`, `release_date`) — no code changes needed.

### 3. Domain Model (`_domain.py`)

Value object + safe constructor — no docstrings:

```python
@dataclass(frozen=True)
class ContextWindow(DomainValue):
    tokens: int

    def __post_init__(self):
        if self.tokens <= 0:
            raise ValueError(f"Context window must be positive: {self.tokens}")

def safe_ctx_window(v) -> Optional[ContextWindow]:
    if v is None:
        return None
    try:
        tokens = int(v)
    except (TypeError, ValueError):
        return None
    return ContextWindow(tokens) if tokens > 0 else None
```

Add field to entity:

```python
@dataclass
class ProjectionRow:
    # ...existing fields...
    context_window: Optional[ContextWindow] = None
```

Add to `to_dict()`:

```python
# In base dict:
"context_window": None,
# In optional_map:
"context_window": self.context_window,
```

### 4. Dashboard Build (`_build_dashboard_data.py`)

Read from registry meta — no separate enrichment file:

```python
meta = reg.get("meta", {})
row = ProjectionRow(
    # ...
    context_window=safe_ctx_window(a.get("meta.context_window")),
)
```

### 5. JS Layer (`viz/_domain.js`)

```javascript
get contextWindow() { return this.context_window; }
get hasContext() { return this.context_window != null; }
```

## Provenance Categories

| Source | Resolution | Transparency |
|--------|-----------|-------------|
| OR API | `context_length` field via crosswalk | Sourced from OpenRouter API |
| Misc | `data/sources/misc.json` — provider docs, blogs | File-based, labeled by directory name |
| Null | Model not on OR, no known spec | Explicit `null` — coverage gap, not error |

## Adding New Models

| Scenario | Action |
|----------|--------|
| On OpenRouter | Auto-fetched via `_pull_sources.py`. Add to `OR_ID_MAP` if crosswalk fails. |
| Not on OR, known spec | Add record to `data/sources/misc.json`. |
| Not on OR, unknown | Leave `null`. Coverage gap is visible in dashboard. |
