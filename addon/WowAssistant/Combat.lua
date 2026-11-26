-- WoW Assistant: combat statistics and advice, ported from the web app (combatReport in src/combat.ts).
--
-- Fights come from two places:
--   * WowAssistantFights (Fights.lua, written into the addon folder by scripts/uploader.mjs from
--     the game's combat log): the same fights the web app shows, read at login or /reload;
--   * Meter.lua: fights seen live in this session through the client's damage meter, as far as
--     the client lets an addon read it.
-- Fight: { start, dur, dmg, target, targetLevel, level, capped, samples, source,
--          ab = { { name, n, dmg, hit, crit, glance, miss, dodge, parry, block, other, max }, ... },
--          casts = { { t, spell, cost, cp }, ... }, auras = { { name, seconds }, ... } }

local _, WA = ...
WA = WA or {}
local C = {}
WA.Combat = C

local FIELDS = { "n", "dmg", "hit", "crit", "glance", "miss", "dodge", "parry", "block", "other", "max" }
local FINISHERS = { Eviscerate = true, ["Slice and Dice"] = true, Rupture = true, ["Kidney Shot"] = true, ["Expose Armor"] = true }
local OFFHAND_MISS = "Melee (off hand miss)"
local function White(name) return name == "Melee" end
local function Dot(name) return name:sub(-6) == " (dot)" end
local function Empty() local t = {} for _, k in ipairs(FIELDS) do t[k] = 0 end return t end
local function Add(into, a)
  for _, k in ipairs(FIELDS) do
    if k == "max" then into.max = math.max(into.max, tonumber(a.max) or 0)
    else into[k] = into[k] + (tonumber(a[k]) or 0) end
  end
end
local function Pct(part, whole) return whole > 0 and part / whole * 100 or 0 end
local function F1(n) return ("%.1f"):format(n) end

-- Newest first, at most `limit` (200 in the web app). `advise` replaces the rogue advice
-- (WA.Hunter.Advise for hunters).
function C.Report(fights, limit, advise)
  limit = limit or 200
  local list = {}
  for _, f in ipairs(fights or {}) do if (f.start or 0) > 0 and (f.dur or 0) > 0 then list[#list + 1] = f end end
  table.sort(list, function(a, b) return a.start > b.start end)
  while #list > limit do table.remove(list) end
  if #list == 0 then return nil end

  local abilities, order = {}, {}
  local white, yellow = Empty(), Empty()
  local cp, cpOrder, auraSecs, auraOrder, byLevel, lvOrder = {}, {}, {}, {}, {}, {}
  local seconds, damage, capped, samples, offhandMiss = 0, 0, 0, 0, 0
  for _, f in ipairs(list) do
    seconds = seconds + f.dur
    damage = damage + f.dmg
    capped = capped + (f.capped or 0)
    samples = samples + (f.samples or 0)
    local fn, fmiss = 0, 0
    for _, a in ipairs(f.ab or {}) do
      local name = a.name
      if name == OFFHAND_MISS then
        offhandMiss = offhandMiss + (tonumber(a.n) or 0)
      else
        local into = abilities[name]
        if not into then into = Empty() abilities[name] = into order[#order + 1] = name end
        Add(into, a)
        if White(name) then Add(white, a) elseif not Dot(name) then Add(yellow, a) end
        if White(name) then fn = fn + (a.n or 0) fmiss = fmiss + (a.miss or 0) end
      end
    end
    for _, c in ipairs(f.casts or {}) do
      local name = c[2]
      if FINISHERS[name] then
        local e = cp[name]
        if not e then e = { casts = 0, cp = 0 } cp[name] = e cpOrder[#cpOrder + 1] = name end
        e.casts = e.casts + 1
        e.cp = e.cp + (tonumber(c[4]) or 0)
      end
    end
    for _, a in ipairs(f.auras or {}) do
      if auraSecs[a[1]] == nil then auraOrder[#auraOrder + 1] = a[1] end
      auraSecs[a[1]] = (auraSecs[a[1]] or 0) + a[2]
    end
    if f.targetLevel and f.level and f.targetLevel > 0 then
      local diff = f.targetLevel - f.level
      local e = byLevel[diff]
      if not e then e = { fights = 0, dmg = 0, dur = 0, n = 0, miss = 0 } byLevel[diff] = e lvOrder[#lvOrder + 1] = diff end
      e.fights, e.dmg, e.dur, e.n, e.miss = e.fights + 1, e.dmg + f.dmg, e.dur + f.dur, e.n + fn, e.miss + fmiss
    end
  end

  local rows = {}
  for _, name in ipairs(order) do
    local a = abilities[name]
    local row = { name = name, share = Pct(a.dmg, damage), avg = (a.hit + a.crit + a.glance) > 0 and a.dmg / (a.hit + a.crit + a.glance) or 0 }
    for _, k in ipairs(FIELDS) do row[k] = a[k] end
    rows[#rows + 1] = row
  end
  WA.Model.Stable(rows, function(a, b) return a.dmg > b.dmg end)
  local function Landed(a) return a.hit + a.crit + a.glance end

  local r = {
    fights = #list, seconds = seconds, damage = damage, dps = damage / seconds, abilities = rows,
    white = { landed = Landed(white), n = white.n, miss = Pct(white.miss, white.n), dodge = Pct(white.dodge, white.n),
      parry = Pct(white.parry, white.n), glance = Pct(white.glance, white.n), crit = Pct(white.crit, white.n) },
    yellow = { n = yellow.n, miss = Pct(yellow.miss, yellow.n), dodge = Pct(yellow.dodge, yellow.n),
      parry = Pct(yellow.parry, yellow.n), crit = Pct(yellow.crit, Landed(yellow)) },
    energyCappedPct = samples > 0 and Pct(capped, samples) or nil,
    offhandMissSharePct = (white.n - Landed(white)) > 0 and Pct(offhandMiss, white.n - Landed(white)) or nil,
    finishers = {}, auras = {}, byLevel = {}, recent = {},
  }
  for _, name in ipairs(cpOrder) do
    r.finishers[#r.finishers + 1] = { name = name, casts = cp[name].casts, avgCp = cp[name].cp / cp[name].casts }
  end
  for _, name in ipairs(auraOrder) do
    r.auras[#r.auras + 1] = { name = name, uptimePct = math.min(100, Pct(auraSecs[name], seconds)) }
  end
  WA.Model.Stable(r.auras, function(a, b) return a.uptimePct > b.uptimePct end)
  while #r.auras > 12 do table.remove(r.auras) end
  for _, diff in ipairs(lvOrder) do
    local e = byLevel[diff]
    r.byLevel[#r.byLevel + 1] = { diff = diff, fights = e.fights, dps = e.dmg / e.dur, missPct = Pct(e.miss, e.n) }
  end
  WA.Model.Stable(r.byLevel, function(a, b) return a.diff < b.diff end)
  for i = 1, math.min(15, #list) do
    local f = list[i]
    r.recent[i] = { start = f.start, dur = f.dur, dps = f.dmg / f.dur, target = f.target or "?", targetLevel = f.targetLevel, source = f.source }
  end
  r.advice = (advise or C.Advise)(r, list)
  return r
end

function C.Advise(r, fights)
  local out = {}
  local function Push(level, title, text) out[#out + 1] = { level = level, title = title, text = text } end
  if r.seconds < 300 or r.white.n < 150 then
    Push("info", "Kevés még az adat", ("Eddig %d harc, %d másodperc és %d auto-attack van rögzítve. "):format(r.fights, math.floor(r.seconds + 0.5), r.white.n) ..
      "Az arányok kb. 10 perc harc után kezdenek megbízhatóak lenni.")
  end
  if r.energyCappedPct and r.energyCappedPct > 8 then
    Push("fix", "Energia megy kárba", ("A harcidő %s%%-ában tele energiával állsz. Minden másodperc a plafonon 10 elveszett energia, "):format(F1(r.energyCappedPct)) ..
      "vagyis kb. negyed Sinister Strike. Harc elején azonnal üss, és ne tartogasd az energiát 80 fölött.")
  end
  local evis
  for _, f in ipairs(r.finishers) do if f.name == "Eviscerate" then evis = f end end
  if evis and evis.casts >= 5 and evis.avgCp < 4 then
    Push("fix", "Túl korán ütöd az Eviscerate-et", ("Az Eviscerate-jeid átlagosan %s combo ponttal mennek (%d használat). "):format(F1(evis.avgCp), evis.casts) ..
      "A sebzése combo pontonként nő, az energiaára viszont fix, ezért 4–5 ponttal éri meg; kivétel, ha a mob 1–2 ponttal is meghal tőle.")
  end
  local avgFight = r.seconds / r.fights
  local snd
  for _, a in ipairs(r.auras) do if a.name == "Slice and Dice" then snd = a end end
  if avgFight >= 12 and (not snd or snd.uptimePct < 50) then
    local whiteShare = 0
    for _, a in ipairs(r.abilities) do if White(a.name) then whiteShare = whiteShare + a.share end end
    Push("fix", "Slice and Dice alig van fent", ("A Slice and Dice a harcidő %s%%-ában aktív, miközben a sebzésed %s%%-a auto-attack. ")
      :format(snd and F1(snd.uptimePct) or "0", F1(whiteShare)) ..
      "Az átlagos harcod elég hosszú ahhoz, hogy az első 1–2 combo pontot Slice and Dice-ra költsd, és utána gyűjts Eviscerate-re.")
  end
  local parried, swings = 0, 0
  for _, a in ipairs(r.abilities) do
    parried = parried + a.parry
    if not Dot(a.name) then swings = swings + a.n end
  end
  local parry = Pct(parried, swings)
  if parry > 2 then
    Push("tip", "Sok ütésedet hárítják", ("Az ütéseid %s%%-át parryzik. A mobok csak szemből tudnak parryzni és blokkolni, "):format(F1(parry)) ..
      "tehát csapatban (dungeonben) állj a célpont mögé. Szólóban ez nem kerülhető el, de egy Gouge utáni helyezkedés segít.")
  end
  if r.white.n >= 150 then
    Push("info", "Mért találati arányok", ("Auto-attack: %s%% miss, %s%% dodge, %s%% glancing, %s%% crit. Képességek: %s%% miss, %s%% crit. ")
      :format(F1(r.white.miss), F1(r.white.dodge), F1(r.white.glance), F1(r.white.crit), F1(r.yellow.miss), F1(r.yellow.crit)) ..
      (r.white.miss > 15 and "A fehér ütések ötöde-hatoda elvész, ezért a +hit tárgyak neked sokat érnek." or "A miss arány rendben van."))
  end
  if r.white.glance > 20 then
    Push("tip", "Sok a glancing ütés", ("Az auto-attackjeid %s%%-a glancing. Ez nálad magasabb szintű mobokon és alacsony fegyverskillnél jön elő: "):format(F1(r.white.glance)) ..
      "ha nemrég váltottál fegyvertípust, a skill felhúzása ingyen DPS.")
  end
  local hasPoison = false
  for _, a in ipairs(r.abilities) do if a.name:lower():find("poison", 1, true) then hasPoison = true end end
  local level = fights[1] and fights[1].level or 0
  if not hasPoison and level >= 20 and r.seconds >= 120 then
    Push("tip", "Nincs méreg a fegyvereiden", "A rögzített harcokban egyetlen méreg-sebzés sincs. Classic alapján 20-as szinttől elérhető az Instant Poison " ..
      "(a Forever-beli feltételt nem ellenőriztem); ha megvan, mindkét fegyverre tedd fel, a gyors balkezes fegyveren ér a legtöbbet.")
  end
  local ss, melee
  for _, a in ipairs(r.abilities) do
    if a.name == "Sinister Strike" and not ss then ss = a end
    if a.name == "Melee" and not melee then melee = a end
  end
  if ss and melee then
    Push("info", "Sebzésmegoszlás", ("Sinister Strike %s%% (átlag %d), auto-attack %s%% (átlag %d). ")
      :format(F1(ss.share), math.floor(ss.avg + 0.5), F1(melee.share), math.floor(melee.avg + 0.5)) ..
      "A Sinister Strike a főkezes fegyver sebzéséből számol, ezért oda a lassú, nagy sebzésű fegyver való, a balkézbe a gyors.")
  end
  return out
end

-- Score of one fight, 0-100, from what a rogue controls. `baseline` is the damage model's
-- expected DPS for your gear (nil when the model has none: then that part is left out and the
-- rest is scaled up). Parts: { key, label, points, max, text }.
local GRADES = { { 90, "S" }, { 80, "A" }, { 65, "B" }, { 50, "C" }, { 0, "D" } }
function C.Score(f, baseline)
  local parts = {}
  local function Part(key, label, got, max, text) parts[#parts + 1] = { key = key, label = label, points = got, max = max, text = text } end
  local dur = f.dur or 0
  local dps = dur > 0 and (f.dmg or 0) / dur or 0
  if baseline and baseline > 0 then
    local ratio = dps / baseline
    Part("dps", "DPS a várthoz képest", math.min(ratio / 1.1, 1) * 40, 40, ("%d DPS, a felszerelésedtől várt %d %d%%-a"):format(
      math.floor(dps + 0.5), math.floor(baseline + 0.5), math.floor(ratio * 100 + 0.5)))
  end
  if (f.samples or 0) > 0 then
    local pct = (f.capped or 0) / f.samples * 100
    Part("energy", "Energia nem megy kárba", (1 - math.min(pct / 20, 1)) * 20, 20, ("az idő %s%%-ában volt tele az energiád"):format(F1(pct)))
  end
  local fin, cps, evis, evisCp = 0, 0, 0, 0
  local casts = f.casts or {}
  for _, c in ipairs(casts) do
    if FINISHERS[c[2]] then
      fin, cps = fin + 1, cps + (tonumber(c[4]) or 0)
      if c[2] == "Eviscerate" then evis, evisCp = evis + 1, evisCp + (tonumber(c[4]) or 0) end
    end
  end
  if evis > 0 then
    local avg = evisCp / evis
    Part("finisher", "Eviscerate elég combo ponttal", math.max(0, math.min((avg - 2) / 3, 1)) * 20, 20,
      ("%d Eviscerate, átlag %s combo ponttal"):format(evis, F1(avg)))
  elseif fin > 0 then
    Part("finisher", "Finisherek", 15, 20, ("%d finisher, átlag %s combo ponttal"):format(fin, F1(cps / fin)))
  end
  if dur >= 15 then
    local snd = 0
    for _, a in ipairs(f.auras or {}) do if a[1] == "Slice and Dice" then snd = a[2] end end
    local pct = math.min(100, snd / dur * 100)
    Part("snd", "Slice and Dice fent", math.min(pct / 60, 1) * 10, 10, ("a harc %d%%-ában"):format(math.floor(pct + 0.5)))
  end
  if dur >= 6 and #casts > 0 then
    local perMin = #casts / dur * 60
    Part("active", "Folyamatos ütés", math.min(perMin / 12, 1) * 10, 10, ("%s képesség percenként"):format(F1(perMin)))
  end
  local got, max = 0, 0
  for _, p in ipairs(parts) do got, max = got + p.points, max + p.max end
  if max == 0 then return nil end
  local total = math.floor(got / max * 100 + 0.5)
  local grade = "D"
  for _, g in ipairs(GRADES) do if total >= g[1] then grade = g[2] break end end
  return { total = total, grade = grade, parts = parts, dps = dps }
end

