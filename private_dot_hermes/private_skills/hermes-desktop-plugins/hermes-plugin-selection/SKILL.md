---
name: hermes-plugin-selection
description: "Use when evaluating Hermes plugins from the catalog."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [hermes, plugins, catalog, evaluation, selection, audit, jev, overlap]
---

# Hermes Plugin Selection

Evaluate, select, or audit Hermes plugins against the user's existing plugin stack before recommending an install. The deliverable is a verdict table over every candidate the keyword sweep found, not a description of the catalog.

## When to Use

Load this when the user asks to find, compare, audit, or install Hermes plugins; when they point at the plugin catalog or `hermes plugins search`; when a plugin is installed but not behaving as expected; or when a new plugin might duplicate something already enabled.

## Standing criteria

Gate every candidate on all three. One failure = reject.

1. **Jev runs through OpenRouter.** The accepted path is `OPENROUTER_API_KEY` against OpenRouter's Decisions API (`https://openrouter.ai/api/alpha/decisions`, model `~typesafe/jev-latest`). A plugin that also consults Hermes' OpenRouter credential pool when the env var is unset is stronger. Reject a plugin whose only routes are `TYPESAFE_API_KEY` direct, Cloudflare, Vercel AI Gateway, a generic `JEV_API_KEY`/`JEV_BASE_URL`, or a local heuristic.
2. **No overlap or contradiction with the installed stack.** Compare `provides_tools` and `provides_hooks` against what is already enabled before judging. Re-implementing an owned primitive, or claiming an auxiliary slot another enabled plugin already serves, is a contradiction rather than an addition.
3. **Cache-safety is a veto.** Anything that trims, rewrites, summarizes, or compacts conversation history, or injects into the system prompt or tool schemas mid-session, breaks prefix caching. Reject. Injection appended to the tail of the user message while the skill roster and system prompt stay byte-stable is acceptable.

A recommendation must also name what the plugin adds that nothing installed already does.

## Procedure

1. **Query the catalog document, not the browse UI.** The card grid, the per-plugin pages, and `hermes plugins search` all render from one generated document:
   `https://hermes-agent.nousresearch.com/docs/api/plugin-catalog.json`
   Fetch it and filter in code. Top level is `generated_at`, `entries`, `removed`; `entries` is a list of records with `name`, `repo`, `sha`, `subdir`, `description`, `maintainer`, `tier`, `category`, `requires_hermes`, `version`, `platforms`, `capabilities` (`provides_tools` / `provides_hooks` / `provides_middleware` / `requires_env`), and often `disclosure`. `hermes plugins search <kw>` prints the same records as a table when a shell view is enough. Do not drive a browser through the site's search box — same data, more round-trips.
2. **Sweep the whole record, not just the name.** Match the keyword against the serialized entry so hits in `description` and `disclosure` are caught. A plugin can be relevant without the keyword in its name, and the keyword family is usually wider than expected.
3. **Read every candidate's catalog entry first, `disclosure` before anything else.** That field states what leaves the machine and which internals get touched. It is the risk surface, not boilerplate.
4. **Read the README at the pinned commit** for provider support, required env vars, surface, and cost:
   `https://raw.githubusercontent.com/<owner>/<repo>/HEAD/README.md`
   For a `subdir` entry read `<subdir>/README.md` inside that repo — a monorepo ships one README per plugin and the root one will not answer provider questions. The README, not the catalog blurb, says which providers a plugin actually accepts.
5. **Audit overlap against the installed stack.** `hermes plugins list --json` gives the enabled set plus provenance (`catalog:<tier>@<sha>`). Then read `~/.hermes/plugins/<name>/plugin.yaml` for `provides_tools`, `provides_hooks`, and `config_schema` defaults, and read the hook implementation to see what it actually does. Overlap cannot be judged from names.
6. **Check effective settings, not the enabled flag.** Plugin settings live at `plugins.entries.<name>.settings.<key>` in `config.yaml`. When that block is absent the plugin's declared defaults apply silently, and a default gate such as `mode: observe` or `allow_content_egress: false` can leave an enabled plugin doing no network work at all. Read the code path that gates egress before claiming a plugin is active or inactive.
7. **Verify machine prerequisites before recommending.** Confirm the dependency a plugin needs actually exists: the browser that holds the user's logins for a browser plugin, plus `uv` / `node` / `pnpm` / a native host for anything else. Do not assume Chrome is present or that the user's logged-in profile is in the browser the plugin drives.
8. **Report as a verdict table.** One row per candidate from the sweep, each with a one-line reason tied to a numbered criterion. Then a short "worth it" section, each item carrying the concrete config or install command, then the rejects. Lead with verdicts; no padding.

## Verifying an installed plugin actually loads

`hermes plugins list` and `hermes memory status` report catalog/config state —
an enabled row says nothing about whether the module imported. Validate per
directory:

```bash
for d in ~/.hermes/plugins/*/; do
  printf '%-28s %s\n' "$(basename "$d")" \
    "$(hermes plugins validate "$d" 2>&1 | grep -aE 'Validation (passed|failed)' | tail -1)"
done
```

- **The offending name is on the line AFTER the `✗` marker**
  (`undeclared hooks registered (not in provides_hooks):` then the name). Grepping
  the marker alone reads as an empty diff.
- **Manifest drift is the usual cause**: the catalog wrapper pins the surface of
  the release it was written for while the resolver installs a newer package that
  registers one more tool or hook. Add the name to `plugin.yaml`; do not downgrade.
- **`<kind> '<name>' loaded but no provider instance found` is a wrapper message,
  not the error.** It prints whenever the loader returns nothing — missing Python
  dependency, `register()` raising, or an empty host process. Get the real cause
  from the DEBUG log, not from that line.
- **A plugin's Python dependencies are installed into a per-root generation venv,
  and a running gateway never switches to a new one.** After enabling a plugin,
  restart the gateway or every session keeps reporting the old state.
- **Confirm the gateway runs the install you patched** before debugging the
  plugin: `pgrep -af 'gateway run'` then
  `tr '\0' '\n' </proc/<pid>/environ | grep HERMES_BIN`. A desktop app spawns the
  agent pinned in its own wrapper, which can be a different build entirely.
- **Optional tool packages can fail staging without blocking the plugin** — the
  install reports `optional <pkg> was not installed` and continues.

## Pitfalls

- **Process-wide monkeypatching of Hermes internals is a red flag, not a feature.** A disclosure that rebinds private symbols (`TurnRunner._progress_build_message`, `BasePlatformAdapter.format_tool_event`, `agent.display.*`) on the module and on every reference found in `sys.modules` will break silently on a Hermes update. Surface it as the top risk and recommend a throwaway profile for the trial.
- **"Agent Plugins v1" catalog entries are not Hermes plugins.** They register no Hermes tools and no hooks — they are a skill plus a stdio MCP server started with `uv run`, needing a manual `mcp_servers` block, and their portable loader does not interpolate env in `mcp.json`. Describe them as what they are.
- **One slot, two providers = contradiction.** Two entries can both claim the same auxiliary task (for example `auxiliary.approval`). Installing both is a conflict; pick the one that matches the standing criteria.
- **A second tool gate doubles spend.** When an installed supervisor already runs a `pre_tool_call` gate, another gate plugin means two provider decisions per tool call. Recommend enabling the existing gate's mode instead of stacking a second judge.
- **Near-duplicate routers exist.** Independent maintainers ship the same cookbook pattern; near-identical entries differ only in provider support and injection point. Choose by criteria and say which entry is the duplicate of which.
- **A prototype is not a platform.** Entries that self-describe as prototypes (no store, no package release, a vision document that is "not the current contract") are not install candidates however well the idea fits.
- **Re-verify the reference table before trusting it.** The catalog changes by reviewed PR; regenerate from the catalog document rather than quoting a stored table.

Reference: `references/jev-plugin-family.md` maps the Jev-family entries to provider, surface, and overlap verdict.
