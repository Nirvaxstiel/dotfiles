# poe-patch-differ — Pitfalls & Debugging

Concrete failure modes observed while building and maintaining the differ. Read before editing
`index.html` (the SPA is now self-contained at repo root — no template, no build script).

## 1. CSS: bare `nav{}` selector hides the sidebar

The SPA has TWO `<nav>` elements:
- `<nav id="toc" class="toc">` — the left contents panel (must always be visible).
- `<nav id="mnav">` — the mobile-only top bar shown under `@media(max-width:860px)`.

A rule written as `nav{display:none; ...}` applies to BOTH, so the contents panel vanishes and
only the league header shows. The filter then "does nothing" because it toggles `.hidden` on nodes
you can't see. Fix: scope the hidden rule to `#mnav` only.

## 2. Runtime: `fetch()` over `file://` is blocked

`index.html` boots by `fetch('leagues/index.json')` then fetches each league JSON. Browsers treat
`file://` origin as opaque and refuse cross-file `fetch()`. Opening `index.html` by double-click
yields an empty main pane and a console error.

Fixes, in order of preference:
- Deploy to GitHub/Forgejo Pages (works natively — same-origin http(s)).
- Local preview: `python -m http.server` from the repo root, then visit `http://localhost:8000/index.html`.
- Never tell users to "just open the file" — document the serve step in the repo README.

## 3. Recursion invariant

`sections` is recursive: a section may contain `sections`. Both renderers must recurse:
- `sectionHtml(s)` renders `s.rows` then `(s.sections||[]).map(sectionHtml)`.
- `tocHtml(sections, depth)` renders rows as `<a>`, children as nested `<details>`.

If you add nesting to a league JSON, confirm both functions still recurse. A branch section usually
omits `rows`; a leaf omits `sections`. The filter walk must also recurse (`#toc > details`, then
nested `:scope details`) or nested branches won't filter.

## 4. Flat architecture — NO build step

`index.html` is the self-contained SPA. On boot it does `fetch('leagues/index.json')`, populates the
league selector, and opens the latest league. There is NO `build_site.py`, NO template substitution,
NO `__MANIFEST__`/`__TITLE__` tokens, NO two-copy skill sync.

- `leagues/index.json` is a **static committed manifest**: `[{version, league, json}]`. Regenerate
  with a one-liner (see README) or hand-edit when adding a league.
- League DATA is fetched at runtime — there is nothing to "rebuild" after editing JSON. Just commit.
- The skill directory (`.agents/skills/poe-patch-differ/`) is **docs-only**: `SKILL.md` + `references/`.
  Do NOT recreate `scripts/` or `templates/` — the agent edits `index.html` directly.

Principle: if the SPA already fetches league data at runtime, do NOT add a build step to inject the
manifest. Fetch the manifest too. A builder that only swaps two string tokens into a template is
pure redundancy (this mistake shipped once; the flatten removed it).

## 5. Top-level `await` in a classic `<script>` throws

`index.html` is a plain `<script>` (NOT `type="module"`). Top-level `await` is ONLY valid in module
scripts or inside an async function. Putting `const MANIFEST = await fetch(...)` at the top level of
the inline script throws `SyntaxError: await is only valid in async functions` in the browser.

This is easy to miss: a headless harness that wraps the script in a `.mjs` (module) will PASS,
because modules allow top-level await — so the bug only surfaces in the real browser.

Fix: declare `let MANIFEST = [];` at top level, then do the `await fetch(...)` INSIDE an existing
`async function boot(){ ... }` IIFE, BEFORE the `Chain.ok(MANIFEST)` call. After any edit, run
`node --check` on the extracted inline script AS A CLASSIC SCRIPT (not `.mjs`) to catch this:
```bash
python -c "import re;h=open('index.html',encoding='utf-8').read();m=re.search(r'<script>([\s\S]*?)</script>',h);open('/tmp/i.js','w').write(m.group(1))"
node --check /tmp/i.js   # must pass with no module flag
```

## 6. Headless verification (no browser) — `_t.js`

The repo-root `_t.js` is the headless smoke test. It extracts `index.html`'s inline `<script>` to a
temp `.mjs`, stubs a minimal DOM + `fetch` (reading the real `leagues/*.json` from disk), imports the
module, and after a tick asserts the app pane rendered rows and the NERF filter click doesn't throw:
```bash
node _t.js
# -> rendered rows: 528 types: {"new":88,"buff":249,"chg":150,"nerf":38,"fix":3}
# -> after NERF click no throw; off: [ 'nerf' ]
```
Run it after every `index.html` edit. It catches the "sidebar empty / filter dead / boot throws"
class of bug without a browser. Note: the harness must build a `file://` URL for the dynamic
`import()` on Windows (absolute paths need the `file:///` scheme), and use `import fs from 'fs'`
(not `require`) inside the generated `.mjs`.

## 7. Title / h1 is render state, not build-time

There is no `__TITLE__` token anymore. `renderLeague(data)` MUST set `document.title` and
`h1.textContent` from `data.meta` (`<version> <league>`), or switching leagues leaves a stale title.
When patching, grep the JS for `document.title =` to confirm it tracks the load.

## 8. Searchable selector — never a native `<select>`

Native `<select>` cannot be typed into. For the league/version picker use a custom combobox:
`<div class="dd"><input id="leagueIn" readonly><div class="list" id="leagueList"></div></div>`.
`buildLeagueOptions(q)` filters `LEAGUES` by `(version + " " + league)` lowercased, sorts
newest-first, renders `<div class="opt" data-json=...>`. Click / Enter(top match) selects; Esc /
outside-click closes. `readonly` + `removeAttribute('readonly')` on focus keeps mobile keyboards
from popping. Do NOT duplicate the league name in both the selector and the contents panel.

## 9. Themed scrollbars (cross-browser)

A bare OS scrollbar clashes with the dark palette. Set both engines:
```css
*{scrollbar-width:thin;scrollbar-color:var(--line) transparent}      /* Firefox */
::-webkit-scrollbar{width:10px;height:10px}
::-webkit-scrollbar-track{background:transparent}
::-webkit-scrollbar-thumb{background:linear-gradient(180deg,var(--amber),var(--cyan));border-radius:0;border:2px solid var(--bg)}
```
Apply to `body`, `.side`, `.toc`, `.diff`. (Cyberpunk variant: `border-radius:0`, neon gradient.)

## 10. `escapeHtml` doesn't escape quotes — breaks data attributes

The `escapeHtml` helper replaces `&`, `<`, `>` but NOT `"` or `'`. When embedding JSON in HTML
attributes (e.g. `data-imgs='${JSON.stringify(imgs)}'`), unescaped double quotes break attribute
parsing. Fix: use custom encoding instead of `escapeHtml` for data attributes:
```js
JSON.stringify(imgs).replace(/'/g,"&#39;").replace(/"/g,"&quot;")
```
Symptom: stray IMG buttons appear on rows that have no `img` field in the JSON.

## 11. TOC row links — scroll to row + flash highlight

Clicking a row in the contents panel should jump to that exact row (not just the section) and flash
it. Pattern that works:
- Give every row a stable `id`: `r-<sectionId>-<slug>` where `slug = (r.k||'').toLowerCase()
  .replace(/[^a-z0-9]+/g,"-")`. Compute it identically in BOTH `sectionHtml` (passed to `rowHtml`)
  and `tocHtml` (the `href`), or links won't resolve.
- TOC row links: `<a href="#r-<sectionId>-<slug>" ...>`. The browser hash-jump works, BUT to control
  offset (sticky nav) and trigger the flash, intercept with a delegated handler:
  ```js
  document.addEventListener("click", e => {
    const a = e.target.closest('#toc a[href^="#r-"]'); if(!a) return;
    const row = document.getElementById(a.getAttribute("href").slice(1));
    if(!row) return;
    e.preventDefault();
    window.scrollTo({top: row.getBoundingClientRect().top + window.scrollY - Math.round(window.innerHeight * 0.28), behavior:"smooth"});
    row.classList.remove("flash"); void row.offsetWidth; row.classList.add("flash");
    setTimeout(() => row.classList.remove("flash"), 1200);
  });
  ```
- CSS: `.row.flash{animation:rowflash 1.1s ease-out}` + `@keyframes rowflash{0%{background:amber}
  40%{background:faded}100%{background:transparent;box-shadow:none}}`. The `void row.offsetWidth`
  forces reflow so re-clicking restarts the animation.
- Verify: render the league, count row `id`s vs TOC `href`s — they must be 1:1 (528/528 in 3.29).

## 12. GGG mutates original posts — use "Updates for" sections as diff source

GGG's patch note update pattern: they mutate the original forum post body AND append
"Updates for YYYY-MM-DD Spoiler" sections at the bottom. The "Updated Patch Notes" subsections
within those spoilers tell you EXACTLY which rows changed and what the new values are.

This means you do NOT need to reconstruct T-0 values — the update sections ARE the diff source.
Tag rows mentioned in "Updated Patch Notes" with the update date (`version` field); rows NOT
mentioned are unchanged. The "was X" pattern in skill-gem `neu` fields is intentional (lets you see
the delta when filtered to new values) — do not strip it as "redundancy."

## 13. Stray `img` fields on wrong rows

When wiring images to rows, verify the JSON has `img` ONLY on the intended rows. A misplaced `img`
field (e.g. on a row that shares a section with the intended row) renders an unwanted IMG button.
After any image wiring, grep the JSON for `"img"` and confirm each hit is on the correct row key.

## 14. `old` is the PREVIOUS STATE, not a restatement of the change

"Party member" was once written as `old: "No longer counts as party member (removes +item
quantity...)"` — wrong. `old` should describe what it WAS; `neu` describes the resulting state. A
redundancy scan that flags `old`/`neu` overlap >60% will surface false positives on skill-gem rows
that use the deliberate "was X" pattern — exclude those from the auto-flag and only fix genuine
mirror cases (e.g. `old` and `neu` are negative-inverses of each other).
