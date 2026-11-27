# Waystone: fejlesztési út és ticketek

Állapot: 2.17.1 (mind a kilenc kasztnak van sebzésmodellje). A ticketek a fennmaradó munkát fedik le, a javasolt sorrendben.

## Javasolt út

1. **Stabilizálás.** Előbb a meglévő munka legyen biztos: egy valódi hiba a paladin tanácsban (WA-001), és a négy új kaszt még nincs játékban ellenőrizve (WA-002). Olcsó, és minden későbbi munka erre épül.
2. **Alapok.** Szintenként helyes kalibráció (WA-004), és az aurák időpontjai, nem csak az összidejük (WA-005). Enélkül minden későbbi számítás egy szinthez lenne hangolva, és nem lehetne bizonyítani semmit, ami időzítésről szól.
3. **Talentek és spec.** Alapszabály: minden számítás a talentjeiddel és a speceddel számol. Előbb az adat (WA-031: a Forever saját talentfái a játékból és a Wowhead Forever adataiból), aztán a közös keret (WA-032), majd kasztonként mindhárom fa minden talentje (WA-032a – WA-032i). Erre épül a talentérték a jelenlegi gearrel (WA-033: mennyit ér egy talent, mennyit a következő pont, és mire hat még), a talent calculator a játékban (WA-034, új Talentek oldal) és a specfelismerés (WA-030).
4. **Rotációs javaslatok, specenként.** Ezt kérted, és itt a legnagyobb a haszon. A rotáció a spectől függ (egy Fire és egy Frost mage, egy Arms és egy Fury warrior mást csinál), ezért specenként van egy-egy ticket, 22 darab. Előbb a közös keret egy speccel (WA-006 + WA-007b, Combat rogue, mert ott van a legtöbb ellenőrzött adat), utána a többi spec egymástól függetlenül, akár párhuzamosan. A tank és gyógyító specek szólózó (sebző) rotációja is itt van; a tankolás és a gyógyítás az 5. és 6. fázisban. Minden spec-ticket a kasztja talenthatásaira épül.
5. **Gyógyítás**, aztán **tankolás.** Mindkettő új adatot igényel a naplóból, és kevesebb karaktert érint, mint a sebzés. A gyógyítás előbb jön, mert négy kasztot érint, a tankolás hármat.
6. **Referencia, szabályok, webapp.** A WoWSims-referencia kutatás (WA-027) bármikor mehet; az új bizonyítható hibák (WA-028) a rotációs munka természetes folytatása; a webapp sorsa (WA-029) döntés, amit érdemes korán meghozni, de nem blokkol semmit.

Méret: **S** néhány óra, **M** egy-két munkamenet, **L** több munkamenet.

## Ticketek

### 0. Stabilizálás

| Ticket | Cím | Méret | Prioritás | Előfeltétel |
|---|---|---|---|---|
| [WA-001](WA-001-paladin-seal-aura.md) | Paladin: a seal ideje a harcnapló aura-adataiból (kész, 2.17.1) | S | magas | – |
| [WA-002](WA-002-jatekon-beluli-ellenorzes.md) | Játékon belüli ellenőrzés: mage, warrior, priest, paladin | S | magas | – |
| [WA-003](WA-003-regi-mappak.md) | Döntés: a régi SessionBar és AzerothChronicle mappák | S | közepes | – |

### 1. Alapok (adat és kalibráció)

| Ticket | Cím | Méret | Prioritás | Előfeltétel |
|---|---|---|---|---|
| [WA-004](WA-004-szintfuggo-kalibracio.md) | Szintfüggő kalibráció | M | magas | – |
| [WA-005](WA-005-aura-idovonal.md) | Aura-idővonal a harcnaplóból | M | magas | – |

### 2. Talentek és spec

| Ticket | Cím | Méret | Prioritás | Előfeltétel |
|---|---|---|---|---|
| [WA-030](WA-030-spec-felismeres.md) | Specfelismerés és specfüggő modellek | M | magas | WA-031 |
| [WA-031](WA-031-talent-adatok.md) | Talentadatok: a Forever talentfái (kész, 2.18.0) | M | magas | – |
| [WA-032](WA-032-talent-hatas-keret.md) | Talenthatások a modellben: közös keret (kész, 2.19.0) | M | magas | WA-031 |
| [WA-032a](WA-032a-talent-rogue.md) | Talenthatások: Rogue, mindhárom fa (kész, 2.20.0) | M | magas | WA-032 |
| [WA-032b](WA-032b-talent-warrior.md) | Talenthatások: Warrior, mindhárom fa (kész, 2.21.0) | M | magas | WA-032 |
| [WA-032c](WA-032c-talent-mage.md) | Talenthatások: Mage, mindhárom fa (kész, 2.22.0) | M | magas | WA-032 |
| [WA-032d](WA-032d-talent-warlock.md) | Talenthatások: Warlock, mindhárom fa (kész, 2.23.0) | M | magas | WA-032 |
| [WA-032e](WA-032e-talent-hunter.md) | Talenthatások: Hunter, mindhárom fa (kész, 2.24.0) | M | magas | WA-032 |
| [WA-032f](WA-032f-talent-shaman.md) | Talenthatások: Shaman, mindhárom fa (kész, 2.25.0) | M | magas | WA-032 |
| [WA-032g](WA-032g-talent-druid.md) | Talenthatások: Druid, mindhárom fa (kész, 2.26.0) | M | magas | WA-032 |
| [WA-032h](WA-032h-talent-priest.md) | Talenthatások: Priest, mindhárom fa (kész, 2.27.0) | M | magas | WA-032 |
| [WA-032i](WA-032i-talent-paladin.md) | Talenthatások: Paladin, mindhárom fa (kész, 2.28.0) | M | magas | WA-032 |
| [WA-033](WA-033-talent-ertek.md) | Talentérték a jelenlegi gearrel | M | magas | WA-032 |
| [WA-034](WA-034-talent-kalkulator.md) | Talent calculator a játékban | L | magas | WA-031, WA-033 |

### 3. Rotációs javaslatok

| Ticket | Cím | Méret | Prioritás | Előfeltétel |
|---|---|---|---|---|
| [WA-006](WA-006-rotacio-keret.md) | Rotációs javaslat: közös keret és felület | L | magas | WA-004, WA-005, WA-030 |
| [WA-007a](WA-007a-rotacio-rogue-assassination.md) | Rotációs javaslat: Rogue – Assassination | M | közepes | WA-006, WA-032a |
| [WA-007b](WA-007b-rotacio-rogue-combat.md) | Rotációs javaslat: Rogue – Combat | M | közepes | WA-006, WA-032a |
| [WA-007c](WA-007c-rotacio-rogue-subtlety.md) | Rotációs javaslat: Rogue – Subtlety | M | közepes | WA-006, WA-032a |
| [WA-008a](WA-008a-rotacio-warrior-arms.md) | Rotációs javaslat: Warrior – Arms | M | közepes | WA-006, WA-032b |
| [WA-008b](WA-008b-rotacio-warrior-fury.md) | Rotációs javaslat: Warrior – Fury | M | közepes | WA-006, WA-032b |
| [WA-009a](WA-009a-rotacio-mage-arcane.md) | Rotációs javaslat: Mage – Arcane | M | közepes | WA-006, WA-032c |
| [WA-009b](WA-009b-rotacio-mage-fire.md) | Rotációs javaslat: Mage – Fire | M | közepes | WA-006, WA-032c |
| [WA-009c](WA-009c-rotacio-mage-frost.md) | Rotációs javaslat: Mage – Frost | M | közepes | WA-006, WA-032c |
| [WA-010a](WA-010a-rotacio-warlock-affliction.md) | Rotációs javaslat: Warlock – Affliction | M | közepes | WA-006, WA-032d |
| [WA-010b](WA-010b-rotacio-warlock-demonology.md) | Rotációs javaslat: Warlock – Demonology | M | közepes | WA-006, WA-032d |
| [WA-010c](WA-010c-rotacio-warlock-destruction.md) | Rotációs javaslat: Warlock – Destruction | M | közepes | WA-006, WA-032d |
| [WA-011a](WA-011a-rotacio-hunter-bm.md) | Rotációs javaslat: Hunter – Beast Mastery | M | közepes | WA-006, WA-032e |
| [WA-011b](WA-011b-rotacio-hunter-mm.md) | Rotációs javaslat: Hunter – Marksmanship | M | közepes | WA-006, WA-032e |
| [WA-011c](WA-011c-rotacio-hunter-survival.md) | Rotációs javaslat: Hunter – Survival | M | közepes | WA-006, WA-032e |
| [WA-012a](WA-012a-rotacio-shaman-elemental.md) | Rotációs javaslat: Shaman – Elemental | M | közepes | WA-006, WA-032f |
| [WA-012b](WA-012b-rotacio-shaman-enhancement.md) | Rotációs javaslat: Shaman – Enhancement | M | közepes | WA-006, WA-032f |
| [WA-013a](WA-013a-rotacio-druid-balance.md) | Rotációs javaslat: Druid – Balance | M | közepes | WA-006, WA-032g |
| [WA-013b](WA-013b-rotacio-druid-feral-cat.md) | Rotációs javaslat: Druid – Feral (macska) | M | közepes | WA-006, WA-032g |
| [WA-014a](WA-014a-rotacio-priest-shadow.md) | Rotációs javaslat: Priest – Shadow | M | közepes | WA-006, WA-032h |
| [WA-014b](WA-014b-rotacio-priest-holy-disc-szolo.md) | Rotációs javaslat: Priest – Holy és Discipline (szólózás) | M | közepes | WA-006, WA-032h |
| [WA-015a](WA-015a-rotacio-paladin-ret.md) | Rotációs javaslat: Paladin – Retribution | M | közepes | WA-006, WA-032i |
| [WA-015b](WA-015b-rotacio-paladin-holy-prot-szolo.md) | Rotációs javaslat: Paladin – Holy és Protection (szólózás) | M | közepes | WA-006, WA-032i |

### 4. Gyógyítás

| Ticket | Cím | Méret | Prioritás | Előfeltétel |
|---|---|---|---|---|
| [WA-016](WA-016-gyogyitas-naplo.md) | Harcnapló: gyógyítási események | M | közepes | – |
| [WA-017](WA-017-gyogyito-keret.md) | Gyógyító keret: HPS, túlgyógyítás, mana | L | közepes | WA-016, WA-032 |
| [WA-018](WA-018-gyogyitas-priest.md) | Gyógyítómodell: Priest | M | alacsony | WA-017 |
| [WA-019](WA-019-gyogyitas-paladin.md) | Gyógyítómodell: Paladin | M | alacsony | WA-017 |
| [WA-020](WA-020-gyogyitas-druid.md) | Gyógyítómodell: Druid | M | alacsony | WA-017 |
| [WA-021](WA-021-gyogyitas-shaman.md) | Gyógyítómodell: Shaman | M | alacsony | WA-017 |

### 5. Tankolás

| Ticket | Cím | Méret | Prioritás | Előfeltétel |
|---|---|---|---|---|
| [WA-022](WA-022-tank-naplo.md) | Harcnapló: elszenvedett sebzés és védekezés | M | alacsony | – |
| [WA-023](WA-023-tank-keret.md) | Tank keret: kivédés, mitigáció, fenyegetés | L | alacsony | WA-022, WA-032 |
| [WA-024](WA-024-tank-warrior.md) | Tankmodell: Protection warrior | M | alacsony | WA-023 |
| [WA-025](WA-025-tank-paladin.md) | Tankmodell: Protection paladin | M | alacsony | WA-023 |
| [WA-026](WA-026-tank-druid.md) | Tankmodell: Feral (medve) druid | M | alacsony | WA-023 |

### 6. Referencia, szabályok, webapp

| Ticket | Cím | Méret | Prioritás | Előfeltétel |
|---|---|---|---|---|
| [WA-027](WA-027-wowsims-referencia.md) | WoWSims Forever referencia 60-as szinten | M | alacsony | – |
| [WA-028](WA-028-bizonyithato-hibak.md) | Új bizonyítható hibaszabályok | M | közepes | WA-005, WA-006 |
| [WA-029](WA-029-webapp-paritas.md) | Webapp: a kasztmodellek és a játék közötti különbség | M | alacsony | – |

## Függőségek röviden

- WA-031 → WA-032 → WA-032a … WA-032i (kasztonként); WA-032 → WA-033 → WA-034; WA-031 → WA-030
- WA-004, WA-005, WA-030 → WA-006 → WA-007a … WA-015b (specenként egy-egy, mindegyik a kasztja WA-032x ticketjére is épül)
- WA-005, WA-006 → WA-028
- WA-016, WA-032 → WA-017 → WA-018 … WA-021
- WA-022, WA-032 → WA-023 → WA-024 … WA-026
- WA-002, WA-003, WA-027, WA-029: önállóak (a WA-001 kész, 2.17.1)

## Szabályok, amelyek minden ticketre érvényesek

- Minden számítás a karakter talentjeivel és specjével számol; ha egy talent hatása nem ellenőrizhető, azt kiírja, nem hallgatja el.
- Minden megjelenített szám visszakövethető (Wowhead Forever, WoWSims Forever motor, vagy mért adat a naplóból).
- Hiba csak akkor, ha a harcadat és egy Foreverre ellenőrzött szabály igazolja; különben megfigyelés, nem megállapítható vagy mért adat.
- Generált Wowhead-adat nem kerül a repóba.
- Magyar felület, ő/ű helyesen.
