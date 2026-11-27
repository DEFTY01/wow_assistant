# WA-032g · Talenthatások: Druid, mindhárom fa

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Talentek és spec | M | magas | modell | nyitott |

**Előfeltétel:** [WA-032](WA-032-talent-hatas-keret.md)  
**Erre épül:** [WA-013a](WA-013a-rotacio-druid-balance.md), [WA-013b](WA-013b-rotacio-druid-feral-cat.md)

## Cél

A druid mindhárom talentfájának minden talentje bekerül a modellbe a hatásával, vagy "nem számolt" jelöléssel és indokkal.

## Miért

Ma egyetlen talentet sem olvas; a modell csak a fő fát nézi, ahol egyáltalán. A spec és a talentek döntik el, mely képességek és szorzók számítanak, ezért enélkül a modell, a gear-értékelés és a rotáció egy átlagos buildet feltételez.

## Teendők

- [ ] Mindhárom fa minden talentje: hatás rangonként a Wowhead Forever adataiból (WA-031), vagy a WoWSims Forever motor kódjából.
- [ ] A sebzést, a statokat, a költséget, a cooldownt vagy a procot változtató talentek a modellben; a túlélést és a gyógyítást változtatók a tank- és gyógyítómodellnek jelölve (WA-017, WA-023).
- [ ] A képességet adó talentek (pl. egy fa csúcstalentje) bekapcsolják a képességet a modellben és a rotációban.
- [ ] Teszt: ugyanaz a gear két különböző builddel más DPS-t és más stat-súlyokat ad, ahol a talentek ezt indokolják.

## Elfogadás

- A druid Talentek oldalán (WA-034) minden talent mellett látszik: számolt vagy nem számolt.
- A meglévő tesztek a talentek nélküli esetben változatlanok.
