# Theme system (colour schemes as data)

Goal: add or swap a colour scheme without touching code, and switch it from the F2 palette.

## Layout

```
themes/registry.lua        ordered list of theme ids (source of truth for order + existence)
themes/<id>.lua            { label, roles, wezterm, config }
colors/theme.lua           resolves + validates the active theme, exposes it
colors/palette.lua         return require('colors.theme').roles   (consumers stay unchanged)
colors/custom.lua          builds the WezTerm `colors` table from roles, then overlays theme.wezterm
```

Adding a theme = drop `themes/<id>.lua` + one line in `themes/registry.lua`. Do NOT discover themes with `wezterm.glob` (yield error at load).

## Theme file contract

```lua
return {
    label = 'Human Readable Name',
    roles = { bg0 = '#0b0b14', text = '#e41951', ... },   -- every required role, all strings
    wezterm = {
        ansi = { 8 colours },
        brights = { 8 colours },
        -- optional extra Palette fields: cursor_*, split, scrollbar_thumb, visual_bell,
        -- compose_*, copy_mode_*, quick_select_*, input_selector_label_*, launcher_label_*,
        -- tab_bar (replaced wholesale, not deep-merged)
    },
    config = {
        -- optional top-level config contributions: inactive_pane_hsb, window_frame
    },
}
```

- `roles` = the semantic vocabulary the event modules consume. Keep one contract for every theme; validation rejects a theme file that misses a role or ships a short `ansi`/`brights` list, logging `theme <id> is invalid: ...` and excluding it from the picker.
- `wezterm` overlay is SHALLOW: a theme that supplies `tab_bar` replaces the derived one entirely.
- `config` is applied by `config/appearance.lua` after the literal defaults, so a theme can override `window_frame` / `inactive_pane_hsb` without editing appearance.

Derive the rest in `colors/custom.lua` from roles (cursor, selection, split, scrollbar_thumb, visual_bell, indexed, quick_select, copy_mode, tab_bar) so a minimal theme only states roles.

## Switching at runtime

1. Persist the id as a custom setting (`Features.set_custom_setting('theme', id)`, which rewrites `config/user.json` through the shared `build_user_config`/`write_user_config` path and then calls `wezterm.reload_configuration()`), or
2. Resolve the active id from `Features.get_custom_settings().theme` at load time, with the default id owned by `Features.CUSTOM_DEFAULTS.theme` — one source of truth for both the fallback and the persisted value.

Palette items: `Theme: Select (<active label>)` (fuzzy InputSelector, `✓` marker on the active entry), `Theme: Next`, `Theme: Previous`. Cycle order comes from the registry, not from sorted keys, so the picker and the cycle agree.

Event modules (`tab-title`, `left-status`, `right-status`, `program-icons`) snapshot colours at require time, so a switch means reload, not hot patching.

## Verification order for a new palette

1. `pcall(dofile, config_dir .. '/wezterm.lua')` in a scratch copy and dump values with `io.open` — proves every module loads and the active theme reaches `colors`.
2. Grep the newest GUI log for `Configuration Error` after the watcher reload — palette fields and colour syntax are only validated there.
3. Only then ask the user to confirm the visuals.
