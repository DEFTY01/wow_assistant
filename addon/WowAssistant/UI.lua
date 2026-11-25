-- WoW Assistant: the main window (/wa). The web app's pages in game, page by page:
--   Haditerv     plan.ts        what to buy, learn, farm and craft with the gold you have
--   Harc         combat.ts      statistics and advice from the recorded fights
--   Felszerelés  gear.ts        dungeon upgrades for every slot, party buffs and consumables
--   Mesterségek  planRoutes     the cheapest way to skill each profession
-- plus buttons for the vendor-crafting window, the session bar and the Chronicle panel.
--
-- Every page is a list of blocks (heading, text, table, check boxes) drawn into one scrolling
-- area. Tables sort by clicking their header; the search box filters the rows of every table.

local _, WA = ...
local UI = {}
WA.UI = UI
local G = WA.Game

local W, H = 920, 600
local CONTENT_W = W - 36
local ROW_H = 16
local TABLE_LIMIT = 60

---------------------------------------------------------------------------
-- formatting
---------------------------------------------------------------------------
local function Money(c)
  if not c then return "|cff888888–|r" end
  local neg = c < 0
  c = math.floor(math.abs(c) + 0.5)
  local g, s, k = math.floor(c / 10000), math.floor(c % 10000 / 100), c % 100
  local t
  if g > 0 then t = ("%d|cffffd700g|r %02d|cffc7c7cfs|r"):format(g, s)
  elseif s > 0 then t = ("%d|cffc7c7cfs|r %02d|cffeda55fc|r"):format(s, k)
  else t = ("%d|cffeda55fc|r"):format(k) end
  return neg and ("-" .. t) or t
end
local function F1(n) return n and ("%.1f"):format(n) or "–" end
local function Pct(n) return n and (("%.1f%%"):format(n)) or "–" end
local function Gain(g) return g and ("|cff40ff40+%.1f|r"):format(g) or "–" end
local QCOLOR = { POOR = "9d9d9d", COMMON = "ffffff", UNCOMMON = "1eff00", RARE = "0070dd", EPIC = "a335ee", LEGENDARY = "ff8000" }
local QNUM = { [0] = "POOR", "COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY" }
local function Item(name, quality)
  if type(quality) == "number" then quality = QNUM[quality] end
  local c = QCOLOR[quality or "COMMON"] or "ffffff"
  return "|cff" .. c .. (name or "?") .. "|r"
end
local function Plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
UI.Money, UI.Item = Money, Item

-- cell: plain text, or { text, sort value }
local function Cell(text, value) return { text, value } end

---------------------------------------------------------------------------
-- window
---------------------------------------------------------------------------
local frame
UI.tab = "plan"
UI.filter = ""
UI.sort = {}       -- table id -> { column, direction }
UI.target = 300    -- profession route target
UI.cache = {}      -- tab -> blocks (cleared by Refresh)

local TABS = {
  { "plan", "Haditerv" }, { "combat", "Harc" }, { "gear", "Felszerelés" }, { "prof", "Mesterségek" },
}

local pools = { text = {}, row = {}, head = {}, check = {}, button = {} }
local used = { text = 0, row = 0, head = 0, check = 0, button = 0 }

local function Acquire(kind, make)
  used[kind] = used[kind] + 1
  local o = pools[kind][used[kind]]
  if not o then
    o = make()
    pools[kind][used[kind]] = o
  end
  o:ClearAllPoints()
  o:Show()
  return o
end

local function Text(parent, font)
  return Acquire("text", function()
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetJustifyH("LEFT")
    t:SetJustifyV("TOP")
    return t
  end)
end

local function Height(fs, fallback)
  local h = tonumber(fs:GetStringHeight())
  return (h and h > 0) and h or fallback
end

local function Build()
  local f = CreateFrame("Frame", "WowAssistantMainFrame", UIParent, "BackdropTemplate")
  f:SetSize(W, H)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  f:SetBackdropColor(0.05, 0.04, 0.03, 0.96)
  f:SetBackdropBorderColor(0.45, 0.35, 0.15, 1)
  tinsert(UISpecialFrames, "WowAssistantMainFrame")

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -8)
  title:SetText("WoW Assistant")
  f.who = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.who:SetPoint("LEFT", title, "RIGHT", 10, 0)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  local function Btn(text, w, x, y, onClick, anchor)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(w, 20)
    b:SetPoint(anchor or "TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
  end
  f.tabs = {}
  for i, t in ipairs(TABS) do
    f.tabs[t[1]] = Btn(t[2], 110, 10 + (i - 1) * 114, -28, function() UI.Show(t[1]) end)
  end
  -- the other windows of the addon
  Btn("Vendor", 70, 10 + #TABS * 114 + 8, -28, function() if WA.VC then WA.VC.Toggle() end end)
  Btn("Session sáv", 90, 10 + #TABS * 114 + 82, -28, function()
    local hidden = WA.db.session and WA.db.session.hidden
    if WA.Session then WA.Session.Command(hidden and "show" or "hide") end
  end)
  Btn("Chronicle", 80, 10 + #TABS * 114 + 176, -28, function() if WA.Chronicle then WA.Chronicle.Command("") end end)

  local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  search:SetSize(130, 20)
  search:SetPoint("TOPRIGHT", -112, -28)
  search:SetAutoFocus(false)
  search:SetScript("OnTextChanged", function(e) UI.filter = e:GetText() or "" UI.Draw() end)
  search:SetScript("OnEscapePressed", function(e) e:ClearFocus() end)
  local sl = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  sl:SetPoint("BOTTOMLEFT", search, "TOPLEFT", -4, 1)
  sl:SetText("szűrés minden táblában")
  Btn("Frissítés", 96, -12, -28, function() UI.Refresh() end, "TOPRIGHT")

  local scroll = CreateFrame("ScrollFrame", nil, f)
  scroll:SetPoint("TOPLEFT", 10, -58)
  scroll:SetPoint("BOTTOMRIGHT", -14, 24)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(CONTENT_W, 10)
  scroll:SetScrollChild(child)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(s, delta)
    local max = math.max(0, (child.h or 0) - (tonumber(s:GetHeight()) or 0))
    s:SetVerticalScroll(math.max(0, math.min(max, (tonumber(s:GetVerticalScroll()) or 0) - delta * 48)))
    UI.UpdateScrollNote()
  end)
  f.scroll, f.child = scroll, child
  f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.note:SetPoint("BOTTOMLEFT", 10, 7)
  f.note:SetPoint("RIGHT", -10, 0)
  f.note:SetJustifyH("LEFT")
  f:Hide()
  return f
end

function UI.UpdateScrollNote()
  if not frame then return end
  local s = frame.scroll
  local max = math.max(0, (frame.child.h or 0) - (tonumber(s:GetHeight()) or 0))
  local at = tonumber(s:GetVerticalScroll()) or 0
  local where = max <= 0 and "" or (at <= 0 and "görgess lefelé ▼" or (at >= max - 1 and "▲ az oldal vége" or "▲ görgess ▼"))
  frame.note:SetText((UI.status or "") .. (where ~= "" and ("   ·   " .. where) or ""))
end

---------------------------------------------------------------------------
-- drawing blocks
---------------------------------------------------------------------------
local function Matches(cells, needle)
  if needle == "" then return true end
  for _, c in ipairs(cells) do
    local t = type(c) == "table" and c[1] or c
    if Plain(t):lower():find(needle, 1, true) then return true end
  end
  return false
end

local function SortValue(c)
  if type(c) == "table" then
    if c[2] ~= nil then return c[2] end
    c = c[1]
  end
  return Plain(c):lower()
end

local function Less(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return ta == "number" end
  return a < b
end

local function DrawTable(child, b, y)
  local needle = UI.filter:lower()
  local rows = {}
  for _, r in ipairs(b.rows) do if Matches(r.cells or r, needle) then rows[#rows + 1] = r end end
  local s = UI.sort[b.id]
  if s then
    local idx = {}
    for i, r in ipairs(rows) do idx[r] = i end
    table.sort(rows, function(x, z)
      local va, vb = SortValue((x.cells or x)[s[1]]), SortValue((z.cells or z)[s[1]])
      if va == vb then return idx[x] < idx[z] end
      if s[2] > 0 then return Less(va, vb) end
      return Less(vb, va)
    end)
  end
  -- header
  local x = 0
  for i, c in ipairs(b.cols) do
    local h = Acquire("head", function()
      local btn = CreateFrame("Button", nil, child)
      btn:SetHeight(ROW_H)
      btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      btn.text:SetAllPoints()
      btn.text:SetWordWrap(false)
      return btn
    end)
    h:SetWidth(c[2])
    h:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
    h.text:SetJustifyH(c[3] or "LEFT")
    h.text:SetText(c[1] .. ((s and s[1] == i) and (s[2] > 0 and " ▲" or " ▼") or ""))
    h:SetScript("OnClick", function()
      local cur = UI.sort[b.id]
      if cur and cur[1] == i then cur[2] = -cur[2]
      else UI.sort[b.id] = { i, (c[3] == "RIGHT") and -1 or 1 } end
      UI.Draw()
    end)
    x = x + c[2] + 6
  end
  y = y + ROW_H + 2
  local limit = b.limit or TABLE_LIMIT
  for n, r in ipairs(rows) do
    if n > limit then break end
    local row = Acquire("row", function()
      local btn = CreateFrame("Button", nil, child)
      btn:SetHeight(ROW_H)
      btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      btn.bg = btn:CreateTexture(nil, "BACKGROUND")
      btn.bg:SetAllPoints()
      btn.bg:SetColorTexture(1, 0.85, 0.5, 0.04)
      btn.cells = {}
      btn:SetScript("OnEnter", function(self)
        if not self.itemId and not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        if self.itemId then pcall(GameTooltip.SetItemByID, GameTooltip, self.itemId) end
        if self.tip then GameTooltip:AddLine(self.tip, 1, 0.82, 0.5, true) end
        GameTooltip:Show()
      end)
      btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
      return btn
    end)
    row:SetWidth(CONTENT_W)
    row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
    row.bg:SetShown(n % 2 == 0)
    row.itemId, row.tip = r.itemId, r.tip
    local cells = r.cells or r
    local cx = 0
    for i, c in ipairs(b.cols) do
      local fs = row.cells[i]
      if not fs then
        fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetWordWrap(false)
        row.cells[i] = fs
      end
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", row, "LEFT", cx, 0)
      fs:SetWidth(c[2])
      fs:SetJustifyH(c[3] or "LEFT")
      local v = cells[i]
      fs:SetText(type(v) == "table" and v[1] or v or "")
      fs:Show()
      cx = cx + c[2] + 6
    end
    for i = #b.cols + 1, #row.cells do row.cells[i]:Hide() end
    y = y + ROW_H
  end
  if #rows == 0 then
    local t = Text(child)
    t:SetWidth(CONTENT_W)
    t:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
    t:SetText(needle ~= "" and "|cff888888(a szűrésnek egy sor sem felel meg)|r" or ("|cff888888" .. (b.empty or "nincs adat") .. "|r"))
    y = y + 14
  elseif #rows > limit then
    local t = Text(child)
    t:SetWidth(CONTENT_W)
    t:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
    t:SetText(("|cff888888… és még %d sor: szűrj a keresőmezővel.|r"):format(#rows - limit))
    y = y + 14
  end
  return y + 8
end

local function DrawChecks(child, b, y)
  local per = b.perRow or 3
  local w = CONTENT_W / per
  for i, c in ipairs(b.checks) do
    local cb = Acquire("check", function()
      local btn = CreateFrame("CheckButton", nil, child, "UICheckButtonTemplate")
      btn:SetSize(20, 20)
      btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      btn.label:SetPoint("LEFT", btn, "RIGHT", 2, 0)
      btn.label:SetJustifyH("LEFT")
      btn.label:SetWordWrap(false)
      return btn
    end)
    local col, line = (i - 1) % per, math.floor((i - 1) / per)
    cb:SetPoint("TOPLEFT", child, "TOPLEFT", col * w, -(y + line * 20))
    cb.label:SetWidth(w - 26)
    cb.label:SetText(c.label)
    cb:SetChecked(c.checked and true or false)
    cb:SetEnabled(not c.disabled)
    cb:SetScript("OnClick", function(self) c.onClick(self:GetChecked() and true or false) end)
  end
  return y + math.ceil(#b.checks / per) * 20 + 6
end

local function DrawButtons(child, b, y)
  local x = 0
  for _, c in ipairs(b.buttons) do
    local btn = Acquire("button", function()
      return CreateFrame("Button", nil, child, "UIPanelButtonTemplate")
    end)
    btn:SetSize(c.width or 120, 20)
    btn:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
    btn:SetText(c.label)
    btn:SetEnabled(not c.disabled)
    btn:SetScript("OnClick", c.onClick)
    x = x + (c.width or 120) + 6
  end
  return y + 26
end

function UI.Draw()
  if not frame or not frame:IsShown() then return end
  for k in pairs(used) do used[k] = 0 end
  local blocks = UI.cache[UI.tab]
  if not blocks then
    local ok, res = pcall(UI.pages[UI.tab])
    blocks = ok and res or { { h = "Hiba" }, { p = "|cffff5050" .. tostring(res) .. "|r" } }
    UI.cache[UI.tab] = blocks
  end
  local child = frame.child
  local y = 0
  for _, b in ipairs(blocks) do
    if b.h then
      local t = Text(child)
      t:SetFontObject(b.small and "GameFontNormalSmall" or "GameFontNormal")
      t:SetWidth(CONTENT_W)
      t:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(y + (b.small and 2 or 6)))
      t:SetText(b.h)
      y = y + (b.small and 18 or 24)
    elseif b.p then
      local t = Text(child)
      t:SetFontObject("GameFontHighlightSmall")
      t:SetWidth(CONTENT_W)
      t:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
      t:SetText(b.p)
      y = y + Height(t, 14) + 4
    elseif b.table then
      y = DrawTable(child, b.table, y)
    elseif b.checks then
      y = DrawChecks(child, b, y)
    elseif b.buttons then
      y = DrawButtons(child, b, y)
    end
  end
  for kind, list in pairs(pools) do
    for i = used[kind] + 1, #list do list[i]:Hide() end
  end
  child.h = y + 10
  child:SetHeight(math.max(10, y + 10))
  for id, b in pairs(frame.tabs) do b:SetEnabled(id ~= UI.tab) end
  frame.who:SetText(("%s · %d. szint · %s"):format(WA.key or UnitName("player"), UnitLevel("player"), Money(GetMoney())))
  UI.UpdateScrollNote()
end

-- Recomputes the current page (new prices, fights, gear...).
function UI.Refresh()
  UI.cache = {}
  UI.Draw()
end

function UI.Show(tab)
  frame = frame or Build()
  if tab and tab ~= UI.tab then
    UI.tab = tab
    frame.scroll:SetVerticalScroll(0)
  end
  frame:Show()
  UI.Draw()
end

function UI.Toggle()
  frame = frame or Build()
  if frame:IsShown() then frame:Hide() return end
  UI.cache = {}
  UI.Show()
end
WA.ToggleMain = UI.Toggle

-- A new fight from the damage meter: the combat page is out of date.
function WA.OnFight()
  UI.cache.combat, UI.cache.plan, UI.cache.gear = nil, nil, nil
  if frame and frame:IsShown() and (UI.tab == "combat") then UI.Draw() end
end

---------------------------------------------------------------------------
-- pages
---------------------------------------------------------------------------
UI.pages = {}
local function Warn(out, list)
  for _, w in ipairs(list or {}) do out[#out + 1] = { p = "|cffff9933! " .. w .. "|r" } end
end

local function NotRogue()
  return {
    { h = "Csak rogue-ra" },
    { p = "A sebzésmodell (és vele a haditerv és a felszerelés oldal) a rogue-ra készült, ahogy a webappban is. " ..
      "A Mesterségek és a Vendor ablak minden karakteren működik." },
  }
end

local SOURCE_HU = { ah = "AH", craft = "gyártás", trainer = "trainer", owned = "megvan", quest = "quest" }

local function OptionRows(list, withCost)
  local rows = {}
  for _, o in ipairs(list) do
    local cells = {
      Cell(o.itemId and Item(o.title, o.quality) or o.title, o.title), SOURCE_HU[o.source] or o.source,
      Cell(Gain(o.gain), o.gain), Cell(Pct(o.gainPct), o.gainPct),
    }
    if withCost then cells[#cells + 1] = Cell(Money(o.cost), o.cost) end
    cells[#cells + 1] = (o.where or "") .. (o.req and (" |cffff9933(" .. o.req .. ". szinttől)|r") or "")
    rows[#rows + 1] = { cells = cells, itemId = o.itemId,
      tip = (o.detail or "") .. (o.warning and ("\n" .. o.warning) or "") .. (o.estimated and "\n(becsült érték)" or "") }
  end
  return rows
end

local function OptionCols(withCost)
  local cols = { { "Mit", 230 }, { "Honnan", 60 }, { "DPS", 50, "RIGHT" }, { "%", 48, "RIGHT" } }
  if withCost then cols[#cols + 1] = { "Ár", 90, "RIGHT" } end
  cols[#cols + 1] = { "Hol / megjegyzés", withCost and 360 or 456 }
  return cols
end

function UI.pages.plan()
  if not G.IsRogue() then return NotRogue() end
  local ctx = G.Context()
  local p = WA.Plan.Build(G.PlanInput(ctx))
  local out = {}
  out[#out + 1] = { h = ("Haditerv – %s, %d. szint, %s"):format(p.name, p.level, Money(p.gold)) }
  out[#out + 1] = { p = ("Becsült DPS most: |cffffffff%s|r (buffok nélkül %s)%s · a terv után: |cff40ff40%s|r")
    :format(F1(p.baseline), F1(p.unbuffed), p.measuredDps and (" · mért: " .. F1(p.measuredDps)) or "", F1(p.projected)) }
  Warn(out, p.warnings)

  out[#out + 1] = { h = "Ezt vedd meg most", small = true }
  out[#out + 1] = { p = ("Elköltve %s, marad %s. A sor fölé húzva az egeret: részletek."):format(Money(p.spent), Money(p.left)) }
  out[#out + 1] = { table = { id = "plan.buy", cols = OptionCols(true), rows = OptionRows(p.buy, true),
    empty = "Ebből az aranyból most nincs érdemi fejlesztés." } }
  if #p.free > 0 then
    out[#out + 1] = { h = "Ingyen: már nálad van vagy le tudod gyártani", small = true }
    out[#out + 1] = { table = { id = "plan.free", cols = OptionCols(false), rows = OptionRows(p.free, false) } }
  end
  if #p.wishlist > 0 then
    out[#out + 1] = { h = "Ha több aranyad lenne", small = true }
    out[#out + 1] = { table = { id = "plan.wish", cols = OptionCols(true), rows = OptionRows(p.wishlist, true) } }
  end
  if #p.quests > 0 then
    out[#out + 1] = { h = "Quest-jutalmak", small = true }
    out[#out + 1] = { table = { id = "plan.quest", cols = OptionCols(false), rows = OptionRows(p.quests, false) } }
  end
  if #p.combat > 0 then
    out[#out + 1] = { h = "A harcaid alapján", small = true }
    for _, a in ipairs(p.combat) do
      out[#out + 1] = { p = ("|cffffd100%s|r – %s"):format(a.title, a.text) }
    end
  end
  if #p.skills > 0 then
    out[#out + 1] = { h = "Trainer", small = true }
    local TIER = { dps = "|cff40ff40DPS|r", core = "|cffffd100alap|r", situational = "helyzeti", skip = "|cff888888kihagyható|r" }
    local TIER_N = { dps = 0, core = 1, situational = 2, skip = 3 }
    local rows = {}
    for _, s in ipairs(p.skills) do
      rows[#rows + 1] = { Cell(s.name, s.name), Cell(TIER[s.tier] or s.tier, TIER_N[s.tier]), Cell(Money(s.cost), s.cost),
        Cell(s.gain > 0 and Gain(s.gain) or "", s.gain), s.why }
    end
    out[#out + 1] = { table = { id = "plan.skills", cols = { { "Képesség", 170 }, { "Fontos", 70 }, { "Ár", 90, "RIGHT" },
      { "DPS", 50, "RIGHT" }, { "Miért", 470 } }, rows = rows } }
  end
  if #p.farm > 0 then
    out[#out + 1] = { h = "Hova menj farmolni", small = true }
    local rows = {}
    for _, d in ipairs(p.farm) do
      local names = {}
      for i = 1, math.min(3, #d.upgrades) do names[i] = Item(d.upgrades[i].name, d.upgrades[i].quality) end
      rows[#rows + 1] = { d.name, d.levels, Cell(Gain(d.gain), d.gain), Cell(d.perRun and Gain(d.perRun) or "–", d.perRun or 0),
        table.concat(names, ", ") }
    end
    out[#out + 1] = { table = { id = "plan.farm", cols = { { "Dungeon", 170 }, { "Szint", 50 }, { "Összes DPS", 70, "RIGHT" },
      { "Futásonként", 76, "RIGHT" }, { "Legjobb tárgyak", 480 } }, rows = rows } }
  end
  if #p.professions > 0 then
    out[#out + 1] = { h = "Mesterségek", small = true }
    local rows = {}
    for _, r in ipairs(p.professions) do
      rows[#rows + 1] = { r.name, Cell(r.skill .. " / " .. r.cap, r.skill), r.next or "–", Cell(Money(r.cost), r.cost), r.note or "" }
    end
    out[#out + 1] = { table = { id = "plan.prof", cols = { { "Szakma", 110 }, { "Skill", 60 }, { "Következő lépés", 300 },
      { "Ára", 90, "RIGHT" }, { "Megjegyzés", 300 } }, rows = rows } }
  end
  if #p.consumables > 0 then
    out[#out + 1] = { h = "Fogyóeszközök (óránkénti ár az AH-ban)", small = true }
    local rows = {}
    for _, c in ipairs(p.consumables) do
      rows[#rows + 1] = { cells = { c.name, c.summary, Cell(Gain(c.gain), c.gain), Cell(Money(c.perHour), c.perHour or math.huge),
        Cell(Money(c.price), c.price or math.huge) }, itemId = c.itemId }
    end
    out[#out + 1] = { table = { id = "plan.cons", cols = { { "Mi", 200 }, { "Hatás", 280 }, { "DPS", 50, "RIGHT" },
      { "Óránként", 90, "RIGHT" }, { "Darabja", 90, "RIGHT" } }, rows = rows } }
  end
  if #p.roadmap > 0 then
    out[#out + 1] = { h = "A következő szintek", small = true }
    local rows = {}
    for _, r in ipairs(p.roadmap) do
      local gear = {}
      for _, g in ipairs(r.gear) do gear[#gear + 1] = Item(g.title, g.quality) .. " " .. Gain(g.gain) end
      rows[#rows + 1] = { Cell(r.level, r.level), table.concat(r.skills, ", "), Cell(Money(r.skillCost), r.skillCost), table.concat(gear, ", ") }
    end
    out[#out + 1] = { table = { id = "plan.road", cols = { { "Szint", 40 }, { "Új képességek", 300 }, { "Ára", 90, "RIGHT" },
      { "Felszerelés", 440 } }, rows = rows } }
  end
  UI.status = ("%d AH-ajánlat · %d harc a modellben"):format(#(G.Offers()), ctx.combat and ctx.combat.fights or 0)
  return out
end

function UI.pages.combat()
  local all = G.Fights()
  local r = WA.Combat.Report(all)
  local out = {}
  local meter = 0
  for _, f in ipairs(all) do if f.source == "meter" then meter = meter + 1 end end
  UI.status = ("%d harc: %d a harcnaplóból (feltöltő), %d a damage meterből"):format(#all, #all - meter, meter)
  if not r then
    out[#out + 1] = { h = "Harc" }
    out[#out + 1] = { p = "Még nincs rögzített harc. Kapcsold be a harcnaplót (/wa log), és fusson a feltöltő " ..
      "(node scripts/uploader.mjs): a harcokat a Fights.lua-ba írja, amit a játék /reload után lát. " ..
      (C_DamageMeter and "A kliens damage meteréből is jönnek harcok, de csak összesítve." or "") }
    return out
  end
  out[#out + 1] = { h = ("Harc – %d harc, %d perc, átlag %s DPS"):format(r.fights, math.floor(r.seconds / 60 + 0.5), F1(r.dps)) }
  if r.energyCappedPct then out[#out + 1] = { p = ("Energiaplafonon töltött idő: %s"):format(Pct(r.energyCappedPct)) } end
  if meter > 0 then
    out[#out + 1] = { p = "|cff888888A damage meterből jött harcokban nincs találati statisztika: a táblák arányait csak a harcnapló harcai adják.|r" }
  end
  if #r.advice > 0 then
    out[#out + 1] = { h = "Tanácsok", small = true }
    local COLOR = { fix = "ff6060", tip = "ffd100", info = "aaaaaa" }
    for _, a in ipairs(r.advice) do
      out[#out + 1] = { p = ("|cff%s%s|r – %s"):format(COLOR[a.level] or "ffffff", a.title, a.text) }
    end
  end
  out[#out + 1] = { h = "Képességek", small = true }
  local rows = {}
  for _, a in ipairs(r.abilities) do
    local landed = a.hit + a.crit + a.glance
    rows[#rows + 1] = { a.name, Cell(Pct(a.share), a.share), Cell(a.dmg, a.dmg), Cell(a.n, a.n), Cell(math.floor(a.avg + 0.5), a.avg),
      Cell(a.max, a.max), Cell(Pct(landed > 0 and a.crit / landed * 100 or 0), landed > 0 and a.crit / landed or 0),
      Cell(Pct(a.n > 0 and a.miss / a.n * 100 or 0), a.n > 0 and a.miss / a.n or 0),
      Cell(Pct(a.n > 0 and a.dodge / a.n * 100 or 0), a.n > 0 and a.dodge / a.n or 0),
      Cell(Pct(a.n > 0 and a.parry / a.n * 100 or 0), a.n > 0 and a.parry / a.n or 0),
      Cell(Pct(a.n > 0 and a.glance / a.n * 100 or 0), a.n > 0 and a.glance / a.n or 0) }
  end
  out[#out + 1] = { table = { id = "combat.ab", cols = { { "Képesség", 180 }, { "Arány", 56, "RIGHT" }, { "Sebzés", 66, "RIGHT" },
    { "Db", 48, "RIGHT" }, { "Átlag", 48, "RIGHT" }, { "Max", 48, "RIGHT" }, { "Crit", 56, "RIGHT" }, { "Miss", 56, "RIGHT" },
    { "Dodge", 56, "RIGHT" }, { "Parry", 56, "RIGHT" }, { "Glancing", 60, "RIGHT" } }, rows = rows } }
  out[#out + 1] = { p = ("Auto-attack: %s miss, %s dodge, %s glancing, %s crit · képességek: %s miss, %s crit")
    :format(Pct(r.white.miss), Pct(r.white.dodge), Pct(r.white.glance), Pct(r.white.crit), Pct(r.yellow.miss), Pct(r.yellow.crit)) }
  if #r.finishers > 0 or #r.auras > 0 then
    out[#out + 1] = { h = "Finisherek és buffok", small = true }
    local rows2 = {}
    for _, x in ipairs(r.finishers) do rows2[#rows2 + 1] = { x.name, "finisher", Cell(x.casts .. " ×, átlag " .. F1(x.avgCp) .. " CP", x.casts) } end
    for _, x in ipairs(r.auras) do rows2[#rows2 + 1] = { x.name, "buff", Cell(Pct(x.uptimePct) .. " uptime", x.uptimePct) } end
    out[#out + 1] = { table = { id = "combat.fin", cols = { { "Név", 200 }, { "Fajta", 80 }, { "Érték", 200 } }, rows = rows2 } }
  end
  if #r.byLevel > 0 then
    out[#out + 1] = { h = "Célpont szintje szerint", small = true }
    local rows3 = {}
    for _, x in ipairs(r.byLevel) do
      rows3[#rows3 + 1] = { Cell((x.diff > 0 and "+" or "") .. x.diff, x.diff), Cell(x.fights, x.fights), Cell(F1(x.dps), x.dps), Cell(Pct(x.missPct), x.missPct) }
    end
    out[#out + 1] = { table = { id = "combat.lvl", cols = { { "Szintkülönbség", 110 }, { "Harc", 60, "RIGHT" }, { "DPS", 70, "RIGHT" },
      { "Fehér miss", 80, "RIGHT" } }, rows = rows3 } }
  end
  out[#out + 1] = { h = "Legutóbbi harcok", small = true }
  local rows4 = {}
  for _, f in ipairs(r.recent) do
    rows4[#rows4 + 1] = { Cell(date("%m.%d %H:%M", f.start), f.start), f.target .. ((f.targetLevel or 0) > 0 and (" (" .. f.targetLevel .. ")") or ""),
      Cell(F1(f.dur) .. " mp", f.dur), Cell(F1(f.dps), f.dps), f.source == "meter" and "damage meter" or "harcnapló" }
  end
  out[#out + 1] = { table = { id = "combat.recent", cols = { { "Mikor", 90 }, { "Célpont", 220 }, { "Hossz", 70, "RIGHT" },
    { "DPS", 60, "RIGHT" }, { "Forrás", 100 } }, rows = rows4 } }
  return out
end

function UI.pages.gear()
  if not G.IsRogue() then return NotRogue() end
  local ctx = G.Context()
  local g = WA.Model.GearReport(ctx, 3)
  local out = {}
  out[#out + 1] = { h = ("Felszerelés – becsült DPS %s (buffok nélkül %s)%s"):format(F1(g.baseline), F1(g.unbuffed),
    g.measuredDps and (", mért " .. F1(g.measuredDps)) or "") }
  local sh = g.sheet
  out[#out + 1] = { p = ("AP %d · crit %s · hit %s · főkéz %s · balkéz %s"):format(sh.ap or 0, Pct(sh.crit), Pct(sh.hit),
    sh.mh and ("%d–%d / %.1f"):format(sh.mh[1], sh.mh[2], sh.mh[3]) or "–", sh.oh and ("%d–%d / %.1f"):format(sh.oh[1], sh.oh[2], sh.oh[3]) or "–") }
  if not WowAssistantData then Warn(out, { "Hiányzik a GameData.lua (dungeon loot): node scripts/build-addon-recipes.mjs --install" }) end

  out[#out + 1] = { h = "Buffok és fogyóeszközök a számításban", small = true }
  local checks = {}
  for _, b in ipairs(g.buffs) do
    checks[#checks + 1] = {
      label = b.name .. " |cff888888" .. (b.summary or "") .. "|r", checked = b.selected, disabled = not b.effect,
      onClick = function(on)
        WA.charDB.buffs = WA.charDB.buffs or {}
        WA.charDB.buffs[b.id] = on or nil
        UI.cache = {}
        UI.Draw()
      end,
    }
  end
  out[#out + 1] = { checks = checks, perRow = 3 }

  out[#out + 1] = { h = "Helyenként a legjobb (most felvehető, 3 szinten belül)", small = true }
  local rows = {}
  for _, s in ipairs(g.bySlot) do
    for i, u in ipairs(s.best) do
      rows[#rows + 1] = { cells = { Cell(i == 1 and (WA.Model.SLOT_HU[s.slot] or s.slot) or "", s.slot .. i), i == 1 and (s.current or "–") or "",
        Cell(Item(u.name, u.quality), u.name), Cell(Gain(u.gain), u.gain), Cell(Pct(u.gainPct), u.gainPct),
        u.dungeon .. (u.boss and (" · " .. u.boss) or ""), Cell(u.dropPct and Pct(u.dropPct) or "–", u.dropPct or 0) },
        itemId = u.itemId, tip = u.detail .. (u.warning and ("\n" .. u.warning) or "") }
    end
  end
  out[#out + 1] = { table = { id = "gear.slot", cols = { { "Hely", 80 }, { "Most", 160 }, { "Jobb", 190 }, { "DPS", 50, "RIGHT" },
    { "%", 48, "RIGHT" }, { "Honnan", 250 }, { "Esés", 50, "RIGHT" } }, rows = rows, limit = 80 } }

  out[#out + 1] = { h = "Dungeonok", small = true }
  local drows = {}
  for _, d in ipairs(g.dungeons) do
    local names = {}
    for i = 1, math.min(4, #d.upgrades) do names[i] = Item(d.upgrades[i].name, d.upgrades[i].quality) end
    drows[#drows + 1] = { d.name, d.levels, Cell(Gain(d.gain), d.gain), Cell(d.perRun and Gain(d.perRun) or "–", d.perRun or 0),
      Cell(#d.upgrades, #d.upgrades), table.concat(names, ", ") }
  end
  out[#out + 1] = { table = { id = "gear.dungeons", cols = { { "Dungeon", 170 }, { "Szint", 50 }, { "Összes DPS", 70, "RIGHT" },
    { "Futásonként", 76, "RIGHT" }, { "Tárgy", 40, "RIGHT" }, { "Legjobbak", 440 } }, rows = drows } }

  if #g.later > 0 then
    out[#out + 1] = { h = "Pár szinttel később", small = true }
    local lrows = {}
    for _, u in ipairs(g.later) do
      lrows[#lrows + 1] = { cells = { Cell(u.reqLevel, u.reqLevel), Cell(Item(u.name, u.quality), u.name), WA.Model.SLOT_HU[u.slot] or u.slot,
        Cell(Gain(u.gain), u.gain), u.dungeon .. (u.boss and (" · " .. u.boss) or "") }, itemId = u.itemId, tip = u.detail }
    end
    out[#out + 1] = { table = { id = "gear.later", cols = { { "Szint", 40 }, { "Tárgy", 220 }, { "Hely", 90 }, { "DPS", 50, "RIGHT" },
      { "Honnan", 400 } }, rows = lrows } }
  end
  out[#out + 1] = { h = "A modell", small = true }
  for _, n in ipairs(g.params.notes or {}) do out[#out + 1] = { p = "|cffaaaaaa" .. n .. "|r" } end
  UI.status = ("%d harc kalibrálja a modellt"):format(ctx.combat and ctx.combat.fights or 0)
  return out
end

function UI.pages.prof()
  local out = {}
  out[#out + 1] = { h = "Mesterségek – a legolcsóbb út a célig" }
  out[#out + 1] = { buttons = {
    { label = "Cél: 225", width = 90, disabled = UI.target == 225, onClick = function() UI.target = 225 UI.cache.prof = nil UI.Draw() end },
    { label = "Cél: 300", width = 90, disabled = UI.target == 300, onClick = function() UI.target = 300 UI.cache.prof = nil UI.Draw() end },
  } }
  if not WowAssistantRecipes then
    Warn(out, { "Hiányzik a receptadat (Recipes.lua): node scripts/build-addon-recipes.mjs --install" })
    return out
  end
  local routes = G.Routes(UI.target)
  if #routes == 0 then
    out[#out + 1] = { p = "Nincs gyártó szakmád, vagy a kliens még nem adta meg a szintjét." }
    return out
  end
  local market = WowAssistantDB and WowAssistantDB.market
  out[#out + 1] = { p = ("Árak: teljes AH-szken %s. A szerzett recepteket a szakma ablakának megnyitása frissíti.")
    :format(market and market.at and date("%m.%d %H:%M", market.at) or "|cffff9933nincs (/wa ah az aukciósháznál)|r") }
  for _, r in ipairs(routes) do
    out[#out + 1] = { h = ("%s %d → %d (most max %d)"):format(r.profession, r.skill, r.target, r.cap), small = true }
    out[#out + 1] = { p = ("Alapanyag %s (ebből már nálad: %s) · tanítás %s · vendor visszaad %s%s"):format(Money(r.totalMats), Money(r.ownedValue),
      Money(r.totalTraining), Money(r.totalVendorBack),
      r.unreachableFrom and ("|cffff9933 · %d fölött nincs ismert recept|r"):format(r.unreachableFrom) or "") }
    for _, n in ipairs(r.notes or {}) do out[#out + 1] = { p = "|cffaaaaaa" .. n .. "|r" } end
    local rows = {}
    for _, s in ipairs(r.steps) do
      local reag = {}
      for _, rg in ipairs(s.reagents) do reag[#reag + 1] = rg.qty .. "× " .. rg.name end
      rows[#rows + 1] = { cells = { Cell(s.from .. " → " .. s.to, s.from), s.recipe .. (s.known and "" or " |cffff9933(tanulni)|r"), Cell(s.crafts, s.crafts),
        Cell(Money(s.matsCost), s.matsCost), Cell(s.trainingCost > 0 and Money(s.trainingCost) or "", s.trainingCost),
        Cell(s.vendorBack > 0 and Money(s.vendorBack) or "", s.vendorBack) }, tip = table.concat(reag, ", ") }
    end
    out[#out + 1] = { table = { id = "prof.steps." .. r.professionId, cols = { { "Skill", 70 }, { "Recept", 300 }, { "Db", 40, "RIGHT" },
      { "Alapanyag", 90, "RIGHT" }, { "Tanítás", 90, "RIGHT" }, { "Vendor vissza", 90, "RIGHT" } }, rows = rows } }
    local shop = {}
    for _, x in ipairs(r.shopping) do
      shop[#shop + 1] = { cells = { Cell(x.name, x.name), Cell(x.qty, x.qty), Cell(x.owned > 0 and x.owned or "", x.owned),
        Cell(Money(x.unit), x.unit or 0), Cell(Money(x.total), x.total), x.source == "vendor" and "kereskedő" or (x.source == "AH" and "AH" or "|cffff9933nincs ár|r") },
        itemId = x.itemId }
    end
    out[#out + 1] = { h = "Bevásárlólista", small = true }
    out[#out + 1] = { table = { id = "prof.shop." .. r.professionId, cols = { { "Alapanyag", 220 }, { "Kell", 50, "RIGHT" },
      { "Megvan", 56, "RIGHT" }, { "Egységár", 90, "RIGHT" }, { "Összesen", 90, "RIGHT" }, { "Honnan", 100 } }, rows = shop } }
  end
  UI.status = ("Cél: %d · %d szakma"):format(UI.target, #routes)
  return out
end

---------------------------------------------------------------------------
-- events: keep the open page current
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local pending = false
local function Soon()
  if pending then return end
  pending = true
  C_Timer.After(1, function()
    pending = false
    if frame and frame:IsShown() then UI.Refresh() end
  end)
end
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_LEVEL_UP" or event == "CHARACTER_POINTS_CHANGED" then
    Soon()
  elseif event == "GET_ITEM_INFO_RECEIVED" or event == "BAG_UPDATE_DELAYED" or event == "PLAYER_MONEY" then
    -- names and gear stats arrive late; recompute only when the window is open
    if frame and frame:IsShown() then Soon() end
  end
end)
for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "CHARACTER_POINTS_CHANGED", "GET_ITEM_INFO_RECEIVED",
  "BAG_UPDATE_DELAYED", "PLAYER_MONEY" }) do
  pcall(ev.RegisterEvent, ev, e)
end

WA.Command("plan", function() UI.Show("plan") end, "/wa – főablak · /wa plan | combat | gear | prof – egy oldala")
WA.Command("combat", function() UI.Show("combat") end)
WA.Command("harc", function() UI.Show("combat") end) -- old name
WA.Command("gear", function() UI.Show("gear") end)
WA.Command("prof", function() UI.Show("prof") end)
