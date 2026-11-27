# WA-032g · Talenthatások: Druid, mindhárom fa

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Talentek és spec | M | magas | modell | kész (2.26.0) |

**Előfeltétel:** [WA-032](WA-032-talent-hatas-keret.md)  
**Erre épül:** [WA-013a](WA-013a-rotacio-druid-balance.md), [WA-013b](WA-013b-rotacio-druid-feral-cat.md)

## Cél

A druid mindhárom talentfájának minden talentje bekerül a modellbe a hatásával, vagy "nem számolt" jelöléssel és indokkal.

## Miért

Ma egyetlen talentet sem olvas; a modell csak a fő fát nézi, ahol egyáltalán. A spec és a talentek döntik el, mely képességek és szorzók számítanak, ezért enélkül a modell, a gear-értékelés és a rotáció egy átlagos buildet feltételez.

## Teendők

- [x] Mindhárom fa minden talentje: hatás rangonként a Wowhead Forever adataiból (WA-031), vagy a WoWSims Forever motor kódjából.
- [x] A sebzést, a statokat, a költséget, a cooldownt vagy a procot változtató talentek a modellben; a túlélést és a gyógyítást változtatók a tank- és gyógyítómodellnek jelölve (WA-017, WA-023).
- [ ] A képességet adó talentek (pl. egy fa csúcstalentje) bekapcsolják a képességet a modellben és a rotációban.
- [x] Teszt: ugyanaz a gear két különböző builddel más DPS-t és más stat-súlyokat ad, ahol a talentek ezt indokolják.

## Elfogadás

- A druid Talentek oldalán (WA-034) minden talent mellett látszik: számolt vagy nem számolt.
- A meglévő tesztek a talentek nélküli esetben változatlanok.

## Eredmény (2.26.0)

- A druid mind az 52 talentje besorolva (`Talent.lua`, `T.EFFECTS.DRUID`): 13 számolt a modellben, 39 indokkal nem számolt. A számolt talentek száma a rang Wowhead Forever szövegéből jön. Eddig a druid modell egyetlen talentet sem olvasott.
- Spec: ha a legtöbb pont a Balance fában van, a modell a varázsló (caster) modellt használja akkor is, ha a karakter tudja a Cat Formot.
- Számolt (`Druid.lua`):
  - Cat Form: Ferocity (olcsóbb Claw, a harc nélküli becslésben több építő képesség), Savage Fury (a Claw, a Rake és a Shred sebzése), Natural Instinct (a képességek crit-bónusza);
  - Sharpened Claws és Leader of the Pack (crit formában), Predatory Strikes (attack power formában): Cat Formban olvasva a karakterlap tartalmazza, más formában olvasva a modell hozzáadja. A Predatory Strikes-ot csak a becsült attack powerhez adja hozzá, a Cat Formban olvasotthoz nem;
  - Heart of the Wild: intellect, és Cat Formban strength;
  - Naturalist: minden sebzés;
  - caster: Vengeance (a varázslatok crit-bónusza, 5/5-nél 2×), Eclipse (Wrath crit, a harcaidban mért Wrath-arányon), Moonkin Form (arcane és nature sebzés, crit-aura; az aurát Moonkin Formban olvasva a karakterlap tartalmazza);
  - a karakterlapon már benne van: Nature's Majesty (crit), Nature's Reach (hit).
- A druid varázslatainak hitje most a játék spell hit-módosítójából (GetSpellHitModifier) jön, legalább 1% miss marad.
- A harcnapló kalibrációja kiosztja a talentszorzókat a mért sebzésből. Ugyanabból a Cat Form-naplóból talent nélkül 81,6, az építő talentekkel 81,4 DPS jön ki. A Naturalist csak a mancs fehér sebzését emeli, mert azt a modell számolja, nem méri.
- Nem számolt, indokkal: medve (WA-026), gyógyítás (WA-017), mana, túlélés, fenyegetés, mozgás és irányítás, több célpont, formaváltás (Furor), a vérzés ideje (Rend and Tear: WA-005), a harcokból mért gyakoriságot vagy finishert változtató talentek (Shredding Attacks, Blood Frenzy, Predatory Discipline, Starlight Wrath, Nature's Grace: WA-013a, WA-013b), a periodikus sebzés (Genesis, Nature's Splendor), a külön nem modellezett varázslatok (Moonfire, Insect Swarm).
- Teszt (t_talents): 40-es szinten Cat Formban talent nélkül 64,1, Feral-builddel 75,5 DPS; casterként talent nélkül 83,2, Balance-builddel 108,6 DPS.
- A talent nélküli eset számai változatlanok (minden teszt átment).
