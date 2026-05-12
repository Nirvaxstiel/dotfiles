mkdir ($nu.data-dir | path join "vendor/autoload")
zoxide init nushell
    | save -f ($nu.data-dir | path join vendor/autoload/zoxide.nu)

oh-my-posh init nu --config ~/.config/omp/ys.xtended.json --print
    | save -f ($nu.data-dir | path join vendor/autoload/oh-my-posh.nu)

# starship init nu 
#     | save -f ($nu.data-dir | path join vendor/autoload/starship.nu)

$env.CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense'
mkdir $"($nu.cache-dir)"
carapace _carapace nushell | save --force $"($nu.cache-dir)/carapace.nu"