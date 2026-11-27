# WA-007b · Rotációs javaslat: Rogue – Combat

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 3. Rotációs javaslatok | M | közepes | új funkció | nyitott |

**Előfeltétel:** [WA-006](WA-006-rotacio-keret.md), [WA-032a](WA-032a-talent-rogue.md)  
**Erre épül:** nincs

## Cél

Rogue – Combat: számításokkal alátámasztott rotáció a WA-006 keretében, a karakter szintjén elérhető képességekkel és rangokkal.

## Miért

A spec dönti el, mely képességek és talentek számítanak: két spec rotációja teljesen más lehet. A keret a kaszt modelljéből számol, ez a ticket a spec saját képességeit és szabályait adja hozzá.

## Teendők

- [ ] Sinister Strike energiánként a normalizált fegyversebességgel; két fegyver és a mellékkéz.
- [ ] Slice and Dice és Eviscerate combo pontonként (a bizonyított Eviscerate-szabállyal összhangban).
- [ ] Shank (10 mp, Forever), Blade Flurry, Adrenaline Rush: mikor és milyen harcban.
- [ ] A talentek hatása csak akkor kerül a számításba, ha a Wowhead Forever vagy a WoWSims Forever motor igazolja; ami nem ellenőrizhető, az megfigyelés.
- [ ] A javaslat összevetése a harcaid mért arányaival; a különbség DPS-ben.
- [ ] Teszt a kaszt tesztfájljában ezzel a speccel; valódi naplón is, ha van ilyen specű harc.

## Elfogadás

- A Harc oldalon ennél a specnél megjelenik a "Javasolt rotáció", minden számmal és forrással.
- Más spec esetén ez a rotáció nem jelenik meg.
