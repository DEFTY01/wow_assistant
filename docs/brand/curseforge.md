# Waystone: adventurer's companion

Name and CurseForge texts of the addon (WoW Assistant until 2.3.1). "WoW" in an addon name uses
Blizzard's trademark; CurseForge asks authors not to, so the public name drops it. The folder, the
saved variables and the Lua globals keep the WowAssistant name, so saved data, the uploader and the
MCP need no change.

- **Name:** Waystone
- **Full title:** Waystone: Adventurer's Companion
- **Slash commands:** `/wa`, `/waystone` (and the old `/wowassistant`).
- **Logo:** `waystone-logo.svg` (source), `waystone-logo.png` (512×512, for CurseForge);
  in game `addon/WowAssistant/Media/Waystone.tga` (128×128): addon list icon and minimap button.

## Summary (CurseForge's one-line field)

Plan your leveling, read your fights, sort your gear and turn crafts into gold, all in one window.

## Description

Paste this into the project's description (CurseForge accepts Markdown).

```markdown
# Waystone: Adventurer's Companion

**Plan your leveling, read your fights, sort your gear and turn crafts into gold, all in one window.**

Waystone is a companion for the long road to max level. Type `/wa` and one window brings together
what you would otherwise piece together from spreadsheets, websites and a handful of other addons.
Everything is worked out inside the game, from your character's stats, gear, talents and spec, your
recorded fights, and what the auction house shows right now. Every number says where it comes from.

## Features

### A damage model for every class
- All nine classes have their own damage model, built from your current stats, gear, **talents** and
  **spec**. It tells you which spec you are in and how it knows.
- Your recorded fights **calibrate** the model: fights close to your current level count the most.
- Every number names its source (Wowhead Forever, WoWSims Forever, your combat log or the game itself).

### Combat page
- Every fight is recorded: damage, DPS, the abilities you used and a **combat score** (S to D).
- A raid-log style damage breakdown for your class, casts per minute, buff and DoT uptimes, and
  cooldown usage.
- The **aura timeline** remembers when your buffs and your debuffs on the target went up and down.
- **Suggested rotation**: the order to use your abilities in and the DPS the model expects from it.
  Combat rogue first; the other specs follow.
- Advice only calls something a mistake when your fight data and a rule checked for Forever prove it.
- Hunters: your pet's damage counts as yours.

### Talents
- An **in-game talent calculator** (`/wa talents`): your trees, a plan, and what every talent is
  worth in DPS with your current gear.
- The most valuable next point, and how your plan compares with your current talents.
- Checks that the talent data matches the game (`/wa talent`).

### Plan and gear
- **Plan**: what to buy and what to do next, from your level, gold, skills and class.
- **Gear**: what is worth replacing and which dungeon or quest drops the upgrade, scored with your
  class's damage model.
- **Enchants** that suit your role, for every class.

### Vendor crafting: gold from a single sale
Which craft brings the most gold when you sell it to a vendor?
- Set how many times you craft (1, 5, 20 or **Best batch**). The costs, the vendor income and the net
  profit follow the number, because buying more reagents pulls in dearer listings.
- Prices come from **live auction house listings**: open the window at the auction house and it checks
  the reagents of the 10 best crafts of **every profession**.
- Vendor sell prices come straight from the game client, so they are always exact.

### Professions
- The cheapest route to the next skill cap, with a shopping list.
- Reads the recipes you know from the profession window.

### Hunter pets
- **Your pet**: family, level, training points, happiness and the ranks it knows.
- **What to teach next**, and which beast to tame to learn it (where and at what level).
- **Best pet for your level** and a searchable **bestiary** of every tameable beast.

### Session bar
A compact bar with this session's playtime, XP and gold per hour, goals, the best farm zones and
your history.

### Chronicle
A journal of your character's milestones week by week, with an optional weekly guild list.

### Also
- **English or Hungarian**: click the EN/HU button next to the window's close button, or type
  `/wa lang en` or `/wa lang hu`.
- Minimap button (left click: main window, right click: vendor crafting, Shift-click: session bar).
  It is listed in the addon compartment too.
- Search box on every page.
- Two window styles: game-style frames or a clean flat look (`/wa style wow | flat`).

## Commands

| Command | What it does |
|---|---|
| `/wa` or `/waystone` | Main window |
| `/wa plan`, `/wa combat`, `/wa gear`, `/wa prof`, `/wa pet` | Open one page |
| `/wa talents` | Talent calculator |
| `/wa vendor` | Vendor crafting |
| `/wa ah` | Full auction house scan (at the auction house) |
| `/wa log` | Combat log on or off |
| `/wa sbar ...` | Session bar: goal, advice, zones, summary, history, lock, scale, hide, show |
| `/wa azc ...` | Chronicle: share on or off, sync, week |
| `/wa lang en \| hu` | Interface language |
| `/wa minimap show \| hide \| icon` | Minimap button |
| `/wa style wow \| flat` | Window style |
| `/wa help` | Every command |

## Good to know
- Made for **Forever**: its numbers, not Classic's. The game data (spells, talents, items) comes from Wowhead Forever.
- The interface is **English** by default; Hungarian is one click away.
- Your data stays on your computer, in the game's saved variables.

## Feedback
Found a bug or have an idea? Leave a comment or open an issue.
```

---

## Összefoglaló (magyarul)

**Waystone**: kalandozótárs. Tervezd meg a szintlépést, nézd vissza a harcaidat, rendezd a
felszerelésed, és csinálj aranyat a szakmáidból, egyetlen ablakban.
