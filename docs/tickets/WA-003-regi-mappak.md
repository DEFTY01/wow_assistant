# WA-003 · Döntés: a régi SessionBar és AzerothChronicle mappák

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 0. Stabilizálás | S | közepes | döntés | nyitott |

**Előfeltétel:** nincs  
**Erre épül:** nincs

## Cél

Eldönteni, hogy a régi addonmappák (üres shimek) maradnak-e, és ha nem, mikor és hogyan törlődnek.

## Miért

A D8 döntés szerint a régi mappákban egy shim maradt, hogy a kliens betöltse a régi SavedVariables-t, és a Waystone veszteség nélkül átmásolja. Ha már mindenki átállt, a shim felesleges. A törlés visszafordíthatatlan, ezért jóváhagyás kell.

## Teendők

- [ ] Megnézni a saját mentéseidet: átmásolódott-e minden a `WowAssistantDB.session` és `.chronicle` alá.
- [ ] Döntés: maradnak / törlődnek. Ha törlődnek: a `## OptionalDeps` sor eltávolítása, a CurseForge-leírás frissítése, egy figyelmeztetés a CHANGELOG-ban.

## Elfogadás

- A döntés bekerül a `docs/DECISIONS.md`-be.
- Törlés csak a felhasználó kifejezett jóváhagyásával.
