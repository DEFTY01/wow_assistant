-- WoW Assistant: the Options window.
--
-- Everything a /wa command switches can be switched here too. Each control runs the same
-- command (WA.Dispatch), so an option and its command always do the same thing, and it reads its
-- state from the saved setting that command writes. The tooltip names the command.
-- /wa options opens it; so do the gear on the main window, Ctrl + click on the minimap button and
-- the game's own AddOns settings.

local _, WA = ...
local L = WA.L
local O = {}
WA.Options = O

local W, H = 720, 500
local LABEL_W, GAP = 110, 24
local frame
local controls = {} -- everything with a :Refresh()
local loadedStyle -- the style the windows were built in (a change shows after /reload)

local function St() return WA.Style end

function O.Refresh()
  if not frame then return end
  for _, c in ipairs(controls) do c:Refresh() end
end

-- Runs a /wa command, then shows the settings it changed.
local function Run(cmd)
  WA.Dispatch(cmd)
  O.Refresh()
end
O.Run = Run

local function Tip(w, text, cmd)
  local hook = w.HookScript and "HookScript" or "SetScript"
  w[hook](w, "OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if text then GameTooltip:AddLine(WA.Fix(text), 1, 1, 1, true) end
    if cmd then GameTooltip:AddLine(WA.Fix(L"Command: ") .. cmd, 0.6, 0.8, 1) end
    GameTooltip:Show()
  end)
  w[hook](w, "OnLeave", function() GameTooltip:Hide() end)
end

local function Refreshing(w, fn)
  w.Refresh = fn
  controls[#controls + 1] = w
  return w
end

---------------------------------------------------------------------------
-- layout: a column fills from the top down
---------------------------------------------------------------------------
local function Column(f, x, y, w) return { f = f, x = x, y = y, w = w } end

local function Section(c, title)
  local h = c.f:CreateFontString(nil, "OVERLAY", "WowAssistantFontHeader")
  h:SetPoint("TOPLEFT", c.x, c.y)
  h:SetText(title)
  local rule = St().Tint(c.f:CreateTexture(nil, "ARTWORK"), "rule", 0.3)
  rule:SetHeight(1)
  rule:SetWidth(c.w)
  rule:SetPoint("TOPLEFT", c.x, c.y - 20)
  c.y = c.y - 28
end

local function Label(c, text)
  local fs = c.f:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlightSmall")
  fs:SetPoint("TOPLEFT", c.x, c.y - 5)
  fs:SetWidth(LABEL_W - 6)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  fs:SetText(text)
  return fs
end

local function CheckRow(c, label, get, set, tip, cmd)
  local cb = St().Check(c.f, label, set)
  cb:SetPoint("TOPLEFT", c.x - 3, c.y)
  Tip(cb, tip, cmd)
  Refreshing(cb, function(self) self:SetChecked(get() and true or false) end)
  c.y = c.y - 26
  return cb
end

local function DropRow(c, label, w, items, get, set, tip, cmd)
  Label(c, label)
  local dd = St().Dropdown(c.f, w, items, get, set)
  dd:SetPoint("TOPLEFT", c.x + LABEL_W, c.y + 1)
  Tip(dd, tip, cmd)
  controls[#controls + 1] = dd
  c.y = c.y - 30
  return dd
end

-- A row of buttons sharing the width: list = { { text, onClick, tip, cmd }, ... }.
local function ButtonRow(c, label, list)
  local x, w = c.x, c.w
  if label then
    Label(c, label)
    x, w = c.x + LABEL_W, c.w - LABEL_W
  end
  local bw = math.floor((w - (#list - 1) * 6) / #list)
  local out = {}
  for i, b in ipairs(list) do
    local btn = St().Button(c.f, b[1], bw, b[2])
    btn:SetPoint("TOPLEFT", x + (i - 1) * (bw + 6), c.y)
    Tip(btn, b[3], b[4])
    out[i] = btn
  end
  c.y = c.y - 30
  return out
end

local function Edit(parent, w, onEnter)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(w, 20)
  e:SetAutoFocus(false)
  e:SetFontObject("WowAssistantFontHighlightSmall")
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() onEnter() end)
  return e
end

---------------------------------------------------------------------------
-- reading the saved settings (the same fields the commands write)
---------------------------------------------------------------------------
local function SessionDB() return WA.db.session or {} end
local function Goals() return WA.charDB and WA.charDB.session and WA.charDB.session.goals or {} end

local function Gold(copper)
  local g, s = math.floor(copper / 10000), math.floor(copper % 10000 / 100)
  return s > 0 and ("%dg %ds"):format(g, s) or ("%dg"):format(g)
end

local function GoalText()
  local g, parts = Goals(), {}
  local function Until(goal) return goal.deadline and (L" until %s"):format(date("%H:%M", goal.deadline)) or "" end
  if g.gold and g.gold.target then parts[#parts + 1] = (L"gold %s"):format(Gold(g.gold.target)) .. Until(g.gold) end
  if g.level and g.level.target then parts[#parts + 1] = (L"level %d"):format(g.level.target) .. Until(g.level) end
  if #parts == 0 then return L"No goal set." end
  return (L"Goals: %s"):format(table.concat(parts, " · "))
end

---------------------------------------------------------------------------
-- the window
---------------------------------------------------------------------------
local function General(c)
  Section(c, L"General")
  DropRow(c, L"Language", 150, function() return { { "en", "English" }, { "hu", "Magyar" } } end,
    function() return WA.lang == "hu" and "hu" or "en" end,
    function(v) if v ~= (WA.lang == "hu" and "hu" or "en") then Run("lang " .. v) end end,
    L"The addon's language. Changing it reloads the interface.", "/wa lang en | hu")

  local style = DropRow(c, L"Window style", 130, function() return St().NAMES end,
    function() return St().Name() end,
    function(v) if v ~= St().Name() then Run("style " .. v) end end,
    L"Runestone: dark slate with the rune light. Game frame: the game's gold border. Flat: plain. Shown after a reload.",
    "/wa style rune | wow | flat")
  local reload = St().Button(c.f, L"Reload", c.w - LABEL_W - 136, function()
    if C_UI and C_UI.Reload then C_UI.Reload() elseif ReloadUI then ReloadUI() end
  end)
  reload:SetPoint("LEFT", style, "RIGHT", 6, 0)
  Tip(reload, L"Reloads the interface, so the windows are drawn in the chosen style.", "/reload")
  Refreshing(reload, function(self) self:SetEnabled(St().Name() ~= loadedStyle) end)

  CheckRow(c, L"Minimap button",
    function() return not (WA.db.minimap and WA.db.minimap.hide) end,
    function(on) Run(on and "minimap show" or "minimap hide") end,
    L"The Waystone button on the edge of the minimap.", "/wa minimap show | hide")
  DropRow(c, L"Minimap icon", 150, function() return WA.Minimap.Icons() end,
    function() return WA.Minimap.Icon() end,
    function(v) WA.Minimap.SetIcon(v) O.Refresh() end,
    L"The picture on the minimap button.", "/wa minimap icon")
  CheckRow(c, L"Combat log",
    function() return WA.db.logCombat end,
    function(on) if (on and true or false) ~= (WA.db.logCombat and true or false) then Run("log") end end,
    L"Writes the game's combat log file (Logs\\WoWCombatLog.txt); starts by itself on every login while on.",
    "/wa log")
end

local function Chronicle(c)
  Section(c, L"Azeroth Chronicle")
  CheckRow(c, L"Share my weekly results with the guild",
    function() return WA.db.chronicle and WA.db.chronicle.share end,
    function(on) Run("azc share " .. (on and "on" or "off")) end,
    L"The guild's other Chronicle users see your week: XP, levels, gold, skills, quests, deaths.",
    "/wa azc share on | off")
  ButtonRow(c, nil, {
    { L"Weekly contest", function() Run("azc") end, L"The weekly contest window.", "/wa azc" },
    { L"Sync", function() Run("azc sync") end, L"Sends your week and asks the guild for theirs.", "/wa azc sync" },
    { L"This week", function() Run("azc week") end, L"Your characters' gains this week, in chat.", "/wa azc week" },
  })
end

local function SessionBar(c)
  Section(c, L"Session bar")
  CheckRow(c, L"Show the session bar",
    function() return not SessionDB().hidden end,
    function(on) Run(on and "sbar show" or "sbar hide") end,
    L"The bar with playtime, XP and gold per hour and your goals.", "/wa sbar show | hide")
  CheckRow(c, L"Lock its position",
    function() return SessionDB().locked end,
    function(on) Run(on and "sbar lock" or "sbar unlock") end,
    L"A locked bar cannot be dragged.", "/wa sbar lock | unlock")
  CheckRow(c, L"Summary in chat at login",
    function() return SessionDB().summary ~= false end,
    function(on) Run("sbar autosummary " .. (on and "on" or "off")) end,
    L"The last session's summary when you log in.", "/wa sbar autosummary on | off")

  -- scale: 0.5 to 2 in steps of 0.1
  Label(c, L"Scale")
  local function Scale() return tonumber(SessionDB().scale) or 1 end
  local function Step(d)
    local v = math.floor((Scale() + d) * 10 + 0.5) / 10
    Run(("sbar scale %.1f"):format(math.min(2, math.max(0.5, v))))
  end
  local minus = St().Button(c.f, "-", 24, function() Step(-0.1) end)
  minus:SetPoint("TOPLEFT", c.x + LABEL_W, c.y)
  local value = c.f:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlight")
  value:SetPoint("LEFT", minus, "RIGHT", 6, 0)
  value:SetWidth(34)
  local plus = St().Button(c.f, "+", 24, function() Step(0.1) end)
  plus:SetPoint("LEFT", value, "RIGHT", 6, 0)
  Tip(minus, L"Smaller session bar.", "/wa sbar scale 0.5-2")
  Tip(plus, L"Bigger session bar.", "/wa sbar scale 0.5-2")
  Refreshing(value, function(self) self:SetText(("%.1f"):format(Scale())) end)
  c.y = c.y - 30

  -- goals: an amount (or level) and an optional HH:MM deadline
  local function GoalRow(label, kind, tip, cmd)
    Label(c, label)
    local amount, deadline
    local function Set()
      local a = strtrim(amount:GetText() or ""):gsub("%s", "")
      local d = strtrim(deadline:GetText() or "")
      Run(("sbar goal %s %s%s"):format(kind, a, d ~= "" and (" " .. d) or ""))
    end
    local set = St().Button(c.f, L"Set", 60, function() Set() end)
    set:SetPoint("TOPRIGHT", c.f, "TOPLEFT", c.x + c.w, c.y)
    deadline = Edit(c.f, 46, Set)
    deadline:SetPoint("RIGHT", set, "LEFT", -8, 0)
    local untilText = c.f:CreateFontString(nil, "OVERLAY", "WowAssistantFontMuted")
    untilText:SetPoint("RIGHT", deadline, "LEFT", -8, 0)
    untilText:SetText(L"until")
    amount = Edit(c.f, 40, Set)
    amount:SetPoint("LEFT", c.f, "TOPLEFT", c.x + LABEL_W + 4, c.y - 11)
    amount:SetPoint("RIGHT", untilText, "LEFT", -8, 0)
    Tip(amount, tip, cmd)
    Tip(deadline, L"Optional deadline today, as HH:MM (e.g. 22:00).", cmd)
    Tip(set, tip, cmd)
    c.y = c.y - 30
    return amount, deadline
  end
  GoalRow(L"Gold goal", "gold", L"A gold balance to reach, e.g. 100; +50 means 50 on top of what you have now.",
    "/wa sbar goal gold 100 [22:00]")
  GoalRow(L"Level goal", "level", L"The level to reach, e.g. 40.", "/wa sbar goal level 40 [22:00]")

  local goals = c.f:CreateFontString(nil, "OVERLAY", "WowAssistantFontMuted")
  goals:SetPoint("TOPLEFT", c.x, c.y - 2)
  goals:SetWidth(c.w)
  goals:SetJustifyH("LEFT")
  goals:SetWordWrap(false)
  Refreshing(goals, function(self) self:SetText(GoalText()) end)
  c.y = c.y - 22

  ButtonRow(c, nil, {
    { L"Summary", function() Run("sbar summary") end, L"This session so far, in chat.", "/wa sbar summary" },
    { L"Advice", function() Run("sbar advice") end, L"Where your gold and XP could come from faster, in chat.", "/wa sbar advice" },
    { L"Zones", function() Run("sbar zones") end, L"Your best zones for gold and XP per hour, in chat.", "/wa sbar zones" },
    { L"History", function() Run("sbar history") end, L"Your last five sessions, in chat.", "/wa sbar history" },
  })

  -- a new session takes two clicks: the current one goes to the history
  local armed = 0
  local reset
  reset = St().Button(c.f, L"Start a new session", c.w - 106, function(self)
    if armed == 0 then
      local token = math.random(1, 2 ^ 30)
      armed = token
      self:SetText(L"Click again to close this session")
      C_Timer.After(4, function()
        if armed == token then armed = 0 reset:SetText(L"Start a new session") end
      end)
      return
    end
    armed = 0
    self:SetText(L"Start a new session")
    Run("sbar reset")
  end)
  reset:SetPoint("TOPLEFT", c.x, c.y)
  Tip(reset, L"Closes this session (its summary goes to chat and the history) and starts a new one.", "/wa sbar reset")
  local clear = St().Button(c.f, L"Clear goals", 100, function() Run("sbar goal clear") end)
  clear:SetPoint("TOPRIGHT", c.f, "TOPLEFT", c.x + c.w, c.y)
  Tip(clear, L"Removes the gold and level goals.", "/wa sbar goal clear [gold | level]")
  c.y = c.y - 30
end

local function Tools(c)
  Section(c, L"Windows and tools")
  ButtonRow(c, L"Open", {
    { L"Main window", function() Run("") end, nil, "/wa" },
    { L"Vendor crafting", function() Run("vendor") end, L"What is worth crafting for the vendor.", "/wa vendor" },
    { L"AH → vendor", function() Run("flip") end, L"Auctions below the merchant price.", "/wa flip" },
    { L"Talents", function() Run("talents") end, L"The talent calculator.", "/wa talents" },
  })
  ButtonRow(c, L"Tools", {
    { L"Status", function() Run("status") end, L"Gold, bags, trainer and combat log state, in chat.", "/wa status" },
    { L"Scan the AH", function() Run("ah") end, L"A full auction house scan (the auction house must be open).", "/wa ah" },
    { L"Slow scan", function() Run("ah slow") end, L"Scans item by item, for when the full scan is not allowed yet.", "/wa ah slow" },
    { L"Talent data", function() Run("talent") end, L"Your talent trees and whether Wowhead Forever's data matches the game, in chat.", "/wa talent" },
    { L"Meter data", function() Run("meter") end, L"What the client gave about the last fight (for debugging), in chat.", "/wa meter" },
    { L"Save", function() Run("save") end, L"Saves the addon's data now (reloads the interface).", "/wa save" },
  })
end

local function Build()
  local S = St()
  local f = S.Window("WowAssistantOptionsFrame", W, H, L"Options")
  frame = f
  local inset, top = f.inset, f.top
  local colW = math.floor((W - 2 * inset - GAP) / 2)
  local y0 = -(top + 6)

  local left = Column(f, inset, y0, colW)
  General(left)
  left.y = left.y - 8
  Chronicle(left)

  local right = Column(f, inset + colW + GAP, y0, colW)
  SessionBar(right)

  local bottom = Column(f, inset, math.min(left.y, right.y) - 6, W - 2 * inset)
  Tools(bottom)

  local note = f:CreateFontString(nil, "OVERLAY", "WowAssistantFontDisableSmall")
  note:SetPoint("BOTTOMLEFT", inset, inset)
  note:SetPoint("RIGHT", f, "RIGHT", -(inset + 130), 0)
  note:SetJustifyH("LEFT")
  note:SetText(L"Each option runs the same /wa command; the tooltip shows which.")
  local help = S.Button(f, L"All commands", 120, function() Run("help") end)
  help:SetPoint("BOTTOMRIGHT", -inset, inset - 4)
  Tip(help, L"Lists every /wa command in chat.", "/wa help")

  f:SetScript("OnShow", O.Refresh)
  f:Hide()
  return f
end

function O.Show()
  frame = frame or Build()
  frame:Show()
  O.Refresh()
end

function O.Toggle()
  if frame and frame:IsShown() then frame:Hide() return end
  O.Show()
end

---------------------------------------------------------------------------
-- the game's AddOns settings: a page with a button to this window
---------------------------------------------------------------------------
local function RegisterSettings()
  local p = CreateFrame("Frame")
  p.name = "Waystone"
  local t = p:CreateFontString(nil, "OVERLAY", "WowAssistantFontTitle")
  t:SetPoint("TOPLEFT", 16, -16)
  t:SetText("Waystone")
  local d = p:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlight")
  d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -10)
  d:SetText(L"Waystone's settings are in its own window.")
  local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  b:SetSize(220, 24)
  b:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -12)
  b:SetText(WA.Fix(L"Open Waystone options"))
  b:SetScript("OnClick", function()
    local panel = (SettingsPanel and SettingsPanel:IsShown() and SettingsPanel)
      or (InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() and InterfaceOptionsFrame)
    if panel then if HideUIPanel then HideUIPanel(panel) else panel:Hide() end end
    O.Show()
  end)
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(p, "Waystone"))
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(p)
  end
end

table.insert(WA.onLoad, function()
  loadedStyle = St().Name()
  local ok, err = pcall(RegisterSettings)
  if not ok and WA.debug then WA.Print("options: " .. tostring(err)) end
end)

local function Toggle() O.Toggle() end
WA.Command("options", Toggle, L"/wa options – the Options window: every setting the commands switch")
WA.Command("config", Toggle)
WA.Command("settings", Toggle)
