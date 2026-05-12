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
    audit: null
    audit_fix: null
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
    audit: null
    audit_fix: null
  }
  {
    name: choco
    category: package-manager
    detect: "^where choco"
    clean: {|| ^choco cache clear --force }
    prune: null
    update: {|| ^choco upgrade all -y }
    audit: null
    audit_fix: null
  }
  {
    name: cargo
    category: toolchain
    detect: "^where cargo"
    clean: {|| cargo cache --autoclean }
    prune: null
    update: {|| cargo install-update -a }
    audit: null
    audit_fix: null
  }
  {
    name: dotnet
    category: sdk
    detect: "^where dotnet"
    clean: {|| ^dotnet nuget locals all --clear }
    prune: null
    update: {|| ^dotnet tool update --all --global }
    audit: null
    audit_fix: null
  }
  {
    name: rustup
    category: toolchain
    detect: "^where rustup"
    clean: null
    prune: {|| rustup toolchain prune }
    update: {|| rustup update }
    audit: null
    audit_fix: null
  }
  {
    name: gem
    category: package-manager
    detect: "^where gem"
    clean: {|| gem cleanup }
    prune: null
    update: {|| gem update --system }
    audit: null
    audit_fix: null
  }
  {
    name: pip
    category: package-manager
    detect: "^where pip"
    clean: {|| pip cache purge }
    prune: null
    update: {|| python -m pip install --upgrade pip }
    audit: null
    audit_fix: null
  }
  {
    name: docker
    category: container
    detect: "^where docker"
    clean: {||
      ^docker builder prune -f --filter type!=exec.cachemount
      ^docker image prune -f
      ^docker image prune -f --filter "dangling=true"
    }
    prune: {||
      ^docker container prune -f
      ^docker network prune -f
      ^docker volume prune -f
    }
    update: {|| ^docker pull nousresearch/hermes-agent:latest }
    audit: null
    audit_fix: null
  }
  {
    name: hermes
    category: agent
    detect: {||
      let has_docker = (^where docker | is-not-empty)
      let has_dockerfile = ((^pwd | path expand) | path join "hermes" "Dockerfile" | path exists)
      if $has_docker and $has_dockerfile { "hermes/docker" } else { null }
    }
    clean: {||
      hermes sessions prune
      hermes checkpoints prune --retention-days 7
      ^docker image rm hermes-dev 2>/dev/null; null
    }
    prune: {||
      hermes checkpoints prune
    }
    update: {||
      hermes update
      hermes-build --pull --no-prune
    }
    audit: {||
      hermes doctor
    }
    audit_fix: {||
      hermes doctor --fix
    }
  }
]