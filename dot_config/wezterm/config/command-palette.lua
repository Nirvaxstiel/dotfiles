local wezterm = require('wezterm')
local act = wezterm.action
local backdrops = require('utils.backdrops')
local Features = require('config.features')

local M = {}

-- stylua: ignore
M.items = {
    { brief = 'Activate Copy Mode', action = act.ActivateCopyMode },
    { brief = 'Toggle Fullscreen',  action = act.ToggleFullScreen },
    { brief = 'Show Debug Overlay', action = act.ShowDebugOverlay },
    { brief = 'Search Text',        action = act.Search({ CaseInSensitiveString = '' }) },
    {
        brief = 'Toggle Feature',
        action = wezterm.action_callback(function(window, pane)
            local choices = Features.get_palette_items()
            window:perform_action(act.InputSelector({
                title = 'Toggle Feature',
                choices = choices,
                fuzzy = true,
                fuzzy_description = 'Select feature to toggle: ',
                action = wezterm.action_callback(function(win, _, id)
                    if not id then
                        return
                    end

                    local new_state = Features.toggle(id)
                    local state_text = new_state and 'enabled' or 'disabled'
                    win:toast_notification('Feature Toggled', 'Feature "' .. id .. '" is now ' .. state_text)
                end),
            }), pane)
        end),
    },
}

if Features.is_enabled('hyperlinks') then
    table.insert(M.items, {
        brief = 'Open URL Under Cursor',
        action = wezterm.action.QuickSelectArgs({
            label = 'open url',
            patterns = {
                '\\((https?://\\S+)\\)',
                '\\[(https?://\\S+)\\]',
                '\\{(https?://\\S+)\\)',
                '<(https?://\\S+)>',
                '\\bhttps?://\\S+[)/a-zA-Z0-9-]+'
            },
            action = wezterm.action_callback(function(window, pane)
                local url = window:get_selection_text_for_pane(pane)
                wezterm.open_with(url)
            end),
        }),
    })
end

if Features.is_enabled('tab-bar') then
    table.insert(M.items, { brief = 'Spawn Tab (Default)',    action = act.SpawnTab('DefaultDomain') })
    table.insert(M.items, { brief = 'Spawn Tab (WSL Ubuntu)', action = act.SpawnTab({ DomainName = 'wsl:ubuntu-fish' }) })
    table.insert(M.items, { brief = 'Close Current Tab',      action = act.CloseCurrentTab({ confirm = true }) })

    table.insert(M.items, { brief = 'Next Tab',               action = act.ActivateTabRelative(1) })
    table.insert(M.items, { brief = 'Previous Tab',           action = act.ActivateTabRelative(-1) })
    table.insert(M.items, { brief = 'Move Tab Left',          action = act.MoveTabRelative(-1) })
    table.insert(M.items, { brief = 'Move Tab Right',         action = act.MoveTabRelative(1) })

    table.insert(M.items, { brief = 'Toggle Tab Bar', action = act.EmitEvent('tabs.toggle-tab-bar') })

    if Features.is_enabled('tab-title') then
        table.insert(M.items, { brief = 'Rename Current Tab', action = act.EmitEvent('tabs.manual-update-tab-title') })
        table.insert(M.items, { brief = 'Undo Rename Tab',    action = act.EmitEvent('tabs.reset-tab-title') })
    end
end

table.insert(M.items, { brief = 'Spawn Window', action = act.SpawnWindow })
table.insert(M.items, { brief = 'Maximize Window', action = wezterm.action_callback(function(window, _pane) window:maximize() end) })
table.insert(M.items, {
    brief = 'Increase Window Size',
    action = wezterm.action_callback(function(window, _pane)
        local dimensions = window:get_dimensions()
        if not dimensions.is_full_screen then
            window:set_inner_size(dimensions.pixel_width + 50, dimensions.pixel_height + 50)
        end
    end)
})
table.insert(M.items, {
    brief = 'Decrease Window Size',
    action = wezterm.action_callback(function(window, _pane)
        local dimensions = window:get_dimensions()
        if not dimensions.is_full_screen then
            window:set_inner_size(dimensions.pixel_width - 50, dimensions.pixel_height - 50)
        end
    end)
})

table.insert(M.items, { brief = 'Split Vertical',   action = act.SplitVertical({ domain = 'CurrentPaneDomain' }) })
table.insert(M.items, { brief = 'Split Horizontal', action = act.SplitHorizontal({ domain = 'CurrentPaneDomain' }) })
table.insert(M.items, { brief = 'Toggle Pane Zoom',   action = act.TogglePaneZoomState })
table.insert(M.items, { brief = 'Close Current Pane', action = act.CloseCurrentPane({ confirm = true }) })

table.insert(M.items, { brief = 'Move to Pane Up',              action = act.ActivatePaneDirection('Up') })
table.insert(M.items, { brief = 'Move to Pane Down',            action = act.ActivatePaneDirection('Down') })
table.insert(M.items, { brief = 'Move to Pane Left',            action = act.ActivatePaneDirection('Left') })
table.insert(M.items, { brief = 'Move to Pane Right',           action = act.ActivatePaneDirection('Right') })
table.insert(M.items, { brief = 'Swap with Active Pane',        action = act.PaneSelect({ alphabet = '1234567890', mode = 'SwapWithActiveKeepFocus' }) })

table.insert(M.items, { brief = 'Scroll Up 5 Lines',    action = act.ScrollByLine(-5) })
table.insert(M.items, { brief = 'Scroll Down 5 Lines',  action = act.ScrollByLine(5) })
table.insert(M.items, { brief = 'Scroll Page Up',       action = act.ScrollByPage(-0.75) })
table.insert(M.items, { brief = 'Scroll Page Down',     action = act.ScrollByPage(0.75) })

if Features.is_enabled('backdrops') then
    table.insert(M.items, { brief = 'Select Random Background', action = wezterm.action_callback(function(window, _pane) backdrops:random(window) end) })
    table.insert(M.items, { brief = 'Cycle to Next Background',     action = wezterm.action_callback(function(window, _pane) backdrops:cycle_forward(window) end) })
    table.insert(M.items, { brief = 'Cycle to Previous Background', action = wezterm.action_callback(function(window, _pane) backdrops:cycle_back(window) end) })
    table.insert(M.items, { brief = 'Toggle Background Focus Mode', action = wezterm.action_callback(function(window, _pane) backdrops:toggle_focus(window) end) })
    table.insert(M.items, { brief = 'Use Transparent Mode (Disable Images)', action = wezterm.action_callback(function(window, _pane) backdrops:enable_transparent(window) end) })
    table.insert(M.items, {
        brief = 'Fuzzy Select Background',
        action = act.InputSelector({
            title = 'Select Background',
            choices = backdrops:choices(),
            fuzzy = true,
            fuzzy_description = 'Select Background: ',
            action = wezterm.action_callback(function(window, _pane, idx)
                if not idx then return end
                backdrops:set_img(window, tonumber(idx))
            end),
        }),
    })
end

table.insert(M.items, { brief = 'Resize Font (Key Table)', action = act.ActivateKeyTable({ name = 'resize_font', one_shot = false, timeout_milliseconds = 1000 }) })
table.insert(M.items, { brief = 'Resize Pane (Key Table)', action = act.ActivateKeyTable({ name = 'resize_pane', one_shot = false, timeout_milliseconds = 1000 }) })

table.insert(M.items, { brief = 'Increase Font Size', action = act.IncreaseFontSize })
table.insert(M.items, { brief = 'Decrease Font Size', action = act.DecreaseFontSize })
table.insert(M.items, { brief = 'Reset Font Size',    action = act.ResetFontSize })

return M
