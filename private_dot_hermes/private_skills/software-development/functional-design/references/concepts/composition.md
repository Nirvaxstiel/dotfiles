# Composition

**Decision:** build behaviour from small, combinable pieces, or from type
hierarchies?

Composition assembles a large behaviour from small ones. It favours functions
that transform values and can be chained over inheritance that binds behaviour
to types.

## The rule

| Situation | Do | Never |
|---|---|---|
| A behaviour is a sequence of transformations | Chain small functions over a value | Write one large method |
| A caller supplies a piece of behaviour | Take a function parameter | Introduce a single-implementation interface |
| Variants differ only by one operation | Parameterise the operation | Duplicate the algorithm per variant |
| A value flows through fallible steps | A composition that short-circuits on failure (see expected-failure.md) | Nested conditionals |

## When inheritance is right

Composition is the default for *behaviour*. Inheritance still fits when there is
a genuine is-a with shared state and a framework lifecycle (e.g. a base type the
platform calls). The test is whether the hierarchy is a *taxonomy* or an
*assembly mechanism*. For assembly, prefer composition.

## Smells

- A strategy interface with exactly one implementation.
- A deep base-class chain where each level adds a small variation.
- Boolean parameters selecting behaviour inside one method.
- Behaviour reachable only by constructing the right subclass.
