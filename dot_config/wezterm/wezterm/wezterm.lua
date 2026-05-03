local Config = require('config')
local wezterm = require('wezterm')
local Features = require('config.features')
local command_palette = require('config.command-palette')

-- Check if user config exists once at startup
local ok, user_config = pcall(require, 'config.user')

if not ok then
    wezterm.log_info('No user config found at config/user.lua. Using defaults.')
    wezterm.log_info('Copy config/user.lua.example to config/user.lua to customize.')
end

-- Load and apply user config once if it exists
if ok then
    user_config:apply()
end

require('utils.backdrops')
    :set_images()
    :random()

require('events.left-status').setup()

local user_opts = {}
pcall(function()
    local user_config = require('config.user')
    user_opts = user_config.custom or {}
end)

require('events.right-status').setup({
    date_format = user_opts.date_format or '%a %H:%M:%S',
    show_workspace = Features.is_enabled('workspace-display'),
    show_cwd = Features.is_enabled('cwd-display'),
    cwd_use_git_root = user_opts.cwd_use_git_root or true,
})

require('events.tab-title').setup({
    hide_active_tab_unseen = user_opts.hide_active_tab_unseen or false,
    unseen_icon = user_opts.unseen_icon or 'circle',
})

require('events.new-tab-button').setup()
require('events.gui-startup').setup()

-- local CwdUtil = require('utils.cwd')
-- CwdUtil.add_alias('/Users/kei/projects', '📁 projects')
-- CwdUtil.add_alias('/Users/kei/.config', '⚙️ config')
-- CwdUtil.add_alias('/var/log', '📋 logs')

wezterm.on('toggle-feature', function(window, pane, feature_name)
    if not feature_name then
        return
    end

    local new_state = Features.toggle(feature_name)
    wezterm.log_info('Feature ' .. feature_name .. ': ' .. (new_state and 'enabled' or 'disabled'))
    window:toast_notification('Feature ' .. feature_name .. ': ' .. (new_state and 'enabled' or 'disabled'))
end)

wezterm.on('augment-command-palette', function(_window, _pane)
    return command_palette.items
end)

return Config:init()
    :append(require('config.appearance'))
    :append(require('config.bindings'))
    :append(require('config.domains'))
    :append(require('config.fonts'))
    :append(require('config.general'))
    :append(require('config.launch')).options
