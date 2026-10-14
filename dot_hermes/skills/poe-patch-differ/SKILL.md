---
name: poe-patch-differ
description: "Generate a colour-coded before-to-after patch differ (nerfs red, buffs green, changes cyan, new amber) for Path of Exile or any game with the same shape, from a single JSON file. FP, data is the source of truth, rendering is a pure function of data. Reusable league-to-league."
---

# POE Patch Differ

Generate a colour-coded **before → after** patch differ for Path of Exile (or any game with the
same shape) from a single JSON file. Pure data-in, HTML-out. FP: the data is the source of truth;
rendering is a pure function of the data (`render(sections) -> html`). No hand-editing the template.

## Hard rule: stay objective
This is a DIFFER, not an editorial. Never inject trust/opinion/verdict framing, capstone
philosophy, or "this is good/bad for the game" commentary into the data, template, or output.
Each row reports what changed (old → new) and is tagged by mechanical direction (buff/nerf/chg/new).
The user explicitly stripped a trust-lens version and asked for objectivity — keep it that way.
If opinion is wanted later, that is a SEPARATE artifact, not this differ.

## Architecture (flat, no build step)
- `index.html` is the **self-contained SPA** at repo root. It is a **classic `<script>`** (no
  `type="module"`), so it CANNOT use top-level `await`. The boot fetches the manifest *inside* the
  async IIFE: `(async function boot(){ MANIFEST = await fetch('leagues/index.json')...;
  Chain.ok(MANIFEST).then(...).catch(reportFatal).run(); })();` with `let MANIFEST = []` declared at
  top level. No `build_site.py`, no template substitution, no two-copy skill sync. Edit `index.html`
  directly for style/behaviour.
- `leagues/index.json` is a **static manifest** — `[{version, league, json}]`, committed. Regenerate
  with a one-liner (see README) or hand-edit when adding a league. It is NOT built.
- This skill dir is **docs-only**: `SKILL.md` + `references/`. No `scripts/`, no `templates/`. The
  agent reads this to learn the data model + conventions; it never runs a builder.

## Design principles (user-stated)
- **FP / data-as-pure-structure.** The JSON is the single source of truth. Rendering is a pure
  function of the data; `index.html` never changes per-league. Do NOT hand-edit rendered output —
  there is none; edit `index.html` only for style/behaviour, and edit JSON for data.
- **Dead-easy plug-and-play.** Each league = ONE json file under `leagues/<ver>/<ver>.json`, plus one
  manifest line. No per-league HTML, no build to run. Restyle once in `index.html`'s `<style>`, it
  applies to all leagues.
- **Add NOTHING that wasn't in the original design during an aesthetic pass.** When restyling/
  colourising, do NOT introduce new structural or decorative elements that weren't there before:
  divider rules between columns, accent border-bars on the header (`border-left:5px`), subtitles
  under the title, container panels wrapping an already-flowing region, extra scroll layers. The
  user has repeatedly rejected these as "wasn't there in the first place" / "too space wasty" /
  "don't need this divider". Pull FROM the original, don't pile ON it. If an element's only job is
  to look busy, delete it. (Corollary: if you added a wrapping container and later strip it, the
  inner boxes must get their shadow BACK — see shadow rule.)
  - **Concrete reversals from the 3.29 cyberpunk/colour-scheme pass (do NOT re-add):** all three were
    added during that pass and the user wanted them gone because they "weren't there in the first place":
    - `#app` as a bordered panel → reduced to a `border-left:2px solid` divider → then the divider
      removed entirely. User: "don't need this divider. too big, too space wasty. wasn't there anyway."
    - `header{ border-left:5px solid var(--amber) }` (the "line divider from title to section card") → removed.
    - `<div class="sub">Patch Notes — before → after</div>` subtitle under `<h1>` → removed (markup + `.sub` CSS rule).
    When unsure whether an element is original, check the pre-restyle commit (`git log`/`git show`) or ask —
    do NOT assume a later aesthetic pass's additions are wanted. The original differ was plain: title +
    meta/legend, no subtitle, no header accent bar, no right-panel border.

## Invocation (read this — host quirks)
- Use `python` (NOT `python3` — `python3` is missing on this Windows/MSYS host; `python` is 3.11).
- The SPA fetches league JSON at runtime, so **`file://` opening is blocked by most browsers**
  (opaque-origin `fetch`). Serve the folder (`python -m http.server` from repo root) or deploy to
  GitHub/Forgejo Pages (works natively). Document this in the repo README so users don't open
  `index.html` directly and see a blank pane.
- **Headless smoke test:** `node _t.js` extracts `index.html`'s inline `<script>`, stubs DOM+fetch,
  imports it as a temp `.mjs` (top-level await needs module scope + a `file://` URL on Windows), and
  confirms it boots + renders rows. Run after any JS edit.

## Sourcing the patch notes (when authoring a new league json)
- poewiki (`Version X.Y.Z`) is **Anubis bot-walled** via curl/web_extract — do not rely on it.
- **The official forum thread via `web_extract` extracts the static notes body ONLY — the
  "Updates for YYYY-MM-DD Spoiler" blocks are JS-collapsed and the extractor returns just the
  header labels ("Updates for 2026-07-24 Spoiler …") with NO body.** So `web_extract` is
  sufficient for the original T-0 notes but **cannot retrieve later update spoilers.** (The body
  text sits in the initial HTML, CSS-collapsed — `web_extract`'s markdown converter drops it.)
- **To get update spoiler bodies: `curl` the raw thread HTML, then slice between the spoiler
  headers.** Cloudflare *does* serve the full HTML to a plain `curl -A "Mozilla/5.0 (Windows
  NT 10.0; Win64; x64)"` (the body is ~199KB, not a challenge page — the earlier "CF-blocked to
  curl" note was about art/CDN URLs, not the forum thread HTML itself). The spoiler content appears
  as plain text between `Updates for <date> Spoiler` and the next `Updates for <date> Spoiler` /
  `Return to top`. Recipe: write the HTML to a file, then with `execute_code` slice on the date
  strings and `re.sub(r'<[^>]+>', ' ', seg)` to strip tags. Working example:
  ```python
  import re, html
  h = open("C:/Users/Kei/pn.html", encoding="utf-8", errors="ignore").read()
  for d in ["2026-07-23", "2026-07-24"]:
      m = re.search(r"Updates for " + d + r" Spoiler", h)
      start = m.end()
      nxt = re.search(r"Updates for 2026-07-\d\d Spoiler", h[start:])
      stop = (start + nxt.start()) if nxt else len(h)
      seg = re.sub(r"<[^>]+>", " ", h[start:stop])
      print(d, "->", re.sub(r"\s+", " ", html.unescape(seg)).strip()[:2000])
  ```
  (Note: `python3` is missing on this host — use `execute_code` or `python`, not `python3`.)
- **The live forum art/CDN URLs are STILL not fetchable headlessly** — `web.poecdn.com` images
  don't resolve via curl and `web_extract` strips them. Never fabricate image URLs; ask the user
  to paste the real `web.poecdn.com` link.
- **`web_extract` strips ALL images** — the cached markdown has zero `<img>`/poecdn URLs. The real
  art links only exist on the live notes page (inline `web.poecdn.com/...`). When the user provides
  one, copy it verbatim into the row's `img` field.
- Process: extract notes → chunk into sections → write rows as `{k,old,neu,t}`. For reworks/bug
  fixes with no clean number, omit `old` (qualitative) rather than inventing a before-value.
- See `references/sourcing.md` for the extraction/chunking recipe.

## Hosting (GitHub Pages / Codeberg Pages)
- GitHub: `.github/workflows/build.yml` uploads the whole repo as a Pages artifact on push — **no
  build step**, it's already static.
- **Codeberg/Forgejo needs NO dedicated CI file.** Codeberg Pages serves
  `https://<user>.codeberg.page/<repo>/` directly from the repo (enable Pages in repo settings).
  Do NOT add a `.forgejo/workflows/*.yml` — it's dead weight. Push the same repo and it works.

## When to use
- You have a set of patch notes and want a scannable differ (nerfs red, buffs green, changes cyan, new amber).
- League-to-league reuse: each league is ONE json file. Run the builder. Done.
- You want to keep a repo of patch differs (e.g. `Gaming/Path of Exile/Patchnotes/`).

## The data model (the only thing you write)

A patch is a JSON object:

```json
{
  "meta": {
    "game": "Path of Exile",
    "version": "3.29.0",
    "league": "Curse of the Allflame",
    "launch": "2026-07-24",
    "posted": "2026-07-16",
    "author": "Stacey_GGG",
    "source": "https://www.pathofexile.com/forum/view-thread/3985332"
  },
  "sections": [
    {
      "id": "skills",
      "n": "14",
      "title": "Skill Gem Changes",
      "sub": "System-wide + notable skills",
      "rows": [
        { "k": "Winter Orb", "old": "1 proj, crit 6%, 360-450 cold", "neu": "2-3 proj, 25% freeze, crit 7.5%, 360-539 cold", "t": "buff" },
        { "k": "Elemental Hit", "old": "Added Fire/Cold/Lightning", "neu": "-17% (Spectrum unaffected)", "t": "nerf" },
        { "k": "New Pact gem", "neu": "Exceptional gem — empowers X", "t": "new" }
      ]
    }
  ]
}
```

### Row type `t` — one of:
- `buff` → new value green
- `nerf` → new value red (old struck-through red)
- `chg`  → structural/rewording, cyan
- `new`  → brand-new content, amber (omit `old`)

If `t` is `new` or `old` is absent, only `neu` is shown (amber/green). Otherwise both `old`
(struck-through) and `neu` render side by side — that is the differ.

### Mixed-signal rows: `pos` / `neg` classification
A single change can help AND hurt (e.g. "no longer counts as party member" — combat penalty gone,
but the item-quantity/rarity bonus is also gone). Players weight effects by impact, so the badge is
NOT a naive "any buff ⇒ BUFF". Add `pos` / `neg` arrays of category tags; resolution in
`resolveClass()` is priority-ordered **`loot` (3) > `combat` (2) > `other` (1)**:
- higher-priority side wins; equal priority → `chg`; neither present → fall back to `t`.
- `loot` = quantity/rarity/currency/drop rate/vendor. `combat` = damage/life/defense/cost/cooldown/
  monster stats. `other` = AI/UI/QoL/behaviour.
- Example: `{...,"t":"buff","neg":["loot"]}` → resolves **NERF** (loot loss outranks absent combat).
This is encoded in `index.html` (`resolveClass`) and documented in
`references/schema.md`. Always tag mixed rows with `pos`/`neg` rather than a manual `t`.

### `img` — official art (lightbox)
Rows may carry `"img": "<url>"`. It renders an `IMG` button → a lightbox with zoom (buttons +
scroll), pan (drag), flip H/V, rotate, reset, close. **Source rule:** patch-note bodies embed
`web.poecdn.com/...` image URLs inline (ascendancy trees, uniques, skill icons). Copy those
VERBATIM into `img`. Do NOT invent URLs and do NOT hotlink from wikis. Note: `web_extract` returns
TEXT ONLY (images stripped), so the URL will NOT appear in the extracted notes — the user must
paste the real `web.poecdn.com` link (or you transcribe it from the live notes page). Fabricating
an image URL breaks the objective/source-attributed standard.

`img` supports **a single URL string OR an array of URLs**. For arrays, the template renders
a single **IMAGES** button that opens a gallery lightbox with **left/right ‹ › navigation**,
a **counter** (e.g. "1 / 4"), and **keyboard support** (←/→ arrows navigate, Escape closes).
Single-string renders a plain **IMG** button (no nav). Use the array form when a row has
multiple official art pieces (e.g. an Ascendancy rework with Left/Top/Right/Bottom tree views):

```json
{ "k": "Reliquarian", "img": [
    "https://web.poecdn.com/...Left.jpg",
    "https://web.poecdn.com/...Top.jpg",
    "https://web.poecdn.com/...Right.jpg",
    "https://web.poecdn.com/...Bottom.jpg"
], ... }
```

Single-string still works: `"img": "https://web.poecdn.com/...jpg"`. The template normalizes
both forms. **Do not silently wire only one of several art pieces** — surface the gap and ask
the user for the remaining URLs.

**Ascendancy art convention:** ascendancy tree images typically come in **quadrants**
(Left/Top/Right/Bottom). The user pastes the `web.poecdn.com` URLs; wire all of them as an
array on the overview row. **Per-league rule:** ascendancy art changes every league (e.g.
Reliquarian in 3.29 ≠ Reliquarian in 3.28). Never carry an `img` URL from one league JSON
into another — each league's images are version-specific.

### `version` — tracking patch note updates

Rows may carry `"version": "2026-07-22"` (ISO date string). This enables the version tracking
UI: a collapsible **Version History** section at the top of each league (showing row counts per
version), **version filter buttons** in the legend area (isolate rows by version date), and
**version badges** on non-original rows (small date tags, e.g. `07-22`).

**How to tag versions:**
- Original T-0 rows: `"version": "2026-07-16"` (the posted date)
- Rows changed in updates: tag with the update date (e.g. `"version": "2026-07-22"`)
- Rows unchanged across versions: keep the original date

**GGG mutation pattern (important):** GGG mutates the original forum post AND appends
"Updates for YYYY-MM-DD Spoiler" sections at the bottom. The "Updated Patch Notes" subsections
within those spoilers tell you EXACTLY which rows changed and what the new values are. This means:
- You do NOT need to reconstruct T-0 values — the update sections ARE the diff source.
- Tag rows mentioned in "Updated Patch Notes" with the update date.
- Rows NOT mentioned are unchanged from T-0.
- **CUMULATIVE RE-LISTINGS ARE NOT NEW CHANGES.** Each update spoiler re-prints the WHOLE "Updated
  Patch Notes" list including entries from EARLIER updates. Before bumping a row's `version` to a
  new date, confirm the row's *value actually changed in THAT specific update* — not just that it's
  mentioned. If a row was last changed on 07-22 and merely re-appears in the 07-24 spoiler, leave it
  at 07-22. Only bump (or add) for rows whose numbers/values were edited *in this update*.
  - **Bump** an existing row (advance its `version` to the update date) when an existing entry's
    values changed again.
  - **Add** a brand-new row (tagged with the update date) when the update introduces an entry that
    does not exist in the JSON yet (e.g. a newly-mentioned gem/unique/modifier).
  - This session: 07-23 only changed `Bladefall of Trarthus` (bump 07-16→07-23); 07-24 changed
    `Rolling Magma` + `The Catch / Matryoshka` (bump) and added `Molten Burst`, `Arcanist Brand`,
    `Lightless Astrolabe` (new rows). The Bitter Frost / Unhallowed Rite / Breach / crafting-bench
    entries were re-listed in 07-24 but had NOT changed since 07-22 — left alone.

**Data model:**
```json
{
  "k": "Bane",
  "t": "buff",
  "old": "radius 2.1-2.4m; 50% inc Debuff Duration per Curse",
  "neu": "radius 2.4-2.7m (was 2.1-2.4); 100% inc Debuff Duration per Curse (was 50%)",
  "version": "2026-07-22"
}
```

**Template constants:** `LATEST_VER` (date string) and `VER_LABELS` (map of ISO dates to
short labels like `"07-22"`) drive the UI. Update these when adding new version dates.

**SYNC + DIFF RULES (HARD — missed once, flagged by user twice):**
1. A new version date in the JSON requires edits in THREE places in `index.html`: advance
   `LATEST_VER`, add the date to `VER_LABELS`, and add it to the `renderVersionFilters()` `dates`
   array. Version History is data-driven (auto), but those three lists are hardcoded. Leaving any
   one stale breaks the convention: raw `2026-07-23` labels, wrong LATEST badge, or missing filter
   buttons. Grep `index.html` for `2026-07-2` after every version round. (Full checklist in
   `references/version-tracking.md`.)
2. Every version-tagged row MUST also carry its actual before/after text in `old`/`neu` (keys are
   `old`/`neu`, NOT `new`/`chg`) transcribed verbatim from the "Updated Patch Notes" spoiler. A
   `version` tag with empty `old`/`neu` renders a name + badge + CHG button but NO diff — useless.
   Audit: every row at the newest `version` date has non-empty `old` AND `neu`.

- **VERSION ROUND = FOUR-PLACE EDIT, not one.** Tagging new patch-note updates breaks the
  convention if you touch only the JSON. A new `version` date requires: (1) JSON `version` on the
  row, (2) `LATEST_VER` advanced in `index.html`, (3) `VER_LABELS` gets the new ISO→short mapping in
  `index.html`, (4) `renderVersionFilters()` `dates` array includes the new date. Miss #3 → badge
  shows raw `2026-07-23` instead of `07-23`. Miss #4 → What's New filter has no button for it. Miss
  #2 → LATEST badge stuck on the old date. Version History is data-driven (auto-picks up new dates),
  so only the three hardcoded lists need manual sync. Grep `index.html` for `2026-07-2` after any
  round. This was missed in 07-23/07-24 and the user flagged it as breaking prior-round conventions.
- **NEVER leave `old`/`neu` blank on a version-tagged row.** The differ renders `r.old`/`r.neu`;
  empty fields = name + badge + CHG button but NO change text. When tagging a row for an update,
  transcribe its before/after verbatim from GGG's "Updated Patch Notes" spoiler into `old`(="—")
  and `neu`. Schema keys are `old`/`neu` — there is no `new`/`chg` field. Audit every newest-version
  row for non-empty `old`+`neu` before commit. Same 07-23/07-24 round: rows were version-tagged but
  diffs were blank; user: "we should still capture what changed right."
- **Data model:** `old` = previous state, `neu` = new state. They should NOT say the same
thing in different words. The "was X" pattern in `neu` is intentional for UX (lets you see the
delta when filtered to show only new values), but `old` must NOT restate the change — it must
describe what WAS there before.

## Build (there is none — static SPA)

`index.html` is a self-contained SPA. On boot it `fetch`es `leagues/index.json`, populates the league
selector, and opens the latest league. Each league renders client-side by fetching its own JSON.
No per-league HTML is generated; no build script runs.

To add a league: drop `leagues/<ver>/<ver>.json`, add a line to `leagues/index.json` (hand-edit or
regenerate — see README), and push. Pages deploys automatically. To restyle: edit `index.html`'s
`<style>` block directly. No template/skill round-trip, no rebuild.

## Conventions for a patch repo
- Folder e.g. `Patchnotes/`. Each league = one JSON file under `leagues/<ver>/<ver>.json`.
- The JSON is the durable, diffable artifact. `index.html` (SPA) + `leagues/index.json` (manifest)
  are committed static files — edit `index.html` for style, hand-edit or regenerate the manifest.
- `index.html` fetches league JSON at runtime; serve over http(s) (GitHub/Forgejo Pages native).

## Pitfalls

- **CSS tag-vs-ID scoping.** A bare `nav{...}` hits *every* `<nav>` — including the sidebar
  `<nav id="toc">`. Scope the mobile top bar to `#mnav` only. This bit us AGAIN in the
  `@media(max-width:860px)` block: `nav{display:flex}` (intended for `#mnav`) forced the sidebar
  `<nav>` to `display:flex` too and triggered a Chrome "Ruleset ignored due to bad selector" warning.
  Symptom of getting this wrong: a "bad selector" console warning AND the contents panel rendering
  oddly on mobile. Fix: always use `#mnav`, never bare `nav`. (The `display:none` variant shipped
  once and looked like a dead filter — same root cause.)
- **`file://` blocks local fetch.** The SPA loads league JSON via `fetch()`; most browsers refuse
  `fetch()` of local files over `file://`. Serve the folder or deploy to Pages. Document this.
- **Recursion is a data invariant, not a feature.** `sections[].sections[]` nests arbitrarily;
  `sectionHtml` AND `tocHtml` must both recurse, and the filter walk (`#toc > details`, then nested
  `:scope details`) must too. A leaf omits `sections`; a branch omits `rows`.
- **Manifest is static, committed — not built.** `leagues/index.json` lists `[{version, league, json}]`.
  Regenerate with a one-liner (see README) or hand-edit when adding a league. After editing any
  league JSON, the SPA reflects it on next load (runtime fetch) — no rebuild needed.
- **Always populate `meta` (version/league/author/source/posted/launch).** The league selector
  input and the page `<title>`/header render from `meta.version` + `meta.league`; an empty/absent
  `meta` shows a blank " · " selector (the "DDL should default to latest league instead of ." bug).
  The default league already *loads* correctly on its own — `init()` sorts the manifest by version
  desc and calls `loadLeague(LEAGUES[0].json)`, so the newest league IS the default. The visible
  blank was purely the missing `meta` label, NOT a default-order problem — when the selector looks
  empty, check `meta` first; do not re-engineer the default-load path. Also surface `meta` in the
  page header (author / source link / posted+launch dates) — the user expects the differ to show
  *where the data came from*.
- **Title/h1 is render state, not static.** `renderLeague` MUST set `document.title` and
  `h1.textContent` from the loaded `meta`, or switching leagues leaves a stale title.
- **Native `<select>` is not searchable.** Use a custom combobox for the league/version picker
  (text input + filtered `.list` of `.opt`, click/Enter to select, Esc/outside-click to close).
  Make the input `readonly` and `removeAttribute('readonly')` on focus so mobile keyboards stay
  hidden. Do NOT duplicate the league name in both the selector and the contents panel — show it once.
- **Cross-browser themed scrollbars.** WebKit needs `::-webkit-scrollbar*` (thumb/track/width);
  Firefox needs `scrollbar-width:thin` + `scrollbar-color`. Set both, applied to `body`, `.side`,
  `.toc`, `.diff`. A bare OS scrollbar clashes with the dark palette.
- **THREE-ISLAND LAYOUT (the only correct split).** Three distinct bordered "islands": (1) **header** —
  full-width top band, scrolls away with the page like normal content; (2) **left TOC** (`.side` + `.toc`)
  — sticky island, always visible, scrolls independently; (3) **right detail** (`#app`) — a bordered
  island that scrolls the WINDOW (no inner scroll). The header is full-width ABOVE the `.layout` grid
  row; left + right are the two grid columns under it. This satisfies "contents always visible" +
  "right scrolls in its entirety" + "top gone on scroll".
  - **Island 1 (header):** normal flow at top of `.wrap` (`margin-top:46px`). Scrolls away naturally —
    NO `position:fixed`. Top-level island → keeps the hard offset shadow.
  - **Island 2 (left TOC):** `.side{position:sticky; top:18px; max-height:calc(100vh - 36px);
    display:flex; flex-direction:column; overflow:hidden}` and `.toc{overflow-y:auto; flex:1; min-height:0}`.
    The TOC list scrolls inside the sticky sidebar when long. Top-level island → keeps shadow.
  - **Island 3 (right detail):** `#app{background:var(--bg2); border:2px solid var(--line);
    padding:18px 20px 22px}` — a bordered island so left and right read as symmetric siblings. It
    scrolls the WINDOW (`.diff` inside has NO `max-height`/`overflow`). Row auto-scroll
    (`wireRowScroll` → `window.scrollTo`) moves the whole page. Top-level island → keeps shadow; its
    inner `.card` boxes do NOT (see shadow rule below). First section inside `#app` gets
    `margin-top:0` so there's no double gap under the border (`#app > section:first-of-type{margin-top:0}`).
  - **What broke before (do not repeat):** (a) Giving `.diff` its own `max-height:70vh; overflow-y:auto`
    made it a NESTED scroll container — clicking a TOC row scrolled the window but the inner `.diff`
    pane stayed put. (b) Removing ALL inner scroll (sidebar non-sticky) killed "contents always
    visible". (c) Letting the header share the top of the right pane (no clear island separation)
    read as a mismatch. The three-island split fixes all three. On mobile (`@media(max-width:860px)`)
    undo the sticky/capped sidebar: `.side{position:static; max-height:none; overflow:visible}` and
    `.toc{overflow:visible; flex:none}` so it stacks and flows normally.
- **Preserve the `const $ = id => document.getElementById(id)` helper.** Every render/init function
  uses `$`. A mid-patch edit that replaces the function block can silently drop this line; the page
  throws `ReferenceError: $ is not defined` at runtime. After any `<script>` edit, headless-run `node _t.js`
  so the error surfaces before commit.
- **Favicon: inline SVG data-URI, not a file.** `<link rel="icon" href="data:image/svg+xml,...">`
  (URL-encoded `<svg>`). No asset to commit, no 404 on Pages. Works on GitHub + Codeberg.
- **Images: data field only, never fabricated.** `img` is optional per row; the lightbox reads it
  as-is. There is NO image extraction step — `web_extract` strips art and the forum is CF-blocked to
  curl. If a row needs art, the `img` URL must come from the user (verbatim `web.poecdn.com` link).
  Shipping a guessed URL breaks source-attribution.
- **`img` is ROW-LEVEL ONLY.** The renderer reads `r.img` inside `rowHtml`; a section-level
  `"img"` key is silently ignored (no button appears). If an entire section's art should be
  viewable, put `img` on the first row of that section (or every row that warrants it). Do NOT put
  `img` on the section object — it looks wired but renders nothing. (If you want section-header
  art later, that is a change to `sectionHtml`, not a data convention.)
- **`web_extract` collapses the forum into few very long lines.** The cached `.md` is ~108K chars
  but only ~67 newlines — the whole notes body is one or two giant lines. So naive `search_files`
  / line-grep misses content. To slice into sections: use `re.finditer` over the full string, and
  for each TOC title pick the **largest offset** occurrence (the TOC copy sits near the top at a
  small offset; the real section body is much later). Split each section on `"Return to top"`.
- **Verify completeness against the forum.** Hand-transcribing 400+ bullets always drops some (a
  whole Breach section was missing once; an Abyssal Jewel numeric block was dropped by a summary
  row). Audit per-section: slice the forum cache into its real TOC sections, report coverage % per
  section, enforce that numeric values actually appear in the JSON (catches dropped numeric lists
  hidden behind a summary row), and flag any row whose text was truncated with `...`. Expect ~90%+
  on a finished league. The remaining misses are mostly lore/flavour text and generic footnotes
  correctly NOT rows — grep-confirm each before adding. (The strict `coverage_scan.py` recipe lives
  in `references/sourcing.md` if you want to re-run it; it is not bundled as a script.)
- **Frontend JS is a MANDATED monadic orchestrator — preserve its shape.** The user explicitly
  required: "make the JS more sane. a monadic chain orchestrator main, and everything else." The
  `<script>` is therefore structured as:
  - **`Chain` monad** (`ok`/`then`/`catch`) — threads the league list through named boot stages:
    `Chain.ok(MANIFEST).then(sortLeagues).then(seedLeagueSelector).then(openLatestLeague)
    .then(wireLeaguePicker).then(wireSectionSearch).then(wireLegendFilter)
    .then(wireVersionFilter).then(wireImageLightbox).catch(reportFatal).run();`. Each `then` wraps
    its step in try/catch so thrown errors flow to `.catch(reportFatal)` (NOT an unhandled rejection).
  - **Boot stages** are descriptively-named functions that thread + return `leagues`. The chain *is*
    the documentation — do NOT reintroduce a flat function pile or an `init()` mega-function.
  - `MANIFEST` is fetched at runtime INSIDE the boot IIFE (`MANIFEST = await fetch('leagues/index.json')...`
    placed as the first line of `(async function boot(){ ... })();`, with `let MANIFEST = []` at top level).
    **NEVER** put `const MANIFEST = await fetch(...)` at the top level of the `<script>` — the SPA is a
    *classic* script (no `type="module"`), so top-level `await` throws `SyntaxError: await is only valid
    in async functions` and the page boots nothing. The whole boot is wrapped in the async IIFE so the
    `await` is legal there.
- **LAZY CHAIN MUST CALL `.run()`.** `.then()` only *builds* the pipeline; nothing executes until
  `.run()` is invoked. A refactor that builds `Chain.ok(MANIFEST).then(...).catch(...)` WITHOUT the
  trailing `.run()` compiles clean, builds clean, and **silently boots nothing** in the browser
  (no rows, no error). Always end the orchestrator with `.run();`.
- **Dropped `</script>` breaks the whole page silently.** When patching the `<script>` block, it is
  easy to drop the closing `</script>` line. After any `<script>` patch, confirm the built `index.html`
  has balanced `<script>`/`</script>` counts.
- **After ANY `<script>` edit, headless-verify with `node _t.js`.** It extracts the inline script,
  stubs DOM+fetch, imports it as a temp `.mjs` (top-level await + native ESM scope + Windows
  `file://` URL requirement), and asserts rows render + the NERF filter fires without throwing. A
  change that looks clean in a build can still throw at runtime — verify before commit.
- **`_t.js` is a MODULE harness — it will NOT catch classic-script-only breakage.** `_t.js` writes
  the inline script to a temp `.mjs` and `import()`s it, so top-level `await` and other module-only
  syntax are LEGAL there. The browser loads `index.html` as a **classic `<script>`** (no
  `type="module"`), where `await` at top level is a `SyntaxError`. A green `_t.js` therefore gave a
  FALSE PASS on a top-level-`await` regression that broke the real page. **Always also run
  `node --check` on the extracted inline script as a classic file** (`python -c "import re;h=open('index.html',encoding='utf-8').read();m=re.search(r'<script>([\s\S]*?)</script>',h);open('/tmp/i.js','w').write(m.group(1))"` then `node --check /tmp/i.js`) — that is the guard that catches browser-only syntax errors. Best of all: serve the folder (`python -m http.server`) and `curl` the three endpoints (manifest + each league json → 200) so you know the static serving path is intact.
- **TOC row scroll + flash (user-requested UX).** Clicking a row in the left contents panel scrolls
  to that row (not just the section) and flashes it. Implementation: each row gets a stable `id`
  `r-<sectionId>-<slug>` (slug = `k.toLowerCase().replace(/[^a-z0-9]+/g,'-')`); `tocHtml` row links
  point to `#r-<sectionId>-<slug>` using the SAME slug transform as `rowHtml`/`sectionHtml` (the two
  must match byte-for-byte or links 404). `wireRowScroll` intercepts `#toc a[href^="#r-"]` clicks:
  `preventDefault`, `window.scrollTo({top: rowRect.top + scrollY - innerHeight*0.28, behavior:'smooth'})`
  (upper-third, not top-pinned — keeps the flash clear of the sticky nav and uses vertical space),
  then retrigger a `.row.flash` CSS animation (remove class → force reflow `void row.offsetWidth` →
  add → `setTimeout` remove after ~1.2s). Verify the id/href pairs match by rendering and asserting
  every `#r-..` href resolves to a real `id` (the build-time 528/528 check).
- **View filtering: clickable legend chips + hide-empties.** The legend (`BUFF/NERF/CHANGE/NEW` +
  `ALL`) chips are clickable toggles. Clicking one hides non-matching rows AND collapses any section
  left with zero visible rows; `ALL` restores everything. Wire filters in `wireLegendFilter` +
  `applyLegendFilter` (reads `row[data-t]`, toggles `style.display`, then hides empty `#app section`).
  Don't regress to a static legend or break the empty-section collapse.
- **`escapeHtml` does NOT escape quotes.** The helper replaces `&`, `<`, `>` but not `"` or `'`.
  When embedding JSON in HTML attributes (e.g. `data-imgs='${JSON.stringify(imgs)}'`), the
  unescaped double quotes break attribute parsing. Fix: use custom encoding
  `JSON.stringify(imgs).replace(/'/g,"&#39;").replace(/"/g,"&quot;")` instead of
  `escapeHtml(JSON.stringify(imgs))`. Symptom: stray buttons appear on wrong rows because the
  browser misparses the attribute boundary.
- **CYBERPUNK NEO-BRUTALIST STYLE (user-approved palette).** When restyling `index.html`'s `<style>`:
  background `#0a0a0f` (void), ink `#e8eaed`; accents — cyan `#00f0ff`, magenta `#ff2a6d`, acid green
  `#39ff14`, amber `#fcee0a`, violet `#bd00ff`. Hard offset shadows `4px 4px 0 0 var(--line)` (NO
  blur), thick `2px solid` borders, `border-radius:0`, mechanical `step-end` hover (element lifts +
  shadow grows; active sinks + shadow vanishes), neon `box-shadow:0 0 Npx` glow on interactive
  badges get a glow halo per type. Scrollbar gradient cyan→magenta.
- **SHADOW ONLY ON TOP-LEVEL ISLANDS.** The hard offset shadow (`4px 4px 0 0 var(--line)`) belongs on
  the three top-level islands — header, `.side`, `#app` — because they are the outermost panels.
  Nested boxes INSIDE a panel do NOT get the shadow: they keep their `2px solid` border but drop the
  `box-shadow`. A `.card` inside `#app` is already inside the main panel, so a second offset shadow
  just doubles up and looks heavy. Rule of thumb: if an element is a child of `#app`/`.side`/header,
  it does not need the panel shadow. Focus/hover neon glows are exempt (those are affordances, not
  panel shadows).
  - **INVERSE — shadow returns when the container is removed.** If you strip a wrapping panel
    (e.g. delete `#app{background;border;padding}` so the right region is plain flow, not an island),
    the boxes that were "nested inside it" are now TOP-LEVEL again and MUST get their `box-shadow`
    back. Removing the panel WITHOUT restoring the inner shadow leaves flat, border-only cards that
    look unstyled. This shipped once as `style: drop redundant box-shadow on nested .card` then had to
    be reverted the moment the `#app` container was removed. Decision order: (1) decide if the region
    is a panel or plain flow; (2) panels → inner boxes no shadow; plain flow → inner boxes get shadow.
- **COMMIT MESSAGES: Conventional Commits.** Use the `type: subject` format — `feat:`/`fix:`/`style:`/
  `refactor:`/`chore:`/`docs:` — with a concise lowercase subject (no trailing period, no free-form
  sentence). Examples that passed review: `style: drop redundant box-shadow on nested .card`,
  `fix: top-level await in classic script`. The user explicitly rejected long descriptive sentences
  as commit messages. Keep the subject under ~72 chars.
- **Do NOT name uninstalled fonts in `font-family`.** A `font-family:"Cascadia Code",...` where
  Cascadia Code isn't installed triggers a browser "Request for font blocked at visibility level 1"
  warning and silently falls back anyway. Use the system stack
  `ui-monospace,SFMono-Regular,Menlo,Consolas,monospace` for code/mono text. Same look, no warning.
- **DATA QUALITY — scan, don't patch one.** When the user flags ONE bad row (redundant text, wrong
  `old`, misclassified `t`), do NOT just fix that one. Scan the WHOLE dataset for sibling issues —
  `old`↔`neu` overlap >60%, `old` restating the change instead of the previous state, misclassified
  `t` — and root-cause *why* (usually a transcription/schema slip, not a one-off). The "was X" pattern
  in skill-gem `neu` fields is intentional (shows the delta when filtered to new values) — not
  redundancy; leave it. Report the scan, fix all hits.
- Deeper debugging notes in `references/pitfalls.md`.

## Files in this skill (docs-only)
- `SKILL.md` — this file (architecture + data model + pitfalls).
- `references/schema.md` — full field reference.
- `references/sourcing.md` — how the notes were pulled into JSON (+ strict completeness audit recipe).
- `references/img-and-classification.md` — image sourcing + `pos`/`neg` loot>combat>other hierarchy.
- `references/pitfalls.md` — deeper debugging notes (CSS, fetch, recursion, top-level await, escapeHtml, GGG mutations, TOC scroll+flash, two-pane scroll).
- `references/cyberpunk-theme.md` — neo-brutalist/cyberpunk palette + research bank (user-approved restyle).
- `references/version-tracking.md` — version tracking design, GGG mutation pattern, implementation details.
