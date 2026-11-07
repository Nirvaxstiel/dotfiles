---
name: poe-build-selection
description: "Select a Path of Exile league starter (or league #2 fund build) under the user's hard rule 'never play the same build twice' — cross-reference their multi-league build log, mine the parsed patch notes for a novel angle, then validate via PoB custom-mod simulation. Gameplay selection, NOT tooling (see poe-patch-differ for the differ SPA)."
---

# POE Build Selection

Pick a league starter (or a league #2 fund build) for this user. The governing constraint is
**never repeat a build** — the user keeps a running build log across many leagues (old machine +
current) and will reject any archetype they've already played. Fun > raw power ("balance
negotiable, fun is not" — confirmed user stance).

## The never-repeat rule (HARD)
- Before proposing, get the user's recent build history. They log per-league
  (e.g. `3.23 lancing steel MF HH DeadEye`, `3.28 azadi glad flicker`,
  `3.28 spark chaos charlatan sword shrine stacking`). The OLD machine has MORE history than the
  current one — ask if unsure which they've played.
- Exclude every archetype they've touched, including variants ("TS — cold conv phys, triple ele,
  corrupting blood" all count as TS done).
- A build is "repeated" if the *core mechanic/archetype* matches, even on a different ascendancy.
  Whole classes absent from their log (e.g. slams/melee across 13 leagues) are fair game.
- Novelty can also come from a **new league mechanic** applied to a familiar shell
  (e.g. WORB + 3.29's Spirit Infusion/Bloodline = never existed before, so not a repeat even if
  WORB-adjacent). State this reasoning so they can veto.

## Workflow
1. **Enumerate + exclude.** Build the exclusion set from their log. State it back so they correct.
2. **Mine the parsed notes for a novel angle.** The repo has per-league JSON
   (`leagues/<ver>/<ver>.json`) with `meta` + `sections`. Grep/read the JSON for new notables,
   new gems, new classes (Bloodline classes in 3.29), reworks. A league-specific empowerment
   (e.g. "Empowers projectile/area/chaining-beam spells") is a legit novel angle for an old skill.
3. **Propose 2-3 candidates** ranked by novelty + fund-fit (cheap to start, liquidates clean if
   it's a fund/league-#1).
4. **Simulate in PoB via custom mods** (see below). The user runs Path of Building and pastes
   screenshots — read the stats, critique defenses, find the upgrade path.
5. **Verify the transition plan.** If build #1 funds build #2, confirm gear either liquidates or
   banks into #2's kit. Flag suffix/gear collisions early (see pitfalls).

## Source discipline (matches poe-patch-differ's objectivity)
- Ground every mechanical claim in the **parsed patch notes** (`leagues/<ver>/<ver>.json`), not dev
  vibes. If a note is absent there, say so.
- GGG-unpublished numbers (Bloodline class exact values, Affliction downside) → label **ASSUMED**
  in any sim. Don't present as fact.
- Community/POB geometry (overlap math, conversion order) → **soft signal**; useful, not from notes.
- The user enforces this themselves ("dev statements = soft signals"). Match it.

## PoB custom-mod simulation (how the user works)
They hardcode transforms as Custom Modifiers and iterate. Patterns that worked:
- Model a **Bloodline Class** (e.g. Lycia) as a modifier block on the skill gem:
  `+N additional Projectiles`, `% more Area of Effect`, `% more Damage`, `+crit`, `Adds X to Y cold`.
  Values are ASSUMED until GGG publishes.
- **Lycia is the Bloodline Class** (player ascendancy-side, not a gem). Pact of Beidat is a
  separate Exceptional Gem that sits under Lycia for lore purposes — mechanically independent.
  Don't conflate the two; model them as separate custom-mod blocks.
- **Bloodline classes that didn't change this patch won't appear in our parsed JSON.** If a
  Bloodline is unchanged, its exact values (e.g. Lycia's 67% ele→chaos) are unsourceable from
  our notes — label ASSUMED and note "not in patch notes (unchanged)".
- Model **new notables** (e.g. "Spirit Infusion while Channelling, max 5") as a channelling-damage
  custom mod: `Channelling Skills deal 50% more Damage` (5 stacks × 10%).
- The **Affliction downside is permanent** (not a buff that expires) — include a placeholder
  downside or wait for the real value. Don't model it as a temporary debuff.

## Pitfalls (gameplay)
- **Cross-ascendancy notables don't transfer.** Double-roll crit + "Base Spell Crit = MH weapon"
  (Instruments of Virtue) are **Assassin**, not Occultist. Don't assume an ascendancy gets another's
  signature notable — confirm the notable's home ascendancy from the parsed `asc` section.
- **WORB overlap is radius-gated, not projectile-gated.** Past ~5 projectiles the extras miss (line
  arrangement). Need ~210% increased AoE (2.6m radius) for 5-overlap. More projectiles without that
  radius = wasted. See `references/worb-geometry.md`.
- **Conversion order.** Nightmare jewels convert a % of *remaining* ele→chaos; they don't stack
  multiplicatively and don't re-convert. Verify total reaches 100% in PoB's conversion order before
  committing to a full-chaos build.
- **LL-without-Shavronne is a real path.** Full chaos conversion + a chaos/pink flask
  (Petrified Blood / Coruscating Elixir style) + chaos-res capped can enable Low Life WITHOUT
  Shavronne's Wrappings (dodges the 6-link chest tax). Keep the belt/flex slot open for the suffix
  puzzle.
- **Suffix overload in transitions.** LL + EB + MoM + cap-block + chaos-res + conversion jewels
  compete for suffixes/jewel-sockets. Decide anchor uniques early so the suffix puzzle stays solvable.
  The free belt slot is the release valve — don't fill it prematurely.
- **FE/FF (Forbidden Flame/Flesh) as placeholder** do nothing until you pick the notable — don't
  credit them in the DPS read.

## When to use
- "What should I play this league?" / "pick me a build" / "build #2 after I fund it".
- The user pastes PoB screenshots and wants critique (defense gaps, upgrade path, transition plan).
- Mining a new league's notes for viable novel builds.

## Files
- `references/worb-geometry.md` — durable WORB mechanics (overlap, Spirit Infusion, Beidat modeling).
- `references/league-mining.md` — how to extract novel build angles from the parsed patch-note JSON.
