# Free API Endpoint Scout — Results

Scouted 20+ endpoints. Only OpenRouter is free + rich + downloadable. Everything else is gated, HTML-only, file-listing-only, or returns empty/gated data.

## Accessibility matrix

| Endpoint | Status | What you actually get |
|---|---|---|
| `openrouter.ai/api/v1/models` | ✅ FREE | 445 models. Full shape: id, name, created, context_length, architecture (modality, input/output modalities, tokenizer), pricing (prompt/completion in $/token, cache_read, cache_write, cache_write_1h), benchmarks.artificial_analysis (intel/coding/agentic indexes, 187 models), benchmarks.design_arena (per-category Elo array, 168 models), reasoning (mandatory, default_enabled, supported_efforts). |
| `openrouter.ai/api/v1/models/{id}/endpoints` | ✅ FREE | Per-provider detail: 10 endpoints for Claude Sonnet 5. Each has provider_name, pricing (prompt/completion/cache_read/cache_write/cache_write_1h), uptime_last_30m/1d/5m, max_completion_tokens, supported_parameters, supports_implicit_caching, throughput/latency_last_30m. |
| `openrouter.ai/api/v1/models/{id}` | ✅ FREE | Single model, same shape as list item. Returns 404 for some IDs. |
| `openrouter.ai/api/v1/models/count` | ✅ FREE | `{"data":{"count":445}}`. |
| `huggingface.co/api/spaces/lmarena-ai/chatbot-arena-leaderboard/tree/main` | ✅ FREE | File listing only: 129 CSV + 136 PKL files. Latest CSV: 2025-08-04. **resolve/main/<file> returns 404** — space is gated, cannot download. |
| `huggingface.co/api/spaces/lmarena-ai/chatbot-arena-leaderboard` | ✅ FREE | Space metadata only (title, tags, sdk, author). No model data. |
| `huggingface.co/api/datasets?filter=benchmark:official` | ✅ FREE | 48 dataset cards. Metadata only (features, splits, download_size). |
| `huggingface.co/api/datasets/OpenEvals/leaderboard-data` | ⚠️ Card public, data gated | Card: 105 models, 23 features (model_id, provider, context_window, aime2026_score, gpqa_score, gsm8k_score, hle_score, mmluPro_score, terminalBench_score, aggregate_score, etc.). **`private: true`** — resolve endpoint returns 404. Cannot download. |
| `huggingface.co/api/datasets/livebench/model_judgment` | ✅ Card public, no leaderboard API | Card: 7 features (question_id, task, model, score, turn, tstamp, category), 60,372 examples in parquet. `/leaderboard` returns `[]`. No aggregated scores — raw per-question data only. |
| `huggingface.co/api/datasets/{id}/leaderboard` | ❌ Empty | Returns `[]` universally. HF does not expose per-dataset leaderboard rows via REST. |
| `artificialanalysis.ai/api/v2/language/models*` | ❌ 401 | "API key is required" on all variants including `/free`. Not usable without credentials. |
| `modelgrep.com/api/v1/models` | ❌ 403 | Forbidden on all variants. |
| `crfm.stanford.edu/helm/*` | ❌ HTML | All endpoints return HTML. No JSON API. |
| `paperswithcode.com` | ❌ HTML | No free JSON API. |
| `github.com/lmarena/arena-catalog` | ⚠️ Git repo | Not an API. Needs cloning + parsing. |
| `github.com/livebench/livebench` | ⚠️ Git repo | Not an API. Needs cloning + parsing. |
| `github.com/stanford-crfm/helm` | ⚠️ Git repo | Not an API. Needs cloning + parsing. |

## OpenRouter live shape (actual, from 2026-09-13)

```json
{
  "id": "anthropic/claude-sonnet-5",
  "canonical_slug": "anthropic/claude-sonnet-5",
  "hugging_face_id": "anthropic/claude-sonnet-5",
  "name": "Anthropic: Claude Sonnet 5",
  "created": 1782843083,
  "context_length": 1000000,
  "architecture": {
    "modality": "text+image+file->text",
    "input_modalities": ["text", "image", "file"],
    "output_modalities": ["text"],
    "tokenizer": "Claude",
    "instruct_type": null
  },
  "pricing": {
    "prompt": "0.000002",
    "completion": "0.00001",
    "input_cache_read": "0.0000002",
    "input_cache_write": "0.0000025",
    "input_cache_write_1h": "0.000004"
  },
  "benchmarks": {
    "artificial_analysis": {
      "intelligence_index": 53.4,
      "coding_index": 81.6,
      "agentic_index": 54.7
    },
    "design_arena": [
      {
        "arena": "models",
        "category": "website",
        "elo": 1150,
        "win_rate": 52.3,
        "rank": 42
      }
    ]
  },
  "reasoning": {
    "mandatory": false,
    "default_enabled": true,
    "supported_efforts": ["low", "medium", "high"],
    "default_effort": "medium"
  },
  "supported_parameters": [...],
  "top_provider": {...}
}
```

**IMPORTANT — field name differences from the old scout doc:** the pricing keys are `prompt`/`completion` (NOT `input`/`output`). The old doc wrote `"input": 10, "output": 50` which is wrong — those were illustrative placeholders. Actual values are per-token floats like `0.000002`.

### Fields that are ALWAYS null/empty (do not waste time on)

- `open_weights.params_b` — 0 models have it populated (keep getting params from OpenLLM)
- `capabilities` — always null/empty
- `modality` (top-level) — always null/empty
- `hugging_face_id` — present but not useful for our pipeline

### Design Arena structure

Two arenas across ~28 categories:
- **`models`** arena (1133 entries, 15 categories): website, codecategories, gamedev, dataviz, uicomponent, 3d, svg, asciiart, graphicdesign, image, logo, imageediting
- **`agents`** arena (465 entries, 13 categories): fullstack, webapps, mobileapps, androidnative, python-pptxslides, godotgamedev, agenticgamedev, htmlslides, agenticslides (multiple formats)

Elo range: 762–1426 (models), 948–1344 (agents). Avg ~1175–1190.

## OpenRouter → Our Domain Model mapping

### Already handled by existing pipeline

| OR field | Our field | Where |
|---|---|---|
| `id` | `aliases.openrouter` | `_canonical.py::openrouter_id_to_canonical()` |
| `name` | `name` | `step_openrouter` strips "Vendor: " prefix |
| `pricing.prompt` × 1M | `pricing.openrouter.inp_price_per_m` | `step_openrouter` |
| `pricing.completion` × 1M | `pricing.openrouter.out_price_per_m` | `step_openrouter` |
| `pricing.input_cache_read` × 1M | `pricing.openrouter.cache_read_price_per_m` | `step_openrouter` |
| `context_length` | `meta.context_window` | `resolve_or_context()` in `_canonical.py` |

### NEW fields (added in scout session, implemented)

| OR field | Our field | Source | Fill strategy | Coverage |
|---|---|---|---|---|
| `created` (unix ts) | `meta.release_date` | OpenRouter | Fill-nulls only | 445 models |
| `benchmarks.artificial_analysis.intelligence_index` | `benchmarks.aa.intel` | AA (via OR mirror) | Fill-nulls only — chart/JSON-LD values win on overlap | 187 models |
| `benchmarks.artificial_analysis.coding_index` | `benchmarks.aa.aa_coding_index` | AA (via OR mirror) | Fill-nulls only | 186 models |
| `benchmarks.artificial_analysis.agentic_index` | `agentic_index` | AA (via OR mirror) | Fill-nulls only | 145 models |
| `benchmarks.design_arena` | `benchmarks.design_arena` (raw array) | DesignArena (new) | Store as-is, no axis projection yet | 168 models |
| `architecture.input_modalities` | `meta.input_modalities` | OpenRouter | Fill-nulls only | 445 models |
| `architecture.output_modalities` | `meta.output_modalities` | OpenRouter | Fill-nulls only | 445 models |
| `reasoning` | `meta.reasoning` (raw object) | OpenRouter | Store as-is | 312 models |

### Measurement conflicts (never map these)

| Concept | AA field | OR field | Reason |
|---|---|---|---|
| Tokens/sec | `pricing.aa.speed_tps` | `performance.throughput_tps` | Different measurement methodology, different numbers |
| TTFT | `pricing.aa.ttft` (seconds) | `performance.latency_ms` (ms) | Different units + different measurement |
| Cache read price | `pricing.aa.cache_hit_price` (observed $/Mtok) | `pricing.input_cache_read` (published rate) | AA is what providers actually charge; OR is rate card |

## What OpenRouter does NOT give us

- `cost_per_task` — AA-computed, no OR equivalent. Primary Crossover X axis.
- `tokens_m` — AA-scraped, no OR equivalent.
- `reasoning_tax_pct` — AA-computed from cost segments.
- Full AA benchmark suite (gpqa, hle, scicode, tau2, terminalbench, livecodebench, mmlu_pro, ifbench, lcr, aime, math_500) — OR only carries the 3 composite indexes.
- Arena Text/Code Elo — OR has design_arena which is a different benchmark.
- LiveBench scores — not in OR.
- OpenLLM scores — not in OR.
- Dirac cache hit rates — not in OR.

## HuggingFace dataset access patterns (what works vs doesn't)

### What DOESN'T work (common failures)

- **`resolve/main/<file>` on gated spaces/datasets returns 404** — the tree endpoint lists files but the resolve endpoint is auth-gated. Do not trust the tree listing as proof of download access.
- **`/api/datasets/{id}/leaderboard` returns `[]`** — HF does not expose leaderboard rows via REST API. Data is in parquet files gated behind dataset access.
- **Dataset card public ≠ data downloadable** — OpenEvals/leaderboard-data has a public card with 23 features listed, but `"private": true` in cardData and the parquet resolve returns 404.

### What DOES work

- **`/api/datasets?filter=benchmark:official`** — returns 48 public dataset cards with features/splits metadata. Useful for discovery.
- **`/api/spaces/.../tree/main`** — returns full file listing for HF spaces. Useful for discovering latest CSV/PKL files even when the space is gated.
- **Public dataset cards** — `livebench/model_judgment` card is fully public with features and split info, even though the data itself is gated.

## Recommended approach

**OpenRouter as additive free source.** Implement in two layers:

**Layer 1 — `_pull_sources.py`:** fetch the FULL API shape. Do NOT strip fields at pull time. The old `pull_openrouter` reduced 445 models to 7 fields — that threw away benchmarks, design_arena, created, architecture, and reasoning. The pull step's job is to download and store; the registry step's job is to transform.

**Layer 2 — `_build_registry.py::step_openrouter`:** merge new fields into `all_models`:
- AA benchmarks → `benchmarks.aa.*` as fill-nulls (chart-scraped values win on overlap)
- Design Arena → `benchmarks.design_arena` as raw array (no axis projection yet)
- `created` → `meta.release_date` via `datetime.fromtimestamp(ts, tz=timezone.utc).date().isoformat()`
- Architecture → `meta.input_modalities` / `meta.output_modalities`
- Reasoning → `meta.reasoning` (raw object)

**Design Arena storage:** store as raw array in `benchmarks.design_arena`. Do NOT explode into per-category axes unless a specific category becomes a frequent filter need. Option A (raw array) is sufficient for v1.

**Commit the refreshed `openrouter_models.json`** after any pull that adds fields — the registry build reads from this file, not the live API. The determinism test compares fresh runs against each other, not HEAD, so a code change that alters output won't fail it — but the committed artifacts must be regenerated or the repo is inconsistent.
