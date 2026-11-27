# WA-032 · Talenthatások a modellben: közös keret

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Talentek és spec | M | magas | modell | kész (2.19.0) |

**Előfeltétel:** [WA-031](WA-031-talent-adatok.md)  
**Erre épül:** [WA-017](WA-017-gyogyito-keret.md), [WA-023](WA-023-tank-keret.md), [WA-032a](WA-032a-talent-rogue.md), [WA-032b](WA-032b-talent-warrior.md), [WA-032c](WA-032c-talent-mage.md), [WA-032d](WA-032d-talent-warlock.md), [WA-032e](WA-032e-talent-hunter.md), [WA-032f](WA-032f-talent-shaman.md), [WA-032g](WA-032g-talent-druid.md), [WA-032h](WA-032h-talent-priest.md), [WA-032i](WA-032i-talent-paladin.md), [WA-033](WA-033-talent-ertek.md)

## Cél

Közös keret, amely a talentek rangonkénti hatását a kasztmodellek paramétereire fordítja (crit, hit, sebzés %, költség, cooldown, proc).

## Miért

Ma a talenthatás kasztonként, kézzel van beírva (`Game.lua` HUNTER_TALENTS, SHAMAN_TALENTS, a rogue tooltip-olvasása), a többi hat kasztnál egyáltalán nincs. A talentek nélkül a modell nem tudja, hogy két azonos gearű karakter más build mellett mást sebez.

## Teendők

- [x] `Talents.lua` (vagy a modellben): talentnév → hatás rangonként, egységes formában, minden hatáshoz forrással.
- [x] A meglévő kézi listák átköltöztetése a keretbe (rogue, hunter, shaman), a számok változása nélkül (a tesztek igazolják).
- [x] Ami nem ellenőrizhető vagy a modell nem tudja számolni, az "nem számolt" talent, indokkal; így látszik, mi hiányzik.
- [x] A modell bemenete a talentek teljes listája, nem csak a fő fa.

## Elfogadás

- A rogue, a hunter és a shaman modellje ugyanazt adja, mint eddig, de a kereten át.
- Minden talentről látszik: számolt (forrással) vagy nem számolt (indokkal).

## Megjegyzés

A kaszt-ticketek (WA-032a – WA-032i) erre épülnek.

## Eredmény (2.19.0)

- `Talent.lua`: `T.EFFECTS` (kasztonként: talentnév → modellkulcs, és hogy a rang szövegének hányadik száma az érték), `T.Effects(class, ranks)` (a modell talent-bemenete mindhárom fa minden talentjéből, és minden ponttal bíró talentnél: számolt, forrással, vagy nem számolt, indokkal), `T.Coverage`. A `Game.lua` kézi listái (HUNTER_TALENTS, SHAMAN_TALENTS, a rogue tooltip-olvasása) megszűntek.
- A szám mindig a rang Wowhead Forever szövegéből jön. A rogue (Malice, Efficient Strikes, Coup de Grace) és a hunter Mortal Shots, Lightning Reflexes, valamint a shaman Thundering Strikes ugyanazt adja, mint eddig.
- Eltért a Forevertől, ezért javítva (nem "változatlan számmal", mert a régi szám nem a Foreveré volt): hunter Lethal Shots → Lethal Attacks; shaman Flurry 6%/rang; Elemental Fury 5 rang, +20%/rang; Elemental Weapons a Forever számaival; a Two-Handed Axes and Maces talent Foreveren nincs a fában, ott a fegyverskill dönt. A Wowhead Forever spell=16269 oldala szerint a spell létezik (megtanítja a 197-es és 199-es fegyverskillt), de hogy hogyan kapja meg a shaman, azt nem írja; ezért a játék skill-listája az irányadó.
- `/wa talent`: a számolt talentek a számmal, a nem számoltak az indokkal.
- D13 a `DECISIONS.md`-ben. Tesztek: t_talents (a keret, a forrás, az indokok, az eltérő rangszám), t_shaman (Forever-rangok, a kétkezes fegyver a skill szerint, és Classic-adattal a talent szerint).
- Nyitva: a webapp (`src/talents.ts`, `src/gear.ts`) még a saját olvasását használja (WA-029).
