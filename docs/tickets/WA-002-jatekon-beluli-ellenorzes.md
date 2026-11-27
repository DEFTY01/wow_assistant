# WA-002 · Játékon belüli ellenőrzés: mage, warrior, priest, paladin

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 0. Stabilizálás | S | magas | ellenőrzés | nyitott |

**Előfeltétel:** nincs  
**Erre épül:** nincs

## Cél

A négy új kaszt minden oldala (Haditerv, Felszerelés, Harc, enchantok) helyesen jelenjen meg a játékban.

## Miért

A 2.14–2.17 csak szintetikus teszteken (fengari) és egy valódi naplón futott. Senki nem nézte meg az ablakot élőben: elcsúszó szöveg, hiányzó fordítás, ő/ű megjelenés, Lua-hiba csak ott derül ki.

## Teendők

- [ ] Ellenőrzőlista minden kaszthoz: `/wa` megnyílik; Haditerv, Felszerelés, Harc oldal és az enchant rész Lua-hiba nélkül; a kasztösszesítő kártyái; a tanácsok szövege; ő/ű.
- [ ] Ha van ilyen karaktered: legalább egy mage- és egy warrior-harc a valódi naplóban, és futtatni rajtuk a `real_pr.mjs`-t és a valódi-adat tesztet, ahogy a priestnél és a paladinnál.
- [ ] A talált hibák javítása, külön commitban.

## Elfogadás

- Mind a négy kasztnál Lua-hiba nélkül nyílik minden oldal.
- A mage és a warrior modellje egy valódi naplón is ellenőrizve van (ha van ilyen karaktered), vagy a ticket leírja, hogy nincs adat.

## Megjegyzés

A felhasználónak kell játékban lennie; Claude az ellenőrzőlistát és a naplóelemzést adja.
