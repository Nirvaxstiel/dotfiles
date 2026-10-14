# Which home-manager options own a FILE

`programs.X.enable` is not automatically package-only. Whether it writes a file
decides whether it collides with the dotfiles repo, and the answer differs per
program — read the module source (`xdg.configFile` / `home.file`, gated on a
`mkIf`) instead of assuming. Verified against the `release-26.05` module sources:

| option | writes | condition |
|---|---|---|
| `programs.git.enable` | `~/.config/git/config` | **always** — `xdg.configFile."git/config".text` is unconditional |
| `programs.ghostty.enable` | `~/.config/ghostty/config` | only under `mkIf (cfg.settings != { })` |
| `programs.rio.enable` | `~/.config/rio/config.toml` | only with `settings`; `themes` written separately |
| `programs.wezterm.enable` | `~/.config/wezterm/wezterm.lua` | only with `settings` / `extraConfig` |

## What this means for one-owner-per-path

- **`programs.git` always owns `~/.config/git/config`.** A dotfiles copy is a
  second owner that the next switch force-links over, so the git identity must be
  set through Nix, not in the dotfiles repo.
- Enabling a program with no `settings` is usually package-only — but verify it,
  because `programs.git` is the counter-example. A program whose config the
  dotfiles repo owns is safe to enable *without* settings.
- **Integration options are per-program and inconsistent.**
  `enableBashIntegration` / `enableZshIntegration` exist on some (ghostty:
  bash/fish/zsh; wezterm: bash/zsh only) and not at all on others — `programs.rio`
  has only `enable`/`package`/`settings`/`themes`. Setting one that does not exist
  is an EVAL FAILURE, not a no-op. They append to a shell rc, so turn them off
  wherever that rc belongs to the dotfiles repo.
- **The app may integrate at RUNTIME instead, outside home-manager.** rio writes
  `shell-integration-<version>/{zsh,powershell,data/fish}` into its own config dir
  and expects those to be sourced from the shell rc. Because the directory is
  version-stamped, a hardcoded `source` path breaks on the next upgrade — and the
  whole directory is a generated artifact, so it belongs in `.chezmoiignore`.
- **When the dotfiles repo takes a file over, look for a NixOS-level
  replacement** rather than deleting the feature. Bash completion is
  `programs.bash.completion.enable` (**nested**; home-manager's flat
  `programs.bash.enableCompletion` has no NixOS twin, so an hm `programs.bash`
  block does not translate line-for-line). `programs.vim.defaultEditor` (which
  asserts `programs.vim.enable`) sets `sessionVariables.EDITOR` system-wide and is
  the replacement for an hm `initExtra` EDITOR export.
