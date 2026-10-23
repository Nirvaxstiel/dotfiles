---
name: monadic-refactor
description: >-
  Refactor a Python/JS/nushell pipeline to a Result (Either) monad with
  explicit short-circuit guards. Covers the foundation, per-stage Result
  contract, the "low-hanging-first, one-commit-per-file" cadence, and
  black-box Ok/Err testing. For nushell, covers the pure-spec ↔ effect-layer
  split and the custom-def pipeline/closure traps. LOAD when the user asks to
  "make it monadic", "Result-oriented", "FP/monadic style", or refactor stages
  to short-circuit on Err.
---

# Monadic Pipeline Refactor

## When to use
User wants error-as-value (not exceptions), stages that short-circuit on the
first failure, composed with explicit one-call-one-function guards (NOT a
`pipe()` fusion). Applies to data pipelines, build orchestrators, and pure
resolvers — NOT event-driven render/click code (forcing a monadic style
there is contrived; skip it).

Success bar (user-stated): the pipeline must be VISIBLE at the top of
`run()`/`build()`, with steps at module level. A `run()` that wraps a
250-line body in `pipe()` but hides the `step_*` closures inside itself is
NOT a win — it's still a monster. See "Step-piping DOESN'T COUNT".

**Section-banner smell (load `commenting-culture-cleanup` too):** if the
function body needs `# ── DOMAIN ──` / `# === STAGE N ===` / `# ── helpers ──`
comments to stay legible, that IS the extract signal. The user flagged this
twice: "if you need to add comments to each section of a code of a massive
function, That already is a telltale sign that you need to break it up." The
`ba = lambda *a, **kw: axes.append(_build_axis(...))` accumulator-lambda
pattern inside a long `run()` is the same smell — replace it with per-domain
named builders that RETURN their slice; `run()` concatenates them. After
extracting, the comments are GONE (function names replace them), not moved.

## Foundation (build once)
A shared `Result` = `Ok(value)` | `Err(reason)`. Methods: `is_ok()`,
`is_err()`, `unwrap()`, `unwrap_or(default)`, `bind(fn)` (short-circuits on
Err — used for SINGLE-step threading, e.g. `ok(x).bind(f).bind(g)`),
`match(ok_fn, err_fn)`. `from_fn(fn)` wraps a side-effecting call so a raised
exception becomes `Err` (not a crash).

Composition idiom (USER DECISION — do NOT use `pipe`/`do`): chain stages with
EXPLICIT one-call-one-function short-circuit guards, matching
`data/_pipeline.py` / `tests/test_pipeline.py`. Either:
  (a) a `for step in (step_a, step_b, ...)` loop with
      `r = step(s); if r.is_err(): return err(r.error); s = r.unwrap()`; or
  (b) `.then(name, fn)` steps on the `Pipeline` object (used at the top level
      to orchestrate `run()` stages).
`pipe(value, *steps)` and `do(*steps)` were ADDED then REMOVED — they are NOT
part of this codebase's Result API. Keep only `ok`, `err`, `bind`, `map`,
`unwrap`, `unwrap_or`, `match`, `from_fn`.

Python: `data/_result.py`. JS: `viz/_result.js` (mirror, zero deps).
Keep the classes/functions importable with NO side effects on import — the
test suite imports them directly; a print/network call at import time breaks
collection.

## Per-stage contract
- A *stage* (`run(ctx)` / `build(ctx)`) returns `Result`. On a
  required load failing, `return err(reason)` — do NOT raise (the
  pipeline's `from_fn`/`step` wrapper already turns a raise into Err, but
  returning Err directly is cleaner and makes the failure a value).
- Pure helpers that can't fail (regex parsers returning `[]` on
  no-match, dict lookups) stay untouched — wrapping them adds nothing.
- I/O boundary (file read, network) gets a `_load_json` / `_load_csv`
  helper returning `Ok(dict)` / `Err(reason)`. A missing/ malformed
  file is `Err`, not `FileNotFoundError`.
- Multi-source pull: each source returns its own `Result`; the
  orchestrator records per-source `failed` and returns `Err` only when
  EVERY source failed (lenient per-source, so one dead source doesn't
  abort the others).

## Cadence (user directive)
- Low-hanging fruit first: foundation, then orchestrators, then pure
  resolvers, then source builders, then JS data layer.
- ONE commit per code file changed. Add/adjust black-box tests in the
  same commit.
- **Doc/code parity is part of the refactor, not a separate chore.** When the
  change touches architecture, CLI surface, build outputs, or the public data
  schema, rewrite the affected markdown (README, viz/README, data-acquisition,
  notes) to the EXACT current state — describe what the code does TODAY, never
  the old behavior. The user explicitly demanded this after a refactor left
  stale docs (wrong tab list, invented `NN-` file names, counts from a live
  pull instead of the committed/offline-reproducible figures). Verify any cited
  counts by actually building from committed sources and reading the artifact
  (e.g. `model_registry.json` `meta.model_count`), NOT by repeating a number
  from memory or from a drifted working tree.

## Verify with Hermes LSP + behavior diff (do this every refactor)
A refactor is only "done" when the LSP is clean AND the generated artifact is
byte-identical to before. Two cheap, high-signal checks:

- **LSP diagnostics (pyright / typescript-language-server).** Hermes ships
  both as LSP *services* — confirm with `hermes lsp status` (look for
  `✓ pyright` / `✓ typescript`). They run automatically on every `write_file`
  / `patch`: the `lint` field in the write_file result IS the LSP verdict
  (`"status": "ok"` = clean). `pyright` is NOT a standalone CLI here — do NOT
  call it in the terminal; trigger it by writing/editing the file. If
  diagnostics are non-empty, the rename/extract introduced an undefined name
  or type error that manual grep would have missed — fix before committing.
- **Behavior-preservation diff.** Refactors must not change output. Capture
  the OLD generated artifact, build with the new code, and diff:
  `git stash push -- <file>` → run the build (old code) → capture output →
  `git stash pop` → run the build (new code) → `diff`. Byte-identical size is
  a strong first signal; follow with a JSON content diff (slug set + per-model
  payload). See `references/verify-refactor.md` for a copy-paste recipe.
- **Pitfall — do NOT self-install LSP.** User directive: use Hermes's built-in
  LSP only; if you think you need more, ASK — never `uv tool install pyright` /
  `ruff` / `basedpyright` yourself. Self-installing mid-refactor was
  interrupted by the user; the built-in service is sufficient and catches the
  undefined-name risks manual grep misses.

## Black-box testing — NO jsdom / NO node-DOM
The user explicitly said "we can do this without node." Verify the Result
contract with pure-Python pytest (and pure-JS node scripts run once then
deleted — never add jsdom as a dev dep).

Pattern for each `Result`-returning function:
- Stub the I/O boundary at the boundary, not the function. e.g.
  `mock.patch.object(mod, "_load_json", return_value=err("boom"))`
  then assert `r.is_err()` and `r.error == "boom"`.
- Happy path: point the function at REAL fixtures (real `model_registry.json`,
  real `aa_charts_export.json`) and assert `r.is_ok()` + shape
  (`len(r.unwrap()["models"]) > 0`). No fake in-memory dicts that
  drift from real data.
- Failure path: assert `Err` on missing / malformed / load-failure.
  NEVER assert on HOW the function reached the result (no mock-call
  counting, no "was _load_json called" spies). Input -> output only.

### The import-path gotcha (costs a failed test run every time)
Modules under `data/` use RELATIVE imports (`from .sources.aa._build
import ...`, `from ..._canonical import ...`). So:
- To import `data/_build_registry.py` in a test, import it as
  `data._build_registry` (package path), and put BOTH the repo root
  AND `data/` on `sys.path`:
  `sys.path.insert(0, repo_root); sys.path.insert(0, repo_root/"data")`.
- Reason: `data/_canonical.py` does `from _result import ok, err`
  (absolute, expects `data/` on path). When loaded as part of the
  `data` package, `_result` resolves only if `data/` is on `sys.path`.
  Missing it → `ModuleNotFoundError: No module named '_result'`.
- For pure top-level modules (`_result.py`, `_pipeline.py`,
  `project_axes.py`) that use `from _result import ...`, just put
  `data/` on path and import them by bare name.

## JS data layer — window-globals IIFE (the real seam)

When the viz layer loads via `<script>` IIFEs that share `window.*` globals
(NOT ES modules), the refactor looks different from Python but the rules hold:

- **Wire the Result module into the HTML load order.** A `viz/_result.js` that
  does `window.Result = { ok, err, fromFn }` is DEAD unless its `<script>` tag
  appears in `dashboard.html` BEFORE any module that reads `window.Result`.
  `_result.js` existed in this repo but was never in the script list — so
  `_domain.js` calling `window.Result` would crash at load. Adding the tag is
  part of the same change as making a dependent use Result.
- **The genuine Result seam is the data-load boundary, not render code.**
  Make `Model.load(raw)` return `Result<Model[]>` (Ok on array, Err on
  non-array). Add a `loadModels(payload)` boundary that normalizes both the
  `{ meta, models }` payload shape AND the raw-array shape into Result, then
  populate `window.MODELS = r.unwrap()` only when `r.isOk()`. Pure helpers
  (`bucketByReasoning`, `paretoFrontier`) and render/event code stay untouched —
  forcing Result into SVG-building `render(container, data)` is contrived; the
  monadic-refactor scope explicitly excludes event-driven render code.
- **Verify the load chain in node, no browser, no jsdom.** Shim `window` and
  eval each script with `new Function('window', src)(win)`; assert `win.Result`
  is present, `win.MODELS` is the expected row count, and
  `loadModels(realProcessed).isOk()`. Load the REAL `data/processed.js` as the
  payload. Reusable recipe in `references/js-window-globals-result.md`.

## Step-piping DOESN'T COUNT if the steps are nested in the function
The user's hard critique: wrapping a 250-line imperative body in a `pipe()`
call while leaving the `step_*` functions NESTED INSIDE `run()` is worthless
— you still scroll past every step body to reach the one call at the
bottom, so the pipeline isn't visible and the function is still a monster.
The refactor is only real when:

- `step_*` functions are MODULE-LEVEL (not closures inside `run()`), so
  `run()` becomes ~15 lines: setup -> explicit guard loop over
  `(step_aa, ..., step_write)` -> summary. The pipeline is readable at the
  top.
- Each step takes a shared `state` dict (e.g. `{"all_models", "src",
  "out", "today", "counts", "name_map"}`) and returns `Ok(state)` or
  `Err`. Steps read paths like `OUT`/`today` from `state` (or a module
  global), NOT from `run()`'s locals — nested closures captured them
  implicitly; hoisted functions must get them via state/global.
- Sharing a module global across `run()` and hoisted steps: declare
  `global BASE` at the top of `run()` and set `BASE = None` at module
  level, so the hoisted steps (which call `get_aa_models(BASE)` etc.)
  resolve it.

This is the user's bar for "done" — not just `Result`-at-the-boundary.
Flag inline `def step_*(...)` inside `run()`/`build()` as not-yet-done.

## Naming discipline (pairs with code-quality §3)
The user also corrected naming during this refactor: descriptive
variable/function names over cryptic short forms. When extracting
`step_*` / helpers, name them so the pipeline reads at a glance
(`step_livebench`, `parse_price`, `canonical_id`, `arena_id`,
`current_state`) — NOT `s`, `r`, `lb`, `cid`, `aid`, `or_price`, `out`.
Rename, don't banner-comment: if a step body needs a `── SECTION ──`
comment to be legible, the helper name should already say it. The
decomposition signal and the full naming rules live in
**code-quality §3 — Naming & Decomposition**; load it for any rename
pass. After a rename, grep for every old reference and run the full
suite — a missed `s[...]` after renaming `s` -> `state` is a
`NameError` that breaks the build (this bit us this session).

## Nushell: pure-spec ↔ effect-layer split (the monadic seam here)
Nushell is a real target (the user's dotfiles are nushell). The monad here is a
`Result` record `{ ok: bool, val: any, err: any }` built by `ok`/`err` defs;
the FP seam is the same as in Python/JS — **separate pure argument/value
builders from the side-effecting runner** so the builders are unit-testable
without executing (e.g. docker). Concretely from the nushell-dotfiles refactor:

- **Pure spec builders** (`hermes/spec.nu`): `dev-spec` / `panic-spec` /
  `build-spec` take the container engine as an INJECTED arg and return the
  `list<string>` arg vector (or a record of vectors). No `try`, no `^docker`.
  Deterministically reproducible → assertable against a captured baseline.
- **Effect layer** (`hermes/run.nu`, `build.nu`): resolve engine, call the
  spec, then `_run-or-dry-run` prints + executes and returns a `Result`.
  Failures flow through `(result-is-err $r)`.
- **Pure arg builders** (`lib/cmd.nu`): `flag [parts, cond, name]` /
  `opt [parts, value, name]` / `build [...segments]` replace the
  `...(if cond {[$f]} else {[]})` spread idiom with explicit, testable fns.
- **maid**: `get-targets [catalog, registry]` is pure (inject both);
  `maid-action` returns a `Result` (ok / `no-action` / `exec-failed`). The
  public `maid` command is the effect orchestration over those pure fns.

Test harness pattern (no framework): each domain file defines
`let <domain>_test = [ { name, run: { assert-... } } ... ]`; a `tests/run.nu`
sources them, flattens, and runs each `run` closure in a `try`, collecting
`{name, ok, msg}` into a list — NEVER mutate a `mut` from inside the `catch`
block (see trap 4). Compute counts from the collected list afterward.

### Nushell syntax traps that cost real failures (verify against `nu` itself)
1. **Piping into a CUSTOM def does NOT bind the input.** `$x | my-fn` reports
   "missing required positional argument" — only BUILTINS (flatten, append,
   where, each, ignore, is-empty…) accept pipeline input that way. Call custom
   Result/cmd fns EXPLICITLY: `(result-is-err $r)`, `(flag $parts $cond $name)`.
   Builtins that take the piped value (append/flatten/where) are fine to pipe.
2. **Closures need `do`.** `($fn $arg)` parses as `$fn $arg` (a two-arg call);
   use `(do $fn $arg)`. Same for `map`/`bind` over a Result: `(do $fn $r.val)`.
3. **`opt [a] 5 --n` treats `--n` as a FLAG, not the string arg.** Quote string
   args meant to be positional: `opt [a] 5 "--n"`. (Applies to any literal
   starting with `-` passed to a custom def.)
4. **`mut` cannot be mutated inside a `catch`/`try` block** ("capture of mutable
   variable"). Don't do `mut n = 0; try { ...; $n = ($n + 1) } catch { ...;
   $n = ($n + 1) }`. Instead collect results into a list inside the try and
   derive counts from the list afterward:
   `let r = try { do $case.run; {ok:true} } catch {|e| {ok:false,msg:$e.msg} };
   $results = ($results | append $r)`.
5. **`is-err` / `is-ok` are BUILTINS (method form)** — defining same-named defs
   conflicts at the `is-err <r>` call site. Name your Result predicates
   `result-is-err` / `result-is-ok`.
6. **`def` params can't have DYNAMIC defaults.** `def f [x = $SOME_VAR]` →
   "Default values should be constant expressions". Make such params REQUIRED
   and have the caller pass the value (e.g. `get-targets $catalog $registry`).
7. **Re-sourcing a file with `def`s is fine** (`source a.nu; source a.nu`), but
   `source` needs a NATIVE path on Windows/MSYS — `/c/...` is rewritten to
   `\c\...` and "File not found". Pass `$HOME/...` forward-slash native
   paths to `nu -c 'source ...'` and `source`.
8. **`assert-equal` must compare RAW values, not `to nuon` strings.** Don't wrap
   test args in `| to nuon` — that stringifies lists and they compare unequal
   to a literal list. Compare `($got | to nuon) != ($want | to nuon)` only
   INSIDE the assertion using raw `$got`/`$want`; the harness prints `to nuon`
   for diagnostics.

Concrete copy-paste starter (monad defs, arg builders, harness, runner,
behavior gate): `references/nushell-result-refactor.md`.

## `pipe`/`do` are NOT in this codebase (user decision)
User asked whether `pipe(1,2,3)` is idiomatic Python and, after seeing it,
rejected it: "if it is not, then let's just stick to the one call one
function instead. just like the test_pipeline.py. be consistent." So:
- `.bind`/`.then` are Rust/Haskell (`Result::bind`) and JS
  (`Promise.then`) idioms. Python has no built-in `then` and no
  pervasive monad culture. `pipe(x, f, g)` mirrored `toolz.pipe` but
  `toolz.pipe` is a plain value-threaded pipeline, NOT error-short-
  circuiting — the fused `pipe` was a deliberate construct, NOT "the
  Python way," and was REMOVED.
- Real Python stops on first error via: exceptions (let it bubble), or
  explicit `if r.is_err(): return r` guards (Go-style). That is exactly
  the pattern used here — see `data/_pipeline.py` / `tests/test_pipeline.py`.
- Chain stages with the explicit guard loop or the `Pipeline.then`
  object — never a `pipe()`/`do()` fusion. Keeping it to one-call-one-
  function is the consistency bar the user set.

## Per-file refactor checklist
1. Add `from _result import ok, err` (+ local `_load_json`/`_load_csv`).
2. Extract each source-merge / I/O block into a MODULE-LEVEL
   `step_*(s)` over a shared `state` dict; returns `Ok(s)` or `Err`.
3. Convert required loads to `_load_json(...)`; `if r.is_err(): return
   err(r.error)`; `data = r.unwrap()`.
4. Convert the function's final `return X` to `return ok(X)`.
5. `run()` / `build()` orchestration: REUSE the repo's existing `Pipeline`
   class (`data/_pipeline.py`) — `Pipeline(ctx).then(name, fn).run()` — rather
   than hand-rolling a `steps` tuple + `for` loop. The user rejected a bespoke
   `steps`-array + forloop as "ugly"/"inconsistent" with the established idiom;
   one `Pipeline().then().run()` shape across every stage (and across Python +
   JS) is the bar. Keep the orchestration ~15 lines and visible at the top;
   steps stay module-level. If no `Pipeline` class exists in the target repo, a
   `for step in (step_a, ...)` guard loop over module-level functions is the
   fallback — but prefer the shared class when present. **When extracting a
   section-banner block from `run()`/`build()`, wire the new helper back as a
   `.then(name, fn)` step (not a bare post-run call) — see `commenting-culture-cleanup`
   recipe 2b(e) for the worked shape + the `ok(ctx[name])` vs `ctx[name]` return trap.**
6. Update callers: `x = fn()` -> `r = fn(); if r.is_err(): return
   err(...)` or `.unwrap_or(None)` for optional sources.
7. `__main__`: `r = run(); if r.is_err(): print + raise SystemExit(1)`.
8. Black-box test: stub `_load_json` -> err, assert Err; real fixtures ->
   Ok. Run `python -m pytest tests/ -q` (full suite must stay green).

### Port `Pipeline` to JS for browser-side orchestration
`viz/_result.js` exposes `window.Result.Pipeline` — same `.then(name, fn).run()`
shape, threads a shared `ctx`, short-circuits on a thrown error or a returned
`Err` (sets `ctx._failed_step` / `ctx._error`). Use it in `_boot.js` to
orchestrate boot as `window.Result.Pipeline({}).then(...).run()` so Python build
stages and the JS boot share ONE idiom. User mandate: do NOT invent a parallel
`VizPipeline` steps-array in the browser — reuse the same `Pipeline` the Python
side already uses. Steps are named functions taking `ctx`; render/event code in
viz files stays untouched (see "JS data layer" above). To use `ok`/`err` inside
boot step functions, capture `const { ok, err } = window.Result;` at the top of
the IIFE (they live on the global, not in lexical scope).

**JS `Pipeline` short-circuit in the orchestrator.** After `.run()`, the
Pipeline sets `ctx._failed_step` on the first thrown error or returned `Err`
but still returns `ctx`. So a `run()` wrapper that does work after the pipeline
MUST check `if (pipeline.ctx._failed_step) return err(...)` (or
`return err(pipeline.ctx["_error"])` in Python) BEFORE reading terminal values —
otherwise it reads undefined/`KeyError`. This mirrors the original explicit
`for`-loop `if r.is_err(): return err(r.error)` early-return.

**Render steps must be resilient — do NOT let one viz abort the boot.**
`Pipeline.run()` swallows a thrown error (sets `_failed_step`, returns) — so a
`render()` that throws stops the WHOLE boot and blanks the page. Wrap each viz
render in a `safeRender(v, mount, models)` helper (try/catch → inline error +
`console.error`, never rethrow) used in `renderFirst`, tab-click, and
filter-sync renders. Keep shell-building steps on the raw pipeline (a broken
shell SHOULD short-circuit), but make RENDER steps resilient so the shell + first
tab always render. Full pattern + the verify-it-renders-on-load node harness in
`viz-js-pitfalls` (Pitfall 10). Symptom this prevents: user reports "it's not
rendering on load" with a blank page and only a missable red error box.

**`then` step return-shape gotchas (cost test failures this session):**
- `Pipeline.then(name, fn)` ALWAYS `unwrap()`s the returned `Result`, so
  `ctx[name]` is the UNWRAPPED value, never a `Result`. If a step fn returns
  `ok(x)`, `ctx[name] == x`. A terminal step that returns `ok(payload)` should
  be returned as `ok(ctx["payload"])` (the dict, wrapped once) — NOT double-
  wrapped into `ok(ok(...))`, which turns `r.unwrap()["field"]` into a crash.
  Conversely, if the terminal helper itself returns `ok(...)`, `ctx[name]` is
  already a `Result`, so `run()` returns `ctx[name]` directly (don't wrap
  again). Check what the helper actually returns before wrapping.
- A step that returns a TUPLE (e.g. `_compute_axis_pairs` →
  `(n_axis_pairs, source_groups)`) lands in `ctx[name]` as the tuple. In a
  later step, pass the tuple slot correctly OR unpack at the step: prefer
  `.then("compute_pairs", c => _compute_axis_pairs(...)[0])` and read the other
  part from an earlier step's `ctx`. Storing the raw tuple and passing it as a
  positional arg later → "tuple has no attribute 'items'" at render.
- Check `_failed_step` before reading terminal values even on the OK path — a
  thrown error in step N leaves later `ctx` keys unset.

## Full-pipeline determinism test (the "ultimate test")
User requires a black-box input→output determinism test proving the pipeline
emits IDENTICAL bytes given identical source data. This is the final gate after
ANY structural refactor. Recipe (this session, `tests/test_pipeline_determinism.py`):

1. `shutil.copytree(real_data_dir, tmp/data, ignore=shutil.ignore_patterns("__pycache__"))`
   — a self-contained fixture set, NO network.
2. Run the real build TWICE. Redirect root to the temp copy so repo artifacts
   are never mutated: `build_from_cache({"root": tmp})`. Every stage must derive
   input and output paths from `ctx["root"]`; the dashboard builder must pass
   explicit temp registry/axes paths to `ProjectionEngine` and write
   `processed.js` under the temp data directory, not beside its imported module.
   Remove `model_registry.json`, `axes_catalog.json`, and `processed.js` from the
   copied data before building, so stale copies cannot make the test pass when a
   stage ignored the temp root.
3. `hashlib.sha256` the three generated artifacts (`model_registry.json`,
   `axes_catalog.json`, `processed.js`) from each run; assert all three match
   across runs. Also assert non-empty (stable-but-empty is a false pass).
4. `shutil.rmtree` the temp dirs.

This is pure input→output comparison — no implementation spying. Run it as the
last check: `pytest tests/ -q` green AND determinism test passing = refactor done.

For the JS window-globals layer (no browser, no jsdom), see
`references/js-window-globals-result.md` for the node load-chain sim that
asserts `window.Result` is wired and `window.MODELS` populates correctly.

## Pitfalls (this session)
- A `.csv` is NOT JSON — `_load_json` on a CSV throws
  `JSONDecodeError`. Add a separate `_load_csv` for `csv.DictReader`
  loads (LiveBench). The all-JSON `_load_json` converted the CSV
  load and broke `run()`; a black-box test on real sources surfaced it.
- When you rename a `Result` var, any later reference to the OLD name
  is a `NameError` (e.g. `aa_models` became `aa.unwrap()` —
  capture `aa_models = aa.unwrap()` before `.update()`).
- Don't duplicate `_load_json` across 5 files if DRY matters; but
  patching the foundation mid-session to add it ripples to every caller
  commit. A local helper per file is the lower-risk, contained move.
- Hoisting `step_*` from inside `run()` to module level: the steps
  referenced `BASE` (a `run()` local). After hoist, `BASE` must be a
  module global — declare `BASE = None` at module level and `global
  BASE` at the top of `run()` before assigning. Otherwise hoisted steps
  raise `NameError: name 'BASE' is not defined` at call time.
- After hoisting, verify the REAL build output is byte-identical (same
  model count / alias count) — the refactor is behavior-preserving, so
  the output JSON must not change. A real-build smoke check catches
  regressions that black-box tests on stubs miss.
- **MSYS `/tmp` does NOT persist across separate `terminal()` calls** on this
  Windows host — each call is a fresh MSYS session and a `/tmp` path written in
  one call may be absent (or a different mount) in the next, so interactive
  before/after behavior-diffs that write to `/tmp` and read later silently
  fail with empty/garbage reads. Do the whole stash→build→capture→pop→build→
  compare in ONE terminal command. Alternative: leave the file in the repo tree
  and use `git stash push -- <file>` to snapshot the before-version in place,
  build, capture, pop, build again, then diff — no `/tmp` needed. (The committed
  pytest determinism test uses a repo-relative tempdir inside a single Python
  process, so it is unaffected.)
- `pipe()`/`do()` fusion WERE ADDED then REMOVED. The user saw
  `pipe(state, step_a, ..., step_write)` and said it's not idiomatic
  Python and to "stick to one call one function, like test_pipeline.py.
  be consistent." Lesson: don't introduce a fusion combinator the user
  didn't ask for — the codebase already had the consistent idiom
  (explicit `if r.is_err(): return err(...)` guards in a loop, or
  `Pipeline.then`). When in doubt, match the existing pattern rather
  than add a new abstraction. After removing them, delete their tests
  too and re-verify the suite stays green.
- **CLI arg-gate fallthrough → silent network pull (the "output differs"
  trap).** A top-level `python -m data._pipeline build_from_cache` that
  only matches the literal `"build"` (i.e. `sys.argv[1] == "build"`) will
  fall through to the FULL `build()` (network pull) for ANY other string —
  including the literal `build_from_cache`. Symptom: "the build produced
  different JSON values than before" with no code change. Root cause was a
  live source pull rewriting `data/sources/openrouter_models.json` and
  cascading into registry/axes/processed. Fix: accept both `build` and
  `build_from_cache` as the offline path; anything else runs the full pull.
  **How to verify a refactor didn't change data:** run a TRUE offline build
  by calling the function directly (`python -c "import data._pipeline as
  p; p.build_from_cache()"`) — NOT the CLI subcommand — then compare against
  HEAD with `git hash-object <file>` (sha) per artifact. A CLI subcommand
  that silently pulls will mask this. If the offline build reproduces HEAD's
  committed artifacts byte-for-byte (sha match) but the working tree still
  differs, the diff is INPUT DRIFT (a pull), not a regression — re-stash the
  accidental pull and don't commit it.
