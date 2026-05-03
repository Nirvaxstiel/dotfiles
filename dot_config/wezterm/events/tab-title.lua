local wezterm = require('wezterm')
local Cells = require('utils.cells')
local OptsValidator = require('utils.opts-validator')
local colors = require('colors.custom')
local gits = require('colors.palette')
local ProgramIcons = require('utils.program-icons')
local Features = require('config.features')

---@alias Event.TabTitleOptions { unseen_icon: 'circle' | 'numbered_circle' | 'numbered_box', hide_active_tab_unseen: boolean }

local EVENT_OPTS = {}

---@type OptsSchema
EVENT_OPTS.schema = {
    {
        name = 'unseen_icon',
        type = 'string',
        enum = { 'circle', 'numbered_circle', 'numbered_box' },
        default = 'circle',
    },
    {
        name = 'hide_active_tab_unseen',
        type = 'boolean',
        default = true,
    },
}
EVENT_OPTS.validator = OptsValidator:new(EVENT_OPTS.schema)

local nf = wezterm.nerdfonts

local M = {}

local GLYPH_SCIRCLE_LEFT = nf.ple_left_half_circle_thick
local GLYPH_SCIRCLE_RIGHT = nf.ple_right_half_circle_thick
local GLYPH_CIRCLE = nf.fa_circle
local GLYPH_ADMIN = nf.md_shield_half_full
local GLYPH_LINUX = nf.cod_terminal_linux
local GLYPH_DEBUG = nf.fa_bug
local GLYPH_SEARCH = '🔭'

---Get icon for a process name
---@param process_name string
---@return string icon
local function get_process_icon(process_name)
    return ProgramIcons.get_process_icon(process_name)
end

---Get color for a process name
---@param process_name string
---@return string color
local function get_process_color(process_name)
    return ProgramIcons.get_process_color(process_name)
end

local GLYPH_UNSEEN_NUMBERED_BOX = {
    [1] = nf.md_numeric_1_box_multiple,
    [2] = nf.md_numeric_2_box_multiple,
    [3] = nf.md_numeric_3_box_multiple,
    [4] = nf.md_numeric_4_box_multiple,
    [5] = nf.md_numeric_5_box_multiple,
    [6] = nf.md_numeric_6_box_multiple,
    [7] = nf.md_numeric_7_box_multiple,
    [8] = nf.md_numeric_8_box_multiple,
    [9] = nf.md_numeric_9_box_multiple,
    [10] = nf.md_numeric_9_plus_box_multiple,
}

local GLYPH_UNSEEN_NUMBERED_CIRCLE = {
    [1] = nf.md_numeric_1_circle,
    [2] = nf.md_numeric_2_circle,
    [3] = nf.md_numeric_3_circle,
    [4] = nf.md_numeric_4_circle,
    [5] = nf.md_numeric_5_circle,
    [6] = nf.md_numeric_6_circle,
    [7] = nf.md_numeric_7_circle,
    [8] = nf.md_numeric_8_circle,
    [9] = nf.md_numeric_9_circle,
    [10] = nf.md_numeric_9_plus_circle,
}

local TITLE_INSET = {
    DEFAULT = 6,
    ICON = 8,
}

local RENDER_VARIANTS = {
    { 'scircle_left', 'icon', 'title', 'padding',       'scircle_right' },
    { 'scircle_left', 'icon', 'title', 'unseen_output', 'padding',       'scircle_right' },
    { 'scircle_left', 'icon', 'admin', 'title',         'padding',       'scircle_right' },
    { 'scircle_left', 'icon', 'admin', 'title',         'unseen_output', 'padding',      'scircle_right' },
    { 'scircle_left', 'icon', 'wsl',   'title',         'padding',       'scircle_right' },
    { 'scircle_left', 'icon', 'wsl',   'title',         'unseen_output', 'padding',      'scircle_right' },
}

---@type table<string, Cells.SegmentColors>
local tab_colors = {
    text_default          = { bg = gits.tabBgDefault, fg = gits.tabFgDefault },
    text_hover            = { bg = gits.tabBgHover, fg = gits.tabFgHover },
    text_active           = { bg = gits.tabBgActive, fg = gits.tabFgActive },

    unseen_output_default = { bg = gits.tabBgDefault, fg = gits.warning },
    unseen_output_hover   = { bg = gits.tabBgHover, fg = gits.warning },
    unseen_output_active  = { bg = gits.tabBgActive, fg = gits.warning },

    scircle_default       = { bg = 'rgba(0, 0, 0, 0.4)', fg = gits.tabBgDefault },
    scircle_hover         = { bg = 'rgba(0, 0, 0, 0.4)', fg = gits.tabBgHover },
    scircle_active        = { bg = 'rgba(0, 0, 0, 0.4)', fg = gits.tabBgActive },
}

---@param proc string
local function clean_process_name(proc)
    local a = string.gsub(proc, '(.*[/\\])(.*)', '%2')
    return a:gsub('%.exe$', '')
end

---Shorten path to show just filename or abbreviated path
---@param path string
---@return string
local function shorten_path(path)
    -- If empty or nil, return placeholder
    if not path or path == '' then
        return 'no title'
    end

    -- If it's just a short filename or simple name, return as-is
    if not path:match('[/\\]') and path:len() < 20 then
        return path
    end

    -- Handle SSH/remote sessions (user@host:path format)
    local user_host = path:match('^%S+@%S+:')
    if user_host then
        local remote_path = path:sub(user_host:len() + 1)
        if not remote_path:match('[/\\]') then
            return path
        end
        local filename = remote_path:match('[^/\\]+$')
        return user_host .. (filename or remote_path)
    end

    -- Replace home directory with ~
    local home = wezterm.home_dir:gsub('\\', '/')
    local short = path:gsub('\\', '/')
    short = short:gsub('^' .. home, '~')

    -- If it starts with ~/, shorten intelligently
    if short:match('^~/') then
        local filename = short:match('[^/]+$')
        local dirname = short:match('^~/(.*)/[^/]+$')

        if dirname and filename then
            -- Split into parts
            local parts = {}
            for part in dirname:gmatch('[^/]+') do
                table.insert(parts, part)
            end

            if #parts > 2 then
                -- Deep paths: ~/.../dir/filename
                return '~/' .. parts[#parts - 1] .. '/' .. filename
            elseif #parts > 0 then
                -- Shallow paths: ~/dir/filename
                return '~/' .. dirname .. '/' .. filename
            else
                -- Just filename
                return '~/' .. filename
            end
        else
            -- Just filename if no directory
            return '~/' .. (filename or short)
        end
    end

    -- For non-home paths, show last 2 components
    local parts = {}
    for part in short:gmatch('[^/]+') do
        table.insert(parts, part)
    end

    if #parts > 2 then
        -- Show last 2 parts for deep paths
        return parts[#parts - 1] .. '/' .. parts[#parts]
    elseif #parts > 1 then
        -- Show last 2 parts
        return parts[#parts - 1] .. '/' .. parts[#parts]
    elseif #parts == 1 then
        -- Just show the single part
        return parts[1]
    else
        return short
    end
end

---@param base_title string
---@param max_width number
---@param inset number
local function create_title(base_title, max_width, inset)
    local title

    if base_title == 'Debug' then
        title = GLYPH_DEBUG .. ' DEBUG'
        inset = inset - 2
    elseif base_title:match('^InputSelector:') ~= nil then
        title = base_title:gsub('InputSelector:', GLYPH_SEARCH)
        inset = inset - 2
    else
        -- Shorten the path
        title = shorten_path(base_title)
    end

    -- Account for icon width (will be added in separate segment)
    local icon_width = 2 -- space + icon (approximate)

    if title:len() + icon_width > max_width - inset then
        local diff = title:len() + icon_width - max_width + inset
        title = title:sub(1, title:len() - diff)
    else
        local padding = max_width - title:len() - icon_width - inset
        title = title .. string.rep(' ', padding)
    end

    return title
end

---@param panes any[] WezTerm https://wezfurlong.org/wezterm/config/lua/pane/index.html
local function check_unseen_output(panes)
    local unseen_output = false
    local unseen_output_count = 0

    for i = 1, #panes, 1 do
        if panes[i].has_unseen_output then
            unseen_output = true
            if unseen_output_count >= 10 then
                unseen_output_count = 10
                break
            end
            unseen_output_count = unseen_output_count + 1
        end
    end

    return unseen_output, unseen_output_count
end

---@class Tab
---@field title string
---@field cells FormatCells
---@field title_locked boolean
---@field locked_title string
---@field is_wsl boolean
---@field is_admin boolean
---@field unseen_output boolean
---@field unseen_output_count number
---@field is_active boolean
---@field process_icon string
---@field process_color string
local Tab = {}
Tab.__index = Tab

function Tab:new()
    local tab = {
        title = '',
        cells = Cells:new(),
        title_locked = false,
        locked_title = '',
        is_wsl = false,
        is_admin = false,
        unseen_output = false,
        unseen_output_count = 0,
        process_icon = '',
        process_color = gits.iconDefault,
    }
    return setmetatable(tab, self)
end

---@param event_opts Event.TabTitleOptions
---@param tab any WezTerm https://wezfurlong.org/wezterm/config/lua/MuxTab/index.html
---@param max_width number
function Tab:set_info(event_opts, tab, max_width)
    local process_name = clean_process_name(tab.active_pane.foreground_process_name)

    self.is_wsl = process_name:match('^wsl') ~= nil
    self.is_admin = (
        tab.active_pane.title:match('^Administrator: ') or tab.active_pane.title:match('(Admin)')
    ) ~= nil
    self.unseen_output = false
    self.unseen_output_count = 0

    -- Store process icon and color
    if process_name and process_name ~= '' then
        self.process_icon = get_process_icon(process_name) or ProgramIcons.get_process_icon('')
        self.process_color = get_process_color(process_name) or gits.iconDefault
    else
        -- Default icon if no process name
        self.process_icon = ProgramIcons.get_process_icon('')
        if not self.process_icon then
            self.process_icon = ''
        end
        self.process_color = gits.iconDefault
    end

    if not event_opts.hide_active_tab_unseen or not tab.is_active then
        self.unseen_output, self.unseen_output_count = check_unseen_output(tab.panes)
    end

    local inset = (self.is_admin or self.is_wsl) and TITLE_INSET.ICON or TITLE_INSET.DEFAULT
    if self.unseen_output then
        inset = inset + 2
    end

    if self.title_locked then
        self.title = create_title(self.locked_title, max_width, inset)
        return
    end
    self.title = create_title(tab.active_pane.title, max_width, inset)
end

function Tab:create_cells()
    local attr = self.cells.attr
    self.cells
        :add_segment('scircle_left', GLYPH_SCIRCLE_LEFT)
        :add_segment('icon', ' ' .. self.process_icon)
        :add_segment('admin', ' ' .. GLYPH_ADMIN)
        :add_segment('wsl', ' ' .. GLYPH_LINUX)
        :add_segment('title', ' ', nil, attr(attr.intensity('Bold')))
        :add_segment('unseen_output', ' ' .. GLYPH_CIRCLE)
        :add_segment('padding', ' ')
        :add_segment('scircle_right', GLYPH_SCIRCLE_RIGHT)
end

---@param title string
function Tab:update_and_lock_title(title)
    self.locked_title = title
    self.title_locked = true
end

---@param event_opts Event.TabTitleOptions
---@param is_active boolean
---@param hover boolean
function Tab:update_cells(event_opts, is_active, hover, tab_index)
    local tab_state = 'default'
    if is_active then
        tab_state = 'active'
    elseif hover then
        tab_state = 'hover'
    end

    self.cells:update_segment_text('icon', ' ' .. (self.process_icon or ''))

    -- Add tab index if feature is enabled
    local title_text = ' ' .. self.title
    if Features.is_enabled('tab-index') and tab_index then
        title_text = ' ' .. tab_index .. ':' .. self.title
    end
    self.cells:update_segment_text('title', title_text)

    if event_opts.unseen_icon == 'numbered_box' and self.unseen_output then
        self.cells:update_segment_text(
            'unseen_output',
            ' ' .. GLYPH_UNSEEN_NUMBERED_BOX[self.unseen_output_count]
        )
    end
    if event_opts.unseen_icon == 'numbered_circle' and self.unseen_output then
        self.cells:update_segment_text(
            'unseen_output',
            ' ' .. GLYPH_UNSEEN_NUMBERED_CIRCLE[self.unseen_output_count]
        )
    end

    self.cells
        :update_segment_colors('scircle_left', tab_colors['scircle_' .. tab_state])
        :update_segment_colors('icon', { bg = tab_colors['text_' .. tab_state].bg, fg = self.process_color })
        :update_segment_colors('admin', tab_colors['text_' .. tab_state])
        :update_segment_colors('wsl', tab_colors['text_' .. tab_state])
        :update_segment_colors('title', tab_colors['text_' .. tab_state])
        :update_segment_colors('unseen_output', tab_colors['unseen_output_' .. tab_state])
        :update_segment_colors('padding', tab_colors['text_' .. tab_state])
        :update_segment_colors('scircle_right', tab_colors['scircle_' .. tab_state])
end

---@return FormatItem[] (ref: https://wezfurlong.org/wezterm/config/lua/wezterm/format.html)
function Tab:render()
    local variant_idx = self.is_admin and 3 or 1
    if self.is_wsl then
        variant_idx = 5
    end

    if self.unseen_output then
        variant_idx = variant_idx + 1
    end
    return self.cells:render(RENDER_VARIANTS[variant_idx])
end

---@type Tab[]
local tab_list = {}

---@param opts? Event.TabTitleOptions Default: {unseen_icon = 'circle', hide_active_tab_unseen = true}
M.setup = function(opts)
    local valid_opts, err = EVENT_OPTS.validator:validate(opts or {})

    if err then
        wezterm.log_error(err)
    end

    wezterm.on('tabs.manual-update-tab-title', function(window, pane)
        window:perform_action(
            wezterm.action.PromptInputLine({
                description = wezterm.format({
                    { Foreground = { Color = colors.foreground } },
                    { Attribute = { Intensity = 'Bold' } },
                    { Text = 'Enter new name for tab' },
                }),
                action = wezterm.action_callback(function(_window, _pane, line)
                    if line ~= nil then
                        local tab = window:active_tab()
                        local id = tab:tab_id()
                        tab_list[id]:update_and_lock_title(line)
                    end
                end),
            }),
            pane
        )
    end)

    wezterm.on('tabs.reset-tab-title', function(window, _pane)
        local tab = window:active_tab()
        local id = tab:tab_id()
        tab_list[id].title_locked = false
    end)

    wezterm.on('tabs.toggle-tab-bar', function(window, _pane)
        local effective_config = window:effective_config()
        window:set_config_overrides({
            enable_tab_bar = not effective_config.enable_tab_bar,
            background = effective_config.background,
        })
    end)

    wezterm.on('format-tab-title', function(tab, _tabs, _panes, _config, hover, max_width)
        -- Return default if tab-title feature is disabled
        if not Features.is_enabled('tab-title') then
            return tab.active_pane.title
        end

        if not tab_list[tab.tab_id] then
            tab_list[tab.tab_id] = Tab:new()
            tab_list[tab.tab_id]:set_info(valid_opts, tab, max_width)
            tab_list[tab.tab_id]:create_cells()
            tab_list[tab.tab_id]:update_cells(valid_opts, tab.is_active, hover, tab.tab_index)
            return tab_list[tab.tab_id]:render()
        end

        tab_list[tab.tab_id]:set_info(valid_opts, tab, max_width)
        tab_list[tab.tab_id]:update_cells(valid_opts, tab.is_active, hover, tab.tab_index)
        return tab_list[tab.tab_id]:render()
    end)
end

return M
