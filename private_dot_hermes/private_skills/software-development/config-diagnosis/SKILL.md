---
name: config-diagnosis
description: "Diagnose why an app setting has no effect."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [config, settings, troubleshooting, root-cause, upstream-source, endpoints]
    related_skills: [debugging]
---

# Config Diagnosis — "the setting does nothing"

## When to Use

- A documented setting in an application you do not own appears to have no
  effect: editor settings, gateway/provider endpoints, plugin config, tool config
  files.
- A feature silently produces nothing — no suggestions, no sync, no integration
  output — and logs no error at all.
- A config value is accepted without complaint but behaves as if it were absent.
- Config copied from docs, a blog post, or an older version no longer matches the
  build the user is actually running.

## The rule

**The documentation is the wrong source of truth.** The application's source
defines the accepted value names, the wire format it actually sends, and the
silent early-return paths that drop your config. Read the code that APPLIES the
key — not the schema page, not a blog post, not memory of how it used to work.

Do not edit config on a guess. Extract the contract from source first.

## Procedure

1. **Find the settings schema struct** for the key. Search the app's repo for the
   literal JSON key name. The struct fields and their doc comments give you the
   valid value set, the defaults, and often the exact failure semantics.
2. **Follow the key to the module that APPLIES it** — a provider registry,
   factory, or model-selection module. Silent drops live there, not in the
   schema.
3. **Extract the exact wire contract**: request field names, the response fields
   parsed, and whether your URL is used verbatim or a fixed path is appended.
4. **Compare that contract against the remote API's contract** for the route you
   targeted.
5. **Change the config last**, then verify from the subsystem's own log.

## Reading upstream source without cloning

```bash
# list every path matching a keyword (no auth needed)
curl -s "https://api.github.com/repos/OWNER/REPO/git/trees/main?recursive=1" \
  | python -c "import sys,json;[print(t['path']) for t in json.load(sys.stdin)['tree'] if 'KEYWORD' in t['path']]"

# fetch one file (explicit UA — see pitfalls)
curl -sL -A "Mozilla/5.0" "https://raw.githubusercontent.com/OWNER/REPO/main/PATH" -o ~/file.rs
```

The tree API beats guessing file locations. Read the downloaded file with a
Python regex as well as `search_files` — one search pass is not proof of absence.
Pin the fetch to the branch or tag the user is actually running when versions
matter.

## Pitfalls

- **"No error at all" means a resolution early-return, not a network failure.**
  A setting that must resolve (an `infer`/`auto`/`default` value) commonly makes
  the app drop the whole config and continue when resolution fails: no request is
  sent, nothing is logged, the feature is just dead. Search the applying function
  for `return None` / `unwrap_or_default` / an empty match arm BEFORE assuming the
  request went out and failed.
- **Inference and lookup helpers often demand an exact string match after
  stripping a tag suffix.** A namespaced identifier (`vendor/model`,
  `model:tag`) reduces to something that matches no bare-name arm, so inference
  silently yields nothing. Set the value explicitly whenever the identifier is
  namespaced.
- **Protocol, not just path.** Confirm which sibling route the app speaks. A
  legacy completions contract (`prompt` in, `choices[].text` out) is not
  interchangeable with a chat contract (`messages` in, `choices[].message` out).
  Pointing a completions client at a chat path produces a 4xx and/or a parse
  error that looks like a credential problem.
- **Check whether your URL is used verbatim.** Apps either append a fixed path to
  a base URL or send your string as the entire request URI. Assuming "base URL"
  when it is verbatim sends every request to the wrong path.
- **Do not conclude a route is absent because an OpenAPI spec omits it.** Vendors
  publish specs that lag the live service. Probe instead — `scripts/probe_route.sh`
  compares the real path against a bogus one: a live auth-gated route answers
  401/403, a nonexistent one answers 404.
- **Comment-tolerant config formats defeat JSON-validating write tools.** A
  `patch`/`write_file` against a `settings.json` carrying comments or trailing
  commas is refused as invalid JSON. Edit it with a Python read → replace →
  write, assert the match count first, then re-read to confirm the change landed.
- **Fetch failures masquerade as empty content.** A `403` or a `200` with
  `size_download 0` from `curl`/`urllib` means the edge rejected the request, not
  that the resource is missing. Add `-A "Mozilla/5.0"` and retry before
  concluding anything. A parser error on a zero-byte file is a fetch failure.
- **A zero-hit content search on a file you know is non-empty is a search
  failure, not evidence of absence.** Re-run the search a second way (read the
  file, regex it in Python) before concluding the pattern is not there.
- **When the user states a precondition is already satisfied** (credentials
  configured, service running), take it as given and drop that branch — say you
  are doing so and move to the remaining causes. Re-verifying a stated
  precondition wastes the user's time and they will say so.

## Verification

- Read the log the subsystem writes, not the UI. Apps typically name the failing
  call and the raw error body there.
- Prefer a full **restart** over a window reload — provider/registry config is
  often read once at startup.
- After editing config, re-read the file from disk and quote the changed lines
  back so the user can see exactly what is now set.
- If part of the fix cannot be verified without a credential you do not hold,
  say so plainly and name the next observable (which log line, which status
  code) instead of claiming success.

## Worked instances

- `references/zed-edit-predictions.md` — Zed `edit_predictions` over an
  OpenAI-compatible gateway: full key/value table, the legacy-completions wire
  contract, and the inference path that silently disables the provider.
