# Azeroth MCP híd – technikai specifikáció

> **Kinek szól:** egy AI fejlesztő ügynöknek (pl. Claude Code), amely ebből a dokumentumból önállóan megépíti a rendszert ebben a repóban (`wow-assitant`).
> **Nyelv:** a dokumentáció magyar; a kód, az azonosítók, a commit üzenetek és a kódkommentek angolul készüljenek (a repó meglévő stílusát követve).
> **Verzió:** 0.2 · 2026-11-25

---

## 0. Utasítások az implementáló ügynöknek

1. Olvasd végig az egész dokumentumot, és nézd át a 3.2-ben felsorolt meglévő fájlokat, mielőtt kódot írsz.
2. A mérföldköveket (12. fejezet) **sorrendben** valósítsd meg. Minden mérföldkő végén fussanak le a hozzá tartozó elfogadási tesztek, és `npm run typecheck` legyen hibamentes.
3. **Újrahasznosíts, ne duplikálj.** A repóban már van SavedVariables parser, combat log parser, addon és Blizzard API kliens. Ezeket közös modulként használd, és ha módosítani kell őket, a Cloudflare Worker és a feltöltő továbbra is működjön.
4. A **„VERIFY”** jelölésű pontok nem ellenőrzött feltételezések: legyenek konfigurálhatók, és írd le a `docs/DECISIONS.md` fájlba, ha élesben eltérést tapasztalsz.
5. A **„MUST NOT”** pontok (2. fejezet) megsértése fiók-tiltást kockáztat. Ezek nem alku tárgyai.
6. Ha egy döntés nincs leírva, válaszd a legegyszerűbb, lokálisan futó, külső szolgáltatást nem igénylő megoldást, és rögzítsd a `docs/DECISIONS.md` fájlban.

---

## 1. Cél és áttekintés

Az **Azeroth MCP** egy teljesen **lokálisan** futó [Model Context Protocol](https://modelcontextprotocol.io) szerver, amely a felhasználó WoW adatait (SavedVariables, combat log, opcionálisan a Blizzard API) **strukturált, lekérdezhető eszközökként** teszi elérhetővé bármely MCP-kompatibilis AI kliens számára (Claude Desktop, Claude Code, saját vagy Ollama-alapú ügynökök).

**Miért lokális:** a meglévő web app Cloudflare Workers + D1 alapú. Nagy mennyiségű log és idősor tárolása ott drága. Az MCP híd ugyanazt az adatot a felhasználó gépén, egy SQLite fájlban tartja, havidíj nélkül. A felhőbe továbbra is csak az kerül, amit a meglévő feltöltő eddig is küldött.

Ez egy **platform**: a későbbi funkciók (lokális coach, Addon Doctor, fiók-idővonal guild-versenyekkel, guild-krónika) mind erre épülnek.

```
┌──────────────── WoW Forever kliens (_forever_) ────────────────┐
│  WowAssistant addon (meglévő, bővítve) ─▶ WTF\...\SavedVariables\WowAssistant.lua
│  SessionBar addon (meglévő)            ─▶ ...\SavedVariables\SessionBar.lua
│  Játék kliens                          ─▶ Logs\WoWCombatLog-*.txt
│  AzerothMCP_Data addon  ◀── generált Data.lua (a következő /reload-kor betölt)
└─────────────────────────────────────────────────────────────────┘
          │ fájlok (csak olvasás, egy kivétellel)
          ▼
┌──────────── mcp/ (Node.js + TypeScript, lokális) ──────────────┐
│  Watcher → Ingest (scripts/lua-table.mjs, combat log parser)    │
│          → lokális SQLite (a meglévő migrations/ + MCP-táblák)  │
│  MCP server (stdio; opcionálisan HTTP csak 127.0.0.1-en)        │
│  Write-back: kizárólag AzerothMCP_Data\Data.lua                 │
└─────────────────────────────────────────────────────────────────┘
          │ MCP
          ▼
   Claude Desktop / Claude Code / lokális LLM ügynök
```

---

## 2. Kötelező szabályok (Blizzard ToS és biztonság)

### MUST NOT
- **Nincs** memóriaolvasás, DLL-injektálás, folyamat-hozzáférés a `Wow.exe`-hez.
- **Nincs** billentyű- vagy egérinput-szimuláció, makró-küldés, ablakfókusz-manipuláció.
- **Nincs** valós idejű, harc közbeni visszacsatolás a játékba (élő overlay a combat logból). A combat logot **csak utólag**, lezárt harcokra dolgozzuk fel. A Blizzard 2023-ban kifejezetten a log-alapú élő raid-overlayek ellen lépett fel.
- **Nincs** képernyő-OCR vagy pixel-olvasás.
- Az MCP szerver a WoW mappában **semmilyen** fájlt nem ír, kivéve: `Interface\AddOns\AzerothMCP_Data\Data.lua`.
- A SavedVariables fájlokat **nem módosítja**: a kliens kilépéskor úgyis felülírná őket, és sérülhetnek.
- Nincs telemetria, nincs felhő-feltöltés az MCP részéről. Hálózati forgalom csak: a) opcionális Blizzard API, b) opcionális LLM API, ha a felhasználó azt konfigurálja.

### MUST
- Minden fájlútvonal egy konfigurált **allowlistben** legyen (WoW flavor mappa + az MCP adatkönyvtár). Path traversal ellen normalizált, `path.resolve()`-olt útvonalakat ellenőrizz.
- A SavedVariables fájlokat **adatként** parse-old (a meglévő `parseSavedVariables`), soha ne futtasd őket Lua interpreterben.
- A titkok (`BLIZZARD_CLIENT_ID`, `BLIZZARD_CLIENT_SECRET`) csak env-ben vagy a nem commitolt `.uploader.env` / `.mcp.env` fájlban legyenek; soha ne kerüljenek logba vagy MCP válaszba.

---

## 3. Célkörnyezet és meglévő kód

### 3.1 Környezet

| Tétel | Érték |
|---|---|
| OS | Windows 11 (elsődleges); a kód legyen platformfüggetlen (`node:path`) |
| WoW kliens | **WoW Forever**: `_forever_`, termékkód `wowf`, kliens **1.60.1**, interface **16001**. A modern addon API-t használja a harci korlátozásokkal (Secret Values) |
| WoW flavor mappa a fejlesztői gépen | `F:/World of Warcraft/_forever_` (a meglévő `WOW_DIR` változó) |
| Futtatókörnyezet | Node.js ≥ 22 (a gépen 22.23 van), ESM (`"type": "module"`) |
| Nyelv | TypeScript (a repó `tsconfig.json`-ját követve), a meglévő `.mjs` szkriptek importálhatók |
| MCP SDK | hivatalos `@modelcontextprotocol/sdk` (`McpServer`, `StdioServerTransport`), sémák `zod`-dal |
| Adatbázis | lokális SQLite: `node:sqlite` (`DatabaseSync`), ha stabilan működik; különben `better-sqlite3`. Rögzítsd a döntést a `DECISIONS.md`-ben |
| Fájlfigyelés | `node:fs` `watch`/`watchFile` (a feltöltő mintájára) vagy `chokidar` |
| Tesztelés | `node:test` + `tsx`, vagy `vitest`; fixture fájlokkal |

### 3.2 Meglévő elemek, amelyekre építeni kell

| Fájl | Mit ad | Hogyan használd |
|---|---|---|
| `scripts/lua-table.mjs` → `parseSavedVariables(src)` | SavedVariables parser | Közvetlenül importáld. Ha hiányzik belőle valami (pl. `[[long string]]`, hex szám), bővítsd, a meglévő viselkedés megtartásával |
| `scripts/combat-log.mjs` → `parseCombatLog(text, character, opts)` | Harcok összegzése egy karakterre, COMBAT_LOG_VERSION 22 advanced mezőkkel | Megmarad a web appnak. Az MCP-nek **általánosabb, streamelő** parser kell (4.3); a mezőtérképet és a `splitCsv` logikát vedd át innen, közös modulba kiemelve. A `parseCombatLog` önálló forrása szándékos (a böngészőnek is kiszolgálják), ezt ne törd el |
| `scripts/uploader.mjs` | `.uploader.env` betöltés, `WOW_DIR`, addon-telepítés, log-felfedezés (`Logs/WoWCombatLog*.txt`) | Az env-betöltést és az útvonal-felfedezést emeld ki közös modulba (`scripts/lib/env.mjs`), és a feltöltő és az MCP is ezt használja |
| `addon/WowAssistant/` | Addon `WowAssistantDB` SavedVariables-szel (gold, táskák, bank, skillek, spellek, trainer; `chars[name]`, `logCombat`) | **Ezt bővítsd** snapshotokkal (5.1). Ne hozz létre külön Collector addont |
| `addon/SessionBar/` | Session idő/XP/arany sáv, `SessionBarCharDB.history` | Az ingest beolvassa (5.3) |
| `src/blizzard.ts` | Blizzard API kliens (Workers környezethez) | Az OAuth és namespace logikát vedd át egy Node-os kliensbe (`mcp/src/bnet.ts`); a Workers-specifikus részeket ne importáld |
| `migrations/*.sql` | D1 (SQLite) séma | A lokális DB **ugyanezeket** a migrációkat futtatja le először, majd az MCP saját migrációit (`mcp/migrations/`). Így a web app és a lokális DB sémája összhangban marad |

---

## 4. Adatforrások

### 4.1 Mappaszerkezet (WoW Forever)

```
<WOW_DIR>\                                   # pl. F:\World of Warcraft\_forever_
  Interface\AddOns\<AddonName>\...
  WTF\Account\<ACCOUNT>\SavedVariables\<Addon>.lua                    # fiók-szintű
  WTF\Account\<ACCOUNT>\<Realm>\<Character>\SavedVariables\<Addon>.lua # karakter-szintű
  Logs\WoWCombatLog*.txt
```

- A fiókok az `<ACCOUNT>` mappák, a karakterek a `<Realm>\<Character>` mappák listázásával fedezhetők fel.
- A SavedVariables fájlokat a kliens **csak `/reload`-kor vagy kilépéskor** írja ki. Az adat ezért „session végi”, nem élő.
- A `WowAssistant.lua` fiók-szintű (`## SavedVariables`), és karakterenként a `WowAssistantDB.chars[name]` alatt tárol. A `SessionBar` karakter-szintű (`SessionBarCharDB`) és fiók-szintű (`SessionBarDB`) fájlt is használ.

### 4.2 SavedVariables
- A `parseSavedVariables` felső szintű értékadásokat ad vissza (`{ WowAssistantDB: {...}, ... }`).
- Hibatűrés: parse-hiba esetén (a kliens éppen írja a fájlt) 3 s múlva próbáld újra, legfeljebb háromszor.
- Teljesítmény-cél: 50 MB-os fájl < 10 s alatt. Ha a meglévő parser ezt nem bírja, optimalizáld (és tesztekkel bizonyítsd, hogy a kimenet nem változott).

### 4.3 Combat log
- Formátum: időbélyeg + **két szóköz** + CSV-szerű mezők. Első sor: `COMBAT_LOG_VERSION,22,ADVANCED_LOG_ENABLED,1,...` (a meglévő parser alapján a WoW Forever így ír). Ismeretlen verziónál figyelmeztess, és csak az alap-prefixet (első 9 mező) dolgozd fel.
- A naplózást a játékos az addonnal kapcsolja be (`/wa log`, a meglévő `logCombat`).
- **Streamelő, inkrementális feldolgozás:** `fs.createReadStream` + `readline`, fájlonként tárolt bájt-offsettel (`ingest_state` tábla). Csak lezárt (`\n`-re végződő) sorokat dolgozz fel.
- **Szegmentálás:**
  - `ENCOUNTER_START`/`ENCOUNTER_END` → boss pull;
  - `CHALLENGE_MODE_START`/`_END` → kulcs, ha létezik ezen a kliensen (VERIFY);
  - minden más harc „open-world/trash” szegmens, amit a meglévő parser `FIGHT_GAP` logikája (8 s inaktivitás) zár le, a `NOT_COMBAT` listával együtt.
- **Aggregálás** szegmensenként és egységenként: kiosztott és kapott sebzés, gyógyítás, halálok (`UNIT_DIED` + az utolsó 10 kapott esemény mint „death recap”), megszakítások (`SPELL_INTERRUPT`), dispelek, cast-számok.
- A nyers eseményeket **nem** tároljuk: csak aggregátumok és halál-recapok kerülnek SQLite-ba, fájl + bájt-tartomány hivatkozással a nyers sorokra.
- Csak **lezárt** szegmensek kerülnek feldolgozásra (2. fejezet).

### 4.4 Blizzard API (opcionális, M5)
- OAuth client credentials (`https://oauth.battle.net/token`), régió EU. A namespace-t a meglévő `src/blizzard.ts` szerint állítsd be, és tedd konfigurálhatóvá.
- Gyorsítótár SQLite-ban (`bnet_cache`; TTL: static 30 nap, dynamic 1 óra). Rate limit: 100 kérés/s és 36 000/óra; 429-es válasznál exponenciális visszalépés.

---

## 5. Játékon belüli komponensek

### 5.1 Snapshotok

> **Döntés (D3, lásd [DECISIONS.md](DECISIONS.md)):** a snapshotokat nem a `WowAssistant`, hanem az új `AzerothChronicle` addon gyűjti ([CHRONICLE_SPEC.md](CHRONICLE_SPEC.md)). Az alábbi mezőlista ott valósul meg; a `WowAssistant` változatlan marad.

Új mező: `WowAssistantDB.chars[name].snapshots` (gyűrűs puffer, legfeljebb 2000 elem), és `.events` (legfeljebb 5000 elem).

Snapshot készül: `PLAYER_LOGIN` után 10 s-mal, `PLAYER_LEVEL_UP`-kor, `PLAYER_LOGOUT`-kor és óránként. Harc közben (`InCombatLockdown()`) nem készül snapshot, csak utána. **Minden API-t feature-detecttel hívj** (`if C_X and C_X.Fn then`).

| Mező | Forrás |
|---|---|
| `ts` | `time()` |
| `level`, `xp`, `xpMax`, `rested` | `UnitLevel`, `UnitXP`, `UnitXPMax`, `GetXPExhaustion` |
| `money` | `GetMoney` |
| `ilvl` | `GetAverageItemLevel` (ha létezik) |
| `played` | `RequestTimePlayed` → `TIME_PLAYED_MSG` (login után csak egyszer kérd) |
| `professions` | ha a meglévő addon már gyűjti a skilleket, azt használd; különben `GetProfessions`/`GetSkillLineInfo` |
| `reputations` | `C_Reputation` vagy `GetFactionInfo`, amelyik létezik |
| `achievementPoints` | `GetTotalAchievementPoints` (ha létezik) |
| `questsCompleted` | `C_QuestLog.GetAllCompletedQuestIDs` elemszáma (ha létezik) |
| `zone` | `GetRealZoneText` |

Események (`events`): `level_up`, `death` (`PLAYER_DEAD`), `zone`.

Emeld meg a `WowAssistantDB.version` értékét. A web app (`src/addon.ts`) az ismeretlen mezőket hagyja figyelmen kívül; ezt teszttel bizonyítsd. A feltöltő a snapshotokat **ne** küldje fel (méret miatt): szűrd ki a `post` előtt.

### 5.2 `AzerothMCP_Data` addon (generált, write-back csatorna)
- Helye: `addon/AzerothMCP_Data/` (`.toc` + üres `Data.lua`), és az `install` parancs ezt is bemásolja.
- A `Data.lua` kizárólag egyetlen, csak literálokat tartalmazó értékadás: `AzerothMCP_Inbox = { generated = <ts>, notes = {...}, goals = {...} }`. Kódot soha nem generálunk.
- A megjelenítést maga az `AzerothMCP_Data` addon végzi (`Display.lua`, statikus fájl): `/amcp` paranccsal nyíló panel. A `Data.lua` csak adat.
- Írás atomikusan: ideiglenes fájlba, majd `fs.renameSync`. Méretkorlát: 256 KB.
- **VERIFY:** a kliens `/reload`-kor újraolvassa-e egy már betöltött addon módosított fájlját. Új fájlt csak kliensindításkor fedez fel, ezért a `Data.lua` telepítéskor jöjjön létre.

### 5.3 `SessionBar`
- Az ingest a `SessionBarCharDB.current` és `.history` adatait a `sessions` táblába írja (kulcs: karakter + `start`).

---

## 6. Adatbázis

- Fájl: `<MCP_DATA_DIR>/azeroth.sqlite` (alapértelmezés: `%APPDATA%/azeroth-mcp/`), WAL mód.
- Migráció-sorrend: először a repó `migrations/*.sql` fájljai (a D1 sémával azonos táblák), majd az `mcp/migrations/*.sql`. A futtatott migrációk nevét egy `_migrations` tábla tárolja.
- Új táblák (`mcp/migrations/0001_mcp.sql`). Ha a meglévő sémában már van megfelelő tábla (pl. karakterek, harcok), **azt bővítsd vagy használd**, és ne duplikáld; ezt a döntést rögzítsd.

```sql
CREATE TABLE IF NOT EXISTS mcp_characters (
  id INTEGER PRIMARY KEY, account TEXT NOT NULL, realm TEXT NOT NULL, name TEXT NOT NULL,
  class TEXT, race TEXT, faction TEXT, UNIQUE(account, realm, name)
);
CREATE TABLE IF NOT EXISTS snapshots (
  id INTEGER PRIMARY KEY, character_id INTEGER NOT NULL, ts INTEGER NOT NULL,
  level INTEGER, xp INTEGER, xp_max INTEGER, money INTEGER, ilvl REAL, played_total INTEGER,
  achievement_points INTEGER, quests_completed INTEGER, data_json TEXT,
  UNIQUE(character_id, ts)
);
CREATE TABLE IF NOT EXISTS char_events (
  id INTEGER PRIMARY KEY, character_id INTEGER NOT NULL, ts INTEGER NOT NULL,
  kind TEXT NOT NULL, data_json TEXT, UNIQUE(character_id, ts, kind)
);
CREATE TABLE IF NOT EXISTS sessions (
  id INTEGER PRIMARY KEY, character_id INTEGER NOT NULL, start INTEGER NOT NULL,
  duration INTEGER, xp INTEGER, levels INTEGER, income_json TEXT, expense_json TEXT,
  UNIQUE(character_id, start)
);
CREATE TABLE IF NOT EXISTS combat_logs (
  id INTEGER PRIMARY KEY, path TEXT UNIQUE, log_version INTEGER, advanced INTEGER,
  build TEXT, first_ts INTEGER, last_ts INTEGER
);
CREATE TABLE IF NOT EXISTS segments (
  id INTEGER PRIMARY KEY, log_id INTEGER NOT NULL, kind TEXT NOT NULL,  -- encounter | challenge_mode | world
  name TEXT, encounter_id INTEGER, difficulty INTEGER, group_size INTEGER,
  start_ts REAL, end_ts REAL, success INTEGER, byte_start INTEGER, byte_end INTEGER
);
CREATE TABLE IF NOT EXISTS segment_units (
  segment_id INTEGER NOT NULL, guid TEXT NOT NULL, name TEXT, is_player INTEGER,
  damage_done INTEGER, healing_done INTEGER, damage_taken INTEGER,
  deaths INTEGER, interrupts INTEGER, dispels INTEGER, casts_json TEXT,
  PRIMARY KEY(segment_id, guid)
);
CREATE TABLE IF NOT EXISTS deaths (
  id INTEGER PRIMARY KEY, segment_id INTEGER NOT NULL, ts REAL, guid TEXT, name TEXT, recap_json TEXT
);
CREATE TABLE IF NOT EXISTS ingest_state (path TEXT PRIMARY KEY, mtime REAL, size INTEGER, offset INTEGER);
CREATE TABLE IF NOT EXISTS bnet_cache (key TEXT PRIMARY KEY, fetched INTEGER, ttl INTEGER, body TEXT);
```

---

## 7. MCP felület

Implementáció: `new McpServer({ name: "azeroth", version })`, `StdioServerTransport`.

Minden eszközre igaz:
- angol név, részletes leírás (az LLM ebből tanulja meg a használatot), `zod` bemeneti séma;
- JSON kimenet (`structuredContent` + rövid szöveges összefoglaló a `content`-ben);
- lapozás (`limit` ≤ 200, `cursor`). Ha a válasz túl nagy (~25 000 token felett), vágd le, és jelezd: `truncated: true`;
- csak olvas, kivéve a `write_ingame_inbox` eszközt (annotációk: `readOnlyHint` vagy `destructiveHint: false`, `idempotentHint: true`).

### 7.1 Eszközök (tools)

| Név | Bemenet | Kimenet / leírás |
|---|---|---|
| `list_characters` | – | karakterek az utolsó snapshot idejével és alapadatokkal |
| `get_character` | `character` | legutóbbi snapshot + a `WowAssistantDB.chars[name]` lényeges részei (gold, táskák, skillek) |
| `get_progress_timeline` | `character?` (üres = egész fiók), `metric` (`level`, `xp`, `money`, `ilvl`, `played`, `achievement_points`, `quests_completed`), `from`, `to`, `bucket` (`day`/`week`) | idősor + összesített „gains” |
| `compare_periods` | `metric`, `period_a`, `period_b`, `character?` | különbség és százalék |
| `list_sessions` | `character?`, `from?`, `to?`, `limit` | SessionBar sessionök: idő, XP/óra, arany/óra, kategóriák |
| `list_combat_segments` | `from?`, `to?`, `kind?`, `name_contains?`, `success?` | szegmensek |
| `get_segment_summary` | `segment_id` | egységenkénti aggregátumok, időtartam, kimenetel |
| `get_deaths` | `segment_id?` vagy `from`/`to`, `player?` | halálok + recap |
| `get_interrupts` | `segment_id` | ki, mit, mikor szakított meg |
| `query_sql` | `sql` (csak `SELECT`/`WITH`), `limit` | read-only kapcsolaton; tiltott: `INSERT/UPDATE/DELETE/ATTACH/PRAGMA/CREATE/DROP`; 5 s időkorlát |
| `read_saved_variables` | `addon`, `scope` (`account`/`character`), `character?`, `path?` (pl. `chars.Defty.gold`) | parse-olt részfa JSON-ként, méretkorláttal |
| `list_addons` | – | telepített addonok `.toc` metaadataival (Title, Version, Interface); jelzi, ha az Interface ≠ 16001 |
| `get_item` / `get_spell` | `id` | Blizzard Game Data (gyorsítótárból), ha engedélyezett |
| `write_ingame_inbox` | `notes[]`, `goals[]` | `AzerothMCP_Data/Data.lua` újragenerálása; a válasz emlékeztet: „/reload szükséges” |
| `ingest_now` | – | azonnali újraolvasás (egyébként a watcher automatikusan dolgozik) |

### 7.2 Erőforrások (resources)
- `wow://characters` – karakterlista
- `wow://character/{realm}/{name}` – legutóbbi snapshot
- `wow://segment/{id}` – szegmens-összefoglaló
- `wow://schema` – a teljes SQLite séma (hogy az LLM tudjon `query_sql`-t írni)

### 7.3 Promptok (prompts)
- `weekly_review(character?)` – heti áttekintés: fejlődés, sessionök, halálok, javaslatok.
- `wipe_analysis(segment_id)` – egy sikertelen pull vagy halál elemzése.
- `addon_health()` – elavult vagy hibás addonok.

---

## 8. Projektstruktúra (a repón belül)

```
wow-assitant/
  addon/
    WowAssistant/           # meglévő, bővítve (5.1)
    SessionBar/             # meglévő
    AzerothMCP_Data/        # új (5.2)
  scripts/
    lib/env.mjs             # új: kiemelt .env-betöltés és útvonal-felfedezés
    lua-table.mjs           # meglévő, közös
    combat-log.mjs          # meglévő (web app), változatlan API
    uploader.mjs            # meglévő; a lib/env.mjs-t használja, a snapshotokat nem tölti fel
  migrations/               # meglévő D1 migrációk (a lokális DB is lefuttatja)
  mcp/
    package.json            # vagy a gyökér package.json workspace-ként; döntsd el és rögzítsd
    tsconfig.json
    migrations/0001_mcp.sql
    src/
      config.ts             # .mcp.env / env, allowlist, MCP_DATA_DIR
      paths.ts              # fiók/realm/karakter felfedezés
      db.ts                 # SQLite kapcsolat, migráció-futtató, read-only kapcsolat
      ingest/
        savedVariables.ts   # WowAssistant + SessionBar → táblák
        combatLog.ts        # streamelő tokenizer, szegmentálás, aggregálás
        watcher.ts          # 2 s debounce
      bnet.ts               # opcionális
      writeback.ts          # Lua-literál serializáló + atomikus írás
      server.ts             # McpServer: tools, resources, prompts
      cli.ts                # `azeroth-mcp serve | ingest | doctor | install`
    test/
      fixtures/{savedvariables,combatlog,wow_root}/
      *.test.ts
  docs/
    AZEROTH_MCP_SPEC.md     # ez a dokumentum
    DECISIONS.md
```

### Konfiguráció (`.mcp.env`, nem commitolt; minta: `.mcp.env.example`)
```
WOW_DIR=F:/World of Warcraft/_forever_
MCP_DATA_DIR=%APPDATA%/azeroth-mcp
WOW_CHARACTER=Defty
BNET_ENABLED=0
BLIZZARD_CLIENT_ID=
BLIZZARD_CLIENT_SECRET=
MCP_TRANSPORT=stdio          # vagy http → csak 127.0.0.1
MCP_HTTP_PORT=8765
```
Ha a `.mcp.env` nem létezik, a `.uploader.env` értékeit is olvassa be (közös `WOW_DIR`, `WOW_CHARACTER`). A `.gitignore`-ba vedd fel a `.mcp.env`-et.

### npm scriptek (gyökér `package.json`)
- `mcp:serve`, `mcp:ingest`, `mcp:doctor`, `mcp:install`, `mcp:test`.

### CLI
- `doctor` – ellenőrzi az útvonalakat, a fiókokat és karaktereket, a combat log verzióját és a feature-detect eredményeket (ha az addon menti őket); ember által olvasható riportot ad.
- `install` – bemásolja a `WowAssistant`, `SessionBar` és `AzerothMCP_Data` addonokat. Felülírás előtt megkérdezi a felhasználót; a játék legyen bezárva.
- `ingest [--full]` – egyszeri beolvasás.
- `serve` – MCP szerver, háttérben a watcherrel.

### Kliens-beállítás (README-be)
- Claude Code: `claude mcp add azeroth -- npm --prefix K:/GITHUB/wow-assitant run -s mcp:serve`
- Claude Desktop: `claude_desktop_config.json` → `"mcpServers": { "azeroth": { "command": "node", "args": ["<repo>/mcp/dist/cli.js", "serve"] } }`
- **Fontos:** stdio módban semmi ne írjon a stdout-ra (csak MCP üzenetek). A naplózás stderr-re vagy fájlba menjen.

---

## 9. Ingest folyamat

1. Induláskor `paths.discover()` → fiókok és karakterek → `mcp_characters` upsert.
2. SavedVariables: ha a fájl `mtime` vagy mérete változott → parse → a `WowAssistantDB.chars[*].snapshots/events` és a `SessionBarCharDB` idempotens upsertje (`UNIQUE` kulcsok + `INSERT OR IGNORE`).
3. Combat logok: a legújabb fájl inkrementálisan, a régebbiek egyszer. Szegmens csak lezáráskor kerül be.
4. A watcher 2 s debounce-szal ugyanezt csinálja fájlváltozáskor.
5. Minden ingest egy tranzakció; hiba esetén rollback, és bejegyzés a `MCP_DATA_DIR/logs/ingest.log` fájlba.

---

## 10. Nem-funkcionális követelmények

- **Teljesítmény:** 1 GB-os combat log első beolvasása < 3 perc; inkrementális frissítés < 2 s.
- **Memória:** streamelés, < 500 MB RAM (a meglévő `parseCombatLog` az egész fájlt beolvassa; az MCP-ben ezt nem szabad).
- **Robusztusság:** az ismeretlen eseménytípusokat számláld és hagyd ki; a `doctor` listázza őket.
- **Adatvédelem:** `MASK_OTHER_PLAYERS=1` opció más játékosok nevének maszkolására az MCP válaszokban.
- **Kompatibilitás:** a Cloudflare Worker (`npm run typecheck`, `npm run dev`) és a feltöltő a változtatások után is működjön.

---

## 11. Tesztelés és elfogadás

- **Unit tesztek:**
  - SV parser: a meglévő funkciók és az új bővítések;
  - combat log tokenizer: idézőjelek, ismeretlen események, advanced blokk;
  - szegmentáló: boss pull, wipe, open-world harc, `NOT_COMBAT` események;
  - Lua-literál serializáló: oda-vissza alakítás a `parseSavedVariables`-szel.
- **Integrációs teszt:** fixture WoW-mappa (`mcp/test/fixtures/wow_root/`) teljes ingesttel; az MCP eszközöket az SDK in-memory kliensével hívd meg.
- **Biztonsági tesztek:**
  - a `query_sql` elutasítja a módosító utasításokat;
  - a path traversal (`..`) elutasítva;
  - a `write_ingame_inbox` nem tud a saját mappáján kívülre írni.
- **Regresszió:** `npm run typecheck` zöld, a `parseCombatLog` kimenete egy fixture logon változatlan.
- **Kézi teszt a felhasználóval:**
  1. Játék, `/wa log`, egy dungeon, majd `/reload`.
  2. `npm run mcp:ingest`.
  3. Claude-ban: „Mennyi XP-t szereztem ezen a héten, mennyit költöttem javításra, és hol haltam meg?”

---

## 12. Mérföldkövek

| # | Tartalom | Elfogadás |
|---|---|---|
| **M0** | `mcp/` váz, `scripts/lib/env.mjs` kiemelés, konfiguráció, `doctor`, útvonal-felfedezés | a `doctor` kilistázza a `_forever_` fiókokat és karaktereket; a feltöltő változatlanul működik |
| **M1** | SQLite + migrációk, SV ingest (WowAssistant, SessionBar), `list_characters`, `get_character`, `list_sessions`, `read_saved_variables`, `query_sql`, `wow://schema` | Claude Code-ból lekérdezhetők a SessionBar sessionök és a karakter goldja |
| **M2** | WowAssistant addon snapshotok, `get_progress_timeline`, `compare_periods` | idősor legalább két snapshotból; a web app nem törik el |
| **M3** | Streamelő combat log parser, szegmentálás, `list_combat_segments`, `get_segment_summary`, `get_deaths`, `get_interrupts` | egy valós log helyes szegmensei és halálai |
| **M4** | `AzerothMCP_Data`, `write_ingame_inbox`, `/amcp`, `install` | egy MCP-ből írt jegyzet `/reload` után látszik a játékban |
| **M5** | Blizzard Game Data, `list_addons`, promptok, README | a `weekly_review` prompt értelmes riportot ad |

Minden mérföldkő után: tesztek zöldek, `README.md` és `docs/DECISIONS.md` frissítve, külön commit.

---

## 13. Nyitott kérdések (VERIFY lista)

1. Írja-e a WoW Forever kliens az `ENCOUNTER_START`/`END`, illetve `CHALLENGE_MODE_*` eseményeket a logba (a 22-es verzió és az advanced logolás megerősített).
2. Mely snapshot-API-k léteznek a WoW Forever kliensen (`GetAverageItemLevel`, `C_Reputation`, `GetTotalAchievementPoints`, `C_QuestLog.GetAllCompletedQuestIDs`). Feature-detect, és az addon mentse el az eredményt, amit a `doctor` riportol.
3. A `/reload` újraolvassa-e egy már betöltött addon módosított fájlját (az `AzerothMCP_Data` csatornához).
4. A `node:sqlite` stabil-e Node 22.23-on a szükséges funkciókkal (WAL, read-only kapcsolat); ha nem, `better-sqlite3`.
5. A meglévő D1 migrációk lefutnak-e változtatás nélkül egy sima SQLite-on (D1-specifikus szintaxis esetén külön lokális migráció kell).
