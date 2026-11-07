# Immutability

**Decision:** should this value change in place, or be replaced by a new value?

A value that cannot change after construction is safe to share, safe to compare,
and safe to reason about locally. Mutation makes correctness depend on everything
that ever touched the object.

## The rule

Prefer construction over modification. When a value must change, produce a new
value from the old one; do not edit the old one.

| Situation | Do | Never |
|---|---|---|
| A domain value gains a field | Return a new value with the field set | Add a public setter "for now" |
| A collection is handed to another component | Hand over an immutable or unshared copy | Hand over a mutable collection others can edit |
| A method computes and also modifies its receiver | Split: compute purely, then replace | Mutate the receiver as a side effect of computing |
| A type crosses a boundary (public API, thread) | Make it immutable | Rely on callers to not mutate it |

## When mutability is correct

Immutability is the default, not a dogma. Local, contained mutation is fine:

- A loop accumulator that never escapes the function.
- A builder that is mutated, then frozen once into an immutable product.
- A performance-critical buffer where copying dominates (measure first).

The test is **reachability**, not the keyword: if no other code can observe the
value while it changes, the mutation is not shared state.

## Smells

- Public setters on a domain type.
- A method whose name reads like a query but that changes state.
- Defensive copying at every boundary — a sign the underlying value should
  have been immutable in the first place.
