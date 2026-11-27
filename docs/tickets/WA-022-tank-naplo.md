# WA-022 · Harcnapló: elszenvedett sebzés és védekezés

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 5. Tankolás | M | alacsony | adat | nyitott |

**Előfeltétel:** nincs  
**Erre épül:** [WA-023](WA-023-tank-keret.md)

## Cél

A feldolgozó rögzítse a téged ért sebzést és a kivédéseket (dodge, parry, block, miss), a halálokat.

## Miért

A tankmodellhez ez az adat kell. Ma a feldolgozó csak a saját (és a pet) sebzését olvassa.

## Teendők

- [ ] A rád irányuló `SWING_DAMAGE`, `SPELL_DAMAGE`, `*_MISSED` események: összeg, elnyelt és blokkolt rész, kivédés fajtája.
- [ ] Fenyegetés-becslés a saját sebzésből és a fenyegetést adó képességekből (a szorzók a WoWSims Forever motorból, ha ellenőrizhető; különben mért adatként, szorzó nélkül).
- [ ] Feltöltő és `Fights.lua`: új `taken` mező.

## Elfogadás

- Valódi naplóból a téged ért sebzés összege egyezik egy kézzel ellenőrzött mintával.
