# WA-032c · Talenthatások: Mage, mindhárom fa

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Talentek és spec | M | magas | modell | kész (2.22.0) |

**Előfeltétel:** [WA-032](WA-032-talent-hatas-keret.md)  
**Erre épül:** [WA-009a](WA-009a-rotacio-mage-arcane.md), [WA-009b](WA-009b-rotacio-mage-fire.md), [WA-009c](WA-009c-rotacio-mage-frost.md)

## Cél

A mage mindhárom talentfájának minden talentje bekerül a modellbe a hatásával, vagy "nem számolt" jelöléssel és indokkal.

## Miért

Ma egyetlen talentet sem olvas; a modell csak a fő fát nézi, ahol egyáltalán. A spec és a talentek döntik el, mely képességek és szorzók számítanak, ezért enélkül a modell, a gear-értékelés és a rotáció egy átlagos buildet feltételez.

## Teendők

- [x] Mindhárom fa minden talentje: hatás rangonként a Wowhead Forever adataiból (WA-031), vagy a WoWSims Forever motor kódjából.
- [x] A sebzést, a statokat, a költséget, a cooldownt vagy a procot változtató talentek a modellben; a túlélést és a gyógyítást változtatók a tank- és gyógyítómodellnek jelölve (WA-017, WA-023).
- [ ] A képességet adó talentek (pl. egy fa csúcstalentje) bekapcsolják a képességet a modellben és a rotációban.
- [x] Teszt: ugyanaz a gear két különböző builddel más DPS-t és más stat-súlyokat ad, ahol a talentek ezt indokolják.

## Elfogadás

- A mage Talentek oldalán (WA-034) minden talent mellett látszik: számolt vagy nem számolt.
- A meglévő tesztek a talentek nélküli esetben változatlanok.

## Eredmény (2.22.0)

- A mage mind az 53 talentje besorolva (`Talent.lua`, `T.EFFECTS.MAGE`): 9 számolt a modellben, 44 indokkal nem számolt. A számolt talentek száma a rang Wowhead Forever szövegéből jön.
- Számolt (`Mage.lua`, a fő varázslat Frostbolt vagy Fireball, plusz pálca):
  - Accelerant (Fireball) és Improved Frostbolt: rövidebb cast idő; az együttható a rangé marad;
  - Ignite: a tűz crit sebzésének %-a égésként (a harcnaplóban mért Ignite-ot a kalibráció nem számolja kétszer);
  - Ice Shards: a fagy crit 50%-os bónusza a talent %-ával nő (5/5-nél 2×);
  - Critical Mass: tűz crit. A játék iskolánként adja a critet: ha a tűz crit nem nagyobb ennyivel a fagy critnél, a karakterlap nem tartalmazza, és a modell hozzáadja; ha nagyobb, nem számolja kétszer;
  - Arcane Instability (spell sebzés %; a crit része a karakterlapon), Arcane Mind (intellect %, a felszerelés intellectjére is), Wand Specialization (pálca);
  - Precision: a karakterlapon (GetSpellHitModifier), harcnapló mellett a mért miss számít.
- Javítva útközben: a modell eddig a tűz és a fagy crit közül a nagyobbikat használta; most a fő varázslat iskolájáét.
- Nem számolt, indokkal: mana (a modell nem számolja), túlélés, irányítás és hatótáv, több célpont, a modellben külön nem szereplő varázslatok (Fire Blast, Scorch, Pyroblast, Ice Lance, Arcane Missiles, Arcane Blast, Arcane Wrath: WA-009a – WA-009c), fagyott célpont (Shatter, Fingers of Frost), cooldownok, a Fire Power (a célponton lévő tűzhatások száma nem jön a harcadatból), az Arcane Subtlety (az ellenállást a modell nem számolja).
- Teszt (t_talents): 40-es szinten Fireball talent nélkül 61,3, Fire-builddel 80,1; Frostbolt talent nélkül 64,1, Frost-builddel 79,2 DPS. Ignite és Ice Shards mellett az intellect (crit) többet ér; a Critical Mass nem számolódik kétszer, ha a karakterlapon már benne van.
- A talent nélküli eset számai változatlanok (minden teszt átment).
