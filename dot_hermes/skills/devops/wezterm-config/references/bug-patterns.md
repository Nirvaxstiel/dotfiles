# WezTerm Config Bug Patterns

High-impact bugs found and fixed in this repo. Use these as the reference shape when similar patterns appear elsewhere.

## Override Merge (`set_config_overrides`)
Always read `window:get_config_overrides()` first, modify, then write back. Direct `set_config_overrides({...})` erases other per-window overrides.

## Backdrops (`backdrops.lua`)
- `transparent_on = transparent_on == true` (was `or true`, which ignores `false`).
- `_set_opt()` and `_set_focus_opt()` must merge overrides.
- Load images before requiring modules that build backdrop choices at load time.

## Hyperlink Regex
Closing delimiter is `}` (escaped `\}`), not `)`. Rule sets should be `wezterm.default_hyperlink_rules()` plus only the rules the defaults genuinely lack.

## GuiWin vs MuxWindow
Event callbacks (`window-resized`, `window-focus-changed`, `gui-startup`'s `cmd`) hand Lua a GuiWin: `get_dimensions`, `set_inner_size`, `set_position`, `maximize`, `is_focused` work. `gui_window()` is a MuxWindow method and raises `attempt to call a nil value (method 'gui_window')` on a GuiWin; reach it only on the object `mux.spawn_window()` returns. GuiWin exposes no `get_position`, so window position is not readable.

## Duplicated Pattern Lists
A regex list copied into both keybindings and the command palette drifts: a typo fixed in one copy stays in the other. Extract to one module (`utils/url-patterns.lua`) and require it from both call sites.

## Finding Runtime Errors
Grep the wezterm log for `ERROR` lines naming repo files before trusting a feature that "looks done". Event-handler failures are silent in the UI and repeat on every event:

```sh
grep -h "ERROR" -A3 $(ls -t "$HOME/.local/share/wezterm"/*-log-*.txt | head -5)
```

## User Config (`config/user.json`)
`.gitignore` ignores `config/user.lua`; `config/user.json` is tracked in git, so runtime toggles dirty the working tree. Flag that to the user rather than silently untracking it. Load via `Features.get_custom_settings()`. Never `require('config.user')`.

## Exit Confirmation
`AlwaysPrompt` confirms; `NeverPrompt` disables confirmation. The feature name is `exit-confirmation`, so enabling it requires `AlwaysPrompt`.

## Blur / Graphics
- `window_background_opacity` must be < 1.0 for blur.
- `kde_window_background_blur` deprecated → `wayland_window_background_blur`.
- `front_end = 'OpenGL'` makes `webgpu_*` settings dead; make them conditional (`if config.front_end == 'WebGpu'`).

## CWD / Git Root (`find_git_dir`)
- Check `.git` file (worktrees/submodules) in addition to `.git/HEAD`.
- Remove `~/` restriction; check any path.

## WSL Bindings
Wrap `DomainName = 'wsl:ubuntu-fish'` actions in `platform.is_win` check.

## WSL Domains
Omit `username` and `default_cwd` from `WslDomain` entries — the distro default user and home are used, which keeps a public config machine-agnostic.

## Tab Title Truncation
Use `wezterm.truncate_right(title, max_width - inset)` instead of `string.sub()` / `string.len()` (byte-based, not cell-width).
