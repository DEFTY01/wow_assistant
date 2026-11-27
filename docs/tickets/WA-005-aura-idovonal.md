# WA-005 · Aura-idővonal a harcnaplóból

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 1. Alapok (adat és kalibráció) | M | magas | adat | kész (2.33.0) |

**Előfeltétel:** nincs  
**Erre épül:** [WA-006](WA-006-rotacio-keret.md), [WA-028](WA-028-bizonyithato-hibak.md)

## Cél

A feldolgozó ne csak az aurák összidejét rögzítse, hanem a be- és kikapcsolás időpontjait is, a castokkal közös idővonalon.

## Miért

A rotációs javaslatok és az új bizonyítható hibák kérdései időpontokról szólnak: fent volt-e a Slice and Dice, amikor lejárt; melyik seal volt fent a Judgementnél; fent volt-e a Shadow Word: Pain a Mind Flay alatt. Ma csak az összidő van meg.

## Teendők

- [x] `scripts/combat-log.mjs`: harconként `auraLog = { { t, name, on/off } }` a saját BUFF-okra és a célponton lévő saját DEBUFF-okra (DoT-ok, Sunder Armor, Faerie Fire).
- [x] Feltöltő és `Fights.lua`: a mező továbbítása, méretkorláttal.
- [x] `Combat.lua`: segédfüggvény: "fent volt-e X a t időpontban", "mennyi idő telt el a lejárattól az újrarakásig".
- [x] Tesztek valódi naplórészlettel.

## Elfogadás

- A rogue Slice and Dice és a priest SW:P uptime ugyanazt adja az idővonalból, mint az összidőből.
- A régi `Fights.lua` (idővonal nélkül) is működik.

## Eredmény (2.33.0)

- `scripts/combat-log.mjs`: harconként `auraLog`, a castokkal közös órán (tized másodperc a harc elejétől): `[t, név, 1 be / 0 ki, "b" buff rajtad / "d" a te debuffod egy ellenfélen]`.
  - Egy buff, ami a harc elején már fent volt, 0-nál kezdődik. A lekerülés ugyanúgy a harc utolsó pillanatára vágva, ahogy az összidőnél.
  - Egy debuff addig van fent, amíg legalább egy ellenfélen rajta van; ha az ellenfél meghal, lekerül róla.
  - Harconként legfeljebb 200 változás; ha több, az `auraLogCut` mondja meg, honnantól hiányzik. Egy valódi napló 199 harcában a legtöbb 50 volt, átlagosan kb. 370 bájt harconként.
- `scripts/uploader.mjs`: a `Fights.lua`-ba is beírja (`auraLog`, `auraLogCut`).
- `Combat.lua`, segédfüggvények:
  - `C.AuraAt(f, név, t)`: fent volt-e;
  - `C.AuraIntervals`, `C.AuraUptime`: mikor és mennyi ideig volt fent;
  - `C.AuraGaps`: mennyi idő telt el a lejárattól az újrarakásig, vagy a harc végéig, ha nem rakta vissza.

  Idővonal nélküli (régi) harcnál, és a vágás után, mindegyik nil-t ad (ismeretlen), soha nem azt, hogy "nem volt fent".
- Teszt (t_aura), egy valódi napló részletével (a teszt a scratchpadben olvassa a naplót, a repóba semmi nem kerül belőle):
  - rogue Slice and Dice, 40 harc: az idővonalból 456,5 mp, az összidőből 456,0 mp; harconként legfeljebb 0,1 mp az eltérés (a tized másodpercre kerekítés miatt);
  - priest Shadow Word: Pain, 3 harc: mind a 18 tick egy olyan időre esik, amikor az idővonal szerint fent volt. A debuffoknak eddig nem volt összideje, ezért itt a tickek az ellenőrzés;
  - kitalált harcon: fent volt-e, a lejárattól az újrarakásig eltelt idő, a vágás, és egy régi harc idővonal nélkül (a harcjelentés ugyanúgy olvassa).
- Az új mezőt csak a frissített uploader írja: a régi harcok idővonal nélkül maradnak, és ugyanúgy működnek.
