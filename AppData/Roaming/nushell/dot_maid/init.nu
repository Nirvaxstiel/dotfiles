const MAID_DIR = ($nu.config-path | path dirname | path join ".maid")
source ($MAID_DIR | path join "catalog.nu")

def get-targets [] {
  let registry_path = ($MAID_DIR | path join "registry.json")
  let registered = (try { open $registry_path | each {|r| $r.name} } catch { [] })
  $MAID_CATALOG | where {|t| $registered | any {|n| $n == $t.name} }
}

def maid-action [target: record, action: string] {
  let action_fn = (match $action {
    "clean" => $target.clean,
    "prune" => $target.prune,
    "update" => $target.update,
    "audit" => $target.audit,
    "audit_fix" => $target.audit_fix,
    _ => null,
  })
  if ($action_fn == null) { print $"($target.name): no ($action) command"; return }
  print $"($target.name): ($action)"
  try {
    do $action_fn | each {|line| print $line }
  } catch {|e|
    if ($e.msg | str contains "exit_code") {
      print $"($target.name): command failed"
    } else {
      print $"($target.name): ($e.msg)"
    }
  }
}

def maid [
  --clean(-c)
  --prune(-p)
  --update(-u)
  --audit(-e)
  --fix(-f)
  --all(-a)
  --list(-l)
  --probe(-r)
  target?: string
] {
  if $probe { maid-probe; return }

  let targets = (get-targets)

  if $all and not $clean and not $prune {
    if ($targets | is-empty) { print "no tools registered. run maid -r"; return }
    maid-clean-all $targets
    maid-prune-all $targets
    return
  }

  if $list {
    print "actions: c (clean)  p (prune)  u (update)  e (audit)  a (clean+prune all)"
    print ""
    if not ($targets | where $it.clean != null | is-empty) {
      print "clean targets:"
      $targets | where $it.clean != null | get name | each {|n| print $"  ($n)"}
    }
    if not ($targets | where $it.prune != null | is-empty) {
      print "prune targets:"
      $targets | where $it.prune != null | get name | each {|n| print $"  ($n)"}
    }
    if not ($targets | where $it.audit != null | is-empty) {
      print "audit targets:"
      $targets | where $it.audit != null | get name | each {|n| print $"  ($n)"}
    }
    return
  }

  if ($targets | is-empty) { print "no tools registered. run maid -r"; return }

  if $clean {
    if ($target | is-empty) { print "specify target or use -c -a"; return }
    if $all { maid-clean-all $targets; return }
    maid-run $target "clean" $targets
    return
  }

  if $prune {
    if ($target | is-empty) { print "specify target or use -p -a"; return }
    if $all { maid-prune-all $targets; return }
    maid-run $target "prune" $targets
    return
  }

  if $update {
    if ($target | is-empty) { print "specify target or use -u -a"; return }
    if $all { maid-update-all $targets; return }
    maid-update $target $targets
    return
  }

  if $audit {
    if ($target | is-empty) { print "specify target or use -e -a"; return }
    if $all { maid-audit-all $targets; return }
    let action = (if $fix { "audit_fix" } else { "audit" })
    maid-run $target $action $targets
    return
  }

  if $fix and not $audit { print "--fix requires --audit (-e)"; maid-help; return }

  maid-help
}

def maid-help [] {
  print "maid: clean up your dev environment"
  print ""
  print "  maid -l              list registered tools"
  print "  maid -c <name>       clean a tool"
  print "  maid -c -a           clean all"
  print "  maid -p <name>       prune a tool"
  print "  maid -p -a           prune all"
  print "  maid -u <name>       update + clean a tool"
  print "  maid -u -a           update + clean all"
  print "  maid -e <name>       audit a tool (security/vulns)"
  print "  maid -e <name> -f    audit + auto-fix vulnerabilities"
  print "  maid -e -a           audit all"
  print "  maid -a              clean + prune all"
  print ""
  print "  maid -r              probe for installed tools"
}

def maid-probe [] {
  print "scanning for installed tools..."
  let found = ($MAID_CATALOG | where {|t| not ($t.detect | is-empty) })
  if ($found | is-empty) { print "(none found)"; return }
  print ""
  $found | group-by category | items {|cat, tools|
    print $"($cat): (($tools | get name | str join ', '))"
  }
  let count = $found | length
  print $""
  print $"($count) tools found. generating registry..."
  let names = ($found | each {|t| {name: $t.name, category: $t.category} })
  $names | to json | save -f ($MAID_DIR | path join "registry.json")
  print "registry updated."
}

def maid-run [target: string, action: string, targets] {
  let t = ($targets | where $it.name == $target | first)
  if ($t == null) { print $"unknown target: ($target)"; return }
  maid-action $t $action
}

def maid-clean-all [targets] {
  let to_clean = ($targets | where $it.clean != null)
  if ($to_clean | is-empty) { print "no clean targets"; return }
  print $"cleaning (($to_clean | length)) target(s)..."
  $to_clean | each {|t| maid-action $t "clean" }
}

def maid-prune-all [targets] {
  let to_prune = ($targets | where $it.prune != null)
  if ($to_prune | is-empty) { print "no prune targets"; return }
  print $"pruning (($to_prune | length)) target(s)..."
  $to_prune | each {|t| maid-action $t "prune" }
}

def maid-update [target: string, targets] {
  let t = ($targets | where $it.name == $target | first)
  if ($t == null) { print $"unknown target: ($target)"; return }
  if ($t.update == null) { print $"($t.name): no update command"; return }
  maid-action $t "update"
  if ($t.clean != null) { maid-action $t "clean" }
}

def maid-update-all [targets] {
  let to_update = ($targets | where $it.update != null)
  if ($to_update | is-empty) { print "no targets have update commands"; return }
  print $"updating (($to_update | length)) target(s)..."
  $to_update | each {|t|
    maid-action $t "update"
    if ($t.clean != null) { maid-action $t "clean" }
  }
}

def maid-audit-all [targets] {
  let to_audit = ($targets | where $it.audit != null)
  if ($to_audit | is-empty) { print "no targets have audit commands"; return }
  print $"auditing (($to_audit | length)) target(s)..."
  $to_audit | each {|t| maid-action $t "audit" }
}
