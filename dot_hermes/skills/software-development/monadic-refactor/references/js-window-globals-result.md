# JS window-globals Result load-chain verification

Black-box check that the viz data layer loads correctly WITHOUT a browser or
jsdom. Run with `node` (no deps). The committed test is `tests/test_domain_js.js`;
this is the reusable recipe for quick interactive checks.

## Load chain simulation

```js
const fs = require('fs');

function loadScript(file, win) {
  const src = fs.readFileSync(file, 'utf8');
  // eslint-disable-next-line no-new-func
  new Function('window', src)(win);
}

const win = {};
loadScript('viz/_result.js', win);   // MUST run before dependents
loadScript('viz/_domain.js', win);
loadScript('viz/_shared.js', win);

console.log('Result present:', typeof win.Result === 'object');
console.log('MODELS rows:', win.MODELS.length);
const r = win.loadProjectionModels(win.PROCESSED_DATA);
console.log('loadProjectionModels Ok:', r.isOk(), 'rows:', r.unwrap().length);
```

## Real payload

`data/processed.js` does `window.PROCESSED_DATA = [...]`. To feed it as the
payload, load it the same way (shim a window, eval, read `.PROCESSED_DATA`)
then pass into `loadProjectionModels`. No fake fixtures — real artifact.

## Gotcha: script load order

`_result.js` only works if its `<script>` tag is in `dashboard.html` BEFORE
`_domain.js`. If a dependent reads `window.Result` and the tag is missing, the
page throws at load. The load-chain sim above fails fast (`Result present:
false`) — run it after any change that touches the Result boundary.
