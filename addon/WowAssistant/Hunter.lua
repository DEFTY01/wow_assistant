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
-- haste (≥ 1), known = { [spell name] = true }, hasPet, talents = { lethal, mortal, reflexes }.

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
  if sh.ranged then
    local shot = H.Shot(sh, sh.ranged)
    total = total + p.rangedUptime * (sh.haste / sh.ranged.speed) * shot * rf
    total = total + p.multiPerSec * (shot + p.multiBonus) * rf
    total = total + p.aimedPerSec * (shot + p.aimedBonus) * rf
    total = total + p.arcanePerSec * p.arcaneDamage * rf
  end
  if sh.mh then
    local mcrit = math.min(sh.mcrit, 100) / 100
    local whiteMiss = math.max(0, (sh.oh and 24 or 5) - sh.hit) / 100
    local yellowMiss = math.max(0, 5 - sh.hit) / 100
    local dodge = p.meleeDodge / 100
    local whiteF = math.max(0, 1 - whiteMiss - dodge - mcrit) + mcrit * 2
    local yellowF = math.max(0, 1 - yellowMiss - dodge) * (1 + mcrit)
    local function avg(w) return (w.min + w.max) / 2 + (sh.ap / 14) * w.speed end
    local white = avg(sh.mh) / sh.mh.speed
    if sh.oh then white = white + avg(sh.oh) * 0.5 / sh.oh.speed end
    total = total + p.meleeUptime * white * whiteF + p.raptorPerSec * (avg(sh.mh) + p.raptorBonus) * yellowF
  end
  return total
end

local function Apply(sh, remove, add, p)
  local dAgi = ((add.agi or 0) - (remove.agi or 0)) * p.agiMult
  local dStr = ((add.str or 0) - (remove.str or 0)) * p.statMult
  local dAp = (add.ap or 0) - (remove.ap or 0)
  local dCrit = (add.crit or 0) - (remove.crit or 0) + dAgi / p.agiPerCrit
  return {
    ap = sh.ap + dAp + dAgi + dStr,
    rap = sh.rap + dAp + ((add.rap or 0) - (remove.rap or 0)) + 2 * dAgi,
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
  notes[#notes + 1] = ("1%% crit ≈ %s agility, 1 agility = 2 ranged AP + 1 melee AP (a saját statjaidból visszaszámolva)."):format(F1(agiPerCrit))

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
    petDps = early and 0 or 0.7 * level,
    stingDps = level >= 4 and (Rank("serpent", level) or 0) / 15 * 0.5 or 0,
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
    if arc and landed(arc) > 0 then
      params.arcaneDamage = mix(params.arcaneDamage, arc.dmg / (arc.hit + params.critMult * arc.crit), landed(arc), 10)
    end
    local shot = H.Shot(sheet, ranged)
    local multi = rate("Multi-Shot", "multiPerSec")
    if multi and ranged and landed(multi) > 0 then
      params.multiBonus = mix(params.multiBonus, math.max(0, multi.dmg / (multi.hit + params.critMult * multi.crit) - shot), landed(multi), 10)
    end
    local aimed = rate("Aimed Shot", "aimedPerSec")
    if aimed and ranged and landed(aimed) > 0 then
      params.aimedBonus = mix(params.aimedBonus, math.max(0, aimed.dmg / (aimed.hit + params.critMult * aimed.crit) - shot), landed(aimed), 10)
    end
    rate("Raptor Strike", "raptorPerSec")
    local sting, pet, other = 0, 0, 0
    for _, a in ipairs(combat.abilities) do
      local base = a.name:gsub(" %(dot%)$", "")
      if base == "Serpent Sting" then sting = sting + a.dmg
      elseif H.PET[base] then pet = pet + a.dmg
      elseif not SHOTS[a.name] then other = other + a.dmg end
    end
    params.stingDps = mix(params.stingDps, sting / secs, secs, 120)
    if pet > 0 then params.petDps = mix(params.petDps, pet / secs, secs, 120) end
    params.otherDps = mix(0, other / secs, secs, 120)
    notes[#notes + 1] = ("Kalibrálva %d rögzített harcból (%d mp). Auto Shot: %s%% alap miss, %s%% dodge, az idő %d%%-ában lősz; közelharc az idő %d%%-ában.")
      :format(combat.fights, Round(secs), F1(params.rangedMissBase), F1(params.rangedDodge),
        Round(params.rangedUptime * 100), Round(params.meleeUptime * 100))
    notes[#notes + 1] = ("Percenként: Arcane Shot %s (%d sebzés), Multi-Shot %s (+%d), Aimed Shot %s (+%d), Raptor Strike %s. Pet %s DPS, Serpent Sting %s DPS, egyéb %s DPS.")
      :format(F1(params.arcanePerSec * 60), Round(params.arcaneDamage), F1(params.multiPerSec * 60), Round(params.multiBonus),
        F1(params.aimedPerSec * 60), Round(params.aimedBonus), F1(params.raptorPerSec * 60), F1(params.petDps), F1(params.stingDps),
        F1(params.otherDps))
  else
    notes[#notes + 1] = ("Nincs rögzített harc, ezért tankönyvi értékekkel számol: az idő %d%%-ában Auto Shot, %s Arcane Shot és %s Multi-Shot percenként, %s. Kapcsold be a harcnaplót (/wa log) a kalibráláshoz.")
      :format(Round(params.rangedUptime * 100), F1(params.arcanePerSec * 60), F1(params.multiPerSec * 60),
        early and "pet nélkül, sok közelharccal (Raptor Strike)" or ("a pet kb. " .. Round(params.petDps) .. " DPS"))
  end
  if not ranged then notes[#notes + 1] = "Nincs távolsági fegyvered: egy íj, puska vagy számszeríj a legnagyobb fejlesztés." end
  if ranged and ranged.ammo and (input.ammoDps or 0) <= 0 then
    notes[#notes + 1] = "Nincs lőszer a lőszer-helyen: lőszer nélkül az Auto Shot nem lő. Vegyél nyilat vagy golyót a kereskedőnél."
  end
  if sheet.haste > 1.001 then notes[#notes + 1] = ("A tegez vagy lőszeres tasak %d%%-kal gyorsítja a lövéseidet."):format(Round((sheet.haste - 1) * 100)) end

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
      bits[#bits + 1] = kind == "bullet" and "golyó kell hozzá, nem nyíl" or "nyíl kell hozzá, nem golyó"
    end
    return table.concat(bits, ", ")
  end

  function ctx.buffGain(e)
    local add = { agi = e.agi or 0, str = e.str or 0, ap = e.ap or 0, crit = e.crit or 0, hit = 0, rap = 0 }
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

  local skills = input.skills
  function ctx.weaponWarning(itemClass, sub)
    if itemClass ~= 2 or not skills or not next(skills) then return nil end
    local line = M.WEAPON_SKILLS[sub]
    local s = line and skills[line]
    if not s then return ("%s nincs kitanulva (fegyvermester)"):format(tostring(line)) end
    if s.rank < s.max - 15 then return ("%s skill %d/%d"):format(line, s.rank, s.max) end
    return nil
  end

  -- Hunter advice from the model's own numbers (the combat page's advice is the rogue's).
  local advice = {}
  if combat and combat.seconds >= 120 then
    if ranged and params.rangedUptime < 0.6 and level >= 10 then
      advice[#advice + 1] = { level = "tip", title = "Kevés Auto Shot",
        text = ("A harcidban csak az idő %d%%-ában lősz. Engedd, hogy a pet fogja meg a mobot, és lőj távolról: a hunter sebzésének nagyja az Auto Shot."):format(Round(params.rangedUptime * 100)) }
    end
    if level >= 10 and params.meleeUptime > 0.3 then
      advice[#advice + 1] = { level = "tip", title = "Sokat vagy közelharcban",
        text = ("Az idő %d%%-ában közelharcban vagy. 10. szinttől a pet tankol: maradj 8 yardon kívül, és Wing Clip + hátralépés, ha rád jön a mob."):format(Round(params.meleeUptime * 100)) }
    end
    if level >= 10 and params.petDps < 0.2 * level then
      advice[#advice + 1] = { level = "tip", title = "Gyenge vagy hiányzó pet",
        text = "A pet alig sebez. Szelídíts a szintedhez illő állatot (Tame Beast), etesd, és tanítsd meg neki a Claw/Bite legújabb rangját." }
    end
  end
  ctx.advice = advice
  return ctx
end
