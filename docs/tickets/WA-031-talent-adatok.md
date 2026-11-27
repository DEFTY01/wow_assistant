# WA-031 · Talentadatok: a Forever talentfái

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Talentek és spec | M | magas | adat | nyitott |

**Előfeltétel:** nincs  
**Erre épül:** [WA-030](WA-030-spec-felismeres.md), [WA-032](WA-032-talent-hatas-keret.md), [WA-034](WA-034-talent-kalkulator.md)

## Cél

Az addon ismerje a Forever mindhárom talentfáját minden kasztnál: a talentek nevét, helyét, rangjait, előfeltételeit és rangonkénti hatását.

## Miért

A Forevernek saját talentjei vannak (pl. a rogue Efficient Strikes és Coup de Grace talentje), ezért a Classic talentadatai nem használhatók. Ma az addon csak a rogue, a hunter és a shaman néhány talentjét olvassa, kézzel felsorolva.

## Teendők

- [ ] A játékból: a teljes fa a kliens API-jából (`GetTalentTabInfo`, `GetTalentInfo`: név, ikon, sor, oszlop, rang, max. rang; `GetTalentPrereqs`; a tooltip szövege rangonként). Így a talent calculator a Forever valódi fáit mutatja, külső adat nélkül.
- [ ] A hatás számai: forrás a Wowhead Forever (talent-kalkulátor vagy a talentek spell-adatai rangonként). Kutatás: elérhető-e a Forever talent-kalkulátora, és melyik spell-azonosító tartozik egy talent egy rangjához.
- [ ] Build szkript (`scripts/build-talents.mjs`): a Wowhead Forever adatából generált `Talents.lua`, a többi generált fájlhoz hasonlóan a repón kívül (.gitignore).
- [ ] A pontszabályok ellenőrzése Foreverre: hány pont jár szintenként, hány pont kell egy sorhoz.
- [ ] Döntés a `DECISIONS.md`-be: mi jön a kliensből, mi a Wowheadből.

## Elfogadás

- Mind a kilenc kasztnál a játékban kiolvasható a teljes fa, és a generált adat rangonként megadja a hatást forrással.
- Generált adat nem kerül a repóba.
