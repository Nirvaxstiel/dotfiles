# C# idioms

The shape to write once a concept decision is made. Decisions and traps only —
not a syntax catalogue.

## Product types

| Situation | Do | Never |
|---|---|---|
| A data type is small and copied | `readonly record struct` | A mutable `struct` with setters |
| A data type may be large or inherits | `record` (class) with `init` | Public `set` accessors |
| A value changes in one field | `with` to produce a new value | Mutate the existing instance |
| Construction must be forced | `required` members or a primary constructor | Rely on callers to set everything |

## Sum types (no built-in unions — see capabilities.md)

```csharp
public abstract record Payment
{
    private Payment() { }                       // closes the hierarchy

    public sealed record Card(string Last4) : Payment;
    public sealed record BankTransfer(string Iban) : Payment;
    public sealed record Cash : Payment;
}
```

| Situation | Do | Never |
|---|---|---|
| A value is one of a fixed set of cases | `abstract record` + private ctor + `sealed` cases | `bool` flags or a `string` kind |
| Matching a sum | `switch` expression over the cases | An `if`/`else` chain |
| Exhaustiveness is required | Add a closed-hierarchy analyzer or a union library | Assume the compiler warns; it does not |
| A case carries no data | A parameterless `sealed record` case | A parallel enum field |

## Optionality

| Situation | Do | Never |
|---|---|---|
| A reference may legitimately be absent | `T?` with nullable reference types enabled | Ignore the warning |
| Absence is a domain state that must be handled | A dedicated optional type | `null` used as a sentinel |
| A lookup may find nothing | Return the optional result | Return `null` and document it |

## Expected failure

| Situation | Do | Never |
|---|---|---|
| Business validation fails | Return a `Result`-style value | Throw for expected failure |
| The environment is broken (I/O, DB down) | Throw, or let the boundary map it | Encode as an expected failure |
| Chaining several fallible steps | Compose via the `Result` type's bind/`SelectMany` | Nested `if`/`try` blocks |

Prefer an existing, well-tested `Result`/`Either` library over a bespoke one.

## Effects at the boundary

Ambient statics are hidden effects. Deterministic helpers are not.

| Ambient (an effect) | Inject instead |
|---|---|
| `DateTime.Now` / `DateTime.UtcNow` | `TimeProvider` (.NET 8+) — one captured instant per operation |
| `File.*`, `Directory.*`, `new FileInfo(...)` | `System.IO.Abstractions` `IFileSystem` |
| `new HttpClient(...)` | `IHttpClientFactory` / an injected `HttpClient` |
| `Environment.*`, `Console.*`, `Process.*`, `Guid.NewGuid` | A small injected seam |

`Path.Combine`, `Path.GetExtension`, `Math.*`, `string.*` take no ambient input
and need no seam. Do not wrap them.

## Purity

| Situation | Do | Never |
|---|---|---|
| A calculation has no ambient input | Mark it a pure `static` method | Reach for an injected dependency |
| A method both computes and mutates | Split into pure compute + replace | Mutate as a side effect of computing |

## Composition

| Situation | Do | Never |
|---|---|---|
| Behaviour is assembled from small steps | Extension methods and LINQ method chains | Deep inheritance hierarchies |
| A caller supplies behaviour | A `Func<>` parameter | A new interface with one implementation |
| A pipeline has fallible steps | A `Result`-returning chain | Exception control flow |
