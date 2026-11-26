-- WoW Assistant: combat statistics and advice, ported from the web app (combatReport in src/combat.ts).
--
-- Fights come from two places:
--   * WowAssistantFights (Fights.lua, written into the addon folder by scripts/uploader.mjs from
--     the game's combat log): the same fights the web app shows, read at login or /reload;
--   * Meter.lua: fights seen live in this session through the client's damage meter, as far as
--     the client lets an addon read it.
-- Fight: { start, dur, dmg, target, targetLevel, level, capped, samples, source,
--          ab = { { name, n, dmg, hit, crit, glance, miss, dodge, parry, block, other, max }, ... },
--          casts = { { t, spell, cost, cp }, ... }, auras = { { name, seconds }, ... },
--          pet, basis = { dmg, dur, pet }, gear, sessionID }   (the last ones from 2.8.0 on)

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
  local evisSeen, evisProven, evisJustified, evisUnchecked = 0, {}, 0, 0
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
    if type(f.evis) == "table" then
      for _, e in ipairs(f.evis) do
        evisSeen = evisSeen + 1
        local proof = C.EvisMistake(e)
        local low = (tonumber(e.cp) or 0) >= 1 and (tonumber(e.cp) or 0) <= 2 and e.landed ~= false
        if proof == true then evisProven[#evisProven + 1] = { start = f.start, e = e }
        elseif proof == false then evisJustified = evisJustified + 1
        elseif low then evisUnchecked = evisUnchecked + 1 end
      end
    else
      -- a fight without the data (an older log, or the live meter): its low-point casts are unchecked
      for _, c in ipairs(f.casts or {}) do
        local n = tonumber(c[4]) or 0
        if c[2] == "Eviscerate" and n >= 1 and n <= 2 then evisUnchecked = evisUnchecked + 1 end
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
    evis = { seen = evisSeen, proven = evisProven, justified = evisJustified, unchecked = evisUnchecked },
    cooldowns = C.CooldownUsage(list),
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

-- Cooldown usage: how much of the fight time an ability with a real cooldown spent recharging,
-- by the WoWAnalyzer method (CastEfficiency, the normal one-charge branch):
--   usage = (finished recharges + the recharge still running at the fight's end + countable cast
--   time and GCD waits after a reset) / the observed fight time.
-- Only abilities whose Forever cooldown is checked (Wowhead Forever, 2026-11-26) and only the
-- fights after the first one where it was cast (before that it may not have been learned).
-- All of these are instant and nothing resets them, so the cast time and the GCD wait are 0. A
-- cooldown still running from the previous fight counts from the pull. Reactive abilities
-- (Riposte after a parry, Kick on a spellcast) are left out: their availability is an event, so
-- recharge time does not say what could have been used.
-- Only log fights count: the live meter's fights record casts too, but their duration comes from
-- the meter session and their cast times from the combat clock, which need not line up.
C.COOLDOWNS = {
  { name = "Shank", cd = 10, source = "Wowhead Forever spell=1329283 (10 mp; mellékkéz-fegyver kell)" },
  { name = "Blade Flurry", cd = 120, source = "Wowhead Forever spell=13877 (2 perc)" },
  { name = "Kidney Shot", cd = 20, source = "Wowhead Forever spell=408 (20 mp)" },
  { name = "Arcane Shot", cd = 6, source = "Wowhead Forever spell=3044 (6 mp)" },
  { name = "Shock", cd = 6, spells = { ["Earth Shock"] = true, ["Flame Shock"] = true, ["Frost Shock"] = true },
    source = "Wowhead Forever spell=8042 (6 mp, a három shock közös cooldownja: WoWSims Forever d5144855 sim/shaman/shocks.go)" },
  { name = "Stormstrike", cd = 8, source = "Wowhead Forever spell=17364 (8 mp)" },
}
C.CD_METHOD = "WoWAnalyzer CastEfficiency (19e94d2d), normál cooldownos ág"

-- usage for one ability over fights (any order); each fight { start, dur, casts = {{t*10, name}, ...} }
function C.CooldownUse(fights, spec)
  local list = {}
  for _, f in ipairs(fights) do
    if type(f.casts) == "table" and #f.casts > 0 and (tonumber(f.dur) or 0) > 0 and f.source ~= "live" and f.source ~= "meter" then
      list[#list + 1] = f
    end
  end
  table.sort(list, function(a, b) return (a.start or 0) < (b.start or 0) end)
  local function Is(name) return spec.spells and spec.spells[name] or name == spec.name end
  local first
  for i, f in ipairs(list) do
    for _, c in ipairs(f.casts) do if Is(c[2]) then first = i break end end
    if first then break end
  end
  if not first then return nil end
  local cd = spec.cd
  local seconds, active, casts, fights, carried = 0, 0, 0, 0, 0
  local readyAt -- absolute time the ability is ready again
  for i = first, #list do
    local f = list[i]
    local start, dur = f.start or 0, f.dur
    fights, seconds = fights + 1, seconds + dur
    local busyUntil = 0 -- seconds into this fight up to which the cooldown was running
    if readyAt and readyAt > start then
      busyUntil = math.min(dur, readyAt - start)
      active, carried = active + busyUntil, carried + busyUntil
    end
    for _, c in ipairs(f.casts) do
      if Is(c[2]) then
        local t = (tonumber(c[1]) or 0) / 10
        casts = casts + 1
        local from = math.max(t, busyUntil) -- log timestamps can overlap the previous recharge by a tick
        local to = math.min(dur, t + cd)
        if to > from then active = active + (to - from) busyUntil = to end
        readyAt = start + t + cd
      end
    end
  end
  return { name = spec.name, cd = cd, casts = casts, fights = fights, seconds = seconds, active = active, carried = carried,
    pct = seconds > 0 and active / seconds * 100 or nil, source = spec.source }
end

function C.CooldownUsage(fights)
  local out = {}
  for _, spec in ipairs(C.COOLDOWNS) do
    local u = C.CooldownUse(fights, spec)
    if u then out[#out + 1] = u end
  end
  return out
end

-- Findings: what the advice may say about you.
--
-- A finding states a measured fact. It may call something a mistake of yours ("hiba", red) only
-- when both hold: the rule behind it is verified for Forever (RULES[key].verified), and the
-- state the decision depended on is known from the events (nothing in `missing`). Otherwise the
-- fact stays a "megfigyelés", and a would-be mistake is "nem megállapítható", with what is
-- missing spelled out.
--
-- Verified (2026-11-26) against the WoWSims Forever engine at commit d5144855 (the mechanics) and
-- Wowhead's Forever spell data (costs, cooldowns, levels, effects). `source` says where.
local SIM = "WoWSims Forever d5144855 "
local WH = "Wowhead Forever spell="
C.RULES = {
  energyCap = { text = "teli energiánál a regenerálódó energia elvész", verified = true,
    source = SIM .. "sim/core/energy.go:111 (új energia = min(jelenlegi + kapott, maximum))" },
  evisCp = { text = "az Eviscerate sebzése combo pontonként nő (pontonként fix sebzés + 4% AP), az ára fix 35 energia", verified = true,
    source = SIM .. "sim/rogue/eviscerate.go; " .. WH .. "2098" },
  sndHaste = { text = "a Slice and Dice 20%-kal gyorsítja a közelharci támadást, combo pontonként 3 mp-cel tovább tart (10-től)", verified = true,
    source = SIM .. "sim/rogue/slice_and_dice.go; " .. WH .. "5171" },
  parryFront = { text = "parry és block csak akkor lehet, ha a célpont előtt állsz", verified = true,
    source = SIM .. "sim/core/spell_outcome.go (InFrontOfTarget feltétel)" },
  poison20 = { text = "az Instant Poison 20-as szinttől tehető a fegyverre", verified = true,
    source = WH .. "8679" },
  glanceSkill = { text = "a glancing esélye azonos szintű célponton is 10%, és 2%-kal nő minden fegyverskill-pontért, ami a célpont szintje × 5-höz hiányzik", verified = true,
    source = SIM .. "sim/core/target.go:577" },
  hitGear = { text = "minden 1% hit 1%-kal csökkenti a miss esélyét", verified = true,
    source = SIM .. "sim/core/spell_outcome.go:660" },
  hunterPet = { text = "10-től (Tame Beast) a hunternek pet-je lehet, amely külön támad", verified = true,
    source = WH .. "1515; " .. SIM .. "sim/hunter/pets.go" },
  hunterRange = { text = "a hunter lövései 8 yardon belül nem használhatók (8–35 yd)", verified = true,
    source = WH .. "3044" },
  serpentSting = { text = "a Serpent Sting 15 mp alatt sebez (4-től)", verified = true,
    source = WH .. "1978; " .. SIM .. "sim/hunter/serpent_sting.go" },
  arcaneShot = { text = "az Arcane Shot azonnali lövés 6 mp cooldownnal (6-tól)", verified = true,
    source = WH .. "3044; " .. SIM .. "sim/hunter/arcane_shot.go" },
  hawk = { text = "az Aspect of the Hawk ranged attack powert ad (10-től)", verified = true,
    source = WH .. "13165" },
  -- a playstyle, not a game rule: it cannot be verified, only measured
  shamanMelee = { text = "az enhancement shaman sebzésének nagyja a fegyver", verified = false,
    source = "játékstílus, nem játékszabály: nem ellenőrizhető" },
  earthShock = { text = "az Earth Shock azonnali sebzés; a három shock közös, 6 mp-es cooldownon van (4-től)", verified = true,
    source = SIM .. "sim/shaman/shocks.go; " .. WH .. "8042" },
  searingTotem = { text = "a Searing Totem 30 mp-ig támad egy 20 yardon belüli ellenfelet (10-től)", verified = true,
    source = WH .. "3599" },
  windfury = { text = "a Windfury Weapon (30-tól) minden találatnál 20% eséllyel 2 extra támadást ad, plusz attack powerrel", verified = true,
    source = WH .. "8232; " .. SIM .. "sim/shaman/weapon_imbues.go" },
  lightningShield = { text = "a Lightning Shield megsebzi azt, aki megüt (8-tól)", verified = true,
    source = WH .. "324" },
}
C.FINDING = { fault = "hiba", observation = "megfigyelés", unproven = "nem megállapítható", data = "mért adat" }
local GREY = "|cff9d9d9d"

-- o = { title, fact, advice (what to try, conditionally), rule (a RULES key), missing (what the
-- events do not show), fault (true when the finding would blame you), info (plain data) }
function C.Finding(o)
  local rule = o.rule and C.RULES[o.rule]
  local status, level
  if o.info then status, level = C.FINDING.data, "info"
  elseif o.fault and rule and rule.verified and not o.missing then status, level = C.FINDING.fault, "fix"
  elseif o.fault then status, level = C.FINDING.unproven, "tip"
  else status, level = C.FINDING.observation, "tip" end
  local why
  if status == C.FINDING.fault then
    why = "Hiba, mert: " .. rule.text .. " (Foreverre ellenőrzött szabály), és a harcadat mutatja a döntés helyzetét."
  elseif status == C.FINDING.unproven then
    local bits = {}
    if o.missing then bits[#bits + 1] = "a harcadatból nem látszik " .. o.missing end
    if rule and not rule.verified then bits[#bits + 1] = "a szabály (" .. rule.text .. ") Foreverre nincs ellenőrizve" end
    if rule and rule.verified then bits[#bits + 1] = "a szabály maga ellenőrzött (" .. rule.text .. ")" end
    why = "Hibának nem megállapítható: " .. table.concat(bits, "; ") .. "."
  elseif rule then
    why = "Szabály: " .. rule.text .. (rule.verified and " (Foreverre ellenőrizve)." or " (Foreverre nincs ellenőrizve).")
  end
  local text = o.fact .. (o.advice and (" " .. o.advice) or "") .. (why and ("\n" .. GREY .. why .. "|r") or "")
  return { level = level, title = o.title, text = text, status = status, fact = o.fact, rule = o.rule, missing = o.missing,
    source = rule and rule.source or nil }
end

-- A low-point Eviscerate is a proven mistake only when the log shows all of it (fight.evis, from
-- the uploader): it spent 1-2 combo points, it hit and the target survived, no roll of it could
-- have killed, and the target lived at least EVIS_ROOM more seconds - two Sinister Strikes' worth
-- of energy, time to build more points.
-- "No roll could have killed": in WoWSims Forever (d5144855 sim/rogue/eviscerate.go) only the
-- rank's base points are rolled; the per-point damage and 4% AP per point add on top, so the
-- highest roll is at most EVIS_SPREAD x the lowest (the base range's max/min; Forever's rank
-- ranges are not published, Classic's are at most about 1.8, so 2 is the safe bound). With a crit
-- (x2) on top: the target must have had more than 4x the hit's non-crit damage (blocked part added
-- back). Returns true (proven), false (low points, but a kill or an excuse the log shows), or nil
-- (not a low-point cast, or the state is not known).
C.EVIS_ROOM = 8
C.EVIS_SPREAD = 2
function C.EvisKillable(e)
  local dmg = (tonumber(e.dmg) or 0) + (tonumber(e.blocked) or 0)
  local normal = e.crit and dmg / 2 or dmg
  return normal * C.EVIS_SPREAD * 2
end
function C.EvisMistake(e)
  local cp = tonumber(e.cp)
  if not cp or cp < 1 or cp > 2 then return nil end
  if e.landed == false then return nil end
  if e.killed then return false end
  local hp, dmg, lived = tonumber(e.hpBefore), tonumber(e.dmg), tonumber(e.lived)
  if not hp or not dmg or not lived then return nil end
  if hp <= C.EvisKillable(e) or lived < C.EVIS_ROOM then return false end
  return true
end

local function Clock(start, tenths)
  local s = (start or 0) + (tonumber(tenths) or 0) / 10
  return date and date("%m.%d. %H:%M:%S", math.floor(s)) or tostring(math.floor(s))
end

function C.Advise(r, fights)
  local out = {}
  local function Push(o) out[#out + 1] = C.Finding(o) end
  if r.seconds < 300 or r.white.n < 150 then
    Push({ info = true, title = "Kevés még az adat", fact = ("Eddig %d harc, %d másodperc és %d auto-attack van rögzítve. "):format(r.fights, math.floor(r.seconds + 0.5), r.white.n) ..
      "Az arányok kb. 10 perc harc után kezdenek megbízhatóak lenni." })
  end
  if r.energyCappedPct and r.energyCappedPct > 8 then
    Push({ title = "Sokszor tele az energiád", fault = true, rule = "energyCap",
      fact = ("A harcidő %s%%-ában tele energiával álltál (félmásodperces minták, illetve a harcnapló energiaértékei)."):format(F1(r.energyCappedPct)),
      advice = "Ha közben ütni tudtál volna, harc elején azonnal üss, és ne tartogasd az energiát 80 fölött.",
      missing = "hogy akkor volt-e használható képességed (távolság, stun, futó vagy elérhetetlen célpont)" })
  end
  local evis
  for _, f in ipairs(r.finishers) do if f.name == "Eviscerate" then evis = f end end
  local ev = r.evis or { seen = 0, proven = {}, justified = 0, unchecked = 0 }
  ev.unchecked = ev.unchecked or 0
  if #ev.proven > 0 then
    local lines = {}
    for i = 1, math.min(3, #ev.proven) do
      local p, e = ev.proven[i], ev.proven[i].e
      lines[i] = ("%s, %s: %d pont, életereje előtte %d / %s, a sebzés %d%s, utána még %s%s mp-ig élt"):format(
        Clock(p.start, e.t), e.target or "?", e.cp, e.hpBefore, e.maxHp and tostring(e.maxHp) or "?", e.dmg, e.crit and " (krit)" or "",
        e.livedKnown and "" or "legalább ", F1(e.lived))
    end
    Push({ title = "Kevés combo pontos Eviscerate", fault = true, rule = "evisCp",
      fact = ("%d Eviscerate ment 1–2 combo ponttal úgy, hogy a célpont nem halt meg tőle, több mint négyszer annyi életereje maradt, mint az ütés normál sebzése (a legnagyobb dobás krittel sem ölt volna), és utána még legalább %d mp-ig élt (harcnapló):\n- %s%s%s")
        :format(#ev.proven, C.EVIS_ROOM, table.concat(lines, "\n- "), #ev.proven > 3 and ("\n- … és még " .. (#ev.proven - 3)) or "",
          ev.unchecked > 0 and ("\nTovábbi " .. ev.unchecked .. " kevés pontosnál a célpont élete nem látszik.") or ""),
      advice = "Ilyenkor építs még 1–2 pontot: az ára ugyanaz a 35 energia, a sebzése pontonként nő." })
  elseif evis and evis.casts >= 5 and evis.avgCp < 4 and ev.unchecked == 0 and ev.justified > 0 then
    Push({ title = "Kevés pontos Eviscerate, de indokolt", rule = "evisCp",
      fact = ("Az Eviscerate-jeid átlagosan %s combo ponttal mentek. Mind a %d darab 1–2 pontos ellenőrizhető volt a harcnaplóban, és egyik sem volt hiba: ölt, kevés életerejű célpontra ment, vagy a célpont hamar meghalt.")
        :format(F1(evis.avgCp), ev.justified) })
  elseif evis and evis.casts >= 5 and evis.avgCp < 4 then
    Push({ title = "Kevés combo pontos Eviscerate", fault = true, rule = "evisCp",
      fact = ("Az Eviscerate-jeid átlagosan %s combo ponttal mentek (%d használat)."):format(F1(evis.avgCp), evis.casts) ..
        (ev.justified > 0 and (" Az 1–2 pontosak közül %d a harcnapló szerint indokolt volt, %d nem ellenőrizhető."):format(ev.justified, ev.unchecked) or ""),
      advice = "4–5 ponttal több sebzés jut egy energiára, kivéve ha a mob 1–2 ponttal is meghal.",
      missing = "a célpont életereje a cast pillanatában (meghalt volna-e kevesebb ponttal is)" .. (ev.unchecked > 0 and (", " .. ev.unchecked .. " kevés pontos Eviscerate-nél") or "") })
  end
  local avgFight = r.seconds / r.fights
  local snd
  for _, a in ipairs(r.auras) do if a.name == "Slice and Dice" then snd = a end end
  if avgFight >= 12 and (not snd or snd.uptimePct < 50) then
    local whiteShare = 0
    for _, a in ipairs(r.abilities) do if White(a.name) then whiteShare = whiteShare + a.share end end
    Push({ title = "Ritkán van fent a Slice and Dice", fault = true, rule = "sndHaste",
      fact = ("A Slice and Dice a harcidő %s%%-ában volt aktív, miközben a sebzésed %s%%-a auto-attack; az átlagos harcod %d mp.")
        :format(snd and F1(snd.uptimePct) or "0", F1(whiteShare), math.floor(avgFight + 0.5)),
      advice = "Hosszabb harcban az első 1–2 combo pont Slice and Dice-ra, utána Eviscerate.",
      missing = "a harc várható hossza a döntés pillanatában, és hogy megtanultad-e a Slice and Dice-t" })
  end
  local parried, swings = 0, 0
  for _, a in ipairs(r.abilities) do
    parried = parried + a.parry
    if not Dot(a.name) then swings = swings + a.n end
  end
  local parry = Pct(parried, swings)
  if parry > 2 then
    Push({ title = "Az ütéseid egy részét hárítják", fault = true, rule = "parryFront",
      fact = ("Az ütéseid %s%%-át parryzták."):format(F1(parry)),
      advice = "Csapatban (dungeonben) a célpont mögül ez elkerülhető; szólóban a mob feléd fordul.",
      missing = "hol álltál a célponthoz képest (a pozíció nincs igazolt skálán), és hogy a mob kit nézett" })
  end
  if r.white.n >= 150 then
    Push({ info = true, title = "Mért találati arányok",
      fact = ("Auto-attack: %s%% miss, %s%% dodge, %s%% glancing, %s%% crit. Képességek: %s%% miss, %s%% crit.")
        :format(F1(r.white.miss), F1(r.white.dodge), F1(r.white.glance), F1(r.white.crit), F1(r.yellow.miss), F1(r.yellow.crit)) ..
        (r.white.miss > 15 and " A +hit tárgyak itt sokat érhetnek." or "") })
  end
  if r.white.glance > 20 then
    Push({ title = "Sok a glancing ütés", rule = "glanceSkill",
      fact = ("Az auto-attackjeid %s%%-a glancing."):format(F1(r.white.glance)),
      advice = "Ha nemrég váltottál fegyvertípust, a fegyverskill felhúzása segít." })
  end
  local hasPoison = false
  for _, a in ipairs(r.abilities) do if a.name:lower():find("poison", 1, true) then hasPoison = true end end
  local level = fights[1] and fights[1].level or 0
  if not hasPoison and level >= 20 and r.seconds >= 120 then
    Push({ title = "Nincs méreg-sebzés", fault = true, rule = "poison20",
      fact = "A rögzített harcokban egyetlen méreg-sebzés sincs.",
      advice = "Ha már van mérged, mindkét fegyverre tedd fel; a gyors balkezes fegyveren ér a legtöbbet.",
      missing = "hogy megtanultad-e a mérgeket és volt-e nálad (a varázskönyv és a táska nem mutatja)" })
  end
  local ss, melee
  for _, a in ipairs(r.abilities) do
    if a.name == "Sinister Strike" and not ss then ss = a end
    if a.name == "Melee" and not melee then melee = a end
  end
  if ss and melee then
    Push({ info = true, title = "Sebzésmegoszlás", fact = ("Sinister Strike %s%% (átlag %d), auto-attack %s%% (átlag %d).")
      :format(F1(ss.share), math.floor(ss.avg + 0.5), F1(melee.share), math.floor(melee.avg + 0.5)) })
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


---------------------------------------------------------------------------
-- where each number of a fight comes from
---------------------------------------------------------------------------
-- Every number the Harc page shows for one fight carries a status:
--   "mért"              summed from a source (the combat log, the client's damage meter);
--   "becsült"           worked out from something less direct (the clock, the target's hits);
--   "szimulált"         computed from given inputs by a model (Waystone's own damage model);
--   "nem értékelhető"   cannot be worked out from what there is: shown as "–", never as 0.
C.STATUS = { measured = "mért", estimated = "becsült", simulated = "szimulált", none = "nem értékelhető" }
local RANK = { ["mért"] = 1, ["becsült"] = 2, ["szimulált"] = 3, ["nem értékelhető"] = 4 }
local function Worst(...)
  local w = "mért"
  for _, s in ipairs({ ... }) do if RANK[s] > RANK[w] then w = s end end
  return w
end

local function PetDamage(f)
  if f.pet then return f.pet end
  local sum = 0
  for _, a in ipairs(f.ab or {}) do if (a.name or ""):sub(1, 5) == "Pet: " then sum = sum + (a.dmg or 0) end end
  return sum
end

-- Whether the model of your current character can be held against this fight: the same level,
-- and (where the fight recorded it) the same gear. Returns ok, reason.
function C.Comparable(f, ctx)
  if not ctx or not ctx.baseline or ctx.baseline <= 0 then return false, "nincs modell ehhez a kaszthoz" end
  if not f.level or f.level == 0 then return false, "a harc szintje ismeretlen" end
  if f.level ~= ctx.level then return false, ("a harc %d. szinten volt, a modell a mostani %d. szintedet számolja"):format(f.level, ctx.level) end
  if f.gear and WA.Meter and WA.Meter.GearAtPull then
    local now = WA.Meter.GearAtPull()
    if now and now ~= f.gear then return false, "azóta más a felszerelésed" end
  end
  return true, f.gear and "azonos szint és felszerelés" or "azonos szint; a felszerelést ez a harc nem rögzítette"
end

-- Rows { key, label, status, value, text, from } for one fight. ctx: the class model (or nil).
function C.Provenance(f, ctx)
  local rows = {}
  local function Row(key, label, status, value, text, from) rows[#rows + 1] = { key = key, label = label, status = status, value = value, text = text, from = from } end
  local b = f.basis or {}
  local log = (f.source or "log") == "log"
  local dur = tonumber(f.dur)
  local total = tonumber(f.dmg)
  local pet = PetDamage(f)

  -- damage
  local dmgStatus, dmgFrom
  if b.dmg == "effective" then
    dmgStatus, dmgFrom = "mért", "a harcnapló saját sebző eseményei, effektív sebzés (a túlsebzés nélkül)" ..
      ((f.overkill or 0) > 0 and (", " .. f.overkill .. " túlsebzés levonva") or "")
  elseif b.dmg == "meter-own" then
    dmgStatus, dmgFrom = "mért", "a játék damage meterének saját sora (isLocalPlayer), a harc után kiolvasva"
  elseif b.dmg == "target-hits" then
    dmgStatus, dmgFrom = "becsült", "a célpontot ért ütések összege (UNIT_COMBAT), egyedül játszva; a damage meter nem volt olvasható"
  elseif log then
    dmgStatus, dmgFrom = "mért", "a harcnapló saját sebző eseményei (régebbi feltöltés: a túlsebzés benne lehet)"
  else
    dmgStatus, dmgFrom = "becsült", "régebbi rögzítés: nem tudni, a damage meterből vagy a célpont ütéseiből jött"
  end
  if not total then dmgStatus = "nem értékelhető" end
  local own = total and (total - pet) or nil
  Row("own", "Saját sebzés (pet nélkül)", dmgStatus, own, own and tostring(math.floor(own + 0.5)) or "–", dmgFrom)

  -- the pet
  local petStatus, petFrom = "mért", nil
  local partial = false
  if b.pet == "owner-flags" or (log and not b.pet) then
    petFrom = "a harcnapló jelzői szerint a te peted vagy totemed (affiliation: mine, pet/guardian); név alapján nem párosít"
  elseif b.pet == "meter-guid" then
    petFrom = "a damage meter pet-sora, a harc végén kint lévő pet GUID-ja szerint; ha közben újrahívtad, a korábbi pet része hiányozhat"
    partial = true
  elseif b.pet == "meter-merged" then
    petFrom = "a damage meter a te sorodban adta a pet képességeit; egyszer számolva"
  elseif b.pet == "guess" then
    petStatus, petFrom, partial = "becsült", "fizikai ütések a célponton, miközben te nem ütöttél: nem igazolt, hogy a peted volt", true
  else
    petFrom = "nem volt pet-sebzés"
  end
  if pet > 0 or (b.pet and b.pet ~= "none") then
    Row("pet", "Pet sebzése", petStatus, pet, tostring(math.floor(pet + 0.5)), petFrom)
  end

  -- duration
  local durStatus, durFrom
  if b.dur == "own-events" or (log and not b.dur) then
    durStatus, durFrom = "mért", "az első és az utolsó saját (vagy pet) sebző esemény között; 8 mp szünet új harcot kezd"
  elseif b.dur == "meter-session" then
    durStatus, durFrom = "mért", "a damage meter sessionjének hossza (durationSeconds)"
  elseif b.dur == "regen-clock" then
    durStatus, durFrom = "becsült", "harcba lépés és kilépés között, óra szerint (a meter nem adott hosszt)"
  else
    durStatus, durFrom = "becsült", "régebbi rögzítés: a meter hossza vagy a harcba lépés óta eltelt idő"
  end
  if not dur or dur <= 0 then durStatus = "nem értékelhető" end
  Row("dur", "Időtartam", durStatus, dur and dur > 0 and dur or nil, dur and dur > 0 and (F1(dur) .. " mp") or "–", durFrom)

  -- DPS
  local okDps = total and dur and dur > 0
  local dps = okDps and total / dur or nil
  local dpsStatus = okDps and Worst(dmgStatus, durStatus, pet > 0 and petStatus or "mért") or "nem értékelhető"
  Row("dps", "DPS (saját + pet)", dpsStatus, dps, dps and (F1(dps) .. (partial and pet > 0 and " (részleges)" or "")) or "–",
    okDps and ("(%d saját + %d pet) / %s mp%s"):format(math.floor(own + 0.5), math.floor(pet + 0.5), F1(dur),
      partial and pet > 0 and "; a pet-rész nem teljesen igazolt" or "") or "nincs pozitív időtartam vagy sebzés")
  if pet > 0 then
    local ownDps = okDps and own / dur or nil
    Row("ownDps", "Saját DPS (pet nélkül)", okDps and Worst(dmgStatus, durStatus) or "nem értékelhető", ownDps, ownDps and F1(ownDps) or "–",
      okDps and ("%d / %s mp"):format(math.floor(own + 0.5), F1(dur)) or "nincs pozitív időtartam")
  end

  -- the model, and the ratio only for a matching situation
  local okCmp, why = C.Comparable(f, ctx)
  if ctx and ctx.baseline and ctx.baseline > 0 then
    local fights = ctx.combat and ctx.combat.fights or 0
    Row("model", "Várt DPS (Waystone-modell)", okCmp and "szimulált" or "nem értékelhető", okCmp and ctx.baseline or nil,
      okCmp and F1(ctx.baseline) or "–",
      ("a Waystone szintezési modellje a mostani statjaidból és felszerelésedből%s; nem WoWSims-szimuláció%s")
        :format(fights > 0 and (", " .. fights .. " rögzített harccal kalibrálva") or ", tankönyvi értékekkel",
          okCmp and "" or (" · " .. why)))
    if okCmp and dps then
      Row("ratio", "Mért / várt", "szimulált", dps / ctx.baseline * 100, ("%d%%"):format(math.floor(dps / ctx.baseline * 100 + 0.5)),
        "100 × mért DPS / várt DPS; " .. why .. ". Az eltérés önmagában nem rotációs hiba: a mozgás, a több célpont vagy a harc vége is benne van.")
    end
  end
  Row("sim", "Referencia-szimuláció (WoWSims Forever)", "nem értékelhető", nil, "–",
    ((f.level or 0) > 0 and f.level < 60) and "a Forever motor csak 60-as karaktert épít: ehhez a szinthez nincs szintazonos referencia"
      or "nincs bekötve az addonba: külső futtatás és import kellene hozzá")

  -- where it all came from
  local srcText = log and "harcnapló (WoWCombatLog, a feltöltő dolgozta fel)"
    or ((b.dmg == "meter-own") and "játékban: a játék damage metere" or "játékban: a célpont ütései")
  Row("source", "Adatforrás", "mért", nil, log and "harcnapló" or "játékban", srcText ..
    (f.sessionID and (", session #" .. f.sessionID) or ""))
  return rows
end
