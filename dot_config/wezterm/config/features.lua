local wezterm = require('wezterm')

---@class Feature
---@field name string
---@field description string
---@field enabled boolean
---@field dependencies string[]
---@field setup function|nil

---@class FeatureRegistry
---@field registry table<string, Feature>
local Features = {
    registry = {},
}

function Features.register(name, feature)
    feature.name = name
    feature.enabled = feature.enabled ~= false
    feature.dependencies = feature.dependencies or {}
    Features.registry[name] = feature
end

function Features.get(name)
    return Features.registry[name]
end

function Features.set_enabled(name, enabled)
    local feature = Features.registry[name]
    if not feature then
        wezterm.log_warn('Feature not found: ' .. name)
        return false
    end
    feature.enabled = enabled
    return true
end

function Features.is_enabled(name)
    local feature = Features.registry[name]
    if not feature then
        wezterm.log_warn('Feature not found: ' .. name)
        return false
    end

    for _, dep in ipairs(feature.dependencies) do
        if not Features.is_enabled(dep) then
            wezterm.log_warn('Feature ' .. name .. ' disabled: dependency ' .. dep .. ' not enabled')
            return false
        end
    end

    return feature.enabled
end

function Features.get_all()
    return Features.registry
end

function Features.list()
    local list = {}
    for name, feature in pairs(Features.registry) do
        table.insert(list, {
            name = name,
            description = feature.description,
            enabled = feature.enabled,
            dependencies = feature.dependencies,
        })
    end
    return list
end

function Features.toggle(name)
    local feature = Features.registry[name]
    if not feature then
        wezterm.log_warn('Feature not found: ' .. name)
        return false
    end

    feature.enabled = not feature.enabled
    Features.save_to_user_config()
    return feature.enabled
end

-- JSON file path for user config
local USER_CONFIG_PATH = wezterm.config_dir .. '/config/user.json'

-- Default custom settings
local CUSTOM_DEFAULTS = {
    scrollback_lines = 20000,
    date_format = '%a %H:%M:%S',
    cwd_use_git_root = true,
    hide_active_tab_unseen = true,
    unseen_icon = 'circle',
}

---Load user configuration from JSON file
---@return table|nil config The loaded config, or nil if not found
function Features.load_user_config()
    local file = io.open(USER_CONFIG_PATH, 'r')
    if not file then
        return nil
    end

    local content = file:read('*all')
    file:close()

    local success, config = pcall(wezterm.json_parse, content)
    if not success then
        wezterm.log_error('Failed to parse user.json: ' .. tostring(config))
        return nil
    end

    return config
end

---Apply loaded configuration to features
---@param config table The configuration table with 'features' and 'custom' fields
function Features.apply_config(config)
    if not config then
        return
    end

    -- Apply feature states
    if config.features then
        for name, enabled in pairs(config.features) do
            Features.set_enabled(name, enabled)
        end
    end
end

---Get custom settings with defaults
---@return table Custom settings merged with defaults
function Features.get_custom_settings()
    local config = Features.load_user_config()
    local custom = {}

    -- Start with defaults
    for key, value in pairs(CUSTOM_DEFAULTS) do
        custom[key] = value
    end

    -- Override with user settings if exists
    if config and config.custom then
        for key, value in pairs(config.custom) do
            custom[key] = value
        end
    end

    return custom
end

function Features.save_to_user_config()
    local features = {}

    for name, feature in pairs(Features.registry) do
        features[name] = feature.enabled
    end

    -- Load existing config to preserve custom settings
    local existing_config = Features.load_user_config()
    local custom = existing_config and existing_config.custom or {}

    -- Ensure all defaults exist
    for key, default in pairs(CUSTOM_DEFAULTS) do
        if custom[key] == nil then
            custom[key] = default
        end
    end

    local config = {
        features = features,
        custom = custom,
    }

    local json_str = wezterm.json_encode(config)
    if not json_str then
        wezterm.log_error('Failed to encode config to JSON')
        return false
    end

    -- Pretty print the JSON
    json_str = Features.pretty_json(json_str)

    local file = io.open(USER_CONFIG_PATH, 'w')
    if not file then
        wezterm.log_error('Failed to write config/user.json')
        return false
    end

    file:write(json_str)
    file:close()

    wezterm.log_info('Feature states saved to config/user.json')
    return true
end

---Pretty print JSON string with indentation
---@param json_str string
---@return string
function Features.pretty_json(json_str)
    local result = {}
    local indent = 0
    local in_string = false
    local escape = false

    for i = 1, #json_str do
        local char = json_str:sub(i, i)

        if escape then
            table.insert(result, char)
            escape = false
        elseif char == "\\" then
            table.insert(result, char)
            escape = true
        elseif char == '"' then
            table.insert(result, char)
            in_string = not in_string
        elseif in_string then
            table.insert(result, char)
        elseif char == "{" or char == "[" then
            table.insert(result, char)
            table.insert(result, "\n")
            indent = indent + 1
            table.insert(result, string.rep("  ", indent))
        elseif char == "}" or char == "]" then
            table.insert(result, "\n")
            indent = indent - 1
            table.insert(result, string.rep("  ", indent))
            table.insert(result, char)
        elseif char == "," then
            table.insert(result, char)
            table.insert(result, "\n")
            table.insert(result, string.rep("  ", indent))
        elseif char == ":" then
            table.insert(result, char)
            table.insert(result, " ")
        else
            table.insert(result, char)
        end
    end

    return table.concat(result)
end

function Features.get_palette_items()
    local items = {}
    local features = Features.list()
    table.sort(features, function(a, b)
        return a.name < b.name
    end)

    for _, feature in ipairs(features) do
        local status_icon = feature.enabled and '✓ ' or '✗ '
        local deps = #feature.dependencies > 0 and ' [deps: ' .. table.concat(feature.dependencies, ', ') .. ']' or ''
        table.insert(items, {
            id = feature.name,
            label = status_icon .. feature.name .. deps .. ' - ' .. feature.description,
        })
    end

    return items
end

-- UI Components
Features.register('left-status', {
    description = 'Left status bar (key table indicator)',
    enabled = true,
})

Features.register('right-status', {
    description = 'Right status bar (workspace, cwd, battery, date)',
    enabled = true,
})

Features.register('workspace-display', {
    description = 'Show workspace name in right status',
    enabled = true,
    dependencies = { 'right-status' },
})

Features.register('cwd-display', {
    description = 'Show current directory in right status',
    enabled = true,
    dependencies = { 'right-status' },
})

Features.register('battery-display', {
    description = 'Show battery status in right status',
    enabled = true,
    dependencies = { 'right-status' },
})

Features.register('date-display', {
    description = 'Show date/time in right status',
    enabled = true,
    dependencies = { 'right-status' },
})

Features.register('tab-bar', {
    description = 'Tab bar at top',
    enabled = true,
})

Features.register('new-tab-button', {
    description = 'New tab button on right of tab bar',
    enabled = true,
})

Features.register('gui-startup', {
    description = 'Maximize window on startup',
    enabled = true,
})

-- Visual Effects
Features.register('backdrops', {
    description = 'Background images with blur effects',
    enabled = true,
})

Features.register('background-blur', {
    description = 'Background blur effects (platform-specific)',
    enabled = true,
    dependencies = { 'backdrops' },
})

Features.register('animations', {
    description = 'UI animations (cursor blink, etc.)',
    enabled = true,
})

Features.register('cursor-blink', {
    description = 'Cursor blinking',
    enabled = true,
    dependencies = { 'animations' },
})

Features.register('visual-bell', {
    description = 'Visual bell effect',
    enabled = true,
})

Features.register('scroll-bar', {
    description = 'Scroll bar on right',
    enabled = true,
})

-- Functionality
Features.register('scrollback', {
    description = 'Scrollback buffer (default: 20000 lines)',
    enabled = true,
})

Features.register('hyperlinks', {
    description = 'Clickable hyperlinks in terminal',
    enabled = true,
})

Features.register('command-palette', {
    description = 'Command palette (F2)',
    enabled = true,
})

Features.register('auto-reload', {
    description = 'Auto-reload config on file change',
    enabled = true,
})

Features.register('exit-confirmation', {
    description = 'Window close confirmation',
    enabled = true,
})

-- Tab Features
Features.register('tab-index', {
    description = 'Show tab index numbers',
    enabled = false,
})

Features.register('tab-title', {
    description = 'Custom tab titles with process icons',
    enabled = true,
})

Features.register('last-active-tab', {
    description = 'Switch to last active tab when closing tab',
    enabled = true,
})

return Features
