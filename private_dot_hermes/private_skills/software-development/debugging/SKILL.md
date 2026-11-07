---
name: debugging
description: "Systematic debugging methodology + Node.js (node inspect) + Python (pdb/debugpy) debugger tools."
version: 1.0.0
author: Hermes Agent (consolidated from systematic-debugging, node-inspect-debugger, python-debugpy)
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [debugging, root-cause, nodejs, python, pdb, debugpy, breakpoints, troubleshooting]
    related_skills: [test-driven-development, plan]
---

# Debugging

Root-cause investigation and debugger tools for Node.js and Python. Always understand the problem before fixing it.

## §1 — Systematic Debugging Methodology

**Core principle:** ALWAYS find root cause before attempting fixes. Symptom fixes are failure.

### The Iron Law
```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

### When to Use
- Test failures, bugs in production, unexpected behavior
- Performance problems, build failures, integration issues
- **ESPECIALLY** under time pressure or when "the fix" seems obvious
- **Don't skip when** the issue seems simple (simple bugs have root causes too)

### The Four Phases

#### Phase 1: Root Cause Investigation (no fixes yet)

1. **Read error messages carefully** — don't skip past errors/warnings
   - Action: `read_file` on relevant source, `search_files` for the error string
2. **Reproduce consistently** — can you trigger it reliably?
   - Action: Use `terminal` to run the failing test: `pytest tests/test_module.py::test_name -v`
3. **Check recent changes** — `git log --oneline -10`, `git diff`
4. **Gather evidence in multi-component systems** — log data at each component boundary
5. **Trace data flow** — find where the bad value originates, trace upstream
   - Action: `search_files("function_name(", path="src/")`

**Checklist before Phase 2:**
- [ ] Error messages fully read and understood
- [ ] Issue reproduced consistently
- [ ] Recent changes identified and reviewed
- [ ] Evidence gathered (logs, state, data flow)
- [ ] Problem isolated to specific component/code
- [ ] Root cause hypothesis formed

#### Phase 2: Pattern Analysis
1. Find working examples in the same codebase
2. Compare against references — read the reference implementation COMPLETELY
3. Identify every difference between working and broken
4. Understand dependencies — what assumptions does the code make?

#### Phase 3: Hypothesis and Testing
1. Form a single hypothesis: "I think X is the root cause because Y"
2. Make the SMALLEST possible change to test the hypothesis
3. One variable at a time — don't fix multiple things at once
4. If it didn't work, form a NEW hypothesis
5. When you don't know, say so and ask the user

#### Phase 4: Implementation
1. **Create failing test case first** — simplest possible reproduction (see `test-driven-development`)
2. **Implement single fix** — one change at a time, no refactoring
3. **Verify fix** — run the specific regression test, then the full suite
4. **Rule of Three** — if 3+ fixes failed, STOP and question the architecture
5. **Architecture problem indicators:** each fix reveals new coupling, fixes create new symptoms elsewhere

### Red Flags — STOP and Follow Process
- "Quick fix for now, investigate later"
- "Just try changing X and see if it works"
- "Add multiple changes, run tests"
- "I don't fully understand but this might work"
- **ALL of these mean: STOP. Return to Phase 1.**

### Pitfall — JS block scoping: `const`/`let` inside `if` is block-scoped, not function-scoped
When a `ReferenceError: X is not defined` points at a line that appears to be inside a conditional, **trace the variable's scope chain before touching it.** A variable declared with `const` or `let` inside an `if` block (e.g., `if (viewDef.options) { const defaultOpt = ...; }`) is **block-scoped** — it is invisible outside that block even when the condition is truthy and the block executed. A reference on a later line that falls outside the declaring block will throw `ReferenceError` every time, regardless of whether the condition was true.

**Do NOT "fix" by wrapping the reference in a mirrored ternary or if/else** — that preserves the scope bug (the reference still falls outside the declaring block). **Hoist to function scope**: declare with `let` before the `if` block, assign inside. Verify every reference to the variable with `grep -n varname file` — each reference must be in a scope that can see the declaration. A superficial scope fix (ternary/if mirror) that leaves the reference outside the block is a band-aid the user will reject as a hackjob.

---

## §4 — "Generated artifacts differ after a refactor" (isolate input-drift from regression)

When a user reports "the build/JSON/render output changed" after a code change,
the diff is often NOT a regression — it's **input drift** from a silent network
pull. Separate the two before touching code.

### Why this happens
A top-level build entry point (`python -m pkg._pipeline build_from_cache`) may
have a CLI arg-gate that only matches the literal `"build"`. Passing any OTHER
string (including the literal `"build_from_cache"`) falls through to the FULL
build (`build()`) which PULLS live sources, rewriting cached source files
(`openrouter_models.json` etc.) that then cascade into every derived artifact.
The "before" you diff against is actually post-pull — so of course it differs.

### The isolation recipe (offline, no network)
1. **Revert the working tree to HEAD** for the suspect artifacts:
   `git checkout -- data/ model_registry.json axes_catalog.json processed.js sources/...`.
2. **Run a TRUE offline build by calling the function directly** — bypass the
   CLI subcommand entirely:
   `python -c "import pkg._pipeline as p; p.build_from_cache()"`
   (The function reads committed sources; it does NOT pull.)
3. **Compare each artifact against HEAD by sha**, not by eyeball:
   for f in model_registry.json axes_catalog.json processed.js; do
     [ "$(git hash-object "$f")" = "$(git rev-parse HEAD:"$f")" ] && echo MATCH || echo DIFF; done
   A sha MATCH = byte-identical = the refactor is value-stable.
4. **If the offline build MATCHES HEAD but the working tree still differs**, the
   diff is upstream input drift (a pull), not a code regression. Re-stash the
   accidental pull (`git stash`) and don't commit it — it's reproducible
   intentionally via a full build later.
5. **If the offline build DIFFERS from HEAD on identical committed sources**, THEN
   you have a real regression: the committed artifacts are stale OR the build is
   non-deterministic. Dig into the specific changed field (use `git diff` /
   `json.tool` on the artifact).

### Pitfall — byte-equality checks
Process substitution `<(...)` works on NixOS/Linux. For byte-equality, still
prefer `git hash-object "$f"` vs `git rev-parse HEAD:"$f"` — it is portable and
does not depend on shell process-substitution semantics.

### Path semantics (NixOS/Linux)
All tools — bash builtins, python, git — share the same POSIX filesystem. An
absolute `/home/kei/...` path resolves identically everywhere; there is no
drive-letter vs MSYS `/c/...` split to work around. Pass absolute paths or
`os.path.join` and the "file exists in bash, not in python" class of bug cannot
occur.

### Pitfall — don't conflate "committed artifacts are stale" with "refactor broke output"
If an offline build from committed sources reproduces committed outputs
(byte-for-byte) on a fresh checkout, the committed artifacts ARE consistent;
any difference you saw came from a pull. The fix is to make the CLI
subcommand honor the offline mode (accept `build` AND `build_from_cache`), not
to touch the refactor.

### Pitfall — parse-check tools can flag pre-existing errors as your fault
When a validation tool (`node -e "new Function(src)"`, Python `compile()`, etc.)
reports a parse error on a file you edited, FIRST check whether the same error
exists on `git show HEAD:file` (the pre-edit version). If it does, the error is
pre-existing and not caused by your change — adjust your verification method
instead of "fixing" code that was never broken. Examples:
- `new Function(src)` rejects browser IIFEs that reference browser-only globals
  (e.g., `app()`); use `node --check` for syntax-only validation.
- Python 3.11 `compile()` rejects Unicode characters (e.g., →, …) even in
  comments; use Node's parser for JS validation.
Do not ship a "fix" for a parse error that existed before your edit — you will
corrupt working code or waste cycles chasing a phantom regression.

---

## §5 — Don't inflate a narrow symptom into a bigger bug (band-aid trap)

When the user reports a SPECIFIC, narrow symptom, fix THAT symptom — do not
generalize it into a larger "the whole thing is broken" narrative and ship a
defensive wrapper around it. A 2026-07 session showed the failure mode:

- User said "the legend filter is hidden on load." Agent read it as "the page
  doesn't render on load," built a node stub-DOM harness, found a `parentElement`
  null-crash in ONE viz, and shipped a `safeRender()` wrapper that swallowed ALL
  viz render errors so "one viz can't blank the page." User pushed back:
  "revert and try again… only fix the part and figure out why it wasnt rendering
  in the first place. i never said the page it self was blank." The `safeRender`
  was a band-aid that masked the real (small) bug; the actual root cause was two
  CSS/JS facts: an inline `display:none` on `#creator-legend` that beat the class
  rule, plus `__renderCreatorLegend()` only being called on tab-click, never on
  load. Both were a 2-line fix.

**Rules to avoid this trap:**
1. **Take the user's symptom literally.** If they say "the legend is hidden,"
   investigate the legend — not the whole render pipeline. Do not assume the
   worst-case framing.
2. **A probe that throws is not proof of the user's bug.** A node stub-DOM
   harness (fake `document`, `querySelectorAll` returns `[]`, `cloneNode` returns
   a fresh stub) will throw on code paths a real browser never hits
   (`container.parentElement.querySelector` when the stub has no parent). That
   throw is a PROBE ARTIFACT, not the reported bug. Verify the actual symptom in
   the real environment before concluding.
3. **Don't ship a swallow-and-continue wrapper** (`try/except: log + continue`)
   to "make it robust" unless the user asked for resilience. It hides the real
   error behind a missable log line and converts a findable bug into a silent
   half-broken page. Fix the specific crash.
4. **After a revert, re-apply only the genuine fix** that was bundled in the
   reverted commit — don't drop a legitimate bug fix just because it rode along
   in a commit you were told to revert.
5. **Confirm the fix matches the symptom's scope.** If the user pointed at the
   legend and your fix touches 5 render functions, you probably over-reached.
6. **Do NOT invent a symptom the user never reported.** If the user says "the
   legend filter is hidden on load," that is the bug — do NOT reframe it as "the
   page is blank / not rendering on load" and start hunting a phantom load-time
   crash. Investigate EXACTLY what they described. A 2026-07 session reframed
   "legend hidden" → "page not rendering on load," built a harness, and shipped a
   `safeRender` boot-resilience wrapper for a bug the user never claimed existed.
   The user reverted it. The literal symptom was the real bug; the imagined one
   was a waste of a commit. When in doubt, restate the user's exact words as your
   investigation target before touching code.



## §2 — Python Debugging (pdb + debugpy)

Three tools, picked by situation:

| Tool | When |
|------|------|
| `breakpoint()` + pdb | Local, interactive, simplest. Add `breakpoint()` in source, run normally. |
| `python -m pdb` | Launch under pdb with no source edits. |
| `debugpy` | Remote / headless / attach to running process. |

**Start with `breakpoint()`.**

### pdb Quick Reference

At the `(Pdb)` prompt:

| Command | Action |
|---------|--------|
| `n` | next line (step over) |
| `s` | step into |
| `r` | return from current function |
| `c` | continue |
| `unt N` | continue until line N |
| `j N` | jump to line N |
| `l` / `ll` | list source / full function |
| `w` | where (stack trace) |
| `u` / `d` | move up/down in stack |
| `a` | print args of current function |
| `p expr` / `pp expr` | print / pretty-print |
| `display expr` | auto-print on every stop |
| `b file:line` | set breakpoint |
| `b func` | break on function entry |
| `b file:line, cond` | conditional breakpoint |
| `cl N` | clear breakpoint N |
| `tbreak file:line` | one-shot breakpoint |
| `!stmt` | execute arbitrary Python |
| `interact` | full Python REPL in current scope |
| `q` | quit |

### Recipes

**Recipe 1 — breakpoint()**
```python
def compute(x, y):
    result = some_helper(x)
    breakpoint()           # <-- drops into pdb here
    return result + y
```
Run normally. Don't forget to remove `breakpoint()` before commit: `rg -n 'breakpoint\\(\\)' --type py`

**Recipe 2 — python -m pdb (no source edits)**
```bash
python -m pdb path/to/script.py arg1 arg2
(Pdb) b path/to/script.py:42
(Pdb) c
```

**Recipe 3 — pytest debugging**
```bash
# Drop to pdb on failure
pytest --pdb -k test_name -v

# Step into pytest during the test
python -m pytest --trace -k test_name -v

# pdb on failure only (hermes test runner style)
pytest -x --tb=long --showlocals -k test_name -v
```

**Recipe 4 — debugpy remote attach**
```bash
# Start with debug server
python -m debugpy --listen 0.0.0.0:5678 --wait-for-client myscript.py

# Then attach (separate terminal)
python -m debugpy --connect localhost:5678 myscript.py
```

**Post-mortem debugging:**
```python
import sys, pdb
try:
    run()
except Exception:
    pdb.post_mortem(sys.exc_info()[2])
```

---

## §3 — Node.js Debugging (node inspect)

Two tools:
- **`node inspect`** — built-in, zero install, CLI REPL. Prefer this first.
- **`ndb` / CDP** — scriptable; best for automating many breakpoints or non-interactive debugging.

### `node inspect` REPL

```bash
node inspect path/to/script.js
# or with tsx
node --inspect-brk $(which tsx) path/to/script.ts
```

At the `debug>` prompt:

| Command | Action |
|---------|--------|
| `c` / `cont` | continue |
| `n` / `next` | step over |
| `s` / `step` | step into |
| `o` / `out` | step out |
| `pause` | pause running code |
| `sb('file.js', 42)` | set breakpoint |
| `cb('file.js', 42)` | clear breakpoint |
| `breakpoints` | list all |
| `bt` | backtrace (call stack) |
| `list(5)` | show source around current position |
| `watch('expr')` | evaluate on every pause |
| `repl` | drop into REPL in current scope |
| `exec expr` | evaluate expression once |
| `restart` | restart script |
| `.exit` | quit |

### Attach to Running Process

```bash
# Send SIGUSR1 to enable inspector
kill -SIGUSR1 <pid>

# Attach
node inspect -p <pid>
# or by URL
node inspect ws://127.0.0.1:9229/<uuid>
```

### CDP Script (chrome-remote-interface)

```javascript
const CDP = require('chrome-remote-interface');
async function debug() {
    let client;
    try {
        client = await CDP({host: '127.0.0.1', port: 9229});
        const {Debugger, Runtime, Profiler} = client;
        await Debugger.enable();
        await Debugger.setBreakpointByUrl({url: 'file.js', lineNumber: 42});
        Debugger.paused(async (params) => {
            const {callFrames} = params;
            for (const frame of callFrames) {
                console.log(frame.functionName, frame.location);
            }
            await Debugger.resume();
        });
        await Runtime.runIfWaitingForDebugger();
    } finally { if (client) await client.close(); }
}
debug();
```

### CPU Profile / Heap Snapshot

```bash
node --inspect script.js
# Then connect with Chrome DevTools or ndb:
ndb -- cpu-profile node --inspect-brk script.js
```

---

## §6 — Config and settings maintenance: study the original working version first

When fixing configuration code (Wezterm, editor configs, build configs, etc.) that has been working for a long time, the TODO list or bug report is not the complete picture. The user's actual usage may rely on behavior that a bug report describes as a "bug" to fix.

### Why this matters
A "bug" flagged in a TODO may be a feature from the user's perspective — behavior they rely on daily. "Fixing" it without understanding the original intent breaks the user's workflow. The original code achieved what the user wanted for a reason; find that reason before changing it.

### Procedure
1. **Find the original working version** — `git log --oneline`, `git show <commit>:path/to/file`
2. **Understand what the user actually uses** — look at user config files (`user.json`, settings files), feature flags, and how the user describes their "preferred" setup
3. **Identify the real issue** — separate "this is a bug to fix" from "this is a behavior the user relies on"
4. **Make changes that preserve working behavior** — add new features as enhancements, not replacements for working behavior

### Pitfall — defaulting to the TODO list without checking user config
The TODO list may flag a behavior as a bug, but the user's config may explicitly enable that behavior. Always check the user's actual config files (`user.json`, settings, feature flags) before assuming a behavior is unwanted.

### Pitfall — "fixing" a bug that is actually a feature
If a behavior has been working for the user for a long time, it is probably a feature, not a bug. Before "fixing" it, understand why the user relies on it. The fix may be to make the behavior configurable, not to remove it.

