---
name: architecture-principles
description: "Code & architecture principles for production systems — domain modeling, state safety, data pipeline audits, static-site architecture, trade-off analysis, simplicity."
version: 2.6.0
author: Kei
license: MIT
metadata:
  hermes:
    tags: [architecture, domain-modeling, state-safety, testing, simplicity, data-pipeline, static-site]
    related_skills: [testing-strategy, csharp-domain-modeling, frontend-static-viz]
---

# Architecture Principles

## Overview

Engineering craft rules for building maintainable, correct systems. These apply regardless of framework, ORM, or project size — they're the constraints that make code predictable and change safe.

## When to Use

- Writing or reviewing production code
- Designing domain models and service boundaries
- Setting up project conventions
- Onboarding to a new codebase

## Principles

### Domain Modeling & State Safety

- Model the business domain accurately using rich types, aggregates, and value objects
- Make invalid states unrepresentable via types, sealed unions, smart constructors
- Encode failures in return type (Result/Either), never exceptions or null

### Spec-First Domain Modelling Workflow

When designing or refactoring a domain model, follow this strict **spec-first** sequence.
The user explicitly confirmed this workflow as preferred over jumping to code:

```
Step 1: Sketch core entities with relationships
   — What exists? (Model, Source, Axis, Pricing)
   — What are the cardinalities? (Model N→N Source, Axis 1→1 Source)
   — What's identity? (Model.id, AxisId = "source.name")

Step 2: Define value objects with domain ranges and composition rules
   — Every non-trivial scalar gets a name: PricePerMToken, IntelligenceScore, Elo
   — Document the valid range: [0, ∞), [0, 100], (0, ∞)
   — Document composition: PricePerMToken × TokensPerTask → CostPerTask
   — Serialization: each value object flattens to its underlying primitive in JSON

Step 3: List every invariant as a testable rule
   — "creator is null only when no AA data"
   — "AA pricing and benchmarks come as a pair"
   — "cost breakdown fields are all-null or all-present"
   — "direction is never null on any axis"
   — Number them for cross-reference

Step 4: Enumerate invalid states that cannot be represented
   — "A model with pricing.aa but no benchmarks.aa"
   — "A PricePerMToken with negative value"
   — "A curated ProjectionRow with null creator"
   — Be explicit: each invalid state should be trivially impossible

Step 5: Only then — implement in code
   — Python: frozen dataclasses + __post_init__ validation
   — Types: enums for Direction, ModelType, SourceKey (not raw strings)
   — JSON: serialized for JS consumption; JS trusts the guaranteed shape
```

**Why spec-first:** The spec becomes the single source of truth that both pipeline (Python) and UI (JavaScript) reference. Changes to the data model start with updating the spec, not with patching code. This prevents the "silent drift" where the code evolves one way and the mental model another.

#### Rich Value Objects as Consumable Properties

Value objects should be designed so the **consuming layer** (UI projection, dashboard rows) can use them directly as typed properties — not as raw floats that need re-interpretation:

```python
# Bad — consumer has to know units, ranges, and validation rules:
inp_price: float  # is this $/tok or $/Mtok? can it be negative?

# Good — consumer uses the type directly:
inp_price: PricePerMToken  # $/Mtok, >=0, validated at construction
intel: IntelligenceScore   # 0-100, validated at construction
direction: Direction       # enum, not nullable boolean
```

On the JavaScript side (zero-build, vanilla JS), value objects are a design-time concept — JSON carries the primitive. The pipeline guarantees validity so JS reads without defensive checks:

```javascript
// Pipeline guarantees this is a valid PricePerMToken >= 0.
// JS just reads the float.
const cost = model.inp_price * tokens;
```

**When to skip value objects:** If a field is never transformed, never validated, and never composed — a pure passthrough string like `license` or `architecture` — leave it as a raw primitive. Value objects pay for themselves at transformation boundaries, not passthrough paths.

### Python Implementation Pattern for Value Objects

```python
from dataclasses import dataclass
from typing import Any

class DomainValue:
    """Base for scalar value objects that serialize to a single primitive.

    Subclasses are frozen dataclasses with exactly one field.
    `as_primitive()` extracts that field for JSON serialization.
    """
    def as_primitive(self) -> Any:
        field_name = next(iter(self.__dataclass_fields__))
        return getattr(self, field_name)

    def __float__(self) -> float:
        v = self.as_primitive()
        assert isinstance(v, (int, float)), f"Cannot convert {type(v)} to float"
        return float(v)


@dataclass(frozen=True)
class PricePerMToken(DomainValue):
    """/M tokens. Non-negative. Flattens to JSON float."""
    usd: float

    def __post_init__(self):
        assert self.usd >= 0, f"Negative price: {self.usd}"


@dataclass(frozen=True)
class IntelligenceScore(DomainValue):
    """AA intelligence score, 0–100."""
    value: float

    def __post_init__(self):
        assert 0 <= self.value <= 100, f"Out of range: {self.value}"
```

**Rules:**
- `frozen=True` — immutable by contract, hashable for sets
- `__post_init__` — validation fires at construction, not at read time
- `DomainValue` base — gives `as_primitive()` for JSON serialization
- The inner field name carries semantics (`usd`, `value`, `pct`) — not a generic `.value` that would hide corruption

### Safe Constructors for Nullable/NaN Data

Raw source data may contain `None`, `NaN`, or missing values. Never pass raw data directly to a value object constructor — wrap with a **safe constructor** that returns `None` for invalid input:

```python
import math

def safe_ppm(v) -> PricePerMToken | None:
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return None
    return PricePerMToken(v)

def safe_intel(v) -> IntelligenceScore | None:
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return None
    return IntelligenceScore(v)
```

**Pattern:** safe constructors handle the "maybe" at the boundary so value objects can be strict. If the data says 103 on a 0-100 scale, the constructor throws — that's a signal, not a bug to silence.

**Where to define them:** Same module as the value object. Export both the strict class and the safe factory. The consuming entity uses safe constructors for all nullable fields:

```python
@dataclass
class ProjectionRow:
    inp_price: PricePerMToken | None = None
    intel: IntelligenceScore | None = None

# Construction:
row = ProjectionRow(
    slug=mid,
    name=name,
    inp_price=safe_ppm(a.get("aa.inp_price")),
    intel=safe_intel(a.get("aa.intel")),
)
```

### Entity `to_dict()` Serialization Pattern

Value objects live in the pipeline. JSON consumers see primitives. Every entity dataclass needs a `to_dict()` method that:
1. Calls `as_primitive()` on each value object field
2. Passes `None` through unmodified
3. Converts `Enum` fields to `.value`
4. Handles nested entity dataclasses recursively

```python
@dataclass
class ProjectionRow:
    slug: str
    name: str
    inp_price: PricePerMToken | None = None
    intel: IntelligenceScore | None = None

    def to_dict(self) -> dict:
        d = {
            "slug": self.slug,
            "name": self.name,
            "inp_price": self.inp_price.as_primitive() if self.inp_price else None,
            "intel": self.intel.as_primitive() if self.intel else None,
        }
        # For fields with identical mapping, use a loop:
        optional_map = {
            "cost_per_task": self.cost_per_task,
            "speed_tps": self.speed_tps,
        }
        for key, val in optional_map.items():
            d[key] = val.as_primitive() if val else None
        return d
```

**Key insight:** The entity's `to_dict()` is the sole JSON contract. If it produces the right shape, the frontend works. Test this by round-tripping: build → to_dict → verify against expected JSON.

### Python Dataclass Field Ordering Pitfall

Python requires that dataclass fields **with defaults** come after fields **without defaults**:

```python
# ❌ ERROR: non-default argument follows default argument
@dataclass
class ProjectionRow:
    slug: str                    # no default
    name: str                    # no default
    type: str | None = None      # has default — ERROR! non-default fields follow
    inp_price: PricePerMToken    # no default

# ✅ CORRECT: all required fields first
@dataclass
class ProjectionRow:
    slug: str                    # required
    name: str                    # required
    inp_price: PricePerMToken    # required
    type: str | None = None      # optional — after all required fields
    blended: PricePerMToken | None = None  # optional
```

**Remember:** Every time you add `= None`, `= field(...)`, or any default to a field, that field must be after every field without a default. Moving fields to satisfy ordering is normal — use keyword arguments in construction so order doesn't matter at call sites.


If a business rule requires tracing through a service layer + three repositories to understand, you've paid complexity without collecting the benefit. A good model makes rules explicit in the type system:

```csharp
// Bad — rule hidden in service
if (order.Status != "shipped") { ... }

// Good — rule in the model
order.AddLine(product, price, qty);  // throws if shipped
```

### Clarity Over Comments

- Comments = weak architecture. Make code self‑explanatory via names, structure, types
- Comment only for external APIs, obscure standards, legal notices
- **Section headers are a smell.** If you're writing `# ── Section ──` or `# ═══════` dividers, the file is too long. Split it into smaller files rather than organizing sections inside one. A 1120-line file with 10 banner-divided sections should become a package. The user will flag this.
- No docstrings on private functions or inline-explanatory comments in build/transform scripts
- Every comment is a candidate for deletion — if renaming the function/variable eliminates the comment, do that instead

### No Backwards Compatibility Unless Asked

- Default: break anything. User must explicitly say "keep backwards compatibility" if needed
- Avoid speculative compatibility shims — YAGNI

### Simplicity First

- Pure functions. Immutability. Pattern matching
- Monadic side effects where stateful operations compose
- Delete duplicate code, dead code, over‑engineered abstractions
- Less code > more code (if correct and clear)
- **Detect dead variables by tracing assignment to consumption** — a variable that's built (string concatenation, loops) but never assigned to a DOM element or returned is dead. In viz modules, `let leg = ...` patterns that end with `legendEl.innerHTML = ''` instead of `legendEl.innerHTML = leg` are dead code.
- **File names must match display labels** — when a file's numeric prefix or name drifts from its `data-id` or tab label, rename the file. Don't justify the mismatch. User will spot it: "the js is named 05 but our view is 04". See `references/viz-module-anti-patterns.md` for full pattern catalog.

### Testing: Black‑Box Only

- Test by input + expected output
- No tests that depend on implementation details (internal calls, state order, mock invocations)
- Refactoring internals must keep tests green

## Comprehensive Codebase Analysis Methodology

See `references/codebase-analysis-output.md` for a worked example.

When performing deep repo analysis (domain model extraction, pipeline mapping, findings writing), follow this procedure:

### 1. Source Inventory
- Read every source file: viz modules, scripts, schemas, docs
- Note naming/numbering conventions and git history for context
- Document directory structure with file sizes and line counts

### 2. Domain Model Extraction
- Identify **entities**: objects with identity (Model, Creator, Source)
- Identify **value objects**: immutable attributes (Price, ELO, IQ, Archetype)
- Document relationships (Creator 1→N Model, Model N→N Source)
- Note **state semantics**: 3-state model — null ≠ 0 ≠ >0 — and document coverage % per field
- Flag **canonical ID resolution** — always the most brittle area, document every resolver

### 3. Data Pipeline Mapping
- Trace every stage: source → transform → output
- Document input contracts (what shape each stage expects)
- Document output contracts (what shape each stage produces)
- Note side effects (file writes, network fetches)
- Flag manual vs automated steps

### 4. I/O Boundary & Contract Analysis
- Per module: input contract, output contract, side effects
- Which fields may be null (with coverage % per field)
- Defensive handling patterns (filters, empty-state renders)
- Event wiring and lifecycle patterns

### 5. Findings Documentation Structure

Format the output document in this order:

```
1. Repo Structure
2. Domain Model (entities, value objects, canonical ID resolver)
3. Data Pipeline (stages with inputs/outputs/contracts)
4. I/O Boundaries (per-module contracts, null semantics)
5. What Works (architecture wins, code quality, git hygiene)
6. Gaps & Issues (Critical → Performance → Correctness → Maintainability → Architecture → Documentation)
7. Refactoring Targets (prioritized phases with effort/impact)
8. Deferred (conscious non-decisions with rationale)
9. Recommended Next Steps (ordered, 3-5 items)
```

**Framing rules:**
- If a design choice is intentional (no price fallback, zero build, no TypeScript), call it "(By design)" — not a gap. Frame as trade-off, not oversight.
- Multi-source null values are **signals, not bugs**. Document as coverage gaps, not data quality failures.
- "What Works" section must precede "Gaps" — establishes context for trade-offs the codebase is already making correctly.
- Refactoring targets must have effort + impact estimates per row.
- "Deferred" section is mandatory — document what you consciously chose NOT to recommend and why. Prevents re-litigating settled decisions.
- When the user corrects a finding, update the document — then save the lesson in this skill's methodology.

### 6. Contract Testing Priority

When recommending tests, lead with **contract tests at transformation boundaries**. See `testing-strategy` skill for the full paradigm.

---
## Refactoring Sequence: Domain Model First

When refactoring a multi-stage data pipeline (or any system with implicit schema across boundaries), follow this strict sequence:

### 1. Write the Domain Model Before Touching Code

Before any refactoring, produce a formal domain model document covering:
- **Core entities** with attributes, relationships, and cardinalities
- **Pipeline stages** with inputs, outputs, and side effects
- **Invariants** (null semantics, slug uniqueness, field domains)
- **Test surface** recovered from any available source (`.pytest_cache/v/cache/nodeids`, git history, pyc bytecode)
- **Known defects** organized by priority
- **Design decisions** with trade-off tables

This document IS the refactoring blueprint. Without it, you're moving code around without knowing what contracts you're preserving.

### 2. Externalize Inline Data Before Changing Logic

If the pipeline embeds data directly in output files (e.g. `dashboard.html` with inline `PROCESSED_DATA`), **externalize first, verify next, change logic last**:

```
Step 1: Extract inline blob to external file     (dashboard.html → data/processed.js)
Step 2: Diff extracted data against ground truth   (verify zero mismatches)
Step 3: Wire new load path                         (script src= instead of inline)
Step 4: Verify runtime behaviour                   (open page, check rendered output)
Step 5: Only THEN modify build script              (add processed.js to build output)
```

**Why this order:** Steps 1–4 are a pure refactor — data content never changes, only how it's loaded. If anything breaks, the diff from Step 2 tells you it's a loading bug, not a data bug. Step 5 is the only code change, and it's verified by the diff invariant from Step 2.

### 3. Merge One by One (Verify After Each Step)

Do not batch externalization changes. Each extraction+verification cycle is a single commit:
- Extract → diff → wire → verify
- If the diff shows mismatches, STOP. Fix the data reconciliation before wiring.
- Only one artifact per cycle (e.g. `processed.js` in one cycle, `axes.js` in another)

### 4. Common Drift Patterns to Check

When the build script produces different output than what's committed:

**Pipeline state drift** — source data files changed, but committed output was manually curated or built from a different state.

**Committed output is ground truth** — the file in the repo is what the frontend uses — the pipeline must reproduce it.

**Investigation: trace a single field through every layer** — when a filter or field behavior is unclear, trace it from source to output:

```
source → registry (model_registry.json)
       → axes catalog (axes_catalog.json)
       → projection engine (project_axes.py: get_value)
       → build script filter (e.g. aa.intel != None)
       → output (processed.json)
       → frontend (dashboard.html viz code)
```

At each layer ask: "where does this value come from? what resolution path is used? what fallback? what filter gates it?" The answer at the registry layer often reveals naming convention drift (hyphens→dots for versions) or data source gaps that downstream filters can't fix.

**Build-script side-effect pitfall**: a Python build script that writes `processed.json` and `processed.js` overwrites committed production data on every run. Always `git diff` before committing after a build run. If the output changed unexpectedly (different model count, different values), `git checkout -- data/processed.json` to restore, then investigate the drift before rerunning. The committed data is the ground truth — don't let a one-off build overwrite it.

**Action**: fix the pipeline to reproduce the committed output, OR update the committed output if the source changes are intentional.

## Multi-Source Data Integrity

When aggregating pricing/benchmark data from multiple sources:

- **Null is not missing**: null means "this source doesn't provide this field." Different sources have different coverage, definitions, and timestamps. Don't fill nulls from another source.
- **Discrepancies are signal**: if AA says $2/Mtok and OpenRouter says $1.80, that's meaningful — different scrapers, different methodology. Auto-fallback masks this.
- **Source-tagged fields**: each source's data lives under its own namespace. User switches sources to observe differences.
- **No implicit fallback**: never substitute one source's data for another's null. If a viz needs field X and source A has null, show null — user sees it's missing from A, not from all sources.
- **Multi-source switchability is the point**: the architecture supports toggling data origins. That capability IS the feature, not a gap to patch with fallback.

### Coverage Communication Over Derivation

When a source provides a metric (like `cost_per_task`) for only a subset of models, the correct response is to **communicate the gap, not paper over it**:

```
❌ Derive:      compute an approximation from other fields (inp_price, out_price)
→ Mixed scales (AA task ~50M tokens vs our 6K task differ 50k×)
→ Charts show two clusters, confusing to the viewer
→ Source vs derived distinction lost

✅ Communicate: show "28/101 models — requires cost_per_task"
→ User knows it's a coverage gap in the source, not a broken chart
→ Decision to fill the gap is explicit, not accidental
→ Viz stays truthful: what you see IS what AA provides
```

**When approximation IS acceptable:**
- The computation is **exact** (no lossy approximation): `iq_per_1k_pt = intel / cost_per_task * 1000`
- The result is clearly labeled as "derived" vs "sourced"
- Scale consistency is maintained (all models use the same task definition)

**When to communicate instead:**
- The formula requires a tunable parameter (task token count, cache ratio)
- The source's methodology is unknowable (AA's internal task definition)
- Mixing sourced and derived values would create scale discontinuities

**Implementation pattern — coverage note in viz:**

Build a small `renderCoverageNote` helper that returns an HTML string to inline directly into the chart container's `innerHTML`. The first parameter (`container`) exists for API uniformity but is **not used** — the function returns a string, it doesn't touch the DOM:

```javascript
function renderCoverageNote(container, shown, total, missingFields) {
  if (shown === total) return '';
  const pct = Math.round(shown / total * 100);
  return `<div style="font-family:monospace;font-size:11px;color:#888;text-align:center;padding:8px;margin-top:8px;">
    <span style="color:var(--neon2,#6a6);opacity:0.5;">//</span>
    Showing ${shown}/${total} models (${pct}%) — requires
    <span style="color:#999;">${missingFields}</span>
  </div>`;
}
```

Call it by concatenating into the chart's innerHTML assignment — NOT by appending to the DOM afterward:

```javascript
// ✅ Works — coverage note is part of the initial render
container.innerHTML = `<svg viewBox="0 0 ${W} ${H}">${svg}</svg>`
  + window.VIZ_HELPERS.renderCoverageNote(null, pts.length, data.length, 'cost_per_wallsec + intel');
```

**Why inline over append:** Chart containers are frequently replaced via `innerHTML = ...` (lazy rendering, filter re-renders). A DOM append after the assignment can survive or get wiped depending on timing. Inlining guarantees the note is part of the initial render — no race conditions with re-render subscribers or legend clearing.

**Pitfall — parameter name mismatch in viz render functions:** When a viz module's render function uses a non-standard parameter name (`allData` instead of the convention `data`), any code referencing `data` inside the function crashes with `ReferenceError`. Standardize render signatures as `function render(container, data)` across all modules. If a module must use a different name, grep for all `data.` references in that function before deploying.

**Pitfall — shown === total guard:** The `if (shown === total) return '';` early exit prevents the note from appearing when all models pass the filter. This is correct — the note communicates _partial_ coverage. When all models are shown, the note is silent noise. Don't remove this guard thinking it's a bug.

**When data coverage is the bottleneck, no amount of viz cleverness can fix it** — every pipeline debugging path should start with the question "how many models have this field?" before touching chart code.

---

## Data Pipeline & Static Site Architecture

### Static Site Data Storage: Format Trade-Offs

For static dashboards with embedded data (~100K dataset), four storage approaches apply. Present all trade-offs explicitly — each approach eliminates some problems and introduces others:

| Approach | Browser load | Local viewing | Git diff | Build dep | Dependency cost |
|----------|-------------|---------------|----------|-----------|-----------------|
| **Inline `<script>`** (data in HTML) | synchronous, no extra request | ✅ works from `file://` | huge one-time bloated diff | none | zero — data is JS |
| **External `<script src>`** (processed.js) | synchronous, cacheable | ✅ works from `file://` | one-time add, then stable | none (data stays committed) | ~25 bytes wrapper |
| **`fetch()` JSON** | async, HTTP round-trip | ❌ Chrome blocks from `file://` | clean (pure JSON) | none | one HTTP request + JSON.parse |
| **SQLite (sql.js WASM)** | async, WASM init + fetch DB | ❌ breaks local | binary blob — every change rewrites entire file | yes (generate .db) | ~1.7MB (sql.js + WASM) for a 99KB dataset |

**SQLite is wrong for this class of problem**: the dependency cost (1.7MB WASM) exceeds the dataset (99KB) by 17×. Git can't delta-compress binary blobs. The browser needs a WASM runtime just to read data. SQLite's value (transactions, indexes, concurrent writes) applies to zero of the actual workloads in a read-only static dashboard.

**`fetch()` JSON breaks local viewing**: Chrome blocks `fetch()` from `file://` protocol. When the repo lives in an Obsidian vault and the user's primary workflow is opening HTML from disk, any approach requiring a local web server is a regression.

**`<script src>` wins for this use case**: synchronous (no async orchestration), cacheable, works from `file://`, zero deps, git-diffable text. The 25-byte JS wrapper (`window.VAR = ...;`) is the cheapest abstraction in the system.

**When to reconsider**: if the dataset exceeds ~500KB, lazy-loading via `fetch()` + `import()` becomes worth the local-server regression. At 100KB, it's not. If the page needs 10+ data files accessed independently, consider a build-time concatenator — still no runtime framework.

### Null Filtering: `is not None` Is a Data-Loss Risk

User directive: **"we do want null and non-nulls. this shows us data gap that we can expedite later on. so do not overcorrect."** Internalize: nulls are intentional data-gap markers, not errors.

Any pipeline filter of the form `[r for r in raw if r["axes"].get("field") is not None]` is a potential data-loss bug. It silently drops models that have data on OTHER axes but lack this particular one. **Null means "this source doesn't provide this field for this model" — not "this model shouldn't be shown."**

Safer pattern:
```python
# ❌ Dangerous — drops models missing aa.intel, even if they have other AA data
aa_models = [r for r in raw if r["axes"].get("aa.intel") is not None]

# ✅ Better — include models with ANY AA data
aa_models = [r for r in raw if any(
    k.startswith("aa.") and v is not None
    for k, v in r["axes"].items()
)]
```

The dashboard renders nulls as "—", "N/A", or "no data" — that's the correct behaviour. Stripping nulls from the data hides coverage gaps from the user and creates model-count discrepancies between pipeline stages.

**When `is not None` IS correct**: transient computation (e.g., "skip if no cost data for derived IQ metric") — never for inclusion/exclusion of models from the output dataset.

### Pipeline Circular Dependency: The `processed.json` Loop

When `_build_registry.py` reads `processed.json` as an AA data source AND `_build_dashboard_data.py` outputs `processed.json`, the pipeline has a bootstrapped circular dependency:

```
processed.json ──→ _build_registry.py ──→ model_registry.json ──→ projection engine
                      ↑                                                                  ↓
                  (reads previous AA data)                                  _build_dashboard_data.py
                                                                                     ↓
                                                                          processed.json + processed.js
```

The first run needs a seed `processed.json` (committed manually or from a previous pipeline version). After that, each run incorporates the previous run's AA data and produces a potentially richer output.

#### Remediation: Switch to Raw Source, Not Curated Output

See `references/circular-dependency-recovery.md` for a full worked example (LLM Pricing Dashboard pipeline).

The fix: **never feed a pipeline stage from its own downstream output.** Use the raw upstream source instead. In this repo, the raw AA source lives at `data/sources/aa/raw/aa_models_scraped.json`, not the curated `processed.js`:

```python
# ❌ Bad — regenerated output from curated AA data
aa_js = Path(BASE, "data", "processed.js").read_text()           # reads pipeline's own output
aa_data = json.loads(...)
for m in aa_models:                                               # loops over 54 (curated) instead of 99 (raw)
    all_models[cid] = registry_record_from(m)

# ✅ Good — reads raw scraped source, breaks the loop
scraped_path = os.path.join(BASE, "data", "sources", "aa", "raw", "aa_models_scraped.json")
with open(scraped_path) as f:
    scraped_models = json.load(f)
for m in scraped_models:                                         # loops over 99 raw models
    all_models[cid] = registry_record_from(m)
```

**Impact of circular dep:** Any filter that reduces dashboard output cascades. The downstream filter (curated set = models with any AA field) runs on the registry output, but the registry itself was built from the PREVIOUS run's curated set. Tighten the filter → curated set shrinks → next registry build has fewer starting models → curated set stays small. The filter can never recover because it feeds its own inputs.

**Detection:** If model count drops between pipeline runs without code changes, suspect circular dependency. Trace the data source for each stage: is any stage consuming its own output from a previous run?

**Map every data source per stage:**

| Stage | Inputs | Effect |
|-------|--------|--------|
| `_build_registry.py` | `data/sources/aa/raw/aa_models_scraped.json` (raw), other source files | Writes `model_registry.json` |
| `_build_axes.py` | source files | Writes axes_catalog.json |
| `_build_dashboard_data.py` | model_registry.json, axes_catalog.json | Writes processed.js |

If ANY input is also an output of a later stage, you have a circular dependency. The fix is always: **use the raw source, not the curated output.**

#### Cleanest approach when both `processed.json` and `processed.js` exist with same data:
- `processed.js` is what the browser loads — keep it committed, it's the live data
- `processed.json` is consumed by the registry builder — either keep it committed or have `_build_registry.py` parse `processed.js` (strip JS wrapper)
- The build pipeline generates both; only one needs to be committed

**Parsing `processed.js` as JSON in Python:**
```python
# Instead of reading processed.json:
content = Path("data", "processed.js").read_text()
models = json.loads(
    content.removeprefix("window.PROCESSED_DATA = ").removesuffix(";\n")
)
```
This works because the JS file is `window.PROCESSED_DATA = [...]` — the only difference from JSON is the variable assignment wrapper. Works for any `window.NAME = ...;` pattern.

**Recovery pattern after accidental divergence:** `git checkout -- data/processed.json` restores the ground truth. Investigate WHY the pipeline produced a different count before rerunning — don't accept a regression as "the pipeline is correct."

### Multi-Source Directory Structuring

When a data source grows beyond 2 files or has multi-stage enrichment (raw base + overlay + cost segments), extract it to its own directory under `data/sources/` with a dedicated `_build.py` module:

```
data/
  sources/
    aa/                         ← source name
      raw/                      ← primary scraped data (one or more files)
      enriched/                 ← hand-curated or overlay data
      _build.py                 ← get_<source>_models(base) → dict[canonical_id, record]
    other-flat-sources.json     ← single-file sources stay flat in sources/
    more-flat.csv
```

**The `_build.py` returns source records; the registry builder merges them:**

```python
from .sources.aa._build import get_aa_models

all_models = {}
all_models.update(get_aa_models(BASE))
```

**Pattern for enrichment layering (within a source):**

| Order | File | What it provides |
|-------|------|-----------------|
| 1 | `raw/primary.json` | Base entries with basic fields (pricing, speed, intel) |
| 2 | `enriched/overlay.json` | Add models only in overlay + fill-null on overlapping |
| 3 | `enriched/fine_grained.json` | Cost segments, breakdowns (matched by name/canonical ID) |

Each later file enriches but **never overwrites a non-null field** from an earlier file. The base scraped data wins for basic fields; enriched data fills in derived fields (tokens_m, iq, cost segments) where available.

**When to extract vs stay flat:**

| Source complexity | Treatment |
|---|---|
| 1 file, simple shape | Flat in `sources/` (LiveBench CSV, OpenRouter JSON) |
| 1 file but needs pre-processing | Flat in `sources/`, logic in `_build_registry.py` |
| 2+ files, enrichment chain | Own `_build.py` in source directory |

**Never feed a build stage from downstream output** — the `_build.py` reads raw files only. The directory boundary enforces the constraint structurally.

**Duplicate enrichment code paths pitfall** — when adding a new enrichment source to an existing `_build.py`, always check if an equivalent code path already exists. Two different strategies (e.g. fuzzy name matching vs explicit hardcoded name map) for the same data source create confusion: which one wins? Do they overlap? Does one silently skip models the other captures?

Concrete example from a real pipeline: `aa_cost_breakdown.json` was ingested via a **fuzzy substring match** (strip parentheticals, lowercase, hyphenate, then substring test) AND via an **explicit name_map dict** (29 entries). Both ran sequentially against the same JSON, each injecting cost segments into the same model records. The fuzzy match added ~1 extra model (false positive) that the name_map missed. Neither had priority rules — last write wins.

Fix: **pick one strategy per data source.** Prefer explicit maps for known sets (naming is deterministic, no accidental joins). Use fuzzy matching only when the name space is unbounded and manual mapping is infeasible. Never combine both — the extra coverage isn't worth the ambiguity.

### Canonical ID Mapping — Single Source of Truth

When aggregating data from N sources, each source uses its own name for the same
entities (model IDs, API slugs, benchmark names). **Never duplicate the mapping
logic across source-parser modules.**

**Right pattern:**
```
data/
  _canonical.py                    ← one module: all source→canonical mappings
  _build_registry.py               ← imports from _canonical.py
  sources/
    aa/_build.py                   ← imports from _canonical.py
```

**Wrong pattern (caught in audit):**
- `sources/aa/_build.py` has `AA_TO_CANONICAL` + `COSTBD_NAME_MAP` (~70 entries)
- `_build_registry.py` has `arena_id_to_canonical()`, `OR_ID_MAP`, `livebench→canonical`, `openllm→canonical` (~30+ entries)
- ~60% overlap between AA and Arena maps (same `claude-opus-4-8` → `claude-opus-4.8` transformation in both files)
- Adding one model requires updating 2-3 maps in 2 files → drift inevitable

**Structure of `_canonical.py`:**

1. A **master `SLUG_TO_CANONICAL` dict** — union of ALL source-specific maps. Every entry
   from every source lives here exactly once.
2. A **`resolve_from_slug(slug)` function** — checks master dict, returns slug as-is
   if unknown. This is the *only* gateway to canonical resolution.
3. **Per-source pre-processors** that clean up source-specific formatting before resolving:
   - `livebench_name_to_canonical(name)` — strips date suffixes (`-20250805`)
   - `openrouter_id_to_canonical(rid)` — strips `provider/` prefix
   - `openllm_name_to_canonical(name)` — extracts model part from HF path
4. **Reverse maps** when needed (e.g. canonical → OpenRouter API ID for context window)

**Rules:**
- `resolve_from_slug` is the **only function** that checks `SLUG_TO_CANONICAL` — every
  source parser goes through it
- No source-specific map is accessed outside `_canonical.py`
- The master dict is a **union, not a priority chain** — a slug maps to exactly one canonical
- Unknown slugs pass through unchanged — do NOT apply automated transformations (hyphen→dot,
  substring stripping) as fallback — those create false joins
- Per-source pre-processors are additive only: they clean up source formatting, then delegate
  to `resolve_from_slug`
- Reverse maps (canonical → source ID) live in the same module so both directions stay adjacent

### Dead Enum Anti-Pattern

When an enum has many meaningful values, is embedded in the domain model, serialized
to output, and referenced in frontend tooltips — but **no pipeline code ever assigns
a non-default value** — that's a **dead enum**.

**Detection — grep for enum values in an assignment context, not just definition/import:**
```
Archetype.FRONTIER   → searched 12 files, 0 assignments found
Archetype.CHEAP      → searched 12 files, 0 assignments found
...
Archetype.UNCATEGORIZED → the only value ever set (always the default)
```

**Root causes:**
1. The enum was speculative — modeled a future classification that was never implemented,
   but the schema was committed as "ready for it"
2. The classification logic was moved to the frontend (JS computes on the fly) but the
   Python enum stayed in the pipeline, creating a false impression that it's computed
   server-side
3. All source data provides null for this field, and no pipeline stage transforms it

**Fix options (pick one):**
- Delete the enum entirely if no consumer depends on it
- Implement the classification logic (tag provenance: SOURCED if identity/name-based,
  DERIVED if computed from metrics — see "Provenance Typing" section)
- Keep the enum but only in the consuming layer (JS, not Python) if it's purely
  a visualization concern

**Extension — dead *entity* classes (not just enums):** When a whole typed
domain model (`RegistryModel`, `AAPricing`, `CostBreakdownPricing`, …) exists
but is never instantiated, the user's preferred resolution order is:
1. **Wire it as the serializer** if it can wrap the existing dict contract with a
   tolerant adapter (`from_flat(dict) → to_dict()`). Keep dict-typed fields
   (`pricing: Dict[str, Any]`) where the pipeline emits plain dicts — do NOT
   re-type every nested object, that forces a rewrite of all source modules.
   This repurposes dead code into a real validating gate. (See "Typed Serializer
   `to_dict()` Silently Drops Undeclared Fields" for the trap here.)
2. **Delete the genuinely-incompatible subclasses** — typed wrappers whose
   constructor expects `AAPricing`/`CostBreakdownPricing` objects the pipeline
   never produces. They can't be wired without a full source-layer rewrite, earn
   no data, and are dead weight. Remove them; keep only what the adapter uses.
3. **Never leave them "in case"** — a spec-first domain model is good; an
   *unwired* one is a lie and a latent crash landmine.

**Ordering — fix known bugs before structural refactors:** When the user reports
a visible defect (e.g. "the crossover circles have no size data") *and* also asks
for dead-code cleanup, investigate and resolve the bug FIRST. A refactor that
touches the same serializer/data path can mask or compound the bug, and the user
explicitly wants the known issue root-caused before churn proceeds.

**Prevention:**
- Every enum value should have a test proving it's reachable in production output
- Before adding enum values, ask: "who assigns this, and from what data?"
- Tag the field with Provenance — if it's SOURCED but always null, the source doesn't
  provide it; drop it or find a real source

### Archetype Classification (Priority-Ordered Predicates)

When a model must be classified into one of several archetypes based on its
sourced metrics (intel, cost, speed), use a **priority-ordered list of
predicates**. First match wins — this lets you encode precedence (frontier
overrides cheap, even if a model is both).

**Pattern:**

```python
ArchetypePriority = [
    ("frontier", lambda r: r.intel and r.intel.as_primitive() >= 50),
    ("reasoning", lambda r: r.reasoning_tax_pct and r.reasoning_tax_pct.as_primitive() >= 20),
    ("cheap", lambda r: r.cost_per_task and r.cost_per_task.as_primitive() < 0.50
                and r.intel and r.intel.as_primitive() >= 30),
    ("fast", lambda r: r.speed_tps and r.speed_tps.as_primitive() >= 150),
    ("compact", lambda r: r.params_b and r.params_b.as_primitive() > 0
                 and r.params_b.as_primitive() < 30
                 and r.intel and r.intel.as_primitive() >= 30),
]


def classify_archetype(row: ProjectionRow) -> Archetype:
    for name, pred in ArchetypePriority:
        if pred(row):
            return Archetype(name)
    return Archetype.UNCATEGORIZED
```

**Rules:**
- Predicates read only SOURCED fields (intel, cost_per_task, speed_tps, etc.)
- Never DERIVED fields — archetype should be computable from what the source
  actually provides
- Thresholds must be calibrated against real data, not guessed (see "Threshold
  Calibration")
- Placeholder predicates (e.g. REASONING when `reasoning_tax_pct` is always
  null) are acceptable — they document intent, produce zero models, and pass
  silently until data coverage improves
- Tag `archetype` as `Provenance.DERIVED` in FIELD_PROVENANCE since it's
  computed from SOURCED inputs

**Test pattern — distribution is proof of classification:**
```python
def test_archetype_classified(self, processed_js):
    counts = {}
    for m in processed_js:
        a = m.get("archetype", "uncategorized")
        counts[a] = counts.get(a, 0) + 1
    assert "frontier" in counts, "expected frontier models"
    assert counts.get("uncategorized", 0) < len(processed_js)
```

### Radar Normalization in Pipeline (Two-Pass: Composites → Norm)

Radar charts display each axis as a [0, 1] normalized score. When multiple
vizzes or views compute this normalization differently, the normalization
logic belongs in the pipeline — one shared computation, one set of bounds.

**Pattern — two-pass in the build stage:**

```python
# Pass 1: compute raw composites per model
def _radar_raws(row):
    intel_raw = row.intel and row.intel.as_primitive()
    speed_raw = row.speed_tps and row.speed_tps.as_primitive()
    cache_raw = (1 - row.cache_hit_price.as_primitive() / row.inp_price.as_primitive()) \
        if row.cache_hit_price and row.inp_price and row.inp_price.as_primitive() > 0 else None
    cost_raw = 1 / row.cost_per_task.as_primitive() \
        if row.cost_per_task and row.cost_per_task.as_primitive() > 0 else None
    ctx_raw = float(row.context_window.as_primitive()) if row.context_window else None
    return intel_raw, speed_raw, cache_raw, cost_raw, ctx_raw

all_raws = [_radar_raws(r) for r in output]

# Pass 2: compute dataset-wide maxes
maxes = []
for axis_idx in range(5):
    vals = [r[axis_idx] for r in all_raws if r[axis_idx] is not None]
    maxes.append(max(vals) if vals else 1)

# Pass 3: normalize each model
for row, raws in zip(output, all_raws):
    row.radar_intel = (raws[0] / maxes[0]) if raws[0] is not None else None
    row.radar_speed = (raws[1] / maxes[1]) if raws[1] is not None else None
    row.radar_cache_eff = (raws[2] / maxes[2]) if raws[2] is not None else None
    row.radar_cost_eff = (raws[3] / maxes[3]) if raws[3] is not None else None
    row.radar_ctx = (raws[4] / maxes[4]) if raws[4] is not None else None
```

**Why two-pass:** You can't normalize a single row without knowing the max of
all rows. The first pass computes composites, the second pass scales them.

**Viz layer change:** Once norms are in the data, the viz reads them directly:
```javascript
// Before (JS computes composites + normalizes per subset):
const avgCacheEff = ...;  // per-creator composite
const normalized = (v - lo) / (hi - lo);

// After (pipeline norms averaged per creator):
const avgCacheEff = ms.reduce((s, m) => s + (m.radar_cache_eff ?? 0), 0) / ms.length;
// No normalization needed — values are already [0, 1].
```

**Tradeoff:** Dataset-global normalization bounds vs subset-adaptive bounds.
With pipeline norms, a filtered subset always plots against the full dataset's
range — your creator radar stays comparable across filter changes. The cost is
that a subset of uniformly-expensive models will look "flat" on the cost-eff
axis (they're all clustered near zero relative to the cheapest model).

**Field chain for radar scores:**
1. Add 5 `radar_*: float` fields to `ProjectionRow` in `_domain.py`
2. Tag them `Provenance.DERIVED` in FIELD_PROVENANCE
3. Include them in `to_dict()` optional_map
4. Compute in `_build_dashboard_data.py` after all rows are constructed
5. Viz reads them — no JS normalization
6. Update the DERIVED set assertion in tests

### Source-Scoped Dedup Warning

When a source file (especially hand-scraped JSON) may contain duplicate
entries, detect and warn at parse time. A silent overwrite hides data quality
issues.

**Pattern — warn, don't crash:**

```python
with open(scraped_path) as f:
    scraped_models = json.load(f)

seen_slugs = set()
for m in scraped_models:
    slug = m.get("slug")
    if slug and slug in seen_slugs:
        print(f"  ⚠ Duplicate AA slug '{slug}' in aa_models_scraped.json")
    seen_slugs.add(slug)
```

**Rules:**
- Warn only — don't crash. A duplicate might be intentional (same model,
  different variant).
- The second occurrence overwrites the first (dict assignment semantics).
  If the duplicates have different data, the last-wins may not be correct.
- Log the filename so the operator knows where to fix.
- This same pattern works for enriched JSON (dict keys are inherently unique,
  but cross-file duplicate detection between scraped and enriched is normal
  merge behavior).

#### Python Monadic Pipeline Orchestration

For multi-step data transformation pipelines (pull → registry → axes → dashboard), compose steps with the repo's ESTABLISHED `Pipeline` class: `data/_pipeline.Pipeline(ctx).then(name, fn).run()`. **Reuse THIS idiom everywhere — Python inner stages import it; JS ports it. Do NOT invent a second pattern.** `_result` (`ok`/`err`/`fromFn`) stays the *value-level* Result/Either primitive only — never fuse stages with `pipe()`/`do()` (user rejected that) and never hand-roll a `steps` tuple + `for` loop (user called it "ugly"/inconsistent vs `Pipeline`).

```python
from _pipeline import Pipeline
from _result import ok, err

def run(ctx=None):
    pipeline = (Pipeline({"engine": ProjectionEngine(), "js_path": str(BASE / "processed.js")})
        .then("project_rows", lambda c: ok(_project_rows(c["engine"], _PROJECTION_AXES)))
        .then("normalize_radar", lambda c: ok(_normalize_radar_scores(c["project_rows"]) or c["project_rows"]))
        .then("payload", lambda c: ok(_build_payload(c["project_rows"])))
        .then("write_js", lambda c: _write_js(c["js_path"], c["wrapper"])))
    pipeline.run()
    if pipeline.ctx.get("_failed_step"):
        return err(pipeline.ctx["_error"])
    return ok(pipeline.ctx["payload"])
```

Each `then(name, fn)`: `fn(ctx)` returns a `Result` OR a plain value (auto-coerced via `ok()`); the returned value is **unwrapped** and stored at `ctx[name]` (so `ctx[name]` is NEVER a `Result`); on `Err`/thrown exception `run()` sets `ctx["_failed_step"]`+`ctx["_error"]` and short-circuits. The caller checks `ctx.get("_failed_step")`. `Pipeline.run()` wrapping exceptions is **correct error capture**, not "raise for control flow" — expected failures return `Err`, only a genuine bug raises.

**One orchestrator (user directive, repeated):** the repo settled on `Pipeline().then().run()`. A `steps` tuple + manual `for` loop re-implements the same short-circuit and was rejected as "inconsistent." Use `Pipeline` for every stage — top level AND inner `run()`/`build()`. JS mirrors it via `window.Result.Pipeline` in `viz/_result.js`; `_boot.js` orchestrates with the same `.then().run()` shape, render internals untouched. Full recipe, gotchas, and the "output JSONs differ" diagnosis tree live in `references/pipeline-orchestration-and-drift.md`.

**Gotchas (all hit in one session):**
- **Don't double-wrap the terminal value.** `then` unwraps, so `ctx[final]` is the plain value. Return `ok(pipeline.ctx[final])` — NOT `ok(ok(...))`.
- **Unpack tuples at the step, not in ctx.** A step returning `ok((a, b))` stores `(a, b)` as `ctx[name]`; return only what the next step needs (`lambda c: _compute_pairs(...)[0]`).
- **Value-stable verification after refactor.** Rebuild via `build_from_cache()` (function, offline) and compare artifact shas (`git hash-object` vs `git rev-parse HEAD:`); confirm the source cache (`data/sources/*.json`) is NOT rewritten. A "different values" report is often an accidental live pull (CLI arg-gate bug), not a code regression.

**Refactoring pattern — script to module:**

Convert a standalone script to a pipeline-compatible module:

```python
# Before — bare script, runs on import
import json
with open("data.json") as f:
    data = json.load(f)
...

# After — wrapped in run(), safe to import
def run(ctx=None):
    if ctx and ctx.get("root"):
        BASE = Path(ctx["root"])
    else:
        BASE = Path(__file__).resolve().parent.parent  # standalone fallback

    with open(BASE / "data.json") as f:
        data = json.load(f)
    ...
    return {"result_key": summary_value}

if __name__ == "__main__":
    run()
```

**Rules:**

1. Each step's `run()` must be importable without side effects — no module-level file I/O
2. `run()` returns a simple dict with summary metrics — not the full data (files are the boundary)
3. `ctx` is read-only within a step — don't mutate previous results
4. Steps that need a previous step's output accept it via `ctx["step_name"]`
5. Every step handles its own I/O — the pipeline only coordinates execution
6. `if __name__` guard is mandatory for standalone invocation

**Pitfalls:**

- **Module-level file reads** — if a script opens files at module level, importing it triggers the read. Wrap everything below imports in `run()`.
- **`__file__` preservation** — `__file__` resolves correctly inside `run()` when imported (Python sets it at module load time). No need to pass paths explicitly unless the pipeline needs a different root.
- **Return value is metadata, not data** — the pipeline stores return values in ctx for visibility, but the actual data exchange is through files. Don't pass megabytes through ctx dicts.
- **None-creator models** — secondary sources may create models with `null` creator. The pipeline is correct to include them; tests should filter `None` from computed creator sets, not reject the data.
- **Standalone vs pipeline consistency** — `run(ctx)` should produce the same output as standalone. If the pipeline passes different paths via ctx, verify the standalone fallback (`__file__` based) matches.
- **Don't double-wrap a Result.** Wrapping a stage that already returns `Ok/Err` in `from_fn` produces `ok(ok(v))` — `.is_err()` is then always False and the short-circuit never fires. Coerce instead: a duck-typed `_is_result(x)` (`hasattr(x, "is_ok") and hasattr(x, "is_err")`) decides whether to pass the value through or wrap it. Pipeline `run()` does `result = returned if _is_result(returned) else ok(returned)`.
- **CSV vs JSON loader pitfall (concrete, this session).** A generic `_load_json` applied to a `.csv` source (`livebench_2026_01_08.csv` is comma-separated, NOT JSON) raises `JSONDecodeError` — and it surfaces only when a black-box test runs the full `run()` against real sources. Keep `_load_csv` (csv.DictReader) SEPARATE from `_load_json`. A refactor that funnels every file read through `_load_json` silently breaks CSV sources; a black-box `run()` test against the real `data/sources/` tree catches it immediately. If a stage reads both formats, branch by extension or keep two helpers.
- **`Err` vs `Ok(None)` is a semantic boundary, not a style choice.** A reader must return `Err` for an *impossible request* (unknown axis id, unresolvable key) and `Ok(value)` where `value` may be `None` for a *legitimately absent* value (model lacks that axis — a coverage gap). Collapsing both to `None` hides typos as data gaps. `project_axes.get_value` is the reference: `resolve_axis` returns `Ok(key) | Err(unknown)`, `get_value` returns `Ok(value-maybe-None) | Err(unknown)`. This is the same null-semantics discipline as the multi-source rule — unknown ≠ absent.

#### Data Enters at the Source, Not Via Enrichment Steps

When a new field (context window, release date, latency percentile) needs to be added to the model dataset:

**The field must enter at source-fetch time and flow through the canonical stages — not via a standalone enrichment step or ad-hoc script.**

```
# Correct flow:
# 1. _pull_sources.py: fetch context_length from OR API alongside pricing
# 2. _build_registry.py: extract context_length into meta.context_window
#    + data/sources/misc.json → meta fields for non-API models
# 3. _build_dashboard_data.py: read context_window from registry meta
# 4. viz/_domain.js: expose as getter
#
# Wrong — user rejected:
# 1. _enrich_context.py: fetch/process context data separately
# 2. Insert as pipeline step between build_axes and build_dashboard
# 3. _build_dashboard_data.py: read separate enrichment file
```

**Why source-first wins:**
- No circular dependency (enrichment reads registry → needs ordered step)
- No duplicate fetching (OR data is already pulled by `_pull_sources.py`)
- No extra pipeline steps to maintain and order correctly
- All model properties arrive through the same entry point and merge at the same stage
- Adding a new model automatically picks up all source fields — no crosswalk logic to update in two places

**When a source doesn't provide the field:** maintain a static JSON file under `data/sources/` (e.g. `misc.json`) with per-model records. The registry build stage reads this file and applies any known fields without overwriting API-sourced ones. This keeps curated data in a proper source file, not inline in build code.

```json
{
  "qwen3-6-plus": { "context_window": 1000000 },
  "gemini-3-pro": { "context_window": 65536 }
}
```

The reader iterates record keys and applies each field to the model's meta dict — no code changes needed when new fields are added to records:

**When to use a dedicated enrichment module:** Never, per user direction. The correct pattern is always source → registry → dashboard. If the data can't be fetched at pull time, it should still enter the registry build stage (via fallback dict or static file), not as a standalone step.

### Pipeline Audit Methodology

When scaling a data pipeline (more models, more sources, more fields), audit by **tracing one change through every layer**:

```
source ──→ registry ──→ catalog ──→ projection ──→ frontend
```

For each layer ask:
- **Add a model**: how many files change? (name mappings, source parsers, schema definitions)
- **Add a field**: how many files change? (extraction, validation, projection, frontend access)
- **Add a source**: how many files change? (new parser, name canonicalizer, axis definition, projection)

Count the edits. If it's >3, the coupling needs attention *before* scaling.

### Field Propagation Chain (Adding a Field)

When a new field must flow from a source into the dashboard output, it passes through **every** layer of the pipeline. A missing touch at any one layer silently drops the field (it shows as `null`/`undefined` downstream, no error). Trace and patch ALL of these:

```
1. Value object field      → ProjectionRow dataclass (_domain.py)
2. Safe constructor call   → projection in _build_dashboard_data.py (safe_ppm(a.get("aa.x")))
3. Axis in ALL_AXES list   → _build_dashboard_data.py ALL_AXES array (else engine rejects it)
4. Axis in catalog GENERATOR → _build_axes.py axis tuple (NOT axes_catalog.json — see gotcha)
5. to_dict() optional_map  → ProjectionRow.to_dict() optional_map dict (else it's never serialized)
6. Axis resolver path      → project_axes.py get_value (checks benchmarks.aa then pricing.aa)
7. Frontend getter         → viz/_domain.js (ModelRow getter)
```

**GOTCHA — `axes_catalog.json` is REGENERATED, not edited.** `_pipeline build` runs `build_axes` → `_build_axes.py` which rewrites `axes_catalog.json` from the registry on every run. Hand-editing `axes_catalog.json` is **futile** — your change is overwritten on the next build, and the projection engine still won't know the axis (it validates against the catalog). Fix the **generator** (`_build_axes.py` axis tuple) instead. The engine reads `axes_catalog.json`'s `axes[].id`; if the id isn't emitted by the generator, `project()` raises `Axis 'x' not found`.

**GOTCHA — verify the build actually re-ran your edits.** After patching, run a *clean* rebuild (`rm -f axes_catalog.json model_registry.json processed.js && python -m data._pipeline build`) and grep the output for the new field. Stale `.pyc` or a half-built artifact can mask a correct patch. Then count models with the field non-null to confirm propagation.

**Worked example:** `cache_hit_price` was missing from the CACHE EFF radar (every creator showed 0%). Root cause was a 4-layer drop: not in `ProjectionRow`, not in `ALL_AXES`, not emitted by `_build_axes.py` (dead `aa.cache` placeholder instead), not in `to_dict()` `optional_map`. See `references/field-propagation-chain.md` for the full trace.

**Discipline:** after adding a field, grep the final output (`processed.js`) for the field name. If 0 hits, the chain has a gap — do NOT assume the viz is wrong.

### Field Removal Chain (Removing a Field / Axis)

Adding a field flows through ~7 layers (Field Propagation Chain). **Removing** one must
touch the SAME layers in reverse — plus the generator files that regenerate the
catalog/registry, or the field silently re-appears on the next build.

Layers to scrub (every one that mentions the field):

```
1. Value object class + safe constructor   → _domain.py (CostPerWallSec, safe_wallsec)
2. Entity field + to_dict() optional_map    → _domain.py (ProjectionRow)
3. FIELD_PROVENANCE entry                   → _domain.py (drop the tag)
4. Projection call                          → _build_dashboard_data.py (safe_x(a.get(...)))
5. ALL_AXES list                            → _build_dashboard_data.py (else engine rejects)
6. Axis GENERATOR tuple                     → _build_axes.py (NOT axes_catalog.json)
7. Source record emitter                    → sources/aa/_build.py (emits "field": None)
8. Catalog output                           → axes_catalog.json (REGENERATED — re-run build)
9. Registry output                          → model_registry.json (REGENERATED from #7)
10. Viz axis entries / getters              → viz/*.js (01 crossover, _domain.js)
11. HTML script tag + the viz file itself   → dashboard.html + delete viz/NN-*.js
12. Tests referencing the field             → tests/*.py (replace with a removal test)
```

**CRITICAL pitfall — source generator re-injection:** If `sources/aa/_build.py` still
emits `"cost_per_wallsec": None` (steps 4/7), any re-run of the registry build RE-INJECTS
the field into `model_registry.json` → downstream → `processed.js`. The removal "works"
until the next build, then the field is back. **Patch the source emitter FIRST**, then
rebuild clean (`rm -f axes_catalog.json model_registry.json processed.js && python -m data._pipeline build`), then grep the output for 0 hits.

**Removal test pattern** (replaces the derivation-integrity test):
```python
def test_field_removed_entirely(self):
    assert "cost_per_wallsec" not in ProjectionRow.FIELD_PROVENANCE
    raw = (REPO / "data" / "processed.js").read_text().strip()
    raw = raw.removeprefix("window.PROCESSED_DATA = ").removesuffix(";")
    data = json.loads(raw)
    for m in data:
        assert "cost_per_wallsec" not in m
```

**Discipline:** after removal, clean-rebuild and grep `processed.js` for the field name.
If >0 hits, a generator still emits it — find and kill the emitter.

### Typed Serializer `to_dict()` Silently Drops Undeclared Fields

A distinct regression class from "Field Propagation Chain" (which is about axis→output). When a typed entity (e.g. `RegistryModel`/`RegistryModelMeta`) becomes the **serializer** for a pipeline that emits plain dicts, its `to_dict()` only emits **declared fields**. If the upstream dict carries a field the dataclass doesn't declare, that field is **silently dropped for every record** — no error, the value just vanishes downstream.

**Session example — `context_window` 104→0:**
- `_build_registry.py` was changed to write `model_registry.json` via `RegistryModel.from_flat(m).to_dict()`.
- `from_flat` wrapped the flat `meta` dict in `RegistryModelMeta`. But `RegistryModelMeta` had NO `context_window` field.
- `to_dict()` iterated `fields(self.meta)` and skipped everything not declared → `context_window` absent for all 2262 models.
- `processed.js` went from 104 non-null `context_window` to **0**. The crossover viz (bubble size = context window) rendered empty circles. Nobody noticed until the user saw the viz.
- Root cause was **not** the source mapping (OpenRouter `context_length` → `meta.context_window` was correct); it was the serializer's type contract.

**Why this is insidious:** the pipeline builds fine, the registry builds fine, the catalog builds fine — every stage passes because none treats a missing `context_window` as an error. The data is gone by the time it reaches `processed.js`.

**Prevention — guard the serializer contract, not just the axis:**
```python
# After wiring a typed serializer, add a regression test that round-trips a
# real record through it and asserts the field survives + lands in output.
class TestContextWindow:
    def test_axis_in_catalog(self):
        cat = json.loads((REPO / "data" / "axes_catalog.json").read_text())
        assert any(a["id"] == "meta.context_window" for a in cat["axes"])

    def test_context_window_populated_in_output(self, processed_js):
        have = [m for m in processed_js if m.get("context_window") is not None]
        assert len(have) >= 50  # was 104 pre-regression; 0 after; guard catches the drop
```
The `>= 50` threshold is the key: it fails the moment the serializer drops the field again, even though the build "succeeds."

**Discipline when wiring a dead typed model as a serializer:**
1. Add every field the pipeline actually emits to the dataclass BEFORE using it as the writer — don't assume the dataclass already declares everything the dict contains.
2. If the dataclass is stricter than the dict (typed `AAPricing` objects vs the pipeline's plain `pricing` dicts), keep the dataclass's dict-typed fields (`pricing: Dict[str, Any]`) and only type the parts you'll actually validate — full re-typing forces a rewrite of every source module.
3. Guard `to_dict()`'s type coercions: `model_type = ModelType(mt)` re-raises on an unknown enum value for models that legitimately carry it. Compute a safe value once (`try: ModelType(mt) except ValueError: None`) and reuse the variable — don't re-call `ModelType(mt)` in the constructor body.

### `to_dict()` Empty-Section Omission vs Round-Trip Equality

When a `to_dict()` omits empty containers (`if self.pricing:` skips `{}`), a serialized record differs from the input dict at the empty sections. Round-trip equality tests must treat `empty == omitted`:

```python
# ❌ Fails: out omits "pricing" (was {}), input has "pricing": {}
assert out.get("pricing") == m.get("pricing", {})
# ✅ Correct: empty and omitted are equivalent
assert (out.get("pricing") or {}) == (m.get("pricing") or {})
```

This matters most when the serializer both (a) drops undeclared fields AND (b) omits empty sections — a naive round-trip test reports the wrong failure (empty-section mismatch) and hides the real one (dropped field). Test the declared-field presence explicitly (see regression test above) rather than full-dict equality.

### Wrong Displayed Value? Render Is Usually Not the Bug

When the user reports a chart shows implausible values (e.g. "cost per task $72 but the model isn't that expensive"), **verify the render is faithful before touching viz code**:

1. Parse the actual output file (`processed.js` is `window.PROCESSED_DATA = [...]`) into Python.
2. Re-read the exact rendering logic from the viz module (the `fmtRaw` / averaging function) and **simulate it** against the real data — do not eyeball.
3. If the simulated output matches what the user sees, the stored data is wrong → the bug is upstream (pipeline/source), not in the chart.

In the `cost_per_task` case: the radar showed $72.42 because `processed.js` *stored* $72.42 — the enrichment step had set it from a corrupt `enriched.cost` (~15× token inflation), and the authoritative cost-breakdown `total` ($0.02) was blocked by an `if cost_per_task is None` guard. The fix was upstream (make breakdown authoritative), not in the viz. **Root-cause discipline: never patch viz to "fix" a number the data is correctly rendering.**

**Multi-source priority pitfall:** when two sources disagree on one field, the `if target is None` fill-null pattern makes **first-loader-wins** — whichever stage runs first locks the value, silently shadowing a more authoritative later source. If a later, better source should win, invert the guard (`if later_source_value is not None: target = later_source_value`). This is the inverse of the usual null-gap concern: here the danger is a *wrong non-null*, not a missing one.

### Trace Field Origin Before Drop/Fix — "Is It Derived?"

When a field looks corrupt or a user says "drop it," **do not delete or null it on a hunch.** First determine its provenance across the whole pipeline:

1. **Where does it come from?** Grep every stage (`_build.py` source parsers, `_domain.py` value objects, `_build_dashboard_data.py` projection, live API cache). A field with no legitimate source (not in any source file, not in the live API response) is a **decoy** — it lives only in one corrupt enrichment file.
2. **Is it derived or sourced?** Per "Derived Field Placement" above: sourced fields pass through; derived fields are computed at transform time. If the code only *consumes* the field (never computes it), it's sourced — trace the source.
3. **Is it physically possible?** Cross-check against a hard invariant the source can't violate — BUT only an invariant you have *confirmed against the source's definition*. A field that looks "impossible" (e.g. `tokens_m` exceeding `context_window`) may be valid under different semantics (here: `tokens_m` = AA's "Output Tokens per Intelligence Index Task", spanning the whole eval suite, so it legitimately exceeds any single context window). Verify the source definition before declaring a value impossible.
4. **Only then decide:** drop (null) if corrupt with no legit source AND no verified physical bound, OR fix the source path.

This trace is the user's explicit workflow correction — *"i think this might be a derived property. check our rich domains to see how this is derived. if it is at all. perhaps we need tests to guard rail all these."* The instinct "just drop the weird number" skips the diagnosis that reveals a **systemic** corruption (here: `tokens_m` was impossible for 32/32 non-null models, not a one-off).

**Guardrail discipline:** once a corrupt field is identified, add a **guardrail test**, not just a one-line fix. The user explicitly wants guardrails so corrupt data can't silently re-enter.

### Verify the Source Definition BEFORE Writing a Guardrail — Anti-Pattern

A guardrail is only as good as the semantic assumption behind it. **Session failure mode:** a
`tokens_m` guardrail nulled values exceeding `5× context_window`, assuming "tokens per task"
must fit in one context. That assumption was WRONG — `tokens_m` was AA's **"Output Tokens
per Intelligence Index Task"**, which spans the *entire* eval suite (many benchmarks, many
turns), so 300M tokens/task legitimately exceeds any context window. The guardrail nulled all
104 values as "impossible"; the data was valid, the validation rule was the bug. Reverted;
`tokens_m` now only sanity-checked as positive + ≤ 10,000M.

**Rule:** Before nulling/clamping a field as "impossible," confirm its *actual source
definition* (read the provider's methodology page, check if the live API exposes it, trace
which file it came from). A value isn't corrupt just because it violates an assumption you
made about its semantics. If you can't verify a bound, don't invent one — trace origin first.

### Threshold Calibration: Inspect Data Before Hardcoding

When setting classification thresholds (archetype bounds, speed tiers, cost ranges), **do not
guess the numbers upfront.** The user's workflow: write a test with your initial threshold,
run the pipeline, inspect the distribution, then adjust.

**Session example — FRONTIER archetype threshold:**
```
Initial guess:  intel >= 65
Actual range:   4 - 60 (max 60)
Test result:    0 frontier models — assertion failed
Inspect data:  sorted(intels, reverse=True)[:10] = [60, 56, 55, 54, 53, 53, 53, 51, 51, 50]
Calibrated:    intel >= 50  ->  12 models (top ~12%)
```

**Process:**
1. Write the threshold with a plausible-first-guess value
2. Run the pipeline + test -> observe failure distribution
3. Query the actual data range via a quick script (`sorted(vals, reverse=True)[:10]`)
4. Calibrate based on observed percentiles, not arbitrary numbers
5. Update the threshold and re-verify
6. Include a distribution-printing test that documents real coverage per bucket

**Never commit a threshold that was never exercised against real data.** If you don't
know the data's range, you don't know if the threshold is reachable.

### Provenance Typing — SOURCED vs DERIVED (Reusable Guardrail Class)

For any domain model with computed fields, tag every field with where its value originates.
This makes the whole class of derived-field bugs testable by construction.

```python
class Provenance(str, Enum):
    SOURCED = "sourced"   # read from a provider file at source-fetch stage
    DERIVED = "derived"   # computed in-pipeline from SOURCED inputs

@dataclass
class ProjectionRow:
    FIELD_PROVENANCE: ClassVar[Dict[str, Provenance]] = {
        "inp_price": Provenance.SOURCED,
        "tokens_m": Provenance.SOURCED,         # AA "Output Tokens per Intelligence Index Task"
        "iq_per_1k_pt": Provenance.DERIVED,     # intel / cost_per_task * 1000
        "cost_per_iq_pt": Provenance.DERIVED,   # cost_per_task / intel
    }
    # NOTE: a field that LOOKS derivable may be INVALID. `cost_per_wallsec`
    # (cost_per_task * speed / (tokens_m*1e6)) was tagged DERIVED and passed
    # internal integrity tests — but was ~10^6x off AA's real cost-per-wall-second
    # (AA's tokens_m is cumulative eval volume, not per-task; our cost_per_task !=
    # AA's full-eval cost). It was REMOVED, not derived. See "Derivation Validity".
```

**Why:** a DERIVED field must never carry a value computed from a null/corrupt/impossible
SOURCED input. The tag lets one test class guard the whole DERIVED set:

```python
class TestDerivedProperties:
    def test_all_fields_have_provenance(self):
        annotated = set(ProjectionRow.FIELD_PROVENANCE)
        field_names = {f.name for f in ProjectionRow.__dataclass_fields__.values()}
        missing = field_names - annotated - {"meta", "FIELD_PROVENANCE"}
        assert not missing, f"Fields missing provenance tag: {missing}"

    def test_no_derived_value_from_corrupt_input(self, processed_js):
        for m in processed_js:
            cws = m.get("cost_per_wallsec")
            if cws is None:
                continue
            ct, sp, tm = m.get("cost_per_task"), m.get("speed_tps"), m.get("tokens_m")
            assert ct and ct > 0 and sp and sp > 0 and tm is not None
            assert abs(ct * sp / (tm * 1e6) - cws) < 1e-6  # derivation integrity

    def test_derived_iq_fields_consistent(self, processed_js):
        for m in processed_js:
            intel, ct = m.get("intel"), m.get("cost_per_task")
            iq1k, ciq = m.get("iq_per_1k_pt"), m.get("cost_per_iq_pt")
            if intel is not None and ct is not None and ct > 0:
                assert abs(iq1k - intel / ct * 1000) < 1e-1
                assert abs(ciq - ct / intel) < 1e-4
            else:
                assert iq1k is None and ciq is None
```

**Key discipline:** the test asserts *derivation integrity* (recompute matches stored), not
just "the field exists." This catches a corrupt SOURCED input silently flowing into a DERIVED
output — the exact failure mode behind the earlier `cost_per_task` corruption.

**Note on dataclass ClassVar:** a `Dict` field default on a dataclass raises
`ValueError: mutable default` — annotate as `ClassVar[Dict[...]]` so it's excluded from
dataclass field processing.

### Derivation Validity — Verify Against a Known Source Value

Internal consistency is NOT sufficient proof a derived metric is correct. A derivation
can be dimensionally sound, unit-aligned, and pass integrity tests — yet still be
~10⁶× off the real value because a hidden semantic mismatch infects the inputs.

**The `cost_per_wallsec` double-invalidation (worked example):** The formula
`cost_per_task × speed_tps / (tokens_m × 1e6)` was tagged DERIVED and passed
`test_no_derived_value_from_corrupt_input` (recompute matched stored). After fixing a
unit bug (tokens_m was millions, not thousands), it was STILL wrong:

| model | derived $/s | AA real $/s | error |
|-------|-------------|-------------|-------|
| Sonnet 5 | $5.96e-7 | ~$8.35 | 14,000,000× |
| Fable 5 | $4.70e-3 | ~$6.95 | 1,500× |

Two independent errors, neither caught by internal checks:
1. **Denominator** — `tokens_m` (300M) is AA's *cumulative* Intelligence-Index token
   volume (sum across all eval samples). AA's "Time per Task" uses a *per-task* token
   count (~thousands) ÷ speed. Dividing by 300M → ~1000× too slow.
2. **Numerator** — our `cost_per_task` ($2.29 Sonnet) ≠ AA's full-eval cost ($4010).
   Our value is per-sample/promo; AA's is the whole run → another ~1000×.

**Rule — ballpark-test every new derivation against a source-verified value:**
- Before trusting a derived metric, fetch the provider's *real published* value for 1-2
  models (their website, API, or methodology page).
- Compute your derived value for those same models.
- If the ratio exceeds ~100× (2 orders of magnitude), the derivation is INVALID even if
  internally consistent. Do NOT ship it — remove it or source the real input.
- This is the user's explicit workflow: "can we get somewhere in the ballpark estimate of
  the real cost (source) value... if not, we have a double invalidation."

**Why internal integrity tests don't catch this:** `test_no_derived_value_from_corrupt_input`
recomputes `ct*sp/(tm*1e6)` and confirms it equals the stored `cws`. That proves the
*formula was applied* — not that the *formula is right*. The wrong relationship lives in
course of a recomputation check.

### Invalid Derivation → Delete the Axis, Don't Disable It

When a derivation is found **INVALID** (ballpark test shows ~10⁶× error vs a source-verified
value, OR the required input isn't available from any programmatic source), the user's
directive is to **remove the entire axis**, not leave a disabled/empty-state placeholder:

> "ok in that case we remove this entire axis, all the way. so our speed-adjusted cost
> graph will go away as well. less headache. along with anything else that mentions it."

Rationale: a disabled viz is dead code that still must be maintained, and a hollow axis
misleads viewers into thinking the metric exists. Scrub **every** layer (see "Field Removal
Chain"): value object + safe constructor + `ProjectionRow` field + `FIELD_PROVENANCE` +
projection call + `ALL_AXES` + axis generator tuple + source emitter + generated
catalog/registry + viz axis entry + HTML script tag + the viz file + tests. The CRITICAL
pitfall: if `sources/aa/_build.py` (or any source emitter) still emits the field as `None`,
a rebuild **re-injects** it into `model_registry.json` → `processed.js`. Patch the emitter
FIRST, then clean-rebuild and grep output for 0 hits.

**Distinction that governs the choice:**
- *Coverage gap* (source exists, partial coverage) → **communicate** via coverage note, keep the axis.
- *Invalid / un-sourceable derivation* (can't be sourced, formula broken) → **delete entirely**.

This is the user's explicit "less headache" preference — embed it so future sessions start
correct, not with a disabled placeholder that has to be cleaned up later.

### Radar Axis Must Be a Directional-Quality Signal — No Inverted-Volume Misnomers

A separate failure mode from invalid derivations: a real, sourced value can still be
**wrong as a radar axis** if you have to *invert* it to force a "higher = better" direction.

**The TOKEN EFF removal (worked example):** `tokens_m` (AA "Output Tokens per Intelligence
Index Task", e.g. 94M for Alibaba) is valid, sourced data. The radar showed
`tokenEff = 1 / avgTokens` labeled "TOKEN EFF", framing *fewer* tokens as *more efficient*.
That's a **misnomer** — the metric is **verbosity** (cumulative eval-token volume), not
efficiency. Inverting `1/tokens` to fake a directional signal breaks the radar's invariant
that every spoke means "more = better" (IQ, speed, cache%, cost-eff, ctx all do). A verbose
model then gets a *big* spoke implying "good," which misleads.

**Rule — a radar axis must satisfy BOTH:**
1. The data is valid and sourced (not a broken derivation).
2. The axis direction is semantically honest — "more = better" without arithmetic inversion.

If you find yourself writing `metric = 1 / real_value` to get the radar direction right,
**stop**. That's a smell. Either:
- **Relabel without inversion** (e.g. "VERBOSITY (M tok/task)" shown as the raw volume, not
  as an efficiency) — but then it breaks the radar's uniform direction, so it doesn't belong
  on a quality-positioning radar; OR
- **Remove the axis** from the radar (keep the raw field in the data table / size axis where
  direction doesn't matter). The user's call here: "this might be a misnomer and just remove
  it (archetype graphs)."

**Detection:** grep the radar builder for `1 /` or `1/` on a volume field. Any inversion of a
volume into a "per-" efficiency on a quality radar is a candidate misnomer. Same removal
discipline as a deleted axis (scrub `_shared.js` `RADAR_AXES` + the viz `values` array +
`fmtRaw`/`fmtMax` cases + coverage note). Add a lock-in test asserting the axis key is absent
and the remaining axes equal the expected set.

### Physical-Impossibility Guardrail (ONLY with verified bounds)

For any field with a physical bound you have **confirmed against the source definition**,
validate at the transform boundary and null violations. Example — a field that truly cannot
exceed a context window (e.g. tokens in a single completion):

```python
# ONLY after confirming the field means "tokens in ONE context"
if row.single_ctx_tokens is not None and ctx:
    if row.single_ctx_tokens.as_primitive() > ctx:
        row.single_ctx_tokens = None
```

**Why null, not clamp:** clamping invents a plausible-but-false value; nulling preserves the
gap as signal. **But** — only apply this when the bound is *verified*. If you're unsure of the
field's semantics, do NOT guess a bound; trace its origin first (see above).

**Secondary blast radius:** a nulled field may feed *derived* fields. If
`cost_per_wallsec = cost_per_task × speed / (tokens_m × 1e6)` and `tokens_m` is nulled,
`cost_per_wallsec` derivation is skipped → it also becomes null (correctly, since it was
built on garbage). Audit every consumer of the nulled field (grep the field name across viz +
pipeline) so dependent views don't NaN-crash — add NaN guards (`isFinite()` in JS radius
scales) or switch their default to a field with real data.

### Build-Time Decomposition

For static data dashboards that must remain zero-runtime-dependency:

```
Current: one inline JSON blob → all viz parse the same array
Better:  build-time split → per-viz JS files, each viz loads only its fields + models
```

| Approach | Build | Runtime | Cache | Offline |
|----------|-------|---------|-------|---------|
| Inline all | none | all data in memory always | HTML uncacheable | ✅ |
| Per-viz chunks | one split script | only whata viz needs | per-file cached | ✅ |
| Lazy fetch | none | async, pay-as-you-go | per-file cached | partial |

**Principle**: Split at build time, keep runtime simple. A build script that runs once on push is invisible to users. An async loading framework in the browser is visible forever.

### Shape Contract Pattern (Pipeline I/O Schema)

When a pipeline has multiple stages and the output shape is defined by a hardcoded mapping (e.g. a 53-field dict in the build script), document the **explicit contract at each boundary** before refactoring:

```
Input  (model_registry.json):  { id, name, creator, pricing: { aa: {...}, openrouter: {...} }, benchmarks: {...} }
Schema (axes_catalog.json):    47 axes, 6 source groups, each with id, source, type, unit, path
Transform (projection engine):  model + axis_id → value, per model → flat row of N axis values  
Output (processed.js):          [{ slug, name, creator, intel, inp_price, out_price, ..., 44 total fields }]
```

**A well-defined shape contract lets you:**
- Replace hardcoded field mappings with a data-driven schema (e.g. iterating over `ALL_AXES` instead of manually mapping each field)
- Verify at each stage that N models in = N models out
- Spot drift immediately (new axis added to catalog but not to output = gap, not magic)
- Reorder/rename output fields without touching transform logic

**Implementation pattern — the `ALL_AXES` list IS the contract:**
```python
# In _build_dashboard_data.py — enumerates every output field and its source
ALL_AXES = [
    ("slug",                    "model.slug"),
    ("name",                    "model.name"),
    ("creator",                 "model.creator"),
    ("intel",                   "axes.aa.intel"),
    ("inp_price",               "axes.aa.inp_price_cost"),
    ("cost_per_task",           "axes.aa.cost_per_task"),
    # ... 38 total
]
# Then iterate, don't hardcode:
result = {}
for out_key, source_path in ALL_AXES:
    segment, field = source_path.split(".")
    if segment == "model":
        result[out_key] = model.get(field)
    elif segment == "axes":
        result[out_key] = projected.get(field)
```

**When the contract is implicit (hardcoded), a future session has to:**
- Read the entire build script to understand the output shape
- Manually cross-reference each field against the axis catalog
- Guess which fields are derived vs sourced vs dropped

**When the contract is explicit, a future session can:**
- Read `ALL_AXES` to know the exact output shape in 30 seconds
- Add a new axis by adding one tuple to the list
- Verify coverage by comparing the list against the axis catalog

This pattern was developed while refactoring an 85-model dashboard pipeline where a 53-field hardcoded `MODEL_FIELDS` dict was the only documentation of the output shape.

### Derived Field Placement: Transform Time vs Domain Model

When a data pipeline produces typed domain objects then serializes them for frontend consumption, some fields are **sourced directly** from upstream data and others are **computed from existing fields**. The question: where in the pipeline does each computation belong?

**Principle:**

| Computation type | Belongs in | Example |
|---|---|---|
| Pure ratio/format of fields already in the domain object | Domain model `compute_derived()` | `iq_per_1k_pt = intel / cost_per_task * 1000` |
| Aggregation of multiple source fields into a new metric | Transform time (build stage that creates domain objects) | `cost_per_wallsec = cost_per_task × speed_tps / (tokens_m × 1e6)` |
| Source-provided field, possibly null | Pass through from projection, no computation | `inp_price`, `intel` |

**Why transform time for composed metrics:**
- The build stage has the full projection context — all axis values resolved, registry available, source overlap visible.
- Domain model's `compute_derived()` is for computational convenience (formatting, unit conversion), not for generating new data from source fields.
- A derived metric that can be null should stay null in the source — compute it intentionally at transform stage where field relationships are explicit.

**Pattern — transform time computation:**

```python
# In _build_dashboard_data.py — after domain object construction
row.compute_derived()

# Derived from two source fields — transform time, not domain model.
# cost_per_iq_pt is a VALID derivation (cost_per_task / intel) — kept in the pipeline.
# (cost_per_wallsec = cost_per_task * speed / (tokens_m*1e6) was ALSO computed here
#  transform-time, but was DELETED — ballpark test showed ~10^6x off AA's real value.
#  See "Derivation Validity". Placement was never the problem; the formula was.)
if row.cost_per_iq_pt is None:
    ct = row.cost_per_task.as_primitive() if row.cost_per_task else None
    intel = row.intel.as_primitive() if row.intel else None
    if ct is not None and ct > 0 and intel is not None and intel > 0:
        row.cost_per_iq_pt = safe_cost_per_iq(ct / intel)

output.append(row)
```

**Why not in `compute_derived()`:** Mixes two concerns — formatting existing data vs generating new data. Transform time keeps the domain model pure (transforms only what's already there).

**Why not in viz:** Compute once in pipeline, not re-derive in every chart. Keeps viz layer data-driven and formula-free.

**When to break the rule:** if the derivation is chart-specific (custom normalization, viz-only aggregation), compute in the viz.

**Corollary — when NOT to derive:** If the derivation requires a tunable parameter (task token count, cache hit ratio) that creates a fundamentally different metric on a different scale, DON'T. Communicate the coverage gap instead. See "Coverage Communication Over Derivation" above.

**Corollary — even a valid derivation can be wrong:** Internal consistency (recompute
matches stored) does NOT prove the *formula* is correct. `cost_per_wallsec =
cost_per_task × speed / (tokens_m × 1e6)` passed integrity checks yet was ~10⁶× off
AA's real value (cumulative-token vs per-task mismatch + per-sample vs full-eval cost).
Always ballpark-test a new derivation against a source-verified value. See "Derivation
Validity" above.

### Debugging Blank Charts (No Visible Data)

When a chart renders axes/grid lines but no data points, follow this sequence rather than jumping to assumptions:

**Step 1: Check the data pipeline first**
```
Does the field exist in processed.js for any model?
→ python -c "import json; ...; sum(1 for m in models if m.get('field') is not None)"
```
If 0 models have the field, the pipeline is dropping it (transform gap, not viz issue).

**Step 2: Check viz filter logic**
```
Which models pass the filter?
→ Compare pts.length (filtered) vs data.length (total)
→ Is the filter too narrow? Are filters compounded (A AND B AND C)?
```
Most blank charts are caused by `pts.length === 0` triggering the empty state OR `pts.length > 0` but none visible.

**Step 3: Check axis ranges**
```
Are the data values within the chart's axis range?
→ Hardcoded ranges (min=5e-9, max=1e-5) vs actual data (3e-5 to 0.005)
→ Points plot off-screen if values exceed the viewBox/viewport
```
The chart may render axes and grid lines from hardcoded constants that fit old data, but actual data values exceed max — points exist in the DOM but outside the SVG viewBox. The empty state never fires because `pts.length > 0`.

**Step 4: Check empty state triggers**
```
Does the empty state fire on pts.length === 0?
Does the chart library silently succeed with empty data instead of throwing?
```
Some chart libraries (Chart.js, raw SVG) render a blank canvas without throwing when data is empty — this bypasses try/catch empty-state handlers that assume a throw.

**Step 5: Fix the root cause, not the symptom**
```
- Data gap → fix pipeline (add transform) OR communicate coverage (add note)
- Off-screen points → computed axis ranges from data, not hardcoded
- Filter too narrow → relax filter or communicate why
- Empty state bypassed → check for pts.length === 0, not try/catch
```

**Proactive measure — dynamic axis ranges:**

Instead of hardcoding axis extents, compute them from the data:

```javascript
// ❌ Brittle — breaks if data scale changes
const minWallSec = 5e-9, maxWallSec = 1e-5;

// ✅ Data-driven — adapts to any input
const vals = pts.map(m => m.cost_per_wallsec);
const minWallSec = Math.pow(10, Math.floor(Math.log10(Math.min(...vals))));
const maxWallSec = Math.pow(10, Math.ceil(Math.log10(Math.max(...vals))));
const wallSecTicks = [];
for (let p = Math.log10(minWallSec); p <= Math.log10(maxWallSec); p += 1) {
    wallSecTicks.push(Math.pow(10, p));
}
```

**Pitfall — reference lines outside data range:** Hardcoded threshold lines (`$0.000001/sec`) become invisible noise when data scale shifts. Either compute dynamically (e.g., median or quartile as reference) or remove.

### Trade-Off Table Format

Every approach pushes complexity somewhere else. Present decisions as a table that maps **what's gained vs what's introduced**:

```md
| Approach | Benefit | New Complexity | Effort |
|----------|---------|----------------|--------|
| Option A | fast queries | needs build step | Medium |
| Option B | zero build | O(n) runtime filters | Low |
```

Never present a solution as "solves X" without also saying "but now Y is harder." The user makes better decisions when both sides are visible.

### Data Gap Audit

After data ingestion, the user asks: "what's still missing, and what can we derive vs what needs new sources?" Run a 3-part audit:

**1. Field coverage matrix** — for each field, count models with non-null values:
```
intel            83/85 (98%)   AA scrape
inp_price        54/85 (64%)   AA scrape
cost_per_task    26/85 (31%)   old data only
livebench        23/85 (27%)   LiveBench
```

**2. Derivable from existing data** — pure computations that don't need a fetch:
- `iq_per_mtok = intel / tokens_m` (just division)
- `cache_discount_pct = 1 - cache_hit_price / inp_price`
- `cost_per_iq_pt = cost_per_task / intel`
- `archetype = f(intel, price_tier)` (rule-based)

These are the **easy wins** — implement as lazy functions in the domain model so they're auto-invoked when source data is null. User phrasing: "if some of those values are derived from already existing properties we have, and if those properties are currently missing and *can* be fetched."

**3. Needs new sources** — for fields with low coverage, identify what would fill them:
- Cost segments (input/cached/answer/reasoning) → AA cost breakdown chart (color-coded, no labels — needs vision/OCR or hand-mapping)
- Cache hit rate (observed) → **NOT auto-ingestible.** OpenRouter API exposes only cache *pricing* (`input_cache_read`), never a hit *rate*. Dirac.run (a real coding-agent product) displays live cache-hit rates **inside its product UI only** — no export/API. Ingestion requires a hand-maintained JSON + canonical map, same as any manual source. Don't phrase this as "pull from Dirac.run" — it's "paste observed numbers into `misc.json`-style file."
- LiveBench / Arena → re-run `_pull_sources.py` to refresh from leaderboards

**Output format** — a single markdown doc with three sections (Coverage, Derivable, Needs Source), explicit lists of which models are missing what. Future sessions know exactly what's still incomplete. Don't promise filling gaps that don't have a source; just enumerate them.

### Documentation-vs-Reality Cross-Check (Audit Must Disprove Claims)

When auditing a pipeline, the user's own docs (README, ARCHITECTURE-*, methodology
notes) are **not ground truth** — they drift after the code moves. Treat every doc
claim as a hypothesis and disprove it against code + actual API endpoints before
reporting "all good." Six false-claim classes to actively check (full checklist in
`references/pipeline-audit-checklist.md`):

1. **Phantom data sources.** A doc claims data from a source (e.g. "observed cache
   hit rates from Dirac.run") that no code references. `grep -rE 'dirac|CACHE_HIT_RATES|cache_hit_rate' data/`
   → 0 hits = never implemented. The external product may be real but expose **no
   API** for the claimed metric, so the feature cannot exist without manual
   ingestion. Either build it (manual JSON + canonical map) or strike the claim from
   the doc. Don't leave a phantom source in the methodology.

2. **Axis-id ↔ registry-field name drift → permanently-null axis.** The axis catalog
   generator asks the registry for `benchmarks.aa.iq_per_dollar`, but the registry field
   is named `iq_per_dollar_pt`. They never match → axis is 0/N forever, silently — it
   looks like a coverage gap but is a naming bug. After any build, `grep` the final
   artifact for each axis id; 0 non-null hits on a claimed axis = name mismatch, not a
   missing source. (Variant of Field Propagation Chain — "generator asks for a key the
   registry never emits.") Distinguish from a genuinely-unavailable field by grepping
   the registry field name directly.

3. **Dead/unused rich domain classes.** A typed domain model (`RegistryModel`,
   `AAPricing`, `CostBreakdownPricing`, …) may exist but be **never instantiated** — the
   pipeline serializes raw dicts and the projection engine consumes dicts. These classes
   are latent crash landmines (e.g. `to_dict()` calls `.as_primitive()` on a `None`-
   defaulted field) and dead weight. `grep` for each class name's usage; zero
   references = delete it or wire it. A spec-first domain model is good; an *unwired*
   one is a lie.

4. **Orphaned committed files.** A committed snapshot (`aa_api_live.json`) that the code
   re-fetches live each run and never reads → false signal of offline fidelity.
   `grep -rl '<filename>' data/` → no code references = orphan. Wire it as the offline
   cache (read-if-no-key) or delete it. Same for manual progress/tracking lists the
   pipeline never consumes.

5. **Built-but-dropped artifact block.** A build script constructs `payload["meta"]`
   (model_count, version, generated date) then serializes a *different* object
   (`wrapper`) that omits `meta`. The artifact ships with no self-describing
   count/version. Verify the serialized file contains every field the doc claims — parse
   it and assert keys, don't trust the build's intermediate variable.

6. **Stale doc counts/structure.** Doc says "85 models / single-file inline HTML" but the
   artifact is 104 models / external `processed.js`. Recompute every count from the actual
   artifact before trusting the doc. Numbers in prose rot; the committed JSON is current.

Audit output ordering: What Works (by-design, keep) → Critical → Correctness →
Maintainability/Dead code → Docs → Refactoring table (Effort×Impact) → Deferred
(conscious non-decisions). Frame each user-enforced design choice as "(By design)" —
not a gap.

### "Flies First, Scale Later"

If the current approach performs well, **don't add infrastructure until it stops flying**. Signals to wait:
- Page load >200ms or data load >500ms after adding content
- Viz code duplication across 5+ views (not 2-3)
- Hard-to-debug bugs (undefined field access, stale pipeline artifacts)
- User says "this feels great" — trust that. Don't pre-optimize.

When you do need to scale, prefer:
1. Build-time changes (invisible to users)
2. Thin helper layers (one file, no framework)
3. Only then: runtime architecture (lazy loading, SQLite, etc.)

**Concrete example**: TypeScript and SQLite were suggested for a static dashboard with99 models. User rejected both — TypeScript adds a build step (tsc + bundler) to a page that "opens from disk and flies"; SQLite adds a binary to git or requires rebuild-on-deploy. Both solve problems that don't exist yet at this scale. The correct path: keep vanilla JS, keep JSON, fix the3 actual problems (pipeline order, name normalization, field coverage).

## Mapping Paradigm Seam

The domain model (FP style — records, DUs, immutability) meets persistence (OOP style — change tracker, mutable DTOs) at an explicit boundary:

```
Domain Model (FP)    ↔    Persistence (OOP/EF Core)
records, DUs,              change tracker,
immutable,                 mutable DTOs,
pattern matching           table mappings

        ↕ mapping layer ↕
   Cost paid here. Tests guardrail.
```

Neither side wins. You keep them separate, pay the mapping cost, test the boundary. If persistence dictates domain shape, you've lost.

## Verification

- [ ] Invalid states are unrepresentable in types
- [ ] No exceptions used for control flow (Result/Either instead)
- [ ] Comments explain *why*, not *what*
- [ ] No speculative backward compatibility
- [ ] No dead code or over‑engineered abstractions
- [ ] Tests verify behavior by input/output, not internal calls
