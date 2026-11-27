# WA-030 · Specfelismerés és specfüggő modellek

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 1. Alapok (adat, kalibráció, spec) | M | magas | modell | nyitott |

**Előfeltétel:** nincs  
**Erre épül:** [WA-006](WA-006-rotacio-keret.md)

## Cél

Minden kaszt modellje tudja, melyik specben vagy, és a spec szerint számoljon.

## Miért

Ma a spec csak néhány helyen számít: az enchant szerepnél (sebző, tank, gyógyító), a mage fő varázslatánál (Fire: Fireball, egyébként Frostbolt), a priest töltelék-varázslatánál (Shadow: Mind Flay) és a paladin sealjénél (Retribution: Seal of Command). A rogue, hunter, shaman, druid, warlock és warrior modellje nem ágazik el spec szerint, csak a harcaidból kalibrál. A rotációs javaslat specenként más, ezért ez előfeltétel.

## Teendők

- [ ] Közös specfelismerés a `Model.lua`-ban: a tehetségfák pontjaiból a fő fa, és a kulcs-talentek (pl. Mortal Strike, Bloodthirst, Stormstrike) megléte; a kliens talent API-jából.
- [ ] Kézi felülírás a felületen, ahogy az enchant szerepnél, ha valaki vegyes fát visz.
- [ ] Minden kasztmodell kapja meg a specet: mely képességek számítanak, és a talentek hatása (csak a Wowhead Forever vagy a WoWSims Forever motor szerint ellenőrzött hatás).
- [ ] A Harc oldal "Modell a kasztodhoz" sora mutassa, melyik spec szerint számol, és miből tudja.
- [ ] Tesztek minden kasztra legalább két speccel.

## Elfogadás

- Mind a kilenc kasztnál látszik, melyik spec szerint számol a modell.
- Ugyanaz a karakter más spec mellett más képességlistát és súlyokat kap, ahol a talentek ezt indokolják.
