# The Jev plugin family

Decision table for the `jev` keyword sweep of the Hermes plugin catalog. Regenerate from the catalog document before relying on it — entries and pins change by reviewed PR.

## Regenerate

```python
import json, urllib.request
data = json.loads(urllib.request.urlopen(
    "https://hermes-agent.nousresearch.com/docs/api/plugin-catalog.json", timeout=60
).read().decode("utf-8"))
blob = lambda e: json.dumps(e).lower()
for e in data["entries"]:
    if "jev" in blob(e):
        print(e["name"], "|", e.get("category"), "|", e.get("maintainer"), "|", e["repo"])
```

## Provider routes

| Route | Endpoint | Key | Notes |
|---|---|---|---|
| OpenRouter Decisions | `https://openrouter.ai/api/alpha/decisions`, model `~typesafe/jev-latest` | `OPENROUTER_API_KEY` | The accepted path. Billed to the OpenRouter key; alpha endpoint |
| TypeSafe direct | `https://api.typesafe.ai/v1/systemone`, model `jev-latest` | `TYPESAFE_API_KEY` | Rejected on the standing criteria |
| Vercel AI Gateway | `{base}/evaluation-model`, model `typesafe-ai/jev` | `AI_GATEWAY_API_KEY` | Rejected |
| Cloudflare AI | `/accounts/{id}/ai/run` | `CLOUDFLARE_JEV_API_TOKEN` + account id | Rejected |
| Generic JEV gateway | `JEV_BASE_URL` + `JEV_API_KEY` | any OpenAI-compatible gateway | Not the OpenRouter Decisions API; reject |
| Local heuristic | none | none | Lexical/deterministic ranking, no network |

## Surface and verdict

| Entry | Surface | Routes | Verdict |
|---|---|---|---|
| `jev-skill-router` (DoGMaTiiC) | `pre_llm_call`; one `<skill_relevance>` line into user-message context | TypeSafe, **OpenRouter**, Vercel; falls back to Hermes' OpenRouter credential pool | consider — cache-safe (roster and system prompt stay byte-stable), no supervisor overlap |
| `typesafe-skill-router` (DECRUX9812) | `pre_llm_call`; same injection | TypeSafe only | reject — duplicate of the above with no OpenRouter route |
| `jev-skill-router-mcp` (ydmw74) | stdio MCP server, `skill_select` | TypeSafe only | reject — manual `mcp_servers` wiring, env not interpolated by the portable loader |
| `jev-judge` (DoGMaTiiC) | `pre_tool_call` gate on `terminal`/`write_file`/`patch` + `jev_ask` | TypeSafe, **OpenRouter**, Vercel | reject — overlaps the installed supervisor's own pre-tool gate |
| `jev-typesafe` (ajensenwaud) | 4 decision tools | TypeSafe only | reject — subset of the installed supervisor's decision tools |
| `jev` (ourines) | `jev_evaluate` | TypeSafe, Cloudflare | reject — subset of the supervisor's tools, no OpenRouter route |
| `jev-effort-router` (AlphaPerseii3000) | `llm_request` middleware, model + reasoning effort | OpenRouter for the decision | reject — routes only the `ollama-cloud` provider; every other provider passes through untouched |
| `hermes-structured-aux-models` (trajectoire-ai) | model-provider for `auxiliary.*` | **OpenRouter** | reject — claims `auxiliary.approval` (already owned), and routes `compression` (cache veto) |
| `jev-agent-router` (Pinutss) | Agent Plugins v1: skill + stdio MCP | generic JEV gateway | reject — registers no Hermes tools or hooks |
| `jev-mcp-router` (Pinutss) | Agent Plugins v1: skill + stdio MCP | generic JEV gateway | reject — same shape |
| `jev-memory-selector` (Pinutss) | Agent Plugins v1: skill + stdio MCP | generic JEV gateway | reject — overlaps the installed memory store's recall |
| `jev-model-router` (Pinutss) | Agent Plugins v1: skill + stdio MCP | generic JEV gateway | reject — same shape |
| `protean-ordaprompt` (aska-digital) | OrdaPilot topic/session classifier | OpenRouter optional | reject — not applicable outside OrdaPilot |

## Installed-stack ownership

Confirm with `hermes plugins list --json` plus each plugin's `plugin.yaml` before reusing this map; it records which primitives are already owned, so a new entry re-implementing one is an overlap.

| Installed | Owns |
|---|---|
| `nerve` (keeltrace) | Typed Jev decisions (`nerve_decide` / `rank` / `assess` / `verify`), a `pre_tool_call` gate with ALLOW/APPROVAL/BLOCK and fail-to-human, context governance (`nerve_context_curate` / `rehydrate`), token-budget trajectory control, Kanban DoD supervision, SSH workers. Hooks: `pre/post_tool_call`, `pre/post_llm_call`, `transform_tool_result`, `pre_verify`, `post_api_request`, `on_session_end`. Uses OpenRouter Jev by default |
| `jev-approvals` (anpicasso) | The `auxiliary.approval` slot under `approvals.mode: smart`. Cannot generate text |
| `jev-curator` (anpicasso) | Jev relation judgments between skill packages, lifecycle debounce, local mutation guard. Supports `provider: openrouter` |
| `yantrikdb` | Memory store, explainable recall, ranking |

## Effective-settings trap

`plugins.entries.<name>.settings.<key>` in `config.yaml` is the only place plugin settings are read. With no `plugins.entries` block, every plugin runs on its declared defaults — and defaults are conservative: `mode: observe` and `allow_content_egress: false` mean an enabled plugin performs no network work at all. Verify the egress gate in the plugin's own code (`mode != off AND allow_content_egress`, or equivalent) before reporting a plugin as active.
