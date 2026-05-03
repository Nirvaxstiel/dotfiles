local wezterm = require('wezterm')
local umath = require('utils.math')
local Cells = require('utils.cells')
local OptsValidator = require('utils.opts-validator')
local gits = require('colors.palette')
local CwdUtil = require('utils.cwd')
local Features = require('config.features')

---@alias Event.RightStatusOptions { date_format?: string, show_cwd?: boolean, cwd_use_git_root?: boolean, show_workspace?: boolean }

---Setup options for right status bar
local EVENT_OPTS = {}

---@type OptsSchema
EVENT_OPTS.schema = {
    {
        name = 'date_format',
        type = 'string',
        default = '%a %H:%M:%S',
    },
    {
        name = 'show_cwd',
        type = 'boolean',
        default = true,
    },
    {
        name = 'cwd_use_git_root',
        type = 'boolean',
        default = true,
    },
    {
        name = 'show_workspace',
        type = 'boolean',
        default = true,
    },
}
EVENT_OPTS.validator = OptsValidator:new(EVENT_OPTS.schema)

local nf = wezterm.nerdfonts
local attr = Cells.attr

local M = {}

local ICON_SEPARATOR = nf.oct_dash
local ICON_DATE = nf.fa_calendar
local ICON_CWD = nf.md_folder_open
local ICON_WORKSPACE = nf.cod_window

---@type string[]
local discharging_icons = {
    nf.md_battery_10,
    nf.md_battery_20,
    nf.md_battery_30,
    nf.md_battery_40,
    nf.md_battery_50,
    nf.md_battery_60,
    nf.md_battery_70,
    nf.md_battery_80,
    nf.md_battery_90,
    nf.md_battery,
}
---@type string[]
local charging_icons = {
    nf.md_battery_charging_10,
    nf.md_battery_charging_20,
    nf.md_battery_charging_30,
    nf.md_battery_charging_40,
    nf.md_battery_charging_50,
    nf.md_battery_charging_60,
    nf.md_battery_charging_70,
    nf.md_battery_charging_80,
    nf.md_battery_charging_90,
    nf.md_battery_charging,
}

---@type table<string, Cells.SegmentColors>
local status_colors = {
    workspace = { fg = gits.success, bg = 'rgba(0, 0, 0, 0.4)' },
    cwd       = { fg = gits.info, bg = 'rgba(0, 0, 0, 0.4)' },
    date      = { fg = gits.statusDate, bg = 'rgba(0, 0, 0, 0.4)' },
    battery   = { fg = gits.statusBattery, bg = 'rgba(0, 0, 0, 0.4)' },
    separator = { fg = gits.statusSeparator, bg = 'rgba(0, 0, 0, 0.4)' }
}

local cells = Cells:new()

cells
    :add_segment('workspace_icon', ICON_WORKSPACE .. ' ', status_colors.workspace, attr(attr.intensity('Bold')))
    :add_segment('workspace_text', '', status_colors.workspace, attr(attr.intensity('Bold')))
    :add_segment('sep_workspace', ' ' .. ICON_SEPARATOR .. '  ', status_colors.separator)
    :add_segment('cwd_icon', ICON_CWD .. ' ', status_colors.cwd, attr(attr.intensity('Bold')))
    :add_segment('cwd_text', '', status_colors.cwd, attr(attr.intensity('Bold')))
    :add_segment('separator1', ' ' .. ICON_SEPARATOR .. '  ', status_colors.separator)
    :add_segment('date_icon', ICON_DATE .. '  ', status_colors.date, attr(attr.intensity('Bold')))
    :add_segment('date_text', '', status_colors.date, attr(attr.intensity('Bold')))
    :add_segment('separator2', ' ' .. ICON_SEPARATOR .. '  ', status_colors.separator)
    :add_segment('battery_icon', '', status_colors.battery)
    :add_segment('battery_text', '', status_colors.battery, attr(attr.intensity('Bold')))

---@return string, string
local function battery_info()
    -- ref: https://wezfurlong.org/wezterm/config/lua/wezterm/battery_info.html

    local charge = ''
    local icon = ''

    for _, b in ipairs(wezterm.battery_info()) do
        local idx = umath.clamp(umath.round(b.state_of_charge * 10), 1, 10)
        charge = string.format('%.0f%%', b.state_of_charge * 100)

        if b.state == 'Charging' then
            icon = charging_icons[idx]
        else
            icon = discharging_icons[idx]
        end
    end

    return charge, icon .. ' '
end

---@param opts? Event.RightStatusOptions Default: {date_format = '%a %H:%M:%S', show_cwd = true, cwd_use_git_root = true, show_workspace = true}
M.setup = function(opts)
    local valid_opts, err = EVENT_OPTS.validator:validate(opts or {})

    if err then
        wezterm.log_error(err)
    end

    wezterm.on('update-right-status', function(window, pane)
        -- Return early if right-status feature is disabled
        if not Features.is_enabled('right-status') then
            window:set_right_status('')
            return
        end

        local battery_text, battery_icon = battery_info()

        -- Get workspace name
        local workspace_text = window:active_workspace() or ''

        -- Get CWD if enabled
        local cwd_text = ''
        if Features.is_enabled('cwd-display') then
            local cwd_uri = pane:get_current_working_dir()
            if cwd_uri then
                local cwd
                if type(cwd_uri) == 'userdata' then
                    cwd = cwd_uri.file_path
                else
                    cwd = cwd_uri:sub(8):gsub('%%(%x%x)', function(hex)
                        return string.char(tonumber(hex, 16))
                    end)
                end
                cwd_text = CwdUtil.get_cwd(cwd, {
                    use_git_root = valid_opts.cwd_use_git_root,
                    show_full_path = false,
                })
            end
        end

        cells
            :update_segment_text('workspace_text', workspace_text)
            :update_segment_text('cwd_text', cwd_text)
            :update_segment_text('date_text', wezterm.strftime(valid_opts.date_format))
            :update_segment_text('battery_icon', battery_icon)
            :update_segment_text('battery_text', battery_text)

        -- Build segments list based on what's shown
        local segments = {}

        if Features.is_enabled('workspace-display') and workspace_text ~= '' then
            table.insert(segments, 'workspace_icon')
            table.insert(segments, 'workspace_text')
            table.insert(segments, 'sep_workspace')
        end

        if Features.is_enabled('cwd-display') and cwd_text ~= '' then
            table.insert(segments, 'cwd_icon')
            table.insert(segments, 'cwd_text')
            table.insert(segments, 'separator1')
        end

        if Features.is_enabled('date-display') then
            table.insert(segments, 'date_icon')
            table.insert(segments, 'date_text')
            table.insert(segments, 'separator2')
        end

        if Features.is_enabled('battery-display') then
            table.insert(segments, 'battery_icon')
            table.insert(segments, 'battery_text')
        end

        window:set_right_status(
            wezterm.format(cells:render(segments))
        )
    end)
end

return M
