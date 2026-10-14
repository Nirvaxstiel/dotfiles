# Window-State Persistence (feature `window-state`)

Goal: reopen at the previous size instead of maximizing. Opt-in (`enabled = false` in the registry).

## What the APIs actually allow

Event callbacks (`window-resized`, `window-focus-changed`) receive a **GuiWin**, whose usable methods are `get_dimensions`, `set_inner_size`, `set_position`, `maximize`, `restore`, `toggle_fullscreen`, `is_focused`. There is **no `get_position`** (checked against `wezterm-gui/src/scripting/guiwin.rs`), and `gui_window()` is a **MuxWindow** method — the inverse of `window:mux_window()` — so calling it on the event object throws `attempt to call a nil value (method 'gui_window')` on every event.

Consequence: window position is unreadable, so it cannot be persisted. Persist size only; drop `x`/`y`/`screen` from the state file.

## Shape

- `utils/window-state.lua`: `save_state(window)` reads `window:get_dimensions()`, returns early when `dims.is_full_screen` (keeps the last windowed size), compares against the last state / file contents before writing, writes `wezterm.config_dir / 'window_state.json'`.
- `events/gui-startup.lua`: `mux.spawn_window(opts)` with cell estimates from the saved pixels for the first paint, then `wezterm.time.call_after(0.3, ...)` → `gui:set_inner_size(w, h)` so the exact pixels win over the spawn estimate.
- `config/features.lua`: registry entry, `enabled = false`.

State file:
```json
{"pixel_height": 1405, "pixel_width": 1718}
```
Legacy files carrying `x`, `y`, `screen`, `saved_at` stay readable — the read path only consumes `pixel_width` / `pixel_height`.

## Verification without a GUI

`setup_startup()` is pure file I/O, so it is testable from a CLI-run probe config in a scratch copy of the repo: missing file → `false`, malformed JSON → `false` (pcall'd parse), legacy file → width/height intact. Feature must be enabled first (`Features.set_enabled('window-state', true)`) or `setup_startup()` short-circuits to `false` — a probe that forgets this reads as a false negative.

The save path needs a real GUI window; it cannot be exercised by `show-keys`.

## Measured behaviour (nightly 20260917)

`get_dimensions()` returns exact **inner** pixels; `set_inner_size()` lands immediately and the `window-resized` event fires reporting the **new** size (spawn estimate 1920x1421 → `set_inner_size(1718, 1405)` → event `1718x1405`, unchanged 1.5 s later). So no outer/inner conversion is needed.

## Restore/save race

Restoring resizes the window after the first `window-resized`/`window-focus-changed` save has already run, and a programmatic resize does not guarantee a later save — so the pre-resize spawn estimate gets persisted (observed: file held `1718x1436` while the window was `1718x1405`), and the next start feeds that inflated value back into the cell estimate. Fix: `M.restore_size(gui, state)` sets a module-level `restoring` flag, seeds `last_state = state`, and clears the flag inside the deferred callback; `save_state` returns early while `restoring`. Seeding `last_state` also makes post-restore saves no-ops until the user actually resizes.

## Testing against the live repo

A running GUI with `auto-reload` picks up repo edits and rewrites `window_state.json` itself, so measurements taken from the real repo can belong to the user's session. Isolate GUI tests in a scratch copy of the repo (`--config-file` sets `config_dir`), and kill test windows by WINPID: `ps -W` column 1 is the MSYS pid, column 4 the WINPID that names the log file (`cmd.exe /c taskkill /F /PID <WINPID>`; `//F` is rejected).
