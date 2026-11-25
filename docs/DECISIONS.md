# Döntések (Azeroth MCP és Chronicle)

| # | Döntés | Indok |
|---|---|---|
| D1 | Az MCP híd külön csomag a `mcp/` mappában, saját `package.json`-nal | A Cloudflare Worker függőségei és a `tsconfig` érintetlenek maradnak |
| D2 | A TypeScript-et a Node 22 beépített type stripping funkciója futtatja, build lépés nincs | Egyszerűbb indítás (`node mcp/src/cli.ts`); csak törölhető típusszintaxis használható (nincs `enum` és `namespace`) |
| D3 | A snapshotokat az új `AzerothChronicle` addon gyűjti, nem a `WowAssistant` | A guild-verseny ugyanazokra az adatokra épül; a feltöltő és a web app így érintetlen |
| D4 | Az adatbázis a beépített `node:sqlite` (`DatabaseSync`), saját sémával. A D1 migrációkat nem futtatjuk | A lokális híd nem használja a web app tábláit, ezért nem kell külső natív modul |
| D5 | A WoW Forever karaktermappák formája `WTF/Account/<fiók>/<régiószám>/<Név-Realm>/SavedVariables`; a felfedezés a Retail-féle `<Realm>/<Név>` formát is kezeli | A fejlesztői gépen talált szerkezet |
| D6 | A combat log formátuma: `COMBAT_LOG_VERSION 22`, advanced logolás, `PROJECT_ID 18`. Az összeg mezői: swing esetén f[28], spell esetén f[31] (a `scripts/combat-log.mjs` alapján) | Valós logból ellenőrizve |
| D7 | Open-world harcban nincs `ENCOUNTER_START`; a szegmentálás 8 s szünet alapján történik, ahogy a meglévő parserben | Valós logból ellenőrizve |
