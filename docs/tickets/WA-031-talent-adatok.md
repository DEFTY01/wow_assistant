# WA-031 · Talentadatok: a Forever talentfái

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Talentek és spec | M | magas | adat | kész (2.18.0) |

**Előfeltétel:** nincs  
**Erre épül:** [WA-030](WA-030-spec-felismeres.md), [WA-032](WA-032-talent-hatas-keret.md), [WA-034](WA-034-talent-kalkulator.md)

## Cél

Az addon ismerje a Forever mindhárom talentfáját minden kasztnál: a talentek nevét, helyét, rangjait, előfeltételeit és rangonkénti hatását.

## Miért

A Forevernek saját talentjei vannak (pl. a rogue Efficient Strikes és Coup de Grace talentje), ezért a Classic talentadatai nem használhatók. Ma az addon csak a rogue, a hunter és a shaman néhány talentjét olvassa, kézzel felsorolva.

## Teendők

- [x] A játékból: a teljes fa a kliens API-jából (`GetTalentTabInfo`, `GetTalentInfo`: név, ikon, sor, oszlop, rang, max. rang; `GetTalentPrereqs`; a tooltip szövege rangonként). Így a talent calculator a Forever valódi fáit mutatja, külső adat nélkül.
- [x] A hatás számai: forrás a Wowhead Forever (talent-kalkulátor vagy a talentek spell-adatai rangonként). Kutatás: elérhető-e a Forever talent-kalkulátora, és melyik spell-azonosító tartozik egy talent egy rangjához.
- [x] Build szkript (`scripts/build-talents.mjs`): a Wowhead Forever adatából generált `Talents.lua`, a többi generált fájlhoz hasonlóan a repón kívül (.gitignore).
- [ ] A pontszabályok ellenőrzése Foreverre: hány pont jár szintenként, hány pont kell egy sorhoz.
- [x] Döntés a `DECISIONS.md`-be: mi jön a kliensből, mi a Wowheadből.

## Elfogadás

- Mind a kilenc kasztnál a játékban kiolvasható a teljes fa, és a generált adat rangonként megadja a hatást forrással.
- Generált adat nem kerül a repóba.

## Eredmény (2.18.0)

- Forrás: a Wowhead Forever talent-kalkulátorának adatfájlja (`nether.wowhead.com/forever/data/talents-classic`, a kalkulátor oldaláról kikeresve). 27 fa, 467 talent, minden ranghoz szöveggel; a fák szerepe (sebző, tank, gyógyító) is benne van.
- `scripts/build-talents.mjs` → `TalentData.lua` (generált, a repón kívül, a kiadásban kötelező fájl).
- `Talent.lua`: a teljes fa a kliensből, párosítás név szerint, eltérések; `/wa talent`.
- D12 a `DECISIONS.md`-ben.
- Nyitva maradt: a szintenkénti pontszabály. A játék megmondja az elköltött és a szabad pontokat (a `/wa talent` kiírja), ebből a jelenlegi szintre pontos; más szintekre a szabályt a talent-kalkulátornál (WA-034) kell igazolni.
- Játékban még nincs kipróbálva: a `/wa talent` kimenete mutatja meg, hogy a Wowhead adata mind a kilenc kasztnál egyezik-e a játékkal.
