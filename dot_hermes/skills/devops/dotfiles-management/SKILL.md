---
name: dotfiles-management
description: Use when managing dotfiles across Windows and Linux.
metadata:
  hermes:
    tags: [dotfiles, nixos, home-manager, windows, yadm]
    related_skills: [nixos-flake-config, nixos-module-gotchas]
---

# Dotfiles Management Across Machines

One repo of config files that must land in the right places on more than one
machine, at least one of which may be Windows.

## When to use
- Choosing, replacing, or evaluating a dotfile manager.
- Making one set of dotfiles exist on Windows **and** on Linux/NixOS.
- Wiring a dotfiles repo into a NixOS flake so a new machine self-provisions.
- Deciding whether the flake or the dotfiles repo owns a given file.

## Core rule: probe the platform before choosing a tool
Managers split into symlink-based and materialising. Whether the target OS can
make symlinks decides the shortlist, and you cannot assume it — probe each OS:

```bash
ln -s target probe && [ -L probe ] && echo "real symlink" || echo "COPIED - symlinks unavailable"
```

Assert with `-L`, never the exit code: under MSYS/git-bash `ln -s` **silently
copies** when the symlink privilege is absent, and still exits 0.

## Core rule: one owner per path
A file has exactly one source of truth. Never let a dotfile manager and
home-manager/Nix both manage the same path, and never keep the same file in two
repos. Pick the owner and delete the other copy in the same change — a second
copy is drift, not redundancy.

Which layer should own what:
- **Dotfiles repo / manager** — anything mutable that gets edited live, and
  anything that must also exist on a non-Nix OS.
- **Nix / home-manager** — packages, services, users, hardware, login, locale,
  and the app binaries with their systemd units. HM is the wrong owner for ANY
  file a human edits, and the mechanism is why: `xdg.configFile.*.source`/`.text`
  and `programs.*.settings` create a **symlink into the read-only store**
  (`ln -Tsf`, not a hardlink), so an in-place write fails. Worse, a tool that
  writes temp-then-`rename()` REPLACES the symlink with a real file, and the next
  switch force-links over it — silently destroying the edit unless
  `home-manager.backupFileExtension` is set. `lib.file.mkOutOfStoreSymlink` is the
  one writable escape hatch. `home.activation` is a different mechanism entirely:
  plain shell, real files, stays editable.

**Split the flake from the dotfiles.** The boundary is: the flake owns the
SYSTEM, the dotfiles manager owns every file a human edits. Write a hand-edited
config into the flake and you have created a file nobody can save. Corollary —
a base config the app ships itself, where you only append one line, belongs to a
flake `home.activation`, which writes a real file and stays editable.

**Before wiring ANY app config into the flake, ask the manager what it already
owns** — `chezmoi managed | grep -i <app>`. A mature dotfiles repo owns more than
you expect; the module you were about to write is then a SECOND owner of the same
path. Delete the flake half in the same change.

Check the reverse direction too: a `programs.*` option can own a file the moment
it is ENABLED, not only once it is configured. `references/home-manager-file-ownership.md`
lists which ones do, and which integration options exist at all.

When Windows is in the mix, **chezmoi is the default**: its target `mode`
defaults to `file`, so it materialises real files and never needs the symlink
privilege Windows normally withholds. Probe the effective mode rather than
assuming it — `chezmoi dump-config | grep -i mode`; an absent key means the
built-in `file` default. `chezmoi doctor`'s
`symlink ... A required privilege is not held by the client` is therefore
EXPECTED and benign — never "fix" it.

yadm stays valid (files in place, no symlinks at all, `yadm.alt-copy` for hosts
that cannot link) and is the better fit when NO Nix system config is involved.
With a flake in the picture chezmoi wins, because it also resolves the
published-repo and encryption problems — see "Split the flake from the dotfiles"
below. Alternatives: `references/windows-linking.md`; chezmoi mechanics:
`references/chezmoi.md`.

## Procedure
1. Probe the platform (above) on every OS the dotfiles must reach.
2. Filter the manager shortlist by that result — a symlink-based manager is dead
   on a host that cannot link.
3. Decide the owner for each path, and delete the losing copy.
4. Wire the bootstrap as clone-if-absent so a rebuild never re-clones and never
   depends on the network after the first run:
   ```nix
   home.activation.dotfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
     if [ ! -e "$HOME/.local/share/yadm/repo.git" ]; then
       run yadm clone https://github.com/you/dotfiles.git
     fi
   '';
   ```
   Guard on the manager's OWN state directory — `~/.local/share/yadm/repo.git`
   for yadm, `~/.local/share/chezmoi/.git` for chezmoi. On a box that already
   runs the manager, prefer its native bootstrap (`chezmoi init --apply <repo>`)
   over hand-rolling the clone.
5. Verify: list what the tool would change before applying, and confirm no path
   appears under both owners.

## Pitfalls
- **`ln -s` can silently copy.** Without the symlink privilege it creates a real
  directory that drifts from the source on the first edit. Assert with `-L`.
- **`rm -rf` through a symlink or junction deletes the TARGET's contents.**
  Unlink the link first; never recurse into one.
- **Checkout conflicts.** git refuses to overwrite files that already exist, so a
  clone/bootstrap only lands cleanly on a fresh machine. On a configured box,
  remove the existing files or accept `--force` deliberately.
- **A published config repo should stay standalone.** An app config that is its
  own repo and is shared (README, demo assets, pushed to more than one host)
  loses its audience if folded into a private umbrella. Ask before merging. Do
  NOT copy its files into the umbrella and do NOT submodule it — declare a
  `type = "git-repo"` external in `.chezmoiexternal.toml`, so the manager clones
  and pulls it at the app's config path. git then owns that directory: the
  manager cannot manage other files in it, and its contents stop appearing in
  `diff`/`dump` (they list under `unmanaged`). That is the point.
- **Reconcile a source-directory manager with a live-editing habit.** If the
  habit is "edit the file, then commit in that directory", a manager that needs a
  re-add/apply round trip reads as friction. Either keep that path in-place (yadm)
  or delegate the whole directory to git with a `git-repo` external, so the round
  trip stays inside the app's own repo.
- **An app that rewrites its own config makes the round trip permanent.** A
  settings file the app regenerates (an editor or terminal `settings.json`, an
  agent's `config.yaml`) drifts on every GUI change, so a manager owning it needs
  a `re-add` after each one. The mechanism is that `apply` is a FULL-FILE render,
  not a patch: it renders the source entry (for a `.tmpl`, the whole template),
  compares, and overwrites — there is NO key-level merge. So a template must hold
  the entire file, and an app-side edit or schema migration is reverted outright.
  Either accept the `re-add` habit, or leave the app as owner and drive only the
  curated keys through the app's own setter from a `run_onchange_` script
  (`hermes config set key value`) — it re-runs only when the key list changes, and
  the app stays free to rewrite and migrate the rest.
- **Case-insensitive filesystems hide two names for one file.** On Windows
  `soul.md` and `SOUL.md` are the SAME file, so both "exist" and read back
  identical; `os.path.exists` cannot tell you which name is real, and a manager
  that stores names verbatim then creates TWO files on Linux. Take the stored case
  from a directory listing — `[n for n in os.listdir(h) if n.lower() ==
  "soul.md"]` returns the real one — and add exactly one spelling.
- **Never name a data file with the `.chezmoi.` prefix.** It collides with the
  reserved namespace (`.chezmoiroot`, `.chezmoiignore`) and reports as a
  `suspicious-entries` warning in `doctor`. A file whose only job is recording a
  per-OS path is documentation — put it in the repo README.
- **Ignore the generated files an app writes into its own config dir**, or
  `apply` reports drift forever. Add them to `.chezmoiignore` as they appear: a
  terminal's `log/` and `shell-integration-*/`, an app's `window_state.json`, a
  shell's `generated/`, anything a Nix activation writes into a shared dir.
- **Keep secrets in neither layer.** An app's `auth.json`, env files and tokens
  go in the plaintext dotfiles or the flake only over a dead body. chezmoi makes
  this cheap: `useBuiltinAge` defaults to `auto`, so `add --encrypt` works with
  no `age` binary installed, and `add.secrets` defaults to `warning` (promote it
  to `error` so a token cannot be committed at all). But decide by WHERE THE
  PLAINTEXT LANDS, not by whether the tool is "secure":
  - **chezmoi** encrypts the SOURCE only. `apply` writes a **plaintext file at
    the destination in `$HOME`**, mode from umask (022 → 0644) unless the target
    is `private_` (→ 0600). So it fits user-level dotfile secrets (an API key in
    `~/.env`-class files) and not root/boot secrets. `encryption` defaults to
    none — encryption is opt-in and protects nothing until set. The builtin age
    lacks passphrase/symmetric/SSH-key modes; use the external CLI for those.
    Never use `transparent` as the confidentiality boundary: it delegates to git
    filters (git-crypt/transcrypt) and `git show`/`git diff` can reveal cleartext.
  - **sops-nix** decrypts at ACTIVATION into `/run/secrets/<name>`, ramfs-backed
    by default (`sops.useTmpfs=false` — leave it; `useTmpfs=true` can swap
    plaintext unencrypted on kernels < 6.4), mode **0400 root:root**, plaintext
    never in the store or on persistent disk. Use it for anything a root systemd
    service reads at boot. For `hashedPasswordFile` you MUST set
    `neededForUsers = true` → `/run/secrets-for-users`, because ordinary secret
    activation runs after user creation. It can take the machine's Ed25519 SSH
    host key as the age identity (`sops.age.sshKeyPaths`), removing separate key
    distribution.
  - **Not either/or.** chezmoi has no native `encryption = "sops"` (choices are
    age/gpg/transparent) and `chezmoi secret` is an OS-keyring integration, but
    the generic `secret`/`secretJSON` template functions (`secret.command` +
    `secret.args`) and `output` can invoke the sops CLI at template time. If
    chezmoi renders the value, plaintext lands in `$HOME` again — so one SOPS
    source serves both only when sops-nix owns the runtime file and chezmoi owns
    a bare pointer. Keep one writer per path, as for any other file.
  - Neither tool is a rotation agent. Rotation without an apply/switch needs a
    runtime secret-manager client.
- **Before adopting a config into a repo that pushes anywhere, scan it — and
  separate a key that NAMES a secret from one that HOLDS one.**
  `access_token_env: BWS_ACCESS_TOKEN` is a variable name and is safe; a long
  high-entropy literal under `api_key`/`token`/`password` is a leak. A regex over
  secret-ish key names hits both, so judge the value's shape before calling it
  one.

## Syncing an existing chezmoi repo to the live state
- **`chezmoi re-add` writes source <- live and will happily destroy good source.**
  Run `re-add --dry-run` first — it prints a real per-file diff. A live file can be
  one host's partial stub while the source holds the real cross-platform config;
  re-adding then replaces the good file with the stub. Classify every hunk as
  line-endings-only vs substantive before writing anything.
- **`--secrets` exists on `add` ONLY, never `re-add`**, so a re-add is unscanned.
  Scan the affected live files yourself first.
- **"Sync to live" also means ADDING what live references.** A live config can name
  files the source has never held (a theme, a shader). Check with
  `chezmoi unmanaged <dir>` and add the referenced ones, or a fresh machine gets a
  config pointing at files it does not have.
- **`add.secrets` is a tripwire, not a net.** Measured: it stops a hardcoded
  password assignment, but does NOT catch PEM/OpenSSH private keys (under any
  filename), GitHub PATs (`ghp_`, `github_pat_`), AWS access keys, `sk-` keys, or
  JWTs. Never rely on it for `~/.ssh` — do not add that directory at all, and add
  an independent key-material scan to pre-commit.
- **Read `chezmoi status` in two columns**: col 1 is drift since chezmoi last
  wrote, col 2 is what `apply` would do. Use it to pick direction — `D` in col 1
  with `A` in col 2 means the live file is gone and only `apply` recreates it; no
  `re-add` will fix it.
- **Verify what an `add` wrote with `git status --short -uall`.** Plain `-short`
  collapses an untracked directory to a single line, so a per-file grep finds
  nothing and you wrongly conclude the write never happened.
- **Pass native paths to chezmoi.** Under MSYS/git-bash `chezmoi unmanaged /c/...`
  returns nothing and reads as "nothing unmanaged"; `C:/...` is correct.
- **A managed directory that is also its own git clone is drift waiting to happen.**
  Measured: the source copy had frozen while the published repo moved on, leaving
  the source missing modules the live config `require`s — so `apply` would have
  broken the app. Copying a published project's files is never the fix; convert it
  to a `git-repo` external.

## Externals and OS-specific roots
- **A `git-repo` external's target key can be a template**, which is how one
  declaration lands in `%APPDATA%` on Windows and `~/.config` elsewhere:
  ```toml
  {{- $t := ".config/nushell" -}}
  {{- if eq .chezmoi.os "windows" -}}{{- $t = "AppData/Roaming/nushell" -}}{{- end -}}
  ["{{ $t }}"]
      type = "git-repo"
      url = "https://github.com/..."
      refreshPeriod = "168h"
  ```
  `.chezmoiexternal.$FORMAT` is rendered as a template, so validate the render
  with `chezmoi execute-template < .chezmoiexternal.toml` and parse the result as
  TOML before trusting it. A TOML linter will reject the raw `.tmpl`-style file —
  expected, since only the render is TOML.
- **Use HTTPS for external URLs when the repos are public.** SSH URLs need keys
  and an agent, so `chezmoi apply` on a fresh machine stalls (`git ls-remote`
  against an SSH remote fails/hangs without them). Add an SSH push remote inside
  the clone if you need to push: `git remote set-url --push origin git@...`.
- **Ignore the other OS's tree per OS**, since a source path maps to one target:
  `{{ if ne .chezmoi.os "windows" }}` / `AppData/**` / `{{ end }}` in
  `.chezmoiignore`. Verify the render, not the file.
- **chezmoi does NOT prune.** Verified in a `--source`/`--destination`/
  `--persistent-state` sandbox: deleting a source entry leaves the live target in
  place. So removing source files that an external has taken over cannot delete
  the clone — but confirm the clones still exist anyway.
- **`chezmoi apply` prompts on every changed file** (`diff/overwrite/
  all-overwrite/skip/quit`) and will sit there forever under a non-interactive
  caller. Use `--no-tty -k` (or `--force`) in scripts; a "hang" is usually this,
  not the network.
- **A zero-byte target is stored as `empty_<name>`** in the source. That is the
  `empty_` attribute, not a stray file — it maps back to the real name.

## Find the app's REAL config path, not the documented one
Three tools on one Windows box resolved three different ways — measure each:
- Terminals/tools that `--help` print their resolution are authoritative: run it.
  `herdr --help` prints `Config: %APPDATA%\herdr\config.toml`.
- Else read the source. herdr's `src/config/io.rs` order on Windows is
  `XDG_CONFIG_HOME` -> `%APPDATA%` -> `USERPROFILE` -> `HOME/.config`; `~/.config`
  is only a last-resort fallback.
- rio reads `%USERPROFILE%\AppData\Local\rio` on Windows and does NOT honour
  `XDG_CONFIG_HOME` there. wezterm honours `.config` on Windows.
Consequence: a `~/.config/<app>` file can be **dead** while looking perfectly
healthy — the app reads AppData and the edits go nowhere. Confirm before
managing it, and prefer an env override (`XDG_CONFIG_HOME`, or the app's own
`RIO_CONFIG_HOME` / `HERDR_CONFIG_PATH`) to keep ONE tree instead of duplicating
config per OS. One-off interactive assignments do not persist: check `env.nu`
/ the registry, not shell history.
- **A path-override variable is used VERBATIM — no `~` expansion.** Measured:
  `HERDR_CONFIG_PATH=~/.config/herdr/config.toml` resolves to that literal
  string, so the app reads nothing. Use an absolute path, and confirm the
  resolved value with the tool's own `--help` (herdr prints it) rather than
  trusting the docs' example.

## Adopting a config file into the dotfiles repo
- **Diff it for host-specific keys before making it shared.** One managed
  `config.yaml` serving two machines pins the first machine's `model` /
  `provider` / `base_url` values onto the second. Either template those keys
  (a `.tmpl` variant plus a `.chezmoi.toml.tmpl` that prompts per machine) or
  leave them unmanaged.
- **Add the config PATHS, not the application home directory.** That directory
  also holds caches, logs, session databases, vendored dependencies and
  downloaded packages — tens of thousands of files. Adding it drags them all in
  and then needs ignore rules to take them back out; two explicit paths need
  none, and leave the entry count small enough to read.
- **For an agent or app home, version the ENABLE/DISABLE LISTS, not the content
  directories.** A curated skills or plugins directory runs to tens of thousands
  of files, much of it fetched from third-party registries, and agent- or
  app-authored entries can embed sensitive material — so tracking it is both
  unwieldy and a leak risk. The app already keeps the denylist in its own config
  (`skills.disabled`, `plugins.enabled`), and that list is the part actually worth
  versioning; hand-written entries transfer manually. Confirm the list really
  lives in config rather than in per-directory state before deciding, and check
  the app's own subcommands for the seeding side of the same question
  (`hermes skills list` / `opt-out`).
- **Derive the curated key list from the app's OWN defaults, not from the module
  you happened to write.** The surface worth versioning is the DIFFERENCE from
  stock. Load the app's default-config data (a pure-data leaf module is ideal —
  `hermes_cli/config_defaults.py` holds `DEFAULT_CONFIG`), flatten both it and the
  live file to dotted leaf keys, and diff. Measured on one agent config: 888 stock
  leaves against 486 live leaves left only **34 keys with a changed value**, plus
  ~64 present only in live — about 100 keys, where the 200-line flake module they
  came from had been mostly restating defaults.

  **Classify every live-only key before scripting it.** Only two buckets belong
  in the script: values that DIFFER from stock, and live-only keys that express
  intent. Skip the rest — hermes BOOKKEEPING (toolset registries, platform maps,
  per-language server tables, `update.installs.*`, `_left_*`), keys the app
  SHIPS and materialises on first run (`agent.personalities.*`, built-in server
  tables), keys whose value is EMPTY, and TRANSIENT keys that track runtime state
  rather than a preference — measured: one flipped on its own when the active
  model changed, so it was never a setting. Model/provider keys are a POLICY
  exclusion, not a technical one: they age fast and the user sets them by hand.
  Pinning internals makes the script fight every release.

  **A scalar setter cannot express a list.** `hermes config set key value` takes
  a single string, so route list-valued keys through the app's own CLI
  (`hermes plugins enable|disable`, `hermes skills opt-out|opt-in`) instead of
  inventing a JSON-string encoding — and confirm that CLI exists before
  promising it.

  **Prove the split with the app's own provenance listing, not the filesystem.**
  A `list` subcommand with a Source column, an install audit log, and a bundled
  manifest together separate "installed from a registry" from "hand-written
  here" — which is exactly the boundary between a command and a file.

  Do NOT try to obtain the defaults by running the tool against a throwaway home
  directory: first-run bootstraps an entire runtime and is slow or fails. Read
  the defaults out of the source instead.

## Committing inside a dotfiles repo
- **`commit.gpgsign = true` with no pinentry configured hangs the FIRST commit**
  (gpg-agent cold start; later commits pass from the cache). Give scripted
  commits a long timeout, and verify `git rev-parse HEAD` changed after each — a
  commit that silently never ran leaves its staged files to be swept into the
  NEXT commit under the wrong message.
- **`git commit` with no pathspec commits the ENTIRE INDEX, not what you staged
  in this command.** After `git reset --soft <base>` the whole tree is staged, so
  `git add -A -- dir` followed by `git commit` sweeps in every other staged file
  under the wrong message. Unstage the ones that belong elsewhere first
  (`git reset -q HEAD -- <file>`), or pass the paths to `commit`. Check
  `git diff --cached --name-only | wc -l` before committing. A directory add plus
  `git reset -q -- <path>` is also how to exclude one file from a bulk deletion
  commit.
- **When squashing unpushed commits, reset to the last commit YOU authored, not
  to `origin/master`.** Resetting to origin collapses commits belonging to other
  people into yours and rewrites history you do not own. Squash only your own
  range and leave earlier commits intact.
- **Read `git remote -v` for a fetch/push URL split.** One remote name showing
  different URLs for fetch and push means you are tracking one repo and pushing
  to another; `origin/master` then reports ahead/behind against the wrong
  baseline. Make fetch match push, re-fetch, and re-read the counts.
- **A dotfiles repo needs `.gitattributes` with `* text=auto eol=lf`.** Without
  it, CRLF files land on Linux as CRLF and a sourced `.bashrc` fails with
  `$'\r': command not found`. CRLF also creeps into `.toml`/`.nu` configs.

## References
- `references/windows-linking.md` — measured symlink/junction behaviour on
  Windows, the no-admin junction recipe, and the manager comparison.
- `references/chezmoi.md` — chezmoi's effective defaults, how to read `doctor`,
  externals, `.chezmoiignore` recipes, secrets, and the ownership boundary.
- `references/home-manager-file-ownership.md` — which `programs.*` options write a
  file (and which integration options exist at all), so the ownership check runs
  in both directions.
- `scripts/verify-config-paths.py` — resolve every relative reference in a config
  tree and fail on a broken one: the proxy for the tool's own validator when it
  cannot run locally, and the check that catches a move that left a path behind.
