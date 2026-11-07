---
name: nixos-module-gotchas
description: Recurring NixOS flake/module pitfalls (top-level options/config clash, greetd API, niri-session deprecation noise) and the verify-against-source-first workflow for scaffolding NixOS configs. Use when building/editing NixOS flake configs, modules, or home-manager trees.
---

# NixOS Module Gotchas & Verification Workflow

## When to use
Scaffolding or editing a NixOS flake: `flake.nix`, `modules/**`, `hosts/**`, `home/**` (home-manager), display managers, wayland compositors (niri/hyprland), secrets.

## Core rule: verify every option against upstream source, not memory
Option names drift between releases. A wrong option = eval failure on-target (you can't always `nix flake check` locally, e.g. on Windows). Before committing an unknown option:
1. `web_search` the option name + release branch (e.g. `nixos-26.05`, `home-manager release-26.05`).
2. `web_extract` the raw module file from the matching branch, e.g.
   `https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-26.05/nixos/modules/services/...`
   `https://raw.githubusercontent.com/nix-community/home-manager/release-26.05/modules/...`
3. Read the `options = { ... }` block to confirm exact attr paths + types.

When fetching raw module source with `curl` (needed when `web_extract` truncates),
write to `/tmp/<file>` or `$TMPDIR` — both are ordinary writable paths on NixOS.

A file in `~/.hermes/cache/scratch` is NOT durable across tool calls: entries
idle >24h are pruned, and it deleted a mid-analysis baseline twice in one
session. Fetch what you need inside a single `execute_code` call, or read the
source directly there — never stage an analysis across calls through scratch.

## Gotcha 1: top-level `options` + top-level config shorthand is REJECTED
A module may use EITHER:
- pure shorthand: top-level `services.foo = {...};` (no `options` key), OR
- explicit shape: `options = {...}; config = { services.foo = {...}; };`
Mixing them — declaring a top-level `options` key AND writing `services.foo = {...}` at the top level — fails with:
`error: Module '.../foo.nix' has an unsupported attribute 'services'. This is caused by introducing a top-level 'config' or 'options' attribute. Add configuration attributes immediately on the top level instead, or move all of them (namely: services) into the explicit 'config' attribute.`
FIX: wrap the config in `config = { ... }`.
(Search landed here via greetd.nix which declared `options.services.greetd.user` then set `services.greetd` at top level.)

## Gotcha 2: greetd (display manager) API — verified 26.05
- `services.greetd.enable = true;`
- Session via `services.greetd.settings.default_session = { command = "..."; user = "kei"; };`
  - `command` is the full session launch, e.g. `${config.programs.niri.package}/bin/niri-session`.
  - `user` defaults to `"greeter"`; override to your real user.
- greetd sets `services.displayManager.enable` + starts `graphical.target`.
- Flip/remove a DM: drop its module import from the services aggregator — no cross-file edits.

## Gotcha 3: `niri-session` "import-environment without a list of variable names is deprecated"
Post-login stderr noise, NOT a config defect. The `niri-session` script inside the `niri` package calls `systemctl --user import-environment` / `dbus-update-activation-environment --all` with no var list; systemd deprecated the blanket form (systemd PR #18137). Trigger: greetd `default_session.command = niri-session`, or any DM launching niri-session.
- Harmless. Upstream niri issue #254/#3901, fix PR #3572 (enumerates vars) not yet in all nixpkgs releases.
- DO NOT patch the flake for this. Only consider a nixpkgs overlay that rewrites `niri-session` if the noise truly blocks something (fragile, breaks on upstream fix).

## Gotcha 4: hardware.nix is a generated artifact, not hand-authored
- `nixos-generate-config --show-hardware-config > hosts/<host>/hardware.nix` emits `fileSystems."/"`, `boot.loader.*`, `hardware.*`. Without it, rebuild fails:
  `error: The 'fileSystems' option does not specify your root file system.`
- Keep machine-specific stubs (NTFS mounts etc.) in a SEPARATE file (e.g. `storage.nix`) so re-running generate-config (which overwrites `hardware.nix` via `>`) doesn't clobber them.
- Import name in `configuration.nix` must match the generated filename exactly (`hardware.nix`, not `hardware-configuration.nix`).

## Gotcha 5: password safety without committing secrets
- Use `users.users.<name>.hashedPasswordFile = "/etc/nixos/secrets/<user>.hash"` (NOT deprecated `passwordFile`, NOT literal `initialHashedPassword` in repo).
- The file is read at activation, NEVER copied to the nix store, never in git (gitignore `/etc/nixos/secrets/`).
- Helper: prompt with `read -s`, hash via `mkpasswd -m sha-512 --rounds=656000 -s` (nixpkgs `mkpasswd`), write mode 600, then `nixos-rebuild switch`.
- sops-nix is the fleet-scale upgrade (encrypted per-recipient); overkill for a single VM scaffold.

## Gotcha 6: home-manager layout (26.05)
- Pin `github:nix-community/home-manager/release-26.05`, `inputs.nixpkgs.follows = "nixpkgs"`.
- Bridge: `home-manager.nixosModules.home-manager` + `useGlobalPkgs = true` + `extraSpecialArgs = { inherit inputs; }` + `users.<name> = import <home tree>;`.
- One `nixos-rebuild switch` builds system + HM in one invocation but HM activates as a SEPARATE user activation phase (not one ACID transaction).
- HM has NO niri module in 26.05 (PRs #7534/#8575 draft) — configure niri at the system layer.
- `programs.noctalia` from `noctalia-shell.nixosModules.default` — the flake ships
  both halves, and the NixOS one carries `recommendedServices.enable`
  (NetworkManager, Bluetooth, UPower, power profiles) that the HM module never
  mentions. The package was mid-rename `noctalia`/`noctalia-shell`; the module
  sets the option internally, so use the module not a bare `enable` guess.
- Symlink landmine: HM-managed dotfiles (`~/.bashrc`, etc.) are store symlinks,
  so an in-place write fails or is replaced by a real file. The next switch does
  NOT silently clobber it — it fails loudly with a remedy menu. Put changes in
  the module (`programs.bash.initExtra` / `shellAliases`) rather than editing the
  live file.

## Gotcha 7: niri config seeding and `include`
- niri writes `~/.config/niri/config.kdl` from its own bundled
  `resources/default-config.kdl` ONLY when the file is absent —
  `File::options().create_new(true)` with `AlreadyExists => return Ok(())`. It
  never rewrites an existing config and has no GUI editor; runtime changes go
  through `niri msg` IPC and are not persisted. A seed script guarded by
  `if [ ! -e "$target" ]` is therefore correct and mirrors the app's semantics.
- That stock default ships in the package's **`doc` output** at
  `$doc/share/doc/niri/default-config.kdl` (verified 26.05). Reference
  `${config.programs.niri.package.doc}` rather than vendoring a copy, so the
  seeded config cannot fall behind the installed version.
- `include` accepts **`optional=true`** and expands `~` (verified in
  `niri-config/src/lib.rs`). Use it when the included file belongs to a dotfiles
  manager: without `optional`, a machine that has activated NixOS but not yet
  applied chezmoi fails to start niri on the missing include.

## Auditing whether home-manager still earns its place
When dotfiles live in a separate manager, HM's remaining job can shrink to
"install packages, and be stopped from writing files the dotfiles repo owns."
Audit before keeping it — the split often makes HM redundant:

- **An `enable = true` with no other keys is a package install.** Replace it with
  `environment.systemPackages`, or `users.users.<name>.packages` when the tool is
  a user tool rather than a system one.
- **Check the NixOS layer before assuming HM is required.** List
  `https://api.github.com/repos/NixOS/nixpkgs/contents/nixos/modules/programs?ref=<branch>`
  — `git`, `lazygit`, `vim` and `firefox` exist there; most app configs do not,
  and do not need to.
- **`programs.git` exists at BOTH layers with DIFFERENT options.** HM has
  `settings` (writes `~/.gitconfig`); NixOS has no `settings` at all — only
  `config`, which writes **`/etc/gitconfig`**, so a NixOS-side identity applies to
  every user including root. `programs.lazygit.settings` does exist at the NixOS
  layer and likewise writes `/etc`.
- **`system.activationScripts` is the NixOS twin of `home.activation`**, shaped
  `{ deps = [ ... ]; text = "..."; }`. It runs as ROOT, so a script writing into
  `$HOME` must `install -o <user> -g <group>` and chown, or the user ends up with
  a root-owned config they cannot edit. Set `deps = [ "users" ]` so the account
  exists before the script runs.
- **Third-party flakes often ship both halves.** Read the flake's `outputs` block:
  a `nixosModules.default` importing a different file from `homeModules.default`
  usually carries the same options at the system layer, including systemd user
  units and extra services the HM module never mentioned.
- **The tell that HM fights the dotfiles split** is integration-disable flags
  (`enableBashIntegration = false`, `enableZshIntegration = false`) whose only
  purpose is to stop HM writing `~/.bashrc`/`~/.zshrc`. They vanish with HM.
- **Mechanism swaps:** `home.activation` -> `system.activationScripts`,
  `home.stateVersion` -> `system.stateVersion`.
- **Dropping HM collapses the module tree.** A `modules/<feature>/nixos.nix` +
  `home-manager.nix` pair exists only because both layers read the same feature;
  with HM gone each becomes a single `modules/<feature>.nix` imported directly
  by `hosts/.../configuration.nix`, and `home/<user>/home.nix` disappears
  entirely. Flatten in the SAME change that drops HM, or you leave empty
  directories, stale import paths and an orphan module behind. Grep the whole
  tree for `home-manager`, `homeManagerModules`, `xdg.configFile` and
  `home.activation` afterwards — a module left unreferenced still evaluates
  fine and only breaks when someone re-imports it.
- Dropping HM also removes the two-phase activation risk: HM activates as a
  separate user phase, so a failed second phase leaves the system already switched.

## Config-generation libraries vs a live-editable dotfile split
A library that renders app config from Nix and points the app at it through an
env var can serve either side of the split — but only if it accepts a path
outside the store. Check that before adopting: a generator that hardcodes a store
path creates a read-only symlink at the app's config path, which is the exact
anti-pattern a dotfiles split exists to avoid. A flake whose module does
`xdg.configFile."<app>/config"` with a store `source` has made that choice for
you, whatever else it offers.

The capability that makes such a library worth adopting is a real module system
(`lib.evalModules` + your own `mkOption`s), because it expresses configuration
that CANNOT live in the app's own config file at all — CLI flags, env vars, and
runtime PATH dependencies. A flat attrset API of flags and env gives you neither
the typed surface nor the file-location choice, so you would be writing your own
option layer on top of it anyway.

## Gotcha: niri's `useNautilus` only wires the D-Bus portal

`programs.niri.useNautilus = true;` (the default) adds `pkgs.nautilus` to
`services.dbus.packages` for the FileChooser portal and switches the portal impl
to `gnome`. It does NOT put the Nautilus binary or desktop entry in
`environment.systemPackages`.

A standalone Nautilus needs the package explicitly, plus `services.gvfs.enable`
and `programs.dconf.enable` for trash/network/media and settings persistence.
See the `nixos-flake-config` skill's `niri-nautilus-noctalia.md` reference for
the full recipe.

## Verification checklist before claiming "done" (no Nix on scaffold host)
- [ ] every `services.*`/`programs.*`/`boot.*` option traced to its 26.05 source module
- [ ] modules with `options` key wrap config in `config = { }`
- [ ] `hardware.nix` generated on-target (root fs defined)
- [ ] password via `hashedPasswordFile` + gitignored secrets dir, or sops-nix
- [ ] imports resolve (no typo'd filenames like hardware-configuration.nix)
- [ ] only remaining "TODO" are real-value fill-ins (UUIDs, identity strings) — documented, not structural
