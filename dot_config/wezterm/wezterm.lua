local Config = require('config')
local wezterm = require('wezterm')
local act = wezterm.action
local Features = require('config.features')

-- Load and apply user configuration from JSON FIRST
local user_config = Features.load_user_config()
if user_config then
    Features.apply_config(user_config)
end

-- Load command palette AFTER config is applied
local command_palette = require('config.command-palette')

require('utils.backdrops')
    -- :set_focus("#000000")
    -- :set_images(wezterm.home_dir .. '/Pictures/Wallpapers/')
    :set_images()
    :random()

require('events.left-status').setup()

local user_opts = Features.get_custom_settings()

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

wezterm.on('toggle-feature', function(_window, _pane, feature_name)
    if not feature_name then
        return
    end
    Features.toggle(feature_name)
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
