# WA-009 · Rotációs javaslat: Mage

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Rotációs javaslatok | M | közepes | új funkció | nyitott |

**Előfeltétel:** [WA-006](WA-006-rotacio-keret.md)  
**Erre épül:** nincs

## Cél

A mage kapjon számításokkal alátámasztott rotációt a WA-006 keretében.

## Miért

A kasztmodell már tudja a rangokat, együtthatókat és költségeket; a keret ezekből számol, a kaszt a saját szabályait adja hozzá.

## Teendők

- [ ] Frostbolt, Fireball és Arcane Missiles rangonként: sebzés cast-másodpercenként és manánként.
- [ ] Fire Blast és Frost Nova beszúrása; mikor éri meg alacsonyabb rangú Frostbolt a manáért.
- [ ] Manaköltségvetés: hány harc fér bele egy evésbe/ivásba; pálca a harc végén; Evocation és mana gem, ha a modell ismeri.
- [ ] A javaslat összevetése a harcaid mért arányaival; a különbség DPS-ben.
- [ ] Teszt a kaszt saját tesztfájljában; valódi naplón is, ha van ilyen kasztú harc.

## Elfogadás

- A Harc oldalon megjelenik a "Javasolt rotáció", minden számmal és forrással.
- Minden szabály forrása a Wowhead Forever vagy a WoWSims Forever motor; ami nem ellenőrizhető, az megfigyelés.
