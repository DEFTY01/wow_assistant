# WA-032 · Talenthatások a modellben: közös keret

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Talentek és spec | M | magas | modell | nyitott |

**Előfeltétel:** [WA-031](WA-031-talent-adatok.md)  
**Erre épül:** [WA-017](WA-017-gyogyito-keret.md), [WA-023](WA-023-tank-keret.md), [WA-032a](WA-032a-talent-rogue.md), [WA-032b](WA-032b-talent-warrior.md), [WA-032c](WA-032c-talent-mage.md), [WA-032d](WA-032d-talent-warlock.md), [WA-032e](WA-032e-talent-hunter.md), [WA-032f](WA-032f-talent-shaman.md), [WA-032g](WA-032g-talent-druid.md), [WA-032h](WA-032h-talent-priest.md), [WA-032i](WA-032i-talent-paladin.md), [WA-033](WA-033-talent-ertek.md)

## Cél

Közös keret, amely a talentek rangonkénti hatását a kasztmodellek paramétereire fordítja (crit, hit, sebzés %, költség, cooldown, proc).

## Miért

Ma a talenthatás kasztonként, kézzel van beírva (`Game.lua` HUNTER_TALENTS, SHAMAN_TALENTS, a rogue tooltip-olvasása), a többi hat kasztnál egyáltalán nincs. A talentek nélkül a modell nem tudja, hogy két azonos gearű karakter más build mellett mást sebez.

## Teendők

- [ ] `Talents.lua` (vagy a modellben): talentnév → hatás rangonként, egységes formában, minden hatáshoz forrással.
- [ ] A meglévő kézi listák átköltöztetése a keretbe (rogue, hunter, shaman), a számok változása nélkül (a tesztek igazolják).
- [ ] Ami nem ellenőrizhető vagy a modell nem tudja számolni, az "nem számolt" talent, indokkal; így látszik, mi hiányzik.
- [ ] A modell bemenete a talentek teljes listája, nem csak a fő fa.

## Elfogadás

- A rogue, a hunter és a shaman modellje ugyanazt adja, mint eddig, de a kereten át.
- Minden talentről látszik: számolt (forrással) vagy nem számolt (indokkal).

## Megjegyzés

A kaszt-ticketek (WA-032a – WA-032i) erre épülnek.
