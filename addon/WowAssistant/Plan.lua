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
WA = WA or {}
local P = {}
WA.Plan = P
local M = WA.Model

-- What a rogue's trainer abilities are worth when leveling and running dungeons.
P.CORE = {
  Kick = "interrupt; in dungeons a must against caster mobs and bosses",
  Sap = "crowd control on pulls, takes one mob out of the fight",
  Feint = "lowers your threat if you pull aggro off the tank in a dungeon",
  Vanish = "emergency exit and aggro wipe",
  Evasion = "survival if something turns on you",
  Sprint = "mobility, escape",
  Gouge = "interrupt and getting behind the mob",
  ["Kidney Shot"] = "stun, good as an interrupt too",
  Blind = "a second crowd control",
  ["Slice and Dice"] = "auto-attack is most of your damage, this speeds it up",
  Stealth = "faster movement in stealth",
  ["Cheap Shot"] = "opening stun",
}
P.SITUATIONAL = {
  Backstab = "needs a dagger in the main hand and the target's back; not used in a Sinister Strike build",
  Ambush = "dagger opener from stealth",
  Garrote = "opening bleed, for longer fights",
  Rupture = "bleed; only worth it over Eviscerate in a long fight (boss)",
  ["Expose Armor"] = "armor reduction; only if there is no warrior in the group",
  Distract = "avoiding patrolling mobs",
  ["Deadly Poison"] = "better for long fights; on short mobs Instant Poison is stronger",
  ["Wound Poison"] = "healing reduction, mostly PvP",
}
P.SKIP = {
  ["Detect Traps"] = "almost never matters",
  ["Disarm Trap"] = "almost never matters",
  ["Pick Pocket"] = "pocket change, gives no DPS",
  ["Pick Lock"] = "a convenience skill",
  ["Safe Fall"] = "a convenience skill",
  ["Mind-numbing Poison"] = "only against casters, mostly PvP",
  ["Crippling Poison"] = "slow, mostly PvP",
}
local MUST = { Kick = true, ["Slice and Dice"] = true, Evasion = true, Sprint = true, Vanish = true }

-- The same for each class: core, situational, skip, must (bought first), the trainer's name.
P.CLASS = {
  ROGUE = { core = P.CORE, situational = P.SITUATIONAL, skip = P.SKIP, must = MUST, trainer = "Rogue trainer" },
  HUNTER = {
    trainer = "Hunter trainer",
    core = {
      ["Aspect of the Hawk"] = "more ranged AP: keep it up in every fight",
      ["Hunter's Mark"] = "more ranged AP against the marked target, and you see where it runs",
      ["Concussive Shot"] = "slow: the running mob, and kiting without a pet",
      ["Wing Clip"] = "slow in melee, then step back to shooting range",
      ["Feign Death"] = "aggro wipe and escape; a lifesaver in dungeons",
      ["Freezing Trap"] = "crowd control: takes one mob out of the pull in a dungeon",
      ["Mend Pet"] = "keeping the pet alive; without it the pet dies quickly",
      ["Revive Pet"] = "reviving the pet",
      ["Call Pet"] = "calling the pet",
      ["Tame Beast"] = "taming a pet; from 10 a good part of your damage comes from the pet",
      ["Feed Pet"] = "a happy pet deals more damage",
      ["Rapid Fire"] = "40% faster shooting for 15 s, for bosses",
      ["Aspect of the Cheetah"] = "faster travel",
      ["Aspect of the Monkey"] = "dodge in melee: important at low level, without a pet",
      Disengage = "takes the aggro off you in melee",
      ["Scare Beast"] = "a beast flees: a second crowd control",
      Volley = "AoE: for the multi-mob pulls in dungeons",
      ["Track Beasts"] = "shows beasts on the map",
      ["Track Humanoids"] = "shows humanoids on the map",
    },
    situational = {
      ["Serpent Sting"] = "for long fights; on short mobs the mana is better spent on Arcane Shot",
      ["Mongoose Bite"] = "only after a dodge, in melee",
      ["Distracting Shot"] = "pulling aggro off the tank or the pet",
      ["Tranquilizing Shot"] = "removing an enrage (Molten Core)",
      ["Viper Sting"] = "draining mana from casters",
      ["Scorpid Sting"] = "the mob hits less often; mostly PvP",
      ["Frost Trap"] = "a slowing zone, for kiting",
      ["Immolation Trap"] = "fire damage to whoever steps into the trap",
      ["Explosive Trap"] = "AoE trap",
      ["Aspect of the Wild"] = "nature resistance, only for certain bosses",
      ["Aspect of the Pack"] = "group travel; dazes you if you are hit",
      Flare = "reveals stealthed units",
      ["Dual Wield"] = "two one-handed weapons; a hunter's melee is small, rarely matters",
      ["Track Undead"] = "tracking is convenience",
      ["Track Elementals"] = "tracking is convenience",
      ["Track Demons"] = "tracking is convenience",
      ["Track Giants"] = "tracking is convenience",
      ["Track Dragonkin"] = "tracking is convenience",
      ["Track Hidden"] = "tracking is convenience",
    },
    skip = {
      ["Aspect of the Beast"] = "beasts cannot see; almost never needed",
      ["Eyes of the Beast"] = "you look through the pet's eyes; convenience",
      ["Beast Lore"] = "information about the beast; convenience",
      ["Dismiss Pet"] = "the pet can be released; rarely needed",
    },
    must = { ["Aspect of the Hawk"] = true, ["Mend Pet"] = true, ["Revive Pet"] = true, ["Feign Death"] = true,
      ["Freezing Trap"] = true, ["Rapid Fire"] = true, ["Hunter's Mark"] = true, ["Tame Beast"] = true, ["Call Pet"] = true },
  },
  SHAMAN = {
    trainer = "Shaman trainer",
    core = {
      ["Earth Shock"] = "instant damage and an interrupt: a must against caster mobs",
      ["Flame Shock"] = "damage + DoT; better than Earth Shock in a longer fight",
      ["Lightning Bolt"] = "pulling from range; when leveling better as an opener, the mana is needed for healing",
      ["Lightning Shield"] = "free damage when the mob hits you: keep it up in combat",
      ["Rockbiter Weapon"] = "weapon imbue: more damage on every hit (before Windfury)",
      ["Flametongue Weapon"] = "weapon imbue: fire damage on every hit",
      ["Windfury Weapon"] = "the strongest imbue from 30, especially with a slow two-handed weapon",
      ["Healing Wave"] = "healing: the shaman's rest between two fights when leveling",
      ["Lesser Healing Wave"] = "quick healing in combat",
      ["Searing Totem"] = "cheap, free damage in a longer fight",
      ["Strength of Earth Totem"] = "+strength: more AP for melee",
      ["Stoneskin Totem"] = "you take less damage",
      ["Ghost Wolf"] = "faster travel before the mount",
      Purge = "removes the mob's buffs (shield, haste)",
      ["Grace of Air Totem"] = "+agility for the group",
      ["Windfury Totem"] = "Windfury for the group's melee; a big boost in dungeons",
      ["Mana Spring Totem"] = "mana restoration for the group",
      ["Ancestral Spirit"] = "resurrection",
      Reincarnation = "self-resurrection with an Ankh",
      ["Astral Recall"] = "a second hearthstone",
    },
    situational = {
      ["Frost Shock"] = "slow: on the fleeing mob",
      ["Chain Lightning"] = "several targets; costs a lot of mana",
      ["Magma Totem"] = "AoE totem for multi-mob pulls",
      ["Fire Nova Totem"] = "AoE explosion; in dungeons",
      ["Frostbrand Weapon"] = "slowing imbue, mostly PvP",
      ["Earthbind Totem"] = "slow around the totem",
      ["Tremor Totem"] = "against fear (certain dungeons, PvP)",
      ["Poison Cleansing Totem"] = "against poison",
      ["Disease Cleansing Totem"] = "against disease",
      ["Cure Poison"] = "removing poison",
      ["Cure Disease"] = "removing disease",
      ["Healing Stream Totem"] = "small healing for the group",
      ["Chain Heal"] = "group healing in dungeons",
      ["Fire Resistance Totem"] = "fire resistance, for certain bosses",
      ["Frost Resistance Totem"] = "frost resistance, for certain bosses",
      ["Nature Resistance Totem"] = "nature resistance, for certain bosses",
      ["Grounding Totem"] = "absorbs one spell; mostly PvP",
      ["Sentry Totem"] = "scouting; rarely needed",
      ["Tranquil Air Totem"] = "less threat for the group",
      ["Windwall Totem"] = "against ranged damage",
    },
    skip = {
      ["Far Sight"] = "you see far; convenience",
      ["Water Breathing"] = "water breathing; rarely needed",
      ["Water Walking"] = "water walking; convenience",
    },
    must = { ["Earth Shock"] = true, ["Lightning Shield"] = true, ["Rockbiter Weapon"] = true, ["Windfury Weapon"] = true,
      ["Healing Wave"] = true, ["Searing Totem"] = true, ["Strength of Earth Totem"] = true, ["Ghost Wolf"] = true },
  },
  DRUID = {
    trainer = "Druid trainer",
    core = {
      Wrath = "damage from range: the main spell before Cat Form",
      Moonfire = "instant damage + DoT; can go while moving too",
      ["Cat Form"] = "the base of feral leveling: energy, combo points, no mana",
      Claw = "Cat Form's main combo point builder",
      Rake = "combo point + 9 s bleed; in a longer fight",
      Rip = "finisher: a bleed from combo points, for a long fight",
      ["Ferocious Bite"] = "finisher: instant damage, from the spare energy too",
      Shred = "a strong builder from behind the target (in a group, with a stun)",
      ["Bear Form"] = "tanking and survival; in dungeons",
      ["Dire Bear Form"] = "the stronger version of Bear Form",
      Maul = "the bear's main damage and threat",
      Swipe = "several targets as a bear",
      ["Healing Touch"] = "healing between two fights",
      Rejuvenation = "healing over time; before or during the fight",
      Regrowth = "quick healing + HoT",
      ["Mark of the Wild"] = "raises every stat: keep it up always",
      Thorns = "damages whoever hits you",
      ["Faerie Fire"] = "less armor on the target",
      ["Travel Form"] = "faster travel before the mount",
      Prowl = "stealth in Cat Form: open with Ravage or Pounce",
      Rebirth = "combat resurrection",
      Innervate = "mana restoration",
    },
    situational = {
      Starfire = "a slow, big spell; for Balance",
      ["Insect Swarm"] = "DoT (talent); for Balance",
      Hurricane = "AoE; for multi-mob pulls",
      ["Entangling Roots"] = "root: keeps the mob away",
      Bash = "stun as a bear",
      ["Demoralizing Roar"] = "the mobs hit for less",
      Growl = "threat for the bear",
      Enrage = "rage as a bear",
      ["Frenzied Regeneration"] = "healing from rage as a bear",
      Dash = "fast running in Cat Form",
      Cower = "lowering threat in a group",
      Pounce = "stunning opener from stealth",
      Ravage = "big opening hit from stealth, from behind the target",
      ["Feral Charge"] = "charge as a bear",
      ["Challenging Roar"] = "group aggro in dungeons",
      Barkskin = "less damage in an emergency",
      ["Remove Curse"] = "removing a curse",
      ["Abolish Poison"] = "removing poison",
      ["Cure Poison"] = "removing poison",
      Tranquility = "group healing",
      Hibernate = "putting a beast or dragonkin to sleep",
      ["Soothe Animal"] = "smaller aggro radius on beasts",
      ["Aquatic Form"] = "faster under water, and you breathe",
    },
    skip = {
      ["Teleport: Moonglade"] = "teleport to Moonglade; convenience",
      ["Track Humanoids"] = "humanoids on the minimap; convenience",
    },
    must = { Wrath = true, Moonfire = true, ["Cat Form"] = true, Claw = true, Rake = true, Rip = true, ["Ferocious Bite"] = true,
      ["Bear Form"] = true, ["Healing Touch"] = true, Rejuvenation = true, ["Mark of the Wild"] = true },
  },
  WARLOCK = {
    trainer = "Warlock trainer",
    core = {
      ["Shadow Bolt"] = "the main direct damage (1.7 s)",
      Corruption = "DoT: 12 s of damage, cheap; in every longer fight",
      ["Bane of Agony"] = "DoT: 24 s, with growing ticks; one Bane per target",
      Immolate = "fire damage + DoT",
      ["Life Tap"] = "mana from health: the engine of warlock leveling",
      ["Drain Life"] = "damage and healing at once",
      ["Drain Soul"] = "a Soul Shard from the dying mob (for the demons)",
      ["Summon Imp"] = "the first demon: damages from range",
      ["Summon Voidwalker"] = "tanks for you: the best for leveling",
      ["Summon Succubus"] = "a damage demon, high damage",
      ["Summon Felhunter"] = "against casters, mana drain",
      ["Demon Skin"] = "armor and health regeneration",
      ["Demon Armor"] = "the stronger version of Demon Skin",
      ["Health Funnel"] = "healing the demon",
      ["Create Healthstone"] = "a healing stone for yourself",
      Fear = "the mob runs away: time for the DoTs",
      ["Siphon Life"] = "a DoT that heals too (talent)",
      ["Death Coil"] = "terror + healing in an emergency",
      ["Searing Pain"] = "quick fire damage",
      ["Soul Fire"] = "big fire damage with a Soul Shard",
    },
    situational = {
      ["Bane of Doom"] = "big damage a minute later; only for a long fight",
      Hellfire = "AoE around you, burns you too",
      ["Rain of Fire"] = "AoE on an area",
      ["Howl of Terror"] = "several mobs run away",
      ["Curse of Weakness"] = "the mob hits for less",
      ["Curse of Recklessness"] = "the mob does not run away",
      ["Curse of Tongues"] = "slower casting for the mob",
      ["Curse of the Elements"] = "more spell damage on the target (in a group)",
      ["Curse of Exhaustion"] = "slow (talent)",
      Banish = "takes a demon or elemental out of the fight",
      ["Enslave Demon"] = "enslaving a demon",
      ["Drain Mana"] = "draining mana",
      ["Shadow Ward"] = "shadow protection",
      ["Create Soulstone"] = "self-resurrection",
      ["Create Firestone"] = "fire damage on the weapon",
      ["Create Spellstone"] = "spell protection",
      ["Ritual of Summoning"] = "summoning a group member",
      ["Detect Invisibility"] = "detecting invisibility",
      ["Sense Demons"] = "demons on the minimap",
      Shadowburn = "execute fire damage (talent)",
      Incinerate = "fire damage",
      Conflagrate = "detonating Immolate (talent)",
    },
    skip = {
      ["Eye of Kilrogg"] = "scouting eye; convenience",
      ["Unending Breath"] = "water breathing; rarely needed",
    },
    must = { ["Shadow Bolt"] = true, Corruption = true, ["Bane of Agony"] = true, ["Life Tap"] = true, ["Summon Voidwalker"] = true,
      ["Demon Skin"] = true, ["Drain Soul"] = true, ["Drain Life"] = true, Immolate = true },
  },
  MAGE = {
    trainer = "Mage trainer",
    core = {
      Frostbolt = "the main damage and slow (1.5–3 s, longer per rank)",
      Fireball = "the main fire damage (1.5–3.5 s) with a small DoT",
      ["Fire Blast"] = "instant fire damage, 8 s cooldown: while moving too",
      ["Arcane Missiles"] = "channeled arcane damage",
      ["Frost Nova"] = "nearby mobs freeze in place: distance and time",
      ["Arcane Intellect"] = "intellect: more mana",
      ["Frost Armor"] = "armor, and slows whoever hits you",
      ["Ice Armor"] = "the stronger version of Frost Armor",
      ["Mage Armor"] = "mana restoration, in combat too",
      ["Conjure Water"] = "free drink: the engine of mage leveling",
      ["Conjure Food"] = "free food",
      Evocation = "a lot of mana back over 8 s (8 min cooldown)",
      Blink = "20 yards forward, frees you from freezes and stuns",
      Polymorph = "takes one mob out of the fight",
      ["Counterspell"] = "interrupts a spell",
      ["Cone of Cold"] = "damages and slows in a close cone",
      ["Scorch"] = "quick fire damage (1.5 s)",
      ["Mana Shield"] = "you pay damage taken with mana",
      ["Conjure Mana Agate"] = "mana gem: free mana in combat",
      ["Conjure Mana Jade"] = "mana gem: free mana in combat",
      ["Conjure Mana Citrine"] = "mana gem: free mana in combat",
      ["Conjure Mana Ruby"] = "mana gem: free mana in combat",
    },
    situational = {
      ["Arcane Explosion"] = "AoE around you (on group pulls)",
      Blizzard = "AoE on an area, channeled",
      Flamestrike = "AoE on an area, with a DoT",
      ["Fire Ward"] = "absorbs fire damage",
      ["Frost Ward"] = "absorbs frost damage",
      ["Dampen Magic"] = "less spell damage and healing",
      ["Amplify Magic"] = "more spell damage and healing",
      ["Remove Lesser Curse"] = "removing a curse",
      ["Detect Magic"] = "you see the mob's buffs",
      ["Arcane Brilliance"] = "Arcane Intellect on the whole group",
      Pyroblast = "big opening fire damage (talent)",
      ["Blast Wave"] = "AoE and slow (talent)",
      ["Ice Barrier"] = "absorb shield (talent)",
    },
    skip = {
      ["Slow Fall"] = "slow fall; convenience",
      ["Teleport: Orgrimmar"] = "convenience travel", ["Teleport: Undercity"] = "convenience travel", ["Teleport: Thunder Bluff"] = "convenience travel",
      ["Teleport: Stormwind"] = "convenience travel", ["Teleport: Ironforge"] = "convenience travel", ["Teleport: Darnassus"] = "convenience travel",
      ["Portal: Orgrimmar"] = "group travel", ["Portal: Undercity"] = "group travel", ["Portal: Thunder Bluff"] = "group travel",
      ["Portal: Stormwind"] = "group travel", ["Portal: Ironforge"] = "group travel", ["Portal: Darnassus"] = "group travel",
    },
    must = { Frostbolt = true, Fireball = true, ["Fire Blast"] = true, ["Frost Nova"] = true, ["Arcane Intellect"] = true, ["Frost Armor"] = true,
      ["Conjure Water"] = true, ["Conjure Food"] = true, ["Arcane Missiles"] = true, Polymorph = true, Evocation = true, Blink = true },
  },
  WARRIOR = {
    trainer = "Warrior trainer",
    core = {
      ["Heroic Strike"] = "spare rage into damage on the next swing: the main rage spender",
      ["Battle Shout"] = "attack power for you and the group",
      Rend = "bleed: cheap damage in a longer fight",
      Charge = "opener: rage and a stun",
      ["Thunder Clap"] = "nearby mobs attack slower, damage",
      Overpower = "a strong hit after a dodge (Forever: spends combo points)",
      Hamstring = "slow: the fleeing mob does not get away",
      Execute = "execute below 20% health: the leftover rage is damage too",
      Bloodrage = "rage from health at the start of the fight",
      ["Sunder Armor"] = "armor reduction, threat when tanking",
      ["Demoralizing Shout"] = "the mobs hit for less",
      Cleave = "Heroic Strike on two targets",
      Slam = "a strong hit (Forever: 1.5 s cast, 15 s cooldown)",
      Whirlwind = "weapon damage on four nearby targets (Berserker Stance)",
      ["Berserker Stance"] = "more crit; the stance of Whirlwind and Intercept",
      ["Defensive Stance"] = "less damage, more threat: the tank stance",
      Taunt = "the mob attacks you (tank)",
      Revenge = "a cheap tank hit after a dodge or block",
      ["Shield Block"] = "more block (tank)",
      ["Victory Rush"] = "a free hit and healing after a kill",
    },
    situational = {
      ["Shield Bash"] = "interrupts a spell with the shield",
      Pummel = "interrupts a spell (Berserker Stance)",
      ["Intimidating Shout"] = "nearby mobs run away",
      ["Challenging Shout"] = "every nearby mob attacks you (tank, emergency)",
      ["Mocking Blow"] = "a short taunt",
      Disarm = "disarm",
      Retaliation = "hits back every attacker",
      ["Shield Wall"] = "much less damage (tank, emergency)",
      Recklessness = "certain crit, but you take more damage",
      Intercept = "charge in combat (Berserker Stance)",
      ["Berserker Rage"] = "against fear, rage",
      ["Mortal Strike"] = "weapon damage + healing reduction (Arms talent)",
      Bloodthirst = "an AP-based hit (Fury talent)",
      ["Shield Slam"] = "shield hit (Protection talent)",
    },
    skip = {
      ["Parry"] = "passive: you learn it automatically",
    },
    must = { ["Heroic Strike"] = true, ["Battle Shout"] = true, Rend = true, Charge = true, ["Thunder Clap"] = true, Overpower = true,
      Execute = true, Bloodrage = true, ["Defensive Stance"] = true, Taunt = true, ["Sunder Armor"] = true, Hamstring = true },
  },
  PRIEST = {
    trainer = "Priest trainer",
    core = {
      Smite = "holy damage (1.5–2.5 s): the first spell of leveling",
      ["Shadow Word: Pain"] = "shadow DoT for 18 s: cheap damage in every longer fight",
      ["Mind Blast"] = "strong shadow damage with an 8 s cooldown",
      ["Power Word: Shield"] = "absorb shield: less damage, the cast is not interrupted",
      ["Power Word: Fortitude"] = "stamina for you and the group",
      ["Inner Fire"] = "armor and attack power",
      Renew = "healing over time",
      ["Lesser Heal"] = "small heal (at low level)",
      Heal = "medium heal",
      ["Flash Heal"] = "quick heal (1.5 s)",
      ["Greater Heal"] = "big heal",
      Fade = "threat reduction: the mob goes to the tank",
      ["Psychic Scream"] = "nearby mobs run away",
      Resurrection = "resurrecting a dead group member",
      ["Holy Fire"] = "holy damage and DoT (3.5 s)",
      ["Mind Flay"] = "channeled shadow damage and slow (Shadow talent)",
      Shadowform = "+shadow damage, less damage taken (Shadow talent)",
    },
    situational = {
      ["Dispel Magic"] = "removes a magic debuff, removes a buff from the enemy",
      ["Cure Disease"] = "removing disease",
      ["Abolish Disease"] = "removing disease over time",
      ["Prayer of Healing"] = "healing the whole group (dungeon)",
      ["Shackle Undead"] = "takes an undead out of the fight",
      ["Mind Control"] = "controlling a humanoid",
      ["Mana Burn"] = "burning mana (PvP, caster mobs)",
      ["Shadow Protection"] = "shadow resistance",
      ["Holy Nova"] = "AoE damage and healing (talent)",
      ["Devouring Plague"] = "a disease DoT that heals (Undead)",
      ["Fear Ward"] = "against fear (Dwarf)",
      ["Inner Focus"] = "a free spell, more crit (talent)",
      ["Power Infusion"] = "a faster and stronger spell (talent)",
      ["Vampiric Embrace"] = "shadow damage heals the group (talent)",
      ["Divine Spirit"] = "spirit (talent)",
    },
    skip = {
      Levitate = "levitation; convenience",
      ["Mind Vision"] = "you see through the target's eyes; convenience",
      ["Mind Soothe"] = "humanoids notice you from closer: rarely needed",
    },
    must = { Smite = true, ["Shadow Word: Pain"] = true, ["Mind Blast"] = true, ["Power Word: Shield"] = true, ["Power Word: Fortitude"] = true,
      ["Inner Fire"] = true, Renew = true, ["Lesser Heal"] = true, Heal = true, ["Flash Heal"] = true, ["Greater Heal"] = true, Fade = true,
      ["Psychic Scream"] = true, Resurrection = true },
  },
  PALADIN = {
    trainer = "Paladin trainer",
    core = {
      ["Seal of Righteousness"] = "holy damage on every hit: the basic leveling seal",
      ["Holy Strike"] = "weapon damage + holy, 10 s cooldown (Forever)",
      Judgement = "releasing the seal: instant damage or effect",
      ["Blessing of Might"] = "attack power for you and the group",
      ["Devotion Aura"] = "armor for the group",
      ["Retribution Aura"] = "damages whoever hits you",
      ["Holy Light"] = "big heal",
      ["Flash of Light"] = "quick heal",
      ["Lay on Hands"] = "full heal in an emergency",
      ["Divine Protection"] = "short invulnerability",
      ["Divine Shield"] = "invulnerability",
      ["Hammer of Justice"] = "stun: interrupts, buys time",
      ["Seal of the Crusader"] = "faster swings, attack power; its Judgement raises holy damage",
      Consecration = "AoE holy damage under your feet",
      Exorcism = "big holy damage on undead and demons",
      ["Hammer of Wrath"] = "execute below 20% health",
      Redemption = "resurrecting a dead group member",
      Purify = "removing disease and poison",
      Cleanse = "removing disease, poison and magic",
      ["Seal of Command"] = "big holy damage on a chance: with a slow two-handed weapon (Retribution talent)",
    },
    situational = {
      ["Seal of Wisdom"] = "mana from your hits",
      ["Seal of Light"] = "healing from your hits",
      ["Seal of Justice"] = "a chance to stun, against fleeing",
      ["Seal of Fury"] = "holy damage on every hit; with a shield it also gives an absorb shield (Forever, for tanking)",
      ["Blessing of Wisdom"] = "mana restoration (for healers, casters)",
      ["Blessing of Kings"] = "all stats (talent)",
      ["Blessing of Salvation"] = "less threat (for non-tanks)",
      ["Blessing of Protection"] = "physical invulnerability for an ally",
      ["Blessing of Freedom"] = "against slows and roots",
      ["Blessing of Sanctuary"] = "less damage taken (talent, tank)",
      ["Righteous Fury"] = "more threat from holy damage (tank)",
      ["Holy Shield"] = "more block, holy damage on block (talent, tank)",
      ["Concentration Aura"] = "the cast is not interrupted",
      ["Holy Wrath"] = "AoE against undead and demons",
      ["Turn Undead"] = "an undead flees",
      ["Holy Shock"] = "damage or healing from range (talent)",
      ["Sense Undead"] = "you see undead on the map",
    },
    skip = {
      ["Shadow Resistance Aura"] = "shadow resistance: rarely needed",
      ["Frost Resistance Aura"] = "frost resistance: rarely needed",
      ["Fire Resistance Aura"] = "fire resistance: rarely needed",
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
      local tier, why, gain = "situational", "a new ability, it has no role in your current rotation", 0
      if share >= 2 then
        tier = "dps"
        gain = (share / 100) * 0.1 * ctx.baseline
        why = ("new rank: this ability is %.1f%% of your damage now"):format(share)
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
    bits[#bits + 1] = (M.SLOT_HU[s.slot] or s.slot) .. (eq and eq.name and (", replacing " .. eq.name) or "")
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
    local x = Option(o.item, "ah", o.price, o.where or "Auction house", ("%d listed"):format(o.listings or 0))
    if x then
      if o.item.reqLevel <= level then all[#all + 1] = x
      elseif o.item.reqLevel <= level + 4 then x.req = o.item.reqLevel soon[#soon + 1] = x end
    end
  end

  -- already in bags or bank
  local free = {}
  for _, item in ipairs(input.ownedGear or {}) do
    if item.reqLevel <= level then
      local x = Option(item, "owned", 0, "It is in your bags or your bank")
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
            local x = Option(item, "craft", cost, "Own " .. g.name,
              (#need > 0 and ("to buy: " .. table.concat(need, ", ")) or "you have every material") ..
              (isKnown and "" or " · the recipe has to be learned"))
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
      bits[#bits + 1] = (M.SLOT_HU[s.slot] or s.slot) .. (eq and eq.name and (", replacing " .. eq.name) or "")
      local o = {
        source = "quest", group = s.slot, title = r[3], quality = QUALITY[r[4] or -1], itemId = r[1],
        detail = table.concat(bits, " · "),
        where = (r[10] or "quest") .. " · " .. (r.zone or "?") .. (r[14] and ((", from level %d"):format(r[14])) or ""),
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
        detail = "basic ability: " .. s.why, where = info.trainer, cost = s.cost, gain = 0, gainPct = 0, estimated = false }
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
      note = (r.cap - r.skill <= 25 and r.cap < 300) and (("you stop at %d: learn the next rank at the trainer"):format(r.cap)) or nil,
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
