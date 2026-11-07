# Pipeline Orchestration Idiom & Drift Diagnosis

## The ONE orchestrator: `Pipeline(ctx).then(name, fn).run()`

The repo ships `data/_pipeline.py` with a `Pipeline` class used at the top level. **Reuse it everywhere** — Python inner stages import it; JS ports it. Do NOT invent a second pattern for stage composition.

### Why the other patterns were rejected (user directive, repeated)
- `pipe()` / `do()` from `data/_result.py` — user rejected fusing stages via these ("no pipe()/do() fusion"). `_result` stays the *value-level* Result/Either primitive only (`ok` / `err` / `fromFn`).
- A `steps` tuple + manual `for` loop (`for name, fn in steps: r = fn(); if r.is_err(): return err(...)`) — user called it "ugly" and "inconsistent" vs `Pipeline`. It hand-reimplements the short-circuit `Pipeline` already provides.
- The `for step in (...)` guard-loop that threads a `state` dict (older `_build_registry.run`) is acceptable, but to keep ONE unambiguous idiom prefer `.then().run()`.

### Python usage
```python
from _pipeline import Pipeline
from _result import ok, err

def run(ctx=None):
    pipeline = (Pipeline({"engine": ProjectionEngine(), "js_path": str(BASE / "processed.js")})
        .then("project_rows", lambda c: ok(_project_rows(c["engine"], _PROJECTION_AXES)))
        .then("normalize_radar", lambda c: ok(_normalize_radar_scores(c["project_rows"]) or c["project_rows"]))
        .then("payload", lambda c: ok(_build_payload(c["project_rows"])))
        .then("write_js", lambda c: _write_js(c["js_path"], c["wrapper"])))
    pipeline.run()
    if pipeline.ctx.get("_failed_step"):
        return err(pipeline.ctx["_error"])
    return ok(pipeline.ctx["payload"])
```

Each `then(name, fn)`:
- `fn(ctx)` receives the shared ctx dict, returns a `Result` OR a plain value (auto-coerced via `ok()`).
- The returned value is **unwrapped** and stored at `ctx[name]`. So `ctx[name]` is NEVER a `Result` — it's the inner value.
- On a returned `Err` or a thrown exception, `run()` sets `ctx["_failed_step"]` + `ctx["_error"]` and returns the ctx early (short-circuit). The caller checks `ctx.get("_failed_step")`.

`Pipeline.run()` itself wraps thrown exceptions into `ctx["_failed_step"]` — that is correct error *capture*, not "raise for control flow." Expected failures return `Err`; only a genuine bug raises (a crash, not a result).

### Gotchas (all hit in one session)
1. **Don't double-wrap the terminal value.** Because `then` unwraps, `ctx[final]` is already the plain value. Return `ok(pipeline.ctx[final])` — NOT `ok(ok(...))`. A terminal step returning `ok(x)` leaves `ctx[final] = x` (unwrapped), so `ok(ctx[final])` is correct and single-wrapped.
2. **Unpack tuples at the step, not in ctx.** A step returning `ok((a, b))` stores `(a, b)` as `ctx[name]`. If downstream steps need `a` and `b` separately, return only what the next step needs (`lambda c: _compute_pairs(...)[0]`) and let the sibling ride along via another step's stored value — don't read `ctx["name"][0]` inside a later `.then`.
3. **Steps that can't fail may return plain values** (e.g. a pure transform returning a dict, or `_write_axes_catalog` returning `ok({...})`). Either is fine — `then` coerces. For uniformity, prefer `ok(...)` at stage boundaries; plain value inside a pure helper.

### JS port (`viz/_result.js` -> `window.Result.Pipeline`)
```javascript
function Pipeline(ctx) {
  const self = {};
  self.ctx = ctx || {};
  self._steps = [];
  self.then = function (name, fn) { self._steps.push({ name, fn }); return self; };
  self.run = function () {
    for (const step of self._steps) {
      let returned;
      try { returned = step.fn(self.ctx); }
      catch (e) { self.ctx._failed_step = step.name; self.ctx._error = e; return self.ctx; }
      const result = returned && typeof returned.isErr === 'function' ? returned : ok(returned);
      if (result.isErr()) { self.ctx._failed_step = step.name; self.ctx._error = result.error; return self.ctx; }
      self.ctx[step.name] = result.unwrap();
    }
    return self.ctx;
  };
  return self;
}
```
Usage in `viz/_boot.js` — each step is a named function `(ctx) => Result`, mirroring the Python stage shape; `render()` internals in viz files stay untouched:
```javascript
const { ok, err } = window.Result;
const pipeline = window.Result.Pipeline({})
  .then("bootstrap_models", bootstrapModels)
  .then("build_shell", buildShell)
  // ...
  .then("repo_links", renderRepoLinks);
pipeline.run();
if (pipeline.ctx._failed_step) console.error(`boot failed at ${pipeline.ctx._failed_step}: ${pipeline.ctx._error}`);
```

## Verifying a refactor is value-stable (no data change)
When you refactor orchestration/plumbing, prove the generated artifacts are unchanged:

1. **Use the TRUE offline build.** The determinism test (`tests/test_pipeline_determinism.py`) calls `build_from_cache(ctx)` as a *function* (skips the network pull). Rebuild and compare artifact shas:
   ```bash
   git checkout -- data/sources/openrouter_models.json   # ensure committed source
   PYTHONPATH=data python -c "import data._pipeline as p; p.build_from_cache()"
   for f in data/model_registry.json data/axes_catalog.json data/processed.js; do
     [ "$(git hash-object $f)" = "$(git rev-parse HEAD:$f)" ] && echo "MATCH $f" || echo "DIFF $f"
   done
   ```
2. **Confirm the source cache is NOT rewritten.** A correct offline build must leave `data/sources/*.json` untouched. If `git diff --stat data/sources/` is non-empty after the build, the build pulled/source-wrote — your "offline" path was wrong (see trap below).
3. **Avoid MSYS process-substitution with `diff`.** On Windows git-bash, `diff -q "$f" <(git show HEAD:"$f")` can report a false DIFFERS. Use `git hash-object` vs `git rev-parse HEAD:"$f"` instead (as above).

### Trap: CLI subcommand that silently pulls
`python -m data._pipeline build_from_cache` did NOT run the offline build — the `__main__` arg gate only matched the literal `"build"`, so any other arg (incl. `build_from_cache`) fell through to the full `build()` (live network pull). That rewrote `openrouter_models.json` with new upstream models and cascaded into every derived artifact, looking like "the build produces different values." Fix: accept both `"build"` and `"build_from_cache"` as the offline path; anything else runs the pull. Always verify the source cache is untouched after a "cache" build.

## Diagnosing "the output JSONs differ from before"
User says render tests produce different JSON values. Two causes:

- **(A) Code regression** — your refactor changed transform logic. Signature: source cache files (`openrouter_models.json`, `aa_*.json`) are UNCHANGED, but derived artifacts (`model_registry.json`, `axes_catalog.json`, `processed.js`) differ after an offline rebuild. -> bisect the stage / check the `Pipeline` steps.
- **(B) Input/source drift (live pull)** — signature: a SOURCE cache file changed (new models, repriced fields, removed models). This cascades into all derived artifacts. The values are real upstream changes, not your code. -> Confirm by offline-rebuilding from committed sources (recipe above): if outputs then MATCH committed, the diff was pure input drift.

In one session the cause was (B): an accidental live pull fetched GPT-5.6 models + repriced deepseek/minimax/moonshot, changing `openrouter_models.json` and cascading. The refactor was provably value-stable (byte-identical offline rebuild). The fix was a CLI-arg-gate bug, not a data bug.
