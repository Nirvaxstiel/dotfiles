#!/usr/bin/env bash
# Re-applies only the Hermes settings this repo owns.
# run_onchange_ re-runs this script only when the file changes, so Hermes keeps
# ownership of everything else and its own runtime edits survive.

set -eu

# Hermes may not be installed yet when chezmoi runs.
command -v hermes >/dev/null 2>&1 || exit 0

hermes config set agent.clarify_timeout 600
hermes config set agent.max_turns 60
hermes config set agent.restart_drain_timeout 180
hermes config set approvals.timeout 700
hermes config set browser.use_real_profile true
hermes config set compression.hygiene_hard_message_limit 400
hermes config set context.engine 'default'
hermes config set curator.backup.keep 5
hermes config set curator.prune_builtins true
hermes config set dashboard.theme 'cyberpunk'
hermes config set delegation.child_timeout_seconds 600
hermes config set desktop.font_family 'Inter'
hermes config set display.personality 'concise'
hermes config set display.reasoning_full true
hermes config set display.skin 'nous'
hermes config set display.streaming true
hermes config set moa.presets.default.enabled false
hermes config set sessions.auto_prune false
hermes config set streaming.fresh_final_after_seconds 60
hermes config set telegram.extra.rich_messages true
hermes config set terminal.font_family 'FiraCode Nerd Font'
hermes config set tools.tool_search.max_search_limit 20
hermes config set tools.tool_search.threshold_pct 10
hermes config set tts.provider 'piper'
hermes config set updates.pre_update_backup 'false'
hermes config set web.backend 'exa'
hermes config set checkpoints.delete_orphans true
hermes config set mcp_servers.jcodemunch.args '["--from", "git+https://github.com/jgravelle/jcodemunch-mcp.git", "jcodemunch-mcp"]'
hermes config set mcp_servers.jcodemunch.command 'uvx'
hermes config set plugins.entries.jev-curator.settings.allow_content_egress true
hermes config set plugins.entries.jev-curator.settings.mode 'observe'
hermes config set plugins.entries.jev-curator.settings.provider 'openrouter'
hermes config set plugins.entries.jev-skill-router.settings.mode true
hermes config set sessions.write_json_snapshots false

# Skills and plugins from Hermes' own registries are installed here rather than
# tracked as files, so `hermes skills update` and `hermes plugins update` keep
# them current. The skills this repo actually wrote live in dot_hermes/skills
# and the skin in dot_hermes/skins; those are plain files and need no command.

# `plugins install` exits non-zero with "already exists. Use force reinstall"
# when the plugin is present, which would abort this script under `set -e`.
# Already installed is the state we want, so only that message is tolerated;
# anything else still fails loudly. `--force` is deliberately absent because it
# would discard local plugin edits on every apply.
install_plugin() {
  local out
  if out=$(hermes plugins install "$1" --yes-deps --enable 2>&1); then
    return 0
  fi
  case "$out" in
    *"already exists"* | *"already installed"*) return 0 ;;
  esac
  printf '%s\n' "$out" >&2
  return 1
}

hermes skills install constraint-driven-development --yes
hermes skills install context-engineering --yes
hermes skills install database-migration --yes
hermes skills install observability-and-instrumentation --yes
hermes skills install openapi-specification-v3.2 --yes
hermes skills install performance-optimization --yes
hermes skills install reverse-engineer-anything --yes
hermes skills install simple-english --yes
hermes skills install docker-management --yes
hermes skills install fastmcp --yes
hermes skills install ast-grep --yes
hermes skills install grill-me --yes
hermes skills install subagent-driven-development --yes

install_plugin mnemosyne
install_plugin jev-approvals
install_plugin jev-curator
install_plugin jev-skill-router
install_plugin fastfinge/hermes-session-reset-policy
install_plugin wysie/mnemosyne-dashboard
install_plugin keeltrace/hermes-nerve
