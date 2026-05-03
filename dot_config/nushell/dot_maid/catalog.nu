let MAID_CATALOG = [
  {
    name: bun
    category: package-manager
    detect: "^where bun"
    clean: {|| bun cache clean --force }
    prune: null
    update: {|| bun upgrade }
    audit: {|| bun audit }
    audit_fix: {|| bun audit --fix }
  }
  {
    name: npm
    category: package-manager
    detect: "^where npm"
    clean: {|| npm cache clean --force }
    prune: null
    update: {|| npm update -g }
    audit: {|| npm audit }
    audit_fix: {|| npm audit fix }
  }
  {
    name: pnpm
    category: package-manager
    detect: "^where pnpm"
    clean: null
    prune: {|| pnpm store prune }
    update: {|| pnpm up -g }
    audit: {|| pnpm audit }
    audit_fix: {|| pnpm audit fix }
  }
  {
    name: uv
    category: package-manager
    detect: "^where uv"
    clean: {|| uv cache clean }
    prune: null
    update: {|| uv self update }
  }
  {
    name: scoop
    category: package-manager
    detect: "^where scoop"
    clean: {||
      scoop cache rm -a
      scoop cleanup -a
    }
    prune: null
    update: {||
      scoop update
      scoop update -a
    }
  }
  {
    name: choco
    category: package-manager
    detect: "^where choco"
    clean: {|| ^choco cache clear --force }
    prune: null
    update: {|| ^choco upgrade all -y }
  }
  {
    name: cargo
    category: toolchain
    detect: "^where cargo"
    clean: {|| cargo cache --autoclean }
    prune: null
    update: {|| cargo install-update -a }
  }
  {
    name: dotnet
    category: sdk
    detect: "^where dotnet"
    clean: {|| ^dotnet nuget locals all --clear }
    prune: null
    update: {|| ^dotnet tool update --all --global }
  }
  {
    name: rustup
    category: toolchain
    detect: "^where rustup"
    clean: null
    prune: {|| rustup toolchain prune }
    update: {|| rustup update }
  }
  {
    name: gem
    category: package-manager
    detect: "^where gem"
    clean: {|| gem cleanup }
    prune: null
    update: {|| gem update --system }
  }
  {
    name: pip
    category: package-manager
    detect: "^where pip"
    clean: {|| pip cache purge }
    prune: null
    update: {|| python -m pip install --upgrade pip }
  }
]
