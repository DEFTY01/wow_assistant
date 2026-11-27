# WA-030 · Specfelismerés és specfüggő modellek

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 2. Talentek és spec | M | magas | modell | kész (2.31.0) |

**Előfeltétel:** [WA-031](WA-031-talent-adatok.md)  
**Erre épül:** [WA-006](WA-006-rotacio-keret.md)

## Cél

Minden kaszt modellje tudja, melyik specben vagy, és a spec szerint számoljon.

## Miért

Ma a spec csak néhány helyen számít: az enchant szerepnél (sebző, tank, gyógyító), a mage fő varázslatánál (Fire: Fireball, egyébként Frostbolt), a priest töltelék-varázslatánál (Shadow: Mind Flay) és a paladin sealjénél (Retribution: Seal of Command). A rogue, hunter, shaman, druid, warlock és warrior modellje nem ágazik el spec szerint, csak a harcaidból kalibrál. A rotációs javaslat specenként más, ezért ez előfeltétel.

## Teendők

- [x] Közös specfelismerés a `Model.lua`-ban: a tehetségfák pontjaiból a fő fa, és a kulcs-talentek (pl. Mortal Strike, Bloodthirst, Stormstrike) megléte; a kliens talent API-jából.
- [x] Kézi felülírás a felületen, ahogy az enchant szerepnél, ha valaki vegyes fát visz.
- [x] Minden kasztmodell kapja meg a specet: mely képességek számítanak, és a talentek hatása (csak a Wowhead Forever vagy a WoWSims Forever motor szerint ellenőrzött hatás).
- [x] A Harc oldal "Modell a kasztodhoz" sora mutassa, melyik spec szerint számol, és miből tudja.
- [x] Tesztek minden kasztra legalább két speccel.

## Elfogadás

- Mind a kilenc kasztnál látszik, melyik spec szerint számol a modell.
- Ugyanaz a karakter más spec mellett más képességlistát és súlyokat kap, ahol a talentek ezt indokolják.

## Eredmény (2.31.0)

- `Model.lua`, `M.Spec`: a spec az a talentfa, amelyikben a legtöbb pontod van.
  - Egyenlő pontszámnál az a fa, amelyikben mélyebb talented van, utána az első.
  - Bizonyítékként kiírja a fa mély talentjeit (5. sortól lefelé), amik megvannak (pl. 31 pontos Arms warriornál a Forever fa két legmélyebb talentje).
  - A pontokat a kliens talent API-ja adja; talent API nélkül a talentlistából és a Wowhead Forever adatából számol.
  - Talentpont nélkül nincs spec: minden modell a saját alapértelmezése szerint számol, és ezt ki is írja.
- Kézi felülírás a Harc oldalon, a "Modell a kasztodhoz" szakaszban: "Spec: automatikus", vagy a kaszt három specje közül egy. Karakterenként mentődik (`WowAssistantCharDB.spec`). Ilyenkor azt is kiírja, mit adnának a talentjeid.
- Minden kasztmodell megkapja a specet (`input.spec`, `input.tab`, és a kontextusban `ctx.spec`). A specfüggő elágazások (a Balance druid varázsló-modellje, a mage fő varázslata, a priest Mind Flayje, a paladin seal-je talentadat nélkül) mostantól ebből dolgoznak, így a kézi választás is hat rájuk. Az enchant szerepe szintén.
- A rogue, a hunter, a shaman, a warlock és a warrior modellje nem ágazik el külön spec szerint. Náluk a spec a talentjeiken keresztül hat (WA-032a–i, csak a Wowhead Forever szerint ellenőrzött hatások), és a harcaidból kalibrálnak. A specenként más képességlista a rotációs ticketekben jön (WA-006 és a spec-ticketek).
- Hol látszik:
  - a Harc oldalon a "Modell a kasztodhoz" szakasz címében, és első sorában ("A modell a(z) Combat spec szerint számol: a legtöbb pontod (21) a(z) Combat fában van, és megvan: …");
  - a spec táblájában a te sorodnál: "a modell e szerint számol";
  - a Felszerelés oldalon a modell megjegyzései közül az első sor: "Spec: …".
- Teszt (t_talents): mind a kilenc kasztnál két spec a valódi Forever fákból (20 pont soronként kitöltve):
  - a spec a kitöltött fa;
  - ugyanaz a karakter a másik spec talentjeivel más DPS-t kap, pl. Mage Fire 53,0 / Frost 59,9, Shaman Elemental 80,6 / Enhancement 92,8, Druid Balance 87,3 / Feral 67,9;
  - egyenlő pontszám, kézi választás, pont nélkül, a kliens fáiból.
