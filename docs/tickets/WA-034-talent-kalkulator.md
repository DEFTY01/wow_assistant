# WA-034 · Talent calculator a játékban

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Talentek és spec | L | magas | új funkció | kész (2.30.0) |

**Előfeltétel:** [WA-031](WA-031-talent-adatok.md), [WA-033](WA-033-talent-ertek.md)  
**Erre épül:** nincs

## Cél

Új "Talentek" oldal a `/wa` ablakban: a Forever talentfái, a jelenlegi pontjaid, és tervezés, minden talenthez az értékével a jelenlegi gearrel.

## Miért

A felhasználó kérése: "kell egy talent calculator in-game a játékba". A Talentek oldal mutatja meg egy helyen, mit ad egy build, és melyik pont ér a legtöbbet.

## Teendők

- [x] Három fa a kliens adataiból (ikon, sor, oszlop, rang/max. rang, előfeltétel-nyilak), WoW-stílusú ablakban, magyar felülettel.
- [x] Tooltip: a játék saját talent-leírása, alatta a Waystone számítása: a jelenlegi rangok és a következő pont értéke, mire hat (WA-033), és a forrás.
- [x] Tervezés: kattintással pont hozzáadása és elvétele egy tervben, a szabályokkal (szintenkénti pontok, soronként szükséges pontok, előfeltételek); a terv DPS-e a jelenlegihez képest, és a különbség forrásonként.
- [x] A legjobb következő pont kiemelése; több terv mentése karakterenként; terv megosztása szövegként.
- [x] A terv csak terv: az addon nem tanul talentet, azt a játék talent-ablakában te teszed meg.
- [x] Teszt: `t_talents.lua` kitalált fával (szabályok, érték, mentés), és a rajzolás a meglévő UI-tesztekben.

## Elfogadás

- A Talentek oldal mind a kilenc kasztnál megnyílik a valódi Forever-fákkal.
- Egy tervben a pontszabályok érvényesek, és a terv DPS-e számmal és forrással látszik.

## Eredmény (2.30.0)

- Új oldal a `/wa` ablakban: **Talentek** (`/wa talentek`). A `/wa talent` szöveges jelentése megmaradt.
- A három fa a játék saját adataiból (fa, ikon, sor, oszlop, rang, előfeltétel); ahol a kliens nem ad fát, a Wowhead Forever adatából. Minden talent ikonja a helyén, a rangja (pl. 3/5), az előfeltételek vonallal és nyílheggyel.
  - arany keret: a talent tele van; zöld: van benne pont, vagy most beletehetsz; szürke, színtelen ikon: zárva;
  - kék rang: a terv itt eltér a mostani talentjeidtől;
  - fénylő keret: a legtöbbet érő következő pont a tervben.
- Tooltip: a játék saját talent-leírása (ahol a kliens adja, különben a Wowhead Forever szövege), alatta a terv rangja, és ha nem tehetsz bele pontot, hogy miért. Utána a Waystone része, a mostani gearrel:
  - a tervben lévő rangok értéke és a következő pont értéke (DPS és %);
  - melyik stat ér miatta többet (WA-033);
  - a forrás (a rang Wowhead Forever szövege), vagy ha a modell nem számol vele, az oka.
- Tervezés: bal klikk egy pont a tervbe, jobb klikk egy pont ki. A játék szabályai (`T.PlanCheck`):
  - legfeljebb annyi pont, amennyi van (elköltött + szabad a játékból, különben szint − 9);
  - egy talentben legfeljebb a rangjai;
  - egy sorhoz soronként 5 pont kell alatta ugyanabban a fában;
  - az előfeltétel-talentben annyi rang, amennyit az adat kér (különben mind).
  Kivenni sem lehet olyan pontot, amire egy feljebb lévő talent épül. Ha nem megy, az oldal tetején kiírja, miért.
- A terv értéke (`T.PlanValue`): a modell DPS-e a tervvel a mostanihoz képest, és talentenként az a változás egyedül, a forrásával. A nem számolt talentek az okukkal szerepelnek, szám nélkül.
- Tervek karakterenként (`WowAssistantCharDB.talentPlans`): mentés, mentés újként, betöltés, törlés. A rajzolt terv /reload után is megmarad. Amíg ugyanaz, mint a mostani talentjeid, követi őket, ha új talentet tanulsz.
- Megosztás szövegként: `Waystone:KASZT:` és fánként a rangok sor és oszlop szerint, egy számjegy talentenként, a fák kötőjellel elválasztva (pl. `Waystone:ROGUE:-3`: az első fa üres, a másodikban az első talent 3 rang). Betöltéskor a kasztot és minden szabályt ellenőriz.
- A terv csak terv: az addon nem tanul talentet, azt a játék talent-ablakában te teszed meg.
- Teszt:
  - t_talents: egy kitalált fán a szabályok, a megosztás és a mentés;
  - a sámán terve a staff-fal: a terv többet ér, talentenként a forrással; a nem számolt talent ok, szám nélkül;
  - a mage kliensfáival az oldal és a kattintás;
  - mind a kilenc kaszt valódi Forever-fáival megnyílik az oldal (minden talent a saját helyén, az előfeltétel ugyanabban a fában).
  - t_draw: az oldal kirajzolása, egy pont be, egy zárt talent oka, mentés, üres terv, betöltés szövegből, egy másik kaszt terve elutasítva, keresés.
