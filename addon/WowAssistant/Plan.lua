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
  Kick = "megszakítás; dungeonben a caster mobok és bossok ellen alap",
  Sap = "tömegkontroll a húzásoknál, egy mobot kivesz a harcból",
  Feint = "csökkenti az aggródat, ha dungeonben átveszed a tanktól",
  Vanish = "vészkijárat és aggro-törlés",
  Evasion = "túlélés, ha rád fordul valami",
  Sprint = "mobilitás, menekülés",
  Gouge = "megszakítás és helyezkedés a mob mögé",
  ["Kidney Shot"] = "stun, megszakításnak is jó",
  Blind = "második tömegkontroll",
  ["Slice and Dice"] = "az auto-attack a sebzésed nagyja, ez gyorsítja",
  Stealth = "gyorsabb mozgás lopakodva",
  ["Cheap Shot"] = "nyitó stun",
}
P.SITUATIONAL = {
  Backstab = "tőr kell hozzá a főkézbe és a célpont háta; Sinister Strike buildben nem használod",
  Ambush = "tőrös nyitás lopakodásból",
  Garrote = "nyitó vérzés, hosszabb harcokra",
  Rupture = "vérzés; csak hosszú harcban (boss) éri meg az Eviscerate helyett",
  ["Expose Armor"] = "páncélcsökkentés; csak akkor, ha nincs warrior a csapatban",
  Distract = "járőröző mobok kikerülése",
  ["Deadly Poison"] = "hosszú harcokra jobb, rövid mobokra az Instant Poison erősebb",
  ["Wound Poison"] = "gyógyításcsökkentés, inkább PvP",
}
P.SKIP = {
  ["Detect Traps"] = "szinte soha nem számít",
  ["Disarm Trap"] = "szinte soha nem számít",
  ["Pick Pocket"] = "aprópénz, DPS-t nem ad",
  ["Pick Lock"] = "kényelmi skill",
  ["Safe Fall"] = "kényelmi skill",
  ["Mind-numbing Poison"] = "csak casterek ellen, főleg PvP",
  ["Crippling Poison"] = "lassítás, főleg PvP",
}
local MUST = { Kick = true, ["Slice and Dice"] = true, Evasion = true, Sprint = true, Vanish = true }

-- The same for each class: core, situational, skip, must (bought first), the trainer's name.
P.CLASS = {
  ROGUE = { core = P.CORE, situational = P.SITUATIONAL, skip = P.SKIP, must = MUST, trainer = "Rogue trainer" },
  HUNTER = {
    trainer = "Hunter trainer",
    core = {
      ["Aspect of the Hawk"] = "több ranged AP: harcban mindig ez legyen fent",
      ["Hunter's Mark"] = "több ranged AP a megjelölt célpont ellen, és látod, hova fut",
      ["Concussive Shot"] = "lassítás: a futó mob, és kiting pet nélkül",
      ["Wing Clip"] = "lassítás közelharcban, utána hátralépés lőtávolba",
      ["Feign Death"] = "aggro-törlés és menekülés; dungeonben életmentő",
      ["Freezing Trap"] = "tömegkontroll: dungeonben egy mobot kivesz a húzásból",
      ["Mend Pet"] = "a pet életben tartása; nélküle a pet hamar elhullik",
      ["Revive Pet"] = "a pet feltámasztása",
      ["Call Pet"] = "a pet előhívása",
      ["Tame Beast"] = "pet szelídítése; 10-től a sebzésed jó része a petből jön",
      ["Feed Pet"] = "a boldog pet többet sebez",
      ["Rapid Fire"] = "40%-kal gyorsabb lövés 15 mp-re, bossokra",
      ["Aspect of the Cheetah"] = "gyorsabb utazás",
      ["Aspect of the Monkey"] = "dodge közelharcban: alacsony szinten, pet nélkül fontos",
      Disengage = "leveszi rólad az aggrót közelharcban",
      ["Scare Beast"] = "egy állat elmenekül: második tömegkontroll",
      Volley = "AoE: dungeonben a sok mobos húzásokra",
      ["Track Beasts"] = "látod a térképen a vadat",
      ["Track Humanoids"] = "látod a térképen a humanoidokat",
    },
    situational = {
      ["Serpent Sting"] = "hosszú harcokra; rövid mobokon a mana jobb helyen van az Arcane Shotban",
      ["Mongoose Bite"] = "csak dodge után, közelharcban",
      ["Distracting Shot"] = "aggro elhúzása a tanktól vagy a pettől",
      ["Tranquilizing Shot"] = "enrage leszedése (Molten Core)",
      ["Viper Sting"] = "mana elvétele casterektől",
      ["Scorpid Sting"] = "a mob ritkábban talál; inkább PvP",
      ["Frost Trap"] = "lassító zóna, kitinghez",
      ["Immolation Trap"] = "tűzsebzés a csapdába lépőre",
      ["Explosive Trap"] = "AoE csapda",
      ["Aspect of the Wild"] = "nature resist, csak bizonyos bossokra",
      ["Aspect of the Pack"] = "csoportos utazás; ha megütnek, elkábít",
      Flare = "lopakodók felfedése",
      ["Dual Wield"] = "két egykezes fegyver; a hunter közelharca kicsi, ritkán számít",
      ["Track Undead"] = "a nyomkövetés kényelmi",
      ["Track Elementals"] = "a nyomkövetés kényelmi",
      ["Track Demons"] = "a nyomkövetés kényelmi",
      ["Track Giants"] = "a nyomkövetés kényelmi",
      ["Track Dragonkin"] = "a nyomkövetés kényelmi",
      ["Track Hidden"] = "a nyomkövetés kényelmi",
    },
    skip = {
      ["Aspect of the Beast"] = "az állatok nem látnak; szinte soha nem kell",
      ["Eyes of the Beast"] = "a pet szemével nézel; kényelmi",
      ["Beast Lore"] = "információ a vadról; kényelmi",
      ["Dismiss Pet"] = "a petet el lehet küldeni; ritkán kell",
    },
    must = { ["Aspect of the Hawk"] = true, ["Mend Pet"] = true, ["Revive Pet"] = true, ["Feign Death"] = true,
      ["Freezing Trap"] = true, ["Rapid Fire"] = true, ["Hunter's Mark"] = true, ["Tame Beast"] = true, ["Call Pet"] = true },
  },
  SHAMAN = {
    trainer = "Shaman trainer",
    core = {
      ["Earth Shock"] = "azonnali sebzés és megszakítás: a caster mobok ellen alap",
      ["Flame Shock"] = "sebzés + DoT; hosszabb harcban jobb az Earth Shocknál",
      ["Lightning Bolt"] = "húzás távolról; szintezésnél inkább nyitásra, a mana kell a gyógyításra",
      ["Lightning Shield"] = "ingyen sebzés, amikor a mob megüt: harcban legyen fent",
      ["Rockbiter Weapon"] = "fegyver-imbue: több sebzés minden ütéssel (Windfury előtt)",
      ["Flametongue Weapon"] = "fegyver-imbue: tűzsebzés minden ütéssel",
      ["Windfury Weapon"] = "a legerősebb imbue 30-tól, főleg lassú kétkezes fegyverrel",
      ["Healing Wave"] = "gyógyítás: a shaman szintezés két harc közti pihenője",
      ["Lesser Healing Wave"] = "gyors gyógyítás harc közben",
      ["Searing Totem"] = "olcsó, ingyen sebzés hosszabb harcban",
      ["Strength of Earth Totem"] = "+strength: több AP a közelharchoz",
      ["Stoneskin Totem"] = "kevesebb sebzést kapsz",
      ["Ghost Wolf"] = "gyorsabb utazás a mount előtt",
      Purge = "leveszi a mob buffjait (pajzs, gyorsítás)",
      ["Grace of Air Totem"] = "+agility a csoportnak",
      ["Windfury Totem"] = "a csoport közelharcosainak Windfury; dungeonben nagy erősítés",
      ["Mana Spring Totem"] = "mana-visszatöltés a csoportnak",
      ["Ancestral Spirit"] = "feltámasztás",
      Reincarnation = "önfeltámadás Ankh-kal",
      ["Astral Recall"] = "második hearthstone",
    },
    situational = {
      ["Frost Shock"] = "lassítás: a menekülő mobra",
      ["Chain Lightning"] = "több célpont; sok manába kerül",
      ["Magma Totem"] = "AoE totem a sok mobos húzásokra",
      ["Fire Nova Totem"] = "AoE robbanás; dungeonben",
      ["Frostbrand Weapon"] = "lassító imbue, inkább PvP",
      ["Earthbind Totem"] = "lassítás a totem körül",
      ["Tremor Totem"] = "félelem ellen (bizonyos dungeonök, PvP)",
      ["Poison Cleansing Totem"] = "méreg ellen",
      ["Disease Cleansing Totem"] = "betegség ellen",
      ["Cure Poison"] = "méreg leszedése",
      ["Cure Disease"] = "betegség leszedése",
      ["Healing Stream Totem"] = "kis gyógyítás a csoportnak",
      ["Chain Heal"] = "csoportgyógyítás dungeonben",
      ["Fire Resistance Totem"] = "tűzellenállás, bizonyos bossokra",
      ["Frost Resistance Totem"] = "fagyellenállás, bizonyos bossokra",
      ["Nature Resistance Totem"] = "nature-ellenállás, bizonyos bossokra",
      ["Grounding Totem"] = "egy varázslatot elnyel; inkább PvP",
      ["Sentry Totem"] = "felderítés; ritkán kell",
      ["Tranquil Air Totem"] = "kevesebb aggro a csoportnak",
      ["Windwall Totem"] = "távolsági sebzés ellen",
    },
    skip = {
      ["Far Sight"] = "messzire látsz; kényelmi",
      ["Water Breathing"] = "víz alatti légzés; ritkán kell",
      ["Water Walking"] = "vízen járás; kényelmi",
    },
    must = { ["Earth Shock"] = true, ["Lightning Shield"] = true, ["Rockbiter Weapon"] = true, ["Windfury Weapon"] = true,
      ["Healing Wave"] = true, ["Searing Totem"] = true, ["Strength of Earth Totem"] = true, ["Ghost Wolf"] = true },
  },
  DRUID = {
    trainer = "Druid trainer",
    core = {
      Wrath = "sebzés távolról: Cat Form előtt ez a fő varázslat",
      Moonfire = "azonnali sebzés + DoT; futás közben is mehet",
      ["Cat Form"] = "a feral szintezés alapja: energia, combo pontok, mana nélkül",
      Claw = "a Cat Form fő combo pont-építője",
      Rake = "combo pont + 9 mp vérzés; hosszabb harcban",
      Rip = "finisher: vérzés combo pontokból, hosszú harcra",
      ["Ferocious Bite"] = "finisher: azonnali sebzés, a fölösleges energiából is",
      Shred = "erős építő a célpont mögül (csoportban, stunnal)",
      ["Bear Form"] = "tankolás és túlélés; dungeonben",
      ["Dire Bear Form"] = "a Bear Form erősebb változata",
      Maul = "a medve fő sebzése és aggrója",
      Swipe = "több célpont medvében",
      ["Healing Touch"] = "gyógyítás két harc között",
      Rejuvenation = "gyógyítás idővel; harc előtt vagy közben",
      Regrowth = "gyors gyógyítás + HoT",
      ["Mark of the Wild"] = "minden statot emel: mindig legyen fent",
      Thorns = "megsebzi azt, aki megüt",
      ["Faerie Fire"] = "kevesebb páncél a célponton",
      ["Travel Form"] = "gyorsabb utazás a mount előtt",
      Prowl = "lopakodás Cat Formban: nyitás Ravage-dzsal vagy Pounce-szal",
      Rebirth = "harci feltámasztás",
      Innervate = "mana-visszatöltés",
    },
    situational = {
      Starfire = "lassú, nagy varázslat; balance-nak",
      ["Insect Swarm"] = "DoT (talent); balance-nak",
      Hurricane = "AoE; sok mobos húzásra",
      ["Entangling Roots"] = "gyökerezés: távol tartja a mobot",
      Bash = "kábítás medvében",
      ["Demoralizing Roar"] = "a mobok kisebbet ütnek",
      Growl = "aggro a medvének",
      Enrage = "rage medvében",
      ["Frenzied Regeneration"] = "rage-ből gyógyulás medvében",
      Dash = "gyors futás Cat Formban",
      Cower = "aggro csökkentése csoportban",
      Pounce = "kábító nyitás lopakodásból",
      Ravage = "nagy nyitó ütés lopakodásból, a célpont mögül",
      ["Feral Charge"] = "berontás medvében",
      ["Challenging Roar"] = "csoportos aggro dungeonben",
      Barkskin = "kevesebb sebzés vészhelyzetben",
      ["Remove Curse"] = "átok leszedése",
      ["Abolish Poison"] = "méreg leszedése",
      ["Cure Poison"] = "méreg leszedése",
      Tranquility = "csoportgyógyítás",
      Hibernate = "állat vagy sárkány elaltatása",
      ["Soothe Animal"] = "kisebb aggro-távolság az állatoknál",
      ["Aquatic Form"] = "víz alatt gyorsabb és lélegzel",
    },
    skip = {
      ["Teleport: Moonglade"] = "teleport a Moongladebe; kényelmi",
      ["Track Humanoids"] = "humanoidok a minimapon; kényelmi",
    },
    must = { Wrath = true, Moonfire = true, ["Cat Form"] = true, Claw = true, Rake = true, Rip = true, ["Ferocious Bite"] = true,
      ["Bear Form"] = true, ["Healing Touch"] = true, Rejuvenation = true, ["Mark of the Wild"] = true },
  },
  WARLOCK = {
    trainer = "Warlock trainer",
    core = {
      ["Shadow Bolt"] = "a fő direkt sebzés (1,7 mp)",
      Corruption = "DoT: 12 mp sebzés, olcsó; minden hosszabb harcba",
      ["Bane of Agony"] = "DoT: 24 mp, egyre nagyobb tickekkel; egy célponton egy Bane lehet",
      Immolate = "tűzsebzés + DoT",
      ["Life Tap"] = "életerőből mana: a warlock szintezés motorja",
      ["Drain Life"] = "sebzés és gyógyulás egyszerre",
      ["Drain Soul"] = "Soul Shard a haldokló mobból (a démonokhoz)",
      ["Summon Imp"] = "az első démon: távolról sebez",
      ["Summon Voidwalker"] = "tankol helyetted: szintezésnél a legjobb",
      ["Summon Succubus"] = "sebző démon, nagy sebzés",
      ["Summon Felhunter"] = "varázslók ellen, mana elszívás",
      ["Demon Skin"] = "páncél és életerő-regenerálás",
      ["Demon Armor"] = "a Demon Skin erősebb változata",
      ["Health Funnel"] = "a démon gyógyítása",
      ["Create Healthstone"] = "gyógyító kő magadnak",
      Fear = "a mob elfut: idő a DoT-oknak",
      ["Siphon Life"] = "DoT, ami gyógyít is (talent)",
      ["Death Coil"] = "rémület + gyógyulás vészhelyzetben",
      ["Searing Pain"] = "gyors tűzsebzés",
      ["Soul Fire"] = "nagy tűzsebzés Soul Sharddal",
    },
    situational = {
      ["Bane of Doom"] = "nagy sebzés egy perc múlva; csak hosszú harcra",
      Hellfire = "AoE maga körül, téged is éget",
      ["Rain of Fire"] = "AoE területre",
      ["Howl of Terror"] = "több mob elfut",
      ["Curse of Weakness"] = "a mob kisebbet üt",
      ["Curse of Recklessness"] = "a mob nem fut el",
      ["Curse of Tongues"] = "lassabb castolás a mobnak",
      ["Curse of the Elements"] = "több varázssebzés a célponton (csoportban)",
      ["Curse of Exhaustion"] = "lassítás (talent)",
      Banish = "démon vagy elementál kivonása a harcból",
      ["Enslave Demon"] = "démon megszelídítése",
      ["Drain Mana"] = "mana elszívása",
      ["Shadow Ward"] = "árnyvédelem",
      ["Create Soulstone"] = "önfeltámadás",
      ["Create Firestone"] = "tűzsebzés a fegyverre",
      ["Create Spellstone"] = "varázsvédelem",
      ["Ritual of Summoning"] = "csoporttárs idézése",
      ["Detect Invisibility"] = "láthatatlanság felfedése",
      ["Sense Demons"] = "démonok a minimapon",
      Shadowburn = "kivégző tűzsebzés (talent)",
      Incinerate = "tűzsebzés",
      Conflagrate = "az Immolate felrobbantása (talent)",
    },
    skip = {
      ["Eye of Kilrogg"] = "felderítő szem; kényelmi",
      ["Unending Breath"] = "víz alatti légzés; ritkán kell",
    },
    must = { ["Shadow Bolt"] = true, Corruption = true, ["Bane of Agony"] = true, ["Life Tap"] = true, ["Summon Voidwalker"] = true,
      ["Demon Skin"] = true, ["Drain Soul"] = true, ["Drain Life"] = true, Immolate = true },
  },
  MAGE = {
    trainer = "Mage trainer",
    core = {
      Frostbolt = "a fő sebzés és lassítás (1,5–3 mp, rangonként hosszabb)",
      Fireball = "a fő tűzsebzés (1,5–3,5 mp) egy kis DoT-tal",
      ["Fire Blast"] = "azonnali tűzsebzés, 8 mp cooldown: mozgás közben is",
      ["Arcane Missiles"] = "csatornázott arcane sebzés",
      ["Frost Nova"] = "a közeli mobok helyben fagynak: távolság és idő",
      ["Arcane Intellect"] = "intellect: több mana",
      ["Frost Armor"] = "páncél, és lassítja, aki megüt",
      ["Ice Armor"] = "a Frost Armor erősebb változata",
      ["Mage Armor"] = "mana-visszatöltés harc közben is",
      ["Conjure Water"] = "ingyen ital: a mage szintezés motorja",
      ["Conjure Food"] = "ingyen étel",
      Evocation = "8 mp alatt sok mana vissza (8 perc cooldown)",
      Blink = "20 yard előre, kiszabadít a fagyásból és a kábításból",
      Polymorph = "egy mob kivonása a harcból",
      ["Counterspell"] = "varázslat megszakítása",
      ["Cone of Cold"] = "közeli kúpban sebez és lassít",
      ["Scorch"] = "gyors tűzsebzés (1,5 mp)",
      ["Mana Shield"] = "a sebzést manából fizeted",
      ["Conjure Mana Agate"] = "mana gem: ingyen mana harc közben",
      ["Conjure Mana Jade"] = "mana gem: ingyen mana harc közben",
      ["Conjure Mana Citrine"] = "mana gem: ingyen mana harc közben",
      ["Conjure Mana Ruby"] = "mana gem: ingyen mana harc közben",
    },
    situational = {
      ["Arcane Explosion"] = "AoE maga körül (csoportos húzásnál)",
      Blizzard = "AoE területre, csatornázott",
      Flamestrike = "AoE területre, DoT-tal",
      ["Fire Ward"] = "tűzsebzés elnyelése",
      ["Frost Ward"] = "fagysebzés elnyelése",
      ["Dampen Magic"] = "kevesebb varázssebzés és gyógyulás",
      ["Amplify Magic"] = "több varázssebzés és gyógyulás",
      ["Remove Lesser Curse"] = "átok levétele",
      ["Detect Magic"] = "látod a mob buffjait",
      ["Arcane Brilliance"] = "Arcane Intellect az egész csoportra",
      Pyroblast = "nagy nyitó tűzsebzés (talent)",
      ["Blast Wave"] = "AoE és lassítás (talent)",
      ["Ice Barrier"] = "elnyelő pajzs (talent)",
    },
    skip = {
      ["Slow Fall"] = "lassú esés; kényelmi",
      ["Teleport: Orgrimmar"] = "kényelmi utazás", ["Teleport: Undercity"] = "kényelmi utazás", ["Teleport: Thunder Bluff"] = "kényelmi utazás",
      ["Teleport: Stormwind"] = "kényelmi utazás", ["Teleport: Ironforge"] = "kényelmi utazás", ["Teleport: Darnassus"] = "kényelmi utazás",
      ["Portal: Orgrimmar"] = "csoportos utazás", ["Portal: Undercity"] = "csoportos utazás", ["Portal: Thunder Bluff"] = "csoportos utazás",
      ["Portal: Stormwind"] = "csoportos utazás", ["Portal: Ironforge"] = "csoportos utazás", ["Portal: Darnassus"] = "csoportos utazás",
    },
    must = { Frostbolt = true, Fireball = true, ["Fire Blast"] = true, ["Frost Nova"] = true, ["Arcane Intellect"] = true, ["Frost Armor"] = true,
      ["Conjure Water"] = true, ["Conjure Food"] = true, ["Arcane Missiles"] = true, Polymorph = true, Evocation = true, Blink = true },
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
      local tier, why, gain = "situational", "új képesség, a mostani rotációdban nincs szerepe", 0
      if share >= 2 then
        tier = "dps"
        gain = (share / 100) * 0.1 * ctx.baseline
        why = ("új rank: ez a képesség most a sebzésed %.1f%%-a"):format(share)
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
    bits[#bits + 1] = (M.SLOT_HU[s.slot] or s.slot) .. (eq and eq.name and (", a " .. eq.name .. " helyére") or "")
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
    local x = Option(o.item, "ah", o.price, o.where or "Aukciósház", ("%d db kint"):format(o.listings or 0))
    if x then
      if o.item.reqLevel <= level then all[#all + 1] = x
      elseif o.item.reqLevel <= level + 4 then x.req = o.item.reqLevel soon[#soon + 1] = x end
    end
  end

  -- already in bags or bank
  local free = {}
  for _, item in ipairs(input.ownedGear or {}) do
    if item.reqLevel <= level then
      local x = Option(item, "owned", 0, "A táskádban vagy a bankodban van")
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
            local x = Option(item, "craft", cost, "Saját " .. g.name,
              (#need > 0 and ("venni kell: " .. table.concat(need, ", ")) or "minden alapanyag megvan") ..
              (isKnown and "" or " · a receptet meg kell tanulni"))
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
      bits[#bits + 1] = (M.SLOT_HU[s.slot] or s.slot) .. (eq and eq.name and (", a " .. eq.name .. " helyére") or "")
      local o = {
        source = "quest", group = s.slot, title = r[3], quality = QUALITY[r[4] or -1], itemId = r[1],
        detail = table.concat(bits, " · "),
        where = (r[10] or "quest") .. " · " .. (r.zone or "?") .. (r[14] and ((", %d-es szinttől"):format(r[14])) or ""),
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
        detail = "alap képesség: " .. s.why, where = info.trainer, cost = s.cost, gain = 0, gainPct = 0, estimated = false }
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
      note = (r.cap - r.skill <= 25 and r.cap < 300) and (("%d-nél megállsz: tanuld meg a következő rangot a trainernél"):format(r.cap)) or nil,
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
