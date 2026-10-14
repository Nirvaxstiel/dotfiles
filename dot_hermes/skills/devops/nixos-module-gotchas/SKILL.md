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
- `programs.noctalia` from `noctalia-shell.homeModules.default` (the package was mid-rename `noctalia`/`noctalia-shell`; the module sets the option internally, so use the module not a bare `enable` guess).
- Symlink landmine: HM-managed dotfiles (`~/.bashrc`, etc.) are store symlinks; editing them directly = wiped on rebuild. Put changes in the module (`programs.bash.initExtra` / `shellAliases`).

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
- **Third-party flakes often ship both halves.** Read the flake's `outputs` block:
  a `nixosModules.default` importing a different file from `homeModules.default`
  usually carries the same options at the system layer, including systemd user
  units and extra services the HM module never mentioned.
- **The tell that HM fights the dotfiles split** is integration-disable flags
  (`enableBashIntegration = false`, `enableZshIntegration = false`) whose only
  purpose is to stop HM writing `~/.bashrc`/`~/.zshrc`. They vanish with HM.
- **Mechanism swaps:** `home.activation` -> `system.activationScripts`,
  `home.stateVersion` -> `system.stateVersion`.
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

## Verification checklist before claiming "done" (no Nix on scaffold host)
- [ ] every `services.*`/`programs.*`/`boot.*` option traced to its 26.05 source module
- [ ] modules with `options` key wrap config in `config = { }`
- [ ] `hardware.nix` generated on-target (root fs defined)
- [ ] password via `hashedPasswordFile` + gitignored secrets dir, or sops-nix
- [ ] imports resolve (no typo'd filenames like hardware-configuration.nix)
- [ ] only remaining "TODO" are real-value fill-ins (UUIDs, identity strings) — documented, not structural
