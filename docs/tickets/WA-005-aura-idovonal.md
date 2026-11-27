# WA-005 · Aura-idővonal a harcnaplóból

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 1. Alapok (adat, kalibráció, spec) | M | magas | adat | nyitott |

**Előfeltétel:** nincs  
**Erre épül:** [WA-006](WA-006-rotacio-keret.md), [WA-028](WA-028-bizonyithato-hibak.md)

## Cél

A feldolgozó ne csak az aurák összidejét rögzítse, hanem a be- és kikapcsolás időpontjait is, a castokkal közös idővonalon.

## Miért

A rotációs javaslatok és az új bizonyítható hibák kérdései időpontokról szólnak: fent volt-e a Slice and Dice, amikor lejárt; melyik seal volt fent a Judgementnél; fent volt-e a Shadow Word: Pain a Mind Flay alatt. Ma csak az összidő van meg.

## Teendők

- [ ] `scripts/combat-log.mjs`: harconként `auraLog = { { t, name, on/off } }` a saját BUFF-okra és a célponton lévő saját DEBUFF-okra (DoT-ok, Sunder Armor, Faerie Fire).
- [ ] Feltöltő és `Fights.lua`: a mező továbbítása, méretkorláttal.
- [ ] `Combat.lua`: segédfüggvény: "fent volt-e X a t időpontban", "mennyi idő telt el a lejárattól az újrarakásig".
- [ ] Tesztek valódi naplórészlettel.

## Elfogadás

- A rogue Slice and Dice és a priest SW:P uptime ugyanazt adja az idővonalból, mint az összidőből.
- A régi `Fights.lua` (idővonal nélkül) is működik.
