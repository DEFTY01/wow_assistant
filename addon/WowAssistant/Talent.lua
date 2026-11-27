-- Waystone: the character's talent trees. The shape comes from the game client (every tab, every
-- talent with its tier, column, rank and prerequisite), the text and numbers of every rank from
-- TalentData.lua (generated from Wowhead's Forever talent calculator by scripts/build-talents.mjs;
-- not in the repo). The two are matched by talent name; where they differ (a talent the data does
-- not know, another rank count or place) the client wins and the difference is reported, so a
-- Forever patch that changes a talent shows up instead of being calculated wrong.
--
--   T.ReadTree()        -> { tabs = { { name, icon, points, talents = { { name, icon, tier, col, rank, max, req } } } },
--                            spent, unspent, level }
--   T.Data(class)       -> the generated data for a class, or nil
--   T.Match(tree, data) -> per tab: the data's tree, matched / missing / differs; and a talent's data by name
--   T.Effects(class, ranks) -> the model's talent input: each counted talent's numbers from the data,
--                          and for every talent with points whether the model counts it, or why not
--   /wa talent          -> the trees, the points, how far the data matches the game, and what the model counts

local _, WA = ...
WA = WA or {}
local T = {}
WA.Talent = T

local function Try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g = pcall(fn, ...)
  if ok then return a, b, c, d, e, f, g end
  return nil
end

function T.Data(class)
  local all = _G.WowAssistantTalents
  return all and class and all[class] or nil
end

-- The client's trees. GetTalentPrereqs gives the required talent's tier and column; it is turned
-- into that talent's name.
function T.ReadTree()
  local tree = { tabs = {}, spent = 0, level = Try(UnitLevel, "player") or 0 }
  local n = Try(GetNumTalentTabs) or 0
  for tab = 1, n do
    local name, icon, points = Try(GetTalentTabInfo, tab)
    local t = { name = name or ("Fa " .. tab), icon = icon, points = 0, talents = {} }
    local at = {}
    for i = 1, (Try(GetNumTalents, tab) or 0) do
      local tname, ticon, tier, col, rank, max = Try(GetTalentInfo, tab, i)
      if tname then
        local x = { index = i, name = tname, icon = ticon, tier = tonumber(tier) or 0, col = tonumber(col) or 0,
          rank = tonumber(rank) or 0, max = tonumber(max) or 0 }
        local rt, rc = Try(GetTalentPrereqs, tab, i)
        if rt and rc then x.reqAt = { tonumber(rt), tonumber(rc) } end
        t.talents[#t.talents + 1] = x
        at[x.tier .. ":" .. x.col] = x
        t.points = t.points + x.rank
      end
    end
    for _, x in ipairs(t.talents) do
      local r = x.reqAt and at[x.reqAt[1] .. ":" .. x.reqAt[2]]
      if r then x.req = r.name end
      x.reqAt = nil
    end
    -- the tab's own count where the client gives one (it includes nothing the talents do not)
    if tonumber(points) and tonumber(points) > t.points then t.points = tonumber(points) end
    tree.spent = tree.spent + t.points
    tree.tabs[tab] = t
  end
  -- unspent points: UnitCharacterPoints where the client has it
  local unspent = Try(UnitCharacterPoints, "player")
  tree.unspent = tonumber(unspent)
  return tree
end

-- Match the client's tabs to the data's trees by talent name (a tab is the tree most of its
-- talents belong to; the tab order is not assumed). For each tab: the data tree, how many talents
-- matched, the client talents the data lacks, and those whose rank count or place differ.
function T.Match(tree, data)
  local out = { tabs = {}, byName = {}, matched = 0, total = 0 }
  if not data then return out end
  local byName = {}
  for _, d in ipairs(data.talents or {}) do byName[d.name] = d end
  local treeById = {}
  for _, tr in ipairs(data.trees or {}) do treeById[tr.id] = tr end
  for tab, t in ipairs(tree.tabs or {}) do
    local votes, m = {}, { matched = 0, missing = {}, differs = {} }
    for _, x in ipairs(t.talents) do
      out.total = out.total + 1
      local d = byName[x.name]
      if not d then
        m.missing[#m.missing + 1] = x.name
      else
        votes[d.tree] = (votes[d.tree] or 0) + 1
        out.byName[x.name] = d
        if d.max ~= x.max or d.tier ~= x.tier or d.col ~= x.col then
          m.differs[#m.differs + 1] = ("%s (game: %d ranks, row %d column %d; data: %d ranks, row %d column %d)")
            :format(x.name, x.max, x.tier, x.col, d.max, d.tier, d.col)
        else
          m.matched = m.matched + 1
          out.matched = out.matched + 1
        end
      end
    end
    local best, bestN = nil, 0
    for id, k in pairs(votes) do if k > bestN or (k == bestN and best and id < best) then best, bestN = id, k end end
    m.tree = best and treeById[best] or nil
    m.count = #t.talents
    out.tabs[tab] = m
  end
  return out
end

-- The text of a rank (1..max) of a talent, from the data; nil when the data does not have it.
function T.RankText(d, rank)
  return d and d.desc and d.desc[rank] or nil
end

-- A talent's data by class and name; nil when the data does not have it.
function T.Find(class, name)
  local data = T.Data(class)
  for _, d in ipairs(data and data.talents or {}) do if d.name == name then return d end end
  return nil
end

---------------------------------------------------------------------------
-- talent effects: what a talent changes in the class model
---------------------------------------------------------------------------
-- Per class, per talent: the model keys it sets. val = which number of the rank's text (the
-- data's vals) is the value, or "rank" for the rank itself (a talent that gives an ability, or
-- one the model counts by rank). The number always comes from the Wowhead Forever data of the
-- rank the character has; the model turns it into its parameters (Model.lua, Hunter.lua, ...).
-- A talent not listed here is "nem számolt": the class ticket says when it gets counted.
T.TICKET = { ROGUE = "WA-032a", WARRIOR = "WA-032b", MAGE = "WA-032c", WARLOCK = "WA-032d", HUNTER = "WA-032e",
  SHAMAN = "WA-032f", DRUID = "WA-032g", PRIEST = "WA-032h", PALADIN = "WA-032i" }
-- Reasons for talents the model does not count, in plain words.
local SURVIVAL = "survival (dodge, parry, less damage taken): goes into the tank model (WA-023), does not change damage"
local UTILITY = "not damage: movement, stealth, control or a defensive cooldown"
local POISON = "the model measures poison damage from your fights (other sources), it does not count it separately"
local MULTI = "several targets: the model counts one target"
local THREAT = "threat: goes into the tank model (WA-024)"
local RAGE = "rage: the model does not simulate rage; it measures how often Heroic Strike and the specials go from your fights (rage comes in the rotation tickets: WA-008a, WA-008b)"
local MANA = "mana: the model does not count mana (mana and resting come in the rotation ticket)"
local RESIST = "the model does not count the target's resistance"
local DEMON = "depends on the demon type; the model measures the demon's damage from your fights"
local PET = "the model measures the pet's damage from your fights; the pet's crit and speed are not in it separately"
local HEAL = "healing: goes into the healer model (WA-017), does not change damage"
local BEAR = "bear (tank): the bear model comes with the tank model (WA-026)"
local PUSHBACK = "protects against cast pushback: the model does not count being hit while casting"
local TANK = "works on block, or on hits and crits you take: the model does not count what hits you (tank model, WA-025)"
local function ROTATION(what, ticket)
  return ("%s is not in the model separately yet; it comes in the rotation ticket (%s)"):format(what, ticket)
end
-- counted by the suggested rotation (Rotation.lua, the Harc page), not by the gear model's DPS
local function IN_ROTATION(what, ticket)
  return ("the Suggested rotation section of the Combat page counts it (%s; %s); it is not in the gear model's DPS"):format(what, ticket)
end
local function COOLDOWN(ticket)
  return ("an active ability with a cooldown: the cooldown is not in the talent data, it comes in the rotation ticket (%s)"):format(ticket)
end
T.EFFECTS = {
  -- Warrior (WA-032b): white swings, Heroic Strike and the weapon specials, the rest measured
  -- (Warrior.lua); rage is not simulated, so the talents that only give rage have that reason.
  WARRIOR = {
    -- Arms
    ["Improved Heroic Strike"] = { reason = RAGE },
    Deflection = { reason = SURVIVAL },
    ["Improved Rend"] = { reason = ROTATION("Rend", "WA-008a") },
    ["Improved Charge"] = { reason = RAGE },
    ["Improved Tactical Mastery"] = { reason = RAGE },
    ["Improved Overpower"] = { reason = ROTATION("Overpower (among the weapon specials, measured together)", "WA-008a") },
    ["Anger Management"] = { reason = RAGE },
    ["Deep Wounds"] = { reason = "the model measures its damage from your fights (Deep Wounds dot, other sources); there is no Forever source on whether a new crit restarts or stacks it, so it is not counted separately" },
    ["Spearing Strike"] = { reason = ROTATION("Spearing Strike", "WA-008a") },
    ["Two-Handed Weapon Specialization"] = { { key = "twoHandSpec", val = 1, what = "two-handed weapon damage %" } },
    Impale = { { key = "impale", val = 1, what = "ability crit damage bonus %" } },
    Bloodthrill = { reason = ROTATION("Overpower", "WA-008a") },
    ["Sweeping Strikes"] = { reason = MULTI },
    Weaponmaster = { { key = "weaponmaster", val = 3, what = "extra attack chance % (sword)" },
      partial = "the axe/polearm crit part and the mace/staff armor penetration are not in the model" },
    ["Improved Slam"] = { reason = ROTATION("Slam", "WA-008a") },
    ["Improved Hamstring"] = { reason = UTILITY },
    ["Mortal Strike"] = { reason = "measured from your fights among the weapon specials (rate and damage); comes separately in the rotation ticket (WA-008a)" },
    -- Protection
    ["Improved Bloodrage"] = { reason = RAGE },
    ["Shield Specialization"] = { reason = SURVIVAL },
    ["Iron Will"] = { reason = UTILITY },
    Anticipation = { reason = SURVIVAL },
    ["Improved Revenge"] = { reason = ROTATION("Revenge", "WA-024") },
    ["Improved Thunder Clap"] = { reason = RAGE },
    ["Last Stand"] = { reason = SURVIVAL },
    ["Master of Defense"] = { reason = SURVIVAL },
    ["Improved Disarm"] = { reason = UTILITY },
    Defiance = { reason = THREAT },
    ["Improved Sunder Armor"] = { reason = RAGE },
    Vanguard = { reason = UTILITY },
    ["Improved Shield Bash"] = { reason = UTILITY },
    ["Improved Shield Wall"] = { reason = SURVIVAL },
    ["Concussion Blow"] = { reason = UTILITY },
    ["Focused Rage"] = { reason = RAGE },
    Bastion = { { key = "bastion", val = 1, what = "damage % with a shield" } },
    ["Shield Slam"] = { reason = ROTATION("Shield Slam", "WA-024") },
    -- Fury
    ["Booming Voice"] = { reason = RAGE },
    Cruelty = { { key = "cruelty", val = 1, what = "crit %", stat = { "crit" } }, sheet = "the game's character sheet (GetCritChance) already includes it" },
    ["Lingering Rage"] = { reason = RAGE },
    ["Unbridled Wrath"] = { reason = RAGE },
    ["Furious Precision"] = { { key = "ohHit", val = 1, what = "off-hand hit %" } },
    ["Piercing Howl"] = { reason = UTILITY },
    ["Blood Craze"] = { reason = SURVIVAL },
    Enrage = { reason = "depends on the hits you take: how often you get hit does not come from the combat data yet" },
    ["Dual Wield Specialization"] = { { key = "dualWield", val = 1, what = "off-hand damage %" }, partial = "the off hand's part of rage (the model does not simulate rage)" },
    ["Reckless Swings"] = { reason = RAGE },
    ["Improved Execute"] = { reason = RAGE },
    ["Improved Berserker Rage"] = { reason = RAGE },
    ["Death Wish"] = { reason = COOLDOWN("WA-008b") },
    ["Gore Drinker"] = { reason = SURVIVAL },
    ["Improved Intercept"] = { reason = UTILITY },
    ["Improved Whirlwind"] = { reason = ROTATION("Whirlwind (among the weapon specials, measured together)", "WA-008b") },
    Flurry = { { key = "flurry", val = 1, what = "attack speed % for the 3 swings after a crit" } },
    Bloodthirst = { reason = "measured from your fights (other sources); comes separately in the rotation ticket (WA-008b)" },
  },
  -- Mage (WA-032c): the main nuke (Frostbolt or Fireball) and the wand, the rest measured (Mage.lua).
  MAGE = {
    -- Fire
    Incineration = { reason = ROTATION("Fire Blast, Scorch, Ice Lance and Arcane Blast", "WA-009b") },
    Accelerant = { { key = "accelerant", val = 1, what = "Fireball cast time − s" } },
    Ignite = { { key = "ignite", val = 1, what = "% of fire crit damage as a burn" } },
    ["Flame Throwing"] = { reason = UTILITY },
    Impact = { reason = UTILITY },
    ["Burning Soul"] = { reason = UTILITY },
    ["Improved Flamestrike"] = { reason = MULTI },
    Pyroblast = { reason = ROTATION("Pyroblast", "WA-009b") },
    ["Improved Fire Blast"] = { reason = ROTATION("Fire Blast", "WA-009b") },
    ["Improved Scorch"] = { reason = ROTATION("Scorch (the vulnerability depends on using Scorch)", "WA-009b") },
    ["Improved Fire Ward"] = { reason = SURVIVAL },
    ["Heating Up"] = { reason = ROTATION("Pyroblast", "WA-009b") },
    ["Master of Elements"] = { reason = MANA },
    ["Critical Mass"] = { { key = "critMass", val = 1, what = "fire spell crit %", gap = { "spellCritFire", "spellCritFrost" } } },
    ["Blast Wave"] = { reason = MULTI },
    ["Fire Power"] = { reason = "depends on the number of fire effects on the target: the combat data does not give this yet" },
    Combustion = { reason = COOLDOWN("WA-009b") },
    -- Frost
    ["Frost Warding"] = { reason = SURVIVAL },
    ["Improved Frostbolt"] = { { key = "impFrostbolt", val = 1, what = "Frostbolt cast time − s" } },
    Precision = { { key = "precision", val = 1, what = "spell hit %", stat = { "spellHit" } }, sheet = "from the game's character sheet (GetSpellHitModifier); with a combat log the measured miss counts" },
    ["Ice Shards"] = { { key = "iceShards", val = 1, what = "frost crit damage bonus %" } },
    Frostbite = { reason = UTILITY },
    ["Improved Frost Nova"] = { reason = UTILITY },
    Permafrost = { reason = UTILITY },
    ["Frost Channeling"] = { reason = MANA },
    ["Improved Blizzard"] = { reason = MULTI },
    ["Ice Lance"] = { reason = ROTATION("Ice Lance", "WA-009c") },
    ["Arctic Reach"] = { reason = UTILITY },
    ["Ice Block"] = { reason = SURVIVAL },
    Shatter = { reason = ROTATION("frozen target (Frost Nova, Frostbite)", "WA-009c") },
    ["Improved Cone of Cold"] = { reason = MULTI },
    ["Cold Snap"] = { reason = COOLDOWN("WA-009c") },
    ["Fingers of Frost"] = { reason = ROTATION("frozen target (Fingers of Frost)", "WA-009c") },
    ["Winter's Chill"] = { reason = ROTATION("Cone of Cold", "WA-009c") },
    ["Ice Barrier"] = { reason = COOLDOWN("WA-009c") },
    -- Arcane
    ["Wand Specialization"] = { { key = "wandSpec", val = 1, what = "wand damage %" } },
    ["Improved Channeling"] = { reason = UTILITY },
    ["Arcane Resilience"] = { reason = SURVIVAL },
    ["Arcane Subtlety"] = { reason = RESIST },
    ["Magic Absorption"] = { reason = SURVIVAL },
    ["Arcane Concentration"] = { reason = MANA },
    ["Missile Barrage"] = { reason = ROTATION("Arcane Missiles", "WA-009a") },
    ["Arcane Geometry"] = { reason = UTILITY },
    ["Arcane Impact"] = { reason = ROTATION("arcane spells (Arcane Missiles, Arcane Blast)", "WA-009a") },
    ["Arcane Blast"] = { reason = ROTATION("Arcane Blast", "WA-009a") },
    ["Arcane Shielding"] = { reason = SURVIVAL },
    ["Improved Counterspell"] = { reason = UTILITY },
    ["Arcane Meditation"] = { reason = MANA },
    ["Arcane Wrath"] = { reason = ROTATION("Arcane Wrath", "WA-009a") },
    ["Presence of Mind"] = { reason = COOLDOWN("WA-009a") },
    ["Arcane Mind"] = { { key = "arcaneMind", val = 1, what = "intellect %" }, partial = "the arcane crit bonus part (arcane spells are not in the model separately yet)" },
    ["Arcane Instability"] = { { key = "instability", val = 1, what = "spell damage %" },
      partial = "the crit part is already on the character sheet (GetSpellCritChance)" },
    ["Arcane Power"] = { reason = COOLDOWN("WA-009a") },
  },
  -- Warlock (WA-032d): direct spells, DoTs and drains, the demon and the wand (Warlock.lua); the
  -- school talents work on the share of each school in your own fights.
  WARLOCK = {
    -- Destruction
    ["Destructive Reach"] = { reason = UTILITY },
    ["Improved Shadow Bolt"] = { reason = "depends on Shadow Bolt's crits and the 12 s duration; how long it is up comes from the aura timeline (WA-005)" },
    Bane = { reason = "the model measures how often the direct spells go from your fights; the cast time comes in the rotation ticket (WA-010c)" },
    ["Molten Skin"] = { reason = SURVIVAL },
    Cataclysm = { reason = MANA },
    Aftermath = { { key = "aftermath", val = 1, what = "Immolate initial damage %" }, partial = "Conflagrate's slow (control)" },
    Ruin = { { key = "ruin", val = 1, what = "Destruction spell crit bonus %" } },
    Shadowburn = { reason = ROTATION("Shadowburn", "WA-010c") },
    Intensity = { reason = UTILITY },
    ["Agonizing Flames"] = { { key = "agonizing", val = 2, what = "Destruction spell damage %" }, partial = "Searing Pain's crit part" },
    Conflagrate = { reason = ROTATION("Conflagrate", "WA-010c") },
    Pyroclasm = { reason = UTILITY },
    ["Bane of Havoc"] = { reason = MULTI },
    ["Fire and Brimstone"] = { reason = ROTATION("Conflagrate", "WA-010c") },
    ["Shadow and Flame"] = { reason = ROTATION("Conflagrate and Shadowburn", "WA-010c") },
    Incinerate = { reason = ROTATION("Incinerate", "WA-010c") },
    -- Affliction
    ["Improved Life Tap"] = { reason = MANA },
    Suppression = { { key = "suppression", val = 1, what = "hit %", stat = { "spellHit" } }, sheet = "from the game's character sheet (GetSpellHitModifier); with a combat log the measured miss counts" },
    ["Improved Corruption"] = { { key = "impCorruption", val = 2, what = "Corruption damage %" }, partial = "the cast time part (the model measures the DoTs from your fights)" },
    ["Grim Reach"] = { reason = UTILITY },
    ["Soul Harvest"] = { reason = MANA },
    ["Improved Drains"] = { { key = "impDrains", val = 1, what = "drain damage %" } },
    ["Improved Bane of Agony"] = { { key = "impAgony", val = 1, what = "Bane of Agony damage %" } },
    ["Fel Concentration"] = { reason = UTILITY },
    ["Amplify Curse"] = { reason = COOLDOWN("WA-010a") },
    Pandemic = { reason = "the model does not count DoT crits separately (they are in the measured DoT damage); comes in the rotation ticket (WA-010a)" },
    Malevolence = { { key = "malevolence", val = 1, what = "shadow crit %", gap = { "spellCrit", "spellCritFire" } } },
    Nightfall = { reason = ROTATION("Shadow Trance (Nightfall)", "WA-010a") },
    ["Curse of Exhaustion"] = { reason = UTILITY },
    ["Siphon Life"] = { reason = "measured from your fights among the DoTs; comes separately in the rotation ticket (WA-010a)" },
    ["Soul Siphon"] = { reason = "depends on the number of DoTs on the target: the aura timeline will give this (WA-005)" },
    ["Shadow Mastery"] = { { key = "shadowMastery", val = 1, what = "shadow spell damage %" } },
    Wrack = { reason = ROTATION("Wrack", "WA-010a") },
    -- Demonology
    ["Improved Health Funnel"] = { reason = SURVIVAL },
    ["Improved Imp"] = { reason = DEMON },
    ["Demonic Embrace"] = { reason = SURVIVAL },
    ["Unholy Power"] = { { key = "unholyPower", val = 1, what = "demon damage %" } },
    ["Demonic Aegis"] = { reason = SURVIVAL },
    ["Improved Voidwalker"] = { reason = DEMON },
    ["Fel Vitality"] = { reason = MANA },
    ["Demonic Energies"] = { reason = MANA },
    ["Improved Sayaad"] = { reason = DEMON },
    ["Demonic Sacrifice"] = { reason = "depends on which demon you sacrifice; whether it is up comes from the aura timeline (WA-005)" },
    ["Master Summoner"] = { reason = UTILITY },
    Decimation = { reason = ROTATION("Soul Fire and the below-35% phase", "WA-010b") },
    ["Fel Domination"] = { reason = UTILITY },
    ["Demonic Brand"] = { reason = DEMON },
    ["Improved Felhunter"] = { reason = DEMON },
    ["Soul Link"] = { reason = "must be activated; whether it is up comes from the aura timeline (WA-005)" },
    ["Demonic Knowledge"] = { { key = "demonicKnowledge", val = 1, what = "% of your level as spell power" },
      sheet = "the game's spell power (GetSpellBonusDamage) already includes it while the demon is out" },
    ["Master Demonologist"] = { reason = DEMON },
    ["Demonic Pact"] = { reason = "depends on Demonic Sacrifice (aura timeline, WA-005)" },
  },
  -- Rogue (WA-032a): the model is Sinister Strike + Eviscerate with white swings (Model.lua); every
  -- talent of the three trees is either counted in it or has its reason.
  ROGUE = {
    -- Combat
    ["Coup de Grace"] = { { key = "coup", val = 1, what = "Eviscerate damage %" }, partial = "the Death Mark part is not in the model" },
    ["Efficient Strikes"] = { { key = "efficient", val = 1, what = "Sinister Strike energy cost −" } },
    ["Lightning Reflexes"] = { reason = SURVIVAL },
    ["Puncturing Wounds"] = { reason = ROTATION("Backstab and Mutilate", "WA-007a, WA-007c") },
    Deflection = { reason = SURVIVAL },
    Precision = { { key = "precision", val = 1, what = "hit %", stat = { "hit" } }, sheet = "the game's character sheet (GetHitModifier) already includes it" },
    ["Improved Sprint"] = { reason = UTILITY },
    Endurance = { reason = UTILITY },
    Riposte = { reason = ROTATION("Riposte (after a parry)", "WA-007b") },
    Composure = { reason = ROTATION("Poised", "WA-007b") },
    ["Improved Kick"] = { reason = UTILITY },
    ["Flawless Execution"] = { { key = "flawless", val = 1, what = "Eviscerate energy cost −" } },
    ["Weapon Expertise"] = { { key = "expertise", val = 1, what = "dodge and parry chance −%" } },
    Aggression = { { key = "aggression", val = 1, what = "Sinister Strike and Eviscerate damage %" } },
    ["Dual Wield Specialization"] = { { key = "dualWield", val = 1, what = "off-hand damage %" } },
    ["Blade Flurry"] = { reason = IN_ROTATION("the value of one use", "WA-007b") },
    ["Hack and Slash"] = { { key = "hackSlash", val = 1, what = "extra attack chance % (axe, sword)" },
      partial = "the dagger/fist crit part and the mace armor penetration are not in the model" },
    ["Flash of Steel"] = { reason = IN_ROTATION("Shank's energy and cooldown", "WA-007b") },
    ["Adrenaline Rush"] = { reason = IN_ROTATION("the value of one use", "WA-007b") },
    -- Assassination
    ["Improved Gouge"] = { reason = UTILITY },
    ["Remorseless Attacks"] = { reason = "an after-kill effect: how many enemies you killed does not come from the combat data yet" },
    Malice = { { key = "malice", val = 1, what = "crit %", stat = { "crit" } }, sheet = "the game's character sheet (GetCritChance) already includes it" },
    Ruthlessness = { { key = "ruthlessness", val = 1, what = "combo point chance % after a finisher" } },
    ["Improved Expose Armor"] = { reason = ROTATION("Expose Armor", "WA-007a") },
    ["Improved Slice and Dice"] = { reason = IN_ROTATION("Slice and Dice's duration", "WA-007b; Assassination: WA-007a") },
    Vigor = { reason = "only raises maximum energy; it does not change sustained damage in this model" },
    ["Blood Splatter"] = { reason = ROTATION("Rupture and Garrote", "WA-007a") },
    Lethality = { { key = "lethality", val = 1, what = "Sinister Strike crit damage bonus %" } },
    ["Vile Poisons"] = { reason = POISON },
    ["Cold Blood"] = { reason = COOLDOWN("WA-007a") },
    ["Improved Poisons"] = { reason = POISON },
    ["Relentless Strikes"] = { { key = "relentless", val = 1, what = "chance % per finisher combo point" },
      { key = "relentlessEnergy", val = 2, what = "energy refunded" } },
    Venom = { reason = ROTATION("Shank", "WA-007a") },
    ["Improved Kidney Shot"] = { reason = ROTATION("Kidney Shot", "WA-007a") },
    ["Seal Fate"] = { { key = "sealFate", val = 1, what = "extra combo point chance % after a crit" } },
    Mutilate = { reason = ROTATION("Mutilate", "WA-007a") },
    -- Subtlety
    Setup = { reason = SURVIVAL },
    ["Master of Deception"] = { reason = UTILITY },
    Opportunity = { reason = ROTATION("Backstab, Garrote, Ambush and Mutilate", "WA-007c") },
    ["Dirty Deeds"] = { reason = ROTATION("opener (Cheap Shot, Garrote)", "WA-007c") },
    Camouflage = { reason = UTILITY },
    ["Improved Ambush"] = { reason = ROTATION("Ambush", "WA-007c") },
    ["Dirty Tricks"] = { reason = UTILITY },
    Initiative = { reason = ROTATION("opener (Ambush, Garrote, Cheap Shot)", "WA-007c") },
    Premeditation = { reason = ROTATION("opener", "WA-007c") },
    ["Serrated Blades"] = { reason = "armor penetration and Rupture: the model does not count the target's armor, and Rupture is not in it (WA-007c)" },
    Elusiveness = { reason = UTILITY },
    ["Ghostly Strike"] = { reason = ROTATION("Ghostly Strike", "WA-007c") },
    ["Quick Getaway"] = { reason = UTILITY },
    ["Heightened Senses"] = { reason = SURVIVAL },
    Preparation = { reason = COOLDOWN("WA-007c") },
    Hemorrhage = { reason = ROTATION("Hemorrhage", "WA-007c") },
    ["Boot Knife"] = { reason = ROTATION("Shank", "WA-007c") },
    ["Death Mark"] = { reason = ROTATION("Death Mark", "WA-007c") },
  },
  -- Hunter (WA-032e): Auto Shot, Arcane Shot, Multi-Shot, Aimed Shot, melee and Raptor Strike, the
  -- pet and Serpent Sting (Hunter.lua).
  HUNTER = {
    -- Beast Mastery
    ["Deadly Aspects"] = { reason = "the haste proc's uptime comes from the aura timeline (WA-005)" },
    ["Endurance Training"] = { reason = SURVIVAL },
    ["Focused Fire"] = { { key = "focusedFire", val = 1, what = "all damage % with a pet" } },
    ["Improved Aspect of the Monkey"] = { reason = SURVIVAL },
    ["Improved Revive Pet"] = { reason = UTILITY },
    Pathfinding = { reason = UTILITY },
    ["Bestial Swiftness"] = { reason = UTILITY },
    ["Unleashed Fury"] = { { key = "unleashedFury", val = 1, what = "pet damage %" } },
    ["Improved Mend Pet"] = { reason = UTILITY },
    Ferocity = { reason = PET },
    ["Summon Hawk"] = { reason = ROTATION("Summon Hawk", "WA-011a") },
    ["Spirit Bond"] = { reason = SURVIVAL },
    Intimidation = { reason = UTILITY },
    ["Bestial Discipline"] = { reason = MANA },
    Frenzy = { reason = PET },
    ["Bestial Wrath"] = { reason = COOLDOWN("WA-011a") },
    -- Survival
    ["Improved Tracking"] = { reason = "depends on what you track and the target's type" },
    Deflection = { reason = SURVIVAL },
    Entrapment = { reason = UTILITY },
    ["Savage Strikes"] = { { key = "savageStrikes", val = 1, what = "melee ability crit %" } },
    Survivalist = { reason = SURVIVAL },
    ["Improved Wing Clip"] = { reason = UTILITY },
    ["Clever Traps"] = { reason = ROTATION("traps", "WA-011c") },
    Surefooted = { { key = "surefooted", val = 1, what = "hit %", stat = { "hit" } }, sheet = "the game's character sheet (GetHitModifier) already includes it", partial = "shorter slows (movement)" },
    Deterrence = { reason = SURVIVAL },
    ["Survival Tactics"] = { reason = UTILITY },
    ["Predator's Edge"] = { { key = "predatorCrit", val = 1, what = "melee ability crit damage %" },
      { key = "predatorOh", val = 2, what = "off-hand damage %" } },
    Counterattack = { reason = ROTATION("Counterattack", "WA-011c") },
    Resourcefulness = { reason = MANA },
    ["Expose Prey"] = { reason = ROTATION("Mongoose Bite", "WA-011c") },
    ["Survivalist's Discipline"] = { reason = UTILITY },
    ["Strider Kick"] = { reason = ROTATION("Strider Kick", "WA-011c") },
    ["Lightning Reflexes"] = { { key = "reflexes", val = 1, what = "agility %" } },
    ["Lacerating Strikes"] = { reason = ROTATION("Mongoose Bite", "WA-011c") },
    -- Marksmanship
    ["Hawk Eye"] = { reason = UTILITY },
    ["Improved Concussive Shot"] = { reason = UTILITY },
    ["Lethal Attacks"] = { { key = "lethal", val = 1, what = "crit %", stat = { "rangedCrit", "crit" } }, sheet = "the game's character sheet (GetRangedCritChance) already includes it" },
    ["Improved Stings"] = { { key = "impStings", val = 1, what = "Serpent Sting damage %" }, partial = "the Viper and Scorpid Sting part" },
    Efficiency = { reason = MANA },
    ["Careful Aim"] = { { key = "carefulAim", val = 1, what = "% of intellect as attack power" } },
    ["Rapid Killing"] = { reason = "an after-kill effect and the Rapid Fire cooldown: the number of kills does not come from the combat data yet" },
    ["Improved Arcane Shot"] = { reason = "the model measures how often Arcane Shot goes from your fights; the cooldown comes in the rotation ticket (WA-011b)" },
    ["Lone Wolf"] = { { key = "loneWolf", val = 1, what = "all damage % without a pet" } },
    ["Trueshot Aura"] = { { key = "trueshot", val = 2, what = "ranged attack power" }, sheet = "the game's ranged attack power already includes it while the aura is up" },
    ["Mortal Shots"] = { { key = "mortal", val = 1, what = "ranged crit damage bonus %" } },
    ["Rapid Recuperation"] = { reason = MANA },
    Barrage = { { key = "barrage", val = 1, what = "Multi-Shot and Aimed Shot damage %" } },
    ["Scatter Shot"] = { reason = UTILITY },
    ["Ranged Weapon Specialization"] = { { key = "rangedSpec", val = 1, what = "ranged weapon damage %" } },
    ["Sniper Shot"] = { reason = ROTATION("Sniper Shot", "WA-011b") },
  },
  -- Paladin (WA-032i): white swings with a seal, Holy Strike, the rest (Judgement, Consecration,
  -- Exorcism) measured (Paladin.lua); healing and tanking go to their models.
  PALADIN = {
    -- Retribution
    Deflection = { reason = SURVIVAL },
    Benediction = { reason = MANA },
    ["Improved Judgement"] = { reason = "the model measures Judgement's damage and rate from your fights; the shorter cooldown comes in the rotation ticket (WA-015a)" },
    Conviction = { { key = "conviction", val = 1, what = "crit %", stat = { "crit" } }, sheet = "the game's melee and spell crit already include it" },
    ["Sanctified Judgement"] = { reason = MANA },
    Vindication = { reason = SURVIVAL },
    ["Unyielding Faith"] = { reason = UTILITY },
    ["Seal of Command"] = { { key = "sealCommand", val = "rank", what = "ability: Seal of Command instead of Seal of Righteousness" } },
    ["Pursuit of Justice"] = { reason = UTILITY },
    ["Eye for an Eye"] = { reason = TANK },
    ["Sacred Arbiter"] = { { key = "sacredArbiter", val = 1, what = "Holy Strike damage %" }, partial = "refreshing the Judgement" },
    ["Two-Handed Weapon Specialization"] = { { key = "twoHandSpec", val = 1, what = "physical and holy damage % with a two-handed weapon" }, partial = "the lower threat" },
    ["Turn Evil"] = { reason = UTILITY },
    Repentance = { reason = UTILITY },
    Vengeance = { reason = "stacks for 30 s after a crit: comes from the aura timeline (WA-005)" },
    ["Champion of the Light"] = { { key = "champion", val = 1, what = "% of intellect as spell power" }, sheet = "the model uses the game's spell power; it also counts the items' intellect as spell power", partial = "Hammer of Wrath's cast time" },
    ["Unsealed Wrath"] = { reason = ROTATION("Unsealed Wrath (switching seals)", "WA-015a") },
    -- Holy
    ["Spiritual Focus"] = { reason = PUSHBACK },
    ["Divine Strength"] = { { key = "divineStrength", val = 1, what = "strength %" } },
    ["Healing Light"] = { reason = HEAL },
    Reverence = { reason = MANA },
    ["Improved Seals"] = { { key = "impSeals", val = 1, what = "seal damage %" }, partial = "the Judgement (the model measures it from your fights)" },
    ["Purifying Power"] = { reason = "the model measures Exorcism's and Holy Wrath's damage from your fights; the shorter cooldown comes in the rotation ticket (WA-015b)" },
    ["Divine Favor"] = { reason = HEAL },
    Illumination = { reason = MANA },
    ["Holy Conduit"] = { reason = MANA },
    ["Divine Precision"] = { reason = "the hit of holy spells (Judgement, Exorcism): the model measures these from your fights" },
    ["Infusion of Light"] = { reason = HEAL },
    ["Oath of Light"] = { reason = HEAL },
    ["Consecrated Ground"] = { reason = MULTI },
    ["Holy Shock"] = { reason = ROTATION("Holy Shock", "WA-015b") },
    ["Boundless Light"] = { reason = HEAL },
    ["Holy Power"] = { reason = HEAL },
    ["Light's Vigil"] = { reason = HEAL },
    -- Protection
    ["Divine Intellect"] = { { key = "divineIntellect", val = 1, what = "intellect %" } },
    Redoubt = { reason = SURVIVAL },
    Precision = { { key = "precision", val = 1, what = "hit %", stat = { "hit" } }, sheet = "the game's hit modifier (GetHitModifier) already includes it" },
    ["Guardian's Favor"] = { reason = UTILITY },
    ["Sacred Duty"] = { reason = SURVIVAL },
    ["Templar's Bulwark"] = { reason = SURVIVAL },
    ["Improved Hammer of Justice"] = { reason = UTILITY },
    ["Shield Specialization"] = { reason = SURVIVAL },
    Toughness = { reason = SURVIVAL },
    ["Swift Judgement"] = { reason = ROTATION("Swift Judgement", "WA-015b") },
    ["Improved Righteous Fury"] = { reason = SURVIVAL },
    Anticipation = { reason = SURVIVAL },
    Stoicism = { reason = UTILITY },
    ["Holy Shield"] = { reason = TANK },
    Reckoning = { reason = TANK },
    ["Iron Creed"] = { reason = THREAT },
    Shieldsworn = { reason = "the model measures how often Holy Strike goes from your fights; the shield hit comes in the tank model (WA-025)" },
  },
  -- Priest (WA-032h): Smite, Mind Blast, Shadow Word: Pain, Mind Flay, Holy Fire and the wand
  -- (Priest.lua); healing and shields go to the healer model.
  PRIEST = {
    -- Discipline
    ["Power in Light"] = { reason = "only if Holy Fire or Shadow Word: Pain is on the target: the aura timeline gives how long (WA-005)" },
    ["Wand Specialization"] = { { key = "wandSpec", val = 1, what = "wand damage %" } },
    ["Twin Disciplines"] = { { key = "twin", val = 1, what = "instant spell damage % (Shadow Word: Pain)" }, partial = "Devouring Plague and Shadow Word: Death (the model measures them as other sources) and healing" },
    ["Silent Resolve"] = { reason = THREAT },
    ["Holy Precision"] = { { key = "holyHit", val = 1, what = "holy hit %" } },
    ["Mental Strength"] = { { key = "mentalStrength", val = 1, what = "intellect %" } },
    Martyrdom = { reason = PUSHBACK },
    ["Mental Agility"] = { reason = MANA },
    ["Inner Focus"] = { reason = COOLDOWN("WA-014b") },
    ["Improved Power Word: Shield"] = { reason = SURVIVAL },
    Meditation = { reason = MANA },
    ["Improved Inner Fire"] = { reason = SURVIVAL },
    ["Improved Mana Burn"] = { reason = UTILITY },
    ["Soul Warding"] = { reason = SURVIVAL },
    Penance = { reason = ROTATION("Penance", "WA-014b") },
    ["Renewed Hope"] = { reason = HEAL },
    ["Divine Aegis"] = { reason = HEAL },
    ["Power Infusion"] = { reason = COOLDOWN("WA-014b") },
    -- Holy
    ["Twilight Focus"] = { reason = PUSHBACK },
    ["Improved Renew"] = { reason = HEAL },
    ["Holy Specialization"] = { { key = "holySpec", val = 1, what = "holy crit %", gap = { "spellCritHoly", "spellCritShadow" } }, sheet = "if the game's holy crit is this much higher than the shadow crit, it already includes it; otherwise the model adds it" },
    ["Spell Warding"] = { reason = SURVIVAL },
    ["Divine Fury"] = { { key = "divineFury", val = 1, what = "shorter Smite and Holy Fire cast time (s)" }, partial = "Heal and Greater Heal" },
    ["Holy Nova"] = { reason = MULTI },
    ["Blessed Recovery"] = { reason = SURVIVAL },
    Inspiration = { reason = HEAL },
    ["Holy Reach"] = { reason = UTILITY },
    ["Improved Healing"] = { reason = HEAL },
    ["Searing Light"] = { { key = "searing", val = 1, what = "holy damage %" }, partial = "the free Holy Nova (mana)" },
    ["Holy Binding"] = { reason = HEAL },
    ["Litany of Light"] = { reason = MANA },
    ["Spirit of Redemption"] = { reason = SURVIVAL },
    ["Spiritual Guidance"] = { reason = "spell power from spirit: the model does not read spirit (nor the items'), it uses the character sheet's spell power" },
    ["Spiritual Healing"] = { reason = HEAL },
    ["Prayer of Mending"] = { reason = HEAL },
    -- Shadow
    ["Shadow Focus"] = { { key = "shadowHit", val = 1, what = "shadow hit %" } },
    Blackout = { reason = UTILITY },
    ["Spirit Tap"] = { reason = MANA },
    ["Improved Mind Blast"] = { { key = "impMindBlast", val = 1, what = "shorter Mind Blast cooldown (s)" } },
    ["Improved Shadow Word: Pain"] = { reason = "the model does not follow DoT duration: it measures Shadow Word: Pain's ticks from your fights" },
    ["Shadow Reach"] = { reason = UTILITY },
    ["Improved Psychic Scream"] = { reason = UTILITY },
    ["Mind Flay"] = { { key = "mindFlay", val = "rank", what = "ability: Mind Flay is the filler instead of Smite" } },
    ["Improved Mind Flay"] = { { key = "impMindFlay", val = 1, what = "% more damage per tick than the previous one" } },
    ["Dark Inspiration"] = { reason = MANA },
    ["Vampiric Embrace"] = { reason = HEAL },
    ["Shadow Weaving"] = { reason = "the stacking depends on the fight's length: comes from the aura timeline (WA-005)" },
    Silence = { reason = UTILITY },
    ["Devouring Contagion"] = { reason = MULTI },
    ["Early Demise"] = { reason = "only on targets under 20% health: the model does not split the fight by the target's health" },
    Darkness = { { key = "darkness", val = 1, what = "shadow damage %" } },
    Shadowform = { { key = "shadowformDmg", val = 1, what = "shadow damage % in Shadowform" }, { key = "shadowformCrit", val = 3, what = "shadow crit bonus %" },
      partial = "reducing mana and physical damage" },
  },
  -- Druid (WA-032g): Cat Form (paw, builders, finishers and bleeds) or the caster (Wrath-sized
  -- casts, Moonkin Form), Druid.lua; bear talents go to the tank model, healing to the healer model.
  DRUID = {
    -- Feral Combat
    Ferocity = { { key = "ferocity", val = 1, what = "lower Claw and Rake energy cost" }, partial = "Maul and Swipe (bear, several targets)" },
    Furor = { reason = "shapeshifting: the model does not count shapeshifting or the rage or energy it gives" },
    ["Feral Swiftness"] = { reason = SURVIVAL },
    ["Feral Instinct"] = { reason = MULTI },
    ["Brutal Impact"] = { reason = UTILITY },
    ["Thick Hide"] = { reason = SURVIVAL },
    ["Shredding Attacks"] = { reason = "Shred only works from behind, Lacerate is bear: the model measures how often the builders go from your fights (WA-013b)" },
    ["Savage Fury"] = { { key = "savage", val = 1, what = "Claw, Rake and Shred damage %" }, partial = "Maul and Swipe (bear)" },
    ["Feral Charge"] = { reason = UTILITY },
    ["Sharpened Claws"] = { { key = "sharpened", val = 1, what = "crit % in form", stat = { "crit" }, form = "cat" }, sheet = "read in Cat Form, the character sheet already includes it; read in another form, the model adds it" },
    ["Predatory Strikes"] = { { key = "predatory", val = 1, what = "% of your level as attack power in form", stat = { "ap" }, form = "cat", scale = "level" }, sheet = "attack power read in Cat Form already includes it; the model adds it to estimated attack power" },
    Lacerate = { reason = BEAR },
    ["Predatory Discipline"] = { reason = "the model measures Ferocious Bite's damage from your fights (finishers); energy comes in the rotation ticket (WA-013b)" },
    ["Blood Frenzy"] = { reason = "the model measures how often finishers go from your fights; combo points come in the rotation ticket (WA-013b)" },
    ["Leader of the Pack"] = { { key = "lotp", val = 2, what = "crit % in form (aura)", stat = { "crit" }, form = "cat" }, sheet = "read in Cat Form, the character sheet already includes it; read in another form, the model adds it" },
    ["Natural Instinct"] = { { key = "natInst", val = 1, what = "ability crit bonus %" }, partial = "healing from intellect" },
    ["Rend and Tear"] = { reason = "the model does not follow the target's bleed duration; it comes from the aura timeline (WA-005)" },
    ["Natural Reaction"] = { reason = SURVIVAL },
    ["Primal Bite"] = { reason = BEAR },
    ["Shifting Power"] = { reason = MANA },
    -- Restoration
    ["Nature's Focus"] = { reason = PUSHBACK },
    ["Heart of the Wild"] = { { key = "hotwInt", val = 1, what = "intellect %" }, { key = "hotwStr", val = 3, what = "strength % in Cat Form" }, partial = "the bear's stamina (tank model)" },
    Naturalist = { { key = "naturalist", val = 2, what = "all damage %" }, partial = "Healing Touch's cast time" },
    Reflection = { reason = MANA },
    ["Natural Shapeshifter"] = { reason = MANA },
    Subtlety = { reason = THREAT },
    ["Gift of Nature"] = { reason = HEAL },
    Bloom = { reason = HEAL },
    ["Tranquil Spirit"] = { reason = HEAL },
    ["Improved Rejuvenation"] = { reason = HEAL },
    Swiftmend = { reason = HEAL },
    ["Nature's Swiftness"] = { reason = COOLDOWN("WA-013a") },
    ["Living Spirit"] = { reason = "spirit: raises mana regeneration; the model does not count mana" },
    ["Improved Tranquility"] = { reason = HEAL },
    ["Improved Regrowth"] = { reason = HEAL },
    ["Wild Growth"] = { reason = HEAL },
    -- Balance
    ["Starlight Wrath"] = { reason = "the model measures how often spells go from your fights; the shorter cast time comes in the rotation ticket (WA-013a)" },
    Genesis = { reason = "the model measures periodic damage (DoT, bleed) from your fights (finishers, other sources), it does not count it separately" },
    Moonglow = { reason = MANA },
    ["Moon and Stars"] = { reason = ROTATION("Moonfire (the model measures spells together)", "WA-013a") },
    ["Nature's Majesty"] = { { key = "majesty", val = 1, what = "crit %", stat = { "crit", "spellCrit" } }, sheet = "the game's melee and spell crit already include it" },
    ["Nature's Reach"] = { { key = "reachHit", val = 2, what = "hit %", stat = { "hit", "spellHit" } }, sheet = "the game's hit modifiers (GetHitModifier, GetSpellHitModifier) already include it", partial = "the range" },
    ["Improved Entangling Roots"] = { reason = UTILITY },
    ["Nature's Splendor"] = { reason = "the model does not follow DoT durations (it measures periodic damage from your fights)" },
    ["Insect Swarm"] = { reason = ROTATION("Insect Swarm", "WA-013a") },
    Vengeance = { { key = "vengeance", val = 1, what = "arcane and nature crit bonus %" } },
    ["Improved Starfire"] = { reason = UTILITY },
    Overgrowth = { reason = UTILITY },
    ["Nature's Grace"] = { reason = "the model measures how often spells go from your fights; the haste after a crit comes in the rotation ticket (WA-013a)" },
    Eclipse = { { key = "eclipse", val = 1, what = "Wrath crit %" }, partial = "Starfire's shorter cast time (rotation, WA-013a)" },
    Dreamstate = { reason = MANA },
    ["Moonkin Form"] = { { key = "moonkinDmg", val = 1, what = "arcane and nature damage % in Moonkin Form" }, { key = "moonkinCrit", val = 5, what = "crit % (aura)", stat = { "spellCrit" }, form = "moonkin" },
      sheet = "read in Moonkin Form, the character sheet already includes the crit aura; read in another form, the model adds it", partial = "armor and Omen of Clarity" },
  },
  -- Shaman (WA-032f): melee with an imbue, Stormstrike, shocks, Lightning Bolt and totems
  -- (Shaman.lua); healing talents go to the healer model.
  SHAMAN = {
    -- Elemental
    Convection = { reason = MANA },
    Concussion = { { key = "concussion", val = 1, what = "Lightning Bolt and Earth Shock damage %" }, partial = "the Chain Lightning part (several targets)" },
    ["Elemental Devastation"] = { reason = "the melee crit proc's uptime comes from the aura timeline (WA-005)" },
    Reverberation = { reason = "the model measures how often shocks go from your fights; the shorter cooldown comes in the rotation ticket (WA-012a)" },
    ["Elemental Alacrity"] = { reason = "the model measures how often Lightning Bolt goes from your fights; the shorter cast time comes in the rotation ticket (WA-012a)" },
    ["Call of Flame"] = { { key = "callFlame", val = 1, what = "fire totem and Flame Shock damage %" }, partial = "Fire Nova (several targets) and the longer Flame Shock" },
    ["Elemental Focus"] = { reason = MANA },
    ["Elemental Warding"] = { reason = SURVIVAL },
    ["Trial by Fire"] = { reason = MULTI },
    ["Eye of the Storm"] = { reason = PUSHBACK },
    Earthbound = { reason = UTILITY },
    ["Elemental Reach"] = { reason = UTILITY },
    ["Call of Thunder"] = { { key = "callThunder", val = 1, what = "Lightning Bolt crit %" }, partial = "the Chain Lightning part (several targets)" },
    ["Lightning Overload"] = { { key = "overload", val = 1, what = "% chance of a second Lightning Bolt at half damage" }, partial = "the Chain Lightning part (several targets)" },
    ["Elemental Fury"] = { { key = "fury", val = 1, what = "spell crit damage bonus %" }, partial = "Searing and Magma Totem crit (the model measures totem damage from your fights)" },
    ["Lightning Mastery"] = { reason = COOLDOWN("WA-012a") },
    -- Restoration
    ["Improved Healing Wave"] = { reason = HEAL },
    ["Tidal Focus"] = { { key = "tidalHit", val = 2, what = "hit %", stat = { "hit", "spellHit" } }, sheet = "the game's hit modifiers (GetHitModifier, GetSpellHitModifier) already include it", partial = "healing mana cost" },
    Mindfulness = { reason = MANA },
    ["Natural Grace"] = { reason = THREAT },
    ["Totemic Focus"] = { reason = MANA },
    ["Improved Reincarnation"] = { reason = SURVIVAL },
    ["Ancestral Healing"] = { reason = HEAL },
    ["Healing Focus"] = { reason = HEAL },
    ["Water Shield"] = { reason = MANA },
    ["Tidal Mastery"] = { reason = HEAL },
    ["Restorative Totems"] = { reason = HEAL },
    ["Mana Tide Totem"] = { reason = MANA },
    ["Healing Way"] = { reason = HEAL },
    ["Nature's Swiftness"] = { reason = COOLDOWN("WA-012a") },
    Purification = { reason = HEAL },
    Riptide = { reason = HEAL },
    -- Enhancement
    ["Earth's Grasp"] = { reason = UTILITY },
    ["Thundering Strikes"] = { { key = "thundering", val = 1, what = "crit %", stat = { "crit", "spellCrit" } }, sheet = "the game's melee and spell crit already include it" },
    ["Ancestral Knowledge"] = { { key = "ancestral", val = 1, what = "intellect %" } },
    ["Guardian Totems"] = { reason = SURVIVAL },
    ["Mental Dexterity"] = { { key = "mentalDex", val = 1, what = "% of intellect as attack power", stat = { "ap" }, scale = "int" }, sheet = "the game's attack power already includes it; the model also counts the items' intellect as attack power" },
    ["Improved Lightning Shield"] = { reason = "the model measures Lightning Shield's damage from your fights (other sources), it does not count it separately" },
    ["Elemental Weapons"] = { { key = "elemRockbiter", val = 1, what = "Rockbiter AP %" },
      { key = "elemWindfury", val = 2, what = "Windfury %" }, { key = "elemFlametongue", val = 3, what = "Flametongue/Frostbrand damage %" } },
    ["Shamanistic Focus"] = { reason = MANA },
    Anticipation = { reason = SURVIVAL },
    Toughness = { reason = SURVIVAL },
    Flurry = { { key = "flurry", val = 1, what = "attack speed % for the 3 swings after a crit" } },
    Stormstrike = { { key = "stormstrike", val = "rank", what = "ability" } },
    ["Improved Ghost Wolf"] = { reason = UTILITY },
    ["Spirit Weapons"] = { reason = THREAT },
    ["Mental Quickness"] = { { key = "mentalQuick", val = 1, what = "% of intellect as spell power" }, sheet = "the model uses the game's spell power; it also counts the items' intellect as spell power" },
    ["Improved Stormstrike"] = { reason = "the model measures how often Stormstrike goes from your fights; mana and the cooldown reset come in the rotation ticket (WA-012b)" },
    ["Maelstrom Weapon"] = { reason = ROTATION("Maelstrom Weapon (shorter Lightning Bolt)", "WA-012b") },
    ["Rage of the Farseer"] = { reason = COOLDOWN("WA-012b") },
    -- Classic only (Forever's trees do not have it): the two-hand gate in Shaman.lua
    ["Two-Handed Axes and Maces"] = { { key = "twoHand", val = "rank", what = "two-handed axes and maces" } },
  },
}

-- The model's talent input from the client's ranks ({ { name, tab, rank, max } }, every tab):
--   out[key]  = the value (0 when the talent has no points)
--   out.ranks = { [name] = rank } of every talent, out.read = the client gave talents, out.list = the
--               ranks it was made from (WA-033 builds variants of it)
--   out.absent = { [name] = true }: talents the model knows but Forever's trees do not have
--   out.status = { { name, rank, max, counted, values = { { key, value, what } }, source, reason } }
--                for every talent with points: counted (with the rank's text as the source) or why not
function T.Effects(class, ranks)
  local eff = T.EFFECTS[class or ""] or {}
  local data = T.Data(class)
  local out = { ranks = {}, status = {}, absent = {}, counted = 0, uncounted = 0, read = (#(ranks or {}) > 0) or nil, list = ranks or {} }
  for name, list in pairs(eff) do
    for _, x in ipairs(list) do out[x.key] = 0 end
    if data and not T.Find(class, name) then out.absent[name] = true end
  end
  for _, r in ipairs(ranks or {}) do
    out.ranks[r.name] = r.rank
    if r.rank > 0 then
      local d = data and T.Find(class, r.name)
      local list = eff[r.name]
      local st = { name = r.name, rank = r.rank, max = r.max }
      if data and not d then
        st.reason = "not in Wowhead Forever's data"
      elseif not list then
        st.reason = ("the model does not count it yet (%s)"):format(T.TICKET[class or ""] or "WA-032")
      elseif list.reason then
        st.reason = list.reason
      elseif not data then
        st.reason = "the talent data (TalentData.lua) is missing"
      elseif r.max and r.max > 0 and r.max ~= d.max then
        st.reason = ("the game knows %d ranks, the data %d"):format(r.max, d.max)
      else
        local vals = d.vals and d.vals[math.min(r.rank, d.max)] or {}
        local got = {}
        for _, x in ipairs(list) do
          local v = x.val == "rank" and r.rank or vals[x.val]
          if v == nil then st.reason = "the number is not in the rank's text" break end
          got[#got + 1] = { key = x.key, value = v, what = x.what }
        end
        if not st.reason then
          for _, g in ipairs(got) do out[g.key] = g.value end
          st.counted, st.values, st.sheet, st.partial = true, got, list.sheet, list.partial
          st.source = "Wowhead Forever: " .. (T.RankText(d, math.min(r.rank, d.max)) or "")
        end
      end
      if st.counted then out.counted = out.counted + 1 else out.uncounted = out.uncounted + 1 end
      out.status[#out.status + 1] = st
    end
  end
  return out
end

-- How many of a class's talents the model counts, how many have a reason not to, of all:
-- counted, explained, total.
function T.Coverage(class)
  local data = T.Data(class)
  local total, counted, explained = 0, 0, 0
  for _, d in ipairs(data and data.talents or {}) do
    total = total + 1
    local e = (T.EFFECTS[class] or {})[d.name]
    if e and e.reason then explained = explained + 1 elseif e then counted = counted + 1 end
  end
  return counted, explained, total
end

---------------------------------------------------------------------------
-- WA-033: what a talent is worth with the gear you have
---------------------------------------------------------------------------
-- The number an effect has at a rank, in the unit of the input field it touches (scale "int": a
-- % of the intellect, "level": a % of the level).
local function EffectValue(x, d, rank, input)
  if rank <= 0 then return 0 end
  local v = x.val == "rank" and rank or (d.vals and d.vals[math.min(rank, d.max)] or {})[x.val] or 0
  if x.scale == "int" then v = v * (input.int or 0) / 100 elseif x.scale == "level" then v = v * (input.level or 0) / 100 end
  return v
end

-- A copy of a model input with some talents at other ranks (changes = { [name] = rank }). The
-- talents the character sheet already holds (stat) are taken off or put on the sheet's numbers
-- too, so the model sees what the game would show: in a form only when the sheet was read in it
-- (form; Cat Form's attack power is also kept as catAp); a school crit only when the gap shows
-- the sheet has it (gap; else the model adds it itself).
function T.Variant(class, input, changes)
  local eff = T.EFFECTS[class or ""] or {}
  local list = input.talents and input.talents.list or {}
  local ranks, old, seen = {}, {}, {}
  for _, r in ipairs(list) do
    ranks[#ranks + 1] = { name = r.name, tab = r.tab, rank = changes[r.name] or r.rank, max = r.max }
    old[r.name], seen[r.name] = r.rank, true
  end
  for name, rank in pairs(changes) do
    if not seen[name] then
      local d = T.Find(class, name)
      ranks[#ranks + 1] = { name = name, rank = rank, max = d and d.max }
      old[name] = 0
    end
  end
  local out = {}
  for k, v in pairs(input) do out[k] = v end
  out.talents = T.Effects(class, ranks)
  for name, rank in pairs(changes) do
    local d, effects = T.Find(class, name), eff[name]
    if d and effects and not effects.reason then
      for _, x in ipairs(effects) do
        local v0, v1 = EffectValue(x, d, old[name] or 0, input), EffectValue(x, d, rank, input)
        local delta = v1 - v0
        if delta ~= 0 and x.gap then
          local a, b = input[x.gap[1]], input[x.gap[2]]
          -- the sheet has it now: take it off (or put the next rank's part on) that school's crit
          if v0 > 0 and a and b and a - b >= v0 - 0.05 then
            if input.spellCrit and math.abs(input.spellCrit - a) < 1e-9 and x.gap[1] ~= "spellCrit" then out.spellCrit = out.spellCrit + delta end
            out[x.gap[1]] = a + delta
          end
        elseif delta ~= 0 and x.stat then
          for _, field in ipairs(x.stat) do
            if not x.form or input.form == x.form then
              if out[field] ~= nil then out[field] = out[field] + delta end
            elseif x.form == "cat" and field == "ap" and input.catAp then
              out.catAp = input.catAp + delta
            end
          end
        end
      end
    end
  end
  return out
end

-- What the talents change in the stat weights: for each stat, the DPS 10 points (crit: 1%) give
-- in one context and in the other. Only the changes that matter (0.05 DPS and 3%).
T.WEIGHT_STATS = { { "agi", 10, "agility" }, { "str", 10, "strength" }, { "ap", 20, "attack power" }, { "crit", 1, "crit %" },
  { "int", 10, "intellect" }, { "sp", 10, "spell power" } }
function T.WeightShift(with, without)
  local out = {}
  if not (with and without and with.buffGain and without.buffGain) then return out end
  for _, s in ipairs(T.WEIGHT_STATS) do
    local e = { [s[1]] = s[2] }
    local w1, w0 = with.buffGain(e) or 0, without.buffGain(e) or 0
    if math.abs(w1 - w0) >= 0.05 and math.abs(w1 - w0) >= 0.03 * math.max(math.abs(w0), math.abs(w1)) then
      out[#out + 1] = { stat = s[1], label = s[3], per = s[2], without = w0, with = w1 }
    end
  end
  return out
end

-- Every talent you have points in and every talent you could put the next point in, with what it
-- is worth now (build = the model, e.g. WA.Model.Context; unspent = free points, nil = unknown):
--   { baseline, rows = { { name, rank, max, tree, counted, reason, now, nowPct, next, nextPct,
--     available, weights, note, source } }, best = the available row whose next point is worth most }
-- now: the model's DPS with the ranks you have minus with none; next: one rank more minus now.
function T.Values(class, input, build, unspent)
  local data = T.Data(class)
  local eff = T.EFFECTS[class or ""] or {}
  local base = build(input)
  local out = { baseline = base and base.baseline or 0, rows = {}, unspent = unspent }
  if not (data and base) then return out end
  local ranks = input.talents and input.talents.ranks or {}
  local treePts, spent = {}, 0
  for _, d in ipairs(data.talents) do
    local r = ranks[d.name] or 0
    treePts[d.tree] = (treePts[d.tree] or 0) + r
    spent = spent + r
  end
  out.spent = spent
  local bl = out.baseline
  local function Pct(x) return bl > 0 and x / bl * 100 or 0 end
  for _, d in ipairs(data.talents) do
    local rank = ranks[d.name] or 0
    local e = eff[d.name]
    -- the next rank is open when the tree has the points and the required talent is full
    local reqOk = not d.req or (ranks[d.req[1]] or 0) >= (d.req[2] or 0)
    local available = rank < d.max and (treePts[d.tree] or 0) >= (d.reqPoints or 0) and reqOk
    if rank > 0 or available then
      local row = { name = d.name, rank = rank, max = d.max, tree = d.tree, available = available,
        counted = e ~= nil and not e.reason, reason = e and e.reason or (not e and ("the model does not count it yet (%s)"):format(T.TICKET[class] or "WA-032")) or nil }
      if row.counted then
        if rank > 0 then
          local without = build(T.Variant(class, input, { [d.name] = 0 }))
          row.now = bl - without.baseline
          row.nowPct = Pct(row.now)
          row.weights = T.WeightShift(base, without)
          row.source = "Wowhead Forever: " .. (T.RankText(d, math.min(rank, d.max)) or "")
        end
        if rank < d.max then
          local more = build(T.Variant(class, input, { [d.name] = rank + 1 }))
          row.next = more.baseline - bl
          row.nextPct = Pct(row.next)
          if rank == 0 then row.weights = T.WeightShift(more, base) end
          row.nextSource = "Wowhead Forever: " .. (T.RankText(d, rank + 1) or "")
        end
        -- a sheet talent whose sheet part is not in an input field: the model cannot take it off
        local broken = false
        for _, x in ipairs(e) do if x.stat or x.gap then broken = true end end
        if e.sheet and not broken then row.note = "the model does not separate out the part already on the character sheet, so the value is lower than the real one" end
      end
      out.rows[#out.rows + 1] = row
      -- the best next point: only one that adds DPS (+0 says nothing)
      if available and row.counted and row.next and row.next > 0.005 and (not out.best or row.next > out.best.next) then out.best = row end
    end
  end
  return out
end

-- The weights your talents move, all of them together: the model with your talents against the
-- model with none of the counted ones (for the gear page's note).
function T.TalentShift(class, input, build, ctx)
  local changes, any = {}, false
  local eff = T.EFFECTS[class or ""] or {}
  for name, rank in pairs(input.talents and input.talents.ranks or {}) do
    local e = eff[name]
    if rank > 0 and e and not e.reason then changes[name], any = 0, true end
  end
  if not any then return {} end
  return T.WeightShift(ctx or build(input), build(T.Variant(class, input, changes)))
end

---------------------------------------------------------------------------
-- WA-034: the talent calculator. A plan is only a plan (ranks by talent name): the addon never
-- learns a talent, you do that in the game's talent window.
---------------------------------------------------------------------------
-- The trees to plan on: the client's shape where the client gives one (tab order, icon, tier,
-- column, rank, prerequisite), else the data's; each talent with its data (text, numbers,
-- the points its row needs, the rank its prerequisite needs).
--   { tabs = { { name, icon, talents = { { name, icon, tier, col, max, rank, req, reqRank, reqPoints, tab, index, data } } } },
--     byName, client = true when the shape is the client's }
function T.PlanTrees(class, tree)
  local data = T.Data(class)
  local byData = {}
  for _, d in ipairs(data and data.talents or {}) do byData[d.name] = d end
  local out = { tabs = {}, byName = {} }
  local function Add(tab, x)
    local d = byData[x.name]
    local t = { name = x.name, tier = x.tier, col = x.col, max = x.max, rank = x.rank or 0, tab = tab.n, index = x.index, data = d,
      icon = x.icon or (d and d.icon and ("Interface\\Icons\\" .. d.icon)) or "Interface\\Icons\\INV_Misc_QuestionMark",
      reqPoints = d and d.reqPoints or 5 * ((x.tier or 1) - 1), req = x.req }
    if t.req then t.reqRank = d and d.req and d.req[1] == t.req and d.req[2] or nil end
    tab.talents[#tab.talents + 1] = t
    out.byName[t.name] = t
  end
  if tree and tree.tabs and #tree.tabs > 0 then
    out.client = true
    for i, ct in ipairs(tree.tabs) do
      local tab = { n = i, name = ct.name, icon = ct.icon, talents = {} }
      out.tabs[i] = tab
      for _, x in ipairs(ct.talents) do Add(tab, x) end
    end
  elseif data then
    local trees = {}
    for _, tr in ipairs(data.trees or {}) do trees[#trees + 1] = tr end
    table.sort(trees, function(a, b) return (a.tab or 0) < (b.tab or 0) end)
    for i, tr in ipairs(trees) do
      local tab = { n = i, name = tr.name, talents = {} }
      out.tabs[i] = tab
      for _, d in ipairs(data.talents) do
        if d.tree == tr.id then Add(tab, { name = d.name, tier = d.tier, col = d.col, max = d.max, req = d.req and d.req[1] }) end
      end
    end
  end
  for _, tab in ipairs(out.tabs) do
    table.sort(tab.talents, function(a, b) if a.tier ~= b.tier then return a.tier < b.tier end return a.col < b.col end)
    -- the prerequisite's rank: the data's, else all of it (the game's rule)
    for _, t in ipairs(tab.talents) do
      if t.req and not t.reqRank then t.reqRank = out.byName[t.req] and out.byName[t.req].max or 1 end
    end
  end
  return out
end

-- The points you have: what you spent and have free where the client says so, else level - 9
-- (the first point at level 10).
function T.PlanPoints(tree)
  if tree and tree.unspent then return (tree.spent or 0) + tree.unspent end
  return math.max(0, ((tree and tree.level) or 0) - 9)
end

function T.PlanSpent(pt, ranks)
  local n = 0
  for name in pairs(pt.byName) do n = n + (ranks[name] or 0) end
  return n
end

local function TabPoints(tab, ranks, belowTier)
  local n = 0
  for _, x in ipairs(tab.talents) do if not belowTier or x.tier < belowTier then n = n + (ranks[x.name] or 0) end end
  return n
end
T.TabPoints = TabPoints

-- Every rule a plan breaks (the game's rules): no more points than you have, no more ranks than a
-- talent has, the points a row needs in the tree under it, the prerequisite's ranks.
function T.PlanCheck(pt, ranks, total)
  local out = {}
  local spent = T.PlanSpent(pt, ranks)
  if total and spent > total then out[#out + 1] = ("the plan has %d points, but you only have %d"):format(spent, total) end
  for _, tab in ipairs(pt.tabs) do
    for _, x in ipairs(tab.talents) do
      local r = ranks[x.name] or 0
      if r > 0 then
        if r > x.max then out[#out + 1] = ("%s: at most %d ranks"):format(x.name, x.max) end
        if TabPoints(tab, ranks, x.tier) < x.reqPoints then
          out[#out + 1] = ("%s: needs %d points above it in the %s tree"):format(x.name, x.reqPoints, tab.name)
        end
        if x.req and (ranks[x.req] or 0) < (x.reqRank or 1) then
          out[#out + 1] = ("%s: needs %s rank %d first"):format(x.name, x.req, x.reqRank or 1)
        end
      end
    end
  end
  return out
end

-- One rank more or less in a talent. Only the rules the change itself breaks stop it (a plan
-- read from a client that differs from the data may break one already). -> new ranks, or nil and why.
local function Change(pt, ranks, name, step, total)
  local x = pt.byName[name]
  if not x then return nil, "no such talent: " .. tostring(name) end
  local new = {}
  for k, v in pairs(ranks) do new[k] = v end
  local r = (new[name] or 0) + step
  if r < 0 then return nil, name .. ": no points in it" end
  if r > x.max then return nil, ("%s: already %d/%d"):format(name, x.max, x.max) end
  new[name] = r > 0 and r or nil
  local before = {}
  for _, m in ipairs(T.PlanCheck(pt, ranks, total)) do before[m] = true end
  for _, m in ipairs(T.PlanCheck(pt, new, total)) do
    if not before[m] then return nil, m end
  end
  return new
end
function T.PlanAdd(pt, ranks, name, total) return Change(pt, ranks, name, 1, total) end
function T.PlanRemove(pt, ranks, name, total) return Change(pt, ranks, name, -1, total) end

-- Whether the next point can go into a talent now (for the look of the tree).
function T.PlanOpen(pt, ranks, name, total)
  return T.PlanAdd(pt, ranks, name, total) ~= nil
end

-- The ranks you have now, from the trees.
function T.PlanCurrent(pt)
  local out = {}
  for name, x in pairs(pt.byName) do if (x.rank or 0) > 0 then out[name] = x.rank end end
  return out
end

-- What the plan is worth against the talents you have now (build = the model):
--   { now, plan, diff, diffPct, changes = { { name, from, to, value, counted, reason, source } },
--     values = T.Values on the plan (each talent's worth and the next point in the plan) }
-- value: that one change alone against now (the changes together can differ from the sum).
function T.PlanValue(class, input, build, ranks, free)
  local cur = input.talents and input.talents.ranks or {}
  local changes, any = {}, false
  for name, r in pairs(ranks) do if r ~= (cur[name] or 0) then changes[name], any = r, true end end
  for name, r in pairs(cur) do if r > 0 and not ranks[name] then changes[name], any = 0, true end end
  local base = build(input)
  local out = { now = base and base.baseline or 0, changes = {} }
  local planInput = any and T.Variant(class, input, changes) or input
  local planCtx = any and build(planInput) or base
  out.plan = planCtx and planCtx.baseline or out.now
  out.diff = out.plan - out.now
  out.diffPct = out.now > 0 and out.diff / out.now * 100 or 0
  local eff = T.EFFECTS[class or ""] or {}
  for name, to in pairs(changes) do
    local e, d = eff[name], T.Find(class, name)
    local c = { name = name, from = cur[name] or 0, to = to, counted = e ~= nil and not e.reason }
    if c.counted then
      c.value = build(T.Variant(class, input, { [name] = to })).baseline - out.now
      c.source = d and ("Wowhead Forever: " .. (T.RankText(d, math.max(1, math.min(math.max(to, c.from), d.max))) or "")) or nil
    else
      c.reason = e and e.reason or ("the model does not count it yet (%s)"):format(T.TICKET[class or ""] or "WA-032")
    end
    out.changes[#out.changes + 1] = c
  end
  table.sort(out.changes, function(a, b)
    local va, vb = a.value and math.abs(a.value) or -1, b.value and math.abs(b.value) or -1
    if va ~= vb then return va > vb end
    return a.name < b.name
  end)
  out.values = T.Values(class, planInput, build, free)
  return out
end

-- Sharing as text: "Waystone:CLASS:" and per tree the ranks in row and column order, one digit a
-- talent, the trees split by "-" (the zeros at the end of a tree left off).
function T.PlanExport(class, pt, ranks)
  local parts = {}
  for i, tab in ipairs(pt.tabs) do
    local d = {}
    for j, x in ipairs(tab.talents) do d[j] = tostring(math.min(9, ranks[x.name] or 0)) end
    parts[i] = (table.concat(d):gsub("0+$", ""))
  end
  return ("Waystone:%s:%s"):format(class or "?", (table.concat(parts, "-"):gsub("%-+$", "")))
end

-- A shared plan back: its ranks, or nil and why (another class, a tree too long, a broken rule).
function T.PlanImport(class, pt, text, total)
  local cls, body = tostring(text or ""):match("^%s*Waystone:(%u+):([%d%-]*)%s*$")
  if not cls then return nil, "this is not a Waystone plan (Waystone:CLASS:digits)" end
  if cls ~= class then return nil, ("this is a %s plan, your character is %s"):format(cls, tostring(class)) end
  local ranks, i = {}, 0
  for part in (body .. "-"):gmatch("([%d]*)%-") do
    i = i + 1
    local tab = pt.tabs[i]
    if not tab then if part ~= "" then return nil, "it has more trees than your class" end
    else
      if #part > #tab.talents then return nil, ("it has more talents in the %s tree than the tree has"):format(tab.name) end
      for j = 1, #part do
        local r = tonumber(part:sub(j, j))
        if r > 0 then ranks[tab.talents[j].name] = r end
      end
    end
  end
  local broken = T.PlanCheck(pt, ranks, total)
  if #broken > 0 then return nil, broken[1] end
  return ranks
end

-- Saved plans, per character: { { name, ranks } }.
function T.PlanList()
  local c = WA.charDB
  if not c then return {} end
  c.talentPlans = c.talentPlans or {}
  return c.talentPlans
end

-- Saves under a name (the same name: overwritten); -> its index.
function T.PlanSave(name, ranks)
  local list = T.PlanList()
  local copy = {}
  for k, v in pairs(ranks) do if v > 0 then copy[k] = v end end
  for i, p in ipairs(list) do
    if p.name == name then p.ranks = copy return i end
  end
  list[#list + 1] = { name = name, ranks = copy }
  return #list
end

function T.PlanDelete(i)
  local list = T.PlanList()
  if list[i] then table.remove(list, i) end
end

local function F2(n) return ("%.2f"):format(n) end
local function Signed(n) return (n >= 0 and "+" or "−") .. F2(math.abs(n)) end
T.F2, T.Signed = F2, Signed

local function Report()
  local class = WA.Game and WA.Game.Class and WA.Game.Class() or select(2, UnitClass("player"))
  local tree = T.ReadTree()
  local data = T.Data(class)
  if #tree.tabs == 0 then
    WA.Print("The game gave no talent tree (the client's talent API is not available).")
    return
  end
  local m = T.Match(tree, data)
  WA.Print(("Talents: %d points spent%s, level %d."):format(tree.spent,
    tree.unspent and (", " .. tree.unspent .. " free") or "", tree.level))
  for tab, t in ipairs(tree.tabs) do
    local x = m.tabs[tab]
    local where = ""
    if data and x and x.count > 0 then
      where = x.tree and (" · Wowhead Forever: %s tree, %d/%d talents match"):format(x.tree.name, x.matched, x.count)
        or (" · not in Wowhead Forever's data (%d talents)"):format(x.count)
    end
    WA.Print(("  %d. %s: %d points%s"):format(tab, t.name, t.points, where))
    if x then
      for i = 1, math.min(5, #x.missing) do WA.Print("    not in the data: " .. x.missing[i]) end
      for i = 1, math.min(5, #x.differs) do WA.Print("    differs: " .. x.differs[i]) end
    end
  end
  -- what the model does with them: the counted talents with their numbers, the rest with the reason
  local ranks = {}
  for tab, t in ipairs(tree.tabs) do
    for _, x in ipairs(t.talents) do ranks[#ranks + 1] = { name = x.name, tab = tab, rank = x.rank, max = x.max } end
  end
  local e = T.Effects(class, ranks)
  -- WA-033: each talent's worth with your gear (the model with and without it, and one rank more)
  local values
  if WA.Game and WA.Game.Supported and WA.Game.Supported() and WA.Model and WA.Model.Context then
    local free = tree.unspent or math.max(0, (tree.level or 0) - 9 - tree.spent)
    local ok, v = pcall(function() return T.Values(class, WA.Game.ModelInput(), WA.Model.Context, free) end)
    if ok and v then
      values = v
      values.byName = {}
      for _, row in ipairs(values.rows) do values.byName[row.name] = row end
      WA.Print(("The model's DPS with your current gear and talents: %s."):format(F2(values.baseline)))
    else
      WA.Print("Talent values cannot be computed now: " .. tostring(v))
    end
  end
  if #e.status > 0 then
    WA.Print(("Talents the model counts: %d, not counted yet: %d."):format(e.counted, e.uncounted))
    for _, st in ipairs(e.status) do
      if st.counted then
        local bits = {}
        for _, v in ipairs(st.values) do bits[#bits + 1] = ("%s %s"):format(v.what, tostring(v.value)) end
        local note = st.sheet and (" (" .. st.sheet .. ")") or ""
        if st.partial then note = note .. "; not counted: " .. st.partial end
        WA.Print(("    counted: %s %d/%d · %s%s"):format(st.name, st.rank, st.max or st.rank, table.concat(bits, ", "), note))
        local row = values and values.byName[st.name]
        if row and row.now then
          WA.Print(("      now %s DPS (%s%%)%s%s"):format(Signed(row.now), Signed(row.nowPct),
            row.next and (", the next point %s DPS (%s%%)"):format(Signed(row.next), Signed(row.nextPct)) or ", maxed",
            row.note and (" · " .. row.note) or ""))
          for _, w in ipairs(row.weights or {}) do
            WA.Print(("      %s: %s → %s DPS / %d"):format(w.label, F2(w.without), F2(w.with), w.per))
          end
        end
      end
    end
    local shown = 0
    for _, st in ipairs(e.status) do
      if not st.counted and shown < 5 then
        shown = shown + 1
        WA.Print(("    not counted: %s · %s"):format(st.name, st.reason))
      end
    end
    if e.uncounted > shown then WA.Print(("    … and %d more talents not counted"):format(e.uncounted - shown)) end
    WA.Print("    (talents not counted are listed with their effect but no value: the tank and healer models are not done yet)")
  end
  if values and values.best then
    local b = values.best
    WA.Print(("The most valuable next point now: %s %d/%d → %d/%d, %s DPS (%s%%)%s. Source: %s.")
      :format(b.name, b.rank, b.max, b.rank + 1, b.max, Signed(b.next), Signed(b.nextPct),
        (values.unspent or 0) > 0 and "" or " (you have no free point now)", b.nextSource or "?"))
  end
  if not data then
    WA.Print("The talent data (TalentData.lua) is missing: node scripts/build-talents.mjs --install")
  else
    WA.Print(("Data: Wowhead Forever talent calculator, downloaded %s."):format(_G.WowAssistantTalents.fetched or "?"))
  end
end
T.Report = Report

if WA.Command then WA.Command("talent", Report, "/wa talent – your talent trees, your points, and whether Wowhead Forever's data matches the game") end
