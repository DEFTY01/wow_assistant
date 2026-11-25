# WoW Addon API Restrictions and Blizzard ToS Boundaries (state as of late November 2026)

Context on timeline (for dating every claim below): Midnight pre-patch 12.0.0 went live around mid/late January 2026 ([Blizzard Watch, 2026-01-13](https://blizzardwatch.com/2026/01/13/addon-apocalypse-midnight/)); 12.0.1 = launch roll-up ([wiki](https://warcraft.wiki.gg/wiki/Patch_12.0.1/API_changes)); 12.0.5 (spring 2026) and 12.0.7 followed; patch 12.1.0 "Curse of Ula'tek" launched 2026-08-11, Season 2 on 2026-08-18 ([Blizzard Watch, 2026-07-28](https://blizzardwatch.com/2026/07/28/wow-12-1-release-date/)). Wiki API-change pages already exist for 12.1.5 and 12.1.7 (12.1.7 listed with a 2026-12-01 date, i.e., PTR/upcoming at time of writing) ([12.1.5](https://warcraft.wiki.gg/wiki/Patch_12.1.5/API_changes), [12.1.7](https://warcraft.wiki.gg/wiki/Patch_12.1.7/API_changes)). A new product, "WoW Forever" (interface 16001 / patch 1.60.1, in beta late 2026), uses the modern (Midnight-style) API, not Classic's.

## Q1. What changed in the Midnight (12.0 and 12.x) addon API?

### Takeaway
Midnight introduced "Secret Values": during combat-restricted contexts (in combat, boss encounters, M+ keystone runs, PvP matches, and for unit identity anywhere in instances) addon code can *display* combat state (pass it to StatusBar:SetValue, Cooldown frames, etc.) but cannot compare, do arithmetic on, or branch on it; COMBAT_LOG_EVENT(_UNFILTERED) is gone for addons; addon comms are locked down during encounters/M+/PvP. Blizzard replaced the lost functionality with native systems (C_DamageMeter, C_EncounterTimeline/Boss Warnings, Cooldown Manager, Combat Audio Alerts, private auras). As of 12.1 (Aug 2026) the direction is still restrictive, not loosening; a new aura system is planned. Anything that makes *decisions* from combat data in-game is effectively dead; out-of-combat and non-combat (housing, collections, professions, AH, social, transmog, UI layout) remain wide open.

### Cited Findings
**Philosophy / official framing**
- Blizzard (Ion Hazzikostas): "Addons should no longer offer a competitive advantage in WoW combat"; combat state becomes a "black box" that addons can restyle ("addons can change the size or shape of the box, and they can paint it a different color") but not read; addons cannot know with certainty whether a target has a given debuff or the cooldown state of an ability. Alpha used the strictest ruleset, loosened later after developer feedback. — [Blizzard news: Combat Philosophy and Addon Disarmament in Midnight](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight)
- Native replacements named by Blizzard: Assisted Highlight and One-Button Rotation (11.1.7), Cooldown Manager (early in 11.1.5, refined in Midnight), Boss Warnings (upcoming mechanics), Combat Audio Alerts (TTS for health/combat events), built-in Damage Meters "with server-side validation", healer raid frame improvements. Class secondary resources (Runes, Holy Power, etc.) were made non-secret. — [Blizzard news](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight)
- Season 1 retrospective (2026-09-25): restriction remains in place, no relaxation mentioned; WeakAuras has no Midnight-compatible version and is unlikely to get one; devs credit record M+ participation partly to lower addon barrier; 12.1 designed around positioning/communication rather than third-party tools. — [Everything Edinburgh, 2026-09-25](https://everythingedinburgh.com/games/news/wow-midnight-season-one-developers-addons/)

**Secret Values mechanics**
- Tainted (addon) code may pass secrets to a limited set of native APIs (e.g., StatusBar:SetValue), may concatenate secret strings/numbers, but may not do arithmetic, comparisons, boolean tests, or use them as table keys. — [warcraft.wiki.gg Patch 12.0.0 API notes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes/notes); [Secret aspects](https://warcraft.wiki.gg/wiki/Secret_aspects)
- New Lua/API surface: `issecretvalue`, `issecrettable`, `hasanysecretvalues`, `scrubsecretvalues`, `secretwrap`, `canaccessvalue`, `dropsecretaccess`, `C_Secrets.*` (Should*BeSecret / Get*Secrecy for spells, auras, casts, cooldowns, power), frame methods `HasSecretValues`, `SetPreventSecretValues`; restriction state via `C_RestrictedActions.GetAddOnRestrictionState` / `IsAddOnRestrictionActive` and event `ADDON_RESTRICTION_STATE_CHANGED`. — [Patch 12.0.0/API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes)
- When secret (per 12.0.0 notes as revised Oct 11 2025 in beta): cooldowns and auras are secret only during a keystone run, PvP match, instance encounter, or while the player is in combat; outside those they are NOT secret. Unit identity (creature names, GUIDs, IDs) is secret while in an instance regardless of combat. Player's own spellcasts (incl. pet, channeled, empowered) are non-secret even in combat. Player's UnitHealthMax/UnitPowerMax non-secret. — [12.0.0 API notes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes/notes)
- Whitelisted non-secret: secondary resources (Combo Points, Runes, Soul Shards, Holy Power, Chi, Arcane Charges, Essence; primary resources remain secret), `UnitStagger` for player, `GetComboPoints`; per-spell "never secret" flags for profession and Dragonriding spells, some auras (Maelstrom Weapon, Ebon Might); `UnitIsUnit` non-secret for target/focus/mouseover/soft targets only. — [12.0.0 API notes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes/notes)
- New display-only helpers so addons can render secrets: `DurationObject`, `C_DurationUtil`, `Cooldown:SetCooldownFromDurationObject`, `C_CurveUtil` (CurveObject/ColorCurveObject), `CreateUnitHealPredictionCalculator`, new C_UnitAuras/C_Spell classifiers (`IsPriorityAura`, `IsSpellImportant`, `IsExternalDefensive`, `IsSpellCrowdControl`, `AuraIsBigDefensive`). — [Patch 12.0.0/API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes)
- 64 APIs deprecated in 12.0.0 (many GetAction* and CombatLog* families); 138 global APIs, 8 events and 153 CVars removed. — [Category:Deprecated API/12.0.0](https://warcraft.wiki.gg/wiki/Category:Deprecated_API/12.0.0); [Patch 12.0.0/API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes)

**Combat log in-addon**
- "Combat Log Events are no longer available to addons"; registering `COMBAT_LOG_EVENT` / `COMBAT_LOG_EVENT_UNFILTERED` errors; Combat Log chat-tab messages converted to KStrings so addons can't parse them; new `C_CombatLog.IsCombatLogRestricted` etc. — [12.0.0 API notes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes/notes); [12.0.0 API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes)

**Damage meters**
- New `C_DamageMeter` (IsDamageMeterAvailable, GetAvailableCombatSessions, GetCombatSessionFromID/Type, GetCombatSessionSourceFromID/Type, ResetAllCombatSessions; events DAMAGE_METER_*). — [12.0.0 API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes)
- All third-party meters (Details!, TomoDamageMeter, CZMeter, RocketMeter, Epic Damage Meter) now read Blizzard's C_DamageMeter data instead of parsing CLEU; one addon page notes meter values are hidden from addons during combat; Details! reads per-spell amountPerSecond from C_DamageMeter (third-party claim). Details! shipped 12.0.1 support April 2026. — [CurseForge Details file](https://www.curseforge.com/wow/addons/details/files/7895022); [Epic Damage Meter](https://www.curseforge.com/wow/addons/epic-damage-meter/files/8325659); [TomoDamageMeter](https://www.curseforge.com/wow/addons/tomodamagemeter) (aggregated via search; not individually fetched)
- Damage meter fields classFilename, specIconID, isLocalPlayer, classification made non-secret; name secret only for units whose identity is secret. — [12.0.0 API notes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes/notes)

**Boss mods / encounter timeline**
- New `C_EncounterTimeline` (GetEventList, GetEventInfo, GetEventState, track APIs, script-event add/cancel/pause, ENCOUNTER_TIMELINE_* events) plus `ENCOUNTER_WARNING`, `C_InstanceEncounter.IsEncounterInProgress`. — [12.0.0 API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes)
- Community summary: boss mods can only change how information is displayed, not show information the base game doesn't already convey; DBM (DBM-Core 12.1.11, 2026-09-25) and BigWigs (v426.1, 2026-09-28) list 12.1 interface and reportedly 12.1.5/12.1.7. Addons not flagged for 12.0.x+ won't load even with "Load out of date addons". — search aggregate incl. [Icy Veins 12.1 guide](https://www.icy-veins.com/wow/midnight-patch-12-1-guide), [Blizzard Watch](https://blizzardwatch.com/2026/01/13/addon-apocalypse-midnight/) (not individually fetched; treat versions as indicative)
- Ion Hazzikostas interview (per wiki notes): open to an audio countdown, but it would have to be in base UI, not an addon. — [12.0.0 API notes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes/notes)

**12.0.5 tightening (spring 2026)**
- Blizzard: "relying on Secret Values alone was not going to be enough" against aura automation; most encounter debuffs turned into private auras; a new aura system planned that "definitely will NOT be in 12.0.5 or 12.0.7". Aura instance IDs re-randomize on entering encounter/M+/PvP; stat APIs return secrets when auras secret; `UnitTokenFromGUID` stops returning boss/nameplate/raid tokens when identities secret; unit identity secret on instanced maps for anyone except player/pet/vehicle/group members; secret instant casts no longer fire UNIT_SPELLCAST_SUCCEEDED for non-player units; `GetNearestPartyMemberToken` blocked. Loosened: private aura anchors, aura booleans (isHelpful/isHarmful/isRaid...) non-secret, party-leader actions restricted only during chat lockdown, throttles waived during PLAYER_LOGOUT. — [Patch 12.0.5 API notes](https://warcraft.wiki.gg/wiki/Patch_12.0.5/API_changes/notes)

**12.1.0 (live 2026-08-11)**
- New AuraContainer/AuraButton intrinsic frames and APIs to display filtered aura sets without exposing underlying data; group-buff alert APIs; `C_CooldownViewer.GetGroupBuffItems`; Animation/ScriptRegion SetScript/HookScript secret-argument handling tightened (AllowedWhenUntainted -> NotAllowed); `CanAccessObject` replaced by `CanBeAccessedInContext`; large new `C_Discord` namespace + `discordInfo` on CHAT_MSG_* events; getglobal/setglobal deprecated; new UI texture filenames no longer published to ManifestInterfaceData. No loosening found. — [Patch 12.1.0/API changes](https://warcraft.wiki.gg/wiki/Patch_12.1.0/API_changes)

### Inferences
- Feasible in-addon on retail: UI/visual reskins of Blizzard-provided data (meters, cooldown manager, timeline, auras via AuraContainer), anything out-of-combat/out-of-instance (gear, talents/loadouts, collections, housing (C_Housing* is new and large), professions/crafting orders, AH, guild/social, routing/quests, transmog outfits), post-combat summaries using C_DamageMeter session data once combat ends.
- Not feasible: rotation helpers, proc/debuff-driven custom alerts in encounters/M+/PvP, custom boss timers driven by combat events, real-time interrupt/CD tracking of other players via comms during encounters, WeakAuras-style logic.
- The C_Discord namespace in 12.1 is a notable new surface (may matter for social/companion ideas) — details not researched.

### Gaps
- Exact live list of which C_DamageMeter fields are readable mid-combat vs. post-combat in 12.1.x not confirmed from a primary source.
- 12.1.5/12.1.7 API pages not read in full; the announced "new aura system" status unknown.
- No primary source found on Hekili's Midnight status (likely non-functional given secrets, unverified) or GSE's current status.

## Q2. Does WoWCombatLog.txt (/combatlog advanced logging) still work in Midnight; can local tools parse it?

### Takeaway
Yes. The client-written log file was deliberately left untouched by Secret Values (Hazzikostas said advanced logging/export "remain completely unchanged"), Warcraft Logs and similar parsers still work. But since 2023 Blizzard has intentionally changed how the advanced log is populated to defeat *real-time* external overlays, so a local app should treat the file as post-hoc/near-time data, not a live feed, and real-time overlay use is explicitly in Blizzard's crosshairs.

### Cited Findings
- Hazzikostas reportedly confirmed Warcraft Logs and similar services won't be affected; "the advanced combat log and exporting for parsing is going to remain completely unchanged." — [Boosting Ground](https://boosting-ground.com/wow-boosting/news/midnight-addon-ban) (secondary source quoting Blizzard; primary interview not located)
- WowCoach (published 2026-02-24, updated 2026-10-07): advanced combat logging still works in Midnight; enable in System > Network or `/console advancedCombatLogging 1`; must type `/combatlog` each login/reload; file `World of Warcraft\_retail_\Logs\WoWCombatLog.txt` (`_classic_` / `_classic_era_` for Classic); no rotation, single file appended until deleted; Secret Values did not affect the log because the game writes it; known Midnight bug: some healing events under-reported (Mistweaver, Holy Paladin), unacknowledged by Blizzard as of April 2026. — [WowCoach](https://wowcoach.gg/blog/how-to-enable-combat-logging-wow)
- Logging is disabled on logout, disconnect, and exit; Warcraft Logs Uploader reads the file to build reports. — [Warcraft Logs help](https://warcraftlogs.com/help/start)
- (Older, Aug 21 2023, Dragonflight) Blizzard blue post: "3rd-party programs using the game's combat logs to draw overlays during raid fights" — "We intend to make changes to how the Advanced Combat Log is populated" — and referred to EULA section 1-C. Technical specifics not published; community speculated batching/delay. — [MMO-Champion](https://www.mmo-champion.com/content/11654-Advanced-Combat-Log-Changes-Coming-to-Prevent-Overlays)
- In-game, CombatAnalytics notes Midnight significantly restricted CLEU, so in-addon real-time analysis is gone (only file-based remains). — [CurseForge CombatAnalytics](https://www.curseforge.com/wow/addons/combatanalytics)

### Inferences
- A local companion that tails WoWCombatLog.txt for post-pull / post-key analysis, coaching, auto-upload, wipe review, etc. is technically feasible and ToS-consistent (same model as Warcraft Logs uploader, which Blizzard explicitly tolerates).
- Using the log to drive live in-combat overlays/alerts re-creates what Midnight removed and what Blizzard acted against in 2023 — high ToS risk and possibly technically defeated by write delay.
- An addon cannot enable logging during combat-relevant automation beyond toggling (LoggingCombat); "auto combat logger" addons still exist (AutoCombatLogger updated to 12.0.2 per WowCoach).

### Gaps
- Current exact write latency/buffering of the advanced combat log in 12.x not documented anywhere found.
- Whether any 12.x log format changes (new fields, removed private-aura info) occurred: not found.

## Q3. Classic (Era, Anniversary/Fresh, MoP/Cata Classic) differences

### Takeaway
As of 12.0.5-era notes (2026-04-17), Blizzard stated the Secret Values system is "entirely disabled on Classic builds" and combat log events "will work just like they do currently in Classic" — so Classic Era / Anniversary / MoP Classic addons retain CLEU, readable auras/cooldowns, and classic combat addons (WeakAuras-type logic, boss mods, CLEU meters). The new "WoW Forever" product is the exception: it uses the modern API with Midnight-style combat restrictions.

### Cited Findings
- "The secret value system is entirely disabled on Classic builds"; APIs returning secrets on Mainline return plain values on Classic; Classic combat log events keep working as before (2026-04-17). — [Patch 12.0.5 API notes](https://warcraft.wiki.gg/wiki/Patch_12.0.5/API_changes/notes)
- The secret-value functions (e.g., `dropsecretaccess`) exist in MoP Classic 5.5.4, BC Classic, and Classic Era 1.15.9 builds (shared codebase) without implying enforcement. — [API dropsecretaccess](https://warcraft.wiki.gg/wiki/API:dropsecretaccess)
- Classic branches historically diverge from retail restrictions (e.g., distance-check API change not picked up for Wrath/Cata Classic/Era). — [Wowhead](https://www.wowhead.com/wotlk/it/news/distance-check-api-change-potentially-coming-next-year-wow-classic-336250)
- Addon messaging differences: Classic allows SAY/YELL addon messages (heavily throttled), disallows CHANNEL; Classic 1.13.4 added severe comms rate throttling; Classic 4.4.0 adopted per-prefix throttle and result codes. — [API C_ChatInfo.SendAddonMessage](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage)
- WoW Forever (interface 16001, patch 1.60.1, beta late 2026): uses the modern API "including restrictions intended to prevent addons from performing complex combat calculations"; Classic Era addons don't transfer automatically; trial accounts can't send addon messages. — [Patch 1.60.1/API changes/notes](https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes/notes); third-party guides e.g. [gamertagmythras](https://gamertagmythras.com/blog/world-of-warcraft/wow-forever-addons-guide) (guide sites contradict each other in places)

### Inferences
- Combat-logic addon ideas (custom alerts, rotation displays, CLEU-based meters/analytics, live comms-based raid tools) remain technically feasible only on Classic flavors; market there is smaller but uncontested by native replacements.
- ToS rules (UI Add-On Policy, EULA) are identical across flavors.

### Gaps
- No confirmation whether Blizzard plans to bring secrets to MoP Classic / future Classic progression; Anniversary/Fresh realm specifics not separately verified.
- WoW Forever's product nature/launch date not verified from a Blizzard primary source.

## Q4. General addon sandbox limits (network, file I/O, protected actions, comms throttling, screenshots)

### Takeaway
Addons are Lua in a Blizzard sandbox: no network sockets, no arbitrary file I/O; the only persistent output is SavedVariables (flushed to disk on logout/`/reload`/exit), plus screenshots and the combat log file which the client itself writes. Protected functions (casting, targeting, movement) require hardware events and are blocked/limited in combat lockdown. Addon-to-addon comms (C_ChatInfo.SendAddonMessage) are throttled per prefix (10 burst, +1/s) and in Midnight return `AddOnMessageLockdown` during encounters/M+/PvP; trial/veteran accounts lose addon messaging in 12.1.7.

### Cited Findings
- SendAddonMessage: prefix <=16 chars, message <=255 chars, no NUL; retail chat types PARTY/RAID/INSTANCE_CHAT/GUILD/OFFICER/WHISPER/CHANNEL; per-prefix allowance 10 messages regenerating 1/s, failing with `AddonMessageThrottle` (not applied to whispers outside instances); server may change values anytime; Blizzard recommends ChatThrottleLib/AceComm; result codes 11 `AddOnMessageLockdown` and 12 `TargetOffline` added in 12.0.0; "Trial accounts (including Veteran) can no longer send addon messages" (12.1.7). — [API C_ChatInfo.SendAddonMessage](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage)
- Midnight chat lockdown: in beta (Oct 2025) addons in instances "are not allowed to send communications to other players (either through addon comms or regular chat)"; narrowed Oct 11 2025 to only while a keystone run, PvP match, or instance encounter is in progress; Blizzard said it would lock down addon-comm workarounds "very soon" (Dec 2025); `C_ChatInfo.InChatMessagingLockdown` and test CVar `addonChatRestrictionsForced`. Chat received in lockdown arrives as secrets. — [12.0.0 API notes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes/notes); [Icy Veins: Combat Addon Restrictions Eased](https://www.icy-veins.com/wow/news/combat-addon-restrictions-eased-in-midnight/)
- 12.0.5: chat channel APIs unusable during chat lockdown or from macros; party actions (ready check, countdown, ping, loot method) restricted during chat messaging lockdown. — [12.0.5 API notes](https://warcraft.wiki.gg/wiki/Patch_12.0.5/API_changes/notes)
- Battle.net bridge APIs exist: `C_BattleNet.SendGameData`, `SendWhisper` / `BNSendGameData`. — [12.0.0 API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes)
- New `C_RestrictedActions.CheckAllowProtectedFunctions` / `ADDON_RESTRICTION_STATE_CHANGED` formalize when protected calls are allowed. — [12.0.0 API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes)
- Addon throttles do not apply during PLAYER_LOGOUT / ADDONS_UNLOADING (12.0.5) — relevant to last-moment SavedVariables prep. — [12.0.5 API notes](https://warcraft.wiki.gg/wiki/Patch_12.0.5/API_changes/notes)

### Inferences
- Addon -> local app data path: SavedVariables (`WTF\Account\<ACCOUNT>\SavedVariables\<Addon>.lua`, and per-character variants) only refresh on reload/logout, so any "live" sync requires the user to `/reload`. The other client-written channels are the combat log file and screenshots (`Screenshots` folder), both read-only to the addon side.
- App -> addon data path: only by writing files the addon loads at startup (e.g., the app rewrites a SavedVariables or data .lua while the game is closed or before reload), as data addons like RaiderIO/TSM-style companion apps do. Game overwrites SavedVariables on logout, so the app must write only while the client is closed or into a separate data-addon file.
- Group coordination tools that rely on comms must do their syncing before pull / between keys.

### Gaps
- SavedVariables flush behavior and screenshot folder were not re-verified from a fetched primary page in this session (well-established long-standing behavior; see [warcraft.wiki.gg SavedVariables](https://warcraft.wiki.gg/wiki/SavedVariables)).
- No primary source found on the "hardware event" requirement changes in 12.x; long-standing rule is that protected actions require a hardware event and cannot be called by insecure code in combat.

## Q5. Blizzard policy on companion apps, overlays, and what leads to bans

### Takeaway
Addons are governed by the UI Add-On Development Policy (free, unobfuscated, no ads, no in-game donation asks, no server/player harm, Blizzard may disable any functionality). External software is governed by EULA Part 1 Section C (no unauthorized software used "in connection with the Platform", no client modification/reverse engineering). Blizzard tolerates passive file-reading companions (Warcraft Logs uploader, RaiderIO/TSM-style apps) but has explicitly targeted combat-log-driven real-time overlays (2023) and bans for automation; pixel/screen-reading rotation bots are sold openly but users report bans. Screen-capture/OCR overlays and voice assistants that only display info are a gray area with no explicit approval.

### Cited Findings
- UI Add-On Development Policy (released 2009-03-20, enforced 2009-05-19; thread still active Nov 2026): (1) free of charge — no paid versions, paywalled access, or paid services; (2) code visible, not obfuscated; (3) no noticeable server/game degradation (excessive chat, disk reads, low FPS); (4) no advertising; (5) donation requests only on website/distribution site, not in-game; (6) ESRB "T" content; (7) must follow ToU/EULA; (8) Blizzard may disable any add-on functionality at its sole discretion; violations can lead to legal action. Contact: WoWUI@blizzard.com. — [Blizzard forums: UI Add-On Development Policy](https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534)
- Enforcement of "free" is loose in US/EU; WoW China cracked down treating any donation-gated access as a paid service; Mythic Dungeon Tools paywalled-data controversy is an example of the gray zone. — [Icy Veins: WoW China Cracks Down](https://www.icy-veins.com/wow/news/wow-china-cracks-down-on-paid-addons-and-paywalled-profiles/); [Wowhead: MDT paywalled data](https://www.wowhead.com/news=320230/mythic-dungeon-tools-paywalled-dungeon-data-available-to-subscribers-only)
- Blizzard (Kaivax, 2025-08-05): "The use of third-party software that modifies the World of Warcraft game client is against our Terms of Service"; targets software that "reverse-engineer[s] and bypass[es] our security protocols to modify the game client and/or control the game in ways that are prohibited"; penalties up to permanent account closure; cites EULA 1-C ("any code and/or software, not expressly authorized by Blizzard, that can be used in connection with the Platform"). No mention of overlays. — [Blizzard forums: Prohibitions on Third-party Software](https://us.forums.blizzard.com/en/wow/t/2142972/1)
- (2023) Blizzard acted against external combat-log overlays drawing raid-mechanic graphics, citing EULA 1-C. — [MMO-Champion](https://www.mmo-champion.com/content/11654-Advanced-Combat-Log-Changes-Coming-to-Prevent-Overlays); [PC Gamer](https://pcgamer.com/wows-ui-arms-race-rages-on-as-blizzard-says-theyll-crack-down-on-sparkly-new-combat-overlays)
- Overwolf-style overlays: no official Blizzard statement found; community argues they're like the Steam overlay and low-risk if they neither modify game data nor give an advantage, but technically not "allowed". — [Blizzard D4 forum thread](https://us.forums.blizzard.com/en/d4/t/third-party-app-diablo-iv-overlay-is-permitted-modcheck/41715)
- Pixel-reading rotation bots (read an addon's on-screen colored pixels, e.g., Hekili output, and press keys): sold openly (PixelRotation claims "0 bans"); user reports a ban in a July 2025 wave for "Exploitative Activity: Unauthorized Cheat Programs (Hacks)" while using a Hekili pixel bot; bot vendors themselves warn of behavioral detection. — [elitepvpers ban report](https://www.elitepvpers.com/forum/wow-bots/5311744-banned-using-my-own-private-rotation-bot.html); [PixelRotation](https://www.wowpixelrotation.com/); [PixelBuddy](https://pixelwowbot.com/product/pixelbuddy/)
- Midnight design intent is that addons not be decision-makers; Blizzard says it is willing to build features (e.g., audio countdowns) only in base UI. — [Blizzard news](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight); [12.0.0 notes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes/notes)

### Inferences (risk tiers for companion ideas)
- Low risk: reading SavedVariables/WTF files, post-session combat log parsing, writing data addons' .lua files while the game is closed, out-of-game web/desktop dashboards, Battle.net API use. Precedents: Warcraft Logs uploader, RaiderIO client, TSM app, WowUp/CurseForge managers.
- Medium/gray: screen-capture or OCR overlays that only display out-of-combat info; voice assistants answering questions (no input injection); Overwolf-style always-on-top overlays. Risk rises sharply if they read combat state in real time (re-creating Midnight-removed capabilities) — Blizzard's 2023 overlay action is the direct precedent.
- High risk / bannable: any input automation (key sending based on screen/pixels/log), memory reading, DLL injection, client modification, OCR "pixel bots", live combat-log overlays telling players where to stand; paid/paywalled addons (policy violation) and obfuscated addon code.
- Monetization: the companion app itself (external, not an addon) can be paid/subscription (precedent: RaiderIO, TSM premium, Warcraft Logs premium), but the in-game addon part must remain free and unobfuscated, with no in-game ads/donation prompts.

### Gaps
- No official Blizzard statement found specifically on Overwolf, OCR overlays, or voice assistants for WoW.
- No verified 2026 ban wave specifically targeting pixel bots; GSE/Hekili controversy specifics not sourced in this session.

## Q6. Official data export methods (Battle.net API etc.)

### Takeaway
There is no in-game `/exportdata` command found; official external data is the Battle.net (Blizzard) Developer API: Game Data APIs (client credentials) and Profile APIs (OAuth authorization-code flow with `wow.profile` scope), free with a developer account, commonly cited limits 36,000 requests/hour and 100 requests/second per client. In-game export otherwise relies on addons producing copy-paste strings (e.g., SimulationCraft-style) or SavedVariables.

### Cited Findings
- Rate limits: 36,000 requests per hour at up to 100 requests per second per API client; developers report 429s on exceeding the hourly cap (and some below it). — [Blizzard forums: API Access - Clients - Rate Limits](https://us.forums.blizzard.com/en/blizzard/t/api-access-clients-rate-limits/5602); [WoW API Limits and 429 errors](https://us.forums.blizzard.com/en/blizzard/t/wow-api-limits-and-429-errors/18526)
- Profile endpoints require an OAuth 2.0 Authorization Code Flow token with `wow.profile` scope; Game Data uses client credentials. — [publicapis.dev Battle.net summary](https://publicapis.dev/resource/battle-net/mfqhkelj) (secondary; primary portal docs at develop.battle.net not fetched)

### Inferences
- A local app can combine Battle.net Profile API (character gear, M+ ratings, achievements, collections, with user consent) + SavedVariables + combat log for a rich companion without touching the client. Data freshness of Profile API is typically on logout/periodic, not live.

### Gaps
- Official developer-portal docs (current limits, any 2026 changes, any fees) not fetched; no evidence of a paid tier — "free" is long-standing but unverified for 2026.
- No evidence found of an official in-game /exportdata command; not confirmed either way.
