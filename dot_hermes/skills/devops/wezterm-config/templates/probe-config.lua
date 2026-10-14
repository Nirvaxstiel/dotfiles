local wezterm = require('wezterm')

-- Copy into a scratch dir that also holds a copy of the repo (wezterm.config_dir is the
-- directory of the --config-file path, so require('config.*') resolves inside the copy), then:
--   wezterm --config-file <scratch>/probe-config.lua show-keys
-- Read results from either channel:
--   grep -h PROBE_START -A40 $(ls -t "$HOME/.local/share/wezterm"/*-log-*.txt | head -1)
--   ... show-keys | grep Nop      (booleans, when log_error never surfaces)

local out = {}

local function probe(label, fn)
    local ok, res = pcall(fn)
    table.insert(out, label .. ' -> ok=' .. tostring(ok) .. ' val=' .. tostring(res))
end

probe('serde.json_encode_pretty', function()
    return wezterm.serde.json_encode_pretty({ a = 1 })
end)
probe('reload_configuration', function()
    return type(wezterm.reload_configuration)
end)
probe('add_to_config_reload_watch_list', function()
    return type(wezterm.add_to_config_reload_watch_list)
end)
probe('time.call_after', function()
    return type(wezterm.time.call_after)
end)
probe('gui.screens', function()
    return type(wezterm.gui.screens)
end)

local rules = wezterm.default_hyperlink_rules()
table.insert(out, 'default_hyperlink_rules count=' .. #rules)
for i, rule in ipairs(rules) do
    table.insert(out, string.format('[%d] regex=%s | format=%s | highlight=%s', i, tostring(rule.regex), tostring(rule.format), tostring(rule.highlight)))
end

wezterm.log_error('PROBE_START\n' .. table.concat(out, '\n') .. '\nPROBE_END')

local function flag(cond, key)
    if cond then
        return { key = key, mods = 'CTRL|ALT|SHIFT', action = 'Nop' }
    end
end

return {
    font_size = 12,
    keys = {
        flag(type(wezterm.reload_configuration) == 'function', 'z'),
        flag(type(wezterm.add_to_config_reload_watch_list) == 'function', 'x'),
        flag(type(wezterm.time) == 'table' and type(wezterm.time.call_after) == 'function', 't'),
        flag(select(1, pcall(wezterm.serde.json_encode_pretty, { a = 1 })), 'c'),
    },
}
