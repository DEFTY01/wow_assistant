# WA-012b · Rotációs javaslat: Shaman – Enhancement

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 3. Rotációs javaslatok | M | közepes | új funkció | nyitott |

**Előfeltétel:** [WA-006](WA-006-rotacio-keret.md), [WA-032f](WA-032f-talent-shaman.md)  
**Erre épül:** nincs

## Cél

Shaman – Enhancement: számításokkal alátámasztott rotáció a WA-006 keretében, a karakter szintjén elérhető képességekkel és rangokkal.

## Miért

A spec dönti el, mely képességek és talentek számítanak: két spec rotációja teljesen más lehet. A keret a kaszt modelljéből számol, ez a ticket a spec saját képességeit és szabályait adja hozzá.

## Teendők

- [ ] Stormstrike (8 mp, Forever), Earth Shock és Flame Shock a közös cooldownnal.
- [ ] Fegyver-imbue összehasonlítása számmal: Rockbiter, Flametongue, Windfury.
- [ ] Totemek: melyik ad mérhető DPS-t, és mennyi mana.
- [ ] A talentek hatása csak akkor kerül a számításba, ha a Wowhead Forever vagy a WoWSims Forever motor igazolja; ami nem ellenőrizhető, az megfigyelés.
- [ ] A javaslat összevetése a harcaid mért arányaival; a különbség DPS-ben.
- [ ] Teszt a kaszt tesztfájljában ezzel a speccel; valódi naplón is, ha van ilyen specű harc.

## Elfogadás

- A Harc oldalon ennél a specnél megjelenik a "Javasolt rotáció", minden számmal és forrással.
- Más spec esetén ez a rotáció nem jelenik meg.
