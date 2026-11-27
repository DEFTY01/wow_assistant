# WA-032b · Talenthatások: Warrior, mindhárom fa

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Talentek és spec | M | magas | modell | kész (2.21.0) |

**Előfeltétel:** [WA-032](WA-032-talent-hatas-keret.md)  
**Erre épül:** [WA-008a](WA-008a-rotacio-warrior-arms.md), [WA-008b](WA-008b-rotacio-warrior-fury.md)

## Cél

A warrior mindhárom talentfájának minden talentje bekerül a modellbe a hatásával, vagy "nem számolt" jelöléssel és indokkal.

## Miért

Ma egyetlen talentet sem olvas; a modell csak a fő fát nézi, ahol egyáltalán. A spec és a talentek döntik el, mely képességek és szorzók számítanak, ezért enélkül a modell, a gear-értékelés és a rotáció egy átlagos buildet feltételez.

## Teendők

- [x] Mindhárom fa minden talentje: hatás rangonként a Wowhead Forever adataiból (WA-031), vagy a WoWSims Forever motor kódjából.
- [x] A sebzést, a statokat, a költséget, a cooldownt vagy a procot változtató talentek a modellben; a túlélést és a gyógyítást változtatók a tank- és gyógyítómodellnek jelölve (WA-017, WA-023).
- [ ] A képességet adó talentek (pl. egy fa csúcstalentje) bekapcsolják a képességet a modellben és a rotációban.
- [x] Teszt: ugyanaz a gear két különböző builddel más DPS-t és más stat-súlyokat ad, ahol a talentek ezt indokolják.

## Elfogadás

- A warrior Talentek oldalán (WA-034) minden talent mellett látszik: számolt vagy nem számolt.
- A meglévő tesztek a talentek nélküli esetben változatlanok.

## Eredmény (2.21.0)

- A warrior mind az 53 talentje besorolva (`Talent.lua`, `T.EFFECTS.WARRIOR`): 8 számolt a modellben, 45 indokkal nem számolt. A számolt talentek száma a rang Wowhead Forever szövegéből jön.
- Számolt (`Warrior.lua`):
  - Two-Handed Weapon Specialization (kétkezes fegyverrel minden modellezett sebzés), Bastion (pajzzsal minden modellezett sebzés; a felszerelési javaslat tudja, ha pajzsot cserélsz vagy kétkezesre váltasz);
  - Impale (a Heroic Strike és a fegyveres specialok crit-bónusza), Weaponmaster kard része (extra támadás);
  - Flurry (a crit utáni 3 ütés gyorsabb; így a crit többet ér), Dual Wield Specialization (off-hand sebzés), Furious Precision (off-hand hit);
  - Cruelty (a karakterlapon már benne van).
  - A harcnaplós kalibráció ezekkel számol: a Flurry gyorsabb ütései és a kard extra támadásai nem növelik az "ütés az idő %-ában" értéket, és a mért Heroic Strike / special sebzésből kiveszi a talentek szorzóit.
- Nem számolt, indokkal: a rage-et adó vagy rage-költséget csökkentő talentek (a modell nem szimulálja a rage-et; WA-008a, WA-008b), túlélés és fenyegetés (tankmodell, WA-023, WA-024), irányítás és mozgás, több célpont (Sweeping Strikes), külön nem modellezett képességek (Rend, Overpower, Slam, Whirlwind, Revenge, Shield Slam, Spearing Strike), a mért források (Mortal Strike, Bloodthirst, Deep Wounds), a Death Wish (a cooldown nincs az adatban), az Enrage (a kapott ütések száma nem jön a harcadatból), a Weaponmaster fejsze/buzogány része.
- Teszt (t_talents): ugyanaz a két kard Arms-builddel 93,4, Fury-builddel 102,0 DPS (talent nélkül 89,3); Flurry mellett 1% crit 0,99% helyett 1,46%-ot ér; a Two-Handed Weapon Specialization 3/3 pontosan +6%, a Bastion 5/5 pajzzsal +10%.
- A talent nélküli eset számai változatlanok (minden teszt átment).
