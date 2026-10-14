---
name: kanban
description: "Orchestrator decomposition playbook + worker pitfalls/examples for Hermes Kanban multi-agent workflows. Profile discovery, card lifecycle, workspace handling, tenant isolation, retry diagnostics."
version: 2.0.0
author: Hermes Agent (consolidated)
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [kanban, multi-agent, orchestration, workflow, routing]
    related_skills: [plan, spike]
---

# Kanban — Multi-Agent Workflow

## Overview

This skill covers the complete Hermes Kanban multi-agent workflow: both the orchestrator's decomposition playbook and the worker's pitfall-guide. The core lifecycle is auto-injected via `KANBAN_GUIDANCE` in every worker's system prompt; this skill provides the deeper detail.

## Orchestrator: Decomposition Playbook

### Step 0: Discover Available Profiles

Before planning, identify which profiles exist. There is no default specialist roster:

```bash
hermes profile list
```

The dispatcher silently fails on unknown assignee names — a card assigned to `researcher` on a setup that only has `docker-worker` sits in `ready` forever.

### Decomposition Guidelines

- **Don't do the work yourself.** Create cards, assign them, monitor progress.
- **Break work into independently verifiable chunks.** Each card should produce a testable output (PR, document, proof of concept).
- **Set explicit success criteria.** The worker needs to know what "done" looks like.
- **Use workspace kinds wisely:** `scratch` (fresh temp dir), `dir:<path>` (shared persistent), `worktree` (git worktree).

### Card Lifecycle

1. **ready** → Created, assignee set, no one has picked it up
2. **running** → Worker is actively working on it
3. **blocked** → Worker hit an issue it can't resolve alone
4. **completed** → Worker finished successfully
5. **incomplete** → Worker gave up or hit unrecoverable error

### Monitoring

- `kanban_list()` to see all cards
- `kanban_board_view()` for structured board view
- When a card is blocked, investigate and either unblock or reassign

## Worker: Pitfalls and Examples

### Workspace Handling

| Kind | What it is | How to work |
|------|------------|-------------|
| `scratch` | Fresh tmp dir, yours alone | Read/write freely; GC'd when task is archived |
| `dir:<path>` | Shared persistent directory | Other runs read what you write. Treat like long-lived state |
| `worktree` | Git worktree | Run `git worktree add` if `.git` doesn't exist |

### Tenant Isolation

If `$HERMES_TENANT` is set, prefix memory entries with the tenant so context doesn't leak across tenants.

### Retry Diagnostics

- Heartbeat timeout: check `$HERMES_KANBAN_WORKSPACE` for partial output
- Worker crashed mid-task: the card returns to `ready` for another attempt
- Blocked resolution: use `kanban_update()` with a clear description of what you need

### Good Handoff Shapes

When completing a card, include:
- What was done
- What wasn't done (explicitly)
- Where the output lives
- Any context the next worker needs
