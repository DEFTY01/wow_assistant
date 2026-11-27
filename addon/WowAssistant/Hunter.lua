-- Waystone: the hunter damage model, levels 1-60. Pure like Model.lua: the same context shape
-- (score, describe, buffGain, weaponWarning, ...) so the plan, the gear report and the pages
-- work for hunters unchanged.
--
-- Classic rules the model follows:
--   * ranged attack power = 2 × agility (+ level × 2); melee attack power = agility + strength;
--     "+attack power" on gear counts for both, "+ranged attack power" for ranged only
--   * Auto Shot: weapon damage + ammo DPS × speed + RAP / 14 × speed, every speed / haste
--     seconds (a quiver or ammo pouch is the haste)
--   * Multi-Shot and Aimed Shot add a fixed bonus to a weapon shot; Arcane Shot is fixed damage;
--     Serpent Sting and the pet do not grow with your gear
--   * a ranged crit does double damage, Mortal Shots raises the bonus
--   * until level 10 there is no pet and a hunter melees a good part of the time (Raptor Strike)
--
-- Extra input besides Model.lua's: rap, rangedCrit, ammoDps, ammoKind ("arrow" / "bullet"),
-- haste (≥ 1), known = { [spell name] = true }, hasPet, int, talents = Talent.lua's T.Effects (the
-- numbers of the rank's Wowhead Forever text): lethal (crit %, on the sheet), mortal (ranged crit
-- bonus %), reflexes (agility %), focusedFire / loneWolf (all damage % with / without a pet),
-- unleashedFury (pet %), impStings (Serpent Sting %), savageStrikes (melee ability crit %),
-- predatorCrit / predatorOh (melee ability crit damage %, off-hand %), carefulAim (intellect % as
-- attack power), barrage (Multi-Shot and Aimed Shot %), rangedSpec (ranged weapon %).

local _, WA = ...
WA = WA or {}
local M = WA.Model
local H = {}
WA.Hunter = H

local function F1(n) return ("%.1f"):format(n) end
local Round = M.Round

-- { level learned, value } per rank; the value at a level is the highest rank learned by then.
local RANKS = {
  arcane = { { 6, 13 }, { 12, 21 }, { 20, 33 }, { 28, 59 }, { 36, 83 }, { 44, 115 }, { 52, 145 }, { 60, 183 } },
  multi = { { 18, 0 }, { 30, 40 }, { 42, 80 }, { 54, 120 }, { 60, 150 } },
  aimed = { { 20, 70 }, { 28, 125 }, { 36, 200 }, { 44, 330 }, { 52, 460 }, { 60, 600 } },
  raptor = { { 1, 5 }, { 8, 11 }, { 16, 21 }, { 24, 34 }, { 32, 50 }, { 40, 80 }, { 48, 110 }, { 56, 140 } },
  serpent = { { 4, 20 }, { 10, 40 }, { 18, 80 }, { 26, 140 }, { 34, 210 }, { 42, 290 }, { 50, 385 }, { 58, 490 } },
}
local function Rank(name, level)
  local v
  for _, r in ipairs(RANKS[name]) do if r[1] <= level then v = r[2] end end
  return v
end
H.Rank = Rank

-- Abilities of the hunter's pet as the damage meter names them.
H.PET = { Claw = true, Bite = true, ["Pet Melee"] = true, ["Pet Attack"] = true, ["Lightning Breath"] = true,
  ["Fire Breath"] = true, ["Scorpid Poison"] = true, Screech = true, Thunderstomp = true, Charge = true,
  ["Furious Howl"] = true, Dive = true }
local SHOTS = { ["Auto Shot"] = true, ["Arcane Shot"] = true, ["Multi-Shot"] = true, ["Aimed Shot"] = true,
  ["Raptor Strike"] = true, Melee = true, ["Serpent Sting"] = true, ["Serpent Sting (dot)"] = true }
H.AMMO_SUBS = { [2] = "arrow", [18] = "arrow", [3] = "bullet" } -- bow, crossbow: arrows; gun: bullets

---------------------------------------------------------------------------
-- the model
---------------------------------------------------------------------------
function H.Shot(sh, w)
  if not w then return 0 end
  local ammo = (w.ammo ~= false) and (sh.ammo or 0) or 0
  return (w.min + w.max) / 2 + ammo * w.speed + (sh.rap / 14) * w.speed
end

-- Sustained DPS of one target, leveling style.
function H.Dps(sh, p)
  local total = p.petDps + p.stingDps + p.otherDps
  local crit = math.min(sh.crit, 100) / 100
  local landR = math.max(0, 1 - math.max(0, p.rangedMissBase - sh.hit) / 100 - p.rangedDodge / 100)
  local rf = landR * (1 + crit * (p.critMult - 1))
  -- talents: all damage (Focused Fire with a pet, Lone Wolf without), the ranged weapon's shots
  -- (Ranged Weapon Specialization), Multi-Shot and Aimed Shot (Barrage)
  local m = p.allMult or 1
  local rw = m * (p.rangedMult or 1)
  if sh.ranged then
    local shot = H.Shot(sh, sh.ranged)
    total = total + p.rangedUptime * (sh.haste / sh.ranged.speed) * shot * rf * rw
    total = total + p.multiPerSec * (shot + p.multiBonus) * rf * rw * (p.barrageMult or 1)
    total = total + p.aimedPerSec * (shot + p.aimedBonus) * rf * rw * (p.barrageMult or 1)
    total = total + p.arcanePerSec * p.arcaneDamage * rf * m
  end
  if sh.mh then
    local mcrit = math.min(sh.mcrit, 100) / 100
    local whiteMiss = math.max(0, (sh.oh and 24 or 5) - sh.hit) / 100
    local yellowMiss = math.max(0, 5 - sh.hit) / 100
    local dodge = p.meleeDodge / 100
    local whiteF = math.max(0, 1 - whiteMiss - dodge - mcrit) + mcrit * 2
    -- Raptor Strike: Savage Strikes adds crit, Predator's Edge raises its crit bonus (100%)
    local rcrit = math.min(sh.mcrit + (p.savageStrikes or 0), 100) / 100
    local yellowF = math.max(0, 1 - yellowMiss - dodge) * (1 + rcrit * (1 + (p.predatorCrit or 0) / 100))
    local function avg(w) return (w.min + w.max) / 2 + (sh.ap / 14) * w.speed end
    local white = avg(sh.mh) / sh.mh.speed
    if sh.oh then white = white + avg(sh.oh) * 0.5 * (1 + (p.predatorOh or 0) / 100) / sh.oh.speed end
    total = total + (p.meleeUptime * white * whiteF + p.raptorPerSec * (avg(sh.mh) + p.raptorBonus) * yellowF) * m
  end
  return total
end

local function Apply(sh, remove, add, p)
  local dAgi = ((add.agi or 0) - (remove.agi or 0)) * p.agiMult
  local dStr = ((add.str or 0) - (remove.str or 0)) * p.statMult
  local dAp = (add.ap or 0) - (remove.ap or 0)
  local dCrit = (add.crit or 0) - (remove.crit or 0) + dAgi / p.agiPerCrit
  -- Careful Aim: a part of the intellect as attack power
  local dIntAp = ((add.int or 0) - (remove.int or 0)) * p.statMult * (p.carefulAim or 0) / 100
  return {
    ap = sh.ap + dAp + dAgi + dStr + dIntAp,
    rap = sh.rap + dAp + ((add.rap or 0) - (remove.rap or 0)) + 2 * dAgi + dIntAp,
    crit = sh.crit + dCrit, mcrit = sh.mcrit + dCrit,
    hit = sh.hit + (add.hit or 0) - (remove.hit or 0),
    ranged = sh.ranged, mh = sh.mh, oh = sh.oh, ammo = sh.ammo, haste = sh.haste,
  }
end

---------------------------------------------------------------------------
-- context
---------------------------------------------------------------------------
function H.Context(input)
  local level = input.level or 1
  local equipped = input.equipped or {}
  local tal = input.talents or {}
  local known = input.known or {}
  local notes = {}
  local function eq(slot) return equipped[slot] and equipped[slot].stats or M.ZERO end

  local agi = input.agi or 0
  local crit = input.rangedCrit or input.crit or 0
  local agiPerCrit = agi / math.max(0.1, crit - (tal.lethal or 0))
  if not (agiPerCrit > 3 and agiPerCrit < 70) then agiPerCrit = 3.5 + (49.5 * (level - 1)) / 59 end
  notes[#notes + 1] = ("1%% crit ≈ %s agility, 1 agility = 2 ranged AP + 1 melee AP (worked back from your own stats)."):format(F1(agiPerCrit))

  local ranged = equipped.RANGED and equipped.RANGED.stats.weapon or nil
  local rangedSub = equipped.RANGED and equipped.RANGED.sub
  if ranged then
    ranged = { min = ranged.min, max = ranged.max, speed = ranged.speed, ammo = rangedSub ~= 16 }
  end
  local sheet = {
    ap = input.ap or 0, rap = input.rap or 0, crit = crit, mcrit = input.crit or crit, hit = input.hit or 0,
    ranged = ranged, mh = eq("MAIN_HAND").weapon, oh = eq("OFF_HAND").weapon,
    ammo = input.ammoDps or 0, haste = math.max(1, math.min(1.5, input.haste or 1)),
  }

  local early = level < 10 or input.hasPet == false
  local params = {
    level = level, agiPerCrit = agiPerCrit, statMult = 1, agiMult = 1 + (tal.reflexes or 0) / 100,
    critMult = 2 + (tal.mortal or 0) / 100,
    rangedMissBase = 5, rangedDodge = 5, meleeDodge = 5,
    rangedUptime = ranged and (level < 10 and 0.6 or 0.85) or 0,
    meleeUptime = sheet.mh and (level < 10 and 0.35 or 0.08) or 0,
    arcanePerSec = (known["Arcane Shot"] ~= false and level >= 6) and 1 / 9 or 0, arcaneDamage = Rank("arcane", level) or 0,
    multiPerSec = (known["Multi-Shot"] ~= false and level >= 18) and 1 / 12 or 0, multiBonus = Rank("multi", level) or 0,
    aimedPerSec = known["Aimed Shot"] and 1 / 20 or 0, aimedBonus = Rank("aimed", level) or 0,
    raptorBonus = Rank("raptor", level) or 0,
    petDps = early and 0 or 0.7 * level * (1 + ((tal.unleashedFury or 0) + (tal.focusedFire or 0)) / 100),
    stingDps = level >= 4 and (Rank("serpent", level) or 0) / 15 * 0.5 * (1 + (tal.impStings or 0) / 100) or 0,
    allMult = 1 + (early and (tal.loneWolf or 0) or (tal.focusedFire or 0)) / 100,
    rangedMult = 1 + (tal.rangedSpec or 0) / 100, barrageMult = 1 + (tal.barrage or 0) / 100,
    savageStrikes = tal.savageStrikes or 0, predatorCrit = tal.predatorCrit or 0, predatorOh = tal.predatorOh or 0,
    carefulAim = tal.carefulAim or 0,
    otherDps = 0, notes = notes,
  }
  params.raptorPerSec = params.meleeUptime / 6

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
    local auto, melee = ab["Auto Shot"], ab.Melee
    if auto and auto.n > 0 then
      params.rangedMissBase = mix(params.rangedMissBase, auto.miss / auto.n * 100 + sheet.hit, auto.n, 100)
      params.rangedDodge = mix(params.rangedDodge, (auto.dodge or 0) / auto.n * 100, auto.n, 100)
      if ranged then
        params.rangedUptime = mix(params.rangedUptime, math.min(1, auto.n / secs * ranged.speed / sheet.haste), secs, 120)
      end
    elseif ranged then
      params.rangedUptime = mix(params.rangedUptime, 0, secs, 120)
    end
    if sheet.mh then
      local expected = 1 / sheet.mh.speed + (sheet.oh and 1 / sheet.oh.speed or 0)
      params.meleeUptime = mix(params.meleeUptime, math.min(1, (melee and melee.n or 0) / secs / expected), secs, 120)
      if melee and melee.n > 0 then params.meleeDodge = mix(params.meleeDodge, (melee.dodge or 0) / melee.n * 100, melee.n, 100) end
    end
    local function rate(name, key, half)
      local a = ab[name]
      params[key] = mix(params[key], (a and a.n or 0) / secs, secs, half or 120)
      return a
    end
    local arc = rate("Arcane Shot", "arcanePerSec")
    -- the logged damage has the damage talents in it
    if arc and landed(arc) > 0 then
      params.arcaneDamage = mix(params.arcaneDamage, arc.dmg / (arc.hit + params.critMult * arc.crit) / params.allMult, landed(arc), 10)
    end
    local shot = H.Shot(sheet, ranged)
    local shotMult = params.allMult * params.rangedMult * params.barrageMult
    local multi = rate("Multi-Shot", "multiPerSec")
    if multi and ranged and landed(multi) > 0 then
      params.multiBonus = mix(params.multiBonus, math.max(0, multi.dmg / (multi.hit + params.critMult * multi.crit) / shotMult - shot), landed(multi), 10)
    end
    local aimed = rate("Aimed Shot", "aimedPerSec")
    if aimed and ranged and landed(aimed) > 0 then
      params.aimedBonus = mix(params.aimedBonus, math.max(0, aimed.dmg / (aimed.hit + params.critMult * aimed.crit) / shotMult - shot), landed(aimed), 10)
    end
    rate("Raptor Strike", "raptorPerSec")
    local sting, pet, other = 0, 0, 0
    for _, a in ipairs(combat.abilities) do
      local base = a.name:gsub(" %(dot%)$", "")
      if base == "Serpent Sting" then sting = sting + a.dmg
      elseif H.PET[base] or base:sub(1, 5) == "Pet: " then pet = pet + a.dmg
      elseif not SHOTS[a.name] then other = other + a.dmg end
    end
    params.stingDps = mix(params.stingDps, sting / secs, secs, 120)
    if pet > 0 then params.petDps = mix(params.petDps, pet / secs, secs, 120) end
    params.otherDps = mix(0, other / secs, secs, 120)
    notes[#notes + 1] = ("Calibrated from %d recorded fights (%d s). Auto Shot: %s%% base miss, %s%% dodge, you shoot %d%% of the time; melee %d%% of the time.")
      :format(combat.fights, Round(secs), F1(params.rangedMissBase), F1(params.rangedDodge),
        Round(params.rangedUptime * 100), Round(params.meleeUptime * 100))
    notes[#notes + 1] = ("Per minute: Arcane Shot %s (%d damage), Multi-Shot %s (+%d), Aimed Shot %s (+%d), Raptor Strike %s. Pet %s DPS, Serpent Sting %s DPS, other %s DPS.")
      :format(F1(params.arcanePerSec * 60), Round(params.arcaneDamage), F1(params.multiPerSec * 60), Round(params.multiBonus),
        F1(params.aimedPerSec * 60), Round(params.aimedBonus), F1(params.raptorPerSec * 60), F1(params.petDps), F1(params.stingDps),
        F1(params.otherDps))
  else
    notes[#notes + 1] = ("No recorded fights, so it uses textbook values: Auto Shot %d%% of the time, %s Arcane Shots and %s Multi-Shots a minute, %s. Turn on the combat log (/wa log) to calibrate.")
      :format(Round(params.rangedUptime * 100), F1(params.arcanePerSec * 60), F1(params.multiPerSec * 60),
        early and "without a pet, with a lot of melee (Raptor Strike)" or ("pet about " .. Round(params.petDps) .. " DPS"))
  end
  if not ranged then notes[#notes + 1] = "You have no ranged weapon: a bow, gun or crossbow is the biggest upgrade." end
  if ranged and ranged.ammo and (input.ammoDps or 0) <= 0 then
    notes[#notes + 1] = "No ammo in the ammo slot: Auto Shot does not fire without ammo. Buy arrows or bullets at a vendor."
  end
  if sheet.haste > 1.001 then notes[#notes + 1] = ("The quiver or ammo pouch speeds up your shots by %d%%."):format(Round((sheet.haste - 1) * 100)) end

  local unbuffed = H.Dps(sheet, params)
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
    params.agiMult = params.agiMult * (1 + pct)
  end
  sheet.ap = sheet.ap + bAgi + bStr + bAp
  sheet.rap = sheet.rap + 2 * bAgi + bAp
  sheet.crit = sheet.crit + bCrit + bAgi / agiPerCrit
  sheet.mcrit = sheet.mcrit + bCrit + bAgi / agiPerCrit
  local baseline = H.Dps(sheet, params)
  local equippedIds = {}
  for _, it in pairs(equipped) do if it.id then equippedIds[it.id] = true end end

  local ctx = M.Common({
    level = level, baseline = baseline, unbuffed = unbuffed, buffs = buffs, params = params, sheet = sheet,
    equipped = equipped, equippedIds = equippedIds, combat = combat, slotOrder = input.slotOrder,
  }, "HUNTER")

  -- Best slot for an item and the DPS it adds there; nil when it is not an upgrade. A two-hand
  -- weapon replaces both hands; a ranged weapon brings its own ammo rule (thrown takes none).
  function ctx.score(add, slots, twoHand, sub)
    local best
    for _, slot in ipairs(slots) do
      local remove = eq(slot)
      if twoHand then
        local oh = eq("OFF_HAND")
        remove = { agi = remove.agi + oh.agi, str = remove.str + oh.str, ap = remove.ap + oh.ap, crit = remove.crit + oh.crit,
          hit = remove.hit + oh.hit, rap = (remove.rap or 0) + (oh.rap or 0) }
      end
      local sh = Apply(sheet, remove, add, params)
      if slot == "MAIN_HAND" then sh.mh = add.weapon if twoHand then sh.oh = nil end end
      if slot == "OFF_HAND" then sh.oh = add.weapon end
      if slot == "RANGED" and add.weapon then
        sh.ranged = { min = add.weapon.min, max = add.weapon.max, speed = add.weapon.speed, ammo = sub ~= 16 }
      end
      local gain = H.Dps(sh, params) - baseline
      if not best or gain > best.gain then best = { slot = slot, gain = gain } end
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
    if add.agi ~= 0 then bits[#bits + 1] = ("+%s agi"):format(add.agi) end
    if add.str ~= 0 then bits[#bits + 1] = ("+%s str"):format(add.str) end
    if add.ap ~= 0 then bits[#bits + 1] = ("+%s AP"):format(add.ap) end
    if (add.rap or 0) ~= 0 then bits[#bits + 1] = ("+%s ranged AP"):format(add.rap) end
    if add.crit ~= 0 then bits[#bits + 1] = ("+%s%% crit"):format(add.crit) end
    if add.hit ~= 0 then bits[#bits + 1] = ("+%s%% hit"):format(add.hit) end
    local kind = weaponSub and H.AMMO_SUBS[weaponSub]
    if kind and ctx.ammoKind and kind ~= ctx.ammoKind then
      bits[#bits + 1] = kind == "bullet" and "needs bullets, not arrows" or "needs arrows, not bullets"
    end
    return table.concat(bits, ", ")
  end

  function ctx.buffGain(e)
    local add = { agi = e.agi or 0, str = e.str or 0, ap = e.ap or 0, crit = e.crit or 0, hit = 0, rap = 0, int = e.int or 0 }
    return H.Dps(Apply(sheet, M.ZERO, add, params), params) - baseline
  end

  -- DPS from ammo of this many damage per second instead of what is in the ammo slot.
  function ctx.ammoGain(dps)
    if not sheet.ranged or not sheet.ranged.ammo then return 0 end
    local sh = Apply(sheet, M.ZERO, M.ZERO, params)
    sh.ammo = dps
    return H.Dps(sh, params) - baseline
  end
  ctx.ammoKind = input.ammoKind or (rangedSub and H.AMMO_SUBS[rangedSub]) or nil
  -- ammo used per second of combat: every Auto Shot and every special shot takes one
  ctx.shotsPerSec = (ranged and ranged.ammo) and (params.rangedUptime * sheet.haste / ranged.speed
    + params.arcanePerSec + params.multiPerSec + params.aimedPerSec) or 0

  local skills = input.skills
  function ctx.weaponWarning(itemClass, sub)
    if itemClass ~= 2 or not skills or not next(skills) then return nil end
    local line = M.WEAPON_SKILLS[sub]
    local s = line and skills[line]
    if not s then return ("%s is not trained (weapon master)"):format(tostring(line)) end
    if s.rank < s.max - 15 then return ("%s skill %d/%d"):format(line, s.rank, s.max) end
    return nil
  end

  -- Hunter advice from the model's own numbers (the combat page's advice is the rogue's).
  local advice = {}
  local function Push(o) advice[#advice + 1] = WA.Combat.Finding(o) end
  if combat and combat.seconds >= 120 then
    if ranged and params.rangedUptime < 0.6 and level >= 10 then
      Push({ title = "Little Auto Shot", fault = true, rule = "hunterRange",
        fact = ("In your fights you were shooting about %d%% of the time."):format(Round(params.rangedUptime * 100)),
        advice = "If the pet could hold the mob, shoot from range: most of a hunter's damage is Auto Shot.",
        missing = "range and movement during the fight" })
    end
    if level >= 10 and params.meleeUptime > 0.3 then
      Push({ title = "You were in melee a lot", fault = true, rule = "hunterRange",
        fact = ("You were in melee about %d%% of the time."):format(Round(params.meleeUptime * 100)),
        advice = "From level 10 the pet tanks: stay outside 8 yards, and Wing Clip + step back if the mob comes at you.",
        missing = "why the mob was on you (the pet's aggro does not show)" })
    end
    if level >= 10 and params.petDps < 0.2 * level then
      Push({ title = "Weak or missing pet", fault = true, rule = "hunterPet",
        fact = ("The pet gave about %s DPS."):format(F1(params.petDps)),
        advice = "Tame a beast that fits your level, feed it, and teach it the newest rank of Claw/Bite.",
        missing = "whether the pet was out and attacking" })
    end
  end
  ctx.advice = advice
  return ctx
end

---------------------------------------------------------------------------
-- the combat page: score, breakdown and advice for hunters
---------------------------------------------------------------------------
local RANGED = { ["Auto Shot"] = true, ["Arcane Shot"] = true, ["Multi-Shot"] = true, ["Aimed Shot"] = true,
  ["Scatter Shot"] = true, ["Volley"] = true }
local MELEE = { Melee = true, ["Raptor Strike"] = true, ["Wing Clip"] = true, ["Mongoose Bite"] = true, ["Counterattack"] = true }
local SPECIALS = { "Arcane Shot", "Multi-Shot", "Aimed Shot" }

local function IsPet(name)
  local base = name:gsub(" %(dot%)$", "")
  return base:sub(1, 5) == "Pet: " or H.PET[base] == true
end
H.IsPet = IsPet

-- Where the damage came from: ranged, melee, pet, dot, other (each { dmg, share }).
function H.Sources(abilities, total)
  local out = { ranged = 0, melee = 0, pet = 0, dot = 0, other = 0 }
  for _, a in ipairs(abilities or {}) do
    local name, dmg = a.name or "", a.dmg or 0
    if IsPet(name) then out.pet = out.pet + dmg
    elseif name:sub(-6) == " (dot)" then out.dot = out.dot + dmg
    elseif RANGED[name] then out.ranged = out.ranged + dmg
    elseif MELEE[name] then out.melee = out.melee + dmg
    else out.other = out.other + dmg end
  end
  local sum = total and total > 0 and total or (out.ranged + out.melee + out.pet + out.dot + out.other)
  local shares = {}
  for k, v in pairs(out) do shares[k] = sum > 0 and v / sum * 100 or 0 end
  return out, shares
end

local function Find(list, name)
  for _, a in ipairs(list or {}) do if a.name == name then return a end end
  return nil
end

-- Auto Shot activity: shots fired against what the weapon could fire in that time (0-1).
function H.AutoUptime(shots, seconds, ranged, haste)
  if not ranged or not seconds or seconds <= 0 then return nil end
  local possible = seconds * (haste or 1) / ranged.speed
  return possible > 0 and math.min(1, shots / possible) or nil
end

-- Score of one fight, 0-100, from what a hunter controls. ctx is the hunter model (for the
-- expected DPS and the weapon speed); parts: { key, label, points, max, text }.
local GRADES = { { 90, "S" }, { 80, "A" }, { 65, "B" }, { 50, "C" }, { 0, "D" } }
function H.Score(f, ctx)
  local parts = {}
  local function Part(key, label, got, max, text) parts[#parts + 1] = { key = key, label = label, points = got, max = max, text = text } end
  local dur = f.dur or 0
  local dps = dur > 0 and (f.dmg or 0) / dur or 0
  local level = f.level or (ctx and ctx.level) or 0
  -- only against the model of the same level and gear (Combat.Comparable)
  local baseline = ctx and WA.Combat.Comparable(f, ctx) and ctx.baseline or nil
  if baseline and baseline > 0 then
    local ratio = dps / baseline
    Part("dps", "DPS against the expected", math.min(ratio / 1.1, 1) * 40, 40, ("%d DPS against the %d your gear and pet should give: %d%%"):format(
      Round(dps), Round(baseline), Round(ratio * 100)))
  end
  local ab = f.ab or {}
  local ranged = ctx and ctx.sheet and ctx.sheet.ranged
  local auto = Find(ab, "Auto Shot")
  if ranged and dur >= 6 then
    local up = H.AutoUptime(auto and auto.n or 0, dur, ranged, ctx.sheet.haste) or 0
    Part("auto", "Auto Shot fires continuously", math.min(up / 0.85, 1) * 20, 20,
      ("%d shots, %d%% of the possible"):format(auto and auto.n or 0, Round(up * 100)))
  end
  local src, share = H.Sources(ab, f.dmg)
  if level >= 10 then
    Part("pet", "The pet deals damage", math.min(share.pet / 25, 1) * 15, 15, ("%d%% of the damage is the pet's (good: over 25%%)"):format(Round(share.pet)))
    local own = src.ranged + src.melee
    if own > 0 then
      local r = src.ranged / own
      Part("range", "You fight from range", math.min(r / 0.8, 1) * 5, 5, ("%d%% of your own damage is ranged"):format(Round(r * 100)))
    end
  end
  if dur >= 15 and level >= 4 then
    local used = Find(ab, "Serpent Sting (dot)") ~= nil
    for _, c in ipairs(f.casts or {}) do if c[2] == "Serpent Sting" then used = true end end
    Part("sting", "Serpent Sting in long fights", used and 10 or 0, 10, used and "was up" or "you did not use it (fights longer than 15 s)")
  end
  if dur >= 10 and level >= 6 then
    local n = 0
    for _, name in ipairs(SPECIALS) do local a = Find(ab, name) n = n + (a and a.n or 0) end
    for _, c in ipairs(f.casts or {}) do if c[2] == "Rapid Fire" or c[2] == "Bestial Wrath" then n = n + 1 end end
    local perMin = n / dur * 60
    Part("shots", "Shots besides Auto Shot", math.min(perMin / 3, 1) * 10, 10, ("%s Arcane / Multi / Aimed per minute"):format(F1(perMin)))
  end
  local got, max = 0, 0
  for _, p in ipairs(parts) do got, max = got + p.points, max + p.max end
  if max == 0 then return nil end
  local total = math.floor(got / max * 100 + 0.5)
  local grade = "D"
  for _, g in ipairs(GRADES) do if total >= g[1] then grade = g[2] break end end
  return { total = total, grade = grade, parts = parts, dps = dps }
end

-- The raid-log style summary of many fights (r = WA.Combat.Report): damage sources, Auto Shot
-- activity, casts per minute and damage per cast, Serpent Sting and Aspect of the Hawk uptime.
function H.Summary(r, ctx)
  if not r then return nil end
  local src, share = H.Sources(r.abilities, r.damage)
  local secs = r.seconds
  local auto = Find(r.abilities, "Auto Shot")
  local ranged = ctx and ctx.sheet and ctx.sheet.ranged
  local s = {
    sources = src, shares = share, seconds = secs, dps = r.dps,
    autoUptime = auto and H.AutoUptime(auto.n, secs, ranged, ctx.sheet.haste) or nil,
    autoMiss = auto and auto.n > 0 and ((auto.miss or 0) + (auto.dodge or 0)) / auto.n * 100 or nil,
    autoCrit = auto and (auto.hit + auto.crit) > 0 and auto.crit / (auto.hit + auto.crit) * 100 or nil,
    rows = {},
  }
  local sting = Find(r.abilities, "Serpent Sting (dot)")
  -- a Serpent Sting ticks every 3 seconds
  s.stingUptime = sting and math.min(100, sting.n * 3 / secs * 100) or 0
  for _, a in ipairs(r.auras or {}) do
    if a.name == "Aspect of the Hawk" then s.hawk = a.uptimePct end
    if a.name == "Aspect of the Monkey" then s.monkey = a.uptimePct end
  end
  for _, a in ipairs(r.abilities) do
    local landed = (a.hit or 0) + (a.crit or 0) + (a.glance or 0)
    s.rows[#s.rows + 1] = { name = a.name, dmg = a.dmg, share = a.share, n = a.n, cpm = a.n / secs * 60,
      perCast = a.n > 0 and a.dmg / a.n or 0, avg = landed > 0 and a.dmg / landed or 0,
      kind = IsPet(a.name) and "pet" or (a.name:sub(-6) == " (dot)" and "dot") or (RANGED[a.name] and "ranged") or (MELEE[a.name] and "melee") or "other" }
  end
  return s
end

-- Advice from all the recorded fights (instead of the rogue's).
function H.Advise(r, fights)
  local out = {}
  local function Push(o) out[#out + 1] = WA.Combat.Finding(o) end
  local auto = Find(r.abilities, "Auto Shot")
  local level = fights[1] and fights[1].level or 0
  if r.seconds < 300 or not auto or auto.n < 100 then
    Push({ info = true, title = "Not enough data yet", fact = ("So far %d fights, %d seconds and %d Auto Shots are recorded. The ratios are reliable after about 10 minutes of combat.")
      :format(r.fights, Round(r.seconds), auto and auto.n or 0) })
  end
  local src, share = H.Sources(r.abilities, r.damage)
  if level >= 10 and r.seconds >= 120 and share.pet < 15 then
    Push({ title = "The pet did little damage", fault = true, rule = "hunterPet",
      fact = ("%d%% of your damage is the pet's (typically 25–40%%)."):format(Round(share.pet)),
      advice = "Check the Pet page: the newest rank of Claw/Bite, happiness (a happy pet does +25% damage), and if its family is weak, a cat or raptor.",
      missing = "whether the pet was alive, out and attacking in the fights (its death and passive mode do not show)" })
  end
  local own = src.ranged + src.melee
  if level >= 10 and own > 0 and src.melee / own > 0.25 then
    Push({ title = "A lot of melee damage", fault = true, rule = "hunterRange",
      fact = ("%d%% of your own damage is melee."):format(Round(src.melee / own * 100)),
      advice = "If the pet could hold the mob, shoot from range; Raptor Strike only when the mob is on you.",
      missing = "why the mob was on you (the pet's aggro, range and movement do not show)" })
  end
  if auto and auto.n >= 50 then
    local miss = ((auto.miss or 0) + (auto.dodge or 0)) / auto.n * 100
    if miss > 9 then
      Push({ title = "Many shots miss", rule = "hitGear",
        fact = ("%s%% of your Auto Shots are a miss or dodge."):format(F1(miss)),
        advice = "+hit items, and avoiding higher-level mobs, help a lot here." })
    end
  end
  local avgFight = r.seconds / math.max(1, r.fights)
  local sting = Find(r.abilities, "Serpent Sting (dot)")
  if level >= 4 and avgFight >= 15 and not sting then
    Push({ title = "No Serpent Sting", fault = true, rule = "serpentSting",
      fact = ("Your average fight is %d s, and there is no Serpent Sting tick."):format(Round(avgFight)),
      advice = "In a longer fight the Sting as an opener is a lot of free damage.",
      missing = "your mana at the start of the fight, and whether the mob was immune to it" })
  end
  local special = 0
  for _, name in ipairs(SPECIALS) do local a = Find(r.abilities, name) special = special + (a and a.n or 0) end
  if level >= 6 and r.seconds >= 120 and special / r.seconds * 60 < 1 then
    Push({ title = "You rarely fire Arcane Shot", fault = true, rule = "arcaneShot",
      fact = ("%s Arcane / Multi / Aimed Shots per minute."):format(F1(special / r.seconds * 60)),
      advice = "If you have mana, Arcane Shot is extra damage every 6 seconds.",
      missing = "your mana in the fights, and whether you could shoot when it was off cooldown" })
  end
  local hawk
  for _, a in ipairs(r.auras or {}) do if a.name == "Aspect of the Hawk" then hawk = a.uptimePct end end
  if level >= 10 and r.seconds >= 120 and (hawk or 0) < 50 then
    Push({ title = "Aspect of the Hawk is rarely up", fault = true, rule = "hawk",
      fact = ("Aspect of the Hawk was up %d%% of combat time."):format(Round(hawk or 0)),
      advice = "Shooting from range, this is the +ranged attack power aspect.",
      missing = "whether you had learned it, and whether another aspect (Monkey, Cheetah) was needed at the time" })
  end
  if auto and auto.n >= 100 then
    local landed = auto.hit + auto.crit
    Push({ info = true, title = "Measured ratios", fact = ("Auto Shot: %s%% miss, %s%% dodge, %s%% crit. Damage: ranged %d%%, pet %d%%, melee %d%%, DoT %d%%.")
      :format(F1((auto.miss or 0) / auto.n * 100), F1((auto.dodge or 0) / auto.n * 100), F1(landed > 0 and auto.crit / landed * 100 or 0),
        Round(share.ranged), Round(share.pet), Round(share.melee), Round(share.dot)) })
  end
  return out
end
