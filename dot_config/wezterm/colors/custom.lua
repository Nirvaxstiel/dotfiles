local gits = require('colors.palette')

local colorscheme = {
    foreground = gits.text,
    background = gits.bg0,

    cursor_bg = gits.cyan,
    cursor_border = gits.cyan,
    cursor_fg = gits.bg0,

    selection_bg = gits.selectionBg,
    selection_fg = gits.selectionFg,

    ansi = {
        '#2d3640',
        gits.red,
        gits.green,
        gits.orange,
        gits.cyan,
        '#ff4d8a',
        gits.teal,
        '#8ecae6',
    },

    brights = {
        '#4a5f6d',
        '#ff66a3',
        '#66ffb3',
        '#ffd480',
        '#80e5ee',
        '#ff66a3',
        '#80eed6',
        '#ffffff',
    },

    tab_bar = {
        background = 'rgba(10, 14, 20, 0.9)',
        active_tab = {
            bg_color = gits.tabBgActive,
            fg_color = gits.tabFgActive,
        },
        inactive_tab = {
            bg_color = gits.bg1,
            fg_color = gits.tabFgDefault,
        },
        inactive_tab_hover = {
            bg_color = gits.tabBgHover,
            fg_color = gits.tabFgHover,
        },
        new_tab = {
            bg_color = gits.bg1,
            fg_color = gits.tabFgDefault,
        },
        new_tab_hover = {
            bg_color = gits.tabBgHover,
            fg_color = gits.tabFgHover,
            italic = true,
        },
    },

    visual_bell = gits.alert,
    indexed = {
        [16] = gits.warning,
        [17] = gits.info,
    },
    scrollbar_thumb = gits.bg3,
    split = gits.border,
    compose_cursor = gits.alert,

    quick_select_label_bg = { Color = gits.hotpink },
    quick_select_label_fg = { Color = gits.bg0 },
    quick_select_match_bg = { Color = gits.cyan },
    quick_select_match_fg = { Color = gits.bg0 },

    copy_mode_active_highlight_bg = { Color = gits.crimson },
    copy_mode_active_highlight_fg = { Color = gits.white },
    copy_mode_inactive_highlight_bg = { Color = gits.bg3 },
    copy_mode_inactive_highlight_fg = { Color = gits.text },
}

return colorscheme
