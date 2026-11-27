# WA-001 · Paladin: a seal ideje a harcnapló aura-adataiból

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 0. Stabilizálás | S | magas | hibajavítás | kész (2.17.1) |

**Előfeltétel:** nincs  
**Erre épül:** [WA-015](WA-015-rotacio-paladin.md)

## Cél

A paladin tanács használja a harcnaplóban rögzített seal-aurák idejét, és ne állítsa, hogy ez az adat hiányzik.

## Miért

A `Paladin.lua` "Nem sebez seal" megfigyelése azt írja: "a harcnapló aura-eseményeit az addon nem rögzíti". Ez nem igaz: a `scripts/combat-log.mjs` minden saját BUFF aurát harconként rögzít (`fight.auras`), a feltöltő továbbadja, a `Combat.lua` beolvassa (a Slice and Dice és az Aspect of the Hawk már így működik). A valódi naplóban a seal BUFF-ként szerepel (pl. `20915 Seal of Command`, `20419 Seal of Fury`). A tanács tehát hamisan állít adathiányt, ami sérti a "minden szám visszakövethető" elvet.

## Teendők

- [x] A paladin harcaiból kiolvasni a seal-aurák idejét (Seal of Righteousness, Seal of Command, Seal of Fury és a többi seal).
- [x] A "Paladin összesítő" mutassa, melyik seal hány százalékban volt fent.
- [x] A "Nem sebez seal" tanács: ha a naplóból látszik, hogy sebző seal volt fent és mégsem sebzett, ez megfigyelés a pontos számokkal; ha nem sebző seal (pl. Seal of Fury, Seal of Wisdom) volt fent, azt nevezze meg.
- [x] Hiba csak akkor, ha a `sealDamage` szabály és az aura-adat együtt igazolja (pl. a harc 100%-ában nem sebző seal volt fent, és sok fehér ütés volt). Ehhez a szabály szövegét a Forever adatai szerint ellenőrizni.
- [x] A hamis "nem rögzíti" szöveg törlése.
- [x] Teszt a `t_paladin.lua`-ban aura-adattal és anélkül (élő mérő harca, ahol nincs aura).

## Elfogadás

- A valódi naplóban Alexforte és Laliore harcainál megjelenik a seal ideje.
- Élő mérő harcánál (aura nélkül) a tanács "nem megállapítható", és megmondja, miért.
- Mind a 22 teszt átmegy.

## Megjegyzés

Ez a 2.17.0 hibája; érdemes 2.17.1-ként kiadni.

## Eredmény (2.17.1)

- A seal idejét a naplózott harcok aura-adataiból számolja (`PA.SealUptime`); az élő mérő harcai kimaradnak, mert azokban nincs aura.
- Hiba nem lett belőle: a nem sebző seal (Crusader, Wisdom, Light, Justice) választható másik haszonért, és hogy megérte-e, az a harcadatból nem mérhető. Megfigyelés marad, a seal nevével és idejével.
- Közben kiderült: a Seal of Fury Foreveren sebez (spell=20419), a modell eddig az "egyéb" közé sorolta. Most sebző seal; a `sealDamage` szabály szövege is javítva.
- Valódi naplón: Alexforte (Seal of Command 86%), Absolon (Seal of Fury 66%, a seal a sebzés 29%-a). Laliore-nak csak 52 mp harca van, ott még nincs elég adat.
