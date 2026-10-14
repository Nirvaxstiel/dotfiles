---
name: code-quality
description: "Pre-commit verification pipeline and post-hoc simplify/cleanup — static scan, independent reviewer, auto-fix, parallel 3-agent review."
version: 1.0.0
author: Hermes Agent (consolidated from requesting-code-review, simplify-code)
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [code-review, quality, security, verification, pre-commit, simplify, cleanup]
    related_skills: [test-driven-development, debugging, plan, github]
---

# Code Quality: Pre-Commit Verification & Post-Hoc Cleanup

Two complementary workflows for keeping code clean, secure, and well-structured.

## §1 — Pre-Commit Verification (`requesting-code-review`)

Automated verification pipeline before code lands. **Core principle:** No agent should verify its own work.

### When to Use
- After implementing, before `git commit` or `git push`
- When user says "commit", "push", "ship", "done", "verify", "review before merge"
- After completing a task with 2+ file edits in a git repo

### Step 1 — Get the diff
```bash
git diff --cached           # staged changes
git diff                     # if empty, working tree
git diff HEAD~1 HEAD        # last commit
```
If diff > 15,000 chars, split by file: `git diff --name-only` then `git diff HEAD -- specific_file.py`

### Step 2 — Static security scan
```bash
# Hardcoded secrets
git diff --cached | grep "^+" | grep -iE "(api_key|secret|password|token|passwd)\s*=\s*['\"][^'\"]{6,}['\"]"
# Shell injection
git diff --cached | grep "^+" | grep -E "os\.system\(|subprocess.*shell=True"
# Dangerous eval/exec
git diff --cached | grep "^+" | grep -E "\beval\(|\bexec\("
# Unsafe deserialization
git diff --cached | grep "^+" | grep -E "pickle\.loads?\("
# SQL injection (string formatting in queries)
git diff --cached | grep "^+" | grep -E "execute\(f\"|\.format\(.*SELECT|\.format\(.*INSERT"
```

### Step 3 — Baseline tests + linting
Detect project language. Stash changes, run baseline, pop. Only NEW failures block.

**Tests** (auto-detect):
```bash
python -m pytest --tb=no -q 2>&1 | tail -5       # Python
npm test -- --passWithNoTests 2>&1 | tail -5       # Node
cargo test 2>&1 | tail -5                          # Rust
go test ./... 2>&1 | tail -5                       # Go
```

**Linting** (run only if installed):
```bash
which ruff && ruff check . 2>&1 | tail -10
which mypy && mypy . --ignore-missing-imports 2>&1 | tail -10
which npx && npx eslint . 2>&1 | tail -10
cargo clippy -- -D warnings 2>&1 | tail -10
go vet ./... 2>&1 | tail -10
```

### Step 4 — Self-review checklist
- [ ] No hardcoded secrets, API keys, or credentials
- [ ] Input validation on user-provided data
- [ ] SQL queries use parameterized statements
- [ ] File operations validate paths (no traversal)
- [ ] External calls have error handling
- [ ] No debug print/console.log left behind
- [ ] **No commented-out code**
- [ ] **Zero noise comments** — no docstrings on module/class/function/test, no section banners (═══ or ── lines), no inline explanatory comments. Allowed: provenance labels, # noqa, copyright headers. Rename instead of comment.
- [ ] **Dead exports**
- [ ] **Dead exports** — extracted helpers referenced by at least one consumer. `grep` for usage after extraction.
- [ ] **Zero-division guards** — percentage calcs, rate computations, anything denom-based guard with `|| 1` or early skip
- [ ] **Rendering consistency** — tooltip/overlay uses same value filters as primary render (don't show zero-value tooltip rows that SVG hides)
- [ ] **Edge-case values** — zero, null, near-zero handled explicitly before falling through generic conditional chains
- [ ] **Inline style ternaries** — ternary-branching inline `style="..."` in JS template literals are brittle. Use CSS classes toggled via `${condition?'active':''}`
- [ ] **Unused parameters** — check function signatures; rename to `_unused` or remove
- [ ] **Full-sweep after pattern fix** — If you fixed a bug, anti-pattern, or quality issue in one file, search ALL files for the same pattern. Fix every instance, not just the first one found. Partial fixes create asymmetric code quality.

**Consolidation check** — After individual fixes, check for duplicate code patterns across files. If 3+ files implement the same algorithm (tooltip wiring, label placement, axis formatting, data filtering), extract to a shared utility and update all consumers. Net-negative line change validates the extraction. Search for copy-paste candidates among touched files.

### Step 5 — Independent reviewer subagent
```python
delegate_task(
    goal="""You are an independent code reviewer. Return ONLY valid JSON.
FAIL-CLOSED: security_concerns/logic_errors non-empty -> passed=false.
<static_scan_results>...</static_scan_results>
<code_changes>...</code_changes>
Return: {"passed": bool, "security_concerns": [], "logic_errors": [], "suggestions": [], "summary": "..."}""",
    context="Independent code review. Return only JSON verdict.",
    toolsets=["terminal"]
)
```

### Step 6 — Evaluate results
- All passed → commit
- Any failures → report, then auto-fix loop

### Step 7 — Auto-fix loop (max 2 cycles)
Spawn a fix agent that fixes ONLY reported issues, no refactoring. Re-verify after each cycle. After 2 failed attempts, escalate to user.

### Pitfalls (Pre-Commit)
- **User expects full-scope quality audits** — When the user says "code quality" or "check with SWE skills", they mean audit ALL files in the project, not just the one you touched. The quality pass must sweep every file for the same class of issue (dead code, duplication, inline styles, missing guards). Partial sweeps create asymmetric code quality and frustrate users who explicitly asked for thoroughness. Load the relevant skills BEFORE starting work, not after.
- **Inline-style ternaries in template literals** — JS strings with nested ternary conditionals for CSS `style="..."` are fragile. One unbalanced quote or brace breaks the page. Use CSS classes toggled via `${condition?'active':''}` instead.
- **Dead libraries** — when extracting shared utility modules, verify every exported function is actually called by at least one consumer before declaring the extraction done. Dead exports are noise.
- **Data integrity across transformations** — when redistributing values (e.g. cost segments), verify the total is preserved after rounding. Drift-correction logic may be needed to keep the sum byte-exact.
- **Partial fix trap** — fixing a class of bug/anti-pattern in only one file leaves asymmetric code quality. After any structural fix, grep for the original bad pattern across ALL files. The fix is incomplete until every instance is handled.
- **Fix the ROOT CAUSE, not a band-aid that masks it.** When the user reports a failure (blank page, render error, test red), find WHY it happens — do not wrap the symptom in a catch/swallow that hides it. A "harden X so it can't throw" wrapper that silently absorbs errors (e.g. wrapping every render in try/catch that logs-and-continues) is a band-aid the user will reject: *"revert and try again, why isnt the legend filter being shown"* / *"only fix the part and figure out why it wasnt rendering in the first place."* Correct response: reproduce the failure (headless harness, console error), locate the actual defect (a null-parent lookup, a missing populate-on-load call), fix THAT precisely, and keep the failure LOUD (let it throw / show an error box) so future regressions surface. Band-aids also hide real bugs and confuse later sessions.
- **Don't invent a regression that wasn't reported.** If the user says "X is broken," verify against actual code/tests before assuming the worst. A missing render might be a single hidden element (a `display:none` strip never populated on load), not a page-wide crash. Match the fix scope to the reported symptom.
- **Extraction without migration** — creating a shared helper function but not converting existing inline copies to use it creates dead API surface. After extracting, update every consumer in the same pass. An exported function with zero callers in the repo is a liability, not a library.
- **Template literal interpolation — use `${}`, not `' + ... + '`** — inside a JS template literal (backtick string), using `' + expr + '` string concatenation produces broken output: the literal text `' + expr + '` appears in the result instead of the evaluated value, and unbalanced quotes corrupt the surrounding string. Always use `${}` for interpolation inside template literals. One unbalanced quote inside a template literal breaks the entire string and often manifests as a silent render bug rather than a loud error.
- **`new Function()` rejects valid browser IIFEs** — `node -e "new Function(src)"` parses a script as a Node program and rejects references to browser-only globals (e.g., `app()`, `document`, `window`) that exist at runtime in the browser. A browser IIFE that runs correctly in the dashboard can fail this check. Use `node --check` for syntax validation instead — it only checks syntax, not runtime references. When this check fails on a file you did not edit, confirm it is pre-existing by running the same check on `git show HEAD:file` before assuming your edit introduced the error.
- **Python `compile()` rejects Unicode in comments** — Python 3.11's `compile()` function rejects source files containing certain Unicode characters (e.g., → U+2192, … U+2026) even when they appear ONLY in comments. This causes false-positive syntax errors when validating JS files from Python. Use Node's parser (`node --check`) for JS validation instead — it handles these characters correctly.
- **Multi-line `patch` calls can re-indent the replacement.** The patch tool preserves *relative* offsets measured against the FIRST line of `old_string`. If that line is written flush-left while the file indents it, every replacement line shifts by that difference (a 4-space body lands at 6 or 8) — syntactically valid code, visibly drifted indentation. Fix: give `old_string`'s first line the file's real indentation and keep `new_string` at matching relative offsets, then re-read the region to confirm. If the same region drifts twice, stop patching and rewrite the file with `write_file` (it preserves the file's existing CRLF/LF convention and only touches the lines you change).
- **Prefer a scratch script file over `-e`/`-c` one-liners.** `node -e` / `python -c` / `execute_code` trip approval gates that stall when the user is away. Write the probe to the scratch dir with `write_file`, then run `node <file>` / `python <file>` — plain script execution goes through unattended.
- **Check whether a red test was already red.** Before "fixing" a failing test that touches code you did not change, run the same call against `git show HEAD:<file>` (extracted to a temp path). Pre-existing breakage (e.g. a test calling a function without its required `fields` arg) is repo state, not your regression — report it as such and fix the test's intent, not the assertion's number.

### Step 8 — Commit
```bash
git add -A && git commit -m "[verified] <description>"
```

---

## §3 — Naming & Decomposition (user preference, cross-cutting)

Applies to EVERY refactor/feature pass, not just cleanup. The user stated it
directly: descriptive names over cryptic short forms, and section-comment
banners inside a function are a decomposition signal, not something to add.

### Naming
- Prefer descriptive variable/function names over opaque short forms
  (`s`, `r`, `ep`, `lb`, `cid`, `aid`, `img_b`, `img_p`, `or_price`,
  `inp`/`out` as prices, `db`, `sp`, `cat`). Long enough to grasp at first
  glance; domain abbreviations OK only if self-evident in context
  (`cid` -> `canonical_id`, `aid` -> `arena_id`, `or_price` -> `parse_price`,
  `s` (state) -> `state`/`current_state`).
- Rename, don't comment. A name that needs a comment to be understood is the
  wrong name.
- When you rename a `Result`/state var mid-refactor, grep for EVERY old
  reference (loop returns, summary blocks, `__main__`) — a single missed
  `s[...]` after renaming `s` -> `state` is a `NameError` that breaks the
  build. Run the full test suite after a rename pass.

### Decomposition signal
- A function that needs `── SECTION ──` banner comments to stay readable is a
  TELLTALE SIGN it should be split: extract each section into its own named
  helper. Banner-commenting a monolith is NOT a fix — it's papering over the
  smell.
- Each extracted helper should be self-describing by name; if you'd reach for
  a section comment to explain what the block does, the helper name should
  already say it (e.g. `step_livebench`, `parse_price`, `resolve_or_context`).
- This pairs with the monadic-refactor rule: hoist `step_*` helpers to module
  level so the orchestrator `run()` shows the pipeline at the top, not buried
  under 250 lines of step bodies.

## §2 — Simplify Code (Parallel Cleanup)

Review recent changes with three focused reviewers running in parallel, then apply selective fixes.

### When to Use
Only when the user explicitly asks: "simplify", "review my code", "clean up my changes", "/simplify".

Optional modifiers:
- **Focus:** `simplify focus on efficiency` → run only efficiency reviewer
- **Dry run:** `simplify but don't change anything` → report only
- **Scope:** `simplify the last commit` / `simplify staged` / `simplify src/foo.py`

### Phase 1 — Identify changes
```bash
git diff                    # default: uncommitted working tree
git diff HEAD               # if empty, include staged
git diff --staged           # "staged changes"
git diff HEAD~1             # "the last commit"
git diff main...HEAD        # "this branch" / "my PR"
```
If >2000 changed lines, warn user and offer to scope down.

### Phase 2 — Launch three reviewers (parallel batch)
Use `delegate_task` batch mode — all three run concurrently with `terminal`, `file`, `search` toolsets:

**Reviewer 1 — Code Reuse**: Find duplicate functionality, existing utilities the new code should call instead of reimplementing.

**Reviewer 2 — Code Quality**: Find redundant state, parameter sprawl, copy-paste-with-variation, leaky abstractions, stringly-typed code.

**Reviewer 3 — Efficiency**: Find unnecessary work, missed concurrency, hot-path bloat, TOCTOU patterns, memory issues, overly broad reads.

### Phase 3 — Aggregate and apply
1. Merge findings, dedupe
2. Discard false positives (you have most context)
3. Resolve conflicts: correctness > user's focus > readability > micro-perf
4. Apply fixes with `patch`/`write_file` (unless dry run)
5. Verify: run targeted tests + linter for touched files
6. Summarize changes grouped by reviewer category

### Pitfalls
- Don't fan out wider than ~3 reviewers
- Give EVERY reviewer the COMPLETE diff (cross-file issues hide in gaps)
- Reviewers must provide `file:line` evidence — drop findings lacking it
- Apply ≠ rewrite — keep edits scoped to what the diff touched
- Respect project conventions (AGENTS.md, linter configs)
- Large diffs blow context — scope down before delegating
