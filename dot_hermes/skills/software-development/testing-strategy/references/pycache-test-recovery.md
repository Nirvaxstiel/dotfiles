# Recovering Test Structure from `.pytest_cache`

When test `.py` source files are deleted but cached artifacts remain, you can recover the full test structure without decompiling.

## Source of Truth: `nodeids`

The file `.pytest_cache/v/cache/nodeids` contains every test node ID that pytest last discovered, one per line:

```
tests/test_data_contracts.py::TestArchetypes::test_all_archetypes_known
tests/test_data_contracts.py::TestArchetypes::test_no_null_archetypes
tests/test_data_contracts.py::TestBooleanFields::test_has_breakdown_is_bool
...
```

Each line gives: `test_file::ClassName::test_method_name`. This is enough to reconstruct the entire test suite structure — what files existed, what classes, what test cases.

## Recovery Procedure

```bash
cat .pytest_cache/v/cache/nodeids | sort | cut -d: -f1 | uniq -c | sort -rn
```

This gives a per-file test count. Group by class:

```bash
cat nodeids | awk -F: '{print $1, $2}' | sort | uniq -c
```

## What You Get Back

| Artifact | Information | Completeness |
|----------|-------------|-------------|
| `nodeids` | Full test names (file::class::method) | Complete — pytest writes all discovered tests |
| `pyc` files | Bytecode — partial structure recovery | Partial — can extract class/method names but not full source |
| `__pycache__/` | Compiled bytecode per file | One file per `.py` source that was imported |

## Limitations

- Test logic (assertions, test bodies) is NOT recoverable from `nodeids` — only test names and structure
- `pyc` files expose function names and class structures but not source code (decompilation from pyc is lossy)
- If tests were parameterized (`@pytest.mark.parametrize`), each parameter combination generates a separate nodeid, making count differ from source-line expectations
- Fixture names and scopes are not recorded in nodeids

## When to Use

- Source `.py` test files were deleted during cleanup but you need to know what was tested
- Test structure was documented in nodeids but source is lost to git history trimming
- You need to rebuild test files from scratch and want the exact class/method structure preserved

## When Not to Use

- The `.py` sources exist — just read them
- Only `__pycache__` exists without `nodeids` — pyc decompilation is fragile, prefer git history recovery
- You need the actual test logic — nodeids won't help there (try `git reflog` or `git fsck`)
