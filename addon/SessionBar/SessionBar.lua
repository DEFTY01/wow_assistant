-- SessionBar: kompakt session sáv (idő, XP, arany) WoW Forever / Retail kliensre.
-- Csak nem-harci adatot használ (pénz, XP), így a Secret Values korlátozás nem érinti.

local ADDON_NAME = ...

---------------------------------------------------------------------------
-- Beállítások
---------------------------------------------------------------------------
local ICONS = {
  clock = "Interface\\Icons\\INV_Misc_PocketWatch_01",
  xp    = "Interface\\Icons\\Achievement_Level_10",
}
local ARROW_DOWN = "Interface\\Buttons\\Arrow-Down-Up"
local ARROW_UP   = "Interface\\Buttons\\Arrow-Up-Up"
local HISTORY_MAX = 50
local CTX_GRACE = 1.5 -- mp-ig marad érvényes a pénzforrás az ablak bezárása után

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

---------------------------------------------------------------------------
-- Állapot
---------------------------------------------------------------------------
local db, charDB, session
local lastMoney, lastXP, lastXPMax
local moneyCtx, ctxToken, repairPending = nil, 0, false
local ready, leaving = false, false

---------------------------------------------------------------------------
-- Segédfüggvények
---------------------------------------------------------------------------
local function Icon(path, size)
  size = size or 14
  return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(path, size, size)
end

local function Abbrev(n)
  n = math.floor(n + 0.5)
  local a = math.abs(n)
  if a >= 1e6 then return ("%.2fM"):format(n / 1e6) end
  if a >= 1e4 then return ("%.1fk"):format(n / 1e3) end
  return tostring(n)
end

local function FmtTime(sec)
  sec = math.max(0, math.floor(sec))
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = sec % 60
  if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
  return ("%d:%02d"):format(m, s)
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
  copper = math.floor(copper + 0.5)
  local str = Coins(math.abs(copper))
  if signed then
    if copper > 0 then return "|cff3cff3c+|r" .. str end
    if copper < 0 then return "|cffff4040-|r" .. str end
  end
  return str
end

local function Elapsed()
  if not session then return 0 end
  return time() - session.start
end

local function PerHour(v)
  local el = Elapsed()
  if el < 60 then return 0 end
  return v * 3600 / el
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
  for _, v in pairs(t) do s = s + v end
  return s
end

---------------------------------------------------------------------------
-- Session kezelés
---------------------------------------------------------------------------
local function NewSession()
  return {
    start = time(), last = time(),
    startLevel = UnitLevel("player"),
    xp = 0, levels = 0,
    income = {}, expense = {},
  }
end

local function ArchiveSession(s)
  if not s or not s.start then return end
  local dur = (s.last or time()) - s.start
  if dur < 60 then return end -- 1 percnél rövidebbet nem mentünk
  table.insert(charDB.history, 1, {
    start = s.start, duration = dur,
    startLevel = s.startLevel, levels = s.levels, xp = s.xp,
    income = s.income, expense = s.expense,
  })
  while #charDB.history > HISTORY_MAX do table.remove(charDB.history) end
end

---------------------------------------------------------------------------
-- Részletes sorok (tooltip és lenyitott panel közös forrása)
---------------------------------------------------------------------------
local function BuildRows()
  local rows = {}
  local function header(t) rows[#rows + 1] = { t, "", true } end
  local function add(l, r) rows[#rows + 1] = { l, r or "" } end

  header(Icon(ICONS.clock) .. " Session: " .. FmtTime(Elapsed()))

  if not IsMaxed() then
    local cur, max = UnitXP("player"), UnitXPMax("player")
    local rph = PerHour(session.xp)
    header(Icon(ICONS.xp) .. " Tapasztalat")
    add("Szerzett XP", Abbrev(session.xp))
    add("XP / óra", Abbrev(rph))
    add("Szint", ("%d  (%.1f%%)"):format(UnitLevel("player"), max > 0 and cur / max * 100 or 0))
    if session.levels > 0 then add("Szintlépés a sessionben", session.levels) end
    if rph > 0 then add("Szintlépésig", "~" .. FmtTime((max - cur) / rph * 3600)) end
    local rested = GetXPExhaustion and GetXPExhaustion()
    if rested and rested > 0 then add("Pihent XP", Abbrev(rested)) end
  end

  local inc, exp = Sum(session.income), Sum(session.expense)
  header(Icon("Interface\\MoneyFrame\\UI-GoldIcon") .. " Arany")
  add("Bevétel", Money(inc))
  for _, c in ipairs(CAT_ORDER) do
    local v = session.income[c]
    if v and v > 0 then add("   " .. CATS[c], Money(v)) end
  end
  add("Kiadás", Money(exp))
  for _, c in ipairs(CAT_ORDER) do
    local v = session.expense[c]
    if v and v > 0 then add("   " .. CATS[c], Money(v)) end
  end
  add("Nettó", Money(inc - exp, true))
  add("Nettó / óra", Money(PerHour(inc - exp), true))
  add("Egyenleg", Money(GetMoney()))
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

bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
bar.text:SetPoint("LEFT", 6, 0)

local toggle = CreateFrame("Button", nil, bar)
toggle:SetSize(16, 16)
toggle:SetPoint("RIGHT", -2, 0)
toggle:SetNormalTexture(ARROW_DOWN)
toggle:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

---------------------------------------------------------------------------
-- UI: lenyitható panel
---------------------------------------------------------------------------
local panel = CreateFrame("Frame", nil, bar, "BackdropTemplate")
panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
panel:SetBackdropColor(0, 0, 0, 0.75)
panel:SetBackdropBorderColor(0, 0, 0, 0.9)
panel:Hide()
panel.rows = {}

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
  if not panel:IsShown() then return end
  local rows = BuildRows()
  local width = 220
  for i, r in ipairs(rows) do
    local row = panel.rows[i]
    if not row then
      row = {
        l = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
        r = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
      }
      row.l:SetPoint("TOPLEFT", 8, -6 - (i - 1) * ROW_H)
      row.r:SetPoint("TOPRIGHT", -8, -6 - (i - 1) * ROW_H)
      row.r:SetJustifyH("RIGHT")
      panel.rows[i] = row
    end
    row.l:SetText(r[1])
    row.r:SetText(r[2])
    if r[3] then row.l:SetTextColor(1, 0.82, 0) else row.l:SetTextColor(0.85, 0.85, 0.85) end
    row.l:Show(); row.r:Show()
    width = math.max(width, row.l:GetStringWidth() + row.r:GetStringWidth() + 30)
  end
  for i = #rows + 1, #panel.rows do
    panel.rows[i].l:Hide(); panel.rows[i].r:Hide()
  end
  panel:SetSize(width, #rows * ROW_H + 12)
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
  for _, r in ipairs(BuildRows()) do
    if r[3] then
      GameTooltip:AddLine(r[1], 1, 0.82, 0)
    else
      GameTooltip:AddDoubleLine(r[1], r[2], 0.85, 0.85, 0.85, 1, 1, 1)
    end
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Húzás: mozgatás  ·  Nyíl: lenyitás  ·  /sbar", 0.5, 0.5, 0.5)
  GameTooltip:Show()
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
local function UpdateBar()
  if not session then return end
  local inc, exp = Sum(session.income), Sum(session.expense)
  local parts = { Icon(ICONS.clock) .. " " .. FmtTime(Elapsed()) }
  if not IsMaxed() then
    parts[#parts + 1] = Icon(ICONS.xp) .. " +" .. Abbrev(session.xp)
  end
  parts[#parts + 1] = Money(inc - exp, true)
  bar.text:SetText(table.concat(parts, "   "))
  bar:SetWidth(bar.text:GetStringWidth() + 6 + 22)
end

local function Tick()
  if not session then return end
  session.last = time()
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

function H.ADDON_LOADED(name)
  if name ~= ADDON_NAME then return end
  SessionBarDB = SessionBarDB or {}
  SessionBarCharDB = SessionBarCharDB or {}
  db, charDB = SessionBarDB, SessionBarCharDB
  charDB.history = charDB.history or {}
  if db.scale then bar:SetScale(db.scale) end
  bar:ClearAllPoints()
  if db.pos then
    bar:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
  else
    bar:SetPoint("TOP", UIParent, "TOP", 0, -4)
  end
  HookRepair()
end

function H.PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
  leaving = false
  if ready then
    -- Zónaváltás (loading screen) után új alapértékek, hogy a kimaradt események ne torzítsanak.
    lastMoney = GetMoney()
    lastXP, lastXPMax = UnitXP("player"), UnitXPMax("player")
    return
  end
  -- Új session csak valódi belépéskor; /reload után folytatjuk a régit.
  if isInitialLogin or not charDB.current then
    ArchiveSession(charDB.current)
    charDB.current = NewSession()
  end
  session = charDB.current
  lastMoney = GetMoney()
  lastXP, lastXPMax = UnitXP("player"), UnitXPMax("player")
  ready = true
  -- A ticker induljon el elsőként, hogy egy későbbi hiba ne állítsa le a frissítést.
  C_Timer.NewTicker(1, function() Safe("tick", Tick) end)
  if not db.hidden then bar:Show() end
  SetExpanded(db.expanded)
  Safe("bar", UpdateBar)
end

-- Kilépéskor (és /reload előtt) a Forever kliens 0 aranyat jelezhet: ezt nem szabad kiadásnak venni.
function H.PLAYER_LOGOUT()
  leaving = true
end
H.PLAYER_LEAVING_WORLD = H.PLAYER_LOGOUT

function H.PLAYER_MONEY()
  if not ready or leaving then return end
  local m = GetMoney()
  local d = m - lastMoney
  lastMoney = m
  if d == 0 then return end
  local cat = moneyCtx or "other"
  if d < 0 and repairPending and moneyCtx == "vendor" then
    cat = "repair"
    repairPending = false
  end
  local t = d > 0 and session.income or session.expense
  t[cat] = (t[cat] or 0) + math.abs(d)
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
  if gained > 0 then session.xp = session.xp + gained end
  lastXP, lastXPMax = cur, max
  Tick()
end

function H.QUEST_TURNED_IN()
  SetCtx("quest")
  ClearCtx("quest")
end

ev:SetScript("OnEvent", function(_, event, ...)
  local ctx = CTX_EVENTS[event]
  if ctx then
    if ctx[2] then SetCtx(ctx[1]) else ClearCtx(ctx[1]) end
    if event == "MERCHANT_CLOSED" then repairPending = false end
    return
  end
  local h = H[event]
  if h then Safe(event, h, ...) end
end)

for e in pairs(CTX_EVENTS) do pcall(ev.RegisterEvent, ev, e) end
for e in pairs(H) do pcall(ev.RegisterEvent, ev, e) end

---------------------------------------------------------------------------
-- Parancsok: /sbar
---------------------------------------------------------------------------
local function Print(msg) print("|cff33ccffSessionBar|r: " .. msg) end

SLASH_SESSIONBAR1 = "/sbar"
SLASH_SESSIONBAR2 = "/sessionbar"
SlashCmdList.SESSIONBAR = function(msg)
  local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
  if cmd == "reset" then
    ArchiveSession(session)
    charDB.current = NewSession()
    session = charDB.current
    Print("új session indult.")
    Tick()
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
      Print(("%s  %s  XP +%s  nettó %s"):format(
        date("%m.%d %H:%M", h.start), FmtTime(h.duration), Abbrev(h.xp or 0),
        Money(Sum(h.income) - Sum(h.expense), true)))
    end
  else
    Print("/sbar reset | lock | unlock | scale 0.5-2 | hide | show | history")
  end
end
