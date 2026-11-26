-- Waystone: the paladin damage model, levels 1-60 (white swings with a seal on them, Holy Strike
-- on its cooldown, Judgement, Consecration and the rest as measured). Pure like Model.lua and
-- Warrior.lua: the same context shape (score, describe, buffGain, weaponWarning, ...) so the plan,
-- the gear report and the pages work for paladins unchanged. Healing is not modelled: the enchant
-- section uses the healer weights for Holy and the tank weights for Protection.
--
-- Forever rules the model follows (Wowhead Forever, 2026-11-27):
--   * Holy Strike (Forever's own paladin strike, 10 s cooldown): a share of the weapon's damage
--     plus a flat holy part, by rank 25% + 11-14 (level 6, spell=679), 29% + 15-20 (12, 678),
--     32% + 18-22 (20, 1866), 36% + 23-29 (28, 680), 39% + 32-40 (36, 2495), 43% + 54-67 (44,
--     5569), 46% + 74-91 (52, 10332), 50% + 97-121 (60, 10333); the flat part with 0.429 of spell
--     power (Spell Details, spell=680 and 2495); a melee hit, so it can miss or be dodged
--   * Seal of Command: a chance on a white hit for 70% of the weapon's damage as holy (spell=20915,
--     20424); Wowhead shows no proc rate, so the model uses the hits you landed with it
--   * Seal of Righteousness: holy damage on every white hit, by rank from R/87 to R/25 with 0.0765
--     to 0.12 of spell power (R = 216 ... 2068, spell=20154 ... 20293; slower weapons more); the
--     model starts from the middle and uses your hits
--   * attack power = 2 x strength; agility gives crit
--
-- Extra input besides Model.lua's: str, agi, ap, crit, hit, spHoly, int, skills, tab.

local _, WA = ...
WA = WA or {}
local M = WA.Model
local PA = {}
WA.Paladin = PA

local function F1(n) return ("%.1f"):format(n) end
local Round = M.Round

-- { level, weapon share, flat min, flat max } per Holy Strike rank (Wowhead Forever tooltips)
PA.HOLY_STRIKE = { { 6, 0.25, 11, 14 }, { 12, 0.29, 15, 20 }, { 20, 0.32, 18, 22 }, { 28, 0.36, 23, 29 }, { 36, 0.39, 32, 40 },
  { 44, 0.43, 54, 67 }, { 52, 0.46, 74, 91 }, { 60, 0.50, 97, 121 } }
PA.HS_COEF, PA.HS_CD = 0.429, 10
-- { level, R } per Seal of Righteousness rank: R/87 to R/25 a hit
PA.SOR = { { 1, 216 }, { 10, 318 }, { 18, 490 }, { 26, 727 }, { 34, 1007 }, { 42, 1328 }, { 50, 1689 }, { 58, 2068 } }
PA.SOC_SHARE = 0.7
PA.SEALS = { ["Seal of Command"] = true, ["Seal of Righteousness"] = true }

local function Rank(list, level)
  local best
  for _, r in ipairs(list) do if r[1] <= (level or 1) then best = r end end
  return best
end
PA.Rank = Rank

-- melee, hs, seal, judgement, other
local function Kind(name)
  name = name or ""
  if name == "Melee" then return "melee" end
  if name == "Holy Strike" then return "hs" end
  if PA.SEALS[name] then return "seal" end
  if name:find("^Judgement") then return "judgement" end
  return "other"
end
PA.Kind = Kind

---------------------------------------------------------------------------
-- the model
---------------------------------------------------------------------------
local function Avg(w, ap) return (w.min + w.max) / 2 + (ap / 14) * w.speed end
local function NormAvg(w, ap, norm) return (w.min + w.max) / 2 + (ap / 14) * (norm or w.speed) end

function PA.Dps(sh, p)
  local total = p.otherDps
  if not sh.mh then return total end
  local mcrit = math.max(0, math.min(sh.crit, 100)) / 100
  local miss = math.max(0, 5 - sh.hit) / 100
  local dodge = p.dodge / 100
  local landF = math.max(0, 1 - miss - dodge)
  local yellowF = landF * (1 + mcrit)
  local whiteF = math.max(0, 1 - miss - dodge - mcrit) + mcrit * 2
  local swings = p.meleeUptime / sh.mh.speed
  local avg = Avg(sh.mh, sh.ap)
  total = total + swings * avg * whiteF
  -- the seal on the white hits that land: Seal of Command a share of the weapon hit, Seal of
  -- Righteousness a flat amount with spell power (both holy spells: a crit adds half)
  local seal = p.socK * avg + p.sorRate * (p.sorPerHit + p.sorCoef * sh.sp)
  total = total + swings * landF * seal * (1 + mcrit * 0.5)
  if p.hs then
    total = total + p.hsPerSec * (p.hs[2] * NormAvg(sh.mh, sh.ap, sh.mh.norm) + p.hsFlat + PA.HS_COEF * sh.sp) * yellowF
  end
  return total
end

local function Apply(sh, remove, add, p)
  local dAgi = ((add.agi or 0) - (remove.agi or 0)) * p.statMult
  local dStr = ((add.str or 0) - (remove.str or 0)) * p.statMult
  return {
    ap = sh.ap + (add.ap or 0) - (remove.ap or 0) + 2 * dStr,
    crit = sh.crit + (add.crit or 0) - (remove.crit or 0) + dAgi / p.agiPerCrit,
    hit = sh.hit + (add.hit or 0) - (remove.hit or 0),
    sp = sh.sp + (add.sp or 0) - (remove.sp or 0),
    mh = sh.mh,
  }
end

---------------------------------------------------------------------------
-- context
---------------------------------------------------------------------------
function PA.Context(input)
  local level = input.level or 1
  local equipped = input.equipped or {}
  local notes = {}
  local function eq(slot) return equipped[slot] and equipped[slot].stats or M.ZERO end
  local agi = input.agi or 0
  local crit = input.crit or 0
  local agiPerCrit = agi / math.max(0.1, crit)
  if not (agiPerCrit > 2 and agiPerCrit < 40) then agiPerCrit = 4 + (16 * (level - 1)) / 59 end
  local combat = input.combat

  local mh = eq("MAIN_HAND").weapon
  local mhItem = equipped.MAIN_HAND
  local twoHand = mhItem and mhItem.sub and (mhItem.sub == 1 or mhItem.sub == 5 or mhItem.sub == 6 or mhItem.sub == 8) or false
  if mh then mh = { min = mh.min, max = mh.max, speed = mh.speed, twoHand = twoHand, norm = M.NormalizedSpeed(mhItem and mhItem.sub, twoHand) } end
  local sheet = { ap = input.ap or 0, crit = crit, hit = input.hit or 0, sp = input.spHoly or input.sp or 0, mh = mh }
  local hs = Rank(PA.HOLY_STRIKE, level)
  local sor = Rank(PA.SOR, level)
  -- Seal of Command is a Retribution talent (level 20); the prior: about 7 procs a minute
  local soc = input.tab == 3 and level >= 20
  local speed = mh and mh.speed or 2.5

  local params = {
    level = level, agiPerCrit = agiPerCrit, statMult = 1, dodge = 5,
    meleeUptime = mh and (level < 10 and 0.65 or 0.85) or 0,
    hs = hs, hsFlat = hs and (hs[3] + hs[4]) / 2 or 0, hsPerSec = hs and 0.7 / PA.HS_CD or 0,
    socK = soc and PA.SOC_SHARE * 7 * speed / 60 or 0,
    sorRate = soc and 0 or 1, sorPerHit = (sor[2] / 87 + sor[2] / 25) / 2, sorCoef = (0.0765 + 0.12) / 2,
    otherDps = 0, notes = notes, tab = input.tab,
    -- the enchant section adds a holy spell damage enchant to the spell power
    school = "holy",
  }
  notes[#notes + 1] = ("1%% crit ≈ %s agility (a saját statjaidból); 1 strength = 2 AP. %s. Seal of Righteousness: ütésenként %d–%d + a spell power 8–12%%-a (%d. szintű rang, Wowhead Forever).")
    :format(F1(agiPerCrit), hs and ("Holy Strike: a fegyver sebzésének %d%%-a + %d–%d holy + a spell power 43%%-a (%d. szintű rang, Wowhead Forever)")
      :format(Round(hs[2] * 100), hs[3], hs[4], hs[1]) or "Holy Strike 6-os szinttől", Round(sor[2] / 87), Round(sor[2] / 25), sor[1])

  local function mix(prior, measured, n, half)
    local w = n / (n + half)
    return prior * (1 - w) + measured * w
  end
  local function landed(a) return (a.hit or 0) + (a.crit or 0) + (a.glance or 0) end
  if combat and combat.seconds > 0 then
    local secs = combat.seconds
    local melee, hsA, socA, sorA, other = nil, nil, nil, nil, 0
    for _, a in ipairs(combat.abilities) do
      if a.name == "Melee" then melee = a
      elseif a.name == "Holy Strike" then hsA = a
      elseif a.name == "Seal of Command" then socA = a
      elseif a.name == "Seal of Righteousness" then sorA = a
      else other = other + a.dmg end
    end
    if mh then
      local whiteLanded = melee and landed(melee) or 0
      params.meleeUptime = mix(params.meleeUptime, math.min(1, (melee and melee.n or 0) / secs * mh.speed), secs, 120)
      if whiteLanded > 0 then
        local avg = Avg(mh, sheet.ap)
        local socDmg = socA and socA.dmg / (1 + 0.5 * (socA.crit or 0) / math.max(1, landed(socA))) or 0
        params.socK = mix(params.socK, socDmg / whiteLanded / avg, whiteLanded, 20)
        local sorHits = sorA and landed(sorA) or 0
        params.sorRate = mix(params.sorRate, math.min(1, sorHits / whiteLanded), whiteLanded, 20)
        if sorHits > 0 then
          local per = sorA.dmg / (sorHits + 0.5 * (sorA.crit or 0))
          params.sorPerHit = mix(params.sorPerHit, math.max(0, per - params.sorCoef * sheet.sp), sorHits, 10)
        end
      end
      if hs then
        params.hsPerSec = mix(params.hsPerSec, (hsA and hsA.n or 0) / secs, secs, 120)
        if hsA and landed(hsA) > 0 then
          local per = hsA.dmg / (landed(hsA) + (hsA.crit or 0))
          params.hsFlat = mix(params.hsFlat, math.max(0, per - hs[2] * NormAvg(mh, sheet.ap, mh.norm) - PA.HS_COEF * sheet.sp), landed(hsA), 10)
        end
      end
    end
    params.otherDps = mix(0, other / secs, secs, 120)
    notes[#notes + 1] = ("Kalibrálva %d rögzített harcból (%d mp): ütés az idő %d%%-ában, Holy Strike %s percenként, Seal of Command a fegyverütés %d%%-a ütésenként, Seal of Righteousness az ütések %d%%-án (%d), minden más (Judgement, Consecration...) %s DPS.")
      :format(combat.fights, Round(secs), Round(params.meleeUptime * 100), F1(params.hsPerSec * 60), Round(params.socK * 100), Round(params.sorRate * 100),
        Round(params.sorPerHit), F1(params.otherDps))
  else
    notes[#notes + 1] = "Nincs rögzített harc, ezért tankönyvi értékekkel számol. Kapcsold be a harcnaplót (/wa log) a kalibráláshoz."
  end
  notes[#notes + 1] = "A manát és a gyógyítást a modell nem számolja."

  local unbuffed = PA.Dps(sheet, params)
  local buffs = M.ResolveBuffs(level, input.buffs, input.data)
  local bAgi, bStr, bAp, bCrit, bSp, pct = 0, 0, 0, 0, 0, 0
  for _, b in ipairs(buffs) do
    if b.selected and b.effect then
      bAgi, bStr, bAp, bCrit = bAgi + (b.effect.agi or 0), bStr + (b.effect.str or 0), bAp + (b.effect.ap or 0), bCrit + (b.effect.crit or 0)
      bSp = bSp + (b.effect.sp or 0)
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
  sheet.sp = sheet.sp + bSp
  local baseline = PA.Dps(sheet, params)
  local equippedIds = {}
  for _, it in pairs(equipped) do if it.id then equippedIds[it.id] = true end end
  local skills = input.skills

  local ctx = M.Common({
    level = level, baseline = baseline, unbuffed = unbuffed, buffs = buffs, params = params, sheet = sheet,
    equipped = equipped, equippedIds = equippedIds, combat = combat, slotOrder = input.slotOrder,
  }, "PALADIN")

  -- one weapon (paladins do not dual wield) and a shield in the off hand
  function ctx.score(add, slots, twoHand2, sub)
    local best
    if add.weapon then
      add.weapon = { min = add.weapon.min, max = add.weapon.max, speed = add.weapon.speed, twoHand = twoHand2 == true,
        norm = M.NormalizedSpeed(sub, twoHand2) }
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
      if slot == "MAIN_HAND" then sh.mh = add.weapon or sh.mh
      elseif slot == "OFF_HAND" and add.weapon then ok = false end
      if ok then
        local gain = PA.Dps(sh, params) - baseline
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
    if (add.sp or 0) ~= 0 then bits[#bits + 1] = ("+%s spell power"):format(add.sp) end
    return table.concat(bits, ", ")
  end

  function ctx.buffGain(e)
    local add = { agi = e.agi or 0, str = e.str or 0, ap = e.ap or 0, crit = e.crit or 0, sp = e.sp or 0 }
    local sh = Apply(sheet, M.ZERO, add, params)
    return PA.Dps(sh, params) - baseline
  end

  function ctx.weaponWarning(itemClass, sub)
    if itemClass ~= 2 or not skills or not next(skills) then return nil end
    local line = M.WEAPON_SKILLS[sub]
    local s = line and skills[line]
    if not line then return nil end
    if not s then return ("%s nincs kitanulva"):format(line) end
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

function PA.Sources(abilities, total)
  local out = { melee = 0, hs = 0, seal = 0, judgement = 0, other = 0 }
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

PA.ManaItems = function(fights) return WA.Mage.ManaItems(fights) end

local GRADES = { { 90, "S" }, { 80, "A" }, { 65, "B" }, { 50, "C" }, { 0, "D" } }
function PA.Score(f, ctx)
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
  local mh = ctx and ctx.sheet and ctx.sheet.mh
  if dur >= 6 and mh then
    local melee = Find(ab, "Melee")
    local swings = melee and melee.n or 0
    local up = math.min(1, swings * mh.speed / dur)
    Part("melee", "Folyamatosan ütsz", math.min(up / 0.9, 1) * 20, 20, ("a harc kb. %d%%-ában ütöttél (%d ütés, %s mp-es fegyver)"):format(
      Round(up * 100), swings, F1(mh.speed)))
  end
  local lv = (f.level or 0) > 0 and f.level or (ctx and ctx.level) or 0
  if dur >= 10 and lv >= 6 then
    local hs = Find(ab, "Holy Strike")
    local n = hs and hs.n or 0
    -- 10 s cooldown: the most that fits is one at the pull and one every 10 s after
    local most = 1 + math.floor(dur / PA.HS_CD)
    Part("hs", "Holy Strike cooldownra", math.min(n / most / 0.8, 1) * 15, 15, ("%d Holy Strike, a %s mp-es harcba legfeljebb %d fér (10 mp cooldown, Wowhead Forever)"):format(n, F1(dur), most))
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

function PA.Summary(r, ctx, fights)
  if not r then return nil end
  local src, share = PA.Sources(r.abilities, r.damage)
  local secs = r.seconds
  local s = { sources = src, shares = share, seconds = secs, dps = r.dps, rows = {}, mana = PA.ManaItems(fights) }
  local melee = Find(r.abilities, "Melee")
  if melee then
    local n = melee.n
    s.melee = { n = n, miss = n > 0 and (melee.miss or 0) / n * 100 or 0, dodge = n > 0 and ((melee.dodge or 0) + (melee.parry or 0)) / n * 100 or 0,
      crit = n > 0 and (melee.crit or 0) / n * 100 or 0, glance = n > 0 and (melee.glance or 0) / n * 100 or 0 }
  end
  local hs = Find(r.abilities, "Holy Strike")
  s.hsCpm = hs and hs.n / secs * 60 or 0
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

function PA.Advise(r, fights)
  local C = WA.Combat
  local out = {}
  local function Push(o) out[#out + 1] = C.Finding(o) end
  if r.seconds < 300 then
    Push({ info = true, title = "Kevés még az adat", fact = ("Eddig %d harc és %d másodperc van rögzítve. Az arányok kb. 10 perc harc után megbízhatóak.")
      :format(r.fights, Round(r.seconds)) })
  end
  local _, share = PA.Sources(r.abilities, r.damage)
  local items = PA.ManaItems(fights)
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
  end
  local melee = Find(r.abilities, "Melee")
  if r.seconds >= 300 and melee and melee.n >= 100 and share.seal < 1 then
    Push({ title = "Nem sebez seal", rule = "sealDamage",
      fact = ("A harcaidban %d fehér ütés van, de a Seal of Command és a Seal of Righteousness sebzése a teljes sebzésed %s%%-a."):format(melee.n, F1(share.seal)),
      advice = "Sebzéshez Seal of Righteousness vagy (Retribution talenttel) Seal of Command kell. A Seal of Wisdom, Light vagy Justice nem sebez.",
      missing = "melyik seal volt rajtad (a harcnapló aura-eseményeit az addon nem rögzíti)" })
  end
  local hs = Find(r.abilities, "Holy Strike")
  if r.seconds >= 300 then
    Push({ info = true, title = "Holy Strike a cooldownhoz képest",
      fact = ("%s Holy Strike percenként; 10 mp-es cooldownnal legfeljebb 6 lehet (Wowhead Forever spell=679). A rövid harcokban ennyi nem is fér bele.")
        :format(F1(hs and hs.n / r.seconds * 60 or 0)) })
  end
  if r.seconds >= 120 then
    Push({ info = true, title = "Mért arányok", fact = ("Sebzés: fehér ütés %d%%, Holy Strike %d%%, seal %d%%, Judgement %d%%, egyéb (Consecration, Exorcism, aura...) %d%%.")
      :format(Round(share.melee), Round(share.hs), Round(share.seal), Round(share.judgement), Round(share.other)) })
  end
  return out
end
