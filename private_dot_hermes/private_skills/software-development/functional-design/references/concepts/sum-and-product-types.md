# Sum and product types

**Decision:** is this data "all of these" (product) or "one of these" (sum)?

- A **product** combines fields that all exist together: a `Customer` has an id
  *and* a name *and* an address.
- A **sum** is exactly one of a closed set of cases: a `Payment` is a card
  *or* a bank transfer *or* cash.

Getting this wrong is what forces boolean flags, `null` branches, and
downstream `if` chains.

## The rule

| Situation | Do | Never |
|---|---|---|
| Several values always travel together | One product type with those fields | Separate parameters passed side by side |
| A value is exactly one of a fixed set of cases | One sum type with explicit, named cases | A `bool` flag, a string "kind", or `null` to select a case |
| Cases carry different data | Give each case its own shape | A shared struct with fields only some cases use |
| The set of cases must be closed | Make the set closable and closed | Leave an open hierarchy anyone can extend |

## Why closure matters

A sum is only as good as the guarantee that its case set is fixed. If new cases
can appear from anywhere, no consumer can be sure it handled them all — and the
compiler cannot warn. Closure is what turns "one of these" into a checkable
fact.

## Distinguish from an enum

An `enum` is a sum with **no data per case**. The moment a case needs to carry
values, an enum plus parallel fields is the wrong shape; it is a sum type.

## Smells

- `bool IsX` plus `bool IsY` that must never both be true.
- A nullable field that is only set for one case.
- A `switch` whose `default` throws "unreachable" because the type system did
  not express the closure.
