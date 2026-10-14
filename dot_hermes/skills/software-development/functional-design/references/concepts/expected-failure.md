# Expected failure

**Decision:** is this failure expected (part of the domain) or exceptional
(a broken assumption)?

Expected failures are outcomes the design anticipates: validation failure, a
missing record, a business rule declined. They are part of the contract and
should be **values**. Exceptional failures are broken invariants or a broken
environment: they should stop the operation and are legitimately thrown.

## The rule

| Situation | Do | Never |
|---|---|---|
| A business rule can decline | Return a failure value | Throw for an expected outcome |
| Input fails validation | Return a failure value carrying the reason | Throw and catch for control flow |
| An invariant is violated, or I/O is broken | Throw (or let the boundary surface it) | Encode it as an expected failure |
| A caller must handle a possible failure | Force the failure into the type | Return `null`, `false`, or a sentinel |

## Distinguish from optionality

Absence ("there may be no value") is not failure ("the operation was rejected").
They are different states and get different types (see `optionality.md`). Fusing
them loses the reason.

## Chaining

Fallible steps compose: a chain that stops at the first failure and carries the
reason forward. This replaces nested `if`/`try` with a single readable pipeline.

## Smells

- `throw` for a case the caller was expected to hit routinely.
- `catch` used to branch on a business outcome.
- `null` or a string error code standing in for a failure.
- A `bool` return that discards *why* the operation failed.
