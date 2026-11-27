# WA-032a · Talenthatások: Rogue, mindhárom fa

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Talentek és spec | M | magas | modell | nyitott |

**Előfeltétel:** [WA-032](WA-032-talent-hatas-keret.md)  
**Erre épül:** [WA-007a](WA-007a-rotacio-rogue-assassination.md), [WA-007b](WA-007b-rotacio-rogue-combat.md), [WA-007c](WA-007c-rotacio-rogue-subtlety.md)

## Cél

A rogue mindhárom talentfájának minden talentje bekerül a modellbe a hatásával, vagy "nem számolt" jelöléssel és indokkal.

## Miért

Ma három talentet olvas: Malice, Efficient Strikes, Coup de Grace (a tooltip szövegéből). A spec és a talentek döntik el, mely képességek és szorzók számítanak, ezért enélkül a modell, a gear-értékelés és a rotáció egy átlagos buildet feltételez.

## Teendők

- [ ] Mindhárom fa minden talentje: hatás rangonként a Wowhead Forever adataiból (WA-031), vagy a WoWSims Forever motor kódjából.
- [ ] A sebzést, a statokat, a költséget, a cooldownt vagy a procot változtató talentek a modellben; a túlélést és a gyógyítást változtatók a tank- és gyógyítómodellnek jelölve (WA-017, WA-023).
- [ ] A képességet adó talentek (pl. egy fa csúcstalentje) bekapcsolják a képességet a modellben és a rotációban.
- [ ] Teszt: ugyanaz a gear két különböző builddel más DPS-t és más stat-súlyokat ad, ahol a talentek ezt indokolják.

## Elfogadás

- A rogue Talentek oldalán (WA-034) minden talent mellett látszik: számolt vagy nem számolt.
- A meglévő tesztek a talentek nélküli esetben változatlanok.
