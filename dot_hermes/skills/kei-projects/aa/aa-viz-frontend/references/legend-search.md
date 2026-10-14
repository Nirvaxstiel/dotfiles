# Search box over a chip/icon grid — shared builder + in-place filter

Search UI for the crossover creator legend (`__renderCreatorLegend` in `_shared.js`). The input is NOT hand-rolled: it comes from the shared `searchBox` builder — the same one the data table uses — so both render and behave identically.

## One builder, both call sites

`_shared.js` defines and exports (`window.VIZ_HELPERS.searchBox`):

```js
function searchBox(opts) {
  opts = opts || {};
  return '<div class="viz-search-row" style="display:flex;align-items:center;gap:8px;' + (opts.rowStyle || '') + '">' +
    `<input class="viz-search" type="text" placeholder="${opts.placeholder || 'Search …'}" style="flex:1;">` +
    '<span class="viz-search-count" style="color:#666;font-size:10px;font-family:monospace;"></span>' +
    '</div>';
}
```

- Data table (`data-table.js` `buildShell`): `window.VIZ_HELPERS.searchBox({ placeholder: 'Search …', rowStyle: 'margin-top:6px;' })`; selectors `.viz-search` and `.viz-search-count`.
- Legend: `searchBox({ placeholder: 'Filter creators…', rowStyle: 'flex:0 0 100%;' })` — `flex:0 0 100%` gives the row its own line inside the wrapping legend flexbox.
- Input styling lives once in `dashboard.css` under `.viz-search` (dark bg, 2px border, inset shadow, neon focus). No per-panel variant classes.

## Legend: render once, filter in place

```js
function applyLegendSearch(root) {
  const q = (window.__legendSearch || '').toLowerCase();
  let shown = 0, total = 0;
  root.querySelectorAll('.lg-fi[data-lg-dim="creator"]').forEach(chip => {
    total++;
    const match = !q || chip.dataset.lgVal.toLowerCase().includes(q);
    chip.style.display = match ? '' : 'none';
    if (match) shown++;
  });
  const count = root.querySelector('.viz-search-count');
  if (count) count.textContent = `${shown} / ${total}`;
}

window.__renderCreatorLegend = function() {
  window.__legendSearch = window.__legendSearch || '';
  // build ALL creator chips — no build-time filtering, hiding is the filter's job
  el.innerHTML = searchBox({ placeholder: 'Filter creators…', rowStyle: 'flex:0 0 100%;' }) +
    '<span class="lg-fi' + (isAllActive ? ' active' : '') + '" data-lg-dim="" data-lg-val="">ALL</span>' +
    creators.map(c => {
      const active = window.__legendFilter && window.__legendFilter.dim === 'creator' && window.__legendFilter.val === c;
      const color = window.creatorColor(c);
      return `<span class="lg-fi${active ? ' active' : ''}" data-lg-dim="creator" data-lg-val="${c}"><span class="cr-fs" style="background:${color}"></span>${c}</span>`;
    }).join('') +
    toggleHtml;

  const newEl = el.cloneNode(true);
  newEl.style.display = 'flex';
  el.parentNode.replaceChild(newEl, el);
  window.__creatorLegendEl = newEl;

  const searchInput = newEl.querySelector('.viz-search');
  if (searchInput) {
    searchInput.value = window.__legendSearch;   // survive rebuilds
    searchInput.addEventListener('input', function() {
      window.__legendSearch = this.value;
      applyLegendSearch(newEl);                  // in place — input node stays alive
    });
  }
  applyLegendSearch(newEl);                      // re-apply persisted query to fresh DOM
};
```

Chip clicks are unchanged by the search feature: clicking a `.lg-fi` chip toggles the legend filter via `__setLegendFilter(dim, val)`; the ALL chip (`data-lg-dim=""`) clears it via `__clearLegendFilter()`. The search filter only toggles chip visibility — it never touches selection state.

## Pitfalls

- **Never call `__renderCreatorLegend()` from the `input` handler.** It replaces the subtree that contains the input, so focus/caret die after the first keystroke (`gpt` registers only `g`). Filter in place — that is what `applyLegendSearch(root)` exists for.
- **Re-apply the persisted query after every rebuild.** The legend rebuilds on tab switches and legend-mode toggles; without `searchInput.value = window.__legendSearch` plus a trailing `applyLegendSearch(newEl)`, the text and the filter are silently dropped.
- **Filter only `.lg-fi[data-lg-dim="creator"]` chips.** The ALL/reset chip must stay visible so the user can reset when nothing matches.
- **Chip markup and filter share one attribute name**: chips carry `data-lg-val`, `applyLegendSearch` reads `chip.dataset.lgVal`. Keep them in sync.
- **Count badge is live**: `shown / total`, updated by `applyLegendSearch` — same semantics as the data table's `filtered / total`. Never render a badge the code does not update.
- **Interpolation in template literals**: inside backtick strings use `${}` everywhere; mixing `' + expr + '` concatenation into a backtick emits literal junk with unbalanced quotes.
- **Query state lives on `window.__legendSearch`** — read by the filter, restored on rebuild; not a local/closure variable.
