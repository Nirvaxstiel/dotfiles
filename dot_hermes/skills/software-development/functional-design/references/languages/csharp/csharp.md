# C#/.NET realization

This layer turns a concept decision into idiomatic C#. It does not redefine the
concepts.

## Concept → C# map

| Concept | C# form | File |
|---|---|---|
| Immutability | `readonly struct`, `record`/`record struct` with `init`, `with`, `System.Collections.Immutable` | `idioms.md` |
| Purity and effects | Pure `static` methods; injected seams (`TimeProvider`, `IFileSystem`, `IHttpClientFactory`) | `idioms.md` |
| Composition | Extension methods, `Func`, LINQ method chains | `idioms.md` |
| Sum and product types | Product: `record`. Sum: `abstract record` + private ctor + `sealed` cases | `idioms.md` |
| Exhaustive matching | `switch` expressions with property/list patterns | `idioms.md` |
| Optionality | Nullable reference types; a dedicated optional type when absence is a domain state | `idioms.md` |
| Expected failure | A `Result` type for expected failure; exceptions for exceptional failure | `idioms.md` |
| State modelling | One type per valid state; smart constructors | `idioms.md` |
| Data vs behaviour | Records plus static functions or extension methods | `idioms.md` |
| Domain modelling | Smart constructors; `TryParse` returning an optional result | `idioms.md` |

## Before you write C# here

1. Read the concept file that owns the decision.
2. Check `capabilities.md` for the language/runtime version facts that make a
   construct available — especially for sum types, where C# lags other
   languages.
3. Use `idioms.md` for the shape; use `dotnet-ecosystem.md` for LINQ, EF Core,
   and serialization interactions.

## Non-negotiables

- Respect C#'s own semantics. Do not present a syntax that does not compile on
  the target version.
- Every capability claim is dated in `capabilities.md`. If you are unsure
  whether a feature ships, say so rather than emitting it.
- A design-school preference (see `../../schools/`) is not a C# rule.
