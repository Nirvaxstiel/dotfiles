# Pipeline Audit Checklist (reusable)

Condensed, session-agnostic steps for auditing a multi-source data pipeline that
produces a domain model the UI consumes (e.g. `processed.js`). Run in order; each
step either confirms health or produces a finding. Built from a real LLM-pricing
multi-source audit (AA + OpenRouter + LiveBench + Arena + OpenLLM + vision-
transcribed chart images).

## 0. Map the repo (don't trust `git ls-files`)
```bash
git ls-files                                   # committed
find . -type f -not -path './.git/*' | sort    # incl gitignored (vault data, images/)
git status --ignored --short                   # what's deliberately uncommitted
```
`images/` / large binary sources are often gitignored but required by the build
(transcription inputs). Note them; they're vault data, not missing files. A
pipeline sitting in an Obsidian vault commonly gitignores its heavy inputs.

## 1. Run the tests + build
```bash
python -m pytest -q
python -m data._pipeline build      # or build_from_cache
```
Tests green ≠ data correct. Proceed to coverage.

## 2. Coverage matrix (parse the artifact, count non-null)
```python
import json
raw = open("data/processed.js").read()
txt = raw.removeprefix("window.PROCESSED_DATA = ").removesuffix(";\n")
d = json.loads(txt)
models = d["models"]
allkeys = set()
for m in models: allkeys.update(m.keys())
for k in sorted(allkeys):
    n = sum(1 for m in models if m.get(k) is not None and m.get(k) != [])
    print(f"  {k:32s} {n:3d}/{len(models)}")
```
Columns at 0/N = dead axis (name drift) or genuinely-unavailable — distinguish next.

## 3. Doc-vs-reality disproval
```bash
# Phantom source claimed in docs but absent in code?
grep -rE 'dirac|CACHE_HIT_RATES|cache_hit_rate' data/        # 0 hits => never built
# Axis id vs registry field name drift?
grep -rE 'iq_per_dollar' data/                               # find the REAL field name
# Dead/unused rich domain classes?
grep -rl 'class RegistryModel' data/                         # then grep usages of 'RegistryModel('
# Orphaned committed files the code never reads?
grep -rl 'aa_api_live' data/                                 # 0 hits => orphan snapshot
```
For each doc claim, `grep` the code. 0 hits = the claim is false (phantom source,
dead axis, or orphan file). Real external APIs still need verification (step 5).

## 4. Serialized-artifact integrity
Confirm the artifact contains every block the doc describes:
```python
assert "models" in d
assert d.get("meta") or d.get("sources_meta"), "meta block dropped at serialize time"
```
If the build constructs `payload["meta"]` but serializes `wrapper`, the meta is gone.

## 5. Verify external API reality (don't trust endpoint strings)
- AA: `GET https://artificialanalysis.ai/api/v2/data/llms/models`, header `x-api-key`.
  Response: `data[]` with `evaluations.artificial_analysis_intelligence_index`,
  `pricing.price_1m_input_tokens`, `median_output_tokens_per_second`.
- OpenRouter: `GET https://openrouter.ai/api/v1/models`. `data[]` with
  `pricing.prompt|completion|input_cache_read`, NOT a cache *hit rate*.
- Dirac.run: real product, displays live cache-hit rates **in its UI only** — no API.
  "Observed cache hit rate" cannot be pipeline-ingested without manual JSON.
- LiveBench: raw CSV from their GitHub `livebench.github.io` public repo (real,
  refreshable). Arena text/code are often committed static JSON the pipeline never
  refreshes — a doc claim of "re-run to refresh" may over-reach if the puller
  skips them.

## 6. Speculative-data bleed check
If a source is flagged speculative (e.g. `AA_IMG` from vision-transcribed chart
images), confirm its scalars don't leak into non-speculative fields. Grep the merge
code: a `fill-null` from speculative `cost_per_task` into the authoritative
`cost_per_task` is a bleed — gate it out, or verify the non-null rows all come from
the real breakdown, never the transcription. Keep the speculative flag on the
*source group*, not just on individual axes.

## 7. Emit findings
Order: What Works (by-design, keep) → Critical → Correctness → Maintainability/Dead
code → Docs → Refactoring table (Effort×Impact) → Deferred (conscious
non-decisions). Frame each design choice the user enforced as "(By design)" — not a
gap. Multi-source nulls are signals, not bugs.
