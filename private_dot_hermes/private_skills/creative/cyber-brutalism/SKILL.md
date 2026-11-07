---
name: cyber-brutalism
title: Cyber-Brutalism
description: Drop-in CSS toolkit for the dark grain+mono+acid-accent aesthetic. Zero framework deps — works with Next.js, Astro, React, Tauri, plain HTML, anything that accepts CSS/Tailwind.
tags:
  - design
  - css
  - tailwind
  - brutalism
  - cyberpunk
  - palette
---

# Cyber-Brutalism Toolkit

A grab-and-go design system for the **dark grain + monospace + acid accent** look popularized by indie dev tools (OpenMonoAgent, ctfmon, Vercel Labs projects, etc.).

## When to use

- Landing pages for developer tools, CLIs, AI products
- Terminal-themed UIs, dashboards, documentation sites
- Anything that needs to feel **raw, engineered, anti-corporate**
- Breaking away from shadcn/glassmorphism sameness

## When NOT to use

- Consumer apps for non-technical audiences (cold traffic bounces)
- Content-heavy editorial (the grain hurts readability at scale)
- Anything that needs a soft/friendly brand voice

## Quick start — plain CSS

Copy the `cyber-brutalism.css` file (see [references/cyber-brutalism.css](references/cyber-brutalism.css)) into your project and link it. That's it.

```html
<link rel="stylesheet" href="/css/cyber-brutalism.css">
<body class="cyber-bg cyber-text">
  <h1 class="cyber-headline">your product</h1>
  <p class="cyber-body">raw, grainy, engineered.</p>
  <button class="cyber-btn">get started</button>
</body>
```

## Quick start — standalone HTML (no framework, no SDK)

For one-off artifacts, dashboards, and Obsidian-exported HTML, the cleanest path is **one file** with inline `<style>` and inline `<script>`. No CDN, no build, opens with `file://` or any static server. The reference template is [templates/standalone-dashboard.html](templates/standalone-dashboard.html) — a copy-and-modify scaffold with header, stat strip, chart panel, and table patterns already wired.

The two reference sites that define the "lab/terminal" subsection of this aesthetic — `ctfmon.vercel.app` (Windows internals deep-dive) and `openmonoagent.ai` (local AI dev stack) — both share these specific patterns that users in this style expect:

- **Section markers**: `01 //`, `02 //`, `03 //` ... as a number gutter before section headings. Neon-colored number, monospace, uppercase heading.
- **Terminal comment prefix**: `//` in muted cyan/gray for metadata, captions, and "TAKEAWAY" callouts. Pairs with `>` blockquote-style left border in the same neon.
- **Hard offset shadows on cards** (no blur): `box-shadow: 6px 6px 0 var(--neon)` — the box-shadow color is a deliberate accent, not gray. Rotate the shadow color between lime and cyan to mark section types.
- **Card border is 3px solid white** on dark cards. Never 1px, never subtle. The border *is* the design.
- **No rounded corners.** `--radius: 0` is the rule, not the default.
- **Mixed type**: monospace for everything technical (data, labels, captions, code), a single display sans for one or two big headlines per page. Don't go full mono — that reads as a terminal, not a website.
- **Grid background**: 24px white-line grid at 2% opacity via `linear-gradient` tiled. Reads as engineering paper, not as a generic texture.
- **Numbered "raw data" tables** in the footer (`// DATA: 38 MODELS · v4.1 · 9 EVALS`) — feels like a lab notebook footer, not a copyright line.

Two accent palette tips for the "lab/terminal" sub-aesthetic:
- **Lime `#a3e635` + cyan `#00e5ff`** — default cyber-brutalism combo, the user-favorite for dev-tool pages.
- **Add a third "warn" red `#ff3366`** for danger callouts and stat cards where the number is a problem, not a success. Used sparingly, only on 1-2 cards per page.

**When NOT to mix** the lab/terminal aesthetic with rounded components, soft shadows, gradients, or emojis — even one rounded element breaks the look.

## Quick start — Tailwind CSS

### 1. Apply the grain texture

Add as a CSS layer in your global CSS:

```css
@layer base {
  body::after {
    content: '';
    position: fixed;
    inset: 0;
    pointer-events: none;
    z-index: 9999;
    background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
    background-size: 256px 256px;
    opacity: 0.035;
    mix-blend-mode: overlay;
  }

  @media (prefers-reduced-motion: reduce) {
    body::after { opacity: 0.02; }
  }
}
```

### 2. Extend your tailwind config

See [references/tailwind-extension.js](references/tailwind-extension.js) for the full config snippet to copy into `tailwind.config.*`.

### 3. Use the classes

```html
<div class="bg-cyber-black border border-cyber-border p-6">
  <span class="text-cyber-accent font-mono text-xs tracking-widest uppercase">$ feature</span>
  <h2 class="text-white font-mono text-2xl mt-2">local-first. zero cloud.</h2>
  <p class="text-cyber-muted font-mono text-sm mt-2 leading-relaxed">
    your code never leaves your machine.
  </p>
  <button class="cyber-btn mt-6">deploy →</button>
</div>
```

## Palette reference

| Token | Value | Usage |
|-------|-------|-------|
| `--cyber-black` | `#000000` | Primary background |
| `--cyber-elevated` | `#0a0a0a` | Cards, elevated surfaces |
| `--cyber-surface` | `#111111` | Secondary surfaces |
| `--cyber-foreground` | `#ededed` | Primary text |
| `--cyber-muted` | `#666666` | Secondary / labels |
| `--cyber-subtle` | `#444444` | Tertiary text |
| `--cyber-accent` | `#a3e635` | Primary accent (lime) |
| `--cyber-accent-dim` | `#7ec22b` | Hover state |
| `--cyber-border` | `rgba(255,255,255,0.08)` | Default border |
| `--cyber-border-strong` | `rgba(255,255,255,0.15)` | Emphasized border |
| `--cyber-danger` | `#e5484d` | Destructive |
| `--cyber-warning` | `#f5a623` | Warning |
| `--cyber-info` | `#0070f3` | Info |
| `--font-mono` | `'JetBrains Mono', 'Fira Code', ui-monospace, monospace` | All text |
| `--grain-opacity` | `0.035` | Noise intensity |
| `--radius` | `0` | No rounding |

## Quick component snippets

### Button
```html
<button class="bg-cyber-accent text-black font-mono text-sm px-5 py-2.5 border-0 cursor-pointer hover:bg-cyber-accent-dim transition-colors duration-100">
  $ run
</button>
```

### Card
```html
<div class="bg-cyber-elevated border border-cyber-border p-6">
  ...
</div>
```

### Terminal block
```html
<pre class="bg-cyber-surface border border-cyber-border p-4 text-cyber-muted text-sm font-mono leading-relaxed overflow-x-auto">
<span class="text-cyber-accent">$</span> openmono agent
<span class="text-cyber-foreground">→ Detected GPU, starting inference...</span>
<span class="text-cyber-accent">✓</span> <span class="text-cyber-foreground">Ready. 20 tools registered.</span>
</pre>
```

### Code fence
```html
<code class="bg-cyber-surface border border-cyber-border px-2 py-0.5 text-cyber-accent text-sm font-mono">
  curl -fsSL https://install.sh
</code>
```

## Visual reference: glyphs & icons

See [references/glyphs.md](references/glyphs.md) for the full catalog. Short version:

- **Unicode glyphs** for feature icons — no icon library, no SVGs. Just paste `⎇` `⧗` `◰` `⚒` `⌕` etc. directly in HTML.
- **Inline SVGs** for the 3–4 common shapes (chevron arrow, GitHub icon, phone icon).
- **ASCII / box-drawing** for terminal banners (`┌─┐│└┘`).

## How diagrams & flowcharts are done

No SVG pipeline, no chart library. The cyber-brutalist approach:

1. **Static images** — Architecture diagrams, agent flows, pipelines are exported as JPEG/PNG and embedded with `<img>`. Drawn in Excalidraw, Figma, draw.io, etc.
2. **HTML tables** — Comparisons, benchmarks, feature grids. Plain `<table>` with cyber palette.
3. **Fake terminal blocks** — Div with `.terminal-body` containing `<span class="prompt">$</span>` etc. Pure CSS.
4. **ASCII banners** — `<pre>` blocks with box-drawing characters.

## How animations are done

Dead simple, zero animation library:

1. **CSS transitions** — `transition: opacity 0.15s` on hover/state changes
2. **IntersectionObserver** — Scroll-reveal: elements get `.reveal` class, Observer adds `.in` → CSS animates opacity/transform
3. **CSS cursor blink** — `@keyframes blink { 50% { opacity: 0 } }`
4. **Grain overlay is static** — no animation, just a fixed `feTurbulence` SVG

That's it. No GSAP, Framer Motion, WebGL, or canvas. The raw aesthetic doesn't need fancy motion.

## Alternative accent palettes

Swap `--cyber-accent` for any of these to shift the vibe:

| Vibe | Accent | Hex |
|------|--------|-----|
| Acid lime (default) | lime-500 | `#a3e635` |
| Cyberpunk pink | pink-500 | `#ec4899` |
| Matrix green | green-500 | `#22c55e` |
| Nuclear | yellow-400 | `#facc15` |
| Electric blue | blue-500 | `#3b82f6` |
| Hacker orange | orange-500 | `#f97316` |

## Pleasant / Cinematic Cyberpunk Variant (Wallace Corp / Blade Runner / GITS)

**Trigger:** when the user says the style should be "more pleasant to read", or names **Wallace Corp**, **Blade Runner**, or **Ghost in the Shell** as the reference. This is the SAME brutalist structure (hard offset shadows, zero radius, `01 //` section numbers, monospace labels) but with **softer color contrast** — the default acid-lime-on-pure-black reads as harsh to many users.

Keep the structure, soften the palette:

| Token | Value | Usage |
|-------|-------|-------|
| `--bg` | `#0a0e14` | Deep charcoal-navy, NOT pure black |
| `--bg2` | `#0f1620` | Panel / cards |
| `--ink` | `#e6ebf2` | Soft off-white text (NOT `#fff` — pure white on dark is the harsh part) |
| `--dim` | `#8b9ca8` | Muted steel for secondary text |
| `--line` | `#27323f` | Hairline borders (subtle, not white) |
| `--amber` | `#e8a13a` | Warm Wallace-Corp amber — primary accent |
| `--cyan` | `#5fd0e0` | Cool Blade-Runner cyan — secondary accent |
| `--rose` | `#d98a9a` | Soft (desaturated) rose for "remove/danger" — NOT `#ff3366` hot red |
| `--green` | `#7fb98a` | Calm green for "add/good" |
| `--violet` | `#9a8fc0` | Quiet violet for misc |

Rules that make it pleasant without losing the look:
- **Never** pure `#000` bg or pure `#fff` text. Off-white `#e6ebf2` on `#0a0e14` is the sweet spot.
- Accents are **warm amber + cool cyan**, not acid lime + hot magenta. Desaturate any "danger" color (rose `#d98a9a`, not `#ff3366`).
- Hard offset shadows stay (`box-shadow: 6px 6px 0 rgba(0,0,0,.45)`) — structure is preserved, only the *hue intensity* drops.
- Diff states in tables use calm green / soft rose / cyan, never screaming red/green.
- Add a faint radial glow (amber top-left, cyan top-right at ~5% opacity) behind the header for the cinematic depth cue.

This variant was extracted from a user request: "make the colour contrasts more pleasant to read, without dropping the style. Wallace Corp / Blade Runner / GITS-like." Treat it as the default when a user signals fatigue with the acid-neon default.

## Tailwind extension

Copy [references/tailwind-extension.js](references/tailwind-extension.js) into your `tailwind.config.js` `theme.extend` block.

## Templates

- [templates/standalone-dashboard.html](templates/standalone-dashboard.html) — single-file dashboard scaffold (header, stat strip, SVG chart, cards, table, footer) with all the cyber-brutalism CSS inlined. Copy and modify.

## Expand/Collapse Toggle for Charts

For dashboards with SVG charts that may not fit the container (ultrawide, dense data), add a brutalist expand toggle. This is a power-user feature — raw function, no polish.

### CSS

```css
/* Expand button — positioned in chart header */
.expand-btn {
  background: transparent; border: 2px solid var(--neon); color: var(--neon);
  padding: 6px 14px; font-family: inherit; font-size: 11px; font-weight: 700;
  text-transform: uppercase; letter-spacing: 0.1em; cursor: pointer;
  box-shadow: 3px 3px 0 var(--neon2); transition: all 60ms linear;
}
.expand-btn:hover { background: var(--neon); color: #000; }

/* Expanded state — fullscreen overlay */
.chart.expanded {
  position: fixed; top: 0; left: 0; right: 0; bottom: 0;
  z-index: 90; margin: 0; overflow: hidden;
  display: flex; flex-direction: column; padding: 24px;
}
.chart.expanded .viz-mount { flex: 1; min-height: 0; display: flex; align-items: center; justify-content: center; }
.chart.expanded svg { max-width: 100%; max-height: 100%; }
```

### JS

```js
// Toggle expand/collapse
document.addEventListener('click', e => {
  const btn = e.target.closest('.expand-btn');
  if (!btn) return;
  const chart = document.getElementById(`chart-${btn.dataset.chart}`);
  const isExpanded = chart.classList.toggle('expanded');
  btn.textContent = isExpanded ? '// COLLAPSE' : '// EXPAND';
});
// ESC to collapse
document.addEventListener('keydown', e => {
  if (e.key !== 'Escape') return;
  const expanded = document.querySelector('.chart.expanded');
  if (!expanded) return;
  expanded.classList.remove('expanded');
  expanded.querySelector('.expand-btn').textContent = '// EXPAND';
});
```

### HTML

```html
<div class="chart" id="chart-01">
  <div class="chart-head">
    <h2>01 // Chart Title</h2>
    <span class="src">// subtitle</span>
    <button class="expand-btn" data-chart="01">// EXPAND</button>
  </div>
  <div class="viz-mount" id="mount-01"></div>
</div>
```

The button text toggles `// EXPAND` ↔ `// COLLAPSE`. ESC collapses. The expanded state uses `position: fixed` to overlay the viewport, with flexbox centering the SVG.
