-- WoW Assistant core: the shared namespace, the character key, SavedVariables and their
-- migration from the separate SessionBar and AzerothChronicle addons, and the /wa command.
--
-- SavedVariables
--   WowAssistantDB (account)
--     version, last            last = key of the character played last
--     chars[key]               exporter data per character (Exporter.lua), key = Name-Realm or Name#id
--     market                   auction order books (VendorCraft.lua)
--     session                  SessionBar settings (bar position, scale, ...)
--     chronicle                Azeroth Chronicle: chars[key] snapshots/weeks, guild standings, share
--     migrated                 what was taken over from the old addons, and when
--   WowAssistantCharDB (per character)
--     id                       random id telling same-name characters apart when the realm is empty
--     known                    recipes known per profession (VendorCraft.lua)
--     session                  SessionBar: current session, history, goals
--     migrated                 per-character migration marks

local ADDON_NAME, WA = ...
WowAssistant = WA -- for /dump and for tests outside the game

WA.DB_VERSION = 7
WA.onLoad = {}   -- run once the SavedVariables are ready (ADDON_LOADED), in file order
WA.onLogin = {}  -- run at PLAYER_LOGIN, once the character key is known
WA.commands = {} -- /wa <name> ... handlers: fn(rest, msg)
WA.help = {}     -- lines for /wa help

---------------------------------------------------------------------------
-- language
---------------------------------------------------------------------------
-- The code is written in English. With Hungarian chosen (WowAssistantDB.lang = "hu", /wa lang hu)
-- L looks every text up in WA.HU (Locale_hu.lua). The files run before the SavedVariables load,
-- so texts written into tables at load time are registered with WA.LR (values) or WA.LRK (keys)
-- and translated in place once the setting is known (ADDON_LOADED).
WA.lang = "en"
WA.HU = WA.HU or {}
function WA.L(s)
  if WA.lang == "hu" then return WA.HU[s] or s end
  return s
end
local L = WA.L
local valueRoots, keyRoots = {}, {}
function WA.LR(t) valueRoots[#valueRoots + 1] = t return t end
function WA.LRK(t) keyRoots[#keyRoots + 1] = t return t end

local function TranslateValues(t, seen)
  if seen[t] then return end
  seen[t] = true
  for k, v in pairs(t) do
    if type(v) == "string" then
      local hu = WA.HU[v]
      if hu then t[k] = hu end
    elseif type(v) == "table" then
      TranslateValues(v, seen)
    end
  end
end

local function TranslateKeys(t)
  local moved = {}
  for k, v in pairs(t) do
    if type(k) == "string" and WA.HU[k] then moved[k] = v end
  end
  for k, v in pairs(moved) do
    t[k] = nil
    t[WA.HU[k]] = v
  end
end

local function ApplyLanguage(db)
  WA.lang = db.lang == "hu" and "hu" or "en"
  if WA.lang ~= "hu" then return end
  local seen = {}
  for _, t in ipairs(valueRoots) do TranslateValues(t, seen) end
  TranslateValues(WA.help, seen)
  for _, t in ipairs(keyRoots) do TranslateKeys(t) end
end

-- Saves the choice and reloads the interface, so every text is built again in that language.
function WA.SetLanguage(lang)
  if lang ~= "hu" then lang = "en" end
  WA.db.lang = lang
  WA.Print(L("language: %s (reloading the interface)"):format(L(lang == "hu" and "Hungarian" or "English")))
  if C_UI and C_UI.Reload then C_UI.Reload() elseif ReloadUI then ReloadUI() end
end

-- Chat uses the game's font, which has no ő and ű: WA.Fix (Style.lua) swaps them for ö and ü.
function WA.Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cfff0c040Waystone:|r " .. (WA.Fix and WA.Fix(msg) or msg)) end

local function Copy(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local t = {}
  seen[v] = t
  for k, x in pairs(v) do t[Copy(k, seen)] = Copy(x, seen) end
  return t
end
WA.Copy = Copy

---------------------------------------------------------------------------
-- character key
---------------------------------------------------------------------------
-- The Forever client can report an empty realm name. Characters are then told apart by an id
-- kept in the per-character SavedVariables, and their key becomes "Name#id".
function WA.RealmName()
  local r = GetNormalizedRealmName and GetNormalizedRealmName()
  if not r or r == "" then r = ((GetRealmName and GetRealmName()) or ""):gsub("%s", "") end
  if r == "" and UnitFullName then r = select(2, UnitFullName("player")) or "" end
  return r
end

function WA.CharKey()
  local name = UnitName("player")
  local realm = WA.RealmName()
  if realm ~= "" then return name .. "-" .. realm end
  return name .. "#" .. WA.charDB.id
end

---------------------------------------------------------------------------
-- migration from SessionBar and AzerothChronicle
---------------------------------------------------------------------------
-- The old addons' SavedVariables are only loaded while an addon that declares them is enabled.
-- Their folders are therefore replaced by small shims (same TOC SavedVariables, no code), and
-- this addon loads after them (OptionalDeps). Everything is copied, never moved: the old files
-- stay as they were, as a backup, until the shim folders are removed.
local function MigrateAccount(db)
  db.migrated = db.migrated or {}
  local m = db.migrated
  if not m.sessionBar and type(SessionBarDB) == "table" then
    db.session = Copy(SessionBarDB)
    m.sessionBar = time()
  end
  if not m.chronicle and type(AzerothChronicleDB) == "table" then
    local old = Copy(AzerothChronicleDB)
    local cur = db.chronicle or {}
    -- Keep anything already recorded by this addon; the old data fills the rest.
    old.chars = old.chars or {}
    for k, v in pairs(cur.chars or {}) do old.chars[k] = v end
    old.guild = old.guild or {}
    for g, weeks in pairs(cur.guild or {}) do
      old.guild[g] = old.guild[g] or {}
      for wk, members in pairs(weeks) do
        old.guild[g][wk] = old.guild[g][wk] or {}
        for name, e in pairs(members) do old.guild[g][wk][name] = e end
      end
    end
    if cur.share ~= nil then old.share = cur.share end
    db.chronicle = old
    m.chronicle = time()
  end
end

local function MigrateCharacter(c)
  c.migrated = c.migrated or {}
  local m = c.migrated
  if not m.sessionBar and type(SessionBarCharDB) == "table" then
    c.session = Copy(SessionBarCharDB)
    m.sessionBar = time()
  end
  if not m.chronicle and type(AzerothChronicleCharDB) == "table" then
    -- The id keeps "Name#id" keys stable, so it must be the one the old addon used.
    if AzerothChronicleCharDB.id then c.id = AzerothChronicleCharDB.id end
    m.chronicle = time()
  end
end

-- Versions before 7 stored the exporter data under the first name only, so same-name
-- characters on other realms shared it. The first character that plausibly continues the old
-- record (same class, level not lower and at most one higher) takes it over; its old key is kept
-- in formerKeys. Otherwise the record stays where it is, and readers treat a key without "-" or
-- "#" as such a legacy record.
local function AdoptLegacyChar(db, key)
  local name = UnitName("player")
  local c = db.chars[name]
  if not c or name == key or db.chars[key] then return end
  local class = select(2, UnitClass("player"))
  local level = UnitLevel("player")
  if c.class ~= class or not c.level or level < c.level or level > c.level + 1 then return end
  c.formerKeys = c.formerKeys or {}
  table.insert(c.formerKeys, name)
  db.chars[key] = c
  db.chars[name] = nil
end

---------------------------------------------------------------------------
-- load and login
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" then
    if name ~= ADDON_NAME then return end
    WowAssistantDB = WowAssistantDB or {}
    WowAssistantCharDB = WowAssistantCharDB or {}
    local db, c = WowAssistantDB, WowAssistantCharDB
    db.chars = db.chars or {}
    MigrateAccount(db)
    MigrateCharacter(c)
    db.session = db.session or {}
    db.chronicle = db.chronicle or {}
    c.session = c.session or {}
    c.known = c.known or {}
    if not c.id then c.id = ("%08x%04x"):format(time() % 2 ^ 32, math.random(0, 0xffff)) end
    WA.db, WA.charDB = db, c
    ApplyLanguage(db)
    for _, fn in ipairs(WA.onLoad) do
      local ok, err = pcall(fn)
      if not ok then WA.Print(L"error while loading: " .. tostring(err)) end
    end
  elseif event == "PLAYER_LOGIN" then
    local db = WA.db
    WA.key = WA.CharKey()
    AdoptLegacyChar(db, WA.key)
    db.version = WA.DB_VERSION
    db.last = WA.key
    for _, fn in ipairs(WA.onLogin) do
      local ok, err = pcall(fn)
      if not ok then WA.Print(L"error at login: " .. tostring(err)) end
    end
  end
end)

---------------------------------------------------------------------------
-- /wa
---------------------------------------------------------------------------
function WA.Command(name, fn, help)
  WA.commands[name] = fn
  if help then WA.help[#WA.help + 1] = help end
end

local function Dispatch(msg)
  msg = strtrim(msg or "")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  local fn = WA.commands[cmd]
  if fn then return fn(rest, msg) end
  if cmd == "help" or cmd == "?" then
    for _, line in ipairs(WA.help) do WA.Print(line) end
    return
  end
  -- Anything else goes to the default handler (the exporter's status and scans).
  if WA.commands[""] then return WA.commands[""](msg, msg) end
end
WA.Dispatch = Dispatch

WA.Command("lang", function(rest)
  rest = (rest or ""):lower()
  if rest == "hu" or rest == "magyar" or rest == "hungarian" then WA.SetLanguage("hu")
  elseif rest == "en" or rest == "angol" or rest == "english" then WA.SetLanguage("en")
  else WA.SetLanguage(WA.lang == "hu" and "en" or "hu") end
end, "/wa lang en | hu – the addon's language (English or Hungarian)")

SLASH_WOWASSISTANT1 = "/wa"
SLASH_WOWASSISTANT2 = "/waystone"
SLASH_WOWASSISTANT3 = "/wowassistant"
SlashCmdList.WOWASSISTANT = Dispatch
