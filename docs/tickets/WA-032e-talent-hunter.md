# WA-032e · Talenthatások: Hunter, mindhárom fa

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Talentek és spec | M | magas | modell | kész (2.24.0) |

**Előfeltétel:** [WA-032](WA-032-talent-hatas-keret.md)  
**Erre épül:** [WA-011a](WA-011a-rotacio-hunter-bm.md), [WA-011b](WA-011b-rotacio-hunter-mm.md), [WA-011c](WA-011c-rotacio-hunter-survival.md)

## Cél

A hunter mindhárom talentfájának minden talentje bekerül a modellbe a hatásával, vagy "nem számolt" jelöléssel és indokkal.

## Miért

Ma három talentet olvas: Lethal Shots, Mortal Shots, Lightning Reflexes. A spec és a talentek döntik el, mely képességek és szorzók számítanak, ezért enélkül a modell, a gear-értékelés és a rotáció egy átlagos buildet feltételez.

## Teendők

- [x] Mindhárom fa minden talentje: hatás rangonként a Wowhead Forever adataiból (WA-031), vagy a WoWSims Forever motor kódjából.
- [x] A sebzést, a statokat, a költséget, a cooldownt vagy a procot változtató talentek a modellben; a túlélést és a gyógyítást változtatók a tank- és gyógyítómodellnek jelölve (WA-017, WA-023).
- [ ] A képességet adó talentek (pl. egy fa csúcstalentje) bekapcsolják a képességet a modellben és a rotációban.
- [x] Teszt: ugyanaz a gear két különböző builddel más DPS-t és más stat-súlyokat ad, ahol a talentek ezt indokolják.

## Elfogadás

- A hunter Talentek oldalán (WA-034) minden talent mellett látszik: számolt vagy nem számolt.
- A meglévő tesztek a talentek nélküli esetben változatlanok.

## Eredmény (2.24.0)

- A hunter mind az 50 talentje besorolva (`Talent.lua`, `T.EFFECTS.HUNTER`): 14 számolt a modellben, 36 indokkal nem számolt. A számolt talentek száma a rang Wowhead Forever szövegéből jön.
- Számolt (`Hunter.lua`: távolsági lövések, közelharc, pet, Serpent Sting):
  - Focused Fire (minden sebzés, ha van petje) és Lone Wolf (minden sebzés, ha nincs). A modell a pet jelenlétéből dönti el, melyik hat;
  - Unleashed Fury: a pet sebzése (a harc nélküli becslésben; a mért petsebzésben benne van);
  - Ranged Weapon Specialization: a távolsági fegyveres sebzés; Barrage: a Multi-Shot és az Aimed Shot; Mortal Shots: a távolsági crit-bónusz;
  - Improved Stings: a Serpent Sting sebzése (a Viper és a Scorpid Sting része nem számolt);
  - Careful Aim: az intellect egy része attack power lesz, ezért a gear-értékelésben az intellectnek is lesz súlya;
  - Savage Strikes és Predator's Edge: a Raptor Strike critje és crit-sebzése, az off-hand sebzés; Lightning Reflexes: agility;
  - a karakterlapon már benne van: Surefooted (hit), Lethal Attacks (távolsági crit), Trueshot Aura (ranged attack power, amíg fent van).
- A harcnapló kalibrációja kiosztja a talentszorzókat a mért sebzésből, hogy ne számolódjanak kétszer.
- Nem számolt, indokkal: túlélés, irányítás és mozgás, mana, a pet fajtájától vagy viselkedésétől függő talentek (Ferocity, Frenzy: a pet sebzését a modell méri), az aura-idővonalra váró hatás (Deadly Aspects: WA-005), cooldownok (Bestial Wrath), ölés utáni hatás (Rapid Killing), a külön nem modellezett képességek (Summon Hawk, csapdák, Counterattack, Mongoose Bite, Strider Kick, Sniper Shot: WA-011a – WA-011c).
- Teszt (t_talents): 40-es szinten talent nélkül 120,2, Beast Mastery-builddel 126,7, Marksmanship-builddel 128,6 DPS; a Careful Aim nélkül az intellect nem ér sebzést, vele igen; a Lone Wolf pet nélkül +20%, pettel semmi.
- A talent nélküli eset számai változatlanok (minden teszt átment).
