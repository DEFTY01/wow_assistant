# WA-006 · Rotációs javaslat: közös keret és felület

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Rotációs javaslatok | L | magas | új funkció | nyitott |

**Előfeltétel:** [WA-004](WA-004-szintfuggo-kalibracio.md), [WA-005](WA-005-aura-idovonal.md)  
**Erre épül:** [WA-007](WA-007-rotacio-rogue.md), [WA-008](WA-008-rotacio-warrior.md), [WA-009](WA-009-rotacio-mage.md), [WA-010](WA-010-rotacio-warlock.md), [WA-011](WA-011-rotacio-hunter.md), [WA-012](WA-012-rotacio-shaman.md), [WA-013](WA-013-rotacio-druid.md), [WA-014](WA-014-rotacio-priest.md), [WA-015](WA-015-rotacio-paladin.md), [WA-028](WA-028-bizonyithato-hibak.md)

## Cél

Közös keret, amely minden kasztnak számításokkal alátámasztott rotációt javasol, és összeveti a harcaiddal.

## Miért

Ezt a felhasználó kérte: "Rotációt is javasoljunk minden kasztnak kalkulációkkal". A modellek már tudják a képességek rangját, együtthatóját és költségét; ebből kiszámolható, mi a legjobb sorrend.

## Teendők

- [ ] Új `Rotation.lua`: képességenként sebzés castonként (a kasztmodellből), cast- és GCD-idő, költség, cooldown; ebből sebzés cast-másodpercenként, sebzés manánként / energiánként / rage-enként.
- [ ] Erőforrás-költségvetés: a regenerációból kiszámolni, meddig tartható a sorrend (pl. a mage hány mp alatt fogy ki a manából), és mikor éri meg pálcára vagy olcsóbb rangra váltani.
- [ ] Kimenet: prioritási lista és a várt DPS; a harcaidban mért arányok mellette; a különbség képességenként ("Mind Blast: 3,0/perc, a cooldown 7,5-öt enged: +4,1 DPS").
- [ ] Felület: új "Javasolt rotáció" rész a Harc oldalon, a Haditervben pedig egy rövid összefoglaló. Minden sor mellett a "Honnan a számok" (Wowhead-rang, együttható, mért gyakoriság).
- [ ] Besorolás: a javaslat számítás, nem hiba. Hiba csak a WA-028 szerinti, bizonyított szabállyal.
- [ ] Tesztelhető interfész: a kaszt-ticketek (WA-007 – WA-015) csak a képességlistát és a különleges szabályokat adják hozzá.

## Elfogadás

- Egy példakaszttal (a rogue-gal, WA-007) végig működik: számítás, felület, teszt.
- Minden megjelenített szám visszakövethető forrásra.
- Új teszt: `t_rotation.lua`.

## Megjegyzés

A kaszt-ticketek erre épülnek.
