-- WoW Assistant exporter.
-- Addons cannot talk to the network: everything is written to SavedVariables, which the
-- game saves on logout or /reload. The uploader script then sends that file to the web app.

WowAssistantDB = WowAssistantDB or {}

local frame = CreateFrame("Frame")
local char -- this character's table inside WowAssistantDB
local bankOpen = false

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cfff0c040WoW Assistant:|r " .. msg)
end

-- Run one scan; a failure is stored for the web app instead of breaking the others.
local function Safe(name, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and char then
    char.errors = char.errors or {}
    char.errors[name] = tostring(err)
  end
  return ok
end

-- ------------------------------------------------------------------ inventory

-- Container API moved into C_Container in newer clients; support both.
local function NumSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then
    return C_Container.GetContainerNumSlots(bag) or 0
  end
  return GetContainerNumSlots(bag) or 0
end

local function SlotItem(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then return info.itemID, info.stackCount end
    return nil
  end
  local _, count, _, _, _, _, _, _, _, itemID = GetContainerItemInfo(bag, slot)
  return itemID, count
end

-- Sum item counts over a list of bag IDs: { [itemID] = count }.
local function ScanBags(bags)
  local items = {}
  for _, bag in ipairs(bags) do
    for slot = 1, NumSlots(bag) do
      local id, count = SlotItem(bag, slot)
      if id then items[id] = (items[id] or 0) + (count or 1) end
    end
  end
  return items
end

local function ScanInventory()
  char.bags = ScanBags({ 0, 1, 2, 3, 4 })
  char.bagsAt = time()
end

local function ScanBank()
  local bags = { BANK_CONTAINER or -1 }
  local first = (NUM_BAG_SLOTS or 4) + 1
  for bag = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do bags[#bags + 1] = bag end
  char.bank = ScanBags(bags)
  char.bankAt = time()
end

local function ScanMoney()
  char.money = GetMoney()
  char.level = UnitLevel("player")
  char.at = time()
end

-- ------------------------------------------------------------------ skills, spells, trainer

-- Skill lines include weapon skills, professions and defense (Classic-style API).
local function ScanSkills()
  if not GetNumSkillLines then return end
  local skills = {}
  for i = 1, GetNumSkillLines() do
    local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
    if name and not isHeader then skills[name] = { rank = rank, max = maxRank } end
  end
  char.skills = skills
end

local function ScanSpells()
  local spells = {}
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
    -- Modern spellbook API.
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    for tab = 1, C_SpellBook.GetNumSpellBookSkillLines() do
      local line = C_SpellBook.GetSpellBookSkillLineInfo(tab)
      if line then
        for i = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
          local info = C_SpellBook.GetSpellBookItemInfo(i, bank)
          if info and info.name then
            spells[#spells + 1] = { name = info.name, rank = info.subName or "", id = info.spellID or info.actionID }
          end
        end
      end
    end
  elseif GetNumSpellTabs then
    for tab = 1, GetNumSpellTabs() do
      local _, _, offset, count = GetSpellTabInfo(tab)
      for i = offset + 1, offset + count do
        local name, sub = GetSpellBookItemName(i, BOOKTYPE_SPELL or "spell")
        local _, id = GetSpellBookItemInfo(i, BOOKTYPE_SPELL or "spell")
        if name then spells[#spells + 1] = { name = name, rank = sub or "", id = id } end
      end
    end
  else
    return
  end
  char.spells = spells
end

-- Reads whatever the open trainer window lists. Tick every box in the trainer's
-- "Filter" menu to export everything it can teach.
local function ScanTrainer()
  if not GetNumTrainerServices then return end
  char.trainer = char.trainer or {}
  for i = 1, GetNumTrainerServices() do
    -- Classic returns (name, rank text, category); the Forever client returns (name, category, icon).
    local name, a, b = GetTrainerServiceInfo(i)
    local sub, category = a, b
    if a == "available" or a == "unavailable" or a == "used" or a == "header" then
      sub, category = "", a
    end
    local level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 0
    if name and category ~= "header" then
      char.trainer[name .. "|" .. (sub or "") .. "|" .. level] = {
        name = name,
        rank = sub or "",
        state = category, -- available / unavailable / used
        cost = GetTrainerServiceCost(i) or 0,
        level = level,
        tradeskill = IsTradeskillTrainer and IsTradeskillTrainer() and true or false,
        at = time(),
      }
    end
  end
end

-- Which client APIs exist, so the web app can tell "not supported" from "not scanned".
local function ScanApi()
  local version, build, _, interface = GetBuildInfo()
  char.api = {
    version = version,
    build = build,
    interface = interface,
    skillLines = GetNumSkillLines ~= nil,
    spellTabs = GetNumSpellTabs ~= nil,
    cSpellBook = C_SpellBook ~= nil and C_SpellBook.GetNumSpellBookSkillLines ~= nil,
    trainer = GetNumTrainerServices ~= nil,
    damageMeter = C_DamageMeter ~= nil,
    loggingCombat = LoggingCombat ~= nil,
    auctionBrowse = C_AuctionHouse ~= nil and C_AuctionHouse.SendBrowseQuery ~= nil,
    itemStats = (C_Item ~= nil and C_Item.GetItemStats ~= nil) or GetItemStats ~= nil,
    tooltipInfo = C_TooltipInfo ~= nil and C_TooltipInfo.GetHyperlink ~= nil,
  }
end

local function ScanAll()
  Safe("money", ScanMoney)
  Safe("inventory", ScanInventory)
  Safe("skills", ScanSkills)
  Safe("spells", ScanSpells)
  Safe("api", ScanApi)
end

-- ------------------------------------------------------------------ combat logging

-- The Forever client does not let addons read combat events (COMBAT_LOG_EVENT_UNFILTERED is
-- reserved for the Blizzard UI). The game can still write the full combat log to
-- Logs/WoWCombatLog*.txt, which the uploader script parses instead.
local function ApplyLogging()
  if not LoggingCombat then return end
  if WowAssistantDB.logCombat then LoggingCombat(true) end
  char.logging = LoggingCombat() and true or false
end

-- ------------------------------------------------------------------ experience tracking

-- One sample per XP change (at most one every 20 seconds): enough to compute XP per hour by zone.
local lastXpSample = 0
local function SampleXp()
  local now = time()
  char.xp = char.xp or {}
  local n = #char.xp
  local level = UnitLevel("player")
  if n > 0 and now - lastXpSample < 20 and char.xp[n][3] == level then
    char.xp[n][1], char.xp[n][2] = now, UnitXP("player")
    return
  end
  lastXpSample = now
  char.xp[n + 1] = { now, UnitXP("player"), level, UnitXPMax("player"), GetRealZoneText and GetRealZoneText() or "" }
  while #char.xp > 1500 do table.remove(char.xp, 1) end
end

-- ------------------------------------------------------------------ auction house scan

-- "/wa ah" with the auction house open: lists the weapons and armor around your level, then
-- looks each one up for its cheapest buyout and its real stats (including random suffixes,
-- which the web API cannot tell apart). Everything goes through the game's own throttle.
local ah = nil -- the running scan

-- What each class can equip: armor subclasses (0 misc, 1 cloth, 2 leather, 3 mail, 4 plate,
-- 6 shield) and weapon subclasses.
local USABLE = {
  ROGUE = { armor = { [0] = true, [1] = true, [2] = true }, weapon = { [4] = true, [7] = true, [13] = true, [15] = true, [2] = true, [3] = true, [16] = true, [18] = true } },
}

local function Usable(classID, subID)
  local rules = USABLE[char.class]
  if not rules then return true end -- unknown class: keep everything, the web app filters
  if classID == 2 then return rules.weapon[subID] == true end
  if classID == 4 then return rules.armor[subID] == true end
  return false
end

local function Sorts(order)
  if not Enum or not Enum.AuctionHouseSortOrder or order == nil then return {} end
  return { { sortOrder = order, reverseSort = false } }
end

-- Damage range and speed are only in the tooltip text.
local function WeaponNumbers(link)
  if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return nil end
  local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
  if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
  local min, max, speed
  for _, line in ipairs(data.lines) do
    for _, text in ipairs({ line.leftText, line.rightText }) do
      if type(text) == "string" then
        local a, b = text:match("(%d+) %- (%d+)")
        if a and not min and text:find("Damage") then min, max = tonumber(a), tonumber(b) end
        local s = text:match("Speed (%d+%.%d+)")
        if s then speed = tonumber(s) end
      end
    end
  end
  if min and speed then return { min, max, speed } end
  return nil
end

local function FinishScan(reason)
  if not ah then return end
  char.ah = { at = time(), items = ah.items, note = reason }
  Print(string.format("AH-szkenneles kesz: %d targy%s. Mentes: /wa save", #ah.items, reason and (" (" .. reason .. ")") or ""))
  ah = nil
end

local function NextSearch()
  if not ah or ah.phase ~= "search" then return end
  if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
    ah.waiting = true
    return
  end
  ah.waiting = nil
  ah.index = ah.index + 1
  local entry = ah.queue[ah.index]
  if not entry then return FinishScan() end
  if ah.index % 50 == 0 then Print(string.format("AH-szkenneles: %d / %d", ah.index, #ah.queue)) end
  ah.current = entry
  local order = Enum and Enum.AuctionHouseSortOrder and (Enum.AuctionHouseSortOrder.Buyout or Enum.AuctionHouseSortOrder.Price)
  local ok = pcall(C_AuctionHouse.SendSearchQuery, entry.key, Sorts(order), false)
  if not ok then C_Timer.After(0.15, NextSearch) end
  -- A query that never answers must not stall the scan.
  local index = ah.index
  C_Timer.After(4, function()
    if ah and ah.phase == "search" and ah.index == index then NextSearch() end
  end)
end

local function OnItemResults(itemKey)
  if not ah or ah.phase ~= "search" or not ah.current then return end
  local entry = ah.current
  if type(itemKey) == "table" and itemKey.itemID ~= entry.key.itemID then return end
  local best
  local n = C_AuctionHouse.GetNumItemSearchResults(entry.key) or 0
  -- The first event can arrive before the listings do: give it one more chance (the stall
  -- timer moves on if nothing ever comes).
  if n == 0 and not entry.retried then
    entry.retried = true
    return
  end
  for i = 1, math.min(n, 20) do
    local r = C_AuctionHouse.GetItemSearchResultInfo(entry.key, i)
    local buyout = r and tonumber(r.buyoutAmount) or 0
    if r and buyout > 0 and not r.containsOwnerItem and r.itemLink and (not best or buyout < best.buyout) then
      best = { buyout = buyout, link = r.itemLink }
    end
  end
  ah.current = nil
  if best then
    local name, _, quality, _, minLevel = GetItemInfo(best.link)
    local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats
    local stats = getStats and getStats(best.link) or nil
    ah.items[#ah.items + 1] = {
      id = entry.key.itemID,
      suffix = entry.key.itemSuffix or 0,
      ilvl = entry.key.itemLevel or 0,
      name = name or entry.name,
      q = quality,
      req = minLevel,
      slot = entry.slot,
      cls = entry.cls,
      sub = entry.sub,
      price = best.buyout,
      count = entry.count,
      st = stats,
      dmg = entry.cls == 2 and WeaponNumbers(best.link) or nil,
    }
  end
  C_Timer.After(0.12, NextSearch)
end

local function OnBrowseResults()
  if not ah or ah.phase ~= "browse" then return end
  if C_AuctionHouse.HasFullBrowseResults and not C_AuctionHouse.HasFullBrowseResults() then
    C_AuctionHouse.RequestMoreBrowseResults()
    return
  end
  local seen = {}
  for _, r in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
    local key = r.itemKey
    local id = key and key.itemID
    local tag = id and (id .. ":" .. tostring(key.itemSuffix or 0) .. ":" .. tostring(key.itemLevel or 0))
    if id and not seen[tag] then
      seen[tag] = true
      local _, _, _, equipLoc, _, classID, subID = GetItemInfoInstant(id)
      if equipLoc and equipLoc ~= "" and Usable(classID, subID) then
        ah.queue[#ah.queue + 1] = { key = key, slot = equipLoc, cls = classID, sub = subID, count = r.totalQuantity, price = r.minPrice }
      end
    end
  end
  -- Cheapest first, and a cap so one scan stays within a few minutes.
  table.sort(ah.queue, function(a, b) return (a.price or 0) < (b.price or 0) end)
  while #ah.queue > 500 do table.remove(ah.queue) end
  Print(string.format("AH-szkenneles: %d targy lekerdezese indul (kb. %d perc). Hagyd nyitva az aukcioshazat.", #ah.queue, math.ceil(#ah.queue * 0.4 / 60)))
  ah.phase = "search"
  ah.index = 0
  NextSearch()
end

local function StartScan()
  if not (C_AuctionHouse and C_AuctionHouse.SendBrowseQuery and C_AuctionHouse.GetBrowseResults) then
    Print("Ez a kliens nem tamogatja az aukcioshaz lekerdezeset addonbol.")
    return
  end
  if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
    Print("Nyisd meg az aukcioshazat, aztan ird be ujra: /wa ah")
    return
  end
  local level = UnitLevel("player")
  ah = { phase = "browse", queue = {}, items = {}, index = 0 }
  local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price
  C_AuctionHouse.SendBrowseQuery({
    searchString = "",
    sorts = Sorts(order),
    minLevel = math.max(1, level - 8),
    maxLevel = level + 4,
    filters = {},
    itemClassFilters = { { classID = 2 }, { classID = 4 } },
  })
  Print("AH-szkenneles: a kinalat lekerese...")
  -- If the browse never completes, say so instead of hanging silently.
  C_Timer.After(20, function()
    if ah and ah.phase == "browse" then
      if #(C_AuctionHouse.GetBrowseResults() or {}) > 0 then OnBrowseResults() else FinishScan("a kinalat nem jott meg") end
    end
  end)
end

-- ------------------------------------------------------------------ events

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    local name = UnitName("player")
    local oldVersion = WowAssistantDB.version or 0
    WowAssistantDB.version = 5
    WowAssistantDB.chars = WowAssistantDB.chars or {}
    WowAssistantDB.chars[name] = WowAssistantDB.chars[name] or {}
    char = WowAssistantDB.chars[name]
    if oldVersion < 4 then char.trainer = nil end -- older versions stored trainer rows wrongly
    char.name = name
    char.class = select(2, UnitClass("player"))
    char.errors = nil
    WowAssistantDB.last = name
  elseif not char then
    return
  elseif event == "PLAYER_ENTERING_WORLD" then
    ScanAll()
    Safe("logging", ApplyLogging)
    Safe("xp", SampleXp)
  elseif event == "PLAYER_MONEY" then
    Safe("money", ScanMoney)
  elseif event == "BAG_UPDATE_DELAYED" then
    Safe("inventory", ScanInventory)
  elseif event == "BANKFRAME_OPENED" then
    bankOpen = true
    Safe("bank", ScanBank)
  elseif event == "BANKFRAME_CLOSED" then
    bankOpen = false
  elseif event == "PLAYERBANKSLOTS_CHANGED" then
    -- Away from the banker the bank reads as almost empty; only trust a scan while it is open.
    if bankOpen then Safe("bank", ScanBank) end
  elseif event == "SKILL_LINES_CHANGED" or event == "PLAYER_LEVEL_UP" then
    Safe("money", ScanMoney)
    Safe("skills", ScanSkills)
  elseif event == "SPELLS_CHANGED" then
    Safe("spells", ScanSpells)
  elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
    Safe("trainer", ScanTrainer)
  elseif event == "PLAYER_XP_UPDATE" then
    Safe("xp", SampleXp)
  elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
    Safe("ah", OnBrowseResults)
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    Safe("ah", OnItemResults, ...)
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    if ah and ah.waiting then Safe("ah", NextSearch) end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    if ah then Safe("ah", FinishScan, "az aukcioshaz bezarult, reszleges")  end
  end
  -- Nothing is scanned on PLAYER_LOGOUT: at that point the Forever client already reports
  -- zero gold and empty bags, which would overwrite the good data.
end)

for _, event in ipairs({
  "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_MONEY", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
  "PLAYERBANKSLOTS_CHANGED", "SKILL_LINES_CHANGED", "PLAYER_LEVEL_UP", "SPELLS_CHANGED",
  "TRAINER_SHOW", "TRAINER_UPDATE", "PLAYER_XP_UPDATE", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
  "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
  "AUCTION_HOUSE_CLOSED",
}) do
  pcall(frame.RegisterEvent, frame, event) -- an event unknown to this client must not break the rest
end

SLASH_WOWASSISTANT1 = "/wa"
SLASH_WOWASSISTANT2 = "/wowassistant"
SlashCmdList["WOWASSISTANT"] = function(msg)
  if not char then return end
  ScanAll()
  if msg == "ah" then
    Safe("ah", StartScan)
    if char.errors and char.errors.ah then Print("hiba (ah): " .. char.errors.ah) end
    return
  end
  if msg == "log" then
    WowAssistantDB.logCombat = not WowAssistantDB.logCombat
    if LoggingCombat then LoggingCombat(WowAssistantDB.logCombat and true or false) end
    Print(WowAssistantDB.logCombat and "harcnaplo BEKAPCSOLVA (minden belepeskor magatol indul)." or "harcnaplo kikapcsolva.")
    return
  end
  if msg == "save" then
    ReloadUI() -- the only way to write SavedVariables without logging out
    return
  end
  local bagCount, trainerCount, errCount = 0, 0, 0
  for _ in pairs(char.bags or {}) do bagCount = bagCount + 1 end
  for _ in pairs(char.trainer or {}) do trainerCount = trainerCount + 1 end
  for _ in pairs(char.errors or {}) do errCount = errCount + 1 end
  Print(string.format("%s, %d fele targy a taskakban, %d trainer skill, harcnaplo: %s, bank: %s.",
    GetCoinText and GetCoinText(char.money or 0) or tostring(char.money),
    bagCount, trainerCount, (LoggingCombat and LoggingCombat()) and "megy" or "all (/wa log)", char.bankAt and "megvan" or "meg nincs"))
  if errCount > 0 then
    for name, err in pairs(char.errors) do Print("hiba (" .. name .. "): " .. err) end
  end
  Print("Aukcioshaz szkenneles: /wa ah (nyitott aukcioshaznal). Mentes: /wa save.")
end
