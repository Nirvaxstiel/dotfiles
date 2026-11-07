# Cyber-Brutalism Glyphs & Visual Elements

Reference sheet of glyphs, Unicode icons, and SVG patterns used in cyber-brutalist designs. All zero-dependency — no icon library needed.

## Unicode Glyphs (HTML-ready)

Used directly in HTML. No SVG, no icon framework. Just paste the character or entity.

### Feature / Capability Icons

| Glyph | Code | Name | Use for |
|-------|------|------|---------|
| `⎇`  | `&#9127;` / `⎇` | Alternative key symbol | branching, routing, agent forks |
| `⧗`  | `&#10775;` / `⧗` | Hourglass | processing, waiting, TUI timing |
| `◰`  | `&#9712;` / `◰` | Square quadrants | sandbox, container, isolation |
| `⚒`  | `&#9874;` / `⚒` | Hammer & pick | tools, build, construction |
| `⌕`  | `&#9109;` / `⌕` | Telephoto / magnify | search, inspect, code intelligence |
| `☷`  | `&#9783;` / `☷` | Trigram earth | LSP, language services, protocols |
| `▤`  | `&#9636;` / `▤` | Square filled UL | playbooks, workflows, automation |
| `⎈`  | `&#9160;` / `⎈` | Helm / Kubernetes | dual-box, distributed, cluster |
| `◷`  | `&#9719;` / `◷` | Circle lower half | sessions, history, persistence |
| `ⓘ`  | `&#9432;` / `ⓘ` | Circled i | info tooltips, footnotes |

### Terminal / CLI Symbols

| Glyph | Use |
|-------|-----|
| `$` | prompt |
| `>` | continuation / output prefix (styled `→` with CSS) |
| `→` `&rarr;` | output arrow, transition |
| `✓` `&#10003;` | success, done |
| `✕` `&#10005;` | close, cancel |
| `☰` `&#9776;` | hamburger menu |
| `#` | comment prefix (styled dim) |
| `&nbsp;` | blank lines in terminal blocks |
| `~` | home directory in paths |
| `>` `_` | logo mark (styled as `>_`) |

### Navigation & Decorations

| Glyph | Use |
|-------|-----|
| `//` | eyebrow labels (`// capabilities`, `// benchmarks`) |
| `★` `&#9733;` | GitHub star CTA |
| `·` `&#183;` | dot separators |
| `—` `&mdash;` | attribution dash |

### ASCII / Box-Drawing Banners

Found in the footer area:

```
┌─────────────────────────────────────────────┐
│    OPEN.    LOCAL.    YOURS.    FOREVER.    │
└─────────────────────────────────────────────┘
```

Characters: `┌` `─` `┐` `│` `└` `┘` (box-drawing U+2500–257F)

## Inline SVGs

### Chevron Arrow (CTA buttons)

```html
<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
  <path d="M5 12h14M13 5l7 7-7 7"/>
</svg>
```

### GitHub Logo (CTA buttons)

```html
<svg viewBox="0 0 24 24" fill="currentColor">
  <path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.43 9.81 8.2 11.4.6.11.82-.26.82-.58v-2.04c-3.34.73-4.04-1.6-4.04-1.6-.55-1.38-1.34-1.75-1.34-1.75-1.09-.74.08-.73.08-.73 1.2.08 1.83 1.24 1.83 1.24 1.08 1.84 2.81 1.31 3.5 1 .11-.78.42-1.31.76-1.61-2.67-.3-5.47-1.33-5.47-5.93 0-1.31.47-2.38 1.24-3.22-.13-.3-.54-1.52.12-3.17 0 0 1.01-.32 3.3 1.23a11.5 11.5 0 0 1 6 0c2.29-1.55 3.3-1.23 3.3-1.23.66 1.65.25 2.87.12 3.17.77.84 1.24 1.91 1.24 3.22 0 4.61-2.81 5.62-5.49 5.92.43.37.81 1.1.81 2.22v3.29c0 .32.22.7.83.58C20.57 21.8 24 17.31 24 12c0-6.63-5.37-12-12-12z"/>
</svg>
```

### Phone Icon (mobile app CTA)

```html
<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <rect x="7" y="2" width="10" height="20" rx="2" ry="2"/>
  <line x1="12" y1="18" x2="12" y2="18.01"/>
</svg>
```

## How Diagrams / Flowcharts Work

No fancy SVG pipeline. They use a dead-simple approach:

1. **Static images** — Architecture diagrams, agent flow, pipeline visuals are exported as JPEG/PNG and embedded with `<img>` tags. Often screenshots of diagrams drawn in other tools (draw.io, Excalidraw, Figma).

2. **HTML tables** for structured comparisons — The competitive landscape and benchmarks are pure `<table>` elements styled with the cyber palette. No chart library.

3. **ASCII art** — Terminal-style banners and decorative elements are literally pre-formatted `<pre>` blocks with box-drawing Unicode characters. Renders perfectly in all browsers.

4. **Terminal blocks** — Fake terminal UIs are just `<div>` with `.terminal-body` containing `<span>` lines. Green prompt, dim comment, white output. Pure HTML/CSS.

## How Animations Work

Also dead simple — no Framer Motion, no GSAP:

1. **CSS transitions** — `transition: opacity 0.15s, background-color 0.1s` on buttons, hover states
2. **IntersectionObserver** — For scroll-reveal: elements start invisible, get a `.reveal` class, Observer adds `.in` class when scrolled into view → CSS animates opacity/transform
3. **CSS-only effects** — Grain overlay is static (no animation needed), blinking cursor uses `@keyframes blink`
4. **Cursor blink** — Terminal cursor at end of command line:
   ```css
   @keyframes blink { 0%, 100% { opacity: 1; } 50% { opacity: 0; } }
   ```

That's it. No WebGL, no canvas, no animation library. The style doesn't need them — the aesthetic IS the raw, minimal motion.

## Key takeaway

The entire visual language fits in a single HTML file with:
- Unicode glyphs instead of an icon library
- Inline SVGs for the 3-4 icons you actually need
- Plain `<table>` for data visualization
- Static images for complex diagrams
- CSS transitions + IntersectionObserver for motion
