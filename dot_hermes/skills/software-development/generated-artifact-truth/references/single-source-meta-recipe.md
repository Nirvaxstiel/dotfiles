# Single-source meta recipe (counts, dates, freshness)

Goal: every count and snapshot date in a repo has exactly one home, and docs/UI read it
from there. Applied to a pipeline that writes `model_registry.json` → `axes_catalog.json` →
`processed.js` (a JS bundle the dashboard loads).

## 1. Declaration point
In the stage that loads the sources (here `_build_registry.py`), declare once:

- source identity: `{source_id: display_name}` (id keys match the counters the stages already produce)
- snapshot dates for sources whose files carry no date: `{source_id: "YYYY-MM-DD"}`
- optional semantic notes per source (e.g. "observed hit rates, not AA's cache price")

Derive the rest:

- `arena_*.json` → `meta.fetched_at[:10]`
- `livebench_YYYY_MM_DD.csv` → date from the filename via `re.search(r"livebench_(\d{4})_(\d{2})_(\d{2})", " ".join(os.listdir(src)))`
- script-pulled sources (no date, refreshed on pull) → leave `None` and render it as `on pull`

Build the artifact entry as `{models: <count>, as_of: <date|null>, note?: <str>}` keyed by
display name, and put it in the build stage's `meta` as `source_meta`.

## 2. Flow to the UI
- Next stage copies the map instead of re-declaring it: bundle `meta.sources` = registry `sources`,
bundle `meta.sources_meta` = registry `source_meta`.
- Add a coverage block while you are there: `meta.counts = {models: <all rows>, aa_models: <rows with any data from the primary source>, creators: <distinct creators among those>}`.
  The "covered" subset is the one a headline should quote; the total describes the dataset.
- Boot renders both: header text from `meta.counts`, a footer line from `meta.sources_meta`
  (`AA 133 · 2026-09-10 · Dirac.run 61 · 2026-07-23 · …`, `null` date → `on pull`).
- Keep the old top-level `sources` / `sources_meta` wrapper keys if a test asserts them —
  fill them from the same meta so there is still one source of truth.

## 3. Verification commands
```bash
# rebuild offline, then confirm only meta moved
git diff -U0 data/processed.js | grep '^@@'          # hunks must be inside the meta block
# read the generated truth
python -c "import json; s=open('data/processed.js').read(); p=json.loads(s[s.index('{'):s.rindex('}')+1]); print(p['meta']['counts'], p['meta']['sources_meta'])"
# audit docs against it
grep -rn "<old number>" README.md *.md viz/README.md
```

## 4. Doc audit checklist
For each doc, either point at the generated home or state a number that a test asserts:

- landing README: headline count, layout block (`processed.js ← N models`, `registry ← N models, M sources`)
- pipeline stage table: rows-per-stage counts
- acquisition doc: per-file sizes (`aa_api_live.json (N models)`, dirac `(N rows)`, overlay `(N models)`) — these are `len(json.load(file))` and drift fastest
- viz/README (the worker contract): field table must match the serializer's real output (a field the serializer stopped emitting, a type changed from `bool` to price, an enum's values renamed)
- methodology/archetype thresholds: compare against the classifier function's predicates, not against an older scheme

## 5. Worked example (LLM Provider Pricing Analysis repo)
- Homes: `data/_build_registry.py` (`SOURCE_NAMES`, `UNDATED_SNAPSHOTS`, `SOURCE_NOTES`) →
  `model_registry.json` meta `source_meta` → `processed.js` meta `counts` / `sources_meta` →
  `dashboard.html` `#header-meta` + `#source-freshness`, rendered by `viz/_boot.js` steps
  `header_meta` and `source_freshness`.
- Offline build that actually works: `PYTHONPATH=data python -c "import data._pipeline as p; p.build_from_cache()"`.
- Doc numbers live in `README.md`, `LLM Provider Pricing Analysis.md`, `viz/README.md`, `DATA-ACQUISITION.md` — all four were stale in different ways at once.
- Source-set changes that invalidate doc counts: dropping the `_select_aa_models` projection filter expanded the bundle from ~120 to all registry rows; every "N models" in the docs was then wrong.
