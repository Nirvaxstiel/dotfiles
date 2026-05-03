local gpu_adapters = require('utils.gpu-adapter')
local backdrops = require('utils.backdrops')
local colors = require('colors.custom')
local platform = require('utils.platform')
local Features = require('config.features')

local background_opts = nil
if Features.is_enabled('backdrops') then
    background_opts = backdrops:initial_options(false, true)
end

local config = {
    -- front_end = 'OpenGL',
    webgpu_power_preference = 'HighPerformance',
    webgpu_preferred_adapter = gpu_adapters:pick_best(),
    underline_thickness = '1.5pt',

    colors = colors,

    window_decorations = "INTEGRATED_BUTTONS|RESIZE",

    window_padding = {
        left = 0,
        right = 0,
        top = 10,
        bottom = 7.5,
    },
    adjust_window_size_when_changing_font_size = false,

    window_frame = {
        active_titlebar_bg = colors.background,
    },

    inactive_pane_hsb = {
        saturation = 1,
        brightness = 1,
    },
}

if Features.is_enabled('animations') then
    config.max_fps = 120
    config.animation_fps = 120
end

if Features.is_enabled('cursor-blink') then
    config.cursor_blink_ease_in = 'Constant'
    config.cursor_blink_ease_out = 'Constant'
    config.default_cursor_style = 'BlinkingBlock'
    config.cursor_blink_rate = 650
end

if Features.is_enabled('visual-bell') then
    config.visual_bell = {
        fade_in_function = 'EaseIn',
        fade_in_duration_ms = 250,
        fade_out_function = 'EaseOut',
        fade_out_duration_ms = 250,
        target = 'CursorColor',
    }
end

if Features.is_enabled('scroll-bar') then
    config.enable_scroll_bar = true
end

if background_opts ~= nil then
    config.background = background_opts

    if Features.is_enabled('background-blur') then
        if platform.is_win then
            config.win32_system_backdrop = 'Acrylic'
        elseif platform.is_mac then
            config.macos_window_background_blur = 20
        elseif platform.is_linux then
            -- kde_window_background_blur only works on KDE Wayland
            -- Other compositors: configure blur in compositor (Hyprland, picom, etc.)
            config.kde_window_background_blur = true
        end
    end
end

if Features.is_enabled('tab-bar') then
    config.enable_tab_bar = true
    config.hide_tab_bar_if_only_one_tab = false
    config.use_fancy_tab_bar = false
    config.tab_max_width = 25

    if Features.is_enabled('tab-index') then
        config.show_tab_index_in_tab_bar = true
    end

    if Features.is_enabled('last-active-tab') then
        config.switch_to_last_active_tab_when_closing_tab = true
    end
end

if Features.is_enabled('command-palette') then
    config.command_palette_fg_color = colors.foreground
    config.command_palette_bg_color = colors.background
    config.command_palette_font_size = 12
    config.command_palette_rows = 25
end

local function get_os()
    local bin_format = package.cpath:match("%p[\\|/]?%p(%a+)")
    if bin_format == "dll" then
        return "windows"
    elseif bin_format == "so" then
        return "linux"
    end

    return "macos"
end

if get_os() == "linux" then
    config.front_end = "OpenGL"
end

return config
