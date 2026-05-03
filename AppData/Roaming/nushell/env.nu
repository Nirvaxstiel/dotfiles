const NU_CONFIG_HOME = $nu.config-path | path dirname

mkdir ($NU_CONFIG_HOME | path join generated)
zoxide init nushell | save -f ($NU_CONFIG_HOME | path join "generated/.zoxide.nu")
oh-my-posh init nu --config ~/.config/omp/ys.xtended.json --print | save -f ($NU_CONFIG_HOME | path join "generated/.oh-my-posh.nu")
