$env.config.show_banner = false
$env.config.shell_integration."osc133" = false
source $"($nu.cache-dir)/carapace.nu"
source ($nu.data-dir | path join vendor/autoload/zoxide.nu)
# I prefer oh-my-posh for now.
source ($nu.data-dir | path join vendor/autoload/oh-my-posh.nu)
# source ($nu.data-dir | path join vendor/autoload/starship.nu)
source ($nu.data-dir | path join ".maid/init.nu")

source .common.nu
source .fastfetch.nu
source .fzf.nu
source .hermes-agent.nu