# Design school: Zoran Horvat

This is a **preference layer**. It records one practitioner's stance so it can be
consulted deliberately. It is not the definition of any concept, and its
preferences are not universal rules. Nothing else in this skill depends on this
file.

Provenance: distilled from the archived Hermes skill `csharp-domain-modeling`
(itself derived from Horvat's talks) plus published course syllabi. Treat
everything below as *a position*, not as fact, and re-verify against a primary
source before quoting it as his.

## Position in one line

Functional design **inside** an object-oriented language, in the right
proportion — use functional techniques where they remove complexity, not as a
replacement for OO.

The archived distillation frames the core claim as general practice rather than
one person's insight: *"A model is anemic because you designed a table, not a
behavior. Pay the mapping cost, test the boundary."*

## Which hat are you wearing?

Horvat's techniques assume a specific context. Decide first.

| Context | What you have | What applies |
|---|---|---|
| **Monolith** | Domain + persistence in one process | Full tension: FP domain vs change-tracked storage. Accept mutability at the aggregate boundary, or pay the mapping cost with tests as guardrail |
| **Leaf** (projection / audit / read model) | Events in, stored, no behaviour | Not a domain-modelling problem — schema versioning tests are the guardrail |
| **Producer** (event source) | Pure domain, no persistence | Full functional design applies; the persistence problem does not exist |

## Recurring themes

| Theme | Stance |
|---|---|
| Discriminated unions | A core modelling tool; a large body of work on working around their absence in older C# |
| Functions as objects | First-class functions to hide dependencies and build larger features |
| Partial application | Hiding implementation behind partially applied functions |
| Composition | Function composition over polymorphic execution for many problems |
| Errors | Railway-oriented programming; functional error handling instead of exceptions |
| Optionality | An explicit optional functional type |
| Control flow | Less branching and null checking: guard clauses, Null Object / Special Case |
| Object creation | Stable constructors over reflexive Builder/Factory ceremony |
| Primitive obsession | Replace primitives with typed values; use an *augment then transform* migration, never a big-bang rewrite |
| Repositories | Write aggregate-specific interfaces that accept the ORM — not a generic `IRepository<T>` |

## Domain-first ordering

Model the domain without considering persistence; the database is an
infrastructure detail. The seam between a functional domain and an
object-oriented store is **structurally necessary**, not a defect — the mapper
is the toll between them. Keep the seam explicit, owned, and tested.

## How to use this file

- Load it when the question is "what would a functional-first C# practitioner
  do here?" — an opinion question.
- Do not present any row above as a rule the concepts require.
- Where this stance conflicts with a concept, the concept wins; where it
  conflicts with an idiom, state both and label it a preference.
- Flip side worth tracking: the "right proportion" framing is itself arguable.
  A functional-first team may push further toward purely pure design. Record
  disagreements rather than smoothing them.

## Related prior art

The archived skill `csharp-domain-modeling` holds the fuller material: the
three-hats decision flow, the mapping-layer contract (read contract, write
strategy, boundary pitfall catch), the no-free-lunch trade-off matrix, EF Core
pitfalls in survival tiers, and an interview pitch. Consult it before expanding
this file; mine it, do not re-derive it.

## Primary talks

| Topic | Reference |
|---|---|
| Thin DDD abstractions | "Your DDD Abstractions Are a Waste of Code" |
| Functional domain modelling | "Unleash Your Functional Modeling Superpowers" |
| Functional behaviour design | "Master the Design of Functional Behavior in C#" |
| Deep immutable entities in EF Core | "Solving the Deep Immutable Problem in EF Core" |
| C# records | "The Ultimate Guide to C# Records" |
| Discriminated unions in C# | "Possibility of Discriminated Unions in C#" |
| Rich domain models with EF Core | "Stop Blaming EF Core for Your Anemic Models" |
| Primitive obsession | "Wish to Remove Primitive Obsession? Try This" |

## Open items

- Re-derive any claim you intend to attribute to Horvat personally from a
  primary source; the archived distillation deliberately attributes little.
- Add a second school only when a real decision needs one.
