local wezterm = require('wezterm')
local platform = require('utils.platform')
local backdrops = require('utils.backdrops')
local Features = require('config.features')
local act = wezterm.action

local mod = {}

if platform.is_mac then
    mod.SUPER = 'SUPER'
    mod.SUPER_REV = 'SUPER|CTRL'
elseif platform.is_win or platform.is_linux then
    mod.SUPER = 'ALT' -- to not conflict with Windows key shortcuts
    mod.SUPER_REV = 'ALT|CTRL'
end

-- stylua: ignore
local keys = {
    { key = 'F1', mods = 'NONE', action = 'ActivateCopyMode' },
}

-- Add custom feature toggle hotkeys here:
--
-- Instant toggle:
-- { key = 'b', mods = mod.SUPER, action = wezterm.action_callback(function() Features.toggle('backdrops') end) }
--
-- Selector toggle:
-- { key = 'f', mods = mod.SUPER, action = act.InputSelector({
--     title = 'Toggle Feature',
--     choices = Features.get_palette_items(),
--     fuzzy = true,
--     action = wezterm.action_callback(function(_window, _pane, name)
--         if not name then return end
--         Features.toggle(name)
--     end)
-- }) }
--
-- Or use F2 command palette for full list.

if Features.is_enabled('command-palette') then
    table.insert(keys, { key = 'F2', mods = 'NONE', action = act.ActivateCommandPalette })
end

table.insert(keys, { key = 'F3', mods = 'NONE', action = act.ShowLauncher })
table.insert(keys, { key = 'F4', mods = 'NONE', action = act.ShowLauncherArgs({ flags = 'FUZZY|TABS' }) })
table.insert(keys, { key = 'F5', mods = 'NONE', action = act.ShowLauncherArgs({ flags = 'FUZZY|WORKSPACES' }) })
table.insert(keys, { key = 'F11', mods = 'NONE', action = act.ToggleFullScreen })
table.insert(keys, { key = 'F12', mods = 'NONE', action = act.ShowDebugOverlay })
table.insert(keys, { key = 'f', mods = mod.SUPER, action = act.Search({ CaseInSensitiveString = '' }) })

if Features.is_enabled('hyperlinks') then
    table.insert(keys, {
        key = 'u',
        mods = mod.SUPER_REV,
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
                wezterm.log_info('opening: ' .. url)
                wezterm.open_with(url)
            end),
        }),
    })
end

table.insert(keys, { key = 'LeftArrow', mods = mod.SUPER, action = act.SendString '\u{1b}OH' })
table.insert(keys, { key = 'RightArrow', mods = mod.SUPER, action = act.SendString '\u{1b}OF' })
table.insert(keys, { key = 'Backspace', mods = mod.SUPER, action = act.SendString '\u{15}' })
table.insert(keys, { key = 'c', mods = 'CTRL|SHIFT', action = act.CopyTo('Clipboard') })
table.insert(keys, { key = 'v', mods = 'CTRL|SHIFT', action = act.PasteFrom('Clipboard') })

if Features.is_enabled('tab-bar') then
    table.insert(keys, { key = 't', mods = mod.SUPER, action = act.SpawnTab('DefaultDomain') })
    table.insert(keys, { key = 't', mods = mod.SUPER_REV, action = act.SpawnTab({ DomainName = 'wsl:ubuntu-fish' }) })
    table.insert(keys, { key = 'w', mods = mod.SUPER_REV, action = act.CloseCurrentTab({ confirm = false }) })

    table.insert(keys, { key = '[', mods = mod.SUPER, action = act.ActivateTabRelative(-1) })
    table.insert(keys, { key = ']', mods = mod.SUPER, action = act.ActivateTabRelative(1) })
    table.insert(keys, { key = '[', mods = mod.SUPER_REV, action = act.MoveTabRelative(-1) })
    table.insert(keys, { key = ']', mods = mod.SUPER_REV, action = act.MoveTabRelative(1) })

    if Features.is_enabled('tab-title') then
        table.insert(keys, { key = '0', mods = mod.SUPER, action = act.EmitEvent('tabs.manual-update-tab-title') })
        table.insert(keys, { key = '0', mods = mod.SUPER_REV, action = act.EmitEvent('tabs.reset-tab-title') })
    end

    table.insert(keys, { key = '9', mods = mod.SUPER, action = act.EmitEvent('tabs.toggle-tab-bar') })
end

table.insert(keys, { key = 'n', mods = mod.SUPER, action = act.SpawnWindow })
table.insert(keys, {
    key = '-',
    mods = mod.SUPER,
    action = wezterm.action_callback(function(window, _pane)
        local dimensions = window:get_dimensions()
        if dimensions.is_full_screen then
            return
        end
        local new_width = dimensions.pixel_width - 50
        local new_height = dimensions.pixel_height - 50
        window:set_inner_size(new_width, new_height)
    end)
})
table.insert(keys, {
    key = '=',
    mods = mod.SUPER,
    action = wezterm.action_callback(function(window, _pane)
        local dimensions = window:get_dimensions()
        if dimensions.is_full_screen then
            return
        end
        local new_width = dimensions.pixel_width + 50
        local new_height = dimensions.pixel_height + 50
        window:set_inner_size(new_width, new_height)
    end)
})
table.insert(keys, {
    key = 'Enter',
    mods = mod.SUPER_REV,
    action = wezterm.action_callback(function(window, _pane)
        window:maximize()
    end)
})

if Features.is_enabled('backdrops') then
    table.insert(keys, {
        key = [[/]],
        mods = mod.SUPER,
        action = wezterm.action_callback(function(window, _pane)
            backdrops:random(window)
        end),
    })
    table.insert(keys, {
        key = [[,]],
        mods = mod.SUPER,
        action = wezterm.action_callback(function(window, _pane)
            backdrops:cycle_back(window)
        end),
    })
    table.insert(keys, {
        key = [[.]],
        mods = mod.SUPER,
        action = wezterm.action_callback(function(window, _pane)
            backdrops:cycle_forward(window)
        end),
    })
    table.insert(keys, {
        key = [[/]],
        mods = mod.SUPER_REV,
        action = act.InputSelector({
            title = 'InputSelector: Select Background',
            choices = backdrops:choices(),
            fuzzy = true,
            fuzzy_description = 'Select Background: ',
            action = wezterm.action_callback(function(window, _pane, idx)
                if not idx then
                    return
                end
                ---@diagnostic disable-next-line: param-type-mismatch
                backdrops:set_img(window, tonumber(idx))
            end),
        }),
    })
    table.insert(keys, {
        key = 'b',
        mods = mod.SUPER,
        action = wezterm.action_callback(function(window, _pane)
            backdrops:toggle_focus(window)
        end)
    })
    table.insert(keys, {
        key = 'n',
        mods = mod.SUPER,
        action = wezterm.action_callback(function(window, _pane)
            backdrops:enable_transparent(window)
        end)
    })
end

table.insert(keys, { key = [[\]], mods = mod.SUPER, action = act.SplitVertical({ domain = 'CurrentPaneDomain' }) })
table.insert(keys, { key = [[\]], mods = mod.SUPER_REV, action = act.SplitHorizontal({ domain = 'CurrentPaneDomain' }) })
table.insert(keys, { key = 'Enter', mods = mod.SUPER, action = act.TogglePaneZoomState })
table.insert(keys, { key = 'w', mods = mod.SUPER, action = act.CloseCurrentPane({ confirm = false }) })
table.insert(keys, { key = 'k', mods = mod.SUPER_REV, action = act.ActivatePaneDirection('Up') })
table.insert(keys, { key = 'j', mods = mod.SUPER_REV, action = act.ActivatePaneDirection('Down') })
table.insert(keys, { key = 'h', mods = mod.SUPER_REV, action = act.ActivatePaneDirection('Left') })
table.insert(keys, { key = 'l', mods = mod.SUPER_REV, action = act.ActivatePaneDirection('Right') })
table.insert(keys, {
    key = 'p',
    mods = mod.SUPER_REV,
    action = act.PaneSelect({ alphabet = '1234567890', mode = 'SwapWithActiveKeepFocus' }),
})
table.insert(keys, { key = 'u', mods = mod.SUPER, action = act.ScrollByLine(-5) })
table.insert(keys, { key = 'd', mods = mod.SUPER, action = act.ScrollByLine(5) })
table.insert(keys, { key = 'PageUp', mods = 'NONE', action = act.ScrollByPage(-0.75) })
table.insert(keys, { key = 'PageDown', mods = 'NONE', action = act.ScrollByPage(0.75) })

table.insert(keys, {
    key = 'f',
    mods = 'LEADER',
    action = act.ActivateKeyTable({
        name = 'resize_font',
        one_shot = false,
        timeout_milliseconds = 1000,
    }),
})
table.insert(keys, {
    key = 'p',
    mods = 'LEADER',
    action = act.ActivateKeyTable({
        name = 'resize_pane',
        one_shot = false,
        timeout_milliseconds = 1000,
    }),
})

-- stylua: ignore
local key_tables = {
    resize_font = {
        { key = 'k', action = act.IncreaseFontSize },
        { key = 'j', action = act.DecreaseFontSize },
        { key = 'r', action = act.ResetFontSize },
        { key = 'Escape', action = 'PopKeyTable' },
        { key = 'q', action = 'PopKeyTable' },
    },
    resize_pane = {
        { key = 'k', action = act.AdjustPaneSize({ 'Up',1 }) },
        { key = 'j', action = act.AdjustPaneSize({ 'Down',1 }) },
        { key = 'h', action = act.AdjustPaneSize({ 'Left',1 }) },
        { key = 'l', action = act.AdjustPaneSize({ 'Right',1 }) },
        { key = 'Escape', action = 'PopKeyTable' },
        { key = 'q', action = 'PopKeyTable' },
    },
}

local mouse_bindings = {
    {
        event = { Up = { streak = 1, button = 'Left' } },
        mods = 'CTRL',
        action = act.OpenLinkAtMouseCursor,
    },
}

return {
    disable_default_key_bindings = false,
    leader = { key = 'Space', mods = mod.SUPER_REV },
    keys = keys,
    key_tables = key_tables,
    mouse_bindings = mouse_bindings,
}
