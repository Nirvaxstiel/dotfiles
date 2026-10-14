# AA Data API — Property Reference (condensed)

From `https://artificialanalysis.ai/data-api/docs` (v2, `/api/v2/language/models`).
Load when mapping AA API fields, resolving "what does property X mean", or debugging
data semantics. Nulls = "not measured", NEVER zero.

## Top-level per-model object
| Property | Type | Meaning |
|---|---|---|
| `id` / `slug` / `name` | string | Identity. `slug` = stable key. |
| `release_date` | string? (ISO 8601) | Release date. |
| `model_creator` | object | Creator/vendor metadata. |
| `reasoning_model` | bool | **Pro+ only.** Is a reasoning model. |
| `intelligence_index_version` | number | Index major.minor (e.g. `4.1`). Scores comparable only within same major version. |

## `evaluations` — composite AA indices
- `artificial_analysis_intelligence_index` — capability 0–100. v4.1 = 9 evals
  (GDPval-AA v2, τ³-Banking, Terminal-Bench v2.1, SciCode, HLE, GPQA Diamond, CritPt,
  AA-Omniscience, AA-LCR). **Pro adds per-benchmark scores.**
- `artificial_analysis_coding_index`, `artificial_analysis_agentic_index` — subsets of above
  (not separately versioned).

## `artificial_analysis_intelligence_index_cost` — PER-TASK COST (authoritative)
> "Pre-calculated cost to run the Intelligence Index evaluation. Free tier exposes
> `total_cost` and `cost_per_task.total_cost`; Pro tier adds input/reasoning/answer cost."
- `cost_per_task.total_cost` — **weighted avg USD per Intelligence Index task**, segmented by
  token type, weighted by Intelligence Index weight. Lower = better. **FREE tier has this.**
- `total_cost` — total to run all Intelligence Index evals (token prices × token counts).
- Pro-only: `input_cost`, `reasoning_cost`, `answer_cost` (at `total` + `cost_per_task` levels).

## `pricing` — token prices (USD per 1M tokens)
- `price_1m_input_tokens`, `price_1m_output_tokens` (Free tier).
- `price_1m_blended_3_to_1` (**Pro+**). Per-provider breakdown = Commercial.

## `performance` — latency/throughput (medians across providers)
- `median_output_tokens_per_second` — output speed.
- `median_time_to_first_token_seconds` — TTFT.
- `median_time_to_first_answer_token_seconds` — time to first answer token.
- `median_end_to_end_response_time_seconds` — end-to-end (assumes 500 answer tokens default).
- **Pro+ adds percentiles/quartiles.**

## Pro/Commercial-only
`context_window_tokens`, `parameters`, `modalities`, `licensing`, `huggingface_url`,
`openrouter_api_id` (Pro+); `evaluation_token_counts`, `aa_omniscience_breakdown`,
`artificial_analysis_openness_index_breakdown` (Pro+, detail endpoint only);
`providers` (Commercial only).

## Tiers (rate limits/day)
| Tier | req/day | Scope |
|---|---|---|
| Free | 100 | headline indices, medians, in/out pricing, free media endpoints. |
| Pro | 500 | full evals, blended pricing, percentiles, context/params. |
| Commercial | custom | provider-level, perf over time, raw measurements. |

## Gotcha that bit us
The hand-curated `data/sources/aa/enriched/aa_model_data.json` `cost` field =
`eff_cost_per_m × tokens_m` = **full-output cost** (fable $5,630). This is NOT the
per-task cost. The real per-task cost is the API's
`artificial_analysis_intelligence_index_cost.cost_per_task.total_cost`. Never map
enriched `cost` → `cost_per_task`.
