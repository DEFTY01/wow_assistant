-- WoW Assistant: fonts and the look of the windows.
--
-- Fonts: the game's own fonts have no ő and ű (they show as boxes), so the addon brings its own:
-- Fira Sans for text and Cinzel for titles (Fonts/, SIL Open Font License). Chat and tooltips keep
-- the game's font, so text sent there gets ő -> ö and ű -> ü.
--
-- Styles (Options, or /wa style rune | wow | flat; shown after /reload):
--   rune  the default: dark slate with a thin glowing blue rune line, diamond studs in the corners,
--         soft gold titles, flat buttons;
--   wow   the game's dialog border and dark stone background, the game's own buttons and tabs;
--   flat  the plain dark panel with a thin gold edge (close to Daylight UI).

local _, WA = ...
local L = WA.L
local S = {}
WA.Style = S

local FONT_DIR = "Interface\\AddOns\\WowAssistant\\Fonts\\"
S.BODY = FONT_DIR .. "FiraSans-Medium.ttf"
S.TITLE = FONT_DIR .. "Cinzel-Black.ttf"
S.GOLD = { 1, 0.82, 0 }

---------------------------------------------------------------------------
-- fonts
---------------------------------------------------------------------------
local function MakeFont(name, path, size, r, g, b)
  local f = CreateFont(name)
  -- a missing file (e.g. an install from the browser, which cannot copy fonts) falls back to the game's font
  if f:SetFont(path, size, "") == false or not f:GetFont() then f:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "") end
  f:SetTextColor(r, g, b)
  f:SetShadowColor(0, 0, 0, 1)
  f:SetShadowOffset(1, -1)
  return f
end
-- The same names as the game's font objects, with "WowAssistant" in front.
-- Colours: one set, used everywhere (gold for titles, parchment white for text, muted brown-grey).
S.C = {
  gold = { 1, 0.82, 0 }, text = { 0.93, 0.9, 0.82 }, muted = { 0.62, 0.57, 0.48 },
  bg = { 0.055, 0.047, 0.04 }, panel = { 0.095, 0.08, 0.062 }, card = { 0.12, 0.1, 0.075 },
  edge = { 0.55, 0.43, 0.2 },
}
S.HEX = { gold = "ffd100", text = "ede6d1", muted = "9e917a", good = "5ee05e", warn = "ff9933", bad = "ff5a5a" }

-- The same names as the game's font objects, with "WowAssistant" in front. Body text is at least 12.
MakeFont("WowAssistantFontTitle", S.TITLE, 16, 1, 0.82, 0)
MakeFont("WowAssistantFontPage", S.TITLE, 19, 1, 0.82, 0)
MakeFont("WowAssistantFontHeader", S.TITLE, 13, 1, 0.82, 0)
MakeFont("WowAssistantFontNav", S.TITLE, 13, 0.93, 0.9, 0.82)
MakeFont("WowAssistantFontBig", S.BODY, 21, 1, 1, 1)
MakeFont("WowAssistantFontNormal", S.BODY, 13, 1, 0.82, 0)
MakeFont("WowAssistantFontNormalSmall", S.BODY, 12, 1, 0.82, 0)
MakeFont("WowAssistantFontHighlight", S.BODY, 13, 0.93, 0.9, 0.82)
MakeFont("WowAssistantFontHighlightSmall", S.BODY, 12, 0.93, 0.9, 0.82)
MakeFont("WowAssistantFontMuted", S.BODY, 12, 0.62, 0.57, 0.48)
MakeFont("WowAssistantFontDisableSmall", S.BODY, 11, 0.62, 0.57, 0.48)

-- For text shown in the game's own font (chat, tooltips).
local FIX = { ["ő"] = "ö", ["ű"] = "ü", ["Ő"] = "Ö", ["Ű"] = "Ü", ["→"] = "->", ["↑"] = "^", ["↓"] = "v", ["…"] = "...", ["≈"] = "~" }
function S.Fix(s)
  if type(s) ~= "string" then return s end
  return (s:gsub("[\226\197][\128-\191][\128-\191]?", function(c) return FIX[c] end))
end
WA.Fix = S.Fix

-- string.upper works on bytes, so it leaves the accented letters lower case (BECSüLT).
local UPPER = { ["á"] = "Á", ["é"] = "É", ["í"] = "Í", ["ó"] = "Ó", ["ö"] = "Ö", ["ő"] = "Ő", ["ú"] = "Ú", ["ü"] = "Ü", ["ű"] = "Ű" }
function S.Upper(s)
  s = tostring(s or ""):upper()
  return (s:gsub("[\195\197][\128-\191]", function(c) return UPPER[c] end))
end
local LOWER = {}
for k, v in pairs(UPPER) do LOWER[v] = k end
function S.Lower(s)
  s = tostring(s or ""):lower()
  return (s:gsub("[\195\197][\128-\191]", function(c) return LOWER[c] end))
end

---------------------------------------------------------------------------
-- style
---------------------------------------------------------------------------
function S.Name()
  local st = WA.db and WA.db.style
  if st == "wow" or st == "flat" then return st end
  return "rune"
end
function S.Wow() return S.Name() == "wow" end
function S.Rune() return S.Name() == "rune" end
S.NAMES = WA.LR { { "rune", L"Runestone" }, { "wow", L"Game frame" }, { "flat", L"Flat" } }

-- Tints for highlights, selections and rules: kind -> colour; the caller gives the alpha.
-- wow and flat keep the warm gold of 2.36; rune is cool slate with the rune blue.
S.T = { accent = { 1, 0.82, 0 }, hover = { 1, 0.9, 0.7 }, rule = { 1, 0.82, 0 }, cardbg = { 0.14, 0.115, 0.08 } }
local RUNE = {
  C = { gold = { 0.91, 0.76, 0.42 }, text = { 0.89, 0.9, 0.92 }, muted = { 0.6, 0.64, 0.68 },
    bg = { 0.082, 0.094, 0.11 }, panel = { 0.094, 0.11, 0.13 }, card = { 0.106, 0.125, 0.15 },
    edge = { 0.42, 0.5, 0.58 } },
  T = { accent = { 0.37, 0.83, 1 }, hover = { 0.55, 0.8, 1 }, rule = { 0.45, 0.55, 0.65 }, cardbg = { 0.106, 0.125, 0.15 } },
  HEX = { text = "e3e6ea", muted = "9aa3ad" },
}
local FONT_ROLE = {
  WowAssistantFontTitle = "gold", WowAssistantFontPage = "gold", WowAssistantFontHeader = "gold",
  WowAssistantFontNav = "text", WowAssistantFontNormal = "gold", WowAssistantFontNormalSmall = "gold",
  WowAssistantFontHighlight = "text", WowAssistantFontHighlightSmall = "text",
  WowAssistantFontMuted = "muted", WowAssistantFontDisableSmall = "muted",
}

-- The chosen style's colours, once the saved setting is known. The tables are changed in place,
-- so code holding S.C, S.T or S.HEX sees the new values.
function S.Apply()
  if not S.Rune() then return end
  for k, v in pairs(RUNE.C) do S.C[k] = v end
  for k, v in pairs(RUNE.T) do S.T[k] = v end
  for k, v in pairs(RUNE.HEX) do S.HEX[k] = v end
  for name, role in pairs(FONT_ROLE) do
    local f, c = _G[name], S.C[role]
    if f and f.SetTextColor then f:SetTextColor(c[1], c[2], c[3]) end
  end
end
table.insert(WA.onLoad, 1, S.Apply)

function S.Tint(tex, kind, alpha)
  local c = S.T[kind] or S.T.accent
  tex:SetColorTexture(c[1], c[2], c[3], alpha or 1)
  return tex
end

-- A frame of the addon's own (the session bar, its panel) in the chosen style.
function S.Skin(f, alpha)
  if not (S.Rune() and f.SetBackdropColor) then return end
  local bg, ac = S.C.bg, S.T.accent
  f:SetBackdropColor(bg[1], bg[2], bg[3], alpha or 0.9)
  f:SetBackdropBorderColor(ac[1], ac[2], ac[3], 0.45)
end

local function Rotate(tex, rad)
  return tex.SetRotation ~= nil and pcall(tex.SetRotation, tex, rad)
end

-- rune: a flat square close button with an X.
function S.CloseButton(f)
  local b = CreateFrame("Button", nil, f, "BackdropTemplate")
  b:SetSize(24, 24)
  if b.SetBackdrop then
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    b:SetBackdropColor(S.C.card[1], S.C.card[2], S.C.card[3], 1)
    b:SetBackdropBorderColor(S.C.edge[1], S.C.edge[2], S.C.edge[3], 0.8)
  end
  local drawn = true
  for _, r in ipairs({ math.pi / 4, -math.pi / 4 }) do
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetSize(12, 2)
    t:SetPoint("CENTER")
    t:SetColorTexture(0.79, 0.81, 0.83, 1)
    if not Rotate(t, r) then t:Hide() drawn = false end
  end
  if not drawn then
    local x = b:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlight")
    x:SetPoint("CENTER", 0, 1)
    x:SetText("x")
  end
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetPoint("TOPLEFT", 1, -1)
  hl:SetPoint("BOTTOMRIGHT", -1, 1)
  S.Tint(hl, "hover", 0.15)
  b:SetScript("OnClick", function() f:Hide() end)
  return b
end

-- rune: the window's edge, its two lines and the four diamond studs.
local function RuneFrame(f)
  local bg, ac = S.C.bg, S.T.accent
  f:SetBackdrop(S.FLAT)
  f:SetBackdropColor(bg[1], bg[2], bg[3], 0.97)
  f:SetBackdropBorderColor(0.03, 0.035, 0.045, 1)
  -- the stone is lighter towards the top
  local shade = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  shade:SetPoint("TOPLEFT", 1, -1)
  shade:SetPoint("TOPRIGHT", -1, -1)
  shade:SetHeight(160)
  shade:SetColorTexture(1, 1, 1, 1)
  local ok = shade.SetGradient and CreateColor
    and pcall(shade.SetGradient, shade, "VERTICAL", CreateColor(0.2, 0.23, 0.27, 0), CreateColor(0.2, 0.23, 0.27, 0.35))
  if not ok then shade:SetColorTexture(0.2, 0.23, 0.27, 0.12) end
  local function Line(inset, r, g, b, a)
    local l = CreateFrame("Frame", nil, f, "BackdropTemplate")
    l:SetPoint("TOPLEFT", inset, -inset)
    l:SetPoint("BOTTOMRIGHT", -inset, inset)
    if l.SetBackdrop then
      l:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
      l:SetBackdropBorderColor(r, g, b, a)
    end
    return l
  end
  Line(2, 0.23, 0.27, 0.31, 1)
  f.glow = Line(4, ac[1], ac[2], ac[3], 0.45)
  local studs = CreateFrame("Frame", nil, f)
  studs:SetAllPoints()
  studs:SetFrameLevel(f.glow:GetFrameLevel() + 1)
  for _, p in ipairs({ { "TOPLEFT", 9, -9 }, { "TOPRIGHT", -9, -9 }, { "BOTTOMLEFT", 9, 9 }, { "BOTTOMRIGHT", -9, 9 } }) do
    for i, d in ipairs({ { 18, ac[1], ac[2], ac[3], 0.18 }, { 11, ac[1], ac[2], ac[3], 1 }, { 6, 0.055, 0.165, 0.21, 1 } }) do
      local t = studs:CreateTexture(nil, "OVERLAY", nil, i)
      t:SetSize(d[1], d[1])
      t:SetPoint("CENTER", f, p[1], p[2], p[3])
      t:SetColorTexture(d[2], d[3], d[4], d[5])
      if not Rotate(t, math.pi / 4) and i == 1 then t:Hide() end
    end
  end
end

local function Try(kind, name, parent, template)
  local ok, f = pcall(CreateFrame, kind, name, parent, template)
  if ok and f then return f end
  return nil
end

local DIALOG = {
  bgFile = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
  tile = false, edgeSize = 32,
  insets = { left = 11, right = 11, top = 11, bottom = 11 },
}
local FLAT = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }
S.FLAT = FLAT

-- A plain panel: solid colour with a 1 px edge (cards, the side menu).
function S.Panel(f, color, edge, edgeAlpha)
  if not f.SetBackdrop then return f end
  f:SetBackdrop(FLAT)
  local c, e = color or S.C.panel, edge or S.C.edge
  f:SetBackdropColor(c[1], c[2], c[3], 0.95)
  f:SetBackdropBorderColor(e[1], e[2], e[3], edgeAlpha or 0.35)
  return f
end

-- A movable window with a title and a close button. Returns the frame; frame.inset is how far
-- content keeps from the edges, frame.top where content may start.
-- wow: dark stone with the gold dialog border and the title banner on the top edge.
function S.Window(name, w, h, title)
  local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
  local banner
  f:SetSize(w, h)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  tinsert(UISpecialFrames, name)
  f.title = f:CreateFontString(nil, "OVERLAY", "WowAssistantFontTitle")
  local close
  if S.Rune() then
    RuneFrame(f)
    f.emblem = f:CreateTexture(nil, "ARTWORK")
    f.emblem:SetTexture("Interface\\AddOns\\WowAssistant\\Media\\Waystone")
    f.emblem:SetSize(24, 24)
    f.emblem:SetPoint("TOPLEFT", 16, -11)
    f.title:SetPoint("LEFT", f.emblem, "RIGHT", 8, 0)
    local rule = f:CreateTexture(nil, "ARTWORK")
    S.Tint(rule, "rule", 0.45)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 12, -42)
    rule:SetPoint("TOPRIGHT", -12, -42)
    close = S.CloseButton(f)
    close:SetPoint("TOPRIGHT", -18, -10)
    f.inset = 16
    f.top = 52
  elseif S.Wow() then
    close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f:SetBackdrop(DIALOG)
    f:SetBackdropColor(S.C.bg[1], S.C.bg[2], S.C.bg[3], 0.97)
    -- a warm glow from the top, so the stone is not flat black
    local glow = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    glow:SetPoint("TOPLEFT", 11, -11)
    glow:SetPoint("TOPRIGHT", -11, -11)
    glow:SetHeight(120)
    glow:SetColorTexture(0.55, 0.4, 0.18, 0.08)
    -- the title banner sits on the top edge
    banner = f:CreateTexture(nil, "ARTWORK")
    banner:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    banner:SetPoint("TOP", 0, 12)
    f.banner = banner
    f.title:SetPoint("TOP", banner, "TOP", 0, -14)
    f.inset = 16
    close:SetPoint("TOPRIGHT", -4, -4)
    f.top = 34
  else
    close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f:SetBackdrop(FLAT)
    f:SetBackdropColor(0.05, 0.04, 0.03, 0.96)
    f:SetBackdropBorderColor(0.45, 0.35, 0.15, 1)
    f.inset = 10
    f.title:SetFontObject("WowAssistantFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -8)
    close:SetPoint("TOPRIGHT", 2, 2)
    f.top = 26
  end
  f.title:SetText(title or "")
  if banner then
    -- Only the middle ~55% of the banner texture is the plate the text sits on (the rest is the
    -- curled ends), so size it from the measured text and never wider than the window.
    local bw = math.max(256, f.title:GetStringWidth() / 0.55 + 20)
    if w and w > 0 then bw = math.min(bw, w - 20) end
    banner:SetSize(bw, 64)
  end
  f.close = close
  return f
end

local function FontButton(b)
  b:SetNormalFontObject("WowAssistantFontNormal")
  b:SetHighlightFontObject("WowAssistantFontHighlight")
  b:SetDisabledFontObject("WowAssistantFontDisableSmall")
  return b
end

function S.Button(parent, text, w, onClick)
  local b
  if S.Rune() then
    -- flat: slate with a thin edge, the rune blue under the mouse
    b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, 22)
    if b.SetBackdrop then
      b:SetBackdrop(FLAT)
      b:SetBackdropColor(S.C.card[1], S.C.card[2], S.C.card[3], 1)
      b:SetBackdropBorderColor(S.C.edge[1], S.C.edge[2], S.C.edge[3], 0.7)
    end
    local fs = b:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlight")
    fs:SetPoint("LEFT", 6, 0)
    fs:SetPoint("RIGHT", -6, 0)
    fs:SetWordWrap(false)
    b:SetFontString(fs)
    b:SetNormalFontObject("WowAssistantFontHighlight")
    b:SetHighlightFontObject("WowAssistantFontHighlight")
    b:SetDisabledFontObject("WowAssistantFontDisableSmall")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    S.Tint(hl, "hover", 0.14)
    if b.SetPushedTextOffset then b:SetPushedTextOffset(1, -1) end
  else
    b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    FontButton(b)
  end
  b:SetText(text)
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

function S.Check(parent, label, onClick)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(22, 22)
  c.label = c:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlightSmall")
  c.label:SetPoint("LEFT", c, "RIGHT", 1, 0)
  c.label:SetText(label)
  local tick = S.Rune() and c.GetCheckedTexture and c:GetCheckedTexture()
  if tick then
    -- the rune style's tick is the rune blue
    if tick.SetDesaturated then tick:SetDesaturated(true) end
    tick:SetVertexColor(S.T.accent[1], S.T.accent[2], S.T.accent[3])
  end
  if onClick then c:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end) end
  return c
end

-- A search box with its label on the left.
function S.Search(parent, label, w, onChange)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(w, 20)
  e:SetAutoFocus(false)
  e:SetFontObject("WowAssistantFontHighlightSmall")
  e:SetScript("OnTextChanged", function(self) onChange(self:GetText() or "") end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  e.label = parent:CreateFontString(nil, "OVERLAY", "WowAssistantFontNormalSmall")
  e.label:SetPoint("RIGHT", e, "LEFT", -8, 0)
  e.label:SetText(label)
  return e
end

-- Dropdown: items() -> { { value, label }, ... }; get() -> current value; set(value).
-- The game's current dropdown where it exists, the older UIDropDownMenu otherwise, and a button
-- that steps through the values as a last resort. :Refresh() updates the shown text.
local ddCount = 0
function S.Dropdown(parent, w, items, get, set)
  local function LabelOf(v)
    for _, it in ipairs(items()) do if it[1] == v then return it[2] end end
    return tostring(v)
  end
  local dd = Try("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  if dd and dd.SetupMenu then
    dd:SetWidth(w)
    dd:SetupMenu(function(_, root)
      for _, it in ipairs(items()) do
        root:CreateRadio(it[2], function() return get() == it[1] end, function() set(it[1]) end)
      end
    end)
    if type(dd.Text) == "table" and dd.Text.SetFontObject then dd.Text:SetFontObject("WowAssistantFontHighlightSmall") end
    function dd:Refresh() if self.GenerateMenu then self:GenerateMenu() end end
    return dd
  end
  ddCount = ddCount + 1
  dd = UIDropDownMenu_Initialize and Try("Frame", "WowAssistantDropdown" .. ddCount, parent, "UIDropDownMenuTemplate")
  if dd then
    UIDropDownMenu_SetWidth(dd, w - 20)
    UIDropDownMenu_Initialize(dd, function()
      for _, it in ipairs(items()) do
        local info = UIDropDownMenu_CreateInfo()
        info.text, info.checked = it[2], get() == it[1]
        info.func = function() set(it[1]) UIDropDownMenu_SetText(dd, it[2]) CloseDropDownMenus() end
        UIDropDownMenu_AddButton(info)
      end
    end)
    function dd:Refresh() UIDropDownMenu_SetText(self, LabelOf(get())) end
    dd:Refresh()
    return dd
  end
  local b = S.Button(parent, "", w)
  b:SetScript("OnClick", function()
    local list = items()
    for i, it in ipairs(list) do
      if it[1] == get() then set(list[i % #list + 1][1]) b:Refresh() return end
    end
    if list[1] then set(list[1][1]) end
    b:Refresh()
  end)
  function b:Refresh() self:SetText(LabelOf(get())) end
  b:Refresh()
  return b
end

-- Page tabs. wow: the game's tabs under the window; flat: a row of buttons at the top.
-- Returns { Select(id) }; .height is the room the tabs take at the top (0 for wow).
function S.Tabs(f, list, onSelect)
  local T = { buttons = {}, height = 0 }
  local wow = S.Wow() and PanelTemplates_SetTab and f:GetName()
  if wow then
    f.Tabs = {}
    for i, t in ipairs(list) do
      local b = Try("Button", f:GetName() .. "Tab" .. i, f, "PanelTabButtonTemplate")
      if not b then wow = false break end
      b:SetID(i)
      b:SetText(t[2])
      if PanelTemplates_TabResize then PanelTemplates_TabResize(b, 0) end
      if i == 1 then b:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 6)
      else b:SetPoint("LEFT", f.Tabs[i - 1], "RIGHT", -12, 0) end
      b:SetScript("OnClick", function() onSelect(t[1]) end)
      f.Tabs[i] = b
      T.buttons[t[1]] = i
    end
    if wow then
      f.numTabs = #list
      PanelTemplates_SetNumTabs(f, #list)
      function T.Select(id) PanelTemplates_SetTab(f, T.buttons[id] or 1) end
      return T
    end
  end
  T.height = 28
  for i, t in ipairs(list) do
    local b = S.Button(f, t[2], 112, function() onSelect(t[1]) end)
    b:SetPoint("TOPLEFT", f.inset + (i - 1) * 116, -f.top)
    T.buttons[t[1]] = b
  end
  function T.Select(id) for k, b in pairs(T.buttons) do b:SetEnabled(k ~= id) end end
  return T
end

-- A scroll area with a scroll bar (when the game has the template). Returns scroll, child.
function S.Scroll(f, left, top, right, bottom, width)
  local scroll = Try("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  local bar = scroll ~= nil
  scroll = scroll or CreateFrame("ScrollFrame", nil, f)
  scroll:SetPoint("TOPLEFT", left, -top)
  scroll:SetPoint("BOTTOMRIGHT", -(right + (bar and 24 or 0)), bottom)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(width, 10)
  scroll:SetScrollChild(child)
  if not bar then
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(s, delta)
      local max = math.max(0, (child.h or 0) - (tonumber(s:GetHeight()) or 0))
      s:SetVerticalScroll(math.max(0, math.min(max, (tonumber(s:GetVerticalScroll()) or 0) - delta * 48)))
    end)
  end
  return scroll, child
end

-- The setting; the windows change at the next /reload.
function S.Set(name)
  if name ~= "wow" and name ~= "flat" then name = "rune" end
  WA.db.style = name ~= "rune" and name or nil
  WA.Print(L"window style: " .. name .. L" (shown after /reload)")
end

WA.Command("style", function(rest)
  rest = (rest or ""):lower()
  if rest ~= "rune" and rest ~= "wow" and rest ~= "flat" then
    WA.Print(L"/wa style rune | wow | flat – now: " .. S.Name())
    return
  end
  S.Set(rest)
end, L"/wa style rune | wow | flat – window style (Runestone, game frame or flat)")
