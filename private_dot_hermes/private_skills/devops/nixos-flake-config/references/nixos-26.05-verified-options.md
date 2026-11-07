# Verified NixOS 26.05 (Yarara, 2026.05/30) option facts

Confirmed by reading the raw `.nix` modules on the `nixos-26.05` branch
(`github:NixOS/nixpkgs/nixos-26.05/...`). Use as a trustable lookup; re-verify
if the pin moves to a later release.

## Release exists
- `nixos-26.05` branch is real; released 2026-05-30 ("Yarara"). Pin as
  `github:NixOS/nixpkgs/nixos-26.05`.

## niri (scrollable-tiling Wayland compositor)
- Module: `nixos/modules/programs/wayland/niri.nix`
- Options: `programs.niri.enable` (bool), `programs.niri.package`
  (mkPackageOption), `programs.niri.useNautilus` (bool, default true).
- Enabling sets `services.displayManager.sessionPackages`, `gnome.gnome-keyring`
  (mkDefault true), `systemd.packages`, `xdg.portal` defaults. Ships the
  `niri-session` binary. `config.programs.niri.package` resolves even with no
  recursion into `enable` (safe to reference from greetd).

## Noctalia Shell (Wayland shell, NOT a compositor)
- Flake: `github:noctalia-dev/noctalia-shell` (main branch).
- Exposes `packages.<system>.default`, `homeModules.default`,
  `nixosModules.default` (NixOS module is DEPRECATED), `overlays.default`.
- The home-module option name is mid-rename: `programs.noctalia` in current
  source, but docs/wiki also say `programs.noctalia-shell`. Prefer consuming the
  package directly via `inputs.noctalia-shell.packages.${pkgs.stdenv.hostPlatform.system}.default`.
- Binary cache: `https://noctalia.cachix.org`, key
  `noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=`.
- Pin its nixpkgs: `inputs.noctalia-shell.inputs.nixpkgs.follows = "nixpkgs"`.
- **Noctalia already implements the "declarative base + live GUI edits + periodic
  export" pattern.** It has TWO layers, and this is why a read-only store symlink
  is correct for it (unlike niri):
  - `~/.config/noctalia/config.toml` — the declarative base. The app NEVER
    rewrites files here. `programs.noctalia.settings` renders exactly this via
    `xdg.configFile."noctalia/config.toml"` (`jsonFormat = pkgs.formats.json` in
    the module, but the file is TOML), plus
    `xdg.configFile."noctalia/palettes/<name>.json"` from
    `programs.noctalia.customPalettes`.
  - `$XDG_STATE_HOME/noctalia/settings.toml` (`~/.local/state/noctalia/`) — the
    app-managed GUI override layer. Upstream keeps it OUTSIDE `~/.config` on
    purpose, "so the GUI can save changes when your config directory is
    read-only, for example on NixOS". Safe to delete to clear GUI overrides.
  - So GUI customisations need no referencing on the live box — they are the
    override layer by design. To make them portable, run the built-in export and
    move the result into `programs.noctalia.settings`:
    `noctalia config export` (merged user config, drops the `config_version`
    marker) or `noctalia config export full` (adds built-in defaults). Export
    writes TOML to stdout and fails rather than emit a partial file.
  - Other module options: `programs.noctalia.{enable,systemd.enable,checkConfig}`
    (`checkConfig` default true runs a config check at activation).
    Upstream warning: settings "can still be overwritten at runtime via the
    settings menu" — that is the state layer, by design.
- PATH SHAPES: `$XDG_CONFIG_HOME`, `$XDG_STATE_HOME`, `$XDG_DATA_HOME`,
  `$XDG_CACHE_HOME` are all honoured, plus the app-specific
  `NOCTALIA_CONFIG_HOME` / `NOCTALIA_STATE_HOME` for a separate shell profile.
- Owned by you: `~/.config/noctalia/` and `~/.local/share/noctalia/` (plugins).
  Owned by the app: `~/.local/state/noctalia/`.

## greetd (display manager) — default_session IS the greeter
- Module: `nixos/modules/services/display-managers/greetd.nix`
- `services.greetd.enable` (bool), `services.greetd.settings` (TOML attrset).
  Schema: `settings.default_session = { command = "..."; user = "..."; }`.
- **CORRECTION to earlier guidance in this file.** `default_session` is the
  **greeter**, not "the session". greetd(5) says verbatim: "This section
  describes the default session, also referred to as the *greeter*"; the `user`
  key is "the user to use for running the **greeter**". Upstream `config.toml`
  comments the same thing. greetd ships NO greeter — the README lists every
  greeter as a separate program, and "greetd makes no assumptions about what you
  want to launch".
- ⇒ Pointing `default_session.command` at the *compositor* (`niri-session`) and
  `user` at the real user makes greetd launch that session directly. Result: the
  machine boots straight into the desktop with **no login screen at all**. That
  is the exact failure mode to look for when "there is no login prompt".
- Correct shape for a login screen: `default_session.command` runs a greeter and
  `user` keeps the module default `"greeter"`. e.g.
  `default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd niri-session"`
  plus `services.greetd.useTextGreeter = true` (nixpkgs sets `/var/cache/tuigreet`
  and the TTY wiring for exactly this; see nixpkgs#248323).
  PITFALL: `pkgs.greetd.tuigreet` still resolves but is a **deprecated alias**
  that warns on instantiate ("`greetd.tuigreet` was renamed to `tuigreet`").
  Use `pkgs.tuigreet`. `agreety` is NOT a package — it is a binary inside
  `pkgs.greetd` (`${pkgs.greetd}/bin/agreety`), which is why the module's own
  example is written that way.
- `initial_session` is the autologin section ("commonly referred to as
  auto-login"). It runs ONCE per boot, guarded by greetd's runfile. Setting it
  makes the module default `restart = false` (otherwise every greetd restart
  re-triggers the autologin).
- `security.pam.services.greetd.allowNullPassword = true` is set by the module,
  so a passwordless login is possible if the account has no hash.
- Other options: `greeterManagesPlymouth`, `useTextGreeter`,
  `services.greetd.package`. The VT is FIXED to `tty1` (`settings.terminal.vt`
  is forced to 1; the old `services.greetd.vt` option was removed).

## Deploying native config files from home-manager (verified release-26.05)
- `xdg.configFile.<rel>.source` and `home.file."<path>".source`:
  - **`recursive` defaults to FALSE**, so the target is a **symlink to the whole
    source DIRECTORY** (`modules/lib/file-type.nix`). `recursive = true` uses
    lndir-style per-file links instead.
  - `force = true` unconditionally replaces the target (its own doc says
    "Warning, this will silently delete the target"). Caveat emptor.
  - Before linking, `home.activation.checkLinkTargets` (`entryBefore
    writeBoundary`) **REFUSES to overwrite an existing real file**. That — not
    "read-only" — is the precise mechanism behind the niri `config.kdl`
    collision, and it fails the whole switch.
  - Everything lands in the store, so the target is READ-ONLY. **Any app that
    writes into its own config dir cannot be pointed at a store symlink**:
    wezterm writes `window_state.json`, rio writes `log/` and
    `shell-integration-<ver>/`. This is why those get cloned instead.
- `config.lib.file.mkOutOfStoreSymlink` still exists in 26.05 (defined in
  `modules/files.nix` as `pkgs.runCommandLocal name {} "ln -s <abs> $out"`).
  Accepts a path or a string. Live-editable, but outside generations/rollback.
- `home.file.".config/x"` hardcodes `.config`; `xdg.configFile."x"` is relative to
  `xdg.configHome` (default `~/.config`, `mkOptionDefault` when `xdg.enable`).
  Prefer the latter.
- **COMMAND GOTCHA:** `home-manager switch --flake .#host` only works for a
  STANDALONE HM setup that exposes `homeConfigurations`. When HM is wired as a
  NixOS module (`home-manager.nixosModules.home-manager` +
  `users.<u> = import …`, as in this repo) there is no `homeConfigurations`
  output and that command fails. Use `nixos-rebuild switch --flake .#<host>`;
  HM then activates as a SECOND phase, not in the same transaction.
- `home.packages = [ pkgs.niri ]` does NOT enable a compositor. Use
  `programs.niri.enable`, which also wires the session, portals and keyring.

## Password provisioning (verified against nixos-26.05 source)
- `users.users.<n>.hashedPasswordFile` is read ONLY by
  `nixos/modules/config/update-users-groups.pl` at activation time. No other
  component (PAM, `/etc/shadow`, sudo, a lock screen, the greeter) ever touches
  that path.
- A MISSING file is a `warn`, not a `die`:
  `warn "warning: password file ‘…’ does not exist\n"`. The switch still
  succeeds and the password is not blanked.
- **`users.mutableUsers` defaults to `true`, and that decouples the file from
  `/etc/shadow`.** In the shadow-rewrite loop the existing `$sp_pwdp` is carried
  through unchanged; `$u->{hashedPassword}` is consulted only in the loop for
  accounts NOT already present in `/etc/shadow`. Consequences:
  - Re-enabling or editing `hashedPasswordFile` does NOT change an existing
    account's password. It is a **first-boot provisioner**.
  - A fresh machine with the file missing creates the account with `!` (no
    password). That is what breaks a greeter that needs authentication.
  - `users.mutableUsers = false` makes activation authoritative: `/etc/shadow`
    is rewritten from the declarative password on every switch (`$sp_pwdp = "!"`
    then set from `$u->{hashedPassword}`).
- ⇒ `sudo`, a lock screen, or a greeter accepting the user's password proves the
  hash in `/etc/shadow` is good. It proves NOTHING about the file.
- Noctalia's lock screen auth path (verified in
  `Modules/LockScreen/LockContext.qml`): `pamConfigDirectory = "/etc/pam.d"`,
  `pamConfig = NOCTALIA_PAM_SERVICE || "login"`, with a probe falling back
  `login` → `system-auth` → `common-auth`. On NixOS it therefore authenticates
  through `/etc/pam.d/login` → `pam_unix` → `/etc/shadow`. The home-manager
  module does NOT generate a lockscreen PAM file on NixOS, so this is why it
  works anyway; override the service with
  `pkgs.noctalia-shell.override { pamConfig = "swaylock"; }` (upstream issue
  #1451 / PR #1468) when a dedicated service is wanted, e.g. for fingerprint.

## udisks2
- Module: `nixos/modules/services/hardware/udisks2.nix`
- `services.udisks2.enable` (bool). Also `package`, `mountOnMedia` (bool,
  default false), `settings` (ini attrset). Implies `security.polkit.enable`.

## gvfs
- Module: `nixos/modules/services/desktops/gvfs.nix`
- `services.gvfs.enable` (bool), `services.gvfs.package` (default
  `pkgs.gnome.gvfs`). Sets `GIO_EXTRA_MODULES`.

## boot.supportedFilesystems
- `boot.supportedFilesystems` accepts a string list (e.g. `[ "ntfs" ]`).
  Confirmed present in `profiles/base.nix` (which already lists ntfs).

## users / sudo
- `users.users.<name>` with `isNormalUser`, `extraGroups`, `initialHashedPassword`.
- `security.sudo.extraRules` = list of `{ groups, commands = [ { command, options } ] }`.
- Password hash tool: `mkpasswd -m sha-512 --rounds=656000`.

## Desktop apps added 26.05-onward (verified against release-26.05)
- **ghostty**: home-manager only — `nixos/modules/programs/ghostty.nix` does NOT
  exist in nixpkgs 26.05. HM `programs.ghostty`: `enable`, `package`, `settings`
  (keyValue → `$XDG_CONFIG_HOME/ghostty/config`, `key = value` lines, lists as
  duplicate keys), `themes`, `clearDefaultKeybinds`, `installVimSyntax`,
  `installBatSyntax`, `systemd.enable` (default true on Linux),
  `enable{Bash,Zsh,Fish}Integration`. `enable` alone installs the package.
- **zed**: HM `programs.zed-editor` (note: `zed-editor`, not `zed`),
  `modules/programs/zed-editor.nix`. Options `enable`, `package`,
  `extraPackages`, `mutableUser{Settings,Keymaps,Tasks,Debug}`, `userSettings`
  (jsonFormat attrset), `extensions` (list of addon ids), `defaultEditor`
  (bool, **default false** → does not touch `EDITOR`/`VISUAL` unless opted in).
- **floorp**: HM `programs.floorp` (Firefox-family via `mkFirefoxModule`),
  `modules/programs/floorp.nix`. `wrappedPackageName = "floorp-bin"` ⇒ default
  `package = pkgs.floorp-bin`. Empty `profiles = { }` is VALID (the
  single-default assertion is `cfg.profiles == { } || length defaults == 1`).
  In nixpkgs 26.05 `floorp-bin` is NOT in `pkgs/by-name/` (only
  `by-name/fl/floorp-bin-unwrapped/`) — the wrapper is defined in
  `pkgs/top-level/all-packages.nix` via `wrapFirefox`.
- **thunar**: nixpkgs `nixos/modules/programs/thunar.nix` → `programs.thunar.enable`,
  `programs.thunar.plugins` (list of packages, injected via
  `pkgs.thunar.override { thunarPlugins = ...; }`). Module also enables
  `programs.xfconf.enable`. No home-manager module — system layer only.
- **tumbler**: `nixos/modules/services/desktops/tumbler.nix` →
  `services.tumbler.enable`. Pair with thunar for thumbnails; gvfs already
  covers trash/network.
- Xfce packages moved to top level in 26.05: use `pkgs.thunar-volman`,
  `pkgs.thunar-archive-plugin`, NOT `pkgs.xfce.*` (scope removed in 26.11).

## niri capability gaps (26.05)
- The nixpkgs niri module has NO declarative config option (only `enable`,
  `package`, `useNautilus`). Config lives in `~/.config/niri/config.kdl`
  (imperative, or HM `xdg.configFile`). `niri-flake`'s `programs.niri.settings`
  is a different module — do not mix.
- niri's default config binds `Mod+T → spawn "alacritty"`, `Mod+D → fuzzel`,
  `Super+Alt+L → swaylock`. None are pulled in by the module: with no managed
  config those binds fail silently. Add a config binding your terminal.
- `useNautilus = false` swaps the portal FileChooser impl to `gtk`; the
  `xdg-desktop-portal-gtk` portal is already added by the module's
  `wayland-session.nix` (`enableGtkPortal` defaults true) — safe without
  Nautilus.
- Home-manager `release-26.05` has NO niri module at all (verified: nothing
  matching niri in `modules/programs`), so `xdg.configFile."niri/config.kdl"` is
  the mechanism. Home-manager is also the RIGHT layer — see below.

### Owning the niri config file (verified against niri v26.04 source)
- Config code moved: it is now the `niri-config` crate
  (`niri-config/src/{lib,binds,output,input,layout}.rs`), NOT `src/config.rs`.
  Docs are in-repo at `docs/wiki/Configuration:*.md` (the GitHub wiki moved to
  niri-wm.github.io); the shipped default is `resources/default-config.kdl`.
- PATH: `$XDG_CONFIG_HOME/niri/config.kdl`, else `/etc/niri/config.kdl`
  (`main.rs default_config_path()` uses `ProjectDirs`). `--config` and
  `$NIRI_CONFIG` win over both and become `ConfigPath::Explicit`, which calls
  `Config::load` — so niri does NOT create the user file in that mode.
- **niri WRITES the user config itself.** Startup uses
  `config_path.load_or_create()` (`main.rs:160`); if the user file is missing,
  niri creates it from the default config embedded via `include_str!`. Break
  consequences: (a) a system-level `environment.etc."niri/config.kdl"` is
  shadowed FOREVER by the user file — the user layer owns this path; (b) the
  file already exists as a REAL file after first boot, so a home-manager
  `xdg.configFile` collides and refuses — delete it once (or set
  `home-manager.backupFileExtension`).
- **MERGE SEMANTICS:** `Config::parse` starts from `Config::default()` and
  merges the parsed file into it (`lib.rs:494`, macro `merge_with` at `:186`).
  So every omitted section falls back to the RUST default — not to the shipped
  `default-config.kdl`.
- **`binds {}` IS EMPTY BY DEFAULT.** `Binds(pub Vec<Bind>)` is
  `#[derive(Default)]` → a config file with no `binds` node yields a session
  with NO KEY BINDINGS AT ALL. Upstream states it outright:
  "A notable exception is `binds {}`: they do not get filled with defaults, so
  make sure you do not erase this section."
- Recipe for owning the file without duplicating ~630 lines:
  `builtins.readFile "${pkgs.niri.src}/resources/default-config.kdl"` and append
  your nodes. In nixpkgs 26.05 `pkgs.niri` is `pname = "niri"`, `version =
  "26.04"`, a plain `fetchFromGitHub { tag = "v${version}"; }` (not a wrapper),
  and the same file is installed to `$doc/share/doc/niri/default-config.kdl`.
  Uses import-from-derivation (needs `allow-import-from-derivation`, the
  default). That file has 160 `{}` pairs, `/-output "eDP-1" {}` COMMENTED OUT (so
  real `output` nodes never collide), and ends with `binds {}`.
- OUTPUT NODES:
  - `mode "<w>x<h>@<refresh>"` — the refresh "must match *exactly*, down to the
    three decimal digits, to what you see in `niri msg outputs`", else niri
    silently falls back to auto.
  - `scale 1` (fractional since 0.1.7, e.g. `scale 1.5`; integer needs no dot).
  - `transform` values: `"normal"`, `"90"`, `"180"`, `"270"`, `"flipped"`,
    `"flipped-90"`, `"flipped-180"`, `"flipped-270"`.
  - `position x=… y=…` is in LOGICAL (scaled) pixels. If unset or overlapping,
    niri places the output automatically and warns.
  - "The cursor can only move between directly adjacent outputs" — a deliberate
    gap between two `position` values means the pointer cannot cross them, and
    `focus-monitor-left/right` follows the same rule.
- Verify a candidate config on the box with `niri validate` (parses and reports
  errors) before switching; the config is also live-reloaded on save.
- **DO NOT manage `niri/config.kdl` with `xdg.configFile`.** Two faults: the
  store symlink is read-only, so the user cannot keep hand-editing the live file
  (the normal early-days workflow), and the symlink collides with the copy that
  niri already wrote at first boot. Use a SEED instead:
  `home.activation.<name> = lib.hm.dag.entryAfter [ "writeBoundary" ] ''if [ ! -e "$HOME/.config/niri/config.kdl" ]; then run ${pkgs.coreutils}/bin/install -Dm644 <seed> "$HOME/.config/niri/config.kdl"; fi''`.
  The seed is `pkgs.writeText` of niri's default config plus the host's `output`
  nodes. Result: a new machine gets a working session on the first activation,
  and an existing file is never touched, so live edits survive every rebuild.
  Delete the file to load the seed again. Quote `${pkgs.coreutils}/bin/install`
  explicitly — do not assume `install` is on the activation PATH.
- **Nix can NEVER read the live config at evaluation time.** A flake evaluates in
  a pure sandbox: a path like `/home/kei/.config/niri/config.kdl` is not visible,
  and `builtins.readFile` of it needs `--impure` (which breaks `nix flake check`,
  remote builds and cache reuse). Reading and writing it at ACTIVATION time is
  correct and supported. Same wall as GPU auto-detection.
- Export/portability caveat: a flake sees only GIT-TRACKED files. An exported
  config that lands in the repo is invisible to evaluation until you `git add`
  it. Plan an export step that stages the file, not just writes it.

## Owning the niri config: the UAT/PROD seed pattern (chosen 2026-10)
- Goal: the live `~/.config/niri/config.kdl` is the **UAT** layer; the flake ships
a **PROD** copy that seeds it. One-directional: live → flake.
- Implementation that was chosen: keep the tracked config at
  `home/kei/files/niri/config.kdl` and copy it in an activation ONLY when the
  live file is absent:
  `install -Dm644 ${../files/niri/config.kdl} "$HOME/.config/niri/config.kdl"`.
  A plain repo `path` interpolated into a string is NOT import-from-derivation.
- Promotion step: a `bin/promote-*.sh` that runs `niri validate`, copies live →
  tracked, and prints `git diff`. Commit to promote.
- REJECTED alternatives, with the reason each failed:
  - `builtins.readFile "${pkgs.niri.src}/resources/default-config.kdl"` — this IS
    IFD (nixpkgs bans IFD; breaks `--no-allow-import-from-derivation`, slows
    `nix flake check`) **and** it silently drifts when nixpkgs is bumped, so the
    UAT file's starting point is never a revision you chose.
  - `xdg.configFile."niri/config.kdl"` (store symlink) — read-only, and it
    collides with the file niri writes itself at first start.
  - `config.lib.file.mkOutOfStoreSymlink` into the repo — live-editable and
    zero-copy promotion (this is the `ryan4yin/nix-config` pattern), but it
    hardcodes the repo path and makes the machine's config a symlink into the
    working tree. Rejected as too fragile here; prefer it when the repo path is
    guaranteed stable.
  - niri-flake `programs.niri.settings` — makes the FLAKE own the live file
    (read-only store symlink), which kills the UAT layer outright. The official
    NixOS wiki backs the non-niri-flake path: niri can be enabled without it; it
    is "only necessary if you would like to use a very recent version of Niri or
    if you would want to write configurations in the Nix language, **although as
    of 2025 this repository is listed near the top in search engines**" — i.e.
    its apparent prominence is SEO, not consensus.

### Best seeding route: reuse the DEFAULT CONFIG THE PACKAGE ALREADY SHIPS
- `pkgs.niri` has `outputs = [ "out" "doc" ]` and its `postInstall` does
  `install -Dm644 README.md resources/default-config.kdl -t $doc/share/doc/niri`.
  So the shipped default config is at
  **`${config.programs.niri.package.doc}/share/doc/niri/default-config.kdl`**.
- Interpolating that store path into an ACTIVATION SCRIPT is NOT import-from-
  derivation: no `readFile` runs at eval time. The doc output becomes a build
  dependency and the file is read at activation. Consequences:
  - the base is always exactly the installed niri's own default (no drift, no
    vendoring of a 632-line file into the repo),
  - cost: the `doc` output (which also holds the wiki) joins the system closure.
- Because `include` is positional and `binds` merge by replacing the same key, the
  seed is: copy that default, then append one line `include "overrides.kdl"`.
  Everything else lives in a ~25-line `overrides.kdl`. Verified: 123 stock binds +
  7 overrides -> 127 keys, exactly 3 intended collisions (Mod+T, Mod+D,
  Super+Alt+L), include lands after the stock `binds` block, idempotent on re-run.
- **There is NO CLI way to make niri generate the config.** `niri validate` calls
  `config_path(config).load()` (`main.rs:105`), NOT `load_or_create()`, so it never
  creates the file. Only actually starting a session does that. `--config` /
  `$NIRI_CONFIG` set `ConfigPath::Explicit`, which also never creates it.

### Upstream churn of `resources/default-config.kdl` (measured 25.02 -> 26.04)
- File 567 -> 632 lines; active lines 168 -> 184; binds 113 -> 124.
- Bind ACTIONS per release: +2/-0/~0, +3/-0/~5, +4/-0/~1, +2/-0/~1.
  **Total over 4 releases: added 11, REMOVED 0, changed 7.** Upstream is purely
  additive in this window, so a stale vendored copy can only ever LACK new
  binds, never hold removed ones.
- Most "changes" are cosmetic (`hotkey-overlay-title` text, or `spawn` ->
  `spawn-sh` with identical effect). The real semantic ones were
  `XF86AudioRaiseVolume` gaining `-l 1.0`, and `Mod+Shift+R` flipping from
  `switch-preset-window-height` to `switch-preset-column-width-back`.
- `Mod+T` -> alacritty, `Mod+D` -> fuzzel, `Super+Alt+L` -> swaylock have never
  changed target in any release; 25.05 only added the overlay titles.

### Distilling the stock `default-config.kdl`
- Stock file: **632 lines, 196 active**. Roughly 180 of the active lines are
  binds; the non-bind payload is ~30 lines (input numlock/tap/natural-scroll,
  layout, hotkey-overlay, screenshot-path, animations, 2 live window-rules).
- A naive comment strip is WRONG: the file contains **3 `/-<node> { ... }`
  disabled blocks** (the `eDP-1` output, a KeePassXC/World-Secrets
  `block-out-from "screen-capture"` rule, and a `geometry-corner-radius` rule).
  Their children are NOT prefixed with `/-`, so a line-level comment filter keeps
  them and emits broken KDL. Brace-match the `/-` node and drop the whole block.
- Result: 186 lines, identical behaviour, braces balanced 145/145, one `binds`
  block, 127 bind keys, zero duplicates.
- Stock config dead endpoints (nothing in the flake provides them): `alacritty`
  (Mod+T), `fuzzel` (Mod+D), `swaylock` (Super+Alt+L), `waybar`
  (`spawn-at-startup`), `playerctl` (4 media keys), `brightnessctl` (2 brightness
  keys), `orca`. `wpctl` is also dead without pipewire/wireplumber.

## Overriding niri binds inside a seeded config (verified against niri v26.04 source)
- niri default config (`resources/default-config.kdl`) hardcodes
  `Mod+T → spawn "alacritty"`, `Mod+D → spawn "fuzzel"`,
  `Super+Alt+L → spawn "swaylock"`. None are installed by the nixpkgs module,
  so they are silent no-ops. There is NO terminal option anywhere in
  `programs.niri`.
- **A second `binds {}` node in ONE file is a hard error**
  (`niri-config/src/lib.rs`: the repeated-node guard exempts only `output`,
  `spawn-at-startup`, `spawn-sh-at-startup`, `window-rule`, `layer-rule`,
  `workspace`, `include`; `binds` is not exempt → "duplicate node `binds`,
  single node expected"). The "later bind wins" replacement only happens across
  `[include]`d files. A duplicate KEY inside one `binds` node is also an error
  (`binds.rs` `seen_keys` → "keybind first defined here").
- ⇒ The SUPPORTED override is a separate file + `include` (below). Neither
  string surgery nor a second `binds` node in one file is needed.

## `include` — niri's supported way to override a seeded config (verified v26.04)
- Since **25.11**; `~/path` expansion and `optional=true` since **26.04**
  (nixpkgs 26.05 ships niri 26.04, so all of it is available). Top level ONLY —
  an `include` inside another section is an error.
- Path resolution: relative to the *including* file's dir (`./x.kdl`),
  absolute, or `~/`. `optional=true` downgrades a missing file to a log warning;
  a present-but-invalid file still fails.
- **Includes are POSITIONAL.** They override every setting written *before* them
  and are overridden by settings written *after*. To beat a stock bind, the
  include must sit AFTER the stock `binds {}` block (i.e. at the end of the seed).
- **`binds` merge across files = later key replaces earlier key**
  (`lib.rs`: `binds.retain(|b| !new.iter().any(|n| n.key == b.key))` then
  `extend`). So an included `binds { Mod+T { spawn "ghostty"; } }` replaces the
  stock `Mod+T` and leaves every other stock bind alone. Only list the keys you
  actually change — no need to reproduce 123 binds.
- Include files are watched; editing one live-reloads. So the override file can
  be a read-only HM store symlink and niri will still never write to it.
- Sections that do NOT merge across includes (they replace wholesale): `struts`,
  `preset-column-widths`, per-device `input` subsections, individual
  `animations` subsections. `window-rule`/`output`/`workspace` are multipart and
  are inserted at the include's position. Border special case: `layout { border {} }`
  enables the border in the MAIN config but is a no-op in an included file —
  included files need an explicit `on`.
- Ricer pattern (e.g. `ryan4yin/nix-config`): split config into
  `config.kdl` + `keybindings.kdl` + `windowrules.kdl` + …, the main file is a
  list of `include`s, and all of them are HM-managed. He uses
  `config.lib.file.mkOutOfStoreSymlink` so the `.kdl` files stay LIVE-EDITABLE
  from the repo working tree instead of read-only store paths — pick that when
  the user wants to iterate without a rebuild.
- The Nix-native alternative is **niri-flake** (`github:sodiboo/niri-flake`):
  `programs.niri.settings.binds."Mod+T".action.spawn = "ghostty";` (or
  `with config.lib.niri.actions; "Mod+D".action = spawn "fuzzel";`), plus
  declarative `outputs.*`, and it VALIDATES the config at build time against the
  installed niri version. It replaces the seed hack entirely. Tradeoffs: third-
  party input + its own cachix; upstream warns `programs.niri.settings` is only
  guaranteed against the two niri versions the flake provides (nixpkgs' niri may
  lag 2+ releases), whereas `programs.niri.config` (raw KDL/structured) is
  version-agnostic and still build-validated.

## niri bind-override landmines (kept: whoever does string surgery anyway)
- If you DO `builtins.replaceStrings` on the stock config text: the stock bind
  lines are indented by **4 spaces**, and a Nix indented string (`''…''`) strips
  its own leading whitespace — so a whole-line anchor silently matches nothing
  and the rewrite no-ops with no error. Match a mid-line substring instead, or
  use a double-quoted string. Verify anchors with `grep -n … | cat -A`.
- Free keys for Noctalia's documented binds: `Mod+Space`, `Mod+S`,
  `Mod+Shift+S`, `Alt+Tab`. **Not free:** `Mod+Comma`
  (`consume-window-into-column`), and every `XF86Audio*` / `XF86MonBrightness*`
  key (already bound to `wpctl` / `brightnessctl` in the default config —
  re-binding them raises a duplicate-keybind error).

## Noctalia v5 IPC / keybinds / terminal (verified on `main`, 2026-10)
- **Noctalia never creates compositor keybinds.** Upstream, verbatim: "Noctalia
  Settings does not create compositor keybinds. Keybinds belong in your
  compositor's configuration; Noctalia only receives the IPC command." A launcher
  that "won't open" is almost always an unbound key, not a bug.
- **v4 → v5 IPC rename:** `noctalia-shell ipc call launcher toggle` is dead. v5
  is `noctalia msg <command>` (binary renamed to `noctalia`). Launcher =
  `noctalia msg panel-toggle launcher`; also `panel-toggle control-center`,
  `settings-toggle`, `window-switcher`, `session lock-and-suspend`, `volume-up`,
  etc. Test the command in a terminal before binding it.
- The bar's launcher is just a widget: bar `start = ["launcher", …]`, config
  section `[widget.launcher]`, icon `grid-dots`. Clicking it runs the SAME
  `panel-toggle launcher` IPC. There is no separate "bar search" surface — the
  launcher panel holds the search box.
- Noctalia has NO shell-level "default terminal" setting. For `.desktop`
  `Terminal=true` apps and `runInTerminal()`, discovery order is: `$TERMINAL`
  (executable name or path ONLY — no `-e`; Noctalia appends `-e`, or `--` for
  gnome-terminal/kgx/ptyxis), else `x-terminal-emulator`, else a probe of
  Ghostty, Kitty, Alacritty, WezTerm, Foot, Konsole. `$TERMINAL` is the only
  preference knob that exists.
- Config layering: `~/.config/noctalia/*.toml` (declarative base, read-only-safe)
  then `~/.local/state/noctalia/settings.toml` (GUI overrides, WINS). An ignored
  hand-written value usually means a stale GUI override; delete or inspect the
  state file.

## boot.supportedFilesystems on 26.05 (semantics!)
- `nixos/modules/tasks/filesystems/ntfs.nix` on 26.05:
  `mkIf (supportedFilesystems.ntfs or supportedFilesystems.ntfs-3g or false)`
  → `system.fsPackages = [ pkgs.ntfs3g ]`. So `"ntfs"` STILL means ntfs-3g
  here. On master the meaning forks (kernel ≥7.1 `"ntfs"` → ntfsprogs-plus,
  separate `"ntfs-3g"` value) — re-check when moving to 26.11.

## home-manager 26.05 option rename: programs.git
- `programs.git.userName` → `programs.git.settings.user.name`
- `programs.git.userEmail` → `programs.git.settings.user.email`
- `programs.git.extraConfig` → `programs.git.settings`
- `programs.git.aliases` → `programs.git.settings.alias`
- `programs.git.signing.gpgPath` → `programs.git.signing.signer`
- Verified in `modules/programs/git.nix` on `release-26.05` (the old names still
  exist as `mkRenamedOptionModule` shims, so they warn rather than fail).
- Unchanged in 26.05: `programs.bash.{enableCompletion,initExtra,shellAliases}`,
  `home-manager.{useGlobalPkgs,extraSpecialArgs,users}`.

## Baseline CLI coverage on 26.05 (`nixos/modules/config/system-path.nix`)
- `environment.corePackages` = acl attr bashInteractive bzip2 coreutils-full cpio
  curl diffutils findutils gawk getent getconf gnugrep gnupatch gnused gnutar gzip
  xz less libcap ncurses netcat mkpasswd procps su time util-linux which zstd.
- `environment.defaultPackages` = perl rsync strace.
- => tar/gzip/bzip2/xz/zstd exist out of the box; **`zip`, `unzip` and `7z` do NOT**.
  Add `pkgs.zip`, `pkgs.unzip`, `pkgs.p7zip` for archives.
- There is NO `programs.p7zip` NixOS module in 26.05 — install via
  `environment.systemPackages`.

## lazygit on 26.05 — two modules, choose by layer
- NixOS `programs.lazygit` (`nixos/modules/programs/lazygit.nix`): `enable`,
  `package`, `settings` (yaml → `/etc/xdg/lazygit/config.yml`, system-wide).
- Home-manager `programs.lazygit` (`modules/programs/lazygit.nix`): `enable`,
  `package`, `settings` (→ `$XDG_CONFIG_HOME/lazygit/config.yml`),
  `enable{Bash,Fish,Zsh,Nushell}Integration`, `shellWrapperName` (default `lg`).
  `enable` alone installs the package + wrapper. Prefer HM for user identity.

## programs.git on 26.05 (both layers)
- NixOS module: `enable` installs `cfg.package` into `environment.systemPackages`;
  options `enable`, `package` (mkPackageOption, example `gitFull`), `config`
  (→ `/etc/gitconfig`, accepts attrset or ordered list), `prompt.enable`,
  `lfs.*`. NOTE: the system option is `config`, NOT `settings`.
- Home-manager module: `enable` adds git to `home.packages`; identity is
  `settings.user.{name,email}` (see the rename section above).

## hermes-agent flake (external input, verified on `main`, 2026-09)
- Input: `github:NousResearch/hermes-agent`. Pins `nixos-unstable`; set
  `inputs.nixpkgs.follows = "nixpkgs"` to keep one pin (upstream builds a uv2nix
  Python venv, so a release-branch nixpkgs may not resolve every dep — drop the
  follows line if the venv build fails).
- Exports `nixosModules.default` AND `homeManagerModules.default` (both share
  `nix/moduleCommon.nix`, so the option set is identical). It also has a
  `packages.{default,minimal,messaging,full,tui,web,desktop}` set.
- **Prefer the HOME-MANAGER module** for a single-user box (upstream's own
  rationale: config, memory, sessions and cron belong to one person).
  - `programs.hermes-agent.{enable,package,desktop.enable,desktop.package}` —
    the CLI + `HERMES_HOME` session variable (the installation).
  - `services.hermes-agent.{enable,hermesHome,settings,configFile,environment,environmentFiles,
    extraPackages,extraPlugins,extraPythonPackages,extraDependencyGroups,gateway.enable}` —
    state, `config.yaml`, `.env`, and the gateway unit.
  - `services.hermes-agent.settings` = deep-merged attrset rendered to
    `config.yaml`; `environmentFiles` = list of `.env` paths (runtime paths
    only — anything in a Nix expression lands in the world-readable store).
  - `services.hermes-agent.hermesHome` default is
    `"${config.home.homeDirectory}/.hermes"` — hermes does NOT use
    `XDG_CONFIG_HOME`; `HERMES_HOME` (else `~/.hermes`) is the state dir holding
    `config.yaml`, `.env`, `auth.json`, sessions, skills, memory, cron.
  - `environmentFiles` is `listOf str` (runtime paths, NOT `path` type — a path
    literal copies the secret into the world-readable store). Activation merges
    every listed file into `$HERMES_HOME/.env`, rewritten from scratch each
    activation (so a secret cannot land in `.env` twice). `environment` (plain
    attrs) merges into the same file.
  - Do NOT set `programs.hermes-agent.desktop.package` to a package from a
    second flake input: the default is `cfgPrograms.package.hermesDesktop` (the
    agent package's own passthru), which keeps the desktop's runtime identical to
    the CLI/service incl. `extraPythonPackages`/`extraDependencyGroups`. The
    module warns that a package you set here "carries its own Hermes runtime, and
    this module cannot make it agree with the services". A second input to the
    same repo yields the same derivation anyway (`packages.desktop ==
    packages.default.hermesDesktop`).
  - HM module requires `users.users.<name>.linger = true` on NixOS, or the user
    systemd units stop at logout (HM cannot run `loginctl enable-linger`).
- Version skew (the "0.0.0" reports): the agent package reads its version from
  `pyproject.toml` (correct, e.g. 0.21.0), while `web`/`tui`/`desktop` read their
  own `apps/*/package.json` (e.g. desktop 0.17.0, web 0.0.0). So flake-output
  version strings for the auxiliary apps can be wrong/placeholder — the
  CLI+gateway path is unaffected.
- `nix build .#desktop` fails on x86_64-linux: the renderer's source filter in
  `nix/desktop.nix` omits `tests/fixtures`, so `tsc -b` errors TS2307. Upstream
  issue #87930, fix PR #87395. Leave `desktop.enable` off until that lands.

- `nix build .#desktop` fails on x86_64-linux: the renderer's source filter in
  `nix/desktop.nix` (`dirs = [ "apps/desktop" "apps/shared" ]`) omits
  `tests/fixtures`, so `tsc -b` in the renderer's buildPhase errors TS2307 on
  `use-session-actions.test.tsx`. `dirs` is HARDCODED at the call site — there is
  no upstream argument to inject the missing dir from outside. Upstream issue
  #87930, fix PR #87395 (+5 lines) still open. Affects the module's
  `programs.hermes-agent.desktop.enable` AND the plain
  `nix run github:NousResearch/hermes-agent#desktop` output.
- Workaround that needs no vendoring: pin the flake input to the PR ref
  `github:NousResearch/hermes-agent/refs/pull/87395/head` (base-repo PR refs
  resolve on the base repo — verified `git/ref/pull/N/head` returns the head
  sha). Revert to the plain URL when the PR merges.

- Version 0.0.0 reports have TWO independent causes, do not conflate them:
  1. PM/git installs: the PM-built venv carries `hermes_agent-0.0.0.dist-info`,
     and `hermes_cli/security_audit.py::_discover_venv` reads `dist.version`, so
     `hermes security audit` reports `hermes-agent==0.0.0` and matches every
     advisory. Open upstream: issue #127610, fix PR #127614. Affects
     `hermes pm` / profile installs, NOT the flake build.
  2. Auxiliary packages read their own `apps/*/package.json` (`nix/web.nix`,
     `nix/tui.nix`, `nix/desktop.nix`) — desktop About reported 0.0.0 (issue
     #124581, fixed by PR #124994); web was 0.0.0, tui 0.0.1, desktop 0.17.0.
  The flake's own agent version = `(fromTOML ../pyproject.toml).project.version`
  (`nix/hermes-agent.nix:162`), which was `0.21.0` on main when checked — so a
  Nix-built CLI/TUI reports the real version.
- Locked git revision embedded as `HERMES_REVISION`; only set when `rev != null`
  (dirty trees get no revision).

## sops-nix (verified against `Mic92/sops-nix` master)
- Flake outputs: `nixosModules.{sops,default}`, `homeManagerModules.{sops,default}`.
- Pick by CONSUMER: a secret read by a **user** systemd unit →
  `homeManagerModules.sops`; a secret read by root/activation (e.g.
  `users.users.<n>.hashedPasswordFile`) → `nixosModules.sops`.
- HM module `modules/home-manager/sops.nix` options:
  `sops.defaultSopsFile`, `sops.defaultSopsFormat` (default `"yaml"`),
  `sops.defaultSopsKey`, `sops.defaultSymlinkPath` (default
  `"${config.xdg.configHome}/sops-nix/secrets"`), `sops.age.keyFile`,
  `sops.age.sshKeyPaths`, `sops.gnupg.*`, `sops.validateSopsFiles` (default true),
  and `sops.secrets.<name>.{name,key,path,format,mode,sopsFile}` with
  `path` default = `${defaultSymlinkPath}/${name}`, `mode` default `0400`.
- The whole `config` block is `lib.mkIf (cfg.secrets != { })` — importing the
  module with NO secrets declared is inert (no key source, no assertion). So the
  input + import can land before secrets exist; only `defaultSopsFile` must point
  at a file that exists, or eval fails.
- Only one key source may be set: `sops.gnupg.home`, `sops.gnupg.sshKeyPaths`,
  `sops.gnupg.qubes-split-gpg.enable` are mutually exclusive; `age.keyFile` /
  `age.sshKeyPaths` are the age-side equivalents.
- PITFALL: in `secrets/sops.yaml`, `creation_rules[].encrypted_regex` restricts
  which keys' VALUES are encrypted. A rule list like `^(data|password|token)$`
  leaves any other value (e.g. a `hermes-env:` block scalar) in PLAINTEXT in git.
  Omit `encrypted_regex` for files where every value is a secret.
- Keep plaintext artifacts out of git but let ciphertext in: ignore
  `secrets/*.hash`, `*.env`, `*.key`, `keys.txt` — NOT `secrets/` wholesale,
  because the encrypted `secrets/*.yaml` must be committed.
- `.gitignore` pitfall: a leading `/` anchors to the REPO ROOT, so
  `/etc/nixos/secrets/` matches `<repo>/etc/nixos/secrets/` and does NOT protect
  the machine path `/etc/nixos/secrets` — which, when the flake is deployed from
  `/etc/nixos`, is `<repo>/secrets/`. Ignore the artifacts (`/secrets/*.hash`),
  not the absolute path.

## filesystems.nix / NTFS landmines
- `fsType = "ntfs-3g"` uses FUSE and needs the ntfs-3g mount helper.
  On 26.05, `boot.supportedFilesystems = [ "ntfs" ]` adds `pkgs.ntfs3g`
  to `system.fsPackages`; a separate systemPackages entry is not required.
- `fsType = "ntfs3"` selects the kernel driver. It supports `uid`, `gid`,
  `umask`, `fmask`, and `dmask`: https://docs.kernel.org/filesystems/ntfs3.html.
- `fsType = "auto"` does not pin a driver. Inspect live mounts with `findmnt`.
- Mount options for an optional data volume can include `nofail`,
  `x-systemd.automount`, and ownership/mask options appropriate to the user.
- Read-only mounts can result from hibernation, dirty filesystems, errors, or
  explicit options. Disable Windows hibernation/Fast Startup when relevant;
  repair corruption with Windows `chkdsk`. Do not recommend clearing dirty flags
  or forcing a mount as a general repair.

## GPUs, unfree packages, and swapping vendor

### Enabling the NVIDIA driver — the minimum set (all 26.05-verified)
- `services.xserver.videoDrivers = [ "nvidia" ]` is THE switch:
  `hardware.nvidia.enabled` is `readOnly` and derived from it
  (`hardware/video/nvidia.nix:8,20`). X11 need NOT be enabled — this is how a
  Wayland-only host turns the driver on.
- `hardware.nvidia.open` MUST be set explicitly from driver 560 on: default is
  `null` for ≥560 and there is a hard assertion
  `cfg.open != null || cfg.datacenter.enable` (nvidia.nix:361-369, 417-422).
  Turing+ (RTX 20xx / GTX 16xx and newer) → `true`; Pascal and older → `false`
  plus a `legacy_*` branch.
- `hardware.graphics.enable` is NOT set by the nvidia module, by niri's module,
  or by xserver — the default is `false` (`hardware/graphics.nix`). Without it
  there is no `/run/opengl-driver` and everything falls back to software
  rendering. `hardware.opengl.*` is renamed to `hardware.graphics.*`.
- `hardware.nvidia.branch` default `"stable"` = highest stable (`production`,
  595.71.05 on this pin). Other values: `latest`, `bleeding_edge`, `beta`,
  `legacy_580`, `legacy_535`, `legacy_470`, `legacy_390`, `dc*`
  (`pkgs/os-specific/linux/nvidia-x11/default.nix`). `hardware.nvidia.package`
  overrides `branch`.
- `hardware.nvidia.modesetting.enable` default is the implicit
  `version >= 535` — pin `true` for Wayland. It makes the module set
  `nvidia-drm.modeset=1` (+ `fbdev=1` on ≥545) via `hardware.nvidia.moduleParams`,
  so NO manual `boot.kernelParams` is needed.
- GOTCHA: `boot.kernelModules = optionals config.services.xserver.enable
  [ "nvidia" "nvidia_modeset" "nvidia_drm" ]` (nvidia.nix:820). A Wayland-only
  host (niri passes `enableXWayland = false` and never sets
  `services.xserver.enable`) gets none of them force-loaded. List them yourself.
- `ibt=off` is auto-added for kernels ≥6.2 only when the driver lacks IBT
  support (≥530 drivers have it, so normally not added).

### Unfree: prefer `allowUnfreePackages` over `allowUnfree`
- `nixpkgs.config.allowUnfreePackages = [ "nvidia-x11" "nvidia-settings" ]`
  matches `lib.getName` = **pname** (`check-meta.nix` `listPredicate`) and,
  unlike `allowUnfreePredicate`, **merges additively** — so each module declares
  what it needs locally. This is the option nixos-generate-config itself emits
  (for `prl-tools`).
- Unfree pnames on the NVIDIA path: `nvidia-x11` (the driver,
  `unfreeRedistributable`), `nvidia-settings` (pushed into
  `environment.systemPackages` unconditionally while `nvidiaSettings`, default
  true), `nvidia-kernel-modules` (only when `open = false`). NOT unfree:
  `nvidia-persistenced` (MIT), the open kernel modules (`gpl2Plus` + `mit`),
  `nvidia-vaapi-driver`, `libXNVCtrl` (MIT).
- Extra license gate in `nvidia-x11/generic.nix`: throws `throwLicense` unless
  `nixpkgs.config.nvidia.acceptLicense`, but ONLY when
  `!acceptLicense && openSha256 == null` — i.e. only branches shipping no open
  modules (`legacy_470/390/340`). `stable` does not need it.
- Keep the unfree policy INSIDE the vendor module. A global `allowUnfree = true`
  masks a missing name and permanently attaches NVIDIA's unfree debt to a host
  that later swaps to AMD (ROCm is MIT → an AMD host needs zero unfree).

### Auto-detection is a dead end — upstream agrees
- `nixos-generate-config.pl` walks `/sys/bus/pci/devices/*` and DOES see vendor
  `0x10de` / class `^0x03`, then discards it:
  `# FIXME: do we want to enable an unfree driver here?` /
  `#$videoDriver = "nvidia" ...`. Detection is deliberately not emitted.
- Pure Nix cannot probe hardware: the flake evaluates on the BUILD host,
  `builtins` has no PCI access, and `builtins.readFile "/sys/..."` is impure →
  needs `--impure`, breaks `nix flake check`, remote builders and caching.
- Hardware probing is legitimate only as a RUN-ON-TARGET generator (same class
  as `hardware.nix`), and only pays for itself at N≥2 hosts.

### Swapping GPU vendor later (power off, change card, power on)
- A generation is a complete closure (kernel + all modules). Booting an NVIDIA
  generation with an AMD card works: the stale `nvidia*` modules load and bind
  nothing (modprobe returns 0 for a device-less module; `nvidia_uvm` may fail —
  log noise, nothing `Requires=` it), `amdgpu` is in the same kernel package and
  autoloads via udev. The only real breakage is X: it would try to load
  `videoDrivers = [ "nvidia" ]`, so avoid `services.xserver.enable` on a
  Wayland-only box.
- THE TRAP: `hardware.enableRedistributableFirmware` defaults **false** in 26.05
  (`hardware/all-firmware.nix`: `default = config.hardware.enableAllFirmware`).
  `amdgpu`/`i915`/wifi need `linux-firmware`; the NVIDIA driver ships its own
  firmware, so an all-NVIDIA box boots fine with the option off and then fails
  to initialise an AMD card after a swap. Set it `true` up front.
- `linux-firmware` is licensed `unfreeRedistributableFirmware`, which has NO
  `free = false` key (`lib/licenses/licenses.nix:1488`, with the note "we
  currently consider these 'free' for inclusion in the channel and NixOS
  images") → `check-meta`'s `isUnfree` does `!(licenses.free or true)` → treated
  as FREE → firmware needs no allowUnfree entry.
- Layout that makes the swap one line: `modules/gpu/graphics.nix`
  (vendor-neutral: `hardware.graphics.enable` +
  `hardware.enableRedistributableFirmware`), with `nvidia.nix` and `amd.nix`
  each doing `imports = [ ./graphics.nix ]`; the HOST imports exactly one. Put
  NO `default.nix` in that directory — then importing the directory fails to
  evaluate and "all vendors at once" is unrepresentable.
- `hardware.graphics.enable = true` always includes mesa (`graphics.nix` sets
  `hardware.graphics.package = mkDefault pkgs.mesa` and
  `driversEnv = [ cfg.package ] ++ extraPackages`), so rendering survives a swap
  even with the vendor module still enabled.

### Path gotcha, 26.05
- `lib/licenses.nix` MOVED to `lib/licenses/` (`default.nix`, `licenses.nix`,
  `helpers.nix`, `operators.nix`). Fetching the old path returns a 404 body, and
  `web_extract` reports "Content was inaccessible or not found" — use
  `curl` + local grep when a raw nixpkgs path 404s, and re-check the path under
  `pkgs/by-name/<2 letters>/<name>/package.nix` (many packages migrated there).
