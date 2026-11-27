-- WoW Assistant: the suggested rotation (WA-006) and its first spec, the Combat rogue (WA-007b).
--
-- A rotation is a calculation, not a verdict: it says what order the class model expects the most
-- damage from, with the numbers behind it, and sets your recorded fights beside it. A gap between
-- the two is never called a mistake here; a mistake ("hiba") needs a Forever-verified rule and the
-- events that prove it (Combat.lua, WA-028).
--
-- R.Build(ctx) -> nil, why | {
--   spec, dps (the suggestion's expected DPS), now (the same model at your measured rates; nil
--   without fights), fightSecs (your average fight, nil without fights),
--   priority = { { name, when, from } },           -- the order to press things in
--   rows = { { name, plan, measured, diff, from } },  -- per ability: suggested vs measured, DPS gap
--   cooldowns = { { name, plan, measured, value, from } },
--   notes = { ... }, summary = "one line for the Haditerv" }
-- ctx: the class model's context (M.Context) with ctx.input (G.Context keeps the input there).
-- A spec gets a definition in R.SPECS[class][tab]; the spec (WA-030) picks it, the level decides
-- which abilities and ranks it has.

local _, WA = ...
WA = WA or {}
local R = {}
WA.Rotation = R

local function F1(n) return ("%.1f"):format(n) end
local function Round(n) return math.floor(n + 0.5) end
local function Copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end

local SIM = "WoWSims Forever d5144855 "
local WH = "Wowhead Forever spell="
R.SIM_APL = SIM .. "ui/specs/rogue/dps/apls/default.apl.json"

-- the ticket of every spec's rotation, in the client's tab order (healer and tank specs: the
-- solo damage ticket or the healer / tank framework)
R.TICKETS = {
  ROGUE = { "WA-007a", "WA-007b", "WA-007c" }, WARRIOR = { "WA-008a", "WA-008b", "WA-024" },
  MAGE = { "WA-009a", "WA-009b", "WA-009c" }, WARLOCK = { "WA-010a", "WA-010b", "WA-010c" },
  HUNTER = { "WA-011a", "WA-011b", "WA-011c" }, SHAMAN = { "WA-012a", "WA-012b", "WA-021" },
  DRUID = { "WA-013a", "WA-013b", "WA-020" }, PRIEST = { "WA-014b", "WA-014b", "WA-014a" },
  PALADIN = { "WA-015b", "WA-015b", "WA-015a" },
}

-- The highest rank a level has: list = { { level, ... } } in level order.
local function Rank(list, level)
  local best
  for _, r in ipairs(list) do if (level or 0) >= r[1] then best = r end end
  return best
end
R.Rank = Rank

-- A talent of the character: its rank, the numbers of that rank's Wowhead Forever text and the
-- text itself; nil when the character does not have it.
local function Talent(ctx, name)
  local tal = ctx.input and ctx.input.talents or {}
  local rank = tal.ranks and tal.ranks[name] or 0
  if rank <= 0 then return nil end
  local T = WA.Talent
  local d = T and T.Find(ctx.class, name)
  local r = d and math.min(rank, d.max) or rank
  return { rank = rank, vals = d and d.vals and d.vals[r] or {}, text = d and T.RankText(d, r) or name }
end
R.Talent = Talent

---------------------------------------------------------------------------
-- Rogue, Combat (WA-007b)
---------------------------------------------------------------------------
-- Wowhead Forever spell data (nether.wowhead.com/forever/tooltip/spell/<id>, read 2026-11-27).
-- Sinister Strike: { level, id, flat damage on top of the weapon }; 45 energy, 1 combo point.
R.SINISTER = { { 1, 1752, 3 }, { 6, 1757, 6 }, { 14, 1758, 10 }, { 22, 1759, 15 }, { 30, 1760, 22 }, { 38, 8621, 33 },
  { 46, 11293, 52 }, { 54, 11294, 68 } }
-- Eviscerate, the trainer's ranks: { level, id, min, max, per point }; damage per hit =
-- min..max + per point × points + 4% of attack power per point (WoWSims sim/rogue/eviscerate.go);
-- 35 energy. Rank 9 (31016, level 60) is a book (Manual of Eviscerate IX), not the trainer's.
R.EVISCERATE = { { 1, 2098, 1, 5, 5 }, { 8, 6760, 3, 11, 11 }, { 16, 6761, 6, 20, 19 }, { 24, 6762, 10, 30, 31 },
  { 32, 8623, 15, 45, 45 }, { 40, 8624, 22, 66, 71 }, { 48, 11299, 34, 102, 110 }, { 56, 11300, 48, 144, 151 } }
R.EVIS_AP = 0.04
-- Slice and Dice: { level, id, melee attack speed % }; 25 energy, 6 + 3 × points seconds
-- (9 s at 1 point to 21 s at 5), × (1 + Improved Slice and Dice %) (sim/rogue/slice_and_dice.go).
R.SLICE = { { 10, 5171, 20 }, { 42, 6774, 30 } }
R.SND_COST, R.SND_BASE, R.SND_POINT = 25, 6, 3
-- Shank (Forever): { level, id, energy it gives }; 5 energy, 10 s cooldown, off-hand strike for 50%
-- weapon damage, cannot miss (crit only), no combo point; Flash of Steel: + energy, − cooldown
-- (sim/rogue/shank.go).
R.SHANK = { { 24, 1329283, 15 }, { 44, 1329549, 25 } }
R.SHANK_COST, R.SHANK_CD = 5, 10
-- Blade Flurry (13877, talent): 25 energy, 2 min cooldown, +20% melee attack speed for 15 s (and a
-- second target). Adrenaline Rush (13750, talent): 5 min cooldown, energy regeneration +100% for 15 s.
R.FLURRY = { id = 13877, cost = 25, cd = 120 }
R.RUSH = { id = 13750, cd = 300 }
-- energy: 1 every 0.1 s (sim/core/energy.go:49), at most 100 at the pull
R.ENERGY, R.ENERGY_MAX = 10, 100

local function CombatRogue(ctx)
  local M = WA.Model
  local p, sh, level = ctx.params, ctx.sheet, ctx.level or 0
  if not (p and sh and p.cycle) then return nil, "a modell nem adott számokat" end
  if not sh.mh then return nil, "nincs fegyver a fő kezedben" end
  local tal = ctx.input and ctx.input.talents or {}
  local c = p.cycle
  local combat = ctx.combat
  local notes = {}

  -- outcomes, as the model counts them (Model.lua M.Dps)
  local crit = math.min(sh.crit, 100) / 100
  local landed = math.max(0, 1 - math.max(0, p.yellowMissBase - sh.hit) / 100 - (p.dodge + p.parry) / 100)
  local cpPerSS = math.max(0.05, landed * (1 + crit * c.sealFate))
  local perPoint = c.refund / 5
  -- a finisher at k points: Sinister Strikes to build them, energy for the whole round
  local function Finisher(k, cost)
    local ss = math.max(0, k - c.ruthless) / cpPerSS
    return ss, ss * c.ssCost + cost - k * perPoint
  end

  -- the model's damage, piece by piece (M.Dps adds them up: white + Sinister Strike + Eviscerate + other)
  local function Dps(swing, ss, evis, evisDmg, other)
    local q = Copy(p)
    q.cycle, q.swingRate, q.ssPerSec, q.evisPerSec = nil, swing, ss, evis
    q.evisDamage, q.otherDps = evisDmg or p.evisDamage, other or 0
    return M.Dps(sh, q)
  end
  local ssCast = Dps(0, 1, 0)
  local function EvisCast(d) return Dps(0, 0, 1, d) end
  local function White(swing) return Dps(swing, 0, 0) end

  -- Eviscerate at 5 points with your rank
  local er = Rank(R.EVISCERATE, level)
  local evisBonus = 1 + ((tal.coup or 0) + (tal.aggression or 0)) / 100
  local function EvisFormula(k) return ((er[3] + er[4]) / 2 + er[5] * k + R.EVIS_AP * k * sh.ap) * evisBonus end
  local evisFin
  for _, f in ipairs(combat and combat.finishers or {}) do if f.name == "Eviscerate" then evisFin = f end end
  local evis5, evisFrom
  if evisFin and evisFin.avgCp > 0 and p.evisDamage > 0 then
    evis5 = p.evisDamage * EvisFormula(5) / EvisFormula(evisFin.avgCp)
    evisFrom = ("a mért %d ütésenként (átlag %s ponttal) átszámolva 5 pontra a rang képletével"):format(Round(p.evisDamage), F1(evisFin.avgCp))
  else
    evis5 = EvisFormula(5)
    evisFrom = "a rang képletéből"
  end
  local evisCast5 = EvisCast(evis5)
  local ssRank = Rank(R.SINISTER, level)

  -- Shank: with a weapon in the off hand, from level 24
  local shank
  local sr = sh.oh and Rank(R.SHANK, level)
  if sr then
    local gain, cd = sr[3], R.SHANK_CD
    local fos = Talent(ctx, "Flash of Steel")
    if fos then gain, cd = gain + (fos.vals[1] or 0), cd - (fos.vals[2] or 0) end
    local w = sh.oh
    local avg = (w.min + w.max) / 2 + (sh.ap / 14) * w.speed
    local hit = avg * 0.5 * (1 + (tal.dualWield or 0) / 100) * 0.5
    shank = { id = sr[2], gain = gain, cd = cd, rate = 1 / cd, net = (gain - R.SHANK_COST) / cd, cast = hit * (1 + crit),
      fos = fos, from = ("%s%d: %d energiáért %d energiát ad, %s mp cooldown%s; az off-hand fegyver sebzésének 50%%-a (off-hand: × 0,5%s), nem lehet kivédeni, csak crit"):format(
        WH, sr[2], R.SHANK_COST, gain, F1(cd), fos and (" (Flash of Steel " .. fos.rank .. ". rang)") or "",
        (tal.dualWield or 0) > 0 and (", Dual Wield Specialization +" .. tal.dualWield .. "%") or "") }
  end

  -- Slice and Dice: from level 10
  local sl = Rank(R.SLICE, level)
  local haste = sl and sl[3] / 100 or 0
  local imp = Talent(ctx, "Improved Slice and Dice")
  local impPct = imp and (imp.vals[1] or 0) or 0

  -- measured: your fights (the model's level-weighted report, WA-004)
  local secs = combat and combat.seconds or 0
  local measured = secs > 0
  local T = measured and secs / math.max(1, combat.fights) or nil
  local function Ab(name)
    for _, a in ipairs(combat and combat.abilities or {}) do if a.name == name then return a end end
    return nil
  end
  local function Uptime(name)
    for _, a in ipairs(combat and combat.auras or {}) do if a.name == name then return a.uptimePct / 100 end end
    return 0
  end
  local sndFin
  for _, f in ipairs(combat and combat.finishers or {}) do if f.name == "Slice and Dice" then sndFin = f end end
  local uNow = measured and Uptime("Slice and Dice") or 0
  -- the model's swing rate is from your fights, Slice and Dice in it: without it, then with the plan's
  local baseSwing = p.swingRate / (1 + haste * uNow)
  local shankAb = Ab("Shank")
  local mixW = measured and secs / (secs + 120) or 0
  local other = math.max(0, p.otherDps - mixW * (shankAb and shankAb.dmg or 0) / math.max(1, secs))

  -- the plan for Slice and Dice at k points (0: without it)
  local ss5, en5 = Finisher(5, c.evisCost)
  local function Plan(k)
    local E = R.ENERGY + (shank and shank.net or 0)
    local pl = { k = k, u = 0, sndRate = 0, dur = 0 }
    local spend, ssSnd = 0, 0
    if k > 0 then
      local ssk, enk = Finisher(k, R.SND_COST)
      local dur = (R.SND_BASE + R.SND_POINT * k) * (1 + impPct / 100)
      -- the opening: k points from none at the pull, with full energy
      local open = k / cpPerSS
      local tOpen = math.max(open, (open * c.ssCost + R.SND_COST - R.ENERGY_MAX) / E)
      local u = T and math.max(0, (T - tOpen) / T) or 1
      pl.u, pl.dur, pl.tOpen, pl.sndRate = u, dur, tOpen, u / dur
      spend, ssSnd = enk / dur * u, ssk / dur * u
    end
    pl.evisRate = math.max(0, E - spend) / en5
    pl.ssRate = ssSnd + pl.evisRate * ss5
    pl.swing = baseSwing * (1 + haste * pl.u)
    pl.shankRate = shank and shank.rate or 0
    pl.dps = Dps(pl.swing, pl.ssRate, pl.evisRate, evis5, other) + pl.shankRate * (shank and shank.cast or 0)
    return pl
  end
  local best = Plan(0)
  local noSnd = best
  local options = { [0] = best.dps }
  if sl then
    for k = 1, 5 do
      local pl = Plan(k)
      options[k] = pl.dps
      if pl.dps > best.dps + 0.01 then best = pl end
    end
  end

  -- your fights at the same model
  local now, nowR
  if measured then
    local ss, ev = Ab("Sinister Strike"), Ab("Eviscerate")
    nowR = { ss = (ss and ss.n or 0) / secs, evis = (ev and ev.n or 0) / secs, swing = p.swingRate,
      shank = (shankAb and shankAb.n or 0) / secs, snd = (sndFin and sndFin.casts or 0) / secs }
    now = Dps(nowR.swing, nowR.ss, nowR.evis, p.evisDamage, other) + nowR.shank * (shank and shank.cast or 0)
  end

  -- per ability: suggested, measured, the DPS between them (the parts add up to the whole gap)
  local rows = {}
  local function PerMin(x) return F1(x * 60) .. "/perc" end
  local whiteGap = measured and (White(best.swing) - White(nowR.swing)) or nil
  if sl then
    rows[#rows + 1] = { name = "Slice and Dice",
      plan = best.k > 0 and ("%d ponttal, amint lejár: %s mp, fent %d%%"):format(best.k, F1(best.dur), Round(best.u * 100)) or "nem éri meg",
      measured = measured and ("fent %d%%%s"):format(Round(uNow * 100), sndFin and (", átlag " .. F1(sndFin.avgCp) .. " ponttal") or "") or nil,
      diff = whiteGap,
      from = ("%s%d: +%d%% közelharci támadási sebesség, %d energia, %d + %d mp pontonként%s. A fehér ütéseid a javaslattal %s DPS-t adnak, Slice and Dice nélkül %s"):format(
        WH, sl[2], sl[3], R.SND_COST, R.SND_BASE, R.SND_POINT,
        imp and (", × " .. F1(1 + impPct / 100) .. " (Improved Slice and Dice " .. imp.rank .. ". rang)") or "",
        F1(White(best.swing)), F1(White(baseSwing))) .. (best.tOpen and ("; az átlagos harcod " .. Round(T or 0) .. " mp, a nyitás (" .. best.k .. " pont) kb. " .. F1(best.tOpen) .. " mp") or "") }
  end
  rows[#rows + 1] = { name = "Eviscerate",
    plan = ("%s, 5 ponttal (%d ütésenként)"):format(PerMin(best.evisRate), Round(evis5)),
    measured = measured and (PerMin(nowR.evis) .. (evisFin and (", átlag " .. F1(evisFin.avgCp) .. " ponttal") or "")) or nil,
    diff = measured and (best.evisRate * evisCast5 - nowR.evis * EvisCast(p.evisDamage)) or nil,
    from = ("%s%d (%d. szinttől): %d–%d + %d pontonként + 4%% AP pontonként; %s; × %s (Coup de Grace, Aggression). Energia: %d − %s visszakapott (Relentless Strikes)"):format(
      WH, er[2], er[1], er[3], er[4], er[5], evisFrom, F1(evisBonus), c.evisCost, F1(5 * perPoint)) }
  rows[#rows + 1] = { name = "Sinister Strike",
    plan = ("%s, combo pontért"):format(PerMin(best.ssRate)),
    measured = measured and PerMin(nowR.ss) or nil,
    diff = measured and ((best.ssRate - nowR.ss) * ssCast) or nil,
    from = ("%s%d (%d. szinttől, +%d); a modellben +%d (%s). %d energia; egy ütés %s combo pontot ad (%d%% talál%s). Castonként %s sebzés"):format(
      WH, ssRank[2], ssRank[1], ssRank[3], Round(p.ssBonus), measured and "a harcaidból kalibrálva" or "alapérték",
      c.ssCost, F1(cpPerSS), Round(landed * 100), c.sealFate > 0 and (", Seal Fate " .. Round(c.sealFate * 100) .. "% crit után") or "",
      F1(ssCast)) }
  if shank then
    rows[#rows + 1] = { name = "Shank",
      plan = ("%s, cooldownon, 80 energia alatt"):format(PerMin(shank.rate)),
      measured = measured and PerMin(nowR.shank) or nil,
      diff = measured and ((shank.rate - nowR.shank) * shank.cast) or nil,
      from = shank.from .. (". Castonként %s sebzés, és %s energia másodpercenként a többire"):format(F1(shank.cast), F1(shank.net)) }
  end

  -- cooldowns: what one use is worth (not in the DPS above: they depend on how often you get to use them)
  local cooldowns = {}
  local perEnergy = (ss5 * ssCast + evisCast5) / en5
  local fights = measured and math.max(1, combat.fights) or nil
  local casts = combat and combat.casts or {}
  if Talent(ctx, "Blade Flurry") then
    local gain = 15 * 0.20 * White(best.swing) - R.FLURRY.cost * perEnergy
    cooldowns[#cooldowns + 1] = { name = "Blade Flurry", value = gain,
      plan = ("harc elején, ha kész: +%d sebzés egy célponton"):format(Round(gain)),
      measured = fights and (F1((casts["Blade Flurry"] or 0) / fights) .. " harconként") or nil,
      from = ("%s%d: 15 mp alatt +20%% támadási sebesség a fehér ütéseidre (%s DPS), mínusz %d energia (%s sebzés energiánként); 2 perc cooldown. Több célponton a második is kap: az több"):format(
        WH, R.FLURRY.id, F1(White(best.swing)), R.FLURRY.cost, F1(perEnergy)) }
  end
  if Talent(ctx, "Adrenaline Rush") then
    local gain = 15 * R.ENERGY * perEnergy
    cooldowns[#cooldowns + 1] = { name = "Adrenaline Rush", value = gain,
      plan = ("ha kész és 50 energia alatt vagy: +%d sebzés"):format(Round(gain)),
      measured = fights and (F1((casts["Adrenaline Rush"] or 0) / fights) .. " harconként") or nil,
      from = ("%s%d: 15 mp alatt +%d energia, %s sebzés energiánként (Sinister Strike és 5 pontos Eviscerate); 5 perc cooldown"):format(
        WH, R.RUSH.id, 15 * R.ENERGY, F1(perEnergy)) }
  end

  -- the order to press things in (the WoWSims Forever default list for this build)
  local priority = {}
  local function P(name, when) priority[#priority + 1] = { name = name, when = when } end
  if Talent(ctx, "Blade Flurry") then P("Blade Flurry", "a harc elején, ha kész") end
  if Talent(ctx, "Adrenaline Rush") then P("Adrenaline Rush", "ha kész, Slice and Dice fent van, és 50 energia alatt vagy") end
  if shank then P("Shank", ("ha kész és 80 energia alatt vagy (a +%d energia ne vesszen el a 100-as plafonon)"):format(shank.gain)) end
  if sl and best.k > 0 then P("Slice and Dice", ("amint lejár, %d ponttal"):format(best.k)) end
  P("Eviscerate", "5 combo ponttal")
  P("Sinister Strike", "egyébként: combo pontot gyűjt")

  notes[#notes + 1] = "Számítás, nem hiba: a mért oszlop a harcaid átlaga (célpontváltás, futás, rövid harcok is benne vannak), a javasolt a modell szerinti legjobb sorrend egy célponton, hátulról."
  notes[#notes + 1] = ("Energia: %d másodpercenként%s; a kihagyott vagy kivédett Sinister Strike energiáját a számítás elveszettnek veszi. A cooldownok nincsenek a fenti DPS-ben."):format(
    R.ENERGY, shank and (", a Shankkel " .. F1(R.ENERGY + shank.net)) or "")
  if sl then
    local list = {}
    for k = 1, 5 do list[#list + 1] = ("%d ponttal %s"):format(k, F1(options[k])) end
    notes[#notes + 1] = ("Slice and Dice: nélküle %s DPS, %s. %s"):format(F1(noSnd.dps), table.concat(list, ", "),
      best.k > 0 and ("A legjobb a %d pontos."):format(best.k)
      or ("Most nem éri meg: a +%d%% támadási sebesség kevesebb sebzést ad, mint amennyit az energiája a Sinister Strike-kal és az Eviscerate-tel érne%s."):format(
        sl[3], T and (" (átlagos harcod: " .. Round(T) .. " mp)") or ""))
  end
  if not sh.oh and level >= 24 then notes[#notes + 1] = "A Shankhez fegyver kell az off-handben." end
  notes[#notes + 1] = "Sorrend: a WoWSims Forever alapértelmezett rogue-listája (" .. R.SIM_APL .. ")."

  local parts = {}
  if sl and best.k > 0 then parts[#parts + 1] = ("Slice and Dice %d ponttal"):format(best.k) end
  parts[#parts + 1] = "Eviscerate 5 ponttal"
  if shank then parts[#parts + 1] = "Shank cooldownon" end
  local summary = ("%s; várt %s DPS%s."):format(table.concat(parts, ", "), F1(best.dps), now and (" (a modell a mért gyakoriságaiddal: " .. F1(now) .. ")") or "")

  return { spec = "Combat", dps = best.dps, now = now, fightSecs = T, priority = priority, rows = rows,
    cooldowns = cooldowns, notes = notes, summary = summary, plan = best, options = options, white = White(baseSwing), ssCast = ssCast, evisCast = evisCast5, cpPerSS = cpPerSS, energy5 = en5, other = other, perEnergy = perEnergy, evis5 = evis5,
    shank = shank, haste = haste }
end

R.SPECS = { ROGUE = { [2] = CombatRogue } }

-- The rotation for the context's class and spec; nil and why when there is none (yet).
function R.Build(ctx)
  if not ctx then return nil, "nincs modell" end
  local spec = ctx.spec or (ctx.input and ctx.input.spec) or {}
  local tab = spec.tab
  if not tab then return nil, "még nincs talentpontod: a spec dönti el, melyik rotáció fut" end
  local fn = R.SPECS[ctx.class or ""] and R.SPECS[ctx.class][tab]
  local ticket = R.TICKETS[ctx.class or ""] and R.TICKETS[ctx.class][tab]
  if not fn then
    return nil, ("a(z) %s rotációja még nem készült el (%s)"):format(spec.name or "?", ticket or "?")
  end
  local ok, out, why = pcall(fn, ctx)
  if not ok then return nil, "számítási hiba: " .. tostring(out) end
  return out, why
end
