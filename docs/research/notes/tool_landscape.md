# WoW External/Companion Tool Landscape and Gaps (as of Nov 2026)

Scope: what exists and what doesn't, as a reference for checking whether new addon and local companion-app ideas are original. Research was done on 2026-11-25. Several vendor pages (archon.gg articles, icy-veins news, theresanaiforthat) returned HTTP 403, so some details come only from search-result snippets. Those are marked.

**Context for everything below: the Midnight (12.0) "Addon Disarmament".** The rules for addons changed in Midnight. COMBAT_LOG_EVENT and COMBAT_LOG_EVENT_UNFILTERED now throw an error when an addon registers them. Combat data is delivered as "Secret Values", which addons can display but cannot compare or do arithmetic on. Inside instances, chat reaches Lua as secret values and addons cannot send communications to other players ([warcraft.wiki.gg Patch 12.0.0 API notes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes/notes), via search snippet). Blizzard has also built in its own versions of several tool types: Assisted Highlight / One-Button Rotation, Cooldown Manager, Boss Warnings, Combat Audio Alerts (TTS), better raid frames and a built-in Damage Meter with server-side validation ([Blizzard: Combat Philosophy and Addon Disarmament in Midnight](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight)). Third-party meters now read Blizzard's `C_DamageMeter` API. Recount Revived's bars stayed empty because of secret values until a later fix ([Recount Revived](https://www.curseforge.com/wow/addons/recount-revived/files/8225229); [TomoDamageMeter](https://www.curseforge.com/wow/addons/tomodamagemeter)). Blizzard has since relaxed some limits ([Icy Veins: Blizzard Relaxing More Addon Limitations](https://www.icy-veins.com/wow/news/blizzard-relaxing-more-addon-limitations-in-midnight/), page itself returned 403 so specifics are unverified). **The consequence that matters most here:** in-game analysis of the combat log is now largely blocked, so serious analysis has moved out of the client to tools that read WoWCombatLog.txt, which is still written to disk (Warcraft Logs, wow.gg and Archon App all still ingest it).

---

## 1. Log/performance analysis: what exists, and what analysis is missing?

### Takeaway
Archon (Warcraft Logs' parent brand) has consolidated the field. It now owns or hosts Warcraft Logs, WoWAnalyzer, Wipefest and Warcraft Recorder, and released the Archon App (recording plus post-pull analysis) in March 2026. Raidbots/SimC work for Midnight. On AI, wow.gg ships a premium "AI assistant" and "log coach", WowCoach.gg is in alpha with "AI wipe analysis", and ParsePal exists, but there is no established, well-known natural-language coach. No verified tool does **local-only, longitudinal (many-weeks) personal coaching with natural-language explanations**.

### Cited Findings
**Warcraft Logs / Archon**
- Warcraft Logs runs under the Archon brand (archon.gg), which covers WoW Retail, several Classic variants, FFXIV, ESO, SWTOR and others — [WowCarry guide](https://wowcarry.com/blog/wow/warcraft-logs-feature-release-popularitybased-tier-lists-and-character-builds-by-archon) (third-party, inconsistent dates); [archon.gg/wow](https://archon.gg/wow)
- Archon also publishes popularity-based tier lists and builds generated from logs — [Wowhead](https://pt.wowhead.com/pt/news/archon-feature-launch-popularity-based-tier-lists-and-character-builds-by-336729)
- **Archon App:** open beta in Feb 2026, full release announced 10 March 2026, includes video recording. July 2026 release notes mention improved "post-pull analysis" in the app — [Introducing Archon App](https://www.archon.gg/wow/articles/news/introducing-archon-app) (403 on fetch, from search snippet); [Archon July release notes](https://www.archon.gg/wow/articles/news/archon-july-release-notes)
- No evidence found of an LLM / natural-language feature in Warcraft Logs or Archon as of these sources (search for "Archon AI analysis 2026" turned up none) — [search results incl. archon.gg FAQ](https://www.archon.gg/wow/articles/help/archon-disclaimers-and-faq)
- WCL subscription tiers are Silver, Gold and Platinum. API limits: 3,600 points/hr free, 9,000 Gold, 18,000 Platinum. Platinum adds guild banners and shared guild log access. **I could not confirm 2026 prices** — [WCL subscriber benefits](https://articles.warcraftlogs.com/help/subscriber-benefits); [archon.gg subscriber benefits](https://www.archon.gg/wow/articles/help/subscriber-benefits); [banner/storage subscription changes](https://www.archon.gg/wow/articles/news/new-banner-feature-and-storage-subscription-changes) (implies storage-related changes to paid tiers)
- WoWAnalyzer was acquired by Warcraft Logs — [Wowhead](https://www.wowhead.com/news/wowanalyzer-acquired-by-warcraft-logs-324677). Icy Veins still lists it (maintained by Vohrr and Trevor) and QELive (by Voulk) as the descriptive post-fight analysis healers rely on in Midnight — [Icy Veins Mistweaver resources](https://www.icy-veins.com/wow/mistweaver-monk-resources)
- **Wipefest** is now presented on archon.gg. In March 2026 it added Voidspire and Dreamrift raid coverage: mechanical analysis, player scores, event timelines, guides and multi-pull analysis, to "narrow down your specific problem areas" — [Wipefest: Voidspire and Dreamrift](https://www.archon.gg/wow/articles/news/wipefest-voidspire-and-dreamrift)
- WoWAnalyzer's GitHub has a CombatLogParser repo meant for a future WoWAnalyzer **Electron (desktop) app** with a custom parser, i.e. an intended local client — [GitHub WoWAnalyzer/CombatLogParser](https://github.com/WoWAnalyzer/CombatLogParser)
- **Localog** is a companion addon for a *local-only fork of WoWAnalyzer* that analyses logs without Warcraft Logs, but it is not LLM-based — [CurseForge Localog](https://www.curseforge.com/wow/addons/localog)

**Raidbots / SimulationCraft**
- Raidbots/SimC had only partial support for the Midnight pre-patch (27 Jan 2026). Droptimizer was ready at Midnight launch in March — [Raidbots support](https://support.raidbots.com/article/71-midnight-prepatch-support)
- Icy Veins' Midnight 12.0.1 guides treat Raidbots as the standard sim tool, though some sim types are not supported for Vengeance DH — [Icy Veins VDH sims](https://www.icy-veins.com/wow/vengeance-demon-hunter-pve-tank-simulations)
- Players worry that SimC's in-game export addon could be the next thing restricted. This is a user thread, not official — [Blizzard forum "Simcraft will be next"](https://us.forums.blizzard.com/en/wow/t/simcraft-will-be-next/2177451)

**Newer log/AI analysis services**
- **wow.gg Logs Analyser:** independent fan project. Accepts Retail WoWCombatLog.txt (.txt/.log/.gz) uploads or Warcraft Logs imports, and requires Advanced Combat Logging. A Compare tab sets your casts, opener and CD cadence against top logs of the same spec and boss. Metrics include avoidable damage, kick/CC split, "death saveability" and "saves from allies". Premium (price not shown) raises limits on SimCraft, the **"log coach" and "AI assistant"**. No Classic support. Server-side (cloud) — [wow.gg/logsanalyzer](https://wow.gg/logsanalyzer); [wow.gg subscription](https://wow.gg/guides/wow-gg-subscription)
- **WowCoach.gg:** a WowCoach account recruited alpha testers on Icy Veins for an "advanced combat log analysis tool" with "full AI wipe analysis" that traces the chain of events behind a wipe and compares it with strategies, offering free access for log uploads. Still alpha/outreach, maturity unknown — [Icy Veins forum](https://www.icy-veins.com/forums/topic/85469-looking-for-alpha-testers-advanced-combat-log-analysis-tool/)
- **ParsePal:** listed as an "AI rotation coaching tool". The page returned 403 and details are unverified — [theresanaiforthat ParsePal](https://theresanaiforthat.com/ai/parsepal/)
- A search summary said "WowCoach.gg (Coach Clutch) and AskLogs" let players query logs in plain English. **I could not verify that AskLogs exists.** Treat it as unconfirmed — (search-engine synthesis, no primary page)

**In-game coaching addons that survive Midnight rules**
- **Midnight Sensei** (MidnightTim): grades each fight A+ to F and tracks cooldown usage, rotation habits and wasted resources, with a HUD, social leaderboard, "Boss Board" and export. Enemy-debuff scoring was blocked in 12.0, and since v1.5.5 self-buff uptime comes from cast events instead of aura scanning. About 10.3K downloads, v1.7.10 updated 4 Nov 2026 for 12.1.7 — [CurseForge Midnight Sensei](https://www.curseforge.com/wow/addons/midnight-sensei)
- Other coaching or analysis addons found but not examined in detail: TacticsCoach (does not read the combat log), Project: Combatant (PvP stats, obeys Midnight rules), CombatAnalytics, CombatAnalyzer, ArenaCoach (linked to arenacoach.gg) — [TacticsCoach](https://www.curseforge.com/wow/addons/tacticscoach); [Project Combatant](https://www.curseforge.com/wow/addons/project-combatant); [CombatAnalytics](https://www.curseforge.com/wow/addons/combatanalytics); [ArenaCoach](https://www.curseforge.com/wow/addons/arenacoach/install)

**Raider.IO**
- The Raider.IO Desktop Client is still active. It auto-updates the addon's database and holds the live-tracking setting. Since client 4.1.0 it no longer supports Windows 7 or older, or macOS 13 or older — [Raider.IO support KB](https://support.raider.io/kb/raider-dot-io-mythic-plus-addon); [client for old OS](https://support.raider.io/kb/raider-dot-io-mythic-plus-addon/client-for-old-operating-systems); [Raider.IO privacy policy, rev. 1 Jul 2025](https://raider.io/privacy-policy)

### Inferences
- Missing, or not verified to exist:
  - (a) **Longitudinal personal coaching:** tracking one player's habits across weeks of logs and explaining trends in plain language. Every tool found works per report or per pull, or compares against top parses.
  - (b) **Fully local / offline LLM explanation of WoWCombatLog.txt.** Everything with "AI" in it (wow.gg, WowCoach) is cloud and freemium.
  - (c) **Natural-language Q&A over your own logs** exists only in early or premium form (wow.gg AI assistant, WowCoach alpha), so differentiation is still possible but the space is not empty.
  - (d) Video and log sync exists through Archon App and Warcraft Recorder (see section 4), but AI auto-commentary on clips does not appear to.
- Midnight's restrictions push analysis out of the client. That favors companion apps that read the log file or SavedVariables, and caps how much an in-game addon can do (Midnight Sensei shows what workarounds are still possible).
- Archon's consolidation (WCL + WoWAnalyzer + Wipefest + Recorder + App) makes it the main incumbent and the most likely to add LLM features. Any "AI log coach" idea should be differentiated on local/privacy, longitudinal tracking, or a specific niche (healers, M+ routes, alts).

### Gaps
- Current prices for WCL Gold/Platinum, Archon App Pro and Wipefest premium could not be confirmed (pages returned 403).
- Details! under Midnight: I found only a build listing for 12.0.1 (April 2026) and no description of how it handles secret values — [Details file listing](https://www.curseforge.com/wow/addons/details/files/7895022).
- "Mythic Stats" was not researched (no time budget left). Its status is unknown.
- I did not find substantial user-complaint threads (Reddit) about WCL/Archon in 2026.

---

## 2. Addon managers & companion apps: gaps?

### Takeaway
Addon managers are split by API access. The CurseForge app (Overwolf) is standalone and has the largest catalogue. WowUp lost CurseForge access and now covers Wago, WoWInterface and GitHub. The Wago App handles WeakAuras and Wago-hosted addons. No 2026-specific comparison discussion surfaced. Status of the TSM Desktop App, the Battle.net companion features and the WoW Armory/Companion mobile app could not be verified this session.

### Cited Findings
- WowUp split into per-provider builds after Overwolf denied it CurseForge API access. The non-CF build supports Wago, WoWInterface, GitHub and others, and downloading from Wago through WowUp requires enabling ads — [Wowhead: WowUp/Overwolf split](https://fr.wowhead.com/news/ads-revenue-and-api-wowup-and-overwolf-split-over-addon-development-325912); [Wowhead: WowUp CF build](https://www.wowhead.com/news=329736/wowup-launches-new-addon-manager-supporting-curseforge-downloads); [Warcraft Tavern guide](https://warcrafttavern.com/wow/guides/how-to-install-and-manage-addons)
- The standalone CurseForge app no longer requires Overwolf, per a forum user. There have been earlier complaints about the redesigned app ("The New CurseForge App is Bad") — [Blizzard forum: alternatives to CurseForge](https://us.forums.blizzard.com/en/wow/t/alternatives-to-curseforge-other-addon-download-sites/1243796); [Blizzard forum: New CurseForge App is Bad](https://us.forums.blizzard.com/en/wow/t/the-new-curseforge-app-is-bad/1350270?page=3)
- The Wago App updates individual WeakAuras and Wago-hosted addons, and its CurseForge support has been spotty because of CF API restrictions — [Warcraft Tavern](https://warcrafttavern.com/wow/guides/how-to-install-and-manage-addons)
- Comparison overview: [PC Gamer best WoW addon managers](https://www.pcgamer.com/best-wow-addon-client-manager)
- A third-party CLI/manager gist exists (instawow by layday) — [gist](https://gist.github.com/layday/0275de150a2d94191d0be61a474cc88a)
- On the CurseForge ideas board, users requested keyboard navigation for blind and low-vision players *in the CurseForge app itself* — [CurseForge ideas CF-I-2498](https://curseforge-ideas.overwolf.com/ideas/CF-I-2498)

### Inferences
- Addon managers only install and update. None of those found **understand what addons do**: no "my UI broke after patch, which addon?" diagnosis, no conflict/taint analysis, no explanation of SavedVariables, no profile backup or diff across machines with AI help. A local "addon doctor" companion looks unoccupied, but verify against CurseForge app features before claiming that.
- The Midnight API change probably broke many addons. A tool that flags which installed addons are dead or obsolete under 12.x would meet a real need (inference, no source on demand).

### Gaps
- TSM Desktop App: current status (AuctionDB sync, any changes in 2026) not verified.
- Blizzard WoW Companion app / Armory mobile: I believe the WoW Companion app was retired years ago, but this was **not verified this session**. Do not cite it without checking.
- Overwolf WoW-specific apps (overlays, Raider.IO-style) were not catalogued.
- No 2026 Reddit comparison found. The forum sources are dated (2021–2024).

---

## 3. AI / LLM tools for WoW that already exist

### Takeaway
There are a handful of small hobby projects and early-stage services. Local or offline LLM use with WoW data exists only in AzerothLM (TBC Classic, Ollama optional, 3 GitHub stars). Prompt-builder addons (WoW AI Prompter) export context to external chatbots. Cloud AI coaches are wow.gg premium, WowCoach.gg (alpha) and ParsePal. **No retail Midnight local-LLM companion that reads combat logs or SavedVariables was found.** The closest analogue, a local llama.cpp combat-log coach (DPSCoach), is for a different game (Throne & Liberty).

### Cited Findings
- **AzerothLM** (MIT, GitHub chefm4tt): an in-game addon writes gear, professions, quests, reputations, talents, zone and gold to SavedVariables. A Python relay sends this to an LLM, either cloud (Gemini, OpenAI, Anthropic via LiteLLM) or **local Ollama**, and the answer returns after `/reload`. Targets TBC Classic / Anniversary (Interface 20505). Public beta v0.1-beta.1, 3 stars. Limitations: manual `/reload` sync, needs Python — [GitHub AzerothLM](https://github.com/chefm4tt/AzerothLM)
- A related project, azeroth-companion (nardo86), is indexed but was not examined — [ecosyste.ms](https://awesome.ecosyste.ms/projects/github.com%2Fnardo86%2Fazeroth-companion)
- **WoW AI Prompter** (eggntoast): a TBC Classic addon that formats character and encounter context into a prompt you paste into ChatGPT, Claude or Gemini. It contacts no AI service. 264 downloads, updated 16 Jul 2026 — [CurseForge](https://www.curseforge.com/wow/addons/wow-ai-prompter)
- **WoWGPT** addon exists on CurseForge (not examined) — [CurseForge wowgpt](https://www.curseforge.com/wow/addons/wowgpt)
- **wow.gg** premium includes an "AI assistant" and "log coach" (cloud) — [wow.gg/logsanalyzer](https://wow.gg/logsanalyzer)
- **WowCoach.gg:** "AI wipe analysis" in alpha — [Icy Veins forum](https://www.icy-veins.com/forums/topic/85469-looking-for-alpha-testers-advanced-combat-log-analysis-tool/)
- **DPSCoach** (Throne & Liberty, not WoW): an MCP server and local coach that is "deterministic SQL-first ... powered by llama-cpp" over parsed combat logs, using intent routing to SQL. This proves the pattern works in another MMO — [Glama DPSCoach](https://glama.ai/mcp/servers/@stalcup-dev/tl-dps-mcp/tree/d95b2f0eb4ad1fb391fb0bce107e133006465d0f); [coach_local.py](https://glama.ai/mcp/servers/@stalcup-dev/tl-dps-mcp/blob/d95b2f0eb4ad1fb391fb0bce107e133006465d0f/app/coach_local.py)
- PC Games (DE) tested whether ChatGPT can make a WoW player better, an example of the general ChatGPT-as-guide use — [PCGames.de](https://www.pcgames.de/World-of-Warcraft-Spiel-42971/Specials/KI-ChatGPT-1553120/)
- **Non-LLM parsers** that could serve as building blocks: WoWP (Rust, retail log to JSON); taptologs (WotLK 3.3.5, in-browser with local DuckDB, no API); frostparse (Go, 3.3.5a); summarize_consumes (Classic consumables summary). The search found **no WoW combat-log project using Ollama/local LLM** — [WoWP](https://github.com/rp4rk/WoWP); [taptologs](https://github.com/Dalvae/taptologs); [frostparse](https://awesome.ecosyste.ms/projects/github.com%2Fbradleybonitatibus%2Ffrostparse); [summarize_consumes](https://github.com/melbaa/summarize_consumes)
- Players have asked Blizzard for documentation of the Advanced Combat Log format, so the format is not officially documented — [Blizzard forum](https://us.forums.blizzard.com/en/wow/t/advanced-combat-log-documentation-requested/2042184)

### Inferences
- These categories appear unoccupied for **retail Midnight**:
  - (a) a local/offline LLM companion that reads WoWCombatLog.txt and explains performance;
  - (b) a local LLM reading SavedVariables across alts (gear, vault, professions, decor collection, weekly chores) for planning;
  - (c) an MCP server exposing WoW logs or SavedVariables to Claude or other agents. The DPSCoach pattern exists for T&L but not for WoW.
- The SavedVariables relay with `/reload` sync (AzerothLM) is the main technical constraint. Addons cannot use network or files directly, so any "AI in-game" design needs a reload cycle or display only outside the game.
- No WoW voice assistant was found in the searches. Treat it as a likely gap, but it was not explicitly searched.

### Gaps
- Discord bots with LLM features for WoW (guild bots) were not searched.
- No Product Hunt or startup listings were found beyond ParsePal and WowCoach. Their funding, users and quality are unknown.
- AskLogs is unverified.

---

## 4. Video/VOD tools: what exists and what's missing?

### Takeaway
Warcraft Recorder (free, open source, Windows) auto-records encounters and labels them, with a paid Pro tier for cloud and guild sharing. It is now part of Archon, and the Archon App (March 2026) also records video tied to post-pull analysis. Video and log sync is therefore covered by the incumbent. Automatic AI commentary, highlight detection and mistake clipping were not found.

### Cited Findings
- Warcraft Recorder: free, open-source WoW-only recorder (Windows), automatic local recording with labelled recordings. The Pro tier adds group features (cloud uploads, guild sharing, character-based upload filtering), and Pro subscribers get ad-free Archon sites. It is now "part of the Archon family" but stays standalone, and the long-term plan is interoperable cloud video between Recorder and the Archon App — [GitHub aza547/wow-recorder](https://github.com/aza547/wow-recorder); [Archon & Warcraft Recorder FAQ](https://archon.gg/wow/articles/help/archon-and-warcraft-recorder-faq); [The future of Warcraft Recorder and Archon Video](https://www.archon.gg/wow/articles/news/the-future-of-warcraft-recorder-and-archon-video) (403, snippet only); [Softpedia](https://www.softpedia.com/get/Gaming-Related/Warcraft-Recorder.shtml)
- Archon App, released 10 Mar 2026, includes video recording features — [Introducing Archon App](https://www.archon.gg/wow/articles/news/introducing-archon-app) (snippet)

### Inferences
- Gaps not found in sources:
  - automatic detection of "the moment you died or made the mistake", with a short clip and a plain-language explanation;
  - local AI summarisation of VODs;
  - a cross-week personal highlight or "progress reel";
  - a coach-review workflow (timestamped comments from a human coach) outside the Archon cloud.
- Pro pricing was not confirmed.

### Gaps
- Warcraft Recorder Pro price and 2026 user complaints were not retrieved.

---

## 5. Notable niche/unusual addons that hint at untapped categories

### Takeaway
AI-voiced quest narration is now a mature, crowded niche (VoiceOver family, Chatty Little NPC about 1.0M downloads, a Hungarian pack exists). Housing (Midnight) already has several decor trackers and guides. Accessibility for blind players has several addons, and the Midnight restrictions hurt them. Colorblind-specific addons and language-learning or journaling tools did not appear in the searches.

### Cited Findings
**Quest TTS / voice**
- Chatty Little NPC (AI Voiceovers): about 1.0M downloads on the owner profile, with pre-generated AI voice packs per expansion from Vanilla to TWW — [CurseForge](https://www.curseforge.com/wow/addons/chatty-little-npc)
- AI Quest Voices: about 32.5K downloads, with separate voice packs (Legion, BfA and others) — [CurseForge](https://www.curseforge.com/wow/addons/ai-quest-voices); [BfA pack](https://www.curseforge.com/wow/addons/ai-quest-voices-battle-for-azeroth)
- VoiceOver (Classic) uses ElevenLabs-generated voices, and VoiceOver Continued revives it for modern Classic clients — [VoiceOver](https://www.curseforge.com/wow/addons/voiceover); [AI VoiceOver Continued](https://www.curseforge.com/wow/addons/ai-voiceover-continued); [Wowhead news](https://www.wowhead.com/classic/pt/news/voiceover-addon-uses-ai-to-add-voice-acted-quests-332419)
- Modern VoiceOver, Spoken, SpeakStone (clones each NPC's in-game voice as the reference), QuestSpeaker — [Modern VoiceOver](https://www.curseforge.com/wow/addons/modern-voiceover); [Spoken](https://www.curseforge.com/wow/addons/spoken); [SpeakStone](https://www.curseforge.com/wow/addons/speakstone-main); [QuestSpeaker](https://www.curseforge.com/wow/addons/questspeaker)
- **HUN VoiceOver** (Hungarian) and RU and French packs exist, so localized AI voice is already being done — [HUN VoiceOver](https://www.curseforge.com/wow/addons/hun-voiceover); [AI VoiceOver TBC RU](https://www.curseforge.com/wow/addons/ai-voiceover-tbc-ru); [French vanilla pack](https://www.curseforge.com/wow/addons/voiceover-sounds-vanilla-french/install)

**Housing (Midnight)**
- HomeDecor: tracks decor, map icons, vendors, quests, achievements and Endeavor progress, account-wide — [CurseForge home-decor](https://www.curseforge.com/wow/addons/home-decor)
- Housing Decor Guide: lists all 1,690 decorations, with vendor shopping routes and waypoints, crafting recipes with material tracking, and profit-margin monitoring — [CurseForge](https://www.curseforge.com/wow/addons/housing-decor-guide/files/7981291)
- Icy Veins also names DecorDrops, Home Bound and Decor Vendor as catalogue-enhancing addons — [Icy Veins housing decor guide](https://www.icy-veins.com/wow/housing-decor-guide)
- Blizzard keeps extending housing (showcases, visitors, effect decor) — [Wowhead state of housing](https://www.wowhead.com/news/the-state-of-player-housing-and-upcoming-features-new-showcases-and-visitor-380523)

**Accessibility**
- WoWAccess (nameplate cycling, `/look`, facing check), KeyboardUINext (keyboard-only UI with TTS), BlindWarcraft (NVDA integration), Blindslash (Blizzard TTS), HoverTTS, TooltipReader, GossipTTS, Hyperlegible Font Replacer, Migraine Helper (black bars over bright effects). Sku is outdated or discontinued — [WoWAccess](https://www.curseforge.com/wow/addons/wowaccess); [KeyboardUINext](https://www.curseforge.com/wow/addons/keyboarduinext); [BlindWarcraft](https://www.curseforge.com/wow/addons/blindwarcraft); [Sku](https://www.curseforge.com/wow/addons/sku); [Blindslash](https://www.curseforge.com/wow/addons/blindslash); [HoverTTS](https://www.curseforge.com/wow/addons/hovertts-hear-the-game); [TooltipReader](https://www.curseforge.com/wow/addons/tooltip-reader); [GossipTTS](https://www.curseforge.com/wow/addons/gossip-tts); [Hyperlegible](https://www.curseforge.com/wow/addons/hyperlegible-font-replacer); [Migraine Helper](https://www.curseforge.com/wow/addons/migraine-helper)
- A blind player complained on the forums that removing addon capabilities in Midnight removes accessibility — [Blizzard forum](https://us.forums.blizzard.com/en/wow/t/removing-addons-removing-accessibility-a-blind-player%E2%80%99s-perspective/2178713)
- No colorblind-specific addon appeared in the search — (absence in [search results](https://www.curseforge.com/wow/addons/wowaccess) set; not exhaustive)

### Inferences
- AI quest voice: crowded. Avoid it unless the angle is different, such as live on-device TTS of *new* Midnight quest text in a user-chosen voice or language. Pre-generated packs lag behind new patches.
- Housing: trackers and shopping routes exist. Not seen: layout/design assistance (AI room styling suggestions, theme generation from a catalogue you own), external 3D planning of a house, and sharing or importing layouts. Verify against Blizzard's own showcase features.
- Accessibility: blind-player tooling exists but is fragmented and vulnerable to Midnight restrictions. An **external companion** (screen reader bridge, OCR or audio description outside the client) is less exposed to addon API limits. That is an inference.
- Language learning, RP journaling with AI (TRP3 + LLM), and personal "adventure diary" auto-generation from SavedVariables were not found in the searches. They are probably open, but this was not specifically searched.

### Gaps
- TRP3 (Total RP 3) and any AI-assisted RP tools were not researched this session.
- Language-learning addons (bilingual quest text, vocab from quests) were not searched explicitly.
- Journaling and screenshot-diary addons were not searched.

---

## 6. Which categories have NO serious tool at all?

### Takeaway
Based on what the searches found and did not find, these look open for retail Midnight as of Nov 2026: local/offline LLM log coaching, longitudinal personal improvement tracking, an MCP/agent bridge to WoW data, AI-explained VOD moments, addon-health diagnosis after patches, AI housing design, and LLM-assisted RP/journaling/language learning. All of these are conclusions from absence, not proven absences.

### Cited Findings
- The only local-LLM WoW project found (AzerothLM) is TBC Classic, beta and 3 stars — [GitHub](https://github.com/chefm4tt/AzerothLM)
- The only working local LLM combat-log coach found is for Throne & Liberty, not WoW — [DPSCoach](https://glama.ai/mcp/servers/@stalcup-dev/tl-dps-mcp/tree/d95b2f0eb4ad1fb391fb0bce107e133006465d0f)
- AI log analysis that exists is cloud and freemium (wow.gg) or alpha (WowCoach) — [wow.gg](https://wow.gg/logsanalyzer); [Icy Veins forum](https://www.icy-veins.com/forums/topic/85469-looking-for-alpha-testers-advanced-combat-log-analysis-tool/)
- Midnight API rules block in-client combat analysis, so external companions are the viable path — [warcraft.wiki.gg](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes/notes); [Blizzard](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight)

### Inferences
Candidate whitespace, ranked roughly by how confident I am that nothing serious exists:
1. A local/offline LLM that explains your own WoWCombatLog.txt over weeks (privacy, no upload, trend coaching). High confidence of a gap for retail.
2. An MCP server or agent bridge for WoW logs and SavedVariables. No WoW instance found.
3. A cross-alt "life admin" assistant reading SavedVariables (vault, professions, housing collection, weeklies) with natural-language planning. Partly covered by non-AI addons (e.g. alt trackers, not researched), so medium confidence.
4. AI-annotated VOD moments (death or mistake auto-clips with explanations). Archon may add this, so medium confidence and high incumbent risk.
5. An "addon doctor" for post-patch breakage, conflict and secret-value incompatibility. Medium confidence.
6. AI housing design assistant. Medium-low confidence, since Blizzard is iterating on housing quickly.
7. LLM RP companion, adventure journal, language learning. Not searched, so low confidence.
- Biggest incumbent risk: Archon (WCL + WoWAnalyzer + Wipefest + Recorder + App), which already has data, video and an app footprint.

### Gaps
- No systematic CurseForge/Wago search for alt trackers, journaling, TRP3 extensions or language tools.
- Reddit sentiment for 2026 was not collected. Several vendor pages blocked fetching (403).
- Wago.io and WoWInterface listings and download counts were not checked. Only CurseForge was sampled.
