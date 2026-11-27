-- WoW Assistant: the purchase plan ("Haditerv"), ported from the web app (buildPlan in src/plan.ts).
-- Pure: Game.lua supplies the input in game, a test can supply the web app's own data.
--
-- input:
--   ctx         Model.Context(...)
--   gold        copper or nil
--   offers      { { item = GearItem, price, listings, where }, ... }  auction house, cheapest source wins
--   ownedGear   { GearItem, ... }                                      gear in bags and bank
--   crafts      { { name, known = {[recipe]=true}, recipes = { { name, product, reagents, trainingCost,
--                    fromTrainer, item = GearItem }, ... } }, ... }    recipes with orange <= skill
--   owned       { [itemId] = count }
--   book        price book (Routes.lua)
--   trainer     { { name, required_level, cost_copper, state, tradeskill }, ... }
--   questLoot   GameData loot rows with source "quest"; side = 1 Alliance, 2 Horde
--   routes      Routes.Plan(...) with target 300
--   warnings    data quality notes from the caller

local _, WA = ...
local L = WA.L
WA = WA or {}
local P = {}
WA.Plan = P
local M = WA.Model

-- What a rogue's trainer abilities are worth when leveling and running dungeons.
P.CORE = WA.LR {
  Kick = L"interrupt; in dungeons a must against caster mobs and bosses",
  Sap = L"crowd control on pulls, takes one mob out of the fight",
  Feint = L"lowers your threat if you pull aggro off the tank in a dungeon",
  Vanish = L"emergency exit and aggro wipe",
  Evasion = L"survival if something turns on you",
  Sprint = L"mobility, escape",
  Gouge = L"interrupt and getting behind the mob",
  ["Kidney Shot"] = L"stun, good as an interrupt too",
  Blind = L"a second crowd control",
  ["Slice and Dice"] = L"auto-attack is most of your damage, this speeds it up",
  Stealth = L"faster movement in stealth",
  ["Cheap Shot"] = L"opening stun",
}
P.SITUATIONAL = WA.LR {
  Backstab = L"needs a dagger in the main hand and the target's back; not used in a Sinister Strike build",
  Ambush = L"dagger opener from stealth",
  Garrote = L"opening bleed, for longer fights",
  Rupture = L"bleed; only worth it over Eviscerate in a long fight (boss)",
  ["Expose Armor"] = L"armor reduction; only if there is no warrior in the group",
  Distract = L"avoiding patrolling mobs",
  ["Deadly Poison"] = L"better for long fights; on short mobs Instant Poison is stronger",
  ["Wound Poison"] = L"healing reduction, mostly PvP",
}
P.SKIP = WA.LR {
  ["Detect Traps"] = L"almost never matters",
  ["Disarm Trap"] = L"almost never matters",
  ["Pick Pocket"] = L"pocket change, gives no DPS",
  ["Pick Lock"] = L"a convenience skill",
  ["Safe Fall"] = L"a convenience skill",
  ["Mind-numbing Poison"] = L"only against casters, mostly PvP",
  ["Crippling Poison"] = L"slow, mostly PvP",
}
local MUST = { Kick = true, ["Slice and Dice"] = true, Evasion = true, Sprint = true, Vanish = true }

-- The same for each class: core, situational, skip, must (bought first), the trainer's name.
P.CLASS = WA.LR {
  ROGUE = { core = P.CORE, situational = P.SITUATIONAL, skip = P.SKIP, must = MUST, trainer = "Rogue trainer" },
  HUNTER = {
    trainer = "Hunter trainer",
    core = {
      ["Aspect of the Hawk"] = L"more ranged AP: keep it up in every fight",
      ["Hunter's Mark"] = L"more ranged AP against the marked target, and you see where it runs",
      ["Concussive Shot"] = L"slow: the running mob, and kiting without a pet",
      ["Wing Clip"] = L"slow in melee, then step back to shooting range",
      ["Feign Death"] = L"aggro wipe and escape; a lifesaver in dungeons",
      ["Freezing Trap"] = L"crowd control: takes one mob out of the pull in a dungeon",
      ["Mend Pet"] = L"keeping the pet alive; without it the pet dies quickly",
      ["Revive Pet"] = L"reviving the pet",
      ["Call Pet"] = L"calling the pet",
      ["Tame Beast"] = L"taming a pet; from 10 a good part of your damage comes from the pet",
      ["Feed Pet"] = L"a happy pet deals more damage",
      ["Rapid Fire"] = L"40% faster shooting for 15 s, for bosses",
      ["Aspect of the Cheetah"] = L"faster travel",
      ["Aspect of the Monkey"] = L"dodge in melee: important at low level, without a pet",
      Disengage = L"takes the aggro off you in melee",
      ["Scare Beast"] = L"a beast flees: a second crowd control",
      Volley = L"AoE: for the multi-mob pulls in dungeons",
      ["Track Beasts"] = L"shows beasts on the map",
      ["Track Humanoids"] = L"shows humanoids on the map",
    },
    situational = {
      ["Serpent Sting"] = L"for long fights; on short mobs the mana is better spent on Arcane Shot",
      ["Mongoose Bite"] = L"only after a dodge, in melee",
      ["Distracting Shot"] = L"pulling aggro off the tank or the pet",
      ["Tranquilizing Shot"] = L"removing an enrage (Molten Core)",
      ["Viper Sting"] = L"draining mana from casters",
      ["Scorpid Sting"] = L"the mob hits less often; mostly PvP",
      ["Frost Trap"] = L"a slowing zone, for kiting",
      ["Immolation Trap"] = L"fire damage to whoever steps into the trap",
      ["Explosive Trap"] = L"AoE trap",
      ["Aspect of the Wild"] = L"nature resistance, only for certain bosses",
      ["Aspect of the Pack"] = L"group travel; dazes you if you are hit",
      Flare = L"reveals stealthed units",
      ["Dual Wield"] = L"two one-handed weapons; a hunter's melee is small, rarely matters",
      ["Track Undead"] = L"tracking is convenience",
      ["Track Elementals"] = L"tracking is convenience",
      ["Track Demons"] = L"tracking is convenience",
      ["Track Giants"] = L"tracking is convenience",
      ["Track Dragonkin"] = L"tracking is convenience",
      ["Track Hidden"] = L"tracking is convenience",
    },
    skip = {
      ["Aspect of the Beast"] = L"beasts cannot see; almost never needed",
      ["Eyes of the Beast"] = L"you look through the pet's eyes; convenience",
      ["Beast Lore"] = L"information about the beast; convenience",
      ["Dismiss Pet"] = L"the pet can be released; rarely needed",
    },
    must = { ["Aspect of the Hawk"] = true, ["Mend Pet"] = true, ["Revive Pet"] = true, ["Feign Death"] = true,
      ["Freezing Trap"] = true, ["Rapid Fire"] = true, ["Hunter's Mark"] = true, ["Tame Beast"] = true, ["Call Pet"] = true },
  },
  SHAMAN = {
    trainer = "Shaman trainer",
    core = {
      ["Earth Shock"] = L"instant damage and an interrupt: a must against caster mobs",
      ["Flame Shock"] = L"damage + DoT; better than Earth Shock in a longer fight",
      ["Lightning Bolt"] = L"pulling from range; when leveling better as an opener, the mana is needed for healing",
      ["Lightning Shield"] = L"free damage when the mob hits you: keep it up in combat",
      ["Rockbiter Weapon"] = L"weapon imbue: more damage on every hit (before Windfury)",
      ["Flametongue Weapon"] = L"weapon imbue: fire damage on every hit",
      ["Windfury Weapon"] = L"the strongest imbue from 30, especially with a slow two-handed weapon",
      ["Healing Wave"] = L"healing: the shaman's rest between two fights when leveling",
      ["Lesser Healing Wave"] = L"quick healing in combat",
      ["Searing Totem"] = L"cheap, free damage in a longer fight",
      ["Strength of Earth Totem"] = L"+strength: more AP for melee",
      ["Stoneskin Totem"] = L"you take less damage",
      ["Ghost Wolf"] = L"faster travel before the mount",
      Purge = L"removes the mob's buffs (shield, haste)",
      ["Grace of Air Totem"] = L"+agility for the group",
      ["Windfury Totem"] = L"Windfury for the group's melee; a big boost in dungeons",
      ["Mana Spring Totem"] = L"mana restoration for the group",
      ["Ancestral Spirit"] = L"resurrection",
      Reincarnation = L"self-resurrection with an Ankh",
      ["Astral Recall"] = L"a second hearthstone",
    },
    situational = {
      ["Frost Shock"] = L"slow: on the fleeing mob",
      ["Chain Lightning"] = L"several targets; costs a lot of mana",
      ["Magma Totem"] = L"AoE totem for multi-mob pulls",
      ["Fire Nova Totem"] = L"AoE explosion; in dungeons",
      ["Frostbrand Weapon"] = L"slowing imbue, mostly PvP",
      ["Earthbind Totem"] = L"slow around the totem",
      ["Tremor Totem"] = L"against fear (certain dungeons, PvP)",
      ["Poison Cleansing Totem"] = L"against poison",
      ["Disease Cleansing Totem"] = L"against disease",
      ["Cure Poison"] = L"removing poison",
      ["Cure Disease"] = L"removing disease",
      ["Healing Stream Totem"] = L"small healing for the group",
      ["Chain Heal"] = L"group healing in dungeons",
      ["Fire Resistance Totem"] = L"fire resistance, for certain bosses",
      ["Frost Resistance Totem"] = L"frost resistance, for certain bosses",
      ["Nature Resistance Totem"] = L"nature resistance, for certain bosses",
      ["Grounding Totem"] = L"absorbs one spell; mostly PvP",
      ["Sentry Totem"] = L"scouting; rarely needed",
      ["Tranquil Air Totem"] = L"less threat for the group",
      ["Windwall Totem"] = L"against ranged damage",
    },
    skip = {
      ["Far Sight"] = L"you see far; convenience",
      ["Water Breathing"] = L"water breathing; rarely needed",
      ["Water Walking"] = L"water walking; convenience",
    },
    must = { ["Earth Shock"] = true, ["Lightning Shield"] = true, ["Rockbiter Weapon"] = true, ["Windfury Weapon"] = true,
      ["Healing Wave"] = true, ["Searing Totem"] = true, ["Strength of Earth Totem"] = true, ["Ghost Wolf"] = true },
  },
  DRUID = {
    trainer = "Druid trainer",
    core = {
      Wrath = L"damage from range: the main spell before Cat Form",
      Moonfire = L"instant damage + DoT; can go while moving too",
      ["Cat Form"] = L"the base of feral leveling: energy, combo points, no mana",
      Claw = L"Cat Form's main combo point builder",
      Rake = L"combo point + 9 s bleed; in a longer fight",
      Rip = L"finisher: a bleed from combo points, for a long fight",
      ["Ferocious Bite"] = L"finisher: instant damage, from the spare energy too",
      Shred = L"a strong builder from behind the target (in a group, with a stun)",
      ["Bear Form"] = L"tanking and survival; in dungeons",
      ["Dire Bear Form"] = L"the stronger version of Bear Form",
      Maul = L"the bear's main damage and threat",
      Swipe = L"several targets as a bear",
      ["Healing Touch"] = L"healing between two fights",
      Rejuvenation = L"healing over time; before or during the fight",
      Regrowth = L"quick healing + HoT",
      ["Mark of the Wild"] = L"raises every stat: keep it up always",
      Thorns = L"damages whoever hits you",
      ["Faerie Fire"] = L"less armor on the target",
      ["Travel Form"] = L"faster travel before the mount",
      Prowl = L"stealth in Cat Form: open with Ravage or Pounce",
      Rebirth = L"combat resurrection",
      Innervate = L"mana restoration",
    },
    situational = {
      Starfire = L"a slow, big spell; for Balance",
      ["Insect Swarm"] = L"DoT (talent); for Balance",
      Hurricane = L"AoE; for multi-mob pulls",
      ["Entangling Roots"] = L"root: keeps the mob away",
      Bash = L"stun as a bear",
      ["Demoralizing Roar"] = L"the mobs hit for less",
      Growl = L"threat for the bear",
      Enrage = L"rage as a bear",
      ["Frenzied Regeneration"] = L"healing from rage as a bear",
      Dash = L"fast running in Cat Form",
      Cower = L"lowering threat in a group",
      Pounce = L"stunning opener from stealth",
      Ravage = L"big opening hit from stealth, from behind the target",
      ["Feral Charge"] = L"charge as a bear",
      ["Challenging Roar"] = L"group aggro in dungeons",
      Barkskin = L"less damage in an emergency",
      ["Remove Curse"] = L"removing a curse",
      ["Abolish Poison"] = L"removing poison",
      ["Cure Poison"] = L"removing poison",
      Tranquility = L"group healing",
      Hibernate = L"putting a beast or dragonkin to sleep",
      ["Soothe Animal"] = L"smaller aggro radius on beasts",
      ["Aquatic Form"] = L"faster under water, and you breathe",
    },
    skip = {
      ["Teleport: Moonglade"] = L"teleport to Moonglade; convenience",
      ["Track Humanoids"] = L"humanoids on the minimap; convenience",
    },
    must = { Wrath = true, Moonfire = true, ["Cat Form"] = true, Claw = true, Rake = true, Rip = true, ["Ferocious Bite"] = true,
      ["Bear Form"] = true, ["Healing Touch"] = true, Rejuvenation = true, ["Mark of the Wild"] = true },
  },
  WARLOCK = {
    trainer = "Warlock trainer",
    core = {
      ["Shadow Bolt"] = L"the main direct damage (1.7 s)",
      Corruption = L"DoT: 12 s of damage, cheap; in every longer fight",
      ["Bane of Agony"] = L"DoT: 24 s, with growing ticks; one Bane per target",
      Immolate = L"fire damage + DoT",
      ["Life Tap"] = L"mana from health: the engine of warlock leveling",
      ["Drain Life"] = L"damage and healing at once",
      ["Drain Soul"] = L"a Soul Shard from the dying mob (for the demons)",
      ["Summon Imp"] = L"the first demon: damages from range",
      ["Summon Voidwalker"] = L"tanks for you: the best for leveling",
      ["Summon Succubus"] = L"a damage demon, high damage",
      ["Summon Felhunter"] = L"against casters, mana drain",
      ["Demon Skin"] = L"armor and health regeneration",
      ["Demon Armor"] = L"the stronger version of Demon Skin",
      ["Health Funnel"] = L"healing the demon",
      ["Create Healthstone"] = L"a healing stone for yourself",
      Fear = L"the mob runs away: time for the DoTs",
      ["Siphon Life"] = L"a DoT that heals too (talent)",
      ["Death Coil"] = L"terror + healing in an emergency",
      ["Searing Pain"] = L"quick fire damage",
      ["Soul Fire"] = L"big fire damage with a Soul Shard",
    },
    situational = {
      ["Bane of Doom"] = L"big damage a minute later; only for a long fight",
      Hellfire = L"AoE around you, burns you too",
      ["Rain of Fire"] = L"AoE on an area",
      ["Howl of Terror"] = L"several mobs run away",
      ["Curse of Weakness"] = L"the mob hits for less",
      ["Curse of Recklessness"] = L"the mob does not run away",
      ["Curse of Tongues"] = L"slower casting for the mob",
      ["Curse of the Elements"] = L"more spell damage on the target (in a group)",
      ["Curse of Exhaustion"] = L"slow (talent)",
      Banish = L"takes a demon or elemental out of the fight",
      ["Enslave Demon"] = L"enslaving a demon",
      ["Drain Mana"] = L"draining mana",
      ["Shadow Ward"] = L"shadow protection",
      ["Create Soulstone"] = L"self-resurrection",
      ["Create Firestone"] = L"fire damage on the weapon",
      ["Create Spellstone"] = L"spell protection",
      ["Ritual of Summoning"] = L"summoning a group member",
      ["Detect Invisibility"] = L"detecting invisibility",
      ["Sense Demons"] = L"demons on the minimap",
      Shadowburn = L"execute fire damage (talent)",
      Incinerate = L"fire damage",
      Conflagrate = L"detonating Immolate (talent)",
    },
    skip = {
      ["Eye of Kilrogg"] = L"scouting eye; convenience",
      ["Unending Breath"] = L"water breathing; rarely needed",
    },
    must = { ["Shadow Bolt"] = true, Corruption = true, ["Bane of Agony"] = true, ["Life Tap"] = true, ["Summon Voidwalker"] = true,
      ["Demon Skin"] = true, ["Drain Soul"] = true, ["Drain Life"] = true, Immolate = true },
  },
  MAGE = {
    trainer = "Mage trainer",
    core = {
      Frostbolt = L"the main damage and slow (1.5–3 s, longer per rank)",
      Fireball = L"the main fire damage (1.5–3.5 s) with a small DoT",
      ["Fire Blast"] = L"instant fire damage, 8 s cooldown: while moving too",
      ["Arcane Missiles"] = L"channeled arcane damage",
      ["Frost Nova"] = L"nearby mobs freeze in place: distance and time",
      ["Arcane Intellect"] = L"intellect: more mana",
      ["Frost Armor"] = L"armor, and slows whoever hits you",
      ["Ice Armor"] = L"the stronger version of Frost Armor",
      ["Mage Armor"] = L"mana restoration, in combat too",
      ["Conjure Water"] = L"free drink: the engine of mage leveling",
      ["Conjure Food"] = L"free food",
      Evocation = L"a lot of mana back over 8 s (8 min cooldown)",
      Blink = L"20 yards forward, frees you from freezes and stuns",
      Polymorph = L"takes one mob out of the fight",
      ["Counterspell"] = L"interrupts a spell",
      ["Cone of Cold"] = L"damages and slows in a close cone",
      ["Scorch"] = L"quick fire damage (1.5 s)",
      ["Mana Shield"] = L"you pay damage taken with mana",
      ["Conjure Mana Agate"] = L"mana gem: free mana in combat",
      ["Conjure Mana Jade"] = L"mana gem: free mana in combat",
      ["Conjure Mana Citrine"] = L"mana gem: free mana in combat",
      ["Conjure Mana Ruby"] = L"mana gem: free mana in combat",
    },
    situational = {
      ["Arcane Explosion"] = L"AoE around you (on group pulls)",
      Blizzard = L"AoE on an area, channeled",
      Flamestrike = L"AoE on an area, with a DoT",
      ["Fire Ward"] = L"absorbs fire damage",
      ["Frost Ward"] = L"absorbs frost damage",
      ["Dampen Magic"] = L"less spell damage and healing",
      ["Amplify Magic"] = L"more spell damage and healing",
      ["Remove Lesser Curse"] = L"removing a curse",
      ["Detect Magic"] = L"you see the mob's buffs",
      ["Arcane Brilliance"] = L"Arcane Intellect on the whole group",
      Pyroblast = L"big opening fire damage (talent)",
      ["Blast Wave"] = L"AoE and slow (talent)",
      ["Ice Barrier"] = L"absorb shield (talent)",
    },
    skip = {
      ["Slow Fall"] = L"slow fall; convenience",
      ["Teleport: Orgrimmar"] = L"convenience travel", ["Teleport: Undercity"] = L"convenience travel", ["Teleport: Thunder Bluff"] = L"convenience travel",
      ["Teleport: Stormwind"] = L"convenience travel", ["Teleport: Ironforge"] = L"convenience travel", ["Teleport: Darnassus"] = L"convenience travel",
      ["Portal: Orgrimmar"] = L"group travel", ["Portal: Undercity"] = L"group travel", ["Portal: Thunder Bluff"] = L"group travel",
      ["Portal: Stormwind"] = L"group travel", ["Portal: Ironforge"] = L"group travel", ["Portal: Darnassus"] = L"group travel",
    },
    must = { Frostbolt = true, Fireball = true, ["Fire Blast"] = true, ["Frost Nova"] = true, ["Arcane Intellect"] = true, ["Frost Armor"] = true,
      ["Conjure Water"] = true, ["Conjure Food"] = true, ["Arcane Missiles"] = true, Polymorph = true, Evocation = true, Blink = true },
  },
  WARRIOR = {
    trainer = "Warrior trainer",
    core = {
      ["Heroic Strike"] = L"spare rage into damage on the next swing: the main rage spender",
      ["Battle Shout"] = L"attack power for you and the group",
      Rend = L"bleed: cheap damage in a longer fight",
      Charge = L"opener: rage and a stun",
      ["Thunder Clap"] = L"nearby mobs attack slower, damage",
      Overpower = L"a strong hit after a dodge (Forever: spends combo points)",
      Hamstring = L"slow: the fleeing mob does not get away",
      Execute = L"execute below 20% health: the leftover rage is damage too",
      Bloodrage = L"rage from health at the start of the fight",
      ["Sunder Armor"] = L"armor reduction, threat when tanking",
      ["Demoralizing Shout"] = L"the mobs hit for less",
      Cleave = L"Heroic Strike on two targets",
      Slam = L"a strong hit (Forever: 1.5 s cast, 15 s cooldown)",
      Whirlwind = L"weapon damage on four nearby targets (Berserker Stance)",
      ["Berserker Stance"] = L"more crit; the stance of Whirlwind and Intercept",
      ["Defensive Stance"] = L"less damage, more threat: the tank stance",
      Taunt = L"the mob attacks you (tank)",
      Revenge = L"a cheap tank hit after a dodge or block",
      ["Shield Block"] = L"more block (tank)",
      ["Victory Rush"] = L"a free hit and healing after a kill",
    },
    situational = {
      ["Shield Bash"] = L"interrupts a spell with the shield",
      Pummel = L"interrupts a spell (Berserker Stance)",
      ["Intimidating Shout"] = L"nearby mobs run away",
      ["Challenging Shout"] = L"every nearby mob attacks you (tank, emergency)",
      ["Mocking Blow"] = L"a short taunt",
      Disarm = L"disarm",
      Retaliation = L"hits back every attacker",
      ["Shield Wall"] = L"much less damage (tank, emergency)",
      Recklessness = L"certain crit, but you take more damage",
      Intercept = L"charge in combat (Berserker Stance)",
      ["Berserker Rage"] = L"against fear, rage",
      ["Mortal Strike"] = L"weapon damage + healing reduction (Arms talent)",
      Bloodthirst = L"an AP-based hit (Fury talent)",
      ["Shield Slam"] = L"shield hit (Protection talent)",
    },
    skip = {
      ["Parry"] = L"passive: you learn it automatically",
    },
    must = { ["Heroic Strike"] = true, ["Battle Shout"] = true, Rend = true, Charge = true, ["Thunder Clap"] = true, Overpower = true,
      Execute = true, Bloodrage = true, ["Defensive Stance"] = true, Taunt = true, ["Sunder Armor"] = true, Hamstring = true },
  },
  PRIEST = {
    trainer = "Priest trainer",
    core = {
      Smite = L"holy damage (1.5–2.5 s): the first spell of leveling",
      ["Shadow Word: Pain"] = L"shadow DoT for 18 s: cheap damage in every longer fight",
      ["Mind Blast"] = L"strong shadow damage with an 8 s cooldown",
      ["Power Word: Shield"] = L"absorb shield: less damage, the cast is not interrupted",
      ["Power Word: Fortitude"] = L"stamina for you and the group",
      ["Inner Fire"] = L"armor and attack power",
      Renew = L"healing over time",
      ["Lesser Heal"] = L"small heal (at low level)",
      Heal = L"medium heal",
      ["Flash Heal"] = L"quick heal (1.5 s)",
      ["Greater Heal"] = L"big heal",
      Fade = L"threat reduction: the mob goes to the tank",
      ["Psychic Scream"] = L"nearby mobs run away",
      Resurrection = L"resurrecting a dead group member",
      ["Holy Fire"] = L"holy damage and DoT (3.5 s)",
      ["Mind Flay"] = L"channeled shadow damage and slow (Shadow talent)",
      Shadowform = L"+shadow damage, less damage taken (Shadow talent)",
    },
    situational = {
      ["Dispel Magic"] = L"removes a magic debuff, removes a buff from the enemy",
      ["Cure Disease"] = L"removing disease",
      ["Abolish Disease"] = L"removing disease over time",
      ["Prayer of Healing"] = L"healing the whole group (dungeon)",
      ["Shackle Undead"] = L"takes an undead out of the fight",
      ["Mind Control"] = L"controlling a humanoid",
      ["Mana Burn"] = L"burning mana (PvP, caster mobs)",
      ["Shadow Protection"] = L"shadow resistance",
      ["Holy Nova"] = L"AoE damage and healing (talent)",
      ["Devouring Plague"] = L"a disease DoT that heals (Undead)",
      ["Fear Ward"] = L"against fear (Dwarf)",
      ["Inner Focus"] = L"a free spell, more crit (talent)",
      ["Power Infusion"] = L"a faster and stronger spell (talent)",
      ["Vampiric Embrace"] = L"shadow damage heals the group (talent)",
      ["Divine Spirit"] = "spirit (talent)",
    },
    skip = {
      Levitate = L"levitation; convenience",
      ["Mind Vision"] = L"you see through the target's eyes; convenience",
      ["Mind Soothe"] = L"humanoids notice you from closer: rarely needed",
    },
    must = { Smite = true, ["Shadow Word: Pain"] = true, ["Mind Blast"] = true, ["Power Word: Shield"] = true, ["Power Word: Fortitude"] = true,
      ["Inner Fire"] = true, Renew = true, ["Lesser Heal"] = true, Heal = true, ["Flash Heal"] = true, ["Greater Heal"] = true, Fade = true,
      ["Psychic Scream"] = true, Resurrection = true },
  },
  PALADIN = {
    trainer = "Paladin trainer",
    core = {
      ["Seal of Righteousness"] = L"holy damage on every hit: the basic leveling seal",
      ["Holy Strike"] = L"weapon damage + holy, 10 s cooldown (Forever)",
      Judgement = L"releasing the seal: instant damage or effect",
      ["Blessing of Might"] = L"attack power for you and the group",
      ["Devotion Aura"] = L"armor for the group",
      ["Retribution Aura"] = L"damages whoever hits you",
      ["Holy Light"] = L"big heal",
      ["Flash of Light"] = L"quick heal",
      ["Lay on Hands"] = L"full heal in an emergency",
      ["Divine Protection"] = L"short invulnerability",
      ["Divine Shield"] = L"invulnerability",
      ["Hammer of Justice"] = L"stun: interrupts, buys time",
      ["Seal of the Crusader"] = L"faster swings, attack power; its Judgement raises holy damage",
      Consecration = L"AoE holy damage under your feet",
      Exorcism = L"big holy damage on undead and demons",
      ["Hammer of Wrath"] = L"execute below 20% health",
      Redemption = L"resurrecting a dead group member",
      Purify = L"removing disease and poison",
      Cleanse = L"removing disease, poison and magic",
      ["Seal of Command"] = L"big holy damage on a chance: with a slow two-handed weapon (Retribution talent)",
    },
    situational = {
      ["Seal of Wisdom"] = L"mana from your hits",
      ["Seal of Light"] = L"healing from your hits",
      ["Seal of Justice"] = L"a chance to stun, against fleeing",
      ["Seal of Fury"] = L"holy damage on every hit; with a shield it also gives an absorb shield (Forever, for tanking)",
      ["Blessing of Wisdom"] = L"mana restoration (for healers, casters)",
      ["Blessing of Kings"] = L"all stats (talent)",
      ["Blessing of Salvation"] = L"less threat (for non-tanks)",
      ["Blessing of Protection"] = L"physical invulnerability for an ally",
      ["Blessing of Freedom"] = L"against slows and roots",
      ["Blessing of Sanctuary"] = L"less damage taken (talent, tank)",
      ["Righteous Fury"] = L"more threat from holy damage (tank)",
      ["Holy Shield"] = L"more block, holy damage on block (talent, tank)",
      ["Concentration Aura"] = L"the cast is not interrupted",
      ["Holy Wrath"] = L"AoE against undead and demons",
      ["Turn Undead"] = L"an undead flees",
      ["Holy Shock"] = L"damage or healing from range (talent)",
      ["Sense Undead"] = L"you see undead on the map",
    },
    skip = {
      ["Shadow Resistance Aura"] = L"shadow resistance: rarely needed",
      ["Frost Resistance Aura"] = L"frost resistance: rarely needed",
      ["Fire Resistance Aura"] = L"fire resistance: rarely needed",
    },
    must = { ["Seal of Righteousness"] = true, ["Holy Strike"] = true, Judgement = true, ["Blessing of Might"] = true, ["Devotion Aura"] = true,
      ["Holy Light"] = true, ["Flash of Light"] = true, ["Lay on Hands"] = true, ["Divine Protection"] = true, ["Hammer of Justice"] = true,
      Consecration = true, Redemption = true },
  },
}
local function ClassInfo(ctx) return P.CLASS[ctx.class or "ROGUE"] or P.CLASS.ROGUE end
local function BaseName(n) return (n:gsub("%s+[IVX]+$", "")) end
local QUALITY = { [0] = "POOR", "COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY" }
local TIER_ORDER = { dps = 0, core = 1, situational = 2, skip = 3 }

function P.RankSkills(rows, ctx)
  local info = ClassInfo(ctx)
  local shares = {}
  for _, a in ipairs(ctx.combat and ctx.combat.abilities or {}) do
    local key = BaseName((a.name:gsub(" %(dot%)$", "")))
    shares[key] = (shares[key] or 0) + a.share
  end
  local out = {}
  for _, r in ipairs(rows) do
    if r.state == "available" and (r.tradeskill or 0) == 0 then
      local base = BaseName(r.name)
      local share = shares[base] or 0
      local tier, why, gain = "situational", L"a new ability, it has no role in your current rotation", 0
      if share >= 2 then
        tier = "dps"
        gain = (share / 100) * 0.1 * ctx.baseline
        why = (L"new rank: this ability is %.1f%% of your damage now"):format(share)
      elseif info.core[base] then tier, why = "core", info.core[base]
      elseif info.skip[base] then tier, why = "skip", info.skip[base]
      elseif info.situational[base] then why = info.situational[base]
      end
      out[#out + 1] = { name = r.name, level = r.required_level, cost = r.cost_copper, tier = tier, why = why, gain = gain }
    end
  end
  return M.Stable(out, function(a, b)
    if TIER_ORDER[a.tier] ~= TIER_ORDER[b.tier] then return TIER_ORDER[a.tier] < TIER_ORDER[b.tier] end
    if b.gain ~= a.gain then return b.gain < a.gain end
    return a.cost < b.cost
  end)
end

-- Multiple-choice knapsack: at most one option per group, total cost within the budget,
-- maximum total DPS. Costs are bucketed so the table stays small.
function P.Allocate(options, budget)
  if budget <= 0 then return {} end
  local unit = math.max(100, math.ceil(budget / 4000))
  local cap = math.floor(budget / unit)
  local groups, lists = {}, {}
  for _, o in ipairs(options) do
    if o.cost <= budget and o.gain > 0 then
      local list = groups[o.group]
      if not list then
        list = {}
        groups[o.group] = list
        lists[#lists + 1] = list
      end
      list[#list + 1] = o
    end
  end
  local best = {}
  for b = 0, cap do best[b] = 0 end
  local picks = {}
  for g, list in ipairs(lists) do
    local nextBest, pick = {}, {}
    for b = 0, cap do nextBest[b] = best[b] pick[b] = -1 end
    for idx, o in ipairs(list) do
      local c = math.ceil(o.cost / unit)
      for b = cap, c, -1 do
        local v = best[b - c] + o.gain
        if v > nextBest[b] + 1e-9 then
          nextBest[b] = v
          pick[b] = idx
        end
      end
    end
    best = nextBest
    picks[g] = pick
  end
  local chosen = {}
  local b = cap
  for g = #lists, 1, -1 do
    local idx = picks[g][b]
    if idx >= 0 then
      local o = lists[g][idx]
      chosen[#chosen + 1] = o
      b = b - math.ceil(o.cost / unit)
    end
  end
  return M.Stable(chosen, function(x, y) return x.gain > y.gain end)
end

local function Copy(o)
  local t = {}
  for k, v in pairs(o) do t[k] = v end
  return t
end

function P.Build(input)
  local ctx = input.ctx
  local level, baseline = ctx.level, ctx.baseline
  local gold = input.gold
  local book = input.book

  local info = ClassInfo(ctx)
  local function Option(item, source, cost, where, extra)
    if ctx.equippedIds[item.itemId] then return nil end
    if not ctx.usable(item.itemClass, item.subclass) then return nil end
    local slots, twoHand = ctx.invSlots(item.slot)
    if not slots then return nil end
    local s = ctx.score(item.stats, slots, twoHand, item.subclass)
    if not s then return nil end
    local eq = ctx.equipped[s.slot]
    local bits = {}
    local d = ctx.describe(item.stats, item.subclass)
    if d ~= "" then bits[#bits + 1] = d end
    bits[#bits + 1] = (M.SLOT_HU[s.slot] or s.slot) .. (eq and eq.name and L(", replacing %s"):format(eq.name) or "")
    if extra and extra ~= "" then bits[#bits + 1] = extra end
    return {
      source = source, group = s.slot, title = item.name, quality = item.quality, itemId = item.itemId,
      detail = table.concat(bits, " · "), where = where, cost = cost, gain = s.gain, gainPct = s.gain / baseline * 100,
      estimated = false, warning = ctx.weaponWarning(item.itemClass, item.subclass),
    }
  end

  -- auction house
  local all, soon = {}, {}
  for _, o in ipairs(input.offers or {}) do
    local x = Option(o.item, "ah", o.price, o.where or (L"Auction house"), (L"%d listed"):format(o.listings or 0))
    if x then
      if o.item.reqLevel <= level then all[#all + 1] = x
      elseif o.item.reqLevel <= level + 4 then x.req = o.item.reqLevel soon[#soon + 1] = x end
    end
  end

  -- already in bags or bank
  local free = {}
  for _, item in ipairs(input.ownedGear or {}) do
    if item.reqLevel <= level then
      local x = Option(item, "owned", 0, L"It is in your bags or your bank")
      if x then free[#free + 1] = x end
    end
  end

  -- things you can craft yourself
  local owned = input.owned or {}
  for _, g in ipairs(input.crafts or {}) do
    for _, r in ipairs(g.recipes) do
      local item = r.item
      if item and item.reqLevel <= level then
        local isKnown = g.known[r.name] == true
        if isKnown or (r.fromTrainer and r.trainingCost ~= nil) then
          local mats, priced, need = 0, true, {}
          for i = 1, #r.reagents, 2 do
            local id, qty = r.reagents[i], r.reagents[i + 1]
            local have = math.min(qty, owned[id] or 0)
            local u = book.unit(id)
            if qty - have > 0 then
              if not u then priced = false else mats = mats + u.price * (qty - have) end
              need[#need + 1] = ("%d× %s"):format(qty - have, book.name(id))
            end
          end
          if priced then
            local cost = M.Round(mats + (isKnown and 0 or r.trainingCost))
            local x = Option(item, "craft", cost, L"Own " .. g.name,
              (#need > 0 and (L"to buy: " .. table.concat(need, ", ")) or (L"you have every material")) ..
              (isKnown and "" or (L" · the recipe has to be learned")))
            if x then
              if cost == 0 then free[#free + 1] = x else all[#all + 1] = x end
            end
          end
        end
      end
    end
  end

  -- trainer skills
  local skills = P.RankSkills(input.trainer or {}, ctx)
  for _, s in ipairs(skills) do
    if s.tier == "dps" and s.cost > 0 then
      all[#all + 1] = { source = "trainer", group = "skill:" .. s.name, title = s.name, detail = s.why, where = info.trainer,
        cost = s.cost, gain = s.gain, gainPct = s.gain / baseline * 100, estimated = true }
    end
  end

  -- quest rewards
  local questBest, questOrder = {}, {}
  for _, r in ipairs(input.questLoot or {}) do
    local slots, twoHand = ctx.lootSlots(r[7])
    local cls, sub = r[8], r[9]
    local ok = slots and not ctx.equippedIds[r[1]] and ctx.usable(cls, sub)
    local stats = ok and M.LootStats(r)
    if stats and cls == 2 and not stats.weapon then stats = nil end
    local s = stats and ctx.score(stats, slots, twoHand, sub)
    if s then
      local eq = ctx.equipped[s.slot]
      local bits = {}
      local d = ctx.describe(stats, sub)
      if d ~= "" then bits[#bits + 1] = d end
      bits[#bits + 1] = (M.SLOT_HU[s.slot] or s.slot) .. (eq and eq.name and L(", replacing %s"):format(eq.name) or "")
      local o = {
        source = "quest", group = s.slot, title = r[3], quality = QUALITY[r[4] or -1], itemId = r[1],
        detail = table.concat(bits, " · "),
        where = (r[10] or "quest") .. " · " .. (r.zone or "?") .. (r[14] and ((L", from level %d"):format(r[14])) or ""),
        cost = 0, gain = s.gain, gainPct = s.gain / baseline * 100, estimated = false, warning = ctx.weaponWarning(cls, sub),
      }
      local cur = questBest[o.title]
      if not cur then questOrder[#questOrder + 1] = o.title end
      if not cur or o.gain > cur.gain then questBest[o.title] = o end
    end
  end
  local quests = {}
  for _, t in ipairs(questOrder) do quests[#quests + 1] = questBest[t] end
  M.Stable(quests, function(a, b) return a.gain > b.gain end)
  while #quests > 8 do table.remove(quests) end

  -- The same item can be both on the AH and craftable: keep the cheaper way.
  local cheapest, cheapOrder = {}, {}
  for _, o in ipairs(all) do
    local key = o.group .. "|" .. o.title
    local cur = cheapest[key]
    if not cur then cheapOrder[#cheapOrder + 1] = key end
    if not cur or o.cost < cur.cost then cheapest[key] = o end
  end
  local options = {}
  for _, k in ipairs(cheapOrder) do options[#options + 1] = cheapest[k] end

  -- Free upgrades first: they change what is worth buying for that slot.
  M.Stable(free, function(a, b) return a.gain > b.gain end)
  local bestFree, freeList = {}, {}
  for _, o in ipairs(free) do
    if not bestFree[o.group] then bestFree[o.group] = o freeList[#freeList + 1] = o end
  end
  local payable = {}
  for _, o in ipairs(options) do
    local f = bestFree[o.group]
    local x = o
    if f then
      x = Copy(o)
      x.gain = o.gain - f.gain
      x.gainPct = (o.gain - f.gain) / baseline * 100
    end
    if x.gain > 0.05 then payable[#payable + 1] = x end
  end

  -- Reserve the basics first, cheapest first, then spend the rest on damage.
  local reserved = {}
  local budget = gold or 0
  local basics = {}
  for _, s in ipairs(skills) do
    if s.tier == "core" and info.must[BaseName(s.name)] then basics[#basics + 1] = s end
  end
  M.Stable(basics, function(a, b) return a.cost < b.cost end)
  for _, s in ipairs(basics) do
    if s.cost <= budget then
      budget = budget - s.cost
      reserved[#reserved + 1] = { source = "trainer", group = "skill:" .. s.name, title = s.name,
        detail = L"basic ability: " .. s.why, where = info.trainer, cost = s.cost, gain = 0, gainPct = 0, estimated = false }
    end
  end
  local buy = {}
  if gold then
    for _, o in ipairs(reserved) do buy[#buy + 1] = o end
    for _, o in ipairs(P.Allocate(payable, budget)) do buy[#buy + 1] = o end
  end
  local spent = 0
  local taken = {}
  for _, o in ipairs(buy) do spent = spent + o.cost taken[o.group] = true end

  -- What you would buy next with more gold: the best option per group you have not covered.
  M.Stable(payable, function(a, b) return a.gain > b.gain end)
  local wishBest, wishlist = {}, {}
  for _, o in ipairs(payable) do
    if not taken[o.group] and not (gold and o.cost <= gold - spent) and not wishBest[o.group] then
      wishBest[o.group] = o
      wishlist[#wishlist + 1] = o
    end
  end
  M.Stable(wishlist, function(a, b) return a.gain / a.cost > b.gain / b.cost end)
  while #wishlist > 6 do table.remove(wishlist) end

  -- dungeons, professions
  local report = M.GearReport(ctx, 3, input.data)
  local farm = {}
  for i = 1, math.min(3, #report.dungeons) do farm[i] = report.dungeons[i] end
  local professions = {}
  for _, r in ipairs(input.routes or {}) do
    local first
    for _, s in ipairs(r.steps) do if s.from < r.cap then first = s break end end
    professions[#professions + 1] = {
      name = r.profession, skill = r.skill, cap = r.cap,
      next = first and ("%s ×%d (%d → %d)"):format(first.recipe, first.crafts, first.from, math.min(first.to, r.cap)) or nil,
      cost = first and M.Round(first.matsCost + first.trainingCost) or 0,
      note = (r.cap - r.skill <= 25 and r.cap < 300) and ((L"you stop at %d: learn the next rank at the trainer"):format(r.cap)) or nil,
    }
  end

  -- consumables: what an hour of each buff costs at auction house prices
  local selectedAlready = {}
  for _, b in ipairs(ctx.buffs) do if b.selected then selectedAlready[b.name] = true end end
  local consumables = {}
  for _, c in ipairs(M.ConsumablesFor(level, input.data)) do
    if not selectedAlready[c.name] then
      local u = book.unit(c.itemId)
      local price = u and u.price or nil
      local gain = ctx.buffGain(c.effect)
      if gain > 0.05 then
        consumables[#consumables + 1] = { name = c.name, itemId = c.itemId, summary = c.summary, gain = gain, price = price,
          minutes = c.minutes, perHour = price and M.Round(price * (60 / c.minutes)) or nil }
      end
    end
  end
  M.Stable(consumables, function(a, b)
    local x = (b.perHour and b.perHour ~= 0) and b.gain / b.perHour or -1
    local y = (a.perHour and a.perHour ~= 0) and a.gain / a.perHour or -1
    return y > x
  end)

  -- what the next levels bring
  local roadmap = {}
  for l = level + 1, level + 4 do
    local rows, cost = {}, 0
    for _, r in ipairs(input.trainer or {}) do
      if r.state == "unavailable" and (r.tradeskill or 0) == 0 and r.required_level == l then
        rows[#rows + 1] = r.name
        cost = cost + r.cost_copper
      end
    end
    local gear = {}
    for _, o in ipairs(soon) do if o.req == l then gear[#gear + 1] = o end end
    M.Stable(gear, function(a, b) return a.gain > b.gain end)
    while #gear > 2 do table.remove(gear) end
    if #rows > 0 or #gear > 0 then roadmap[#roadmap + 1] = { level = l, skillCost = cost, skills = rows, gear = gear } end
  end

  local projected = baseline
  for _, o in ipairs(buy) do projected = projected + o.gain end
  for _, o in ipairs(freeList) do projected = projected + o.gain end
  -- combat advice: the rogue's comes from Combat.lua, other classes bring their own
  local combat = {}
  for _, a in ipairs(ctx.advice or (ctx.combat and ctx.combat.advice) or {}) do
    if a.level ~= "info" then combat[#combat + 1] = a end
  end

  -- ammo (hunters): the best vendor ammo for this level against what is in the ammo slot
  local ammo = {}
  if ctx.ammoGain and ctx.ammoKind then
    for _, a in ipairs(input.ammo or {}) do
      if a.kind == ctx.ammoKind and a.reqLevel <= level then
        local gain = ctx.ammoGain(a.dps)
        -- what you have, and only the ammo that is better than it
        if a.current or gain > 0.05 then ammo[#ammo + 1] = { name = a.name, itemId = a.itemId, dps = a.dps, reqLevel = a.reqLevel, gain = gain,
          gainPct = gain / baseline * 100, current = a.current, price = a.price, priceSource = a.priceSource,
          perHour = a.price and (ctx.shotsPerSec or 0) > 0 and a.price * ctx.shotsPerSec * 3600 or nil } end
      end
    end
    M.Stable(ammo, function(a, b) return a.dps > b.dps end)
    while #ammo > 3 do table.remove(ammo) end
  end
  return {
    name = input.name or "", level = level, gold = gold, baseline = baseline, unbuffed = ctx.unbuffed,
    measuredDps = ctx.combat and ctx.combat.dps or nil, projected = projected,
    buy = buy, spent = spent, left = gold and (gold - spent) or nil, wishlist = wishlist, free = freeList,
    quests = quests, combat = combat, skills = skills, farm = farm, professions = professions, roadmap = roadmap,
    consumables = consumables, warnings = input.warnings or {}, ammo = ammo, class = ctx.class,
    shotsPerHour = (ctx.shotsPerSec or 0) * 3600,
  }
end
