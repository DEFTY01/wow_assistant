# WA-004 · Szintfüggő kalibráció

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 1. Alapok (adat és kalibráció) | M | magas | modell | nyitott |

**Előfeltétel:** nincs  
**Erre épül:** [WA-006](WA-006-rotacio-keret.md)

## Cél

A modell más szintekre adott becslése ne igazodjon túlzottan ahhoz a szinthez, ahol a harcaid nagy része volt.

## Miért

Most minden kaszt a harcaidból kalibrál (arányok, alapsebzés, egyéb DPS), és ezt az összes szintre alkalmazza. Ha minden harcod 30-as szinten volt, a 45-ös becslés is a 30-as rotációt és rangokat tükrözi.

## Teendők

- [ ] A harcokat a szinttávolság szerint súlyozni (pl. a súly felére esik 5 szintenként); a rangfüggő értékeket (alapsebzés) rangonként kalibrálni, ne szintenként.
- [ ] A becslés mellé kiírni, hány harc és milyen szintekről kalibrált ("Honnan a számok").
- [ ] Közös segédfüggvény a `Model.lua`-ban, és mind a kilenc kaszt használja.
- [ ] Tesztek: harcok csak 30-on → a 30-as becslés változatlan, a 45-ös visszaesik a Wowhead-alapértékekre.

## Elfogadás

- Minden kasztnál látszik, honnan jön a kalibráció.
- A meglévő tesztek számai csak ott változnak, ahol a szinttávolság ezt indokolja; a változás a commitban dokumentálva.
