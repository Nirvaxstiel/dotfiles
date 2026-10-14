# State modelling

**Decision:** how do I make illegal states unrepresentable?

Most invalid-state bugs come from a type that *allows* combinations the domain
forbids — a `null` that is only valid in one mode, two booleans that must not
both be true, a status enum plus fields that must agree with it. The fix is to
make each legal state its own shape, so an illegal one cannot be constructed.

## The rule

| Situation | Do | Never |
|---|---|---|
| A value has distinct modes with different data | One case per mode (see sum-and-product-types.md) | A shared record with fields valid only in some modes |
| A value is only meaningful after validation | A type that only a validated path can produce | A raw primitive plus a flag |
| Two fields must stay consistent | Combine them into one value | Store them independently and hope |
| An invariant must always hold | Enforce it in the only constructor | Document it and check at call sites |

Pattern: **parse, don't validate.** Convert untyped input into a typed value
once, at the boundary. Inside the boundary, the type carries the proof, so
downstream code stops re-checking.

## Smart constructors

The only way to build the value is a path that enforces the invariant. An
invalid value is then unconstructable, not merely discouraged.

## Smells

- A nullable field that is set only for one case.
- `bool IsA, IsB` that must never both be true (or both false).
- `status` plus data fields that must agree with each status.
- Validation repeated at every call site instead of once at construction.
