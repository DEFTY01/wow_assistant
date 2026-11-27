-- Waystone: the warrior damage model, levels 1-60 (white swings, Heroic Strike on a swing when the
-- rage is there, weapon specials between: Overpower, Mortal Strike, Slam, Whirlwind; Rend,
-- Execute, Bloodthirst and the rest as measured). Pure like Model.lua and Shaman.lua: the same
-- context shape (score, describe, buffGain, weaponWarning, ...) so the plan, the gear report and
-- the pages work for warriors unchanged.
--
-- Forever rules the model follows (Wowhead Forever and WoWSims Forever d5144855, 2026-11-27):
--   * rage from a white hit: 3.46 x weapon speed, a two-hander 4.5 x speed, a crit twice that, an
--     off-hand hit half (sim/core/rage.go BaseRageHitFactor, TwoHandRageHitFactor, CritRageBonus);
--     rage stops at 100 and what goes over is lost (rage.go AddRage: min(current + gain, max))
--   * Heroic Strike adds a flat amount to the next swing, by rank 11 / 21 / 32 / 44 / 58 / 80 /
--     111 / 138 / 157 (Wowhead Forever spell=78 ... 25286); it is a yellow hit (no glancing)
--   * Mortal Strike, Overpower, Slam and Whirlwind are weapon damage plus a flat amount; on
--     Forever Overpower spends combo points and Slam has a 15 s cooldown (spell=7384, 1464)
--   * attack power = 2 x strength (+ level x 3 - 20); agility gives crit (and armor), not attack power
--   * an off-hand weapon hits for half (Dual Wield Specialization adds to it) and misses more
--
-- Extra input besides Model.lua's: str, agi, ap, crit, hit, skills, tab (the talent tab with the most
-- points), talents = Talent.lua's T.Effects (the numbers of the rank's Wowhead Forever text):
-- cruelty (crit, already on the sheet), twoHandSpec (two-hander damage %), impale (abilities' crit
-- bonus %), weaponmaster (extra attack % with a sword), bastion (damage % with a shield), ohHit
-- (off-hand hit %), dualWield (off-hand damage %), flurry (attack speed % for 3 swings after a crit).

local _, WA = ...
WA = WA or {}
local M = WA.Model
local WR = {}
WA.Warrior = WR

local function F1(n) return ("%.1f"):format(n) end
local Round = M.Round

-- { level, flat damage } per Heroic Strike rank (Wowhead Forever)
WR.HS = { { 1, 11 }, { 8, 21 }, { 16, 32 }, { 24, 44 }, { 32, 58 }, { 40, 80 }, { 48, 111 }, { 56, 138 }, { 60, 157 } }
WR.RAGE_HIT, WR.RAGE_HIT_2H, WR.RAGE_MAX = 3.46, 4.5, 100
-- specials that are weapon damage plus a flat amount
WR.WEAPON_SPECIALS = { ["Mortal Strike"] = true, Overpower = true, Slam = true, Whirlwind = true, Cleave = true }
-- rage you press yourself (its loss over the maximum is your choice), and the passive procs
WR.RAGE_PRESSED = { Bloodrage = true, Charge = true, ["Berserker Rage"] = true }

function WR.HsRank(level)
  local best
  for _, r in ipairs(WR.HS) do if r[1] <= (level or 1) then best = r end end
  return best
end

-- melee, hs, special, dot, other
local function Kind(name)
  name = name or ""
  if name == "Melee" then return "melee" end
  if name == "Heroic Strike" then return "hs" end
  if WR.WEAPON_SPECIALS[name] then return "special" end
  if name:sub(-6) == " (dot)" then return "dot" end
  return "other"
end
WR.Kind = Kind

---------------------------------------------------------------------------
-- the model
---------------------------------------------------------------------------
local function Avg(w, ap) return (w.min + w.max) / 2 + (ap / 14) * w.speed end
local function NormAvg(w, ap, norm) return (w.min + w.max) / 2 + (ap / 14) * (norm or w.speed) end

-- Talents (Wowhead Forever): Flurry speeds the three swings after a crit; Weaponmaster gives a
-- sword's landed attacks an extra attack; Impale raises the abilities' crit bonus (100%).
function WR.Haste(crit, p) return 1 + (p.flurry or 0) / 100 * (1 - (1 - math.max(0, math.min(crit, 100)) / 100) ^ 3) end
local SWORD = { [7] = true, [8] = true }
local function Extra(w, p) return (w and SWORD[w.sub] and (p.weaponmaster or 0) / 100) or 0 end
WR.Extra = Extra

function WR.Dps(sh, p)
  local modeled = 0
  local mcrit = math.max(0, math.min(sh.crit, 100)) / 100
  local miss = math.max(0, 5 - sh.hit) / 100
  local dodge = p.dodge / 100
  local landed = math.max(0, 1 - miss - dodge)
  local yellowF = landed * (1 + mcrit * (1 + (p.impale or 0) / 100))
  local haste = WR.Haste(sh.crit, p)
  if sh.mh then
    local whiteF = math.max(0, 1 - miss - dodge - mcrit) + mcrit * 2
    local swings = p.meleeUptime / sh.mh.speed * haste
    local avg = Avg(sh.mh, sh.ap)
    local mult = sh.mh.twoHand and 1 + (p.twoHandSpec or 0) / 100 or 1
    -- a Heroic Strike swing is a yellow hit with the rank's flat damage on top of the white one
    local hs = math.min(p.hsPerSec, swings)
    modeled = modeled + ((swings - hs) * avg * whiteF + hs * (avg + p.hsBonus) * yellowF) * mult
    modeled = modeled + p.specialPerSec * (NormAvg(sh.mh, sh.ap, sh.mh.norm) + p.specialBonus) * yellowF * mult
    local extra = Extra(sh.mh, p)
    if extra > 0 then modeled = modeled + (swings + p.specialPerSec) * landed * extra * avg * whiteF * mult end
  end
  if sh.oh then
    -- the off hand: half damage (Dual Wield Specialization adds to it), dual wield misses more
    -- (+19%, less with Furious Precision)
    local ohMiss = math.max(0, math.min(1, miss + 0.19 - (p.ohHit or 0) / 100))
    local whiteF = math.max(0, 1 - ohMiss - dodge - mcrit) + mcrit * 2
    local swings = p.meleeUptime / sh.oh.speed * haste
    local avg = Avg(sh.oh, sh.ap) * p.ohMult
    modeled = modeled + swings * avg * whiteF
    local extra = Extra(sh.oh, p)
    if extra > 0 then modeled = modeled + swings * math.max(0, 1 - ohMiss - dodge) * extra * avg * whiteF end
  end
  -- Bastion: all damage with a shield (the measured rest has it already)
  if sh.shield then modeled = modeled * (1 + (p.bastion or 0) / 100) end
  return p.otherDps + modeled
end

local function Apply(sh, remove, add, p)
  local dAgi = ((add.agi or 0) - (remove.agi or 0)) * p.statMult
  local dStr = ((add.str or 0) - (remove.str or 0)) * p.statMult
  return {
    ap = sh.ap + (add.ap or 0) - (remove.ap or 0) + 2 * dStr,
    crit = sh.crit + (add.crit or 0) - (remove.crit or 0) + dAgi / p.agiPerCrit,
    hit = sh.hit + (add.hit or 0) - (remove.hit or 0),
    mh = sh.mh, oh = sh.oh, shield = sh.shield,
  }
end

-- rage a second from white hits (the model's own check: is there rage for its Heroic Strikes?)
function WR.WhiteRage(sh, p)
  if not sh.mh then return 0 end
  local mcrit = math.max(0, math.min(sh.crit, 100)) / 100
  local land = math.max(0, 1 - math.max(0, 5 - sh.hit) / 100 - p.dodge / 100)
  local factor = sh.mh.twoHand and WR.RAGE_HIT_2H or WR.RAGE_HIT
  local r = p.meleeUptime / sh.mh.speed * land * factor * sh.mh.speed * (1 + mcrit)
  if sh.oh then r = r + p.meleeUptime / sh.oh.speed * land * WR.RAGE_HIT / 2 * sh.oh.speed * (1 + mcrit) end
  return r
end

---------------------------------------------------------------------------
-- context
---------------------------------------------------------------------------
function WR.Context(input)
  local level = input.level or 1
  local equipped = input.equipped or {}
  local notes = {}
  local function eq(slot) return equipped[slot] and equipped[slot].stats or M.ZERO end
  local tal = input.talents or {}
  local agi = input.agi or 0
  local crit = input.crit or 0
  local agiPerCrit = agi / math.max(0.1, crit - (tal.cruelty or 0))
  if not (agiPerCrit > 2 and agiPerCrit < 40) then agiPerCrit = 4 + (16 * (level - 1)) / 59 end
  local combat = input.combat

  local mh = eq("MAIN_HAND").weapon
  local oh = eq("OFF_HAND").weapon
  local mhItem = equipped.MAIN_HAND
  local twoHand = mhItem and mhItem.sub and (mhItem.sub == 1 or mhItem.sub == 5 or mhItem.sub == 6 or mhItem.sub == 8 or mhItem.sub == 10) or false
  if mh then mh = { min = mh.min, max = mh.max, speed = mh.speed, twoHand = twoHand, norm = M.NormalizedSpeed(mhItem and mhItem.sub, twoHand),
    sub = mhItem and tonumber(mhItem.sub) } end
  local ohItem = equipped.OFF_HAND
  if oh then oh = { min = oh.min, max = oh.max, speed = oh.speed, sub = ohItem and tonumber(ohItem.sub) } end
  -- a shield in the off hand (Bastion): armor class 4, subclass 6
  local shield = ohItem and not oh and ohItem.item and ((ohItem.item.classID == 4 and ohItem.item.sub == 6) or ohItem.item.equipLoc == "INVTYPE_SHIELD") or false
  local sheet = { ap = input.ap or 0, crit = crit, hit = input.hit or 0, mh = mh, oh = oh, shield = shield }
  local hsRank = WR.HsRank(level)

  local params = {
    level = level, agiPerCrit = agiPerCrit, statMult = 1, dodge = 5, ohMult = 0.5 * (1 + (tal.dualWield or 0) / 100),
    twoHandSpec = tal.twoHandSpec or 0, impale = tal.impale or 0, weaponmaster = tal.weaponmaster or 0,
    bastion = tal.bastion or 0, ohHit = tal.ohHit or 0, flurry = tal.flurry or 0,
    meleeUptime = mh and (level < 10 and 0.65 or 0.85) or 0,
    -- priors: a Heroic Strike every fourth swing, a weapon special every 10 s from level 12
    hsPerSec = mh and 0.25 / mh.speed or 0, hsBonus = hsRank and hsRank[2] or 0,
    specialPerSec = level >= 12 and 0.1 or 0, specialBonus = 5 + 1.5 * level,
    otherDps = 0, notes = notes,
  }
  notes[#notes + 1] = ("1%% crit ≈ %s agility (from your own stats); 1 strength = 2 AP. Heroic Strike: +%d damage on the next swing (level %d rank, Wowhead Forever).")
    :format(F1(agiPerCrit), params.hsBonus, hsRank and hsRank[1] or 1)

  local function mix(prior, measured, n, half)
    local w = n / (n + half)
    return prior * (1 - w) + measured * w
  end
  local function landed(a) return (a.hit or 0) + (a.crit or 0) + (a.glance or 0) end
  if combat and combat.seconds > 0 then
    local secs = combat.seconds
    local melee, hs, specials, specialDmg, specialLanded, specialCrit, other = nil, nil, 0, 0, 0, 0, 0
    for _, a in ipairs(combat.abilities) do
      local k = Kind(a.name)
      if k == "melee" then melee = a
      elseif k == "hs" then hs = a
      elseif k == "special" then
        specials, specialDmg, specialLanded, specialCrit = specials + a.n, specialDmg + a.dmg, specialLanded + landed(a), specialCrit + (a.crit or 0)
      else other = other + a.dmg end
    end
    if mh then
      -- the logged swings are faster with Flurry and include Weaponmaster's extra attacks; the
      -- logged damage has Two-Handed Weapon Specialization, Impale and Bastion in it
      local swings = (melee and melee.n or 0) + (hs and hs.n or 0)
      local land = math.max(0, 1 - math.max(0, 5 - sheet.hit) / 100 - params.dodge / 100)
      local per1 = WR.Haste(sheet.crit, params) * (1 + Extra(mh, params) * land)
      params.meleeUptime = mix(params.meleeUptime, math.min(1, swings / secs * mh.speed / per1), secs, 120)
      params.hsPerSec = mix(params.hsPerSec, (hs and hs.n or 0) / secs, secs, 120)
      local mult = (mh.twoHand and 1 + params.twoHandSpec / 100 or 1) * (shield and 1 + params.bastion / 100 or 1)
      local critBonus = 1 + params.impale / 100
      if hs and landed(hs) > 0 then
        local per = hs.dmg / (landed(hs) + (hs.crit or 0) * critBonus) / mult
        params.hsBonus = mix(params.hsBonus, math.max(0, per - Avg(mh, sheet.ap)), landed(hs), 10)
      end
      if specialLanded > 0 then
        local per = specialDmg / (specialLanded + specialCrit * critBonus) / mult
        params.specialBonus = mix(params.specialBonus, math.max(0, per - NormAvg(mh, sheet.ap, mh.norm)), specialLanded, 10)
      end
    end
    params.specialPerSec = mix(params.specialPerSec, specials / secs, secs, 120)
    params.otherDps = mix(0, other / secs, secs, 120)
    notes[#notes + 1] = ("Calibrated from %d recorded fights (%d s): swinging %d%% of the time, Heroic Strike %s per minute (+%d), weapon special %s per minute (+%d), everything else (Rend, Execute, Bloodthirst...) %s DPS.")
      :format(combat.fights, Round(secs), Round(params.meleeUptime * 100), F1(params.hsPerSec * 60), Round(params.hsBonus),
        F1(params.specialPerSec * 60), Round(params.specialBonus), F1(params.otherDps))
  else
    notes[#notes + 1] = "No recorded fights, so it uses textbook values. Turn on the combat log (/wa log) to calibrate."
  end
  notes[#notes + 1] = ("The model does not simulate rage: your white hits give about %s rage a second (3.46 × weapon speed per hit, 4.5 × with a two-hander; WoWSims Forever sim/core/rage.go).")
    :format(F1(WR.WhiteRage(sheet, params)))

  local unbuffed = WR.Dps(sheet, params)
  local buffs = M.ResolveBuffs(level, input.buffs, input.data)
  local bAgi, bStr, bAp, bCrit, pct = 0, 0, 0, 0, 0
  for _, b in ipairs(buffs) do
    if b.selected and b.effect then
      bAgi, bStr, bAp, bCrit = bAgi + (b.effect.agi or 0), bStr + (b.effect.str or 0), bAp + (b.effect.ap or 0), bCrit + (b.effect.crit or 0)
      pct = pct + (b.effect.statPct or 0)
    end
  end
  if pct > 0 then
    bAgi = bAgi + pct * (agi + bAgi)
    bStr = bStr + pct * ((input.str or 0) + bStr)
    params.statMult = 1 + pct
  end
  sheet.ap = sheet.ap + 2 * bStr + bAp
  sheet.crit = sheet.crit + bCrit + bAgi / agiPerCrit
  local baseline = WR.Dps(sheet, params)
  local equippedIds = {}
  for _, it in pairs(equipped) do if it.id then equippedIds[it.id] = true end end
  local skills = input.skills

  local ctx = M.Common({
    level = level, baseline = baseline, unbuffed = unbuffed, buffs = buffs, params = params, sheet = sheet,
    equipped = equipped, equippedIds = equippedIds, combat = combat, slotOrder = input.slotOrder,
  }, "WARRIOR")

  -- dual wield from level 20 (the Dual Wield skill); a shield any time
  local usableAt = ctx.usableAt
  function ctx.usableAt(itemClass, sub, level2) return usableAt(itemClass, sub, level2) end

  function ctx.score(add, slots, twoHand2, sub)
    local best
    if add.weapon then
      add.weapon = { min = add.weapon.min, max = add.weapon.max, speed = add.weapon.speed, twoHand = twoHand2 == true,
        norm = M.NormalizedSpeed(sub, twoHand2), sub = tonumber(sub) }
    end
    for _, slot in ipairs(slots) do
      local remove = eq(slot)
      if twoHand2 then
        local o = eq("OFF_HAND")
        remove = {}
        for k in pairs(M.ZERO) do remove[k] = (eq(slot)[k] or 0) + (o[k] or 0) end
      end
      local sh = Apply(sheet, remove, add, params)
      local ok = true
      if slot == "MAIN_HAND" then
        sh.mh = add.weapon or sh.mh
        if twoHand2 then sh.oh, sh.shield = nil, false end
      elseif slot == "OFF_HAND" then
        if add.weapon and (level < 20 or (sheet.mh and sheet.mh.twoHand)) then ok = false end
        -- an off-hand item without weapon numbers and subclass 6 is a shield
        sh.oh, sh.shield = add.weapon, (not add.weapon and tonumber(sub) == 6) or false
      end
      if ok then
        local gain = WR.Dps(sh, params) - baseline
        if not best or gain > best.gain then best = { slot = slot, gain = gain } end
      end
    end
    if best and best.gain > 0.05 then return best end
    return nil
  end

  function ctx.describe(add, weaponSub)
    local bits = {}
    if add.weapon then
      local w = add.weapon
      bits[#bits + 1] = ("%s %s–%s / %s"):format(M.WEAPON_NAMES[weaponSub or -1] or "Weapon", w.min, w.max, F1(w.speed))
    end
    if (add.str or 0) ~= 0 then bits[#bits + 1] = ("+%s str"):format(add.str) end
    if (add.agi or 0) ~= 0 then bits[#bits + 1] = ("+%s agi"):format(add.agi) end
    if (add.ap or 0) ~= 0 then bits[#bits + 1] = ("+%s AP"):format(add.ap) end
    if (add.crit or 0) ~= 0 then bits[#bits + 1] = ("+%s%% crit"):format(add.crit) end
    if (add.hit or 0) ~= 0 then bits[#bits + 1] = ("+%s%% hit"):format(add.hit) end
    return table.concat(bits, ", ")
  end

  function ctx.buffGain(e)
    local add = { agi = e.agi or 0, str = e.str or 0, ap = e.ap or 0, crit = e.crit or 0 }
    local sh = Apply(sheet, M.ZERO, add, params)
    return WR.Dps(sh, params) - baseline
  end

  function ctx.weaponWarning(itemClass, sub)
    if itemClass ~= 2 or not skills or not next(skills) then return nil end
    local line = M.WEAPON_SKILLS[sub]
    local s = line and skills[line]
    if not line then return nil end
    if not s then return ("%s is not trained"):format(line) end
    if s.rank < s.max - 15 then return ("%s skill %d/%d"):format(line, s.rank, s.max) end
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

function WR.Sources(abilities, total)
  local out = { melee = 0, hs = 0, special = 0, dot = 0, other = 0 }
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

-- rage of fights from the log: per spell { n, gain, over }; the pressed ones (Bloodrage's instant
-- rage, Charge) that lost at least half over the maximum; the passive procs' loss
function WR.Rage(fights)
  local out = { seen = 0, bySpell = {}, wasteful = {}, passiveOver = 0, passiveN = 0, gain = 0, over = 0 }
  for _, f in ipairs(fights or {}) do
    if type(f.rage) == "table" then
      out.seen = out.seen + 1
      for _, r in ipairs(f.rage) do
        local s = out.bySpell[r.spell] or { n = 0, gain = 0, over = 0 }
        out.bySpell[r.spell] = s
        s.n, s.gain, s.over = s.n + 1, s.gain + (r.gain or 0), s.over + (r.over or 0)
        out.gain, out.over = out.gain + (r.gain or 0), out.over + (r.over or 0)
        if WR.RAGE_PRESSED[r.spell] and not r.tick then
          if (r.gain or 0) + (r.over or 0) > 0 and (r.over or 0) * 2 >= (r.gain or 0) + (r.over or 0) then
            out.wasteful[#out.wasteful + 1] = { start = f.start, r = r }
          end
        elseif (r.over or 0) > 0 then
          out.passiveOver, out.passiveN = out.passiveOver + r.over, out.passiveN + 1
        end
      end
    end
  end
  return out
end

local GRADES = { { 90, "S" }, { 80, "A" }, { 65, "B" }, { 50, "C" }, { 0, "D" } }
function WR.Score(f, ctx)
  local parts = {}
  local function Part(key, label, got, max, text) parts[#parts + 1] = { key = key, label = label, points = got, max = max, text = text } end
  local dur = f.dur or 0
  local dps = dur > 0 and (f.dmg or 0) / dur or 0
  local baseline = ctx and WA.Combat.Comparable(f, ctx) and ctx.baseline or nil
  if baseline and baseline > 0 then
    local ratio = dps / baseline
    Part("dps", "DPS against the expected", math.min(ratio / 1.1, 1) * 40, 40, ("%d DPS against the %d your gear should give: %d%%"):format(
      Round(dps), Round(baseline), Round(ratio * 100)))
  end
  local ab = f.ab or {}
  local mh = ctx and ctx.sheet and ctx.sheet.mh
  if dur >= 6 and mh then
    local melee, hs = Find(ab, "Melee"), Find(ab, "Heroic Strike")
    local swings = (melee and melee.n or 0) + (hs and hs.n or 0)
    local up = math.min(1, swings * mh.speed / dur)
    Part("melee", "You swing continuously", math.min(up / 0.9, 1) * 20, 20, ("you were swinging about %d%% of the fight (%d swings, %s s weapon)"):format(
      Round(up * 100), swings, F1(mh.speed)))
  end
  if type(f.rage) == "table" and #f.rage > 0 then
    local gain, over = 0, 0
    for _, r in ipairs(f.rage) do gain, over = gain + (r.gain or 0), over + (r.over or 0) end
    local total = gain + over
    local kept = total > 0 and gain / total or 1
    Part("rage", "No rage wasted", kept * 15, 15, ("%d rage from the logged rage sources, of which %d was lost over 100"):format(Round(total), Round(over)))
  end
  local got, max = 0, 0
  for _, x in ipairs(parts) do got, max = got + x.points, max + x.max end
  if max == 0 then return nil end
  local total = math.floor(got / max * 100 + 0.5)
  local grade = "D"
  for _, g in ipairs(GRADES) do if total >= g[1] then grade = g[2] break end end
  return { total = total, grade = grade, parts = parts, dps = dps }
end

function WR.Summary(r, ctx, fights)
  if not r then return nil end
  local src, share = WR.Sources(r.abilities, r.damage)
  local secs = r.seconds
  local s = { sources = src, shares = share, seconds = secs, dps = r.dps, rows = {}, rage = WR.Rage(fights) }
  local melee = Find(r.abilities, "Melee")
  if melee then
    local n = melee.n
    s.melee = { n = n, miss = n > 0 and (melee.miss or 0) / n * 100 or 0, dodge = n > 0 and ((melee.dodge or 0) + (melee.parry or 0)) / n * 100 or 0,
      crit = n > 0 and (melee.crit or 0) / n * 100 or 0, glance = n > 0 and (melee.glance or 0) / n * 100 or 0 }
  end
  local hs = Find(r.abilities, "Heroic Strike")
  s.hsShare = melee and hs and hs.n / (hs.n + melee.n) * 100 or 0
  for _, a in ipairs(r.abilities) do
    local landed = (a.hit or 0) + (a.crit or 0) + (a.glance or 0)
    s.rows[#s.rows + 1] = { name = a.name, dmg = a.dmg, share = a.share, n = a.n, cpm = a.n / secs * 60,
      perCast = a.n > 0 and a.dmg / a.n or 0, avg = landed > 0 and a.dmg / landed or 0, kind = Kind(a.name) }
  end
  return s
end

local function Clock(start, tenths)
  local s = (start or 0) + (tonumber(tenths) or 0) / 10
  return date and date("%m/%d %H:%M:%S", math.floor(s)) or tostring(math.floor(s))
end

function WR.Advise(r, fights)
  local C = WA.Combat
  local out = {}
  local function Push(o) out[#out + 1] = C.Finding(o) end
  if r.seconds < 300 then
    Push({ info = true, title = "Not enough data yet", fact = ("So far %d fights and %d seconds are recorded. The ratios are reliable after about 10 minutes of combat.")
      :format(r.fights, Round(r.seconds)) })
  end
  local _, share = WR.Sources(r.abilities, r.damage)
  local rage = WR.Rage(fights)
  if #rage.wasteful > 0 then
    local lines = {}
    for i = 1, math.min(3, #rage.wasteful) do
      local x = rage.wasteful[i]
      lines[i] = ("%s: %s, %d rage, %d of it lost"):format(Clock(x.start, x.r.t), x.r.spell, (x.r.gain or 0) + (x.r.over or 0), x.r.over or 0)
    end
    Push({ title = "Bloodrage or Charge at full rage", fault = true, rule = "rageCap",
      fact = ("%d times most of the rage gained went over 100 and was lost (combat log: the rage event itself says how much went over the maximum):\n- %s%s")
        :format(#rage.wasteful, table.concat(lines, "\n- "), #rage.wasteful > 3 and ("\n- … plus " .. (#rage.wasteful - 3)) or ""),
      advice = "Press Bloodrage when there is room for the rage: spend first (Heroic Strike, special)." })
  end
  if rage.passiveOver > 0 then
    Push({ info = true, title = "Rage over the maximum",
      fact = ("Passive rage sources (e.g. Shield Specialization, Unbridled Wrath) gave rage over 100 %d times, %d rage lost in total: your rage was full then.")
        :format(rage.passiveN, Round(rage.passiveOver)) })
  end
  local avgFight = r.fights > 0 and r.seconds / r.fights or 0
  local hs = Find(r.abilities, "Heroic Strike")
  if r.seconds >= 300 and avgFight >= 10 and not hs and rage.passiveOver > 0 then
    Push({ title = "No Heroic Strike although rage was full", rule = "hsDump",
      fact = ("There is not a single Heroic Strike in your fights, while %d rage was lost over 100."):format(Round(rage.passiveOver)),
      advice = "Heroic Strike puts spare rage into the next swing: at full rage that is free damage." })
  end
  if r.seconds >= 120 then
    Push({ info = true, title = "Measured ratios", fact = ("Damage: white hits %d%%, Heroic Strike %d%%, weapon specials %d%%, DoT (Rend) %d%%, other %d%%.")
      :format(Round(share.melee), Round(share.hs), Round(share.special), Round(share.dot), Round(share.other)) })
  end
  return out
end
