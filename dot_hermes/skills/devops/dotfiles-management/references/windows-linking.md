# Linking dotfiles on Windows (and the manager comparison)

## Measured behaviour, Windows 11 under MSYS/git-bash

| Attempt | Result |
|---|---|
| `ln -s <dir> link` (MSYS default) | **silently COPIES.** Not a link. This is the trap |
| `MSYS=winsymlinks:nativestrict ln -s` | `Operation not permitted` — no symlink privilege (Developer Mode off) |
| `cmd /c mklink /J` through MSYS | mangled by path translation; creates nothing |
| `powershell -NoProfile -Command "New-Item -ItemType Junction -Path P -Target T"` | **works, no admin.** MSYS reports it as a symlink; write-through confirmed |
| hardlink (`ln file link`) | works, no admin — files only, same volume |

So on a Windows box with no Developer Mode:
- Every symlink-based manager is unusable. Do not propose one without checking.
- Directory mapping is still possible with no admin, via a PowerShell junction.

Junction recipe (directories only, target must not already exist):
```bash
powershell -NoProfile -Command "New-Item -ItemType Junction -Path '<target>' -Target '<source>'"
```
Removing one: unlink the junction, never `rm -rf` it.

## Manager comparison

| Tool | Mechanism | Windows-viable |
|---|---|---|
| stow | symlink farm | no |
| dotter | symlinks + templating | no |
| rcm | symlinks | no |
| dotbot | script-driven symlinks | no |
| chezmoi | source dir, then `apply` writes real files | yes |
| yadm | `$HOME` is the worktree, files in place | yes |
| bare git repo | same as yadm, no tooling | yes |

Home-manager has **no** module for chezmoi, stow, yadm or dotter — each is
install-the-package and drive it yourself. All of the above are packaged in
nixpkgs, so install them with `home.packages` or `environment.systemPackages`.

## yadm

- No symlinks and no source directory: `$HOME` IS the worktree, so
  `~/.config/<app>/config.toml` is simply the tracked file. This removes the
  mapping problem instead of solving it.
- Git-native, so it matches "edit the live file, then commit in place".
- `file##os.Linux` / `file##os.Windows` alternates handle per-OS differences
  with no branches.
- `yadm.alt-copy = true` makes alternates copies instead of symlinks —
  upstream's own documented answer for systems that cannot make symlinks.
- It is a POSIX shell script, so on Windows it runs under git-bash.
- Bootstrap: `yadm clone <url>`. The repo lives at
  `~/.local/share/yadm/repo.git`. Set `yadm config status.showUntrackedFiles no`
  or `$HOME` floods `status`.

Tool-free equivalent, if no tool is wanted:
```
git clone --bare <url> ~/.dotfiles
git --git-dir=$HOME/.dotfiles --work-tree=$HOME checkout
git --git-dir=$HOME/.dotfiles --work-tree=$HOME config status.showUntrackedFiles no
```

## Nix integration

```nix
home.packages = [ pkgs.yadm ];
home.activation.dotfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  if [ ! -e "${config.home.homeDirectory}/.local/share/yadm/repo.git" ]; then
    run ${pkgs.yadm}/bin/yadm clone <url>
  fi
'';
```

Two hazards:
- **Checkout conflicts** — the clone only lands cleanly on a fresh machine; a
  configured box needs the existing files removed or `--force` accepted.
- **One owner per path** — the flake must own no path yadm owns, or the two
  fight on every rebuild.
