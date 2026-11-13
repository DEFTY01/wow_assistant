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

-- ------------------------------------------------------------------ events

frame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    local name = UnitName("player")
    local oldVersion = WowAssistantDB.version or 0
    WowAssistantDB.version = 4
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
  end
  -- Nothing is scanned on PLAYER_LOGOUT: at that point the Forever client already reports
  -- zero gold and empty bags, which would overwrite the good data.
end)

for _, event in ipairs({
  "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_MONEY", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
  "PLAYERBANKSLOTS_CHANGED", "SKILL_LINES_CHANGED", "PLAYER_LEVEL_UP", "SPELLS_CHANGED",
  "TRAINER_SHOW", "TRAINER_UPDATE",
}) do
  pcall(frame.RegisterEvent, frame, event) -- an event unknown to this client must not break the rest
end

SLASH_WOWASSISTANT1 = "/wa"
SLASH_WOWASSISTANT2 = "/wowassistant"
SlashCmdList["WOWASSISTANT"] = function(msg)
  if not char then return end
  ScanAll()
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
  Print("Mentes es feltoltes: /wa save (ujratolti a feluletet).")
end
