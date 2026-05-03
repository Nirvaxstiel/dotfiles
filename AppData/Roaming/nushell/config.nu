const NU_CONFIG_HOME = $nu.config-path | path dirname

source ($NU_CONFIG_HOME | path join "generated/.zoxide.nu")
source ($NU_CONFIG_HOME | path join "generated/.oh-my-posh.nu")

$env.config.show_banner = false

source ($NU_CONFIG_HOME | path join ".maid" | path join "init.nu")
