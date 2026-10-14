# C#/.NET capability facts

Dated, sourced, and kept separate from design guidance. Re-verify on the
maintenance cycle (`../../maintenance.md`). Last checked 2026-10-07.

Sources: Microsoft Learn "What's new in C# 14" and "The history of C#";
`dotnet/csharplang` proposals and the discriminated-unions working group.

## Current versions

| Item | Value |
|---|---|
| Latest C# release | C# 14, released November 2025, ships with .NET 10 |
| Next | .NET 11 / C# 15 in development (upstream repo carries a `dotnet11` plugin) |
| Target framework for new code | `net10.0` unless the project pins lower |

## Feature availability

| Feature | Ships since | Use for |
|---|---|---|
| `record` (class) | C# 9 | Product types with value equality |
| `record struct` | C# 10 | Small product values with value semantics |
| `init`-only setters, `with` | C# 9 | Non-destructive mutation |
| Nullable reference types | C# 8 | Optionality surface (warnings, not errors) |
| Property / positional patterns | C# 8–10 | Matching on products |
| Relational, logical, parenthesized patterns | C# 9 | Range and combined patterns |
| List patterns | C# 11 | Matching sequences |
| Required members | C# 11 | Forcing construction-time assignment |
| Primary constructors | C# 12 | Concise construction |
| `static abstract` interface members | C# 11 | Generic-math style abstraction (partial HKT substitute) |

## Load-bearing gap: discriminated unions

**C# has no built-in closed union / discriminated-union type as of C# 14.**

- A union proposal exists and is under active design in `dotnet/csharplang`
  (nominal type unions; a "closed class hierarchies" variant). Not shipped.
- Do **not** emit `union` syntax; it will not compile.
- Idiomatic substitute today: an `abstract record` with a **private
  constructor** and `sealed` case records. See `idioms.md`.
- **Exhaustiveness is not compiler-enforced** over that substitute. A `switch`
  expression needs a wildcard arm. Restore the guarantee with a
  closed-hierarchy analyzer or a union library — not by pretending the compiler
  checks it.

## Higher-kinded types

Not supported (`csharplang#339`, closed). Do not present typeclass- or
monad-general abstractions as first-class. LINQ's `SelectMany` is the practical
monad bind; note it is a compiler-level binding, not a general interface.

## Re-check triggers

Re-verify this file when any of these changes upstream: C# language version,
the discriminated-union proposal status, `dotnet/csharplang` proposal moves, or
a new `dotnet11`-style capability plugin appears.
