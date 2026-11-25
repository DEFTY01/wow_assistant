# Azeroth Chronicle – fiók-szintű fejlődési idővonal guild-versenyekkel

> Specifikáció és megvalósítási terv · v0.1 · 2026-11-25
> Kapcsolódó: [AZEROTH_MCP_SPEC.md](AZEROTH_MCP_SPEC.md) (a lokális MCP híd, amely az adatokat elemezhetővé teszi)

## 1. Cél

Wise Old Man (OSRS) és gw2efficiency mintájára egy olyan eszköz, ami:
1. **minden karaktered fejlődését idővonalon** mutatja (szint, XP, arany, profession skillek, questek, halálok);
2. **heti guild-versenyeket** rendez a játékon belül, szerver és felhő nélkül;
3. az adatokat a lokális **MCP hídon** keresztül az AI-nak is átadja: grafikonokhoz, előrejelzéshez és heti guild-krónikához.

A WoW-ban ma nincs ilyen. A Raider.IO és a Warcraft Logs a végjátékot méri, nem a fejlődési utat.

## 2. Komponensek

```
AzerothChronicle addon (játékon belül)
  ├─ snapshotok minden karakterről (fiók-szintű SavedVariables)
  ├─ heti alapvonal + heti nyereség (gains) karakterenként
  ├─ guild-szinkron: addon-üzenetek a GUILD csatornán (opt-in)
  └─ /azc panel: guild-ranglista + saját karakterek heti áttekintése
            │ SavedVariables (/reload, kilépés)
            ▼
Azeroth MCP híd (mcp/)
  ├─ ingest → snapshots, guild_standings táblák
  ├─ get_progress_timeline, compare_periods, get_guild_leaderboard
  └─ guild_chronicle prompt → heti krónika szövege (a felhasználó posztolja)
```

## 3. Az addon (`addon/AzerothChronicle`)

### 3.1 Szabályok
- Csak nem-harci API-t használ: szint, XP, pénz, skill line, quest-leadás, halál. A Secret Values ezeket nem érinti.
- Harc közben és instance-ban nem küld addon-üzenetet. Az új API ott tiltja; a hibakódot naplózza és később újrapróbál.
- **Kilépéskor nem készít snapshotot**, mert a WoW Forever kliens ilyenkor 0 aranyat és üres táskát jelez (lásd a `WowAssistant` addon megjegyzését).
- A megosztás **opt-in**: `/azc share on` nélkül semmit nem küld.

### 3.2 Adatmodell (`AzerothChronicleDB`, fiók-szintű)
```lua
AzerothChronicleDB = {
  version = 1,
  share = false,
  chars = {
    ["Defty-Graveshade"] = {
      class = "ROGUE", race = "Undead", faction = "Horde", guild = "Guild Name",
      counters = { xp = 123456, deaths = 3, quests = 41 },  -- követés kezdete óta, monoton
      snapshots = { { ts, level, xp, xpMax, money, cxp, deaths, quests, skills, zone }, ... }, -- max. 2000
      weeks = { [weekKey] = { base = <snapshot>, last = <snapshot> } },  -- max. 26 hét
    },
  },
  guild = {
    ["Guild Name"] = {
      [weekKey] = { ["Name-Realm"] = { ts, class, level, xp, money, levels, skills, quests, deaths }, ... },
    },
  },
}
```
- `cxp`: kumulált megszerzett XP (szintlépésen át is). Ebből a heti XP verseny szintfüggetlen.
- `skills`: a profession skill-rankek összege (Professions + Secondary Skills fejlécek alatt).
- `weekKey`: `floor((GetServerTime() - 6*86400 - 7*3600) / 604800)`, vagyis a hét szerda 07:00 UTC-kor kezdődik, az EU reset idején. A kezdőpont a konstanssal állítható.

### 3.3 Snapshot-időpontok
- `PLAYER_ENTERING_WORLD` után 5 s-mal;
- `PLAYER_LEVEL_UP`, `QUEST_TURNED_IN`, `PLAYER_DEAD` után;
- 10 percenként, ha nincs harc.

Ha az előző snapshot 60 s-nál frissebb, felülírja azt, így nem duzzad a lista.

### 3.4 Heti nyereség
- A hét első snapshotja a `base`, a legutóbbi a `last`.
- `gains = last − base`, mezőnként: `xp` (cxp alapján), `money`, `levels`, `skills`, `quests`, `deaths`.

### 3.5 Guild-protokoll
- Prefix: `AZCHR` (`C_ChatInfo.RegisterAddonMessagePrefix`).
- **Állapot üzenet** (≤ 255 bájt): `S1;<weekKey>;<class>;<level>;<xp>;<money>;<levels>;<skills>;<quests>;<deaths>`
- **Kérés**: `R1;<weekKey>`. A fogadó 2–10 s véletlen késleltetés után válaszol a saját állapotával, legfeljebb percenként egyszer.
- Küldés: belépés után 20 s-mal, 10 percenként, és ha a felhasználó megnyitja a panelt (kérés). Csak ha `share = true`, van guild, nincs harc és nincs instance.
- A beérkező üzenet küldőjét az esemény `sender` paramétere adja (`Name-Realm`). A saját adatot is beírja a táblába.
- Bizalom: az adat saját bevallás. A panel ezt jelzi; az ellenőrzés (Blizzard API) a későbbi MCP mérföldkő része.

### 3.6 Versenyek és pontozás
| Kategória | Érték | Megjegyzés |
|---|---|---|
| XP | heti `xp` | szintfüggetlen, mert a kumulált XP-ből számolódik |
| Szintek | heti `levels` | |
| Arany | heti `money` (nettó) | negatív is lehet |
| Profession | heti `skills` | skill-upok száma |
| Questek | heti `quests` | |
| Túlélő | `deaths == 0` és `xp > 0` | rangsor XP szerint, de csak a halál nélküliek |

A panelen fejlécgombokkal lehet kategóriát váltani. A sorokban: helyezés, név (osztályszínnel), szint, érték, utolsó frissítés ideje.

### 3.7 Parancsok
- `/azc`: panel
- `/azc share on|off`: megosztás
- `/azc sync`: kérés a guildnek
- `/azc week`: a saját karakterek heti összesítése a chatbe

## 4. MCP oldal (`mcp/`)
- **Ingest:** `AzerothChronicleDB.chars[*].snapshots` → `snapshots` tábla; `guild[*][week][*]` → `guild_standings` tábla.
- **Eszközök:**
  - `get_progress_timeline`: metrika, időszak és napi/heti bontás, egy karakterre vagy az egész fiókra;
  - `compare_periods`;
  - `get_week_summary`: a fiók összes karakterének heti nyeresége;
  - `get_guild_leaderboard`: egy hét és egy kategória rangsora;
  - `list_guild_weeks`.
- **Prompt:** `guild_chronicle(week?)`. Az LLM narratív heti krónikát ír magyarul. Posztolni a felhasználó posztolja; az eszköz nem küld semmit.

## 5. Megvalósítási terv

| Lépés | Tartalom | Kész, ha |
|---|---|---|
| C1 | Addon: snapshotok, számlálók, heti alapvonal, `/azc week` | `/reload` után a SavedVariables-ben megjelennek a snapshotok |
| C2 | Addon: guild-protokoll, opt-in, throttling, instance- és harcvédelem | két guild-tag látja egymás heti adatát |
| C3 | Addon: ranglista panel kategóriákkal | a panel rendezett listát mutat |
| C4 | MCP: ingest + timeline és leaderboard eszközök | Claude-ból lekérdezhető a heti rangsor |
| C5 | MCP: `guild_chronicle` prompt | értelmes, magyar krónika készül |
| később | Blizzard API ellenőrzés („verified”), szezonok (havi), Discord-szöveg export | |

## 6. Ismert korlátok
- A heti adat csak azokról a karakterekről van, akikkel a héten beléptél.
- A guild-adat csak akkor frissül, ha a másik fél is online van és megosztást kapcsolt be. A legutóbbi ismert állapot megmarad.
- Trial fiókról nem lehet addon-üzenetet küldeni.
