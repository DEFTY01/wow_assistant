-- WoW Assistant: fights seen live through the client's damage meter (C_DamageMeter).
--
-- This client gives addons no combat log, but it has the built-in damage meter's API. During
-- combat its numbers can be secret values (issecretvalue), which an addon may not read, so a fight
-- is read only after combat ends. What the meter gives (total damage, damage per spell) is stored
-- in WowAssistantCharDB.meterFights as a fight with source "meter". Such fights show in the Combat
-- window; they calibrate the damage model only when the meter also reported hit counts
-- ("detailed"), because the model needs hit and crit rates. The uploader's Fights.lua, from the
-- combat log, has those for every fight.
--
-- /wa meter      what the client's damage meter API returned for the last fight (for debugging)

local _, WA = ...
local MT = {}
WA.Meter = MT
local KEEP = 200

local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function Num(v)
  if v == nil or Secret(v) then return nil end
  return tonumber(v)
end
local function Str(v)
  if v == nil or Secret(v) then return nil end
  return type(v) == "string" and v or nil
end

-- Calls an API function by name with pcall; nil when missing or failing.
local function Call(name, ...)
  local api = C_DamageMeter
  local fn = api and api[name]
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if not ok then return nil end
  return a, b
end

local function Enum_(group, key, fallback)
  local e = Enum and Enum[group]
  local v = e and e[key]
  if v == nil then return fallback end
  return v
end

-- The player's entry in a meter session's list of sources.
local function Me(session)
  if type(session) ~= "table" then return nil end
  local list = session.combatSources or session.sources or session
  if type(list) ~= "table" then return nil end
  local me = UnitName("player")
  local guid = UnitGUID and UnitGUID("player")
  for _, s in ipairs(list) do
    if type(s) == "table" then
      if s.isLocalPlayer == true then return s end
      local g, n = Str(s.sourceGUID or s.guid), Str(s.name)
      if (g and g == guid) or (n and (n == me or n:match("^([^-]+)") == me)) then return s end
    end
  end
  return nil
end

local COUNTS = { n = { "hits", "count", "numHits", "casts" }, crit = { "crits", "critCount", "numCrits" },
  miss = { "misses", "missCount" }, dodge = { "dodges" }, parry = { "parries" } }

-- One spell of the meter -> an ability row of the fight. `detailed` when counts were present.
local function Ability(sp)
  -- Field names as the client's own meter uses them (DaylightUI_InfoPanel reads the same API):
  -- spellID (none for melee swings), totalAmount, amountPerSecond, combatSpellDetails.
  local id = Num(sp.spellID)
  local name = Str(sp.spellName or sp.name) or (id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id))
    or (id and GetSpellInfo and GetSpellInfo(id)) or (id and ("Spell #" .. id)) or Str(sp.creatureName) or "Melee"
  if id == 6603 or name == "Auto Attack" then name = "Melee" end
  local a = { name = name, dmg = Num(sp.totalAmount or sp.amount) or 0, n = 0, hit = 0, crit = 0, glance = 0, miss = 0,
    dodge = 0, parry = 0, block = 0, other = 0, max = Num(sp.maxAmount or sp.biggestHit) or 0 }
  local detailed = false
  for field, keys in pairs(COUNTS) do
    for _, k in ipairs(keys) do
      local v = Num(sp[k])
      if v then a[field] = v detailed = true break end
    end
  end
  if detailed then a.hit = math.max(0, a.n - a.crit - a.miss - a.dodge - a.parry) end
  return a, detailed
end

local fight -- the fight in progress: start, target, targetLevel
MT.last = nil -- what the API returned for the last fight, for /wa meter

local function Read()
  local f = fight
  fight = nil
  if not f or not C_DamageMeter then return end
  local damage = Enum_("DamageMeterType", "DamageDone", 0)
  local current = Enum_("DamageMeterSessionType", "Current", 1)
  local session = Call("GetCombatSessionFromType", current, damage)
  MT.last = { session = session, at = time() }
  local me = Me(session)
  if not me then return end
  local total = Num(me.totalAmount or me.amount)
  if not total or total <= 0 then return end
  local dur = Num(session.durationSeconds) or Num((Call("GetSessionDurationSeconds", current))) or (time() - f.start)
  if dur <= 0 then return end
  local ab, detailed = {}, false
  local guid = Str(me.sourceGUID) or (UnitGUID and UnitGUID("player"))
  local spells = me.combatSpells
  if not spells and guid then
    local src = Call("GetCombatSessionSourceFromType", current, damage, guid, nil)
    MT.last.source = src
    spells = type(src) == "table" and (src.combatSpells or src.spells) or nil
  end
  for _, sp in ipairs(type(spells) == "table" and spells or {}) do
    if type(sp) == "table" then
      local a, d = Ability(sp)
      if a.dmg > 0 or a.n > 0 then ab[#ab + 1] = a detailed = detailed or d end
    end
  end
  local list = WA.charDB.meterFights
  list[#list + 1] = {
    start = f.start, dur = math.floor(dur * 10 + 0.5) / 10, dmg = total, target = f.target or "?", targetLevel = f.targetLevel or 0,
    level = UnitLevel("player"), capped = 0, samples = 0, source = "meter", detailed = detailed or nil,
    ab = ab, casts = {}, auras = {},
  }
  while #list > KEEP do table.remove(list, 1) end
  if WA.OnFight then WA.OnFight() end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_DISABLED" then
    local name = UnitExists("target") and UnitCanAttack("player", "target") and UnitName("target") or nil
    fight = { start = time(), target = Str(name), targetLevel = name and Num(UnitLevel("target")) or 0 }
  elseif event == "PLAYER_REGEN_ENABLED" then
    -- The meter's numbers stop being secret once combat is over; give it a moment to settle.
    C_Timer.After(1, Read)
  end
end)

table.insert(WA.onLoad, function()
  WA.charDB.meterFights = WA.charDB.meterFights or {}
  if not C_DamageMeter then return end
  frame:RegisterEvent("PLAYER_REGEN_DISABLED")
  frame:RegisterEvent("PLAYER_REGEN_ENABLED")
end)

-- Prints a table a few levels deep, secret values marked.
local function Dump(v, indent, depth, out)
  if #out > 60 then return end
  if type(v) ~= "table" then
    out[#out + 1] = indent .. (Secret(v) and "<secret>" or tostring(v))
    return
  end
  if depth > 3 then out[#out + 1] = indent .. "{...}" return end
  local n = 0
  for k, x in pairs(v) do
    n = n + 1
    if n > 12 then out[#out + 1] = indent .. "..." break end
    if type(x) == "table" then
      out[#out + 1] = indent .. tostring(k) .. " ="
      Dump(x, indent .. "  ", depth + 1, out)
    else
      out[#out + 1] = indent .. tostring(k) .. " = " .. (Secret(x) and "<secret>" or tostring(x))
    end
  end
end

WA.Command("meter", function()
  local print = function(s) DEFAULT_CHAT_FRAME:AddMessage("|cffd4a24cWA meter|r " .. s) end
  if not C_DamageMeter then print("ez a kliens nem ad damage meter API-t.") return end
  local fns = {}
  for k, v in pairs(C_DamageMeter) do if type(v) == "function" then fns[#fns + 1] = k end end
  table.sort(fns)
  print("API: " .. table.concat(fns, ", "))
  print(("Tárolt meter-harcok: %d"):format(#(WA.charDB.meterFights or {})))
  if not MT.last then print("Még nem volt harc ebben a munkamenetben.") return end
  local out = {}
  Dump(MT.last, "  ", 0, out)
  for _, line in ipairs(out) do print(line) end
end, "/wa meter – a damage meter API utolsó válasza (hibakereséshez)")
