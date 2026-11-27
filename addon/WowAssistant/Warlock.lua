-- Waystone: the warlock damage model, levels 1-60 (affliction-style leveling: DoTs, Shadow Bolt,
-- a demon, a wand between casts, Life Tap for mana). Pure like Model.lua and Shaman.lua: the same
-- context shape (score, describe, buffGain, weaponWarning, ...) so the plan, the gear report and
-- the pages work for warlocks unchanged.
--
-- Forever rules the model follows (Wowhead Forever and WoWSims Forever d5144855, 2026-11-26):
--   * Shadow Bolt: 1.7 s cast, 0.486 of spell power (Wowhead Forever spell=686)
--   * Corruption 12 s and Immolate 15 s, a tick every 3 s; Bane of Agony 24 s, a tick every 2 s,
--     its ticks ramp (half, full, one and a half); Siphon Life 30 s, every 3 s (spell=172, 348,
--     980, 18265; sim/warlock/agony.go); only one Bane per target (sim/warlock/bane_of_havoc.go,
--     agony.go deactivateOtherBanes)
--   * Wrack, a channel, makes your DoTs on the target tick faster while it lasts (sim/warlock/
--     wrack.go): tick counts then overstate the uptime
--   * Life Tap turns health into mana, and mana over the maximum is lost (sim/warlock/lifetap.go,
--     sim/core/mana.go AddMana: new mana = min(old + gained, maximum))
--   * the demon inherits from you: AP 0.17 S, spell damage 0.10 S, S = spell damage + max(shadow,
--     fire) (sim/warlock/pets.go; Combat.lua C.REF.WarlockDemon)
--   * a wand's damage does not grow with spell power
--
-- Extra input besides Model.lua's: int, sp (shadow spell power), spellCrit (shadow), spellCritFire,
-- spellHit, talents = Talent.lua's T.Effects (the numbers of the rank's Wowhead Forever text):
-- shadowMastery, agonizing (school damage %), ruin (Destruction crit bonus %), malevolence (shadow
-- crit %), aftermath (Immolate's direct hit %), impCorruption, impAgony, impDrains (their damage %),
-- unholyPower (demon %), suppression and demonicKnowledge (already on the sheet).
--
-- The school talents work on shares: how much of your direct spells and of your DoTs and drains is
-- shadow, Destruction, Immolate, Corruption, Bane of Agony or a drain, from your fights (before
-- any fight: Shadow Bolt and a Corruption-like DoT, the model's own priors).

local _, WA = ...
local L = WA.L
WA = WA or {}
local M = WA.Model
local W = {}
WA.Warlock = W

local function F1(n) return ("%.1f"):format(n) end
local Round = M.Round

W.NUKES = { ["Shadow Bolt"] = true, ["Searing Pain"] = true, Shadowburn = true, ["Soul Fire"] = true, Incinerate = true,
  Conflagrate = true, ["Death Coil"] = true, Immolate = true, Hellfire = true, ["Hellfire Effect"] = true, ["Rain of Fire"] = true }
-- channels: the drains, and Wrack, which deals damage of its own while it speeds up your DoTs
W.DRAIN = { ["Drain Life"] = true, ["Drain Soul"] = true, ["Drain Mana"] = true, Wrack = true }
-- DoT tick interval in seconds (Wowhead Forever spell=172, 348, 980, 18265)
W.DOT_TICK = { Corruption = 3, Immolate = 3, ["Bane of Agony"] = 2, ["Siphon Life"] = 3 }
-- schools and trees of the spells, for the talents that work on one of them (Wowhead Forever)
W.SHADOW = { ["Shadow Bolt"] = true, Shadowburn = true, ["Death Coil"] = true, Corruption = true, ["Bane of Agony"] = true,
  ["Bane of Doom"] = true, ["Siphon Life"] = true, ["Drain Life"] = true, ["Drain Soul"] = true, ["Drain Mana"] = true, Wrack = true }
W.DESTRUCTION = { ["Shadow Bolt"] = true, Shadowburn = true, Immolate = true, ["Searing Pain"] = true, ["Soul Fire"] = true,
  Incinerate = true, Conflagrate = true, Hellfire = true, ["Hellfire Effect"] = true, ["Rain of Fire"] = true }
W.SB_CAST = 1.7
W.SB_COEF = 0.486
W.DOT_SP_PER_SEC = 0.2 / 3

local function Base(name) return ((name or ""):gsub(" %(dot%)$", "")) end
local function IsDot(name) return (name or ""):sub(-6) == " (dot)" end

-- pet, wand, drain, dot, nuke, melee, other
local function Kind(name)
  name = name or ""
  local base = Base(name)
  if base:sub(1, 5) == "Pet: " then return "pet" end
  if name == "Shoot" then return "wand" end
  if W.DRAIN[base] then return "drain" end
  if IsDot(name) then return "dot" end
  if W.NUKES[base] then return "nuke" end
  if name == "Melee" then return "melee" end
  return "other"
end
W.Kind = Kind

local function WandDps(w) return w and w.speed and w.speed > 0 and (w.min + w.max) / 2 / w.speed or 0 end
W.WandDps = WandDps

---------------------------------------------------------------------------
-- the model
---------------------------------------------------------------------------
function W.Dps(sh, p)
  local scrit = math.max(0, math.min(sh.spellCrit + (p.critAdd or 0), 100)) / 100
  local miss = math.max(1, p.spellMiss - (sh.spellHit or 0)) / 100
  local sf = (1 - miss) * (1 + scrit * ((p.critMult or 1.5) - 1))
  local total = p.otherDps + p.petDps
  total = total + p.nukePerSec * (p.nukeDamage + W.SB_COEF * sh.sp) * sf * (p.nukeMult or 1)
  -- one DoT's worth of spell power a second: Corruption gives 0.2 of it a tick, every 3 s
  total = total + (p.dotDps + W.DOT_SP_PER_SEC * sh.sp) * (1 - miss) * (p.dotMult or 1)
  total = total + p.wandUptime * WandDps(sh.wand) * (1 - miss)
  return total
end

local function Apply(sh, remove, add, p)
  local dInt = ((add.int or 0) - (remove.int or 0)) * p.statMult
  return {
    sp = sh.sp + (add.sp or 0) - (remove.sp or 0),
    spellCrit = sh.spellCrit + dInt / p.intPerCrit,
    spellHit = sh.spellHit, wand = sh.wand, ap = sh.ap, crit = sh.crit, hit = sh.hit, mh = sh.mh,
  }
end

---------------------------------------------------------------------------
-- context
---------------------------------------------------------------------------
function W.Context(input)
  local level = input.level or 1
  local equipped = input.equipped or {}
  local notes = {}
  local function eq(slot) return equipped[slot] and equipped[slot].stats or M.ZERO end
  local intPerCrit = 6 + (54 * (level - 1)) / 59
  local tal = input.talents or {}

  local wand = eq("RANGED").weapon
  local sheet = { sp = input.sp or 0, spellCrit = input.spellCrit or 0, spellHit = input.spellHit or 0, wand = wand,
    ap = input.ap or 0, crit = input.crit or 0, hit = input.hit or 0, mh = eq("MAIN_HAND").weapon }
  notes[#notes + 1] = (L"Shadow Bolt 1.7 s, with 48.6%% of spell power (Wowhead Forever); 1%% spell crit ≈ %s intellect. The wand is %s DPS, which does not grow with spell power.")
    :format(F1(intPerCrit), F1(WandDps(wand)))

  -- priors: a Shadow Bolt-sized cast every 4 s (DoTs, Life Tap, moving between), the DoTs a
  -- quarter of the spell damage, the demon about 0.6 DPS a level, the wand a fifth of the time
  local params = {
    level = level, intPerCrit = intPerCrit, statMult = 1, spellMiss = 4,
    nukePerSec = 1 / 4, nukeDamage = 13 + 8.4 * (level - 1),
    dotDps = 0,
    petDps = level >= 1 and 0.6 * level or 0,
    wandUptime = wand and 0.2 or 0,
    otherDps = 0, notes = notes,
  }
  params.dotDps = 0.25 * params.nukePerSec * params.nukeDamage
  params.petDps = params.petDps * (1 + (tal.unholyPower or 0) / 100)

  -- the school shares (priors: Shadow Bolt, a Corruption-like DoT), measured below
  local share = { nShadow = 1, nDestr = 1, nImmolate = 0, dShadow = 1, dDestr = 0, dCorruption = 1, dAgony = 0, dDrain = 0 }
  local function Mults()
    params.nukeMult = 1 + (share.nShadow * (tal.shadowMastery or 0) + share.nDestr * (tal.agonizing or 0) + share.nImmolate * (tal.aftermath or 0)) / 100
    params.dotMult = 1 + (share.dShadow * (tal.shadowMastery or 0) + share.dDestr * (tal.agonizing or 0) + share.dCorruption * (tal.impCorruption or 0)
      + share.dAgony * (tal.impAgony or 0) + share.dDrain * (tal.impDrains or 0)) / 100
    params.critMult = 1.5 + 0.5 * share.nDestr * (tal.ruin or 0) / 100
    -- Malevolence is shadow crit: when the client's shadow crit is not above its fire crit by that
    -- much, the sheet does not have it
    local gap = (input.spellCrit or 0) - (input.spellCritFire or 0)
    local onSheet = input.spellCritFire ~= nil and gap >= (tal.malevolence or 0) - 0.05
    params.critAdd = (not onSheet) and share.nShadow * (tal.malevolence or 0) or 0
  end
  Mults()

  local combat = input.combat
  local function mix(prior, measured, n, half)
    local w = n / (n + half)
    return prior * (1 - w) + measured * w
  end
  local function landed(a) return (a.hit or 0) + (a.crit or 0) + (a.glance or 0) end
  if combat and combat.seconds > 0 then
    local secs = combat.seconds
    local nukes, nukeDmg, nukeLanded, nukeCrit, nukeMiss, dot, pet, wandN, other = 0, 0, 0, 0, 0, 0, 0, 0, 0
    local by = { nShadow = 0, nDestr = 0, nImmolate = 0, dShadow = 0, dDestr = 0, dCorruption = 0, dAgony = 0, dDrain = 0 }
    for _, a in ipairs(combat.abilities) do
      local k = Kind(a.name)
      local b = Base(a.name)
      if k == "nuke" then
        nukes, nukeDmg, nukeLanded, nukeCrit = nukes + a.n, nukeDmg + a.dmg, nukeLanded + landed(a), nukeCrit + (a.crit or 0)
        nukeMiss = nukeMiss + (a.miss or 0) + (a.other or 0)
        if W.SHADOW[b] then by.nShadow = by.nShadow + a.dmg end
        if W.DESTRUCTION[b] then by.nDestr = by.nDestr + a.dmg end
        if b == "Immolate" then by.nImmolate = by.nImmolate + a.dmg end
      elseif k == "dot" or k == "drain" then
        dot = dot + a.dmg
        if W.SHADOW[b] then by.dShadow = by.dShadow + a.dmg end
        if W.DESTRUCTION[b] then by.dDestr = by.dDestr + a.dmg end
        if b == "Corruption" then by.dCorruption = by.dCorruption + a.dmg end
        if b == "Bane of Agony" then by.dAgony = by.dAgony + a.dmg end
        if b == "Drain Life" or b == "Drain Soul" or b == "Drain Mana" then by.dDrain = by.dDrain + a.dmg end
      elseif k == "pet" then pet = pet + a.dmg
      elseif k == "wand" then wandN = wandN + a.n
      else other = other + a.dmg end
    end
    for key, v in pairs(by) do
      local total = key:sub(1, 1) == "n" and nukeDmg or dot
      if total > 0 then share[key] = mix(share[key], v / total, secs, 120) end
    end
    Mults()
    params.nukePerSec = mix(params.nukePerSec, nukes / secs, secs, 120)
    if nukeLanded > 0 then
      -- the logged damage has the school talents and Ruin's crit bonus in it
      local per = nukeDmg / (nukeLanded + (params.critMult - 1) * nukeCrit) / params.nukeMult
      params.nukeDamage = mix(params.nukeDamage, math.max(0, per - W.SB_COEF * sheet.sp), nukeLanded, 10)
    end
    if nukes > 0 then params.spellMiss = mix(params.spellMiss, nukeMiss / nukes * 100, nukes, 30) end
    params.dotDps = mix(params.dotDps, math.max(0, dot / secs / params.dotMult - W.DOT_SP_PER_SEC * sheet.sp), secs, 120)
    params.petDps = mix(params.petDps, pet / secs, secs, 120)
    if wand then params.wandUptime = mix(params.wandUptime, math.min(1, wandN / secs * wand.speed), secs, 120) end
    params.otherDps = mix(0, other / secs, secs, 120)
    notes[#notes + 1] = (L"Calibrated from %d recorded fights (%d s): %s direct spells per minute (%d damage without spell power), DoTs and drains %s DPS, demon %s DPS, wand %d%% of the time, other %s DPS.")
      :format(combat.fights, Round(secs), F1(params.nukePerSec * 60), Round(params.nukeDamage), F1(params.dotDps), F1(params.petDps),
        Round(params.wandUptime * 100), F1(params.otherDps))
  else
    notes[#notes + 1] = L"No recorded fights, so it uses textbook values. Turn on the combat log (/wa log) to calibrate."
  end
  notes[#notes + 1] = L"The model does not count mana (Life Tap refills it): intellect is only worth something for spell crit, spirit and stamina nothing."

  local unbuffed = W.Dps(sheet, params)
  local buffs = M.ResolveBuffs(level, input.buffs, input.data)
  local bInt, bSp = 0, 0
  for _, b in ipairs(buffs) do
    if b.selected and b.effect then bInt, bSp = bInt + (b.effect.int or 0), bSp + (b.effect.sp or 0) end
  end
  sheet.sp = sheet.sp + bSp
  sheet.spellCrit = sheet.spellCrit + bInt / intPerCrit
  local baseline = W.Dps(sheet, params)
  local equippedIds = {}
  for _, it in pairs(equipped) do if it.id then equippedIds[it.id] = true end end

  local ctx = M.Common({
    level = level, baseline = baseline, unbuffed = unbuffed, buffs = buffs, params = params, sheet = sheet,
    equipped = equipped, equippedIds = equippedIds, combat = combat, slotOrder = input.slotOrder,
  }, "WARLOCK")

  -- Best slot for an item and the DPS it adds there; nil when it is not an upgrade. A wand goes
  -- to the ranged slot; a melee weapon counts only for its stats.
  function ctx.score(add, slots, twoHand)
    local best
    for _, slot in ipairs(slots) do
      local remove = eq(slot)
      if twoHand then
        local oh = eq("OFF_HAND")
        remove = {}
        for k in pairs(M.ZERO) do remove[k] = (eq(slot)[k] or 0) + (oh[k] or 0) end
      end
      local sh = Apply(sheet, remove, add, params)
      if slot == "RANGED" then sh.wand = add.weapon end
      local gain = W.Dps(sh, params) - baseline
      if not best or gain > best.gain then best = { slot = slot, gain = gain } end
    end
    if best and best.gain > 0.05 then return best end
    return nil
  end

  function ctx.describe(add, weaponSub)
    local bits = {}
    if add.weapon then
      local w = add.weapon
      if weaponSub == 19 then
        bits[#bits + 1] = ("Wand %s DPS / %s"):format(F1(WandDps(w)), F1(w.speed))
      else
        bits[#bits + 1] = ("%s %s–%s / %s"):format(M.WEAPON_NAMES[weaponSub or -1] or "Weapon", w.min, w.max, F1(w.speed))
      end
    end
    if (add.sp or 0) ~= 0 then bits[#bits + 1] = ("+%s spell power"):format(add.sp) end
    if (add.int or 0) ~= 0 then bits[#bits + 1] = ("+%s int"):format(add.int) end
    if (add.crit or 0) ~= 0 then bits[#bits + 1] = ("+%s%% crit"):format(add.crit) end
    return table.concat(bits, ", ")
  end

  function ctx.buffGain(e)
    local add = { int = e.int or 0, sp = e.sp or 0 }
    local sh = Apply(sheet, M.ZERO, add, params)
    return W.Dps(sh, params) - baseline
  end

  function ctx.weaponWarning(itemClass, sub)
    if itemClass ~= 2 or sub == 19 then return nil end
    return nil
  end

  ctx.advice = {}
  return ctx
end

---------------------------------------------------------------------------
-- the combat page
---------------------------------------------------------------------------
local function Find(list, name)
  for _, a in ipairs(list or {}) do if a.name == name then return a end end
  return nil
end

function W.Sources(abilities, total)
  local out = { nuke = 0, dot = 0, drain = 0, pet = 0, wand = 0, melee = 0, other = 0 }
  for _, a in ipairs(abilities or {}) do
    local k = Kind(a.name)
    out[k] = out[k] + (a.dmg or 0)
  end
  local sum = 0
  for _, v in pairs(out) do sum = sum + v end
  if total and total > 0 then sum = total end
  local shares = {}
  for k, v in pairs(out) do shares[k] = sum > 0 and v / sum * 100 or 0 end
  return out, shares
end

-- DoT uptime from its ticks: ticks x the tick interval / the time (0-100), nil without ticks.
function W.DotUptime(abilities, name, seconds)
  local a = Find(abilities, name .. " (dot)")
  if not a or not seconds or seconds <= 0 then return nil end
  return math.min(100, a.n * W.DOT_TICK[name] / seconds * 100)
end

local function Wracked(casts)
  for _, c in ipairs(casts or {}) do if c[2] == "Wrack" then return true end end
  return false
end

-- the Life Taps of fights: gained, over (lost), the taps that lost at least half of what they gave
function W.Taps(fights)
  local out = { n = 0, gain = 0, over = 0, wasteful = {}, seen = 0 }
  for _, f in ipairs(fights or {}) do
    if type(f.taps) == "table" then
      out.seen = out.seen + 1
      for _, t in ipairs(f.taps) do
        local gain, over = tonumber(t.gain) or 0, tonumber(t.over) or 0
        out.n, out.gain, out.over = out.n + 1, out.gain + gain, out.over + over
        if gain > 0 and over * 2 >= gain then out.wasteful[#out.wasteful + 1] = { start = f.start, t = t } end
      end
    end
  end
  return out
end

local GRADES = { { 90, "S" }, { 80, "A" }, { 65, "B" }, { 50, "C" }, { 0, "D" } }
function W.Score(f, ctx)
  local parts = {}
  local function Part(key, label, got, max, text) parts[#parts + 1] = { key = key, label = label, points = got, max = max, text = text } end
  local dur = f.dur or 0
  local dps = dur > 0 and (f.dmg or 0) / dur or 0
  local baseline = ctx and WA.Combat.Comparable(f, ctx) and ctx.baseline or nil
  if baseline and baseline > 0 then
    local ratio = dps / baseline
    Part("dps", L"DPS against the expected", math.min(ratio / 1.1, 1) * 40, 40, (L"%d DPS against the %d your gear should give: %d%%"):format(
      Round(dps), Round(baseline), Round(ratio * 100)))
  end
  local ab = f.ab or {}
  if dur >= 6 then
    -- busy time: casts (a Shadow Bolt 1.7 s, anything else a 1.5 s global cooldown) and wand shots
    local busy = 0
    for _, c in ipairs(f.casts or {}) do
      if c[2] ~= "Shoot" and c[2] ~= "Life Tap" then busy = busy + (c[2] == "Shadow Bolt" and W.SB_CAST or 1.5) end
    end
    local shoot = Find(ab, "Shoot")
    local wand = ctx and ctx.sheet and ctx.sheet.wand
    if shoot and wand then busy = busy + shoot.n * wand.speed end
    local up = math.min(1, busy / dur)
    Part("active", L"You cast continuously", math.min(up / 0.8, 1) * 20, 20, (L"you were casting or wanding about %d%% of the time (from the casts and the shots)"):format(Round(up * 100)))
  end
  if dur >= 15 then
    local up = W.DotUptime(ab, "Corruption", dur)
    if up or Find(ab, "Immolate (dot)") or Find(ab, "Bane of Agony (dot)") then
      local best = math.max(up or 0, W.DotUptime(ab, "Bane of Agony", dur) or 0, W.DotUptime(ab, "Immolate", dur) or 0)
      Part("dot", L"DoT in longer fights", math.min(best / 70, 1) * 15, 15, (L"the longest-running DoT ticked about %d%% of the fight (from the ticks%s)")
        :format(Round(best), Wracked(f.casts) and (L"; leans high with Wrack") or ""))
    else
      Part("dot", L"DoT in longer fights", 0, 15, L"no DoT ticked in this fight longer than 15 s")
    end
  end
  if type(f.taps) == "table" and #f.taps > 0 then
    local gain, over = 0, 0
    for _, t in ipairs(f.taps) do gain, over = gain + (t.gain or 0), over + (t.over or 0) end
    local kept = gain > 0 and 1 - over / gain or 1
    Part("tap", L"No Life Tap wasted", kept * 15, 15, (L"%d Life Taps: %d mana, of which %d was lost over the maximum"):format(#f.taps, Round(gain), Round(over)))
  end
  local got, max = 0, 0
  for _, p in ipairs(parts) do got, max = got + p.points, max + p.max end
  if max == 0 then return nil end
  local total = math.floor(got / max * 100 + 0.5)
  local grade = "D"
  for _, g in ipairs(GRADES) do if total >= g[1] then grade = g[2] break end end
  return { total = total, grade = grade, parts = parts, dps = dps }
end

function W.Summary(r, ctx, fights)
  if not r then return nil end
  local src, share = W.Sources(r.abilities, r.damage)
  local secs = r.seconds
  local s = { sources = src, shares = share, seconds = secs, dps = r.dps, dots = {}, rows = {}, taps = W.Taps(fights) }
  for _, name in ipairs({ "Corruption", "Bane of Agony", "Immolate", "Siphon Life" }) do
    local up = W.DotUptime(r.abilities, name, secs)
    if up then s.dots[#s.dots + 1] = { name = name, uptime = up } end
  end
  table.sort(s.dots, function(a, b) return a.uptime > b.uptime end)
  for _, f in ipairs(fights or {}) do if Wracked(f.casts) then s.wrack = true break end end
  for _, a in ipairs(r.abilities) do
    local landed = (a.hit or 0) + (a.crit or 0) + (a.glance or 0)
    s.rows[#s.rows + 1] = { name = a.name, dmg = a.dmg, share = a.share, n = a.n, cpm = a.n / secs * 60,
      perCast = a.n > 0 and a.dmg / a.n or 0, avg = landed > 0 and a.dmg / landed or 0, kind = Kind(a.name) }
  end
  return s
end

local function Clock(start, tenths)
  local s = (start or 0) + (tonumber(tenths) or 0) / 10
  return date and date(L"%m/%d %H:%M:%S", math.floor(s)) or tostring(math.floor(s))
end

function W.Advise(r, fights)
  local C = WA.Combat
  local out = {}
  local function Push(o) out[#out + 1] = C.Finding(o) end
  if r.seconds < 300 then
    Push({ info = true, title = L"Not enough data yet", fact = (L"So far %d fights and %d seconds are recorded. The ratios are reliable after about 10 minutes of combat.")
      :format(r.fights, Round(r.seconds)) })
  end
  local _, share = W.Sources(r.abilities, r.damage)
  -- Life Tap over the maximum: the event itself states the lost part
  local taps = W.Taps(fights)
  if #taps.wasteful > 0 then
    local lines = {}
    for i = 1, math.min(3, #taps.wasteful) do
      local x = taps.wasteful[i]
      lines[i] = (L"%s: gave %d mana, %d of it lost"):format(Clock(x.start, x.t.t), x.t.gain, x.t.over)
    end
    Push({ title = L"Life Tap at full mana", fault = true, rule = "lifeTapCap",
      fact = (L"%d Life Taps put most of their mana over the maximum, and it was lost (combat log: the mana event itself says how much went over the maximum):\n- %s%s\nIn total %d Life Taps, %d mana, %d of it lost.")
        :format(#taps.wasteful, table.concat(lines, "\n- "), #taps.wasteful > 3 and (L"\n- … plus " .. (#taps.wasteful - 3)) or "",
          taps.n, Round(taps.gain), Round(taps.over)),
      advice = L"Use Life Tap when there is room for the mana: you pay the health either way." })
  elseif taps.n > 0 then
    Push({ info = true, title = "Life Tap", fact = (L"%d Life Taps in the fights: %d mana, %d of it went over the maximum."):format(taps.n, Round(taps.gain), Round(taps.over)) })
  end
  local avgFight = r.fights > 0 and r.seconds / r.fights or 0
  local corr = W.DotUptime(r.abilities, "Corruption", r.seconds)
  local agony = W.DotUptime(r.abilities, "Bane of Agony", r.seconds)
  if avgFight >= 15 and r.seconds >= 300 and math.max(corr or 0, agony or 0) < 30 then
    Push({ title = L"Your DoTs rarely tick", fault = true, rule = "dotTicks",
      fact = (L"Corruption ticked about %d%% of combat time, Bane of Agony about %d%% (from the ticks); your average fight is %d s.")
        :format(Round(corr or 0), Round(agony or 0), Round(avgFight)),
      advice = L"In fights longer than 15 s Corruption and Bane of Agony are the cheapest damage per mana.",
      missing = L"your mana, and whether the target lived long enough for the DoT" })
  end
  if r.seconds >= 300 and share.pet < 5 then
    Push({ title = L"Your demon barely does damage", rule = "demonInherit",
      fact = (L"%s%% of your damage is the demon's."):format(F1(share.pet)),
      advice = L"While leveling the Voidwalker tanks and the Imp deals damage: the demon's damage is yours too." })
  end
  if r.seconds >= 120 then
    Push({ info = true, title = L"Measured ratios", fact = (L"Damage: direct spells %d%%, DoTs %d%%, drains and Wrack %d%%, demon %d%%, wand %d%%, other %d%%.")
      :format(Round(share.nuke), Round(share.dot), Round(share.drain), Round(share.pet), Round(share.wand), Round(share.other + share.melee)) })
  end
  return out
end
