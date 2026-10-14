---
name: parallel-worktree-planning
description: "Use when parallelizing work into subagent worktrees."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [delegation, subagent, worktree, parallel, planning]
    related_skills: [subagent-driven-development, plan, github]
---

# Parallel Worktree Planning

Decide whether a change set CAN be split across parallel subagent worktrees, and
prove it with evidence, BEFORE dispatching anything. The failure mode is
answering "yes, 4 lanes" from the task list and discovering the collisions after
the merges. `git worktree add` branches from a commit, so a dirty tree makes
parallelism impossible.

## When to Use
- The user asks to hand work off to subagents in parallel worktrees, or to split a change set across parallel lanes.
- You are about to dispatch 2+ implementer subagents and must know whether they can run concurrently.
- A plan already exists and the open question is "can this run in parallel?" rather than "what is the work?".

## Procedure

### 1. Check the tree is committed — this gates everything
```bash
git status --short
git branch --show-current
```
`git worktree add` branches from a **commit**. Uncommitted work does not exist in
any worktree. If the tree is dirty, every lane silently starts from the pre-fix
tree and re-introduces the exact bugs the working tree already fixed. Under a
"do not commit yet" instruction, parallel lanes are **impossible** — say so and
work one branch, or ask to commit first. Never "temporarily commit" to unlock
lanes without saying that is what you are doing.

### 2. Build the file-collision matrix
For each candidate workstream, list the files it MUST touch. Then invert to
`file -> [workstreams]`. Any file with 2+ entries is a merge conflict by
construction, not a risk.

Worked shape:
```
_build_dashboard_data.py  <- {1, 2, 3}   COLLISION
viz/_boot.js              <- {1, 4a, 4b} COLLISION
project_axes.py           <- {2}         clean
viz/_shared.js            <- {4a}        clean
```

### 3. Count REAL lanes, not workstreams
Group workstreams by their file sets. Two workstreams that share any file are
**one lane**, not two. Four plausible workstreams above collapse to two lanes.
Report the collapsed number — it is usually the whole answer.

### 4. Check what serializes anyway
A shared generated artifact, or one full-build / determinism / integration
verification that must run once per lane, means the lanes cannot finish
independently. When the verification is the expensive part and it runs serially,
parallel lanes buy nothing: the wall-clock is the same plus merge overhead.
Say this explicitly; it is the argument that ends the worktree debate.

### 5. Place worktree dirs outside the repo
Sibling dirs appear as real folders in the parent. If the repo lives inside a
vault, a project root, or any tracked tree, siblings pollute it — put worktrees
under a scratch dir (e.g. `~/.hermes/cache/scratch/`).

### 6. Recommend, don't perform
Recommend **single branch, sequenced commits** when any of these hold: the total
change is small relative to the repo, files overlap, verification serializes, or
the tree is dirty. State the collision matrix and the lane count as evidence —
the user decides. Do not dispatch lanes and then report the conflicts.

## Pitfalls
- **Answering from the task list instead of the file list.** Two tasks that read
  as independent can write the same orchestrator, registry, or boot file. Only
  the file sets settle it — read the code before claiming independence.
- **Treating "independent" as "no shared files".** Shared *contracts* (a schema,
  an axis catalog, a source-meta shape) collide even when no file does. A change
  that adds a field to a shared type must land before the lanes that consume it,
  or the lanes build against two different shapes.
- **Assuming a lane can verify itself.** If the repo has a whole-build or
  byte-identical determinism check, each lane needs the merged tree to run it
  meaningfully. That check is the serialization point — name it.
- **Skipping the dirty-tree check because the plan looks good.** The plan's
  quality is irrelevant to `git worktree add`; a dirty tree means the lanes have
  nothing to build on.

## Reporting shape
Lead with the lane count and the collisions that forced it, then the
recommendation. A verdict with no matrix is not verifiable and will be re-asked.
