# WA-006 · Rotációs javaslat: közös keret és felület

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Rotációs javaslatok | L | magas | új funkció | nyitott |

**Előfeltétel:** [WA-004](WA-004-szintfuggo-kalibracio.md), [WA-005](WA-005-aura-idovonal.md), [WA-030](WA-030-spec-felismeres.md)  
**Erre épül:** [WA-007a](WA-007a-rotacio-rogue-assassination.md), [WA-007b](WA-007b-rotacio-rogue-combat.md), [WA-007c](WA-007c-rotacio-rogue-subtlety.md), [WA-008a](WA-008a-rotacio-warrior-arms.md), [WA-008b](WA-008b-rotacio-warrior-fury.md), [WA-009a](WA-009a-rotacio-mage-arcane.md), [WA-009b](WA-009b-rotacio-mage-fire.md), [WA-009c](WA-009c-rotacio-mage-frost.md), [WA-010a](WA-010a-rotacio-warlock-affliction.md), [WA-010b](WA-010b-rotacio-warlock-demonology.md), [WA-010c](WA-010c-rotacio-warlock-destruction.md), [WA-011a](WA-011a-rotacio-hunter-bm.md), [WA-011b](WA-011b-rotacio-hunter-mm.md), [WA-011c](WA-011c-rotacio-hunter-survival.md), [WA-012a](WA-012a-rotacio-shaman-elemental.md), [WA-012b](WA-012b-rotacio-shaman-enhancement.md), [WA-013a](WA-013a-rotacio-druid-balance.md), [WA-013b](WA-013b-rotacio-druid-feral-cat.md), [WA-014a](WA-014a-rotacio-priest-shadow.md), [WA-014b](WA-014b-rotacio-priest-holy-disc-szolo.md), [WA-015a](WA-015a-rotacio-paladin-ret.md), [WA-015b](WA-015b-rotacio-paladin-holy-prot-szolo.md), [WA-028](WA-028-bizonyithato-hibak.md)

## Cél

Közös keret, amely minden spec számára számításokkal alátámasztott rotációt javasol, és összeveti a harcaiddal.

## Miért

Ezt a felhasználó kérte: "Rotációt is javasoljunk minden kasztnak kalkulációkkal". A modellek már tudják a képességek rangját, együtthatóját és költségét; ebből kiszámolható, mi a legjobb sorrend.

## Teendők

- [ ] Új `Rotation.lua`: képességenként sebzés castonként (a kasztmodellből), cast- és GCD-idő, költség, cooldown; ebből sebzés cast-másodpercenként, sebzés manánként / energiánként / rage-enként.
- [ ] Erőforrás-költségvetés: a regenerációból kiszámolni, meddig tartható a sorrend (pl. a mage hány mp alatt fogy ki a manából), és mikor éri meg pálcára vagy olcsóbb rangra váltani.
- [ ] Kimenet: prioritási lista és a várt DPS; a harcaidban mért arányok mellette; a különbség képességenként ("Mind Blast: 3,0/perc, a cooldown 7,5-öt enged: +4,1 DPS").
- [ ] Felület: új "Javasolt rotáció" rész a Harc oldalon, a Haditervben pedig egy rövid összefoglaló. Minden sor mellett a "Honnan a számok" (Wowhead-rang, együttható, mért gyakoriság).
- [ ] Besorolás: a javaslat számítás, nem hiba. Hiba csak a WA-028 szerinti, bizonyított szabállyal.
- [ ] A rotáció specenként külön definíció: a spec (WA-030) dönti el, melyik fut; a szint dönti el, mely képességek és rangok érhetők el.
- [ ] Tesztelhető interfész: a spec-ticketek (WA-007a – WA-015b) csak a spec képességlistáját és különleges szabályait adják hozzá.

## Elfogadás

- Egy példa-speccel (Combat rogue, WA-007b) végig működik: számítás, felület, teszt.
- Minden megjelenített szám visszakövethető forrásra.
- Új teszt: `t_rotation.lua`.

## Megjegyzés

A spec-ticketek erre épülnek.
