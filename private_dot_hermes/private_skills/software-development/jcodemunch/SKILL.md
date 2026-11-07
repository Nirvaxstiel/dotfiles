---
name: jcodemunch
description: "Use jcodemunch-mcp (mcp_jcodemunch_* tools) for token-efficient code exploration via tree-sitter AST parsing. Index once, query cheaply."
tags: [code, ast, symbols, refactoring, dead-code, blast-radius]
version: 1.0.0
---

# jcodemunch-mcp

**Always use `mcp_jcodemunch_*` tools for code lookup when available.** Prefer symbol search, outlines, and targeted retrieval over reading full files. jcodemunch cuts code-reading tokens by ~95% vs brute-force file reads.

## When to Use

Any code comprehension task:

- Understanding unfamiliar repos
- Finding symbol definitions / references
- Refactoring safety analysis
- Code review / PR risk assessment
- Dead code detection
- Dependency analysis
- Architecture discovery

## Key Tools by Scenario

### Quick Orientation
| Tool | When |
|------|------|
| `mcp_jcodemunch_digest` | Agent stand-up briefing for a repo |
| `mcp_jcodemunch_get_repo_outline` | High-level repo structure |
| `mcp_jcodemunch_list_repos` | See what's already indexed |
| `mcp_jcodemunch_suggest_queries` | Let AI suggest starting points |

### Symbol Retrieval (prefer over `read_file`)
| Tool | When |
|------|------|
| `mcp_jcodemunch_search_symbols` | Find symbols matching a query |
| `mcp_jcodemunch_get_symbol_source` | Get exact source of one symbol (not whole file) |
| `mcp_jcodemunch_get_file_outline` | Get all symbols in a file |
| `mcp_jcodemunch_get_context_bundle` | Source + imports for multiple symbols in one call |
| `mcp_jcodemunch_search_text` | Full-text search across indexed files |

### Safety & Refactoring
| Tool | When |
|------|------|
| `mcp_jcodemunch_get_blast_radius` | What breaks if I change this symbol? |
| `mcp_jcodemunch_check_delete_safe` | Can this symbol be deleted? |
| `mcp_jcodemunch_check_edit_safe` | Can this symbol be edited? |
| `mcp_jcodemunch_plan_refactoring` | Generate edit-ready refactoring instructions |
| `mcp_jcodemunch_get_impact_preview` | What breaks on remove/rename |

### Analysis
| Tool | When |
|------|------|
| `mcp_jcodemunch_find_dead_code` | Unreachable symbols/files |
| `mcp_jcodemunch_get_signal_chains` | How an HTTP route propagates through code |
| `mcp_jcodemunch_get_tectonic_map` | Module boundaries and god-module risks |
| `mcp_jcodemunch_get_dependency_cycles` | Circular imports |
| `mcp_jcodemunch_get_hotspots` | Highest-risk symbols |
| `mcp_jcodemunch_get_pr_risk_profile` | Unified risk score for a PR diff |

### Cross-Cutting
| Tool | When |
|------|------|
| `mcp_jcodemunch_search_ast` | Cross-language AST pattern matching (70+ langs) |
| `mcp_jcodemunch_get_changed_symbols` | Map git diff → affected symbols |
| `mcp_jcodemunch_get_symbol_importance` | PageRank-based architectural centrality |
| `mcp_jcodemunch_find_similar_symbols` | Duplicate detection |
| `mcp_jcodemunch_get_ranked_context` | Best-fit context within a token budget |

## First-Time Setup

Call `mcp_jcodemunch_index_repo(repo="owner/name")` or `mcp_jcodemunch_index_folder(path="/path/to/code")` before querying. Indexing fetches source and builds the AST cache.

## Principles

1. **Precision over breadth** — one `get_symbol_source` call (avg ~30 lines) replaces a full file read (700+ lines)
2. **Use `compact` format** — append `format="compact"` to any tool call for ~45% fewer bytes
3. **Bundle requests** — `get_context_bundle` fetches multiple symbols in one round trip
4. **Know when to read raw** — for large-scale refactors or file-wide renames, still use `read_file`. jcodemunch is for **retrieval**, not wholesale replacement of file I/O

## Registration

Registered as MCP server `jcodemunch`. All tools prefixed `mcp_jcodemunch_*`.
