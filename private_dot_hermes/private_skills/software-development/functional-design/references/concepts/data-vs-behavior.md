# Data vs behaviour

**Decision:** are the data and the functions over it separated?

In object-oriented design, a type carries both its data and the methods on it.
Functional design separates them: types describe **shape**, and functions
operate on that shape. This separation is what lets matching over a sum type be
exhaustive — all the behaviour for a case set lives in one place, not spread
across the types.

## The rule

| Situation | Do | Never |
|---|---|---|
| Behaviour over a sum type | Functions (or a `switch`) over the cases | Virtual methods spread across the case types |
| Behaviour over a product type | A method or an extension is fine | Force indirection where none is needed |
| Adding a case to a sum | A compile error at each function | A silent new branch everywhere |
| Adding an operation | A new function over the cases | A change in every case type |

This is the expression problem: sums make *adding cases* costly and *adding
operations* cheap; classes make the reverse. Choose deliberately.

## Smells

- A sum type's cases each implement an operation, so no single place shows all
  behaviour and no `switch` can be checked for totality.
- Business logic identical across several types, copy-pasted rather than
  extracted into a function over a shared shape.
