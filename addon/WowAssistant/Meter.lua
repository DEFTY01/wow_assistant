-- WoW Assistant: records every fight in game, as it happens.
--
-- This client gives addons no combat log, so a fight is put together from what it does give:
--   * your casts (UNIT_SPELLCAST_SUCCEEDED): when, which spell, energy and combo points;
--   * what happens to your target (UNIT_COMBAT): hit, crit, glancing, miss, dodge, parry, block,
--     with the amount. A hit landing right after one of your instant attacks counts for that
--     attack, any other physical hit for the auto-attack ("Melee"), others for "Other". Counted
--     only when you are not in a group, because the target's hits can come from anyone.
--   * every half second: whether your energy is full, and which buffs are on you;
--   * after combat: the client's damage meter (C_DamageMeter), whose totals and per-spell damage
--     are exact. During combat its numbers are secret values (issecretvalue), so it is read when
--     the fight is over.
-- Anything the client keeps secret is skipped. The fight is stored in
-- WowAssistantCharDB.meterFights (the newest 200) in the same shape as the combat-log fights of
-- Fights.lua, and the Harc page shows it at once.
--
-- /wa meter      what the client gave for the last fight (for debugging)

local _, WA = ...
local MT = {}
WA.Meter = MT
local KEEP = 200
local TICK = 0.5
local ATTRIBUTE = 0.4 -- seconds after a cast in which a hit on the target belongs to that cast
local MAX_CASTS = 400

local FINISHERS = { Eviscerate = true, ["Slice and Dice"] = true, Rupture = true, ["Kidney Shot"] = true, ["Expose Armor"] = true }
-- Casts that do not hit the target themselves.
local NO_HIT = { ["Slice and Dice"] = true, Stealth = true, Vanish = true, Sprint = true, Evasion = true,
  ["Blade Flurry"] = true, ["Adrenaline Rush"] = true, ["Cold Blood"] = true, Preparation = true, Distract = true,
  ["Pick Pocket"] = true, Sap = true, ["Instant Poison"] = true, ["Deadly Poison"] = true, ["Crippling Poison"] = true }

local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function Num(v)
  if Secret(v) or v == nil then return nil end
  return tonumber(v)
end
local function Str(v)
  if Secret(v) or v == nil then return nil end
  return type(v) == "string" and v or nil
end

local function Call(name, ...)
  local api = C_DamageMeter
  local fn = api and api[name]
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if not ok then return nil end
  return a, b
end

local function EnumValue(group, key)
  local e = Enum and Enum[group]
  return e and e[key]
end

local function SpellName(id)
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellName then
    local ok, n = pcall(C_Spell.GetSpellName, id)
    if ok and Str(n) then return n end
  end
  if GetSpellInfo then
    local ok, n = pcall(GetSpellInfo, id)
    if ok and Str(n) then return n end
  end
  return nil
end

local POWER_ENERGY = 3
local POWER_CP = 4
local function Power(kind)
  local ok, v = pcall(UnitPower, "player", kind)
  return ok and Num(v) or nil
end
local function PowerMax(kind)
  local ok, v = pcall(UnitPowerMax, "player", kind)
  return ok and Num(v) or nil
end

---------------------------------------------------------------------------
-- the fight in progress
---------------------------------------------------------------------------
local fight
MT.last = nil -- what the client gave for the last fight, for /wa meter

local function Ability(name)
  local a = fight.ab[name]
  if not a then
    a = { name = name, n = 0, dmg = 0, hit = 0, crit = 0, glance = 0, miss = 0, dodge = 0, parry = 0, block = 0, other = 0, max = 0 }
    fight.ab[name] = a
    fight.order[#fight.order + 1] = name
  end
  return a
end

local function InGroup()
  if not IsInGroup then return false end
  local g = IsInGroup()
  if Secret(g) then return nil end
  return g and true or false
end

-- The target's name when it is an enemy. Any secret answer (in combat) counts as "no".
local function EnemyTarget()
  -- In combat UnitExists/UnitCanAttack may be secret while the name is not: a readable name is
  -- enough, unless the client says plainly that the target is not an enemy.
  local name = Str(UnitName("target"))
  if not name then return nil end
  local c = UnitCanAttack("player", "target")
  if not Secret(c) and not c then return nil end
  return name
end

-- The last enemy you targeted while its name could be read (usually just before the pull).
local lastTarget
local function RememberTarget()
  local name = EnemyTarget()
  if name then lastTarget = { name = name, level = Num(UnitLevel("target")) or 0, at = GetTime() } end
end
local function TargetNow()
  local name = EnemyTarget()
  if name then return name, Num(UnitLevel("target")) or 0 end
  if lastTarget and GetTime() - lastTarget.at < 60 then return lastTarget.name, lastTarget.level end
  return nil, 0
end

local function Begin()
  local name, level = TargetNow()
  fight = {
    start = time(), t0 = GetTime(), target = name, targetLevel = level,
    level = Num(UnitLevel("player")) or 0, casts = {}, ab = {}, order = {}, samples = 0, capped = 0, auras = {}, auraOrder = {},
    cp = Power(POWER_CP) or 0, spent = 0, spentAt = 0, pending = nil, events = 0, secret = 0,
    solo = InGroup() == false,
  }
end

local function OnCast(spellID)
  if not fight then return end
  local name = SpellName(Num(spellID))
  if not name then return end
  local now = GetTime()
  local cp = fight.cp
  if FINISHERS[name] and cp == 0 and now - fight.spentAt < 1 then cp = fight.spent end
  if #fight.casts < MAX_CASTS then
    fight.casts[#fight.casts + 1] = { math.floor((now - fight.t0) * 10 + 0.5), name, Power(POWER_ENERGY) or -1, cp }
  end
  if not fight.target then
    local t, l = TargetNow()
    fight.target, fight.targetLevel = t, l
  end
  if not NO_HIT[name] then
    fight.pending = { name = name, at = now }
    Ability(name).n = Ability(name).n + 1
  end
end

local function OnPower(kind)
  if not fight or kind ~= "COMBO_POINTS" then return end
  local cp = Power(POWER_CP)
  if not cp then return end
  if cp < fight.cp then fight.spent, fight.spentAt = fight.cp, GetTime() end
  fight.cp = cp
end

-- What happened to the target: action is WOUND, MISS, DODGE, PARRY, BLOCK, ...; flag CRITICAL,
-- GLANCING, CRUSHING or ""; school 1 is physical.
local function OnTargetHit(unit, action, flag, amount, school)
  if not fight or unit ~= "target" or not fight.solo then return end
  if Secret(action) or Secret(flag) then fight.secret = fight.secret + 1 return end
  if action == "HEAL" or action == "ENERGIZE" then return end
  fight.events = fight.events + 1
  local now = GetTime()
  local name
  local p = fight.pending
  if p and now - p.at <= ATTRIBUTE then
    name = p.name
    fight.pending = nil
  elseif Num(school) and Num(school) ~= 1 then
    name = "Other"
  else
    name = "Melee"
  end
  local a = Ability(name)
  if name == "Melee" or name == "Other" then a.n = a.n + 1 end
  local dmg = Num(amount)
  if action == "WOUND" then
    if flag == "CRITICAL" then a.crit = a.crit + 1
    elseif flag == "GLANCING" then a.glance = a.glance + 1
    else a.hit = a.hit + 1 end
    if dmg then
      a.dmg = a.dmg + dmg
      if dmg > a.max then a.max = dmg end
    end
  elseif action == "MISS" then a.miss = a.miss + 1
  elseif action == "DODGE" then a.dodge = a.dodge + 1
  elseif action == "PARRY" then a.parry = a.parry + 1
  elseif action == "BLOCK" then a.block = a.block + 1
  else a.other = a.other + 1 end
end

local function Sample()
  if not fight then return end
  fight.samples = fight.samples + 1
  local e, m = Power(POWER_ENERGY), PowerMax(POWER_ENERGY)
  if e and m and m > 0 and e >= m then fight.capped = fight.capped + 1 end
  local seen = {}
  for i = 1, 40 do
    local name
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
      if not ok or Secret(d) or not d then break end
      name = Str(d.name)
    elseif UnitBuff then
      local n = UnitBuff("player", i)
      if Secret(n) or not n then break end
      name = Str(n)
    else
      break
    end
    if name and not seen[name] then
      seen[name] = true
      if not fight.auras[name] then fight.auras[name] = 0 fight.auraOrder[#fight.auraOrder + 1] = name end
      fight.auras[name] = fight.auras[name] + TICK
    end
  end
end

-- The damage meter's view of the fight that just ended: total, length, damage per spell.
local function MeterTotals()
  if not C_DamageMeter then return nil end
  local damage = EnumValue("DamageMeterType", "DamageDone")
  local current = EnumValue("DamageMeterSessionType", "Current")
  if damage == nil or current == nil then return nil end
  local session = Call("GetCombatSessionFromType", current, damage)
  MT.last = { session = session, at = time() }
  if type(session) ~= "table" then return nil end
  local me
  for _, s in ipairs(type(session.combatSources) == "table" and session.combatSources or {}) do
    if type(s) == "table" and s.isLocalPlayer == true then me = s break end
  end
  if not me then return nil end
  local out = { total = Num(me.totalAmount), dur = Num(session.durationSeconds) or Num((Call("GetSessionDurationSeconds", current))), spells = {} }
  local src = Call("GetCombatSessionSourceFromType", current, damage, UnitGUID("player"), nil)
  MT.last.source = src
  for _, sp in ipairs(type(src) == "table" and type(src.combatSpells) == "table" and src.combatSpells or {}) do
    local id = Num(sp.spellID)
    local name = SpellName(id) or (id == nil and "Melee") or nil
    if id == 6603 then name = "Melee" end
    local amount = Num(sp.totalAmount)
    if name and amount then out.spells[name] = (out.spells[name] or 0) + amount end
  end
  return out
end

local function Finish()
  local f = fight
  fight = nil
  if not f then return end
  local m = MeterTotals()
  local dur = (m and m.dur and m.dur > 0) and m.dur or (GetTime() - f.t0)
  if dur < 1 then return end
  -- exact damage per spell from the meter, counts from what the target took
  if m then
    for name, amount in pairs(m.spells) do
      local a = f.ab[name]
      if not a then
        a = { name = name, n = 0, dmg = 0, hit = 0, crit = 0, glance = 0, miss = 0, dodge = 0, parry = 0, block = 0, other = 0, max = 0 }
        f.ab[name] = a
        f.order[#f.order + 1] = name
      end
      a.dmg = amount
    end
  end
  local ab, total = {}, 0
  for _, name in ipairs(f.order) do
    local a = f.ab[name]
    if a.n > 0 or a.dmg > 0 then ab[#ab + 1] = a total = total + a.dmg end
  end
  local dmg = (m and m.total and m.total > 0) and m.total or total
  -- no damage dealt (running away, a potion and Evasion): nothing to score, and it would only push
  -- a 0 DPS "D" to the top of the list
  if dmg <= 0 then return end
  local auras = {}
  for _, name in ipairs(f.auraOrder) do auras[#auras + 1] = { name, f.auras[name] } end
  local list = WA.charDB.meterFights
  list[#list + 1] = {
    start = f.start, dur = math.floor(dur * 10 + 0.5) / 10, dmg = dmg, target = f.target or "?", targetLevel = f.targetLevel or 0,
    level = f.level, capped = f.capped, samples = f.samples, source = "live", detailed = (f.events >= 5) or nil,
    ab = ab, casts = f.casts, auras = auras, events = f.events, secret = f.secret > 0 and f.secret or nil,
  }
  while #list > KEEP do table.remove(list, 1) end
  if MT.last then MT.last.events, MT.last.secret, MT.last.casts = f.events, f.secret, #f.casts end
  if WA.OnFight then WA.OnFight() end
end

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local acc = 0
frame:SetScript("OnUpdate", function(_, elapsed)
  if not fight then return end
  acc = acc + elapsed
  if acc >= TICK then acc = acc - TICK Sample() end
end)
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_REGEN_DISABLED" then
    Begin()
    acc = 0
  elseif event == "PLAYER_REGEN_ENABLED" then
    -- the meter's numbers stop being secret once combat is over; give it a moment to settle
    if fight then fight.ended = GetTime() end
    C_Timer.After(1, Finish)
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local unit, _, spellID = ...
    if unit == "player" then OnCast(spellID) end
  elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" then
    local unit, kind = ...
    if unit == "player" then OnPower(kind) end
  elseif event == "UNIT_COMBAT" then
    OnTargetHit(...)
  elseif event == "PLAYER_TARGET_CHANGED" then
    RememberTarget()
  end
end)

table.insert(WA.onLoad, function()
  WA.charDB.meterFights = WA.charDB.meterFights or {}
  -- fights saved before 2.2.1 could have no damage at all
  local list = WA.charDB.meterFights
  for i = #list, 1, -1 do if (tonumber(list[i].dmg) or 0) <= 0 then table.remove(list, i) end end
  for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_POWER_FREQUENT", "UNIT_COMBAT", "PLAYER_TARGET_CHANGED" }) do
    pcall(frame.RegisterEvent, frame, e)
  end
end)

---------------------------------------------------------------------------
-- /wa meter
---------------------------------------------------------------------------
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
  local print = function(s) DEFAULT_CHAT_FRAME:AddMessage("|cffd4a24cWA meter|r " .. WA.Fix(s)) end
  print(("Rögzített harcok: %d"):format(#(WA.charDB.meterFights or {})))
  local last = WA.charDB.meterFights and WA.charDB.meterFights[#WA.charDB.meterFights]
  if last then
    print(("Utolsó: %s, %.1f mp, %d sebzés, %d cast, %d találat a célponton%s"):format(last.target, last.dur, last.dmg,
      #(last.casts or {}), last.events or 0, last.secret and (", " .. last.secret .. " titkos érték") or ""))
  end
  if not C_DamageMeter then print("ez a kliens nem ad damage meter API-t.") return end
  local fns = {}
  for k, v in pairs(C_DamageMeter) do if type(v) == "function" then fns[#fns + 1] = k end end
  table.sort(fns)
  print("API: " .. table.concat(fns, ", "))
  if not MT.last then print("Még nem volt harc ebben a munkamenetben.") return end
  local out = {}
  Dump(MT.last, "  ", 0, out)
  for _, line in ipairs(out) do print(line) end
end, "/wa meter – mit adott a kliens az utolsó harcról (hibakereséshez)")
