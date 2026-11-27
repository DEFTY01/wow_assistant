# WA-032h · Talenthatások: Priest, mindhárom fa

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Talentek és spec | M | magas | modell | kész (2.27.0) |

**Előfeltétel:** [WA-032](WA-032-talent-hatas-keret.md)  
**Erre épül:** [WA-014a](WA-014a-rotacio-priest-shadow.md), [WA-014b](WA-014b-rotacio-priest-holy-disc-szolo.md)

## Cél

A priest mindhárom talentfájának minden talentje bekerül a modellbe a hatásával, vagy "nem számolt" jelöléssel és indokkal.

## Miért

Ma egyetlen talentet sem olvas; a modell csak a fő fát nézi, ahol egyáltalán. A spec és a talentek döntik el, mely képességek és szorzók számítanak, ezért enélkül a modell, a gear-értékelés és a rotáció egy átlagos buildet feltételez.

## Teendők

- [x] Mindhárom fa minden talentje: hatás rangonként a Wowhead Forever adataiból (WA-031), vagy a WoWSims Forever motor kódjából.
- [x] A sebzést, a statokat, a költséget, a cooldownt vagy a procot változtató talentek a modellben; a túlélést és a gyógyítást változtatók a tank- és gyógyítómodellnek jelölve (WA-017, WA-023).
- [ ] A képességet adó talentek (pl. egy fa csúcstalentje) bekapcsolják a képességet a modellben és a rotációban.
- [x] Teszt: ugyanaz a gear két különböző builddel más DPS-t és más stat-súlyokat ad, ahol a talentek ezt indokolják.

## Elfogadás

- A priest Talentek oldalán (WA-034) minden talent mellett látszik: számolt vagy nem számolt.
- A meglévő tesztek a talentek nélküli esetben változatlanok.

## Eredmény (2.27.0)

- A priest mind az 52 talentje besorolva (`Talent.lua`, `T.EFFECTS.PRIEST`): 13 számolt a modellben, 39 indokkal nem számolt. A számolt talentek száma a rang Wowhead Forever szövegéből jön.
- Számolt (`Priest.lua`, a modell részein: Smite, Mind Blast, Shadow Word: Pain, Mind Flay, Holy Fire, pálca):
  - Searing Light (holy sebzés), Darkness és Shadowform (shadow sebzés; a Shadowform a shadow crit-bónuszt is duplázza), Twin Disciplines (a Shadow Word: Pain), Improved Mind Flay (minden tick az előzőnél 20%-kal több: teljes csatornán átlag ×1,213);
  - Holy Precision és Shadow Focus: hit iskolánként; Holy Specialization: holy crit. A játék holy és shadow critjének különbségéből látja, hogy a karakterlap tartalmazza-e;
  - Mind Flay: a töltelék varázslat a Smite helyett, ha megvan a talent (eddig a Shadow fa döntött);
  - Divine Fury (rövidebb Smite és Holy Fire) és Improved Mind Blast (rövidebb cooldown): a harc nélküli becslésben; harcnapló mellett a mért gyakoriság számít;
  - Mental Strength (intellect), Wand Specialization (pálca).
- A priest crit most iskolánként jön a játékból (GetSpellCritChance holy és shadow), és a mért miss-hez a modell hozzáadja a lap és a talentek hitjét, hogy ne vonja le kétszer.
- A harcnapló kalibrációja kiosztja a talentszorzókat a mért sebzésből: ugyanabból a Shadow-naplóból csak Mind Flay-jel 88,9, a shadow talentekkel 89,0 DPS.
- Nem számolt, indokkal: gyógyítás és pajzs (WA-017), mana, túlélés, fenyegetés, cast-visszalökés, irányítás, több célpont, az aura-idővonalra váró hatások (Power in Light, Shadow Weaving: WA-005), cooldownok (Inner Focus, Power Infusion), 20% alatti célpont (Early Demise), a DoT hossza (Improved Shadow Word: Pain), a spiritből jövő spell power (Spiritual Guidance: a modell nem olvassa a spiritet), a külön nem modellezett Penance (WA-014b).
- Teszt (t_talents): 40-es szinten talent nélkül 73,4, Holy-builddel 85,8, Shadow-builddel 107,6 DPS.
- A talent nélküli eset számai változatlanok (minden teszt átment).
