# WA-034 · Talent calculator a játékban

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Talentek és spec | L | magas | új funkció | nyitott |

**Előfeltétel:** [WA-031](WA-031-talent-adatok.md), [WA-033](WA-033-talent-ertek.md)  
**Erre épül:** nincs

## Cél

Új "Talentek" oldal a `/wa` ablakban: a Forever talentfái, a jelenlegi pontjaid, és tervezés, minden talenthez az értékével a jelenlegi gearrel.

## Miért

A felhasználó kérése: "kell egy talent calculator in-game a játékba". A Talentek oldal mutatja meg egy helyen, mit ad egy build, és melyik pont ér a legtöbbet.

## Teendők

- [ ] Három fa a kliens adataiból (ikon, sor, oszlop, rang/max. rang, előfeltétel-nyilak), WoW-stílusú ablakban, magyar felülettel.
- [ ] Tooltip: a játék saját talent-leírása, alatta a Waystone számítása: a jelenlegi rangok és a következő pont értéke, mire hat (WA-033), és a forrás.
- [ ] Tervezés: kattintással pont hozzáadása és elvétele egy tervben, a szabályokkal (szintenkénti pontok, soronként szükséges pontok, előfeltételek); a terv DPS-e a jelenlegihez képest, és a különbség forrásonként.
- [ ] A legjobb következő pont kiemelése; több terv mentése karakterenként; terv megosztása szövegként.
- [ ] A terv csak terv: az addon nem tanul talentet, azt a játék talent-ablakában te teszed meg.
- [ ] Teszt: `t_talents.lua` kitalált fával (szabályok, érték, mentés), és a rajzolás a meglévő UI-tesztekben.

## Elfogadás

- A Talentek oldal mind a kilenc kasztnál megnyílik a valódi Forever-fákkal.
- Egy tervben a pontszabályok érvényesek, és a terv DPS-e számmal és forrással látszik.
