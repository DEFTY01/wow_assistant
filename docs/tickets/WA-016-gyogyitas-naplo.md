# WA-016 · Harcnapló: gyógyítási események

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 4. Gyógyítás | M | közepes | adat | nyitott |

**Előfeltétel:** nincs  
**Erre épül:** [WA-017](WA-017-gyogyito-keret.md)

## Cél

A feldolgozó rögzítse a saját gyógyításaidat: gyógyítás, túlgyógyítás, elnyelés, manaköltség.

## Miért

Gyógyítómodell nélkül a Holy és Discipline priest, a Holy paladin, a Restoration druid és shaman csak enchant-súlyokat kap. Ehhez először adat kell: ma a feldolgozó a gyógyítást egyáltalán nem olvassa.

## Teendők

- [ ] `SPELL_HEAL` és `SPELL_PERIODIC_HEAL`: összeg, túlgyógyítás, crit, célpont; a mezők helyét valódi naplóból ellenőrizni (a D6 mintájára).
- [ ] Elnyelés (Power Word: Shield): `SPELL_ABSORBED`, ha a Forever naplója tartalmazza.
- [ ] Harcszegmentálás gyógyítónak: a harc akkor is tart, ha te nem sebzel, csak gyógyítasz.
- [ ] Feltöltő és `Fights.lua`: új `heals` mező; a régi harcok működnek nélküle.
- [ ] Döntés a `DECISIONS.md`-be a mezők helyéről.

## Elfogadás

- Egy valódi naplóban a gyógyítás és a túlgyógyítás összege egyezik egy kézzel ellenőrzött mintával.
