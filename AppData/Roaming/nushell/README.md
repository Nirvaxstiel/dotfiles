# maid

Personal dev environment cleanup tool using nushell functions

## Usage

```
maid -l              list registered tools
maid -c <name>       clean a tool
maid -c -a           clean all
maid -p <name>       prune a tool
maid -p -a           prune all
maid -u <name>       update + clean a tool
maid -u -a           update + clean all
maid -e <name>       audit a tool (security/vulns)
maid -e <name> -f    audit + auto-fix vulnerabilities
maid -e -a           audit all
maid -a              clean + prune all
maid -r              probe for installed tools
```

## Add a tool

Edit `.maid/catalog.nu`:

```nu
{
  name:     "mytool"
  category: "package-manager"
  detect:   "^where mytool"
  clean:    {|| mytool cache clean }
  prune:    null
  update:   null
  audit:    null
  audit_fix: null
}
```

Then `maid -r` to register it.

## Files

| File | Purpose |
|---|---|
| `catalog.nu` | known tools + commands |
| `registry.json` | tools this machine has |
| `init.nu` | command definitions |
| `custom.nu` | your additions (not sourced) |
