-- Waystone: the druid damage model, levels 1-60 (feral-style leveling: Wrath and Moonfire before
-- Cat Form, then Cat Form with Claw, Rake, Rip and Ferocious Bite). Pure like Model.lua and
-- Shaman.lua: the same context shape (score, describe, buffGain, weaponWarning, ...) so the plan,
-- the gear report and the pages work for druids unchanged.
--
-- Forever rules the model follows (WoWSims Forever d5144855, Wowhead Forever, 2026-11-26):
--   * Cat Form swings once a second with a paw whose damage is the main-hand weapon's DPS x 1.0
--     (+-20%): the weapon's speed does not count, its DPS does (sim/druid/forms.go feralWeapon);
--     attack power adds AP / 14 per second as for any weapon
--   * Claw (45 energy), Shred (60, from behind) and Rake (40) build a combo point; Rip (30) and
--     Ferocious Bite (35) spend them all (Wowhead Forever spell=1082, 5221, 1822, 1079, 22568)
--   * Ferocious Bite: base roll + per point + every extra energy + AP per point (sim/druid/
--     ferocious_bite.go); Rip: per point, 4 points' AP at most (sim/druid/rip.go)
--   * Rake bleeds for 9 s (a tick every 3 s), Rip for 12 s (a tick every 2 s) (Wowhead Forever)
--   * Tiger's Fury is not in the game on Forever (Wowhead Forever spell=5217)
--   * energy regenerates 10 a second (20 every 2 s tick)
-- Not verified for Forever, kept from Classic and named in the notes: 1 agility = 1 attack power
-- in Cat Form, 1 strength = 2.
--
-- Talents (WA-032g, the numbers of the rank's Wowhead Forever text): Ferocity (cheaper Claw and
-- Rake), Savage Fury (builders), Natural Instinct (the abilities' crit bonus), Sharpened Claws,
-- Leader of the Pack and Predatory Strikes (in the forms: on the sheet when read in Cat Form),
-- Heart of the Wild (intellect, strength in Cat Form), Naturalist (all damage), Vengeance (the
-- spells' crit bonus), Eclipse (Wrath crit), Moonkin Form (arcane and nature damage, crit aura).
-- Most points in Balance: the caster model even with Cat Form.
--
-- Extra input besides Model.lua's: int, sp (nature spell power), spellCrit, spellHit, form (the
-- shapeshift form at reading: "cat", "bear", "moonkin", "caster", ...), catAp (attack power last
-- read in Cat Form), known = { [spell] = true/false }, tab (the talent tab with the most points),
-- talents = Talent.lua's T.Effects.

local _, WA = ...
local L = WA.L
WA = WA or {}
local M = WA.Model
local D = {}
WA.Druid = D

local function F1(n) return ("%.1f"):format(n) end
local Round = M.Round

D.CAT_BUILD = { Claw = true, Shred = true, Rake = true, Ravage = true, Pounce = true }
D.CAT_FINISH = { Rip = true, ["Ferocious Bite"] = true }
D.BEAR = { Maul = true, Swipe = true, Lacerate = true, ["Primal Bite"] = true, Bash = true }
D.SPELLS = { Wrath = true, Moonfire = true, Starfire = true, ["Insect Swarm"] = true, Hurricane = true, Thorns = true,
  ["Entangling Roots"] = true }
-- bleed tick interval in seconds (Wowhead Forever spell=1822 Rake, 1079 Rip)
D.BLEED_TICK = { Rake = 3, Rip = 2 }
D.ENERGY_PER_SEC = 10

local function Base(name) return (name or ""):gsub(" %(dot%)$", "") end
local function IsDot(name) return (name or ""):sub(-6) == " (dot)" end

-- melee (white), cat (builders and finishers), bleed (Rake/Rip/Pounce ticks), bear, spell, other
local function Kind(name)
  local base = Base(name)
  if name == "Melee" then return "melee" end
  if IsDot(name) and (D.BLEED_TICK[base] or base == "Pounce") then return "bleed" end
  if D.SPELLS[base] then return "spell" end
  if D.CAT_BUILD[base] or D.CAT_FINISH[base] then return "cat" end
  if D.BEAR[base] then return "bear" end
  return "other"
end
D.Kind = Kind

-- The paw's average damage before attack power: the weapon's DPS x 1.0 s (no weapon: 1).
function D.PawAvg(w)
  if not w or not w.speed or w.speed <= 0 then return 1 end
  return (w.min + w.max) / 2 / w.speed
end

---------------------------------------------------------------------------
-- the model
---------------------------------------------------------------------------
-- Sustained DPS of one target. p.cat: Cat Form leveling, else caster (Wrath, Moonfire, a staff).
function D.Dps(sh, p)
  local total = p.otherDps
  local mcrit = math.max(0, math.min(sh.crit, 100)) / 100
  local miss = math.max(0, 5 - sh.hit) / 100
  local dodge = p.dodge / 100
  local whiteF = math.max(0, 1 - miss - dodge - mcrit) + mcrit * 2
  -- Natural Instinct raises the abilities' crit bonus (yellowCrit = 1 + its %)
  local yellowF = math.max(0, 1 - miss - dodge) * (1 + mcrit * p.yellowCrit)
  if p.cat then
    local paw = D.PawAvg(sh.mh) + sh.ap / 14
    total = total + p.meleeUptime * paw * whiteF
    total = total + p.buildPerSec * (paw + p.buildBonus) * yellowF * p.buildMult
    total = total + p.finishDps
  else
    if sh.mh then
      total = total + p.meleeUptime * ((sh.mh.min + sh.mh.max) / 2 + sh.ap / 14 * sh.mh.speed) / sh.mh.speed * whiteF
    end
    -- at least 1% of the spells miss; Eclipse adds Wrath's crit by Wrath's share of the casts
    local hitF = 1 - math.max(1, p.spellMiss - (sh.spellHit or 0)) / 100
    local scrit = math.max(0, math.min(sh.spellCrit + p.castCritAdd, 100)) / 100
    local sf = hitF * (1 + scrit * (p.critMult - 1))
    total = total + p.castPerSec * (p.castDamage + p.castCoef * sh.sp) * sf * p.castMult
  end
  -- Naturalist: all damage
  return total * p.allMult
end

local function Apply(sh, remove, add, p)
  local dAgi = ((add.agi or 0) - (remove.agi or 0)) * p.statMult
  local dStr = ((add.str or 0) - (remove.str or 0)) * p.statMult * p.strMult
  local dInt = ((add.int or 0) - (remove.int or 0)) * p.statMult * p.intMult
  return {
    ap = sh.ap + (add.ap or 0) - (remove.ap or 0) + 2 * dStr + (p.cat and dAgi or 0),
    crit = sh.crit + (add.crit or 0) - (remove.crit or 0) + dAgi / p.agiPerCrit,
    hit = sh.hit + (add.hit or 0) - (remove.hit or 0),
    sp = sh.sp + (add.sp or 0) - (remove.sp or 0),
    spellCrit = sh.spellCrit + dInt / p.intPerCrit,
    spellHit = sh.spellHit,
    mh = sh.mh,
  }
end

---------------------------------------------------------------------------
-- context
---------------------------------------------------------------------------
function D.Context(input)
  local level = input.level or 1
  local equipped = input.equipped or {}
  local known = input.known or {}
  local tal = input.talents or {}
  local notes = {}
  local function eq(slot) return equipped[slot] and equipped[slot].stats or M.ZERO end

  -- Cat Form: from the spellbook when it was read, else from level 20 (Classic's level for it);
  -- most talent points in Balance (tab 1): the caster model
  local cat
  if known["Cat Form"] ~= nil then cat = known["Cat Form"] == true else cat = level >= 20 end
  local balance = input.tab == 1
  if balance then cat = false end

  local agi = input.agi or 0
  local crit = input.crit or 0
  -- crit in the forms (Sharpened Claws, Leader of the Pack): on the sheet only when read in Cat Form
  local formCrit = (tal.sharpened or 0) + (tal.lotp or 0)
  local agiPerCrit = agi / math.max(0.1, crit - 0.9 - (tal.majesty or 0) - (input.form == "cat" and formCrit or 0))
  if not (agiPerCrit > 0.8 and agiPerCrit < 40) then agiPerCrit = 1 + (19 * (level - 1)) / 59 end
  local intPerCrit = 6 + (54 * (level - 1)) / 59

  -- attack power in Cat Form: read in Cat Form now, else the last value read there, else the
  -- caster's attack power + agility (the Classic rule)
  local ap, apFrom = input.ap or 0, L"now, read in Cat Form"
  if cat and input.form ~= "cat" then
    if input.catAp then ap, apFrom = input.catAp, L"last read in Cat Form"
    else
      -- Predatory Strikes (a % of the level) and Heart of the Wild's strength only count in a form
      ap = (input.ap or 0) + agi + level * (tal.predatory or 0) / 100 + 2 * (input.str or 0) * (tal.hotwStr or 0) / 100
      apFrom = L"estimated: current AP + agility (more precise when read in Cat Form)"
    end
  end
  local mh = eq("MAIN_HAND").weapon
  local sheet = { ap = ap, crit = crit, hit = input.hit or 0, sp = input.sp or 0, spellCrit = input.spellCrit or 0,
    spellHit = input.spellHit or 0, mh = mh }
  if cat and input.form ~= "cat" then sheet.crit = crit + formCrit end
  -- Moonkin Form: the caster casts in it; its crit aura is on the sheet only when read there
  local moonkin = not cat and (tal.moonkinDmg or 0) > 0
  if moonkin and input.form ~= "moonkin" then sheet.spellCrit = sheet.spellCrit + (tal.moonkinCrit or 0) end
  if cat then
    notes[#notes + 1] = (L"Cat Form: the claws hit for your weapon's DPS per second (%s), the weapon's speed does not matter. Attack power %d (%s); 1 strength = 2 AP, 1 agility = 1 AP (the classic rule, not verified for Forever), 1%% crit ≈ %s agility.")
      :format(F1(D.PawAvg(mh)), Round(ap), apFrom, F1(agiPerCrit))
  else
    notes[#notes + 1] = (balance and (L"Balance spec: Wrath, Moonfire and your staff%s. 1%% spell crit ≈ %s intellect.")
      or (L"Before Cat Form: Wrath, Moonfire and your staff%s. 1%% spell crit ≈ %s intellect.")):format(moonkin and (L", in Moonkin Form") or "", F1(intPerCrit))
  end

  -- caster prior: a Wrath-sized cast every 3 s (mana, moving, Moonfire between); the Wrath of
  -- this level (about 14 + 4.4 a level, a Classic-sized estimate) and its share of spell power
  local params = {
    level = level, cat = cat, agiPerCrit = agiPerCrit, intPerCrit = intPerCrit, statMult = 1,
    dodge = 5, spellMiss = 4,
    meleeUptime = cat and 0.85 or (mh and 0.3 or 0),
    -- energy 10 a second, Claw 45: about 0.22 a second; the prior gives finishers a third.
    -- Ferocity makes Claw cheaper (45 - its rank's energy)
    buildPerSec = cat and 1 / 6.5 * 45 / (45 - (tal.ferocity or 0)) or 0,
    buildBonus = cat and math.max(0, (level - 20) * 2.5) or 0,
    finishDps = 0,
    castPerSec = cat and 0 or 1 / 3,
    castDamage = 14 + 4.4 * (level - 1), castCoef = 1.5 / 3.5 * math.max(0.25, 1 - math.max(0, 20 - level) * 0.0375),
    otherDps = 0, notes = notes,
    buildMult = 1 + (tal.savage or 0) / 100, yellowCrit = 1 + (tal.natInst or 0) / 100,
    allMult = 1 + (tal.naturalist or 0) / 100,
    castMult = moonkin and 1 + (tal.moonkinDmg or 0) / 100 or 1,
    critMult = 1.5 + 0.5 * (tal.vengeance or 0) / 100,
    eclipse = tal.eclipse or 0, wrathShare = 1,
    intMult = 1 + (tal.hotwInt or 0) / 100, strMult = cat and 1 + (tal.hotwStr or 0) / 100 or 1,
  }
  params.castCritAdd = params.eclipse * params.wrathShare
  params.finishDps = cat and 0.35 * params.buildPerSec * (D.PawAvg(mh) + ap / 14 + params.buildBonus) or 0

  local combat = input.combat
  local function mix(prior, measured, n, half)
    local w = n / (n + half)
    return prior * (1 - w) + measured * w
  end
  local function landed(a) return (a.hit or 0) + (a.crit or 0) + (a.glance or 0) end
  if combat and combat.seconds > 0 then
    local secs = combat.seconds
    local melee, build, buildDmg, buildLanded, buildCrit, finish, casts, castDmg, castLanded, castCrit, other = nil, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    local wrath = 0
    local all = params.allMult
    for _, a in ipairs(combat.abilities) do
      if a.name == "Wrath" then wrath = a.n end
      local k, base = Kind(a.name), Base(a.name)
      if a.name == "Melee" then melee = a
      elseif k == "cat" and D.CAT_BUILD[base] and not IsDot(a.name) then
        build, buildDmg, buildLanded, buildCrit = build + a.n, buildDmg + a.dmg, buildLanded + landed(a), buildCrit + (a.crit or 0)
      elseif k == "cat" or k == "bleed" then finish = finish + a.dmg
      elseif k == "spell" and not IsDot(a.name) then
        casts, castDmg, castLanded, castCrit = casts + a.n, castDmg + a.dmg, castLanded + landed(a), castCrit + (a.crit or 0)
      else other = other + a.dmg end
    end
    if cat then
      params.meleeUptime = mix(params.meleeUptime, math.min(1, (melee and melee.n or 0) / secs), secs, 120)
      params.buildPerSec = mix(params.buildPerSec, build / secs, secs, 120)
      if buildLanded > 0 then
        -- one builder hit without the talents (Natural Instinct's crit, Savage Fury, Naturalist)
        local per = buildDmg / (buildLanded + buildCrit * params.yellowCrit) / (params.buildMult * all)
        params.buildBonus = mix(params.buildBonus, math.max(0, per - D.PawAvg(mh) - ap / 14), buildLanded, 10)
      end
      params.finishDps = mix(params.finishDps, finish / secs / all, secs, 120)
    else
      if mh then params.meleeUptime = mix(params.meleeUptime, math.min(1, (melee and melee.n or 0) / secs * mh.speed), secs, 120) end
      params.castPerSec = mix(params.castPerSec, casts / secs, secs, 120)
      if casts > 0 then
        params.wrathShare = mix(params.wrathShare, wrath / casts, casts, 10)
        params.castCritAdd = params.eclipse * params.wrathShare
      end
      if castLanded > 0 then
        -- one cast without the talents (Vengeance's crit, Moonkin Form, Naturalist)
        local per = castDmg / (castLanded + (params.critMult - 1) * castCrit) / (params.castMult * all)
        params.castDamage = mix(params.castDamage, math.max(0, per - params.castCoef * sheet.sp), castLanded, 10)
      end
      other = other + finish
    end
    if melee and melee.n > 0 then params.dodge = mix(params.dodge, (melee.dodge or 0) / melee.n * 100, melee.n, 100) end
    params.otherDps = mix(0, other / secs / all, secs, 120)
    if cat then
      notes[#notes + 1] = (L"Calibrated from %d recorded fights (%d s): claws %d%% of the time, %s builders per minute (+%d damage on the claws), finishers and bleeds %s DPS, other %s DPS.")
        :format(combat.fights, Round(secs), Round(params.meleeUptime * 100), F1(params.buildPerSec * 60), Round(params.buildBonus),
          F1(params.finishDps), F1(params.otherDps))
    else
      notes[#notes + 1] = (L"Calibrated from %d recorded fights (%d s): %s spells per minute (%d damage), other %s DPS.")
        :format(combat.fights, Round(secs), F1(params.castPerSec * 60), Round(params.castDamage), F1(params.otherDps))
    end
  else
    notes[#notes + 1] = L"No recorded fights, so it uses textbook values. Turn on the combat log (/wa log) to calibrate."
  end
  notes[#notes + 1] = L"The model does not count mana or shapeshifting: intellect is only worth something for spell crit."

  local unbuffed = D.Dps(sheet, params)
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
  sheet.ap = sheet.ap + 2 * bStr + bAp + (cat and bAgi or 0)
  sheet.crit = sheet.crit + bCrit + bAgi / agiPerCrit
  local baseline = D.Dps(sheet, params)
  local equippedIds = {}
  for _, it in pairs(equipped) do if it.id then equippedIds[it.id] = true end end

  local ctx = M.Common({
    level = level, baseline = baseline, unbuffed = unbuffed, buffs = buffs, params = params, sheet = sheet,
    equipped = equipped, equippedIds = equippedIds, combat = combat, slotOrder = input.slotOrder,
  }, "DRUID")

  -- Best slot for an item and the DPS it adds there; nil when it is not an upgrade. A two-hand
  -- weapon replaces both hands.
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
      if slot == "MAIN_HAND" then sh.mh = add.weapon end
      if slot ~= "OFF_HAND" or not add.weapon then
        local gain = D.Dps(sh, params) - baseline
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
      bits[#bits + 1] = ("%s %s–%s / %s (%s DPS)"):format(M.WEAPON_NAMES[weaponSub or -1] or "Weapon", w.min, w.max, F1(w.speed), F1(D.PawAvg(w)))
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
    return D.Dps(sh, params) - baseline
  end

  local skills = input.skills
  function ctx.weaponWarning(itemClass, sub)
    if itemClass ~= 2 or not skills or not next(skills) then return nil end
    local line = M.WEAPON_SKILLS[sub]
    local s = line and skills[line]
    if not s then return (L"%s is not trained (weapon master)"):format(tostring(line)) end
    -- in Cat Form the weapon skill does not count (feral combat skill instead)
    if not cat and s.rank < s.max - 15 then return ("%s skill %d/%d"):format(line, s.rank, s.max) end
    return nil
  end

  ctx.advice = {}
  return ctx
end

---------------------------------------------------------------------------
-- the combat page: score, breakdown and advice for druids
---------------------------------------------------------------------------
local function Find(list, name)
  for _, a in ipairs(list or {}) do if a.name == name then return a end end
  return nil
end

-- Where the damage came from: melee, cat, bleed, bear, spell, other (each { dmg, share }).
function D.Sources(abilities, total)
  local out = { melee = 0, cat = 0, bleed = 0, bear = 0, spell = 0, other = 0 }
  for _, a in ipairs(abilities or {}) do
    local k = Kind(a.name)
    out[k] = out[k] + (a.dmg or 0)
  end
  local sum = total and total > 0 and total or (out.melee + out.cat + out.bleed + out.bear + out.spell + out.other)
  local shares = {}
  for k, v in pairs(out) do shares[k] = sum > 0 and v / sum * 100 or 0 end
  return out, shares
end

-- A fight in Cat Form: any cat ability among the hits or the casts.
function D.CatFight(f)
  for _, a in ipairs(f.ab or {}) do if Kind(a.name) == "cat" or Kind(a.name) == "bleed" then return true end end
  for _, c in ipairs(f.casts or {}) do if D.CAT_BUILD[c[2]] or D.CAT_FINISH[c[2]] then return true end end
  return false
end

-- Bleed uptime from its ticks: ticks x the tick interval / the time (0-100), nil without ticks.
function D.BleedUptime(abilities, name, seconds)
  local a = Find(abilities, name .. " (dot)")
  if not a or not seconds or seconds <= 0 then return nil end
  return math.min(100, a.n * D.BLEED_TICK[name] / seconds * 100)
end

-- finisher casts and their average combo points: { [name] = { casts, cp } }
local function Finishers(casts)
  local out = {}
  for _, c in ipairs(casts or {}) do
    if D.CAT_FINISH[c[2]] then
      local e = out[c[2]] or { casts = 0, cp = 0 }
      out[c[2]] = e
      e.casts, e.cp = e.casts + 1, e.cp + (tonumber(c[4]) or 0)
    end
  end
  return out
end

-- Score of one fight, 0-100, from what a druid controls; parts: { key, label, points, max, text }.
local GRADES = { { 90, "S" }, { 80, "A" }, { 65, "B" }, { 50, "C" }, { 0, "D" } }
function D.Score(f, ctx)
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
  if D.CatFight(f) then
    local melee = Find(ab, "Melee")
    if dur >= 6 then
      -- the paw swings once a second (sim/druid/forms.go GetCatWeapon)
      local up = math.min(1, (melee and melee.n or 0) / dur)
      Part("melee", L"You swing continuously", math.min(up / 0.85, 1) * 20, 20, (L"%d swings, %d%% of the possible (one a second in Cat Form)"):format(melee and melee.n or 0, Round(up * 100)))
    end
    if (f.samples or 0) > 0 then
      local pct = (f.capped or 0) / f.samples * 100
      Part("energy", L"No wasted energy", (1 - math.min(pct / 20, 1)) * 15, 15, (L"your energy was full %s%% of the time"):format(F1(pct)))
    end
    local fin, cps = 0, 0
    for _, e in pairs(Finishers(f.casts)) do fin, cps = fin + e.casts, cps + e.cp end
    if fin > 0 then
      local avg = cps / fin
      Part("finisher", L"Finishers with enough combo points", math.max(0, math.min((avg - 2) / 3, 1)) * 15, 15,
        (L"%d finishers (Rip, Ferocious Bite), average %s combo points"):format(fin, F1(avg)))
    end
    if dur >= 15 then
      local up = D.BleedUptime(ab, "Rake", dur) or 0
      Part("rake", L"Rake in longer fights", math.min(up / 60, 1) * 10, 10, (L"Rake was bleeding about %d%% of the fight (from the ticks: one every 3 s)"):format(Round(up)))
    end
  else
    local casts = 0
    for _, a in ipairs(ab) do if D.SPELLS[a.name] then casts = casts + a.n end end
    if dur >= 6 then
      local perMin = casts / dur * 60
      Part("spell", L"Spells in the fight", math.min(perMin / 15, 1) * 30, 30, (L"%s spells per minute (good: over 15, Wrath 1.5 s)"):format(F1(perMin)))
    end
  end
  local got, max = 0, 0
  for _, p in ipairs(parts) do got, max = got + p.points, max + p.max end
  if max == 0 then return nil end
  local total = math.floor(got / max * 100 + 0.5)
  local grade = "D"
  for _, g in ipairs(GRADES) do if total >= g[1] then grade = g[2] break end end
  return { total = total, grade = grade, parts = parts, dps = dps }
end

-- The raid-log style summary of many fights (r = WA.Combat.Report).
function D.Summary(r, ctx)
  if not r then return nil end
  local src, share = D.Sources(r.abilities, r.damage)
  local secs = r.seconds
  local melee = Find(r.abilities, "Melee")
  local s = {
    sources = src, shares = share, seconds = secs, dps = r.dps,
    rake = D.BleedUptime(r.abilities, "Rake", secs), rip = D.BleedUptime(r.abilities, "Rip", secs),
    meleeMiss = melee and melee.n > 0 and ((melee.miss or 0) + (melee.dodge or 0) + (melee.parry or 0)) / melee.n * 100 or nil,
    meleeCrit = melee and (melee.hit + melee.crit) > 0 and melee.crit / (melee.hit + melee.crit) * 100 or nil,
    energyCapped = r.energyCappedPct, rows = {},
  }
  for _, f in ipairs(r.finishers or {}) do
    if D.CAT_FINISH[f.name] then s[f.name == "Rip" and "ripCp" or "biteCp"] = f.avgCp end
  end
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

-- Advice from all the recorded fights (instead of the rogue's).
function D.Advise(r, fights)
  local C = WA.Combat
  local out = {}
  local function Push(o) out[#out + 1] = C.Finding(o) end
  local melee = Find(r.abilities, "Melee")
  local level = fights[1] and fights[1].level or 0
  if r.seconds < 300 then
    Push({ info = true, title = L"Not enough data yet", fact = (L"So far %d fights and %d seconds are recorded. The ratios are reliable after about 10 minutes of combat.")
      :format(r.fights, Round(r.seconds)) })
  end
  local _, share = D.Sources(r.abilities, r.damage)
  local catDmg = share.cat + share.bleed
  if r.energyCappedPct and r.energyCappedPct > 8 then
    Push({ title = L"Your energy is often full", fault = true, rule = "energyCap",
      fact = (L"In Cat Form you sat at full energy for %s%% of combat time (the combat log's energy values)."):format(F1(r.energyCappedPct)),
      advice = L"If you could have attacked meanwhile: at 100 energy a 5-point Ferocious Bite turns the extra energy into damage too.",
      missing = L"whether you had a usable ability at that moment (range, stun, a fleeing or unreachable target)" })
  end
  -- Ferocious Bite on 1-2 points: the same proof as the rogue's Eviscerate (Combat.lua EvisMistake)
  local ev = r.finisherEvidence and r.finisherEvidence["Ferocious Bite"] or { seen = 0, proven = {}, justified = 0, unchecked = 0 }
  local bite
  for _, f in ipairs(r.finishers or {}) do if f.name == "Ferocious Bite" then bite = f end end
  if #ev.proven > 0 then
    local lines = {}
    for i = 1, math.min(3, #ev.proven) do
      local p, e = ev.proven[i], ev.proven[i].e
      lines[i] = (L"%s, %s: %d points, its health before %d / %s, the damage %d%s, it lived %s%s s more"):format(
        Clock(p.start, e.t), e.target or "?", e.cp, e.hpBefore, e.maxHp and tostring(e.maxHp) or "?", e.dmg, e.crit and (L" (crit)") or "",
        e.livedKnown and "" or (L"at least "), F1(e.lived))
    end
    Push({ title = L"Low-combo-point Ferocious Bite", fault = true, rule = "biteCp",
      fact = (L"%d Ferocious Bites went out with 1–2 combo points while the target did not die from them, had more than four times the hit's normal damage left in health (even the biggest roll with a crit would not have killed it), and lived at least %d s more (combat log):\n- %s%s%s")
        :format(#ev.proven, C.EVIS_ROOM, table.concat(lines, "\n- "), #ev.proven > 3 and (L"\n- … plus " .. (#ev.proven - 3)) or "",
          ev.unchecked > 0 and (L"\nAnother " .. ev.unchecked .. L" low-point ones: the target's health does not show.") or ""),
      advice = L"In that case build 1–2 more points with Claw: Bite costs the same 35 energy, and its damage grows with every point." })
  elseif bite and bite.casts >= 5 and bite.avgCp < 4 and ev.unchecked == 0 and ev.justified > 0 then
    Push({ title = L"Low-point Ferocious Bite, but justified", rule = "biteCp",
      fact = (L"Your Ferocious Bites went out with %s combo points on average. All %d of the 1–2 point ones could be checked in the combat log, and none was a mistake: they killed, went on a low-health target, or the target died soon.")
        :format(F1(bite.avgCp), ev.justified) })
  elseif bite and bite.casts >= 5 and bite.avgCp < 4 then
    Push({ title = L"Low-combo-point Ferocious Bite", fault = true, rule = "biteCp",
      fact = (L"Your Ferocious Bites went out with %s combo points on average (%d uses)."):format(F1(bite.avgCp), bite.casts) ..
        (ev.justified > 0 and (L" Of the 1–2 point ones, %d were justified by the combat log, %d cannot be checked."):format(ev.justified, ev.unchecked) or ""),
      advice = L"With 4–5 points you get more damage per energy, unless the mob dies with 1–2 points too.",
      missing = L"the target's health at the moment of the cast (whether it would have died with fewer points)" .. (ev.unchecked > 0 and (", " .. ev.unchecked .. L" low-point Bites") or "") })
  end
  -- Rake: an observation only (whether the fight was long enough to be worth a bleed is not known)
  local rake = D.BleedUptime(r.abilities, "Rake", r.seconds)
  local avgFight = r.fights > 0 and r.seconds / r.fights or 0
  if catDmg > 20 and avgFight >= 15 and r.seconds >= 300 and (rake or 0) < 25 then
    Push({ title = L"Rake rarely bleeds", fault = true, rule = "rakeBleed",
      fact = (L"Rake was bleeding about %d%% of combat time (counted from the ticks); your average fight is %d s."):format(Round(rake or 0), Round(avgFight)),
      advice = L"In fights longer than 15 s Rake gives 9 s of bleeding on top of a combo point.",
      missing = L"whether you had learned Rake, and the fight's expected length at the moment of the decision" })
  end
  if level >= 20 and r.seconds >= 300 and share.spell > 50 and catDmg < 25 then
    Push({ title = L"Most of your damage is spells", rule = "druidCat",
      fact = (L"%d%% of your damage is spells, %d%% Cat Form abilities and bleeds."):format(Round(share.spell), Round(catDmg)),
      advice = L"When leveling Feral, Cat Form is faster and needs no mana; as Balance this is fine." })
  end
  if melee and melee.n >= 50 then
    local miss = ((melee.miss or 0) + (melee.dodge or 0) + (melee.parry or 0)) / melee.n * 100
    if miss > 12 then
      Push({ title = L"Many swings miss", rule = "hitGear",
        fact = (L"%s%% of your swings are a miss, dodge or parry."):format(F1(miss)),
        advice = L"+hit items help; parries only come from the front." })
    end
  end
  if melee and melee.n >= 100 then
    local landed = melee.hit + melee.crit
    Push({ info = true, title = L"Measured ratios", fact = (L"Melee: %s%% miss, %s%% dodge, %s%% crit. Damage: claws %d%%, Cat Form abilities %d%%, bleeds %d%%, bear %d%%, spells %d%%.")
      :format(F1((melee.miss or 0) / melee.n * 100), F1((melee.dodge or 0) / melee.n * 100), F1(landed > 0 and melee.crit / landed * 100 or 0),
        Round(share.melee), Round(share.cat), Round(share.bleed), Round(share.bear), Round(share.spell)) })
  end
  return out
end
