local wezterm = require('wezterm')
local Cells = require('utils.cells')
local gits = require('colors.palette')
local Features = require('config.features')

local nf = wezterm.nerdfonts
local attr = Cells.attr

local M = {}

local GLYPH_SEMI_CIRCLE_LEFT = nf.ple_left_half_circle_thick
local GLYPH_SEMI_CIRCLE_RIGHT = nf.ple_right_half_circle_thick
local GLYPH_KEY_TABLE = nf.md_table_key
local GLYPH_KEY = nf.md_key

---@type table<string, Cells.SegmentColors>
local left_colors = {
    default = { bg = gits.keyIndicatorBg, fg = gits.keyIndicatorFg },
    scircle = { bg = 'rgba(0, 0, 0, 0.4)', fg = gits.keyIndicatorBg },
}

local cells = Cells:new()

cells
    :add_segment('scircle_left', GLYPH_SEMI_CIRCLE_LEFT, left_colors.scircle, attr(attr.intensity('Bold')))
    :add_segment('key_table_glyph', ' ', left_colors.default, attr(attr.intensity('Bold')))
    :add_segment('key_table_text', ' ', left_colors.default, attr(attr.intensity('Bold')))
    :add_segment('scircle_right', GLYPH_SEMI_CIRCLE_RIGHT, left_colors.scircle, attr(attr.intensity('Bold')))

M.setup = function()
    wezterm.on('update-right-status', function(window, _pane)
        if not Features.is_enabled('left-status') then
            window:set_left_status('')
            return
        end

        local name = window:active_key_table()

        if not name and not window:leader_is_active() then
            window:set_left_status('')
            return
        end

        local segments_to_render = { 'scircle_left' }

        if name then
            cells
                :update_segment_text('key_table_glyph', GLYPH_KEY_TABLE)
                :update_segment_text('key_table_text', ' ' .. string.upper(name))
            table.insert(segments_to_render, 'key_table_glyph')
            table.insert(segments_to_render, 'key_table_text')
        elseif window:leader_is_active() then
            cells:update_segment_text('key_table_glyph', GLYPH_KEY):update_segment_text('key_table_text', ' ')
            table.insert(segments_to_render, 'key_table_glyph')
            table.insert(segments_to_render, 'key_table_text')
        end

        table.insert(segments_to_render, 'scircle_right')
        window:set_left_status(wezterm.format(cells:render(segments_to_render)))
    end)
end

return M
