# WA-007b · Rotációs javaslat: Rogue – Combat

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 3. Rotációs javaslatok | M | közepes | új funkció | kész (2.34.0) |

**Előfeltétel:** [WA-006](WA-006-rotacio-keret.md), [WA-032a](WA-032a-talent-rogue.md)  
**Erre épül:** nincs

## Cél

Rogue – Combat: számításokkal alátámasztott rotáció a WA-006 keretében, a karakter szintjén elérhető képességekkel és rangokkal.

## Miért

A spec dönti el, mely képességek és talentek számítanak: két spec rotációja teljesen más lehet. A keret a kaszt modelljéből számol, ez a ticket a spec saját képességeit és szabályait adja hozzá.

## Teendők

- [x] Sinister Strike energiánként a normalizált fegyversebességgel; két fegyver és a mellékkéz.
- [x] Slice and Dice és Eviscerate combo pontonként (a bizonyított Eviscerate-szabállyal összhangban).
- [x] Shank (10 mp, Forever), Blade Flurry, Adrenaline Rush: mikor és milyen harcban.
- [x] A talentek hatása csak akkor kerül a számításba, ha a Wowhead Forever vagy a WoWSims Forever motor igazolja; ami nem ellenőrizhető, az megfigyelés.
- [x] A javaslat összevetése a harcaid mért arányaival; a különbség DPS-ben.
- [x] Teszt a kaszt tesztfájljában ezzel a speccel; valódi naplón is, ha van ilyen specű harc.

## Elfogadás

- A Harc oldalon ennél a specnél megjelenik a "Javasolt rotáció", minden számmal és forrással.
- Más spec esetén ez a rotáció nem jelenik meg.

## Eredmény (2.34.0)

Az első spec a WA-006 keretében. Minden szám forrása:

- Wowhead Forever spelladat (nether.wowhead.com/forever/tooltip/spell/…, 2026-11-27):
  - Sinister Strike rangok (1752 … 11294): 45 energia, +3 … +68 sebzés a fegyveren felül, 1 combo pont;
  - Eviscerate trénerrangok (2098 … 11300): 35 energia, min–max + pontonkénti sebzés; a 9. rang (31016, 60) könyv, nem tréner;
  - Slice and Dice: 1. rang (5171, 10-től) +20%, a 2. rang (6774, 42-től) +30% támadási sebesség; 25 energia, 9–21 mp;
  - Shank (Forever): 1. rang (1329283, 24-től) 15, a 2. rang (1329549, 44-től) 25 energiát ad; 5 energia, 10 mp cooldown;
  - Blade Flurry (13877): 25 energia, 2 perc, +20% 15 mp-ig; Adrenaline Rush (13750): 5 perc, +100% energia 15 mp-ig.
- WoWSims Forever d5144855:
  - `sim/rogue/eviscerate.go`: pontonként 4% AP;
  - `sim/rogue/slice_and_dice.go`: (6 + 3 × pont) × (1 + Improved Slice and Dice);
  - `sim/rogue/shank.go`: off-hand, 50% fegyversebzés (× 0,5 off-hand), nem lehet kivédeni, nem ad combo pontot, Flash of Steel: + energia, − cooldown;
  - `sim/core/energy.go:49`: 0,1 mp-enként 1 energia;
  - `ui/specs/rogue/dps/apls/default.apl.json`: a sorrend (Blade Flurry, Adrenaline Rush 50 energia alatt, Shank 80 energia alatt, Slice and Dice amint lejár, Eviscerate 5 ponttal, Sinister Strike).
- A talentek rangja és a számaik a Wowhead Forever talentadatból: Flash of Steel, Improved Slice and Dice, Blade Flurry, Adrenaline Rush, valamint a modell meglévő talentjei (Ruthlessness, Seal Fate, Relentless Strikes, Aggression, Coup de Grace, Dual Wield Specialization).

Mit számol:

- Energia-költségvetés: 10 energia másodpercenként, plusz a Shank nettó energiája; ebből megy a Slice and Dice fenntartása, a maradék a Sinister Strike + 5 pontos Eviscerate körre.
- A Slice and Dice pontszámát kiszámolja (nélküle, 1–5 ponttal, mind a hat DPS-t kiírja), az átlagos harcod hosszával: a nyitásnál a pontokat nulláról kell felépíteni, ezért rövid harcban kevesebb ideig van fent.
- Az 5 pontos Eviscerate sebzése a mért ütésenkénti sebzésedből, a rang képletével átszámolva 5 pontra; harcok nélkül a képletből.
- Cooldownok: egy használat értéke sebzésben (a fenti DPS-ben nincs benne, mert attól függ, milyen gyakran éred el).
- Feltételezések, kiírva: egy célpont, hátulról; a kihagyott Sinister Strike energiáját elveszettnek veszi (a visszatérítés aránya nincs ellenőrizve).

Teszt (`t_rotation.lua`):

- harcok nélkül: a sorrend, a rangok a szinthez (Shank 24-től és off-hand fegyverrel, a 2. rang 44-től; Slice and Dice 30% 42-től), az Eviscerate képlete számra pontosan, a Slice and Dice ideje az Improved Slice and Dice-szal;
- spec: Assassination és Subtlety nem kap rotációt, a WA-007a / WA-007c ticketet nevezi meg; más kaszt a sajátját;
- mért harcokkal: a képességenkénti különbségek összege pontosan a teljes különbség; rövid harcban a Slice and Dice kevesebbet ér; a 2. rang többet ér;
- a rogue saját valódi naplójának 200 harcával (csak a scratchpadben): a mért oszlop kitöltve, a részek összeadódnak;
- a Harc oldal része (táblák, Honnan oszlop, kirajzolás), Assassination specnél a ticket sora, és a Haditerv sora.
