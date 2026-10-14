---
name: commenting-culture-cleanup
description: >
  ZERO comments on new code. Strip docstrings, banners, dividers from all files.
  The user has expressed EXTREME frustration about this multiple times.
  LOAD THIS BEFORE ANY EDIT THAT TOUCHES CODE OR COMMENTS.
---

# Commenting Culture Cleanup

## LOAD THIS BEFORE EDITING ANY FILE — User Enforces Extremely Rigorously

**This is the single most-violated rule in this codebase.** The user has said:
- "Hates noise comments — docstrings, inline explanations, section headers"
- "A lot of comments I specifically asked not to have those comments"
- "please for the love of God, pass through all of the comments"
- "I'm pretty sure I've explained this very, very many times"

**Every comment you ADD or LEAVE IN PLACE is a deletion candidate. Zero tolerance.**

**Scope:** Python, JS, HTML, CSS, config, YAML — every file type.

## Cardinal Rules

### 1. Zero comments on new code
If code needs a comment to explain what it does, rename the function/variable. No inline comments inside function bodies. No docstrings on private functions.

### 2. Section banners = function too long -> split the function
Any `# ═══════` / `// ────` / `# ── DOMAIN ──` / `# === STAGE N ===` divider
inside a function body means the function needs internal navigation because
it's too long. **Extract the sections into named module-level helpers; the
function name replaces the comment — the comment does NOT move, it disappears.**
User directive (verbatim, this session): "if you need to add comments to each
section of a code of a massive function, That already is a telltale sign that
you need to break it up." Concrete smells the user flagged:
- `# ── AA PRICING ──` / `# ── LIVEBENCH ──` banners inside a long `run()` →
  each domain becomes a named builder (`_build_aa_pricing_axes(models)`) that
  RETURNS its axis list; `run()` concatenates them (`axes = _build_aa_pricing_axes(models) + _build_cost_breakdown_axes(models) + ...`).
- The accumulator-lambda `ba = lambda *a, **kw: axes.append(_build_axis(models, *a, **kw))`
  inside a long `run()` is the SAME smell — replace it with per-domain named
  builders; never keep a `lambda` just to shorten appends.
- `# === 0) ... ===` stage comments inside a merge function → each stage
  becomes a `_step_*(state)` that returns `Ok(state)`/`Err`, and the function
  becomes a thin orchestrator with explicit short-circuit guards (see
  `monadic-refactor` skill for the Result-guarded step pattern).
- `# ── helpers ──` / `# ── helpers ──` file-level markers above a block of
  already-named functions are removable too — the function names self-group.
"700 lines is still 700 lines too many": a 700-line file with banners becomes
a package (or a set of named step functions) immediately.

### 2b. Worked extraction recipe (this session — the real shape)

These three transformations are the canonical pattern. Reuse them verbatim.

**(a) Domain-banner monster `run()` → per-domain named builders that RETURN their
list; `run()` concatenates.** From `_build_axes.py` (`ba = lambda *a, **kw:
axes.append(_build_axis(models, *a, **kw))` + `# ── AA PRICING ──` etc.):
```python
def _build_aa_pricing_axes(models):
    return [_build_axis(models, "aa.inp_price", "AA", ...), ...]

def run(ctx=None):
    ...
    axes = (
        _build_aa_pricing_axes(models)
        + _build_cost_breakdown_axes(models)
        + _build_aa_performance_axes(models)
        + ...
    )
    axes.sort(key=lambda a: (a["source"], a["type"], -a["models_have"]))
    ...
```
No `lambda` accumulator, no banners. `run()` becomes ~15 lines; the pipeline is
visible at the top.

**(b) Nested closure inside `run()` → module-level helper.** From
`_build_dashboard_data.py` (`def _radar_raws(row):` nested in `build()`):
hoist to `_extract_radar_raws(row)` (module level) + `_normalize_radar_scores(output)`
which consumes the collected raws. The closure captured `output` implicitly; the
hoisted version takes it as an argument.

**(c) `=== N)` stage comments in a merge function → `_step_*(state)` returning
`Ok(state)`/`Err`, thin orchestrator with short-circuit guards.** From
`sources/aa/_build.py` `get_aa_models`:
```python
def _step_scraped(all_models, aa_dir) -> "Ok[dict]|Err[str]":
    scraped = _load_json(...);  if scraped.is_err(): return err(scraped.error)
    ...
    return ok(all_models)

def get_aa_models(base):
    all_models = _step_charts(all_models, AA_DIR)
    all_models = _step_jsonld(all_models, AA_DIR)
    r = _step_scraped(all_models, AA_DIR);  if r.is_err(): return err(r.error)
    all_models = r.unwrap()
    ...
    return ok(all_models)
```
Each stage that can fail returns `Err` on the first failing load; the orchestrator
short-circuits. Matches `monadic-refactor`'s Result-guarded step pattern.

**(d) Duplicated closure → single shared helper.** `get_aa_jsonld_models` and
`get_aa_charts_models` each had the SAME 35-line `ensure(slug)` closure. Extracted
- `_ensure_aa_record(out, slug)`. Delete the duplicates — never keep two
  copies of an inline closure "because it's local."

**(e) In-repo `Pipeline` present → extract then WIRE AS A `.then()` STEP (not a bare call).**
User directive (this session, verbatim): "if the function does many things and we
use comments to structurally define a space, it should become encapsulated and then
wired up as a monad." When the host module already orchestrates via a shared
`Pipeline` (e.g. `data/_pipeline.py`'s `Pipeline(ctx).then(name, fn).run()`), the
extracted helper must be RE-INSERTED into the pipeline as a named `.then()` step —
NOT left as a bare function call after `pipeline.run()`. Concretely, from
`_build_registry.run()` which held a `# ── Summary ──` block doing 3 distinct
tallies:
```python
def _print_summary(output_models, name_map):
  print("\n── SOURCE COVERAGE ──")
  ...  # the 3 tallies, unchanged
  return ok({"model_count": len(output_models), "name_map_size": len(name_map)})

def run(ctx=None):
  pipeline = (Pipeline(state)
      .then("step_aa", lambda c: step_aa(c))
      ...
      .then("step_write", lambda c: step_write(c))
      .then("print_summary", lambda c: _print_summary(c["output_models"], c["name_map"])))
  pipeline.run()
  if pipeline.ctx.get("_failed_step"):
      return err(pipeline.ctx["_error"])
  return ok(pipeline.ctx["print_summary"])   # wrap the UNWRAPPED value once
```
The banner comment is GONE (the step name `print_summary` replaces it) and the
step is visible in the orchestrator. Two return-shape traps when wiring:
- `Pipeline.then` ALWAYS `unwrap()`s a returned `Result`, so `ctx["print_summary"]`
  is the UNWRAPPED dict, not a `Result`. Return it as `ok(ctx["print_summary"])` —
  do NOT write `return pipeline.ctx["print_summary"]` (that returns a plain dict and
  the caller's `r.is_ok()` blows up with `AttributeError: 'dict' has no attribute
  'is_ok'`). Conversely, if the terminal helper itself returns `ok(...)` and you
  return `ctx[name]` directly, don't wrap again — check what the helper actually
  returns before deciding.
- If the extracted block reads values computed by EARLIER steps, read them from
  `ctx["step_name"]` (the unwrapped output of that step), not from a local var that
  no longer exists after extraction.
This (e) is the monadic closure of the banner rule when a `Pipeline` already exists
in the module. If NO `Pipeline` exists, fall back to (c)'s explicit guard-loop
orchestrator. See `monadic-refactor` skill for the `Pipeline` shape + the
`then`-step return-shape gotchas in full.

**File-level markers are removable too:**
already-named functions is not a function-body banner, but the user still wants it
gone — the function names self-group. Strip it.

### 3. No docstrings on non-public code
No `"""..."""` on private functions/methods. Class docstrings only if the class name can't convey purpose. Module-level docstrings NEVER. Test docstrings also stripped — methods must be self-documenting.

### 4. Active refactoring over deferred cleanup
When user says "pay the cost today," do the structural work NOW. No TODOs, no plan entries, no deferred markers. Big file needing banners gets split into a package immediately.

### 5. NEVER write_file as cleanup shortcut
`write_file` replaces the entire file — one wrong import silently changes behavior. Use targeted `patch` for comment removal, or read+verify before `write_file`.

### 6. Redundant chat narration is the same disease as code comments
The user extended the no-noise rule to how the agent talks back, not just code.
Do NOT restate in prose what the code/diff already shows, do NOT explain your
changes to someone who reads code fluently, and do NOT add hedging that presumes
the user needs hand-holding ("as you can see", "this means that", "the fix is
simply"). Treat the user as a competent engineer: lead with the change/answer,
skip the walkthrough. A one-line summary of *why a non-obvious decision was made*
is fine; narrating *what* the code does is not. This is a style correction, not a
documentation preference — it applies to every reply.

### 8. Delete, don't tombstone
When removing a feature/source/field, REMOVE it from every doc and code path — do not leave `- REMOVED` / `DEPRECATED` markers or `#3 (was X)` ghost references. A tombstone in markdown (or a `DEPRECATED` label) confuses future sessions into thinking the thing still exists. Concrete case this session: the user removed the AA-image (vision/OCR) source end-to-end, then caught the agent annotating docs with `— REMOVED` instead of deleting the rows/sections. Fix: delete the matrix row, the detail section, the repro line, the schema field, the provenance bullet — and renumber the matrix so there's no gap. If a removal needs a reader note, phrase it forward ("metrics now come from #1A/#1B"), never as a pointer at a deleted entity.

This pairs with the doc-parity rule in `monadic-refactor`: docs must describe CURRENT behavior. A deleted feature with a tombstone is stale-by-design — worse than no note. When a removal also changes numbering (e.g. matrix rows renumber), update ALL cross-references in the same pass.

### 7. No berating, no dumb-treatment, no restate-the-code narration
**EXPLICIT USER DIRECTIVE (first-class — treat as a hard line, not a style note):**
"Don't include comments that seem berating of the user. Don't treat the user as if they're dumb. Make sure... just treat them like a normal functioning intelligent human being. Stop making bullshit comments that already tell you what the code already does."

- This covers BOTH code comments AND chat replies. A reply that re-explains what the diff shows, or frames the user as needing a walkthrough, IS the berating pattern the user called out.
- Lead with the change/answer. Skip the walkthrough. Never hedge as if the user can't read code. A one-line *why* for a non-obvious decision is fine; narrating *what* is not.
- Do not write comments (code OR chat) that merely restate behavior the reader can see. That is the "bullshit comment" class — delete on sight.

## Bulk Comment Stripping Process

### Step 1: Single-line docstrings (safest first)
```
content = re.sub(r'^( *)\"\"\"[^\n]*?\"\"\"\\n', '', content, flags=re.MULTILINE)
```
This matches `    """text"""` on its own line. Safe because `[^\n]` can't span lines.

### Step 2: Multi-line docstrings (while loop, one at a time)
```
while re.search(r'^( *)\"\"\"\\n', content, re.MULTILINE):
    m = re.search(r'^( *)\"\"\"\\n(.|\\n)*?\"\"\"\\n', content)
    if not m: break
    content = content[:m.start()] + content[m.end():]
```

### Step 3: Banner separators
```
content = re.sub(r'^# [═╗╚╔╝║\\-#─]{3,}.*\\n?', '', content, flags=re.MULTILINE)
```

### Step 4: Verify after each pass
```
python -m py_compile path/to/file.py
node --check path/to/file.js
python -m pytest tests/ -v
```

## Pitfalls (Must-Read — Proven This Session)

- **Loading this skill is not optional:** if you edit any file without loading this first, you WILL add comments the user flags. Documented repeatedly — does not stick without the load.
- **LSP verification = Hermes built-in, NOT self-installed.** User directive (verbatim): "use hermes already built in lsp, if you still need more, let me decide. dont do it yourself." Hermes ships `pyright` (Python) and `typescript-language-server` (JS) — confirm via `hermes lsp status`. They are NOT shell CLIs: `pyright` on PATH returns "command not found". They run as post-write semantic diagnostics inside `write_file`/`patch` — the `lint: {status: "ok"}` field in the tool result IS the LSP verdict (undefined names, type errors). After a `write_file`, read `lint.status`; re-run `pytest` for runtime confirmation. NEVER `uv tool install ruff basedpyright` or similar on your own — ask the user first.
- **Regex eats class definitions:** NEVER use `(class \w+.*:)\n\s+""".*?"""\n` with `re.DOTALL` — `.*?` searches across class boundaries for the next `"""`, deleting everything between. Destroyed the `Archetype` enum in one pass.
- **Multi-line docstrings need the loop:** single-shot `re.sub` can't safely remove multi-line `"""` blocks without cross-boundary matches.
- **Test files aren't exempt:** strip docstrings from test methods too.
- **CRLF/LF line endings:** Use `git diff --stat` to verify — if every line shows as changed, it's a line-ending issue.
- **`write_file` as cleanup shortcut is dangerous:** one wrong import silently changes behavior. Use targeted `patch` for comment removal, or read+verify with `py_compile` + `pytest` after `write_file`.
- **Python mutable-default `**MODEL_STUB` trap:** `**{"meta":{}, "pricing":{}, "aliases":{}}` spreads the SAME empty dict references to every new model. Subsequent `model["aliases"]["source"] = x` sets it on ALL models sharing that stub. Inline the dict literals instead: `{"aliases": {}}` not `**MODEL_STUB`.
- **Live data calibration rule:** Never commit a threshold (archetype bound, speed tier, cost range) without running it against real data. Write test with guess → inspect distribution → calibrate → re-verify.

## Package Split Sequence (When 700+ Lines)

When a file reaches 700+ lines with section banners, split into a package:

1. Identify clean dependency chain (enums → values → entities → projection → serialization)
2. Create package directory (e.g. `_domain/`)
3. Write each submodule file using `write_file` (new files, no regression risk)
4. Create `__init__.py` re-exporting all public symbols
5. Delete old flat file
6. Verify: `python -m py_compile` on every file, then run full pipeline + tests
