-- WoW Assistant: the minimap button.
--
-- The icon: the Waystone logo (Media/Waystone.tga). /wa minimap icon switches between a few
-- others. Left click: main window; right click: vendor crafting; shift +
-- left click: session bar on/off; ctrl + left click: options; drag: move it around the minimap.
-- /wa minimap hides or shows it.
-- Also listed in the addon compartment (the addon list button by the minimap) where the client has one.

local _, WA = ...
local L = WA.L
local MB = {}
WA.Minimap = MB

-- { icon, badge (small texture on the bottom right corner, or nil), name, whole texture (no crop) }
local ICONS = WA.LR {
  { "Interface\\AddOns\\WowAssistant\\Media\\Waystone", nil, "Waystone", true },
  { "Interface\\Icons\\INV_Weapon_ShortBlade_05", "Interface\\MoneyFrame\\UI-GoldIcon", L"dagger and gold" },
  { "Interface\\Icons\\Ability_Rogue_Eviscerate", nil, "Eviscerate" },
  { "Interface\\Icons\\INV_Misc_Coin_01", nil, L"gold coins" },
  { "Interface\\Icons\\Ability_Stealth", nil, L"stealth" },
  { "Interface\\Icons\\INV_Misc_Map_01", nil, L"map" },
}
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local button

local function DB()
  WA.db.minimap = WA.db.minimap or { angle = 200, hide = false, icon = 1 }
  return WA.db.minimap
end

-- Position on the minimap's edge (round or square minimaps).
local function Place()
  local d = DB()
  local a = math.rad(d.angle or 200)
  local x, y = math.cos(a), math.sin(a)
  local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
  local r = (Minimap:GetWidth() / 2) + 5
  if shape == "SQUARE" then
    local m = math.max(math.abs(x), math.abs(y))
    x, y = x / m, y / m
    r = r - 2
  end
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", x * r, y * r)
end

local function SetIcon()
  local d = DB()
  local it = ICONS[d.icon or 1] or ICONS[1]
  button.icon:SetTexture(it[1])
  if it[4] then button.icon:SetTexCoord(0, 1, 0, 1) else button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  if not button.icon:GetTexture() then button.icon:SetTexture(FALLBACK_ICON) end
  if it[2] then button.badge:SetTexture(it[2]) button.badge:Show() else button.badge:Hide() end
end

---------------------------------------------------------------------------
-- tooltip
---------------------------------------------------------------------------
local GRADE_COLOR = { S = "ff8000", A = "a335ee", B = "0070dd", C = "1eff00", D = "9d9d9d" }

local function LastFightLine()
  local list = WA.charDB and WA.charDB.meterFights
  local f = list and list[#list]
  if not f then return nil end
  local baseline
  local G = WA.Game
  if G and G.IsRogue and G.IsRogue() and G.Context then
    local ok, ctx = pcall(G.Context)
    baseline = ok and ctx and ctx.baseline or nil
  end
  local ok, sc = pcall(WA.Combat.Score, f, baseline)
  local dps = (f.dur or 0) > 0 and (f.dmg or 0) / f.dur or 0
  local grade = ok and sc and ("|cff%s%d (%s)|r"):format(GRADE_COLOR[sc.grade] or "ffffff", sc.total, sc.grade) or "–"
  return ("%s: %.1f DPS, %s"):format(f.target or "?", dps, grade)
end

local function ShowTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("Waystone", 1, 0.82, 0)
  GameTooltip:AddLine(WA.Fix((L"%s's companion"):format(UnitName("player") or "")), 0.8, 0.8, 0.8)
  local last = LastFightLine()
  if last then
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(WA.Fix(L"Last fight"), WA.Fix(last), 1, 0.82, 0, 1, 1, 1)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine(WA.Fix(L"Left-click"), WA.Fix(L"main window"), 0.6, 0.8, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine(WA.Fix(L"Right-click"), WA.Fix(L"what to craft for vendors"), 0.6, 0.8, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine(WA.Fix(L"Shift + left-click"), WA.Fix(L"session bar on/off"), 0.6, 0.8, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine(WA.Fix(L"Ctrl + left-click"), WA.Fix(L"options"), 0.6, 0.8, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine(WA.Fix(L"Drag"), WA.Fix(L"move"), 0.6, 0.8, 1, 1, 1, 1)
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- clicks
---------------------------------------------------------------------------
local function ToggleSessionBar()
  local s = WA.db.session or {}
  if WA.Session then WA.Session.Command(s.hidden and "show" or "hide") end
end

function MB.Click(btn)
  if btn == "RightButton" then
    if WA.VC then WA.VC.Toggle() end
  elseif IsShiftKeyDown and IsShiftKeyDown() then
    ToggleSessionBar()
  elseif IsControlKeyDown and IsControlKeyDown() and WA.Options then
    WA.Options.Toggle()
  elseif WA.ToggleMain then
    WA.ToggleMain()
  end
end

-- The addon compartment (TOC: AddonCompartmentFunc) calls these globals.
function WowAssistant_OnAddonCompartmentClick(_, btn) MB.Click(btn) end
function WowAssistant_OnAddonCompartmentEnter(_, frame) ShowTooltip(frame) end
function WowAssistant_OnAddonCompartmentLeave() GameTooltip:Hide() end

---------------------------------------------------------------------------
-- the button
---------------------------------------------------------------------------
local function Build()
  local b = CreateFrame("Button", "WowAssistantMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(24, 24)
  bg:SetPoint("CENTER", 0, 1)

  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(20, 20)
  b.icon:SetPoint("CENTER", 0, 1)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  b.badge = b:CreateTexture(nil, "OVERLAY", nil, 1)
  b.badge:SetSize(11, 11)
  b.badge:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 3, -2)

  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  b:SetScript("OnClick", function(_, btn) MB.Click(btn) end)
  b:SetScript("OnEnter", ShowTooltip)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnMouseDown", function(self) self.icon:SetPoint("CENTER", 1, 0) end)
  b:SetScript("OnMouseUp", function(self) self.icon:SetPoint("CENTER", 0, 1) end)
  b:SetScript("OnDragStart", function(self)
    GameTooltip:Hide()
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      cx, cy = cx / scale, cy / scale
      DB().angle = math.deg((math.atan2 or math.atan)(cy - my, cx - mx)) % 360
      Place()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  return b
end

function MB.Update()
  if not Minimap then return end
  button = button or Build()
  SetIcon()
  Place()
  button:SetShown(not DB().hide)
end

table.insert(WA.onLogin, MB.Update)

-- For the Options window: { { index, name }, ... }, the current one, and choosing one.
function MB.Icons()
  local t = {}
  for i, it in ipairs(ICONS) do t[i] = { i, it[3] } end
  return t
end
function MB.Icon() return DB().icon or 1 end
function MB.SetIcon(i)
  if not ICONS[i] then return end
  DB().icon = i
  MB.Update()
end

WA.Command("minimap", function(rest)
  local d = DB()
  rest = strtrim(rest or ""):lower()
  if rest == "icon" then
    d.icon = (d.icon or 1) % #ICONS + 1
    WA.Print((L"minimap icon: %s (%d/%d)"):format(ICONS[d.icon][3], d.icon, #ICONS))
  elseif rest == "show" then
    d.hide = false
  elseif rest == "hide" then
    d.hide = true
  else
    d.hide = not d.hide
  end
  MB.Update()
end, L"/wa minimap [show | hide | icon] – minimap button on/off, change the icon")
