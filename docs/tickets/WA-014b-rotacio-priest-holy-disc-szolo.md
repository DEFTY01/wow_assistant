# WA-014b · Rotációs javaslat: Priest – Holy és Discipline (szólózás)

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Rotációs javaslatok | M | közepes | új funkció | nyitott |

**Előfeltétel:** [WA-006](WA-006-rotacio-keret.md)  
**Erre épül:** nincs

## Cél

Priest – Holy és Discipline (szólózás): számításokkal alátámasztott rotáció a WA-006 keretében, a karakter szintjén elérhető képességekkel és rangokkal.

## Miért

A spec dönti el, mely képességek és talentek számítanak: két spec rotációja teljesen más lehet. A keret a kaszt modelljéből számol, ez a ticket a spec saját képességeit és szabályait adja hozzá.

## Teendők

- [ ] Szólózás gyógyító speccel: Shadow Word: Pain, Smite, Holy Fire nyitásként, Mind Blast.
- [ ] A Forever saját varázslatai: Starshards, Penance (Wowhead Forever: rang, együttható, cooldown).
- [ ] Mana: Power Word: Shield költsége, pálca a harc végén.
- [ ] A talentek hatása csak akkor kerül a számításba, ha a Wowhead Forever vagy a WoWSims Forever motor igazolja; ami nem ellenőrizhető, az megfigyelés.
- [ ] A javaslat összevetése a harcaid mért arányaival; a különbség DPS-ben.
- [ ] Teszt a kaszt tesztfájljában ezzel a speccel; valódi naplón is, ha van ilyen specű harc.

## Elfogadás

- A Harc oldalon ennél a specnél megjelenik a "Javasolt rotáció", minden számmal és forrással.
- Más spec esetén ez a rotáció nem jelenik meg.

## Megjegyzés

A gyógyítás a WA-018-ban.
