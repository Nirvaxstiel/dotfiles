# Purity and effects

**Decision:** which parts are computation, and where do side effects live?

A pure function returns the same output for the same input and has no observable
effect. Everything else — reading the clock, touching the disk, hitting the
network, logging, mutating shared state — is an effect. A design is functional
when the *core* is pure and effects sit at the edges.

## The rule

| Situation | Do | Never |
|---|---|---|
| Domain logic needs the current time | Pass the time in as a value | Read the clock inside the logic |
| Logic needs to read or write the outside world | Push the effect to a boundary; keep the core pure | Call I/O from the middle of the domain |
| Several steps are pure except one | Isolate the one effect; keep the pipeline pure | Interleave effects through the pipeline |
| A "calculation" also writes a record | Split: compute a value, then let the boundary persist it | Compute and persist in one step |

Pattern: **functional core, imperative shell.** The core is pure and testable
with no mocks; the shell performs effects and holds no logic.

## Classifying a call

Ask: does this depend on ambient state, or only on its arguments?

- Ambient (an effect): clock, filesystem, network, environment, console,
  process, randomness, identity generation.
- Pure: deterministic helpers (`Path.Combine`, `Math.*`, `string.*`) that take no
  ambient input. These need no seam. Wrapping them is over-engineering.

Reading the clock twice in one operation is both an effect and a defect: two
reads can disagree. Capture one instant.

## Smells

- Rich logic that reads `DateTime.Now` or `Environment.*` directly.
- A method that computes and has an unstated side effect.
- Every unit test needs a fake filesystem to test arithmetic.
