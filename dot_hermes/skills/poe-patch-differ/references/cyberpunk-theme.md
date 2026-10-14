# Neo-brutalist / Cyberpunk web theming — research bank

User asked for a neo-brutalist + cyberpunk refresh of the differ. Compiled from 2025–2026 design
sources (Design Signal, Lucky Graphics, NN/g, neubrutalism.com, cybercore-css, cyberpunk-ui,
shadcn cyberpunk, DESIGN.md cyberpunk entries). Condensed for reuse.

## Two aesthetics, distinct DNA

**Neo-brutalism** (reaction to "Apple-grey" minimalism; the "anti-AI signal" — looks hand-built):
- Hard offset shadows, NO blur: `box-shadow: 4px 4px 0 0 #000` (use `var(--line)` here).
- Thick borders (2–3px solid), `border-radius: 0` (sharp corners).
- Mechanical transitions: `transition: all .08s step-start` (no ease-in-out).
- Hover: element lifts + shadow grows. Active: sinks + shadow vanishes (`transform: translate(2px,2px)`).
- Oversized bold display type; monospace for data/technical rows.
- Limit palette: 2–3 high-contrast colors (B&W + 1–2 accents). No gradients.
- Accessibility: high-contrast is inherently AAA; focus state = thick magenta/amber border, not subtle ring.

**Cyberpunk** (Blade Runner / Akira terminal culture):
- Void-dark backgrounds (`#0a0a0f` / `#050512`).
- Neon accents: cyan `#00f0ff`, magenta `#ff2a6d`, acid green `#39ff14`, cyber yellow `#fcee0a`,
  electric purple `#bd00ff`.
- Subtle neon glow on interactive elements: `box-shadow: 0 0 8px rgba(0,240,255,.4)`.
- Monospace for data; scanline/grid textures optional.
- "No pure white backgrounds; no oversaturated accents >80% saturation" (DESIGN.md rule).

## The merge that works (cyber-brutalism)

Combine: dark void base + neon accents + hard brutalist shadows + thick borders + sharp corners +
mechanical hover + selective glow. DO NOT soften shadows back to blur, DO NOT round corners.

Reference palette adopted for the differ (`:root` vars):
```
--bg:#0a0a0f; --bg2:#111118; --ink:#e8eaed; --dim:#6b7280; --line:#1e293b;
--amber:#fcee0a; --cyan:#00f0ff; --magenta:#ff2a6d; --rose:#ff6b9d; --green:#39ff14; --violet:#bd00ff;
```
Badge glow halos per type: `box-shadow:0 0 6px <neon>` on `.b-buff/.b-nerf/.b-chg/.b-new`.
Version badges in magenta; "latest" gets amber + `box-shadow:0 0 6px rgba(252,238,10,.3)`.
Neon scrollbar gradient (cyan → magenta), `border-radius:0`.

## Source links (authoritative)
- Neo-brutalism 2026 (Lucky Graphics): hard shadows, exposed gridlines, accessibility.
- NN/g Neobrutalism best practices: limit palette, whitespace, test interactions.
- neubrutalism.com: the definitive guide; "cyber-brutalism" = glitch + dark + neon + mono.
- cybercore-css (GitHub sebyx07): pure-CSS cyberpunk framework, exact palette above.
- cyberpunk-ui (rintran720): Tailwind v4 neon tokens, glow shadows, scanline/grid effects.
- shadcn cyberpunk theme: "neon isn't subtle and doesn't pretend to be."

## Why this trend (context for the user)
User noticed "latest fable models" and AI design templates converging on this look. It reads as a
"made by a human, not a model" signal against AI-generated sameness — which is exactly why
neo-brutalism is durable as a grammar even if maximal forms are trendy.
