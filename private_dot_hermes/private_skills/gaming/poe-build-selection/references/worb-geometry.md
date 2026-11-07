# WORB Geometry & Simulation (durable)

Winter Orb (WORB) was "consistently bad for years" then buffed; in 3.29 it gains a never-before
angle via Bloodline classes. The user simulated the 3.29 version in PoB with custom mods.

## Overlap (the #1 scalar — beats any % damage gem)
- WORB projectiles arrange along a LINE between you and the target, NOT a cluster. Extra
  projectiles past the soft cap start missing the boss.
- Overlap is RADIUS-gated, not projectile-count-gated. Need ~210% increased AoE ~= 2.6m radius
  for consistent 5-overlap (shotgun). Each explosion that lands on the target = ~x5 damage. A 20%
  more gem ~= +20%; going 1->5 overlap ~= +400%.
- Soft cap = 5 projectiles for single-target. Dying Sun (4 proj @ 30% AoE) ~= GMP (5 proj @ 75%
  strength) on paper; Dying Sun wins because its 30% AoE guarantees overlap of all 4.
- Conc Effect = tighter line -> higher effective overlap per unit, but worse clear. Use on
  single-target after hitting the radius threshold.
- Distance: WORB hits HARDER further away (line needs room to spread) -- not point-blank.
- Standing still (Expansive Might +50% AoE) is the buffer to clear the 2.6m threshold on bosses.

## Quality-as-projectiles (user's sim model -- NOT in parsed notes)
- User modeled WORB quality granting +projectiles: 30% qual (blue socket) -> 4 proj (4.5 round
  down). + Beidat (+3) = 7 total, but overlap caps at 5. So GMP is skipped (proj past 5 waste a
  linkslot) and the 6th link is Conc Effect instead.
- This quality-grants-projectiles behavior is the USER's simulation assumption. 3.29.json has NO
  WORB row (confirmed empty), so it is not source-verified. Label as assumed.

## Lycia + Beidat (separate mechanics, user-clarified)
**Lycia** = the Bloodline Class (player ascendancy-side, NOT a gem). Grants 67% ele→chaos
(unchanged this patch → not in our parsed JSON; label ASSUMED). **Pact of Beidat** = a separate
Exceptional Gem that sits under Lycia for lore purposes — mechanically independent. Don't
conflate the two; model them as separate custom-mod blocks. Beidat empowers projectile/area/
chaining-beam spells:

- 25% more Damage
- 16% more Area of Effect
- +1.5% to Critical Strike Chance
- Adds 0 to 89 Cold Damage
- Skills Fire 3 additional Projectiles

- The AoE line = "enhanced coverage." It aids CLEAR (wider spread) but does NOT raise single-target
  overlap past the 5-cap (that's radius-gated). Keep the character's 210% inc AoE on tree/gear.
- The Affliction is permanent (the cost of the gem, not a buff that expires). Add a placeholder
  downside (e.g. -12% max Life) or wait for GGG's value. Don't model it as temporary.

## Full-chaos conversion path (Tier-2 endgame)
- Lycia Bloodline: 67% of ele→chaos. Nightmare jewels convert the remaining ~33%.
- Full chaos + pink flask (Petrified Blood / Coruscating Elixir style) + chaos-res capped =
  Low Life WITHOUT Shavronne's Wrappings (dodges the 6-link chest tax).
- Occultist chaos wheel is dense → easy chaos cap. Void Battery stays viable (charge-stack
  scaling doesn't conflict with conversion).

## Spirit Infusion (real, parsed asc 3.29) -- the build's backbone
New notable: "gain Spirit Infusion/s while Channelling (max 5); ES recharge start, +dmg, +cost."
Modeled as: Channelling Skills deal 50% more Damage (5 stacks x 10%). This is the single biggest
scalar that makes 3.29 WORB viable vs prior "bad" leagues. It is a REAL parsed fact, not assumed.

## Sustain
- WORB ES-cost can be moved to mana via Eldritch Battery + Occultist always-regen -> ES Regen "red"
  in PoB is a pre-EB artifact. Once EB slotted, cost is mana, not ES. Non-issue.
- Caster-channel + EB + MoM + cap-block is a coherent LL second tier.

## Validated baseline (user's PoB screenshot, ~3.9M hit DPS, T16-ready)
- AoE 2.8m (cleared 2.6m threshold), Hit Rate 5.4 (5-overlap live), Crit 92%/477% (no double-roll
  / no Instruments -- those are Assassin, not Occy), Avg Hit ~724K, DPS ~3.9M.
- With Full DPS ×5 overlap: ~20M effective. Exposure adds free damage. Tornado/Hydrosphere can
  add secondary hit events on top of the 5-overlap foundation.
- Soft spots: Chaos res 18% / Chaos Max Hit 14.3K (death source -- Circle of Fear ring gives the
  chaos-res implicit, so keep it), Phys Max Hit 22.8K (low for the boss simmed).
- Free belt slot = flex for the LL transition.

## Source discipline
- Overlap geometry = community/POB-verified (soft signal, not from our parsed notes).
- Beidat exact %, quality-grants-projectiles, Lycia 67% = ASSUMED (Bloodline unchanged → not in notes).
- Spirit Infusion, double-roll-crit-why-its-Assassin = REAL parsed (asc/features).
