local wezterm = require('wezterm')
local mux = wezterm.mux
local Features = require('config.features')

local M = {}

M.setup = function()
    if not Features.is_enabled('gui-startup') then
        return
    end

    wezterm.on('gui-startup', function(cmd)
        local _, _, window = mux.spawn_window(cmd or {})
        window:gui_window():maximize()
    end)
end

return M
