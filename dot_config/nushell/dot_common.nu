def _run-or-dry-run [cmd: list<string>, dry_run: bool] {
    print ""
    print ""
    print ($cmd | str join " ")
    print ""
    if not $dry_run { ^$cmd.0 ...($cmd | skip 1) }
}

def path-slug [len: int = 4] {
    let p = pwd | path expand
    let base = ($p | path basename | str replace -r -a '[ .]' '-')
    let id = ($p | hash md5 | str substring 0..$len)
    $"($base)-($id)"
}