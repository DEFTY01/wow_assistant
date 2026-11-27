-- Azeroth Chronicle: progress snapshots for every character and weekly guild competitions.
-- Only non-combat data (level, XP, money, skills, quests, deaths) is used, so the client's
-- combat restrictions do not apply. Guild messages are opt-in (/azc share on) and never sent
-- in combat or inside instances. No snapshot is taken on logout: the Forever client reports
-- zero money at that moment.

-- Part of WoW Assistant: data in WowAssistantDB.chronicle (the old AzerothChronicleDB is copied
-- there once by Core.lua), the character id in WowAssistantCharDB.id.
local _, WA = ...
local L = WA.L
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

local CATEGORIES = WA.LR {
  { id = "xp",       label = "XP" },
  { id = "levels",   label = L"Level" },
  { id = "money",    label = L"Gold" },
  { id = "skills",   label = L"Profession" },
  { id = "quests",   label = "Quest" },
  { id = "survivor", label = L"Survivor" },
}

local db, me, myKey, charDb
local lastXP, lastXPMax
local lastBroadcast, lastReply = 0, 0
local ready = false
local panel

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function Print(msg) print("|cffc0a060Azeroth Chronicle|r: " .. WA.Fix(msg)) end

local function Now() return (GetServerTime and GetServerTime()) or time() end
local function WeekKey(ts) return math.floor(((ts or Now()) - WEEK_OFFSET) / WEEK) end
local function WeekStart(k) return k * WEEK + WEEK_OFFSET end

-- The Forever client can report an empty realm name. Characters are then told apart by an id
-- kept in the per-character SavedVariables, and their key becomes "Name#id".
local RealmName = WA.RealmName
local CharKey = WA.CharKey

local function DisplayName(key)
  return (key:gsub("#.*$", ""):gsub("%-" .. RealmName() .. "$", ""))
end

-- The guild key of an addon message sender: "Name-Realm". The Forever client can give the sender
-- as "Name Realm" (a space, not a dash); character names have neither, so the name is everything
-- before the first one, and the realm loses its spaces like GetNormalizedRealmName's.
local function MemberKey(sender)
  local name, realm = sender:match("^([^%s%-]+)[%s%-]+(.+)$")
  if not name then
    local mine = RealmName()
    return mine ~= "" and (sender .. "-" .. mine) or sender
  end
  return name .. "-" .. (realm:gsub("[%s%-]", ""))
end

-- Is this guild key the current character?
local function IsMe(key)
  local name, realm = strsplit("-", key, 2)
  if name ~= UnitName("player") then return false end
  local mine = RealmName()
  return not realm or mine == "" or realm == mine
end

-- Up to 2.35.0 a "Name Realm" sender was stored as "Name Realm-Realm", next to the character's own
-- "Name-Realm" record: the same character twice. Fold those keys back, keeping the newer record.
local function MergeSpacedMembers()
  for _, weeks in pairs(db.guild) do
    for _, members in pairs(weeks) do
      local moved = {}
      for key, e in pairs(members) do
        local name, realm = key:match("^([^%s%-]+)%s+([^%-]+)%-")
        if name then moved[key] = { name .. "-" .. realm:gsub("%s", ""), e } end
      end
      for key, m in pairs(moved) do
        members[key] = nil
        local old = members[m[1]]
        if not old or (old.ts or 0) < (m[2].ts or 0) then members[m[1]] = m[2] end
      end
    end
  end
end

-- Name the guild sees: "Name-Realm" when the realm is known, else just "Name".
local function GuildName()
  local realm = RealmName()
  return realm ~= "" and (UnitName("player") .. "-" .. realm) or UnitName("player")
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
  StoreStanding(guild, wk, GuildName(), e)
  local msg = table.concat({ "S1", wk, e.class or "", e.level or 0, e.xp, e.money, e.levels, e.skills, e.quests, e.deaths }, ";")
  if Send(msg) then lastBroadcast = Now() end
end

local function Request()
  if not ready or not CanTalk() then return end
  Send("R1;" .. WeekKey())
end

local function OnAddonMessage(prefix, text, channel, sender)
  if prefix ~= PREFIX or channel ~= "GUILD" or not db then return end
  if not sender or sender == "" then return end
  sender = MemberKey(sender)
  local me_ = IsMe(sender)
  local parts = { strsplit(";", text) }
  local kind, wk = parts[1], tonumber(parts[2])
  if not wk or math.abs(wk - WeekKey()) > 1 then return end
  if kind == "S1" then
    if me_ then return end
    StoreStanding(GetGuildInfo("player"), wk, sender, {
      ts = Now(), class = parts[3] ~= "" and parts[3] or nil, level = tonumber(parts[4]),
      xp = tonumber(parts[5]) or 0, money = tonumber(parts[6]) or 0, levels = tonumber(parts[7]) or 0,
      skills = tonumber(parts[8]) or 0, quests = tonumber(parts[9]) or 0, deaths = tonumber(parts[10]) or 0,
    })
    if panel and panel:IsShown() then panel:Refresh() end
  elseif kind == "R1" and not me_ then
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
  -- The shared window style (banner, gold border, close button) with a short fixed title; the
  -- guild, category and week go on a line of their own so they never run into the close button.
  local St = WA.Style
  local W = 460
  local f = St.Window("AzerothChronicleFrame", W, 0, L"Weekly contest")
  local inset = f.inset
  f.cat = db.lastCategory or "xp"
  f.view = "guild"

  f.sub = f:CreateFontString(nil, "OVERLAY", "WowAssistantFontNormal")
  f.sub:SetPoint("TOPLEFT", inset, -f.top)
  f.sub:SetPoint("TOPRIGHT", -inset, -f.top)
  f.sub:SetJustifyH("CENTER")
  f.sub:SetWordWrap(false)

  -- category buttons, spread over the full width (the addon font has ő, the game's does not)
  local n, gap = #CATEGORIES, 4
  local bw = math.floor((W - 2 * inset - (n - 1) * gap) / n)
  local tabY = -(f.top + 20)
  f.tabs = {}
  for i, c in ipairs(CATEGORIES) do
    local b = St.Button(f, c.label, bw, function()
      f.cat = c.id
      f.view = "guild"
      db.lastCategory = c.id
      f:Refresh()
    end)
    b:SetPoint("TOPLEFT", inset + (i - 1) * (bw + gap), tabY)
    f.tabs[c.id] = b
  end

  local bottom = inset - 4
  local mine = St.Button(f, L"My characters", 110, function()
    f.view = f.view == "mine" and "guild" or "mine"
    f:Refresh()
  end)
  mine:SetPoint("BOTTOMLEFT", inset, bottom)
  local sync = St.Button(f, L"Refresh", 90, function()
    Broadcast(true)
    Request()
    f:Refresh()
  end)
  sync:SetPoint("LEFT", mine, "RIGHT", 4, 0)
  f.footer = f:CreateFontString(nil, "OVERLAY", "WowAssistantFontDisableSmall")
  f.footer:SetPoint("LEFT", sync, "RIGHT", 8, 0)
  f.footer:SetPoint("RIGHT", f, "RIGHT", -inset, 0)
  f.footer:SetJustifyH("RIGHT")
  f.footer:SetWordWrap(false)

  local rowsTop = -(f.top + 52)
  f.rows = {}
  for i = 1, ROWS do
    local r = {}
    local y = rowsTop - (i - 1) * 18
    r.rank = f:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlightSmall")
    r.rank:SetPoint("TOPLEFT", inset, y)
    r.rank:SetWidth(24)
    r.rank:SetJustifyH("RIGHT")
    r.name = f:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlightSmall")
    r.name:SetPoint("TOPLEFT", inset + 32, y)
    r.name:SetWidth(210)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.level = f:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlightSmall")
    r.level:SetPoint("TOPLEFT", inset + 250, y)
    r.value = f:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlightSmall")
    r.value:SetPoint("TOPRIGHT", -inset, y)
    r.value:SetJustifyH("RIGHT")
    f.rows[i] = r
  end
  f:SetHeight(f.top + 52 + ROWS * 18 + 40)

  -- shown in the middle of the list when there is nothing to list
  f.empty = f:CreateFontString(nil, "OVERLAY", "WowAssistantFontMuted")
  f.empty:SetPoint("TOP", f, "TOP", 0, rowsTop - 60)
  f.empty:SetWidth(W - 4 * inset)
  f.empty:SetJustifyH("CENTER")

  function f:SetRow(i, rank, name, level, value)
    local r = self.rows[i]
    r.rank:SetText(rank or "")
    r.name:SetText(name or "")
    r.level:SetText(level or "")
    r.value:SetText(value or "")
  end

  function f:Refresh()
    local wk = WeekKey()
    local from = date(L"%m/%d", WeekStart(wk))
    for id, b in pairs(self.tabs) do
      if id == self.cat and self.view == "guild" then b:LockHighlight() else b:UnlockHighlight() end
    end
    for i = 1, ROWS do self:SetRow(i) end
    self.empty:SetText("")

    if self.view == "mine" then
      self.sub:SetText((L"My characters – this week (since %s)"):format(from))
      local list = {}
      for key, c in pairs(db.chars) do
        local g = Gains(c, wk)
        if g then list[#list + 1] = { key = key, c = c, g = g } end
      end
      table.sort(list, function(a, b) return a.g.xp > b.g.xp end)
      for i, e in ipairs(list) do
        if i > ROWS then break end
        self:SetRow(i, "", ClassColor(e.c.class) .. DisplayName(e.key) .. "|r", "Lv " .. (e.g.level or "?"),
          ("+%s XP  %s  +%d q"):format(Abbrev(e.g.xp), Money(e.g.money), e.g.quests))
      end
      self.footer:SetText("")
      if #list == 0 then self.empty:SetText(L"No weekly data yet.") end
      return
    end

    local guild = GetGuildInfo("player")
    local cat = self.cat
    local label = cat
    for _, c in ipairs(CATEGORIES) do if c.id == cat then label = c.label end end
    self.sub:SetText((L"%s · %s · since %s"):format(guild or (L"No guild"), label, from))
    if not db.share then
      self.footer:SetText(L"Sharing is off: /azc share on")
    else
      self.footer:SetText(L"Self-reported data · /azc help")
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
      local name = ClassColor(x.e.class) .. DisplayName(x.member) .. "|r"
      if x.member == GuildName() then name = name .. " |cff00ff00(te)|r" end
      self:SetRow(i, i .. ".", name, x.e.level and ("Lv " .. x.e.level) or "", FormatValue(cat, Value(x.e, cat)))
    end
    if #list == 0 then self.empty:SetText(L"No data in this category yet.") end
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
-- Version 0.1.0 saved every character as "Name-" when the realm came back empty, so alts with
-- the same name shared one record. The first character that plausibly continues it takes it over
-- (same class, level not lower and at most one higher); the old key is kept in formerKeys so
-- the Azeroth MCP bridge can move its history too.
local function AdoptLegacy(key)
  local old = UnitName("player") .. "-"
  local c = db.chars[old]
  if key == old or not c or db.chars[key] then return end
  local last = c.snapshots and c.snapshots[#c.snapshots]
  local level = UnitLevel("player")
  if c.class ~= select(2, UnitClass("player")) or not last or not last.level then return end
  if level < last.level or level > last.level + 1 then return end
  c.formerKeys = c.formerKeys or {}
  table.insert(c.formerKeys, old)
  db.chars[key] = c
  db.chars[old] = nil
  Print(L"the earlier shared \"" .. UnitName("player") .. L"\" data was moved to this character.")
end

local ev = CreateFrame("Frame")
local H = {}

WA.onLoad[#WA.onLoad + 1] = function()
  db = WA.db.chronicle
  db.version = 1
  db.chars = db.chars or {}
  db.guild = db.guild or {}
  MergeSpacedMembers()
  if db.share == nil then db.share = false end
  charDb = WA.charDB
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
end

function H.PLAYER_ENTERING_WORLD()
  if ready then return end
  myKey = CharKey()
  AdoptLegacy(myKey)
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
local function ChronicleCommand(msg)
  local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
  if cmd == "" then
    TogglePanel()
  elseif cmd == "share" then
    db.share = arg == "on"
    Print(db.share and (L"sharing ON: the guild's other Chronicle users see your weekly results.") or (L"sharing off."))
    if db.share then Broadcast(true) end
  elseif cmd == "sync" then
    Broadcast(true)
    Request()
    Print(CanTalk() and (L"request sent to the guild.") or (L"cannot send now (no guild, combat, instance or sharing off)."))
  elseif cmd == "week" then
    Snapshot()
    local wk = WeekKey()
    for key, c in pairs(db.chars) do
      local g = Gains(c, wk)
      if g then
        Print((L"%s: +%s XP, %+d levels, %s, +%d skill, %d quests, %d deaths"):format(key, Abbrev(g.xp), g.levels, Money(g.money), g.skills, g.quests, g.deaths))
      end
    end
  else
    Print("/azc – panel · /azc share on|off · /azc sync · /azc week")
  end
end
WA.Chronicle = { Command = ChronicleCommand, Gains = function(c, wk) return Gains(c, wk) end, WeekKey = WeekKey,
  Snapshot = function() return Snapshot() end, db = function() return db end }
WA.Command("azc", ChronicleCommand, L"/wa azc [share on|off | sync | week] – Azeroth Chronicle (formerly /azc)")
SLASH_AZEROTHCHRONICLE1 = "/azc"
SlashCmdList.AZEROTHCHRONICLE = ChronicleCommand
