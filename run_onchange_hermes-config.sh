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
hermes config set delegation.backend model_map
hermes config set delegation.backends.model_map.options '[{"name": "cheap-worker", "description": "Simple, bounded tasks: extraction, classification, formatting, small edits, routine tool calls. Optimize for cost.", "provider": "openrouter", "model": "z-ai/glm-5.3-flash", "reasoning_effort": "medium", "service_tier": "normal"}, {"name": "fast-agent", "description": "Latency-sensitive agent loops, tool selection, search query generation, short summaries, parallel subagent work.", "provider": "openrouter", "model": "inception/mercury-3", "reasoning_effort": "medium", "service_tier": "normal"}, {"name": "general-worker", "description": "General-purpose subagent for research, coding tasks, investigation, and multi-step work. Balance quality and cost.", "provider": "openrouter", "model": "openai/gpt-6-luna", "reasoning_effort": "high", "service_tier": "normal"}, {"name": "code-worker", "description": "Implement features, modify multiple files, write tests, debug ordinary failures. Prefer coding competence and reliable tool use over lowest price.", "provider": "openrouter", "model": "anthropic/claude-haiku-5.5", "reasoning_effort": "medium", "service_tier": "normal"}, {"name": "reasoning-worker", "description": "Difficult debugging, architecture analysis, unfamiliar codebases, complex trade-offs, and ambiguous requirements.", "provider": "openrouter", "model": "deepseek/deepseek-v4.1-flash-1017", "reasoning_effort": "medium", "service_tier": "normal"}, {"name": "independent-reviewer", "description": "Review plans, patches, and conclusions independently. Find subtle bugs, missing assumptions, and security issues.", "provider": "openrouter", "model": "openai/gpt-6-sol", "reasoning_effort": "medium", "service_tier": "normal"}, {"name": "deep-escalation", "description": "High-impact decisions or problems that resisted cheaper models. Use only when expected value justifies cost.", "provider": "openrouter", "model": "openai/gpt-6.1-sol", "reasoning_effort": "medium", "service_tier": "normal"}]'
hermes config set delegation.backends.model_map.default general-worker
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
# A plugin already installed (e.g. nerve, whose community-source re-install is
# blocked by the security scanner) is the state we want — skip, and leave
# updates to `hermes plugins update`.
plugin_installed() {
  local j base
  base=${1##*/}
  j=$(hermes plugins list --json --user 2>/dev/null)
  case "$j" in
    *"\"name\": \"$base\""*) return 0 ;;
  esac
  base=${base#hermes-}
  case "$j" in
    *"\"name\": \"$base\""*) return 0 ;;
  esac
  return 1
}

install_plugin() {
  plugin_installed "$1" && return 0
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

# `skills install` re-resolves from the registry even when the skill already
# exists locally, and ambiguous names (e.g. context-engineering) abort the run
# under `set -e`. A skill already on disk is the state we want.
install_skill() {
  local name="$1"
  if find "$HOME/.hermes/skills" -maxdepth 3 -type d -name "$name" | grep -q .; then
    return 0
  fi
  hermes skills install "$name" --yes
}

install_skill constraint-driven-development
install_skill context-engineering
install_skill database-migration
install_skill observability-and-instrumentation
install_skill openapi-specification-v3.2
install_skill performance-optimization
install_skill reverse-engineer-anything
install_skill simple-english
install_skill docker-management
install_skill fastmcp
install_skill ast-grep
install_skill grill-me
install_skill subagent-driven-development

install_plugin mnemosyne
install_plugin jev-approvals
install_plugin jev-curator
install_plugin jev-skill-router
install_plugin fastfinge/hermes-session-reset-policy
install_plugin wysie/mnemosyne-dashboard
install_plugin keeltrace/hermes-nerve
