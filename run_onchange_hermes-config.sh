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
hermes config set mcp_servers.rea.args '["C:\\Users\\Kei\\AppData\\Local\\npm-cache\\_npx\\9b9809298fe40d2c\\node_modules\\rea-agents\\scripts\\rea.mjs", "mcp"]'
hermes config set mcp_servers.rea.command 'C:\Users\Kei\.hermes\node\node.exe'
hermes config set mcp_servers.rea.enabled true
hermes config set plugins.disabled '[]'
hermes config set plugins.enabled '["disk-cleanup", "herdr-agent-state", "hermes-session-reset-policy", "jev-approvals", "jev-curator", "jev-skill-router", "mnemosyne", "mnemosyne-dashboard", "nerve", "security-guidance"]'
hermes config set plugins.entries.jev-curator.settings.allow_content_egress true
hermes config set plugins.entries.jev-curator.settings.mode 'observe'
hermes config set plugins.entries.jev-curator.settings.provider 'openrouter'
hermes config set plugins.entries.jev-skill-router.settings.mode true
hermes config set sessions.write_json_snapshots false
