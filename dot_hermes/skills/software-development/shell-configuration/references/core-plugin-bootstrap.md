# Nushell core-plugin registration

## Decision: do not register plugins from startup config

Nushell release archives ship `nu_plugin_*` next to the `nu` binary and register none of them, so `plugin list` is empty on a fresh install. That is deliberate, and the fix is a one-shot user step, not a startup hook:

- A nushell maintainer confirms registration is a user step by design: `plugin add` searches only `$env.NU_PLUGIN_DIRS` and never `PATH`, so nothing auto-registers (nushell/nushell#15677).
- Homebrew and the official `.deb`/`.rpm` packages install the plugin binaries and leave registration to the user; `cargo install nu` puts them in `~/.cargo/bin`; Debian's package ships no plugins at all.
- The registry file is user state. Registering from `config.nu` rewrites it during shell startup, turning a deliberate one-shot into a per-launch side effect, for a gain of roughly 10 ms of startup cost on every launch.

Prefer the package manager's own one-shot. For scoop, the manifest writes `register-core-plugins.nu` next to `nu.exe` and prints the instruction; run it once per nu upgrade and restart:

```nu
nu ($nu.current-exe | path dirname | path join 'register-core-plugins.nu')
```

If a config-side bootstrap is genuinely wanted anyway, derive the desired set from the install instead of hardcoding it, and gate on the plugin system existing. The portable rule — the one that works on Windows, macOS, and Linux, and the one the scoop manifest notes use — is *shipped `nu_plugin_*` minus the `example`/`custom_values`/`stress_internals` dev fixtures*. A declared core list (`$core` in a scoop `manifest.json`) is scoop-only and must not be the only source: on other machines it silently falls back to registering the dev fixtures.

## Registration facts (verified on 0.116.0, Windows)

- `plugin add <path>` writes `$nu.plugin-path` (default `<config-dir>/plugin.msgpackz`) and edits only the registry. The commands appear on the **next** launch, so an in-config bootstrap is correct but must print a restart notice.
- `plugin add` canonicalizes the path: adding `...\nu\current\nu_plugin_inc.exe` stores `...\nu\0.116.0\nu_plugin_inc.exe`. Do not compare registered paths against `$nu.current-exe | path dirname` — they will never match.
- `status: loaded` is **not** a health signal. With `nu_plugin_inc.exe` deleted from disk, `plugin list` still reports `loaded` and Nushell prints no error or warning: the command is silently gone. Never gate on status alone.
- A plugin is usable only when all three hold: status is `loaded` or `running`; the recorded `filename` exists on disk; and the recorded `filename` resolves to the same path as the expected binary next to `$nu.current-exe`.
- `path expand` resolves the scoop `current` junction (`...\nu\current\nu_plugin_x.exe` -> `...\nu\0.116.0\nu_plugin_x.exe`). Expand both sides before comparing, then compare exactly. No version heuristics needed.
- Scoop keeps old version directories, so a registry written before an upgrade points at the old directory, passes a file-exists check, and still fails to load. The path-equality clause catches that case; status alone does not.
- `path expand` is total: it does not error on a missing path, and it resolves a relative path against the current directory. Always anchor the comparison on an absolute expected path.
- `plugin add` with a new path **replaces** the entry for that plugin name — it does not append a duplicate. Verified by seeding a registry from a fake old install directory, then registering: the five old-dir entries were rewritten to the current directory with no leftovers.
- Registration is deterministic: registries built from different scratch paths were byte-identical (`sha256sum` equal), so a deleted registry regenerates identically and needs no restore.

## Registry file states

- Absent: the normal fresh-install state. `plugin list` returns an empty list and `plugin add` creates the file. An early `path exists` return here registers nothing, ever.
- 0 bytes: treated as empty, registers normally.
- Corrupt: `plugin list` throws `Failed to load plugin file: Invalid Data`; `plugin add` throws `Error while reading plugin registry file ... you might try deleting the file and registering all of your plugins again`; neither repairs it (it stays corrupt at its old size). Nushell separately prints its own startup error to stderr before any config code runs. If handling this, emit one actionable summary line rather than swallowing it to `[]` and then failing on every add.
- `$nu.plugin-path` is **never empty** and `$nu` is immutable: it resolves on every launch, including `--no-config-file`, an unset `NU_PLUGIN_PATH`, and `--plugin-config` (which replaces the value rather than clearing it). `$nu.plugin-path = x` fails with `needs to be a mutable variable`. Any `if ($nu.plugin-path | is-empty) { return }` guard is dead code.

## Nushell traps hit while building this

- `nu -c` does not load `config.nu`. Verifying any config side effect requires `nu --config <native path> -c ...`; plain `nu -c` skips the config and shows no side effect. `nu --plugin-config <path> -c ...` alone also skips config, so use `--config` and `--plugin-config` together to test against a throwaway registry.
- `glob` fails with `error with glob pattern` on a Windows path: `path join` emits backslashes and glob reads `\` as an escape. Convert first — `glob ($dir | path join "nu_plugin_*.exe" | str replace -a '\' '/')`.
- Nushell's own `ls` does not expand a glob held in a variable: `ls ($dir | path join "*.exe")` fails with `No matches found for DoNotExpand(...)`. Use `glob`, which returns `[]` for no matches where `ls` throws.
- `[] | first` returns null rather than throwing, so `| where {...} | first | is-empty` is a safe probe for a missing line.
- `parse -r "'(?<name>[a-z0-9_]+)'"` extracts a list from a quoted PowerShell array line. In `core-names-from-lines`, a single-quoted nushell string is raw: `'$core = ''polars'''` is how a doubled quote is written inside it.
- Variables cannot use `-`: `let has-command = ...` is a parse error (`expected valid variable name`). Use `has_command`.
- `(version)` has no `columns` in 0.116 and `$nu` has no `version` key. Use `(version).version`.
- `not-in` is not a command in 0.116. Write `not ($x in $list)`.
- `and` is line-scoped. `(a)` then `and (b)` on the next line parses as a new statement and fails with `Command `and` not found`. Keep chains on one line (`$a and $b and $c`) or bind each operand to a `let` first. `&&` is rejected by the parser outright.
- `all [...]` with pipeline elements fails with `expected bool, found list<any>`; element types do not infer. Bind each element to a `let` first.
- `scope commands | where name == "plugin"` is a cheap plugin-system availability probe (no measurable startup cost), and it answers "does this build have the plugin command" without a version check.

## Config-load rules

- Never `error make` from `config.nu`: a throw aborts config loading and leaves a broken shell. Return discriminated records and let the caller print.
- A bare command call whose value is not consumed is echoed into every startup. A reporting facade must print and return nothing; keep the Result-returning function separate for programmatic use and tests.
- Keep `plugin` as the first field of every error record so one uniform `($failure.error.plugin): ($failure.error.msg)` line covers all failures.
- If a bootstrap is kept: cheap check per launch, write at most once, and verify by hashing the registry before and after an ordinary startup — it must not change once every plugin is loaded.

## Verification recipe for a registry-writing change

1. Hash `plugin.msgpackz`, delete it, load the config through `nu --config <native path> -c ...` (not bare `nu -c`). Expect a restart notice and only the intended plugins registered.
2. Confirm the regenerated registry matches the backup hash (registration is deterministic) — then nothing needs restoring.
3. Relaunch twice: silent, every plugin `loaded`, registry hash unchanged.
4. Exercise each branch against throwaway registries via `--plugin-config`: absent, 0-byte, corrupt, stale-path (seed from a fake old install dir).
5. Measure `$nu.startup-time` A/B over several runs and report the spread, not one run. On this config the whole startup is ~145 ms without the call and ~154-170 ms with it: roughly +10 ms from parsing the ~43 KB registry every launch.
6. Gitignore the registry file: `plugin.msgpackz` is generated machine state and belongs with `/vendor` and the maid registry, not in the tracked config.

Pass native forward-slash paths to `nu --config` (`$HOME/.../config.nu`). MSYS `/c/...` paths are not converted and fail with `File not found`.
