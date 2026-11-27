# WA-032i · Talenthatások: Paladin, mindhárom fa

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Talentek és spec | M | magas | modell | kész (2.28.0) |

**Előfeltétel:** [WA-032](WA-032-talent-hatas-keret.md)  
**Erre épül:** [WA-015a](WA-015a-rotacio-paladin-ret.md), [WA-015b](WA-015b-rotacio-paladin-holy-prot-szolo.md)

## Cél

A paladin mindhárom talentfájának minden talentje bekerül a modellbe a hatásával, vagy "nem számolt" jelöléssel és indokkal.

## Miért

Ma egyetlen talentet sem olvas; a modell csak a fő fát nézi, ahol egyáltalán. A spec és a talentek döntik el, mely képességek és szorzók számítanak, ezért enélkül a modell, a gear-értékelés és a rotáció egy átlagos buildet feltételez.

## Teendők

- [x] Mindhárom fa minden talentje: hatás rangonként a Wowhead Forever adataiból (WA-031), vagy a WoWSims Forever motor kódjából.
- [x] A sebzést, a statokat, a költséget, a cooldownt vagy a procot változtató talentek a modellben; a túlélést és a gyógyítást változtatók a tank- és gyógyítómodellnek jelölve (WA-017, WA-023).
- [ ] A képességet adó talentek (pl. egy fa csúcstalentje) bekapcsolják a képességet a modellben és a rotációban.
- [x] Teszt: ugyanaz a gear két különböző builddel más DPS-t és más stat-súlyokat ad, ahol a talentek ezt indokolják.

## Elfogadás

- A paladin Talentek oldalán (WA-034) minden talent mellett látszik: számolt vagy nem számolt.
- A meglévő tesztek a talentek nélküli esetben változatlanok.

## Eredmény (2.28.0)

- A paladin mind az 51 talentje besorolva (`Talent.lua`, `T.EFFECTS.PALADIN`): 9 számolt a modellben, 42 indokkal nem számolt. A számolt talentek száma a rang Wowhead Forever szövegéből jön. A paladin talentjeinek nagy része tank- vagy gyógyító talent, ezért kevesebb a számolt.
- Számolt (`Paladin.lua`: fehér ütés seallel, Holy Strike, a többi mérve):
  - Seal of Command: ha megvan a talent, a modell Seal of Commanddal számol a Seal of Righteousness helyett (eddig a Retribution fa döntött; talentadat nélkül továbbra is az);
  - Improved Seals (a seal sebzése), Sacred Arbiter (Holy Strike), Two-Handed Weapon Specialization (minden sebzés kétkezes fegyverrel; a gear-értékelésben egykezesre váltva elmarad);
  - Divine Strength (strength), Divine Intellect (intellect), Champion of the Light (az intellect egy része spell power lesz: a gear-értékelésben az intellect így sebzést ér);
  - a karakterlapon már benne van: Conviction (crit), Precision (hit).
- A harcnapló kalibrációja kiosztja a talentszorzókat a mért sebzésből: ugyanabból a naplóból csak Seal of Commanddal 66,5, a seal és Holy Strike talentekkel 66,6 DPS.
- Nem számolt, indokkal: gyógyítás (WA-017), tank (blokk, a téged érő ütések és critek: WA-025), mana, túlélés, fenyegetés, irányítás és mozgás, több célpont, az aura-idővonalra váró Vengeance (WA-005), a harcokból mért Judgement, Exorcism és Holy Strike gyakoriságát változtató talentek (Improved Judgement, Purifying Power, Shieldsworn: WA-015a, WA-015b), a külön nem modellezett képességek (Holy Shock, Swift Judgement, Unsealed Wrath).
- Teszt (t_talents): 40-es szinten kétkezes fegyverrel talent nélkül 63,0, Retribution-builddel 70,4 DPS (ugyanez a build egykezessel 53,3).
- Ezzel mind a kilenc kaszt minden talentje besorolva; a t_talents ezt kasztonként ellenőrzi.
- A talent nélküli eset számai változatlanok (minden teszt átment).
