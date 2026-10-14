# Verify a behavior-preserving refactor (Hermes LSP + git-stash diff)

## 1. LSP clean check (automatic)
`write_file` / `patch` return a `lint` field — `"status": "ok"` means pyright
(Python) / typescript-language-server (JS) found no diagnostics. You do NOT
call `pyright` in the terminal; it isn't a CLI in this environment. To confirm
the servers exist: `hermes lsp status` (look for `✓ pyright` / `✓ typescript`).

If `lint.status` != "ok", the edit introduced an undefined name / type error
that manual grep would have missed — fix it before committing.

## 2. Behavior-preservation diff (git stash round-trip)
Run OLD code, capture output, run NEW code, diff. Works without a separate
fixture because the real build IS the test.

```bash
cd "<repo>"
# stash ONLY the refactored file
git stash push -q -- data/foo.py
python -u -c "import sys; sys.path[...]; import data.foo as f; f.build(); \
  import json; json.dump(load('data/out.json'), open('before.json','w'))"
git stash pop -q
python -u -c "import sys; sys.path[...]; import data.foo as f; f.build(); \
  import json; a=json.load(open('before.json')); b=json.load(open('data/out.json')); \
  print('match' if a==b else 'MISMATCH')"
rm -f before.json
```

### MSYS /tmp caveat
On this Windows+MSYS host `/tmp` does NOT persist across separate `terminal`
calls (each call is a fresh session). Write comparison artifacts INTO the repo
dir (e.g. `before.json`) and delete them after — never `/tmp/before.json`.

### Strong first signal
If the generated artifact is byte-identical in size before vs after
(`wc -c`), behavior is almost certainly preserved; the JSON content diff is the
confirmation step.

## 3. Import-path gotcha when importing the refactored module standalone
Modules under `data/` use relative imports (`from ..._canonical import ...`).
Importing `data/sources/aa/_build.py` directly as a top-level module raises
`ImportError: attempted relative import beyond top-level package`. Always drive
the check through the real entry point (e.g. `data._build_registry.run(...)`),
which imports the target correctly — compare the registry's model count /
source coverage before vs after.
