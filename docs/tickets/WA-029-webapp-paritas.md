# WA-029 · Webapp: a kasztmodellek és a játék közötti különbség

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 6. Referencia, szabályok, webapp | M | alacsony | döntés | nyitott |

**Előfeltétel:** nincs  
**Erre épül:** nincs

## Cél

Eldönteni, hogy a webapp harcoldala és coachja kövesse-e a játékbeli kasztmodelleket.

## Miért

A D10 szerint a játék és a webapp ugyanazt mutatta. Azóta a druid, warlock, mage, warrior, priest és paladin modellje csak Lua-ban létezik; a `src/` nem ismeri őket.

## Teendők

- [ ] Felmérni, mi tér el (`src/combat.ts`, `src/coach.ts`, `src/gear.ts` a Lua-modellekhez képest).
- [ ] Döntés: átírjuk TypeScriptre, a webapp csak a játék eredményét mutatja, vagy a webapp harcoldala megszűnik.
- [ ] A döntés a `DECISIONS.md`-be.

## Elfogadás

- Írásos döntés, és ha átírás, akkor külön ticketek kasztonként.

## Megjegyzés

A web-app-convert-wowhead munkamenet a webappon dolgozik; egyeztetni kell vele.
