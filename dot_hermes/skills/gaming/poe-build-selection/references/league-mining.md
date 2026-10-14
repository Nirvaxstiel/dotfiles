# Mining a New League's Notes for a Novel Build Angle

The repo ships per-league patch-note JSON (leagues/<ver>/<ver>.json) with a meta block and
sections[] (each id, title, rows[] with k/old/neu/t). To find a build the user has NOT played,
mine these for NEW mechanics and cross-reference against their exclusion log.

## Where to look
- sections[].id values of interest for build-selection:
  - features -> New Content & Features (Bloodline Classes, Exceptional Gems/Supports, new skills).
  - asc -> Ascendancy reworks / new notables (CONFIRM the notable's home ascendancy -- see
    pitfalls: double-roll crit + "Base Spell Crit = MH weapon" are Assassin, not Occy).
  - skills / skills2 -> skill gem buffs/nerfs (radius, crit, proj, damage effectiveness changes).
  - uniq / items -> new uniques or modifier-tier shifts that enable a shell.
  - reliq-nodes / lum-nodes -> the new Ascendancy node lists (full text in rows).
- meta -> version, league name, author, source thread, posted/launch dates (cite the source).

## Proven angle from 3.29 (WORB example)
- features rows: "Empowers projectile/area/chaining-beam spells (more damage, enhanced coverage)
  but burdens you with an Affliction" (Beidat) and "Empowers next channelling spells (more damage,
  periodic lightning while channelling). Affliction." (Lycia). These are Bloodline Classes =
  gem transforms, NEW in 3.29.
- asc row: "Critical Strike Chance is rolled twice; if either roll succeeds..." -- confirmed
  Assassin, NOT a generic buff. This is why an Occultist WORB does NOT get double-roll crit.
- A 3.29-specific empowerment applied to an old skill = a legitimate novel angle even if the skill
  itself is familiar. State this so the user can veto.

## Exclusion cross-reference
- Get the user's multi-league build log FIRST (old machine may have more than current).
- Map each league's rows to archetypes and strike any the user has played (including variants).
- Whole classes absent from their log (e.g. slams/melee across 13 leagues) are prime novel picks.

## Source discipline
- Ground claims in the parsed JSON. If a value is absent, say "no WORB row in 3.29.json" -- don't
  invent.
- GGG-unpublished numbers (Bloodline class exact %, Affliction downside) -> ASSUMED in any sim.
- Community/POB geometry -> soft signal.
