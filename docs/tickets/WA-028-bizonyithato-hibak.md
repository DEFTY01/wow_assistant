# WA-028 · Új bizonyítható hibaszabályok

| Fázis | Méret | Prioritás | Típus | Állapot |
|---|---|---|---|---|
| 5. Referencia, szabályok, webapp | M | közepes | szabály | nyitott |

**Előfeltétel:** [WA-005](WA-005-aura-idovonal.md), [WA-006](WA-006-rotacio-keret.md)  
**Erre épül:** nincs

## Cél

Az aura-idővonalra és a rotációs számításokra építve új, bizonyítható hibaszabályok, kasztonként.

## Miért

Most három bizonyítható hiba van (kevés combo pontos Eviscerate, manaital teli manánál, rage-túlcsordulás Bloodrage/Charge után). Minden más megfigyelés, mert a döntés pillanatának állapota nem látszott.

## Teendők

- [ ] Jelöltek: Slice and Dice lejárt, miközben volt combo pont és energia; nem sebző seal fent a harc egészében; a DoT újrarakása, mielőtt lejárt volna (a felülírt tickek a naplóból).
- [ ] Minden szabályhoz: Forever-forrás (Wowhead vagy a motor kódja), a pontos feltételek, és az esetek listája időponttal, mint az Eviscerate-nél.
- [ ] Ahol egy feltétel nem látszik, az megfigyelés marad, és ezt a tanács megírja.

## Elfogadás

- Minden új hibaszabály valódi naplón ellenőrizve, hamis pozitív nélkül.
