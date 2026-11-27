# WA-033 · Talentérték a jelenlegi gearrel

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Talentek és spec | M | magas | új funkció | kész (2.29.0) |

**Előfeltétel:** [WA-032](WA-032-talent-hatas-keret.md)  
**Erre épül:** [WA-034](WA-034-talent-kalkulator.md)

## Cél

Minden talentnél kiszámolni, mennyit ér a jelenlegi gearrel: a meglévő rangok értéke, a következő pont értéke, és mire hat még (stat-súlyok, rotáció).

## Miért

A felhasználó kérése: "adni egy kalkulációt, hogy a jelenlegi gearhez az adott talent mennyi mindent befolyásol". A talent értéke a geartől függ: egy crit-sebzést növelő talent többet ér, ha sok a critünk.

## Teendők

- [x] Talentenként: a modell DPS-e a talenttel és nélküle (a meglévő rangok értéke), és egy ranggal több (a következő pont értéke), DPS-ben és százalékban.
- [x] Mire hat még: hogyan változnak a stat-súlyok a talent miatt (pl. a talent miatt az agility X-szel többet ér), és mely képességek sebzése vagy költsége változik.
- [x] A következő pont ajánlása: melyik elérhető talent ér a legtöbbet most (a sor- és előfeltétel-szabályokkal).
- [x] Tank és gyógyító specnél: amíg nincs tank- és gyógyítómodell (WA-017, WA-023), a talent a hatásával jelenik meg (pl. +3% parry), érték nélkül, és ezt ki is írja.
- [x] A Felszerelés oldalon egy rövid sor: a talentjeid miatt melyik stat ér többet vagy kevesebbet.
- [x] Tesztek: a talent értéke a gearrel együtt változik.

## Elfogadás

- Minden számolt talentnél látszik a jelenlegi és a következő pont értéke, a forrással.
- A stat-súlyok a talentekkel együtt számolódnak mindenhol (gear, enchant, terv).

## Eredmény (2.29.0)

- `Talent.lua`: `T.Values` minden talentre, amiben pontod van, és amibe a következő pontot teheted:
  - a meglévő rangok értéke: a modell DPS-e a talenttel, mínusz nélküle (DPS-ben és százalékban);
  - a következő pont értéke: egy ranggal több, mínusz a mostani;
  - a forrás: a rang Wowhead Forever szövege.
- A karakterlapon már benne lévő talenteknél (pl. crit, hit) a modell a lap számából is levonja a talent részét (`T.Variant`), különben ezek 0-t érnének. Formához kötött talentnél (Sharpened Claws, Moonkin Form) csak akkor, ha a lapot abban a formában olvasta; iskolás critnél (Critical Mass, Malevolence, Holy Specialization) csak akkor, ha a két iskola critjének különbsége mutatja, hogy a lapon van. Ahol a lap részét a modell nem tudja kivonni (Mental Quickness, Champion of the Light, Demonic Knowledge, Trueshot Aura), ott kiírja, hogy az érték kisebb a valódinál.
- Mire hat még: a stat-súlyok változása talenttel és nélküle (agility, strength, attack power, crit, intellect, spell power), ahol a különbség legalább 0,05 DPS és 3%.
- A legtöbbet érő következő pont: csak a nyitott talentek közül (a fában elég pont van, és az előfeltétel-talent megvan), a szabad pontokat a játék adja (UnitCharacterPoints).
- `/wa talent`: a számolt talentek alatt a mostani és a következő pont értéke, a stat-súlyok változása, a végén a legtöbbet érő következő pont. A nem számolt (tank, gyógyító…) talentek a hatásukkal és az okkal szerepelnek, érték nélkül.
- Felszerelés oldal: egy sor a modell megjegyzései között, hogy a talentjeid miatt melyik stat mennyit ér (talentek nélkül → velük). Csak akkor számolódik újra, ha a szint, a gear, a talentek vagy a harcok változnak.
- Teszt (t_talents, t_shaman): a talent értéke a gearrel együtt változik (több spell crittel az Elemental Fury többet ér), a mélyebb talent nem nyitott kevés ponttal, a karakterlapos talent is ér valamit, a Holy Specialization ugyanannyit ér, akár a lapon van, akár a modell adja hozzá, a Mental Dexterity és a Careful Aim az intellectet teszi értékesebbé.
