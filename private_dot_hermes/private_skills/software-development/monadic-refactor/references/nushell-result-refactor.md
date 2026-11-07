# Nushell Result-refactor recipe (concrete, copy-modify)

From the real nushell-dotfiles refactor (hermes dev/panic/build + maid). The
monadic seam = pure spec builders (no side effects) split from the effect
runner. This file is a worked starter, not a mirror of upstream nu docs.

## Result monad (lib/result.nu)
```nu
def ok [val?: any] { { ok: true, val: $val, err: null } }
def err [e?: any] { { ok: false, val: null, err: $e } }
def result-is-ok [r: record] { $r.ok == true }
def result-is-err [r: record] { $r.ok == false }
def map [r: record, fn: closure] { if ($r.ok == true) { ok (do $fn $r.val) } else { $r } }
def bind [r: record, fn: closure] { if ($r.ok == true) { do $fn $r.val } else { $r } }
def unwrap-or [r: record, default: any] { if ($r.ok == true) { $r.val } else { $default } }
```
NOTE: `is-ok`/`is-err` are builtins (method form) - do NOT redefine; use
`result-is-ok`/`result-is-err`. Closures need `do`: `(do $fn $r.val)`.

## Pure arg builders (lib/cmd.nu)
```nu
def flag [parts: list<string>, cond: bool, name: string] {
    if $cond { $parts | append $name } else { $parts }
}
def opt [parts: list<string>, value: any, name: string] {
    if ($value | is-not-empty) { $parts | append $name | append $value } else { $parts }
}
def build [...segments: list<string>] { $segments | flatten }
```
Pipe `append`/`flatten` (builtins) freely; call `flag`/`opt` EXPLICITLY with
the list as first arg - piping into a custom def misbinds on this nu version.

## Effect runner returns Result (hermes/run.nu pattern)
```nu
def _run-or-dry-run [cmd: list<string>, dry_run: bool] {
    print ""; print "RANA"; print ($cmd | str join " "); print ""
    if $dry_run { return (ok $cmd) }
    try { ^$cmd.0 ...($cmd | skip 1); ok $cmd }
    catch { |e| err { msg: $e.msg, exit_code: ($e | get exit_code?) } }
}
```
Then `hermes-dev` = resolve engine -> `dev-spec $engine ...` -> `_run-or-dry-run
$spec $dry_run | ignore` (the public fn swallows the Result; lib fns return it).

## Test harness (tests/harness.nu)
```nu
def assert-equal [got: any, want: any] {
    if ($got | to nuon) != ($want | to nuon) {
        error make { msg: $"assert-equal FAILED\n  got:  ($got | to nuon)\n  want: ($want | to nuon)" }
    }
}
def assert-true [cond: bool] { if not $cond { error make { msg: "assert-true FAILED" } } }
def assert-is-ok [r: record] { if not ($r.ok == true) { error make { msg: $"err: ($r|to nuon)" } } }
def assert-is-err [r: record] { if not ($r.ok == false) { error make { msg: $"err: ($r|to nuon)" } } }
```

## Test suite + runner (tests/run.nu)
Each domain file ends with `let <domain>_test = [ {name, run:{...}} ... ]`
(NOT a trailing `$cases` expression). Runner:
```nu
source ./harness.nu
source ./result_test.nu   # defines $result_test
source ./cmd_test.nu      # defines $cmd_test
let all = ($result_test ++ $cmd_test)
mut results = []
for case in $all {
    let r = try { do $case.run; {name:$case.name, ok:true} } catch {|e| {name:$case.name, ok:false, msg:$e.msg} }
    $results = ($results | append $r)
}
let passed = ($results | where ok == true | length)
let failed = ($results | where ok == false | length)
# print + `if $failed > 0 { exit 1 }`
```
KEY: never assign to a `mut` inside `catch` (capture-of-mutable-variable
error). Collect into a list, derive counts after. Run with
`nu tests/run.nu` from repo root; use native `C:/...` paths for `source`.

## Behavior-preservation gate
Capture the OLD dry-run output (`hermes-dev dashboard --insecure --dry-run`),
refactor, then assert the NEW spec vectors match the baseline list exactly
(`assert-equal $spec [docker run --rm -it ...]`). The pure specs make this a
plain value comparison - no docker execution needed.
