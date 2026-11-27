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
--   talents = Talent.lua's T.Effects (the numbers of the rank's Wowhead Forever text): malice / precision
--             (already on the character sheet), efficient, flawless (energy), coup, aggression (damage %),
--             lethality (crit bonus %), dualWield (off-hand %), expertise (dodge/parry −%), hackSlash (extra
--             attack % with an axe or sword), ruthlessness, sealFate (combo point %), relentless,
--             relentlessEnergy
--   combat = report from Combat.lua or nil    calibration from recorded fights
--   buffs = { [id] = true }                   selected party buffs and consumables
--   skills = { ["Daggers"] = { rank, max } }  weapon skills, nil when unknown

local _, WA = ...
local L = WA.L
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
-- The Sinister Strike / Eviscerate cycle from combo points and energy (Wowhead Forever talents):
-- Sinister Strikes per Eviscerate = (5 − Ruthlessness's chance) / (1 + a landed Sinister Strike's
-- crit chance × Seal Fate's chance); energy per cycle = that × the Sinister Strike cost + the
-- Eviscerate cost − Relentless Strikes' refund (5 points × its chance a point × its energy);
-- 10 energy a second. Returns Sinister Strikes and Eviscerates a second.
function M.RogueCycle(p, crit, landed)
  local c = p.cycle
  local perStrike = 1 + math.min(math.max(crit, 0), 100) / 100 * landed * c.sealFate
  local strikes = math.max(1, (5 - c.ruthless) / perStrike)
  local energy = strikes * c.ssCost + c.evisCost - c.refund
  local cycles = 10 / math.max(1, energy)
  return strikes * cycles, cycles
end

-- Hack and Slash: an axe (0) or a sword (7) gives its hand's landed attacks an extra attack.
local AXE_SWORD = { [0] = true, [7] = true }
local function ExtraAttack(w, p) return (w and AXE_SWORD[w.sub] and (p.hackSlash or 0) / 100) or 0 end
M.RogueExtraAttack = ExtraAttack

-- Simplified sustained single-target DPS for a Sinister Strike / Eviscerate rogue.
function M.Dps(sh, p)
  local crit = math.min(sh.crit, 100) / 100
  local avoid = (p.dodge + p.parry) / 100
  local glance = p.glance / 100
  local whiteMiss = math.max(0, p.whiteMissBase - sh.hit) / 100
  local yellowMiss = math.max(0, p.yellowMissBase - sh.hit) / 100
  local plain = math.max(0, 1 - whiteMiss - avoid - glance - crit)
  local whiteFactor = plain + glance * 0.7 + crit * 2
  local landed = math.max(0, 1 - yellowMiss - avoid)
  local yellowFactor = landed * (1 + crit)
  -- Lethality raises the Sinister Strike's crit bonus (100%) by its %
  local ssFactor = landed * (1 + crit * (1 + (p.lethality or 0) / 100))
  local whiteLanded = math.max(0, 1 - whiteMiss - avoid)
  local ohMult = 0.5 * (1 + (p.dualWield or 0) / 100)
  local function avg(w) return (w.min + w.max) / 2 + (sh.ap / 14) * w.speed end
  -- the cycle's rates move with crit only through Seal Fate (else the ratio is 1)
  local ssRate, evisRate = p.ssPerSec, p.evisPerSec
  if p.cycle and p.cycle.ref then
    local s1, e1 = M.RogueCycle(p, sh.crit, landed)
    ssRate, evisRate = ssRate * s1 / p.cycle.ref[1], evisRate * e1 / p.cycle.ref[2]
  end
  local total = p.otherDps
  if sh.mh then
    local swings = p.swingRate / sh.mh.speed
    total = total + swings * avg(sh.mh) * whiteFactor
    local extra = ExtraAttack(sh.mh, p)
    if extra > 0 then total = total + (swings * whiteLanded + ssRate * landed) * extra * avg(sh.mh) * whiteFactor end
  end
  if sh.oh then
    local swings = p.swingRate / sh.oh.speed
    total = total + swings * avg(sh.oh) * ohMult * whiteFactor
    local extra = ExtraAttack(sh.oh, p)
    if extra > 0 then total = total + swings * whiteLanded * extra * avg(sh.oh) * ohMult * whiteFactor end
  end
  if sh.mh then
    total = total + ssRate * (M.InstantWeaponDamage(sh.mh, sh.ap) + p.ssBonus) * (p.ssMult or 1) * ssFactor
    total = total + evisRate * p.evisDamage * yellowFactor
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
  -- cloth, leather, mail, plate from 40, shields; every melee weapon but the wand, bows, guns,
  -- crossbows and thrown in the ranged slot (Warrior.lua; a second weapon from level 20)
  WARRIOR = {
    armor = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [6] = true }, plateFrom = 40,
    weapon = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true,
      [10] = true, [13] = true, [15] = true, [16] = true, [18] = true },
    slots = { "MAIN_HAND", "OFF_HAND", "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET", "FINGER", "TRINKET" },
  },
  -- cloth, leather, mail, plate from 40, shields; axes, maces, swords and polearms, one weapon
  -- (Paladin.lua)
  PALADIN = {
    armor = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [6] = true }, plateFrom = 40,
    weapon = { [0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true },
    slots = { "MAIN_HAND", "OFF_HAND", "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET", "FINGER", "TRINKET" },
  },
  -- cloth; daggers, one-hand maces, staves, and a wand in the ranged slot (Priest.lua)
  PRIEST = {
    armor = { [0] = true, [1] = true },
    weapon = { [4] = true, [10] = true, [15] = true, [19] = true },
    slots = { "RANGED", "MAIN_HAND", "OFF_HAND", "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET", "FINGER", "TRINKET" },
  },
  -- cloth; daggers, one-hand swords, staves, and a wand in the ranged slot (Mage.lua)
  MAGE = {
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
    if sub == 4 and rules.plateFrom and (level or 0) < rules.plateFrom then return false end
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
M.SLOT_HU = WA.LR {
  HEAD = L"head", NECK = L"neck", SHOULDER = L"shoulder", BACK = L"back", CHEST = L"chest", WRIST = L"wrist", HANDS = L"hands",
  WAIST = L"waist", LEGS = L"legs", FEET = L"feet", FINGER_1 = L"ring", FINGER_2 = L"ring", TRINKET_1 = "trinket",
  TRINKET_2 = "trinket", MAIN_HAND = L"main hand", OFF_HAND = L"off hand / shield", RANGED = L"ranged", FINGER = L"ring", TRINKET = "trinket",
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
  if e.agi and e.str and e.agi == e.str then bits[#bits + 1] = (L"+%d all stats"):format(e.agi)
  else
    if e.agi then bits[#bits + 1] = ("+%d agi"):format(e.agi) end
    if e.str then bits[#bits + 1] = ("+%d str"):format(e.str) end
  end
  if e.ap then bits[#bits + 1] = ("+%d AP"):format(e.ap) end
  if e.crit then bits[#bits + 1] = ("+%s%% crit"):format(e.crit) end
  if e.statPct then bits[#bits + 1] = (L"+%d%% stats"):format(Round(e.statPct * 100)) end
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
        summary = (L"from level %d"):format(b[5][1][1]), selected = false }
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
local function ClassContext(input)
  if input.class == "HUNTER" and WA.Hunter then return WA.Hunter.Context(input) end
  if input.class == "SHAMAN" and WA.Shaman then return WA.Shaman.Context(input) end
  if input.class == "DRUID" and WA.Druid then return WA.Druid.Context(input) end
  if input.class == "WARLOCK" and WA.Warlock then return WA.Warlock.Context(input) end
  if input.class == "MAGE" and WA.Mage then return WA.Mage.Context(input) end
  if input.class == "WARRIOR" and WA.Warrior then return WA.Warrior.Context(input) end
  if input.class == "PRIEST" and WA.Priest then return WA.Priest.Context(input) end
  if input.class == "PALADIN" and WA.Paladin then return WA.Paladin.Context(input) end
  return M.RogueContext(input)
end

-- input.spec (M.Spec) goes with the context, so every page can say which spec the model counts for.
function M.Context(input)
  local ctx = ClassContext(input)
  if ctx then ctx.spec = input.spec end
  return ctx
end

---------------------------------------------------------------------------
-- WA-004: calibration by level. Every class pulls its defaults towards the recorded fights with
-- mix(prior, measured, n, half), n a count (swings, casts) or seconds. A fight far from your level
-- shows another rotation and other spell ranks, so it counts less: its weight halves every
-- M.LEVEL_HALF levels. The counts and seconds are weighted (Combat.lua, fight.weight), the rates
-- and the damage per hit are not changed by it; only how far the model trusts them.
---------------------------------------------------------------------------
M.LEVEL_HALF = 5

-- A fight's weight at a level: 1 at your level, 0.5 five levels away, 0.25 ten away. A fight
-- without a level counts in full (nothing tells how far it is).
function M.LevelWeight(fightLevel, level)
  fightLevel, level = tonumber(fightLevel), tonumber(level)
  if not (fightLevel and level and fightLevel > 0 and level > 0) then return 1 end
  return 0.5 ^ (math.abs(fightLevel - level) / M.LEVEL_HALF)
end

-- The fights with their weight (copies; the saved fights are not changed), and where the
-- numbers come from: { level, fights, seconds, counted (weighted seconds), min, max, noLevel }.
function M.WeighFights(fights, level)
  local out = {}
  local info = { level = level, fights = 0, seconds = 0, counted = 0, noLevel = 0 }
  for _, f in ipairs(fights or {}) do
    local w = M.LevelWeight(f.level, level)
    out[#out + 1] = setmetatable({ weight = w }, { __index = f })
    local dur = tonumber(f.dur) or 0
    info.fights = info.fights + 1
    info.seconds = info.seconds + dur
    info.counted = info.counted + dur * w
    local lv = tonumber(f.level)
    if lv and lv > 0 then
      info.min = math.min(info.min or lv, lv)
      info.max = math.max(info.max or lv, lv)
    else
      info.noLevel = info.noLevel + 1
    end
  end
  return out, info
end

-- "Honnan a számok": one line for the notes.
function M.CalibrationNote(info)
  if not info or info.fights == 0 then return nil end
  local from
  if not info.min then from = L"from fights without a level"
  elseif info.min == info.max then from = (L"from level %d"):format(info.min)
  else from = (L"from levels %d–%d"):format(info.min, info.max) end
  local same = info.min and info.min == info.max and info.min == info.level
  local tail
  if same or info.seconds <= 0 then
    tail = L"all at your current level, at full weight"
  else
    tail = (L"those further from your current level (%d) count less (half weight every 5 levels): of %s s of combat, %s s counts (%d%%)")
      :format(info.level or 0, Round(info.seconds), Round(info.counted), Round(info.counted / info.seconds * 100))
  end
  return (L"Where the numbers come from: %d fights %s%s; %s."):format(info.fights, from,
    info.noLevel > 0 and info.min and (L" (%d without a level)"):format(info.noLevel) or "", tail)
end

---------------------------------------------------------------------------
-- WA-030: the spec. The talent tree with the most points; on a tie the one with the deeper
-- talent, then the first. The tree's deep talents (row 5 and below) are named as the proof
-- (e.g. Mortal Strike, Adrenaline Rush). A spec chosen by hand on the Harc page wins.
---------------------------------------------------------------------------
M.SPEC_NAMES = {
  ROGUE = { "Assassination", "Combat", "Subtlety" }, WARRIOR = { "Arms", "Fury", "Protection" },
  MAGE = { "Arcane", "Fire", "Frost" }, WARLOCK = { "Affliction", "Demonology", "Destruction" },
  HUNTER = { "Beast Mastery", "Marksmanship", "Survival" }, SHAMAN = { "Elemental", "Enhancement", "Restoration" },
  DRUID = { "Balance", "Feral", "Restoration" }, PRIEST = { "Discipline", "Holy", "Shadow" },
  PALADIN = { "Holy", "Protection", "Retribution" },
}

-- class; points = { [tab] = points } from the client (nil: counted from list); list = the
-- talents with their ranks ({ name, tab, rank }); override = the tab chosen by hand.
-- -> { tab, name, points, keys = { deep talents }, manual, from (why, as text) }; tab is nil
--    before the first talent point (the models then use their own default).
function M.Spec(class, points, list, override)
  local names = M.SPEC_NAMES[class or ""] or {}
  local T = WA.Talent
  local data = T and T.Data(class)
  local treeTab = {}
  for _, tr in ipairs(data and data.trees or {}) do treeTab[tr.id] = tr.tab end
  local count = points == nil
  local pts = {}
  for k, v in pairs(points or {}) do pts[k] = v end
  local deep, keys = {}, {}
  for _, r in ipairs(list or {}) do
    if (r.rank or 0) > 0 then
      local d = T and T.Find(class, r.name)
      local tab = r.tab or (d and treeTab[d.tree])
      if tab then
        if count then pts[tab] = (pts[tab] or 0) + r.rank end
        local tier = d and d.tier or 0
        if tier > (deep[tab] or 0) then deep[tab] = tier end
        if tier >= 5 then
          keys[tab] = keys[tab] or {}
          keys[tab][#keys[tab] + 1] = { name = r.name, tier = tier }
        end
      end
    end
  end
  local out = { class = class, points = pts, names = names }
  local best, tie
  for tab = 1, #names do
    local p = pts[tab] or 0
    if p > 0 then
      if not best or p > pts[best] then best, tie = tab, false
      elseif p == pts[best] then
        tie = true
        if (deep[tab] or 0) > (deep[best] or 0) then best = tab end
      end
    end
  end
  if override and names[override] then
    out.tab, out.manual = override, true
  else
    out.tab = best
  end
  if not out.tab then
    out.from = L"you have no talent points yet: the model counts with the class default"
    return out
  end
  out.name = names[out.tab]
  local k = keys[out.tab] or {}
  table.sort(k, function(a, b) if a.tier ~= b.tier then return a.tier > b.tier end return a.name < b.name end)
  out.keys = {}
  for i = 1, math.min(2, #k) do out.keys[i] = k[i].name end
  if out.manual then
    out.from = (L"chosen by hand on the Combat page (by your talents: %s)"):format(best and names[best] or (L"not yet"))
  else
    out.from = (L"most of your points (%d) are in the %s tree%s%s"):format(pts[out.tab], out.name,
      #out.keys > 0 and (L", and you have: " .. table.concat(out.keys, ", ")) or "",
      tie and (L" (a tie: the deeper talent decided)") or "")
  end
  return out
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
  notes[#notes + 1] = (L"1%% crit ≈ %s agility (worked back from your own stats)."):format(F1(agiPerCrit))

  -- talents (Talent.lua, the numbers of the rank's Wowhead Forever text): energy costs, damage %
  -- (Coup de Grace and Aggression add up on Eviscerate), crit bonus, off-hand, dodge/parry, combo points
  local ssCost = 45 - (tal.efficient or 0)
  local evisCost = 35 - (tal.flawless or 0)
  local evisBonus = 1 + ((tal.coup or 0) + (tal.aggression or 0)) / 100
  local function eq(slot) return equipped[slot] and equipped[slot].stats or M.ZERO end
  local sheet = {
    ap = input.ap or 0, crit = critNow, hit = input.hit or 0,
    mh = eq("MAIN_HAND").weapon, oh = eq("OFF_HAND").weapon,
  }
  for slot, key in pairs({ MAIN_HAND = "mh", OFF_HAND = "oh" }) do
    local w = sheet[key]
    if w and equipped[slot] then w.norm, w.sub = M.NormalizedSpeed(equipped[slot].sub), tonumber(equipped[slot].sub) end
  end

  local params = {
    level = level, agiPerCrit = agiPerCrit,
    whiteMissBase = sheet.oh and 24 or 5, yellowMissBase = 5,
    dodge = math.max(0, 5 - (tal.expertise or 0)), parry = 0, glance = 0, swingRate = 1,
    ssBonus = Round(level / 2), evisDamage = Round(12 * level * evisBonus),
    ssMult = 1 + (tal.aggression or 0) / 100, lethality = tal.lethality or 0,
    dualWield = tal.dualWield or 0, hackSlash = tal.hackSlash or 0,
    cycle = { ssCost = ssCost, evisCost = evisCost, ruthless = (tal.ruthlessness or 0) / 100,
      sealFate = (tal.sealFate or 0) / 100, refund = 5 * (tal.relentless or 0) / 100 * (tal.relentlessEnergy or 0) },
    otherDps = 0, statMult = 1, notes = notes,
  }
  local function Landed() return math.max(0, 1 - math.max(0, params.yellowMissBase - sheet.hit) / 100 - (params.dodge + params.parry) / 100) end
  params.ssPerSec, params.evisPerSec = M.RogueCycle(params, sheet.crit, Landed())

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
    local ss, evis
    for _, a in ipairs(combat.abilities) do
      if a.name == "Sinister Strike" and not ss then ss = a end
      if a.name == "Eviscerate" and not evis then evis = a end
    end
    if sheet.mh then
      -- Hack and Slash's extra attacks are white swings in the log too: expected with them
      local whiteLanded = math.max(0, 1 - (combat.white.miss + params.dodge + params.parry) / 100)
      local expected = (1 / sheet.mh.speed) * (1 + ExtraAttack(sheet.mh, params) * whiteLanded)
        + (sheet.oh and (1 / sheet.oh.speed) * (1 + ExtraAttack(sheet.oh, params) * whiteLanded) or 0)
        + (ss and (ss.hit + ss.crit) / secs or 0) * ExtraAttack(sheet.mh, params)
      params.swingRate = mix(1, wn / secs / expected, secs, 120)
    end
    params.ssPerSec = mix(params.ssPerSec, (ss and ss.n or 0) / secs, secs, 120)
    params.evisPerSec = mix(params.evisPerSec, (evis and evis.n or 0) / secs, secs, 120)
    if ss and sheet.mh and ss.hit + ss.crit > 0 then
      -- the logged damage already has Aggression and Lethality in it
      local normal = ss.dmg / (ss.hit + (2 + params.lethality / 100) * ss.crit) / params.ssMult
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
    notes[#notes + 1] = (L"Calibrated from %d recorded fights (%d s, %d auto-attacks): the measured values now weigh about %d%%, and grow with the sample.")
      :format(combat.fights, Round(secs), Round(wn), weight)
    notes[#notes + 1] = (L"Auto-attack: %s%% base miss, %s%% dodge, %s%% parry, %s%% glancing. Sinister Strike %s/min (+%d bonus), Eviscerate %s/min (%d damage), other sources %s DPS.")
      :format(F1(params.whiteMissBase), F1(params.dodge), F1(params.parry), F1(params.glance), F1(params.ssPerSec * 60),
        Round(params.ssBonus), F1(params.evisPerSec * 60), Round(params.evisDamage), F1(params.otherDps))
  else
    notes[#notes + 1] = L"No recorded fights, so it uses textbook values: 24% dual-wield miss, 5% dodge, hitting from behind, " ..
      L"Eviscerate after 5 Sinister Strikes. Turn on the combat log (/wa log) to calibrate."
  end

  -- the rates above are at the character's own crit; Seal Fate moves them with crit from here
  params.cycle.ref = { M.RogueCycle(params, sheet.crit, Landed()) }
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
    if add.weapon then add.weapon.norm, add.weapon.sub = M.NormalizedSpeed(sub, twoHand), tonumber(sub) end
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
    if not s then return (L"%s is not trained"):format(tostring(line)) end
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
