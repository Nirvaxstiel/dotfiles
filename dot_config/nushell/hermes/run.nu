source ../.common.nu

def hermes-dev [
    command?: string
    ...extra_args: string
    --profile (-p)
    --dry-run
    --insecure
    --tui
    --fix
    --resume (-r): string
    --clone
    --clone-all
] {
    let DASHBOARD = "dashboard"
    let host_cwd = pwd | path expand
    let dirname = $host_cwd | path basename
    let slug = (path-slug 4)

    let DATA_VOL = $"-v ($env.USERPROFILE)/.hermes:/opt/data"
    let PROJECT_VOL = $"-v ($host_cwd)/.hermes:/home/user/projects/($dirname)"
    let WORKDIR = "-w /home/user/projects/"

    let dash_ports = if $command == $DASHBOARD {
        ["-p" "9119:9119" "-p" "8642:8642" "-e" "GATEWAY_HEALTH_URL=https://127.0.0.1:8642"]
    } else { [] }

    let PROFILE_CMDS = ["use" "create" "delete" "show" "alias" "rename" "export" "import"]
    let needs_dirname = ($extra_args | any { |arg| $arg in $PROFILE_CMDS })

    let hermes_args = match $command {
        "dashboard" => ["dashboard" "-host" "0.0.0.0" ...(if $insecure { ["--insecure"] } else { [] }) ...$extra_args]
        "doctor" => ["doctor" ...(if $fix { ["--fix"] } else { [] }) ...$extra_args]
        "profile" => ["profile" ...$extra_args ...(if $needs_dirname { ["--needs_dirname"] } else { [] }) ...(if $clone { ["--clone"] } else { [] }) ...(if $clone_all { ["--clone-all"] } else { [] })]
        null => $extra_args
        _ => [$command ...$extra_args]
    }

    let chat_fallback = if $profile and $command != "profile" { ["hermes" "-p" $slug "chat"] } else { [] }
    let flags = [...(if $tui { ["--tui"] } else { [] }) ...(if ($resume != null) { ["--resume" $resume] } else { [] })]

    let cmd = ["docker" "run" "--rm" "-it" $DATA_VOL $PROJECT_VOL $WORKDIR ...$dash_ports "hermes-dev" ...$hermes_args ...$chat_fallback ...$flags]

    _run-or-dry-run $cmd $dry_run
}

def hermes-panic [
    command?: string
    --fix
    --tui
] {
    let cmd = [
        "docker" "run" "--rm" "-it"
        "-v" $"($env.USERPROFILE)/.hermes:/opt/data"
        "nousresearch/hermes-agent"
        $command
        ...(if $fix { ["--fix"] } else { [] })
        ...(if $tui { ["--tui"] } else { [] })
    ]

    ^$cmd.0 ...($cmd | skip 1)
}