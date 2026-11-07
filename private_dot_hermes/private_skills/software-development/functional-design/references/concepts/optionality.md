# Optionality

**Decision:** is absence a real domain state, and how is it represented?

Absence is information. "No middle name" and "middle name is the empty string"
are different facts. Collapsing absence into `null`, a sentinel, or a default
destroys that information and moves the check to runtime.

## The rule

Represent absence as a value of its own. Make the caller acknowledge it.

| Situation | Do | Never |
|---|---|---|
| A field is genuinely optional | Model it as optional, and say what "absent" means | Use `null` to mean "absent" |
| A lookup may find nothing | Return an optional result | Return `null` and document it |
| Absence and failure are both possible | Keep them separate: `Option` for absence, a failure type for failure | Fuse "not found" and "error" into one `null` |
| A default is genuinely correct | Use the default, explicitly | Use a default to hide a missing value |

## Distinguish three things

1. **Absence** — the value legitimately may not exist (no middle name).
2. **Failure** — the value should exist but the operation failed (see
   `expected-failure.md`).
3. **Default** — a real, meaningful value chosen when none is supplied.

Conflating them is the most common optionality defect.

## Smells

- `null` checks scattered across call sites instead of one boundary.
- A `TryGet(out T value)` that callers ignore and then use `value` anyway.
- A boolean `HasValue` flag sitting next to the value it qualifies.
- A sentinel (`-1`, `""`, `DateTime.MinValue`) standing in for "not set".
