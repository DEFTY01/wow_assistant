-- Enchants for the gear you wear, chosen for your role: damage for a damage dealer, survival for a
-- tank, healing for a healer. The enchants and what they give come from Enchants.lua
-- (scripts/build-enchants.mjs, the Wowhead Forever spell tooltips).
--
-- How an enchant is valued:
--   * damage dealer of a class the addon's damage model knows: the DPS it adds, the model's own
--     number (ctx.score with the slot's item plus the enchant), the same as on the gear list;
--   * every other case: the stat weights (EP) WoWSims Forever publishes for that spec, a point of
--     each stat in the spec's own scale. Where a spec has none (Holy Paladin, Restoration Druid and
--     Shaman, Protection Paladin) the nearest spec's weights are used and the page says whose.
-- The enchant's numbers are converted to the engine's units with its own constants (WoWSims
-- Forever d5144855 sim/core/base_stats_auto_gen.go: 14 crit rating = 1% crit, 12 dodge rating =
-- 1% dodge, 5 block rating = 1% block, 10 haste rating = 1% haste, 10 hit rating = 1% hit,
-- 1 defense rating = 1 defense; sim/core/character.go: 10 health per stamina).
-- Procs (Crusader, Fiery Weapon) are listed, not valued: how often they happen is not stated.
local _, WA = ...
local L = WA.L
local E = {}
WA.Enchant = E

E.SIM = "WoWSims Forever d5144855"
E.RATING = { crit = 14, dodge = 12, block = 5, haste = 10, hit = 10 }
E.HEALTH_PER_STA = 10

-- Weights per spec, as the engine's presets give them (a point of stat or rating; mhDps: one point
-- of main-hand weapon DPS). Only the stats an enchant can give are kept.
E.PROFILES = {
  BEAR = { name = "Feral (Bear) tank", source = "ui/specs/druid/feral_ep.ts BearEp", w = {
    str = 0.486, agi = 0.433, sta = 1.003, ap = 0.221, hit = 0.688, crit = 0.363, haste = 0.358, def = 0.876, dodge = 0.107,
    armor = 0.174, mhDps = 3.093 } },
  WARRIOR_PROT = { name = "Protection Warrior", source = "ui/specs/warrior/protection/presets.ts Pre-BiS - Balanced", w = {
    sta = 1.15, str = 0.62, agi = 0.66, ap = 0.27, hit = 0.04, crit = 0.43, haste = 0.17, def = 0.53, block = 0, dodge = 0.29,
    armor = 0.06, mhDps = 1.42 } },
  PRIEST_HOLY = { name = "Holy Priest", source = "ui/specs/priest/healer/presets.ts Holy Single-Target", w = {
    heal = 1.0, crit = 0.3, haste = 0.5, int = 0.35, spi = 0.3, mp5 = 0.6 } },
  PRIEST_DISC = { name = "Discipline Priest", source = "ui/specs/priest/healer/presets.ts Disc Single-Target", w = {
    heal = 1.0, crit = 0.7, haste = 0.15, int = 0.2, spi = 0.15, mp5 = 0.4 } },
  SHADOW = { name = "Shadow Priest", source = "ui/specs/priest/dps/presets.ts Shadow", w = {
    int = 0.26, sp = 1.0, sp_shadow = 1.0, hit = 1.2, crit = 0.99, haste = -0.09, mp5 = 0.01 } },
  RET = { name = "Retribution Paladin", source = "ui/specs/paladin/retribution/presets.ts Holy Shock", w = {
    str = 2.4, agi = 1.91, int = 1.77, sp = 2.47, sp_holy = 2.06, ap = 1, hit = 7.23, crit = 3, haste = 2.73, mp5 = 0.01, mhDps = 14.02 } },
  FURY = { name = "Fury Warrior", source = "ui/specs/warrior/dps/presets.ts Pre-BiS - Fury", w = {
    str = 2.2, agi = 1.7, ap = 1, hit = 1.69, haste = 1.76, crit = 2.26, mhDps = 12.59 } },
  ARMS = { name = "Arms Warrior", source = "ui/specs/warrior/dps/presets.ts Pre-BiS - Arms", w = {
    str = 2.2, agi = 1.76, ap = 1, hit = 5.03, haste = 1.29, crit = 2.32, mhDps = 16.71 } },
}

-- talent tab (1-3) -> role, by class; a tab not listed is a damage dealer
local HEALER_TABS = { DRUID = { [3] = true }, PALADIN = { [1] = true }, PRIEST = { [1] = true, [2] = true }, SHAMAN = { [3] = true } }
local TANK_TABS = { WARRIOR = { [3] = true }, PALADIN = { [2] = true } }
E.ROLE_HU = WA.LR { dps = L"Damage (DPS)", tank = "Tank", healer = L"Healer" }

-- role, reason. override: "dps" / "tank" / "healer" chosen on the page; form: the druid's form now.
function E.Role(class, tab, form, override)
  if override == "dps" or override == "tank" or override == "healer" then return override, L"chosen by hand" end
  if not tab then return "dps", L"you have no talent points yet: counting as damage" end
  if HEALER_TABS[class] and HEALER_TABS[class][tab] then return "healer", L"most of your talent points are in a healer tree" end
  if TANK_TABS[class] and TANK_TABS[class][tab] then return "tank", L"most of your talent points are in a tank tree" end
  if class == "DRUID" and tab == 2 then
    if form == "bear" then return "tank", L"Feral tree, and you are in Bear Form now" end
    return "dps", L"Feral tree, not in Bear Form: counting as Cat damage (pick Tank for tanking)"
  end
  return "dps", L"most of your talent points are in a damage tree"
end

-- The weights for a role, or nil when the damage model values it (or nothing does).
function E.Profile(class, tab, role, hasModel)
  if role == "tank" then
    if class == "DRUID" then return E.PROFILES.BEAR end
    if class == "WARRIOR" then return E.PROFILES.WARRIOR_PROT end
    return E.PROFILES.WARRIOR_PROT, "a " .. (class or "?") .. L" tank has no weight table of its own: using the Protection Warrior's"
  end
  if role == "healer" then
    if class == "PRIEST" and tab == 1 then return E.PROFILES.PRIEST_DISC end
    if class == "PRIEST" then return E.PROFILES.PRIEST_HOLY end
    return E.PROFILES.PRIEST_HOLY, L"this healer has no weight table of its own: using the Holy Priest's"
  end
  if hasModel then return nil end
  if class == "PRIEST" then return E.PROFILES.SHADOW end
  if class == "PALADIN" then return E.PROFILES.RET end
  if class == "WARRIOR" then return tab == 1 and E.PROFILES.ARMS or E.PROFILES.FURY end
  return nil
end

-- An enchant's value with weights: the sum of weight x amount, the amount in the engine's units.
-- weaponSpeed: the item's speed, for flat weapon damage (N damage / speed = DPS).
function E.Weighted(stats, w, weaponSpeed)
  local v, parts = 0, {}
  for k, amount in pairs(stats) do
    local key, units = k, amount
    if E.RATING[k] then units = amount * E.RATING[k] end
    if k == "dmg" then key, units = "mhDps", (weaponSpeed and weaponSpeed > 0) and amount / weaponSpeed or 0 end
    local weight = w[key]
    if weight and weight ~= 0 and units ~= 0 then
      v = v + weight * units
      parts[#parts + 1] = ("%s %s × %s"):format(key, WA.Model.Round and WA.Model.Round(units * 100) / 100 or units, weight)
    end
  end
  table.sort(parts)
  return v, table.concat(parts, " + ")
end

local STAT_HU = WA.LR { str = "Strength", agi = "Agility", sta = "Stamina", int = "Intellect", spi = "Spirit", armor = L"armor", def = "Defense",
  dodge = "% dodge", block = "% block", heal = L"healing", sp = "spell damage", mp5 = L"mana / 5 s", dmg = L"weapon damage",
  crit = "% crit", haste = L"% haste", resAll = L"all resistances", run = L"% run speed", threat = "% threat" }
function E.Describe(stats)
  local bits = {}
  for k, v in pairs(stats) do
    local school = k:match("^sp_(%a+)") or k:match("^res_(%a+)")
    local label = school and (k:find("^sp_") and (school .. " spell damage") or (school .. L" resistance")) or STAT_HU[k] or k
    bits[#bits + 1] = ((v > 0 and "+" or "") .. v .. (label:sub(1, 1) == "%" and "" or " ") .. label)
  end
  table.sort(bits)
  return table.concat(bits, ", ")
end

-- the school a class's damage model counts as its spell damage
local SCHOOL = { WARLOCK = "shadow", SHAMAN = "nature", DRUID = "nature" }

local RANGED_SUB = { [2] = true, [3] = true, [16] = true, [18] = true, [19] = true, [20] = true }
-- Can this enchant go on the item in this slot? item: { classID, sub, equipLoc }
function E.Fits(e, slot, item)
  if not item then return false end
  local group = slot:gsub("_[12]$", "")
  if e.slot == "MAIN_HAND" then
    if slot ~= "MAIN_HAND" and slot ~= "OFF_HAND" then return false end
    if item.classID ~= 2 or RANGED_SUB[item.sub or -1] then return false end
    if e.twoHand then return slot == "MAIN_HAND" and item.equipLoc == "INVTYPE_2HWEAPON" end
    return true
  end
  if e.slot == "OFF_HAND" then return slot == "OFF_HAND" and item.classID == 4 and item.sub == 6 end
  return e.slot == group
end

-- rows of Enchants.lua -> records
function E.List()
  local out = {}
  for _, r in ipairs(_G.WowAssistantEnchants or {}) do
    out[#out + 1] = { spell = r[1], slot = r[2], twoHand = r[3], name = r[4], skill = r[5], trainerCost = r[6], reagents = r[7],
      stats = r[8] or {}, proc = r[9], text = r[10] }
  end
  return out
end

local function Cost(reagents, book)
  if not book then return nil end
  local total, missing = 0, false
  for i = 1, #reagents, 2 do
    local u = book.unit(reagents[i])
    if u then total = total + u.price * (reagents[i + 1] or 1) else missing = true end
  end
  return total, missing
end

-- input: { class, level, tab, form, override, equipped (slot -> { name, link, stats, item = { classID, sub,
--   equipLoc }, enchant }), slotOrder, ctx (the damage model's, or nil), book }
-- -> { role, reason, profile, borrowed, unit ("DPS" / "EP"), slots = { { slot, current, enchant, best = { ... } } },
--      procs = { names }, missing (no Enchants.lua) }
function E.Report(input)
  local role, reason = E.Role(input.class, input.tab, input.form, input.override)
  local ctx = input.ctx
  local useModel = role == "dps" and ctx ~= nil
  local profile, borrowed = E.Profile(input.class, input.tab, role, useModel)
  local out = { role = role, reason = reason, profile = profile, borrowed = borrowed, unit = useModel and "DPS" or "EP",
    useModel = useModel, slots = {}, procs = {}, missing = _G.WowAssistantEnchants == nil }
  local list = E.List()
  local procSeen = {}
  for _, slot in ipairs(input.slotOrder or {}) do
    local it = input.equipped[slot]
    if it and it.item then
      local best = {}
      for _, e in ipairs(list) do
        if E.Fits(e, slot, it.item) then
          if e.proc then
            if not procSeen[e.name] then procSeen[e.name] = true out.procs[#out.procs + 1] = e.name end
          elseif next(e.stats) then
            local value, how
            local speed = it.stats and it.stats.weapon and it.stats.weapon.speed
            if useModel then
              local add = {}
              for k, v in pairs(it.stats or WA.Model.ZERO) do add[k] = v end
              for k in pairs(WA.Model.ZERO) do add[k] = (add[k] or 0) + (e.stats[k] or 0) end
              local sname = SCHOOL[input.class] or (ctx.params and ctx.params.school)
              local school = sname and e.stats["sp_" .. sname]
              if school then add.sp = add.sp + school end
              local w = it.stats and it.stats.weapon
              if w then add.weapon = { min = w.min + (e.stats.dmg or 0), max = w.max + (e.stats.dmg or 0), speed = w.speed } end
              local s = ctx.score(add, { slot }, it.item.equipLoc == "INVTYPE_2HWEAPON", it.item.sub)
              value = s and s.gain or 0
              how = L"the damage model: your item + the enchant"
            elseif profile then
              value, how = E.Weighted(e.stats, profile.w, speed)
            end
            if value and value > 0.005 then
              local cost, partial = Cost(e.reagents, input.book)
              local detail = e.text .. "\n" .. (how or "")
              if role == "tank" and e.stats.sta then detail = detail .. (L"\n+%d health (%d HP / Stamina)"):format(e.stats.sta * E.HEALTH_PER_STA, E.HEALTH_PER_STA) end
              best[#best + 1] = { spell = e.spell, name = e.name, value = value, effect = E.Describe(e.stats), cost = cost, partial = partial,
                skill = e.skill, trainer = e.trainerCost >= 0, detail = detail }
            end
          end
        end
      end
      table.sort(best, function(a, b)
        if math.abs(a.value - b.value) > 1e-6 then return a.value > b.value end
        return (a.cost or math.huge) < (b.cost or math.huge)
      end)
      for i = #best, 4, -1 do best[i] = nil end
      out.slots[#out.slots + 1] = { slot = slot, current = it.name, enchant = it.enchant, best = best }
    end
  end
  table.sort(out.procs)
  return out
end

