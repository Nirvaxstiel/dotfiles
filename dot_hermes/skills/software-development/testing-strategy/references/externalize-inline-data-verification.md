# Externalize Inline Data — Verification Workflow

Verification protocol for extracting embedded JS/Python data from static HTML/markup into separate files with guaranteed zero output change.

## The Problem

Static HTML dashboard has ~100KB of model data inlined as `var PROCESSED_DATA = [...]` inside a `<script>` tag. It needs to become `data/processed.js` loaded via `<script src="...">`. The viz scripts depend on every field, every floating point value, every null vs undefined distinction. Any deviation breaks the rendered page.

## The Workflow

### 1. Pin the Committed Version

Before extracting, confirm what the committed data looks like. The git HEAD version is the ground truth — the working tree may already have local edits.

```bash
# Extract committed inline data for comparison
git show HEAD:dashboard.html > /tmp/old_dashboard.html
```

### 2. Extract the Inline Data Blob

Use Python/JSON parsing (never sed/grep) to pull the exact JS assignment:

```python
import json, re

html = open("dashboard.html").read()
m = re.search(r'window\.PROCESSED_DATA = (\[.*?\]);', html, re.DOTALL)
old_data = json.loads(m.group(1))
```

**Critical**: the `re.DOTALL` flag is required — model data spans many lines, and the regex must match through newlines.

### 3. Write the External File

```python
with open("data/processed.js", "w") as f:
    f.write("window.PROCESSED_DATA = ")
    json.dump(old_data, f, indent=2)
    f.write(";\n")
```

### 4. Compare Slug-for-Slug, Field-for-Field

```python
old_map = {m["slug"]: m for m in old_data}    # from git HEAD
js_map  = {m["slug"]: m for m in js_data}     # from data/processed.js

# Slug set check
assert set(old_map.keys()) == set(js_map.keys())

# Field-level comparison
diffs = 0
for slug in old_map:
    o, j = old_map[slug], js_map[slug]
    # Union of all keys — catches both dropped and added fields
    for k in set(list(o.keys()) + list(j.keys())):
        if o.get(k) != j.get(k):
            diffs += 1
assert diffs == 0, f"{diffs} field differences"
```

### 5. Replace the Inline Block in HTML

Replace the entire comment+script+data block with a single `<script src="...">` tag:

- **Before:** `<!-- PROCESSED DATA (inlined) -->\n<script>\nwindow.PROCESSED_DATA = [...]\n</script>`
- **After:** `<script src="./data/processed.js"></script>`

### 6. Verify Script Loading Order

The boot/polling pattern must work:
1. Data script loads first (`processed.js`) — sets `window.PROCESSED_DATA`
2. Shared helpers load (`_shared.js`) — sets `CREATOR_COLORS`, `VIZ_REGISTRY`
3. Viz scripts load — each pushes to `VIZ_REGISTRY`
4. Boot function polls: `if (!window.PROCESSED_DATA || !window.VIZ_REGISTRY) { return setTimeout(boot, 50); }`

The boot function must use **polling** (`setTimeout` retry), not `DOMContentLoaded` or `defer` — data loading may complete after the boot function runs.

## Stale Data Detection

A common pitfall: the committed data is from an **older pipeline run** and the current pipeline produces different output (different model counts, different field values, different naming conventions).

| Check | What to do |
|-------|------------|
| Old slugs ≠ current registry IDs | Registry was rebuilt with different naming (hyphens→dots for versions). The old data is a **frozen snapshot**, not reproducible. |
| Old model count ≠ build output count | The build pipeline's filter is different from what generated the old data. Don't run the build against production data until you understand the gap. |
| Field values differ (same slug) | AA/OR/arena data was re-scraped. Pipeline produces fresher values. |

**Rule:** the extracted `processed.js` is the **live dashboard data** (what users see). The pipeline's `processed.json` is the **latest build output** (may differ). They can coexist with different counts — the dashboard uses `processed.js`.

## Recovery: Git Restore

If a build script run overwrites `processed.json` (or `processed.js`) with incompatible data:

```bash
git checkout -- data/processed.json
python -c "
import json
data = json.load(open('data/processed.json'))
with open('data/processed.js', 'w') as f:
    f.write('window.PROCESSED_DATA = ')
    json.dump(data['models'], f, indent=2)
    f.write(';\n')
"
```

## Verification Checklist

- [ ] slug set identical (no dropped/missing models)
- [ ] field set identical (no dropped/missing fields)
- [ ] every field value identical per slug
- [ ] HTML header count (e.g., "85 MODELS · 24 CREATORS") matches data
- [ ] all `<script src="...">` paths resolve to existing files
- [ ] `processed.js` syntax-valid (`window.PROCESSED_DATA = [...]` starts + ends correctly)
- [ ] boot polling works (data may load after boot function runs)
- [ ] viz files parse as IIFE `(function() { ... })()` (except data/helper scripts)

## Contract Tests Template

See `tests/test_data_contracts.py` in the LLM Pricing Dashboard repo for a full implementation with 8 tests covering fidelity, coverage, syntax, and script integrity.
