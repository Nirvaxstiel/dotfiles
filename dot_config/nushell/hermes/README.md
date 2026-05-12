# Hermes Agent Setup

## Structure

```
nushell/
├── .common.nu          # Shared utils: _run-or-dry-run, path-slug
├── .hermes-agent.nu    # Entry point: sources run.nu + build.nu
└── hermes/
    ├── Dockerfile      # Custom image (dotnet, roslyn-ls, graphify)
    ├── build.nu        # hermes-build [--pull] [--dry-run] [--no-prune]
    └── run.nu          # hermes-dev, hermes-panic
```

## Quick Start

```nu
source .hermes-agent.nu

hermes-build --pull   # build docker image (run from nushell/ dir)
hermes-dev -p         # interactive chat with auto profile
hermes-dev --dry-run  # inspect command without running
```

## Shared Utils (.common.nu)

```nu
path-slug [len: int = 4]     # deterministic slug: "my-project-a1b2"
_run-or-dry-run [cmd, dry]   # print + exec, or dry-run
```

## hermes-dev

```nu
hermes-dev [command] [args...] [flags]
hermes-dev chat -q "summarize this"
hermes-dev profile list
hermes-dev dashboard
hermes-dev doctor --fix
```

## Flags

| Flag          | Short | Description                           |
|---------------|-------|---------------------------------------|
| `--profile`   | `-p`  | Auto-chat with `dirname-hash` profile |
| `--dry-run`   |       | Print command without executing        |
| `--insecure`  |       | Dashboard: skip TLS                   |
| `--tui`       |       | Use TUI mode                          |
| `--fix`       |       | Doctor: auto-fix issues               |
| `--resume`    | `-r`  | Resume session by name/ID             |
| `--clone`     |       | Profile: clone config from active     |
| `--clone-all` |       | Profile: clone all state              |

## Volume Mounts

| Host                   | Container                        | Purpose            |
|------------------------|----------------------------------|--------------------|
| `$USERPROFILE/.hermes` | `/opt/data`                      | Hermes data dir    |
| `$(pwd)/.hermes`       | `/home/user/projects/<dirname>`  | Per-project data   |
| `/home/user/projects/` | `-w`                            | Default workdir    |

## Profile Naming

`path-slug 4` → `my-project-a1b2`  
`path-slug` (default 4) uses md5 of full path — same name from anywhere in the tree, unique across different paths with identical dirname.

## Custom Image Additions

- .NET SDK 10.0 + ASP.NET 10.0/8.0 runtimes
- `roslyn-language-server` (dotnet tool)
- `graphify` (uv tool, hermes platform)

## Maid Cleanup

Registered in `.maid/catalog.nu` — run `maid -r` to pick them up.

```nu
maid -c -a              # clean + prune everything
maid -c docker          # prune dangling images, builder cache
maid -c hermes          # prune old sessions + checkpoints
maid -u hermes         # update hermes agent + clean
maid -e hermes -f      # doctor --fix
maid -c hermes-img     # rm old hermes-dev image
maid -u hermes-img     # rebuild hermes-dev with --pull --no-prune
```
