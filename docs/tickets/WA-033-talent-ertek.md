# WA-033 · Talentérték a jelenlegi gearrel

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Talentek és spec | M | magas | új funkció | nyitott |

**Előfeltétel:** [WA-032](WA-032-talent-hatas-keret.md)  
**Erre épül:** [WA-034](WA-034-talent-kalkulator.md)

## Cél

Minden talentnél kiszámolni, mennyit ér a jelenlegi gearrel: a meglévő rangok értéke, a következő pont értéke, és mire hat még (stat-súlyok, rotáció).

## Miért

A felhasználó kérése: "adni egy kalkulációt, hogy a jelenlegi gearhez az adott talent mennyi mindent befolyásol". A talent értéke a geartől függ: egy crit-sebzést növelő talent többet ér, ha sok a critünk.

## Teendők

- [ ] Talentenként: a modell DPS-e a talenttel és nélküle (a meglévő rangok értéke), és egy ranggal több (a következő pont értéke), DPS-ben és százalékban.
- [ ] Mire hat még: hogyan változnak a stat-súlyok a talent miatt (pl. a talent miatt az agility X-szel többet ér), és mely képességek sebzése vagy költsége változik.
- [ ] A következő pont ajánlása: melyik elérhető talent ér a legtöbbet most (a sor- és előfeltétel-szabályokkal).
- [ ] Tank és gyógyító specnél: amíg nincs tank- és gyógyítómodell (WA-017, WA-023), a talent a hatásával jelenik meg (pl. +3% parry), érték nélkül, és ezt ki is írja.
- [ ] A Felszerelés oldalon egy rövid sor: a talentjeid miatt melyik stat ér többet vagy kevesebbet.
- [ ] Tesztek: a talent értéke a gearrel együtt változik.

## Elfogadás

- Minden számolt talentnél látszik a jelenlegi és a következő pont értéke, a forrással.
- A stat-súlyok a talentekkel együtt számolódnak mindenhol (gear, enchant, terv).
