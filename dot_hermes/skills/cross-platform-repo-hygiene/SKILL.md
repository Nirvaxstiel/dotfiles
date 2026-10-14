---
name: cross-platform-repo-hygiene
description: Use when a Windows-edited repo deploys to Linux.
version: 1.0.0
author: hermes-curator
license: MIT
metadata:
  hermes:
    tags: [cross-platform, windows, msys, line-endings, verification]
    related_skills: [nixos-flake-config, testing-strategy]
---

# Cross-platform repo hygiene (Windows host -> Linux target)

A repo edited on Windows and deployed to Linux carries three failure classes that
are invisible on the host and fatal on the target: line endings, path separators,
and artifacts declared "verified" that were never actually run. None of them
require the target machine to fix or to detect.

## When to Use

- Editing any repo on a Windows/MSYS host whose runtime or deploy target is Linux.
- Generating or copying files into such a repo from a script.
- Writing a shell script that will only ever execute on the Linux side.
- Verifying generated config or script logic when the target toolchain is not
  installed on the host (no package manager, no compiler, no application).
- Before committing anything to such a repo: the line-ending check is a
  pre-commit step, never a post-deploy investigation.

## Always-on rules

### 1. Pin LF in `.gitattributes` before anything else
Without it, `core.autocrlf=true` (the Windows default) rewrites `bin/*.sh` to CRLF
on checkout, and the shebang then fails on Linux with
`bad interpreter: /usr/bin/env bash^M` — a failure that only ever appears on the
target, long after the commit that caused it.

```
* text=auto eol=lf
```

`eol=lf` keeps the working tree LF on every platform, which is what a repo whose
only runtime is Linux wants. Verify by walking every tracked file and flagging any
that contains `\r`; do this before committing, not after deploying.

### 2. Never let the host platform add CR to a generated file
Python's `Path.write_text` opens in text mode and translates `\n` to CRLF on
Windows. Every generated file a Linux tool reads (config, script, data) must be
written with `newline=""`:

```python
dst.write_text(text, encoding="utf-8", newline="")
```

The same applies when copying files INTO the repo with a script: normalize on the
way in (`text.replace("\r\n", "\n").replace("\r", "\n")`), then re-read and
assert `"\r" not in content` so the repo never silently gains a CRLF file.

### 3. Hand POSIX paths to anything bash or a native tool reads
`terminal` runs bash, but MSYS does NOT translate path arguments for native
programs. A Windows `Path()` string interpolated into a bash command loses its
backslashes (`C:\Users\Kei\x` becomes `C:UsersKeix`), so the command reads or
writes the WRONG file — and frequently still exits 0.

```python
p = pathlib.Path(...).as_posix()      # C:/Users/Kei/x — safe for bash
```

Always assert the intended side effect as well as the exit code.

### 4. Verify generated artifacts by simulation, not by assertion of correctness
When the target toolchain is absent from the host (package manager, compiler, the
application itself), the logic that decides the target's behaviour is still
testable:

1. Reproduce the artifact from the real upstream input and read it.
2. Test merge/override logic against the REAL upstream file, not a stub — assert
   both the resulting key set and the collision set.
3. Test a shell script in a THROWAWAY COPY with the environment call replaced by an
   injected fixture: swap `$(id -u)` for `0` and `getent shadow "$USER"` for
   `cat "$FAKE_SHADOW_FILE"`, then write one fixture per branch and assert the exit
   code plus the one message that matters.
4. State plainly what remains unverified and hand over the exact commands.

Prepending a stub directory to `PATH` does NOT reliably beat the real binary —
`command -v` keeps resolving the system copy under MSYS. Replacing the call site
is what works.

### 5. Delete by exact path, never by glob
A broad glob can match paths outside the repo — including the agent's own runtime
directory — and destructive-delete guards will (correctly) refuse the whole
command. Resolve the target in a language runtime and unlink the exact path:

```python
target.unlink()
```

Then re-check the repo root: a stray harness or fixture lands in `git status` as
untracked junk and gets committed by accident.

## Pitfalls
- A CRLF defect is invisible until the target executes the file. Grep for `\r` as
  a pre-commit step, never as a post-deploy investigation.
- Exit code 0 does not mean the correct file was touched. Assert the side effect.
- Keep test harnesses and fixtures OUT of the repo, and delete them when done.
  Never place a harness inside a tracked directory — removing it later risks
  taking tracked files with it.
- Authoring a file with a heredoc/echo through bash on this host reintroduces the
  CRLF problem; write files with a file-writing tool instead.
