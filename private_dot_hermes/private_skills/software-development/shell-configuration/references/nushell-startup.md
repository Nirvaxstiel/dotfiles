# Nushell Startup & Autoload Reference

## Startup boundaries

| Concern | Store or run it here | Reason |
|---|---|---|
| Environment variables required before config evaluation | `env.nu` | Loaded first; keep side-effect free beyond environment setup. |
| Repository-owned modules and commands | `$nu.default-config-dir` | Nushell's config root is stable regardless of `$PWD`. |
| Generated integrations | `$nu.data-dir/vendor/autoload/*.nu` | Nushell loads vendor autoload files automatically during interactive startup. |
| Non-essential cache | `$nu.cache-dir` | Do not make startup depend on a cache file existing. |

Nushell's `source` keyword resolves files while parsing. Use a constant path expression:

```nu
source ($nu.default-config-dir | path join "lib" "commands.nu")
```

Avoid `source ./module.nu` in a config that may be loaded from another directory. Avoid sourcing a vendor-autoload file explicitly after moving it into an autoload directory.

## Load-path rules

`source` is parse-time. Resolve repository-local modules from the config directory:

```nu
source ($nu.default-config-dir | path join ".common.nu")
source ($nu.default-config-dir | path join "lib" "result.nu")
```

Use `$nu.data-dir/vendor/autoload` for generated vendor integrations. Nushell loads `.nu` files there during normal startup. Do not explicitly source the same generated file from `config.nu`, or it can load twice. Keep generated output outside version control when it is machine-specific.

## Explicit refresh pattern

Keep `env.nu` and `config.nu` side-effect-light. Put generators behind a command that creates the destination directory and writes every generated file:

```nu
def refresh-integrations [] {
    let autoload_dir = ($nu.data-dir | path join "vendor" "autoload")
    mkdir $autoload_dir | ignore
    tool init nushell | save --force ($autoload_dir | path join "tool.nu")
    print "integrations refreshed; restart Nushell to load them"
}
```

Verify refresh and startup separately:

```bash
nu --config C:/path/to/nushell/config.nu -c 'refresh-integrations'
sha256sum vendor/autoload/*.nu
nu --config C:/path/to/nushell/config.nu -c exit
sha256sum vendor/autoload/*.nu
```

The two hash sets must match after startup. Run refresh only when a tool, its config, or its generated format changes.

## Effect-path probes

A builder test does not exercise command execution. Add or run one probe per changed boundary:

```nu
nu --no-config-file -c 'source C:/path/to/nushell/.maid/init.nu; let targets = [{name: demo update: {|| error make {msg: "update failed"}} clean: {|| print "CLEAN-RAN"}}]; maid-update-all $targets'
```

Expected output contains the update failure and no `CLEAN-RAN`. This catches ignored Results, unconditional dependent cleanup, and runtime interpolation errors.

Nushell interpolated strings use parentheses for expressions. Literal text such as `target(s)` can be parsed as a command substitution when evaluated. Prefer `targets` or escape the literal parentheses, then execute the branch that contains the string.

## Result variant shape

Use one constructor per variant and one discriminator:

```nu
def ok [value: any] { { kind: "ok", value: $value } }
def err [error: any] { { kind: "err", error: $error } }
```

Migrate all consumers and tests in one pass. Search for old fields after changing the shape; a missed `.val`, `.err`, or `.ok` can survive parsing until a specific failure path runs.

## Refresh recipe (summary)

Keep generator calls behind an explicit command. The command should:

1. Create `$nu.data-dir/vendor/autoload`.
2. Generate each integration into a named file with `save --force`.
3. Fail loudly when an expected executable is missing or generation fails.
4. Tell the user to restart Nushell, because newly written autoload files are not retroactively parsed into the current session.

Use a hash probe to prove normal startup is read-only:

```text
hash generated files
start Nushell with config
hash the same files
compare hashes
```

## Path verification

For tests that build command vectors, derive expected paths from `$nu.default-config-dir` or `$nu.data-dir`. A literal `.` can pass only when the current directory happens to be the config root, masking a portability defect.

On Windows, pass `C:/...` paths to native programs such as `nu`, `python`, and `git`; MSYS shell builtins can use `/c/...`. Keep path-form conversion at the process boundary instead of changing stored domain paths.

## Security and reproducibility probes

For container argument builders, assert loopback bindings explicitly:

```nu
assert-equal (build-docker docker --dashboard | where $it == "-p" | get 1) "[IP_ADDRESS]:9119:9119"
```

For source builds, let Corepack read the checked-out project's `packageManager` field instead of preparing a moving `latest` version. Add an environment or flag override for the exact source commit when the default resolves a branch head.

## Review checklist

- Does startup rewrite files, call a network endpoint, or run a package manager?
- Are repository sources resolved from config root?
- Are generated files in data/vendor autoload rather than tracked source?
- Are result records discriminated and consumed rather than discarded?
- Do dependent cleanup actions run only after successful updates?
- Are development ports loopback-bound?
- Are package-manager and source revisions pinned or explicitly overrideable?
- Did tests run from a working directory different from config root?
