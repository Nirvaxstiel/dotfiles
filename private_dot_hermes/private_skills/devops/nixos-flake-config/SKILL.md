---
name: nixos-flake-config
description: Use when editing NixOS flakes. Verify source and builds.
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
4. **Choose the source policy before editing host files.** Machine-specific
   identifiers are not credentials. Track per-host configurations when recovery
   and multi-host use are the goal. When the user wants a reusable tracked
   blueprint with private local values, use tracked modules that require ignored
   `<feature>.local.nix` imports. Do not use permanent stashes or Git index flags
   as a configuration layer. A new machine still needs its own hardware, mounts,
   and vendor settings; ignoring files does not make a host portable.
5. **Preserve generated hardware.** Generate into the actual hardware artifact,
   not its tracked wrapper. Keep root, boot, and swap in that artifact; keep
   additional persistent mounts in the separate storage artifact. Before replacing
   device names with UUID paths, verify each device with `lsblk` and `findmnt`;
   preserve the driver and options unless a change is requested.
6. **Separate build from activation.** Run real evaluation and build checks,
   inspect the resulting configuration, and report whether activation occurred.
   When the user reserves authentication, leave `sudo nixos-rebuild switch` and
   credential setup to them.
7. **Don't invent nice-to-haves.** Only add what was asked. A missing display
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
- **Noctalia's NixOS module exposes no template options.** It starts the shell
  and its recommended services; GTK/Qt app theming lives in Noctalia's own
  `~/.config/noctalia/config.toml` (`[theme.templates] builtin_ids = [ "gtk3" "gtk4" ]`).
  GUI changes in `~/.local/state/noctalia/settings.toml` override that file.
  Do not search for a NixOS option to enable GTK templates.
- **greetd `default_session.user`** defaults to the system user `"greeter"`
  (created by the greetd module). Override it to a real user or the session has
  no account to start. greetd auto-sets `services.displayManager.enable` and
  `systemd.defaultUnit = graphical.target` — no extra DM wiring needed.
  To flip/remove: it's one import line in `modules/services/default.nix`; swap
  the compositor by changing `command` to another session binary.
- **No user module = no login.** greetd needs an existing `users.users.<name>`.
  Generate the password hash with `mkpasswd -m sha-512 --rounds=656000`; for a
  vault-minded setup, read it from sops-nix instead of inlining.
- **NTFS drivers and repair.** `fsType = "ntfs-3g"` uses FUSE and requires
  the ntfs-3g mount helper; NixOS `boot.supportedFilesystems = [ "ntfs" ]`
  supplies it on 26.05. `fsType = "ntfs3"` selects the kernel driver, which
  supports `uid`, `gid`, and `umask` (https://docs.kernel.org/filesystems/ntfs3.html).
  `fsType = "auto"` does not guarantee which driver is selected; inspect `findmnt`.
  A read-only mount has several possible causes. Disable Windows hibernation/Fast
  Startup when relevant; use Windows `chkdsk` for repair, not blanket `ntfsfix -d`.
- **An NTFS mount without `uid`/`gid`/`umask` is not writable by your user, and
  the app gets blamed.** ntfs3 derives modes from the on-disk NTFS ACLs, so
  subdirectories come out root-owned at `0755` while the volume root may be
  `0777`. Prove it before touching the application: `ls -ld` the directory and
  `touch` a probe file as the desktop user; a root-owned file plus `Permission
  denied` is the entire diagnosis. `chown`/`chmod` on NTFS do nothing — ownership
  is per mount. The mask changes the Linux view only, so a Windows dual-boot is
  unaffected. Choosing between a mount mask and copying the file to POSIX
  storage (one master vs two that drift, and the Fast Startup read-only trap that
  comes with sharing) is covered in
  `references/filesystem-ownership-and-sharing.md`; that file also carries the
  hash-and-keyfile procedure for relocating a password database.
- **Ignored local modules need an explicit path source.** Use
  `--flake path:/absolute/repo#host` for this design; normal Git sources exclude
  ignored files. Require the imports, initialize empty modules with `{}` rather
  than zero bytes, and back up local artifacts outside Git. Audit all source-tree
  files, including ignored files, before evaluation: `path:` also copies ignored
  secrets into the world-readable store. Follow
  `references/local-artifacts.md` for setup and verification.
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

## Nix profile hygiene (verified)
A flake installed with `nix profile install` is the LIVE binary source —
`~/.nix-profile/bin/*` symlinks into its store path. Editing/rebuilding that
flake changes the running install; nothing else. Check before acting:

```
nix profile list | grep '^Name:'        # elements + priorities
readlink -f ~/.nix-profile/bin/<bin>   # which element actually wins
ps -eo pid,cmd | grep <bin>            # what the running process execs
```

- **Priority decides collisions.** Lowest priority number wins; the loser's
  same-named binaries are shadowed, not removed.
- **A duplicate profile element is a hidden dependency.** Before
  `nix profile remove <element>`, diff its `bin/` against the system profile:
  `for b in $(ls <element>/bin); do [ -e /run/current-system/sw/bin/$b ] || echo UNIQUE:$b; done`
  Anything unique must move into `environment.systemPackages` and be rebuilt
  BEFORE the element is removed. Removing first breaks whatever needs it.
- **No-op upgrades look like success.** `nix build .#default --print-out-paths`
  returning the already-installed store path means `nix profile upgrade`
  rebuilds nothing. Say so instead of reporting a fix.
- **Overriding `version` on a derivation does not change Python wheel
  metadata.** The derivation name becomes `<pkg>-<version>`, but the built
  `.dist-info`/install stamp still says whatever `pyproject.toml` said. A tool
  that reports its version from installed metadata keeps printing the old
  value. Fix it by patching the dist-info post-install in the flake, not by
  re-locking. Trace first: reported version -> install-root function -> wrapper
  env var -> python derivation -> site-packages symlinks -> `*.dist-info/METADATA`
  -> source `pyproject.toml`. The last two are what to patch.
- **A commented-out flake input is a deliberate boundary.** A system rebuild
  neither installs nor removes that package; keep profile-managed and
  system-managed installs separate or they fight.
- **A packaged app's launcher can pin its own copy of a dependency.** GUI
  wrappers hardcode the path they spawn (`HERMES_DESKTOP_HERMES`, `*_BIN`), taken
  from the derivation's own dependency. `override { <dep> = fixed; }` is accepted
  and still leaves the old store path in the generated wrapper, so the CLI looks
  patched while the app's child processes are not. Grep the wrapper for the store
  path after any override; if it is stale, wrap the package and rewrite that line.
- **Verify which process actually runs before declaring a fix effective.**
  `pgrep -af` shows the exec'd store path and `tr '\0' '\n' </proc/<pid>/environ`
  shows the launcher env it inherited. A service started before the rebuild, or
  spawned by a different package, keeps reproducing the old failure and makes a
  correct fix look broken.
- **A silent `override` is not a proven `override`.** Build the output and grep
  it for the store path you expect; arguments that exist can still be dropped by
  a string that was snapshotted into a wrapper at build time.

## Verification on the target box

Use the source type selected for the repository. For ignored local artifacts:

```bash
nix flake check --no-write-lock-file --no-build path:/absolute/repo
nix build --no-write-lock-file --no-link --print-out-paths \
  'path:/absolute/repo#nixosConfigurations.HOST.config.system.build.toplevel'
```

When `sudo` is unavailable and a full `nixos-rebuild` is the user's step, still
prove the module itself parses and carries the shape you intended — no privileges
needed, and it catches a malformed option list before the rebuild does:

```bash
nix-instantiate --eval --strict --json hosts/<host>/storage.local.nix
```

For fully tracked configurations, a normal Git-backed source is appropriate.
Inspect the built settings and binaries before claiming success. Activate only
when authorized; otherwise provide the exact `nixos-rebuild switch` command.
Resolve required hardware imports, user creation, password provisioning, and
real device definitions before activation.

## References
- `references/nixos-26.05-verified-options.md` — option names/paths confirmed
  against the `nixos-26.05` branch module source this session.
- `references/filesystem-ownership-and-sharing.md` — why an NTFS mount is
  unwritable for the desktop user even though the app opened the file, the
  mount-mask vs copy-to-POSIX decision table, relocating a password database
  with its keyfile, and reverting an un-applied fstab change.
- `references/niri-nautilus-noctalia.md` — Nautilus under niri with Noctalia:
  packages, services, GTK template IDs, and chezmoi ownership traps.
- `references/python-apps-with-own-package-manager.md` — a Python app whose
  runtime package manager (uv/pm) needs a project tree and tool store that the
  wheel does not ship: missing locks, drift checks that ignore PATH, prebuilt
  binaries that fail the Nix loader, the venv-overlay fix, the system-tool
  override map, extension dependencies in per-root generation venvs, and the
  launcher that pins a different copy of the app.
