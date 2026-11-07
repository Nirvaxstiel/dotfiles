# Coverage QA — auditing a league against the forum

Condensed recipe + lessons from the 3.29 / 3.28 audit pass. Read this before authoring
or extending a league; it captures the failure modes that cost the most rework.

## Why this exists
Hand-transcribing 400+ patch-note bullets always drops some. Two distinct failure modes:

1. **Whole section missing.** A section's body can sit *between* two TOC headers in the
   collapsed forum text (e.g. the Breach / Genesis Tree block landed between Betrayal and the
   Breach header). A naive section-slice skipped it entirely — the whole Breach section was
   absent from the JSON.
2. **A summary row drops a numeric list.** A single row like
   `"Jewel top-tier mods: Cold 20% (was 15)…"` scored "covered" on 60% word-overlap while the
   *entire* `Adds 30 to 42 Fire Damage to Spells (previously up to 23 to 32)` block was absent.
   Word-overlap alone cannot catch this.

## The scanner (recipe — recreate as needed)
The strict per-section scanner described below was a standalone `python` script. The repo no
longer bundles it (build pipeline flattened), but the *recipe* is reusable — reproduce it in a
throwaway `execute_code` block when auditing a new league. Core logic:
- Slice the forum cache into its real TOC sections via a curated `KNOWN_TITLES` list (the cache
  collapses notes into 1–2 giant lines, so the TOC is a single space-joined line; do NOT use a
  regex fallback that merges adjacent titles).
- Per-section coverage % and numeric-token enforcement (a fact with ≥2 distinct numbers is a HARD
  miss if none appear in the JSON).
- Truncation detection (`"..."` in any row).
What it does:
- **Slices the forum into its real TOC sections** via a curated `KNOWN_TITLES` list
  (`coverage_scan.py`). The forum cache collapses the notes into 1–2 giant lines, so the TOC is
  a single space-joined line. A regex that matches `.*?(Changes|Revamp|…)` **MERGES adjacent
  titles** (e.g. `"Betrayal Breach Endgame Changes"`) — do NOT use a regex fallback; match the
  curated list instead. If a league has titles not in `KNOWN_TITLES`, add them there.
- **Per-section coverage %** — a 0% section means the whole section is missing.
- **Numeric-token enforcement** — a fact carrying ≥2 distinct numbers (ranges like `"30 to 42"`,
  percentages, `"(was 23 to 32)"`) is a HARD miss if NONE of those numbers appear in the JSON.
  This is the check that catches dropped numeric lists.
- **Truncation detection** — flags any row whose `neu`/`old` contains `"..."` for expansion.

## Reading the output
- Expect **~90%+** on a finished league.
- The remaining misses are mostly **lore/flavour text and generic footnotes** that are
  correctly *not* rows:
  - Narrative: `"Meet Valerie, a dangerous corsair captain…"`, `"We really hope you enjoy…"`
  - Generic footnotes repeated per unique: `"Existing versions can be updated with a Divine Orb"`
  - Descriptive-only: `"This is purely a descriptive change, the functionality has not been changed"`
  Grep-confirm each miss before adding — do not blindly transpose forum sentences into rows.
- The **per-section %** is the real signal. A section <80% with several numeric misses needs a
  look; a section at 100% with a couple of word-level flags is fine (present under other wording).

## Gotchas
- The forum cache comes from `web_extract`: the full notes body is saved even though the tool
  *preview* is truncated, but **all image URLs are stripped** — art still comes from the user.
- **No build pipeline / no skill-copy sync.** The skill dir is docs-only (`SKILL.md` +
  `references/`). There is NO `.hermes` copy and NO `build_site.py` — the SPA is static and
  `index.html` is edited directly at repo root. Scan the JSON directly (not via a built site);
  there is nothing to build and nothing to keep in sync.
- A finished league is judged complete when the scanner is green AND no row contains `"..."`.
