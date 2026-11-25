# Unmet needs and recurring pain points of WoW players (Retail + Classic), 2024–2026

Research date: 2026-11-25. Method: about 20 web searches and fetches. Main sources: Blizzard US/EU forums, PCGamesN, MMO-Champion, Wowhead, CurseForge listings, Comicbook.com and guide sites.

**Important caveat on sources:**
- Reddit threads did not surface through the search tool at all, so no Reddit upvote counts are available.
- Demand evidence is limited to Blizzard forum like counts (small numbers) and to press coverage.
- Several 2026 search results mention a "WoW Forever" game version/server type that Midnight addon limits reportedly also apply to. I could not confirm what that product is, so treat those references with care.

---

## Q1. What do players repeatedly complain about or wish for? (master list of 22 pain points)

### Takeaway
The strongest, best-evidenced unmet needs fall into four clusters:
1. Things the Midnight 12.0 API restrictions made impossible or degraded: personal combat-state tracking, interrupt and cast awareness, in-instance addon sync, and PvP tools.
2. Onboarding and "what do I do next" guidance for returning or casual players.
3. Social discovery: guild finding, guild profiles and loot tools.
4. New-system friction in housing and Warbound alt gearing.

Accessibility and chat translation have addons, but each covers only part of the problem.

### Cited Findings

**A. Combat / Midnight-era (see Q2 for detail)**

1. **Tracking your own buffs, procs, resources and cooldowns in combat (the WeakAuras gap).**
   - Midnight's "secret values" hide your own buffs, resources and cooldowns from addons. — [PCGamesN, Nov 29 2025](https://www.pcgamesn.com/world-of-warcraft/midnight-weakauras-update)
   - The WeakAuras team calls tracking your own combat state "the core functionality of WeakAuras". They say a version without it would be "nearly useless", and they will not ship one. — [PCGamesN](https://www.pcgamesn.com/world-of-warcraft/midnight-weakauras-update); [MMO-Champion](https://www.mmo-champion.com/content/13710-WeakAuras-Ends-Addon-Support-for-Midnight)
   - Players still ask for WeakAuras back in an August 2026 "what addon do you wish existed" thread. — [Blizzard forums, Aug 15 2026](https://us.forums.blizzard.com/en/wow/t/what-addon-do-you-wish-existed-but-nobody-seems-to-have-made-properly-yet/2337182)

2. **Interrupt-priority / enemy-cast awareness.**
   - Wish: an addon that scans enemies in combat, lists the priority interrupts and marks the targets. The poster implies a version of this once existed. — [Blizzard forums wish thread, Aug 2026](https://us.forums.blizzard.com/en/wow/t/what-addon-do-you-wish-existed-but-nobody-seems-to-have-made-properly-yet/2337182)
   - Midnight hides NPC identities, buffs/debuffs and spell casts from nameplate addons. — [PCGamesN](https://www.pcgamesn.com/world-of-warcraft/midnight-weakauras-update)

3. **Cooldown tracking that is accurate and customizable.**
   - Blizzard's built-in Cooldown Manager is configured through Edit Mode. — [Wowhead UI hub](https://www.wowhead.com/guide/ui/user-interface-hub-raidframes-damage-meter-timelines-edit-mode)
   - Addons that extend it say they offer only "limited (where API restrictions allow us)" custom tracker support. — [TerribleBuffTracker on Wago](https://addons.wago.io/addons/terriblebufftracker)
   - A custom tracker counts down a typed-in duration from the cast, so haste and cooldown reduction are not reflected. — reported in [epiccarry Midnight addon guide](https://epiccarry.com/blogs/wow-midnight-pre-patch-addons/) and summarized via search; not independently verified.

4. **In-instance group coordination and addon sync.**
   - Midnight blocks addons from freely sending and receiving chat/addon messages during combat. — [PCGamesN](https://www.pcgamesn.com/world-of-warcraft/midnight-weakauras-update)
   - Guides report that addons cannot sync with each other in real time inside instances, and cannot read health, debuffs or cooldowns during boss fights or M+. — [mythic-store guide](https://mythic-store.com/blog/best-wow-midnight-addons-what-still-works-after-the-api-overhaul) (commercial source)

5. **PvP tooling loss.** A poster laments that "useful PvP addons" were removed. — [Blizzard forums wish thread, Aug 2026](https://us.forums.blizzard.com/en/wow/t/what-addon-do-you-wish-existed-but-nobody-seems-to-have-made-properly-yet/2337182)

6. **Stability and diagnosis: Lua errors and silent breakage.**
   - An August 2026 forum thread reports Lua errors even with addons disabled. The poster blames the default UI's own use of secret values. — [Blizzard forums "anti consumer practices of midnight"](https://us.forums.blizzard.com/en/wow/t/the-anti-consumer-practices-of-midnight/2336536) (summarized from search; not fetched)
   - A last-minute API change in patch 12.0.1 broke action bar addons (ElvUI, Bartender) mid-dungeon. — [Wowhead News](https://www.wowhead.com/news/action-bar-addons-affected-by-last-minute-addon-changes-380950)

**B. Onboarding, learning, improvement**

7. **Returning-player overload and "what should I prioritize".** Original post: [Blizzard US forum, Nov 12 2025](https://us.forums.blizzard.com/en/wow/t/returning-player-experience-%E2%80%93-overwhelming-systems-lack-of-guidance-and-poor-clarity/2198684), 2 likes, 1 reply.
   - Warbands, Delves, Renown, professions and many currencies are layered "with no onboarding or prioritization". The game feels "more like homework".
   - Tooltips are vague; the example given is Earth-Encrusted Gems.
   - The player spent more time on Wowhead and Icy Veins than in game.
   - Asks: a returning-player orientation, better tooltips, and guidance on priorities.

8. **"Game doesn't explain itself" for casual/returning players.** Thread: [EU forum, Oct 8 2026](https://eu.forums.blizzard.com/en/wow/t/wow-is-becoming-too-complicated-for-returning-and-casual-players/634303), about 20 posts and about 27 likes on page 1.
   - The original poster needed about 5 months, plus help from guildmates, to learn crafting, roll tokens and upgrades.
   - Specific complaints: satchels don't say whether they give crests or gear; pet battles start in old zones; nobody tells you to talk to Chromie; flying unlocks are unclear.
   - Asks: an optional simplified beginner UI. Replies joke about a "Clippy" or AI helper.
   - Counterpoint in the same thread: veterans say the information exists in tooltips and quest chains, but players skip reading it.

9. **Professions abandoned because they are too opaque.** A reply in the Nov 2025 thread says the player has given up on professions, once a favorite part of the game. — [Blizzard US forum](https://us.forums.blizzard.com/en/wow/t/returning-player-experience-%E2%80%93-overwhelming-systems-lack-of-guidance-and-poor-clarity/2198684). Note: profession *planners* are excluded from scope; the unmet need here is conceptual explanation, not planning.

10. **Learning M+ without trial and error / a solo practice path.** A player says they must watch long guides before their first key because they can't learn through solo trial and error. Someone suggests a solo queue. — [EU forum, Oct 2026](https://eu.forums.blizzard.com/en/wow/t/wow-is-becoming-too-complicated-for-returning-and-casual-players/634303)

11. **Turning logs into actionable improvement.**
    - Guides admit many players "feel overwhelmed when they first open a log". — [exitlag guide](https://www.exitlag.com/blog/wow-classic-logs/), [Icy Veins forum guide](https://www.icy-veins.com/forums/topic/26240-how-to-use-warcraft-logs-part-2-personal-performance/) (older)
    - A forum user notes WoWAnalyzer showed them they were holding cooldowns all fight, which raw logs did not make obvious. — [Blizzard forums "how to read logs"](https://us.forums.blizzard.com/en/wow/t/how-to-read-wow-logs-parses/841229?page=2) (older, pre-2024)
    - New in-game "coach" addons are appearing: [TacticsCoach](https://www.curseforge.com/wow/addons/tacticscoach) (live tips plus a post-fight report) and [Midnight Sensei](https://www.curseforge.com/wow/addons/midnight-sensei). This suggests developers see the demand. How well they work under secret values is unverified.

**C. Social / guild / group**

12. **Guild discovery that actually filters.** Wish from the [Blizzard forums thread, Aug 15 2026](https://us.forums.blizzard.com/en/wow/t/what-addon-do-you-wish-existed-but-nobody-seems-to-have-made-properly-yet/2337182) (6 likes, the top post):
    - A guild finder showing more than 3 results per page.
    - Filters by raid difficulty and schedule, M+ key range, RBGs and arena.
    - Today's workaround is code strings in the listing text, which is cramped for space.
    - The EU thread also calls the guild finder broken, with "ghost guilds". — [EU forum](https://eu.forums.blizzard.com/en/wow/t/wow-is-becoming-too-complicated-for-returning-and-casual-players/634303)

13. **Richer guild profiles / guild UI overhaul.** Wish: let guilds say much more about themselves, plus a broader guild UI rework. 1 like. — [Blizzard forums wish thread](https://us.forums.blizzard.com/en/wow/t/what-addon-do-you-wish-existed-but-nobody-seems-to-have-made-properly-yet/2337182)

14. **Schedule-compatible adult/casual groups.**
    - Recruitment posts repeatedly stress age (30s–50s), families and careers, and "not clocking into a second job". They advertise schedule fit and "no minimum attendance". — [Blizzard forums recruitment](https://us.forums.blizzard.com/en/wow/t/older-player-looking-for-casual-friendly-and-helpful-guild/2331854); [EU casual guild for Midnight](https://eu.forums.blizzard.com/en/wow/t/player-looking-for-a-new-casual-guild-for-midnight/608207)
    - Third-party listing sites fill part of the gap: [guildsofwow.com](https://guildsofwow.com/looking-for-guild), [wowguildfinder.com](https://wowguildfinder.com/)

15. **Reliable loot distribution tooling.** Wish: a "more robust, less buggy" RC Loot Council. — [Blizzard forums wish thread](https://us.forums.blizzard.com/en/wow/t/what-addon-do-you-wish-existed-but-nobody-seems-to-have-made-properly-yet/2337182)

16. **Automated premade group formation for content without queues.** Wish: automate premade group forming for dungeons and raids that lack queues. — [same thread](https://us.forums.blizzard.com/en/wow/t/what-addon-do-you-wish-existed-but-nobody-seems-to-have-made-properly-yet/2337182)

**D. Alts, housing, collections, QoL**

17. **Warbound gear routing / alt prioritization.**
    - Wish: rank alts and show which one gains most (5–10%+) from a Warbound or BoE item. Altoholic requires manual checking. — [Blizzard forums thread](https://us.forums.blizzard.com/en/wow/t/what-addon-do-you-wish-existed-but-nobody-seems-to-have-made-properly-yet/2337182)
    - The same poster released "Warbound Gear Router" on CurseForge (announced Sept 14 2026), so this gap is now partially filled.

18. **Housing: decor buying, planning and layout friction.** Source: [Comicbook.com, Dec 24 2025](https://comicbook.com/gaming/list/biggest-player-housing-changes-wow-needs-to-make-in-2026/)
    - Decor must be bought in exact quantities at specific shops, then carried home. If you buy the wrong count of something like fences, you travel back. Costs "can get pretty steep".
    - Structural customization is limited, and neighborhoods feel empty.
    - The [Decor request megathread](https://us.forums.blizzard.com/en/wow/t/decor-request-megathread/2243154?page=34) adds requests to lock placed decor (one user has about 1K items placed), plus outdoor versions of indoor items and per-room weather.
    - A decor-collection tracker addon already exists ("Home Bound" and others, via [Yahoo/PC Gamer](https://tech.yahoo.com/gaming/articles/world-warcrafts-adding-player-housing-161906705.html)), so the unmet part is layout planning, a shopping list and layout sharing.

19. **Mail QoL replacement.** Wish: a Postal replacement, because "Postal is no longer maintained". — [Blizzard forums thread](https://us.forums.blizzard.com/en/wow/t/what-addon-do-you-wish-existed-but-nobody-seems-to-have-made-properly-yet/2337182)

20. **Cosmetic, modular quest/objective tracker.** Wish: a skinnable, movable, modular tracker. The existing option is updated very late. — [same thread](https://us.forums.blizzard.com/en/wow/t/what-addon-do-you-wish-existed-but-nobody-seems-to-have-made-properly-yet/2337182)

21. **Flight-instrument HUD for skyriding.** Wish: an aircraft-style instrument "T" (attitude, airspeed, altimeter, heading). It can't be built because the API gives no Z coordinate. Niche. — [same thread](https://us.forums.blizzard.com/en/wow/t/what-addon-do-you-wish-existed-but-nobody-seems-to-have-made-properly-yet/2337182)

**E. Accessibility and language**

22. **Accessibility beyond blind players.**
    - Blind players are served by a niche addon, [BlindSlash](https://www.curseforge.com/wow/addons/blindslash): it reads quest text and tooltips aloud and works with keyboard navigation (updated Sept 2026).
    - Players who can't use voice chat have [Accessibility TTS](https://www.curseforge.com/wow/addons/accessibilitytts), with only about 254 downloads.
    - Motion and peripheral-visual sensitivity: a free addon, "Sensory Vignette", was released Nov 8 2026. The same foundation sent Blizzard a report on bouncing quest markers and spell effects. — [International Misophonia Foundation](https://misophoniafoundation.com/the-international-misophonia-foundation-releases-free-world-of-warcraft-addon-that-lets-players-shade-out-peripheral-movement/)
    - Blind players asked for help mapping quest routes. — [MMO-Champion thread, about 2023, older](https://www.mmo-champion.com/threads/2647361-Requesting-help-with-mapping-the-game-for-totally-blind-players-(No-coding-needed))

23. **Chat translation that works where it matters.** Many translators exist, but each falls short:
    - [Chat-Translator](https://www.curseforge.com/wow/addons/chat-translator) translates word by word and "goes silent in dungeons and raids" because the game hides chat from addons there.
    - [TranslatorZ](https://www.curseforge.com/wow/addons/translatorz) says long sentences come out clumsy.
    - Companion-app tools ([BianLingo](https://www.curseforge.com/wow/addons/bianlingo-chat-translator), [WOWGLING](https://www.curseforge.com/wow/addons/wowgling-chat-translator), [wowaichat](https://wowaichat.com/)) need setup, and some send text to cloud providers.

**F. UI setup burden**

24. **Mental load of building and maintaining a UI.**
    - 2026 guides advise a "native-first" setup and warn that "a larger custom UI means more addon layers and profiles; greater patch and compatibility risk". — [TechBloat](https://www.techbloat.com/configure-wow-for-launch-a-native-first-settings-and-addon-plan.html)
    - ElvUI "can feel overwhelming to configure from scratch", per a 2026 guide summarized via search.
    - Blizzard moved many addon jobs into the client: a damage meter (off by default), the Cooldown Manager, and Edit Mode. — [Blizzard Watch, Jan 21 2026](https://blizzardwatch.com/2026/01/21/activate-use-new-built-damage-meter-wow-midnight/); [Wowhead UI hub](https://www.wowhead.com/guide/ui/user-interface-hub-raidframes-damage-meter-timelines-edit-mode)

**G. Classic**

25. **Classic-specific wishes: weak evidence.**
    - Questie is still described as a must-have because the game "doesn't really track quests". — [Sportskeeda hardcore addons](https://sportskeeda.com/mmo/5-best-addons-install-wow-classic-hardcore) (older)
    - SoD Hardcore relies on a community Hardcore addon without official backing. — [Sportskeeda](https://sportskeeda.com/mmo/how-play-wow-classic-season-of-discovery-hardcore-rules-restrictions-and-more)
    - I found no 2025–2026 Classic-specific "addon request" evidence.

### Inferences
- The single highest-signal "radically new" area is **out-of-combat or out-of-instance intelligence**, because in-combat data is now locked. Examples:
  - pre-pull and post-fight review and coaching;
  - interrupt and kick planning done *before* the pull;
  - onboarding and prioritization ("what should I do this week with 3 hours");
  - guild and group matchmaking by schedule and goals.

  These live where the API is still open, or in companion apps fed by logs or the Battle.net API.
- Onboarding pain is persistent and cross-expansion: both the TWW (Nov 2025) and Midnight (Oct 2026) threads describe the same problems. A contextual "explain this item/currency/system and whether I should care" layer is a recurring ask that the known excluded categories (todo lists, guides) do not cover.
- Guild/social discovery is under-served. The top-liked wish in the Aug 2026 thread was a better guild finder, and third-party websites exist only outside the game.
- Several wishes target *maintenance* gaps rather than new ideas (Postal, RCLC, quest tracker skin). An abandoned-but-loved-addon revival is a low-risk niche.

### Gaps
- **No Reddit data.** The search tool returned no r/wow, r/classicwow, r/wowaddons or r/CompetitiveWoW threads, so upvote counts are unavailable. The only engagement numbers are Blizzard forum likes, which are small (1–9).
- No evidence found for deaf or hard-of-hearing players (caption needs) or for colorblind-specific complaints in 2024–2026.
- No evidence gathered on transmog/mount goal planning, lore/story engagement, or time-limited "dad gamer" session planning beyond guild recruitment posts.
- CurseForge/Wago "addon request" boards and Wowhead comment threads were not fetched.

---

## Q2. Which needs are new or worse after the Midnight 12.0 addon restrictions?

### Takeaway
Midnight (released March 2, 2026) made five kinds of addon data "secret":
- the player's own combat state (buffs, procs, resources, cooldowns);
- NPC cast, identity and aura info on nameplates;
- in-combat addon communication;
- unit health arithmetic, which affects raid frames;
- full boss mod logic.

Blizzard loosened some restrictions, but WeakAuras still declined to return. The new built-in tools (damage meter, Cooldown Manager) are judged adequate by some guides but limited in customization.

### Cited Findings
- Midnight's API restrictions make WeakAuras Conditions, Actions and multiple triggers "completely impossible". The team will not release a Midnight version. — [MMO-Champion](https://www.mmo-champion.com/content/13710-WeakAuras-Ends-Addon-Support-for-Midnight); [PCGamesN interview](https://www.pcgamesn.com/world-of-warcraft/midnight-weakauras-interview-stanzilla)
- Ion Hazzikostas framed the goal as addons that personalize, but "aren't giving you an objective competitive advantage over people using the base UI". Blizzard loosened some limits after the beta. WeakAuras said the changes "don't really pass muster". — [PCGamesN, Nov 29 2025](https://www.pcgamesn.com/world-of-warcraft/midnight-weakauras-update); [Icy Veins](https://www.icy-veins.com/wow/news/weakauras-responds-to-addon-limitation-loosening-in-midnight/) (fetch blocked, 403; headline only)
- Affected per the WA team: ElvUI and ConsolePort, as well as WeakAuras. — [PCGamesN](https://www.pcgamesn.com/world-of-warcraft/midnight-weakauras-update)
- Launch coverage lists WeakAuras, DBM, Plater and BigWigs as unable to work as before. Addons can see that an event happened, but not its details. — [Escapist](https://www.escapistmagazine.com/world-of-warcraft-midnight-addon/) (summarized via search)
- Unit health returned as a secret value broke third-party raid frames; Grid2 threw arithmetic errors. Reported for "WoW Forever". — [wowforeverbuilds.com](https://wowforeverbuilds.com/news/what-the-wow-forever-beta-breaks-for-addons-secret-health-values-dead-secure-sni)
- Patch 12.0.1 shipped an untested API change that broke action bar addons. — [Wowhead](https://www.wowhead.com/news/action-bar-addons-affected-by-last-minute-addon-changes-380950)
- Built-in replacements:
  - The damage meter is off by default, with per-ability breakdown and Edit Mode styling. — [Blizzard Watch](https://blizzardwatch.com/2026/01/21/activate-use-new-built-damage-meter-wow-midnight/)
  - The Cooldown Manager is extended by addons such as Arc UI, within API limits. — [Wowhead best addons](https://www.wowhead.com/guide/ui/best-addons-boss-mods-nameplates-raidframes)
  - Details! is still rated above the default meter for post-fight breakdowns, per guide summaries.
- Chat translators go silent inside dungeons and raids because chat is hidden from addons there. This is a direct Midnight-era degradation for non-English group play. — [Chat-Translator CurseForge](https://www.curseforge.com/wow/addons/chat-translator)

### Inferences
**New or worse needs created by Midnight:**
- custom proc and resource alerts (personal combat-state awareness);
- interrupt and cast prioritization;
- raid frame logic;
- instance-wide addon coordination (assignments, sync);
- PvP enemy tracking;
- in-instance translation;
- error and breakage diagnosis when an addon breaks without warning after a patch.

**Openings for new tools:**
- An "addon health check" tool: which addons break after a patch, which built-in feature replaces each, and a migration guide.
- "Cooldown Manager / Edit Mode preset sharing" as a lightweight replacement for WeakAuras-string sharing.
- Pre-pull and post-pull review in place of live alerts.

Of these, the last is consistent with Blizzard's "no competitive advantage over the base UI" principle, so it is less likely to be blocked later.

### Gaps
- The exact list of whitelisted or restored spells and APIs after the beta loosening is not captured; the Icy Veins page returned 403.
- No quantitative player sentiment data was found (polls, upvotes).
- "WoW Forever" could not be clearly placed relative to Retail/Classic.

---

## Q3. Which needs stay unmet even though addons exist, and why do existing ones fall short?

### Takeaway
Existing addons often fail on maintenance, on API ceilings or on usability, not on a missing concept.

### Cited Findings
- Altoholic covers alt data, but deciding which alt should get Warbound gear needed manual checking. A new addon (Warbound Gear Router) appeared in Sept 2026. — [Blizzard forums](https://us.forums.blizzard.com/en/wow/t/what-addon-do-you-wish-existed-but-nobody-seems-to-have-made-properly-yet/2337182)
- RC Loot Council is called "buggy", Postal "no longer maintained", and the quest tracker skin is "updated very late". — [same thread](https://us.forums.blizzard.com/en/wow/t/what-addon-do-you-wish-existed-but-nobody-seems-to-have-made-properly-yet/2337182)
- Chat translators are either rough (offline, word by word), blocked in instances, or require a companion app and may send text to the cloud. — [Chat-Translator](https://www.curseforge.com/wow/addons/chat-translator); [TranslatorZ](https://www.curseforge.com/wow/addons/translatorz); [BianLingo](https://www.curseforge.com/wow/addons/bianlingo-chat-translator)
- Accessibility addons exist but are niche and small; Accessibility TTS has about 254 downloads. — [CurseForge](https://www.curseforge.com/wow/addons/accessibilitytts)
- Guild finding is handled by external websites rather than in-game tools. The in-game finder shows 3 results per page with no content or schedule filters. — [Blizzard forums](https://us.forums.blizzard.com/en/wow/t/what-addon-do-you-wish-existed-but-nobody-seems-to-have-made-properly-yet/2337182); [guildsofwow.com](https://guildsofwow.com/looking-for-guild)
- Housing decor trackers exist ("Home Bound"), but nothing found addresses exact-quantity shopping or layout planning and sharing. — [Comicbook](https://comicbook.com/gaming/list/biggest-player-housing-changes-wow-needs-to-make-in-2026/); [Yahoo/PC Gamer](https://tech.yahoo.com/gaming/articles/world-warcrafts-adding-player-housing-161906705.html)
- Log analysis tools (Warcraft Logs, WoWAnalyzer) exist but overwhelm new users. — [exitlag](https://www.exitlag.com/blog/wow-classic-logs/); [Blizzard forums](https://us.forums.blizzard.com/en/wow/t/how-to-read-wow-logs-parses/841229?page=2) (older)

### Inferences
- **Failure modes, ranked:**
  1. API ceiling (Midnight secret values, chat hidden in instances, no Z coordinate).
  2. Abandonment and maintenance (Postal, the quest tracker skin).
  3. Usability and overwhelm (logs, ElvUI setup).
  4. Discoverability (accessibility addons with tiny install bases).
- Companion apps outside the game client (web, mobile, desktop overlay) avoid ceiling 1 for anything not needed live in combat. That favours ideas around onboarding, guild matchmaking, housing planning, alt planning and post-fight coaching.

### Gaps
- No download or usage numbers were gathered for most of the cited addons, except Accessibility TTS.
- Reviews of the new coach addons (TacticsCoach, Midnight Sensei) were not checked, so how well they work is unknown.
