# WA-032d · Talenthatások: Warlock, mindhárom fa

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Talentek és spec | M | magas | modell | kész (2.23.0) |

**Előfeltétel:** [WA-032](WA-032-talent-hatas-keret.md)  
**Erre épül:** [WA-010a](WA-010a-rotacio-warlock-affliction.md), [WA-010b](WA-010b-rotacio-warlock-demonology.md), [WA-010c](WA-010c-rotacio-warlock-destruction.md)

## Cél

A warlock mindhárom talentfájának minden talentje bekerül a modellbe a hatásával, vagy "nem számolt" jelöléssel és indokkal.

## Miért

Ma egyetlen talentet sem olvas; a modell csak a fő fát nézi, ahol egyáltalán. A spec és a talentek döntik el, mely képességek és szorzók számítanak, ezért enélkül a modell, a gear-értékelés és a rotáció egy átlagos buildet feltételez.

## Teendők

- [x] Mindhárom fa minden talentje: hatás rangonként a Wowhead Forever adataiból (WA-031), vagy a WoWSims Forever motor kódjából.
- [x] A sebzést, a statokat, a költséget, a cooldownt vagy a procot változtató talentek a modellben; a túlélést és a gyógyítást változtatók a tank- és gyógyítómodellnek jelölve (WA-017, WA-023).
- [ ] A képességet adó talentek (pl. egy fa csúcstalentje) bekapcsolják a képességet a modellben és a rotációban.
- [x] Teszt: ugyanaz a gear két különböző builddel más DPS-t és más stat-súlyokat ad, ahol a talentek ezt indokolják.

## Elfogadás

- A warlock Talentek oldalán (WA-034) minden talent mellett látszik: számolt vagy nem számolt.
- A meglévő tesztek a talentek nélküli esetben változatlanok.

## Eredmény (2.23.0)

- A warlock mind az 52 talentje besorolva (`Talent.lua`, `T.EFFECTS.WARLOCK`): 11 számolt a modellben, 41 indokkal nem számolt. A számolt talentek száma a rang Wowhead Forever szövegéből jön.
- Számolt (`Warlock.lua`: direkt varázslatok, DoT-ok és drainek, démon, pálca):
  - iskolás talentek a harcaid arányán: Shadow Mastery (árnyék), Agonizing Flames (Destruction), Aftermath (az Immolate kezdő sebzése), Improved Corruption, Improved Bane of Agony, Improved Drains (a saját varázslatuk része a DoT-sebzésből). A modell a harcnaplóból méri, a direkt varázslatok és a DoT-ok mekkora része árnyék, Destruction, Immolate, Corruption, Bane of Agony vagy drain; harc nélkül a saját alapfeltevése (Shadow Bolt és egy Corruption-szerű DoT) szerint;
  - Ruin: a Destruction varázslatok crit-bónusza (5/5-nél 2×);
  - Malevolence: árnyék crit. Ha a játék árnyék critje nem nagyobb ennyivel a tűz critnél, a karakterlap nem tartalmazza, és a modell hozzáadja;
  - Unholy Power: a démon sebzése (a harc nélküli becslésben; a mért démonsebzésben benne van);
  - a karakterlapon már benne van: Suppression (hit), Demonic Knowledge (spell power, amíg a démon kint van).
- Nem számolt, indokkal: mana (Life Tap, Cataclysm…), túlélés, irányítás és hatótáv, több célpont (Bane of Havoc), a démon fajtájától függő talentek (a démon sebzését a modell méri), az aura-idővonalra váró hatások (Improved Shadow Bolt, Soul Siphon, Demonic Sacrifice, Soul Link: WA-005), a DoT-ok critje (Pandemic), a cast idő (Bane), a külön nem modellezett varázslatok (Shadowburn, Conflagrate, Incinerate, Wrack, Siphon Life, Soul Fire: WA-010a – WA-010c).
- Teszt (t_talents): 40-es szinten talent nélkül 160,9, Affliction-builddel 179,8, Destruction-builddel 176,2 DPS; harc nélkül a Shadow Mastery és az Improved Corruption a DoT-on +20%, a Shadow Bolton +10%; a Malevolence nem számolódik kétszer, ha a karakterlapon már benne van.
- A talent nélküli eset számai változatlanok (minden teszt átment).
