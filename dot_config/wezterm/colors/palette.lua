-- Ghost in the Shell color palette
-- Separate from colorscheme to avoid WezTerm validation errors

local gits = {
    bg0 = '#0b0b14',
    bg1 = '#0d0d1a',
    bg2 = '#131322',
    bg3 = '#1a1a33',
    bg5 = '#2d2d4d',

    text = '#e41951',
    textMuted = '#c7c7c7',
    textMuted2 = '#686868',

    cyan = '#00c5c7',
    green = '#00dc84',
    teal = '#00d4aa',
    red = '#ff0051',
    orange = '#ffa726',

    crimson = '#ff0051',
    hotpink = '#e41951',
    magenta = '#ca30c7',
    blood = '#8a0303',
    rose = '#ff6e67',

    black = '#101116',
    white = '#c7c7c7',
    crust = '#070a0d',

    tabBgDefault = '#131322',
    tabBgHover = '#2d2d4d',
    tabBgActive = '#ff0051',
    tabFgDefault = '#c7c7c7',
    tabFgHover = '#e41951',
    tabFgActive = '#0b0b14',

    statusDate = '#00c5c7',
    statusBattery = '#ff0051',
    statusSeparator = '#e41951',

    iconTerminal = '#00d4aa',
    iconWsl = '#ff0051',
    iconSsh = '#e41951',
    iconUnix = '#00d4aa',

    keyIndicatorBg = '#ff0051',
    keyIndicatorFg = '#ffffff',

    -- Program icon colors
    iconLang = '#00dc84',    -- green
    iconTool = '#00c5c7',    -- cyan
    iconDevOps = '#ffa726',  -- orange
    iconEditor = '#e41951',  -- hot pink
    iconSystem = '#8ecae6',  -- kept original (light blue)
    iconDefault = '#686868', -- Gray for unknown programs,

    alert = '#ff0051',
    warning = '#e41951',
    success = '#00dc84',
    info = '#00c5c7',

    -- selectionBg = '#1a2332',
    selectionBg = 'rgba(220, 20, 60, 0.5)',
    selectionFg = '#0b0b14',

    border = '#1a1a33',
    borderActive = '#e41951',
}

return gits
