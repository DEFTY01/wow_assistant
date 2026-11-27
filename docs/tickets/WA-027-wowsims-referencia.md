# WA-027 · WoWSims Forever referencia 60-as szinten

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 5. Referencia, szabályok, webapp | M | alacsony | kutatás | nyitott |

**Előfeltétel:** nincs  
**Erre épül:** nincs

## Cél

Megvizsgálni, hogyan köthető be a WoWSims Forever szimuláció referenciaként 60-as karaktereknél.

## Miért

A Harc oldal "Referencia-szimuláció" sora most "nem értékelhető": a motor nincs bekötve, és 60 alatt nem ad szintazonos referenciát.

## Teendők

- [ ] Kideríteni, a motor futtatható-e helyben (CLI vagy WASM), milyen bemenet kell (felszerelés, talentek, rotáció).
- [ ] Ha igen: a feltöltő futtassa 60-as karakterekre, és az eredményt írja a `Fights.lua` mellé.
- [ ] Ha nem: a sor szövegének pontosítása, és döntés a `DECISIONS.md`-be.

## Elfogadás

- Írásos döntés: bekötjük vagy nem, indokkal.

## Megjegyzés

Kutatási feladat; a megvalósítás külön ticket lesz, ha megéri.
