local wezterm = require('wezterm')
local gits = require('colors.palette')
local nf = wezterm.nerdfonts

local M = {}

---Path aliases - replace specific paths with custom text
---@type table<string, string>
local PATH_ALIASES = {
    -- Example: Replace long project paths with shorter names
    -- ['/Users/kei/.config'] = '⚙️ config',
    -- ['/Users/kei/projects'] = '📁 projects',
    -- ['/var/log'] = '📋 logs',
}

---Find git directory starting from given directory and moving up the directory tree.
---@param directory string
---@return string|nil
local function find_git_dir(directory)
    directory = directory:gsub('~', wezterm.home_dir)

    while directory do
        local handle = io.open(directory .. '/.git/HEAD', 'r')
        if handle then
            handle:close()
            directory = directory:match('([^/]+)$')
            return directory
        elseif directory == '/' or directory == '' then
            break
        else
            directory = directory:match('(.+)/[^/]*')
        end
    end

    return nil
end

---Apply configured path aliases to a path string
---@param path string
---@return string
local function apply_path_aliases(path)
    for pattern, replacement in pairs(PATH_ALIASES) do
        path = path:gsub(pattern, replacement)
    end
    return path
end

---Shorten CWD path intelligently
---@param cwd string
---@param opts? { use_git_root?: boolean, show_full_path?: boolean }
---@return string
function M.get_cwd(cwd, opts)
    opts = opts or {}

    if not cwd or cwd == '' then
        return ''
    end

    -- Normalize path separators
    local path = cwd:gsub('\\', '/')

    -- Replace home directory with ~
    path = path:gsub('^' .. wezterm.home_dir:gsub('\\', '/'), '~')

    -- Apply path aliases
    path = apply_path_aliases(path)

    -- Use git root if requested
    if opts.use_git_root and path:match('^~/') then
        local git_root = find_git_dir(path)
        if git_root then
            return git_root
        end
    end

    -- Show full path if requested
    if opts.show_full_path then
        return path
    end

    -- Default: show abbreviated path (last 2 components)
    if path:match('^~/') then
        local filename = path:match('[^/]+$')
        local dirname = path:match('^~/(.*)/[^/]+$')

        if dirname and filename then
            local parts = {}
            for part in dirname:gmatch('[^/]+') do
                table.insert(parts, part)
            end

            if #parts > 2 then
                -- ~/.../dir/file
                return '~/' .. parts[#parts - 1] .. '/' .. filename
            elseif #parts > 0 then
                -- ~/dir/file
                return '~/' .. dirname .. '/' .. filename
            else
                -- ~/file
                return '~/' .. filename
            end
        end
        return '~/' .. (filename or path)
    else
        -- Non-home paths: show last 2 components
        local parts = {}
        for part in path:gmatch('[^/]+') do
            table.insert(parts, part)
        end

        if #parts > 2 then
            return parts[#parts - 1] .. '/' .. parts[#parts]
        elseif #parts > 1 then
            return parts[#parts - 1] .. '/' .. parts[#parts]
        else
            return parts[1] or path
        end
    end
end

---Add a path alias
---@param pattern string
---@param replacement string
function M.add_alias(pattern, replacement)
    PATH_ALIASES[pattern] = replacement
end

---Remove a path alias
---@param pattern string
function M.remove_alias(pattern)
    PATH_ALIASES[pattern] = nil
end

return M
