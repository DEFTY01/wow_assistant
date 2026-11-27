# WA-008a · Rotációs javaslat: Warrior – Arms

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 3. Rotációs javaslatok | M | közepes | új funkció | nyitott |

**Előfeltétel:** [WA-006](WA-006-rotacio-keret.md), [WA-032b](WA-032b-talent-warrior.md)  
**Erre épül:** nincs

## Cél

Warrior – Arms: számításokkal alátámasztott rotáció a WA-006 keretében, a karakter szintjén elérhető képességekkel és rangokkal.

## Miért

A spec dönti el, mely képességek és talentek számítanak: két spec rotációja teljesen más lehet. A keret a kaszt modelljéből számol, ez a ticket a spec saját képességeit és szabályait adja hozzá.

## Teendők

- [ ] Mortal Strike cooldownon, Overpower dodge után, Rend, Execute 20% alatt.
- [ ] Heroic Strike rage-küszöbe a meglévő rage-modellből; Sweeping Strikes több célpontra.
- [ ] Kétkezes fegyver; Bloodrage és Charge a rage-túlcsordulás nélkül.
- [ ] A talentek hatása csak akkor kerül a számításba, ha a Wowhead Forever vagy a WoWSims Forever motor igazolja; ami nem ellenőrizhető, az megfigyelés.
- [ ] A javaslat összevetése a harcaid mért arányaival; a különbség DPS-ben.
- [ ] Teszt a kaszt tesztfájljában ezzel a speccel; valódi naplón is, ha van ilyen specű harc.

## Elfogadás

- A Harc oldalon ennél a specnél megjelenik a "Javasolt rotáció", minden számmal és forrással.
- Más spec esetén ez a rotáció nem jelenik meg.
