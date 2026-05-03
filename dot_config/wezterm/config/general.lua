local wezterm = require('wezterm')
local Features = require('config.features')

local user_opts = {}
pcall(function()
    local user_config = require('config.user')
    user_opts = user_config.custom or {}
end)

local config = {
    exit_behavior = 'CloseOnCleanExit', -- if shell program exited with a successful status
    exit_behavior_messaging = 'Verbose',
    status_update_interval = 1000,
    audible_bell = 'Disabled',
}

if Features.is_enabled('auto-reload') then
    config.automatically_reload_config = true
end

if Features.is_enabled('scrollback') then
    config.scrollback_lines = user_opts.scrollback_lines or 20000
end

if Features.is_enabled('hyperlinks') then
    config.hyperlink_rules = {
        {
            regex = '\\((\\w+://\\S+)\\)',
            format = '$1',
            highlight = 1,
        },
        {
            regex = '\\[(\\w+://\\S+)\\]',
            format = '$1',
            highlight = 1,
        },
        {
            regex = '\\{(\\w+://\\S+)\\)',
            format = '$1',
            highlight = 1,
        },
        {
            regex = '<(\\w+://\\S+)>',
            format = '$1',
            highlight = 1,
        },
        {
            regex = '\\b\\w+://\\S+[)/a-zA-Z0-9-]+',
            format = '$0',
        },
        {
            regex = '\\b\\w+@[\\w-]+(\\.[\\w-]+)+\\b',
            format = 'mailto:$0',
        },
    }
end

if Features.is_enabled('exit-confirmation') then
    config.window_close_confirmation = 'NeverPrompt'
end

return config
