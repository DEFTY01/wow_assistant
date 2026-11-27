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
          m.differs[#m.differs + 1] = ("%s (játék: %d rang, %d. sor %d. oszlop; adat: %d rang, %d. sor %d. oszlop)")
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
local SURVIVAL = "túlélés (dodge, parry, kevesebb sebzés): a tankmodellbe kerül (WA-023), a sebzést nem változtatja"
local UTILITY = "nem sebzés: mozgás, lopakodás, irányítás vagy védekező cooldown"
local POISON = "a mérgek sebzését a modell a harcaidból méri (egyéb források), külön nem számolja"
local MULTI = "több célpont: a modell egy célpontra számol"
local THREAT = "fenyegetés (threat): a tankmodellbe kerül (WA-024)"
local RAGE = "rage: a modell nem szimulálja a rage-et; a Heroic Strike és a specialok gyakoriságát a harcaidból méri (a rage a rotációs ticketben jön: WA-008a, WA-008b)"
local MANA = "mana: a modell nem számolja a manát (a mana és a pihenő a rotációs ticketben jön)"
local RESIST = "a célpont ellenállását (resistance) a modell nem számolja"
local DEMON = "a démon fajtájától függ; a démon sebzését a modell a harcaidból méri"
local PET = "a pet sebzését a modell a harcaidból méri; a pet critje és sebessége külön nincs benne"
local HEAL = "gyógyítás: a gyógyítómodellbe kerül (WA-017), a sebzést nem változtatja"
local function ROTATION(what, ticket)
  return ("a(z) %s még nincs külön a modellben; a rotációs ticketben jön (%s)"):format(what, ticket)
end
local function COOLDOWN(ticket)
  return ("aktív képesség cooldownnal: a cooldown ideje nincs a talentadatban, a rotációs ticketben jön (%s)"):format(ticket)
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
    ["Improved Overpower"] = { reason = ROTATION("Overpower (a fegyveres specialok között, együtt mérve)", "WA-008a") },
    ["Anger Management"] = { reason = RAGE },
    ["Deep Wounds"] = { reason = "a sebzését a modell a harcaidból méri (Deep Wounds dot, egyéb források); hogy újabb crit újraindítja vagy halmozza, arról nincs Forever-forrás, ezért külön nem számolja" },
    ["Spearing Strike"] = { reason = ROTATION("Spearing Strike", "WA-008a") },
    ["Two-Handed Weapon Specialization"] = { { key = "twoHandSpec", val = 1, what = "kétkezes fegyver sebzés %" } },
    Impale = { { key = "impale", val = 1, what = "képességek crit-sebzés bónusz %" } },
    Bloodthrill = { reason = ROTATION("Overpower", "WA-008a") },
    ["Sweeping Strikes"] = { reason = MULTI },
    Weaponmaster = { { key = "weaponmaster", val = 3, what = "extra támadás esély % (kard)" },
      partial = "a fejsze/polearm crit része és a buzogány/bot páncéltörése nincs a modellben" },
    ["Improved Slam"] = { reason = ROTATION("Slam", "WA-008a") },
    ["Improved Hamstring"] = { reason = UTILITY },
    ["Mortal Strike"] = { reason = "a fegyveres specialok között a harcaidból méri (gyakoriság és sebzés); külön a rotációs ticketben jön (WA-008a)" },
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
    Bastion = { { key = "bastion", val = 1, what = "sebzés % pajzzsal" } },
    ["Shield Slam"] = { reason = ROTATION("Shield Slam", "WA-024") },
    -- Fury
    ["Booming Voice"] = { reason = RAGE },
    Cruelty = { { key = "cruelty", val = 1, what = "crit %" }, sheet = "a játék karakterlapja (GetCritChance) már tartalmazza" },
    ["Lingering Rage"] = { reason = RAGE },
    ["Unbridled Wrath"] = { reason = RAGE },
    ["Furious Precision"] = { { key = "ohHit", val = 1, what = "off-hand hit %" } },
    ["Piercing Howl"] = { reason = UTILITY },
    ["Blood Craze"] = { reason = SURVIVAL },
    Enrage = { reason = "a kapott ütésektől függ: hogy milyen gyakran ütnek meg, az a harcadatból még nem jön" },
    ["Dual Wield Specialization"] = { { key = "dualWield", val = 1, what = "off-hand sebzés %" }, partial = "az off-hand rage része (a rage-et a modell nem szimulálja)" },
    ["Reckless Swings"] = { reason = RAGE },
    ["Improved Execute"] = { reason = RAGE },
    ["Improved Berserker Rage"] = { reason = RAGE },
    ["Death Wish"] = { reason = COOLDOWN("WA-008b") },
    ["Gore Drinker"] = { reason = SURVIVAL },
    ["Improved Intercept"] = { reason = UTILITY },
    ["Improved Whirlwind"] = { reason = ROTATION("Whirlwind (a fegyveres specialok között, együtt mérve)", "WA-008b") },
    Flurry = { { key = "flurry", val = 1, what = "támadási sebesség % a crit utáni 3 ütésre" } },
    Bloodthirst = { reason = "a harcaidból méri (egyéb források); külön a rotációs ticketben jön (WA-008b)" },
  },
  -- Mage (WA-032c): the main nuke (Frostbolt or Fireball) and the wand, the rest measured (Mage.lua).
  MAGE = {
    -- Fire
    Incineration = { reason = ROTATION("Fire Blast, Scorch, Ice Lance és Arcane Blast", "WA-009b") },
    Accelerant = { { key = "accelerant", val = 1, what = "Fireball cast idő − mp" } },
    Ignite = { { key = "ignite", val = 1, what = "tűz crit sebzésének %-a égésként" } },
    ["Flame Throwing"] = { reason = UTILITY },
    Impact = { reason = UTILITY },
    ["Burning Soul"] = { reason = UTILITY },
    ["Improved Flamestrike"] = { reason = MULTI },
    Pyroblast = { reason = ROTATION("Pyroblast", "WA-009b") },
    ["Improved Fire Blast"] = { reason = ROTATION("Fire Blast", "WA-009b") },
    ["Improved Scorch"] = { reason = ROTATION("Scorch (a sebezhetőség a Scorch használatától függ)", "WA-009b") },
    ["Improved Fire Ward"] = { reason = SURVIVAL },
    ["Heating Up"] = { reason = ROTATION("Pyroblast", "WA-009b") },
    ["Master of Elements"] = { reason = MANA },
    ["Critical Mass"] = { { key = "critMass", val = 1, what = "tűz spell crit %" } },
    ["Blast Wave"] = { reason = MULTI },
    ["Fire Power"] = { reason = "a célponton lévő tűzhatások számától függ: ezt a harcadat még nem adja" },
    Combustion = { reason = COOLDOWN("WA-009b") },
    -- Frost
    ["Frost Warding"] = { reason = SURVIVAL },
    ["Improved Frostbolt"] = { { key = "impFrostbolt", val = 1, what = "Frostbolt cast idő − mp" } },
    Precision = { { key = "precision", val = 1, what = "spell hit %" }, sheet = "a játék karakterlapja (GetSpellHitModifier) adja; harcnapló mellett a mért miss számít" },
    ["Ice Shards"] = { { key = "iceShards", val = 1, what = "fagy crit-sebzés bónusz %" } },
    Frostbite = { reason = UTILITY },
    ["Improved Frost Nova"] = { reason = UTILITY },
    Permafrost = { reason = UTILITY },
    ["Frost Channeling"] = { reason = MANA },
    ["Improved Blizzard"] = { reason = MULTI },
    ["Ice Lance"] = { reason = ROTATION("Ice Lance", "WA-009c") },
    ["Arctic Reach"] = { reason = UTILITY },
    ["Ice Block"] = { reason = SURVIVAL },
    Shatter = { reason = ROTATION("fagyott célpont (Frost Nova, Frostbite)", "WA-009c") },
    ["Improved Cone of Cold"] = { reason = MULTI },
    ["Cold Snap"] = { reason = COOLDOWN("WA-009c") },
    ["Fingers of Frost"] = { reason = ROTATION("fagyott célpont (Fingers of Frost)", "WA-009c") },
    ["Winter's Chill"] = { reason = ROTATION("Cone of Cold", "WA-009c") },
    ["Ice Barrier"] = { reason = COOLDOWN("WA-009c") },
    -- Arcane
    ["Wand Specialization"] = { { key = "wandSpec", val = 1, what = "pálca sebzés %" } },
    ["Improved Channeling"] = { reason = UTILITY },
    ["Arcane Resilience"] = { reason = SURVIVAL },
    ["Arcane Subtlety"] = { reason = RESIST },
    ["Magic Absorption"] = { reason = SURVIVAL },
    ["Arcane Concentration"] = { reason = MANA },
    ["Missile Barrage"] = { reason = ROTATION("Arcane Missiles", "WA-009a") },
    ["Arcane Geometry"] = { reason = UTILITY },
    ["Arcane Impact"] = { reason = ROTATION("arcane varázslatok (Arcane Missiles, Arcane Blast)", "WA-009a") },
    ["Arcane Blast"] = { reason = ROTATION("Arcane Blast", "WA-009a") },
    ["Arcane Shielding"] = { reason = SURVIVAL },
    ["Improved Counterspell"] = { reason = UTILITY },
    ["Arcane Meditation"] = { reason = MANA },
    ["Arcane Wrath"] = { reason = ROTATION("Arcane Wrath", "WA-009a") },
    ["Presence of Mind"] = { reason = COOLDOWN("WA-009a") },
    ["Arcane Mind"] = { { key = "arcaneMind", val = 1, what = "intellect %" }, partial = "az arcane crit-bónusz része (az arcane varázslatok még nincsenek külön a modellben)" },
    ["Arcane Instability"] = { { key = "instability", val = 1, what = "spell sebzés %" },
      partial = "a crit része a karakterlapon (GetSpellCritChance) már benne van" },
    ["Arcane Power"] = { reason = COOLDOWN("WA-009a") },
  },
  -- Warlock (WA-032d): direct spells, DoTs and drains, the demon and the wand (Warlock.lua); the
  -- school talents work on the share of each school in your own fights.
  WARLOCK = {
    -- Destruction
    ["Destructive Reach"] = { reason = UTILITY },
    ["Improved Shadow Bolt"] = { reason = "a Shadow Bolt critjeitől és a 12 mp-es időtartamtól függ; hogy mennyi ideig van fent, az aura-idővonalból jön (WA-005)" },
    Bane = { reason = "a direkt varázslatok gyakoriságát a modell a harcaidból méri; a cast idő a rotációs ticketben jön (WA-010c)" },
    ["Molten Skin"] = { reason = SURVIVAL },
    Cataclysm = { reason = MANA },
    Aftermath = { { key = "aftermath", val = 1, what = "Immolate kezdő sebzés %" }, partial = "a Conflagrate lassítása (irányítás)" },
    Ruin = { { key = "ruin", val = 1, what = "Destruction varázslatok crit-bónusz %" } },
    Shadowburn = { reason = ROTATION("Shadowburn", "WA-010c") },
    Intensity = { reason = UTILITY },
    ["Agonizing Flames"] = { { key = "agonizing", val = 2, what = "Destruction varázslatok sebzés %" }, partial = "a Searing Pain crit része" },
    Conflagrate = { reason = ROTATION("Conflagrate", "WA-010c") },
    Pyroclasm = { reason = UTILITY },
    ["Bane of Havoc"] = { reason = MULTI },
    ["Fire and Brimstone"] = { reason = ROTATION("Conflagrate", "WA-010c") },
    ["Shadow and Flame"] = { reason = ROTATION("Conflagrate és Shadowburn", "WA-010c") },
    Incinerate = { reason = ROTATION("Incinerate", "WA-010c") },
    -- Affliction
    ["Improved Life Tap"] = { reason = MANA },
    Suppression = { { key = "suppression", val = 1, what = "hit %" }, sheet = "a játék karakterlapja (GetSpellHitModifier) adja; harcnapló mellett a mért miss számít" },
    ["Improved Corruption"] = { { key = "impCorruption", val = 2, what = "Corruption sebzés %" }, partial = "a cast idő része (a DoT-okat a modell a harcaidból méri)" },
    ["Grim Reach"] = { reason = UTILITY },
    ["Soul Harvest"] = { reason = MANA },
    ["Improved Drains"] = { { key = "impDrains", val = 1, what = "drain sebzés %" } },
    ["Improved Bane of Agony"] = { { key = "impAgony", val = 1, what = "Bane of Agony sebzés %" } },
    ["Fel Concentration"] = { reason = UTILITY },
    ["Amplify Curse"] = { reason = COOLDOWN("WA-010a") },
    Pandemic = { reason = "a DoT-ok critjét a modell külön nem számolja (a mért DoT-sebzésben benne van); a rotációs ticketben jön (WA-010a)" },
    Malevolence = { { key = "malevolence", val = 1, what = "árnyék crit %" } },
    Nightfall = { reason = ROTATION("Shadow Trance (Nightfall)", "WA-010a") },
    ["Curse of Exhaustion"] = { reason = UTILITY },
    ["Siphon Life"] = { reason = "a DoT-ok között a harcaidból méri; külön a rotációs ticketben jön (WA-010a)" },
    ["Soul Siphon"] = { reason = "a célponton lévő DoT-ok számától függ: ezt az aura-idővonal adja majd (WA-005)" },
    ["Shadow Mastery"] = { { key = "shadowMastery", val = 1, what = "árnyék varázslatok sebzés %" } },
    Wrack = { reason = ROTATION("Wrack", "WA-010a") },
    -- Demonology
    ["Improved Health Funnel"] = { reason = SURVIVAL },
    ["Improved Imp"] = { reason = DEMON },
    ["Demonic Embrace"] = { reason = SURVIVAL },
    ["Unholy Power"] = { { key = "unholyPower", val = 1, what = "démon sebzés %" } },
    ["Demonic Aegis"] = { reason = SURVIVAL },
    ["Improved Voidwalker"] = { reason = DEMON },
    ["Fel Vitality"] = { reason = MANA },
    ["Demonic Energies"] = { reason = MANA },
    ["Improved Sayaad"] = { reason = DEMON },
    ["Demonic Sacrifice"] = { reason = "attól függ, melyik démont áldozod fel; hogy fent van-e, az aura-idővonalból jön (WA-005)" },
    ["Master Summoner"] = { reason = UTILITY },
    Decimation = { reason = ROTATION("Soul Fire és a 35% alatti szakasz", "WA-010b") },
    ["Fel Domination"] = { reason = UTILITY },
    ["Demonic Brand"] = { reason = DEMON },
    ["Improved Felhunter"] = { reason = DEMON },
    ["Soul Link"] = { reason = "aktiválni kell; hogy fent van-e, az aura-idővonalból jön (WA-005)" },
    ["Demonic Knowledge"] = { { key = "demonicKnowledge", val = 1, what = "a szinted %-a spell powerként" },
      sheet = "a játék spell powere (GetSpellBonusDamage) már tartalmazza, amíg a démon kint van" },
    ["Master Demonologist"] = { reason = DEMON },
    ["Demonic Pact"] = { reason = "a Demonic Sacrifice-tól függ (aura-idővonal, WA-005)" },
  },
  -- Rogue (WA-032a): the model is Sinister Strike + Eviscerate with white swings (Model.lua); every
  -- talent of the three trees is either counted in it or has its reason.
  ROGUE = {
    -- Combat
    ["Coup de Grace"] = { { key = "coup", val = 1, what = "Eviscerate sebzés %" }, partial = "a Death Mark része nincs a modellben" },
    ["Efficient Strikes"] = { { key = "efficient", val = 1, what = "Sinister Strike energiaköltség −" } },
    ["Lightning Reflexes"] = { reason = SURVIVAL },
    ["Puncturing Wounds"] = { reason = ROTATION("Backstab és a Mutilate", "WA-007a, WA-007c") },
    Deflection = { reason = SURVIVAL },
    Precision = { { key = "precision", val = 1, what = "hit %" }, sheet = "a játék karakterlapja (GetHitModifier) már tartalmazza" },
    ["Improved Sprint"] = { reason = UTILITY },
    Endurance = { reason = UTILITY },
    Riposte = { reason = ROTATION("Riposte (parry után)", "WA-007b") },
    Composure = { reason = ROTATION("Poised", "WA-007b") },
    ["Improved Kick"] = { reason = UTILITY },
    ["Flawless Execution"] = { { key = "flawless", val = 1, what = "Eviscerate energiaköltség −" } },
    ["Weapon Expertise"] = { { key = "expertise", val = 1, what = "dodge és parry esély −%" } },
    Aggression = { { key = "aggression", val = 1, what = "Sinister Strike és Eviscerate sebzés %" } },
    ["Dual Wield Specialization"] = { { key = "dualWield", val = 1, what = "off-hand sebzés %" } },
    ["Blade Flurry"] = { reason = COOLDOWN("WA-007b") },
    ["Hack and Slash"] = { { key = "hackSlash", val = 1, what = "extra támadás esély % (fejsze, kard)" },
      partial = "a dagger/ököl crit része és a buzogány páncéltörése nincs a modellben" },
    ["Flash of Steel"] = { reason = ROTATION("Shank", "WA-007b") },
    ["Adrenaline Rush"] = { reason = COOLDOWN("WA-007b") },
    -- Assassination
    ["Improved Gouge"] = { reason = UTILITY },
    ["Remorseless Attacks"] = { reason = "ölés utáni hatás: hogy hány ellenfelet öltél, az a harcadatból még nem jön" },
    Malice = { { key = "malice", val = 1, what = "crit %" }, sheet = "a játék karakterlapja (GetCritChance) már tartalmazza" },
    Ruthlessness = { { key = "ruthlessness", val = 1, what = "finisher utáni combo pont esély %" } },
    ["Improved Expose Armor"] = { reason = ROTATION("Expose Armor", "WA-007a") },
    ["Improved Slice and Dice"] = { reason = ROTATION("Slice and Dice", "WA-007a, WA-007b") },
    Vigor = { reason = "csak a maximális energiát emeli; a tartós sebzést ebben a modellben nem változtatja" },
    ["Blood Splatter"] = { reason = ROTATION("Rupture és a Garrote", "WA-007a") },
    Lethality = { { key = "lethality", val = 1, what = "Sinister Strike crit-sebzés bónusz %" } },
    ["Vile Poisons"] = { reason = POISON },
    ["Cold Blood"] = { reason = COOLDOWN("WA-007a") },
    ["Improved Poisons"] = { reason = POISON },
    ["Relentless Strikes"] = { { key = "relentless", val = 1, what = "finisher combo pontonként esély %" },
      { key = "relentlessEnergy", val = 2, what = "visszakapott energia" } },
    Venom = { reason = ROTATION("Shank", "WA-007a") },
    ["Improved Kidney Shot"] = { reason = ROTATION("Kidney Shot", "WA-007a") },
    ["Seal Fate"] = { { key = "sealFate", val = 1, what = "crit utáni extra combo pont esély %" } },
    Mutilate = { reason = ROTATION("Mutilate", "WA-007a") },
    -- Subtlety
    Setup = { reason = SURVIVAL },
    ["Master of Deception"] = { reason = UTILITY },
    Opportunity = { reason = ROTATION("Backstab, a Garrote, az Ambush és a Mutilate", "WA-007c") },
    ["Dirty Deeds"] = { reason = ROTATION("nyitás (Cheap Shot, Garrote)", "WA-007c") },
    Camouflage = { reason = UTILITY },
    ["Improved Ambush"] = { reason = ROTATION("Ambush", "WA-007c") },
    ["Dirty Tricks"] = { reason = UTILITY },
    Initiative = { reason = ROTATION("nyitás (Ambush, Garrote, Cheap Shot)", "WA-007c") },
    Premeditation = { reason = ROTATION("nyitás", "WA-007c") },
    ["Serrated Blades"] = { reason = "páncéltörés és Rupture: a modell nem számol a célpont páncéljával, és Rupture sincs benne (WA-007c)" },
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
    ["Deadly Aspects"] = { reason = "a gyorsító proc fenntartási ideje az aura-idővonalból jön (WA-005)" },
    ["Endurance Training"] = { reason = SURVIVAL },
    ["Focused Fire"] = { { key = "focusedFire", val = 1, what = "minden sebzés % pettel" } },
    ["Improved Aspect of the Monkey"] = { reason = SURVIVAL },
    ["Improved Revive Pet"] = { reason = UTILITY },
    Pathfinding = { reason = UTILITY },
    ["Bestial Swiftness"] = { reason = UTILITY },
    ["Unleashed Fury"] = { { key = "unleashedFury", val = 1, what = "pet sebzés %" } },
    ["Improved Mend Pet"] = { reason = UTILITY },
    Ferocity = { reason = PET },
    ["Summon Hawk"] = { reason = ROTATION("Summon Hawk", "WA-011a") },
    ["Spirit Bond"] = { reason = SURVIVAL },
    Intimidation = { reason = UTILITY },
    ["Bestial Discipline"] = { reason = MANA },
    Frenzy = { reason = PET },
    ["Bestial Wrath"] = { reason = COOLDOWN("WA-011a") },
    -- Survival
    ["Improved Tracking"] = { reason = "attól függ, mit követsz (tracking) és milyen típusú a célpont" },
    Deflection = { reason = SURVIVAL },
    Entrapment = { reason = UTILITY },
    ["Savage Strikes"] = { { key = "savageStrikes", val = 1, what = "közelharci képességek crit %" } },
    Survivalist = { reason = SURVIVAL },
    ["Improved Wing Clip"] = { reason = UTILITY },
    ["Clever Traps"] = { reason = ROTATION("csapdák", "WA-011c") },
    Surefooted = { { key = "surefooted", val = 1, what = "hit %" }, sheet = "a játék karakterlapja (GetHitModifier) már tartalmazza", partial = "a lassítás rövidítése (mozgás)" },
    Deterrence = { reason = SURVIVAL },
    ["Survival Tactics"] = { reason = UTILITY },
    ["Predator's Edge"] = { { key = "predatorCrit", val = 1, what = "közelharci képességek crit-sebzés %" },
      { key = "predatorOh", val = 2, what = "off-hand sebzés %" } },
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
    ["Lethal Attacks"] = { { key = "lethal", val = 1, what = "crit %" }, sheet = "a játék karakterlapja (GetRangedCritChance) már tartalmazza" },
    ["Improved Stings"] = { { key = "impStings", val = 1, what = "Serpent Sting sebzés %" }, partial = "a Viper és a Scorpid Sting része" },
    Efficiency = { reason = MANA },
    ["Careful Aim"] = { { key = "carefulAim", val = 1, what = "intellect %-a attack powerként" } },
    ["Rapid Killing"] = { reason = "ölés utáni hatás és Rapid Fire cooldown: az ölések száma a harcadatból még nem jön" },
    ["Improved Arcane Shot"] = { reason = "az Arcane Shot gyakoriságát a modell a harcaidból méri; a cooldown a rotációs ticketben jön (WA-011b)" },
    ["Lone Wolf"] = { { key = "loneWolf", val = 1, what = "minden sebzés % pet nélkül" } },
    ["Trueshot Aura"] = { { key = "trueshot", val = 2, what = "ranged attack power" }, sheet = "a játék ranged attack powere már tartalmazza, amíg az aura fent van" },
    ["Mortal Shots"] = { { key = "mortal", val = 1, what = "távolsági crit-sebzés bónusz %" } },
    ["Rapid Recuperation"] = { reason = MANA },
    Barrage = { { key = "barrage", val = 1, what = "Multi-Shot és Aimed Shot sebzés %" } },
    ["Scatter Shot"] = { reason = UTILITY },
    ["Ranged Weapon Specialization"] = { { key = "rangedSpec", val = 1, what = "távolsági fegyveres sebzés %" } },
    ["Sniper Shot"] = { reason = ROTATION("Sniper Shot", "WA-011b") },
  },
  -- Shaman (WA-032f): melee with an imbue, Stormstrike, shocks, Lightning Bolt and totems
  -- (Shaman.lua); healing talents go to the healer model.
  SHAMAN = {
    -- Elemental
    Convection = { reason = MANA },
    Concussion = { { key = "concussion", val = 1, what = "Lightning Bolt és Earth Shock sebzés %" }, partial = "a Chain Lightning része (több célpont)" },
    ["Elemental Devastation"] = { reason = "a közelharci crit-proc fenntartási ideje az aura-idővonalból jön (WA-005)" },
    Reverberation = { reason = "a shockok gyakoriságát a modell a harcaidból méri; a rövidebb cooldown a rotációs ticketben jön (WA-012a)" },
    ["Elemental Alacrity"] = { reason = "a Lightning Bolt gyakoriságát a modell a harcaidból méri; a rövidebb cast idő a rotációs ticketben jön (WA-012a)" },
    ["Call of Flame"] = { { key = "callFlame", val = 1, what = "tűztotemek és Flame Shock sebzés %" }, partial = "a Fire Nova (több célpont) és a hosszabb Flame Shock" },
    ["Elemental Focus"] = { reason = MANA },
    ["Elemental Warding"] = { reason = SURVIVAL },
    ["Trial by Fire"] = { reason = MULTI },
    ["Eye of the Storm"] = { reason = "a cast-visszalökés (pushback) ellen véd: a modell nem számol azzal, hogy ütnek cast közben" },
    Earthbound = { reason = UTILITY },
    ["Elemental Reach"] = { reason = UTILITY },
    ["Call of Thunder"] = { { key = "callThunder", val = 1, what = "Lightning Bolt crit %" }, partial = "a Chain Lightning része (több célpont)" },
    ["Lightning Overload"] = { { key = "overload", val = 1, what = "% esély egy második, fél sebzésű Lightning Boltra" }, partial = "a Chain Lightning része (több célpont)" },
    ["Elemental Fury"] = { { key = "fury", val = 1, what = "spell crit-sebzés bónusz %" }, partial = "a Searing és a Magma Totem critje (a totemek sebzését a modell a harcaidból méri)" },
    ["Lightning Mastery"] = { reason = COOLDOWN("WA-012a") },
    -- Restoration
    ["Improved Healing Wave"] = { reason = HEAL },
    ["Tidal Focus"] = { { key = "tidalHit", val = 2, what = "hit %" }, sheet = "a játék hit-módosítói (GetHitModifier, GetSpellHitModifier) már tartalmazzák", partial = "a gyógyítás mana-költsége" },
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
    ["Thundering Strikes"] = { { key = "thundering", val = 1, what = "crit %" }, sheet = "a játék közelharci és spell critje már tartalmazza" },
    ["Ancestral Knowledge"] = { { key = "ancestral", val = 1, what = "intellect %" } },
    ["Guardian Totems"] = { reason = SURVIVAL },
    ["Mental Dexterity"] = { { key = "mentalDex", val = 1, what = "intellect %-a attack powerként" }, sheet = "a játék attack powere már tartalmazza; a tárgyak intellectjét a modell attack powerként is számolja" },
    ["Improved Lightning Shield"] = { reason = "a Lightning Shield sebzését a modell a harcaidból méri (egyéb források), külön nem számolja" },
    ["Elemental Weapons"] = { { key = "elemRockbiter", val = 1, what = "Rockbiter AP %" },
      { key = "elemWindfury", val = 2, what = "Windfury %" }, { key = "elemFlametongue", val = 3, what = "Flametongue/Frostbrand sebzés %" } },
    ["Shamanistic Focus"] = { reason = MANA },
    Anticipation = { reason = SURVIVAL },
    Toughness = { reason = SURVIVAL },
    Flurry = { { key = "flurry", val = 1, what = "támadási sebesség % a crit utáni 3 ütésre" } },
    Stormstrike = { { key = "stormstrike", val = "rank", what = "képesség" } },
    ["Improved Ghost Wolf"] = { reason = UTILITY },
    ["Spirit Weapons"] = { reason = THREAT },
    ["Mental Quickness"] = { { key = "mentalQuick", val = 1, what = "intellect %-a spell powerként" }, sheet = "a modell a játék spell powerét használja; a tárgyak intellectjét spell powerként is számolja" },
    ["Improved Stormstrike"] = { reason = "a Stormstrike gyakoriságát a modell a harcaidból méri; a mana és a cooldown visszaállása a rotációs ticketben jön (WA-012b)" },
    ["Maelstrom Weapon"] = { reason = ROTATION("Maelstrom Weapon (rövidebb Lightning Bolt)", "WA-012b") },
    ["Rage of the Farseer"] = { reason = COOLDOWN("WA-012b") },
    -- Classic only (Forever's trees do not have it): the two-hand gate in Shaman.lua
    ["Two-Handed Axes and Maces"] = { { key = "twoHand", val = "rank", what = "kétkezes fejsze és buzogány" } },
  },
}

-- The model's talent input from the client's ranks ({ { name, tab, rank, max } }, every tab):
--   out[key]  = the value (0 when the talent has no points)
--   out.ranks = { [name] = rank } of every talent, out.read = the client gave talents
--   out.absent = { [name] = true }: talents the model knows but Forever's trees do not have
--   out.status = { { name, rank, max, counted, values = { { key, value, what } }, source, reason } }
--                for every talent with points: counted (with the rank's text as the source) or why not
function T.Effects(class, ranks)
  local eff = T.EFFECTS[class or ""] or {}
  local data = T.Data(class)
  local out = { ranks = {}, status = {}, absent = {}, counted = 0, uncounted = 0, read = (#(ranks or {}) > 0) or nil }
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
        st.reason = "nincs a Wowhead Forever adatában"
      elseif not list then
        st.reason = ("a modell még nem számol vele (%s)"):format(T.TICKET[class or ""] or "WA-032")
      elseif list.reason then
        st.reason = list.reason
      elseif not data then
        st.reason = "a talentadat (TalentData.lua) hiányzik"
      elseif r.max and r.max > 0 and r.max ~= d.max then
        st.reason = ("a játék %d, az adat %d rangot ismer"):format(r.max, d.max)
      else
        local vals = d.vals and d.vals[math.min(r.rank, d.max)] or {}
        local got = {}
        for _, x in ipairs(list) do
          local v = x.val == "rank" and r.rank or vals[x.val]
          if v == nil then st.reason = "a rang szövegében nincs meg a szám" break end
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

local function Report()
  local class = WA.Game and WA.Game.Class and WA.Game.Class() or select(2, UnitClass("player"))
  local tree = T.ReadTree()
  local data = T.Data(class)
  if #tree.tabs == 0 then
    WA.Print("A játék nem adott talentfát (a kliens talent-API-ja nem elérhető).")
    return
  end
  local m = T.Match(tree, data)
  WA.Print(("Talentek: %d elköltött pont%s, %d. szint."):format(tree.spent,
    tree.unspent and (", " .. tree.unspent .. " szabad") or "", tree.level))
  for tab, t in ipairs(tree.tabs) do
    local x = m.tabs[tab]
    local where = ""
    if data and x and x.count > 0 then
      where = x.tree and (" · Wowhead Forever: %s fa, %d/%d talent egyezik"):format(x.tree.name, x.matched, x.count)
        or (" · a Wowhead Forever adatában nincs meg (%d talent)"):format(x.count)
    end
    WA.Print(("  %d. %s: %d pont%s"):format(tab, t.name, t.points, where))
    if x then
      for i = 1, math.min(5, #x.missing) do WA.Print("    nincs az adatban: " .. x.missing[i]) end
      for i = 1, math.min(5, #x.differs) do WA.Print("    eltér: " .. x.differs[i]) end
    end
  end
  -- what the model does with them: the counted talents with their numbers, the rest with the reason
  local ranks = {}
  for tab, t in ipairs(tree.tabs) do
    for _, x in ipairs(t.talents) do ranks[#ranks + 1] = { name = x.name, tab = tab, rank = x.rank, max = x.max } end
  end
  local e = T.Effects(class, ranks)
  if #e.status > 0 then
    WA.Print(("A modell számolt talentjei: %d, még nem számolt: %d."):format(e.counted, e.uncounted))
    for _, st in ipairs(e.status) do
      if st.counted then
        local bits = {}
        for _, v in ipairs(st.values) do bits[#bits + 1] = ("%s %s"):format(v.what, tostring(v.value)) end
        local note = st.sheet and (" (" .. st.sheet .. ")") or ""
        if st.partial then note = note .. "; nem számolt: " .. st.partial end
        WA.Print(("    számolt: %s %d/%d · %s%s"):format(st.name, st.rank, st.max or st.rank, table.concat(bits, ", "), note))
      end
    end
    local shown = 0
    for _, st in ipairs(e.status) do
      if not st.counted and shown < 5 then
        shown = shown + 1
        WA.Print(("    nem számolt: %s · %s"):format(st.name, st.reason))
      end
    end
    if e.uncounted > shown then WA.Print(("    … és még %d nem számolt talent"):format(e.uncounted - shown)) end
  end
  if not data then
    WA.Print("A talentadat (TalentData.lua) hiányzik: node scripts/build-talents.mjs --install")
  else
    WA.Print(("Adat: Wowhead Forever talent-kalkulátor, letöltve %s."):format(_G.WowAssistantTalents.fetched or "?"))
  end
end
T.Report = Report

if WA.Command then WA.Command("talent", Report, "/wa talent – a talentfáid, a pontjaid, és hogy a Wowhead Forever adata egyezik-e a játékkal") end
