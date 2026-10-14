---
name: nixos-flake-config
description: Scaffold or extend a NixOS flake-based configuration using a DDD "infrastructure-as-code" structure, verifying EVERY option name against the pinned release-branch module source before writing it. Use when building flake.nix / hosts / modules for NixOS, adding services (greetd, niri, noctalia-shell, udisks2, gvfs, ntfs mounts), or auditing/confirming NixOS option names for a specific release.
---

# NixOS Flake Config (DDD style)

Author NixOS configs as a high-integrity codebase. The flake is the bounded
context; hosts are aggregates; `modules/` are domain models; `secrets/` is the
vault. Code over config: if you'd manually change a setting on the box, you've
failed — add it to a module and rebuild.

## When to use
- Scaffolding a new NixOS flake repo from scratch.
- Adding a host, module, or service to an existing flake.
- Confirming an option name / attr path is valid for the pinned NixOS release
  (NEVER trust memory or a wiki snippet alone).

## Core workflow
1. **Pin the release branch.** `nixpkgs.url = "github:NixOS/nixpkgs/nixos-<ver>"`
   (e.g. `nixos-26.05`). Verify the branch exists (web_search "NixOS <ver>
   released") before committing it.
2. **VERIFY every option against upstream source.** This is mandatory, not
   optional. `web_extract` the raw `.nix` module from the SAME branch the flake
   pins:
   `https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-<ver>/nixos/modules/<path>.nix`
   Confirm the option exists and read its exact type/shape. This catches the
   "I remember it being X" failures. See `references/nixos-26.05-verified-options.md`
   for facts already verified this way.
3. **Keep purity.** Flake inputs that also need nixpkgs must
   `inputs.nixpkgs.follows = "nixpkgs"` so the whole tree builds from one pin.
   Add the dependency's binary cache to `nixConfig.extra-substituters` /
   `extra-trusted-public-keys` (e.g. `https://noctalia.cachix.org`).
4. **Clobber-safety.** `nixos-generate-config --show-hardware-config` prints to
   stdout and you choose the filename via the redirect
   (`> hosts/<h>/hardware.nix`). NEVER hand-write into that file — a later
   regenerate overwrites it. Put host-specific stubs (NTFS mounts, etc.) in a
   SEPARATE file (e.g. `hosts/<h>/storage.nix`) imported by `configuration.nix`.
5. **Don't invent nice-to-haves.** Only add what was asked. A missing display
   manager / user / network manager is a real blocker to flag, not something to
   silently fill in.

## Structure (DDD)
```
flake.nix                 # inputs (pin nixpkgs), outputs → nixosConfigurations.<host>
hosts/<host>/
  configuration.nix       # root aggregate: imports hardware + storage + module dirs
  hardware.nix            # generated value object (regenerate on-target, do NOT hand-edit)
  storage.nix             # host-specific mounts (persists across regen)
modules/
  core/        default.nix → nix.nix, git.nix, user.nix
  desktop/     default.nix → niri.nix, noctalia.nix
  services/    default.nix → filesystems.nix, greetd.nix
secrets/sops.yaml         # vault routing (public keys / creation_rules only)
```

## PITFALLS (verified the hard way)
- **Noctalia Shell is NOT a compositor.** It's a Quickshell-based *shell* that
  runs ON TOP of a Wayland compositor. Enable niri (or hyprland) separately.
  Consume via `inputs.noctalia-shell.packages.${pkgs.stdenv.hostPlatform.system}.default`.
  The NixOS/Home-Manager module option name is mid-rename
  (`programs.noctalia` vs `programs.noctalia-shell`) and the NixOS module is
  deprecated — prefer the package path.
- **greetd `default_session.user`** defaults to the system user `"greeter"`
  (created by the greetd module). Override it to a real user or the session has
  no account to start. greetd auto-sets `services.displayManager.enable` and
  `systemd.defaultUnit = graphical.target` — no extra DM wiring needed.
  To flip/remove: it's one import line in `modules/services/default.nix`; swap
  the compositor by changing `command` to another session binary.
- **No user module = no login.** greetd needs an existing `users.users.<name>`.
  Generate the password hash with `mkpasswd -m sha-512 --rounds=656000`; for a
  vault-minded setup, read it from sops-nix instead of inlining.
- **ntfs-3g is FUSE.** `fsType = "ntfs-3g"` requires `pkgs.ntfs3g` in
  `environment.systemPackages`. Alternatively use the in-kernel `fsType = "ntfs3"`
  and DROP `uid`/`gid`/`umask`. Emergency: read-only mount ⇒ Windows "Fast
  Startup" dirty bit; fix with `powercfg /h off` in Windows or `ntfsfix -d`.
- **Enabling NVIDIA (or any unfree driver) is its own domain.** Verify against
  source: `hardware.nvidia.open` is MANDATORY from driver 560 (assertion, not a
  default), `hardware.graphics.enable` must be set by you, and the unfree policy
  belongs in the vendor module via the additive
  `nixpkgs.config.allowUnfreePackages` — never a global `allowUnfree`. Also check
  `hardware.enableRedistributableFirmware`, which defaults FALSE and is what
  lets a future AMD/Intel card initialise. See
  `references/nixos-26.05-verified-options.md` → "GPUs, unfree packages, and
  swapping vendor".
- **`nix flake check` cannot run on a non-Nix host** (e.g. Windows/MSYS). The
  real validation happens on the target box. NEVER fabricate a successful build
  result — say explicitly it's unverified and hand over the exact commands.

## House style (repo conventions, enforced by the user)
- **COMMENTS MEAN WEAK ARCHITECTURE.** The default is no comment. Nothing gets a
  comment for being explained; it gets one only if it is a **pitfall** (a
  non-obvious failure mode a competent reader would hit) or a **needed
  side-effect** (why this line is required to make something else work).
  - KEEP: `extraPackages = [ pkgs.uv ];` with "the jcodemunch MCP server below
    uses uvx, which ships in uv" — a needed side-effect.
  - KEEP: `services.tumbler.enable` / `useNautilus = false` / `linger = true` /
    the greetd-vs-user name match — each names what breaks without it.
  - DELETE: "git writes these into every commit" above `settings.user`. Everyone
    knows git. Do not comment the obvious.
- **Comments are written for a FIRST-TIMER.** Self-contained: never reference a
  design discussion, an earlier version, or a mechanism not present in the file.
  "niri writes this file itself, so a home-manager symlink would collide" fails,
  because the reader has no idea why a symlink is in play.
- **No banner labels.** `TRIVIA:`, `FILL:`, `FILL-UUID:`, `EMERGENCY:`,
  `CAUTION:`, `NOTE:`, `SECURITY:` are a self-invented dialect from an earlier
  agent session. They read as a personal scratchpad. Delete the label, keep the
  sentence that states the constraint.
- **No commented-out code.** Git is the archive.
- **An EMPTY or stub file is legitimate when it gives direction** — the user
  wants them kept. `hosts/<h>/storage.nix` evaluates to `{}` with a commented
  mount template and "read the UUID with `ls -l /dev/disk/by-uuid/`, then
  uncomment" is exactly right. Do NOT delete it as dead weight, and do not
  "fix" it by making the mounted block live.
- **No placeholder values that evaluate.** `REPLACE_WITH_GIT_NAME` ships and
  silently produces a wrong git identity. Make it an option or an assertion.
- Comments go INSIDE the module body, never above the `{ config, ... }:` header.
- Naming: `bin/*.sh` is kebab-case, `#!/usr/bin/env bash` + `set -euo pipefail`,
  one `<verb>-<object>.sh` per action, no positional args. `default.nix` is an
  aggregator only. `git.nix`/`niri.nix` existing in BOTH `modules/` and
  `home/<user>/modules/` is fine — the directory is the layer marker.
  A path under `home/<user>/config/` maps to the same path under
  `$XDG_CONFIG_HOME`; do not use a vague `files/` directory.
- **Line endings: `.gitattributes` must pin `* text=auto eol=lf`.** Editing on
  Windows with `core.autocrlf=true` and no `.gitattributes` silently rewrites
  `bin/*.sh` to CRLF on checkout, and the shebang then fails on Linux with
  "bad interpreter: /usr/bin/env bash^M". Related trap when generating files:
  Python's `Path.write_text` translates `\n` to CRLF on Windows — pass
  `newline=""`, or the generated `.kdl`/`.sh` lands CRLF while every hand-edited
  file is LF.

## Verification on the target box
```
nix flake check --no-build
sudo nixos-rebuild switch --flake .#<host>
```
Pre-flight blockers to resolve first: generate `hardware.nix`, create the user,
set the password hash, fill any UUID stubs.

## References
- `references/nixos-26.05-verified-options.md` — option names/paths confirmed
  against the `nixos-26.05` branch module source this session.
