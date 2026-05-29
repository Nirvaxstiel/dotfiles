source ../.common.nu
source ./container.nu

def hermes-build [
    --pull
    --dry-run
    --no-prune
    --podman
] {
    let engine = get-container-engine --podman
    let build_cmd = [$engine "build" ...(if $pull { ["--pull"] } else { [] }) "-t" "hermes-dev" "."]
    _run-or-dry-run $build_cmd $dry_run

    if not $no_prune {
        _run-or-dry-run [$engine "builder" "prune" "-f" "--filter" "type!=exec.cachemount"] $dry_run
    }
}