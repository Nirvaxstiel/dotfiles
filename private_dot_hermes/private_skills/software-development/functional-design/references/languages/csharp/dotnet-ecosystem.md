# C#/.NET ecosystem interactions

Where functional design meets the frameworks. Decisions only.

## LINQ

- LINQ method chains are composition and, via `SelectMany`, the practical monad
  bind. Prefer a chain over a manual loop when the operation is a transformation.
- LINQ is lazy for `IEnumerable<T>`. Do not return a deferred query across a
  boundary where the source may be disposed; materialise at the boundary.
- Keep `IEnumerable<T>` deferred queries out of properties that look like cheap
  accessors.

## Entity Framework Core

| Situation | Do | Never |
|---|---|---|
| A domain value object is persisted | Map it as an owned type or a value converter | Expose EF entities as the domain model |
| Read-only queries | `AsNoTracking()` | Track entities you will not modify |
| A domain type is immutable | Map via a converter or an owned type with backing fields | Add public setters purely for EF |
| Rich domain behaviour is needed | Keep behaviour on the domain type, persistence-mapped | Put business logic in the `DbContext` |

Entity classes are persistence shapes, not domain types. Do not let them define
the domain model; map between them at the boundary.

Prior art: the archived Hermes skill `csharp-domain-modeling` already holds the
EF Core material in depth — the three-hats decision flow (monolith / leaf /
producer), the mapping-layer contract, the no-free-lunch trade-off matrix, and
twelve EF Core pitfalls in survival tiers. Consult it before duplicating any of
that here; this file stays a thin decision layer.

## Collections

- `System.Collections.Immutable` (`ImmutableArray<T>`, `ImmutableList<T>`) for
  shared, never-mutated collections crossing boundaries.
- A `readonly` field holding a mutable collection is **not** immutable; the
  contents can still change.

## Serialization

- A `record` serialises by its properties; a positional record's parameter names
  are the property names. Renaming a case record member changes the wire shape —
  check `System.Text.Json` name mapping before renaming for style.
- Contracts beyond C# call sites (serialization, reflection, DI, P/Invoke) are
  part of the design surface. A compile-clean rename can still break a consumer.

## Nullable reference types

- Enable them project-wide. The warning surface is the optionality contract.
- At a boundary, convert `null`-able external input into a domain optional value
  once; do not let `null` propagate inward.
