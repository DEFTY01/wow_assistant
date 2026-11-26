-- WoW Assistant: the rogue damage model and gear upgrades, ported from the web app (src/gear.ts).
--
-- Pure functions: everything comes in as plain tables, so the same code runs in game (Game.lua
-- builds the input from the client) and in a Lua VM against the web app's own numbers.
--
-- ItemStats: { agi, str, ap, crit, hit, weapon = { min, max, speed } or nil }
-- Model input:
--   level, agi, str (effective), ap, crit (%), hit (%)
--   equipped[SLOT] = { id, name, stats }      Blizzard slot names (MAIN_HAND, FINGER_1, ...)
--   slotOrder = { SLOT, ... }                 order the equipped items are listed in (display)
--   talents = { malice = crit %, efficient = energy, coup = Eviscerate % }
--   combat = report from Combat.lua or nil    calibration from recorded fights
--   buffs = { [id] = true }                   selected party buffs and consumables
--   skills = { ["Daggers"] = { rank, max } }  weapon skills, nil when unknown

local _, WA = ...
WA = WA or {}
local M = {}
WA.Model = M

local function Stable(list, less)
  for i, v in ipairs(list) do v.__i = i end
  table.sort(list, function(a, b)
    if less(a, b) then return true end
    if less(b, a) then return false end
    return a.__i < b.__i
  end)
  for _, v in ipairs(list) do v.__i = nil end
  return list
end
M.Stable = Stable

local function F1(n) return ("%.1f"):format(n) end
local function Round(n) return math.floor(n + 0.5) end
M.Round = Round

M.ZERO = { agi = 0, str = 0, ap = 0, crit = 0, hit = 0, rap = 0, int = 0, sp = 0 }

-- Normalized weapon speed (WoWSims Forever d5144855 sim/core/attack.go newWeaponFromItem): instant
-- attacks such as Sinister Strike add AP / 14 x this, not x the weapon's own speed. A dagger 1.7
-- (in either hand), any other two-hander 3.3, a ranged weapon 2.8, every other one-hander 2.4.
-- sub: the item subclass (15 dagger; 1 2H axe, 5 2H mace, 6 polearm, 8 2H sword, 10 staff; 2 bow,
-- 3 gun, 16 thrown, 18 crossbow, 19 wand). nil when the subclass is not known.
local TWO_HAND_SUBS = { [1] = true, [5] = true, [6] = true, [8] = true, [10] = true }
local RANGED_SUBS = { [2] = true, [3] = true, [16] = true, [18] = true, [19] = true }
function M.NormalizedSpeed(sub, twoHand)
  sub = tonumber(sub)
  if sub == nil then return nil end
  if sub == 15 then return 1.7 end
  if twoHand or TWO_HAND_SUBS[sub] then return 3.3 end
  if RANGED_SUBS[sub] then return 2.8 end
  return 2.4
end
-- The weapon part of an instant attack (Sinister Strike): average weapon damage + AP / 14 x the
-- normalized speed; the weapon's own speed only while its subclass is unknown.
function M.InstantWeaponDamage(w, ap)
  return (w.min + w.max) / 2 + (ap / 14) * (w.norm or w.speed)
end

-- Wowhead loot stats -> ItemStats (lootStats in src/gear.ts; GameData.lua already has the numbers).
-- rap: ranged attack power only (hunters); weapon: melee or ranged numbers.
function M.LootStats(row)
  return {
    agi = row[15] or 0, str = row[16] or 0, ap = row[17] or 0, crit = row[18] or 0, hit = row[19] or 0, rap = row[23] or 0,
    int = row[24] or 0, sp = row[25] or 0,
    weapon = row[22] and { min = row[20], max = row[21], speed = row[22] } or nil,
  }
end

-- The game's GetItemStats table (and the weapon numbers from the tooltip) -> ItemStats,
-- the same as normalize() in src/scan.ts. In this era's data the "ratings" are percentages.
function M.GameStats(st, dmg)
  local function v(...)
    local s = 0
    for i = 1, select("#", ...) do s = s + (tonumber(st and st[select(i, ...)]) or 0) end
    return s
  end
  return {
    agi = v("ITEM_MOD_AGILITY_SHORT"),
    str = v("ITEM_MOD_STRENGTH_SHORT"),
    ap = v("ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_MELEE_ATTACK_POWER_SHORT"),
    crit = v("ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_CRIT_MELEE_RATING_SHORT"),
    hit = math.max(v("ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HIT_MELEE_RATING_SHORT"), v("ITEM_MOD_HIT_RANGED_RATING_SHORT")),
    rap = v("ITEM_MOD_RANGED_ATTACK_POWER_SHORT"),
    int = v("ITEM_MOD_INTELLECT_SHORT"),
    sp = v("ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT"),
    weapon = (type(dmg) == "table" and #dmg == 3 and dmg[3] > 0) and { min = dmg[1], max = dmg[2], speed = dmg[3] } or nil,
  }
end

---------------------------------------------------------------------------
-- the model
---------------------------------------------------------------------------
-- Simplified sustained single-target DPS for a Sinister Strike / Eviscerate rogue.
function M.Dps(sh, p)
  local crit = math.min(sh.crit, 100) / 100
  local avoid = (p.dodge + p.parry) / 100
  local glance = p.glance / 100
  local whiteMiss = math.max(0, p.whiteMissBase - sh.hit) / 100
  local yellowMiss = math.max(0, p.yellowMissBase - sh.hit) / 100
  local plain = math.max(0, 1 - whiteMiss - avoid - glance - crit)
  local whiteFactor = plain + glance * 0.7 + crit * 2
  local yellowFactor = math.max(0, 1 - yellowMiss - avoid) * (1 + crit)
  local function avg(w) return (w.min + w.max) / 2 + (sh.ap / 14) * w.speed end
  local total = p.otherDps
  if sh.mh then total = total + p.swingRate * (avg(sh.mh) / sh.mh.speed) * whiteFactor end
  if sh.oh then total = total + p.swingRate * ((avg(sh.oh) * 0.5) / sh.oh.speed) * whiteFactor end
  if sh.mh then
    total = total + p.ssPerSec * (M.InstantWeaponDamage(sh.mh, sh.ap) + p.ssBonus) * yellowFactor
    total = total + p.evisPerSec * p.evisDamage * yellowFactor
  end
  return total
end

local function Apply(sh, remove, add, p)
  local dAgi = (add.agi - remove.agi) * p.statMult
  local dStr = (add.str - remove.str) * p.statMult
  return {
    ap = sh.ap + (add.ap - remove.ap) + dStr + dAgi,
    crit = sh.crit + (add.crit - remove.crit) + dAgi / p.agiPerCrit,
    hit = sh.hit + (add.hit - remove.hit),
    mh = sh.mh, oh = sh.oh,
  }
end

---------------------------------------------------------------------------
-- slots, items a rogue can use
---------------------------------------------------------------------------
-- Wowhead inventory type -> Blizzard equipment slots. 17 two-hand, 15 ranged (bow), 25 thrown,
-- 26 ranged right (gun, crossbow, wand).
M.WOWHEAD_SLOTS = {
  [1] = { "HEAD" }, [2] = { "NECK" }, [3] = { "SHOULDER" }, [5] = { "CHEST" }, [20] = { "CHEST" }, [6] = { "WAIST" },
  [7] = { "LEGS" }, [8] = { "FEET" }, [9] = { "WRIST" }, [10] = { "HANDS" }, [11] = { "FINGER_1", "FINGER_2" },
  [12] = { "TRINKET_1", "TRINKET_2" }, [16] = { "BACK" }, [13] = { "MAIN_HAND", "OFF_HAND" }, [21] = { "MAIN_HAND" },
  [22] = { "OFF_HAND" }, [17] = { "MAIN_HAND" }, [15] = { "RANGED" }, [25] = { "RANGED" }, [26] = { "RANGED" },
  [14] = { "OFF_HAND" }, [23] = { "OFF_HAND" },
}
M.WOWHEAD_TWO_HAND = { [17] = true }
-- Blizzard inventory type (INVTYPE_ without the prefix) -> slots (INV_SLOTS in src/market.ts).
M.INV_SLOTS = {
  HEAD = { "HEAD" }, NECK = { "NECK" }, SHOULDER = { "SHOULDER" }, CHEST = { "CHEST" }, ROBE = { "CHEST" },
  WAIST = { "WAIST" }, LEGS = { "LEGS" }, FEET = { "FEET" }, WRIST = { "WRIST" }, HAND = { "HANDS" },
  FINGER = { "FINGER_1", "FINGER_2" }, TRINKET = { "TRINKET_1", "TRINKET_2" }, CLOAK = { "BACK" },
  WEAPON = { "MAIN_HAND", "OFF_HAND" }, WEAPONMAINHAND = { "MAIN_HAND" }, WEAPONOFFHAND = { "OFF_HAND" },
  ["2HWEAPON"] = { "MAIN_HAND" }, RANGED = { "RANGED" }, RANGEDRIGHT = { "RANGED" }, THROWN = { "RANGED" },
  SHIELD = { "OFF_HAND" }, HOLDABLE = { "OFF_HAND" },
}
M.INV_TWO_HAND = { ["2HWEAPON"] = true }

-- What each class can wear and wield. Armor subclasses: 0 misc, 1 cloth, 2 leather, 3 mail;
-- 6 shield; Wowhead's own negative ones: -2 ring, -3 neck, -4 trinket, -6 cloak. Weapon subclasses:
-- 0 axe, 1 two-hand axe, 2 bow, 3 gun, 4 mace, 5 two-hand mace, 6 polearm, 7 sword, 8 two-hand
-- sword, 10 staff, 13 fist, 15 dagger, 16 thrown, 18 crossbow. mailFrom: the level mail armor is
-- learned at.
local JEWELRY = { [-2] = true, [-3] = true, [-4] = true, [-6] = true }
M.CLASSES = {
  ROGUE = {
    armor = { [0] = true, [1] = true, [2] = true },
    weapon = { [4] = true, [7] = true, [13] = true, [15] = true },
    slots = { "MAIN_HAND", "OFF_HAND", "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET", "FINGER", "TRINKET" },
  },
  HUNTER = {
    armor = { [0] = true, [1] = true, [2] = true, [3] = true }, mailFrom = 40,
    weapon = { [0] = true, [1] = true, [2] = true, [3] = true, [6] = true, [7] = true, [8] = true, [10] = true,
      [13] = true, [15] = true, [16] = true, [18] = true },
    slots = { "RANGED", "MAIN_HAND", "OFF_HAND", "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET", "FINGER", "TRINKET" },
  },
  -- two-hand axes and maces need the Two-Handed Axes and Maces talent (Shaman.lua checks it)
  SHAMAN = {
    armor = { [0] = true, [1] = true, [2] = true, [3] = true, [6] = true }, mailFrom = 40,
    weapon = { [0] = true, [1] = true, [4] = true, [5] = true, [10] = true, [13] = true, [15] = true },
    slots = { "MAIN_HAND", "OFF_HAND", "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET", "FINGER", "TRINKET" },
  },
  -- cloth and leather; maces, two-hand maces, staves, fist weapons, daggers (Druid.lua: in Cat
  -- Form only the weapon's DPS counts)
  DRUID = {
    armor = { [0] = true, [1] = true, [2] = true },
    weapon = { [4] = true, [5] = true, [10] = true, [13] = true, [15] = true },
    slots = { "MAIN_HAND", "OFF_HAND", "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET", "FINGER", "TRINKET" },
  },
  -- cloth; daggers, one-hand swords, staves, and a wand in the ranged slot (Warlock.lua)
  WARLOCK = {
    armor = { [0] = true, [1] = true },
    weapon = { [7] = true, [10] = true, [15] = true, [19] = true },
    slots = { "RANGED", "MAIN_HAND", "OFF_HAND", "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET", "FINGER", "TRINKET" },
  },
}
-- Kept for code that still asks about the rogue's list.
M.ARMOR_SUBS = M.CLASSES.ROGUE.armor
M.WEAPON_SUBS = M.CLASSES.ROGUE.weapon

-- Can this class (at this level) use an item of this item class and subclass?
function M.UsableSub(class, itemClass, sub, level)
  local rules = M.CLASSES[class or "ROGUE"] or M.CLASSES.ROGUE
  if itemClass == 4 then
    if JEWELRY[sub] then return true end
    if not rules.armor[sub] then return false end
    if sub == 3 and rules.mailFrom and (level or 0) < rules.mailFrom then return false end
    return true
  end
  if itemClass == 2 then return rules.weapon[sub] == true end
  return false
end

local WEAPON_NAMES = { [0] = "Axe", [1] = "2H Axe", [2] = "Bow", [3] = "Gun", [4] = "Mace", [5] = "2H Mace", [6] = "Polearm", [7] = "Sword",
  [8] = "2H Sword", [10] = "Staff", [13] = "Fist", [15] = "Dagger", [16] = "Thrown", [18] = "Crossbow", [19] = "Wand" }
M.WEAPON_NAMES = WEAPON_NAMES
M.WEAPON_SKILLS = { [0] = "Axes", [1] = "Two-Handed Axes", [2] = "Bows", [3] = "Guns", [4] = "Maces", [5] = "Two-Handed Maces", [6] = "Polearms",
  [7] = "Swords", [8] = "Two-Handed Swords", [10] = "Staves", [13] = "Fist Weapons", [15] = "Daggers", [16] = "Thrown",
  [18] = "Crossbows" }
local WEAPON_SKILLS = M.WEAPON_SKILLS
M.SLOT_HU = {
  HEAD = "fej", NECK = "nyak", SHOULDER = "váll", BACK = "köpeny", CHEST = "mellkas", WRIST = "csukló", HANDS = "kéz",
  WAIST = "öv", LEGS = "láb", FEET = "lábfej", FINGER_1 = "gyűrű", FINGER_2 = "gyűrű", TRINKET_1 = "trinket",
  TRINKET_2 = "trinket", MAIN_HAND = "főkéz", OFF_HAND = "balkéz / pajzs", RANGED = "távolsági", FINGER = "gyűrű", TRINKET = "trinket",
}

-- GearItem { itemId, name, slot (INV type), itemClass, subclass, reqLevel, itemLevel, quality, stats }
-- level: the character's level (mail armor for hunters from 40); nil = no level limit.
function M.Usable(class, item, level)
  if not M.INV_SLOTS[item.slot] then return false end
  if not M.UsableSub(class, item.itemClass, item.subclass, level or 99) then return false end
  if item.itemClass == 2 then return item.stats.weapon ~= nil end
  return item.itemClass == 4
end
function M.RogueUsable(item) return M.Usable("ROGUE", item) end

---------------------------------------------------------------------------
-- buffs (src/buffs.ts)
---------------------------------------------------------------------------
local function Effect(t)
  return { agi = t[3], str = t[4], ap = t[5], crit = t[6], statPct = t[7] }
end

local function DescribeEffect(e)
  local bits = {}
  if e.agi and e.str and e.agi == e.str then bits[#bits + 1] = ("+%d minden stat"):format(e.agi)
  else
    if e.agi then bits[#bits + 1] = ("+%d agi"):format(e.agi) end
    if e.str then bits[#bits + 1] = ("+%d str"):format(e.str) end
  end
  if e.ap then bits[#bits + 1] = ("+%d AP"):format(e.ap) end
  if e.crit then bits[#bits + 1] = ("+%s%% crit"):format(e.crit) end
  if e.statPct then bits[#bits + 1] = ("+%d%% statok"):format(Round(e.statPct * 100)) end
  return table.concat(bits, ", ")
end
M.DescribeEffect = DescribeEffect

function M.ResolveBuffs(level, selected, D)
  local out = {}
  for _, b in ipairs((D or WowAssistantData or {}).buffs or {}) do
    local tier
    for _, t in ipairs(b[5]) do if t[1] <= level then tier = t end end
    if not tier then
      out[#out + 1] = { id = b[1], name = b[2], source = b[3], group = b[4], effect = nil,
        summary = ("%d-es szinttől"):format(b[5][1][1]), selected = false }
    else
      local e = Effect(tier)
      out[#out + 1] = { id = b[1], name = tier[2] or b[2], source = b[3], group = b[4], effect = e,
        summary = DescribeEffect(e), selected = selected and selected[b[1]] or false }
    end
  end
  return out
end

-- Every consumable usable at this level, weaker ranks included.
function M.ConsumablesFor(level, D)
  D = D or WowAssistantData or {}
  local out = {}
  for _, b in ipairs(D.buffs or {}) do
    if b[4] == "consumable" then
      for _, t in ipairs(b[5]) do
        if t[1] <= level then
          local name = t[2] or b[2]
          local item = D.consumables and D.consumables[name]
          if item then
            local e = Effect(t)
            out[#out + 1] = { name = name, itemId = item[1], minutes = item[2], effect = e, summary = DescribeEffect(e) }
          end
        end
      end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- context: what is needed to score a piece of gear against what is equipped now
---------------------------------------------------------------------------
-- The class's own model: HUNTER goes to Hunter.lua, SHAMAN to Shaman.lua, DRUID to Druid.lua,
-- WARLOCK to Warlock.lua, everything else is the rogue.
function M.Context(input)
  if input.class == "HUNTER" and WA.Hunter then return WA.Hunter.Context(input) end
  if input.class == "SHAMAN" and WA.Shaman then return WA.Shaman.Context(input) end
  if input.class == "DRUID" and WA.Druid then return WA.Druid.Context(input) end
  if input.class == "WARLOCK" and WA.Warlock then return WA.Warlock.Context(input) end
  return M.RogueContext(input)
end

-- Fields every class's context has besides its numbers: what it can use, which slots an item
-- goes to, the slot order of the reports.
function M.Common(ctx, class)
  ctx.class = class
  ctx.slotGroups = M.CLASSES[class].slots
  -- usableAt: at a given level (the gear report looks a few levels ahead); a class may narrow it
  function ctx.usableAt(itemClass, sub, level) return M.UsableSub(class, itemClass, sub, level) end
  function ctx.usable(itemClass, sub) return ctx.usableAt(itemClass, sub, ctx.level) end
  -- Slots for a Wowhead row (r[7]) or a GearItem's inventory type, and whether it takes both hands.
  function ctx.lootSlots(wowheadSlot) return M.WOWHEAD_SLOTS[wowheadSlot], M.WOWHEAD_TWO_HAND[wowheadSlot] end
  function ctx.invSlots(invType) return M.INV_SLOTS[invType], M.INV_TWO_HAND[invType] end
  return ctx
end

function M.RogueContext(input)
  local level = input.level
  local equipped = input.equipped or {}
  local notes = {}
  local tal = input.talents or {}
  local agi = input.agi or 0
  local critNow = input.crit or 0
  local agiPerCrit = agi / math.max(0.1, critNow - (tal.malice or 0))
  if not (agiPerCrit > 3 and agiPerCrit < 60) then agiPerCrit = 2.2 + (26.8 * (level - 1)) / 59 end
  notes[#notes + 1] = ("1%% crit ≈ %s agility (a saját statjaidból visszaszámolva)."):format(F1(agiPerCrit))

  local ssCost = 45 - (tal.efficient or 0)
  local evisBonus = 1 + (tal.coup or 0) / 100
  local function eq(slot) return equipped[slot] and equipped[slot].stats or M.ZERO end
  local sheet = {
    ap = input.ap or 0, crit = critNow, hit = input.hit or 0,
    mh = eq("MAIN_HAND").weapon, oh = eq("OFF_HAND").weapon,
  }
  for slot, key in pairs({ MAIN_HAND = "mh", OFF_HAND = "oh" }) do
    local w = sheet[key]
    if w and equipped[slot] then w.norm = M.NormalizedSpeed(equipped[slot].sub) end
  end

  local cycleSeconds = (5 * ssCost + 35) / 10
  local params = {
    level = level, agiPerCrit = agiPerCrit,
    whiteMissBase = sheet.oh and 24 or 5, yellowMissBase = 5,
    dodge = 5, parry = 0, glance = 0, swingRate = 1,
    ssPerSec = 5 / cycleSeconds, evisPerSec = 1 / cycleSeconds,
    ssBonus = Round(level / 2), evisDamage = Round(12 * level * evisBonus),
    otherDps = 0, statMult = 1, notes = notes,
  }

  -- Pull every default towards what the recorded fights show.
  local combat = input.combat
  local function mix(prior, measured, n, half)
    local w = n / (n + half)
    return prior * (1 - w) + measured * w
  end
  if combat and combat.seconds > 0 then
    local secs = combat.seconds
    local wn = combat.white.n
    params.whiteMissBase = mix(params.whiteMissBase, combat.white.miss + sheet.hit, wn, 100)
    params.dodge = mix(params.dodge, combat.white.dodge, wn, 100)
    params.parry = mix(params.parry, combat.white.parry, wn, 100)
    params.glance = mix(params.glance, combat.white.glance, wn, 100)
    params.yellowMissBase = mix(params.yellowMissBase, combat.yellow.miss + sheet.hit, combat.yellow.n, 100)
    if sheet.mh then
      local expected = 1 / sheet.mh.speed + (sheet.oh and 1 / sheet.oh.speed or 0)
      params.swingRate = mix(1, wn / secs / expected, secs, 120)
    end
    local ss, evis
    for _, a in ipairs(combat.abilities) do
      if a.name == "Sinister Strike" and not ss then ss = a end
      if a.name == "Eviscerate" and not evis then evis = a end
    end
    params.ssPerSec = mix(params.ssPerSec, (ss and ss.n or 0) / secs, secs, 120)
    params.evisPerSec = mix(params.evisPerSec, (evis and evis.n or 0) / secs, secs, 120)
    if ss and sheet.mh and ss.hit + ss.crit > 0 then
      local normal = ss.dmg / (ss.hit + 2 * ss.crit)
      local weapon = M.InstantWeaponDamage(sheet.mh, sheet.ap)
      params.ssBonus = mix(params.ssBonus, math.max(0, normal - weapon), ss.hit + ss.crit, 20)
    end
    if evis and evis.hit + evis.crit > 0 then
      params.evisDamage = mix(params.evisDamage, evis.dmg / (evis.hit + 2 * evis.crit), evis.hit + evis.crit, 3)
    end
    local other = 0
    for _, a in ipairs(combat.abilities) do
      if a.name ~= "Melee" and a.name ~= "Sinister Strike" and a.name ~= "Eviscerate" then other = other + a.dmg end
    end
    params.otherDps = mix(0, other / secs, secs, 120)
    local weight = Round((wn / (wn + 100)) * 100)
    notes[#notes + 1] = ("Kalibrálva %d rögzített harcból (%d mp, %d auto-attack): a mért értékek súlya most kb. %d%%, és a mintával együtt nő.")
      :format(combat.fights, Round(secs), wn, weight)
    notes[#notes + 1] = ("Auto-attack: %s%% alap miss, %s%% dodge, %s%% parry, %s%% glancing. Sinister Strike %s/perc (+%d bónusz), Eviscerate %s/perc (%d sebzés), egyéb források %s DPS.")
      :format(F1(params.whiteMissBase), F1(params.dodge), F1(params.parry), F1(params.glance), F1(params.ssPerSec * 60),
        Round(params.ssBonus), F1(params.evisPerSec * 60), Round(params.evisDamage), F1(params.otherDps))
  else
    notes[#notes + 1] = "Nincs rögzített harc, ezért tankönyvi értékekkel számol: 24% dual-wield miss, 5% dodge, hátulról ütve, " ..
      "5 Sinister Strike után Eviscerate. Kapcsold be a harcnaplót (/wa log) a kalibráláshoz."
  end

  local unbuffed = M.Dps(sheet, params)
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
  sheet.ap = sheet.ap + bAgi + bStr + bAp
  sheet.crit = sheet.crit + bCrit + bAgi / agiPerCrit
  local baseline = M.Dps(sheet, params)
  local skills = input.skills
  local equippedIds = {}
  for _, it in pairs(equipped) do if it.id then equippedIds[it.id] = true end end

  local ctx = M.Common({
    level = level, baseline = baseline, unbuffed = unbuffed, buffs = buffs, params = params, sheet = sheet,
    equipped = equipped, equippedIds = equippedIds, combat = combat, slotOrder = input.slotOrder,
  }, "ROGUE")

  -- Best slot for an item and the DPS it adds there; nil when it is not an upgrade.
  function ctx.score(add, slots, twoHand, sub)
    if add.weapon then add.weapon.norm = M.NormalizedSpeed(sub, twoHand) end
    local best
    for _, slot in ipairs(slots) do
      local sh = Apply(sheet, eq(slot), add, params)
      if slot == "MAIN_HAND" then sh.mh = add.weapon end
      if slot == "OFF_HAND" then sh.oh = add.weapon end
      local gain = M.Dps(sh, params) - baseline
      if not best or gain > best.gain then best = { slot = slot, gain = gain } end
    end
    if best and best.gain > 0.05 then return best end
    return nil
  end

  function ctx.describe(add, weaponSub)
    local bits = {}
    if add.weapon then
      local w = add.weapon
      bits[#bits + 1] = ("%s %s–%s / %s"):format(WEAPON_NAMES[weaponSub or -1] or "Weapon", w.min, w.max, F1(w.speed))
    end
    if add.agi ~= 0 then bits[#bits + 1] = ("+%s agi"):format(add.agi) end
    if add.str ~= 0 then bits[#bits + 1] = ("+%s str"):format(add.str) end
    if add.ap ~= 0 then bits[#bits + 1] = ("+%s AP"):format(add.ap) end
    if add.crit ~= 0 then bits[#bits + 1] = ("+%s%% crit"):format(add.crit) end
    if add.hit ~= 0 then bits[#bits + 1] = ("+%s%% hit"):format(add.hit) end
    return table.concat(bits, ", ")
  end

  function ctx.buffGain(e)
    local dAgi = (e.agi or 0) * params.statMult
    local dStr = (e.str or 0) * params.statMult
    local sh = { ap = sheet.ap + dAgi + dStr + (e.ap or 0), crit = sheet.crit + (e.crit or 0) + dAgi / agiPerCrit,
      hit = sheet.hit, mh = sheet.mh, oh = sheet.oh }
    return M.Dps(sh, params) - baseline
  end

  function ctx.weaponWarning(itemClass, sub)
    if itemClass ~= 2 or not skills or not next(skills) then return nil end
    local line = WEAPON_SKILLS[sub]
    local s = skills[line]
    if not s then return ("%s nincs kitanulva"):format(tostring(line)) end
    if s.rank < s.max - 15 then return ("%s skill %d/%d"):format(line, s.rank, s.max) end
    return nil
  end

  return ctx
end

---------------------------------------------------------------------------
-- dungeon upgrades (gearReport)
---------------------------------------------------------------------------
local SLOT_ORDER = { "MAIN_HAND", "OFF_HAND", "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET", "FINGER", "TRINKET" }
local function Group(s) return (s:gsub("_[12]$", "")) end
M.Group = Group

function M.GearReport(ctx, lookahead, D)
  lookahead = lookahead or 3
  D = D or WowAssistantData or {}
  local level, baseline = ctx.level, ctx.baseline
  local rows = {}
  for _, r in ipairs(D.loot or {}) do
    if r[12] == "dungeon" and (r[6] or 0) <= level + lookahead and D.dungeons[r[2]] then rows[#rows + 1] = r end
  end
  local upgrades = {}
  for _, r in ipairs(rows) do
    local id, cls, sub = r[1], r[8], r[9]
    -- mail is checked a few levels ahead: a hunter's mail shows under "later" from 37
    local ok = not ctx.equippedIds[id] and ctx.usableAt(cls, sub, level + lookahead)
    local slots, twoHand
    if ok then slots, twoHand = ctx.lootSlots(r[7]) end
    local add = slots and M.LootStats(r)
    if add and cls == 2 and not add.weapon then add = nil end
    local best = add and ctx.score(add, slots, twoHand, sub)
    if best then
      local eq = ctx.equipped[best.slot]
      upgrades[#upgrades + 1] = {
        itemId = id, name = r[3], quality = r[4], itemLevel = r[5], reqLevel = r[6], slot = best.slot,
        replaces = eq and eq.name or nil, boss = r[10], dropPct = r[11], dungeon = D.dungeons[r[2]][1], zoneId = r[2],
        gain = best.gain, gainPct = best.gain / baseline * 100,
        usableNow = (r[6] or 0) <= level and ctx.usableAt(cls, sub, level),
        detail = ctx.describe(add, sub), warning = ctx.weaponWarning(cls, sub),
      }
    end
  end
  Stable(upgrades, function(a, b) return a.gain > b.gain end)

  local usable = {}
  for _, u in ipairs(upgrades) do if u.usableNow then usable[#usable + 1] = u end end

  -- Per dungeon: the best usable upgrade for each slot, summed.
  local byDungeon, order = {}, {}
  for _, u in ipairs(usable) do
    local slots = byDungeon[u.zoneId]
    if not slots then
      slots = { list = {}, seen = {} }
      byDungeon[u.zoneId] = slots
      order[#order + 1] = u.zoneId
    end
    if not slots.seen[u.slot] then
      slots.seen[u.slot] = true
      slots.list[#slots.list + 1] = u
    end
  end
  local dungeons = {}
  for _, zoneId in ipairs(order) do
    local ups = Stable(byDungeon[zoneId].list, function(a, b) return a.gain > b.gain end)
    local gain, perRun, known = 0, 0, 0
    for _, u in ipairs(ups) do
      gain = gain + u.gain
      if u.dropPct then known = known + 1 perRun = perRun + u.gain * (u.dropPct / 100) end
    end
    local d = D.dungeons[zoneId]
    dungeons[#dungeons + 1] = {
      zoneId = zoneId, name = d[1], levels = (d[2] and d[2] > 0) and (d[2] .. "–" .. d[3]) or "?",
      gain = gain, perRun = known > 0 and perRun or nil, gainPct = gain / baseline * 100, upgrades = ups,
    }
  end
  Stable(dungeons, function(a, b) return (a.perRun or a.gain * 0.15) > (b.perRun or b.gain * 0.15) end)

  local bySlot = {}
  for _, slot in ipairs(ctx.slotGroups or SLOT_ORDER) do
    local best = {}
    for _, u in ipairs(usable) do
      if Group(u.slot) == slot and #best < 3 then best[#best + 1] = u end
    end
    if #best > 0 then
      local cur = {}
      for _, s in ipairs(ctx.slotOrder or {}) do
        if Group(s) == slot and ctx.equipped[s] then cur[#cur + 1] = ctx.equipped[s].name end
      end
      bySlot[#bySlot + 1] = { slot = slot, current = #cur > 0 and table.concat(cur, " + ") or nil, best = best }
    end
  end
  local later = {}
  for _, u in ipairs(upgrades) do
    if not u.usableNow and #later < 10 then later[#later + 1] = u end
  end
  return {
    baseline = baseline, measuredDps = ctx.combat and ctx.combat.dps or nil, unbuffed = ctx.unbuffed,
    buffs = ctx.buffs, params = ctx.params, sheet = ctx.sheet, dungeons = dungeons, bySlot = bySlot, later = later,
  }
end
