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
Everything is worked out inside the game, from what your character knows and what the auction house
shows right now.

## Features

### Vendor crafting: gold from a single sale
Which craft brings the most gold when you sell it to a vendor?
- Set how many times you craft (1, 5, 20 or **Best batch**). The costs, the vendor income and the net
  profit follow the number, because buying more reagents pulls in dearer listings.
- Prices come from **live auction house listings**: open the window at the auction house and it checks
  the reagents of the 10 best crafts of **every profession**.
- Losing recipes are hidden. Every column explains itself on mouse-over.
- Vendor sell prices come straight from the game client, so they are always exact.

### Combat log and score
- Every fight is recorded from the game's own damage meter: damage, DPS, the abilities you used and
  a **combat score** (S to D).
- Fights with no damage dealt (a potion and a vanish) are left out.
- Look back at your recent fights to see whether a new rotation or item really helped.

### Plan and gear *(Rogue only for now)*
- **Plan**: what to buy and what to do next, worked out from your level, gold and skills.
- **Gear**: what is worth replacing and which dungeon or quest drops the upgrade, using a damage
  model of your character.

### Professions
- The cheapest route to the next skill cap, with a shopping list.
- Reads the recipes you know from the profession window.

### Session bar
A compact bar with this session's playtime, XP per hour and gold, with goals, zone stats and history.

### Chronicle
A journal of your character's milestones, week by week.

### Also
- Minimap button (left click: main window, right click: vendor crafting, Shift-click: session bar).
  It is listed in the addon compartment too.
- Search box on every page.
- Two window styles: game-style frames or a clean flat look (`/wa style wow | flat`).

## Commands

| Command | What it does |
|---|---|
| `/wa` or `/waystone` | Main window |
| `/wa plan`, `/wa combat`, `/wa gear`, `/wa prof` | Open one page |
| `/wa vendor` | Vendor crafting |
| `/wa ah` | Full auction house scan (at the auction house) |
| `/wa sbar ...` | Session bar: goal, summary, history, lock, scale, hide, show |
| `/wa minimap show \| hide \| icon` | Minimap button |
| `/wa style wow \| flat` | Window style |
| `/wa help` | Every command |

## Good to know
- **Language:** the interface is **Hungarian** for now. English is coming.
- **Plan and gear** are for Rogues for now; the other pages work for every class.
- Your data stays on your computer, in the game's saved variables.

## Feedback
Found a bug or have an idea? Leave a comment or open an issue.
```

---

## Összefoglaló (magyarul)

**Waystone**: kalandozótárs. Tervezd meg a szintlépést, nézd vissza a harcaidat, rendezd a
felszerelésed, és csinálj aranyat a szakmáidból, egyetlen ablakban.
