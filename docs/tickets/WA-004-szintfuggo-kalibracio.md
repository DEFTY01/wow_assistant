# WA-004 · Szintfüggő kalibráció

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 1. Alapok (adat és kalibráció) | M | magas | modell | kész (2.32.0) |

**Előfeltétel:** nincs  
**Erre épül:** [WA-006](WA-006-rotacio-keret.md)

## Cél

A modell más szintekre adott becslése ne igazodjon túlzottan ahhoz a szinthez, ahol a harcaid nagy része volt.

## Miért

Most minden kaszt a harcaidból kalibrál (arányok, alapsebzés, egyéb DPS), és ezt az összes szintre alkalmazza. Ha minden harcod 30-as szinten volt, a 45-ös becslés is a 30-as rotációt és rangokat tükrözi.

## Teendők

- [x] A harcokat a szinttávolság szerint súlyozni (pl. a súly felére esik 5 szintenként).
- [ ] A rangfüggő értékeket (alapsebzés) rangonként kalibrálni, ne szintenként: a harcnapló a képességet névvel tárolja, ranggal nem, ezért ez az uploader bővítésére vár (lásd lent).
- [x] A becslés mellé kiírni, hány harc és milyen szintekről kalibrált ("Honnan a számok").
- [x] Közös segédfüggvény a `Model.lua`-ban, és mind a kilenc kaszt használja.
- [x] Tesztek: harcok csak 30-on → a 30-as becslés változatlan, a 45-ös visszaesik a Wowhead-alapértékekre.

## Elfogadás

- Minden kasztnál látszik, honnan jön a kalibráció.
- A meglévő tesztek számai csak ott változnak, ahol a szinttávolság ezt indokolja; a változás a commitban dokumentálva.

## Eredmény (2.32.0)

- `Model.lua`:
  - `M.LevelWeight`: egy harc súlya a mostani szintedhez: a saját szinteden 1, 5 szinttel arrébb 0,5, 10 szinttel 0,25 (`M.LEVEL_HALF = 5`). Szint nélküli harc teljes súllyal számít.
  - `M.WeighFights`: a harcok súllyal (másolatok, a mentett harcok nem változnak), és hogy honnan jönnek a számok.
  - `M.CalibrationNote`: egy sor a modell megjegyzései közé.
- `Combat.lua`, `C.Report`: a súlyozott harcok darabszámai és másodpercei a súllyal számítanak. Az arányok és az ütésenkénti sebzés nem változnak, csak az, mennyire bízik bennük a modell. Minden kaszt ugyanígy kalibrál: `mix(alap, mért, n, fél)`, ahol n egy darabszám vagy másodperc.
- `Game.lua`: a modell harcadata (`G.CombatReport(true, szint)`) súlyozott, mind a kilenc kasztnál. A Harc oldal statisztikája és tanácsai továbbra is az egész harcokat mutatják, súly nélkül.
- Honnan a számok: a Felszerelés oldalon a modell megjegyzései között, pl.:

  > Honnan a számok: 30 harc a(z) 30. szintről; a mostani (45.) szintedtől távolabbiak kevesebbet számítanak (5 szintenként fele súly): 1800 mp harcidőből 225 mp számít (13%).

- Teszt (t_talents), 30 harc csak a 30. szinten, paladin:
  - a 30-as becslés változatlan (80,2);
  - a 45-ös becslés eddig 80,4 volt (minden harc teljes súllyal), most 69,4, az alapérték 49,1;
  - az 55-ös eddig 80,6, most 59,0, az alapérték 50,9.

  Sok harcnál a 1/8 súly is érdemi marad (225 mp a keverés 120 mp-es felezőpontjához képest kb. 65% bizalom), ezért a 45-ös nem esik vissza teljesen. Távolabb egyre jobban visszaesik.
- A meglévő tesztek számai nem változtak (mind a 23 teszt átment): a tesztek harcai a modell szintjén vannak, vagy nem a pontos számot ellenőrzik.
- Nyitott: rangonkénti alapsebzés. A harcnapló (`Fights.lua`) a képességet névvel tárolja, a varázslat azonosítója és rangja nélkül. Ehhez az uploadernek a spell ID-t is ki kell írnia; addig a szint szerinti súly helyettesíti, mert a közeli szintek harcai a közeli rangokat mutatják.
