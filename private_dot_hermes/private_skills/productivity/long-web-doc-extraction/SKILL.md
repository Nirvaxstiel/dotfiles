---
name: long-web-doc-extraction
title: Long Web Document Extraction & Chunking
description: Reliably fetch + read very large web documents (50k–200k+ char patch notes, wiki pages, forum threads) when web_extract truncates the body and read_file truncates long lines. Verified path for the Hermes NixOS/Linux environment.
tags:
  - web
  - extraction
  - chunking
  - patch-notes
  - references
  - hermes
---

# Long Web Document Extraction & Chunking

When a source page is huge (Path of Exile patch notes, vendor changelogs, long wiki articles), the normal one-shot tools silently drop the middle. This skill is the verified path that gets the **complete** text and makes it readable inside the agent's tool constraints.

## The failure modes (why you can't just call web_extract + read_file)

- **`web_extract` truncates the body.** It returns `head` (~37.5k chars) + `tail` (~12.5k chars) of the clean text and saves the FULL file to disk, telling you the path. The middle is absent from the return value. You must read the saved file, not the return.
- **`read_file` truncates long lines.** If a section is one giant line (common for scraped HTML where newlines were stripped), `read_file` shows only the first ~2000 chars of that line and reports `total_lines: 0`. You cannot page through a 36k-char "line" with offset/limit — the whole thing is line 1.
- **`terminal` curl often gets bot-walled.** poewiki.net returns an Anubis proof-of-work challenge page, not content. The official forum (pathofexile.com/forum/view-thread/ID) works through `web_extract` even when curl is blocked.
- **`search_files` on the saved cache file can fail** with an IO error — fall back to `read_file` or slice it in `execute_code`.

## The verified working path (NixOS/Linux Hermes)

1. **Fetch with `web_extract`** on the target URL(s). It returns the head+tail AND writes the FULL text to a cache path like:
   `/home/kei/.hermes/cache/web/www.<domain>-<hash>.md`
   Capture that path from the return's footer. (Use the URL's forum thread, not a wiki mirror, to avoid bot walls.)
2. **Slice the full text with `execute_code`** (NOT read_file — read_file can't see past line 1's 2000-char cap). In `execute_code`, open the file by its absolute Linux path, e.g. `open("/home/kei/.hermes/cache/web/www.example.com-abc.md")`.
3. **Find section boundaries** by string: `body.find("Section Header")` / `body.find("Return to top NextSection")`. Extract each section slice.
4. **Make slices readable** by wrapping to short lines, then read with `read_file`:
   ```python
   import textwrap
   wrapped = "\n".join(textwrap.wrap(slice_text, 200) or [""])
   open("/home/kei/.hermes/cache/web/section_wrap.txt", "w", encoding="utf-8").write(wrapped)
   ```
   `textwrap.wrap(.., 200)` turns one 36k-char line into ~180 readable lines that `read_file` paginates fine.
5. **Read the wrapped files** with `read_file` (limit 2000). Repeat per section.
6. If a section is itself huge (e.g. 28k-char Skill Gem block), split it at sub-headers the same way before wrapping.

### Why execute_code (not terminal python)
`execute_code` and `terminal` share the same Linux filesystem here; the sandbox restriction that forced a separate path form is gone. Do all slicing in one `execute_code` call, write wrapped files, then `read_file` them.

## Worked example — POE 3.29.0 patch notes (~107k chars)

- `web_extract(["https://www.pathofexile.com/forum/view-thread/3985332"])` → returned head+tail, saved full to `www.pathofexile.com-83702db1b9.md`.
- `execute_code`: open full file, `body.find("Player Changes Sources of Avoid")` → `body.find("Return to top Unique Item Changes")` → wrote `mid_329.txt` (36.8k). Then split mid into asc/skill/vaal/supp/uniq by `body.find(...)` on each header, wrapped each at 200 chars to `*_wrap.txt`.
- `read_file` each `*_wrap.txt` to ingest. The "Skill Gem Changes" block alone was 28k — wrapped to 141 lines, read in one shot.

## Reconciliation caveat
When the user has *also* given you a partial paste or a stream summary, **verify against the fetched full text before encoding claims**. In the 3.29 case a "Harbinger returns" stream claim was ABSENT from the real notes — flag it as a discrepancy rather than encoding it as fact.

## Things NOT to do
- Don't trust the `web_extract` return body as complete — it's truncated. Go to the saved file.
- Don't try to `read_file` a giant single-line section expecting offset/limit to work — it won't.
- Don't `curl` poewiki.net for bot-walled pages — use `web_extract` on the official forum.
- Don't `search_files` the cache `.md` when it errors — use `read_file` or slice it in `execute_code`.

## references/
- `references/poe-329-extraction.md` — the exact slice map (finder strings → output files) used for the 3.29 notes, copy-modify for future POE patches.
