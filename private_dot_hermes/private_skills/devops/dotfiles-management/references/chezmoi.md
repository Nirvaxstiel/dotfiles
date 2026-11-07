# chezmoi — effective behaviour and the system/dotfiles boundary

Depth for `dotfiles-management`. These are chezmoi's documented defaults; confirm
against the installed version's own output before relying on any of them.

## Probe the installed tool first
```bash
chezmoi doctor                          # one screen of environment facts
chezmoi dump-config | grep -i mode      # absent => built-in default applies
chezmoi source-path                     # the git working tree
chezmoi managed | grep -i <app>         # what it ALREADY owns
chezmoi unmanaged                       # present on disk but not owned
```
`managed` is the discovery step. Run it BEFORE adding an app's config to any
other manager: a mature repo owns more than you expect, and the file you were
about to declare elsewhere already has an owner.

## Defaults that decide the design
| Variable | Default | Consequence |
|---|---|---|
| `mode` | `file` | Materialises REAL FILES, not symlinks — no symlink privilege needed. This is why it works on Windows; `symlink` is opt-in. |
| `useBuiltinAge` | `auto` | Ships its own age, so `add --encrypt` works with no `age` in `$PATH`. |
| `add.secrets` | `warning` | Complains when an added file looks like a secret. Keep it. |
| `encryption` | none | Nothing is encrypted until age or gpg is configured. |
| `format` | `json` | Data output format. |
| `edit.hardlink` | `true` | The editor edits a hardlink to the source file. |
| `git.autoAdd` / `autoCommit` / `autoPush` | `false` | Nothing leaves the machine automatically. |
| `update.apply` | `true` | `chezmoi update` pulls and then applies. |

## Reading `chezmoi doctor`
- `symlink ... A required privilege is not held by the client` — EXPECTED on
  Windows, harmless: under `mode = file` no symlink is ever created. Never
  "fix" it by granting the privilege.
- `suspicious-entries` — a source-tree filename colliding with the reserved
  namespace (see below).
- `upgrade-method` failing under a package manager — that manager's own manifest
  format, cosmetic, does not affect `apply`.
- `config-file ... not found` — no `~/.config/chezmoi/chezmoi.toml`, so templates
  have no `[data]` values. Fine until a template needs custom data.
- `age-command not found` — a non-issue; `useBuiltinAge` covers it.

## Reserved namespace
`.chezmoiroot`, `.chezmoiignore`, `.chezmoiexternal.$FORMAT`,
`.chezmoitemplates/` and `.chezmoiscripts/` are special. A data file named
`.chezmoi.<anything>` is NOT, and it surfaces as `suspicious-entries`. A file
whose only content is a per-OS path is documentation — README, not a data file.

## Per-OS differences
There are no filename-based alternates (that is yadm's `alt_`). Branch inside the
file instead: `{{ if eq .chezmoi.os "windows" }}...{{ else }}...{{ end }}`.

## Externals: `.chezmoiexternal.$FORMAT`
Use for anything that is already a repo or a published archive, instead of
copying its files into the source tree.

```toml
[".config/<app>"]
    type = "git-repo"
    url = "git@github.com:you/<app>-config.git"
    refreshPeriod = "168h"
```

- `git-repo` runs `git clone`, then `git pull` at most every `refreshPeriod`
  (default 0 = never). Force with `chezmoi -R apply`.
- git then OWNS that directory: chezmoi cannot manage other files in it, its
  contents stop appearing in `diff`/`dump`, and they list under `unmanaged`. That
  is the trade, and it is correct when you edit that config inside its own repo.
- `archive` / `file` / `archive-file` unpack into place, but chezmoi validates
  their exact contents on every `diff`/`apply`/`verify` — do not point them at a
  large tree; use a `run_onchange_` script for that.
- Set `external_` on any subdirectory holding a git submodule, or its
  `run_*`-shaped filenames get interpreted as scripts.

## `.chezmoiignore` recipes
Add an app's generated files as they appear, or `apply` reports drift forever:
- a terminal writing `log/` and `shell-integration-*/` inside its config dir
- an app's `window_state.json`, history, or cache files
- a shell's `generated/` directory
- anything a Nix activation writes into a directory chezmoi also owns

## Secrets
`auth.json`, env files and tokens belong in NEITHER the plaintext dotfiles nor
the flake. Encrypt with age (`chezmoi add --encrypt`) or keep them local and list
them in `.chezmoiignore`.

## The boundary
| Concern | Owner |
|---|---|
| packages, services, users, hardware, login, locale, network | flake |
| app binaries and their systemd units | flake |
| app config a human hand-edits (on any OS) | dotfiles manager |
| shell rc files | dotfiles manager |
| a config that is its own published repo | `git-repo` external |
| a base config the app ships, needing one appended line | flake `home.activation` (real file, stays editable) |
| `auth.json`, env files, tokens | neither — local or encrypted |
