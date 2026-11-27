-- Waystone: the priest damage model, levels 1-60 (Smite or Mind Flay as the filler, Mind Blast on
-- its cooldown, Shadow Word: Pain kept up, Holy Fire, a wand when the mana runs out). Pure like
-- Model.lua and Mage.lua: the same context shape (score, describe, buffGain, weaponWarning, ...)
-- so the plan, the gear report and the pages work for priests unchanged. A healing priest's
-- healing is not modelled: the enchant section uses the healer weights for Discipline and Holy.
--
-- Forever rules the model follows (Wowhead Forever, 2026-11-27):
--   * every rank's level, cast time and damage from its Wowhead Forever tooltip: Smite (spell=585
--     ... 10934), Mind Blast (8092 ... 10947, 1.5 s, 8 s cooldown), Shadow Word: Pain (589 ...
--     10894, 18 s, a tick every 3 s), Mind Flay (15407 ... 18807, 3 s channel, a tick every
--     second), Holy Fire (14914 ... 15261, 3.5 s, and a DoT for 10 s, a tick every 2 s)
--   * spell power coefficients from the Spell Details table (SP mod): Smite 0.429 at 1.5 s and
--     0.714 at 2.5 s, that is cast time / 3.5; Mind Blast 0.429; Shadow Word: Pain 0.2 a tick;
--     Mind Flay 0.167 a tick; Holy Fire 0.75 and 0.05 a DoT tick. The model uses the top rank's
--     for every rank (the lower ranks' pages were not all read) and says so.
--   * a direct hit and a periodic tick both crit for 150%: the combat log shows Shadow Word: Pain
--     and Holy Fire ticks critting on Forever (a real log, 2026-11-22: 5 crits in 90 ticks)
--   * a mana potion or a mana gem: mana over the maximum is lost (the same rule as the mage's)
--   * a wand's damage does not grow with spell power
--
-- Talents (WA-032h, the numbers of the rank's Wowhead Forever text), on the parts they touch:
-- Searing Light (holy), Darkness and Shadowform (shadow; Shadowform also doubles the shadow crit
-- bonus), Twin Disciplines (Shadow Word: Pain), Improved Mind Flay (each tick more than the one
-- before), Holy Precision / Shadow Focus (hit by school), Holy Specialization (holy crit, when the
-- sheet does not have it), Divine Fury and Improved Mind Blast (the prior's cast time and
-- cooldown), Mind Flay (the filler), Mental Strength (intellect), Wand Specialization.
--
-- Extra input besides Model.lua's: int, spHoly, spShadow (spell power by school), spellCrit,
-- spellCritHoly, spellCritShadow (crit by school), spellHit, tab (the talent tab with the most
-- points), talents = Talent.lua's T.Effects.

local _, WA = ...
WA = WA or {}
local M = WA.Model
local PR = {}
WA.Priest = PR

local function F1(n) return ("%.1f"):format(n) end
local Round = M.Round

-- direct spells: { level, min, max, cast seconds } per rank
PR.SMITE = { { 1, 14, 18, 1.5 }, { 6, 26, 31, 2 }, { 14, 44, 51, 2.5 }, { 22, 59, 68, 2.5 }, { 30, 81, 91, 2.5 }, { 38, 94, 105, 2.5 },
  { 46, 124, 139, 2.5 }, { 54, 167, 186, 2.5 } }
PR.MIND_BLAST = { { 10, 40, 44, 1.5 }, { 16, 70, 75, 1.5 }, { 22, 103, 110, 1.5 }, { 28, 154, 162, 1.5 }, { 34, 198, 210, 1.5 },
  { 40, 259, 276, 1.5 }, { 46, 325, 344, 1.5 }, { 52, 406, 428, 1.5 }, { 58, 485, 511, 1.5 } }
-- Holy Fire: { level, min, max, cast, DoT total }
PR.HOLY_FIRE = { { 20, 53, 65, 3.5, 20 }, { 24, 64, 78, 3.5, 25 }, { 30, 80, 98, 3.5, 30 }, { 36, 90, 112, 3.5, 35 }, { 42, 103, 127, 3.5, 45 },
  { 48, 133, 166, 3.5, 50 }, { 54, 164, 205, 3.5, 65 }, { 60, 196, 244, 3.5, 75 } }
-- periodic spells: { level, total damage }
PR.SWP = { { 4, 30 }, { 10, 60 }, { 18, 108 }, { 26, 180 }, { 34, 288 }, { 42, 426 }, { 50, 582 }, { 58, 762 } }
PR.FLAY = { { 20, 63 }, { 28, 102 }, { 36, 153 }, { 44, 225 }, { 52, 294 }, { 60, 390 } }

PR.MB_CD = 8
PR.SHADOW = { ["Mind Blast"] = true, ["Shadow Word: Pain"] = true, ["Mind Flay"] = true, ["Devouring Plague"] = true, ["Shadow Word: Death"] = true }
PR.NUKES = { Smite = true, ["Mind Blast"] = true, ["Holy Fire"] = true, ["Shadow Word: Death"] = true, ["Mind Flay"] = true, Penance = true }
PR.DOTS = { ["Shadow Word: Pain"] = true, ["Devouring Plague"] = true, ["Holy Fire"] = true, ["Mind Flay"] = true, ["Vampiric Embrace"] = true,
  Starshards = true }
PR.AOE = { ["Holy Nova"] = true, ["Mind Sear"] = true }
-- cast seconds of the casts that are not a 1.5 s global cooldown (Smite uses its rank's)
PR.CAST = { ["Holy Fire"] = 3.5, ["Mind Flay"] = 3, ["Mind Control"] = 3, Heal = 3, ["Greater Heal"] = 3, ["Lesser Heal"] = 2.5,
  ["Prayer of Healing"] = 3, Resurrection = 10 }
PR.MANA_ITEMS = { ["Restore Mana"] = true, ["Replenish Mana"] = true }

local function Base(name) return ((name or ""):gsub(" %(dot%)$", "")) end
local function IsDot(name) return (name or ""):sub(-6) == " (dot)" end

-- wand, dot, nuke, flay, aoe, melee, other (Mind Flay's ticks are its own: the filler)
local function Kind(name)
  name = name or ""
  local base = Base(name)
  if name == "Shoot" then return "wand" end
  if base == "Mind Flay" then return "flay" end
  if IsDot(name) and PR.DOTS[base] then return "dot" end
  if PR.NUKES[base] then return "nuke" end
  if PR.AOE[base] then return "aoe" end
  if name == "Melee" then return "melee" end
  return "other"
end
PR.Kind = Kind

local function WandDps(w) return w and w.speed and w.speed > 0 and (w.min + w.max) / 2 / w.speed or 0 end
PR.WandDps = WandDps

local function Rank(list, level)
  local best
  for _, r in ipairs(list) do if r[1] <= (level or 1) then best = r end end
  return best
end
PR.Rank = Rank

-- The parts the model counts, by the name a fight's ability list uses: per hit (or tick) base
-- damage, spell power coefficient, school, whether it crits, the prior rate a second.
function PR.Parts(level, tab, tal)
  tal = tal or {}
  local parts = {}
  local smite = Rank(PR.SMITE, level)
  local mb = Rank(PR.MIND_BLAST, level)
  local swp = Rank(PR.SWP, level)
  local flay = Rank(PR.FLAY, level)
  local hf = Rank(PR.HOLY_FIRE, level)
  -- time budget of a typical fight: the filler gets what Mind Blast leaves of 55%
  local filler = 0.55
  if mb then
    -- Improved Mind Blast: a shorter cooldown (the prior; the fights' rate replaces it)
    local cd = PR.MB_CD - (tal.impMindBlast or 0)
    parts["Mind Blast"] = { base = (mb[2] + mb[3]) / 2, coef = 0.429, school = "shadow", crits = true, rate = 0.6 / cd, rank = mb, cast = 1.5 }
    filler = filler - 0.6 / cd * 1.5
  end
  if swp then
    parts["Shadow Word: Pain (dot)"] = { base = swp[2] / 6, coef = 0.2, school = "shadow", crits = true, rate = 0.6 / 3, rank = swp, tick = true }
  end
  -- Mind Flay is a talent on Forever: the filler when the talent scan has it, else (no scan) by
  -- the Shadow tab
  local useFlay
  if tal.read then useFlay = flay and (tal.mindFlay or 0) > 0 else useFlay = flay and tab == 3 end
  -- Divine Fury: shorter Smite and Holy Fire casts (not below the 1.5 s global cooldown); the
  -- spell power share stays the base cast time's
  local fury = tal.divineFury or 0
  if smite then
    local cast = math.max(1.5, smite[4] - fury)
    parts.Smite = { base = (smite[2] + smite[3]) / 2, coef = smite[4] / 3.5, school = "holy", crits = true, rate = useFlay and 0 or filler / cast,
      rank = smite, cast = cast }
  end
  if flay then
    parts["Mind Flay (dot)"] = { base = flay[2] / 3, coef = 0.167, school = "shadow", crits = true, rate = useFlay and filler or 0, rank = flay, tick = true }
  end
  if hf then
    parts["Holy Fire"] = { base = (hf[2] + hf[3]) / 2, coef = 0.75, school = "holy", crits = true, rate = 0, rank = hf, cast = math.max(1.5, 3.5 - fury) }
    parts["Holy Fire (dot)"] = { base = hf[5] / 5, coef = 0.05, school = "holy", crits = true, rate = 0, rank = hf, tick = true }
  end
  -- the talents' multipliers on each part
  local holyMult = 1 + (tal.searing or 0) / 100
  local shadowMult = (1 + (tal.darkness or 0) / 100) * (1 + (tal.shadowformDmg or 0) / 100)
  local shadowCrit = 1.5 + 0.5 * (tal.shadowformCrit or 0) / 100
  -- Improved Mind Flay: the ticks of a full channel are 1, 1 + r, (1 + r)^2 times the first
  local r = (tal.impMindFlay or 0) / 100
  local flayMult = (1 + (1 + r) + (1 + r) ^ 2) / 3
  for name, x in pairs(parts) do
    if x.school == "shadow" then x.mult, x.critMult = shadowMult, shadowCrit else x.mult, x.critMult = holyMult, 1.5 end
    if name == "Shadow Word: Pain (dot)" then x.mult = x.mult * (1 + (tal.twin or 0) / 100) end
    if name == "Mind Flay (dot)" then x.mult = x.mult * flayMult end
  end
  return parts
end

---------------------------------------------------------------------------
-- the model
---------------------------------------------------------------------------
function PR.Dps(sh, p)
  local miss = math.max(1, p.spellMiss - (sh.spellHit or 0)) / 100
  local total = p.otherDps
  for _, x in pairs(p.parts) do
    if x.rate > 0 then
      local shadow = x.school == "shadow"
      local sp = shadow and sh.spShadow or sh.spHoly
      -- crit and hit by school (Holy Specialization, Holy Precision, Shadow Focus)
      local crit = shadow and (sh.critShadow or sh.spellCrit) or (sh.critHoly or sh.spellCrit)
      local scrit = math.max(0, math.min(crit, 100)) / 100
      local xmiss = math.max(1, p.spellMiss - (sh.spellHit or 0) - (shadow and p.shadowHit or p.holyHit)) / 100
      local f = (1 - xmiss) * (x.crits and (1 + scrit * ((x.critMult or 1.5) - 1)) or 1)
      total = total + x.rate * (x.base + x.coef * sp) * f * (x.mult or 1)
    end
  end
  total = total + p.wandUptime * WandDps(sh.wand) * (1 - miss) * p.wandMult
  return total
end

local function Apply(sh, remove, add, p)
  local dInt = ((add.int or 0) - (remove.int or 0)) * p.statMult * p.intMult
  local dSp = (add.sp or 0) - (remove.sp or 0)
  return {
    spHoly = sh.spHoly + dSp, spShadow = sh.spShadow + dSp, sp = sh.sp + dSp,
    spellCrit = sh.spellCrit + dInt / p.intPerCrit,
    critHoly = sh.critHoly + dInt / p.intPerCrit, critShadow = sh.critShadow + dInt / p.intPerCrit,
    spellHit = sh.spellHit, wand = sh.wand, ap = sh.ap, crit = sh.crit, hit = sh.hit, mh = sh.mh,
  }
end

---------------------------------------------------------------------------
-- context
---------------------------------------------------------------------------
function PR.Context(input)
  local level = input.level or 1
  local equipped = input.equipped or {}
  local notes = {}
  local function eq(slot) return equipped[slot] and equipped[slot].stats or M.ZERO end
  local intPerCrit = 6 + (54 * (level - 1)) / 59
  local combat = input.combat
  local tal = input.talents or {}
  local parts = PR.Parts(level, input.tab, tal)

  local wand = eq("RANGED").weapon
  local spHoly, spShadow = input.spHoly or input.sp or 0, input.spShadow or input.sp or 0
  local sheet = { spHoly = spHoly, spShadow = spShadow, sp = math.max(spHoly, spShadow), spellCrit = input.spellCrit or 0, spellHit = input.spellHit or 0,
    wand = wand, ap = input.ap or 0, crit = input.crit or 0, hit = input.hit or 0, mh = eq("MAIN_HAND").weapon }
  -- crit by school; Holy Specialization is added when the holy crit is not that much above the
  -- shadow crit (the sheet does not have it), the way the mage's Critical Mass is
  sheet.critHoly = input.spellCritHoly or sheet.spellCrit
  sheet.critShadow = input.spellCritShadow or sheet.spellCrit
  local holySpec = tal.holySpec or 0
  local holySpecAdded = holySpec > 0 and (sheet.critHoly - sheet.critShadow) < holySpec - 0.05
  if holySpecAdded then sheet.critHoly = sheet.critHoly + holySpec end

  local params = { level = level, intPerCrit = intPerCrit, statMult = 1, spellMiss = 4, parts = parts, tab = input.tab,
    wandUptime = wand and 0.15 or 0, otherDps = 0, notes = notes,
    holyHit = tal.holyHit or 0, shadowHit = tal.shadowHit or 0, holySpecAdded = holySpecAdded,
    wandMult = 1 + (tal.wandSpec or 0) / 100, intMult = 1 + (tal.mentalStrength or 0) / 100 }

  local function PartsNote()
    local bits = {}
    for _, k in ipairs({ "Smite", "Mind Blast", "Shadow Word: Pain (dot)", "Mind Flay (dot)", "Holy Fire" }) do
      local x = parts[k]
      if x and x.rate > 0.002 then
        bits[#bits + 1] = ("%s (%d. szintű rang, %s %d%%-a)"):format(Base(k) .. (x.tick and " tick" or ""), x.rank[1], x.tick and "tickenként a spell power" or "a spell power",
          Round(x.coef * 100))
      end
    end
    return ("A modell részei: %s (Wowhead Forever; a tickek is critelnek, a harcnapló szerint). Az együttható a legmagasabb rang oldaláról, minden rangra. 1%% spell crit ≈ %s intellect. A pálca %s DPS, ez nem nő a spell powerrel.")
      :format(#bits > 0 and table.concat(bits, ", ") or "csak a pálca", F1(intPerCrit), F1(WandDps(wand)))
  end

  local function mix(prior, measured, n, half)
    local w = n / (n + half)
    return prior * (1 - w) + measured * w
  end
  local function landed(a) return (a.hit or 0) + (a.crit or 0) + (a.glance or 0) end
  if combat and combat.seconds > 0 then
    local secs = combat.seconds
    local seen, wandN, other = {}, 0, 0
    local missN, castN, hitBack = 0, 0, 0
    for _, a in ipairs(combat.abilities) do
      local x = parts[a.name]
      if x then
        seen[a.name] = true
        x.rate = mix(x.rate, a.n / secs, secs, 120)
        local l = landed(a)
        if l > 0 then
          -- one hit without the talents (the crit bonus and the multiplier of its part)
          local per = a.dmg / (l + (x.crits and ((x.critMult or 1.5) - 1) * (a.crit or 0) or 0)) / (x.mult or 1)
          local sp = x.school == "shadow" and sheet.spShadow or sheet.spHoly
          x.base = mix(x.base, math.max(0, per - x.coef * sp), l, 10)
        end
        if not x.tick then
          missN, castN = missN + (a.miss or 0) + (a.other or 0), castN + a.n
          hitBack = hitBack + a.n * (x.school == "shadow" and params.shadowHit or params.holyHit)
        end
      elseif Kind(a.name) == "wand" then wandN = wandN + a.n
      elseif Base(a.name) ~= "Mind Flay" and Base(a.name) ~= "Shadow Word: Pain" then other = other + a.dmg end
    end
    for k, x in pairs(parts) do if not seen[k] then x.rate = mix(x.rate, 0, secs, 120) end end
    -- the measured miss is after the sheet's spell hit and the school's talent hit; the model
    -- subtracts those itself
    if castN > 0 then params.spellMiss = mix(params.spellMiss, missN / castN * 100 + sheet.spellHit + hitBack / castN, castN, 30) end
    if wand then params.wandUptime = mix(params.wandUptime, math.min(1, wandN / secs * wand.speed), secs, 120) end
    params.otherDps = mix(0, other / secs, secs, 120)
    local rates = {}
    for _, k in ipairs({ "Smite", "Mind Blast", "Mind Flay (dot)", "Shadow Word: Pain (dot)", "Holy Fire" }) do
      local x = parts[k]
      if x and x.rate > 0.002 then
        rates[#rates + 1] = ("%s %s %s"):format(F1(x.rate * 60), Base(k), x.tick and "tick/perc" or "/perc")
      end
    end
    notes[#notes + 1] = ("Kalibrálva %d rögzített harcból (%d mp): %s; pálca az idő %d%%-ában, minden más %s DPS.")
      :format(combat.fights, Round(secs), #rates > 0 and table.concat(rates, ", ") or "nincs varázslat", Round(params.wandUptime * 100), F1(params.otherDps))
  else
    notes[#notes + 1] = "Nincs rögzített harc, ezért tankönyvi értékekkel számol. Kapcsold be a harcnaplót (/wa log) a kalibráláshoz."
  end
  table.insert(notes, 1, PartsNote())
  notes[#notes + 1] = "A manát a modell nem számolja: az intellect csak a spell crit miatt ér valamit, a valóságban a nagyobb mana miatt többet (kevesebb pihenő, kevesebb pálca). A gyógyítást a modell nem számolja."

  -- the school the model's damage leans on (the enchant section adds a school's spell damage by it)
  local holy, shadow = 0, 0
  for _, x in pairs(parts) do
    local v = x.rate * (x.base + x.coef * (x.school == "shadow" and sheet.spShadow or sheet.spHoly))
    if x.school == "shadow" then shadow = shadow + v else holy = holy + v end
  end
  params.school = shadow > holy and "shadow" or "holy"

  local unbuffed = PR.Dps(sheet, params)
  local buffs = M.ResolveBuffs(level, input.buffs, input.data)
  local bInt, bSp = 0, 0
  for _, b in ipairs(buffs) do
    if b.selected and b.effect then bInt, bSp = bInt + (b.effect.int or 0), bSp + (b.effect.sp or 0) end
  end
  sheet.spHoly, sheet.spShadow, sheet.sp = sheet.spHoly + bSp, sheet.spShadow + bSp, sheet.sp + bSp
  sheet.spellCrit = sheet.spellCrit + bInt / intPerCrit
  sheet.critHoly, sheet.critShadow = sheet.critHoly + bInt / intPerCrit, sheet.critShadow + bInt / intPerCrit
  local baseline = PR.Dps(sheet, params)
  local equippedIds = {}
  for _, it in pairs(equipped) do if it.id then equippedIds[it.id] = true end end

  local ctx = M.Common({
    level = level, baseline = baseline, unbuffed = unbuffed, buffs = buffs, params = params, sheet = sheet,
    equipped = equipped, equippedIds = equippedIds, combat = combat, slotOrder = input.slotOrder,
  }, "PRIEST")

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
      local gain = PR.Dps(sh, params) - baseline
      if not best or gain > best.gain then best = { slot = slot, gain = gain } end
    end
    if best and best.gain > 0.05 then return best end
    return nil
  end

  function ctx.describe(add, weaponSub)
    local out = {}
    if add.weapon then
      local w = add.weapon
      if weaponSub == 19 then
        out[#out + 1] = ("Wand %s DPS / %s"):format(F1(WandDps(w)), F1(w.speed))
      else
        out[#out + 1] = ("%s %s–%s / %s"):format(M.WEAPON_NAMES[weaponSub or -1] or "Weapon", w.min, w.max, F1(w.speed))
      end
    end
    if (add.sp or 0) ~= 0 then out[#out + 1] = ("+%s spell power"):format(add.sp) end
    if (add.int or 0) ~= 0 then out[#out + 1] = ("+%s int"):format(add.int) end
    if (add.crit or 0) ~= 0 then out[#out + 1] = ("+%s%% crit"):format(add.crit) end
    return table.concat(out, ", ")
  end

  function ctx.buffGain(e)
    local sh = Apply(sheet, M.ZERO, { int = e.int or 0, sp = e.sp or 0 }, params)
    return PR.Dps(sh, params) - baseline
  end

  function ctx.weaponWarning() return nil end

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

function PR.Sources(abilities, total)
  local out = { nuke = 0, flay = 0, dot = 0, aoe = 0, wand = 0, melee = 0, other = 0 }
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

-- Shadow Word: Pain's share of the fight it was ticking: ticks x 3 s / fight length (percent),
-- nil when it did not tick
function PR.SwpUptime(ab, dur)
  local a = Find(ab, "Shadow Word: Pain (dot)")
  if not a or not dur or dur <= 0 then return nil end
  return math.min(100, a.n * 3 / dur * 100)
end

PR.ManaItems = function(fights) return WA.Mage.ManaItems(fights) end

local function CastTime(name, p)
  if name == "Smite" and p and p.parts and p.parts.Smite then return p.parts.Smite.cast end
  return PR.CAST[name] or 1.5
end

local GRADES = { { 90, "S" }, { 80, "A" }, { 65, "B" }, { 50, "C" }, { 0, "D" } }
function PR.Score(f, ctx)
  local parts = {}
  local function Part(key, label, got, max, text) parts[#parts + 1] = { key = key, label = label, points = got, max = max, text = text } end
  local dur = f.dur or 0
  local dps = dur > 0 and (f.dmg or 0) / dur or 0
  local baseline = ctx and WA.Combat.Comparable(f, ctx) and ctx.baseline or nil
  if baseline and baseline > 0 then
    local ratio = dps / baseline
    Part("dps", "DPS a várthoz képest", math.min(ratio / 1.1, 1) * 40, 40, ("%d DPS, a felszerelésedtől várt %d %d%%-a"):format(
      Round(dps), Round(baseline), Round(ratio * 100)))
  end
  local ab = f.ab or {}
  local p = ctx and ctx.params
  if dur >= 6 then
    local busy = 0
    for _, c in ipairs(f.casts or {}) do
      if c[2] ~= "Shoot" and not PR.MANA_ITEMS[c[2]] then busy = busy + CastTime(c[2], p) end
    end
    local shoot = Find(ab, "Shoot")
    local wand = ctx and ctx.sheet and ctx.sheet.wand
    if shoot and wand then busy = busy + shoot.n * wand.speed end
    local up = math.min(1, busy / dur)
    Part("active", "Folyamatosan castolsz", math.min(up / 0.8, 1) * 20, 20, ("az idő kb. %d%%-ában castoltál vagy lőttél pálcával (a castokból és a lövésekből)"):format(Round(up * 100)))
  end
  local lv = (f.level or 0) > 0 and f.level or (ctx and ctx.level) or 0
  if dur >= 15 and lv >= 4 then
    local up = PR.SwpUptime(ab, dur)
    if up then
      Part("dot", "Shadow Word: Pain a hosszabb harcban", math.min(up / 70, 1) * 15, 15, ("a Shadow Word: Pain a harc kb. %d%%-ában sebzett (a tickekből, 3 mp-enként egy)"):format(Round(up)))
    else
      Part("dot", "Shadow Word: Pain a hosszabb harcban", 0, 15, "nem sebzett Shadow Word: Pain ebben a 15 mp-nél hosszabb harcban")
    end
  end
  if type(f.gems) == "table" and #f.gems > 0 then
    local gain, over = 0, 0
    for _, t in ipairs(f.gems) do gain, over = gain + (t.gain or 0), over + (t.over or 0) end
    local kept = gain > 0 and 1 - over / gain or 1
    Part("mana", "A manaital nem megy kárba", kept * 15, 15, ("%d manaital: %d mana, ebből %d a maximum fölött elveszett"):format(#f.gems, Round(gain), Round(over)))
  end
  local got, max = 0, 0
  for _, x in ipairs(parts) do got, max = got + x.points, max + x.max end
  if max == 0 then return nil end
  local total = math.floor(got / max * 100 + 0.5)
  local grade = "D"
  for _, g in ipairs(GRADES) do if total >= g[1] then grade = g[2] break end end
  return { total = total, grade = grade, parts = parts, dps = dps }
end

function PR.Summary(r, ctx, fights)
  if not r then return nil end
  local src, share = PR.Sources(r.abilities, r.damage)
  local secs = r.seconds
  local s = { sources = src, shares = share, seconds = secs, dps = r.dps, rows = {}, mana = PR.ManaItems(fights) }
  -- Mind Blast against its cooldown: the most it can be cast is once every 8 s (plus its cast)
  local mb = Find(r.abilities, "Mind Blast")
  if mb then
    local l = (mb.hit or 0) + (mb.crit or 0)
    s.mb = { cpm = mb.n / secs * 60, max = 60 / PR.MB_CD, crit = l > 0 and (mb.crit or 0) / l * 100 or 0 }
  end
  local swp = Find(r.abilities, "Shadow Word: Pain (dot)")
  if swp and secs > 0 then s.swp = math.min(100, swp.n * 3 / secs * 100) end
  for _, a in ipairs(r.abilities) do
    local landed = (a.hit or 0) + (a.crit or 0) + (a.glance or 0)
    s.rows[#s.rows + 1] = { name = a.name, dmg = a.dmg, share = a.share, n = a.n, cpm = a.n / secs * 60,
      perCast = a.n > 0 and a.dmg / a.n or 0, avg = landed > 0 and a.dmg / landed or 0, kind = Kind(a.name) }
  end
  return s
end

local function Clock(start, tenths)
  local s = (start or 0) + (tonumber(tenths) or 0) / 10
  return date and date("%m.%d. %H:%M:%S", math.floor(s)) or tostring(math.floor(s))
end

function PR.Advise(r, fights)
  local C = WA.Combat
  local out = {}
  local function Push(o) out[#out + 1] = C.Finding(o) end
  if r.seconds < 300 then
    Push({ info = true, title = "Kevés még az adat", fact = ("Eddig %d harc és %d másodperc van rögzítve. Az arányok kb. 10 perc harc után megbízhatóak.")
      :format(r.fights, Round(r.seconds)) })
  end
  local _, share = PR.Sources(r.abilities, r.damage)
  local items = PR.ManaItems(fights)
  if #items.wasteful > 0 then
    local lines = {}
    for i = 1, math.min(3, #items.wasteful) do
      local x = items.wasteful[i]
      lines[i] = ("%s: %d manát adott, ebből %d elveszett"):format(Clock(x.start, x.t.t), x.t.gain, x.t.over)
    end
    Push({ title = "Manaital teli manánál", fault = true, rule = "manaItemCap",
      fact = ("%d manaital a mana nagyobbik felét a maximum fölé adta, az elveszett (harcnapló: a mana-esemény maga mondja meg, mennyi ment a maximum fölé):\n- %s%s\nÖsszesen %d, %d mana, ebből %d elveszett.")
        :format(#items.wasteful, table.concat(lines, "\n- "), #items.wasteful > 3 and ("\n- … és még " .. (#items.wasteful - 3)) or "",
          items.n, Round(items.gain), Round(items.over)),
      advice = "Manaitalt akkor igyál, amikor legalább annyi mana hiányzik, amennyit ad." })
  elseif items.n > 0 then
    Push({ info = true, title = "Manaitalok", fact = ("%d manaital a harcokban: %d mana, ebből %d ment a maximum fölé."):format(items.n, Round(items.gain), Round(items.over)) })
  end
  if r.seconds >= 300 and share.wand >= 40 then
    Push({ title = "Sokat pálcázol", rule = "wandFlat",
      fact = ("A sebzésed %s%%-a a pálcáé."):format(F1(share.wand)),
      advice = "A pálca sebzése nem nő a spell powerrel. Priestként a pálca a mana kímélése miatt rendben van; ha a Mind Blast és a Shadow Word: Pain kimarad, az a sebzés nagyobbik része.",
      missing = "a manád a harcok alatt (a harcnapló nem mutatja)" })
  end
  local mb = Find(r.abilities, "Mind Blast")
  if mb and r.seconds >= 300 then
    local cpm = mb.n / r.seconds * 60
    Push({ info = true, title = "Mind Blast a cooldownhoz képest",
      fact = ("%s Mind Blast percenként; 8 mp-es cooldownnal legfeljebb 7,5 lehet (Wowhead Forever spell=8092). A rövid harcokban ennyi nem is fér bele."):format(F1(cpm)) })
  end
  if r.seconds >= 120 then
    Push({ info = true, title = "Mért arányok", fact = ("Sebzés: direkt varázslat %d%%, Mind Flay %d%%, DoT %d%%, AoE %d%%, pálca %d%%, egyéb %d%%.")
      :format(Round(share.nuke), Round(share.flay), Round(share.dot), Round(share.aoe), Round(share.wand), Round(share.other + share.melee)) })
  end
  return out
end
