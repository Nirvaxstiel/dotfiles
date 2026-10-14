---
name: functional-design
category: software-development
description: Apply functional design to code and domain models.
version: 0.4.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [functional-programming, design, architecture, domain-modeling, immutability]
    related_skills: [architecture-principles, constraint-driven-development, testing-strategy]
---

# Functional Design

Design with values, pure functions, and explicit failure. Keep effects at the
edges. Make illegal states unrepresentable.

## When to use

Load when the decision is a **design** decision:

- Modelling a domain (types, states, cases).
- Deciding where side effects live.
- Replacing null- or exception-driven control flow.
- Reviewing a design for invalid-state or hidden-effect risk.

## When not to use

- Syntax trivia with no design decision.
- Test authoring — use the project's test workflow.
- Build or tooling failures, or performance tuning.

## Layers

| Layer | Path | Use when |
|---|---|---|
| Concepts (language-independent) | `references/concepts/` | Deciding *what* the design should be |
| Realization | `references/languages/` | Deciding *how* to express it in a given language |
| Design schools (optional) | `references/schools/` | You want one author's stance |

One realization directory per language. Load only the one for the language at
hand; its capability facts are dated beside it.

## Navigate by decision

1. State the design decision in one sentence ("model a customer that is either
   registered or a guest").
2. Open the concept that owns that decision: start at
   `references/concepts/_index.md`.
3. Open the realization for the target language under `references/languages/`.
4. Prefer the general concept. Treat a design school as a *preference layer*
   (`references/schools/`), never as the definition of the concept.

## Ground rules

- Concepts are language-independent. If a sentence only makes sense in one
  language, it belongs in that language's realization.
- A realization respects its language's own semantics and idioms. Do not force
  another language's shape onto it.
- Track language and runtime capability facts separately from design guidance,
  and date them.
- Separate *general principle* from *optional design-school preference*. Never
  present a school's preference as a universal rule.

## Index

- Concepts: `references/concepts/_index.md`
- Realizations: `references/languages/` (one directory per language)
- Design schools: `references/schools/`
