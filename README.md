# WoW Assistant

Min-max segéd a WoW: Forever karakteredhez. A Blizzard API-ból, az aukciósház áraiból, egy saját
addonból és a játék harcnaplójából megmondja, mire költsd a goldod, mit craftolj, melyik
dungeonbe menj, és mit javíts a rotációdon.

## Ha meghívót kaptál

1. Nyisd meg a kapott linket, és írd be a karaktered teljes nevét (keresztnév és vezetéknév).
   Legalább 10-es szintű legyen, és egyszer jelentkezz ki vele, hogy a Blizzard API lássa.
2. Kapsz egy saját linket. **Ez a jelszavad**: aki ismeri, látja és módosíthatja az oldaladat.
3. A karakterlap és a mesterség-útvonal ennyivel már működik.

A vásárlási tervhez (gold, táskák, bank, trainer skillek) és a harcelemzéshez kell az addon és a
feltöltő is. Ehhez [Node.js](https://nodejs.org) 20 vagy újabb szükséges.

```bash
git clone https://github.com/DEFTY01/wow_assistant.git
cd wow_assistant
```

Hozz létre egy `.uploader.env` fájlt a mappában. A pontos tartalmát a saját oldalad Karakter
füle mutatja („Addon és feltöltő"):

```
APP_URL=https://...
UPLOAD_TOKEN=a_saját_kulcsod
WOW_CHARACTER=Keresztnév
WOW_DIR=C:/Program Files (x86)/World of Warcraft/_forever_
```

Telepítsd az addont (a játék legyen bezárva), aztán indítsd a feltöltőt:

```bash
node scripts/uploader.mjs --install
node scripts/uploader.mjs
```

A játékban:

- `/wa` – kiírja, mit lát az addon.
- `/wa log` – bekapcsolja a harcnaplót (utána minden belépéskor magától indul).
- `/wa save` – kiírja az adatokat lemezre (újratölti a felületet); a feltöltő ekkor küldi fel.
- A trainernél a Filter menüben pipálj be mindent, a bankot pedig nyisd meg egyszer.

### Korlátok

- A sebzésmodell és a vásárlási terv egyelőre csak **rogue** karakterre készült el.
- Az aukciós árak az EU Normal ruleset Horde aukciósházából származnak.
- A random utótagos tárgyak („of the Tiger") kimaradnak az aukciós ajánlásból.

## Csak a saját gépeden (Cloudflare nélkül)

Egy parancs elindítja az appot helyi adatbázissal, a feltöltőt és a 30 percenkénti
Blizzard-szinkront. Csak a `127.0.0.1` címen figyel, a hálózatról nem érhető el. Kell hozzá
egy `.dev.vars` a Blizzard API kulcsokkal (minta: `.dev.vars.example`).

```bash
npm install
npm run db:migrate:local   # csak első alkalommal
npm run local              # aztán: http://127.0.0.1:8787
```

Az adatok a `.wrangler/state` mappában vannak; ezt érdemes időnként lementeni. Az online
adatbázis egy korábbi exportja a `backups/` mappában van (nincs a gitben).

## Saját példány üzemeltetése

Cloudflare Workers + D1. A titkok (`BLIZZARD_CLIENT_ID`, `BLIZZARD_CLIENT_SECRET`,
`UPLOAD_TOKEN`) `wrangler secret put` paranccsal állíthatók be; helyi futtatáshoz a
`.dev.vars.example` a minta.

```bash
npm install
npm run db:migrate:local
npm run dev
```

Az oldalt Cloudflare Access védi. A `/api/addon`, `/api/fights` és `/u` útvonalakhoz Bypass
szabály kell: az elsőket a feltöltő token, a megosztott oldalakat a linkben lévő kulcs védi.

## Lokális AI-híd (Azeroth MCP) és Chronicle

Teljesen a saját gépeden futó [MCP](https://modelcontextprotocol.io) szerver: a játék fájljaiból
(SavedVariables, harcnapló) helyi SQLite adatbázist épít, és ezt Claude (vagy más MCP-kliens)
eszközökként kérdezheti le. Felhő és havidíj nincs. Részletek: [docs/AZEROTH_MCP_SPEC.md](docs/AZEROTH_MCP_SPEC.md),
[docs/CHRONICLE_SPEC.md](docs/CHRONICLE_SPEC.md).

Node.js 22.18 vagy újabb kell (a TypeScriptet build nélkül futtatja).

```bash
npm run mcp:install-deps
npm run mcp:doctor
```

A `doctor` megmutatja, mit talál a `WOW_DIR` mappában (a `.uploader.env`-ből vagy egy `.mcp.env`
fájlból olvassa), és első alkalommal beolvas mindent. Claude Code a repó `.mcp.json` fájljából
magától felismeri az `azeroth` szervert (első indításkor jóvá kell hagyni).

Addonok a játékhoz (a játék legyen bezárva, mert új addont csak induláskor lát):

- **AzerothChronicle** – minden karaktered fejlődését menti, és heti guild-versenyt rendez.
  `/azc` panel, `/azc share on` megosztás a guilddel, `/azc week` heti összesítő.
- **AzerothMCP_Data** – ide írhat az AI jegyzeteket és célokat; `/reload` után `/amcp`.
- **SessionBar** – kompakt session-sáv (idő, XP, arany).

Az adatok csak `/reload` vagy kilépés után kerülnek lemezre, utána frissül az adatbázis.
Példa kérdések Claude-nak: „Mennyi XP-t szereztem ezen a héten az előzőhöz képest?",
„Miből haltam meg legtöbbször?", „Írj guild-krónikát a heti versenyről."
