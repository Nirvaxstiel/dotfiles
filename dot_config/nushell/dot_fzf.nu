def fzfzf [] {
    fzf --ansi --disabled --bind "change:reload:rg --line-number --no-heading --color=always --smart-case {q} || :" --bind "enter:execute(${EDITOR:-zed} +{2} {1})" --delimiter ":" --preview 'bat --color=always {1}
    --highlight-line {2}' --preview-window 'up:80%,border-bottom,~3,+{2}+3/3'
}