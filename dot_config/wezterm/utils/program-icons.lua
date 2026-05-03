local wezterm = require('wezterm')
local gits = require('colors.palette')

local nf = wezterm.nerdfonts

---Program icon mapping with colors
---@class ProgramIcon
---@field icon string
---@field color string

---@type table<string, ProgramIcon>
local PROGRAM_DATA = {
    -- Shells (Cyan)
    ['bash'] = { icon = nf.cod_terminal_bash, color = gits.iconTool },
    ['zsh'] = { icon = nf.dev_terminal, color = gits.iconTool },
    ['fish'] = { icon = nf.dev_terminal, color = gits.iconTool },
    ['nu'] = { icon = nf.dev_terminal, color = gits.iconTool },
    ['sh'] = { icon = nf.dev_terminal, color = gits.iconTool },

    -- Editors (Pink)
    ['vim'] = { icon = nf.dev_vim, color = gits.iconEditor },
    ['nvim'] = { icon = nf.custom_vim, color = gits.iconEditor },
    ['neovim'] = { icon = nf.custom_vim, color = gits.iconEditor },
    ['vi'] = { icon = nf.dev_vim, color = gits.iconEditor },
    ['emacs'] = { icon = nf.dev_emacs, color = gits.iconEditor },
    ['nano'] = { icon = nf.dev_console, color = gits.iconEditor },
    ['less'] = { icon = nf.dev_console, color = gits.iconEditor },
    ['more'] = { icon = nf.dev_console, color = gits.iconEditor },
    ['man'] = { icon = nf.dev_console, color = gits.iconEditor },

    -- Languages (Green)
    ['node'] = { icon = nf.md_hexagon, color = gits.iconLang },
    ['npm'] = { icon = nf.md_nodejs, color = gits.iconLang },
    ['yarn'] = { icon = nf.dev_yarn, color = gits.iconLang },
    ['pnpm'] = { icon = nf.md_nodejs, color = gits.iconLang },
    ['python'] = { icon = nf.dev_python, color = gits.iconLang },
    ['python3'] = { icon = nf.dev_python, color = gits.iconLang },
    ['pip'] = { icon = nf.dev_python, color = gits.iconLang },
    ['pip3'] = { icon = nf.dev_python, color = gits.iconLang },
    ['poetry'] = { icon = nf.dev_python, color = gits.iconLang },
    ['golang'] = { icon = nf.seti_go, color = gits.iconLang },
    ['go'] = { icon = nf.seti_go, color = gits.iconLang },
    ['cargo'] = { icon = nf.dev_rust, color = gits.iconLang },
    ['rust'] = { icon = nf.dev_rust, color = gits.iconLang },
    ['rustc'] = { icon = nf.dev_rust, color = gits.iconLang },
    ['ruby'] = { icon = nf.dev_ruby, color = gits.iconLang },
    ['gem'] = { icon = nf.dev_ruby, color = gits.iconLang },
    ['bundler'] = { icon = nf.dev_ruby, color = gits.iconLang },
    ['java'] = { icon = nf.seti_java, color = gits.iconLang },
    ['javac'] = { icon = nf.seti_java, color = gits.iconLang },
    ['gradle'] = { icon = nf.dev_gradle, color = gits.iconLang },
    ['maven'] = { icon = nf.dev_maven, color = gits.iconLang },
    ['php'] = { icon = nf.dev_php, color = gits.iconLang },
    ['composer'] = { icon = nf.dev_php, color = gits.iconLang },
    ['composer.phar'] = { icon = nf.dev_php, color = gits.iconLang },
    ['lua'] = { icon = nf.seti_lua, color = gits.iconLang },
    ['luajit'] = { icon = nf.seti_lua, color = gits.iconLang },
    ['perl'] = { icon = nf.dev_perl, color = gits.iconLang },
    ['raku'] = { icon = nf.dev_perl, color = gits.iconLang },

    -- Git & version control (Cyan)
    ['git'] = { icon = nf.dev_git, color = gits.iconTool },
    ['lazygit'] = { icon = nf.dev_github_alt, color = gits.iconTool },
    ['tig'] = { icon = nf.dev_git, color = gits.iconTool },
    ['gh'] = { icon = nf.dev_github_badge, color = gits.iconTool },
    ['hub'] = { icon = nf.dev_github_badge, color = gits.iconTool },
    ['svn'] = { icon = nf.dev_git, color = gits.iconTool },
    ['hg'] = { icon = nf.dev_git, color = gits.iconTool },
    ['fossil'] = { icon = nf.dev_git, color = gits.iconTool },

    -- Container & deployment (Orange)
    ['docker'] = { icon = nf.linux_docker, color = gits.iconDevOps },
    ['docker-compose'] = { icon = nf.linux_docker, color = gits.iconDevOps },
    ['kubectl'] = { icon = nf.linux_docker, color = gits.iconDevOps },
    ['k8s'] = { icon = nf.linux_docker, color = gits.iconDevOps },
    ['helm'] = { icon = nf.linux_docker, color = gits.iconDevOps },
    ['docker-credential'] = { icon = nf.linux_docker, color = gits.iconDevOps },
    ['podman'] = { icon = nf.linux_docker, color = gits.iconDevOps },
    ['nerdctl'] = { icon = nf.linux_docker, color = gits.iconDevOps },
    ['terraform'] = { icon = nf.dev_terraform, color = gits.iconDevOps },
    ['ansible'] = { icon = nf.dev_terraform, color = gits.iconDevOps },
    ['pulumi'] = { icon = nf.dev_terraform, color = gits.iconDevOps },

    -- Database (Green)
    ['psql'] = { icon = nf.dev_postgresql, color = gits.iconLang },
    ['postgres'] = { icon = nf.dev_postgresql, color = gits.iconLang },
    ['mysql'] = { icon = nf.dev_database, color = gits.iconLang },
    ['mariadb'] = { icon = nf.dev_database, color = gits.iconLang },
    ['sqlite3'] = { icon = nf.dev_database, color = gits.iconLang },
    ['redis-cli'] = { icon = nf.dev_redis, color = gits.iconLang },
    ['redis-server'] = { icon = nf.dev_redis, color = gits.iconLang },
    ['mongo'] = { icon = nf.dev_mongodb, color = gits.iconLang },
    ['mongod'] = { icon = nf.dev_mongodb, color = gits.iconLang },

    -- Networking & HTTP (Cyan)
    ['curl'] = { icon = nf.md_waves, color = gits.iconTool },
    ['wget'] = { icon = nf.md_arrow_down_box, color = gits.iconTool },
    ['http'] = { icon = nf.md_api, color = gits.iconTool },
    ['httpie'] = { icon = nf.md_api, color = gits.iconTool },
    ['ssh'] = { icon = nf.dev_terminal, color = gits.iconTool },
    ['telnet'] = { icon = nf.dev_terminal, color = gits.iconTool },
    ['nc'] = { icon = nf.dev_terminal, color = gits.iconTool },
    ['netcat'] = { icon = nf.dev_terminal, color = gits.iconTool },

    -- Build tools (Green)
    ['make'] = { icon = nf.seti_makefile, color = gits.iconLang },
    ['ninja'] = { icon = nf.seti_makefile, color = gits.iconLang },
    ['cmake'] = { icon = nf.dev_cmake, color = gits.iconLang },
    ['meson'] = { icon = nf.seti_makefile, color = gits.iconLang },
    ['bazel'] = { icon = nf.dev_gnu, color = gits.iconLang },
    ['gradlew'] = { icon = nf.dev_gradle, color = gits.iconLang },
    ['mvn'] = { icon = nf.dev_maven, color = gits.iconLang },

    -- Package managers (Orange)
    ['apt'] = { icon = nf.dev_ubuntu, color = gits.iconDevOps },
    ['apt-get'] = { icon = nf.dev_ubuntu, color = gits.iconDevOps },
    ['dnf'] = { icon = nf.dev_redhat, color = gits.iconDevOps },
    ['yum'] = { icon = nf.dev_redhat, color = gits.iconDevOps },
    ['pacman'] = { icon = nf.dev_archlinux, color = gits.iconDevOps },
    ['yay'] = { icon = nf.dev_archlinux, color = gits.iconDevOps },
    ['paru'] = { icon = nf.dev_archlinux, color = gits.iconDevOps },
    ['brew'] = { icon = nf.dev_apple, color = gits.iconDevOps },
    ['choco'] = { icon = nf.dev_windows, color = gits.iconDevOps },
    ['scoop'] = { icon = nf.dev_windows, color = gits.iconDevOps },
    ['winget'] = { icon = nf.dev_windows, color = gits.iconDevOps },

    -- System & monitoring (Cyan)
    ['htop'] = { icon = nf.md_chart_line, color = gits.iconTool },
    ['btop'] = { icon = nf.md_chart_line, color = gits.iconTool },
    ['top'] = { icon = nf.md_chart_line, color = gits.iconTool },
    ['glances'] = { icon = nf.md_chart_line, color = gits.iconTool },
    ['vmstat'] = { icon = nf.md_chart_line, color = gits.iconTool },
    ['iostat'] = { icon = nf.md_chart_line, color = gits.iconTool },
    ['sar'] = { icon = nf.md_chart_line, color = gits.iconTool },
    ['systemctl'] = { icon = nf.md_cog, color = gits.iconSystem },
    ['journalctl'] = { icon = nf.md_file_document, color = gits.iconSystem },
    ['strace'] = { icon = nf.dev_bug, color = gits.iconSystem },
    ['ltrace'] = { icon = nf.dev_bug, color = gits.iconSystem },
    ['tcpdump'] = { icon = nf.md_network, color = gits.iconSystem },
    ['wireshark'] = { icon = nf.md_network, color = gits.iconSystem },

    -- IDEs (Pink)
    ['code'] = { icon = nf.dev_vscode, color = gits.iconEditor },
    ['code-insiders'] = { icon = nf.dev_vscode, color = gits.iconEditor },
    ['cursor'] = { icon = nf.dev_vscode, color = gits.iconEditor },
    ['subl'] = { icon = nf.dev_vscode, color = gits.iconEditor },
    ['sublime_text'] = { icon = nf.dev_vscode, color = gits.iconEditor },
    ['atom'] = { icon = nf.dev_vscode, color = gits.iconEditor },
    ['intellij-idea'] = { icon = nf.dev_jetbrains, color = gits.iconEditor },
    ['pycharm'] = { icon = nf.dev_jetbrains, color = gits.iconEditor },
    ['webstorm'] = { icon = nf.dev_jetbrains, color = gits.iconEditor },
    ['goland'] = { icon = nf.dev_jetbrains, color = gits.iconEditor },
    ['rider'] = { icon = nf.dev_jetbrains, color = gits.iconEditor },

    -- Cloud (Orange)
    ['cloudflare'] = { icon = nf.md_cloud, color = gits.iconDevOps },
    ['aws'] = { icon = nf.md_cloud, color = gits.iconDevOps },
    ['az'] = { icon = nf.md_cloud, color = gits.iconDevOps },
    ['gcloud'] = { icon = nf.md_cloud, color = gits.iconDevOps },

    -- File operations (Cyan)
    ['cp'] = { icon = nf.md_file, color = gits.iconTool },
    ['mv'] = { icon = nf.md_file, color = gits.iconTool },
    ['rm'] = { icon = nf.md_file, color = gits.iconTool },
    ['rsync'] = { icon = nf.md_file, color = gits.iconTool },
    ['scp'] = { icon = nf.md_file, color = gits.iconTool },
    ['sftp'] = { icon = nf.md_file, color = gits.iconTool },
    ['tar'] = { icon = nf.md_file_zip, color = gits.iconTool },
    ['zip'] = { icon = nf.md_file_zip, color = gits.iconTool },
    ['unzip'] = { icon = nf.md_file_zip, color = gits.iconTool },
    ['gzip'] = { icon = nf.md_file_zip, color = gits.iconTool },
    ['bzip2'] = { icon = nf.md_file_zip, color = gits.iconTool },
    ['xz'] = { icon = nf.md_file_zip, color = gits.iconTool },

    -- Searching (Cyan)
    ['grep'] = { icon = nf.md_magnify, color = gits.iconTool },
    ['ripgrep'] = { icon = nf.md_magnify, color = gits.iconTool },
    ['rg'] = { icon = nf.md_magnify, color = gits.iconTool },
    ['ag'] = { icon = nf.md_magnify, color = gits.iconTool },
    ['ack'] = { icon = nf.md_magnify, color = gits.iconTool },
    ['fzf'] = { icon = nf.md_magnify, color = gits.iconTool },
    ['find'] = { icon = nf.md_magnify, color = gits.iconTool },
    ['fd'] = { icon = nf.md_magnify, color = gits.iconTool },
    ['locate'] = { icon = nf.md_magnify, color = gits.iconTool },

    -- Misc (System)
    ['sudo'] = { icon = nf.fa_hashtag, color = gits.iconSystem },
    ['doas'] = { icon = nf.fa_hashtag, color = gits.iconSystem },
    ['su'] = { icon = nf.fa_hashtag, color = gits.iconSystem },
    ['watch'] = { icon = nf.md_clock, color = gits.iconSystem },
    ['screen'] = { icon = nf.dev_terminal, color = gits.iconTool },
    ['tmux'] = { icon = nf.dev_terminal, color = gits.iconTool },
    ['zellij'] = { icon = nf.dev_terminal, color = gits.iconTool },
    ['wezterm'] = { icon = nf.dev_terminal, color = gits.iconTool },

    -- Default
    ['default'] = { icon = nf.cod_workspace_trust, color = gits.iconDefault },
}

local M = {}

---Get icon and color for a process name
---@param process_name string
---@return string icon, string color
function M.get_process_icon_data(process_name)
    if not process_name or process_name == '' then
        return PROGRAM_DATA['default'].icon, PROGRAM_DATA['default'].color
    end
    local lower_name = process_name:lower()
    local data = PROGRAM_DATA[lower_name] or PROGRAM_DATA['default']
    return data.icon, data.color
end

---Get just the icon for a process name
---@param process_name string
---@return string icon
function M.get_process_icon(process_name)
    local icon = M.get_process_icon_data(process_name)
    return icon
end

---Get just the color for a process name
---@param process_name string
---@return string color
function M.get_process_color(process_name)
    local _, color = M.get_process_icon_data(process_name)
    return color
end

return M
