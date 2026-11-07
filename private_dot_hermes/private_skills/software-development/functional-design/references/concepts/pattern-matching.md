# Exhaustive matching

**Decision:** is every case handled, and is that checked?

Matching decomposes a value by its shape. Its value over an `if`/`else` chain is
**totality**: when the set of cases is fixed, the compiler can require that all
are handled, and adding a case becomes a compile error rather than a silent
miss.

## The rule

| Situation | Do | Never |
|---|---|---|
| A value is one of a fixed set of cases | Match every case explicitly | Add a catch-all that hides a forgotten case |
| A new case is added | Let every match fail to compile until updated | Rely on tests to catch the miss |
| Matching a single condition | A guard clause | A one-arm `switch` |
| The case set is open | Match the type you actually handle, and say what is unhandled | Pretend it is exhaustive |

## The catch-all trap

A wildcard arm (`_`) is correct only when it genuinely means "everything else".
Used to silence the compiler over a closed set, it converts a future compile
error into a runtime bug. totallity is the whole point; do not trade it away.

## Totality requires closure

The compiler can only enforce exhaustiveness if it knows the case set is closed.
Where the type system cannot express closure, totality becomes a discipline
(an analyzer, a library, or a convention) — say which you are relying on rather
than implying a guarantee you do not have.

## Smells

- `default: throw new UnreachableException()` — the type did not express closure.
- `_ => { }` swallowing cases that should be handled.
- A long `if`/`else if` chain over what is really a fixed set of cases.
