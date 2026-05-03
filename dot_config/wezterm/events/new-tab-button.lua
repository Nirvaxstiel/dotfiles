local wezterm = require('wezterm')
local launch_menu = require('config.launch').launch_menu
local domains = require('config.domains')
local Cells = require('utils.cells')
local colors = require('colors.custom')
local gits = require('colors.palette')
local Features = require('config.features')

local nf = wezterm.nerdfonts
local act = wezterm.action
local attr = Cells.attr

local M = {}

local btn_colors = {
    label_text   = { fg = colors.foreground },
    icon_default = { fg = gits.iconTerminal },
    icon_wsl     = { fg = gits.iconWsl },
    icon_ssh     = { fg = gits.iconSsh },
    icon_unix    = { fg = gits.iconUnix },
}

local cells = Cells:new()
    :add_segment('icon_default', ' ' .. nf.oct_terminal .. ' ', btn_colors.icon_default)
    :add_segment('icon_wsl', ' ' .. nf.cod_terminal_linux .. ' ', btn_colors.icon_wsl)
    :add_segment('icon_ssh', ' ' .. nf.md_ssh .. ' ', btn_colors.icon_ssh)
    :add_segment('icon_unix', ' ' .. nf.dev_gnu .. ' ', btn_colors.icon_unix)
    :add_segment('label_text', '', btn_colors.label_text, attr(attr.intensity('Bold')))

local function build_choices()
    local choices = {}
    local choices_data = {}
    local idx = 1

    for _, v in ipairs(launch_menu) do
        cells:update_segment_text('label_text', v.label)

        table.insert(choices, {
            id = tostring(idx),
            label = wezterm.format(cells:render({ 'icon_default', 'label_text' })),
        })
        table.insert(choices_data, {
            args = v.args,
            domain = 'DefaultDomain',
        })
        idx = idx + 1
    end

    for _, v in ipairs(domains.wsl_domains) do
        cells:update_segment_text('label_text', v.name)

        table.insert(choices, {
            id = tostring(idx),
            label = wezterm.format(cells:render({ 'icon_wsl', 'label_text' })),
        })
        table.insert(choices_data, {
            domain = { DomainName = v.name },
        })
        idx = idx + 1
    end

    for _, v in ipairs(domains.ssh_domains) do
        cells:update_segment_text('label_text', v.name)

        table.insert(choices, {
            id = tostring(idx),
            label = wezterm.format(cells:render({ 'icon_ssh', 'label_text' })),
        })
        table.insert(choices_data, {
            domain = { DomainName = v.name },
        })
        idx = idx + 1
    end

    for _, v in ipairs(domains.unix_domains) do
        cells:update_segment_text('label_text', v.name)

        table.insert(choices, {
            id = tostring(idx),
            label = wezterm.format(cells:render({ 'icon_unix', 'label_text' })),
        })
        table.insert(choices_data, {
            domain = { DomainName = v.name },
        })
        idx = idx + 1
    end

    return choices, choices_data
end

local choices, choices_data = build_choices()

M.setup = function()
    if not Features.is_enabled('new-tab-button') then
        return
    end

    wezterm.on('new-tab-button-click', function(window, pane, button, default_action)
        if default_action and button == 'Left' then
            window:perform_action(default_action, pane)
        end

        if default_action and button == 'Right' then
            window:perform_action(
                act.InputSelector({
                    title = 'InputSelector: Launch Menu',
                    choices = choices,
                    fuzzy = true,
                    fuzzy_description = nf.md_rocket .. ' Select a lauch item: ',
                    action = wezterm.action_callback(function(_window, _pane, id, label)
                        if not id and not label then
                            return
                        else
                            wezterm.log_info('you selected ', id, label)
                            wezterm.log_info(choices_data[tonumber(id)])
                            window:perform_action(
                                act.SpawnCommandInNewTab(choices_data[tonumber(id)]),
                                pane
                            )
                        end
                    end),
                }),
                pane
            )
        end
        return false
    end)
end

return M
