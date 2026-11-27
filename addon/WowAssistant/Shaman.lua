-- Waystone: the shaman damage model, levels 1-60 (enhancement-style leveling: melee with a
-- weapon imbue, shocks between swings, Lightning Bolt to pull, a Searing Totem). Pure like
-- Model.lua: the same context shape (score, describe, buffGain, weaponWarning, ...) so the plan,
-- the gear report and the pages work for shamans unchanged.
--
-- Classic rules the model follows:
--   * melee attack power = 2 × strength (+ level × 2 − 20); agility gives melee crit only
--   * one weapon (shamans do not dual wield in Classic): a two-hander or a one-hander + shield;
--     two-hand axes and maces need the Two-Handed Axes and Maces talent in Classic; Forever's talent
--     trees do not have it (Wowhead Forever talent calculator), so there the weapon skill decides
--   * the weapon imbue multiplies the white damage: Rockbiter early, Flametongue from 10,
--     Windfury from 30 (strongest on a slow two-hander)
--   * Earth Shock and Lightning Bolt grow with spell power (coefficient = cast time / 3.5, less
--     for ranks learned before level 20); a spell crit does 1.5×, and Elemental Fury raises the
--     50% bonus by 20% a rank (Forever: 5 ranks, 2× at the fifth)
--   * intellect gives spell crit and mana; mana is not modeled, so intellect counts for little
--   * Flurry: a melee crit makes the next three swings faster (Forever: 6% a rank)
--
-- Extra input besides Model.lua's: int, sp (nature spell power), spellCrit, known = { [spell] =
-- true }, talents = Talent.lua's T.Effects: flurry, thundering, fury (the numbers of the rank's
-- Wowhead Forever text), elemRockbiter / elemWindfury / elemFlametongue, stormstrike, twoHand
-- (ranks), read, absent.

local _, WA = ...
WA = WA or {}
local M = WA.Model
local S = {}
WA.Shaman = S

local function F1(n) return ("%.1f"):format(n) end
local Round = M.Round

-- { level learned, average damage, cast time } per rank.
local RANKS = {
  earth = { { 4, 20 }, { 8, 37 }, { 14, 67 }, { 24, 130 }, { 36, 242 }, { 48, 383 }, { 56, 531 } },
  flame = { { 10, 53 }, { 18, 99 }, { 28, 191 }, { 40, 332 }, { 52, 501 }, { 60, 612 } },
  bolt = { { 1, 16, 1.5 }, { 8, 30, 2.0 }, { 14, 52, 2.5 }, { 20, 94, 3.0 }, { 26, 140, 3.0 }, { 32, 190, 3.0 },
    { 38, 250, 3.0 }, { 44, 308, 3.0 }, { 50, 378, 3.0 }, { 56, 452, 3.0 } },
}
local function Rank(name, level)
  local v
  for _, r in ipairs(RANKS[name]) do if r[1] <= level then v = r end end
  return v
end
S.Rank = Rank

-- spells learned before level 20 get a smaller share of spell power
local function LowLevel(rankLevel) return math.max(0.25, 1 - math.max(0, 20 - rankLevel) * 0.0375) end

S.SHOCKS = { ["Earth Shock"] = true, ["Flame Shock"] = true, ["Frost Shock"] = true }
S.IMBUE = { ["Flametongue Attack"] = true, ["Windfury Attack"] = true, ["Frostbrand Attack"] = true }
S.TOTEM = { ["Searing Totem"] = true, ["Searing Bolt"] = true, ["Magma Totem"] = true, ["Fire Nova"] = true,
  ["Fire Nova Totem"] = true, Attack = true }
local SPELLS = { ["Lightning Bolt"] = true, ["Chain Lightning"] = true, ["Earth Shock"] = true, ["Flame Shock"] = true,
  ["Frost Shock"] = true, ["Lightning Shield"] = true }
local MELEE = { Melee = true, Stormstrike = true }

local function IsTotem(name)
  local base = name:gsub(" %(dot%)$", "")
  return base:sub(1, 5) == "Pet: " or S.TOTEM[base] == true
end
S.IsTotem = IsTotem

---------------------------------------------------------------------------
-- the model
---------------------------------------------------------------------------
local function Avg(w, ap) return (w.min + w.max) / 2 + (ap / 14) * w.speed end

-- Sustained DPS of one target, leveling style.
function S.Dps(sh, p)
  local total = p.totemDps + p.otherDps
  if sh.mh then
    local mcrit = math.max(0, math.min(sh.crit, 100)) / 100
    local miss = math.max(0, 5 - sh.hit) / 100
    local dodge = p.dodge / 100
    local whiteF = math.max(0, 1 - miss - dodge - mcrit) + mcrit * 2
    local yellowF = math.max(0, 1 - miss - dodge) * (1 + mcrit)
    -- Flurry: up after a crit for the next three swings
    local haste = 1 + p.flurry * (1 - (1 - mcrit) ^ 3)
    local avg = Avg(sh.mh, sh.ap)
    total = total + p.meleeUptime * avg / sh.mh.speed * haste * whiteF * p.imbueMult
    total = total + p.stormPerSec * avg * yellowF
  end
  local scrit = math.max(0, math.min(sh.spellCrit, 100)) / 100
  local sf = math.max(0, 1 - p.spellMiss / 100) * (1 + scrit * (p.spellCritMult - 1))
  total = total + p.shockPerSec * (p.shockDamage + p.shockCoef * sh.sp) * sf * p.stormBonus
  total = total + p.boltPerSec * (p.boltDamage + p.boltCoef * sh.sp) * sf
  return total
end

local function Apply(sh, remove, add, p)
  local dAgi = ((add.agi or 0) - (remove.agi or 0)) * p.statMult
  local dStr = ((add.str or 0) - (remove.str or 0)) * p.statMult
  local dInt = ((add.int or 0) - (remove.int or 0)) * p.statMult
  return {
    ap = sh.ap + (add.ap or 0) - (remove.ap or 0) + 2 * dStr,
    crit = sh.crit + (add.crit or 0) - (remove.crit or 0) + dAgi / p.agiPerCrit,
    hit = sh.hit + (add.hit or 0) - (remove.hit or 0),
    sp = sh.sp + (add.sp or 0) - (remove.sp or 0),
    spellCrit = sh.spellCrit + dInt / p.intPerCrit,
    mh = sh.mh,
  }
end

-- the white-damage multiplier of the best imbue at this level; Elemental Weapons raises the
-- imbue's own part by its rank's % (Wowhead Forever: Windfury 13/27/40%, Flametongue 5/10/15%,
-- Rockbiter 7/13/20%)
local function ImbuePrior(level, mh, tal)
  if level >= 30 then
    local base = (mh and mh.speed >= 3.0) and 1.22 or 1.15
    return 1 + (base - 1) * (1 + (tal.elemWindfury or 0) / 100)
  end
  if level >= 10 then return 1 + 0.10 * (1 + (tal.elemFlametongue or 0) / 100) end
  return 1 + 0.06 * (1 + (tal.elemRockbiter or 0) / 100)
end

---------------------------------------------------------------------------
-- context
---------------------------------------------------------------------------
function S.Context(input)
  local level = input.level or 1
  local equipped = input.equipped or {}
  local tal = input.talents or {}
  local known = input.known or {}
  local notes = {}
  local function eq(slot) return equipped[slot] and equipped[slot].stats or M.ZERO end

  local agi = input.agi or 0
  local crit = input.crit or 0
  local agiPerCrit = agi / math.max(0.1, crit - (tal.thundering or 0) - 1.7)
  if not (agiPerCrit > 0.8 and agiPerCrit < 40) then agiPerCrit = 1 + (19 * (level - 1)) / 59 end
  local intPerCrit = 6 + (53.5 * (level - 1)) / 59
  notes[#notes + 1] = ("1%% közelharci crit ≈ %s agility, 1%% spell crit ≈ %s intellect; 1 strength = 2 AP."):format(F1(agiPerCrit), F1(intPerCrit))

  local mh = eq("MAIN_HAND").weapon
  local sheet = {
    ap = input.ap or 0, crit = crit, hit = input.hit or 0, sp = input.sp or 0,
    spellCrit = input.spellCrit or 0, mh = mh,
  }

  local earth, bolt = Rank("earth", level), Rank("bolt", level)
  local storm = (tal.stormstrike or 0) > 0 or known.Stormstrike == true
  local params = {
    level = level, agiPerCrit = agiPerCrit, intPerCrit = intPerCrit, statMult = 1,
    dodge = 5, spellMiss = 4,
    meleeUptime = mh and (level < 10 and 0.6 or 0.85) or 0,
    imbueMult = ImbuePrior(level, mh, tal),
    flurry = (tal.flurry or 0) / 100,
    -- Stormstrike: 8 s cooldown on Forever (Wowhead Forever spell=17364); the prior is about 80% of
    -- that (every 10 s), as the shocks' prior leaves room for mana and the global cooldown
    stormPerSec = (storm and level >= 40) and 1 / 10 or 0,
    shockPerSec = earth and 1 / 11 or 0,
    shockDamage = earth and earth[2] or 0, shockCoef = earth and 0.386 * LowLevel(earth[1]) or 0,
    boltPerSec = level < 10 and 1 / 15 or 1 / 40,
    boltDamage = bolt[2], boltCoef = bolt[3] / 3.5 * LowLevel(bolt[1]),
    spellCritMult = 1.5 + 0.5 * (tal.fury or 0) / 100,
    totemDps = level >= 10 and 0.12 * level or 0,
    otherDps = 0, notes = notes,
  }
  -- Stormstrike: +20% nature damage on the next two spells, about every other shock
  params.stormBonus = params.stormPerSec > 0 and 1.1 or 1

  -- Pull every default towards what the recorded fights show.
  local combat = input.combat
  local function mix(prior, measured, n, half)
    local w = n / (n + half)
    return prior * (1 - w) + measured * w
  end
  local function landed(a) return (a.hit or 0) + (a.crit or 0) + (a.glance or 0) end
  if combat and combat.seconds > 0 then
    local secs = combat.seconds
    local ab = {}
    for _, a in ipairs(combat.abilities) do if not ab[a.name] then ab[a.name] = a end end
    local melee = ab.Melee
    if mh then
      params.meleeUptime = mix(params.meleeUptime, math.min(1, (melee and melee.n or 0) / secs * mh.speed), secs, 120)
      if melee and melee.n > 0 then params.dodge = mix(params.dodge, (melee.dodge or 0) / melee.n * 100, melee.n, 100) end
    end
    -- shocks: how often, and the damage of one without the spell power part
    local shockN, shockMiss, shockDmg, shockLanded, shockCrit = 0, 0, 0, 0, 0
    for name in pairs(S.SHOCKS) do
      local a = ab[name]
      if a then
        shockN, shockMiss = shockN + a.n, shockMiss + (a.miss or 0) + (a.resist or 0)
        shockDmg, shockLanded, shockCrit = shockDmg + a.dmg, shockLanded + landed(a), shockCrit + (a.crit or 0)
      end
    end
    if earth then params.shockPerSec = mix(params.shockPerSec, shockN / secs, secs, 120) end
    if shockN > 0 then params.spellMiss = mix(params.spellMiss, shockMiss / shockN * 100, shockN, 30) end
    if shockLanded > 0 then
      local per = shockDmg / (shockLanded + (params.spellCritMult - 1) * shockCrit)
      params.shockDamage = mix(params.shockDamage, math.max(0, per - params.shockCoef * sheet.sp), shockLanded, 10)
    end
    local lb = ab["Lightning Bolt"]
    params.boltPerSec = mix(params.boltPerSec, (lb and lb.n or 0) / secs, secs, 120)
    if lb and landed(lb) > 0 then
      local per = lb.dmg / (landed(lb) + (params.spellCritMult - 1) * (lb.crit or 0))
      params.boltDamage = mix(params.boltDamage, math.max(0, per - params.boltCoef * sheet.sp), landed(lb), 10)
    end
    local ss = ab.Stormstrike
    if params.stormPerSec > 0 or ss then params.stormPerSec = mix(params.stormPerSec, (ss and ss.n or 0) / secs, secs, 120) end
    local totem, imbue, other = 0, 0, 0
    for _, a in ipairs(combat.abilities) do
      local base = a.name:gsub(" %(dot%)$", "")
      if IsTotem(a.name) then totem = totem + a.dmg
      elseif S.IMBUE[base] then imbue = imbue + a.dmg
      elseif not MELEE[a.name] and not S.SHOCKS[a.name] and a.name ~= "Lightning Bolt" then other = other + a.dmg end
    end
    params.totemDps = mix(params.totemDps, totem / secs, secs, 120)
    if imbue > 0 and melee and melee.dmg > 0 then
      params.imbueMult = mix(params.imbueMult, 1 + imbue / melee.dmg, secs, 120)
    end
    params.otherDps = mix(0, other / secs, secs, 120)
    notes[#notes + 1] = ("Kalibrálva %d rögzített harcból (%d mp). Közelharc az idő %d%%-ában, %s%% dodge; az imbue %d%%-ot ad a fehér sebzéshez.")
      :format(combat.fights, Round(secs), Round(params.meleeUptime * 100), F1(params.dodge), Round((params.imbueMult - 1) * 100))
    notes[#notes + 1] = ("Percenként: shock %s (%d sebzés), Lightning Bolt %s (%d), Stormstrike %s. Totem %s DPS, egyéb (DoT, Lightning Shield) %s DPS.")
      :format(F1(params.shockPerSec * 60), Round(params.shockDamage), F1(params.boltPerSec * 60), Round(params.boltDamage),
        F1(params.stormPerSec * 60), F1(params.totemDps), F1(params.otherDps))
  else
    notes[#notes + 1] = ("Nincs rögzített harc, ezért tankönyvi értékekkel számol: az idő %d%%-ában közelharc, %s shock és %s Lightning Bolt percenként, imbue +%d%%. Kapcsold be a harcnaplót (/wa log) a kalibráláshoz.")
      :format(Round(params.meleeUptime * 100), F1(params.shockPerSec * 60), F1(params.boltPerSec * 60), Round((params.imbueMult - 1) * 100))
  end
  if not mh then notes[#notes + 1] = "Nincs fegyvered a főkézben: egy kétkezes bot, buzogány vagy balta a legnagyobb fejlesztés." end
  notes[#notes + 1] = "A manát a modell nem számolja: az intellect csak a spell crit miatt ér valamit, a valóságban a több shock és gyógyítás miatt többet."

  local unbuffed = S.Dps(sheet, params)
  local buffs = M.ResolveBuffs(level, input.buffs, input.data)
  local bAgi, bStr, bAp, bCrit, pct = 0, 0, 0, 0, 0
  for _, b in ipairs(buffs) do
    if b.selected and b.effect then
      bAgi = bAgi + (b.effect.agi or 0)
      bStr = bStr + (b.effect.str or 0)
      bAp = bAp + (b.effect.ap or 0)
      bCrit = bCrit + (b.effect.crit or 0)
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
  local baseline = S.Dps(sheet, params)
  local equippedIds = {}
  for _, it in pairs(equipped) do if it.id then equippedIds[it.id] = true end end

  local ctx = M.Common({
    level = level, baseline = baseline, unbuffed = unbuffed, buffs = buffs, params = params, sheet = sheet,
    equipped = equipped, equippedIds = equippedIds, combat = combat, slotOrder = input.slotOrder,
  }, "SHAMAN")

  -- Two-hand axes and maces: where the talent trees have Two-Handed Axes and Maces, it is needed
  -- (known from the talent scan, else from level 20, the first level it can be taken). Forever's
  -- trees do not have it (absent): there the game's weapon skill decides, where it is known.
  -- Staves are fine either way.
  local skills = input.skills
  local noTalent = tal.absent and tal.absent["Two-Handed Axes and Maces"]
  local function twoHandOk(level2, sub)
    if (tal.twoHand or 0) > 0 then return true end
    if noTalent then
      if skills and next(skills) then return skills[M.WEAPON_SKILLS[sub]] ~= nil end
      return true
    end
    return not tal.read and level2 >= 20
  end
  local baseUsable = ctx.usableAt
  function ctx.usableAt(itemClass, sub, level2)
    if itemClass == 2 and (sub == 1 or sub == 5) and not twoHandOk(level2, sub) then return false end
    return baseUsable(itemClass, sub, level2)
  end

  -- Best slot for an item and the DPS it adds there; nil when it is not an upgrade. A two-hand
  -- weapon replaces both hands (the shield too).
  function ctx.score(add, slots, twoHand, sub)
    local best
    for _, slot in ipairs(slots) do
      local remove = eq(slot)
      if twoHand then
        local oh = eq("OFF_HAND")
        remove = {}
        for k in pairs(M.ZERO) do remove[k] = (eq(slot)[k] or 0) + (oh[k] or 0) end
      end
      local sh = Apply(sheet, remove, add, params)
      if slot == "MAIN_HAND" then sh.mh = add.weapon end
      if slot ~= "OFF_HAND" or not add.weapon then
        local gain = S.Dps(sh, params) - baseline
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
    if (add.int or 0) ~= 0 then bits[#bits + 1] = ("+%s int"):format(add.int) end
    if (add.sp or 0) ~= 0 then bits[#bits + 1] = ("+%s spell power"):format(add.sp) end
    return table.concat(bits, ", ")
  end

  function ctx.buffGain(e)
    local add = { agi = e.agi or 0, str = e.str or 0, ap = e.ap or 0, crit = e.crit or 0, hit = 0, int = e.int or 0, sp = e.sp or 0 }
    local sh = Apply(sheet, M.ZERO, add, params)
    return S.Dps(sh, params) - baseline
  end

  function ctx.weaponWarning(itemClass, sub)
    if itemClass ~= 2 then return nil end
    if (sub == 1 or sub == 5) and (tal.twoHand or 0) == 0 and not noTalent then
      return "a Two-Handed Axes and Maces talent kell hozzá (Enhancement)"
    end
    if not skills or not next(skills) then return nil end
    local line = M.WEAPON_SKILLS[sub]
    local s = line and skills[line]
    if not s then return ("%s nincs kitanulva (fegyvermester)"):format(tostring(line)) end
    if s.rank < s.max - 15 then return ("%s skill %d/%d"):format(line, s.rank, s.max) end
    return nil
  end

  -- Shaman advice from the model's own numbers.
  local advice = {}
  local function Push(o) advice[#advice + 1] = WA.Combat.Finding(o) end
  if combat and combat.seconds >= 120 then
    if mh and params.meleeUptime < 0.6 and level >= 10 then
      Push({ title = "Kevés közelharc", rule = "shamanMelee",
        fact = ("A harcaidban az idő kb. %d%%-ában ütöttél."):format(Round(params.meleeUptime * 100)),
        advice = "Enhancement szintezésnél húzz Lightning Bolttal, aztán üss; elementalként ez így rendben van." })
    end
    if earth and params.shockPerSec * 60 < 2 then
      Push({ title = "Ritkán shockolsz", fault = true, rule = "earthShock",
        fact = ("Percenként kb. %s shock."):format(F1(params.shockPerSec * 60)),
        advice = "Ha van manád, az Earth Shock minden 6 mp-ben mehet.",
        missing = "a manád a harcokban" })
    end
    if level >= 10 and params.totemDps < 0.03 * level then
      Push({ title = "Alig sebeznek a totemjeid", fault = true, rule = "searingTotem",
        fact = ("A totemjeid kb. %s DPS-t adtak."):format(F1(params.totemDps)),
        advice = "Hosszabb harcban vagy több mobnál a Searing Totem olcsó sebzés.",
        missing = "hogy megtanultad-e, és a harcok hossza" })
    end
  end
  ctx.advice = advice
  return ctx
end

---------------------------------------------------------------------------
-- the combat page: score, breakdown and advice for shamans
---------------------------------------------------------------------------
local function Find(list, name)
  for _, a in ipairs(list or {}) do if a.name == name then return a end end
  return nil
end

-- Where the damage came from: melee, imbue, spell, totem, dot, other (each { dmg, share }).
function S.Sources(abilities, total)
  local out = { melee = 0, imbue = 0, spell = 0, totem = 0, dot = 0, other = 0 }
  for _, a in ipairs(abilities or {}) do
    local name, dmg = a.name or "", a.dmg or 0
    if IsTotem(name) then out.totem = out.totem + dmg
    elseif name:sub(-6) == " (dot)" then out.dot = out.dot + dmg
    elseif MELEE[name] then out.melee = out.melee + dmg
    elseif S.IMBUE[name] then out.imbue = out.imbue + dmg
    elseif SPELLS[name] then out.spell = out.spell + dmg
    else out.other = out.other + dmg end
  end
  local sum = total and total > 0 and total or (out.melee + out.imbue + out.spell + out.totem + out.dot + out.other)
  local shares = {}
  for k, v in pairs(out) do shares[k] = sum > 0 and v / sum * 100 or 0 end
  return out, shares
end

local function Kind(name)
  if IsTotem(name) then return "totem" end
  if name:sub(-6) == " (dot)" then return "dot" end
  if MELEE[name] then return "melee" end
  if S.IMBUE[name] then return "imbue" end
  if SPELLS[name] then return "spell" end
  return "other"
end

-- Swing activity: melee swings against what the weapon could swing in that time (0-1).
function S.SwingUptime(swings, seconds, mh)
  if not mh or not seconds or seconds <= 0 then return nil end
  local possible = seconds / mh.speed
  return possible > 0 and math.min(1, swings / possible) or nil
end

local function ShockCount(ab)
  local n = 0
  for name in pairs(S.SHOCKS) do local a = Find(ab, name) n = n + (a and a.n or 0) end
  return n
end

-- Score of one fight, 0-100, from what a shaman controls. ctx is the shaman model (expected DPS,
-- weapon speed); parts: { key, label, points, max, text }.
local GRADES = { { 90, "S" }, { 80, "A" }, { 65, "B" }, { 50, "C" }, { 0, "D" } }
function S.Score(f, ctx)
  local parts = {}
  local function Part(key, label, got, max, text) parts[#parts + 1] = { key = key, label = label, points = got, max = max, text = text } end
  local dur = f.dur or 0
  local dps = dur > 0 and (f.dmg or 0) / dur or 0
  local level = f.level or (ctx and ctx.level) or 0
  -- only against the model of the same level and gear (Combat.Comparable)
  local baseline = ctx and WA.Combat.Comparable(f, ctx) and ctx.baseline or nil
  if baseline and baseline > 0 then
    local ratio = dps / baseline
    Part("dps", "DPS a várthoz képest", math.min(ratio / 1.1, 1) * 40, 40, ("%d DPS, a felszerelésedtől várt %d %d%%-a"):format(
      Round(dps), Round(baseline), Round(ratio * 100)))
  end
  local ab = f.ab or {}
  local mh = ctx and ctx.sheet and ctx.sheet.mh
  local melee = Find(ab, "Melee")
  if mh and dur >= 6 then
    local up = S.SwingUptime(melee and melee.n or 0, dur, mh) or 0
    Part("melee", "Folyamatosan ütsz", math.min(up / 0.85, 1) * 20, 20, ("%d ütés, a lehetséges %d%%-a"):format(melee and melee.n or 0, Round(up * 100)))
  end
  if dur >= 12 and level >= 4 then
    local perMin = ShockCount(ab) / dur * 60
    Part("shock", "Shock a harcban", math.min(perMin / 3, 1) * 15, 15, ("%s shock percenként (jó: 3 fölött)"):format(F1(perMin)))
  end
  if dur >= 25 and level >= 10 then
    local used = false
    for _, a in ipairs(ab) do if IsTotem(a.name) then used = true end end
    for _, c in ipairs(f.casts or {}) do if (c[2] or ""):find("Totem") then used = true end end
    Part("totem", "Totem a hosszú harcban", used and 10 or 0, 10, used and "volt totem" or "nem tettél le totemet (25 mp-nél hosszabb harc)")
  end
  local storm = ctx and ctx.params and ctx.params.stormPerSec or 0
  if dur >= 12 and level >= 40 and (storm > 0 or Find(ab, "Stormstrike")) then
    local ss = Find(ab, "Stormstrike")
    local perMin = (ss and ss.n or 0) / dur * 60
    -- full points at 6 a minute: 80% of the 7.5 an 8 s cooldown allows (Wowhead Forever spell=17364)
    Part("storm", "Stormstrike cooldownra", math.min(perMin / 6, 1) * 10, 10, ("%s Stormstrike percenként (8 mp a cooldown, legfeljebb 7,5)"):format(F1(perMin)))
  end
  local got, max = 0, 0
  for _, p in ipairs(parts) do got, max = got + p.points, max + p.max end
  if max == 0 then return nil end
  local total = math.floor(got / max * 100 + 0.5)
  local grade = "D"
  for _, g in ipairs(GRADES) do if total >= g[1] then grade = g[2] break end end
  return { total = total, grade = grade, parts = parts, dps = dps }
end

-- The raid-log style summary of many fights (r = WA.Combat.Report): damage sources, swing
-- activity, shocks per minute, casts per minute and damage per cast, Lightning Shield uptime.
function S.Summary(r, ctx)
  if not r then return nil end
  local src, share = S.Sources(r.abilities, r.damage)
  local secs = r.seconds
  local melee = Find(r.abilities, "Melee")
  local mh = ctx and ctx.sheet and ctx.sheet.mh
  local s = {
    sources = src, shares = share, seconds = secs, dps = r.dps,
    swingUptime = melee and S.SwingUptime(melee.n, secs, mh) or nil,
    meleeMiss = melee and melee.n > 0 and ((melee.miss or 0) + (melee.dodge or 0) + (melee.parry or 0)) / melee.n * 100 or nil,
    meleeCrit = melee and (melee.hit + melee.crit) > 0 and melee.crit / (melee.hit + melee.crit) * 100 or nil,
    shocksPerMin = secs > 0 and ShockCount(r.abilities) / secs * 60 or 0,
    rows = {},
  }
  for _, a in ipairs(r.auras or {}) do
    if a.name == "Lightning Shield" then s.shield = a.uptimePct end
  end
  for _, a in ipairs(r.abilities) do
    local landed = (a.hit or 0) + (a.crit or 0) + (a.glance or 0)
    s.rows[#s.rows + 1] = { name = a.name, dmg = a.dmg, share = a.share, n = a.n, cpm = a.n / secs * 60,
      perCast = a.n > 0 and a.dmg / a.n or 0, avg = landed > 0 and a.dmg / landed or 0, kind = Kind(a.name) }
  end
  return s
end

-- Advice from all the recorded fights (instead of the rogue's).
function S.Advise(r, fights)
  local out = {}
  local function Push(o) out[#out + 1] = WA.Combat.Finding(o) end
  local melee = Find(r.abilities, "Melee")
  local level = fights[1] and fights[1].level or 0
  if r.seconds < 300 or not melee or melee.n < 100 then
    Push({ info = true, title = "Kevés még az adat", fact = ("Eddig %d harc, %d másodperc és %d ütés van rögzítve. Az arányok kb. 10 perc harc után megbízhatóak.")
      :format(r.fights, Round(r.seconds), melee and melee.n or 0) })
  end
  local _, share = S.Sources(r.abilities, r.damage)
  if level >= 10 and r.seconds >= 120 and share.spell > 50 and share.melee < 35 then
    Push({ title = "A sebzésed nagyja varázslat", rule = "shamanMelee",
      fact = ("A sebzésed %d%%-a varázslat, %d%%-a közelharc."):format(Round(share.spell), Round(share.melee)),
      advice = "Enhancement szintezésnél a Lightning Bolt inkább húzásra jó, a mana shockra és gyógyításra; elementalként ez így rendben van." })
  end
  if melee and melee.n >= 50 then
    local miss = ((melee.miss or 0) + (melee.dodge or 0) + (melee.parry or 0)) / melee.n * 100
    if miss > 12 then
      Push({ title = "Sok ütés megy mellé", rule = "hitGear",
        fact = ("Az ütéseid %s%%-a miss, dodge vagy parry."):format(F1(miss)),
        advice = "A +hit tárgyak segítenek; a parry csak szemből jön." })
    end
  end
  local perMin = r.seconds > 0 and ShockCount(r.abilities) / r.seconds * 60 or 0
  if level >= 4 and r.seconds >= 120 and perMin < 1.5 then
    Push({ title = "Ritkán shockolsz", fault = true, rule = "earthShock",
      fact = ("Percenként %s shock."):format(F1(perMin)),
      advice = "Ha van manád, az Earth Shock azonnali sebzés és megszakítás; hosszabb harcban a Flame Shock.",
      missing = "a manád a harcokban (a gyógyításra tartott mana nem látszik)" })
  end
  if level >= 10 and r.seconds >= 300 and share.totem < 2 then
    Push({ title = "Alig sebeznek a totemjeid", fault = true, rule = "searingTotem",
      fact = ("A sebzésed %s%%-a totemé."):format(F1(share.totem)),
      advice = "A Searing Totem (10-től) olcsó sebzés hosszabb harcban; több mobra a Magma Totem (26-tól).",
      missing = "hogy megtanultad-e a Searing Totemet, és a harcok hossza a letétel pillanatában" })
  end
  local imbueSeen = false
  for name in pairs(S.IMBUE) do if Find(r.abilities, name) then imbueSeen = true end end
  if level >= 30 and r.seconds >= 300 and not imbueSeen then
    Push({ title = "Nincs Windfury- vagy Flametongue-sebzés", fault = true, rule = "windfury",
      fact = "A harcokban nincs Windfury Attack vagy Flametongue Attack.",
      advice = "30-tól a Windfury Weapon (lassú kétkezesen) a legerősebb imbue.",
      missing = "melyik imbue volt a fegyvereden (a Rockbiter nem látszik a harcnaplóban)" })
  end
  local shield
  for _, a in ipairs(r.auras or {}) do if a.name == "Lightning Shield" then shield = a.uptimePct end end
  if level >= 8 and r.seconds >= 120 and (shield or 0) < 30 then
    Push({ title = "Lightning Shield ritkán van fent", fault = true, rule = "lightningShield",
      fact = ("A harcidő %d%%-ában volt fent a Lightning Shield."):format(Round(shield or 0)),
      advice = "Ha a mob ütöget, ez ingyen sebzés.",
      missing = "a manád, és hogy megtanultad-e" })
  end
  if melee and melee.n >= 100 then
    local landed = melee.hit + melee.crit
    Push({ info = true, title = "Mért arányok", fact = ("Közelharc: %s%% miss, %s%% dodge, %s%% crit. Sebzés: közelharc %d%%, imbue %d%%, varázslat %d%%, totem %d%%, DoT %d%%.")
      :format(F1((melee.miss or 0) / melee.n * 100), F1((melee.dodge or 0) / melee.n * 100), F1(landed > 0 and melee.crit / landed * 100 or 0),
        Round(share.melee), Round(share.imbue), Round(share.spell), Round(share.totem), Round(share.dot)) })
  end
  return out
end
