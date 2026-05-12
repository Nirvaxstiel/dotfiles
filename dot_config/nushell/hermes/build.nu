source ../.common.nu

def hermes-build [
    --pull
    --dry-run
    --no-prune
] {
    let build_cmd = ["docker" "build" ...(if $pull { ["--pull"] } else { [] }) "-t" "hermes-dev" "."]
    _run-or-dry-run $build_cmd $dry_run

    if not $no_prune {
        _run-or-dry-run ["docker" "builder" "prune" "-f" "--filter" "type!=exec.cachemount"] $dry_run
    }
}