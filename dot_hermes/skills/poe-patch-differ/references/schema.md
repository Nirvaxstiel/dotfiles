# POE Patch Differ — Data Schema

The differ is driven entirely by a JSON document. Rendering is a pure function of this data; the
template never changes per-league.

## Top level

| field    | type   | required | notes                                         |
|----------|--------|----------|-----------------------------------------------|
| `meta`   | object | yes*     | Header/legend metadata (see below). Effectively REQUIRED: the league selector input and the page header/`<title>` render from `meta.version` + `meta.league`; an empty/absent `meta` shows a blank " · " selector (the "DDL defaults to ." bug). Always populate it. |
| `sections` | array | yes     | Ordered list of sections (see below)          |

### `meta` fields (all optional but recommended)
| field    | example                                    |
|----------|--------------------------------------------|
| `game`   | `"Path of Exile"`                          |
| `version`| `"3.29.0"`                                 |
| `league` | `"Curse of the Allflame"`                  |
| `launch` | `"2026-07-24"`                             |
| `posted` | `"2026-07-16"`                             |
| `author` | `"Stacey_GGG"`                             |
| `source` | `"https://www.pathofexile.com/forum/..."`  |

Unknown meta keys are ignored. Missing keys simply omit that tag in the header.

## `sections[]`

| field  | type   | required | notes                                              |
|--------|--------|----------|----------------------------------------------------|
| `id`   | string | yes      | URL anchor + nav target (unique, kebab-case)       |
| `n`    | string | no       | Section number shown in the heading (e.g. `"14"`)  |
| `title`| string | yes      | Section heading                                    |
| `sub`  | string | no       | Sub-heading / one-line context                     |
| `rows` | array  | yes*     | Changed items (see below)                          |
| `sections` | array | no   | **Optional, recursive.** A section may contain nested `sections` (sub-groups). The contents panel and the rendered page both recurse, so you can build arbitrary depth (e.g. a league → category → sub-category → rows). A parent section with `sections` usually omits `rows`, but you may mix both. |

`* rows` is required at a leaf (a section with no `sections`). A branch section uses `sections` instead.

## `sections[].rows[]`

| field | type   | required | notes                                                       |
|-------|--------|----------|-------------------------------------------------------------|
| `k`   | string | yes      | The changed thing (gem, unique, mechanic, system…)          |
| `old` | string | no*      | Previous state. Struck-through red. Omit for `new` OR when the change is qualitative (rework, new source, bug fix) with no clean before/after number. |
| `neu` | string | yes      | New state. Colour depends on `t`.                           |
| `t`   | string | yes      | One of `buff` \| `nerf` \| `chg` \| `new` (see below)       |
| `pos` | array  | no       | Positive impact categories (see **Classification hierarchy**). Overrides `t` when present alongside `neg`. |
| `neg` | array  | no       | Negative impact categories. Values: `loot` \| `combat` \| `other`. |
| `img` | string \| array | no       | Optional image URL(s). A single string renders one IMG button; an array of strings renders one button per URL (each opens the lightbox independently). Use the array form when a row has multiple official art pieces (e.g. Ascendancy L/T/R/B tree views). Source from the official notes: patch-note bodies embed `web.poecdn.com/...` image URLs inline — copy those verbatim. Do not invent or hotlink from wikis. |
| `version` | string | no       | ISO date string (e.g. `"2026-07-22"`) indicating when this row was added or last modified. Drives the version tracking UI: collapsible Version History section, version filter buttons, and date badges on non-original rows. Original T-0 rows get the posted date; updated rows get the update date. See SKILL.md for the GGG mutation pattern and tagging rules. |

`* old` is optional for ALL types. If present and non-empty it renders struck-through as the
"before". If omitted, only `neu` shows (the new state). Use omission for qualitative changes
(reworks, new sources, bug fixes) that have no clean number to strike through.

### `t` semantics (drives colour + badge)
| `t`    | colour of `neu` | badge | meaning                                  |
|--------|-----------------|-------|------------------------------------------|
| `buff` | green           | BUFF  | numerical/functional improvement         |
| `nerf` | red             | NERF  | numerical/functional reduction           |
| `chg`  | cyan            | CHG   | structural rework / rewording, no clear net direction |
| `new`  | amber→green     | NEW   | content did not exist before             |

For `buff`/`nerf`/`chg` both `old` and `neu` render: `<old> → <neu>`.
For `new` only `neu` renders (amber label, green text).

### Classification hierarchy (mixed-signal rows)

A single change can help in one way and hurt in another. Players weight effects by impact, so the
badge is not a naive "any buff ⇒ BUFF". Priority, high → low:

1. **`loot`** — item quantity, rarity, currency, drop rate, vendor/store changes. *Players care most about the loot multiplier.*
2. **`combat`** — damage dealt, life/ES, defenses, skill/stat costs, cooldowns, monster damage/life.
3. **`other`** — AI, UI, QoL, monster behaviour, misc.

A row may declare `pos:["loot"]` / `neg:["loot"]` etc. Resolution:
- If `neg` has a priority **≥** `pos` → **NERF** (e.g. "no longer counts as party member" removes the qty/rarity bonus → `neg:["loot"]` ⇒ NERF, even though the combat penalty is gone).
- Else if `pos` outranks `neg` → **BUFF**.
- If both present at equal priority → **CHG**.
- If neither `pos` nor `neg` is given, the manual `t` field is used.

Example (the "party member" case):
```json
{"k":"Party member?","old":"No longer counts as party member (no life/qty/rarity penalty)","neu":"loot penalty removed","t":"buff","neg":["loot"]}
```
→ resolves to **NERF** because the loot loss outranks the (absent) combat benefit.

## Authoring conventions (NOT auto-enforced)

NOTE: `build_site.py` does **not** validate row structure — it only scans `leagues/*/*.json`,
writes the manifest, and renders the template. The renderer is tolerant of missing optional
fields (a bad `t` falls back to CHG; a missing `old` just hides the strike-through). These are
conventions the author must follow; proofread your rows and run `scripts/verify_spa.js` +
`scripts/coverage_scan.py` before committing.

1. Top level must have `sections` (array, non-empty) for the page to render anything.
2. Every section needs `id` (unique, non-empty) and `title` and `rows` (array). A branch
   section may use nested `sections` instead of `rows`.
3. Every row needs `k` (non-empty), `neu` (non-empty), `t` ∈ {buff,nerf,chg,new}. If `t` is
   none of these the badge falls back to CHG at render time.
4. `old` is optional for every row type. When present and non-empty it renders struck-through
   as the "before"; when absent, only `neu` (the new state) renders. Qualitative changes
   (reworks, new sources, bug fixes) legitimately omit `old`.
5. `meta` — populate it (see above); if present it must be an object.

## Authoring tips
- Keep `k` short and stable (`Winter Orb`, `Doryani's Delusion`) so leagues can be diffed against each other later.
- Put the number/range in `old` and `neu` explicitly — that is what the differ shows.
- When a change is a rework with no clean before/after number, use `t:"chg"` and describe both sides in `old`/`neu`.
- New content with no prior state: `t:"new"`, `neu` only.
- Mixing signals (a buff and a nerf in one row): tag `pos`/`neg` with `loot`/`combat`/`other` instead of relying on `t` — the badge resolves by impact priority.
- Images: when the official notes embed an art URL (e.g. `https://web.poecdn.com/public/news/.../*.jpg`), add it to the relevant row's `img` field. It renders an `IMG` button → lightbox with zoom/pan/flip/rotate. Only use real, source-attributed URLs.
