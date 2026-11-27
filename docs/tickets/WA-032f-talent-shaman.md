# WA-032f · Talenthatások: Shaman, mindhárom fa

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Talentek és spec | M | magas | modell | kész (2.25.0) |

**Előfeltétel:** [WA-032](WA-032-talent-hatas-keret.md)  
**Erre épül:** [WA-012a](WA-012a-rotacio-shaman-elemental.md), [WA-012b](WA-012b-rotacio-shaman-enhancement.md)

## Cél

A shaman mindhárom talentfájának minden talentje bekerül a modellbe a hatásával, vagy "nem számolt" jelöléssel és indokkal.

## Miért

Ma hat talentet olvas: Flurry, Thundering Strikes, Elemental Fury, Two-Handed Axes and Maces, Elemental Weapons, Stormstrike. A spec és a talentek döntik el, mely képességek és szorzók számítanak, ezért enélkül a modell, a gear-értékelés és a rotáció egy átlagos buildet feltételez.

## Teendők

- [x] Mindhárom fa minden talentje: hatás rangonként a Wowhead Forever adataiból (WA-031), vagy a WoWSims Forever motor kódjából.
- [x] A sebzést, a statokat, a költséget, a cooldownt vagy a procot változtató talentek a modellben; a túlélést és a gyógyítást változtatók a tank- és gyógyítómodellnek jelölve (WA-017, WA-023).
- [ ] A képességet adó talentek (pl. egy fa csúcstalentje) bekapcsolják a képességet a modellben és a rotációban.
- [x] Teszt: ugyanaz a gear két különböző builddel más DPS-t és más stat-súlyokat ad, ahol a talentek ezt indokolják.

## Elfogadás

- A shaman Talentek oldalán (WA-034) minden talent mellett látszik: számolt vagy nem számolt.
- A meglévő tesztek a talentek nélküli esetben változatlanok.

## Eredmény (2.25.0)

- A shaman mind az 50 talentje besorolva (`Talent.lua`, `T.EFFECTS.SHAMAN`): 13 számolt a modellben, 37 indokkal nem számolt. A számolt talentek száma a rang Wowhead Forever szövegéből jön. A Classic Two-Handed Axes and Maces talentje nincs a Forever fákban: ott továbbra is a fegyverskill dönt.
- Számolt (`Shaman.lua`: közelharc imbue-val, Stormstrike, shockok, Lightning Bolt, totemek):
  - Concussion: a Lightning Bolt és az Earth Shock sebzése; Call of Flame: a tűztotemek és a Flame Shock. A shockokon a harcnaplóból mért arányon hat (mennyi a shocksebzésből Earth Shock és Flame Shock); harc nélkül Earth Shockkal számol;
  - Call of Thunder: a Lightning Bolt critje; Lightning Overload: a castok %-ában egy második, fél sebzésű Lightning Bolt. A harcnapló ezt is Lightning Boltnak írja, ezért a kalibráció a mért ütésszámot elosztja (1 + esély)-lyel;
  - Elemental Fury: a varázslatok crit-bónusza (5/5-nél 2×);
  - Ancestral Knowledge (intellect), Mental Dexterity (az intellect attack power lesz), Mental Quickness (az intellect egy része spell power lesz): a gear-értékelésben az intellect így közelharci és varázssebzést is ér;
  - Flurry, Elemental Weapons, Stormstrike: ahogy eddig;
  - a karakterlapon már benne van: Thundering Strikes (crit), Tidal Focus (hit), Mental Dexterity (a jelenlegi attack power).
- A shaman varázslatainak hitje most a játék spell hit-módosítójából (GetSpellHitModifier) jön, legalább 1% miss marad. A mért miss-hez a modell hozzáadja a lap hitjét, hogy ne vonja le kétszer.
- A harcnapló kalibrációja kiosztja a talentszorzókat a mért sebzésből: ugyanabból a naplóból talenttel és nélküle is 84,0 DPS jön ki.
- Nem számolt, indokkal: gyógyítás (WA-017), mana, túlélés, fenyegetés, mozgás és irányítás, több célpont (Trial by Fire, a Chain Lightning része), az aura-idővonalra váró hatás (Elemental Devastation: WA-005), cooldownok (Lightning Mastery, Nature's Swiftness, Rage of the Farseer), a harcokból mért gyakoriságot változtató talentek (Reverberation, Elemental Alacrity, Improved Stormstrike, Maelstrom Weapon: WA-012a, WA-012b), a mért Lightning Shield (Improved Lightning Shield).
- Teszt (t_talents): 40-es szinten talent nélkül 80,6, Elemental-builddel 85,3, Enhancement-builddel 86,3 DPS; +10 intellect talent nélkül nem ér mérhető sebzést, a Mental Dexterity-vel 0,92 DPS-t.
- A talent nélküli eset számai változatlanok (minden teszt átment).
