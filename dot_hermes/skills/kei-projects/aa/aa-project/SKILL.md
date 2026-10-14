---
name: aa-project
category: kei-projects
description: Umbrella for the "LLM Provider Pricing Analysis" repo project skills (Artificial Analysis data pipeline). Load this when working in that repo — it points to the sub-skills covering pipeline source integration, live API null-fill, data acquisition, and the viz frontend.
---

# AA Project — LLM Provider Pricing Analysis

Domain landing for the Artificial Analysis pricing-pipeline project (repo: `.../LLM Provider Pricing Analysis/`, an Obsidian vault subfolder). Zero-build JS, no TS. Pipeline: raw source files → `model_registry.json` → `axes_catalog.json` → `processed.js` (consumed by `viz/*.js`).

This domain holds three coordinated skills (physically under `kei-projects/aa/`). Load the one matching the task:

| Skill | When to load |
|---|---|
| `pipeline-source-integration` | Adding ANY new data source (scrape/API/vision) to the registry→axes→dashboard pipeline. The contract-first recipe + 9-point wiring checklist + silent-drop pitfalls. Start here for new work. |
| `aa-api-live-fill` | Filling nulls from the AA live API at source-fetch stage (auth, slug map, nulls-only merge). |
| `aa-data-acquisition` | **How each source is ACQUIRED** — method (scrape/API/vision/manual table), auth, which script fetches it, repro checklist. Load when refreshing sources or debugging "where did X come from". |
| `aa-viz-frontend` | Dashboard render layer: VIZ_REGISTRY/id contract (slugs not numbers), positional tab numbering, `#tooltip` system, crossover creator/reasoning color modes. |

## Shared conventions (all skills)
- Run build scripts as `python -m data.<script>` from repo root (relative imports).
- Import idiom in tests: `_build_registry` uses RELATIVE imports → `import data._build_registry as br`; `_pull_sources` / `project_axes` / `_build_dashboard_data` use BARE imports (`from _result import ok, err`) → `import _pull_sources` with `data/` on `sys.path`, and run scripts with `PYTHONPATH=data`.
- `ProjectionEngine.project()` and `feasibility_report()` return `Result` (not a bare list / not `ValueError`). `project_axes.py`'s `__main__` wraps them in a `rows()` helper that raises `SystemExit` at the CLI boundary.
- Line endings: the patch tool inserts LF into CRLF files. After editing any tracked file, normalize (`b.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')` when `count('\r\n') != count('\n')`) or `git diff` shows whole-file churn.
- New fields thread through: value type + `safe_*` → `ProjectionRow` field + `FIELD_PROVENANCE` → `ALL_AXES` + row constructor → axis builder (`_build_axes.py`) → `project_axes.py` benchmark whitelist.
- Multi-source honesty: nulls are gaps, never override; AA owns `intel`/`cost_per_task`/`context_window`/`speed_tps`/`ttft`/`tokens_m` — don't duplicate.
- `processed.js` is a wrapper `{sources, sources_meta, models}`; UI unwraps `.models`. The test suite's loaders must unwrap too.

## Build orchestration & refactor mandate (enforced by user, twice)
The repo has ONE orchestrator idiom — `Pipeline(ctx).then(name, fn).then(...).run()` from `data/_pipeline.py`, ported to JS as `window.Result.Pipeline` in `viz/_result.js`. Reuse it everywhere.
- **NEVER hand-roll a `steps` tuple + manual `for` loop** to run pipeline stages. The user explicitly rejected this as "ugly"/"inconsistent" vs the existing `Pipeline`. It is the default trap when refactoring a lockstep `run()`/`build()`.
- Python inner stages (`_build_registry.run()`, `_build_axes.run()`, `_build_dashboard_data.build()`) and JS boot (`viz/_boot.js`) ALL compose steps via `.then().run()`.
- **Monster→monad rule:** if a function does several unrelated things and uses comment-section banners (`# ── X ──`, `// --- Y ---`, `# Section`) to carve out the space, that banner is the signal to EXTRACT each concern into a named helper and wire it as a `.then()` step. Drop the banner. (Example: `_build_registry.run()`'s inline `# ── Summary ──` block → extracted to `_print_summary()` as a terminal `.then("print_summary", ...)` step in commit `bee9643`.)
- `Pipeline.run()` returns `ctx` (not a wrapped Result). Each step stores its return under `ctx[step_name]`; terminal steps that return `ok({...})` get UNWRAPPED by `run()`, so callers must do `return ok(pipeline.ctx["step_name"])` to re-wrap. After `.run()`, check `if pipeline.ctx.get("_failed_step"): return err(pipeline.ctx["_error"])` before reading outputs.
- Render/event viz code (`render()` internals) is intentionally NOT monadified — only orchestration/boot flow uses the Pipeline. Don't contrive dropdown widgets etc. into steps.

## Build invocation — offline vs pull (CRITICAL pitfall)
`data/_pipeline.py` CLI gate only matches the literal `"build"`:
- `python -m data._pipeline build` or `build_from_cache` → **OFFLINE**, no network. Reads committed `data/sources/*`, writes `model_registry.json` / `axes_catalog.json` / `processed.js`.
- `python -m data._pipeline` (no arg) or **ANY other arg** (e.g. `build_from_cache` misspelled) → falls through to `build()` → **full network PULL** (LiveBench/OpenLLM/OpenRouter) + rebuild.
- **Trap:** `python -m data._pipeline build_from_cache` does NOT match `"build"` → it runs the full pull, silently rewriting `data/sources/openrouter_models.json` + all derived artifacts. Always use the bare `build` subcommand for offline. Fixed in commit `5567093`.
- Verify offline reproducibility: `git checkout -- data/sources/ data/model_registry.json data/axes_catalog.json data/processed.js`, then run offline build, then `git diff --stat` + `git hash-object` each artifact vs HEAD — must be byte-identical. The determinism test (`tests/test_pipeline_determinism.py`) calls `build_from_cache(ctx)` as a FUNCTION (correct, no pull).

## Release manifest + deploy gate (added 2026-09-25)
`_build_dashboard_data.build()` writes `data/manifest.json` beside the artifact it records: `build_id` (`{generated}@{sha256[:12]}`), `generated`, `artifact`, `artifact_sha256`, `model_count`, `sources` (name → `as_of`).
- `data/_verify_manifest.py` recomputes those three fields from the committed artifact and returns Err on drift; both deploy workflows run `PYTHONPATH=data python3 data/_verify_manifest.py` before publishing. Run it standalone after any artifact write.
- **Never put `git_sha` in the manifest.** It is unknowable at build time, so every commit + rebuild dirties the file. Identity is the artifact hash; the commit is in git history. Removing it made the manifest stable across commits (verified: identical sha256 before and after a commit + rebuild).
- Keep the manifest OUT of the `test_pipeline_determinism.py` byte-compare set (`model_registry.json`, `axes_catalog.json`, `processed.js`) — a timestamped file in that set can never pass.
- Manifest drift is a real failure mode: a stale `processed.js` shipping against a fresh manifest is exactly the mixed-age-data bug. The gate exists to make that impossible to deploy.

## Failed-refresh signal (added 2026-09-25)
`_pull_sources.run()` writes `data/sources/_pull_status.json` (`checked_at`, `ok`, `failed` with error text) **before** the all-failed check, so a total failure is still recorded. A failed refresh leaves the previous source file in place and the build still succeeds.
- `_build_registry._source_meta()` reads it via `PULL_KEYS` (pull key → registry display name: `aa`→`aa_public_catalog`, `livebench`→`livebench`, `openllm_aa_subset`→`openllm`, `openrouter`→`openrouter`, `dirac`→`dirac`; `arena_code`/`arena_text` have no pull key) and adds `refresh_failed` + `refresh_error` to the affected source only.
- Surfaces: `viz/_boot.js` footer (`// REFRESH FAILED`) and `viz/_shared.js axisProvenance()` (`REFRESH FAILED` in each affected chart's provenance note).
- The status file is **committed source state**, not a build artifact — the offline build reads it, so the warning persists until a refresh succeeds.
- Do not interpolate `refresh_error` (an external exception string) into HTML. The marker text is a constant; the reason stays in the data.

## Reviewer / external-feedback verification discipline
When acting on third-party review feedback (no full repo visibility), verify each claim against actual code before changing anything:
- Reviewer XSS/bug claims are often misreads — grep for the exact cited line; if it doesn't exist, don't "fix" it.
- Smoke-test generated code against REAL data, not just the happy path: load `processed.js` under Node with a DOM stub, run the new logic, assert (a) real data → ok/no-false-failure, (b) drifted/mistyped input → caught. This caught a false-positive in the schema validator (86/117 models have null `intel` — a `typeof !== 'number'` check would've blocked boot; fix: only type-check present, non-null values).
- Convergence between two independent reviewers on the same suggestion (e.g. post-load schema validation) is a strong signal to act.
- Verifying a viz change without a JS test runner: copy `dashboard.html` + `viz/` + `data/` to a scratch dir, doctor `processed.js`, serve it with `python -m http.server`, then `tool_call` → `desktop_preview action="read"` to read the rendered text. For `_shared.js` helpers, load the file in Node with `new Function('window', src)(win)` plus a `document` stub, then call `win.VIZ_HELPERS.*`. `AXIS_SOURCES` is internal — probe with real axis keys (`livebench_coding`, `openrouter_inp_price_per_m`), not catalog ids (which use dots).
- `viz/_boot.js` and `_shared.js` are load-time IIFEs, so they cannot be unit-tested through the repo's Node harness (`new Function('window', src)`) without refactoring. `desktop_preview` read is the honest verification for boot/footer behaviour.

## References (session-hardened detail)
- `references/aa-build-verify.md` — exact offline/pull CLI matrix, the `build_from_cache` arg trap, the `PYTHONPATH=data` run gotcha (bare `from _result import`), the fuzzy-patch duplicate-block corruption pitfall, and the byte-identical determinism-check recipe. Load when rebuilding, refreshing sources, or investigating "values changed" complaints.

## References (session-hardened detail)
- `references/aa-data-viz-pitfalls.md` — real bugs + how to investigate this pipeline's data/viz layer: `cost`≠per-task (`cost_per_task` priority chain: API→breakdown→image→null), `reasoning_tax_pct` derivation, `#tooltip` (not `getTooltipEl`), `VIZ_DEFAULTS` + positional tab numbering. Load when tracing a "weird viz" or bad-cost symptom.
- `references/aa-api-properties.md` — condensed AA Data API v2 property map (what each field means, tiers, the `cost_per_task.total_cost` authoritative per-task source). Load when mapping API fields or debugging data semantics.

## Skill relationship
`pipeline-source-integration` is the general contract; `aa-api-live-fill` is the concrete source implementation of it (live-API null-fill). When you add a source, follow `pipeline-source-integration` and consult the specific skill for source-type quirks.
