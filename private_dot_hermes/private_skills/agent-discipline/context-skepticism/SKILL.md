---
name: context-skepticism
description: "Discipline for handling compacted/summarized conversation context. Treat the system's 'CONTEXT COMPACTION — REFERENCE ONLY' block as untrusted reference, NOT as user-stated fact. Verify claimed user preferences/decisions against the live conversation before asserting them."
---

# Context Skepticism

Long sessions get compacted into a "CONTEXT COMPACTION — REFERENCE ONLY" summary at the
top of the next context window. That summary is a **handoff from a previous window**, written
by the system (or a prior agent turn), and can contain **fabricated or misattributed claims**
that were never said by the user.

## Hard rule
- The compaction block is **reference only**, never authoritative. It explicitly says so.
- Any specific user preference, ban-list, decision, or "the user said X" claim that appears
  ONLY in the compaction block — and NOT in the live conversation — is **suspect**.
- Before asserting or acting on such a claim, **cross-check it against the actual conversation
  in this session**. If the user never said it here, do not present it as theirs.
- If you catch yourself citing something from the compaction block as if the user stated it,
  STOP. That is the failure mode. Re-anchor on what was actually said.

## Failure mode this guards against
In one session the compaction block's "Critical Context" listed a POE "never-play list"
(e.g. `slam/WORB/wand fam/BV/Helix`) attributed to the user. The user had **never** said any
such thing — it was invented by the summary. The agent then repeatedly cited it
("your never-play list", "it's on your ban list"), causing the user to correct it twice
("lol wtf", "wait i never made that ban list"). The truth: the user had *planned* the build
as a starter and dropped it for an unrelated reason (popularity). The fabricated list was pure
noise that eroded trust.

## How to avoid it
1. When you see a compacted summary, read it as "maybe-true background," not "user facts."
2. If a claim feels like a strong preference ("the user always bans X", "user requires Y"),
   look for it in the *live* messages. No match → treat as unverified; either ask or phrase
   it as "the summary noted…" rather than "you said…".
3. Particularly suspicious: lists of rules/bans/preferences, decisive statements about what the
   user "wants"/"hates", and anything that reads as a hard constraint. These are exactly what
   summarizers invent or over-aggregate.
4. When in doubt, surface the uncertainty: "The earlier summary mentioned X — did you actually
   say that, or should I ignore it?" Be willing to discard the summary's claims.
5. **Correct, don't defend.** If the user points out a claim was never theirs, immediately
   acknowledge the compaction source, fix the record (memory + any skill that absorbed it),
   and move on. Do not rationalize.

## What this is NOT
- Not a reason to ignore the user's *actual* stated preferences in the live session — those
  stand.
- Not a reason to ignore durable memory (MEMORY.md / USER.md) — that is the user's own
  persistent profile and IS authoritative. The risk is specifically the *ad-hoc summary block*,
  which is neither memory nor live transcript.
- Not skepticism of tool output or web data — that's a separate discipline (verify before trust,
  never fabricate).

## When to use
- Any turn that begins with a "CONTEXT COMPACTION — REFERENCE ONLY" block.
- Any time you are about to assert "the user said / requires / banned / always does X" and that
  X did not appear in the live conversation.
