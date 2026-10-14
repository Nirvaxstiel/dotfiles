# Sourcing POE patch notes → differ JSON

Recipe used to build `examples/3.29.json` from the official 3.29.0 notes. Reuse per league.

## 1. Get the notes text
- **Avoid poewiki** (`https://www.poewiki.net/wiki/Version_X.Y.Z`): fronted by Anubis proof-of-work,
  returns a "Making sure you're not a bot!" page to curl AND to `web_extract`. Not usable here.
- **Use the official forum thread** via `web_extract`
  (`https://www.pathofexile.com/forum/view-thread/<id>`): returns the full notes body as markdown.
  - The tool preview truncates the MIDDLE (head + tail shown, middle saved to a cache `.md`).
  - The saved file is one giant line; `read_file` truncates long lines. To read the middle:
    - Read the cache file with Python (`open(path, encoding="utf-8")`), slice by `body.find("Section Name")`.
    - Re-wrap: `textwrap.wrap(t, 200)` then write to a temp file, then `read_file` that temp in pages.
- The notes are organised by TOC sections. The forum TOC lists the exact section titles for that
  league (e.g. "The Mirage Challenge League", "Endgame Changes", "Skill Gem Changes", "Bug Fixes").
  Use those TOC titles as your `sections[].title` — search the cache body for the SECOND occurrence
  of each title (the first is the TOC itself; the second is the real section body). Section sets
  differ every league, so read the TOC each time rather than assuming a fixed list.

## 1b. Slice the cached notes into per-section files (deep-scan pattern)
The full notes body is one giant string. To transcribe accurately (and avoid the "you missed
data" failure where a first pass only summarises big sections), slice it programmatically:

```python
import re, os, textwrap
cache = r"C:\Users\Kei\.hermes\cache\web\www.pathofexile.com-<hash>.md"
body = open(cache, encoding="utf-8", errors="replace").read()
titles = ["The Curse of the Allflame Challenge League", "New Content and Features",
          "Skill Gem Changes", "Unique Item Changes", "Item Changes", "Bug Fixes"]  # from TOC
# real body = SECOND occurrence (first is the TOC link). Skip offsets < ~2000.
def body_off(t):
    occ = [m.start() for m in re.finditer(re.escape(t), body)]
    past = [o for o in occ if o > 2000]
    return past[0] if past else occ[-1]
order = sorted(range(len(titles)), key=lambda i: body_off(titles[i]))
prev = 0
for i in order:
    a = body_off(titles[i]); b = body_off(titles[(i+1) % len(titles)]) if i+1 < len(order) else len(body)
    txt = re.sub(r"Return to top\s*$", "", body[a:b]).strip()
    open(f"/tmp/sec_{i}.txt", "w").write("\n".join(textwrap.wrap(txt, 200)))
```
Then `read_file` each sliced file in pages. **Transcribe ALL rows** — do not summarise large
mechanical sections (Skill Gem Changes can be 80+ gems; Unique Item Changes 60+ items). A thin
summary will be flagged as incomplete by the user. Big sections (skills/vaal/supp/uniq/items) are
best built from tuples in execute_code (see SKILL.md "Invocation" for the MSYS path gotcha) and
written to the JSON in batches to avoid oversized single calls.

## 2. Chunk into rows
For each changed item write:
```json
{ "k": "<name>", "old": "<before>", "neu": "<after>", "t": "buff|nerf|chg|new" }
```
- Numeric/functional change with a clear before/after → `old` + `neu`, tag `buff` or `nerf`.
- Rework / new source / system change with no clean number → omit `old`, tag `chg` (or `new` if
  the content did not exist before). Do NOT invent a before-value to satisfy a schema.
- Bug fixes are almost all `t:"chg"` with `old` omitted (qualitative).

## 3. Validate + build
The site is an SPA: drop the league json, then run the ONE builder. There is no per-league
`build.py` — only `build_site.py`, which scans `leagues/*/*.json` and regenerates the manifest +
`index.html`.
```bash
python scripts/build_site.py --root <repo>      # writes leagues/index.json + index.html
```
On this host invoke via execute_code subprocess with absolute Windows paths (see SKILL.md
"Invocation" for the spaced-path MSYS gotcha). `build_site.py` does NOT type-validate rows — it
only scans/slices/mirrors. Type correctness (`t` ∈ buff/nerf/chg/new, `old` optional) is enforced
in the template at render time. Proofread your rows after authoring.
Bug fixes are almost all `t:"chg"` with `old` omitted (qualitative).

## 4. Keep json, treat html as build output
The json is the durable, diffable artifact. The SPA fetches it at runtime — after authoring or
editing any league json, re-run `build_site.py` so the manifest + `index.html` pick it up.

## 5. Scope the Bug Fixes section + "Updates for" hotfixes correctly
A patch forum thread often ends with "Updates for YYYY-MM-DD" hotfix bulletins AFTER the main
"Bug Fixes" paragraph. These fall into two categories:

**Pre-launch updates (BEFORE league launch date):** These are corrections/additions to the
original patch notes and ARE part of the launch differ. Include them — they modify the same
content (gem数值, keystones, notables, unique changes). Example: 3.29 launched July 24;
"Updates for 2026-07-22" was a pre-launch update adding keystones, gem buffs, and unique
changes. These went into the same sections as the original notes.

**Post-launch hotfixes (AFTER league launch date):** These are balance adjustments and bug
fixes made after players are live. They are a SEPARATE artifact — do NOT fold them into the
launch differ unless the user explicitly asks for a "Hotfixes" section.

**Detection pattern:** After extracting the main notes, search the cached text for
`Updates for 2026-MM-DD`. Compare the date to the league `meta.launch` date. Before launch =
include. After launch = separate.

**Extraction:** The "Updates for" sections are at the END of the forum text, after "Return to
top" of the Bug Fixes section. Each starts with `Updates for YYYY-MM-DD Spoiler` and contains
`New Patch Notes:` (additions) and/or `Updated Patch Notes:` (modifications to existing rows).
- `New Patch Notes:` → add as new rows in the appropriate sections.
- `Updated Patch Notes:` → these modify rows already in the JSON. Either UPDATE the existing
  row's `old`/`neu` fields, or add a new row with the updated values and mark the old one as
  superseded (the user decides which approach).
