---
name: autonomous-ai-agents
description: "Orchestrate external AI coding agents — Claude Code, OpenAI Codex CLI, OpenCode CLI. Delegation patterns, PTY/tmux management, print/background/interactive modes, PR review, parallel work."
version: 1.0.0
author: Hermes Agent (consolidated from claude-code, codex, opencode)
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [coding-agent, delegation, claude, codex, opencode, orchestration, pty, tmux]
    related_skills: [hermes-agent, code-quality, github]
---

# Autonomous AI Coding Agents: Orchestration Guide

Delegate coding tasks to external AI coding agent CLIs via Hermes terminal. All three agents share the same fundamental patterns: terminal-based CLI invocation, PTY/tmux for interactivity, print/background modes, PR review, and parallel work.

## Shared Patterns

### Prerequisites (all agents)
```bash
# Claude Code
npm install -g @anthropic-ai/claude-code
claude auth login

# Codex
npm install -g @openai/codex
# OPENAI_API_KEY env var or codex OAuth

# OpenCode
npm i -g opencode-ai@latest
opencode auth login
```

### Modes Comparison
| Mode | Claude Code | Codex | OpenCode |
|------|-------------|-------|----------|
| One-shot (print) | `claude -p "task"` | `codex exec "task"` | `opencode run "task"` |
| Interactive | PTY/tmux | PTY | PTY (TUI) |
| Background | `background=true, pty=true` | same | same |
| PR review | `--from-pr N` / git diff pipe | `codex review --base main` | `opencode pr N` |
| Enable dangerous | `--dangerously-skip-permissions` | `--yolo` | n/a |
| Session resume | `-c` / `-r <id>` | n/a | `-c` / `-s <id>` |

All three require `pty=true` for interactive sessions. One-shot commands may work without PTY.

---

## §1 — Claude Code

Anthropic's autonomous coding agent. Full CLI reference, interactive tmux setup, PR review, parallel instances.

### Print Mode (Preferred)
```bash
terminal(command="claude -p 'Add error handling to all API calls in src/' --allowedTools 'Read,Edit' --max-turns 10", workdir="/path/to/project", timeout=120)
```

**Key flags:**
| Flag | Use |
|------|-----|
| `-p, --print` | Non-interactive one-shot mode |
| `-c, --continue` | Resume most recent conversation |
| `-r, --resume <id>` | Resume specific session |
| `--fork-session` | Create new session ID on resume |
| `--model <sonnet\|opus\|haiku>` | Model selection |
| `--effort <low\|medium\|high\|max\|auto>` | Reasoning depth |
| `--max-turns <n>` | Limit agentic loops (prevent runaway) |
| `--max-budget-usd <n>` | Cap API spend |
| `--dangerously-skip-permissions` | Auto-approve ALL tool use |
| `--allowedTools <tools...>` | Whitelist specific tools |
| `--output-format json` | Machine-readable JSON result |
| `--output-format stream-json` | Real-time streaming JSON |
| `--bare` | Skip plugins, MCP, CLAUDE.md (fastest) |
| `--fallback-model haiku` | Auto-fallback on overload |

**Structured JSON output:**
```json
{"type":"result","subtype":"success","session_id":"...","num_turns":3,"total_cost_usd":0.0787,"duration_ms":10276}
```

### Interactive Mode (tmux)
```bash
terminal(command="tmux new-session -d -s claude-work -x 140 -y 40")
terminal(command="tmux send-keys -t claude-work 'cd /project && claude' Enter")
# Handle trust dialog
terminal(command="sleep 4 && tmux send-keys -t claude-work Enter")
# Handle permissions dialog (with --dangerously-skip-permissions):
terminal(command="sleep 3 && tmux send-keys -t claude-work Down && sleep 0.3 && tmux send-keys -t claude-work Enter")
```

#### Session Continuation
```bash
# Start task, capture session_id
terminal(command="claude -p 'Refactor DB layer' --output-format json --max-turns 10 > /tmp/session.json", timeout=180)
# Resume
terminal(command="claude -p 'Add connection pooling' --resume $(cat /tmp/session.json | python3 -c 'import json,sys; print(json.load(sys.stdin)[\"session_id\"])')", timeout=120)
# Fork
terminal(command="claude -p 'Try different approach' --resume <id> --fork-session --max-turns 10", timeout=120)
```

#### PR Review Patterns
```bash
# Quick: pipe diff
terminal(command="git diff main...feature | claude -p 'Review for bugs, security, style' --max-turns 1", timeout=60)
# Deep: interactive + worktree
terminal(command="claude -w pr-review --tmux", workdir="/path/to/repo")
# From PR number
terminal(command="claude -p 'Review PR thoroughly' --from-pr 42 --max-turns 10", workdir="/path/to/repo", timeout=120)
```

#### Parallel Claude Instances
```bash
terminal(command="claude -p 'Fix issue #1' -w fix-1 --tmux", workdir="/repo", background=true, pty=true)
terminal(command="claude -p 'Fix issue #2' -w fix-2 --tmux", workdir="/repo", background=true, pty=true)
```

#### Settings Hierarchy
1. CLI flags (highest)
2. `.claude/settings.local.json` (personal, gitignored)
3. `.claude/settings.json` (project, git-tracked)
4. `~/.claude/settings.json` (global)

#### Memory Files (CLAUDE.md)
- `~/.claude/CLAUDE.md` — global, all projects
- `./CLAUDE.md` — project-specific, git-tracked
- `.claude/CLAUDE.local.md` — personal overrides, gitignored
- In interactive mode: `# Always use 2-space indentation` adds to memory

#### Slash Commands
| Command | Purpose |
|---------|---------|
| `/help` | Show all commands |
| `/compact` | Compress context |
| `/clear` | Wipe conversation |
| `/context` | Visualize context usage |
| `/cost` | Token/cost breakdown |
| `/review` | Request code review |
| `/security-review` | Security analysis |
| `/plan` | Enter plan mode |
| `/model` | Switch model |
| `/effort` | Set reasoning effort |
| `/init` | Create CLAUDE.md |
| `/memory` | Edit CLAUDE.md |
| `/config` | Settings UI |
| `/permissions` | Tool permissions |
| `/agents` | Manage subagents |
| `/mcp` | MCP server management |
| `/batch` | Auto-create worktrees for parallel changes |

#### Custom Slash Commands
Create `.claude/commands/<name>.md` (shared) or `~/.claude/commands/<name>.md` (personal):
```markdown
# .claude/commands/deploy.md
Run the deploy pipeline:
1. Run all tests
2. Build Docker image
3. Push to registry
4. Update $ARGUMENTS environment
```
Usage: `/deploy production` — `$ARGUMENTS` replaced with user input.

---

## §2 — Codex CLI

OpenAI's autonomous coding agent CLI.

### One-Shot Tasks
```bash
terminal(command="codex exec 'Add dark mode toggle'", workdir="~/project", pty=true)
```

### Background Mode (Long Tasks)
```bash
terminal(command="codex exec --full-auto 'Refactor auth module'", workdir="~/project", background=true, pty=true)
process(action="poll", session_id="<id>")
process(action="submit", session_id="<id>", data="yes")
```

### Key Flags
| Flag | Effect |
|------|--------|
| `exec "prompt"` | One-shot execution |
| `--full-auto` | Auto-approves file changes in sandbox |
| `--yolo` | No sandbox, no approvals (fastest, dangerous) |
| `--sandbox danger-full-access` | Skip bubblewrap sandboxing |

### PR Reviews
```bash
terminal(command="REVIEW=$(mktemp -d) && git clone https://github.com/user/repo.git $REVIEW && cd $REVIEW && gh pr checkout 42 && codex review --base origin/main", pty=true)
```

### Parallel Issue Fixing (Worktrees)
```bash
terminal(command="git worktree add -b fix/issue-78 /tmp/issue-78 main", workdir="~/project")
terminal(command="codex --yolo exec 'Fix issue #78 and commit'", workdir="/tmp/issue-78", background=true, pty=true)
```

### Rules
1. Always use `pty=true` — Codex hangs without PTY
2. Git repo required — use `mktemp -d && git init` for scratch
3. Use `exec` for one-shots
4. `--full-auto` for building
5. Background for long tasks
6. Sandbox failures in gateway/service context: use `--sandbox danger-full-access`

---

## §3 — OpenCode CLI

Provider-agnostic, open-source AI coding agent.

### One-Shot Tasks
```bash
terminal(command="opencode run 'Add retry logic to API calls'", workdir="~/project")
```
Attach files with `-f`, show thinking with `--thinking`, force model with `--model`.

### Interactive TUI (Background)
```bash
terminal(command="opencode", workdir="~/project", background=true, pty=true)
process(action="submit", session_id="<id>", data="Implement OAuth refresh flow")
process(action="poll", session_id="<id>")
# Exit: Ctrl+C (NOT /exit!)
process(action="write", session_id="<id>", data="\x03")
```

**Important:** Do NOT use `/exit` — it opens an agent selector. Use `\x03` (Ctrl+C) or `process(action="kill")`.

### PR Review
```bash
terminal(command="opencode pr 42", workdir="~/project", pty=true)
```

### Session & Cost Management
```bash
opencode session list
opencode stats --days 7 --models anthropic/claude-sonnet-4
```

### Pitfalls
- `opencode run` does NOT need pty; interactive TUI does
- `/exit` is not valid — use Ctrl+C
- PATH mismatch can select wrong binary. Use `which -a opencode` to check
- Enter may need to be pressed twice to submit in TUI
- Avoid sharing one working directory across parallel OpenCode sessions

---

## §4 — Agent Selection Guide

| Need | Best Agent |
|------|-----------|
| Most capable coding | Claude Code (best tool ecosystem) |
| Fastest (cheapest) one-shot | OpenCode (provider-agnostic, choose cheap model) |
| Batch issue fixes | Codex (worktree pattern + --yolo) |
| PR review | Claude Code (--from-pr) or OpenCode (opencode pr) |
| No-cost/open-source | OpenCode |
| Sandbox safety | Codex (sandbox by default) |
| Session cost tracking | Claude Code (total_cost_usd in JSON) or OpenCode (`opencode stats`) |

## Pitfalls
- PATH issues across agent types — use explicit paths or `which` before delegating
- Don't run interactive agents without `pty=true` — they hang waiting for TTY
- Background long tasks don't report progress automatically — use `process(action="poll")` or `notify_on_complete`
- Each agent has its own exit/shutdown command — check before using
- Don't share working directories across parallel agent instances
