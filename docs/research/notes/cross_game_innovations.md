# Cross-Game Companion Tools, Overlays and Mods with Transplantable Ideas for WoW

Research date: 2026-11-25. Around 20 searches/fetches. Popularity figures are hard to find for most tools. The exception is RuneLite, whose Plugin Hub publishes active install counts. Many secondary sources are vendor pages or listicles, and these are flagged below.

## Q1: Standout tools in other games (what they do, adoption, technical method, ToS status)

### Takeaway
The most widely adopted companion tools fall into five groups:
- Contextual guidance (OSRS Quest Helper, 557k installs)
- Activity-specific "solvers" for minigames and bosses (many RuneLite plugins with 200k–340k installs)
- Personal progress and net-worth tracking (Wise Old Man, Exilence CE, gw2efficiency)
- Log-to-shareable-report pipelines (ArcDPS → Elite Insights → dps.report)
- Item and loadout optimizers driven by an official API (DIM)

The technical method sets the ToS risk. Tools that read logs, official APIs, chat-log files or screenshots are tolerated or sanctioned. Tools that inject code or read memory or packets (Dalamud, ArcDPS, LOA Logs) are gray or against ToS.

### Cited Findings

**Old School RuneScape: RuneLite Plugin Hub (the strongest adoption data available)**
- RuneLite Plugin Hub active installs, top entries: Quest Helper 557,697; 117 HD (GPU renderer) 377,068; Sailing 371,837; Tile Packs 360,974; Guardians of the Rift Helper 337,209; Tombs of Amascut 318,141; WikiSync ("shares player data so the wiki can personalize your experience") 304,777; Better NPC Highlight 297,321; Hub Party Panel (side panel with party members' info) 247,192; Banked Experience 231,596; Inventory Setups (saves gear setups per activity) 218,029; Skills Progress 213,649. — [RuneLite Plugin Hub](https://runelite.net/plugin-hub)
- Lower-ranked progress and tracking plugins: Wise Old Man (WOM Utils) 81,471; Collection Log Luck 82,792; Time Tracking Reminder (birdhouse/farming reminders) 76,448; Loot Logger (local loot history) 64,874; Raid Data Tracker 55,660; Dude Where's My Stuff (item location finder) 32,548; Discord Loot Logger 25,539. The fetched portion of the listing showed no AI/LLM plugins. — [RuneLite Plugin Hub](https://runelite.net/plugin-hub)
- Many highly installed plugins are "activity companions" for one minigame or boss, such as Gauntlet 275,720, Zulrah rotations 267,434, Tempoross 244,703, Mahogany Homes 253,205 and Fight Cave Waves 222,534. — [RuneLite Plugin Hub](https://runelite.net/plugin-hub)
- Jagex launched its own separate Plugin Hub for RuneScape 3 (live 19 October 2026, five community plugins at launch). This is an example of a developer officially sanctioning third-party plugins. — [allthings.how](https://allthings.how/runescape-plugin-hub-is-live-with-five-community-plugins-you-can-install-now/); [RS Wiki update page](https://runescape.wiki/w/Update:RuneScape_Plugins_Officially_Available_Now!)
- Wise Old Man is a free, open-source web app and API built on the official hiscores. It tracks gains through snapshots and supports group and clan competitions and achievements. Updates can be triggered from the website, the RuneLite plugin or a Discord bot. — [WOM docs](https://docs.wiseoldman.net/guides/how-to-start-tracking); [WOM GitHub](https://www.github.com/wise-old-man/wise-old-man); [WOM competitions guide](https://docs.wiseoldman.net/guides/how-to-join-a-competition)

**Final Fantasy XIV: Dalamud / ACT**
- Dalamud is the dominant plugin framework (code injection). Square Enix treats it with a "don't ask, don't tell" stance. A community guide states that plugins are against FFXIV ToS and can lead to penalties. — [Materia Raiding plugin page](https://materiaraiding.pages.dev/resources/plugins); [PCGamesN](https://www.pcgamesn.com/final-fantasy-xiv/ff14-mod-plugin-controversy-playerscope)
- Enforcement examples: PlayerScope, a plugin that tracked player data and alts and was called a stalking risk, reportedly received a cease-and-desist and its data was deleted. Yoshi-P warned of legal action. A "legal inquiry" also shut down one of the most popular mods. — [GamesRadar](https://www.gamesradar.com/games/final-fantasy/infamous-final-fantasy-14-plugin-that-could-enable-stalking-reportedly-hit-with-a-cease-and-desist-with-all-player-data-permanently-and-irreversibly-deleted); [Windows Central](https://www.windowscentral.com/gaming/ffxiv-lead-yoshi-p-warns-square-enix-may-pursue-legal-action-against-stalker-enabling-mod); [PC Gamer](https://www.pcgamer.com/games/final-fantasy/legal-inquiry-shuts-down-one-of-final-fantasy-14s-most-popular-mods-adding-yet-another-blurry-line-in-the-sand-from-square-enix)
- Mare, a social and RP syncing tool, is used for RP venues and group posing. — [PCGamesN](https://www.pcgamesn.com/final-fantasy-xiv/ff14-mod-plugin-controversy-playerscope)
- Lesson for WoW: privacy-invasive cross-player tracking draws publisher action and community backlash, even where the tooling is popular. — same sources as above

**Path of Exile / PoE2**
- Exilence CE (formerly Exilence Next) calculates the value of a character, inventory and stash tabs. Friends can group up in the app to see combined net worth. Prices come from the poe.ninja API. — [Exilence CE GitHub](https://github.com/exilence-ce/exilence-ce); [Exilence (original) GitHub](https://www.github.com/viktorgullmark/exilence)
- NeverSink / FilterBlade loot filter: FilterBlade is described as the most popular centralized loot-filter tool for PoE1. It launched for PoE2 on 14 Jan 2025. NeverSink's PoE2 filters reportedly hold positions 1–7 among the most popular filters on pathofexile.com. The PoE2 filter repo has about 2.8k GitHub stars. — [Sportskeeda](https://www.sportskeeda.com/mmo/path-exile-2-poe2-filterblade-neversink); [Maxroll](https://maxroll.gg/poe2/news/filterblade-launch-for-path-of-exile-2); [mein-mmo](https://mein-mmo.de/en/the-most-important-tool-for-path-of-exile-2-receives-a-major-update-for-its-10th-anniversary-from-the-german-developer,1250413); [NeverSink PoE2 GitHub](https://github.com/NeverSinkDev/NeverSink-Filter-for-PoE2/releases)
- Path of Building Community is an offline build planner. No user count was found. — [PoB README](https://cdn.jsdelivr.net/gh/pathofbuildingcommunity/pathofbuilding@dev/README.md)

**Guild Wars 2**
- ArcDPS is a damage meter (injected DLL that GW2 tolerates). Its logs are parsed by GW2 Elite Insights, which can also run locally, and dps.report hosts the parsed report at a unique URL. This is the standard pipeline raiders use. — [Snow Crows log guide](https://snowcrows.com/guides/getting-started/reading-logs); [Elite Insights GitHub](https://www.Github.com/baaron4/GW2-Elite-Insights-Parser); [dps.report](https://dps.report)
- Blish HUD is an overlay platform that hosts modules such as Inquest Chipset and Commander Markers. It can read ArcDPS data, but ArcDPS deliberately delays combat data by several seconds, so modules cannot show real-time combat data. — [Blish HUD ArcDPS integration](https://blishhud.com/docs/user/arcdps-integration); [GamersDecide](https://gamersdecide.com/articles/guild-wars-2-best-addons)
- gw2efficiency computes account value from read-only official API keys. The valuation covers bank, shared inventory, dyes, minis, outfits, recipes and finishers, and the library is open source. Values drop when the official API breaks, so the tool depends entirely on that API. — [gw2efficiency account-value GitHub](https://github.com/gw2efficiency/account-value); [GW2 Wiki API key](https://wiki.guildwars2.com/wiki/API_key); [GW2 forum](https://en-forum.guildwars2.com/discussion/47113/massive-drop-in-account-value)

**EVE Online**
- Intel tools read local chat log files on disk, enrich pilot names through ESI and zKillboard, and raise audible or proximity alarms on a map:
  - HARUSPEX: terminal tool for d-scan and local intel
  - Telescope: open source, reads chat logs, ESI and zKillboard, includes a live killfeed and eve-scout wormhole data
  - IntelPy: cross-platform log monitor with proximity alarms
  - Vintel: plots intel on a dotlan map
  - PySpy: unmaintained

  CCP publishes an official community-tools directory. — [HARUSPEX forum](https://forums.eveonline.com/t/haruspex-terminal-d-scan-and-local-intel-tool-macos-linux-windows/508318); [Telescope](https://forums.eveonline.com/t/telescope-1-1-2-open-source-intel-tool-multiplatform/519696.md); [IntelPy GitHub](https://github.com/Riftr/intelpy/); [Vintel GitHub](https://github.com/bperian/vintel); [PySpy GitHub](https://github.com/Eve-PySpy/PySpy); [EVE developers community tools](https://developers.eveonline.com/docs/community/)
- Wormhole mappers: Tripwire, Pathfinder and Wanderer, a lighter alternative to Pathfinder. — [awesome-eve](https://www.github.com/Proopai/awesome-eve)

**Destiny 2: DIM**
- DIM uses the Bungie.net API to read game state and move or equip items. Its own DIM API syncs tags, notes and saved loadouts. It offers a loadout optimizer and filters. GamesRadar ran a story titled "the game is almost unplayable without apps like DIM" after Bungie disabled third-party API access during an outage. The only user count found is old and dates from Destiny 1: about 200k active users. — [DIM API GitHub](https://github.com/DestinyItemManager/dim-api); [GamesRadar](https://www.gamesradar.com/destiny-2-players-just-got-a-brutal-reminder-that-the-game-is-almost-unplayable-without-apps-like-dim); [Kotaku](https://kotaku.com/1709872503)

**Lost Ark**
- LOA Logs is a Rust DPS meter. Its core packet-handling code is closed source because the packets are encrypted. It is not endorsed by the publisher and carries ban risk. — [loa-logs GitHub](https://gh.ali360.cloudns.ch/snoww/loa-logs); [GGRecon](https://www.ggrecon.com/guides/lost-ark-dps-meter/)

**Competitive game AI coaches and clipping**
- Mobalytics reportedly launched "AI Coach 2.0" in January 2026 with a multi-game GPI diagnostic. The source is weak and the win-rate figure is self-reported. — [technosports](https://technosports.co.in/ai-powered-gaming-tools-are-reshaping-player/)
- Omnic.ai runs AI analysis of uploaded footage. Its free tier allows 5 uploads and 2 insights per game. It has a PlayVS partnership for high-school esports. — [TechRadar](https://techradar.com/computing/artificial-intelligence/can-an-ai-coach-help-your-esports-team-clinch-the-championship); [CB Insights](https://www.cbinsights.com/company/omnic-1)
- Insights.gg is a team VOD-review workspace with timestamped comments and drawing on frames. — [Insights.gg blog](https://insights.gg/blog/what-is-vod-review)
- ESIC's draft framework (Feb 2026) allows post-game AI analysis but bans real-time AI instructions in sanctioned matches. This is a useful precedent for drawing a "post-session vs live" line. — [aiyd comparison](https://aiyd-com.pages.dev/best-ai-for-esports-coaching) (low-reliability source)
- Medal auto-clips detected events (aces, multi-kills, clutches) without a hotkey, using "Medal AI" event detection for supported games. A competitor disputes how broad the support is. Overwolf Outplayed uses game event data from Overwolf integrations. — [Medal auto-clipping](https://medal.tv/ar/auto-clipping); [Medal support](https://support.medal.tv/support/solutions/articles/48001167701-how-to-use-medal-ai); [Eklipse vs Medal](https://eklipse.gg/compare/eklipse-vs-medal-tv)

### Inferences
- The most important adoption pattern is that "context-aware helpers for one specific activity" dominate the RuneLite installs. The 200k–340k plugins are mostly one-minigame or one-boss solvers. WoW's equivalent niche (BigWigs/DBM, WeakAuras) was the most affected by Midnight's in-combat restrictions (see Q3). That shifts value to out-of-combat and out-of-instance helpers.
- Readings of the ToS risk spectrum:
  - Safe: official API (DIM, gw2efficiency, WOM through hiscores) and log or file readers (EVE intel, Warcraft Recorder, Elite Insights).
  - Tolerated gray: ArcDPS.
  - Against ToS or legally risky: Dalamud, PlayerScope, LOA Logs packet capture.

  WoW's model (sandboxed Lua plus external readers of SavedVariables and the combat log file) maps onto the "safe" tier.

## Q2: Emerging 2025–2026 trends (AI companions, overlays, recaps, clipping)

### Takeaway
Platform-level AI overlays now exist in production beta: Microsoft Gaming Copilot in Game Bar and NVIDIA G-Assist with a plugin hub. Both understand games through screenshots and voice. Many indie "AI game companions" use the same external, screen-only, non-injecting design, which is the only architecture compatible with WoW's ToS. No MMO-specialised AI companion was found, apart from small WoW hobby projects (Q3).

### Cited Findings
- Microsoft Gaming Copilot (Beta): went to Xbox Insiders in Game Bar in August 2025 and to all 18+ PC Game Bar users in September 2025, with the Xbox mobile app following in October. Features: Voice Mode while playing, answers based on screenshots, "proactive coaching" announced as a future feature. Reviewers raised open questions about anti-cheat and performance. — [Xbox Wire Aug 2025](https://news.xbox.com/en-us/2025/08/06/gaming-copilot-beta-begins-rolling-out-to-xbox-insiders-on-game-bar-today/); [Xbox Wire Sep 2025](https://news.xbox.com/en-us/2025/09/18/gaming-copilot-xbox-pc-mobile/); [Tom's Hardware](https://www.tomshardware.com/software/windows/gaming-copilot-hits-windows-in-public-beta)
- NVIDIA Project G-Assist: a local on-device AI assistant. Details:
  - A plug-in hub was added in August 2025.
  - The 2026 update works on all RTX GPUs with 6GB+ VRAM, using a lighter model.
  - Users can download plugins directly in G-Assist with no restart.
  - It ships an Elgato Stream Deck plugin through MCP.
  - A Cursor-based Plug-in Builder supports "vibe-coding" plugins, and developers can submit plugins to NVIDIA.

  — [NVIDIA G-Assist page](https://www.nvidia.com/en-us//software/nvidia-app/g-assist); [NVIDIA blog Plug-In Builder](https://blogs.nvidia.com/blog/rtx-ai-garage-g-assist-plugin-builder); [Notebookcheck](https://www.notebookcheck.net/Nvidia-expands-Project-G-Assist-with-plug-in-hub-leaner-model-and-wider-RTX-support.1089322.0.html); [TweakTown](https://www.tweaktown.com/news/107134/nvidias-g-assist-can-now-download-and-install-its-own-plugins-all-you-need-to-do-is-ask/index.html)
- Indie AI companions:
  - AiGameCompanion: transparent always-on-top overlay with voice and screenshot context; uses Gemini, Claude or OpenAI; no injection. — [GitHub](https://github.com/swang666/AiGameCompanion)
  - OpenGameMate: can run fully offline with Ollama, using screen-only perception. — [opengamebot.ai](https://opengamebot.ai/)
  - Sidekick: states it does not inject code, modify game files or read memory, and watches only the screen. — [Sidekick](https://sidekick.modax.ai/gaming-ai-overlay)
  - Questie.ai: multi-LLM voice and vision companion that claims MMO support. — [Questie](https://www.questie.ai/)
  - HakkoAI. — [hakko.ai](https://www.hakko.ai/)
  - Capri (Cyberpunk 2077 mod): local voice option of about 900 MB. — [Nexus Mods](https://www.nexusmods.com/cyberpunk2077/mods/37034)
- No MMO-focused AI companion project was found in the search; MMO support appears only as a general claim from Questie. — [search summary of the above sources]
- Auto-highlight clipping is a mature category: Medal AI event detection, Outplayed through Overwolf event APIs, NVIDIA Highlights, and Eklipse/Clypse AI detection on recorded footage. — [Medal](https://medal.tv/ar/auto-clipping); [Eklipse blog](https://blog.eklipse.gg/tools/ai-clip-maker-gaming.html); [TechCrunch](https://techcrunch.com/?p=2200891)

### Inferences
- G-Assist's MCP-based plugin hub and Gaming Copilot's screenshot Q&A show that a "WoW knowledge plugin" could plug into these platforms. It would feed them structured state from SavedVariables or the combat log instead of relying on raw screenshots. Being a data provider to platform assistants may be a cheaper entry point than building a standalone overlay.
- AI-generated session recaps (for example "what you did tonight: loot, gold delta, keys, deaths, progress") did not appear as a named product category in any game. This is a possible white space everywhere, not only in WoW. Unverified: absence in search results is not proof that nothing exists.

## Q3: Which concepts are clearly absent in WoW, and which already exist or are being attempted?

### Takeaway
WoW already covers recording triggered by the combat log (Warcraft Recorder), and a wave of small LLM projects (wow-agent, AzerothLM, Warband Companion, ParsePal, Midnight Sensei) is starting in 2026. None has visible scale. Midnight (12.0) moved real-time combat data behind "Secret Values" and added a built-in damage meter. That makes out-of-instance and post-session external tools the main area left for innovation. The clearest gaps compared with other games: (1) a cross-character net-worth and progress timeline with friend or guild competitions, like Wise Old Man, Exilence or gw2efficiency; (2) a polished AI post-session coach or recap; (3) WikiSync-style personalization of a guide or wiki; (4) EVE-style external chat-log intel and alerts; (5) RuneLite-scale activity "solvers" outside combat.

### Cited Findings
- **Already exists in WoW:**
  - Warcraft Recorder is an open-source desktop recorder that watches the WoW combat log file and records interesting events automatically. Companion addons such as "PvP Combat Log On" switch on combat logging so it can trigger. — [wow-recorder GitHub](https://github.com/aza547/wow-recorder); [CurseForge PvP Combat Log On](https://www.curseforge.com/wow/addons/pvpcombatlogon)
  - Archon has announced an "Archon app" for WoW. The page could not be fetched (HTTP 403), so its features are unverified. — [archon.gg](https://www.archon.gg/wow/articles/news/introducing-archon-app)
- **Emerging WoW LLM tools (small, self-published):**
  - wow-agent: a Lua addon exports state to SavedVariables, which are written on reload or logout, and an Electron chat app reads them. It supports Anthropic, OpenAI and Copilot providers. — [wow-agent GitHub](https://github.com/Oighty/wow-agent)
  - AzerothLM. — [GitHub](https://github.com/chefm4tt/AzerothLM)
  - azeroth-companion. — [ecosyste.ms](https://awesome.ecosyste.ms/projects/github.com%2Fnardo86%2Fazeroth-companion)
  - Warband Companion: a desktop app that reads SavedVariables and adds combat analytics. — [CurseForge](https://www.curseforge.com/wow/addons/warband-companion)
  - ParsePal: web-based rotation feedback on an uploaded combat log. — [theresanaiforthat](https://theresanaiforthat.com/ai/parsepal/)
  - Midnight Sensei: "real-time combat coaching". — [CurseForge](https://www.curseforge.com/wow/addons/midnight-sensei)
  - Also: WoWGPT, Azeroth AI, AzerMind, TacticsCoach and WoW AI Prompter. — [CurseForge WoWGPT](https://www.curseforge.com/wow/addons/wowgpt); [Azeroth AI](https://www.curseforge.com/wow/addons/azeroth-ai); [AzerMind](https://www.curseforge.com/wow/addons/azermind); [TacticsCoach](https://www.curseforge.com/wow/addons/tacticscoach)
- **Midnight (12.0) constraints:**
  - "Secret Values" hide combat numbers from tainted addon code.
  - Addons can no longer read the combat log or combat chat inside dungeons and raids.
  - Addons cannot send communications to other players while in an instance.
  - Blizzard ships built-in boss warnings, cooldown tracking, audio alerts and a damage meter (C_DamageMeter).
  - ExitLag reports that the combat log text file stays readable for external tools. This is a secondary source; check it against Blizzard's own notes.

  — [Blizzard: Combat Philosophy and Addon Disarmament](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight); [warcraft.wiki.gg 12.0.0 API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes/notes); [Wowhead damage meter](https://www.wowhead.com/news=379952/new-updates-made-to-blizzards-damage-meter-in-midnight-beta); [ExitLag](https://www.exitlag.com/blog/world-of-warcraft-addon-changes/); [PCGamesN](https://www.pcgamesn.com/world-of-warcraft/midnight-alpha-disables-combat-mods)

### Inferences
Candidate "game-changer" transplants, with a feasibility note for each. WoW equivalents marked "known" come from general domain knowledge and were not re-verified in this session.

1. **Wise Old Man-style progress timeline and competitions** (OSRS, 81k plugin installs plus web/API/Discord). Tracks multi-character gains over time (ilvl, M+ rating, gold, collections, rep, achievements), with snapshots, group and guild competitions, and a Discord bot.
   - Feasibility: high. SavedVariables export plus Blizzard's public profile API.
   - Known partial WoW equivalents: Raider.IO (M+ only) and Wowaudit (guild sheets). No general "gains tracker with competitions" was found.
2. **Exilence / gw2efficiency net-worth tracker.** Values every character's bags, bank and Warband bank, plus mounts and transmog, at AH prices, shows the history, and lets friend groups compare.
   - Feasibility: high. SavedVariables plus AH price data.
   - Known partial: TSM / Saddlebag Exchange gold tracking. No "account value over time" dashboard like gw2e was verified.
3. **AI post-session recap and coach.** Reads the combat log file and SavedVariables after the session to produce a narrative recap and three improvement points, staying on the "post-game" side of the ESIC line.
   - Feasibility: high. Only small hobby projects exist (wow-agent, ParsePal), so the niche is uncrowded but no longer empty.
4. **Auto-highlight clipping with AI tagging.** Warcraft Recorder already records fights. The gap is automatic highlight *selection* (wipe moments, clutch saves, key timer finishes) and shareable short clips, as Medal or Outplayed do.
   - Feasibility: high (combat-log timestamps let the tool find moments in the recording).
5. **WikiSync-style personalization** (305k installs). Wowhead or a guide site shows "what you still need" for your account.
   - Known: the Wowhead Client already uploads collections. Unverified here.
6. **Quest Helper-style contextual step guidance** (557k, the #1 plugin). Known WoW equivalents: Zygor, RestedXP, Questie (Classic). Not clearly absent; lower opportunity.
7. **Activity "solvers" for non-combat content** (Mahogany Homes, Giants' Foundry, Hunter Rumours, Port Tasks: 200k–250k each). The WoW analogue would be helpers for professions, housing (Midnight player housing), delves, world events and weekly chores, all outside instance restrictions.
   - Feasibility: high, because Secret Values mainly affect combat inside instances.
8. **Time-tracking reminders** (birdhouses, farming): reminders for weekly resets, profession cooldowns, crafting orders and renown caps across all alts, delivered as desktop or phone notifications from a SavedVariables reader.
   - Feasibility: high. External notifications are needed because addons only run in-game.
9. **Inventory Setups / DIM loadout optimizer.** DIM-like gear optimization *across* characters and banks is limited in WoW because there is no item-move API. Plan-only optimizers (Raidbots / SimC) exist.
   - Feasibility: medium, as recommendations only; moving items automatically would be automation.
10. **EVE-style chat-log intel and alerts.** An external reader of WoW chat logs (WoWChatLog.txt) that alerts on keywords such as LFG and trade matches or guild calls.
    - Feasibility: medium. It needs /chatlog enabled, and chat inside instances is now Secret.
11. **GW2 log → shareable report pipeline.** Already covered in WoW by Warcraft Logs. No gap.
12. **Loot filter (FilterBlade).** Not applicable to WoW's loot model; a loot-*evaluation* overlay (keep or sell or vendor-value advice) is the closer analogue.
13. **Platform AI overlays** (Gaming Copilot, G-Assist plugins). A WoW-aware G-Assist or MCP plugin that serves structured character state to the assistant.
    - Feasibility: high and novel. Nothing like it was found.
14. **Hub Party Panel** (247k). Shared party info between addon users. Addon-to-addon communication is now blocked inside instances, so this only works out of instance.
15. **Privacy lesson from PlayerScope.** Any cross-player tracking or lookup feature risks backlash. Keep data first-party and opt-in.

### Gaps
- No install or MAU figures were found for Dalamud plugins, ACT, ArcDPS, Blish HUD, Path of Building, DIM (current), Exilence CE, Mobalytics or Medal. RuneLite is the only ecosystem with public install counts.
- The Archon app article returned 403, so its features (possible recording or AI) are unverified.
- CurseForge and Wago download counts for the WoW AI addons listed were not checked, so their traction is unknown. Some listings looked inconsistent.
- Not verified: whether the WoW combat log file remains fully detailed in instances after Midnight (only ExitLag claims this), and the exact wording of Blizzard's policy on external apps that read SavedVariables.
- No sources were found specifically on MMO accessibility tools (for example FFXIV TextToTalk, OSRS TTS plugins, WoW VoiceOver) or on AI-generated session recaps as a product category. Both are worth a targeted follow-up.
- Mobalytics "AI Coach 2.0" and Omnic details come from low-reliability listicles and vendor pages.
- Microsoft Gaming Copilot's status after the beta (GA, proactive coaching delivery) was not confirmed for late 2026.
