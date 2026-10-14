# Concepts (language-independent)

Load one file per design decision. These files describe concepts, independent of
any language.

| Concept | Load when the decision is… |
|---|---|
| `immutability.md` | Whether a value changes in place or is replaced |
| `purity-and-effects.md` | Which parts are computation, and where effects live |
| `composition.md` | Whether to build behaviour from small pieces or hierarchies |
| `sum-and-product-types.md` | Whether data is "all of these" or "one of these" |
| `pattern-matching.md` | Whether every case is handled, and checked |
| `optionality.md` | Whether absence is a real domain state |
| `expected-failure.md` | Whether a failure is expected (a value) or exceptional |
| `state-modeling.md` | How to make illegal states unrepresentable |
| `data-vs-behavior.md` | Whether data and the functions over it are separated |
| `domain-modeling.md` | Whether the types speak the domain |

## Reading order

Concepts build on each other. `immutability` and `purity-and-effects` are the
foundation; `sum-and-product-types` and `pattern-matching` are the working core;
the rest specialize those.

## Rules for this directory

- One concept per file. If a file needs a second decision, it is two files.
- No language syntax. If a paragraph only makes sense in one language, it belongs
  in that language's realization.
