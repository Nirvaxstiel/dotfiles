# Domain modelling

**Decision:** do the types speak the domain, or do primitives stand in for it?

A type is documentation the compiler enforces. When a domain concept is modelled
as a bare primitive (`string` for a customer id, `decimal` for money, `int` for
a quantity of anything), every rule about that concept lives only in the
reader's head and in scattered checks.

## The rule

| Situation | Do | Never |
|---|---|---|
| A primitive carries a domain rule | A dedicated type with a smart constructor | A bare primitive plus validation calls |
| A value must be validated once | Produce a validated type at the boundary | Re-validate everywhere it is used |
| Two values must not be confused | Distinct types | The same primitive for both |
| A unit matters (money, duration) | Encode the unit in a type | A naked number |

Pattern: **parse, don't validate** (see `state-modeling.md`). A value that has
been validated should carry that proof in its type, so no downstream code needs
to check again.

## Smells

- Many `string`/`decimal`/`int` parameters where the order is easy to get wrong.
- Validation code repeated at the top of many methods.
- A value that is sometimes treated as validated and sometimes not.
- Money as `double`.
