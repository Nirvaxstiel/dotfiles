#!/usr/bin/env node
// Headless render check for the poe-patch-differ SPA. Stubs a minimal DOM + fetch,
// evaluates index.html's <script>, and asserts a chosen league renders its sections/rows
// without a browser. Catches the "sidebar empty / filter dead" class of bug (e.g. the
// `nav{display:none}` CSS scoping mistake) in CI or after any template edit.
//
// Usage: node verify_spa.js <index.html> <league.json> [expectKey]
//   expectKey  optional row key that must appear in the rendered app pane (case-insensitive substring)
const fs = require('fs');

const [, , idxPath, leaguePath, expectKey] = process.argv;
if (!idxPath || !leaguePath) {
  console.error('usage: node verify_spa.js <index.html> <league.json> [expectKey]');
  process.exit(2);
}

const html = fs.readFileSync(idxPath, 'utf8');
const leagueJson = fs.readFileSync(leaguePath, 'utf8');
const m = html.match(/<script>([\s\S]*?)<\/script>/);
if (!m) { console.error('FAIL: no <script> found in', idxPath); process.exit(1); }
const script = m[1];

// minimal DOM: getElementById returns persistent elements that capture innerHTML/value
const store = {};
function mkEl() {
  return {
    _html: '', _value: '',
    classList: { toggle() {}, add() {}, remove() {} },
    set innerHTML(v) { this._html = v; }, get innerHTML() { return this._html; },
    set value(v) { this._value = v; }, get value() { return this._value; },
    addEventListener() {},
    querySelector() { return mkEl(); },
    querySelectorAll() { return []; },
  };
}
global.document = {
  getElementById(id) { if (!store[id]) store[id] = mkEl(); return store[id]; },
  querySelectorAll() { return []; },
};
global.fetch = async () => ({ ok: true, status: 200, json: async () => JSON.parse(leagueJson) });

(async () => {
  try {
    (0, eval)(script);
  } catch (e) {
    console.error('FAIL: script threw:', e.message);
    process.exit(1);
  }
  await new Promise(r => setTimeout(r, 60)); // let the async fetch + render settle

  const app = store['app'] ? store['app']._html : '';
  const toc = store['toc'] ? store['toc']._html : '';
  const meta = store['meta'] ? store['meta']._html : '';
  const fails = [];

  const details = (toc.match(/<details/g) || []).length;
  if (details === 0) fails.push('TOC has no <details> — sections missing (sidebar empty?)');
  if (app.length < 50) fails.push('app pane empty — league did not render');

  const data = JSON.parse(leagueJson);
  const key = (expectKey || (data.sections[0] && data.sections[0].rows[0] && data.sections[0].rows[0].k) || '').toLowerCase();
  if (key && !app.toLowerCase().includes(key)) fails.push('expected row "' + key + '" not rendered in app pane');

  if (!store['leagueSel'] || !/<option/.test(store['leagueSel']._html)) fails.push('league <select> not populated');

  if (fails.length) {
    console.error('FAIL:\n - ' + fails.join('\n - '));
    process.exit(1);
  }
  console.log('OK: SPA renders. toc <details>=' + details + ', app bytes=' + app.length + ', meta set=' + (meta.length > 0) + ', sample row="' + key + '" present');
})();
