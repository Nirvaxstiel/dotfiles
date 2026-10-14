---
name: generated-artifact-truth
category: software-development
description: Use when docs quote numbers from generated artifacts.
---

# Generated-artifact truth

Trigger: a repo generates data artifacts (`*.json`, a JS data bundle, a catalog file) that READMEs, vault notes, dashboards, or external reviewers quote numbers from — record counts, model counts, snapshot dates, dataset versions, source lists.

## Rule 1 — one declaration point, everything else derives
- Declare the fact in the stage that already knows it (the build step that loads/counts the sources): source identity map, snapshot dates for sources whose files carry no date, source notes.
- Derive what is derivable instead of declaring it twice — read dates out of the source files themselves (`meta.fetched_at`, dated filenames) and fall back to a declared map only for the undated ones.
- Flow downstream through generated meta (build-stage meta → bundle meta → UI), never by re-typing it in the next stage.
- Headline counts in the UI must come from generated meta, not from `data.length` over a mixed population: a bundle holding both covered and uncovered records will print a number that describes neither.

## Rule 2 — docs never restate a generated number
- If an artifact carries it, the doc points at the artifact. Two numbers for one fact is a latent bug that surfaces later as a reviewer finding.
- Whenever the dataset's population changes (dropping a projection filter, adding/removing a source), grep every doc for the OLD number. Each hand-typed count is now wrong, and they usually disagree with each other too.
- Cheapest guard: a test that parses the doc's claim (regex) and asserts it equals the generated meta, failing with the correct number. Prefer that over trusting future discipline.

## Rule 3 — prove a meta-only change stayed meta-only
`git diff -U0 <bundle> | grep '^@@'` — every hunk must sit inside the meta block. A hunk in the data rows means the change was not cosmetic.

## Rule 4 — delete dead weight instead of documenting it
- A field that no builder populates AND no serializer emits is dead: delete field + provenance entry + serializer entry + wiring + now-unused imports. Deleting it is artifact-neutral — prove it by rebuilding and diffing.
- Dead fixtures are worse than dead code: a test fixture nothing consumes keeps the OLD artifact shape, so the break it would have caught stays invisible. Grep for consumers before trusting any fixture; delete the ones with none.
- Orphaned assertions (a block dedented into an unrelated test method) are dead too — give them a named test or delete them.

## Rule 5 — third-party review / roast triage
- Verify every claim against the artifact before acting. Count/date claims are checkable in one pass: load the bundle meta, count the real values, grep the docs for the quoted numbers.
- Separate taste (monads, chart choice, no-framework) from defect (numbers that disagree). Say which is which in the reply; do not refactor taste.
- When a claim is TRUE, fix the root (single-source the number in generated meta) instead of editing the prose number.
- Claims of the form "X is stale / undecided / internally inconsistent" are the highest-yield ones — they usually mean the docs were never updated after a pipeline change, and the fix is mechanical.

## Pitfall — `python -m pkg.mod` fails on bare imports inside the package
When modules inside a package do a bare `from _result import ok` (not `from pkg._result`), `python -m pkg.mod` raises `ModuleNotFoundError` — `-m` puts the repo root, not the package dir, on `sys.path`. Fix: prefix `PYTHONPATH=pkg` (`PYTHONPATH=data python -m data._pipeline build`) or run `python -c "import data._pipeline as p; p.build_from_cache()"` from the repo root. Read the repo's own build reference BEFORE the first build of a session: the naive `-m` command is the one you reach for, and it fails.

## Pitfall — the refresh checklist belongs in the same commit
When a manually acquired source snapshot lands, bump the declared snapshot map / freshness metadata in the SAME commit, and make sure the acquisition doc's repro checklist names that step. Otherwise the dashboard keeps reporting the previous snapshot date while the data is new.

## References
- `references/single-source-meta-recipe.md` — the concrete recipe (declaration point, derived-vs-declared dates, meta flow to the UI, verification commands, doc-audit greps) plus the worked example from the LLM pricing dashboard repo.
