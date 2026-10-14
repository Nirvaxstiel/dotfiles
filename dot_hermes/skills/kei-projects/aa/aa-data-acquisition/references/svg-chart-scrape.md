# AA SVG chart scrape (method-2) — parsing recipe

Source-of-truth export: `data/sources/aa/aa_charts_export.json`. A JSON array of
`{ svg: <outerHTML>, spans: [title, subtitle, desc] }`, one entry per chart. Parser:
`data/sources/aa/_parse_charts.py` (`parse_aa_charts(path) -> {chart_key: [(slug, value)]}`).

## Why this works
AA renders every chart as an inline **recharts SVG**. For bar/ranking charts the SVG
embeds the model identity and the metric value as plain text:
- Model slug: `<a href="/models/{slug}">…display name…</a>` (one per data point, render order)
- Value label: `<text x=".." y="..">VALUE</text>` (one per data point, same render order)

Pair the two lists **by index** — recharts draws them in the same data order, so element
N of the href list maps to element N of the value list. Verified 1:1 on Coding (58/58).

## Extraction (regex, no XML parser needed)
- slugs:   `re.findall(r'href="/models/([a-z0-9\-]+)"', svg)`
- values:  `re.findall(r'<text[^>]*>(.*?)</text>', svg)` then strip inner tags, keep numeric-ish

Scatter charts (Intelligence vs Cost / Context Window / etc.) have **no `<a>` and no
value text** — they plot `<circle>`/`<path>` by x/y coordinate. Skip them; their data is
derivable from existing per-model axes.

**Scatter/over-time charts cannot be slug-mapped from SVG.** The 10 scatter and over-time
charts in the export have zero `<a href="/models/{slug}">` links — only `<circle cx= cy=
data-chart-item-id=UUID>` points. There is no reliable way to attach a circle to a model
slug without fragile text-label proximity matching. More importantly, every scatter chart's
data is already sourced from other places (intel from JSON-LD, cost_per_task from JSON-LD,
context_window from OpenRouter, params_b from OpenLLM, ttft/speed_tps from the AA live API).
Re-extracting scatter chart data from SVG would duplicate existing values with no slug linkage
and no new information. The parser is correct to skip them; do not attempt to recover them
from SVG.

## Value normalization (`_norm_value`)
| Raw           | Stored     | Note                                        |
|---------------|------------|---------------------------------------------|
| `78.3`        | `78.3`     | plain float                                 |
| `$470`        | `470.0`    | strip `$`                                  |
| `16%`         | `0.16`     | strip `%`, divide by 100 (omniscience is 0..1) |
| `&lt;0.01`    | `0.01`     | unescape `&lt;` → `<`; treat `<X` as `X`   |
| `1,234`       | `1234.0`   | strip thousands comma                      |

Omniscience is the ONLY `%` chart → safe to `/100`. Coding/Intel/Time are plain floats;
Briefcase is Elo (plain); Pricing/Cost are `$`.

## Multi-value detection
Some charts carry >1 value per model (Briefcase Elo = analytical + presentation). Detect
by ratio: if `len(values) == len(slugs)` → 1 val/model (zip). If `len(values) % len(slugs)
== 0` → `per = len(values)//len(slugs)`, emit `(slug, values[i*per:(i+1)*per])`. Briefcase
yields `[analytical, presentation]` per model.

## Pitfalls specific to this source
## Pitfalls specific to this source
- **Values are rounded to SVG label precision** (e.g. `0.3` not the precise `0.2963`).
  The exact value lives in JSON-LD if needed; don't treat the rounded chart value as
  authoritative for high-precision viz.
- **Omniscience values live in `<text>` as `89%`**, NOT in `<title>` tooltips (the
  `<title>`s hold model display names). Earlier assumption that omniscience needed
  name→slug resolution was wrong — the `<a href>` slug is right there in render order.
- **File is 2.5MB / 16 charts.** Parse lazily; don't load-all-into-memory carelessly in
  tests — the contract test reads it once per test class, not per test.
