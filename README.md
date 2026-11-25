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

- `/wa` – megnyitja a főablakot: a webapp oldalai a játékban (lásd lent).
- `/wa status` – kiírja, mit lát az addon.
- `/wa log` – bekapcsolja a harcnaplót (utána minden belépéskor magától indul).
- `/wa save` – kiírja az adatokat lemezre (újratölti a felületet); a feltöltő ekkor küldi fel.
- `/wa help` – az összes parancs.
- A trainernél a Filter menüben pipálj be mindent, a bankot pedig nyisd meg egyszer.

### A webapp a játékban (`/wa`)

A 2.0-s addon egyetlen mappa (`WowAssistant`), benne a korábbi SessionBar és AzerothChronicle is.
A főablak fülei ugyanazt számolják, mint a webapp, ugyanazzal a kóddal Lua-ra átírva:

- **Haditerv** – mit vegyél, tanulj, gyárts és hol farmolj a meglévő aranyadból (`/wa plan`).
- **Harc** – statisztika és tanácsok a rögzített harcokból (`/wa combat`).
- **Felszerelés** – dungeon-fejlesztések helyenként, buffok és fogyóeszközök ki-be kapcsolva (`/wa gear`).
- **Mesterségek** – a legolcsóbb út 225-ig vagy 300-ig, bevásárlólistával (`/wa prof`).
- Gombok a vendorra gyártás ablakához, a session-sávhoz és a Chronicle panelhez.

A táblák a fejlécükre kattintva rendezhetők, a keresőmező minden tábla sorait szűri. A karakter
adatait (statok, felszerelés, táska, szakmák, pénz) élőben olvassa; az árakat a `/wa ah` szkenből.

**Harc:** az addon minden harcot magától rögzít, ahogy a Details: mikor mit használtál (idő,
energia, combo pont), képességenként a találatokat (hit, crit, glancing, miss, dodge, parry – ezeket
a célpont ütéseiből, csak egyedül játszva), az energiaplafont és a buffokat. Harc után a kliens damage
meteréből jön a pontos sebzés képességenként, és a harc pontszámot kap (0–100, S–D): DPS a
felszerelésedtől várthoz képest, kárba ment energia, Eviscerate combo pontjai, Slice and Dice
uptime, képességek percenként. A Harc fülön bármelyik harcra rákattintva látod a részleteit.
A feltöltő a harcnaplóból feldolgozott harcokat is beleírja a játék addon-mappájába
(`WowAssistant/Fights.lua`; belépéskor vagy `/reload` után látszik). `/wa meter` mutatja, mit ad a kliens.

**Kinézet:** alapból játékbeli ablakok (kő háttér, díszes keret, fülek alul); `/wa style flat` a
letisztult, Daylight UI-szerű változat, `/wa style wow` vissza (utána `/reload`). A játék betűi
között nincs ő és ű, ezért az addon saját betűkészlettel jön (Fira Sans, Cinzel – `Fonts/`, SIL OFL).

A recept-, loot- és buffadat generált fájlokból jön, amelyek nincsenek a gitben:
`npm run addon:recipes` készíti el és telepíti őket (`Recipes.lua`, `GameData.lua`).

**Átköltözés 2.0-ra:** a telepítés a régi `SessionBar` és `AzerothChronicle` mappába egy üres
átköltöztető addont tesz, amely csak a régi mentéseket tölti be. Minden karakter első belépésekor a
WowAssistant átmásolja őket (a régi parancsok, `/sbar` és `/azc`, továbbra is működnek). Ha már
minden karaktereddel beléptél egyszer, a két régi mappa törölhető.

### Korlátok

- A sebzésmodell és a vásárlási terv egyelőre csak **rogue** karakterre készült el.
- Az aukciós árak az EU Normal ruleset Horde aukciósházából származnak.
- A random utótagos tárgyak („of the Tiger") kimaradnak az aukciós ajánlásból.

## Vendorra gyártás

A **Vendorra gyártás** fül azokat a recepteket mutatja, amelyeknél a vendor többet fizet a kész
tárgyért, mint amennyibe az alapanyag kerül. Az alapanyagot az aukciósházból veszi (vagy
kereskedőtől, ha ott olcsóbb). Minden szakma minden receptjét végignézi 300-as skillig, és szűrni
lehet a saját szakmáidra, a jelenlegi skilledre, illetve csak a már ismert receptekre.

- **Pontos költség:** az óránkénti árletöltés minden hirdetést megőriz. A számítás a legolcsóbbtól
  felfelé veszi meg az alapanyagot, és ott áll meg, ahol a következő gyártás már veszteséges. A nem
  osztható köteget egészben számolja.
- **Átlagár is:** mellette látod, mennyit hoz egy gyártás a piaci átlagárral.
- **Vendorár ellenőrzése:** a Blizzard tárgyadatbázisát összeveti a Wowhead Forever adatával, és
  jelzi, ha eltérnek.
- **Cooldown:** a cooldownos recepteknél (transmute, Mooncloth) az adag egyetlen gyártás.

**Játékon belül is:** az aukciósháznál a „Vendorra gyártás” gomb (vagy `/wa vendor`) ugyanezt
számolja, a játék saját adataival:
- a vendorárat a kliens adja meg, így az pontos;
- az alapanyagok árai a webapp óránkénti AH-adatából jönnek: a feltöltő beírja őket az addon
  mappájába (`Market.lua`, a játék belépéskor vagy `/reload` után látja); ha frissebb, a játékbeli
  teljes AH-szken (`/wa ah`) számít;
- élőben frissülnek, amikor egy alapanyagra rákeresel az AH-ban, megnyomod az „Árak frissítése”
  gombot, vagy megnyitod az ablakot az aukciósháznál: ilyenkor a legjobb 10 gyártás alapanyagait
  magától lekérdezi („Legjobb 10 élő ára” gomb);
- az ismert recepteket a szakmaablakból olvassa ki: szakmánként egyszer nyisd meg.

A receptadatot az addon egy generált fájlból kapja, amely nincs a gitben. Az elkészítése és
telepítése: `npm run addon:recipes`.

A receptlisták a Wowhead Forever szakmaoldalairól származnak. Ezeket a `data/wowhead/<szakma
azonosító>.json` fájlokba kell lementeni (nincsenek a gitben), és a futó appba ezzel tölthetők be:
`npm run import:recipes`.

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

- **WowAssistant** – a 2.0 óta ebben van a két alábbi modul is (régen külön addonok voltak):
- *Azeroth Chronicle* – minden karaktered fejlődését menti, és heti guild-versenyt rendez.
  `/azc` (vagy `/wa azc`) panel, `/azc share on` megosztás a guilddel, `/azc week` heti összesítő.
- **AzerothMCP_Data** – ide írhat az AI jegyzeteket és célokat; `/reload` után `/amcp`.
- *SessionBar* – kompakt session-sáv (idő, XP, arany; `/sbar` vagy `/wa sbar`); egérrel tooltip, a nyíllal részletes panel.
  - XP-források (mobölés / küldetés / felfedezés), zónánkénti XP/óra és arany/óra.
  - AFK-szűrés: AFK vagy 5 perc tétlenség nem rontja az óránkénti értékeket.
  - Célok vékony csíkkal a sáv alján: `/sbar goal gold 100 [22:00]`, `/sbar goal gold +50`,
    `/sbar goal level 40 [22:00]`, `/sbar goal clear`; lassú tempónál figyelmeztet.
  - Arany-tanács (`/sbar advice`): legjobb zóna, fő bevételi forrás, szürke tárgyak, becsült idő a célig.
  - Pihent XP tervező, táska szabad hely + szürke tárgyak vendor-értéke, nyíl a korábbi sessionök
    átlagához képest, mini grafikon, összefoglaló kilépéskor és belépéskor (`/sbar summary`, `/sbar zones`).

Az adatok csak `/reload` vagy kilépés után kerülnek lemezre, utána frissül az adatbázis.
Példa kérdések Claude-nak: „Mennyi XP-t szereztem ezen a héten az előzőhöz képest?",
„Miből haltam meg legtöbbször?", „Írj guild-krónikát a heti versenyről."
