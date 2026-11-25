-- SessionBar (a WoW Assistant modulja): kompakt session sáv (idő, XP, arany) WoW Forever / Retail kliensre.
-- Csak nem-harci adatot használ (pénz, XP, táska), így a Secret Values korlátozás nem érinti.
-- Beállítások: WowAssistantDB.session, karakterenként: WowAssistantCharDB.session
-- (a régi SessionBarDB / SessionBarCharDB tartalmát a Core.lua másolja át egyszer).

local _, WA = ...

---------------------------------------------------------------------------
-- Beállítások
---------------------------------------------------------------------------
local ICONS = {
  clock = "Interface\\Icons\\INV_Misc_PocketWatch_01",
  xp    = "Interface\\Icons\\Achievement_Level_10",
  gold  = "Interface\\MoneyFrame\\UI-GoldIcon",
  bag   = "Interface\\Icons\\INV_Misc_Bag_08",
  rest  = "Interface\\Icons\\Spell_Nature_Sleep",
  goal  = "Interface\\Icons\\INV_Misc_Note_01",
  zone  = "Interface\\Icons\\INV_Misc_Map_01",
  trend = "Interface\\Icons\\INV_Misc_Spyglass_03",
}
local ARROW_DOWN = "Interface\\Buttons\\Arrow-Down-Up"
local ARROW_UP   = "Interface\\Buttons\\Arrow-Up-Up"

local HISTORY_MAX     = 50
local CTX_GRACE       = 1.5   -- mp-ig marad érvényes a pénzforrás az ablak bezárása után
local IDLE_LIMIT      = 300   -- ennyi mp tétlenség után nem számít aktív időnek
local SAMPLE_EVERY    = 60    -- grafikon mintavétel (mp)
local SAMPLES_MAX     = 240
local MIN_RATE_ACTIVE = 300   -- ennyi aktív mp kell az összevetéshez
local MIN_ZONE_ACTIVE = 600   -- ennyi aktív mp kell egy zóna rangsorolásához
local SURE_ACTIVE     = 1800  -- e fölött (vagy SURE_KILLS ölés fölött) megbízható egy zóna adata
local SURE_KILLS      = 60
local LUCK_QUALITY    = 2     -- ettől a minőségtől (zöld) ritka drop, ami nem számít a stabil értékbe
local BAG_WARN        = 8     -- ennyi szabad hely alatt látszik a táska a sávon
local WARN_EVERY      = 900   -- cél-tempó figyelmeztetés gyakorisága (mp)
local LEVEL_GROWTH    = 1.06  -- becslés a táblán túli szintekre
local REST_PER_8H     = 0.05  -- fogadóban 8 óra alatt a szint 5%-a gyűlik (kb.)
local REST_CAP        = 1.5   -- pihent XP felső korlátja: 1,5 szint

-- Szintlépéshez szükséges XP szintenként (a WoW Forever mentéseiből ellenőrizve).
local XP_TABLE = {
  400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600,
  8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200,
  25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
  50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700,
  95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500,
  153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800,
}

local SPARK_N, SPARK_W, SPARK_H = 48, 4, 16
local SPARK_BLOCK = SPARK_H + 12
local SPARK_WIDTH = SPARK_N * SPARK_W + 16
local SPARK_HEIGHT = SPARK_BLOCK * 2 + 6

local CATS = {
  loot    = "Loot",
  quest   = "Küldetés",
  vendor  = "Vendor",
  mail    = "Posta (AH-eladás is)",
  ah      = "Aukciósház",
  trade   = "Kereskedés",
  repair  = "Javítás",
  taxi    = "Repülés",
  trainer = "Tréner",
  other   = "Egyéb",
}
local CAT_ORDER = { "loot", "quest", "vendor", "mail", "ah", "trade", "repair", "taxi", "trainer", "other" }

local INCOME_TIPS = {
  loot   = "A mobokból hulló arany a fő forrásod: maradj a legjobb zónádban, és sűrű, gyorsan ölhető csoportokat válassz.",
  vendor = "A vendornál eladott loot hozza a legtöbbet: tartsd üresen a táskát, és vigyél vissza minden eladható tárgyat.",
  quest  = "A küldetések hozzák a legtöbbet: ha a jutalomtárgy nem kell, a legdrágábban eladhatót válaszd.",
  mail   = "Az AH-eladásból (posta) jön sok arany: tegyél fel több alapanyagot (bőr, érc, gyógynövény, szövet).",
  ah     = "Az aukciósház fontos forrás: a keresett alapanyagot AH-n add el, ne a vendornál.",
  trade  = "A játékosoknak közvetlenül eladott áru jól megy nálad: ezt érdemes folytatni.",
}

local KILL_FMTS = {
  "COMBATLOG_XPGAIN_FIRSTPERSON", "COMBATLOG_XPGAIN_FIRSTPERSON_GROUP", "COMBATLOG_XPGAIN_FIRSTPERSON_RAID",
  "COMBATLOG_XPGAIN_EXHAUSTION1", "COMBATLOG_XPGAIN_EXHAUSTION1_GROUP", "COMBATLOG_XPGAIN_EXHAUSTION1_RAID",
}

---------------------------------------------------------------------------
-- Állapot
---------------------------------------------------------------------------
local db, charDB, session
local lastMoney, lastXP, lastXPMax, lastRested
local moneyCtx, ctxToken, repairPending = nil, 0, false
local ready, leaving = false, false
local lastTick, lastActivity, lastSample = 0, 0, 0
local lastWarn = {}
local bags = { free = 0, total = 0, junk = 0, junkCount = 0 }
local hist = { n = 0, zones = {}, income = {}, expense = {}, src = { xp = 0, kill = 0, quest = 0 } }
local killPatterns = {}
local campingShown = false
local wasActive = true
local lootSlots = {}

---------------------------------------------------------------------------
-- Segédfüggvények
---------------------------------------------------------------------------
local function Print(msg) print("|cff33ccffSessionBar|r: " .. WA.Fix(msg)) end

local function Icon(path, size)
  size = size or 14
  return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(path, size, size)
end

local function Abbrev(n)
  n = math.floor((n or 0) + 0.5)
  local a = math.abs(n)
  if a >= 1e6 then return ("%.2fM"):format(n / 1e6) end
  if a >= 1e4 then return ("%.1fk"):format(n / 1e3) end
  return tostring(n)
end

local function FmtTime(sec)
  sec = math.max(0, math.floor(sec or 0))
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = sec % 60
  if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
  return ("%d:%02d"):format(m, s)
end

local function Pct(part, whole)
  if not whole or whole <= 0 then return 0 end
  return math.floor(part / whole * 100 + 0.5)
end

-- Saját formázó: a GetCoinTextureString az új API-ban már nem globális függvény.
local COIN_ICONS = {
  gold   = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t",
  silver = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t",
  copper = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t",
}

local function Thousands(n)
  local s = tostring(n)
  local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
  return (out:gsub("^ ", ""))
end

local function Coins(copper)
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = Thousands(g) .. COIN_ICONS.gold end
  if s > 0 or g > 0 then parts[#parts + 1] = s .. COIN_ICONS.silver end
  parts[#parts + 1] = c .. COIN_ICONS.copper
  return table.concat(parts, " ")
end

local function Money(copper, signed)
  copper = math.floor((copper or 0) + 0.5)
  local str = Coins(math.abs(copper))
  if signed then
    if copper > 0 then return "|cff3cff3c+|r" .. str end
    if copper < 0 then return "|cffff4040-|r" .. str end
  elseif copper < 0 then
    return "|cffff4040-|r" .. str
  end
  return str
end

-- Hibák kiírása a chatbe (helyenként egyszer), hogy egy hiba ne némítsa el az egész addont.
local reported = {}
local function Safe(where, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and not reported[where] then
    reported[where] = true
    print("|cffff4040SessionBar hiba (" .. where .. "):|r " .. tostring(err))
  end
  return ok
end

local function IsMaxed()
  if IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel() then return true end
  if IsXPUserDisabled and IsXPUserDisabled() then return true end
  return (UnitXPMax("player") or 0) == 0
end

local function Sum(t)
  local s = 0
  for _, v in pairs(t or {}) do s = s + v end
  return s
end

local function Rested()
  return (GetXPExhaustion and GetXPExhaustion()) or 0
end

-- Óránkénti érték az aktív idő alapján; nil, ha még kevés az adat.
local function Rate(v, active, minActive)
  if not active or active < (minActive or 60) then return nil end
  return (v or 0) * 3600 / active
end

local function ActiveOf(s) return s.active or s.duration or 0 end
local function Net(s) return Sum(s.income) - Sum(s.expense) end

-- Stabil farm érték: lootolt érme + küldetéspénz + a leesett szürke/fehér tárgyak vendor-ára,
-- annak a zónának jóváírva, ahol leestek. A városi eladás (vendor/AH/posta) ide nem számít.
-- A zöld és jobb tárgyak (ritka drop) külön mennek, mert egy-egy szerencsés drop eltorzítaná.
local function Farm(s)
  local inc = s.income or {}
  return (inc.loot or 0) + (inc.quest or 0) + (s.lootItems or 0)
end
local function ZoneFarm(z) return (z.inc or 0) + (z.items or 0) end

local ZONE_FIELDS = { "xp", "inc", "items", "luck", "luckN", "kills", "exp", "active" }
local function NewZone()
  local z = {}
  for _, f in ipairs(ZONE_FIELDS) do z[f] = 0 end
  return z
end
local function MergeZone(dst, name, z)
  local t = dst[name] or NewZone()
  for _, f in ipairs(ZONE_FIELDS) do t[f] = (t[f] or 0) + (z[f] or 0) end
  dst[name] = t
end

local function ZoneName()
  local z = GetRealZoneText and GetRealZoneText() or ""
  if not z or z == "" then z = GetZoneText and GetZoneText() or "" end
  if not z or z == "" then z = "?" end
  return z
end

local function Zone(s, name)
  local z = s.zones[name]
  if not z then
    z = NewZone()
    s.zones[name] = z
  end
  return z
end

-- XP-források: mobölés (chat üzenetből), küldetés (QUEST_TURNED_IN), a maradék felfedezés/egyéb.
local function Sources(s)
  local total = s.xp or 0
  local src = s.xpSrc or {}
  local kill = math.min(src.kill or 0, total)
  local quest = math.min(src.quest or 0, total - kill)
  return kill, quest, total - kill - quest
end

local function Arrow(up, r, g, b)
  return ("|T%s:12:12:0:0:32:32:0:32:0:32:%d:%d:%d|t"):format(up and ARROW_UP or ARROW_DOWN, r, g, b)
end

-- Nyíl a korábbi sessionök átlagához képest.
local function Trend(cur, avg)
  if not cur or not avg or avg <= 0 then return "" end
  local r = cur / avg
  if r >= 1.1 then return " " .. Arrow(true, 60, 255, 60) end
  if r <= 0.9 then return " " .. Arrow(false, 255, 64, 64) end
  return " |cffaaaaaa=|r"
end

local function Touch() lastActivity = time() end

-- In combat some answers (UnitIsAFK, IsResting...) are secret values: testing them is an error. Secret = unknown.
local function Known(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function IsActive(now)
  if UnitIsAFK and Known(UnitIsAFK("player")) then return false end
  return (now or time()) - lastActivity < IDLE_LIMIT
end

---------------------------------------------------------------------------
-- XP-forrás felismerés (mobölés chat üzenet)
---------------------------------------------------------------------------
local function FmtToPattern(fmt)
  fmt = fmt:gsub("%%(%d)%$([sd])", "%%%2")
  local order = {}
  for spec in fmt:gmatch("%%([sd])") do order[#order + 1] = spec end
  local p = fmt:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")
  p = p:gsub("%%s", "(.-)"):gsub("%%d", "(%%d+)")
  p = p:gsub("%%%.$", "")
  local dIndex
  for i, spec in ipairs(order) do
    if spec == "d" then dIndex = i break end
  end
  if not dIndex then return nil end
  return { p = "^" .. p, d = dIndex }
end

local function BuildKillPatterns()
  local seen = {}
  for _, name in ipairs(KILL_FMTS) do
    local fmt = _G[name]
    if type(fmt) == "string" and not seen[fmt] then
      seen[fmt] = true
      local kp = FmtToPattern(fmt)
      if kp then killPatterns[#killPatterns + 1] = kp end
    end
  end
  if #killPatterns == 0 then
    killPatterns[1] = FmtToPattern("%s dies, you gain %d experience.")
  end
end

---------------------------------------------------------------------------
-- Session kezelés
---------------------------------------------------------------------------
local function NewSession()
  local now = time()
  return {
    start = now, last = now, active = 0,
    startLevel = UnitLevel("player"), startMoney = GetMoney(),
    xp = 0, levels = 0, xpSrc = { kill = 0, quest = 0 },
    restedUsed = 0, lootItems = 0, lootLuck = 0, lootLuckN = 0, kills = 0,
    income = {}, expense = {}, zones = {},
    samples = { { t = now, xp = 0, net = 0 } },
  }
end

-- Régebbi (0.1.x) mentésekből hiányzó mezők pótlása.
local function Migrate(s)
  s.active = s.active or math.max(0, (s.last or time()) - s.start)
  s.xpSrc = s.xpSrc or { kill = 0, quest = 0 }
  s.restedUsed = s.restedUsed or 0
  s.lootItems = s.lootItems or 0
  s.lootLuck, s.lootLuckN, s.kills = s.lootLuck or 0, s.lootLuckN or 0, s.kills or 0
  s.zones = s.zones or {}
  s.income = s.income or {}
  s.expense = s.expense or {}
  s.samples = s.samples or { { t = s.start, xp = 0, net = 0 } }
  s.startMoney = s.startMoney or GetMoney()
  return s
end

local function RebuildHist()
  local h = { n = 0, zones = {}, income = {}, expense = {}, src = { xp = 0, kill = 0, quest = 0 } }
  local sx, nx, sg = 0, 0, 0
  for _, e in ipairs(charDB.history) do
    local a = ActiveOf(e)
    if a >= MIN_ZONE_ACTIVE then
      h.n = h.n + 1
      local g = Net(e) * 3600 / a
      sg = sg + g
      if not h.bestGph or g > h.bestGph then h.bestGph = g end
      if (e.xp or 0) > 0 then
        local x = e.xp * 3600 / a
        sx, nx = sx + x, nx + 1
        if not h.bestXph or x > h.bestXph then h.bestXph = x end
      end
    end
    for c, v in pairs(e.income or {}) do h.income[c] = (h.income[c] or 0) + v end
    for c, v in pairs(e.expense or {}) do h.expense[c] = (h.expense[c] or 0) + v end
    for name, z in pairs(e.zones or {}) do MergeZone(h.zones, name, z) end
    if e.xpSrc then
      local kill, quest = Sources(e)
      h.src.xp = h.src.xp + (e.xp or 0)
      h.src.kill, h.src.quest = h.src.kill + kill, h.src.quest + quest
    end
  end
  if h.n > 0 then h.avgGph = sg / h.n end
  if nx > 0 then h.avgXph = sx / nx end
  hist = h
end

local function ArchiveSession(s)
  if not s or not s.start then return nil end
  local dur = (s.last or time()) - s.start
  if dur < 60 then return nil end -- 1 percnél rövidebbet nem mentünk
  local e = {
    start = s.start, duration = dur, active = s.active,
    startLevel = s.startLevel, levels = s.levels, xp = s.xp,
    xpSrc = s.xpSrc, restedUsed = s.restedUsed, lootItems = s.lootItems,
    lootLuck = s.lootLuck, lootLuckN = s.lootLuckN, kills = s.kills,
    income = s.income, expense = s.expense, zones = s.zones,
  }
  table.insert(charDB.history, 1, e)
  while #charDB.history > HISTORY_MAX do table.remove(charDB.history) end
  RebuildHist()
  return e
end

local function TakeSample(now)
  lastSample = now
  local s = session.samples
  s[#s + 1] = { t = now, xp = session.xp, net = Net(session) }
  if #s > SAMPLES_MAX then
    -- Ritkítás: minden második pontot megtartjuk (az elsőt és az utolsót mindig).
    local keep = { s[1] }
    for i = 3, #s - 1, 2 do keep[#keep + 1] = s[i] end
    keep[#keep + 1] = s[#s]
    session.samples = keep
  end
end

local function TrackRested()
  local r = Rested()
  if lastRested and r < lastRested and session then
    session.restedUsed = session.restedUsed + (lastRested - r)
  end
  lastRested = r
end

---------------------------------------------------------------------------
-- Táska: szabad hely és a szürke tárgyak vendor-értéke
---------------------------------------------------------------------------
local function ContainerSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) end
  if GetContainerNumSlots then return GetContainerNumSlots(bag) end
  return 0
end

local function ContainerFree(bag)
  if C_Container and C_Container.GetContainerNumFreeSlots then return C_Container.GetContainerNumFreeSlots(bag) end
  if GetContainerNumFreeSlots then return GetContainerNumFreeSlots(bag) end
  return 0, 0
end

local function SlotInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local i = C_Container.GetContainerItemInfo(bag, slot)
    if i then return i.itemID, i.quality, i.stackCount, i.hasNoValue end
    return nil
  end
  if GetContainerItemInfo then
    local _, count, _, quality, _, _, _, _, noValue, id = GetContainerItemInfo(bag, slot)
    return id, quality, count, noValue
  end
end

local function SellPrice(id)
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not fn then return nil end
  return (select(11, fn(id)))
end

local function ItemQuality(id)
  local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not fn then return nil end
  return (select(3, fn(id)))
end

local function ScanBags()
  local free, total, junk, cnt, missing = 0, 0, 0, 0, false
  local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
  for bag = 0, last do
    local n = ContainerSlots(bag) or 0
    if n > 0 then
      local f, kind = ContainerFree(bag)
      if (kind or 0) == 0 then
        free, total = free + (f or 0), total + n
      end
      for slot = 1, n do
        local id, q, count, noValue = SlotInfo(bag, slot)
        if id and q == 0 and not noValue then
          local p = SellPrice(id)
          if p then
            junk, cnt = junk + p * (count or 1), cnt + (count or 1)
          else
            missing = true
          end
        end
      end
    end
  end
  bags.free, bags.total, bags.junk, bags.junkCount = free, total, junk, cnt
  return missing
end

local bagScanPending = false
local function RequestBagScan(delay)
  if bagScanPending then return end
  bagScanPending = true
  C_Timer.After(delay or 0.5, function()
    bagScanPending = false
    local ok, missing = pcall(ScanBags)
    if ok and missing then RequestBagScan(2) end
  end)
end

---------------------------------------------------------------------------
-- Statisztika: zónák, célok, tanácsok
---------------------------------------------------------------------------
local function AllZones()
  local out = {}
  for n, z in pairs(hist.zones) do MergeZone(out, n, z) end
  for n, z in pairs(session.zones) do MergeZone(out, n, z) end
  return out
end

-- Zónák rangsora stabil farm érték/óra ("gold") vagy XP/óra ("xp") szerint, az összes mentett adatból.
-- Aranynál a megbízható (elég idő vagy ölés) zónák kerülnek előre, a ritka dropok nem számítanak bele.
local function RankZones(field)
  local list = {}
  for name, z in pairs(AllZones()) do
    if z.active >= MIN_ZONE_ACTIVE then
      local v = field == "xp" and z.xp or ZoneFarm(z)
      list[#list + 1] = {
        name = name, rate = v * 3600 / z.active, active = z.active,
        kills = z.kills, perKill = z.kills > 0 and ZoneFarm(z) / z.kills or nil,
        luck = z.luck, luckN = z.luckN,
        sure = z.active >= SURE_ACTIVE or z.kills >= SURE_KILLS,
      }
    end
  end
  table.sort(list, function(a, b)
    if field ~= "xp" and a.sure ~= b.sure then return a.sure end
    return a.rate > b.rate
  end)
  return list
end

-- Mennyi adat áll egy zóna mögött (és mennyi ritka drop esett ott, ami nincs benne az értékben).
local function Evidence(z)
  local s = ("%d perc, %d ölés"):format(math.floor(z.active / 60), z.kills or 0)
  if (z.luckN or 0) > 0 then
    s = s .. (", ritka drop: %d db %s"):format(z.luckN, Money(z.luck))
  end
  return s
end

-- A tervezéshez használt tempó: a mostani session, ha van elég adat, különben a korábbi átlag.
local function PlanRate(cur, avg)
  if session.active >= MIN_ZONE_ACTIVE and cur and cur > 0 then return cur end
  if avg and avg > 0 then return avg end
  if cur and cur > 0 then return cur end
  return nil
end

local function XPToLevel(target)
  local lvl = UnitLevel("player")
  if target <= lvl then return 0 end
  local max = UnitXPMax("player") or 0
  local need, m = max - (UnitXP("player") or 0), max
  for l = lvl + 1, target - 1 do
    m = XP_TABLE[l] or (m * LEVEL_GROWTH)
    need = need + m
  end
  return need
end

local function LevelNow()
  local max = UnitXPMax("player") or 0
  return UnitLevel("player") + (max > 0 and (UnitXP("player") or 0) / max or 0)
end

local function GoalStatus(kind)
  local g = charDB.goals[kind]
  if not g then return nil end
  local st = { goal = g }
  local base = g.base or 0
  local span = g.target - base
  if kind == "gold" then
    st.remaining = math.max(0, g.target - GetMoney())
    st.progress = span > 0 and (GetMoney() - base) / span or 1
    st.rate = PlanRate(Rate(Net(session), session.active, 60), hist.avgGph)
  else
    st.remaining = IsMaxed() and 0 or XPToLevel(g.target)
    st.progress = span > 0 and (LevelNow() - base) / span or 1
    st.rate = PlanRate(Rate(session.xp, session.active, 60), hist.avgXph)
  end
  st.progress = math.min(1, math.max(0, st.progress))
  st.done = st.remaining <= 0
  if st.done then st.progress = 1 end
  if not st.done and st.rate and st.rate > 0 then st.eta = st.remaining / st.rate * 3600 end
  if g.deadline and not st.done then
    st.left = g.deadline - time()
    if st.left > 0 then st.need = st.remaining * 3600 / st.left end
    st.late = st.left <= 0 or (st.eta ~= nil and st.eta > st.left)
  end
  return st
end

local function MergedCats(field)
  local out = {}
  for c, v in pairs(hist[field]) do out[c] = v end
  for c, v in pairs(session[field]) do out[c] = (out[c] or 0) + v end
  return out
end

-- Arany-tanácsok a zóna-statisztika, a bevételi források és a táska alapján.
local function GoldAdvice()
  local out = {}
  local function add(s) out[#out + 1] = s end
  local zones = RankZones("gold")
  local here = ZoneName()
  local best = zones[1]
  if best and best.sure and best.rate > 0 then
    add(("Legjobb farm-zónád: |cffffd100%s|r – %s/óra stabil bevétel (%s)."):format(
      best.name, Money(best.rate), Evidence(best)))
    if best.name ~= here then
      local hereZ
      for _, z in ipairs(zones) do if z.name == here then hereZ = z end end
      if hereZ and best.rate > hereZ.rate * 1.2 then
        add(("Itt (%s) %s/óra%s: a(z) %s %d%%-kal jobban fizet."):format(
          here, Money(hereZ.rate), hereZ.sure and "" or " (még kevés adat)", best.name,
          hereZ.rate > 0 and math.floor((best.rate / hereZ.rate - 1) * 100) or 100))
      end
    end
  elseif best and best.rate > 0 then
    add(("Még bizonytalan, de eddig |cffffd100%s|r a legjobb: %s/óra (%s). Fél óra vagy %d ölés után lesz megbízható."):format(
      best.name, Money(best.rate), Evidence(best), SURE_KILLS))
    best = nil -- bizonytalan zónára nem építünk célbecslést
  else
    add("Még kevés az adat a zónák összevetéséhez (zónánként 10 aktív perc kell).")
  end
  if session.lootLuckN > 0 then
    add(("Ebben a sessionben %d ritka drop esett (%s vendor-áron). Ez szerencse, ezért nincs benne a zóna-értékben; AH-n általában többet ér."):format(
      session.lootLuckN, Money(session.lootLuck)))
  end

  local inc = MergedCats("income")
  local total = Sum(inc)
  if total > 0 then
    local top, topV = nil, 0
    for c, v in pairs(inc) do
      if c ~= "other" and v > topV then top, topV = c, v end
    end
    if top then
      add(("Fő bevételed: %s (%d%%). %s"):format(CATS[top], Pct(topV, total), INCOME_TIPS[top] or ""))
    end
  end

  if bags.junk > 0 then
    add(("A táskádban %s értékű szürke tárgy van (%d db): add el a vendornál."):format(Money(bags.junk), bags.junkCount))
  end
  if bags.total > 0 and bags.free <= BAG_WARN then
    add(("Csak %d szabad hely maradt: tele táskával lootot hagysz a földön."):format(bags.free))
  end

  local exp = MergedCats("expense")
  local expTotal = Sum(exp)
  if expTotal > 0 and (exp.repair or 0) / expTotal >= 0.3 then
    add(("A kiadásaid %d%%-a javítás: kevesebb halál, több arany."):format(Pct(exp.repair, expTotal)))
  end

  local st = GoalStatus("gold")
  if st and not st.done then
    local parts = {}
    if st.eta then parts[#parts + 1] = ("a mostani tempóval ~%s"):format(FmtTime(st.eta)) end
    if best and best.rate > 0 and best.name ~= here then
      parts[#parts + 1] = ("a(z) %s tempójával ~%s"):format(best.name, FmtTime(st.remaining / best.rate * 3600))
    end
    if #parts > 0 then
      add(("A célig hátra %s: %s."):format(Money(st.remaining), table.concat(parts, ", ")))
    end
  end
  return out
end

local function LevelAdvice()
  local out = {}
  local zones = RankZones("xp")
  if zones[1] then
    out[#out + 1] = ("Legtöbb XP/óra: |cffffd100%s|r – %s/óra."):format(zones[1].name, Abbrev(zones[1].rate))
  end
  local kill, quest = Sources(session)
  local total = session.xp + hist.src.xp
  kill, quest = kill + hist.src.kill, quest + hist.src.quest
  if total > 0 then
    if quest >= kill then
      out[#out + 1] = ("XP-d %d%%-a küldetésből jön: gyűjts össze több questet egy zónában, és add le őket egyszerre."):format(Pct(quest, total))
    else
      out[#out + 1] = ("XP-d %d%%-a mobölésből jön: a sűrű, saját szintű mobcsoportok a leggyorsabbak."):format(Pct(kill, total))
    end
  end
  local rested = Rested()
  if rested > 0 then
    out[#out + 1] = ("Van %s pihent XP-d: amíg tart, a mobölés dupla XP-t ad."):format(Abbrev(rested))
  end
  return out
end

local function RestedRate()
  local r = Rate(session.restedUsed, session.active, MIN_RATE_ACTIVE)
  if r and r > 0 then return r end
  local kill = Rate(session.xpSrc.kill, session.active, MIN_RATE_ACTIVE)
  if kill and kill > 0 then return kill / 2 end
  return nil
end

---------------------------------------------------------------------------
-- Session-összefoglaló (chatbe)
---------------------------------------------------------------------------
local function SummaryLines(s, title)
  local a = ActiveOf(s)
  local dur = s.duration or ((s.last or time()) - s.start)
  local net = Net(s)
  local L = { "|cffffd100" .. title .. "|r" }
  L[#L + 1] = ("Idő: %s (aktív %s)"):format(FmtTime(dur), FmtTime(a))
  if (s.xp or 0) > 0 then
    local kill, quest, other = Sources(s)
    L[#L + 1] = ("XP: +%s (%s/óra) – mob %s, küldetés %s, felfedezés/egyéb %s%s"):format(
      Abbrev(s.xp), Abbrev(Rate(s.xp, a, 60) or 0), Abbrev(kill), Abbrev(quest), Abbrev(other),
      (s.levels or 0) > 0 and (", +%d szint"):format(s.levels) or "")
  end
  L[#L + 1] = ("Arany: %s (%s/óra) · farm érték %s/óra"):format(Money(net, true), Money(Rate(net, a, 60) or 0, true),
    Money(Rate(Farm(s), a, 60) or 0))
  if (s.lootLuckN or 0) > 0 then
    L[#L + 1] = ("Ritka drop (szerencse, nincs a farm értékben): %d db, %s vendor-áron"):format(s.lootLuckN, Money(s.lootLuck))
  end
  local bestName, bestRate
  for name, z in pairs(s.zones or {}) do
    if (z.active or 0) >= 300 then
      local r = ZoneFarm(z) * 3600 / z.active
      if not bestRate or r > bestRate then bestName, bestRate = name, r end
    end
  end
  if bestName then L[#L + 1] = ("Legjobb zóna: %s (%s/óra)"):format(bestName, Money(bestRate, true)) end
  if hist.n > 0 and a >= MIN_RATE_ACTIVE then
    local cmp = {}
    local xph, gph = Rate(s.xp, a, 60), Rate(net, a, 60)
    if xph and hist.avgXph and (s.xp or 0) > 0 then cmp[#cmp + 1] = ("XP/óra %d%%"):format(Pct(xph, hist.avgXph)) end
    if gph and hist.avgGph and hist.avgGph > 0 then cmp[#cmp + 1] = ("arany/óra %d%%"):format(Pct(gph, hist.avgGph)) end
    if #cmp > 0 then L[#L + 1] = "Az átlagodhoz képest: " .. table.concat(cmp, ", ") end
  end
  return L
end

local function PrintSummary(s, title)
  for _, line in ipairs(SummaryLines(s, title)) do Print(line) end
end

---------------------------------------------------------------------------
-- Részletes sorok (tooltip és lenyitott panel közös forrása)
-- sor: { bal, jobb, típus } – típus: "h" fejléc, "n" tördelt megjegyzés, nil normál sor
---------------------------------------------------------------------------
local function BuildRows(full)
  local rows = {}
  local function header(t) rows[#rows + 1] = { t, "", "h" } end
  local function add(l, r) rows[#rows + 1] = { l, r or "" } end
  local function note(t) rows[#rows + 1] = { t, "", "n" } end
  local now = time()
  local a = session.active
  local maxed = IsMaxed()

  header(Icon(ICONS.clock) .. " Session: " .. FmtTime(now - session.start))
  add("Aktív idő", FmtTime(a) .. (IsActive(now) and "" or " |cff888888(AFK, áll)|r"))

  -- Tapasztalat és források
  if not maxed then
    local cur, max = UnitXP("player"), UnitXPMax("player")
    local rph = Rate(session.xp, a, 60) or 0
    header(Icon(ICONS.xp) .. " Tapasztalat")
    add("Szerzett XP", Abbrev(session.xp))
    add("XP / óra", Abbrev(rph) .. Trend(Rate(session.xp, a, MIN_RATE_ACTIVE), hist.avgXph))
    if session.xp > 0 then
      local kill, quest, other = Sources(session)
      local function src(v)
        return ("%s (%d%%)  %s/óra"):format(Abbrev(v), Pct(v, session.xp), Abbrev(Rate(v, a, 60) or 0))
      end
      add("   Mobölés", src(kill))
      add("   Küldetés", src(quest))
      add("   Felfedezés / egyéb", src(other))
    end
    add("Szint", ("%d  (%.1f%%)"):format(UnitLevel("player"), max > 0 and cur / max * 100 or 0))
    if session.levels > 0 then add("Szintlépés a sessionben", session.levels) end
    if rph > 0 then add("Szintlépésig", "~" .. FmtTime((max - cur) / rph * 3600)) end

    -- Pihent XP tervező
    local rested = Rested()
    local cap = REST_CAP * max
    local per8 = REST_PER_8H * max
    header(Icon(ICONS.rest) .. " Pihent XP")
    if rested > 0 then
      add("Pihent XP", ("%s  (%d%% szint)"):format(Abbrev(rested), Pct(rested, max)))
      local rr = RestedRate()
      if rr then add("Elfogy kb.", FmtTime(rested / rr * 3600) .. " játék múlva") end
    else
      add("Pihent XP", "|cff888888elfogyott|r")
    end
    if IsResting and Known(IsResting()) then
      add("Pihenőhelyen vagy", ("|cff3cff3c+%s / 8 óra|r"):format(Abbrev(math.min(per8, math.max(0, cap - rested)))))
      if full and cap > rested then add("   Tele lesz (150%)", "~" .. FmtTime((cap - rested) / per8 * 8 * 3600) .. " múlva") end
    else
      add("Kilépés", "|cffffd100fogadóban 4x gyorsabb|r")
    end
  end

  -- Arany
  local inc, exp = Sum(session.income), Sum(session.expense)
  header(Icon(ICONS.gold) .. " Arany")
  add("Bevétel", Money(inc))
  if full then
    for _, c in ipairs(CAT_ORDER) do
      local v = session.income[c]
      if v and v > 0 then add("   " .. CATS[c], Money(v)) end
    end
  end
  add("Kiadás", Money(exp))
  if full then
    for _, c in ipairs(CAT_ORDER) do
      local v = session.expense[c]
      if v and v > 0 then add("   " .. CATS[c], Money(v)) end
    end
  end
  add("Nettó", Money(inc - exp, true))
  add("Nettó / óra", Money(Rate(inc - exp, a, 60) or 0, true) .. Trend(Rate(inc - exp, a, MIN_RATE_ACTIVE), hist.avgGph))
  add("Farm érték / óra (stabil)", Money(Rate(Farm(session), a, 60) or 0))
  if full and session.lootItems > 0 then add("   szürke/fehér loot vendor-ára", Money(session.lootItems)) end
  if session.lootLuckN > 0 then
    add(("   ritka drop: %d db (külön)"):format(session.lootLuckN), "|cff1eff00" .. Money(session.lootLuck) .. "|r")
  end
  if full and session.kills > 0 then add("   érték / ölés", Money(Farm(session) / session.kills)) end
  add("Egyenleg", Money(GetMoney()))

  -- Zónák
  local here = ZoneName()
  if full then
    header(Icon(ICONS.zone) .. " Zónák (ez a session)")
    local list = {}
    for name, z in pairs(session.zones) do list[#list + 1] = { name = name, z = z } end
    table.sort(list, function(x, y) return x.z.active > y.z.active end)
    for i = 1, math.min(5, #list) do
      local z = list[i].z
      local label = (list[i].name == here and "|cffffffff" or "") .. list[i].name .. (list[i].name == here and "|r" or "")
      if z.active >= 60 then
        add(label, ("%s XP/óra · %s/óra%s"):format(Abbrev(Rate(z.xp, z.active, 60)), Money(Rate(ZoneFarm(z), z.active, 60)),
          (z.luckN or 0) > 0 and (" |cff1eff00+%d ritka|r"):format(z.luckN) or ""))
      else
        add(label, "|cff888888kevés adat|r")
      end
    end
  else
    local z = session.zones[here]
    if z and z.active >= 60 then
      add(Icon(ICONS.zone) .. " " .. here, ("%s XP/óra · %s/óra"):format(
        Abbrev(Rate(z.xp, z.active, 60)), Money(Rate(ZoneFarm(z), z.active, 60))))
    end
  end

  -- Táska
  if bags.total > 0 then
    header(Icon(ICONS.bag) .. " Táska")
    local col = bags.free <= 3 and "|cffff4040" or (bags.free <= BAG_WARN and "|cffffd100" or "|cffffffff")
    add("Szabad hely", ("%s%d|r / %d"):format(col, bags.free, bags.total))
    if bags.junk > 0 then add("Szürke tárgyak", ("%s  (%d db)"):format(Money(bags.junk), bags.junkCount)) end
  end

  -- Célok és tanácsok
  local gst, lst = GoalStatus("gold"), GoalStatus("level")
  if gst or lst then
    header(Icon(ICONS.goal) .. " Célok")
    local function deadlineRow(st, fmtNeed)
      if not st.goal.deadline or st.done then return end
      local label = "   Határidő " .. date("%H:%M", st.goal.deadline)
      if st.late then
        add(label, "|cffff4040" .. (st.need and ("kell " .. fmtNeed(st.need) .. "/óra") or "lejárt") .. "|r")
      else
        add(label, "|cff3cff3crendben|r")
      end
    end
    if gst then
      add("Arany: " .. Money(gst.goal.target), gst.done and "|cff3cff3ckész!|r" or ("%d%%"):format(math.floor(gst.progress * 100)))
      if not gst.done then
        add("   Hátra", Money(gst.remaining))
        if gst.eta then add("   Becsült idő", "~" .. FmtTime(gst.eta)) end
        deadlineRow(gst, function(v) return Money(v) end)
      end
    end
    if lst then
      add("Szint: " .. lst.goal.target, lst.done and "|cff3cff3ckész!|r" or ("%d%%"):format(math.floor(lst.progress * 100)))
      if not lst.done then
        add("   Hátra", "~" .. Abbrev(lst.remaining) .. " XP")
        if lst.eta then add("   Becsült idő", "~" .. FmtTime(lst.eta)) end
        deadlineRow(lst, Abbrev)
      end
    end
  end
  if full then
    header(Icon(ICONS.gold) .. " Arany-tanács")
    local adv = GoldAdvice()
    for i = 1, math.min(4, #adv) do note(adv[i]) end
    if lst and not lst.done then
      header(Icon(ICONS.xp) .. " Szint-tanács")
      for _, s in ipairs(LevelAdvice()) do note(s) end
    end
    if not gst and not lst then note("|cff888888Cél: /sbar goal gold 100  vagy  /sbar goal level 40 22:00|r") end
  elseif gst and not gst.done then
    local adv = GoldAdvice()
    if adv[1] then note(adv[1]) end
  end

  -- Összevetés a korábbi sessionökkel
  if hist.n > 0 then
    header(Icon(ICONS.trend) .. (" Összevetés (%d korábbi session)"):format(hist.n))
    if not maxed and hist.avgXph then
      local cx = Rate(session.xp, a, MIN_RATE_ACTIVE)
      add("XP/óra most", (cx and Abbrev(cx) or "–") .. Trend(cx, hist.avgXph))
      add("   átlag / legjobb", Abbrev(hist.avgXph) .. " / " .. Abbrev(hist.bestXph or 0))
    end
    if hist.avgGph then
      local cg = Rate(inc - exp, a, MIN_RATE_ACTIVE)
      add("Arany/óra most", (cg and Money(cg, true) or "–") .. Trend(cg, hist.avgGph))
      add("   átlag", Money(hist.avgGph, true))
      if full then add("   legjobb", Money(hist.bestGph or 0, true)) end
    end
  end
  return rows
end

---------------------------------------------------------------------------
-- UI: sáv
---------------------------------------------------------------------------
local bar = CreateFrame("Frame", "SessionBarFrame", UIParent, "BackdropTemplate")
bar:SetHeight(20)
bar:SetWidth(200)
bar:SetClampedToScreen(true)
bar:SetMovable(true)
bar:EnableMouse(true)
bar:RegisterForDrag("LeftButton")
bar:SetFrameStrata("MEDIUM")
bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
bar:SetBackdropColor(0, 0, 0, 0.6)
bar:SetBackdropBorderColor(0, 0, 0, 0.9)
bar:Hide()

bar.text = bar:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlightSmall")
bar.text:SetPoint("LEFT", 6, 0)

-- Vékony cél-csíkok a sáv alján (arany: sárga, szint: lila).
bar.goal = {}
for _, kind in ipairs({ "gold", "level" }) do
  local bg = bar:CreateTexture(nil, "BORDER")
  bg:SetColorTexture(0.15, 0.15, 0.15, 0.9)
  bg:SetHeight(2)
  local fg = bar:CreateTexture(nil, "ARTWORK")
  fg:SetHeight(2)
  bg:Hide(); fg:Hide()
  bar.goal[kind] = { bg = bg, fg = fg }
end

local toggle = CreateFrame("Button", nil, bar)
toggle:SetSize(16, 16)
toggle:SetPoint("RIGHT", -2, 0)
toggle:SetNormalTexture(ARROW_DOWN)
toggle:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

---------------------------------------------------------------------------
-- UI: mini grafikon (arany és XP a session alatt)
---------------------------------------------------------------------------
local function CreateSpark(parent, template)
  local f = CreateFrame("Frame", nil, parent, template)
  f:SetSize(SPARK_WIDTH, SPARK_HEIGHT)
  f.series = {}
  local defs = { { key = "net", title = "Arany", r = 1, g = 0.82, b = 0 }, { key = "xp", title = "XP", r = 0.6, g = 0.45, b = 1 } }
  for si, d in ipairs(defs) do
    local top = -2 - (si - 1) * SPARK_BLOCK
    local s = { key = d.key, title = d.title, color = d, bars = {} }
    s.label = f:CreateFontString(nil, "OVERLAY", "WowAssistantFontDisableSmall")
    s.label:SetPoint("TOPLEFT", 8, top)
    for i = 1, SPARK_N do
      local t = f:CreateTexture(nil, "ARTWORK")
      t:SetWidth(SPARK_W - 1)
      t:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 8 + (i - 1) * SPARK_W, top - SPARK_BLOCK + 2)
      s.bars[i] = t
    end
    f.series[si] = s
  end
  return f
end

-- Az érték a [t0, most] idősáv n egyenletes pontján (mintákból, lépcsőzetesen).
local function SeriesValues(key, n)
  local s = session.samples
  local t0, span = session.start, time() - session.start
  local vals, p = {}, 1
  for j = 1, n do
    local tj = t0 + span * (j - 1) / (n - 1)
    while s[p + 1] and s[p + 1].t <= tj do p = p + 1 end
    vals[j] = (s[p] and s[p][key]) or 0
  end
  vals[n] = key == "xp" and session.xp or Net(session)
  return vals
end

local function UpdateSpark(f)
  local enough = time() - session.start >= 120
  for _, s in ipairs(f.series) do
    if not enough then
      s.label:SetText(s.title .. ": |cff888888adatgyűjtés…|r")
      for _, t in ipairs(s.bars) do t:Hide() end
    else
      local vals = SeriesValues(s.key, SPARK_N)
      local lo, hi = 0, 0
      for _, v in ipairs(vals) do
        if v < lo then lo = v end
        if v > hi then hi = v end
      end
      local range = hi - lo
      for i, v in ipairs(vals) do
        local t = s.bars[i]
        t:SetHeight(range > 0 and (1 + (SPARK_H - 1) * (v - lo) / range) or 1)
        if v < 0 then t:SetColorTexture(1, 0.25, 0.25, 0.9) else t:SetColorTexture(s.color.r, s.color.g, s.color.b, 0.9) end
        t:Show()
      end
      local last = vals[SPARK_N]
      s.label:SetText(s.title .. ": " .. (s.key == "xp" and ("+" .. Abbrev(last)) or Money(last, true)))
    end
  end
end

local tipSpark = CreateSpark(UIParent, "BackdropTemplate")
tipSpark:SetFrameStrata("TOOLTIP")
tipSpark:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
tipSpark:SetBackdropColor(0, 0, 0, 0.85)
tipSpark:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
tipSpark:Hide()
GameTooltip:HookScript("OnHide", function() tipSpark:Hide() end)
if GameTooltip:HasScript("OnTooltipCleared") then
  GameTooltip:HookScript("OnTooltipCleared", function() tipSpark:Hide() end)
end

---------------------------------------------------------------------------
-- UI: lenyitható panel
---------------------------------------------------------------------------
local panel = CreateFrame("Frame", nil, bar, "BackdropTemplate")
panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
panel:SetBackdropColor(0, 0, 0, 0.75)
panel:SetBackdropBorderColor(0, 0, 0, 0.9)
panel:Hide()
panel.rows, panel.notes = {}, {}
panel.spark = CreateSpark(panel)

local ROW_H = 14

local function AnchorPanel()
  panel:ClearAllPoints()
  local bottom = bar:GetBottom() or 500
  if bottom < (panel:GetHeight() + 20) then
    panel:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 2)
  else
    panel:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -2)
  end
end

local function UpdatePanel()
  if not panel:IsShown() or not session then return end
  local rows = BuildRows(true)
  local width = SPARK_WIDTH
  local items, nr, nn = {}, 0, 0
  for _, r in ipairs(rows) do
    if r[3] == "n" then
      nn = nn + 1
      local fs = panel.notes[nn]
      if not fs then
        fs = panel:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        fs:SetTextColor(0.8, 0.8, 0.8)
        panel.notes[nn] = fs
      end
      fs:SetText(r[1])
      items[#items + 1] = { note = fs }
    else
      nr = nr + 1
      local row = panel.rows[nr]
      if not row then
        row = {
          l = panel:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlightSmall"),
          r = panel:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlightSmall"),
        }
        row.r:SetJustifyH("RIGHT")
        panel.rows[nr] = row
      end
      row.l:SetText(r[1])
      row.r:SetText(r[2])
      if r[3] == "h" then row.l:SetTextColor(1, 0.82, 0) else row.l:SetTextColor(0.85, 0.85, 0.85) end
      width = math.max(width, row.l:GetStringWidth() + row.r:GetStringWidth() + 30)
      items[#items + 1] = { row = row }
    end
  end
  width = math.min(width, 420)
  local y = 6
  for _, it in ipairs(items) do
    if it.note then
      it.note:ClearAllPoints()
      it.note:SetPoint("TOPLEFT", 8, -y)
      it.note:SetWidth(width - 16)
      it.note:Show()
      y = y + it.note:GetStringHeight() + 3
    else
      it.row.l:ClearAllPoints()
      it.row.l:SetPoint("TOPLEFT", 8, -y)
      it.row.r:ClearAllPoints()
      it.row.r:SetPoint("TOPRIGHT", -8, -y)
      it.row.l:Show(); it.row.r:Show()
      y = y + ROW_H
    end
  end
  for i = nr + 1, #panel.rows do panel.rows[i].l:Hide(); panel.rows[i].r:Hide() end
  for i = nn + 1, #panel.notes do panel.notes[i]:Hide() end
  panel.spark:ClearAllPoints()
  panel.spark:SetPoint("TOPLEFT", 0, -(y + 2))
  UpdateSpark(panel.spark)
  y = y + 2 + SPARK_HEIGHT
  panel:SetSize(width, y + 4)
  AnchorPanel()
end

local function SetExpanded(on)
  db.expanded = on and true or false
  if on then
    panel:Show()
    toggle:SetNormalTexture(ARROW_UP)
    GameTooltip:Hide()
    Safe("panel", UpdatePanel)
  else
    panel:Hide()
    toggle:SetNormalTexture(ARROW_DOWN)
  end
end

toggle:SetScript("OnClick", function() SetExpanded(not panel:IsShown()) end)

---------------------------------------------------------------------------
-- UI: tooltip egérrel
---------------------------------------------------------------------------
local function ShowTooltip()
  if panel:IsShown() or not session then return end
  GameTooltip:SetOwner(bar, "ANCHOR_BOTTOM")
  for _, r in ipairs(BuildRows(false)) do
    if r[3] == "h" then
      GameTooltip:AddLine(WA.Fix(r[1]), 1, 0.82, 0)
    elseif r[3] == "n" then
      GameTooltip:AddLine(WA.Fix(r[1]), 0.8, 0.8, 0.8, true)
    else
      GameTooltip:AddDoubleLine(WA.Fix(r[1]), WA.Fix(r[2]), 0.85, 0.85, 0.85, 1, 1, 1)
    end
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Húzás: mozgatás  ·  Nyíl: lenyitás  ·  /sbar", 0.5, 0.5, 0.5)
  GameTooltip:Show()
  tipSpark:ClearAllPoints()
  tipSpark:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, -2)
  UpdateSpark(tipSpark)
  tipSpark:Show()
end

bar:SetScript("OnEnter", function() Safe("tooltip", ShowTooltip) end)
bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

bar:SetScript("OnDragStart", function(self)
  if not db.locked then self:StartMoving() end
end)
bar:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local p, _, rp, x, y = self:GetPoint()
  db.pos = { p, rp, x, y }
  AnchorPanel()
end)

---------------------------------------------------------------------------
-- Frissítés
---------------------------------------------------------------------------
local function UpdateGoalLines(width)
  local n = 0
  for _, kind in ipairs({ "gold", "level" }) do
    local line = bar.goal[kind]
    local st = GoalStatus(kind)
    if st then
      line.bg:ClearAllPoints(); line.fg:ClearAllPoints()
      line.bg:SetPoint("BOTTOMLEFT", 1, 1 + n * 2)
      line.bg:SetWidth(width - 2)
      line.fg:SetPoint("BOTTOMLEFT", 1, 1 + n * 2)
      line.fg:SetWidth(math.max(1, (width - 2) * st.progress))
      if st.done then
        line.fg:SetColorTexture(0.24, 1, 0.24, 1)
      elseif st.late then
        line.fg:SetColorTexture(1, 0.25, 0.25, 1)
      elseif kind == "gold" then
        line.fg:SetColorTexture(1, 0.82, 0, 1)
      else
        line.fg:SetColorTexture(0.6, 0.45, 1, 1)
      end
      line.bg:Show(); line.fg:Show()
      n = n + 1
    else
      line.bg:Hide(); line.fg:Hide()
    end
  end
end

local function UpdateBar()
  if not session then return end
  local now = time()
  local inc, exp = Sum(session.income), Sum(session.expense)
  local a = session.active
  local clock = FmtTime(now - session.start)
  if not IsActive(now) then clock = "|cff888888" .. clock .. " AFK|r" end
  local parts = { Icon(ICONS.clock) .. " " .. clock }
  if not IsMaxed() then
    parts[#parts + 1] = Icon(ICONS.xp) .. " +" .. Abbrev(session.xp) .. Trend(Rate(session.xp, a, MIN_RATE_ACTIVE), hist.avgXph)
  end
  parts[#parts + 1] = Money(inc - exp, true) .. Trend(Rate(inc - exp, a, MIN_RATE_ACTIVE), hist.avgGph)
  if bags.total > 0 and bags.free <= BAG_WARN then
    local col = bags.free <= 3 and "|cffff4040" or "|cffffd100"
    parts[#parts + 1] = Icon(ICONS.bag) .. " " .. col .. bags.free .. "|r"
  end
  bar.text:SetText(table.concat(parts, "   "))
  local width = bar.text:GetStringWidth() + 6 + 22
  bar:SetWidth(width)
  UpdateGoalLines(width)
end

-- Cél elérése és lassú tempó jelzése a chatben.
local function CheckGoals(now)
  for _, kind in ipairs({ "gold", "level" }) do
    local st = GoalStatus(kind)
    if st then
      local g = st.goal
      if st.done and not g.announced then
        g.announced = true
        Print(kind == "gold" and ("|cff3cff3cArany cél teljesítve: %s!|r"):format(Money(g.target))
          or ("|cff3cff3cSzint cél teljesítve: %d!|r"):format(g.target))
        pcall(PlaySound, 888)
      elseif st.late and g.deadline and session.active >= MIN_ZONE_ACTIVE
        and now - (lastWarn[kind] or 0) >= WARN_EVERY then
        lastWarn[kind] = now
        local need = st.need and (kind == "gold" and Money(st.need) or Abbrev(st.need)) or "?"
        Print(("|cffff4040A(z) %s cél lemarad|r: %s-ig óránként %s kellene, most %s megy."):format(
          kind == "gold" and "arany" or "szint", date("%H:%M", g.deadline), need,
          st.rate and (kind == "gold" and Money(st.rate) or Abbrev(st.rate)) or "?"))
        if kind == "gold" then
          local adv = GoldAdvice()
          if adv[1] then Print(adv[1]) end
        end
      end
    end
  end
end

local function Tick()
  if not session then return end
  local now = time()
  local dt = now - lastTick
  if lastTick == 0 or dt < 0 or dt > 5 then dt = 0 end
  lastTick = now
  session.last = now
  -- In combat the client hands out the speed as a secret value that cannot be compared,
  -- so combat counts as activity and the speed is only read outside it.
  local moving = InCombatLockdown()
  if not moving then
    local ok, speed = pcall(GetUnitSpeed, "player")
    moving = ok and type(speed) == "number" and not (issecretvalue and issecretvalue(speed)) and speed > 0
  end
  if moving then Touch() end
  local active = IsActive(now)
  if dt > 0 and active then
    session.active = session.active + dt
    local z = Zone(session, ZoneName())
    z.active = z.active + dt
  elseif wasActive and not active then
    -- Most lett tétlen: az utolsó mozdulat óta eltelt időt (max. 5 perc) visszamenőleg levonjuk.
    local retro = math.min(IDLE_LIMIT, math.max(0, now - lastActivity), session.active)
    session.active = session.active - retro
    local z = session.zones[ZoneName()]
    if z then z.active = math.max(0, z.active - retro) end
  end
  wasActive = active
  if now - lastSample >= SAMPLE_EVERY then TakeSample(now) end
  Safe("goals", CheckGoals, now)
  Safe("bar", UpdateBar)
  Safe("panel", UpdatePanel)
  if GameTooltip:IsOwned(bar) then Safe("tooltip", ShowTooltip) end
end

---------------------------------------------------------------------------
-- Pénzforrás-kontextus
---------------------------------------------------------------------------
local function SetCtx(c)
  ctxToken = ctxToken + 1
  moneyCtx = c
end

local function ClearCtx(c)
  local tok = ctxToken
  C_Timer.After(CTX_GRACE, function()
    if ctxToken == tok and moneyCtx == c then moneyCtx = nil end
  end)
end

local CTX_EVENTS = {
  MERCHANT_SHOW = { "vendor", true },     MERCHANT_CLOSED = { "vendor", false },
  AUCTION_HOUSE_SHOW = { "ah", true },    AUCTION_HOUSE_CLOSED = { "ah", false },
  MAIL_SHOW = { "mail", true },           MAIL_CLOSED = { "mail", false },
  TAXIMAP_OPENED = { "taxi", true },      TAXIMAP_CLOSED = { "taxi", false },
  TRAINER_SHOW = { "trainer", true },     TRAINER_CLOSED = { "trainer", false },
  TRADE_SHOW = { "trade", true },         TRADE_CLOSED = { "trade", false },
  LOOT_OPENED = { "loot", true },         LOOT_CLOSED = { "loot", false },
  QUEST_COMPLETE = { "quest", true },     QUEST_FINISHED = { "quest", false },
}

local function HookRepair()
  local function onRepair(useGuildBank)
    if not useGuildBank then repairPending = true end
  end
  if type(RepairAllItems) == "function" then
    hooksecurefunc("RepairAllItems", onRepair)
  end
  if C_MerchantFrame and type(C_MerchantFrame.RepairAllItems) == "function" then
    hooksecurefunc(C_MerchantFrame, "RepairAllItems", onRepair)
  end
end

---------------------------------------------------------------------------
-- Események
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local H = {}

WA.onLoad[#WA.onLoad + 1] = function()
  db, charDB = WA.db.session, WA.charDB.session
  charDB.history = charDB.history or {}
  charDB.goals = charDB.goals or {}
  if db.scale then bar:SetScale(db.scale) end
  bar:ClearAllPoints()
  if db.pos then
    bar:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
  else
    bar:SetPoint("TOP", UIParent, "TOP", 0, -4)
  end
  HookRepair()
  BuildKillPatterns()
  RebuildHist()
end

function H.PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
  leaving = false
  Touch()
  if ready then
    -- Zónaváltás (loading screen) után új alapértékek, hogy a kimaradt események ne torzítsanak.
    lastMoney = GetMoney()
    lastXP, lastXPMax = UnitXP("player"), UnitXPMax("player")
    lastRested = Rested()
    lastTick = time()
    RequestBagScan()
    return
  end
  -- Új session csak valódi belépéskor; /reload után folytatjuk a régit.
  local summary
  if isInitialLogin or not charDB.current then
    local prev = charDB.current
    if prev then
      Migrate(prev)
      -- Az összefoglaló az archiválás előtt készül, hogy ne önmagához hasonlítsa a sessiont.
      summary = SummaryLines(prev, "Előző session összefoglalója")
    end
    if not ArchiveSession(prev) then summary = nil end
    charDB.current = NewSession()
  end
  session = Migrate(charDB.current)
  lastMoney = GetMoney()
  lastXP, lastXPMax = UnitXP("player"), UnitXPMax("player")
  lastRested = Rested()
  lastTick = time()
  local smp = session.samples[#session.samples]
  lastSample = smp and smp.t or time()
  ready = true
  -- A ticker induljon el elsőként, hogy egy későbbi hiba ne állítsa le a frissítést.
  C_Timer.NewTicker(1, function() Safe("tick", Tick) end)
  if not db.hidden then bar:Show() end
  SetExpanded(db.expanded)
  RequestBagScan(1)
  Safe("bar", UpdateBar)
  if summary and db.summary ~= false then
    C_Timer.After(6, function()
      for _, line in ipairs(summary) do Print(line) end
    end)
  end
end

-- Kilépéskor (és /reload előtt) a Forever kliens 0 aranyat jelezhet: ezt nem szabad kiadásnak venni.
function H.PLAYER_LOGOUT()
  leaving = true
end
H.PLAYER_LEAVING_WORLD = H.PLAYER_LOGOUT

-- A kilépési visszaszámlálás alatt összefoglaló és pihent XP emlékeztető.
function H.PLAYER_CAMPING()
  if not ready or campingShown then return end
  campingShown = true
  C_Timer.After(30, function() campingShown = false end)
  PrintSummary(session, "Session összefoglaló")
  if not IsMaxed() and not (IsResting and Known(IsResting())) then
    Print("|cffffd100Nem pihenőhelyen lépsz ki:|r fogadóban vagy városban négyszer gyorsabban gyűlik a pihent XP.")
  end
end

function H.PLAYER_MONEY()
  if not ready or leaving then return end
  local m = GetMoney()
  local d = m - lastMoney
  lastMoney = m
  if d == 0 then return end
  Touch()
  local cat = moneyCtx or "other"
  if d < 0 and repairPending and moneyCtx == "vendor" then
    cat = "repair"
    repairPending = false
  end
  local t = d > 0 and session.income or session.expense
  t[cat] = (t[cat] or 0) + math.abs(d)
  -- A zónához csak a farmból jövő pénz kerül; a városi eladás/javítás torzítaná a zóna-rangsort.
  if d > 0 and (cat == "loot" or cat == "quest") then
    local z = Zone(session, ZoneName())
    z.inc = z.inc + d
  end
  Tick()
end

function H.PLAYER_XP_UPDATE(unit)
  if not ready or (unit and unit ~= "player") then return end
  local cur, max = UnitXP("player"), UnitXPMax("player")
  local gained
  if cur >= lastXP then
    gained = cur - lastXP
  else
    gained = (lastXPMax - lastXP) + cur -- szintlépés történt
    session.levels = session.levels + 1
  end
  if gained > 0 then
    session.xp = session.xp + gained
    local z = Zone(session, ZoneName())
    z.xp = z.xp + gained
    Touch()
  end
  lastXP, lastXPMax = cur, max
  TrackRested()
  Tick()
end

function H.UPDATE_EXHAUSTION()
  if ready then TrackRested() end
end

-- Mobölésből kapott XP: a "%s dies, you gain %d experience." üzenetből.
function H.CHAT_MSG_COMBAT_XP_GAIN(msg)
  if not ready or type(msg) ~= "string" then return end
  if issecretvalue and issecretvalue(msg) then return end
  for _, kp in ipairs(killPatterns) do
    local ok, a, b, c = pcall(string.match, msg, kp.p)
    if ok and a then
      local n = tonumber(({ a, b, c })[kp.d])
      if n then
        session.xpSrc.kill = session.xpSrc.kill + n
        session.kills = session.kills + 1
        local z = Zone(session, ZoneName())
        z.kills = (z.kills or 0) + 1
        Touch()
        return
      end
    end
  end
end

function H.QUEST_TURNED_IN(_, xpReward)
  SetCtx("quest")
  ClearCtx("quest")
  Touch()
  if not ready or IsMaxed() then return end
  local n = tonumber(xpReward)
  if n and n > 0 then session.xpSrc.quest = session.xpSrc.quest + n end
end

function H.BAG_UPDATE_DELAYED()
  Touch()
  RequestBagScan()
end

function H.GET_ITEM_INFO_RECEIVED()
  if bags.total > 0 then RequestBagScan(1) end
end

H.PLAYER_REGEN_DISABLED = Touch

-- Lootolt tárgyak vendor-ára (a farm értékhez). Csoportban a dobásra menő tárgyakat kihagyjuk.
local LOOT_ITEM = (Enum and Enum.LootSlotType and Enum.LootSlotType.Item) or 1
local function SnapshotLoot()
  wipe(lootSlots)
  if not GetNumLootItems or not GetLootSlotLink then return end
  local threshold = IsInGroup and IsInGroup() and GetLootThreshold and GetLootThreshold() or nil
  for i = 1, GetNumLootItems() do
    if not GetLootSlotType or GetLootSlotType(i) == LOOT_ITEM then
      local link = GetLootSlotLink(i)
      if link then
        local _, _, qty = GetLootSlotInfo(i)
        local q = ItemQuality(link)
        if not (threshold and q and q >= threshold) then
          lootSlots[i] = { link = link, qty = tonumber(qty) or 1, q = q }
        end
      end
    end
  end
end
H.LOOT_READY = SnapshotLoot
H.LOOT_OPENED = SnapshotLoot

function H.LOOT_SLOT_CLEARED(slot)
  local s = ready and slot and lootSlots[slot]
  if not s then return end
  lootSlots[slot] = nil
  local p = SellPrice(s.link)
  if p and p > 0 then
    local v = p * s.qty
    local z = Zone(session, ZoneName())
    if s.q and s.q >= LUCK_QUALITY then
      -- Ritka drop: külön tartjuk, hogy egy szerencsés zöld/kék ne torzítsa a zóna értékét.
      session.lootLuck, session.lootLuckN = session.lootLuck + v, session.lootLuckN + 1
      z.luck, z.luckN = (z.luck or 0) + v, (z.luckN or 0) + 1
    else
      session.lootItems = session.lootItems + v
      z.items = (z.items or 0) + v
    end
  end
end

function H.LOOT_CLOSED() wipe(lootSlots) end

local UNIT_EVENTS = { UNIT_SPELLCAST_SUCCEEDED = Touch } -- pl. horgászat, gyűjtés, craft

ev:SetScript("OnEvent", function(_, event, ...)
  local ctx = CTX_EVENTS[event]
  if ctx then
    if ctx[2] then SetCtx(ctx[1]) else ClearCtx(ctx[1]) end
    if event == "MERCHANT_CLOSED" then repairPending = false end
    Touch()
  end
  local h = H[event] or UNIT_EVENTS[event]
  if h then Safe(event, h, ...) end
end)

for e in pairs(CTX_EVENTS) do pcall(ev.RegisterEvent, ev, e) end
for e in pairs(H) do pcall(ev.RegisterEvent, ev, e) end
for e in pairs(UNIT_EVENTS) do pcall(ev.RegisterUnitEvent, ev, e, "player") end

---------------------------------------------------------------------------
-- Parancsok: /sbar
---------------------------------------------------------------------------
local function ParseDeadline(s)
  if not s then return nil end
  local h, m = s:match("^(%d%d?):(%d%d)$")
  h, m = tonumber(h), tonumber(m)
  if not h or h > 23 or m > 59 then return nil end
  local t = date("*t")
  t.hour, t.min, t.sec = h, m, 0
  local ts = time(t)
  if ts <= time() then ts = ts + 86400 end
  return ts
end

local function ShowGoal(kind)
  local st = GoalStatus(kind)
  if not st then return end
  local g = st.goal
  local what = kind == "gold" and ("Arany cél: " .. Money(g.target)) or ("Szint cél: " .. g.target)
  if st.done then Print(what .. " – |cff3cff3cteljesítve|r") return end
  local rem = kind == "gold" and Money(st.remaining) or ("~" .. Abbrev(st.remaining) .. " XP")
  local line = ("%s – %d%%, hátra %s"):format(what, math.floor(st.progress * 100), rem)
  if st.eta then line = line .. (", becsült idő ~%s"):format(FmtTime(st.eta)) end
  if g.deadline then
    line = line .. (", határidő %s %s"):format(date("%H:%M", g.deadline),
      st.late and "|cffff4040(lassú a tempó)|r" or "|cff3cff3c(rendben)|r")
  end
  Print(line)
end

local function GoalCommand(args)
  local kind, val, dl = args[2], args[3], args[4]
  if kind == "arany" then kind = "gold" elseif kind == "szint" then kind = "level" end
  if kind == "clear" or kind == "torol" then
    if val == "gold" or val == "arany" then charDB.goals.gold = nil
    elseif val == "level" or val == "szint" then charDB.goals.level = nil
    else charDB.goals = {} end
    Print("cél törölve.")
    Tick()
    return
  end
  if kind ~= "gold" and kind ~= "level" then
    if charDB.goals.gold or charDB.goals.level then
      ShowGoal("gold"); ShowGoal("level")
    else
      Print("nincs cél. Példák:")
    end
    Print("/sbar goal gold 100 [22:00]  – 100 arany egyenleg (opcionális határidővel)")
    Print("/sbar goal gold +50  – +50 arany a mostanihoz képest")
    Print("/sbar goal level 40 [22:00]  ·  /sbar goal clear [gold|level]")
    return
  end
  local deadline = ParseDeadline(dl)
  if dl and not deadline then Print("a határidő formája ÓÓ:PP, pl. 22:00") return end
  if kind == "gold" then
    local rel = val and val:sub(1, 1) == "+"
    local n = tonumber(((val or ""):gsub("^%+", ""):gsub("g$", ""):gsub(",", ".")))
    if not n or n <= 0 then Print("adj meg arany összeget, pl. /sbar goal gold 100") return end
    local copper = math.floor(n * 10000 + 0.5)
    local money = GetMoney()
    local target = rel and (money + copper) or copper
    if target <= money then Print(("ennyi már megvan (%s)."):format(Money(money))) return end
    charDB.goals.gold = { target = target, base = rel and money or 0, deadline = deadline, set = time() }
  else
    local n = tonumber(val)
    local lvl = UnitLevel("player")
    if not n or n <= lvl then Print(("a cél szint legyen nagyobb, mint a mostani (%d)."):format(lvl)) return end
    charDB.goals.level = { target = math.floor(n), base = LevelNow(), deadline = deadline, set = time() }
  end
  lastWarn[kind] = nil
  ShowGoal(kind)
  local adv = kind == "gold" and GoldAdvice() or LevelAdvice()
  for i = 1, math.min(3, #adv) do Print(adv[i]) end
  Tick()
end

local function SessionCommand(msg)
  local args = {}
  for w in strtrim(msg or ""):lower():gmatch("%S+") do args[#args + 1] = w end
  local cmd, arg = args[1], args[2]
  if not session then Print("még töltődik, próbáld újra pár másodperc múlva.") return end
  if cmd == "reset" then
    local lines = SummaryLines(session, "Lezárt session")
    if ArchiveSession(session) then
      for _, line in ipairs(lines) do Print(line) end
    end
    charDB.current = NewSession()
    session = charDB.current
    lastSample = time()
    Print("új session indult.")
    Tick()
  elseif cmd == "goal" or cmd == "cel" then -- the Hungarian words are old aliases
    GoalCommand(args)
  elseif cmd == "advice" or cmd == "tanacs" then
    Print("|cffffd100Arany-tanács|r")
    for _, s in ipairs(GoldAdvice()) do Print(s) end
    if not IsMaxed() then
      Print("|cffffd100Szint-tanács|r")
      for _, s in ipairs(LevelAdvice()) do Print(s) end
    end
  elseif cmd == "zones" or cmd == "zonak" then
    local g, x = RankZones("gold"), RankZones("xp")
    if #g == 0 then Print("még nincs zóna legalább 10 aktív perccel.") return end
    Print("|cffffd100Stabil farm érték / óra zónánként|r (érme, küldetés, szürke/fehér loot – a ritka drop külön)")
    for i = 1, math.min(5, #g) do
      local z = g[i]
      Print(("%d. %s – %s/óra%s%s  |cff888888(%s)|r"):format(i, z.name, Money(z.rate),
        z.sure and "" or " |cffff9933bizonytalan|r",
        z.perKill and (", %s/ölés"):format(Money(z.perKill)) or "", Evidence(z)))
    end
    if not IsMaxed() then
      Print("|cffffd100XP / óra zónánként|r")
      for i = 1, math.min(5, #x) do Print(("%d. %s – %s"):format(i, x[i].name, Abbrev(x[i].rate))) end
    end
  elseif cmd == "summary" or cmd == "osszegzes" then
    PrintSummary(session, "Session összefoglaló")
  elseif cmd == "autosummary" then
    db.summary = arg ~= "off"
    Print("belépéskori összefoglaló: " .. (db.summary and "be" or "ki"))
  elseif cmd == "lock" then
    db.locked = true; Print("sáv rögzítve.")
  elseif cmd == "unlock" then
    db.locked = false; Print("sáv mozgatható.")
  elseif cmd == "scale" and tonumber(arg) then
    db.scale = math.min(2, math.max(0.5, tonumber(arg)))
    bar:SetScale(db.scale); Print("méret: " .. db.scale)
  elseif cmd == "hide" then
    db.hidden = true; bar:Hide()
  elseif cmd == "show" then
    db.hidden = false; bar:Show()
  elseif cmd == "history" then
    if #charDB.history == 0 then Print("még nincs mentett session.") return end
    for i = 1, math.min(5, #charDB.history) do
      local h = charDB.history[i]
      local a = ActiveOf(h)
      Print(("%s  %s (aktív %s)  XP +%s  nettó %s  (%s/óra)"):format(
        date("%m.%d %H:%M", h.start), FmtTime(h.duration), FmtTime(a), Abbrev(h.xp or 0),
        Money(Net(h), true), Money(Rate(Net(h), a, 60) or 0, true)))
    end
  else
    Print("/sbar goal | advice | zones | summary | history | reset")
    Print("/sbar lock | unlock | scale 0.5-2 | hide | show | autosummary on|off")
  end
end
WA.Session = { Command = SessionCommand }
WA.SessionState = function() return session, charDB end
WA.Command("sbar", SessionCommand, "/wa sbar goal | advice | zones | summary | history | reset | lock | unlock | scale | hide | show (régen /sbar)")
SLASH_SESSIONBAR1 = "/sbar"
SLASH_SESSIONBAR2 = "/sessionbar"
SlashCmdList.SESSIONBAR = SessionCommand
