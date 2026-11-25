-- Azeroth Chronicle: progress snapshots for every character and weekly guild competitions.
-- Only non-combat data (level, XP, money, skills, quests, deaths) is used, so the client's
-- combat restrictions do not apply. Guild messages are opt-in (/azc share on) and never sent
-- in combat or inside instances. No snapshot is taken on logout: the Forever client reports
-- zero money at that moment.

local ADDON_NAME = ...
local PREFIX = "AZCHR"
local WEEK = 604800
local WEEK_OFFSET = 6 * 86400 + 7 * 3600 -- weeks start Wednesday 07:00 UTC (EU reset)
local MAX_SNAPSHOTS = 2000
local KEEP_WEEKS = 26
local KEEP_GUILD_WEEKS = 8
local SNAPSHOT_EVERY = 600
local BROADCAST_EVERY = 600
local PROF_HEADERS = { ["Professions"] = true, ["Secondary Skills"] = true }
if TRADE_SKILLS then PROF_HEADERS[TRADE_SKILLS] = true end

local CATEGORIES = {
  { id = "xp",       label = "XP" },
  { id = "levels",   label = "Szint" },
  { id = "money",    label = "Arany" },
  { id = "skills",   label = "Szakma" },
  { id = "quests",   label = "Quest" },
  { id = "survivor", label = "Túlélő" },
}

local db, me, myKey
local lastXP, lastXPMax
local lastBroadcast, lastReply = 0, 0
local ready = false
local panel

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function Print(msg) print("|cffc0a060Azeroth Chronicle|r: " .. msg) end

local function Now() return (GetServerTime and GetServerTime()) or time() end
local function WeekKey(ts) return math.floor(((ts or Now()) - WEEK_OFFSET) / WEEK) end
local function WeekStart(k) return k * WEEK + WEEK_OFFSET end

local function RealmName()
  local r = GetNormalizedRealmName and GetNormalizedRealmName()
  if not r or r == "" then r = (GetRealmName() or ""):gsub("%s", "") end
  return r
end

local COIN = {
  g = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t",
  s = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t",
  c = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t",
}
local function Money(copper)
  local neg = copper < 0
  copper = math.abs(math.floor(copper))
  local g, s, c = math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100
  local out
  if g > 0 then out = g .. COIN.g .. " " .. s .. COIN.s
  elseif s > 0 then out = s .. COIN.s .. " " .. c .. COIN.c
  else out = c .. COIN.c end
  return (neg and "-" or "") .. out
end

local function Abbrev(n)
  n = n or 0
  if math.abs(n) >= 1e6 then return ("%.2fM"):format(n / 1e6) end
  if math.abs(n) >= 1e4 then return ("%.1fk"):format(n / 1e3) end
  return tostring(math.floor(n))
end

local function ClassColor(class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  return c and ("|c" .. (c.colorStr or "ffffffff")) or "|cffffffff"
end

local function SkillSum()
  if not GetNumSkillLines then return nil end
  local total, header = 0, nil
  for i = 1, GetNumSkillLines() do
    local name, isHeader, _, rank = GetSkillLineInfo(i)
    if isHeader then header = name
    elseif header and PROF_HEADERS[header] then total = total + (rank or 0) end
  end
  return total
end

local function CanTalk()
  if not db.share or not IsInGuild() then return false end
  if InCombatLockdown() then return false end
  local inInstance = IsInInstance()
  return not inInstance
end

---------------------------------------------------------------------------
-- snapshots and weekly gains
---------------------------------------------------------------------------
local function Snapshot()
  if not me then return end
  local s = {
    ts = Now(),
    level = UnitLevel("player"),
    xp = UnitXP("player"),
    xpMax = UnitXPMax("player"),
    money = GetMoney(),
    cxp = me.counters.xp,
    deaths = me.counters.deaths,
    quests = me.counters.quests,
    skills = SkillSum() or (me.snapshots[#me.snapshots] and me.snapshots[#me.snapshots].skills) or 0,
    zone = GetRealZoneText and GetRealZoneText() or nil,
  }
  local n = #me.snapshots
  if n > 0 and s.ts - me.snapshots[n].ts < 60 then me.snapshots[n] = s else me.snapshots[n + 1] = s end
  while #me.snapshots > MAX_SNAPSHOTS do table.remove(me.snapshots, 1) end

  local wk = WeekKey(s.ts)
  me.weeks[wk] = me.weeks[wk] or { base = s }
  me.weeks[wk].last = s
  for k in pairs(me.weeks) do
    if k < wk - KEEP_WEEKS then me.weeks[k] = nil end
  end
  me.guild = GetGuildInfo("player") or me.guild
  return s
end

local function Gains(char, wk)
  local w = char and char.weeks and char.weeks[wk]
  if not w or not w.base or not w.last then return nil end
  local b, l = w.base, w.last
  return {
    xp = (l.cxp or 0) - (b.cxp or 0),
    money = (l.money or 0) - (b.money or 0),
    levels = (l.level or 0) - (b.level or 0),
    skills = (l.skills or 0) - (b.skills or 0),
    quests = (l.quests or 0) - (b.quests or 0),
    deaths = (l.deaths or 0) - (b.deaths or 0),
    level = l.level,
  }
end

---------------------------------------------------------------------------
-- guild sync
---------------------------------------------------------------------------
local function StoreStanding(guild, wk, member, e)
  if not guild then return end
  db.guild[guild] = db.guild[guild] or {}
  local g = db.guild[guild]
  g[wk] = g[wk] or {}
  local old = g[wk][member]
  if old and (old.ts or 0) > e.ts then return end
  g[wk][member] = e
  for k in pairs(g) do
    if k < wk - KEEP_GUILD_WEEKS then g[k] = nil end
  end
end

local function MyStanding(wk)
  local gains = Gains(me, wk)
  if not gains then return nil end
  return {
    ts = Now(), class = me.class, level = gains.level, xp = gains.xp, money = gains.money,
    levels = gains.levels, skills = gains.skills, quests = gains.quests, deaths = gains.deaths,
  }
end

local function Send(msg)
  if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
  -- Newer clients return a result code; 0 (Success) or nil means it went out.
  return ok and (result == nil or result == true or result == 0)
end

local function Broadcast(force)
  if not ready or not CanTalk() then return end
  if not force and Now() - lastBroadcast < 60 then return end
  Snapshot()
  local wk = WeekKey()
  local e = MyStanding(wk)
  if not e then return end
  local guild = GetGuildInfo("player")
  StoreStanding(guild, wk, myKey, e)
  local msg = table.concat({ "S1", wk, e.class or "", e.level or 0, e.xp, e.money, e.levels, e.skills, e.quests, e.deaths }, ";")
  if Send(msg) then lastBroadcast = Now() end
end

local function Request()
  if not ready or not CanTalk() then return end
  Send("R1;" .. WeekKey())
end

local function OnAddonMessage(prefix, text, channel, sender)
  if prefix ~= PREFIX or channel ~= "GUILD" or not db then return end
  if sender and not sender:find("-") then sender = sender .. "-" .. RealmName() end
  local parts = { strsplit(";", text) }
  local kind, wk = parts[1], tonumber(parts[2])
  if not wk or math.abs(wk - WeekKey()) > 1 then return end
  if kind == "S1" then
    if sender == myKey then return end
    StoreStanding(GetGuildInfo("player"), wk, sender, {
      ts = Now(), class = parts[3] ~= "" and parts[3] or nil, level = tonumber(parts[4]),
      xp = tonumber(parts[5]) or 0, money = tonumber(parts[6]) or 0, levels = tonumber(parts[7]) or 0,
      skills = tonumber(parts[8]) or 0, quests = tonumber(parts[9]) or 0, deaths = tonumber(parts[10]) or 0,
    })
    if panel and panel:IsShown() then panel:Refresh() end
  elseif kind == "R1" and sender ~= myKey then
    if Now() - lastReply < 60 then return end
    lastReply = Now()
    C_Timer.After(2 + math.random() * 8, function() Broadcast(true) end)
  end
end

---------------------------------------------------------------------------
-- panel
---------------------------------------------------------------------------
local ROWS = 15

local function Value(e, cat)
  if cat == "survivor" then return e.xp end
  return e[cat] or 0
end

local function FormatValue(cat, v)
  if cat == "money" then return Money(v) end
  if cat == "xp" or cat == "survivor" then return Abbrev(v) end
  return tostring(v)
end

local function BuildPanel()
  local f = CreateFrame("Frame", "AzerothChronicleFrame", UIParent, "BackdropTemplate")
  f:SetSize(420, 70 + ROWS * 18)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  f:SetBackdropColor(0, 0, 0, 0.85)
  f:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
  tinsert(UISpecialFrames, "AzerothChronicleFrame")
  f.cat = db.lastCategory or "xp"
  f.view = "guild"

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 10, -8)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  f.tabs = {}
  for i, c in ipairs(CATEGORIES) do
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(62, 20)
    b:SetPoint("TOPLEFT", 10 + (i - 1) * 64, -28)
    b:SetText(c.label)
    b:SetScript("OnClick", function()
      f.cat = c.id
      f.view = "guild"
      db.lastCategory = c.id
      f:Refresh()
    end)
    f.tabs[c.id] = b
  end

  local mine = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  mine:SetSize(100, 18)
  mine:SetPoint("BOTTOMLEFT", 8, 6)
  mine:SetText("Karaktereim")
  mine:SetScript("OnClick", function()
    f.view = f.view == "mine" and "guild" or "mine"
    f:Refresh()
  end)
  local sync = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  sync:SetSize(90, 18)
  sync:SetPoint("LEFT", mine, "RIGHT", 4, 0)
  sync:SetText("Frissítés")
  sync:SetScript("OnClick", function()
    Broadcast(true)
    Request()
    f:Refresh()
  end)
  f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.footer:SetPoint("BOTTOMRIGHT", -10, 10)

  f.rows = {}
  for i = 1, ROWS do
    local r = {}
    local y = -54 - (i - 1) * 18
    r.rank = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.rank:SetPoint("TOPLEFT", 12, y)
    r.rank:SetWidth(22)
    r.rank:SetJustifyH("RIGHT")
    r.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("TOPLEFT", 40, y)
    r.name:SetWidth(190)
    r.name:SetJustifyH("LEFT")
    r.level = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.level:SetPoint("TOPLEFT", 235, y)
    r.value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.value:SetPoint("TOPRIGHT", -12, y)
    r.value:SetJustifyH("RIGHT")
    f.rows[i] = r
  end

  function f:SetRow(i, rank, name, level, value)
    local r = self.rows[i]
    r.rank:SetText(rank or "")
    r.name:SetText(name or "")
    r.level:SetText(level or "")
    r.value:SetText(value or "")
  end

  function f:Refresh()
    local wk = WeekKey()
    local from = date("%m.%d", WeekStart(wk))
    for id, b in pairs(self.tabs) do
      if id == self.cat and self.view == "guild" then b:LockHighlight() else b:UnlockHighlight() end
    end
    for i = 1, ROWS do self:SetRow(i) end

    if self.view == "mine" then
      self.title:SetText(("Karaktereim – a hét (%s óta)"):format(from))
      local list = {}
      for key, c in pairs(db.chars) do
        local g = Gains(c, wk)
        if g then list[#list + 1] = { key = key, c = c, g = g } end
      end
      table.sort(list, function(a, b) return a.g.xp > b.g.xp end)
      for i, e in ipairs(list) do
        if i > ROWS then break end
        self:SetRow(i, "", ClassColor(e.c.class) .. e.key .. "|r", "Lv " .. (e.g.level or "?"),
          ("+%s XP  %s  +%d q"):format(Abbrev(e.g.xp), Money(e.g.money), e.g.quests))
      end
      self.footer:SetText(#list == 0 and "Még nincs heti adat." or "")
      return
    end

    local guild = GetGuildInfo("player")
    local cat = self.cat
    local label = cat
    for _, c in ipairs(CATEGORIES) do if c.id == cat then label = c.label end end
    self.title:SetText(("%s – heti verseny: %s (%s óta)"):format(guild or "Nincs guild", label, from))
    if not db.share then
      self.footer:SetText("Megosztás kikapcsolva: /azc share on")
    else
      self.footer:SetText("Önbevallásos adat · /azc help")
    end
    local week = guild and db.guild[guild] and db.guild[guild][wk] or {}
    local list = {}
    for member, e in pairs(week) do
      if cat ~= "survivor" or ((e.deaths or 0) == 0 and (e.xp or 0) > 0) then
        list[#list + 1] = { member = member, e = e }
      end
    end
    table.sort(list, function(a, b) return Value(a.e, cat) > Value(b.e, cat) end)
    for i, x in ipairs(list) do
      if i > ROWS then break end
      local name = ClassColor(x.e.class) .. x.member:gsub("%-" .. RealmName() .. "$", "") .. "|r"
      if x.member == myKey then name = name .. " |cff00ff00(te)|r" end
      self:SetRow(i, i .. ".", name, x.e.level and ("Lv " .. x.e.level) or "", FormatValue(cat, Value(x.e, cat)))
    end
    if #list == 0 then self:SetRow(1, "", "Még nincs adat ebben a kategóriában.") end
  end

  f:Hide()
  return f
end

local function TogglePanel()
  panel = panel or BuildPanel()
  if panel:IsShown() then panel:Hide() return end
  Snapshot()
  Request()
  panel:Refresh()
  panel:Show()
end

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local H = {}

function H.ADDON_LOADED(name)
  if name ~= ADDON_NAME then return end
  AzerothChronicleDB = AzerothChronicleDB or {}
  db = AzerothChronicleDB
  db.version = 1
  db.chars = db.chars or {}
  db.guild = db.guild or {}
  if db.share == nil then db.share = false end
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
end

function H.PLAYER_ENTERING_WORLD()
  if ready then return end
  myKey = UnitName("player") .. "-" .. RealmName()
  db.chars[myKey] = db.chars[myKey] or {}
  me = db.chars[myKey]
  me.counters = me.counters or { xp = 0, deaths = 0, quests = 0 }
  me.snapshots = me.snapshots or {}
  me.weeks = me.weeks or {}
  me.class = select(2, UnitClass("player"))
  me.race = select(2, UnitRace("player"))
  me.faction = UnitFactionGroup("player")
  lastXP, lastXPMax = UnitXP("player"), UnitXPMax("player")
  ready = true
  C_Timer.After(5, Snapshot)
  C_Timer.After(20, function() Broadcast(true) end)
  C_Timer.NewTicker(SNAPSHOT_EVERY, function()
    if not InCombatLockdown() then Snapshot() end
  end)
  C_Timer.NewTicker(BROADCAST_EVERY, function() Broadcast() end)
end

function H.PLAYER_XP_UPDATE(unit)
  if not ready or (unit and unit ~= "player") then return end
  local cur, max = UnitXP("player"), UnitXPMax("player")
  local gained = cur >= lastXP and (cur - lastXP) or ((lastXPMax - lastXP) + cur)
  if gained > 0 then me.counters.xp = me.counters.xp + gained end
  lastXP, lastXPMax = cur, max
end

function H.PLAYER_LEVEL_UP()
  if ready then C_Timer.After(1, Snapshot) end
end

function H.QUEST_TURNED_IN()
  if not ready then return end
  me.counters.quests = me.counters.quests + 1
  C_Timer.After(1, Snapshot)
end

function H.PLAYER_DEAD()
  if not ready then return end
  me.counters.deaths = me.counters.deaths + 1
  Snapshot()
end

function H.SKILL_LINES_CHANGED()
  -- Skill-ups are picked up by the next snapshot; nothing to do right away.
end

function H.CHAT_MSG_ADDON(...)
  OnAddonMessage(...)
end

ev:SetScript("OnEvent", function(_, event, ...)
  local h = H[event]
  if h then h(...) end
end)
for e in pairs(H) do pcall(ev.RegisterEvent, ev, e) end

---------------------------------------------------------------------------
-- commands
---------------------------------------------------------------------------
SLASH_AZEROTHCHRONICLE1 = "/azc"
SlashCmdList.AZEROTHCHRONICLE = function(msg)
  local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
  if cmd == "" then
    TogglePanel()
  elseif cmd == "share" then
    db.share = arg == "on"
    Print(db.share and "megosztás BEKAPCSOLVA: a heti eredményeid a guild többi Chronicle-felhasználója látja." or "megosztás kikapcsolva.")
    if db.share then Broadcast(true) end
  elseif cmd == "sync" then
    Broadcast(true)
    Request()
    Print(CanTalk() and "lekérés elküldve a guildnek." or "most nem lehet küldeni (nincs guild, harc, instance vagy kikapcsolt megosztás).")
  elseif cmd == "week" then
    Snapshot()
    local wk = WeekKey()
    for key, c in pairs(db.chars) do
      local g = Gains(c, wk)
      if g then
        Print(("%s: +%s XP, %+d szint, %s, +%d skill, %d quest, %d halál"):format(key, Abbrev(g.xp), g.levels, Money(g.money), g.skills, g.quests, g.deaths))
      end
    end
  else
    Print("/azc – panel · /azc share on|off · /azc sync · /azc week")
  end
end
