-- WoW Assistant: what the game client knows, in the shape the engines (Model, Routes, Plan,
-- Combat) take. The web app gets the same facts from the Blizzard API and the uploads; here they
-- are read live, so the windows are up to date without /reload.

local _, WA = ...
local G = {}
WA.Game = G
local M = WA.Model

local QUALITY = { [0] = "POOR", "COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY" }
G.QUALITY = QUALITY
local SCAN_FRESH = 12 * 3600 -- the web app uses in-game scans younger than 12 hours

local function R() return WowAssistantRecipes end

---------------------------------------------------------------------------
-- items
---------------------------------------------------------------------------
local requested = {}
local function Request(id)
  if not requested[id] and C_Item and C_Item.RequestLoadItemDataByID then
    requested[id] = true
    pcall(C_Item.RequestLoadItemDataByID, id)
  end
end

function G.ItemName(id)
  local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or GetItemInfo(id)
  if not name then Request(id) end
  return name or (R() and R().names[id]) or ("Item #" .. id)
end

-- Vendor price of one piece: the client's own value when the item is loaded.
function G.SellPrice(id)
  local sell = select(11, GetItemInfo(id))
  if sell then return sell end
  Request(id)
  return R() and R().sell[id] or 0
end

local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats

-- A piece of gear as the plan sees it (GearItem), or nil when it is not loaded yet or not gear.
local gearCache = {}
function G.GearItem(idOrLink)
  local cached = gearCache[idOrLink]
  if cached ~= nil then return cached or nil end
  local name, link, quality, ilvl, minLevel, _, _, _, equipLoc, _, _, classID, subID = GetItemInfo(idOrLink)
  if not name then
    if type(idOrLink) == "number" then Request(idOrLink) end
    return nil
  end
  local item = false
  if equipLoc and equipLoc ~= "" and (classID == 2 or classID == 4) then
    local st = getStats and getStats(link) or nil
    local dmg = classID == 2 and WA.WeaponNumbers and WA.WeaponNumbers(link) or nil
    item = {
      itemId = tonumber(link:match("item:(%d+)")) or idOrLink, name = name, slot = equipLoc:gsub("^INVTYPE_", ""),
      itemClass = classID, subclass = subID, reqLevel = minLevel or 0, itemLevel = ilvl or 0,
      quality = QUALITY[quality or 1] or "COMMON", stats = M.GameStats(st, dmg),
    }
    if not M.Usable(G.Class(), item) then item = false end
  end
  gearCache[idOrLink] = item
  return item or nil
end

---------------------------------------------------------------------------
-- character
---------------------------------------------------------------------------
-- Blizzard slot names (as in the web app) -> inventory slot ids.
G.SLOTS = {
  { "HEAD", 1 }, { "NECK", 2 }, { "SHOULDER", 3 }, { "BACK", 15 }, { "CHEST", 5 }, { "WRIST", 9 }, { "HANDS", 10 },
  { "WAIST", 6 }, { "LEGS", 7 }, { "FEET", 8 }, { "FINGER_1", 11 }, { "FINGER_2", 12 }, { "TRINKET_1", 13 },
  { "TRINKET_2", 14 }, { "MAIN_HAND", 16 }, { "OFF_HAND", 17 }, { "RANGED", 18 },
}

function G.Equipped()
  local equipped, order = {}, {}
  for _, s in ipairs(G.SLOTS) do
    local link = GetInventoryItemLink("player", s[2])
    if link then
      local id = tonumber(link:match("item:(%d+)"))
      local st = getStats and getStats(link) or nil
      local dmg = (s[1] == "MAIN_HAND" or s[1] == "OFF_HAND" or s[1] == "RANGED") and WA.WeaponNumbers and WA.WeaponNumbers(link) or nil
      local sub, classID, equipLoc
      if GetItemInfoInstant then
        local _, _, _, loc, _, cls, sc = GetItemInfoInstant(link)
        sub, classID, equipLoc = sc, cls, loc
      end
      -- the enchant on it: the second field of the item link (item:id:enchant:...), 0 or empty when none
      local enchant = tonumber(link:match("item:%d+:(%d*)") or "")
      equipped[s[1]] = { id = id, name = (GetItemInfo(link)) or link:match("%[(.-)%]") or ("Item #" .. tostring(id)), stats = M.GameStats(st, dmg),
        link = link, sub = sub, item = { classID = classID, sub = sub, equipLoc = equipLoc },
        enchant = enchant and enchant > 0 and enchant or nil }
      order[#order + 1] = s[1]
    end
  end
  return equipped, order
end

-- Talent values the model uses. The ranks come from the talent API; the numbers from the
-- talent's tooltip with the same patterns the web app applies to the Blizzard text.
local scanTip
local function TalentText(tab, index)
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "WowAssistantScanTip", UIParent, "GameTooltipTemplate")
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  end
  scanTip:ClearLines()
  if not pcall(scanTip.SetTalent, scanTip, tab, index) then return "" end
  local parts = {}
  for i = 1, scanTip:NumLines() do
    local line = _G["WowAssistantScanTipTextLeft" .. i]
    local t = line and line:GetText()
    if t then parts[#parts + 1] = t end
  end
  return table.concat(parts, " ")
end

-- Hunter talents by rank: Lethal Shots +1% ranged crit, Mortal Shots +6% crit damage bonus,
-- Lightning Reflexes +3% agility per rank.
local HUNTER_TALENTS = { ["Lethal Shots"] = { "lethal", 1 }, ["Mortal Shots"] = { "mortal", 6 }, ["Lightning Reflexes"] = { "reflexes", 3 } }
-- shaman: ranks as they are (Shaman.lua turns them into numbers); read = the talents were scanned
local SHAMAN_TALENTS = { Flurry = { "flurry", 1 }, ["Thundering Strikes"] = { "thundering", 1 }, ["Elemental Fury"] = { "fury", 1 },
  ["Two-Handed Axes and Maces"] = { "twoHand", 1 }, ["Elemental Weapons"] = { "elemWeapons", 1 }, Stormstrike = { "stormstrike", 1 } }
local CLASS_TALENTS = { HUNTER = HUNTER_TALENTS, SHAMAN = SHAMAN_TALENTS }

-- The talent tab with the most points (1-3), nil before the first talent point.
function G.MainTalentTab()
  if not GetNumTalentTabs then return nil end
  local best, bestPts = nil, 0
  for tab = 1, GetNumTalentTabs() do
    local pts = 0
    for i = 1, (GetNumTalents and GetNumTalents(tab) or 0) do
      local _, _, _, _, rank = GetTalentInfo(tab, i)
      pts = pts + (tonumber(rank) or 0)
    end
    if pts > bestPts then best, bestPts = tab, pts end
  end
  return best, bestPts
end

function G.Talents()
  local out = { malice = 0, efficient = 0, coup = 0, lethal = 0, mortal = 0, reflexes = 0 }
  if not GetNumTalentTabs then return out end
  local map = CLASS_TALENTS[G.Class() or ""]
  if map then
    for tab = 1, GetNumTalentTabs() do
      for i = 1, (GetNumTalents and GetNumTalents(tab) or 0) do
        local name, _, _, _, rank = GetTalentInfo(tab, i)
        local t = name and map[name]
        if t and rank and rank > 0 then out[t[1]] = rank * t[2] end
        if name then out.read = true end
      end
    end
    return out
  end
  for tab = 1, GetNumTalentTabs() do
    for i = 1, (GetNumTalents and GetNumTalents(tab) or 0) do
      local name, _, _, _, rank = GetTalentInfo(tab, i)
      if rank and rank > 0 and (name == "Malice" or name == "Efficient Strikes" or name == "Coup de Grace") then
        local text = TalentText(tab, i)
        if name == "Malice" then out.malice = tonumber(text:match("by (%d+)%%")) or rank
        elseif name == "Efficient Strikes" then out.efficient = tonumber(text:match("by (%d+)")) or 0
        else out.coup = tonumber(text:match("Eviscerate ability by (%d+)%%")) or 0 end
      end
    end
  end
  return out
end

-- Professions: the skill line API where the client has it, else the profession API.
function G.Professions()
  local byName = {}
  for id, name in pairs(R() and R().professions or {}) do byName[name] = id end
  local out = {}
  if GetNumSkillLines then
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
      if name and not isHeader and byName[name] then out[#out + 1] = { id = byName[name], name = name, skill = rank, cap = maxRank } end
    end
  end
  if #out == 0 and GetProfessions and GetProfessionInfo then
    for _, index in ipairs({ GetProfessions() }) do
      if index then
        local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
        local id = (R() and R().professions[skillLine]) and skillLine or byName[name]
        if id then out[#out + 1] = { id = id, name = R().professions[id] or name, skill = rank or 0, cap = maxRank or 0 } end
      end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  for _, p in ipairs(out) do p.known = WA.charDB and WA.charDB.known[p.id] or {} end
  return out
end

function G.Owned()
  local c = WA.char or {}
  local owned = {}
  for _, src in ipairs({ c.bags or {}, c.bank or {} }) do
    for id, n in pairs(src) do owned[tonumber(id)] = (owned[tonumber(id)] or 0) + n end
  end
  return owned
end

function G.Trainer()
  local rows = {}
  local STATES = { available = true, unavailable = true, used = true }
  for _, t in pairs(WA.char and WA.char.trainer or {}) do
    local state = STATES[t.state] and t.state or (STATES[t.rank] and t.rank or "unavailable")
    rows[#rows + 1] = { name = t.name, required_level = t.level or 0, cost_copper = t.cost or 0, state = state,
      tradeskill = t.tradeskill and 1 or 0 }
  end
  table.sort(rows, function(a, b)
    if a.required_level ~= b.required_level then return a.required_level < b.required_level end
    return a.name < b.name
  end)
  return rows
end

---------------------------------------------------------------------------
-- prices
---------------------------------------------------------------------------
local DEPTH = 40
-- Average price of the cheapest 40 units of an order book (the web app's "depth" price).
local function Depth(b)
  local need, cost = DEPTH, 0
  for i = 1, #b, 3 do
    local take = math.min(need, b[i + 1])
    cost = cost + take * b[i]
    need = need - take
    if need <= 0 then break end
  end
  local bought = DEPTH - need
  return bought > 0 and M.Round(cost / bought) or nil
end
G.Depth = Depth

-- unit(id): vendor price for the reagents vendors sell when cheaper, else the auction depth price
-- (order books of the full scan, refreshed live), else the cheapest unit price of the last scan.
function G.Book()
  local market = WowAssistantDB and WowAssistantDB.market or {}
  local books = market.books or {}
  local prices = WA.char and WA.char.ah and WA.char.ah.prices or {}
  local rd = R() or {}
  local cache = {}
  return {
    unit = function(id)
      local c = cache[id]
      if c ~= nil then return c or nil end
      local auction = books[id] and #books[id] > 0 and Depth(books[id]) or prices[id]
      local vendor = rd.vendorReagents and rd.vendorReagents[id] and rd.vendor[id] or nil
      if vendor and vendor > 0 and (not auction or vendor <= auction) then c = { price = vendor, source = "vendor" }
      elseif auction and auction > 0 then c = { price = auction, source = "AH" }
      else c = false end
      cache[id] = c
      return c or nil
    end,
    vendorSell = G.SellPrice,
    name = G.ItemName,
  }
end

---------------------------------------------------------------------------
-- fights and the model
---------------------------------------------------------------------------
-- Combat-log fights written by the uploader (Fights.lua), plus the ones the damage meter saw in
-- this session that the log does not have yet.
function G.Fights()
  local list = {}
  local fromLog = WowAssistantFights and WA.key and WowAssistantFights[WA.key] or {}
  for _, f in ipairs(fromLog) do list[#list + 1] = f end
  for _, f in ipairs(WA.charDB and WA.charDB.meterFights or {}) do
    local covered = false
    for _, l in ipairs(fromLog) do
      if f.start >= l.start - 5 and f.start <= l.start + l.dur + 5 then covered = true break end
    end
    if not covered then list[#list + 1] = f end
  end
  return list
end

-- Only fights with hit counts calibrate the model (the damage meter may report totals only).
function G.CombatReport(forModel)
  local list = G.Fights()
  if forModel then
    local detailed = {}
    -- log fights always; in-game fights only with hit counts (the damage meter alone has none)
    for _, f in ipairs(list) do if (f.source ~= "meter" and f.source ~= "live") or f.detailed then detailed[#detailed + 1] = f end end
    list = detailed
  end
  return WA.Combat.Report(list)
end

-- "Adds 4.5 damage per second" on an ammo tooltip.
local function AmmoDps(link)
  if not (link and C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return nil end
  local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
  if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
  for _, line in ipairs(data.lines) do
    local t = type(line.leftText) == "string" and line.leftText or ""
    local v = t:match("Adds ([%d%.]+) damage per second")
    if v then return tonumber(v) end
  end
  return nil
end
G.AmmoDps = AmmoDps

-- Spells in the spellbook (Exporter's scan), by name; nil when the book was never read.
local function KnownSpells()
  local list = WA.char and WA.char.spells
  if not list or #list == 0 then return nil end
  local known = {}
  for _, s in ipairs(list) do known[s.name] = true end
  return known
end

function G.Class() return select(2, UnitClass("player")) end
function G.IsRogue() return G.Class() == "ROGUE" end
-- Classes the damage model (and with it the plan and the gear page) knows.
function G.Supported() return M.CLASSES[G.Class() or ""] ~= nil end

function G.ModelInput()
  local equipped, order = G.Equipped()
  local _, agi = UnitStat("player", 2)
  local _, str = UnitStat("player", 1)
  local base, pos, neg = UnitAttackPower("player")
  local input = {
    class = G.Class(),
    level = UnitLevel("player"), agi = agi or 0, str = str or 0, ap = (base or 0) + (pos or 0) + (neg or 0),
    crit = GetCritChance and GetCritChance() or 0, hit = GetHitModifier and (GetHitModifier() or 0) or 0,
    equipped = equipped, slotOrder = order, talents = G.Talents(), combat = G.CombatReport(true),
    buffs = WA.charDB and WA.charDB.buffs or {}, skills = WA.char and WA.char.skills,
  }
  if input.class == "HUNTER" then
    local rb, rp, rn = 0, 0, 0
    if UnitRangedAttackPower then rb, rp, rn = UnitRangedAttackPower("player") end
    input.rap = (rb or 0) + (rp or 0) + (rn or 0)
    input.rangedCrit = GetRangedCritChance and GetRangedCritChance() or input.crit
    local w = equipped.RANGED and equipped.RANGED.stats.weapon
    local speed = UnitRangedDamage and UnitRangedDamage("player")
    if w and speed and speed > 0 then input.haste = w.speed / speed end
    local ammoLink = GetInventoryItemLink("player", INVSLOT_AMMO or 0)
    input.ammoDps = AmmoDps(ammoLink) or 0
    input.ammoId = ammoLink and tonumber(ammoLink:match("item:(%d+)")) or nil
    local known = KnownSpells()
    if known then
      input.known = { ["Aimed Shot"] = known["Aimed Shot"] or nil, ["Arcane Shot"] = known["Arcane Shot"] or false,
        ["Multi-Shot"] = known["Multi-Shot"] or false }
      if (input.level or 0) >= 10 and not known["Call Pet"] then input.hasPet = false end
    end
  elseif input.class == "SHAMAN" then
    local _, int = UnitStat("player", 4)
    input.int = int or 0
    -- nature (school 4): Lightning Bolt and Earth Shock
    input.sp = GetSpellBonusDamage and (GetSpellBonusDamage(4) or 0) or 0
    input.spellCrit = GetSpellCritChance and (GetSpellCritChance(4) or 0) or 0
    local known = KnownSpells()
    if known then input.known = { Stormstrike = known.Stormstrike or nil } end
  elseif input.class == "DRUID" then
    local _, int = UnitStat("player", 4)
    input.int = int or 0
    -- nature (school 4): Wrath and Moonfire's nature part
    input.sp = GetSpellBonusDamage and (GetSpellBonusDamage(4) or 0) or 0
    input.spellCrit = GetSpellCritChance and (GetSpellCritChance(4) or 0) or 0
    -- the shapeshift form now (1 Cat, 5 Bear, 8 Dire Bear, 31 Moonkin): attack power read in Cat
    -- Form is kept for when the sheet is read in another form
    local id = GetShapeshiftFormID and GetShapeshiftFormID() or nil
    input.form = id == 1 and "cat" or (id == 5 or id == 8) and "bear" or id == 31 and "moonkin" or id and "other" or "caster"
    if input.form == "cat" and WA.charDB then WA.charDB.catAp = input.ap end
    input.catAp = WA.charDB and WA.charDB.catAp or nil
    local known = KnownSpells()
    if known then input.known = { ["Cat Form"] = known["Cat Form"] or false } end
  elseif input.class == "WARLOCK" then
    local _, int = UnitStat("player", 4)
    input.int = int or 0
    -- shadow (school 6): Shadow Bolt, Corruption, Bane of Agony
    input.sp = GetSpellBonusDamage and (GetSpellBonusDamage(6) or 0) or 0
    input.spellCrit = GetSpellCritChance and (GetSpellCritChance(6) or 0) or 0
    input.spellHit = GetSpellHitModifier and (GetSpellHitModifier() or 0) or 0
  elseif input.class == "MAGE" then
    local _, int = UnitStat("player", 4)
    input.int = int or 0
    -- fire (school 3): Fireball; frost (school 5): Frostbolt. Mage.lua picks the main nuke's.
    input.spFire = GetSpellBonusDamage and (GetSpellBonusDamage(3) or 0) or 0
    input.spFrost = GetSpellBonusDamage and (GetSpellBonusDamage(5) or 0) or 0
    input.spellCrit = GetSpellCritChance and math.max(GetSpellCritChance(3) or 0, GetSpellCritChance(5) or 0) or 0
    input.spellHit = GetSpellHitModifier and (GetSpellHitModifier() or 0) or 0
    input.tab = (G.MainTalentTab())
  elseif input.class == "WARRIOR" then
    input.tab = (G.MainTalentTab())
  elseif input.class == "PRIEST" then
    local _, int = UnitStat("player", 4)
    input.int = int or 0
    -- holy (school 2): Smite, Holy Fire; shadow (school 6): Mind Blast, Shadow Word: Pain, Mind Flay
    input.spHoly = GetSpellBonusDamage and (GetSpellBonusDamage(2) or 0) or 0
    input.spShadow = GetSpellBonusDamage and (GetSpellBonusDamage(6) or 0) or 0
    input.spellCrit = GetSpellCritChance and math.max(GetSpellCritChance(2) or 0, GetSpellCritChance(6) or 0) or 0
    input.spellHit = GetSpellHitModifier and (GetSpellHitModifier() or 0) or 0
    input.tab = (G.MainTalentTab())
  end
  return input
end

-- Enchants for what you wear, for your role (Enchant.lua). ctx: the damage model's context, nil
-- for a class it does not know yet.
function G.EnchantReport(ctx)
  local equipped, order = G.Equipped()
  local form
  if G.Class() == "DRUID" and GetShapeshiftFormID then
    local id = GetShapeshiftFormID()
    form = (id == 5 or id == 8) and "bear" or id == 1 and "cat" or nil
  end
  return WA.Enchant.Report({
    class = G.Class(), level = UnitLevel("player"), tab = (G.MainTalentTab()), form = form,
    override = WA.charDB and WA.charDB.role or nil, equipped = equipped, slotOrder = order, ctx = ctx, book = G.Book(),
  })
end

function G.Context()
  if not G.Supported() then return nil end
  local input = G.ModelInput()
  local ctx = M.Context(input)
  ctx.ammoId = input.ammoId
  return ctx
end

-- Ammo the vendors sell (General Goods, Bowyer, Gunsmith): arrows and bullets by level.
G.VENDOR_AMMO = { 2512, 2515, 3030, 11285, 2516, 2519, 3033, 11284 }
local AMMO_KIND = { [2] = "arrow", [3] = "bullet" }

-- { itemId, name, kind, reqLevel, dps, current } for the vendor ammo plus what is in the ammo
-- slot; items the client has not loaded yet are left out (they load for the next draw).
function G.Ammo(currentId)
  local out, seen, ids = {}, {}, {}
  for _, id in ipairs(G.VENDOR_AMMO) do ids[#ids + 1] = id end
  if currentId then ids[#ids + 1] = currentId end
  for _, id in ipairs(ids) do
    if not seen[id] then
      seen[id] = true
      local name, link, _, _, minLevel, _, _, _, _, _, _, classID, subID = GetItemInfo(id)
      if not name then
        Request(id)
      elseif classID == 6 and AMMO_KIND[subID] then
        local dps = AmmoDps(link)
        if dps then
          local price, source = G.AmmoPrice(id)
          out[#out + 1] = { itemId = id, name = name, kind = AMMO_KIND[subID], reqLevel = minLevel or 0, dps = dps, current = id == currentId,
            price = price, priceSource = source }
        end
      end
    end
  end
  return out
end

function G.Routes(target)
  return WA.Routes.Plan({
    profs = G.Professions(), recipes = WA.Routes.FromRecipeData(), book = G.Book(), owned = G.Owned(),
    level = UnitLevel("player"), target = target,
  })
end

-- Auction house gear from the in-game scan (char.ah), when it is fresh enough.
function G.Offers()
  local ah = WA.char and WA.char.ah
  local out = {}
  if not ah or not ah.at or time() - ah.at > SCAN_FRESH then return out, ah and ah.at end
  for _, it in ipairs(ah.items or {}) do
    local item = {
      itemId = it.id, name = it.name or G.ItemName(it.id), slot = tostring(it.slot or ""):gsub("^INVTYPE_", ""),
      itemClass = it.cls or 0, subclass = it.sub or 0, reqLevel = it.req or 0, itemLevel = it.ilvl or 0,
      quality = QUALITY[it.q or 1] or "COMMON", stats = M.GameStats(it.st, it.dmg),
    }
    if not (item.itemClass == 2 and not item.stats.weapon) and M.Usable(G.Class(), item) and (it.price or 0) > 0 then
      out[#out + 1] = { item = item, price = it.price, listings = it.count or 0, where = "Aukciósház (játékban szkennelve)" }
    end
  end
  return out, ah.at
end

function G.PlanInput(ctx)
  local level = ctx.level
  local owned = G.Owned()
  local ownedGear = {}
  local ids = {}
  for id in pairs(owned) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local g = G.GearItem(id)
    if g then ownedGear[#ownedGear + 1] = g end
  end
  local profs = G.Professions()
  local crafts = {}
  local recipes = WA.Routes.FromRecipeData()
  for _, p in ipairs(profs) do
    local list = {}
    for _, r in ipairs(recipes) do
      if r.prof == p.id and r.product ~= 0 and r.orange <= p.skill then
        list[#list + 1] = { name = r.name, product = r.product, reagents = r.reagents, trainingCost = r.trainingCost,
          fromTrainer = r.fromTrainer, item = G.GearItem(r.product) }
      end
    end
    crafts[#crafts + 1] = { name = p.name, known = p.known, recipes = list }
  end
  local side = UnitFactionGroup("player") == "Alliance" and 1 or 2
  local quest = {}
  local D = WowAssistantData or {}
  for _, r in ipairs(D.loot or {}) do
    if r[12] == "quest" and (r[6] or 0) <= level and (r[14] or 0) <= level and (r[13] == 0 or r[13] == side) and D.dungeons[r[2]] then
      local row = { unpack(r) }
      row.zone = D.dungeons[r[2]][1]
      quest[#quest + 1] = row
    end
  end
  local offers, scanAt = G.Offers()
  local trainer = G.Trainer()
  local warnings = {}
  local c = WA.char or {}
  if not c.bankAt then warnings[#warnings + 1] = "A bank tartalma ismeretlen: nyisd meg egyszer a bankot." end
  local classHu = ({ ROGUE = "rogue", HUNTER = "hunter", SHAMAN = "shaman", DRUID = "druid", WARLOCK = "warlock", MAGE = "mage", WARRIOR = "warrior", PRIEST = "priest" })[ctx.class] or "class"
  if #trainer == 0 then warnings[#warnings + 1] = ("Nincs trainer-adat: nyisd meg a %s trainer ablakát minden szűrővel."):format(classHu) end
  if ctx.class == "HUNTER" and not (WA.char and WA.char.spells and #WA.char.spells > 0) then
    warnings[#warnings + 1] = "A varázskönyved még nincs beolvasva: /reload után az addon megnézi, mit tudsz (Aimed Shot, Multi-Shot, pet)."
  end
  if not scanAt then
    warnings[#warnings + 1] = "Még nem szkennelted az aukciósházat: /wa ah az aukciósháznál. Enélkül nincs AH-ajánlat és ár."
  elseif #offers == 0 then
    warnings[#warnings + 1] = "Az aukciósház-szkennelésed több mint 12 órás: /wa ah az aukciósháznál."
  end
  if not ctx.combat then warnings[#warnings + 1] = "Nincs rögzített harc: a modell tankönyvi értékekkel számol. /wa log, és fusson a feltöltő." end
  if not WowAssistantData then warnings[#warnings + 1] = "Hiányzik a GameData.lua (dungeon loot): npm run addon:recipes" end
  local routes = WA.Routes.Plan({ profs = profs, recipes = recipes, book = G.Book(), owned = owned, level = level, target = 300 })
  return {
    ctx = ctx, gold = GetMoney(), offers = offers, ownedGear = ownedGear, crafts = crafts, owned = owned, book = G.Book(),
    trainer = trainer, questLoot = quest, routes = routes, warnings = warnings, name = UnitName("player"),
    ammo = ctx.class == "HUNTER" and G.Ammo(ctx.ammoId) or nil,
  }
end

---------------------------------------------------------------------------
-- hunter: the pet, Beast Training and ammo prices
---------------------------------------------------------------------------
local function Try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { n = 0 }
  local function Pack(...) r.n = select("#", ...) for i = 1, r.n do r[i] = (select(i, ...)) end end
  Pack(pcall(fn, ...))
  if not r[1] then return nil end
  return unpack(r, 2, r.n)
end

-- Name and rank of the i-th spell in the pet's spellbook, whichever API this client has.
local function PetSpell(i)
  local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet) or BOOKTYPE_PET or "pet"
  local name, sub
  if C_SpellBook and C_SpellBook.GetSpellBookItemName then name, sub = Try(C_SpellBook.GetSpellBookItemName, i, bank) end
  if not name then name, sub = Try(GetSpellBookItemName, i, BOOKTYPE_PET or "pet") end
  if not name then name, sub = Try(GetSpellName, i, BOOKTYPE_PET or "pet") end
  return name, sub and tonumber(tostring(sub):match("(%d+)")) or nil
end

-- The pet out now: { name, family, level, tp, tpSpent, loyalty, happiness, known, at }; it is
-- also saved (char.pet) so the page works with the pet dismissed.
function G.Pet()
  local c = WA.char
  if not Try(UnitExists, "pet") or G.Class() ~= "HUNTER" then return c and c.pet or nil end
  local pet = { name = Try(UnitName, "pet"), family = Try(UnitCreatureFamily, "pet"), level = Try(UnitLevel, "pet"), known = {}, at = time() }
  pet.tp, pet.tpSpent = Try(GetPetTrainingPoints)
  pet.loyalty = Try(GetPetLoyalty)
  pet.happiness = Try(GetPetHappiness)
  local n = Try(HasPetSpells) or 0
  if C_SpellBook and C_SpellBook.HasPetSpells then n = Try(C_SpellBook.HasPetSpells) or n end
  for i = 1, math.min(tonumber(n) or 0, 40) do
    local name, rank = PetSpell(i)
    if name then pet.known[name] = math.max(pet.known[name] or 0, rank or 1) end
  end
  if c then c.pet = pet end
  return pet
end

-- Beast Training (the hunter's craft window): the highest rank you can teach of each ability.
local function ScanBeastTraining()
  local line = Try(GetCraftDisplaySkillLine) or Try(GetCraftName)
  if line ~= "Beast Training" or not WA.char then return end
  local taught = {}
  for i = 1, Try(GetNumCrafts) or 0 do
    local name, sub, kind = Try(GetCraftInfo, i)
    if name and kind ~= "header" then
      local rank = sub and tonumber(tostring(sub):match("(%d+)")) or 1
      taught[name] = math.max(taught[name] or 0, rank)
    end
  end
  if next(taught) then WA.char.beastTraining = { ranks = taught, at = time() } end
end
function G.Taught()
  local t = WA.char and WA.char.beastTraining
  return t and t.ranks or nil
end

-- Ammo prices from the vendors you visit: db.ammoPrices[item] = copper per piece.
local function ScanMerchant()
  local n = Try(GetMerchantNumItems) or 0
  WA.db.ammoPrices = WA.db.ammoPrices or {}
  for i = 1, n do
    local link = Try(GetMerchantItemLink, i)
    local id = link and tonumber(link:match("item:(%d+)"))
    if id then
      local _, _, _, _, _, classID = Try(GetItemInfoInstant, id)
      if classID == 6 then
        local price, quantity
        if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
          local info = Try(C_MerchantFrame.GetItemInfo, i)
          if type(info) == "table" then price, quantity = info.price, info.stackCount end
        end
        if not price then
          local _, _, p, q = Try(GetMerchantItemInfo, i)
          price, quantity = p, q
        end
        if price and price > 0 then WA.db.ammoPrices[id] = price / math.max(1, quantity or 1) end
      end
    end
  end
end

-- Price of one piece of ammo: { price, source } from a vendor you visited, the auction house,
-- or an estimate from the vendor sell price (vendors sell for 4 × what they pay).
function G.AmmoPrice(id)
  local seen = WA.db and WA.db.ammoPrices and WA.db.ammoPrices[id]
  if seen then return seen, "vendor" end
  local book = G.Book().unit(id)
  if book then return book.price, book.source end
  local sell = select(11, GetItemInfo(id))
  if sell and sell > 0 then return sell * 4, "becslés" end
  return nil, nil
end

local hunterFrame = CreateFrame("Frame")
hunterFrame:SetScript("OnEvent", function(_, event)
  if not WA.char then return end
  if event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then pcall(ScanBeastTraining)
  elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then pcall(ScanMerchant)
  else pcall(G.Pet) end
end)
for _, e in ipairs({ "CRAFT_SHOW", "CRAFT_UPDATE", "MERCHANT_SHOW", "MERCHANT_UPDATE", "UNIT_PET", "PET_BAR_UPDATE", "PLAYER_ENTERING_WORLD" }) do
  pcall(hunterFrame.RegisterEvent, hunterFrame, e)
end
