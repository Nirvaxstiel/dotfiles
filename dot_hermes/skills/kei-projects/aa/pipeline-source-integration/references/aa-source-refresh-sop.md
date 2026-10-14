# AA Source Refresh SOP (scrape + API + table pulls)

Operational playbook for refreshing the Artificial Analysis sources in this repo.
Captured from repeated refresh cycles (Jul–31 Jul 2026) where the same failure
modes recurred.

## 1. AA SVG chart scrape — `aa_charts_export.json`

**Selector (changed when AA redesigned its site):** the old `el.querySelector('svg')`
captured PAGE ICONS (lucide), not chart surfaces. AA now requires the role
attribute. Use exactly:

```js
// In the AA page console — capture each chart section as { svg, spans }.
JSON.stringify(Array.from(document.querySelectorAll('[dir=ltr].scroll-mt-24'))
  .map(el => ({ svg: el.querySelector('svg[role]')?.outerHTML || '',
                spans: Array.from(el.querySelectorAll('span')).map(s => s.textContent) })))
```

Save the array as `data/sources/aa/aa_charts_export.json`.

**VALIDATION (run before ingesting — do NOT skip):**
```bash
python -c "import json; d=json.load(open('data/sources/aa/aa_charts_export.json')); \
print('entries',len(d)); \
print('recharts',sum('recharts-surface' in e.get('svg','') for e in d)); \
print('empty_svg',sum(1 for e in d if not e.get('svg')))"
```
Acceptance: `recharts >= entries` (every chart has a real recharts surface) AND
`empty_svg == 0`. The parser (`_parse_charts.py`) matches charts by `spans[0]` title
and SKIPS charts that parse to 0 rows.

**Recurring failure modes (seen 3x across 13jul/23jul/31jul — all REJECTED):**
- **All-lucide scrape:** `recharts=0`, `lucide~48` across all 16 entries → the
  selector grabbed page icons, not charts. The `svg[role]` fix above is the cure.
  If a delivered file still shows this, the fix did NOT take — re-scrape.
- **PARTIAL scrape (31jul):** only 2/16 entries had real SVG; the other 14 had
  `svg=""` (empty). The scrape got titles for all 16 but SVG content for 2.
  Ingesting this DROPS Briefcase/Omniscience/Pricing/Time-per-task charts →
  regression. Reject; keep the last valid file. A valid scrape has all 16 with
  full recharts SVGs (~250KB each).

## 2. AA live API — `aa_api_live.json`

**Endpoint:** `GET https://artificialanalysis.ai/api/v2/data/llms/models` with header
`x-api-key: $AA_API_KEY` (from `~/.hermes/.env`). The `/v1/models` and `/v2/language/
models/free` paths are wrong/stale — use the `/api/v2/data/llms/models` path.

Re-pull is CHEAP and high-value: it's AA's authoritative, always-current pricing +
release_date + 16 eval scores. It picks up AA price CHANGES (e.g. gpt-5-6-luna
1/6 -> 0.2/1.2, gpt-5-6-terra 2.5/15 -> 2/12 on 31jul) — but ONLY if `_overlay_aa_api`
OVERRIDES pricing (nulls-only would keep stale prices; see Pitfalls in SKILL.md).

Pretty-print when saving (`json.dump(..., indent=2)`) so diffs are reviewable.

## 3. AA JSON-LD — `aa_jsonld_export.json`

Export from the AA page console (schema.org Dataset JSON-LD). It arrives
backtick-wrapped: `` `[...]` ``. Strip the backticks before `json.loads`. 10
datasets + a trailing FAQPage (skip non-`Dataset` entries).

**AA has been REMOVING datasets:** as of 31jul2026 the "Artificial Analysis Coding
Index" dataset is GONE from both the chart and the JSON-LD. When a dataset
disappears, the metric it sourced (`aa_coding_index`) becomes UNSOURCEABLE -> per the
user rule, delete it (don't leave an always-None column). Update the contract test
to assert absence, not presence.

## 4. Dirac.run — `dirac/cache_hit_rates.json`

**Now scriptable (no manual transcription).** Fetch the page and parse the HTML
`<table>` after the `#the-full-table` anchor:
```python
import urllib.request, re, json
html = urllib.request.urlopen(req).read().decode()
# find the <table> after id="the-full-table", parse <tr><td> rows
# -> [{model, provider, eff_input_price, eff_output_price, cache_hit_rate}, ...]
# 398 rows as of 31jul2026 (was 276 in the old manual transcription)
```
Shape: flat list (not wrapped). Parser (`_build.py`) consumes it directly.

## 5. Refresh sequence
1. Re-pull live API (endpoint above) -> `aa_api_live.json`.
2. Copy new JSON-LD (strip backticks) -> `aa_jsonld_export.json`.
3. Re-scrape SVG charts; VALIDATE recharts/empty_svg before swapping
   `aa_charts_export.json`. If invalid, KEEP the last good file.
4. Re-parse Dirac table -> `dirac/cache_hit_rates.json`.
5. `PYTHONPATH=data python -c "import data._pipeline as p; p.build_from_cache()"`
6. `PYTHONPATH=data uvx --with jsonschema pytest tests/` -> all green.
7. Determinism: `tests/test_pipeline_determinism.py` (compare two fresh runs).
