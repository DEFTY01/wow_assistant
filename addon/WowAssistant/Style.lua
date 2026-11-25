-- WoW Assistant: fonts and the look of the windows.
--
-- Fonts: the game's own fonts have no ő and ű (they show as boxes), so the addon brings its own:
-- Fira Sans for text and Cinzel for titles (Fonts/, SIL Open Font License). Chat and tooltips keep
-- the game's font, so text sent there gets ő -> ö and ű -> ü.
--
-- Styles (/wa style wow | flat, after /reload):
--   wow   the default: dialog border and dark stone background, tabs under the window, dropdowns
--         and buttons from the game's own templates, so it looks like a game window;
--   flat  the plain dark panel with a thin gold edge (close to Daylight UI).

local _, WA = ...
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
MakeFont("WowAssistantFontTitle", S.TITLE, 16, 1, 0.82, 0)
MakeFont("WowAssistantFontHeader", S.TITLE, 13, 1, 0.82, 0)
MakeFont("WowAssistantFontNormal", S.BODY, 12, 1, 0.82, 0)
MakeFont("WowAssistantFontNormalSmall", S.BODY, 11, 1, 0.82, 0)
MakeFont("WowAssistantFontHighlight", S.BODY, 12, 1, 1, 1)
MakeFont("WowAssistantFontHighlightSmall", S.BODY, 11, 1, 1, 1)
MakeFont("WowAssistantFontDisableSmall", S.BODY, 10, 0.6, 0.6, 0.6)

-- For text shown in the game's own font (chat, tooltips).
local FIX = { ["ő"] = "ö", ["ű"] = "ü", ["Ő"] = "Ö", ["Ű"] = "Ü", ["→"] = "->", ["↑"] = "^", ["↓"] = "v", ["…"] = "...", ["≈"] = "~" }
function S.Fix(s)
  if type(s) ~= "string" then return s end
  return (s:gsub("[\226\197][\128-\191][\128-\191]?", function(c) return FIX[c] end))
end
WA.Fix = S.Fix

---------------------------------------------------------------------------
-- style
---------------------------------------------------------------------------
function S.Name()
  local st = WA.db and WA.db.style
  return st == "flat" and "flat" or "wow"
end
function S.Wow() return S.Name() == "wow" end

local function Try(kind, name, parent, template)
  local ok, f = pcall(CreateFrame, kind, name, parent, template)
  if ok and f then return f end
  return nil
end

local DIALOG = {
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 },
}
local FLAT = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }

-- A movable window with a title and a close button. Returns the frame; frame.inset is how far
-- content keeps from the edges.
function S.Window(name, w, h, title)
  local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
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
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  if S.Wow() then
    f:SetBackdrop(DIALOG)
    f:SetBackdropColor(1, 1, 1, 1)
    f.inset = 18
    f.title:SetPoint("TOP", 0, -16)
    close:SetPoint("TOPRIGHT", -5, -5)
    -- a thin gold rule under the title
    local rule = f:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(1, 0.82, 0, 0.35)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 18, -38)
    rule:SetPoint("TOPRIGHT", -18, -38)
    f.top = 44
  else
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
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 22)
  FontButton(b)
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

WA.Command("style", function(rest)
  rest = (rest or ""):lower()
  if rest ~= "wow" and rest ~= "flat" then
    WA.Print("/wa style wow | flat – most: " .. S.Name())
    return
  end
  WA.db.style = rest
  WA.Print("ablakstílus: " .. rest .. " (a /reload után látszik)")
end, "/wa style wow | flat – ablakstílus (játékos vagy letisztult)")
