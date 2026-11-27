-- Waystone: the mage damage model, levels 1-60 (a main nuke, Frostbolt or Fireball, with Fire
-- Blast, Arcane Missiles and the rest around it, a wand when the mana runs out). Pure like
-- Model.lua and Warlock.lua: the same context shape (score, describe, buffGain, weaponWarning, ...)
-- so the plan, the gear report and the pages work for mages unchanged.
--
-- Forever rules the model follows (Wowhead Forever and WoWSims Forever d5144855, 2026-11-26):
--   * Frostbolt and Fireball by rank: the level, the cast time and the damage from each rank's
--     Wowhead Forever tooltip (spell=116 ... 25304, 133 ... 25306). Frostbolt goes from 1.5 s to
--     3 s, Fireball from 1.5 s to 3.5 s.
--   * spell power coefficient: Frostbolt 0.407 at 1.5 s and 0.814 at 3 s (Wowhead Forever
--     spell=116, 8406, 25304), that is cast time / 3.5 x 0.95 (the slow); Fire Blast and Scorch
--     0.429, an Arcane Missiles missile 0.286 (spell=10199, 10207, 25346). Wowhead shows none for
--     Fireball: the model uses the same rule, cast time / 3.5, and says so.
--   * a mana potion or a mana gem gives mana, and mana over the maximum is lost (sim/core/mana.go
--     AddMana: new mana = min(old + gained, maximum); the energize event states the lost part)
--   * a wand's damage does not grow with spell power
--
-- Extra input besides Model.lua's: int, spFire, spFrost (spell power by school), spellCrit (and
-- spellCritFire, spellCritFrost by school), spellHit, tab (the talent tab with the most points),
-- talents = Talent.lua's T.Effects (the numbers of the rank's Wowhead Forever text): accelerant,
-- impFrostbolt (cast time − s), ignite (% of a fire crit), iceShards (frost crit bonus %), critMass
-- (fire crit %), wandSpec (wand %), arcaneMind (intellect %), instability (spell damage %), precision.

local _, WA = ...
WA = WA or {}
local M = WA.Model
local MG = {}
WA.Mage = MG

local function F1(n) return ("%.1f"):format(n) end
local Round = M.Round

-- { level, min, max, cast seconds } per rank (Wowhead Forever tooltips)
MG.RANKS = {
  Frostbolt = { { 4, 18.8, 20.8, 1.5 }, { 8, 28.4, 32.0, 1.8 }, { 14, 45.4, 50.6, 2.2 }, { 20, 69.6, 76.8, 2.6 }, { 26, 104.5, 113.9, 3 },
    { 32, 134.9, 146.7, 3 }, { 38, 181.4, 196.6, 3 }, { 44, 243.6, 262.8, 3 }, { 50, 305.8, 331.0, 3 }, { 56, 382.9, 412.3, 3 }, { 60, 470.0, 505.6, 3 } },
  Fireball = { { 1, 15, 23, 1.5 }, { 6, 27, 39, 2 }, { 12, 45, 61, 2.5 }, { 18, 68, 93, 3 }, { 24, 108, 143, 3.5 }, { 30, 138, 182, 3.5 },
    { 36, 171, 222, 3.5 }, { 42, 213, 275, 3.5 }, { 48, 272, 348, 3.5 }, { 54, 339, 431, 3.5 }, { 60, 409, 517, 3.5 } },
}
MG.SCHOOL = { Frostbolt = "frost", Fireball = "fire" }
MG.NUKES = { Frostbolt = true, Fireball = true, ["Fire Blast"] = true, Scorch = true, Pyroblast = true, ["Arcane Missiles"] = true,
  ["Arcane Blast"] = true, ["Ice Lance"] = true, ["Frostfire Bolt"] = true }
MG.AOE = { ["Arcane Explosion"] = true, ["Frost Nova"] = true, ["Cone of Cold"] = true, Blizzard = true, Flamestrike = true, ["Blast Wave"] = true }
-- cast seconds of the casts that are not a global cooldown (the main nukes use their rank's)
MG.CAST = { Scorch = 1.5, Pyroblast = 6, Flamestrike = 3, ["Arcane Missiles"] = 5, Blizzard = 8, Evocation = 8 }
-- potions and gems that give mana (the log's spell names)
MG.MANA_ITEMS = { ["Restore Mana"] = true, ["Replenish Mana"] = true }

local function Base(name) return ((name or ""):gsub(" %(dot%)$", "")) end
local function IsDot(name) return (name or ""):sub(-6) == " (dot)" end

-- wand, dot, nuke, aoe, melee, other
local function Kind(name)
  name = name or ""
  local base = Base(name)
  if name == "Shoot" then return "wand" end
  if IsDot(name) then return "dot" end
  if MG.NUKES[base] then return "nuke" end
  if MG.AOE[base] then return "aoe" end
  if name == "Melee" then return "melee" end
  return "other"
end
MG.Kind = Kind

local function WandDps(w) return w and w.speed and w.speed > 0 and (w.min + w.max) / 2 / w.speed or 0 end
MG.WandDps = WandDps

-- the highest rank at this level: { level, min, max, cast }, or nil before the first
function MG.Rank(spell, level)
  local best
  for _, r in ipairs(MG.RANKS[spell] or {}) do if r[1] <= (level or 1) then best = r end end
  return best
end

-- spell power coefficient of a rank (cast time / 3.5; Frostbolt x 0.95 for its slow)
function MG.Coef(spell, rank)
  if not rank then return 0 end
  local c = math.min(rank[4], 3.5) / 3.5
  if spell == "Frostbolt" then c = c * 0.95 end
  return c
end

---------------------------------------------------------------------------
-- the model
---------------------------------------------------------------------------
-- A crit does 1.5× (Ice Shards raises a frost crit's 50% bonus by its %); Ignite burns a fire crit's
-- damage by its % more; Arcane Instability adds to all spell damage; Wand Specialization to the wand.
function MG.Dps(sh, p)
  local scrit = math.max(0, math.min(sh.spellCrit + (p.critAdd or 0), 100)) / 100
  local miss = math.max(1, p.spellMiss - (sh.spellHit or 0)) / 100
  local critMult = p.critMult or 1.5
  local sf = (1 - miss) * (1 + scrit * (critMult - 1) + scrit * critMult * (p.ignite or 0) / 100)
  local total = p.otherDps
  total = total + p.nukePerSec * (p.nukeDamage + p.coef * sh.sp) * sf * (p.dmgMult or 1)
  total = total + p.wandUptime * WandDps(sh.wand) * (1 - miss) * (1 + (p.wandSpec or 0) / 100)
  return total
end

local function Apply(sh, remove, add, p)
  local dInt = ((add.int or 0) - (remove.int or 0)) * p.statMult * (p.intMult or 1)
  return {
    sp = sh.sp + (add.sp or 0) - (remove.sp or 0),
    spellCrit = sh.spellCrit + dInt / p.intPerCrit,
    spellHit = sh.spellHit, wand = sh.wand, ap = sh.ap, crit = sh.crit, hit = sh.hit, mh = sh.mh,
  }
end

---------------------------------------------------------------------------
-- context
---------------------------------------------------------------------------
function MG.Context(input)
  local level = input.level or 1
  local equipped = input.equipped or {}
  local notes = {}
  local function eq(slot) return equipped[slot] and equipped[slot].stats or M.ZERO end
  local intPerCrit = 6 + (54 * (level - 1)) / 59
  local combat = input.combat
  local tal = input.talents or {}

  -- the main nuke: the one you cast more in your fights, else Fireball for a Fire mage, else
  -- Frostbolt (Fireball before level 4, when Frostbolt is not trained yet)
  local counts = { Frostbolt = 0, Fireball = 0 }
  for _, a in ipairs(combat and combat.abilities or {}) do
    if counts[a.name] then counts[a.name] = counts[a.name] + (a.n or 0) end
  end
  local nuke
  if counts.Frostbolt + counts.Fireball > 0 then nuke = counts.Fireball > counts.Frostbolt and "Fireball" or "Frostbolt"
  else nuke = (input.tab == 2 or level < 4) and "Fireball" or "Frostbolt" end
  local rank = MG.Rank(nuke, level) or MG.Rank("Fireball", level)
  if not MG.Rank(nuke, level) then nuke = "Fireball" end
  local coef = MG.Coef(nuke, rank)
  local school = MG.SCHOOL[nuke]
  local sp = school == "fire" and (input.spFire or input.sp or 0) or (input.spFrost or input.sp or 0)

  local wand = eq("RANGED").weapon
  -- the main nuke's own school's crit where the client gives it by school
  local schoolCrit = school == "fire" and input.spellCritFire or input.spellCritFrost
  local sheet = { sp = sp, spellCrit = schoolCrit or input.spellCrit or 0, spellHit = input.spellHit or 0, wand = wand,
    ap = input.ap or 0, crit = input.crit or 0, hit = input.hit or 0, mh = eq("MAIN_HAND").weapon }
  notes[#notes + 1] = ("Main spell: %s (level %d rank, %s s, %d–%d damage; Wowhead Forever), with %d%% of spell power%s. 1%% spell crit ≈ %s intellect. The wand is %s DPS, which does not grow with spell power.")
    :format(nuke, rank[1], F1(rank[4]), Round(rank[2]), Round(rank[3]), Round(coef * 100),
      nuke == "Fireball" and " (Wowhead shows no coefficient for Fireball: following Frostbolt, cast time / 3.5)" or "",
      F1(intPerCrit), F1(WandDps(wand)))

  -- talents: Accelerant / Improved Frostbolt shorten the nuke's cast (the coefficient stays the
  -- rank's); Critical Mass is fire crit: when the client's fire crit is not above its frost crit by
  -- that much, the sheet does not have it, so the model adds it
  local cast = math.max(1, rank[4] - (nuke == "Fireball" and (tal.accelerant or 0) or (tal.impFrostbolt or 0)))
  local critAdd = 0
  if school == "fire" and (tal.critMass or 0) > 0 then
    local gap = (input.spellCritFire or 0) - (input.spellCritFrost or 0)
    if not (input.spellCritFire and input.spellCritFrost and gap >= tal.critMass - 0.05) then critAdd = tal.critMass end
    notes[#notes + 1] = critAdd > 0 and ("Critical Mass: +%s%% fire crit added (the game's fire crit is not that much higher than its frost crit, so the character sheet does not include it)."):format(F1(critAdd))
      or "Critical Mass: the game's fire crit is that much higher than its frost crit, so the character sheet already includes it."
  end

  -- priors: the main nuke 60% of the time (mana, moving, pulling), the wand a tenth of it
  local params = {
    level = level, intPerCrit = intPerCrit, statMult = 1, spellMiss = 4, nuke = nuke, rank = rank, coef = coef, school = school,
    nukePerSec = 0.6 / cast, nukeDamage = (rank[2] + rank[3]) / 2,
    wandUptime = wand and 0.1 or 0,
    critAdd = critAdd, critMult = 1.5 + (school == "frost" and 0.5 * (tal.iceShards or 0) / 100 or 0),
    ignite = school == "fire" and (tal.ignite or 0) or 0, dmgMult = 1 + (tal.instability or 0) / 100,
    wandSpec = tal.wandSpec or 0, intMult = 1 + (tal.arcaneMind or 0) / 100,
    otherDps = 0, notes = notes,
  }

  local function mix(prior, measured, n, half)
    local w = n / (n + half)
    return prior * (1 - w) + measured * w
  end
  local function landed(a) return (a.hit or 0) + (a.crit or 0) + (a.glance or 0) end
  if combat and combat.seconds > 0 then
    local secs = combat.seconds
    local main, wandN, other = nil, 0, 0
    for _, a in ipairs(combat.abilities) do
      if a.name == nuke then main = a
      elseif Kind(a.name) == "wand" then wandN = wandN + a.n
      -- Ignite's burn is the model's (from the nuke's crits) once the talent is counted
      elseif params.ignite > 0 and Base(a.name) == "Ignite" then
      else other = other + a.dmg end
    end
    if main then
      params.nukePerSec = mix(params.nukePerSec, main.n / secs, secs, 120)
      local l = landed(main)
      if l > 0 then
        -- the logged damage has Ice Shards' crit bonus and Arcane Instability in it
        local per = main.dmg / (l + (params.critMult - 1) * (main.crit or 0)) / params.dmgMult
        params.nukeDamage = mix(params.nukeDamage, math.max(0, per - coef * sheet.sp), l, 10)
      end
      if main.n > 0 then params.spellMiss = mix(params.spellMiss, ((main.miss or 0) + (main.other or 0)) / main.n * 100, main.n, 30) end
    else
      params.nukePerSec = mix(params.nukePerSec, 0, secs, 120)
    end
    if wand then params.wandUptime = mix(params.wandUptime, math.min(1, wandN / secs * wand.speed), secs, 120) end
    params.otherDps = mix(0, other / secs, secs, 120)
    notes[#notes + 1] = ("Calibrated from %d recorded fights (%d s): %s %s per minute (%d damage without spell power), wand %d%% of the time, everything else %s DPS.")
      :format(combat.fights, Round(secs), F1(params.nukePerSec * 60), nuke, Round(params.nukeDamage), Round(params.wandUptime * 100), F1(params.otherDps))
  else
    notes[#notes + 1] = "No recorded fights, so it uses textbook values. Turn on the combat log (/wa log) to calibrate."
  end
  notes[#notes + 1] = "The model does not count mana: intellect is only worth something for spell crit, in reality more for the bigger mana pool (less resting, less wand)."

  local unbuffed = MG.Dps(sheet, params)
  local buffs = M.ResolveBuffs(level, input.buffs, input.data)
  local bInt, bSp = 0, 0
  for _, b in ipairs(buffs) do
    if b.selected and b.effect then bInt, bSp = bInt + (b.effect.int or 0), bSp + (b.effect.sp or 0) end
  end
  sheet.sp = sheet.sp + bSp
  sheet.spellCrit = sheet.spellCrit + bInt / intPerCrit
  local baseline = MG.Dps(sheet, params)
  local equippedIds = {}
  for _, it in pairs(equipped) do if it.id then equippedIds[it.id] = true end end

  local ctx = M.Common({
    level = level, baseline = baseline, unbuffed = unbuffed, buffs = buffs, params = params, sheet = sheet,
    equipped = equipped, equippedIds = equippedIds, combat = combat, slotOrder = input.slotOrder,
  }, "MAGE")

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
      local gain = MG.Dps(sh, params) - baseline
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
    return MG.Dps(sh, params) - baseline
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

function MG.Sources(abilities, total)
  local out = { nuke = 0, dot = 0, aoe = 0, wand = 0, melee = 0, other = 0 }
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

-- mana potions and gems of fights: gained, over (lost), the ones that lost at least half
function MG.ManaItems(fights)
  local out = { n = 0, gain = 0, over = 0, wasteful = {}, seen = 0 }
  for _, f in ipairs(fights or {}) do
    if type(f.gems) == "table" then
      out.seen = out.seen + 1
      for _, t in ipairs(f.gems) do
        local gain, over = tonumber(t.gain) or 0, tonumber(t.over) or 0
        out.n, out.gain, out.over = out.n + 1, out.gain + gain, out.over + over
        if gain > 0 and over * 2 >= gain then out.wasteful[#out.wasteful + 1] = { start = f.start, t = t } end
      end
    end
  end
  return out
end

local function CastTime(name, p)
  if p and name == p.nuke then return p.rank[4] end
  return MG.CAST[name] or 1.5
end

local GRADES = { { 90, "S" }, { 80, "A" }, { 65, "B" }, { 50, "C" }, { 0, "D" } }
function MG.Score(f, ctx)
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
  local p = ctx and ctx.params
  if dur >= 6 then
    -- busy time: casts (the main nuke its rank's cast time, the channels theirs, anything else a
    -- 1.5 s global cooldown) and wand shots
    local busy = 0
    for _, c in ipairs(f.casts or {}) do
      if c[2] ~= "Shoot" and not MG.MANA_ITEMS[c[2]] then busy = busy + CastTime(c[2], p) end
    end
    local shoot = Find(ab, "Shoot")
    local wand = ctx and ctx.sheet and ctx.sheet.wand
    if shoot and wand then busy = busy + shoot.n * wand.speed end
    local up = math.min(1, busy / dur)
    Part("active", "You cast continuously", math.min(up / 0.8, 1) * 20, 20, ("you were casting or wanding about %d%% of the time (from the casts and the shots)"):format(Round(up * 100)))
  end
  if type(f.gems) == "table" and #f.gems > 0 then
    local gain, over = 0, 0
    for _, t in ipairs(f.gems) do gain, over = gain + (t.gain or 0), over + (t.over or 0) end
    local kept = gain > 0 and 1 - over / gain or 1
    Part("mana", "No mana potion wasted", kept * 15, 15, ("%d mana potions or mana gems: %d mana, of which %d was lost over the maximum"):format(#f.gems, Round(gain), Round(over)))
  end
  local got, max = 0, 0
  for _, x in ipairs(parts) do got, max = got + x.points, max + x.max end
  if max == 0 then return nil end
  local total = math.floor(got / max * 100 + 0.5)
  local grade = "D"
  for _, g in ipairs(GRADES) do if total >= g[1] then grade = g[2] break end end
  return { total = total, grade = grade, parts = parts, dps = dps }
end

function MG.Summary(r, ctx, fights)
  if not r then return nil end
  local src, share = MG.Sources(r.abilities, r.damage)
  local secs = r.seconds
  local s = { sources = src, shares = share, seconds = secs, dps = r.dps, rows = {}, mana = MG.ManaItems(fights),
    nuke = ctx and ctx.params and ctx.params.nuke }
  local main = s.nuke and Find(r.abilities, s.nuke)
  if main then
    local l = (main.hit or 0) + (main.crit or 0)
    s.main = { name = s.nuke, cpm = main.n / secs * 60, crit = l > 0 and (main.crit or 0) / l * 100 or 0, miss = main.n > 0 and ((main.miss or 0) + (main.other or 0)) / main.n * 100 or 0 }
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
  return date and date("%m/%d %H:%M:%S", math.floor(s)) or tostring(math.floor(s))
end

function MG.Advise(r, fights)
  local C = WA.Combat
  local out = {}
  local function Push(o) out[#out + 1] = C.Finding(o) end
  if r.seconds < 300 then
    Push({ info = true, title = "Not enough data yet", fact = ("So far %d fights and %d seconds are recorded. The ratios are reliable after about 10 minutes of combat.")
      :format(r.fights, Round(r.seconds)) })
  end
  local _, share = MG.Sources(r.abilities, r.damage)
  -- a mana potion or gem over the maximum: the event itself states the lost part
  local items = MG.ManaItems(fights)
  if #items.wasteful > 0 then
    local lines = {}
    for i = 1, math.min(3, #items.wasteful) do
      local x = items.wasteful[i]
      lines[i] = ("%s: gave %d mana, %d of it lost"):format(Clock(x.start, x.t.t), x.t.gain, x.t.over)
    end
    Push({ title = "Mana potion at full mana", fault = true, rule = "manaItemCap",
      fact = ("%d mana potions or mana gems put most of their mana over the maximum, and it was lost (combat log: the mana event itself says how much went over the maximum):\n- %s%s\nIn total %d, %d mana, %d of it lost.")
        :format(#items.wasteful, table.concat(lines, "\n- "), #items.wasteful > 3 and ("\n- … plus " .. (#items.wasteful - 3)) or "",
          items.n, Round(items.gain), Round(items.over)),
      advice = "Use mana potions and mana gems when you are missing at least as much mana as they give." })
  elseif items.n > 0 then
    Push({ info = true, title = "Mana potions", fact = ("%d mana potions or mana gems in the fights: %d mana, %d of it went over the maximum."):format(items.n, Round(items.gain), Round(items.over)) })
  end
  if r.seconds >= 300 and share.wand >= 25 then
    Push({ title = "You wand a lot", rule = "wandFlat",
      fact = ("%s%% of your damage is the wand's."):format(F1(share.wand)),
      advice = "Wand damage does not grow with spell power: if you often run out of mana, more intellect and spirit, or a drink instead of a shorter rest, helps.",
      missing = "your mana during the fights (the combat log does not show it)" })
  end
  if r.seconds >= 120 then
    Push({ info = true, title = "Measured ratios", fact = ("Damage: direct spells %d%%, DoTs %d%%, AoE %d%%, wand %d%%, other %d%%.")
      :format(Round(share.nuke), Round(share.dot), Round(share.aoe), Round(share.wand), Round(share.other + share.melee)) })
  end
  return out
end
