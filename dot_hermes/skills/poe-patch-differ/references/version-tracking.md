# Version Tracking — Design & Implementation

Patch notes are living documents. GGG posts T-0, then mutates the original post and appends
"Updates for" sections. This feature tracks which rows belong to which version.

## Data Model

Each row gains an optional `version` field (ISO date string):

```json
{
  "k": "Bane",
  "t": "buff",
  "old": "radius 2.1-2.4m; 50% inc Debuff Duration per Curse",
  "neu": "radius 2.4-2.7m (was 2.1-2.4); 100% inc Debuff Duration per Curse (was 50%)",
  "version": "2026-07-22"
}
```

- Original T-0 rows: `"version": "2026-07-16"` (posted date)
- Rows changed in updates: tag with the update date
- Rows unchanged: keep original date

## Template Implementation

### Constants (update when adding new versions)
```js
const LATEST_VER = "2026-07-22";
const VER_LABELS = {"2026-07-16":"07-16","2026-07-17":"07-17","2026-07-22":"07-22"};
```

### Row rendering
- `rowHtml()` adds `data-ver="${ver}"` attribute to each row
- Non-original rows get a version badge: `<span class="ver-badge">07-22</span>`
- Latest version gets `.latest` class (amber glow)

### Version History section
`renderVersionHistory(data)` generates a collapsible `<details>` at the top of the league:
- Counts rows per version
- Shows first 6 row keys per version as preview
- Marks the latest version with "LATEST" badge

### Version filter buttons
`renderVersionFilters()` generates filter buttons in the legend area:
- One button per version date + "ALL" button
- Clicking a button calls `applyVersionFilter()`
- Filters rows by `data-ver` attribute
- Hides sections with zero visible rows

### Chain integration
```
Chain.ok(MANIFEST)
  .then(sortLeagues)
  .then(seedLeagueSelector)
  .then(openLatestLeague)
  .then(wireLeaguePicker)
  .then(wireSectionSearch)
  .then(wireLegendFilter)
  .then(wireVersionFilter)     // <-- new
  .then(wireImageLightbox)
  .catch(reportFatal)
  .run();
```

`fetchAndRender()` resets `verFilter = "all"` on league switch.

## GGG Mutation Pattern

GGG's update pattern:
1. Mutate the original post body (values change in-place)
2. Append "Updates for YYYY-MM-DD Spoiler" sections at the bottom
3. Within those spoilers, "Updated Patch Notes" subsections list exact changes

The `web_extract` cache captures the CURRENT state (post-mutation). The "Updates for" sections
are the authoritative diff source — they tell you which rows changed and what the new values are.

Tagging workflow:
1. Parse the "Updates for" sections to identify changed rows
2. Tag those rows with the update date
3. Rows NOT mentioned are unchanged from T-0
4. Update `LATEST_VER` and `VER_LABELS` constants

## SYNC CHECKLIST — three places must change together (HARD RULE)

When you tag a row with a NEW version date (bump an existing row, or add a new row for an
update), you MUST update the data AND all three hardcoded UI lists in `index.html`, or the
version convention breaks. This was missed in the 07-23/07-24 round: rows got `version` tags
but the UI still showed `2026-07-23` as a raw YYYY-MM-DD label, the LATEST badge stayed on
07-22, and the What's New filter had no buttons for the new dates. The user flagged it as
"you didnt preserve the existing conventions of the previous round."

After editing `3.29.json` (or any league json) for an update, verify ALL of:

1. **JSON `version` field** — every changed/added row carries the new ISO date.
2. **`LATEST_VER`** (const in `index.html`) — advanced to the newest date in the data.
3. **`VER_LABELS`** (const in `index.html`) — map the new ISO date(s) to short labels
   (`"2026-07-23":"07-23"`). WITHOUT this, the badge renders the raw `2026-07-23` instead of `07-23`.
4. **`renderVersionFilters()` `dates` array** (hardcoded list in `index.html`) — include the new
   date(s) so the What's New / Version filter shows buttons for them.

The Version History section is DATA-DRIVEN (`Object.keys(byVer).sort()`), so it picks up new
dates automatically — only the three hardcoded lists (#2/#3/#4) need manual edits. Grep
`index.html` for `2026-07-2` after any version round to confirm no stale date is left behind.

Note: this two-source-of-truth split (JSON data + hardcoded UI lists) is a known fragility.
If you want to remove the regression surface entirely, derive `VER_LABELS` keys and the filter
`dates` from the JSON's actual version set at runtime instead of hardcoding them. Prefer that
refactor over re-typing the lists each round.

## DIFF-TEXT RULE — never leave `old`/`neu` blank on a version-tagged row

A row that changed in an update MUST carry its actual before/after text, transcribed verbatim
from the "Updated Patch Notes" spoiler — NOT just a `version` tag with empty `old`/`neu`. This
was missed in the same 07-23/07-24 round: rows were tagged + got version badges but rendered
with NO diff text (the render reads `r.old`/`r.neu`; both empty → empty `.v` cell, only the
name + CHG button showed). The user flagged: "we should still capture what changed right."

- For a **bumped** row: set `old:"—"` and `neu:"<the update's exact wording>"` (e.g.
  `"Now has 140% Effectiveness of Added Damage at gem level 20 (previously 120%)..."`).
- For an **added** row (new entry from the update): same — `old:"—"`, `neu:"<exact wording>"`.
- The schema keys are `old` and `neu` (NOT `new`/`chg`). `new`/`chg` do not exist as data fields.
- Populate from GGG's own spoiler text — do NOT paraphrase or invent. If the spoiler only says
  "description change", record that literally (e.g. Arcanist Brand: "Now states Projectiles from
  Supported Skills have 4.8 metres maximum Direct Flight (description change only).").

Quick audit after an update round: load the JSON, assert every row whose `version` is the newest
date has non-empty `old` AND `neu`. Zero blanks allowed.

## Redundancy Rule

`old` = previous state, `neu` = new state. They should NOT say the same thing in different words.

- CORRECT: `old: "50% block"`, `neu: "40% block (was 50%)"` — old describes previous state
- WRONG: `old: "50% block"`, `neu: "No longer has 50% block"` — neu restates old in negative form

The "was X" pattern in `neu` is intentional for UX (lets you see the delta when filtered), but
`old` must describe what WAS there, not what the change IS.

## CSS

- `.ver-badge` — small date tag on rows (magenta border, latest gets amber glow)
- `.ver-hist` — collapsible version history section (violet left border)
- `.ver-entry` — each version entry with date, count, and row preview
- `.vf` — version filter button container
- `.vfb` — individual filter button (active = amber, inactive = dimmed)
