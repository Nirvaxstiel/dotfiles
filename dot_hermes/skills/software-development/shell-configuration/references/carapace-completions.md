# Carapace + Nushell External Completions

## When to Use

Load this when reviewing, configuring, or debugging shell completion in a Nushell setup that uses an external completer (carapace, fish, or a hand-written closure), and whenever a refresh/patch command writes a generated integration file.

The external completer is a configuration surface with its own contract, its own generation artifact, and a version-coupled patch step. Review all three, not just the generated file.

## Contract (Nushell 0.116)

- `$env.config.completions.external` is the record `{enable, max_results, completer}`. Defaults: `enable: true`, `max_results: 100`, `completer: null`.
- The completer declares the inputs it wants by naming positional parameters — `token`, `place`, `buffer`, in any order. `{|place| carapace ($place.command | first) nushell ...$place.command | from json}`; `$place.command` is the token list of the command at the cursor and `place` also carries `cursor`, `target`, `kind`, `index`, `flag`, `shape`. Results are records with `value` (plus optional `display`, `description`, `style`). `null` declines and falls back to file completion.
- `{|spans| ...}` still binds but raises `nu::shell::deprecated` and the bridge will be removed. `$place.command` replaces `spans` exactly — and Nushell has already expanded alias heads inside it, so do **not** re-implement alias expansion: a manual first-word rewrite passed `gco mai` to carapace as `git mai` instead of `git checkout mai`.
- Carapace's own generated integration still declares `spans`, so it is the deprecated side of this change. Owning the completer in the config moves ahead of upstream rather than waiting for it.
- Load order is `env.nu` → `config.nu` → `vendor-autoload-dirs` → `user-autoload-dirs` → `login.nu`. Vendor autoload runs **after** `config.nu`, which is why the generated file only installs the completer when the slot is empty (`| upsert completer { if $in == null { $carapace_completer } }`) and why a completer set in `config.nu` wins. `nu -c` and `nu --no-config-file` skip vendor autoload: source the generated file explicitly to test it.
- Menu behavior is not under `completions`. Layouts live in `$env.config.menus`; default bindings are `tab` → `completion_menu`, `ctrl+space` → `ide_completion_menu`, `shift+backtab` → `completion_previous`, `ctrl+x` / `ctrl+z` page. Default `completion_menu` is `columns: 4, col_width: 20`, so carapace descriptions clip; `ide_completion_menu` (`layout: ide`, `description_mode: prefer_right`) shows them wider.
- Nushell does not re-run external results through `completions.algorithm` (`prefix` by default). Carapace filters internally — use `CARAPACE_MATCH` for case behavior.
- `completions.external.max_results` truncates real result sets. Probe the biggest commands before assuming the default is enough.

## Generated-integration drift

Owning the completer in the config is the durable fix; the patching technique below is for configs that already carry such debt, and for reading whether an installed generated file is current.

`carapace _carapace nushell` output is version-coupled to the carapace build and changes shape between releases: the wrapper, the shell-context variables it exports, and where emptiness is handled all move. A patch function that rewrites that text with `str replace` is coupled to the same shape, and `str replace` returns its input unchanged on a miss — so a carapace upgrade silently stops applying the patch while the refresh command still claims success.

Rules:

- On every carapace upgrade, diff fresh output against the installed autoload file before concluding the config is current:
  ```bash
  carapace _carapace nushell > fresh.nu
  diff "$NU_CONFIG_DIR/vendor/autoload/carapace.nu" fresh.nu
  ```
  The installed file's mtime relative to the patch commit and to the installed carapace version is the cheapest drift signal.
- Assert each patch changed the text. Run the refresh pipeline into a second file and diff it against the raw generator output; an empty diff is a failure, not a no-op.
- Re-derive regexes from the current template, and check whether a guard patch is still needed before porting it forward. In 0.116, empty carapace output yields `null` with no throw, so an `is-empty → null` guard patch is unnecessary; upstream's own `($spans | length) == 1 → null` guard covers the single-span case.
- Keep the patched text minimal and version-independent where possible; a patch that only strips a line is cheaper to maintain than one that rewrites a closure.

## Verification commands

| Question | Command |
|---|---|
| Which commands have a spec? | `carapace --list` — JSON keyed by completer name; match `"name": [` |
| Does one command complete? | `carapace git nushell git checkout ""` → JSON array |
| How large can a result set get? | pipe the same call into `python -c "import json,sys;print(len(json.load(sys.stdin)))"` |
| Does the completer fall back on no match? | drive the closure with an unknown command; expect `null`, not an error |
| What record will the completer receive here? | `'git checkout mai' | commandline complete --input` |
| Is the completer wired into the engine? | `'docker run --' | commandline complete | length` — non-zero proves the configured external completer is reached |
| Where are carapace's own dirs? | `carapace --help` prints the cache dir, config dir, and specs dir |

`carapace --list` is JSON, not a flat name list: a `grep -x <name>` over it returns zero for every command and looks like "no specs installed". Match the `"<name>": [` shape instead.

## Environment knobs

| Variable | Effect |
|---|---|
| `CARAPACE_BRIDGES` | Fallback completions from other shells / frameworks. Set only for shells that exist on this machine — a bridge for a missing shell is inert and still implies those completers exist. |
| `CARAPACE_LENIENT=1` | Keep completing after an unknown flag. Without it one typo kills completion for the rest of the line. |
| `CARAPACE_HIDDEN=1` | Show hidden commands and flags (`2` includes `_carapace`). |
| `CARAPACE_MATCH=1` | Case-insensitive matching. |
| `CARAPACE_UNFILTERED=1` | Skip carapace's final filtering step. |
| `CARAPACE_NOSPACE`, `CARAPACE_MERGEFLAGS`, `CARAPACE_EXCLUDES` | Suffix handling, flag grouping, exclude internal completers. |
| `CARAPACE_LOG=1` | Log completions when a result looks wrong. |

## Completion sources for your own binaries

When `carapace --list` has no entry for a tool, pick in this order:

1. A carapace spec file in carapace's own specs directory (`carapace --help` prints it). Author with `--schema` / `--codegen`, probe with `--run` and `--diff`. Keeps one completion engine and one source of truth — see the spec-file rules below. A carapace spec only ever describes external binaries; for your own Nushell `def`, use option 3 instead. Store the spec recipe on that tool's existing registry entry (a `spec` action alongside its clean/update/audit closures) rather than in a completion-specific tool list, and drive the refresh from the catalog rather than the detected registry. The generator interrogates the CLI, so gate it on the local CLI being present.
2. The tool's own generator (`mytool completion nushell|fish|bash`), bridged rather than hand-written.
3. `extern` plus a `nu-complete` function in Nushell, attached with `@`. Correct Nushell, but it introduces a second engine alongside carapace.

### Spec file rules

- Place the file in carapace's specs directory (normally `<UserConfigDir>/carapace/specs`) and name it `<name>.yaml` to match the spec's `name`. Carapace's loader registers only names matching `^[a-zA-Z0-9_\-.]+\\.yaml$`, so a `.json` spec is ignored with no message at all — verify registration with `carapace --list | grep '"<name>"'` instead of trusting the file's existence.
- Shape: `{name, description, flags, commands}`. `flags` maps every spelling separately (`-q` and `--query` are two keys) to either a description string or `{description, nargs}`; `commands` nests the same shape. `nargs: 1` is what makes carapace expect — and complete — a value after the flag.
- Specs are read when `carapace` runs, so a new completion works on the next invocation; an already-registered file picks up edits immediately.

### Generating a spec from an argparse CLI

An argparse program exposes no machine-readable tree, so derive it from `--help`, parsing the `positional arguments:` and `options:` sections:

- Subcommands are the entries *under* a group line: `{a,b,c}`, `<command>`, or an all-uppercase metavar (`COMMAND`). The same section also lists plain positional arguments at the same indent (`message   Message text...`); treating those as subcommands invents names that do not exist, and the follow-up `tool <bogus> --help` exits non-zero and aborts the whole build.
- Separate them by indentation: the group line sits at 2-4 spaces and its choices deeper. Require candidate names to match `^[a-z0-9][a-z0-9-]*$` as a final guard.
- Continuation lines are the deeper-indented ones; join them onto the first line or the description silently loses its opening clause.
- argparse prints the metavar only on the last spelling, so derive `nargs` from the entry, not the alias: `-q, --query QUERY` means `-q` takes a value too.
- Spot-check the parse against raw help before trusting the spec: compare parsed choices with the names listed in the section for commands with many subcommands. Parsed == listed everywhere is the gate; a mismatch means the group rule is too loose or too strict.
- One `--help` call per command is the bulk of the cost (~1.7 s for a Python CLI, so ~400 commands take ~100 s). Fan the levels out with `par-each` over an explicit work list — collect one level, then fan out the next — rather than nesting `par-each`.

## Cost of a tab press

On Windows each spawn costs roughly 100 ms, and the generated completer rebuilds shell context (`help commands`, `scope aliases`, `scope variables`) on every invocation, then spawns carapace. Measure both parts (`carapace --version` vs the real completion call) before blaming carapace; a scoop shim adds a process hop over the real executable, and bridges add a shell spawn whenever a spec is missing.

The split, measured on a real completion: a command with no spec returns in ~55 ms while a full completion costs ~290 ms, so carapace's own start plus spec init dominates and nothing in Nushell is the bottleneck. Calling the real executable behind a scoop shim instead of the shim saves ~90 ms per press; the shell-context rebuild is ~12 ms in-process, so caching it buys nothing and only risks stale aliases. Resolve the shim's target by reading the `.shim` file next to the resolved path (`path = "..."`), falling back to `which` when no shim exists.

## Probe pitfalls

- `nu -c 'from json | length'` cannot read stdin ("no input value was piped in"). Pipe JSON into `python -c` or run a script file that consumes `$in`.
- The bash tool's `$TMPDIR` is an MSYS path; native `nu`, `python`, and `git` need `C:/...` form. Write probes to the scratch directory with a native path.
- `to nuon` on `$env.config.completions.external` fails: closures are not serializable. Print fields individually with `describe` or `to nuon` on a partial record.
