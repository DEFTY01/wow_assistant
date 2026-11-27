# Waystone: fejlesztési út és ticketek

Állapot: 2.17.0 (mind a kilenc kasztnak van sebzésmodellje). A ticketek a fennmaradó munkát fedik le, a javasolt sorrendben.

## Javasolt út

1. **Stabilizálás.** Előbb a meglévő munka legyen biztos: egy valódi hiba a paladin tanácsban (WA-001), és a négy új kaszt még nincs játékban ellenőrizve (WA-002). Olcsó, és minden későbbi munka erre épül.
2. **Alapok.** A rotációs javaslathoz két dolog kell: szintenként helyes kalibráció (WA-004), és az aurák időpontjai, nem csak az összidejük (WA-005). Enélkül a javaslatok egy szinthez lennének hangolva, és nem lehetne bizonyítani semmit, ami időzítésről szól.
3. **Rotációs javaslatok.** Ezt kérted, és itt a legnagyobb a haszon: minden sebző karakternek. Előbb a közös keret egy kaszttal (WA-006 + WA-007, rogue, mert ott van a legtöbb ellenőrzött adat), utána a többi nyolc kaszt egymástól függetlenül, akár párhuzamosan.
4. **Gyógyítás**, aztán **tankolás.** Mindkettő új adatot igényel a naplóból, és kevesebb karaktert érint, mint a sebzés. A gyógyítás előbb jön, mert négy kasztot érint, a tankolás hármat.
5. **Referencia, szabályok, webapp.** A WoWSims-referencia kutatás (WA-027) bármikor mehet; az új bizonyítható hibák (WA-028) a rotációs munka természetes folytatása; a webapp sorsa (WA-029) döntés, amit érdemes korán meghozni, de nem blokkol semmit.

Méret: **S** néhány óra, **M** egy-két munkamenet, **L** több munkamenet.

## Ticketek

### 0. Stabilizálás

| Ticket | Cím | Méret | Prioritás | Előfeltétel |
|---|---|---|---|---|
| [WA-001](WA-001-paladin-seal-aura.md) | Paladin: a seal ideje a harcnapló aura-adataiból | S | magas | – |
| [WA-002](WA-002-jatekon-beluli-ellenorzes.md) | Játékon belüli ellenőrzés: mage, warrior, priest, paladin | S | magas | – |
| [WA-003](WA-003-regi-mappak.md) | Döntés: a régi SessionBar és AzerothChronicle mappák | S | közepes | – |

### 1. Alapok (adat és kalibráció)

| Ticket | Cím | Méret | Prioritás | Előfeltétel |
|---|---|---|---|---|
| [WA-004](WA-004-szintfuggo-kalibracio.md) | Szintfüggő kalibráció | M | magas | – |
| [WA-005](WA-005-aura-idovonal.md) | Aura-idővonal a harcnaplóból | M | magas | – |

### 2. Rotációs javaslatok

| Ticket | Cím | Méret | Prioritás | Előfeltétel |
|---|---|---|---|---|
| [WA-006](WA-006-rotacio-keret.md) | Rotációs javaslat: közös keret és felület | L | magas | WA-004, WA-005 |
| [WA-007](WA-007-rotacio-rogue.md) | Rotációs javaslat: Rogue | M | közepes | WA-006 |
| [WA-008](WA-008-rotacio-warrior.md) | Rotációs javaslat: Warrior | M | közepes | WA-006 |
| [WA-009](WA-009-rotacio-mage.md) | Rotációs javaslat: Mage | M | közepes | WA-006 |
| [WA-010](WA-010-rotacio-warlock.md) | Rotációs javaslat: Warlock | M | közepes | WA-006 |
| [WA-011](WA-011-rotacio-hunter.md) | Rotációs javaslat: Hunter | M | közepes | WA-006 |
| [WA-012](WA-012-rotacio-shaman.md) | Rotációs javaslat: Shaman | M | közepes | WA-006 |
| [WA-013](WA-013-rotacio-druid.md) | Rotációs javaslat: Druid | M | közepes | WA-006 |
| [WA-014](WA-014-rotacio-priest.md) | Rotációs javaslat: Priest | M | közepes | WA-006 |
| [WA-015](WA-015-rotacio-paladin.md) | Rotációs javaslat: Paladin | M | közepes | WA-006, WA-001 |

### 3. Gyógyítás

| Ticket | Cím | Méret | Prioritás | Előfeltétel |
|---|---|---|---|---|
| [WA-016](WA-016-gyogyitas-naplo.md) | Harcnapló: gyógyítási események | M | közepes | – |
| [WA-017](WA-017-gyogyito-keret.md) | Gyógyító keret: HPS, túlgyógyítás, mana | L | közepes | WA-016 |
| [WA-018](WA-018-gyogyitas-priest.md) | Gyógyítómodell: Priest | M | alacsony | WA-017 |
| [WA-019](WA-019-gyogyitas-paladin.md) | Gyógyítómodell: Paladin | M | alacsony | WA-017 |
| [WA-020](WA-020-gyogyitas-druid.md) | Gyógyítómodell: Druid | M | alacsony | WA-017 |
| [WA-021](WA-021-gyogyitas-shaman.md) | Gyógyítómodell: Shaman | M | alacsony | WA-017 |

### 4. Tankolás

| Ticket | Cím | Méret | Prioritás | Előfeltétel |
|---|---|---|---|---|
| [WA-022](WA-022-tank-naplo.md) | Harcnapló: elszenvedett sebzés és védekezés | M | alacsony | – |
| [WA-023](WA-023-tank-keret.md) | Tank keret: kivédés, mitigáció, fenyegetés | L | alacsony | WA-022 |
| [WA-024](WA-024-tank-warrior.md) | Tankmodell: Protection warrior | M | alacsony | WA-023 |
| [WA-025](WA-025-tank-paladin.md) | Tankmodell: Protection paladin | M | alacsony | WA-023 |
| [WA-026](WA-026-tank-druid.md) | Tankmodell: Feral (medve) druid | M | alacsony | WA-023 |

### 5. Referencia, szabályok, webapp

| Ticket | Cím | Méret | Prioritás | Előfeltétel |
|---|---|---|---|---|
| [WA-027](WA-027-wowsims-referencia.md) | WoWSims Forever referencia 60-as szinten | M | alacsony | – |
| [WA-028](WA-028-bizonyithato-hibak.md) | Új bizonyítható hibaszabályok | M | közepes | WA-005, WA-006 |
| [WA-029](WA-029-webapp-paritas.md) | Webapp: a kasztmodellek és a játék közötti különbség | M | alacsony | – |

## Függőségek röviden

- WA-004, WA-005 → WA-006 → WA-007 … WA-015 (a WA-015 a WA-001-et is igényli)
- WA-005, WA-006 → WA-028
- WA-016 → WA-017 → WA-018 … WA-021
- WA-022 → WA-023 → WA-024 … WA-026
- WA-001, WA-002, WA-003, WA-027, WA-029: önállóak

## Szabályok, amelyek minden ticketre érvényesek

- Minden megjelenített szám visszakövethető (Wowhead Forever, WoWSims Forever motor, vagy mért adat a naplóból).
- Hiba csak akkor, ha a harcadat és egy Foreverre ellenőrzött szabály igazolja; különben megfigyelés, nem megállapítható vagy mért adat.
- Generált Wowhead-adat nem kerül a repóba.
- Magyar felület, ő/ű helyesen.
