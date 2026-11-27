# WA-032a · Talenthatások: Rogue, mindhárom fa

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Talentek és spec | M | magas | modell | kész (2.20.0) |

**Előfeltétel:** [WA-032](WA-032-talent-hatas-keret.md)  
**Erre épül:** [WA-007a](WA-007a-rotacio-rogue-assassination.md), [WA-007b](WA-007b-rotacio-rogue-combat.md), [WA-007c](WA-007c-rotacio-rogue-subtlety.md)

## Cél

A rogue mindhárom talentfájának minden talentje bekerül a modellbe a hatásával, vagy "nem számolt" jelöléssel és indokkal.

## Miért

Ma három talentet olvas: Malice, Efficient Strikes, Coup de Grace (a tooltip szövegéből). A spec és a talentek döntik el, mely képességek és szorzók számítanak, ezért enélkül a modell, a gear-értékelés és a rotáció egy átlagos buildet feltételez.

## Teendők

- [x] Mindhárom fa minden talentje: hatás rangonként a Wowhead Forever adataiból (WA-031), vagy a WoWSims Forever motor kódjából.
- [x] A sebzést, a statokat, a költséget, a cooldownt vagy a procot változtató talentek a modellben; a túlélést és a gyógyítást változtatók a tank- és gyógyítómodellnek jelölve (WA-017, WA-023).
- [ ] A képességet adó talentek (pl. egy fa csúcstalentje) bekapcsolják a képességet a modellben és a rotációban.
- [x] Teszt: ugyanaz a gear két különböző builddel más DPS-t és más stat-súlyokat ad, ahol a talentek ezt indokolják.

## Elfogadás

- A rogue Talentek oldalán (WA-034) minden talent mellett látszik: számolt vagy nem számolt.
- A meglévő tesztek a talentek nélküli esetben változatlanok.

## Eredmény (2.20.0)

- A rogue mind az 54 talentje besorolva (`Talent.lua`, `T.EFFECTS.ROGUE`): 13 számolt a modellben, 41 indokkal nem számolt. A számolt talentek száma mindig a rang Wowhead Forever szövegéből jön.
- Számolt (`Model.lua`, a Sinister Strike + Eviscerate modell):
  - energia: Efficient Strikes (Sinister Strike), Flawless Execution (Eviscerate), Relentless Strikes (finisher után visszakapott energia);
  - combo pont: Ruthlessness, Seal Fate (a crit így többet ér: a ciklus a crittel együtt mozog);
  - sebzés: Coup de Grace és Aggression (az Eviscerate-en összeadódnak), Aggression a Sinister Strike-on, Lethality (Sinister Strike crit-bónusz), Dual Wield Specialization (off-hand);
  - találat: Weapon Expertise (kevesebb dodge és parry), Hack and Slash (fejszével vagy karddal extra támadás; a naplóban ezek fehér ütések, a kalibráció számol velük);
  - a karakterlapon már benne van: Malice (crit), Precision (hit).
- Nem számolt, indokkal: túlélés (tankmodell, WA-023), mozgás/lopakodás/irányítás, a modellben még nem szereplő képességek (Backstab, Mutilate, Hemorrhage, Ghostly Strike, Slice and Dice, Rupture, Shank, nyitások: a rotációs ticketek, WA-007a – WA-007c), cooldownok (a cooldown ideje nincs a talentadatban), mérgek (a modell a harcokból méri), a Remorseless Attacks (az ölések száma még nem jön a harcadatból), a Serrated Blades és a Hack and Slash buzogányos része (a modell nem számol páncéllal), a Vigor (a tartós sebzést nem változtatja).
- Teszt (t_talents): ugyanaz a gear Combat-builddel és Assassination-builddel más DPS-t ad (L40: talent nélkül 118,0, Combat 146,7, Assassination 128,3), a Seal Fate-tel 1% crit többet ér (1,05% helyett 1,19%), és Hack and Slash mellett a kard többet ér, mint ugyanaz a buzogány.
- A talent nélküli eset számai változatlanok (minden teszt átment).
- Nyitva: a képességet adó talentek a rotációs ticketekben kapcsolják be a képességet (WA-007a – WA-007c); a Talentek oldal a WA-034-ben jön, addig a `/wa talent` mutatja, mi számolt.
