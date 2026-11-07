---
name: shell-configuration
description: "Use when maintaining Nushell configuration. Verify startup."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [windows, linux, macos]
metadata:
  hermes:
    tags: [nushell, shell, configuration, startup, dotfiles, containers]
---

# Shell Configuration Maintenance

Maintain Nushell configuration as a small startup system, not a pile of sourced scripts. Validate roast/review claims against source, runtime behavior, official Nushell startup rules, and tests before changing behavior.

## Procedure

1. Establish baseline before edits.
   - Run `git status --short`, `git diff --stat`, `git log --oneline -8`, and list tracked config, test, and container files.
   - Read `env.nu`, `config.nu`, every directly sourced module, generated-autoload paths, tests, and relevant Dockerfiles.
   - Run `nu --version` and the repository test command with `nu --no-config-file` when tests source their own fixtures.
   - Test config loading from an unrelated working directory. Record `$nu.startup-time` when startup cost is part of the review.

2. Classify each finding before fixing it.
   - Startup side effect: a generator, network request, package update, or file rewrite runs during every shell launch.
   - Path boundary: repository-owned source belongs under `$nu.default-config-dir`; generated vendor state belongs under `$nu.data-dir`.
   - Error boundary: a command returns a result but a caller discards it or performs a dependent action after failure.
   - Exposure boundary: a container port is published beyond loopback without an explicit requirement.
   - Reproducibility boundary: a build resolves `latest`, a moving branch, or another unpinned dependency.
   - Treat roast prose as a hypothesis. Keep a finding only after source inspection or a reproducible probe confirms its mechanism.

3. Make startup declarative.
   - Keep `env.nu` limited to environment initialization.
   - Move integration generators into an explicit refresh command. Write generated output into Nushell's vendor autoload directory, which Nushell loads automatically on interactive startup; print a restart instruction after refresh.
   - Do not explicitly source files already loaded by vendor autoload directories; duplicate loading can redefine commands and double startup work.
   - Resolve repository modules from `$nu.default-config-dir | path join ...`; `source` is parse-time, so do not depend on `$PWD` or a caller's working directory.
   - When the refresh command patches generated output with `str replace`, regenerate the output and diff it before trusting the patch: `str replace` returns its input unchanged when the pattern misses, so a generator release that changes its template degrades the config silently instead of failing.

4. Keep domain helpers explicit.
   - Model result values as discriminated records such as `{ kind: "ok", value: ... }` and `{ kind: "err", error: ... }`, not a boolean plus two nullable fields.
   - Preserve result values through orchestration. Do not pipe action results to `ignore`; collect batch results, report failures, and gate cleanup after update on update success.
   - Use `$nu.default-config-dir` for paths to repository Dockerfiles and config modules. Use `$nu.data-dir` for generated runtime/autoload state. Tests must derive expected paths from those constants rather than hard-code `.` or a machine path.

5. Apply security and reproducibility fixes narrowly.
   - Bind local development ports to `127.0.0.1` unless remote access is an explicit requirement.
   - Let Corepack resolve the package-manager version declared by checked-out `package.json`; never add `pnpm@latest` to a reproducible build.
   - Permit a pinned commit through an explicit input when a convenience command otherwise resolves a moving branch. Keep latest resolution as opt-in convenience, not the only path.
   - Remove dead commented build attempts only after confirming they are not the sole documentation of a required external constraint.

6. Verify behavior, not implementation details.
   - Re-run the full Nushell test suite after edits and update tests for intentional path or result-shape changes.
   - Start config from outside its directory and verify commands load without relying on the caller's current directory.
   - Hash generated autoload files before and after an ordinary shell startup; startup must not rewrite them. Run the explicit refresh command separately and verify generated files exist in the intended data directory.
   - Run Dockerfile syntax/build checks only when a container engine exists. Report skipped checks plainly; never infer a successful image build.
   - Assert completion behaviour through the engine (`commandline complete`), not only the closure, and test text parsers with inline fixtures (input text → expected records) so the suite stays offline and version-independent; a fixture failure can mean either the parser or the expectation is wrong, so re-read the raw source text before changing either.
   - Grep the config load for deprecations after editing it: `nu -c 'source ($nu.default-config-dir | path join "config.nu")' 2>&1 | grep -i 'deprecat\|warning'`. Nushell reports removed syntax as warnings, so deprecated code keeps working, passes the tests, and stays invisible until a user hits it.
   - Inspect `git diff`, `git diff --check` with repository line-ending rules, and `git status --short`. Do not commit unless requested.

## User-specific quality bar

Prefer root-cause fixes over catch-and-continue wrappers. Keep working command names and user-visible behavior unless evidence requires a change. Remove duplicate sources, dead commented code, and generated artifacts from the repository; avoid broad rewrites for cosmetic cleanup. Report changed files, real test output, and unverified external checks concisely.

## Nushell 0.116 completion input model

- Declare completion inputs by naming positional parameters: `token`, `place`, `buffer`. `spans` still binds but raises `nu::shell::deprecated` and will be removed.
- Use `$place.command` (token list at the cursor) as the direct replacement for `spans`.
- Do not re-implement alias expansion inside a completer: Nushell expands alias heads before handing `place.command` over. A manual expansion silently mangles arguments (`gco mai` became `git mai`).
- Test a completer without a REPL: `'git checkout mai' | commandline complete --input` returns the exact `{token, place, buffer}` record the completer receives. `commandline complete` without `--input` runs the real engine, which proves the configured external completer is actually reached.
- Carapace's generated Nushell integration still uses `spans`, so it sits on the deprecated side of this change; owning the completer in the config avoids waiting on upstream.
- Pick the engine per command: a carapace spec covers external binaries only. For a `def` of your own, attach a completer to the positional with `@` (`target?: string@maid-targets`); its flags already complete from the signature, so positional values are the whole gap.

## Nushell authoring traps

- A wrapped `and` / `or` starts a new statement, so it is parsed as a command (`Command 'and' not found`). Keep conditions on one line, or build a list and reduce it with `all { |ok| $ok }` / `any { |ok| $ok }`.
- `reduce` nested inside another `reduce` closure consumes the outer accumulator and misreports the input type. Map to a flat list of records, then run a single `reduce` over it.
- A `def` returning a record cannot be piped into `first` / `each`. Read it with `columns`, or assert on the record directly.
- Only `def`s survive `source`; a top-level `let` stays in the sourced file's scope. Expose values through `$env` / `$env.config` or return them from a command instead of assuming a caller can see them.

## Tool registry and per-tool actions

- Keep one registry per concept. A tool that already has a lifecycle entry (detect plus clean/prune/update/audit closures) takes new capabilities as new action fields on that entry; a second list of "tools needing X" duplicates tool identity and drifts from the first.
- Make every registry entry declare the same action field set. Runners look an action up by name (`$target | get $action`), so an entry missing that field raises a column error instead of the clean `no-action` result. Enforce uniformity with a test over the catalog.
- Keep the capability as data and the primitive in a module: the entry holds the recipe closure, the module holds the generator. The registry then never references module internals.
- Route actions that need the tool installed through the detected registry, but drive artifacts you own (completion specs, generated definitions) from the full catalog. A `detect` closure may legitimately report nothing on this machine, and a registry-gated refresh then skips the only entry that declared the work.
- Make `detect` cover every install pathway, and derive pathways from predicates rather than hard-coding one:
  ```nu
  def hermes-cli []       { (which hermes | is-not-empty) }
  def hermes-container [] { (which docker | is-not-empty) and (...Dockerfile exists) }
  detect: {|| hermes-pathway (hermes-cli) (hermes-container) }
  ```
  Encoding one pathway as the tool's identity — a container engine plus one specific Dockerfile — hides installs using another pathway, so the tool never registers and none of its actions ever run. Keep the decision a pure function of the predicates (`hermes-pathway $cli $container`) so every combination is testable on a machine that has only one.
- An action whose pathway is absent must fail loudly, naming what is missing, rather than silently doing nothing.

## Version-coupled third-party startup files

- Never regex-patch a vendored third-party startup file (`carapace _carapace nushell`, `zoxide init`, `oh-my-posh init`). Its text changes between releases and the patch stops matching silently. Move the assumption (binary location, shim hop, config shape) into owned code instead.
- Confirm an API or template change against the running binary before rewriting working config. Release notes, docs pages, and generated files disagree with each other and with the installed version.

## Tool registries

- Keep one per-machine tool list and hang per-tool capabilities off it as fields. A second registry for a single capability (completion specs, for example) duplicates tool identity and drifts from the first.
- Split the two roles: definition artifacts you own (a generated completion spec) follow the catalog of tools you maintain; actions that need the tool present (update, audit) follow the detected registry. A tool whose detection reports nothing still needs its definition rebuilt.
- Make every install pathway detectable. A `detect` closure that knows only one method (container-only, for a tool that also ships a local CLI) renders the tool invisible to registry-driven actions, so they never run and nothing reports the gap.
- Keep catalog entries structurally uniform — same fields on every entry, null for absent actions — so one dispatcher can look an action up by name.
- When a tool has several install pathways, branch each action on the pathway helpers rather than assuming one; a bare-metal action and a container action are different commands.

See `references/nushell-startup.md` for startup ordering, path boundaries, and an integration-refresh recipe.

See `references/core-plugin-bootstrap.md` for why plugin registration stays a one-shot user step instead of a startup hook, the verified `plugin list` facts (status lies, path-equality gate, registry file states), and the 0.116 syntax traps (`glob` and Windows backslashes, `ls` DoNotExpand, `not-in` removed, variables cannot contain `-`).

See `references/carapace-completions.md` for the completer contract (`place` in, `null` means file fallback), the `completions` / `menus` / keybinding surface, carapace environment knobs, writing carapace specs (including deriving one from an argparse CLI's `--help`), and the generated-integration drift pitfall.

## Absorbed: shell-configuration-maintenance (archived)

The following rules were distilled from the now-archived `shell-configuration-maintenance` skill and merged into this umbrella.

### Always-on rules (added)

- Treat generated startup files as artifacts with an owner, destination, refresh command, and load mechanism. Never run code generators on every shell launch when an autoload directory can load their output.
- Resolve shell-local imports from the shell's config directory, not `$PWD`; in Nushell use parse-time `$nu.default-config-dir | path join ...` for `source`.
- Model success and failure as tagged variants such as `{ kind: "ok", value: ... }` and `{ kind: "err", error: ... }`; do not represent both variants with nullable fields.
- Aggregate batch Results and report failures. Continue only when continuation is intentional; never run dependent cleanup after failed update.
- Bind host-published services to loopback by default and test exact argument vectors. An unqualified host port can expose a local service to the network.
- Pin external inputs where reproducibility matters: prefer a checked-out project's declared package-manager version and allow a commit override for dynamically fetched source.
- Preserve user workflows unless the requested change explicitly authorizes breaking behavior; document deliberate internal API changes.

### Failure signals (stop and investigate instead of adding a defensive wrapper when)

- startup rewrites generated files;
- a pure test suite passes but a command's effect branch has not run;
- an error is piped to `ignore` or converted to an empty/default success;
- a config path works only from one current directory;
- a string interpolation contains literal parentheses near an interpolation expression;
- a service binding changes from loopback to all interfaces;
- a dependency or source revision resolves through a moving `latest`/branch reference without an explicit pin path;
- a `str replace` patch over generated output matches nothing (diff is empty) while the command still reports success;
- a printed duration times only the final write (the timer wraps the I/O step, not the generation step) while the command's real cost is an order of magnitude larger — time the whole command, or from the right boundary.
