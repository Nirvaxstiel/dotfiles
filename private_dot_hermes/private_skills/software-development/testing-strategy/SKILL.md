---
name: testing-strategy
description: "Domain-oriented testing strategy — integration flows, black-box I/O parameterisation, and unit-level business logic verification. Complements upstream TDD skill."
version: 2.1.0
author: Kei
license: MIT
metadata:
  hermes:
    tags: [testing, integration-tests, black-box, unit-tests, domain-modeling]
    related_skills: [architecture-principles, csharp-domain-modeling]
---

# Testing Strategy

## Overview

Four paradigms for testing domain-driven systems. They work together: integration tests validate the full machine, black-box I/O tests catch regressions when requirements shift, unit tests lock down business logic internals, and contract tests guard data pipeline transformation boundaries.

All three depend on good domain modeling. If invalid states are representable, every test becomes more complex and less reliable.

## When to Use

- Adding tests to a domain-oriented .NET codebase
- Writing new features or modifying business logic
- Setting up the project's test suite
- Reviewing test coverage and quality

## Prerequisites

These three paradigms deliver value only when the domain model is well-structured:

- **Domain modeling** — rich types, aggregates, value objects
- **Architecture design** — clear boundaries, explicit seams, dependency inversion
- **State safety** — invalid states unrepresentable, failures encoded in types (Result/Either), not exceptions

> "If I can read the domain model and understand what the business does, I've won. If I need to read the DB schema, I've lost."

### Monadic Functional Style

Business logic composed as functional pipelines — each step transforms input, returns a Result, and feeds into the next. This narrows the pipe, making every stage independently testable:

```csharp
// Pipeline — each stage is a pure function or monadic bind
var result = await ValidateOrder(request)
    .Bind(order => ApplyPricing(order, catalog))
    .Bind(order => CheckInventory(order, warehouse))
    .Bind(order => PersistOrder(order, db))
    .Match(
        success: ok => Ok(ok),
        failure: errors => BadRequest(errors)
    );
```

Advantages for testing:
- Each stage has a single responsibility — tests focus on one thing
- Pipeline composition is declarative — add/remove/reorder stages without rewriting tests
- Failure paths are first-class — every `.Bind` can short-circuit

### Domain ↔ Transactional Mapping

The seam between functional domain and OOP persistence is explicit:

```
Domain Model (FP)          ↔          Persistence (OOP)
records, DUs,                         change tracker,
immutable values,                     mutable DTOs,
pattern matching                      table columns

           ↕ explicit mapping layer ↕
      (guardrail tests here)
```

Define a mapping contract before writing any mapper:

1. **Read contract** — what shape from DB? Columns → domain types? Null defaults?
2. **Write strategy** — full replace? Diff? Append only?
3. **Boundary pitfalls** — null handling, missing columns, version conflicts

Write mapping guardrail tests that assert every field maps correctly. When a new field is added to the domain model, the mapper test fails until the transactional DTO is updated — no silent drift.

**The pattern:** Each event version or domain type gets a test that asserts the full mapping shape. If a new field is added to the domain record but the mapper/transactional DTO isn't updated, the test fails at compile or assert time — not in production.

```csharp
[Fact]
void OrderPlaced_v2_maps_all_fields()
{
    var orderPlaced = new OrderPlaced_v2(
        OrderId: new(Guid.NewGuid()),
        CustomerId: new(Guid.NewGuid()),
        Lines: ImmutableList.Create(
            new OrderLine_v2(ProductId: new(Guid.NewGuid()), Qty: 1, Price: 49.99m)),
        ShippedAt: null,
        Source: "web"
    );

    var row = OrderMapper.ToRow(orderPlaced);

    Assert.Equal(orderPlaced.OrderId.Value, row.Id);
    Assert.Equal(orderPlaced.CustomerId.Value, row.CustomerId);
    Assert.Equal(orderPlaced.Lines.Count, row.Lines.Count);
    Assert.Equal(orderPlaced.Source, row.Source);  // ← test catches if this is missing
}

[Fact]
void OrderPlaced_v1_still_maps()
{
    // Backward compat — v1 has no Source field
    var v1Event = CreateV1Event();
    var row = OrderMapper.ToRow(v1Event);
    Assert.Null(row.Source);  // ← default for old events
}
```

**Why this works:**
- New field added to `OrderPlaced_v2` record → test for `v2` must be updated → explicit, not silent
- Removes the "I forgot to update the transactional model" class of bugs
- Each event version gets its own test, so backward compat is explicit
- Refactoring the mapper (e.g. changing column naming) is safe if tests pass

**When to use:** Monolith with two-model mapping, event-sourced systems, any boundary where domain shape and persistence shape diverge.

**Don't overdo:** Not needed for simple CRUD where domain model ≈ table shape.

## The Four Paradigms

### 1. Integration Tests

Full-flow tests that exercise the real stack (domain → persistence → query). Validate that components wire up correctly and the system works end-to-end.

**Characteristics:**
- Use real database (test container or in-memory with caution)
- Cover happy paths through aggregate boundaries
- Test that the mapping layer materializes and persists correctly
- Few in number (1-3 per aggregate) — they're slow, so be selective

**Example:**
```csharp
[Fact]
async Task place_order_flow_persists_and_retrieves()
{
    // Arrange — build a real domain order
    var order = new Order(OrderId.New(), CustomerId.New());
    order.AddLine(productId, price, qty);

    // Act — persist via real DbContext, then re-query
    db.Orders.Add(order);
    await db.SaveChangesAsync();
    var loaded = await db.Orders.FindAsync(order.Id);

    // Assert — domain shape survived the round trip
    Assert.NotNull(loaded);
    Assert.Equal(order.Total, loaded.Total);
}
```

### 2. Black-Box I/O Tests

Configure input parameters, inject into the test subject, assert different outputs for different parameter combinations. The test knows nothing about internals — only contract.

**Characteristics:**
- Single assertion per test case
- Parameterized (xUnit `[Theory]`, NUnit `[TestCase]`)
- Failure tells you *which input combination* broke — easy to diagnose when requirements change
- Covers boundary cases, edge cases, error paths

**Example:**
```csharp
[Theory]
[InlineData(100, "USD", 50, "USD", 150)]   // same currency
[InlineData(100, "USD", 50, "EUR", null)]    // currency mismatch
[InlineData(-10, "USD", 50, "USD", null)]    // negative amount
void price_engine_computes_total(
    decimal p1, string c1, decimal p2, string c2, decimal? expected)
{
    var line1 = new OrderLine(ProductId.New(), p1, new Currency(c1));
    var line2 = new OrderLine(ProductId.New(), p2, new Currency(c2));
    var order = new Order(OrderId.New(), CustomerId.New())
        .WithLines([line1, line2]);

    var result = PricingEngine.ComputeTotal(order);

    Assert.Equal(expected, result.IsSuccess ? result.Value : null);
}
```

When a new requirement comes in (e.g. loyalty discount), you add one `[InlineData]` row. If it breaks, you know exactly which input combo failed.

### 3. Unit Tests

Test specific stages of the business logic pipeline. Assert on internal checkpoints — but only through the pipeline's public API, never by reaching into private state.

**Characteristics:**
- Test one transformation per test
- Mock only the boundary (I/O, external services), not domain internals
- Feed a known input, assert the pipeline output

**Example:**
```csharp
[Fact]
void discount_applied_when_customer_is_premium()
{
    // Pipeline: Validate → ApplyDiscount → CalculateTotal
    var order = new OrderBuilder()
        .WithCustomer(Customer.Premium())
        .WithLine(productId, 100m)
        .Build();

    var result = await PricingPipeline.Run(order, _catalog);

    Assert.True(result.IsSuccess);
    Assert.Equal(90m, result.Value.Total); // 10% premium discount
}
```

### 4. Contract Tests at Data Transformation Boundaries

For data pipelines that ingest raw scraped/external data and transform it into a canonical domain model. This paradigm is distinct from the other three — it tests **structural invariants** and **mapping completeness**, not behavioral logic.

**When to use:**
- Pipeline has multiple stages (scrape → normalize → enrich → project → serialize)
- Model identity changes across stages (slug normalization, ID resolution)
- Schema is implicit (bare dicts, JSON objects, no type system)
- A missed mapping silently drops data without error

**What to test:**
- **Canonical ID resolution**: every source ID (AA hyphens, Arena names, OR provider/name) maps to exactly one canonical ID. No collisions, no orphans.
- **Coverage invariant**: if N models go in, does N come out? Assert the known count at each boundary.
- **Schema mapping drift**: fields listed in one place (e.g., `ALL_AXES` list) must match fields mapped in output dict. Keep them in sync.
- **Path resolution**: deeply nested data structures (cost segments, pricing tiers) — does each axis path resolve correctly?

**Enabling Contract Testing — Extracting Pure Functions from Pipeline Code**

Contract tests for data pipelines fail at step zero if the transformation logic is buried inside I/O-heavy scripts. You can't import `_build_registry.py` in a test — it opens files on import and crashes without data. The fix is a two-part extraction:

1. **Pull pure resolvers and constants into a standalone module** (e.g. `data/_resolvers.py`). No file I/O, no side effects, no global state — just functions and dicts.
2. **Import that module from both the pipeline script and the test suite.** The pipeline script retains file handling; the tests exercise only the pure layer.

```python
# data/_resolvers.py — pure, importable, testable
AA_TO_CANONICAL = {
    "gpt-5-5": "gpt-5.5-xhigh",
    "claude-opus-4-8": "claude-opus-4.8",
    ...
}

def aa_slug_to_canonical(slug):
    return AA_TO_CANONICAL.get(slug, slug)

def openrouter_id_to_canonical(rid):
    return rid.strip().lower().split("/")[-1]
```

```python
# data/_build_registry.py — retains I/O, imports resolvers
from _resolvers import aa_slug_to_canonical, openrouter_id_to_canonical, ...

with open("sources/livebench.csv") as f:
    ...
    cid = openrouter_id_to_canonical(m["id"])
```

```python
# tests/test_resolvers.py — tests the pure layer
from _resolvers import aa_slug_to_canonical

def test_all_aa_slugs_resolve():
    for slug in load_aa_slugs():
        assert aa_slug_to_canonical(slug) is not None

def test_no_collisions():
    results = [aa_slug_to_canonical(s) for s in load_aa_slugs()]
    assert len(results) == len(set(results))
```

**File organization for pipeline tests:**

Put test files at the project root (not in `data/`) and inject the data directory into `sys.path` from conftest:

```
project/
  data/
    _resolvers.py       ← pure functions
    _build_registry.py  ← I/O, imports from _resolvers
    _build_axes.py
    processed.json      ← output
    sources/
      ...
  tests/
    conftest.py         ← sys.path.insert(0, DATA_DIR), session-scoped fixtures
    test_resolvers.py   ← contract tests for ID resolution
    test_data_contracts.py ← shape invariants on processed.json
```

```python
# tests/conftest.py
import sys, os, json, pytest
DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
sys.path.insert(0, DATA_DIR)

@pytest.fixture(scope="session")
def processed_models():
    path = os.path.join(DATA_DIR, "processed.json")
    if not os.path.exists(path):
        pytest.skip(f"{path} not found — run build pipeline first")
    with open(path) as f:
        return json.load(f)["models"]
```

**Graceful skip for data-dependent tests:**

Pipeline tests depend on data files that may not exist (pipeline hasn't run, or data changed). Use `pytest.skip()` in fixtures rather than failing:

```python
@pytest.fixture(scope="session")
def raw_scraped():
    path = os.path.join(DATA_DIR, "aa_models_scraped.json")
    if not os.path.exists(path):
        pytest.skip(f"{path} not found")
    with open(path) as f:
        return json.load(f)
```

This means `test --co` shows skips instead of failures when data is absent — green CI even without upstream data, with clear documentation of what's missing.

**What this buys you:**
- Pipeline I/O errors (file not found, malformed JSON) are separate from logic errors (wrong canonical mapping, data collision)
- Tests run in <0.1s — no file I/O during test execution of resolvers
- Adding a new source or canonical mapping is safe — the contract test suite catches collisions

**Example pattern (Python/pytest):**
```python
def test_all_aa_slugs_resolve_to_canonical():
    aa_slugs = load("aa_models_scraped.json").keys()
    for slug in aa_slugs:
        canonical = resolve_canonical(slug)
        assert canonical is not None, f"Unmapped AA slug: {slug}"

def test_processed_model_count_matches_input():
    models = load("model_registry.json")
    processed = load("processed.json")
    assert len(processed) == 85  # known count from AA primary source

def test_axis_field_list_matches_output_keys():
    axes = load("axes_catalog.json")
    output_keys = get_output_keys()
    defined_keys = {a["id"] for a in axes}
    assert defined_keys == set(output_keys.keys())
```

**Why it's distinct:**
| Test type | What it proves | Example |
|-----------|----------------|---------|
| Integration | Wiring, materialization | Persist-and-retrieve round-trip |
| Black-box I/O | Contract fidelity with inputs | Same inputs → same outputs |
| Unit | Logic correctness per stage | Discount applied when premium |
| **Contract** | **Structural invariants, mapping completeness** | Every slug resolves, N-in→N-out |

**Recovering test structure from `.pytest_cache`:** When test `.py` source files have been deleted but cached artifacts remain, `references/pycache-test-recovery.md` documents the procedure to recover the full test suite structure from `nodeids`.

### Derived vs Required Field Contracts

Not all fields are equal. Distinguish two tiers and test them differently:

- **Required fields** — must exist on every entity (slug, name, creator, primary key). Missing one is a hard failure.
- **Derived fields** — computed from preconditions. Only present when inputs satisfy the derivation formula. Missing one when preconditions ARE met is also a hard failure; missing one when preconditions aren't met is correct behaviour.

**Stronger form — Provenance tagging (preferred for rich domain models):** Instead of maintaining a hand-written `DERIVED_FIELDS` list, tag every field with a `Provenance` enum (SOURCED / DERIVED) on the domain class (see `architecture-principles` → "Provenance Typing"). One test class then guards the whole DERIVED set:

1. `test_all_fields_have_provenance` — every dataclass field is in the tag map (catches a new field added without a tag).
2. `test_no_derived_value_from_corrupt_input` — for each non-null DERIVED value, recompute the formula from its SOURCED inputs and assert it matches (derivation-integrity). Also assert each SOURCED input is present/valid. This catches a corrupt SOURCED input silently flowing into a DERIVED output.
3. `test_derived_fields_absent_when_inputs_missing` — when preconditions aren't met, the DERIVED field must be null.

This is more robust than a hand-maintained list because the tag lives next to the field definition (can't drift), and the integrity test proves the *computation*, not just presence.

```python
# tests/test_derived_properties.py
def test_no_derived_value_from_corrupt_input(processed_js):
    for m in processed_js:
        cws = m.get("cost_per_wallsec")
        if cws is None:
            continue
        ct, sp, tm = m.get("cost_per_task"), m.get("speed_tps"), m.get("tokens_m")
        assert ct and ct > 0 and sp and sp > 0 and tm is not None
        assert abs(ct * sp / (tm * 1e6) - cws) < 1e-6  # recompute matches stored
```

Fallback pattern (when the domain model has no provenance tag yet) — keep a `DERIVED_FIELDS` list in `tests/_constants.py` and assert presence when preconditions met:

```python
# tests/_constants.py — separate module for contract definitions
REQUIRED_FIELDS = ["slug", "name", "creator", "intel", "cost_per_task", ...]
DERIVED_FIELDS = [
    "iq_per_1k_pt",    # needs intel AND cost_per_task > 0
    "cost_per_iq_pt",  # needs intel > 0 AND cost_per_task is not None
]

# test: every model has all required fields
def test_required_fields_present(processed_models):
    missing = {}
    for m in processed_models:
        for field in REQUIRED_FIELDS:
            if field not in m:
                missing.setdefault(field, []).append(m["slug"])
    assert not missing, f"{len(missing)} required fields missing"

# test: derived fields exist when preconditions met
def test_derived_fields_absent_when_no_cost(models):
    for m in models:
        intel = m.get("intel")
        cost = m.get("cost_per_task")
        if intel is not None and cost is not None and cost > 0:
            assert "iq_per_1k_pt" in m  # precondition met, must exist
```

This prevents: (a) treating optional computation gaps as pipeline bugs, and (b) silently shipping a computation that silently returns nothing.

### Cross-Layer Contract Tests: JS ↔ Python

When the pipeline runs in Python and visualisation is in JS (or any two runtimes), test the contractual boundary between them:

- **Axis keys** — the `ALL_AXES` / `RADAR_AXES` array in JS references fields in pipeline output. Test every axis key exists in the data.
- **Field labels** — `FIELD_LABELS` mapping in JS should cover every user-facing field in the data. Test both directions: every label key exists in the data (hard fail for dead labels), and every display-candidate field has a label entry (soft advisory for gaps). See `references/contract-test-drift-detection.md` § "FIELD_LABELS Contract Test".
- **Creator/index colours** — `CREATOR_COLORS` in JS must cover every creator value in pipeline output. Missing entries produce broken visualisation.

```python
def test_all_axes_keys_exist_in_data(processed_models, shared_js):
    """Every RADAR_AXES key maps to a field in processed.json models."""
    axes = extract_js_axes(shared_js)
    keys = {a["key"] for a in axes}
    sample = processed_models[0]
    missing = keys - set(sample.keys())
    assert not missing, f"Axes referencing non-existent fields: {missing}"

def test_creator_colors_cover_all_creators(processed_models, shared_js):
    creators = extract_js_creators(shared_js)
    data_creators = {m["creator"] for m in processed_models if m.get("creator")}
    uncovered = data_creators - set(creators.keys())
    assert not uncovered, f"Creators missing colour mapping: {uncovered}"
```

This catches drift when a new field is added to the pipeline but omitted from the viz config, or a new creator appears in scraped data but has no colour assigned.

> **Concrete example:** `references/contract-test-drift-detection.md` in this skill has a full worked example — regex-based JS parsing, computed-field dependency mapping (computed axis → raw data fields), soft warnings for unreferenced fields, and the real drift it caught (`cache_hit_price` missing from `processed.json`). Use it as a template for new cross-layer contract tests.
>
> **Externalizing inline data:** `references/externalize-inline-data-verification.md` documents the verification workflow for extracting embedded JS data from static HTML into a separate file — slug-for-slug, field-for-field comparison, stale data detection, contract test template, and recovery patterns.

### Back-to-Green: Test Relaxation vs Pipeline Fix

When a contract test fails on first run, the cause might be an overly strict test, not a real bug. The two paths:

| Scenario | Response |
|----------|----------|
| Test assumes count invariant that doesn't hold (e.g., scraped count 107 ≠ filtered count 85) | Relax test to a **range assertion** (`30 ≤ n ≤ 200`) or assert the **processing metric** (filtered count ≤ scraped count). Document why the exact number can't be pinned. |
| Test assumes archetype set that's outdated (pipeline added 'mid-tier' but test only knows 'frontier') | Add the new values to `KNOWN_ARCHETYPES` in `_constants.py` — **always keep the known set in `_constants.py`**, not inline in the test. |
| Test assumes field always present but it's actually derived | Move to derived-field pattern above. |
| Real structural defect (slug collision, zero models) | Fix the pipeline — don't relax. |

Distinction: a failure that can't be reproduced with older data or varies per pipeline run is a test problem, not a data problem.

**Pitfalls:**
- Contract tests fail silently if input data shape changes — pin test data or version it
- Coverage invariants require knowing the expected count — document the source of truth
- Don't over-specify: test that every model has a canonical ID, not that every field has a value (that's a data quality test, not a contract test)
- Use `pytest.skip()` in fixtures for data-dependent tests — green CI even when upstream sources haven't run yet
- Keep contract reference sets (archetypes, creator colours, axis keys) in a shared `_constants.py` module, not inline in test files — guarantees one source of truth that both test and pipeline can reference
- When adding a new source to the pipeline, add its resolver and a contract test for it in the same commit — before the data flows through

### Frontend Viz Verification (No Browser / No jsdom)
When the visualisation layer (vanilla JS, zero-build, SVG/DOM) needs coverage, do NOT reach for jsdom, Puppeteer, or a node test runner. The user explicitly rejected node-based test infra ("we can do this without node"). Verify with:
- **Pure-JS replica**: extract the function's pure logic (geometry, clustering, state transitions) into a standalone `node script.js` with zero imports (no jsdom), assert input→output, run it, then `rm` it. This reproduces the real code path without a browser. Worked this session: cluster union-find fan-out (min separation before/after explode), explode→collapse position divergence (each point returns to its OWN layout index, not a shared slot — a `data-g`-as-index bug collapsed them to one point), highlight/dim class state machine on click.
- **pytest on extracted pure helpers**: if the logic can live in a Python module (resolvers, projection), import and assert there — no DOM needed.
- **Black-box only**: assert the observable Result/return value. Never spy on internal calls, mock invocations, or DOM structure. The user called implementation-heavy tests out explicitly ("no brittle nonsense implementation heavy tests") — they break on any refactor and get deleted. A test that verifies *what* the code produces survives; one that verifies *how* it produces it won't.
**Pitfall — jsdom as a browser stand-in**: jsdom parses SVG/CSS incompletely (no layout, `getScreenCTM()` returns null, no rAF paint). A test that "passes" under jsdom can still be broken in a real browser, and installing it adds a node dep the user won't want. Prefer the pure-JS replica. If a DOM behaviour genuinely can't be replicated purely, say so and verify in-browser rather than faking it with jsdom.

### Back-to-Green: Per-File Monadic Refactor Workflow (user-confirmed)
When converting a pipeline/stage library to `Result`/`Either` monadic style:
- **One commit per code file changed.** The user's rule: "we'll commit at the end of the day when we make a change to a single code file, a code file we will make one commit." A contract change that forces caller updates (e.g. a resolver now returns `Result`, callers `.unwrap_or(None)`) lands in the SAME commit — leaving callers broken violates finish-the-job. Don't split a forced ripple into a broken intermediate commit.
- **Convert at the real I/O boundary.** Wrap file reads/network in a `_load_json` / `_load_csv` (or `from_fn`) returning `Ok(value)` / `Err(reason)`. Pure helpers that can't fail (regex parsers return `[]` on no-match) need no wrapping — forcing `Result` on them adds nothing.
- **Keep `run()` / `build()` returning `Result`**, not raising. A stage that hits an *expected* failure (missing optional file, parse error, empty source) returns `Err`; only a genuinely unexpected bug may still raise (that's a crash, not control flow). The pipeline (`_pipeline.py`) wraps each stage in `from_fn` and short-circuits on `Err`.
- **Don't double-wrap a `Result`.** Wrapping a stage that already returns `Ok`/`Err` in `from_fn` produces `ok(ok(v))` — `.is_err()` is then always False and the short-circuit never fires. Coerce instead: a duck-typed `_is_result(x)` (`hasattr(x, "is_ok") and hasattr(x, "is_err")`) decides whether to pass the value through or wrap it. Pipeline `run()` does `result = returned if _is_result(returned) else ok(returned)`.
- **Black-box tests, no internal spying.** The user explicitly rejected "brittle nonsense implementation heavy tests." Assert the observable `Ok`/`Err` contract by stubbing the I/O boundary (mock `urllib` / `open` / `_load_json`). No mock invocations, no DOM structure, no checking internal call order. A test that verifies *what* the code produces survives a refactor; one that verifies *how* it produces it won't.
- **No jsdom / no node test infra** for the JS layer — verify with a pure-JS replica (extract the function, run with `node`, then delete the temp file). The user said "we can do this without node" originally about JS; the same applies to monadic JS tests.
- **Commit-message style**: terse, lead with the behavior change, note the black-box test addition and suite count. No section banners, no restating the diff.

**Pitfall — relative-import + `_result` resolution (concrete, this session):** A module under `data/` that does `from _result import ok, err` (top-level, expects `data/` on path) breaks when imported as a *package* (`data._build_registry`, `data.sources.aa._build`) because its transitive `from _canonical import ...` → `_canonical` does `from _result import` and can't find `_result`. Fix in the test: put BOTH the repo root AND `data/` on `sys.path`:
```python
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))           # repo root
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "data"))  # data/ for `from _result import`
import data._build_registry as br
from data._result import ok, err
```
**Pitfall — CSV vs JSON loader (concrete, this session):** A `_load_json` applied to a `.csv` source (LiveBench `livebench_2026_01_08.csv`) raises `JSONDecodeError` and surfaces only when a black-box test runs `run()` against real sources. Keep `_load_csv` (csv.DictReader) SEPARATE from `_load_json`. The original code used `csv.DictReader(open(lb_path))`, not `json.load` — a refactor that funnels every load through `_load_json` silently breaks CSV sources. A black-box `run()` test against the real `data/sources/` tree catches this immediately.

When the visualisation layer (vanilla JS, zero-build, SVG/DOM) needs coverage, do NOT reach for jsdom, Puppeteer, or a node test runner. The user explicitly rejected node-based test infra ("we can do this without node"). Verify with:

- **Pure-JS replica**: extract the function's pure logic (geometry, clustering, state transitions) into a standalone `node script.js` with zero imports (no jsdom), assert input→output, run it, then `rm` it. This reproduces the real code path without a browser. Worked this session: cluster union-find fan-out (min separation before/after explode), explode→collapse position divergence (each point returns to its OWN layout index, not a shared slot — a `data-g`-as-index bug collapsed them to one point), highlight/dim class state machine on click.
- **pytest on extracted pure helpers**: if the logic can live in a Python module (resolvers, projection), import and assert there — no DOM needed.
- **Black-box only**: assert the observable Result/return value. Never spy on internal calls, mock invocations, or DOM structure. The user called implementation-heavy tests out explicitly ("no brittle nonsense implementation heavy tests") — they break on any refactor and get deleted. A test that verifies *what* the code produces survives; one that verifies *how* it produces it doesn't.

**Pitfall — jsdom as a browser stand-in**: jsdom parses SVG/CSS incompletely (no layout, `getScreenCTM()` returns null, no rAF paint). A test that "passes" under jsdom can still be broken in a real browser, and installing it adds a node dep the user doesn't want. Prefer the pure-JS replica. If a DOM behaviour genuinely can't be replicated purely, say so and verify in-browser rather than faking it with jsdom.

---

## How They Fit Together

| Layer | Test type | What it proves | Count |
|-------|-----------|----------------|-------|
| System boundary | Integration | Wiring, materialization, persistence round-trip | Few (1-3 per aggregate) |
| Public API | Black-box I/O | Contract fidelity, regression detection | Many (parameterised) |
| Pipeline stages | Unit | Business logic correctness per transformation | Moderate (per pipeline step) |
| Data transformation | Contract | Structural invariants, mapping completeness, coverage | One per boundary |

Without good domain modeling, all four degenerate:
- Integration tests become slow end-to-end UI tests
- Black-box tests explode combinatorially (too many states to enumerate)
- Unit tests mock everything and prove nothing

## Verification

- [ ] Contract tests verify every source slug maps to a canonical ID
- [ ] Model count invariant asserted (N-in, N-out) at pipeline boundaries
- [ ] Field mapping lists (ALL_AXES vs output dict) tested for drift
- [ ] Integration tests cover each aggregate's persistence round-trip
- [ ] Black-box I/O tests use parameterised inputs with expected outputs per combo
- [ ] Unit tests test one pipeline stage per test
- [ ] No test reaches into private state or implementation details
- [ ] Domain model mapping tests exist at domain ↔ persistence boundary
- [ ] All three paradigms present in the test suite
- [ ] Adding a new feature = new `[InlineData]` row, not rewriting tests
