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
  HUNTER = {
    ["Lethal Attacks"] = { { key = "lethal", val = 1, what = "crit %" } },
    ["Mortal Shots"] = { { key = "mortal", val = 1, what = "távolsági crit-sebzés bónusz %" } },
    ["Lightning Reflexes"] = { { key = "reflexes", val = 1, what = "agility %" } },
  },
  SHAMAN = {
    Flurry = { { key = "flurry", val = 1, what = "támadási sebesség % a crit utáni 3 ütésre" } },
    ["Thundering Strikes"] = { { key = "thundering", val = 1, what = "crit %" } },
    ["Elemental Fury"] = { { key = "fury", val = 1, what = "spell crit-sebzés bónusz %" } },
    ["Elemental Weapons"] = { { key = "elemRockbiter", val = 1, what = "Rockbiter AP %" },
      { key = "elemWindfury", val = 2, what = "Windfury %" }, { key = "elemFlametongue", val = 3, what = "Flametongue/Frostbrand sebzés %" } },
    Stormstrike = { { key = "stormstrike", val = "rank", what = "képesség" } },
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
