# AA build: offline vs pull + determinism verify

## CLI matrix (`data/_pipeline.py`)
The `__main__` gate is `sys.argv[1] == "build"`. Only the bare literal `"build"` (or `"build_from_cache"`) takes the offline path.

| Invocation | Path | Network? |
|---|---|---|
| `python -m data._pipeline build` | `build_from_cache()` | NO — reads committed `data/sources/*` |
| `python -m data._pipeline build_from_cache` | `build_from_cache()` | NO |
| `python -m data._pipeline` (no arg; `arg` defaults to `"build"`) | `build()` | YES — pulls then builds |
| `python -m data._pipeline build_from_cache` **misspelled** / any other token | falls through → `build()` | YES — silent full pull |

**Trap:** `python -m data._pipeline build_from_cache` (the whole word) does NOT equal `"build"` → runs `build()` → live pull of OpenRouter/LiveBench/OpenLLM, rewriting `data/sources/openrouter_models.json` + `model_registry.json`/`axes_catalog.json`/`processed.js`. A "rebuild from cache" that was supposed to be offline will silently fetch upstream and change every JSON. Always use the bare `build` subcommand for offline.

`_pull_sources.py` standalone (`python -m data._pull_sources`) is ALSO a full pull. Its `__main__` had a `NameError` (`s` vs bound `pipeline_state`) — fixed `fdd071c`.

**Running `data.*` modules needs `data/` on `sys.path`.** Several modules do a BARE `from _result import ok` (not `from data._result`). So `python -m data._pipeline` / `python -m data._pull_sources` from the repo root FAILS with `ModuleNotFoundError: No module named '_result'`. Fix: prefix `PYTHONPATH=data` so the bare import resolves:
- Offline build: `PYTHONPATH=data python -c "import data._pipeline as p; p.build_from_cache()"`
- Pull sources: `PYTHONPATH=data python -m data._pull_sources`
(`python -c "import data._pipeline as p; p.build_from_cache()"` from repo root without PYTHONPATH also works because repo root lands on path and `data` is a package — but `python -m data._pipeline` does NOT, because it puts the *parent* on path, not `data/`.)

**Editing pitfall — fuzzy `patch` can corrupt a file with duplicate blocks.** When removing a large block (e.g. a 90-line `AA_IMG_NAME_MAP` + function) via `old_string`/`new_string`, the fuzzy matcher may match only the FIRST occurrence of a shared tail and leave a DUPLICATE of the surrounding structure (e.g. two `DIRAC_NAME_MAP = {` blocks, or the deleted function re-appearing). The result compiles but is logically wrong. If a patch's diff looks smaller than expected or the lint says "unmatched }", revert and redo: `git checkout -- <file>`, re-read the exact boundaries, then patch a PRECISE unique block. Never trust a diff that's suspiciously small.

## Determinism / "values changed" investigation recipe
When the user reports generated JSONs differ from before:
1. `git stash` (or `git checkout -- data/sources/ data/model_registry.json data/axes_catalog.json data/processed.js`) to revert to committed state.
2. Run **offline**: `PYTHONPATH=data python -c "import data._pipeline as p; p.build_from_cache()"`.
3. Compare each artifact to HEAD:
   ```
   git hash-object data/model_registry.json
   git hash-object data/axes_catalog.json
   git hash-object data/processed.js
   ```
   vs `git hash-object HEAD:data/<file>`. Byte-identical = the refactor is value-stable; the diff was input drift (live pull), not code.
4. If the offline build STILL differs from HEAD, the committed artifacts are stale — a real data/logic change. Bisect commits.
5. Revert generated artifacts after probing so the working tree stays at HEAD (`git checkout -- data/...`).

The pytest `tests/test_pipeline_determinism.py` calls `build_from_cache(ctx)` as a **function** (correct, no pull) and asserts byte-identical outputs across two runs.

## Node smoke-test of generated JS (no jsdom)
For new boot/load logic (e.g. `validateSchema` in `_boot.js`): load `processed.js` + `viz/_result.js` + `viz/_domain.js` + `viz/_shared.js` under Node with a minimal DOM stub, run the logic, assert both directions:
- real `PROCESSED_DATA` → `ok`, no false boot failure
- drifted/mistyped input → `err` caught

DOM stub shape (reuse; avoids the Hermes TS-wrapper `eval` quirk by writing a `.js` file and `node`-ing it, not `node -e`):
```js
function el(){const e={innerHTML:'',style:{},textContent:'',dataset:{},classList:{toggle(){},add(){},remove(){},contains(){return false;}},remove(){},addEventListener(){},appendChild(){},insertBefore(){},querySelector(){return el();},querySelectorAll(){return[];},closest(){return el();},getAttribute(){return null;},setAttribute(){},scrollIntoView(){};e.parentElement=e;return e;}
const doc={getElementById:()=>el(),querySelector:()=>el(),querySelectorAll:()=>[],addEventListener(){},createElement:()=>el()};
const win={document:doc,setTimeout:f=>f(),console};win.requestAnimationFrame=f=>f();
function loadInto(p){new Function('window','document','setTimeout','requestAnimationFrame',fs.readFileSync(p,'utf8'))(win,doc,win.setTimeout,win.requestAnimationFrame);}
```
**Gotcha:** `createSVGPoint`/object-literal stubs with nested `return {...}` inside an object literal often break the MSYS `node -e` wrapper — write the harness to a temp `.js` file and run `node temp.js` instead. Always `rm` the temp file after.

**Null-aware type checks:** many `ProjectionRow` fields are null by design (e.g. `intel` is null for models without IQ — ~86/117). A `typeof x.intel !== 'number'` check false-positives and would block boot. Type-check only **present, non-null** values: `(x.intel != null && typeof x.intel !== 'number')`.
