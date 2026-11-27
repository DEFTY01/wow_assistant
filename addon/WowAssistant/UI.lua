-- WoW Assistant: the main window (/wa). The web app's pages in game:
--   Haditerv     plan.ts        what to buy, learn, farm and craft with the gold you have
--   Harc         combat.ts      the recorded fights: score, abilities, advice
--   Felszerelés  gear.ts        the next upgrade for every slot, buffs and consumables
--   Mesterségek  planRoutes     the cheapest way to skill each profession
--   Talentek     (WA-034)       the talent trees, a plan and what each talent is worth with your gear
--
-- Layout: a side menu (character, pages, the addon's other windows) and the page on the right.
-- A page shows the few numbers that matter as cards, then sections. Only the important sections
-- are open, tables show their key columns and first rows; the rest is one click away (open a
-- section, "Több oszlop", "Mutasd mind"), and the search box filters every table of the page.
-- Which sections are open and which show more columns is remembered.

local _, WA = ...
local UI = {}
WA.UI = UI
local G = WA.Game

local W, H = 1000, 640
local NAV_W = 190
local ROW_H = 20
local GAP = 8          -- between table columns
local ROWS_SHOWN = 8   -- rows before "Mutasd mind"
local ROWS_MAX = 200
local CONTENT_W = 700  -- set by Build

---------------------------------------------------------------------------
-- formatting
---------------------------------------------------------------------------
local HEX = WA.Style.HEX
local function Color(hex, s) return "|cff" .. hex .. tostring(s) .. "|r" end
local function Muted(s) return Color(HEX.muted, s) end
local function Money(c)
  if not c then return Muted("–") end
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
local function Gain(g) return g and Color(HEX.good, ("+%.1f"):format(g)) or "–" end
local QCOLOR = { POOR = "9d9d9d", COMMON = "ffffff", UNCOMMON = "1eff00", RARE = "0070dd", EPIC = "a335ee", LEGENDARY = "ff8000" }
local QNUM = { [0] = "POOR", "COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY" }
local function Item(name, quality)
  if type(quality) == "number" then quality = QNUM[quality] end
  return "|cff" .. (QCOLOR[quality or "COMMON"] or "ffffff") .. (name or "?") .. "|r"
end
local function Plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
UI.Money, UI.Item = Money, Item

-- cell: plain text, or { text, sort value }
local function Cell(text, value) return { text, value } end

---------------------------------------------------------------------------
-- state
---------------------------------------------------------------------------
local frame
UI.tab = "plan"
UI.filter = ""
UI.sort = {}       -- table id -> { column, direction }
UI.more = {}       -- table id -> true: every row (this session)
UI.target = 300    -- profession route target
UI.cache = {}      -- tab -> blocks (cleared by Refresh)
UI.head = {}       -- tab -> { title, subtitle } (set by the page)

local function State()
  WA.db.ui = WA.db.ui or {}
  local s = WA.db.ui
  s.open, s.detail = s.open or {}, s.detail or {}
  return s
end

local PAGES = {
  { "plan", "Haditerv", "Interface\\Icons\\INV_Misc_Map_01" },
  { "combat", "Harc", "Interface\\Icons\\Ability_Rogue_Eviscerate" },
  { "gear", "Felszerelés", "Interface\\Icons\\INV_Chest_Leather_09" },
  { "pet", "Pet", "Interface\\Icons\\Ability_Hunter_BeastTaming", class = "HUNTER" },
  { "prof", "Mesterségek", "Interface\\Icons\\Trade_Engineering" },
  { "talent", "Talentek", "Interface\\Icons\\Ability_Marksmanship" },
}
local WINDOWS = {
  { "Vendor gyártás", "Interface\\Icons\\INV_Misc_Coin_02", function() if WA.VC then WA.VC.Toggle() end end },
  { "Session sáv", "Interface\\Icons\\INV_Misc_PocketWatch_01", function()
    local hidden = WA.db.session and WA.db.session.hidden
    if WA.Session then WA.Session.Command(hidden and "show" or "hide") end
  end },
  { "Chronicle", "Interface\\Icons\\INV_Misc_Book_09", function() if WA.Chronicle then WA.Chronicle.Command("") end end },
}

---------------------------------------------------------------------------
-- pooled widgets (the page is redrawn from blocks; frames are reused)
---------------------------------------------------------------------------
local pools, used = {}, {}
local function Acquire(kind, make)
  pools[kind] = pools[kind] or {}
  used[kind] = (used[kind] or 0) + 1
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
  local t = Acquire("text", function()
    local fs = parent:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    return fs
  end)
  t:SetFontObject(font or "WowAssistantFontHighlightSmall")
  t:SetWordWrap(true)
  return t
end

local function Height(fs, fallback)
  local h = tonumber(fs:GetStringHeight())
  return (h and h > 0) and h or fallback
end

local function Fill(tex, r, g, b, a) tex:SetColorTexture(r, g, b, a) return tex end

---------------------------------------------------------------------------
-- the window
---------------------------------------------------------------------------
local function NavButton(parent, label, icon, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(NAV_W - 16, 34)
  b.sel = Fill(b:CreateTexture(nil, "BACKGROUND"), 1, 0.82, 0, 0.13)
  b.sel:SetAllPoints()
  b.bar = Fill(b:CreateTexture(nil, "ARTWORK"), 1, 0.82, 0, 0.9)
  b.bar:SetPoint("TOPLEFT")
  b.bar:SetPoint("BOTTOMLEFT")
  b.bar:SetWidth(3)
  local hl = Fill(b:CreateTexture(nil, "HIGHLIGHT"), 1, 0.9, 0.7, 0.07)
  hl:SetAllPoints()
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(24, 24)
  b.icon:SetPoint("LEFT", 10, 0)
  b.icon:SetTexture(icon)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.label = b:CreateFontString(nil, "OVERLAY", "WowAssistantFontNav")
  b.label:SetPoint("LEFT", b.icon, "RIGHT", 10, 0)
  b.label:SetPoint("RIGHT", -6, 0)
  b.label:SetJustifyH("LEFT")
  b.label:SetWordWrap(false)
  b.label:SetText(label)
  b:SetScript("OnClick", onClick)
  function b:SetSelected(on)
    self.sel:SetShown(on)
    self.bar:SetShown(on)
    self.label:SetFontObject(on and "WowAssistantFontHeader" or "WowAssistantFontNav")
  end
  b:SetSelected(false)
  return b
end

local function Build()
  local St = WA.Style
  local f = St.Window("WowAssistantMainFrame", W, H, "Waystone")
  local inset, top = f.inset, f.top

  -- side menu: who, the pages, the other windows
  local nav = CreateFrame("Frame", nil, f, "BackdropTemplate")
  nav:SetPoint("TOPLEFT", inset, -top)
  nav:SetPoint("BOTTOMLEFT", inset, inset)
  nav:SetWidth(NAV_W)
  St.Panel(nav, St.C.panel, St.C.edge, 0.3)
  f.portrait = nav:CreateTexture(nil, "ARTWORK")
  f.portrait:SetSize(46, 46)
  f.portrait:SetPoint("TOPLEFT", 10, -12)
  local ring = nav:CreateTexture(nil, "OVERLAY")
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  ring:SetSize(80, 80)
  ring:SetPoint("TOPLEFT", f.portrait, "TOPLEFT", -6, 5)
  f.name = nav:CreateFontString(nil, "OVERLAY", "WowAssistantFontHeader")
  f.name:SetPoint("TOPLEFT", f.portrait, "TOPRIGHT", 10, -2)
  f.name:SetPoint("RIGHT", -8, 0)
  f.name:SetJustifyH("LEFT")
  f.name:SetWordWrap(false)
  f.level = nav:CreateFontString(nil, "OVERLAY", "WowAssistantFontMuted")
  f.level:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -3)
  f.money = nav:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlightSmall")
  f.money:SetPoint("TOPLEFT", f.level, "BOTTOMLEFT", 0, -3)

  local y = -76
  local rule = Fill(nav:CreateTexture(nil, "ARTWORK"), 1, 0.82, 0, 0.25)
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", 8, y)
  rule:SetPoint("TOPRIGHT", -8, y)
  y = y - 8
  f.nav = {}
  for _, p in ipairs(PAGES) do
    if not p.class or p.class == G.Class() then
      local b = NavButton(nav, p[2], p[3], function() UI.Show(p[1]) end)
      b:SetPoint("TOPLEFT", 8, y)
      f.nav[p[1]] = b
      y = y - 36
    end
  end
  y = y - 10
  local other = nav:CreateFontString(nil, "OVERLAY", "WowAssistantFontDisableSmall")
  other:SetPoint("TOPLEFT", 14, y)
  other:SetText("ABLAKOK")
  y = y - 18
  for _, w in ipairs(WINDOWS) do
    local b = NavButton(nav, w[1], w[2], w[3])
    b:SetHeight(30)
    b.icon:SetSize(20, 20)
    b.label:SetFontObject("WowAssistantFontHighlightSmall")
    b.SetSelected = function() end
    b.sel:Hide() b.bar:Hide()
    b:SetPoint("TOPLEFT", 8, y)
    y = y - 32
  end
  f.note = nav:CreateFontString(nil, "OVERLAY", "WowAssistantFontDisableSmall")
  f.note:SetPoint("BOTTOMLEFT", 12, 10)
  f.note:SetPoint("RIGHT", -10, 0)
  f.note:SetJustifyH("LEFT")
  f.note:SetJustifyV("BOTTOM")

  -- page header: title, one line about the page, search
  local left = inset + NAV_W + 18
  f.pageTitle = f:CreateFontString(nil, "OVERLAY", "WowAssistantFontPage")
  f.pageTitle:SetPoint("TOPLEFT", left, -(top + 4))
  f.pageSub = f:CreateFontString(nil, "OVERLAY", "WowAssistantFontMuted")
  f.pageSub:SetPoint("TOPLEFT", f.pageTitle, "BOTTOMLEFT", 0, -4)
  f.pageSub:SetPoint("RIGHT", f, "RIGHT", -(inset + 260), 0)
  f.pageSub:SetJustifyH("LEFT")
  f.pageSub:SetWordWrap(false)
  local search = St.Search(f, "Keresés", 170, function(text) UI.filter = text UI.Draw() end)
  search:SetPoint("TOPRIGHT", -(inset + 6), -(top + 8))
  f.search = search
  local headRule = Fill(f:CreateTexture(nil, "ARTWORK"), 1, 0.82, 0, 0.3)
  headRule:SetHeight(1)
  headRule:SetPoint("TOPLEFT", left, -(top + 52))
  headRule:SetPoint("TOPRIGHT", -(inset + 4), -(top + 52))

  local scrollTop = top + 62
  CONTENT_W = W - left - inset - 32
  f.scroll, f.child = St.Scroll(f, left, scrollTop, inset + 4, inset + 2, CONTENT_W)
  f:Hide()
  return f
end

---------------------------------------------------------------------------
-- drawing blocks
---------------------------------------------------------------------------
local function Matches(cells, needle)
  if needle == "" then return true end
  for _, c in pairs(cells) do
    local t = type(c) == "table" and c[1] or c
    if WA.Style.Lower(Plain(t)):find(needle, 1, true) then return true end
  end
  return false
end

-- While searching, a section is shown only when something in it matches.
local SectionHits
local function BlockHits(b, needle)
  if b.table then
    for _, r in ipairs(b.table.rows or {}) do if Matches(r.cells or r, needle) then return true end end
  elseif b.p then return Matches({ b.p }, needle)
  elseif b.h then return Matches({ b.h }, needle)
  elseif b.tips then
    for _, a in ipairs(b.tips) do if Matches({ a.title or "", a.text or "" }, needle) then return true end end
  elseif b.checks then
    for _, c in ipairs(b.checks) do if Matches({ c.label or "" }, needle) then return true end end
  elseif b.section then return SectionHits(b.section, needle)
  end
  return false
end
function SectionHits(s, needle)
  if Matches({ s.title or "" }, needle) then return true end
  for _, b in ipairs(s.blocks or {}) do if BlockHits(b, needle) then return true end end
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

-- Which columns show, and how wide: the extra ones only with "Több oszlop"; flex columns share
-- what is left.
local function Layout(cols, w, detail)
  local vis, fixed, flex = {}, 0, 0
  for i, c in ipairs(cols) do
    if detail or not c.extra then
      vis[#vis + 1] = { i = i, c = c }
      if c.flex then flex = flex + 1 else fixed = fixed + c[2] end
    end
  end
  local rest = math.max(80, w - fixed - (#vis - 1) * GAP)
  for _, v in ipairs(vis) do v.w = v.c.flex and math.floor(rest / math.max(1, flex)) or v.c[2] end
  return vis
end

local function HasExtra(cols)
  for _, c in ipairs(cols) do if c.extra then return true end end
  return false
end

local function MoreButton(child)
  return Acquire("more", function()
    local b = CreateFrame("Button", nil, child)
    b:SetHeight(20)
    b.text = b:CreateFontString(nil, "OVERLAY", "WowAssistantFontNormalSmall")
    b.text:SetPoint("LEFT", 4, 0)
    local hl = Fill(b:CreateTexture(nil, "HIGHLIGHT"), 1, 0.9, 0.7, 0.06)
    hl:SetAllPoints()
    return b
  end)
end

local function DrawTable(child, b, x, y, w, detail)
  local needle = WA.Style.Lower(UI.filter)
  local rows = {}
  for _, r in ipairs(b.rows) do if Matches(r.cells or r, needle) then rows[#rows + 1] = r end end
  local s = UI.sort[b.id]
  if s then
    local idx = {}
    for i, r in ipairs(rows) do idx[r] = i end
    table.sort(rows, function(p, q)
      local va, vb = SortValue((p.cells or p)[s[1]]), SortValue((q.cells or q)[s[1]])
      if va == vb then return idx[p] < idx[q] end
      if s[2] > 0 then return Less(va, vb) end
      return Less(vb, va)
    end)
  end
  local vis = Layout(b.cols, w, detail)

  -- header: click to sort
  local cx = x
  for _, v in ipairs(vis) do
    local c, i = v.c, v.i
    local h = Acquire("head", function()
      local btn = CreateFrame("Button", nil, child)
      btn:SetHeight(18)
      btn.text = btn:CreateFontString(nil, "OVERLAY", "WowAssistantFontDisableSmall")
      btn.text:SetAllPoints()
      btn.text:SetWordWrap(false)
      return btn
    end)
    h:SetWidth(v.w)
    h:SetPoint("TOPLEFT", child, "TOPLEFT", cx, -y)
    h.text:SetJustifyH(c[3] or "LEFT")
    h.text:SetText(WA.Style.Upper(c[1]) .. ((s and s[1] == i) and (s[2] > 0 and " ↑" or " ↓") or ""))
    h:SetScript("OnClick", function()
      local cur = UI.sort[b.id]
      if cur and cur[1] == i then cur[2] = -cur[2]
      else UI.sort[b.id] = { i, (c[3] == "RIGHT") and -1 or 1 } end
      UI.Draw()
    end)
    cx = cx + v.w + GAP
  end
  y = y + 18
  local line = Acquire("line", function() return Fill(child:CreateTexture(nil, "ARTWORK"), 1, 0.82, 0, 0.18) end)
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
  line:SetWidth(w)
  y = y + 3

  local limit = UI.more[b.id] and ROWS_MAX or (b.limit or ROWS_SHOWN)
  for n, r in ipairs(rows) do
    if n > limit then break end
    local row = Acquire("row", function()
      local btn = CreateFrame("Button", nil, child)
      btn:SetHeight(ROW_H)
      btn.bg = btn:CreateTexture(nil, "BACKGROUND")
      btn.bg:SetAllPoints()
      local hl = Fill(btn:CreateTexture(nil, "HIGHLIGHT"), 1, 0.9, 0.7, 0.08)
      hl:SetAllPoints()
      btn.cells = {}
      btn:SetScript("OnEnter", function(self)
        if not self.itemId and not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        if self.itemId then pcall(GameTooltip.SetItemByID, GameTooltip, self.itemId) end
        if self.tip and self.tip ~= "" then GameTooltip:AddLine(WA.Fix(self.tip), 1, 0.82, 0.5, true) end
        GameTooltip:Show()
      end)
      btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
      return btn
    end)
    row:SetWidth(w)
    row:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
    if r.selected then Fill(row.bg, 1, 0.82, 0, 0.16) row.bg:Show()
    else Fill(row.bg, 1, 0.9, 0.7, 0.035) row.bg:SetShown(n % 2 == 0) end
    row.itemId, row.tip = r.itemId, r.tip
    row:SetScript("OnClick", r.onClick)
    local cells = r.cells or r
    local px = 0
    for k, v in ipairs(vis) do
      local fs = row.cells[k]
      if not fs then
        fs = row:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlightSmall")
        fs:SetWordWrap(false)
        row.cells[k] = fs
      end
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", row, "LEFT", px + 2, 0)
      fs:SetWidth(v.w - 2)
      fs:SetJustifyH(v.c[3] or "LEFT")
      local val = cells[v.i]
      fs:SetText(type(val) == "table" and val[1] or val or "")
      fs:Show()
      px = px + v.w + GAP
    end
    for k = #vis + 1, #row.cells do row.cells[k]:Hide() end
    y = y + ROW_H
  end
  if #rows == 0 then
    local t = Text(child, "WowAssistantFontMuted")
    t:SetWidth(w)
    t:SetPoint("TOPLEFT", child, "TOPLEFT", x + 2, -(y + 3))
    t:SetText(needle ~= "" and "A keresésnek egy sor sem felel meg." or (b.empty or "Nincs adat."))
    y = y + 22
  elseif #rows > (b.limit or ROWS_SHOWN) then
    local m = MoreButton(child)
    m:SetWidth(w)
    m:SetPoint("TOPLEFT", child, "TOPLEFT", x, -(y + 2))
    if UI.more[b.id] then m.text:SetText("Kevesebb sor")
    else m.text:SetText(("Mutasd mind (még %d)"):format(#rows - limit)) end
    m:SetScript("OnClick", function() UI.more[b.id] = not UI.more[b.id] or nil UI.Draw() end)
    y = y + 24
  end
  return y + 6
end

local function DrawCards(child, b, x, y, w)
  local n = #b.cards
  if n == 0 then return y end
  local cw = math.floor((w - (n - 1) * 10) / n)
  for i, c in ipairs(b.cards) do
    local card = Acquire("card", function()
      local fr = CreateFrame("Frame", nil, child, "BackdropTemplate")
      WA.Style.Panel(fr, WA.Style.C.card, WA.Style.C.edge, 0.4)
      fr:SetHeight(70)
      fr.label = fr:CreateFontString(nil, "OVERLAY", "WowAssistantFontDisableSmall")
      fr.label:SetPoint("TOPLEFT", 10, -8)
      fr.label:SetPoint("RIGHT", -8, 0)
      fr.label:SetJustifyH("LEFT")
      fr.label:SetWordWrap(false)
      fr.value = fr:CreateFontString(nil, "OVERLAY", "WowAssistantFontBig")
      fr.value:SetPoint("TOPLEFT", fr.label, "BOTTOMLEFT", 0, -3)
      fr.value:SetPoint("RIGHT", -8, 0)
      fr.value:SetJustifyH("LEFT")
      fr.value:SetWordWrap(false)
      fr.sub = fr:CreateFontString(nil, "OVERLAY", "WowAssistantFontMuted")
      fr.sub:SetPoint("BOTTOMLEFT", 10, 7)
      fr.sub:SetPoint("RIGHT", -8, 0)
      fr.sub:SetJustifyH("LEFT")
      fr.sub:SetWordWrap(false)
      return fr
    end)
    card:SetWidth(cw)
    card:SetPoint("TOPLEFT", child, "TOPLEFT", x + (i - 1) * (cw + 10), -y)
    card.label:SetText(WA.Style.Upper(c.label))
    card.value:SetText(c.value or "–")
    card.sub:SetText(c.sub or "")
    card.tip = c.tip
    card:SetScript("OnEnter", c.tip and function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:AddLine(WA.Fix(self.tip), 1, 0.82, 0.5, true)
      GameTooltip:Show()
    end or nil)
    card:SetScript("OnLeave", c.tip and function() GameTooltip:Hide() end or nil)
  end
  return y + 70 + 14
end

local TIP_COLOR = { fix = HEX.bad, warn = HEX.warn, tip = HEX.gold, info = HEX.muted, good = HEX.good }
local function DrawTips(child, b, x, y, w)
  local needle = WA.Style.Lower(UI.filter or "")
  for _, a in ipairs(b.tips) do
    if Matches({ a.title or "", a.text or "" }, needle) then
    local mark = Acquire("mark", function() return child:CreateTexture(nil, "ARTWORK") end)
    local c = TIP_COLOR[a.level] or HEX.gold
    mark:SetColorTexture(tonumber(c:sub(1, 2), 16) / 255, tonumber(c:sub(3, 4), 16) / 255, tonumber(c:sub(5, 6), 16) / 255, 0.9)
    mark:SetSize(3, 14)
    mark:SetPoint("TOPLEFT", child, "TOPLEFT", x, -(y + 1))
    local t = Text(child)
    t:SetWidth(w - 12)
    t:SetPoint("TOPLEFT", child, "TOPLEFT", x + 10, -y)
    t:SetText(a.title and (Color(c, a.title) .. (a.text and a.text ~= "" and ("  " .. a.text) or "")) or a.text)
    y = y + Height(t, 14) + 6
    end
  end
  return y + 2
end

local function DrawChecks(child, b, x, y, w)
  local per = b.perRow or 3
  local cw = w / per
  for i, c in ipairs(b.checks) do
    local cb = Acquire("check", function()
      local btn = CreateFrame("CheckButton", nil, child, "UICheckButtonTemplate")
      btn:SetSize(22, 22)
      btn.label = btn:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlightSmall")
      btn.label:SetPoint("LEFT", btn, "RIGHT", 2, 0)
      btn.label:SetJustifyH("LEFT")
      btn.label:SetWordWrap(false)
      return btn
    end)
    local col, line = (i - 1) % per, math.floor((i - 1) / per)
    cb:SetPoint("TOPLEFT", child, "TOPLEFT", x + col * cw, -(y + line * 24))
    cb.label:SetWidth(cw - 28)
    cb.label:SetText(c.label)
    cb:SetChecked(c.checked and true or false)
    cb:SetEnabled(not c.disabled)
    cb:SetScript("OnClick", function(self) c.onClick(self:GetChecked() and true or false) end)
  end
  return y + math.ceil(#b.checks / per) * 24 + 6
end

local function DrawButtons(child, b, x, y)
  for _, c in ipairs(b.buttons) do
    local btn = Acquire("button", function() return WA.Style.Button(child, "", 120) end)
    btn:SetSize(c.width or 120, 22)
    btn:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
    btn:SetText(c.label)
    btn:SetEnabled(true)
    if c.active then btn:LockHighlight() else btn:UnlockHighlight() end
    btn:SetScript("OnClick", c.onClick)
    x = x + (c.width or 120) + 6
  end
  return y + 30
end

-- A text box with a button after it (b.edit = { text, button, onEnter(text), width }): the text is
-- selected when the box gets the focus, so it can be copied; Enter or the button hands it back.
local function DrawEdit(child, b, x, y, w)
  local e = Acquire("edit", function()
    local box = CreateFrame("EditBox", nil, child, "InputBoxTemplate")
    box:SetHeight(20)
    box:SetAutoFocus(false)
    box:SetFontObject("WowAssistantFontHighlightSmall")
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    return box
  end)
  local bw = b.button and 110 or 0
  e:SetWidth(b.width or (w - bw - 24))
  e:SetPoint("TOPLEFT", child, "TOPLEFT", x + 6, -y)
  -- a redraw while you type or paste keeps your text
  if not (e.HasFocus and e:HasFocus() == true) then e:SetText(b.text or "") end
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() if b.onEnter then b.onEnter(self:GetText() or "") end end)
  if b.button then
    local btn = Acquire("button", function() return WA.Style.Button(child, "", 120) end)
    btn:SetSize(bw, 22)
    btn:SetPoint("LEFT", e, "RIGHT", 10, 0)
    btn:SetText(b.button)
    btn:SetEnabled(true)
    btn:UnlockHighlight()
    btn:SetScript("OnClick", function() if b.onEnter then b.onEnter(e:GetText() or "") end end)
  end
  return y + 30
end

-- The talent trees (WA-034): three panels side by side, each talent an icon at its row and column
-- with its rank, the prerequisite lines, the open talents lit, the best next point marked.
--   b.talents = { tabs (T.PlanTrees), ranks (the plan), cur (now), open(name) -> bool,
--                 best = name, tip(x, tooltip), onClick(x, button) }
local TICON, TCX, TCY, THEAD = 34, 54, 46, 28
local function DrawTalents(child, b, x, y, w)
  local tb = b.talents
  local n = #tb.tabs
  if n == 0 then return y end
  local gap = 12
  local tw = math.floor((w - (n - 1) * gap) / n)
  local tiers = 1
  for _, tab in ipairs(tb.tabs) do for _, t in ipairs(tab.talents) do if t.tier > tiers then tiers = t.tier end end end
  local th = THEAD + tiers * TCY + 8
  local needle = WA.Style.Lower(UI.filter or "")
  local lvl = (child.GetFrameLevel and child:GetFrameLevel() or 1)
  for i, tab in ipairs(tb.tabs) do
    local px = x + (i - 1) * (tw + gap)
    local panel = Acquire("talentTree", function()
      local fr = CreateFrame("Frame", nil, child, "BackdropTemplate")
      WA.Style.Panel(fr, WA.Style.C.card, WA.Style.C.edge, 0.4)
      fr.icon = fr:CreateTexture(nil, "ARTWORK")
      fr.icon:SetSize(18, 18)
      fr.icon:SetPoint("TOPLEFT", 8, -6)
      fr.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      fr.title = fr:CreateFontString(nil, "OVERLAY", "WowAssistantFontHeader")
      fr.title:SetPoint("LEFT", fr.icon, "RIGHT", 6, 0)
      fr.title:SetJustifyH("LEFT")
      fr.title:SetWordWrap(false)
      fr.points = fr:CreateFontString(nil, "OVERLAY", "WowAssistantFontMuted")
      fr.points:SetPoint("TOPRIGHT", -8, -9)
      fr.lines = {}
      return fr
    end)
    panel:SetFrameLevel(lvl + 1)
    panel:SetSize(tw, th)
    panel:SetPoint("TOPLEFT", child, "TOPLEFT", px, -y)
    panel.icon:SetTexture(tab.icon or (tab.talents[1] and tab.talents[1].icon))
    panel.title:SetText(tab.name or "")
    local pts, ptsNow = WA.Talent.TabPoints(tab, tb.ranks), WA.Talent.TabPoints(tab, tb.cur)
    panel.points:SetText(pts ~= ptsNow and ("%d pont (most %d)"):format(pts, ptsNow) or ("%d pont"):format(pts))
    -- where a talent sits inside the panel
    local left = math.floor((tw - 4 * TCX) / 2) + math.floor((TCX - TICON) / 2)
    local function At(t) return left + (t.col - 1) * TCX, THEAD + (t.tier - 1) * TCY end
    -- prerequisite lines: from the required talent across to the column, then down to the talent
    local nl = 0
    local function Line(lx, ly, lw, lh, on)
      nl = nl + 1
      local l = panel.lines[nl]
      if not l then l = panel:CreateTexture(nil, "ARTWORK") panel.lines[nl] = l end
      l:ClearAllPoints()
      l:SetPoint("TOPLEFT", panel, "TOPLEFT", lx, -ly)
      l:SetSize(math.max(1, lw), math.max(1, lh))
      if on then l:SetColorTexture(1, 0.82, 0, 0.85) else l:SetColorTexture(0.45, 0.42, 0.36, 0.7) end
      l:Show()
    end
    local byName = {}
    for _, t in ipairs(tab.talents) do byName[t.name] = t end
    for _, t in ipairs(tab.talents) do
      local r = t.req and byName[t.req]
      if r then
        local on = (tb.ranks[r.name] or 0) >= (t.reqRank or 1)
        local rx, ry = At(r)
        local ax, ay = At(t)
        local mid = math.floor(TICON / 2) - 1
        if r.tier == t.tier then
          local a, z = math.min(rx, ax) + TICON, math.max(rx, ax)
          Line(a, ry + mid, z - a, 3, on)
        else
          if r.col ~= t.col then
            local a, z = math.min(rx, ax) + mid, math.max(rx, ax) + mid
            if rx < ax then a = rx + TICON end
            if rx > ax then z = rx end
            Line(a, ry + mid, z - a + 3, 3, on)
            Line(ax + mid, ry + mid, 3, ay - ry - mid, on)
          else
            Line(ax + mid, ry + TICON, 3, ay - ry - TICON, on)
          end
          Line(ax + mid - 2, ay - 5, 7, 4, on) -- the arrowhead
        end
      end
    end
    for k = nl + 1, #panel.lines do panel.lines[k]:Hide() end
    -- the talents
    for _, t in ipairs(tab.talents) do
      local btn = Acquire("talentBtn", function()
        local bt = CreateFrame("Button", nil, child)
        bt:SetSize(TICON, TICON)
        if bt.RegisterForClicks then bt:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
        bt.edge = bt:CreateTexture(nil, "BACKGROUND")
        bt.edge:SetPoint("TOPLEFT", -2, 2)
        bt.edge:SetPoint("BOTTOMRIGHT", 2, -2)
        bt.icon = bt:CreateTexture(nil, "ARTWORK")
        bt.icon:SetAllPoints()
        bt.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        bt.glow = bt:CreateTexture(nil, "OVERLAY")
        bt.glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        bt.glow:SetBlendMode("ADD")
        bt.glow:SetPoint("TOPLEFT", -6, 6)
        bt.glow:SetPoint("BOTTOMRIGHT", 6, -6)
        bt.rankBg = Fill(bt:CreateTexture(nil, "OVERLAY"), 0, 0, 0, 0.85)
        bt.rankBg:SetSize(26, 13)
        bt.rankBg:SetPoint("BOTTOMRIGHT", 6, -5)
        bt.rank = bt:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlightSmall")
        bt.rank:SetPoint("CENTER", bt.rankBg, "CENTER", 0, 0)
        local hl = Fill(bt:CreateTexture(nil, "HIGHLIGHT"), 1, 1, 1, 0.15)
        hl:SetAllPoints()
        bt:SetScript("OnEnter", function(self)
          if not self.talent or not self.tipFn then return end
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          self.tipFn(self.talent, GameTooltip)
          GameTooltip:Show()
        end)
        bt:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bt:SetScript("OnClick", function(self, button) if self.clickFn then self.clickFn(self.talent, button) end end)
        return bt
      end)
      btn:SetFrameLevel(lvl + 3)
      local ix, iy = At(t)
      btn:SetPoint("TOPLEFT", child, "TOPLEFT", px + ix, -(y + iy))
      local r, now = tb.ranks[t.name] or 0, tb.cur[t.name] or 0
      local open = tb.open(t.name)
      btn.talent, btn.tipFn, btn.clickFn = t, tb.tip, tb.onClick
      btn.icon:SetTexture(t.icon)
      btn.icon:SetDesaturated(r == 0 and not open)
      -- the edge: gold full, green with points or open, grey locked
      if r >= t.max then Fill(btn.edge, 1, 0.82, 0, 1)
      elseif r > 0 or open then Fill(btn.edge, 0.25, 0.85, 0.25, 1)
      else Fill(btn.edge, 0.3, 0.28, 0.24, 1) end
      local rc = r >= t.max and HEX.gold or ((r > 0 or open) and HEX.good or HEX.muted)
      if r ~= now then rc = "66ccff" end -- the plan differs from now here
      btn.rank:SetText(Color(rc, ("%d/%d"):format(r, t.max)))
      btn.glow:SetShown(tb.best == t.name)
      local hit = needle == "" or WA.Style.Lower(t.name):find(needle, 1, true)
      if needle ~= "" and hit then UI.hits = (UI.hits or 0) + 1 end
      btn:SetAlpha(hit and 1 or 0.25)
    end
  end
  return y + th + 12
end

local DrawBlocks

-- A section: a header bar (click: open/close; "Több oszlop" when its table has extra columns)
-- and its blocks under it.
local function DrawSection(child, s, x, y, w)
  local st = State()
  local open = st.open[s.id]
  if open == nil then open = s.open and true or false end
  if UI.filter ~= "" then
    if not SectionHits(s, WA.Style.Lower(UI.filter)) then return y end
    open = true
    UI.hits = (UI.hits or 0) + 1
  end
  local detail = st.detail[s.id] and true or false
  local hasExtra = false
  for _, b in ipairs(s.blocks or {}) do if b.table and HasExtra(b.table.cols) then hasExtra = true end end

  local h = Acquire("section", function()
    local btn = CreateFrame("Button", nil, child)
    btn:SetHeight(28)
    btn.bg = Fill(btn:CreateTexture(nil, "BACKGROUND"), 0.14, 0.115, 0.08, 0.9)
    btn.bg:SetAllPoints()
    local hl = Fill(btn:CreateTexture(nil, "HIGHLIGHT"), 1, 0.9, 0.7, 0.06)
    hl:SetAllPoints()
    btn.edge = Fill(btn:CreateTexture(nil, "ARTWORK"), 1, 0.82, 0, 0.35)
    btn.edge:SetPoint("BOTTOMLEFT")
    btn.edge:SetPoint("BOTTOMRIGHT")
    btn.edge:SetHeight(1)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetSize(14, 14)
    btn.icon:SetPoint("LEFT", 8, 0)
    btn.title = btn:CreateFontString(nil, "OVERLAY", "WowAssistantFontHeader")
    btn.title:SetPoint("LEFT", btn.icon, "RIGHT", 8, 0)
    btn.title:SetJustifyH("LEFT")
    btn.title:SetWordWrap(false)
    btn.count = btn:CreateFontString(nil, "OVERLAY", "WowAssistantFontMuted")
    btn.count:SetPoint("LEFT", btn.title, "RIGHT", 8, 0)
    btn.detail = CreateFrame("Button", nil, btn)
    btn.detail:SetSize(110, 22)
    btn.detail:SetPoint("RIGHT", -6, 0)
    btn.detail.text = btn.detail:CreateFontString(nil, "OVERLAY", "WowAssistantFontNormalSmall")
    btn.detail.text:SetPoint("RIGHT", -2, 0)
    local dhl = Fill(btn.detail:CreateTexture(nil, "HIGHLIGHT"), 1, 0.9, 0.7, 0.08)
    dhl:SetAllPoints()
    return btn
  end)
  h:SetWidth(w)
  h:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
  h.icon:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
  h.title:SetText(s.title)
  h.count:SetText(s.count and s.count > 0 and ("(" .. s.count .. ")") or "")
  h:SetScript("OnClick", function()
    st.open[s.id] = not open
    UI.Draw()
  end)
  h.detail:SetShown(open and hasExtra)
  h.detail.text:SetText(detail and "Kevesebb oszlop" or "Több oszlop")
  h.detail:SetScript("OnClick", function()
    st.detail[s.id] = not detail or nil
    UI.Draw()
  end)
  y = y + 28 + 8
  if open then
    y = DrawBlocks(child, s.blocks or {}, x + 6, y, w - 6, detail)
    y = y + 6
  end
  return y + 4
end

function DrawBlocks(child, blocks, x, y, w, detail)
  for _, b in ipairs(blocks) do
    if b.cards then
      y = DrawCards(child, b, x, y, w)
    elseif b.section then
      y = DrawSection(child, b.section, x, y, w)
    elseif b.h then
      local t = Text(child, "WowAssistantFontNormal")
      t:SetWidth(w)
      t:SetPoint("TOPLEFT", child, "TOPLEFT", x, -(y + 2))
      t:SetText(b.h)
      y = y + 22
    elseif b.p then
      local t = Text(child, b.muted and "WowAssistantFontMuted" or "WowAssistantFontHighlightSmall")
      t:SetWidth(w)
      t:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
      t:SetText(b.p)
      y = y + Height(t, 14) + 8
    elseif b.tips then
      y = DrawTips(child, b, x, y, w)
    elseif b.table then
      y = DrawTable(child, b.table, x, y, w, detail)
    elseif b.checks then
      y = DrawChecks(child, b, x, y, w)
    elseif b.buttons then
      y = DrawButtons(child, b, x, y)
    elseif b.edit then
      y = DrawEdit(child, b.edit, x, y, w)
    elseif b.talents then
      y = DrawTalents(child, b, x, y, w)
    elseif b.empty then
      local t = Text(child, "WowAssistantFontHeader")
      t:SetWidth(w)
      t:SetPoint("TOPLEFT", child, "TOPLEFT", x, -(y + 30))
      t:SetJustifyH("CENTER")
      t:SetText(b.empty[1])
      local t2 = Text(child, "WowAssistantFontMuted")
      t2:SetWidth(w - 120)
      t2:SetPoint("TOPLEFT", child, "TOPLEFT", x + 60, -(y + 56))
      t2:SetJustifyH("CENTER")
      t2:SetText(b.empty[2] or "")
      y = y + 56 + Height(t2, 14) + 20
    end
  end
  return y
end

function UI.Draw()
  if not frame or not frame:IsShown() then return end
  for k in pairs(used) do used[k] = 0 end
  local blocks = UI.cache[UI.tab]
  if not blocks then
    local ok, res = pcall(UI.pages[UI.tab])
    blocks = ok and res or { { empty = { "Hiba", Color(HEX.bad, tostring(res)) } } }
    UI.cache[UI.tab] = blocks
  end
  local child = frame.child
  UI.hits = 0
  local y = DrawBlocks(child, blocks, 0, 4, CONTENT_W, false)
  if UI.filter ~= "" and UI.hits == 0 then
    y = DrawBlocks(child, { { empty = { "Nincs találat", ("Ezen az oldalon semmi sem tartalmazza ezt: „%s”."):format(UI.filter) } } }, 0, y, CONTENT_W, false)
  end
  for kind, list in pairs(pools) do
    for i = (used[kind] or 0) + 1, #list do list[i]:Hide() end
  end
  child.h = y + 10
  child:SetHeight(math.max(10, y + 10))

  for id, b in pairs(frame.nav) do b:SetSelected(id == UI.tab) end
  local head = UI.head[UI.tab] or {}
  frame.pageTitle:SetText(head[1] or "")
  frame.pageSub:SetText(head[2] or "")
  pcall(SetPortraitTexture, frame.portrait, "player")
  frame.name:SetText(UnitName("player") or "")
  local class = UnitClass and UnitClass("player")
  frame.level:SetText(("%d. szint%s"):format(UnitLevel("player") or 0, class and (" · " .. class) or ""))
  frame.money:SetText(Money(GetMoney()))
  frame.note:SetText(UI.status or "")
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

-- A fight was just recorded: show it (the newest one is selected again).
function WA.OnFight()
  UI.cache.combat, UI.cache.plan, UI.cache.gear = nil, nil, nil
  UI.selFight = nil
  if frame and frame:IsShown() and (UI.tab == "combat") then UI.Draw() end
end

---------------------------------------------------------------------------
-- pages
---------------------------------------------------------------------------
UI.pages = {}
local function Section(id, title, blocks, open, count)
  return { section = { id = id, title = title, blocks = blocks, open = open, count = count } }
end
local function Warnings(list)
  local tips = {}
  for _, w in ipairs(list or {}) do tips[#tips + 1] = { level = "warn", text = w } end
  return #tips > 0 and { tips = tips } or nil
end
local function Add(out, b) if b then out[#out + 1] = b end end

local function NotSupported(tab, title)
  UI.head[tab] = { title, "A sebzésmodell még nem ismeri ezt a kasztot" }
  return { { empty = { "Egyelőre rogue, hunter, shaman, druid, warlock, mage, warrior, priest és paladin", "A sebzésmodell (és vele a Haditerv és a Felszerelés) egyelőre a rogue-ot, a huntert, a shamant, a druidot, a warlockot, a mage-et, a warriort, a priestet és a paladint ismeri; " ..
    "a többi kaszt sorban jön. A Mesterségek és a Vendor gyártás minden karakteren működik." } } }
end

local SOURCE_HU = { ah = "AH", craft = "gyártás", trainer = "trainer", owned = "megvan", quest = "quest" }

local function OptionRows(list, withCost)
  local rows = {}
  for _, o in ipairs(list) do
    local cells = {
      Cell(o.itemId and Item(o.title, o.quality) or o.title, o.title), Cell(Gain(o.gain), o.gain),
      withCost and Cell(Money(o.cost), o.cost) or "",
      (o.where or "") .. (o.req and Color(HEX.warn, (" (" .. o.req .. ". szinttől)")) or ""),
      SOURCE_HU[o.source] or o.source, Cell(Pct(o.gainPct), o.gainPct),
    }
    rows[#rows + 1] = { cells = cells, itemId = o.itemId,
      tip = (o.detail or "") .. (o.warning and ("\n" .. o.warning) or "") .. (o.estimated and "\n(becsült érték)" or "") }
  end
  return rows
end
local function OptionCols(withCost)
  return { { "Mit", 0, flex = true }, { "DPS", 56, "RIGHT" }, { "Ár", 92, "RIGHT", extra = not withCost },
    { "Hol", 220 }, { "Honnan", 70, extra = true }, { "%", 52, "RIGHT", extra = true } }
end

function UI.pages.plan()
  if not G.Supported() then return NotSupported("plan", "Haditerv") end
  local ctx = G.Context()
  local p = WA.Plan.Build(G.PlanInput(ctx))
  UI.head.plan = { "Haditerv", "Mit vegyél, tanulj és hol farmolj abból, amid most van" }
  local out = {}
  out[#out + 1] = { cards = {
    { label = "Becsült DPS most", value = F1(p.baseline), sub = "buffok nélkül " .. F1(p.unbuffed) .. (p.measuredDps and (" · mért " .. F1(p.measuredDps)) or "") },
    { label = "A terv után", value = Color(HEX.good, F1(p.projected)), sub = (p.projected and p.baseline) and (Gain(p.projected - p.baseline) .. " DPS") or "" },
    { label = "Elköltendő", value = Money(p.spent), sub = "ennyiből jön ki a terv" },
    { label = "Marad", value = Money(p.left), sub = "az aranyadból: " .. Money(p.gold) },
  } }
  Add(out, Warnings(p.warnings))
  out[#out + 1] = Section("plan.buy", "Vedd meg most", { { table = { id = "plan.buy", cols = OptionCols(true), rows = OptionRows(p.buy, true),
    empty = "Ebből az aranyból most nincs érdemi fejlesztés." } } }, true, #p.buy)
  if #p.free > 0 then
    out[#out + 1] = Section("plan.free", "Ingyen: nálad van vagy le tudod gyártani",
      { { table = { id = "plan.free", cols = OptionCols(false), rows = OptionRows(p.free, false) } } }, true, #p.free)
  end
  if #p.skills > 0 then
    local TIER = { dps = Color(HEX.good, "DPS"), core = Color(HEX.gold, "alap"), situational = "helyzeti", skip = Muted("kihagyható") }
    local TIER_N = { dps = 0, core = 1, situational = 2, skip = 3 }
    local rows = {}
    for _, s in ipairs(p.skills) do
      rows[#rows + 1] = { cells = { Cell(s.name, s.name), Cell(TIER[s.tier] or s.tier, TIER_N[s.tier]), Cell(Money(s.cost), s.cost),
        Cell(s.gain > 0 and Gain(s.gain) or "", s.gain), s.why }, tip = s.why }
    end
    out[#out + 1] = Section("plan.skills", "Tanuld meg a trainernél", { { table = { id = "plan.skills",
      cols = { { "Képesség", 0, flex = true }, { "Fontos", 80 }, { "Ár", 92, "RIGHT" }, { "DPS", 56, "RIGHT" }, { "Miért", 330, extra = true } },
      rows = rows } } }, true, #p.skills)
  end
  if #p.combat > 0 then
    local tips = {}
    for _, a in ipairs(p.combat) do tips[#tips + 1] = { level = "tip", title = a.title, text = a.text } end
    out[#out + 1] = Section("plan.combat", "Tanácsok a harcaid alapján", { { tips = tips } }, true, #tips)
  end
  if p.ammo and #p.ammo > 0 then
    local rows = {}
    for _, a in ipairs(p.ammo) do
      local src = a.priceSource == "vendor" and "kereskedőnél láttad" or (a.priceSource == "becslés" and "becslés az eladási árból" or a.priceSource)
      rows[#rows + 1] = { cells = { Cell(Item(a.name, "COMMON") .. (a.current and Muted(" (most ez van nálad)") or ""), a.name),
        Cell(F1(a.dps), a.dps), Cell(a.current and "–" or Gain(a.gain), a.gain),
        Cell(a.price and Money(a.price * 200) or Muted("?"), a.price or math.huge),
        Cell(a.perHour and Money(a.perHour) or Muted("?"), a.perHour or math.huge), Cell(a.reqLevel, a.reqLevel) }, itemId = a.itemId,
        tip = "Lőszer: a kereskedőnél (General Goods, Bowyer, Gunsmith) kapod. Minden Auto Shot és lövés hozzáadja a sebzését." ..
          (a.price and ("\nÁr: " .. Plain(Money(a.price)) .. "/db (" .. (src or "?") .. ")") or "\nÁr: nyisd meg egy lőszert árusító kereskedő ablakát.") ..
          (a.perHour and ("\nÓránként: " .. math.floor(p.shotsPerHour + 0.5) .. " lövés folyamatos harcban.") or "") }
    end
    out[#out + 1] = Section("plan.ammo", "Lőszer", { { p = ("Folyamatos harcban kb. %d lövés óránként (%s percenként); az ár 200 darabra szól.")
      :format(math.floor((p.shotsPerHour or 0) + 0.5), F1((p.shotsPerHour or 0) / 60)), muted = true },
      { table = { id = "plan.ammo", cols = { { "Lőszer", 0, flex = true },
      { "DPS-e", 60, "RIGHT" }, { "Neked", 60, "RIGHT" }, { "200 db", 80, "RIGHT" }, { "Óránként", 80, "RIGHT" }, { "Szint", 50, "RIGHT", extra = true } },
      rows = rows } } }, true, #p.ammo)
  end
  if #p.farm > 0 then
    local rows = {}
    for _, d in ipairs(p.farm) do
      local names = {}
      for i = 1, math.min(3, #d.upgrades) do names[i] = Item(d.upgrades[i].name, d.upgrades[i].quality) end
      rows[#rows + 1] = { d.name, d.levels, Cell(Gain(d.gain), d.gain), Cell(d.perRun and Gain(d.perRun) or "–", d.perRun or 0),
        table.concat(names, ", ") }
    end
    out[#out + 1] = Section("plan.farm", "Hova menj farmolni", { { table = { id = "plan.farm", cols = { { "Dungeon", 0, flex = true },
      { "Szint", 60 }, { "Összes DPS", 80, "RIGHT" }, { "Futásonként", 84, "RIGHT" }, { "Legjobb tárgyak", 0, flex = true, extra = true } },
      rows = rows } } }, false, #p.farm)
  end
  if #p.wishlist > 0 then
    out[#out + 1] = Section("plan.wish", "Ha több aranyad lenne",
      { { table = { id = "plan.wish", cols = OptionCols(true), rows = OptionRows(p.wishlist, true) } } }, false, #p.wishlist)
  end
  if #p.quests > 0 then
    out[#out + 1] = Section("plan.quest", "Quest-jutalmak",
      { { table = { id = "plan.quest", cols = OptionCols(false), rows = OptionRows(p.quests, false) } } }, false, #p.quests)
  end
  if #p.professions > 0 then
    local rows = {}
    for _, r in ipairs(p.professions) do
      rows[#rows + 1] = { r.name, Cell(r.skill .. " / " .. r.cap, r.skill), r.next or "–", Cell(Money(r.cost), r.cost), r.note or "" }
    end
    out[#out + 1] = Section("plan.prof", "Mesterségek", { { table = { id = "plan.prof", cols = { { "Szakma", 120 }, { "Skill", 70 },
      { "Következő lépés", 0, flex = true }, { "Ára", 92, "RIGHT" }, { "Megjegyzés", 0, flex = true, extra = true } }, rows = rows } } }, false, #p.professions)
  end
  if #p.consumables > 0 then
    local rows = {}
    for _, c in ipairs(p.consumables) do
      rows[#rows + 1] = { cells = { c.name, Cell(Gain(c.gain), c.gain), Cell(Money(c.perHour), c.perHour or math.huge), c.summary,
        Cell(Money(c.price), c.price or math.huge) }, itemId = c.itemId, tip = c.summary }
    end
    out[#out + 1] = Section("plan.cons", "Fogyóeszközök", { { table = { id = "plan.cons", cols = { { "Mi", 0, flex = true },
      { "DPS", 56, "RIGHT" }, { "Óránként", 92, "RIGHT" }, { "Hatás", 260, extra = true }, { "Darabja", 92, "RIGHT", extra = true } },
      rows = rows } } }, false, #p.consumables)
  end
  if #p.roadmap > 0 then
    local rows = {}
    for _, r in ipairs(p.roadmap) do
      local gear = {}
      for _, g in ipairs(r.gear) do gear[#gear + 1] = Item(g.title, g.quality) .. " " .. Gain(g.gain) end
      rows[#rows + 1] = { Cell(r.level, r.level), table.concat(r.skills, ", "), Cell(Money(r.skillCost), r.skillCost), table.concat(gear, ", ") }
    end
    out[#out + 1] = Section("plan.road", "A következő szintek", { { table = { id = "plan.road", cols = { { "Szint", 50 },
      { "Új képességek", 0, flex = true }, { "Ára", 92, "RIGHT" }, { "Felszerelés", 0, flex = true, extra = true } }, rows = rows } } }, false, #p.roadmap)
  end
  UI.status = ("%d AH-ajánlat · %d harc a modellben"):format(#(G.Offers()), ctx.combat and ctx.combat.fights or 0)
  return out
end

local GRADE_COLOR = { S = "ff8000", A = "a335ee", B = "0070dd", C = "1eff00", D = "9d9d9d" }
local function Grade(sc)
  if not sc then return "–" end
  return ("|cff%s%d (%s)|r"):format(GRADE_COLOR[sc.grade] or "ffffff", sc.total, sc.grade)
end
local function TargetName(x)
  return (x.target and x.target ~= "?" and x.target ~= "") and x.target or Muted("ismeretlen célpont")
end
local SOURCE_NAME = { log = "harcnapló", live = "játékban", meter = "damage meter" }
local function Clock(ds) -- deciseconds -> m:ss.d
  local s = (ds or 0) / 10
  return ("%d:%04.1f"):format(math.floor(s / 60), s % 60)
end

local function AbilityRows(list, damage)
  local rows = {}
  for _, a in ipairs(list) do
    local n = tonumber(a.n) or 0
    local landed = (a.hit or 0) + (a.crit or 0) + (a.glance or 0)
    local function R(x) return n > 0 and (x or 0) / n * 100 or nil end
    local avoided = n > 0 and R((a.miss or 0) + (a.dodge or 0) + (a.parry or 0)) or nil
    rows[#rows + 1] = { a.name, Cell(Pct(damage > 0 and a.dmg / damage * 100 or 0), a.dmg), Cell(a.dmg, a.dmg), Cell(n, n),
      Cell(landed > 0 and Pct(a.crit / landed * 100) or "–", landed > 0 and a.crit / landed or -1),
      Cell(avoided and Pct(avoided) or "–", avoided or -1),
      Cell(landed > 0 and math.floor(a.dmg / landed + 0.5) or "–", landed > 0 and a.dmg / landed or 0), Cell(a.max or 0, a.max or 0),
      Cell(n > 0 and Pct(R(a.miss)) or "–", R(a.miss) or -1), Cell(n > 0 and Pct(R(a.dodge)) or "–", R(a.dodge) or -1),
      Cell(n > 0 and Pct(R(a.parry)) or "–", R(a.parry) or -1), Cell(n > 0 and Pct(R(a.glance)) or "–", R(a.glance) or -1) }
  end
  return rows
end
local ABILITY_COLS = { { "Képesség", 0, flex = true }, { "Arány", 60, "RIGHT" }, { "Sebzés", 70, "RIGHT" },
  { "Db", 44, "RIGHT" }, { "Crit", 56, "RIGHT" }, { "Elkerülve", 70, "RIGHT" },
  { "Átlag", 54, "RIGHT", extra = true }, { "Max", 54, "RIGHT", extra = true }, { "Miss", 52, "RIGHT", extra = true },
  { "Dodge", 54, "RIGHT", extra = true }, { "Parry", 52, "RIGHT", extra = true }, { "Glancing", 64, "RIGHT", extra = true } }

-- Hunters: the raid-log style summary of every fight (damage sources, Auto Shot activity,
-- casts per minute and damage per cast, sting and aspect uptime).
local KIND_HU = { ranged = "távolsági", melee = "közelharc", pet = "pet", dot = "DoT", other = "egyéb" }
local function HunterSummary(r, ctx)
  local s = WA.Hunter.Summary(r, ctx)
  local function Bar(pct) return ("%s %s"):format(Pct(pct), Muted(("|"):rep(math.floor(pct / 4 + 0.5)))) end
  local blocks = {
    { cards = {
      { label = "Átlag DPS", value = F1(s.dps), sub = ("%d harc, %d perc"):format(r.fights, math.floor(s.seconds / 60 + 0.5)) },
      { label = "Auto Shot", value = s.autoUptime and Pct(s.autoUptime * 100) or "–", sub = "a lehetséges lövésekből",
        tip = "Hány lövést adtál le ahhoz képest, amennyit a fegyvered (a tegezzel) ennyi idő alatt lőhetett volna." },
      { label = "Serpent Sting", value = Pct(s.stingUptime), sub = "uptime a harcidőben" },
      { label = "Aspect of the Hawk", value = s.hawk and Pct(s.hawk) or "–", sub = "uptime" },
    } },
  }
  local srcRows = {}
  for _, k in ipairs({ "ranged", "pet", "melee", "dot", "other" }) do
    if (s.sources[k] or 0) > 0 then
      srcRows[#srcRows + 1] = { KIND_HU[k], Cell(Bar(s.shares[k]), s.shares[k]), Cell(s.sources[k], s.sources[k]),
        Cell(F1(s.sources[k] / s.seconds), s.sources[k] / s.seconds) }
    end
  end
  blocks[#blocks + 1] = { h = "Honnan jön a sebzés" }
  blocks[#blocks + 1] = { table = { id = "combat.hsrc", cols = { { "Forrás", 110 }, { "Arány", 0, flex = true }, { "Sebzés", 80, "RIGHT" },
    { "DPS", 64, "RIGHT" } }, rows = srcRows } }
  local rows = {}
  for _, a in ipairs(s.rows) do
    rows[#rows + 1] = { a.name, KIND_HU[a.kind] or a.kind, Cell(Pct(a.share), a.share), Cell(a.n, a.n), Cell(F1(a.cpm), a.cpm),
      Cell(math.floor(a.perCast + 0.5), a.perCast), Cell(math.floor(a.avg + 0.5), a.avg) }
  end
  blocks[#blocks + 1] = { h = "Képességek: használat percenként és sebzés használatonként" }
  blocks[#blocks + 1] = { table = { id = "combat.hcpm", cols = { { "Képesség", 0, flex = true }, { "Fajta", 80 }, { "Arány", 60, "RIGHT" },
    { "Db", 50, "RIGHT" }, { "Percenként", 76, "RIGHT" }, { "Használatonként", 104, "RIGHT" }, { "Átlag találat", 90, "RIGHT", extra = true } }, rows = rows } }
  if s.autoMiss then
    blocks[#blocks + 1] = { p = ("Auto Shot: %s miss/dodge, %s crit."):format(Pct(s.autoMiss), Pct(s.autoCrit)), muted = true }
  end
  return Section("combat.hunter", "Hunter összesítő (minden harc)", blocks, true, r.fights)
end

-- Shamans: the same summary (melee, imbue, spells, totems, DoT; swing activity, shocks).
local KIND_SH = { melee = "közelharc", imbue = "imbue", spell = "varázslat", totem = "totem", dot = "DoT", other = "egyéb" }
local function ShamanSummary(r, ctx)
  local s = WA.Shaman.Summary(r, ctx)
  local function Bar(pct) return ("%s %s"):format(Pct(pct), Muted(("|"):rep(math.floor(pct / 4 + 0.5)))) end
  local blocks = {
    { cards = {
      { label = "Átlag DPS", value = F1(s.dps), sub = ("%d harc, %d perc"):format(r.fights, math.floor(s.seconds / 60 + 0.5)) },
      { label = "Közelharc", value = s.swingUptime and Pct(s.swingUptime * 100) or "–", sub = "a lehetséges ütésekből",
        tip = "Hány ütést adtál le ahhoz képest, amennyit a fegyvered ennyi idő alatt üthetett volna (a Windfury plusz ütései is benne vannak)." },
      { label = "Shock", value = F1(s.shocksPerMin), sub = "percenként" },
      { label = "Lightning Shield", value = s.shield and Pct(s.shield) or "–", sub = "uptime" },
    } },
  }
  local srcRows = {}
  for _, k in ipairs({ "melee", "imbue", "spell", "totem", "dot", "other" }) do
    if (s.sources[k] or 0) > 0 then
      srcRows[#srcRows + 1] = { KIND_SH[k], Cell(Bar(s.shares[k]), s.shares[k]), Cell(s.sources[k], s.sources[k]),
        Cell(F1(s.sources[k] / s.seconds), s.sources[k] / s.seconds) }
    end
  end
  blocks[#blocks + 1] = { h = "Honnan jön a sebzés" }
  blocks[#blocks + 1] = { table = { id = "combat.ssrc", cols = { { "Forrás", 110 }, { "Arány", 0, flex = true }, { "Sebzés", 80, "RIGHT" },
    { "DPS", 64, "RIGHT" } }, rows = srcRows } }
  local rows = {}
  for _, a in ipairs(s.rows) do
    rows[#rows + 1] = { a.name, KIND_SH[a.kind] or a.kind, Cell(Pct(a.share), a.share), Cell(a.n, a.n), Cell(F1(a.cpm), a.cpm),
      Cell(math.floor(a.perCast + 0.5), a.perCast), Cell(math.floor(a.avg + 0.5), a.avg) }
  end
  blocks[#blocks + 1] = { h = "Képességek: használat percenként és sebzés használatonként" }
  blocks[#blocks + 1] = { table = { id = "combat.scpm", cols = { { "Képesség", 0, flex = true }, { "Fajta", 80 }, { "Arány", 60, "RIGHT" },
    { "Db", 50, "RIGHT" }, { "Percenként", 76, "RIGHT" }, { "Használatonként", 104, "RIGHT" }, { "Átlag találat", 90, "RIGHT", extra = true } }, rows = rows } }
  if s.meleeMiss then
    blocks[#blocks + 1] = { p = ("Közelharc: %s miss/dodge/parry, %s crit."):format(Pct(s.meleeMiss), Pct(s.meleeCrit)), muted = true }
  end
  return Section("combat.shaman", "Shaman összesítő (minden harc)", blocks, true, r.fights)
end

-- Druids: the same summary (paw, Cat Form abilities, bleeds, bear, spells; bleed uptime from the
-- ticks, finisher combo points, energy at the cap).
local KIND_DR = { melee = "mancs / közelharc", cat = "Cat Form", bleed = "vérzés", bear = "medve", spell = "varázslat", other = "egyéb" }
local function DruidSummary(r, ctx)
  local s = WA.Druid.Summary(r, ctx)
  local function Bar(pct) return ("%s %s"):format(Pct(pct), Muted(("|"):rep(math.floor(pct / 4 + 0.5)))) end
  local blocks = {
    { cards = {
      { label = "Átlag DPS", value = F1(s.dps), sub = ("%d harc, %d perc"):format(r.fights, math.floor(s.seconds / 60 + 0.5)) },
      { label = "Rake", value = s.rake and Pct(s.rake) or "–", sub = "vérzés a harcidőben",
        tip = "A Rake tickjeiből: tickenként 3 mp vérzés (Wowhead Forever spell=1822), osztva az összes harcidővel." },
      { label = "Rip", value = s.rip and Pct(s.rip) or "–", sub = s.ripCp and ("átlag " .. F1(s.ripCp) .. " combo pont") or "vérzés a harcidőben",
        tip = "A Rip tickjeiből: tickenként 2 mp vérzés (Wowhead Forever spell=1079), osztva az összes harcidővel." },
      { label = "Energia tele", value = s.energyCapped and Pct(s.energyCapped) or "–", sub = s.biteCp and ("Bite átlag " .. F1(s.biteCp) .. " pont") or "Cat Formban",
        tip = "A harcnapló energiaértékeiből: az idő hány százalékában álltál teli energiával." },
    } },
  }
  local srcRows = {}
  for _, k in ipairs({ "melee", "cat", "bleed", "bear", "spell", "other" }) do
    if (s.sources[k] or 0) > 0 then
      srcRows[#srcRows + 1] = { KIND_DR[k], Cell(Bar(s.shares[k]), s.shares[k]), Cell(s.sources[k], s.sources[k]),
        Cell(F1(s.sources[k] / s.seconds), s.sources[k] / s.seconds) }
    end
  end
  blocks[#blocks + 1] = { h = "Honnan jön a sebzés" }
  blocks[#blocks + 1] = { table = { id = "combat.dsrc", cols = { { "Forrás", 120 }, { "Arány", 0, flex = true }, { "Sebzés", 80, "RIGHT" },
    { "DPS", 64, "RIGHT" } }, rows = srcRows } }
  local rows = {}
  for _, a in ipairs(s.rows) do
    rows[#rows + 1] = { a.name, KIND_DR[a.kind] or a.kind, Cell(Pct(a.share), a.share), Cell(a.n, a.n), Cell(F1(a.cpm), a.cpm),
      Cell(math.floor(a.perCast + 0.5), a.perCast), Cell(math.floor(a.avg + 0.5), a.avg) }
  end
  blocks[#blocks + 1] = { h = "Képességek: használat percenként és sebzés használatonként" }
  blocks[#blocks + 1] = { table = { id = "combat.dcpm", cols = { { "Képesség", 0, flex = true }, { "Fajta", 100 }, { "Arány", 60, "RIGHT" },
    { "Db", 50, "RIGHT" }, { "Percenként", 76, "RIGHT" }, { "Használatonként", 104, "RIGHT" }, { "Átlag találat", 90, "RIGHT", extra = true } }, rows = rows } }
  if s.meleeMiss then
    blocks[#blocks + 1] = { p = ("Közelharc: %s miss/dodge/parry, %s crit."):format(Pct(s.meleeMiss), Pct(s.meleeCrit)), muted = true }
  end
  return Section("combat.druid", "Druid összesítő (minden harc)", blocks, true, r.fights)
end

-- Warlocks: the same summary (spells, DoTs, drains, demon, wand; DoT uptime from the ticks, Life Tap).
local KIND_WL = { nuke = "direkt varázslat", dot = "DoT", drain = "drain, Wrack", pet = "démon", wand = "pálca", melee = "közelharc", other = "egyéb" }
local function WarlockSummary(r, ctx, fights)
  local s = WA.Warlock.Summary(r, ctx, fights)
  local function Bar(pct) return ("%s %s"):format(Pct(pct), Muted(("|"):rep(math.floor(pct / 4 + 0.5)))) end
  local dot1, dot2 = s.dots[1], s.dots[2]
  local blocks = {
    { cards = {
      { label = "Átlag DPS", value = F1(s.dps), sub = ("%d harc, %d perc"):format(r.fights, math.floor(s.seconds / 60 + 0.5)) },
      { label = dot1 and dot1.name or "DoT", value = dot1 and Pct(dot1.uptime) or "–", sub = "sebzett a harcidőben",
        tip = "A tickekből: tickenként 3 mp (Corruption, Immolate, Siphon Life) vagy 2 mp (Bane of Agony), osztva az összes harcidővel." ..
          (s.wrack and " A Wrack alatt a DoT-ok gyorsabban tickelnek, ezért ez az érték felfelé torzít." or "") },
      { label = dot2 and dot2.name or "Démon", value = dot2 and Pct(dot2.uptime) or Pct(s.shares.pet), sub = dot2 and "sebzett a harcidőben" or "a sebzésedből" },
      { label = "Life Tap", value = s.taps.n > 0 and tostring(s.taps.n) or "–",
        sub = s.taps.n > 0 and ("%d mana, %d elveszett"):format(math.floor(s.taps.gain + 0.5), math.floor(s.taps.over + 0.5)) or "nincs adat a harcokban",
        tip = "A harcnaplóból: a mana-esemény maga mondja meg, mennyi ment a maximum fölé." },
    } },
  }
  local srcRows = {}
  for _, k in ipairs({ "nuke", "dot", "drain", "pet", "wand", "melee", "other" }) do
    if (s.sources[k] or 0) > 0 then
      srcRows[#srcRows + 1] = { KIND_WL[k], Cell(Bar(s.shares[k]), s.shares[k]), Cell(s.sources[k], s.sources[k]),
        Cell(F1(s.sources[k] / s.seconds), s.sources[k] / s.seconds) }
    end
  end
  blocks[#blocks + 1] = { h = "Honnan jön a sebzés" }
  blocks[#blocks + 1] = { table = { id = "combat.wsrc", cols = { { "Forrás", 120 }, { "Arány", 0, flex = true }, { "Sebzés", 80, "RIGHT" },
    { "DPS", 64, "RIGHT" } }, rows = srcRows } }
  local rows = {}
  for _, a in ipairs(s.rows) do
    rows[#rows + 1] = { a.name, KIND_WL[a.kind] or a.kind, Cell(Pct(a.share), a.share), Cell(a.n, a.n), Cell(F1(a.cpm), a.cpm),
      Cell(math.floor(a.perCast + 0.5), a.perCast), Cell(math.floor(a.avg + 0.5), a.avg) }
  end
  blocks[#blocks + 1] = { h = "Képességek: használat percenként és sebzés használatonként" }
  blocks[#blocks + 1] = { table = { id = "combat.wcpm", cols = { { "Képesség", 0, flex = true }, { "Fajta", 100 }, { "Arány", 60, "RIGHT" },
    { "Db", 50, "RIGHT" }, { "Percenként", 76, "RIGHT" }, { "Használatonként", 104, "RIGHT" }, { "Átlag találat", 90, "RIGHT", extra = true } }, rows = rows } }
  return Section("combat.warlock", "Warlock összesítő (minden harc)", blocks, true, r.fights)
end

-- Mages: the same summary (main nuke, other spells, AoE, wand; mana potions and gems).
local KIND_MG = { nuke = "direkt varázslat", dot = "DoT", aoe = "AoE", wand = "pálca", melee = "közelharc", other = "egyéb" }
local function MageSummary(r, ctx, fights)
  local s = WA.Mage.Summary(r, ctx, fights)
  local function Bar(pct) return ("%s %s"):format(Pct(pct), Muted(("|"):rep(math.floor(pct / 4 + 0.5)))) end
  local blocks = {
    { cards = {
      { label = "Átlag DPS", value = F1(s.dps), sub = ("%d harc, %d perc"):format(r.fights, math.floor(s.seconds / 60 + 0.5)) },
      { label = s.main and s.main.name or (s.nuke or "Fő varázslat"), value = s.main and (F1(s.main.cpm) .. "/perc") or "–",
        sub = s.main and ("crit %s, miss %s"):format(Pct(s.main.crit), Pct(s.main.miss)) or "nincs adat" },
      { label = "Pálca része", value = Pct(s.shares.wand), sub = ("AoE %d%%"):format(math.floor(s.shares.aoe + 0.5)) },
      { label = "Manaital, mana gem", value = s.mana.n > 0 and tostring(s.mana.n) or "–",
        sub = s.mana.n > 0 and ("%d mana, %d elveszett"):format(math.floor(s.mana.gain + 0.5), math.floor(s.mana.over + 0.5)) or "nincs adat a harcokban",
        tip = "A harcnaplóból: a mana-esemény maga mondja meg, mennyi ment a maximum fölé." },
    } },
  }
  local srcRows = {}
  for _, k in ipairs({ "nuke", "dot", "aoe", "wand", "melee", "other" }) do
    if (s.sources[k] or 0) > 0 then
      srcRows[#srcRows + 1] = { KIND_MG[k], Cell(Bar(s.shares[k]), s.shares[k]), Cell(s.sources[k], s.sources[k]),
        Cell(F1(s.sources[k] / s.seconds), s.sources[k] / s.seconds) }
    end
  end
  blocks[#blocks + 1] = { h = "Honnan jön a sebzés" }
  blocks[#blocks + 1] = { table = { id = "combat.msrc", cols = { { "Forrás", 120 }, { "Arány", 0, flex = true }, { "Sebzés", 80, "RIGHT" },
    { "DPS", 64, "RIGHT" } }, rows = srcRows } }
  local rows = {}
  for _, a in ipairs(s.rows) do
    rows[#rows + 1] = { a.name, KIND_MG[a.kind] or a.kind, Cell(Pct(a.share), a.share), Cell(a.n, a.n), Cell(F1(a.cpm), a.cpm),
      Cell(math.floor(a.perCast + 0.5), a.perCast), Cell(math.floor(a.avg + 0.5), a.avg) }
  end
  blocks[#blocks + 1] = { h = "Képességek: használat percenként és sebzés használatonként" }
  blocks[#blocks + 1] = { table = { id = "combat.mcpm", cols = { { "Képesség", 0, flex = true }, { "Fajta", 100 }, { "Arány", 60, "RIGHT" },
    { "Db", 50, "RIGHT" }, { "Percenként", 76, "RIGHT" }, { "Használatonként", 104, "RIGHT" }, { "Átlag találat", 90, "RIGHT", extra = true } }, rows = rows } }
  return Section("combat.mage", "Mage összesítő (minden harc)", blocks, true, r.fights)
end

-- Priests: Smite, Mind Blast, Mind Flay, Shadow Word: Pain, wand; mana potions.
local KIND_PR = { nuke = "direkt varázslat", flay = "Mind Flay", dot = "DoT", aoe = "AoE", wand = "pálca", melee = "közelharc", other = "egyéb" }
local function PriestSummary(r, ctx, fights)
  local s = WA.Priest.Summary(r, ctx, fights)
  local function Bar(pct) return ("%s %s"):format(Pct(pct), Muted(("|"):rep(math.floor(pct / 4 + 0.5)))) end
  local blocks = {
    { cards = {
      { label = "Átlag DPS", value = F1(s.dps), sub = ("%d harc, %d perc"):format(r.fights, math.floor(s.seconds / 60 + 0.5)) },
      { label = "Mind Blast", value = s.mb and (F1(s.mb.cpm) .. "/perc") or "–",
        sub = s.mb and ("legfeljebb %s/perc (8 mp cooldown)"):format(F1(s.mb.max)) or "nincs a harcokban" },
      { label = "Shadow Word: Pain", value = s.swp and Pct(s.swp) or "–", sub = "a harcidő része, amikor sebzett (tickekből)" },
      { label = "Manaital", value = s.mana.n > 0 and tostring(s.mana.n) or "–",
        sub = s.mana.n > 0 and ("%d mana, %d elveszett"):format(math.floor(s.mana.gain + 0.5), math.floor(s.mana.over + 0.5)) or "nincs adat a harcokban",
        tip = "A harcnaplóból: a mana-esemény maga mondja meg, mennyi ment a maximum fölé." },
    } },
  }
  local srcRows = {}
  for _, k in ipairs({ "nuke", "flay", "dot", "aoe", "wand", "melee", "other" }) do
    if (s.sources[k] or 0) > 0 then
      srcRows[#srcRows + 1] = { KIND_PR[k], Cell(Bar(s.shares[k]), s.shares[k]), Cell(s.sources[k], s.sources[k]),
        Cell(F1(s.sources[k] / s.seconds), s.sources[k] / s.seconds) }
    end
  end
  blocks[#blocks + 1] = { h = "Honnan jön a sebzés" }
  blocks[#blocks + 1] = { table = { id = "combat.psrc", cols = { { "Forrás", 120 }, { "Arány", 0, flex = true }, { "Sebzés", 80, "RIGHT" },
    { "DPS", 64, "RIGHT" } }, rows = srcRows } }
  local rows = {}
  for _, a in ipairs(s.rows) do
    rows[#rows + 1] = { a.name, KIND_PR[a.kind] or a.kind, Cell(Pct(a.share), a.share), Cell(a.n, a.n), Cell(F1(a.cpm), a.cpm),
      Cell(math.floor(a.perCast + 0.5), a.perCast), Cell(math.floor(a.avg + 0.5), a.avg) }
  end
  blocks[#blocks + 1] = { h = "Képességek: használat percenként és sebzés használatonként" }
  blocks[#blocks + 1] = { table = { id = "combat.pcpm", cols = { { "Képesség", 0, flex = true }, { "Fajta", 100 }, { "Arány", 60, "RIGHT" },
    { "Db", 50, "RIGHT" }, { "Percenként", 76, "RIGHT" }, { "Használatonként", 104, "RIGHT" }, { "Átlag találat", 90, "RIGHT", extra = true } }, rows = rows } }
  return Section("combat.priest", "Priest összesítő (minden harc)", blocks, true, r.fights)
end

-- Paladins: white swings, Holy Strike, seals, Judgement, Consecration.
local KIND_PA = { melee = "fehér ütés", hs = "Holy Strike", seal = "seal", judgement = "Judgement", other = "egyéb" }
local function PaladinSummary(r, ctx, fights)
  local s = WA.Paladin.Summary(r, ctx, fights)
  local function Bar(pct) return ("%s %s"):format(Pct(pct), Muted(("|"):rep(math.floor(pct / 4 + 0.5)))) end
  local m = s.melee
  local blocks = {
    { cards = {
      { label = "Átlag DPS", value = F1(s.dps), sub = ("%d harc, %d perc"):format(r.fights, math.floor(s.seconds / 60 + 0.5)) },
      { label = "Fehér ütés", value = m and Pct(s.shares.melee) or "–",
        sub = m and ("miss %s, dodge %s, crit %s"):format(Pct(m.miss), Pct(m.dodge), Pct(m.crit)) or "nincs adat" },
      { label = "Seal", value = Pct(s.shares.seal), sub = (s.seals.seconds >= 60 and #s.seals.list > 0)
        and ("%s fent, Judgement %d%%"):format(WA.Paladin.SealList({ list = { s.seals.list[1] } }), math.floor(s.shares.judgement + 0.5))
        or ("Judgement %d%%"):format(math.floor(s.shares.judgement + 0.5)) },
      { label = "Holy Strike", value = F1(s.hsCpm) .. "/perc", sub = "legfeljebb 6/perc (10 mp cooldown)" },
    } },
  }
  local srcRows = {}
  for _, k in ipairs({ "melee", "hs", "seal", "judgement", "other" }) do
    if (s.sources[k] or 0) > 0 then
      srcRows[#srcRows + 1] = { KIND_PA[k], Cell(Bar(s.shares[k]), s.shares[k]), Cell(s.sources[k], s.sources[k]),
        Cell(F1(s.sources[k] / s.seconds), s.sources[k] / s.seconds) }
    end
  end
  blocks[#blocks + 1] = { h = "Honnan jön a sebzés" }
  blocks[#blocks + 1] = { table = { id = "combat.pasrc", cols = { { "Forrás", 120 }, { "Arány", 0, flex = true }, { "Sebzés", 80, "RIGHT" },
    { "DPS", 64, "RIGHT" } }, rows = srcRows } }
  local rows = {}
  for _, a in ipairs(s.rows) do
    rows[#rows + 1] = { a.name, KIND_PA[a.kind] or a.kind, Cell(Pct(a.share), a.share), Cell(a.n, a.n), Cell(F1(a.cpm), a.cpm),
      Cell(math.floor(a.perCast + 0.5), a.perCast), Cell(math.floor(a.avg + 0.5), a.avg) }
  end
  blocks[#blocks + 1] = { h = "Képességek: használat percenként és sebzés használatonként" }
  blocks[#blocks + 1] = { table = { id = "combat.pacpm", cols = { { "Képesség", 0, flex = true }, { "Fajta", 100 }, { "Arány", 60, "RIGHT" },
    { "Db", 50, "RIGHT" }, { "Percenként", 76, "RIGHT" }, { "Használatonként", 104, "RIGHT" }, { "Átlag találat", 90, "RIGHT", extra = true } }, rows = rows } }
  return Section("combat.paladin", "Paladin összesítő (minden harc)", blocks, true, r.fights)
end

-- Warriors: white swings, Heroic Strike, weapon specials, Rend; rage over the maximum.
local KIND_WR = { melee = "fehér ütés", hs = "Heroic Strike", special = "fegyveres special", dot = "DoT (Rend)", other = "egyéb" }
local function WarriorSummary(r, ctx, fights)
  local s = WA.Warrior.Summary(r, ctx, fights)
  local function Bar(pct) return ("%s %s"):format(Pct(pct), Muted(("|"):rep(math.floor(pct / 4 + 0.5)))) end
  local lost = 0
  for _, x in pairs(s.rage.bySpell) do lost = lost + x.over end
  local blocks = {
    { cards = {
      { label = "Átlag DPS", value = F1(s.dps), sub = ("%d harc, %d perc"):format(r.fights, math.floor(s.seconds / 60 + 0.5)) },
      { label = "Fehér ütés", value = s.melee and Pct(100 - s.melee.miss - s.melee.dodge) or "–",
        sub = s.melee and ("miss %s, dodge/parry %s, crit %s"):format(Pct(s.melee.miss), Pct(s.melee.dodge), Pct(s.melee.crit)) or "nincs adat" },
      { label = "Heroic Strike", value = Pct(s.hsShare), sub = "az ütéseidből" },
      { label = "Elveszett rage", value = s.rage.seen > 0 and tostring(math.floor(lost + 0.5)) or "–",
        sub = s.rage.seen > 0 and ("%d rage a naplózott forrásokból"):format(math.floor(s.rage.gain + lost + 0.5)) or "nincs adat a harcokban",
        tip = "A harcnaplóból: a rage-esemény (Bloodrage, Charge, Shield Specialization, Unbridled Wrath...) maga mondja meg, mennyi ment a 100 fölé. A fehér ütések rage-e nem esemény, az nem látszik." },
    } },
  }
  local srcRows = {}
  for _, k in ipairs({ "melee", "hs", "special", "dot", "other" }) do
    if (s.sources[k] or 0) > 0 then
      srcRows[#srcRows + 1] = { KIND_WR[k], Cell(Bar(s.shares[k]), s.shares[k]), Cell(s.sources[k], s.sources[k]),
        Cell(F1(s.sources[k] / s.seconds), s.sources[k] / s.seconds) }
    end
  end
  blocks[#blocks + 1] = { h = "Honnan jön a sebzés" }
  blocks[#blocks + 1] = { table = { id = "combat.wrsrc", cols = { { "Forrás", 120 }, { "Arány", 0, flex = true }, { "Sebzés", 80, "RIGHT" },
    { "DPS", 64, "RIGHT" } }, rows = srcRows } }
  local rows = {}
  for _, a in ipairs(s.rows) do
    rows[#rows + 1] = { a.name, KIND_WR[a.kind] or a.kind, Cell(Pct(a.share), a.share), Cell(a.n, a.n), Cell(F1(a.cpm), a.cpm),
      Cell(math.floor(a.perCast + 0.5), a.perCast), Cell(math.floor(a.avg + 0.5), a.avg) }
  end
  blocks[#blocks + 1] = { h = "Képességek: használat percenként és sebzés használatonként" }
  blocks[#blocks + 1] = { table = { id = "combat.wrcpm", cols = { { "Képesség", 0, flex = true }, { "Fajta", 110 }, { "Arány", 60, "RIGHT" },
    { "Db", 50, "RIGHT" }, { "Percenként", 76, "RIGHT" }, { "Használatonként", 104, "RIGHT" }, { "Átlag találat", 90, "RIGHT", extra = true } }, rows = rows } }
  return Section("combat.warrior", "Warrior összesítő (minden harc)", blocks, true, r.fights)
end

function UI.pages.combat()
  local all = G.Fights()
  table.sort(all, function(a, b) return a.start > b.start end)
  local counts = { log = 0, live = 0, meter = 0 }
  for _, f in ipairs(all) do counts[f.source or "log"] = (counts[f.source or "log"] or 0) + 1 end
  UI.status = ("%d harc: %d játékban rögzítve, %d a harcnaplóból"):format(#all, counts.live + counts.meter, counts.log)
  UI.head.combat = { "Harc", "Minden harc magától rögzül; válassz egyet a listából a részleteihez" }
  if #all == 0 then
    return { { empty = { "Még nincs rögzített harc", "Az addon minden harcot magától rögzít: üss meg egy mobot, és a harc vége után itt lesz." } } }
  end
  local hunter = G.Class() == "HUNTER"
  local shaman = G.Class() == "SHAMAN"
  local druid = G.Class() == "DRUID"
  local warlock = G.Class() == "WARLOCK"
  local mage = G.Class() == "MAGE"
  local warrior = G.Class() == "WARRIOR"
  local priest = G.Class() == "PRIEST"
  local paladin = G.Class() == "PALADIN"
  local ctx = G.Supported() and G.Context() or nil
  local baseline = ctx and ctx.baseline or nil
  local function Score(x)
    if hunter then return WA.Hunter.Score(x, ctx) end
    if shaman then return WA.Shaman.Score(x, ctx) end
    if druid then return WA.Druid.Score(x, ctx) end
    if warlock then return WA.Warlock.Score(x, ctx) end
    if mage then return WA.Mage.Score(x, ctx) end
    if warrior then return WA.Warrior.Score(x, ctx) end
    if priest then return WA.Priest.Score(x, ctx) end
    if paladin then return WA.Paladin.Score(x, ctx) end
    return WA.Combat.Score(x, WA.Combat.Comparable(x, ctx) and baseline or nil)
  end
  local out = {}

  local f = all[1]
  for _, x in ipairs(all) do if x.start == UI.selFight then f = x end end
  local sc = Score(f)
  local prov = WA.Combat.Provenance(f, ctx)
  local P = {}
  for _, r in ipairs(prov) do P[r.key] = r end
  UI.head.combat[2] = ("%s%s · %s · forrás: %s"):format(TargetName(f), (f.targetLevel or 0) > 0 and (" (" .. f.targetLevel .. ")") or "",
    date("%m.%d %H:%M", f.start), SOURCE_NAME[f.source or "log"] or "?")
  out[#out + 1] = { cards = {
    { label = "Pontszám", value = Grade(sc), sub = sc and "0–100, S a legjobb" or "nincs elég adat",
      tip = hunter and "DPS a várthoz képest, Auto Shot folyamatossága, a pet része, távolság, Serpent Sting, lövések percenként."
        or shaman and "DPS a várthoz képest, ütések folyamatossága, shock percenként, totem a hosszú harcban, Stormstrike cooldownra."
        or druid and "DPS a várthoz képest; Cat Formban ütések folyamatossága, kárba ment energia, finisherek combo pontjai, Rake; Cat Form nélkül varázslatok percenként."
        or warlock and "DPS a várthoz képest, folyamatos castolás (pálcával együtt), DoT a hosszabb harcban, kárba ment Life Tap."
        or mage and "DPS a várthoz képest, folyamatos castolás (pálcával együtt), kárba ment manaital vagy mana gem."
        or warrior and "DPS a várthoz képest, folyamatos ütés, a 100 fölött elveszett rage (a harcnapló rage-eseményeiből)."
        or priest and "DPS a várthoz képest, folyamatos castolás (pálcával együtt), Shadow Word: Pain a hosszabb harcban, kárba ment manaital."
        or paladin and "DPS a várthoz képest, folyamatos ütés, Holy Strike a cooldownjához képest, kárba ment manaital."
        or "DPS a felszerelésedtől várthoz képest, kárba ment energia, Eviscerate combo pontjai, Slice and Dice uptime, képességek percenként." },
    { label = "DPS", value = P.dps.text, sub = P.dps.status .. (P.model and P.model.value and (" · várt " .. P.model.text .. " (szimulált)") or ""),
      tip = P.dps.from .. (P.model and ("\nVárt: " .. P.model.from) or "") },
    hunter and (function()
      local _, sh = WA.Hunter.Sources(f.ab, f.dmg)
      return { label = "Pet része", value = Pct(sh.pet), sub = ("távolsági %d%%, közel %d%%"):format(math.floor(sh.ranged + 0.5), math.floor(sh.melee + 0.5)) }
    end)() or shaman and (function()
      local _, sh = WA.Shaman.Sources(f.ab, f.dmg)
      return { label = "Közelharc része", value = Pct(sh.melee + sh.imbue), sub = ("varázslat %d%%, totem %d%%"):format(math.floor(sh.spell + 0.5), math.floor(sh.totem + 0.5)) }
    end)() or druid and (function()
      local _, sh = WA.Druid.Sources(f.ab, f.dmg)
      return { label = "Cat Form része", value = Pct(sh.melee + sh.cat + sh.bleed), sub = ("vérzés %d%%, varázslat %d%%"):format(math.floor(sh.bleed + 0.5), math.floor(sh.spell + 0.5)) }
    end)() or warlock and (function()
      local _, sh = WA.Warlock.Sources(f.ab, f.dmg)
      return { label = "DoT része", value = Pct(sh.dot + sh.drain), sub = ("démon %d%%, pálca %d%%"):format(math.floor(sh.pet + 0.5), math.floor(sh.wand + 0.5)) }
    end)() or mage and (function()
      local _, sh = WA.Mage.Sources(f.ab, f.dmg)
      return { label = "Direkt varázslat", value = Pct(sh.nuke), sub = ("AoE %d%%, pálca %d%%"):format(math.floor(sh.aoe + 0.5), math.floor(sh.wand + 0.5)) }
    end)() or warrior and (function()
      local _, sh = WA.Warrior.Sources(f.ab, f.dmg)
      return { label = "Fehér ütés része", value = Pct(sh.melee), sub = ("Heroic Strike %d%%, special %d%%"):format(math.floor(sh.hs + 0.5), math.floor(sh.special + 0.5)) }
    end)() or priest and (function()
      local _, sh = WA.Priest.Sources(f.ab, f.dmg)
      return { label = "Varázslat része", value = Pct(sh.nuke + sh.flay + sh.dot), sub = ("DoT %d%%, pálca %d%%"):format(math.floor(sh.dot + 0.5), math.floor(sh.wand + 0.5)) }
    end)() or paladin and (function()
      local _, sh = WA.Paladin.Sources(f.ab, f.dmg)
      return { label = "Fehér ütés része", value = Pct(sh.melee), sub = ("seal %d%%, Holy Strike %d%%"):format(math.floor(sh.seal + 0.5), math.floor(sh.hs + 0.5)) }
    end)() or { label = "Sebzés", value = tostring(f.dmg or 0), sub = (f.ab and #f.ab or 0) .. " képesség" },
    { label = "Hossz", value = F1(f.dur) .. " mp", sub = f.casts and (#f.casts .. " használat") or "" },
  } }
  if f.source == "live" and not f.detailed then
    out[#out + 1] = { tips = { { level = "info", text = "Ebben a harcban nincs találati arány: a célpont ütéseit az addon csak egyedül játszva számolja." } } }
  end

  local list = {}
  for i = 1, math.min(60, #all) do
    local x = all[i]
    local s2 = Score(x)
    list[#list + 1] = { cells = { Cell(date("%m.%d %H:%M", x.start), x.start), TargetName(x) .. ((x.targetLevel or 0) > 0 and (" (" .. x.targetLevel .. ")") or ""),
      Cell((x.dur or 0) > 0 and F1(x.dmg / x.dur) or "–", (x.dur or 0) > 0 and x.dmg / x.dur or -1), Cell(Grade(s2), s2 and s2.total or -1),
      Cell(F1(x.dur) .. " mp", x.dur), SOURCE_NAME[x.source or "log"] or "?" },
      selected = x == f, onClick = function() UI.selFight = x.start UI.cache.combat = nil UI.Draw() end }
  end
  out[#out + 1] = Section("combat.list", "Harcok", { { table = { id = "combat.list", cols = { { "Mikor", 90 }, { "Célpont", 0, flex = true },
    { "DPS", 64, "RIGHT" }, { "Pont", 74, "RIGHT" }, { "Hossz", 70, "RIGHT", extra = true }, { "Forrás", 96, extra = true } }, rows = list, limit = 6 } } }, true, #all)

  -- where every number above comes from, and what kind of number it is
  local STATUS_COLOR = { ["mért"] = HEX.good, ["becsült"] = HEX.gold, ["szimulált"] = "8fb8ff", ["nem értékelhető"] = HEX.warn }
  local provRows = {}
  for _, r in ipairs(prov) do
    provRows[#provRows + 1] = { cells = { r.label, Color(STATUS_COLOR[r.status] or "ffffff", r.status), Cell(r.text, r.value or -1), r.from },
      tip = r.label .. ": " .. r.from }
  end
  out[#out + 1] = Section("combat.prov", "Honnan a számok", { { p = "mért: forrásból összesítve · becsült: közvetett adatból · szimulált: modellből számolva · " ..
    "nem értékelhető: nincs hozzá adat (ilyenkor nem 0, hanem –).", muted = true },
    { table = { id = "combat.prov", cols = { { "Mi", 190 }, { "Állapot", 104 }, { "Érték", 80, "RIGHT" }, { "Miből", 0, flex = true } },
      rows = provRows } } }, true, #prov)

  if sc then
    local rows = {}
    for _, p in ipairs(sc.parts) do
      local pct = p.max > 0 and p.points / p.max or 0
      local col = pct >= 0.8 and HEX.good or (pct >= 0.5 and HEX.gold or HEX.warn)
      rows[#rows + 1] = { p.label, Cell(Color(col, ("%d / %d"):format(math.floor(p.points + 0.5), p.max)), pct), p.text }
    end
    out[#out + 1] = Section("combat.score", "Mitől ennyi a pontszám", { { p = "A pontszám a mért adataid összevetése a szokásos játékkal; " ..
      "egy alacsony rész önmagában nem bizonyított hiba (lásd a tanácsoknál, mi igazolható).", muted = true }, { table = { id = "combat.score",
      cols = { { "Mi számít", 210 }, { "Pont", 70, "RIGHT" }, { "Részletek", 0, flex = true } }, rows = rows } } }, true)
  end

  local ab = {}
  for _, a in ipairs(f.ab or {}) do ab[#ab + 1] = a end
  WA.Model.Stable(ab, function(a, b) return (a.dmg or 0) > (b.dmg or 0) end)
  out[#out + 1] = Section("combat.fab", "Képességek ebben a harcban", { { table = { id = "combat.fab", cols = ABILITY_COLS,
    rows = AbilityRows(ab, f.dmg or 0) } } }, true, #ab)

  if f.casts and #f.casts > 0 then
    local rows = {}
    for i, c in ipairs(f.casts) do
      rows[#rows + 1] = { Cell(Clock(c[1]), c[1]), c[2], Cell((c[3] or -1) >= 0 and c[3] or "–", c[3] or -1),
        Cell((c[4] or 0) > 0 and c[4] or "", c[4] or 0), Cell(i, i) }
    end
    out[#out + 1] = Section("combat.casts", "Mikor mit használtál", { { table = { id = "combat.casts", cols = { { "Idő", 70 },
      { "Képesség", 0, flex = true }, { "Energia", 70, "RIGHT" }, { "Combo", 60, "RIGHT" }, { "#", 40, "RIGHT", extra = true } }, rows = rows, limit = 12 } } },
      false, #f.casts)
  end

  -- all fights together (the web app's combat page)
  local r = WA.Combat.Report(all, nil, hunter and WA.Hunter.Advise or shaman and WA.Shaman.Advise or druid and WA.Druid.Advise or warlock and WA.Warlock.Advise or mage and WA.Mage.Advise or warrior and WA.Warrior.Advise or priest and WA.Priest.Advise or paladin and WA.Paladin.Advise or nil)
  if not r then return out end
  if hunter then out[#out + 1] = HunterSummary(r, ctx) end
  if shaman then out[#out + 1] = ShamanSummary(r, ctx) end
  if druid then out[#out + 1] = DruidSummary(r, ctx) end
  if warlock then out[#out + 1] = WarlockSummary(r, ctx, all) end
  if mage then out[#out + 1] = MageSummary(r, ctx, all) end
  if warrior then out[#out + 1] = WarriorSummary(r, ctx, all) end
  if priest then out[#out + 1] = PriestSummary(r, ctx, all) end
  if paladin then out[#out + 1] = PaladinSummary(r, ctx, all) end
  if #r.advice > 0 then
    local tips = {}
    for _, a in ipairs(r.advice) do tips[#tips + 1] = { level = a.level, title = a.title, text = a.text } end
    out[#out + 1] = Section("combat.advice", "Tanácsok az összes harcod alapján", { { tips = tips } }, true, #tips)
  end
  local blocks = {
    { p = ("%d harc, %d perc, átlag %s DPS%s"):format(r.fights, math.floor(r.seconds / 60 + 0.5), F1(r.dps),
      r.energyCappedPct and (" · energiaplafonon " .. Pct(r.energyCappedPct)) or "") },
    { p = ("Auto-attack: %s miss, %s dodge, %s glancing, %s crit · képességek: %s miss, %s crit")
      :format(Pct(r.white.miss), Pct(r.white.dodge), Pct(r.white.glance), Pct(r.white.crit), Pct(r.yellow.miss), Pct(r.yellow.crit)), muted = true },
    { table = { id = "combat.ab", cols = ABILITY_COLS, rows = AbilityRows(r.abilities, r.damage) } },
  }
  if #r.finishers > 0 or #r.auras > 0 then
    local rows2 = {}
    for _, x in ipairs(r.finishers) do rows2[#rows2 + 1] = { x.name, "finisher", Cell(x.casts .. " ×, átlag " .. F1(x.avgCp) .. " CP", x.casts) } end
    for _, x in ipairs(r.auras) do rows2[#rows2 + 1] = { x.name, "buff", Cell(Pct(x.uptimePct) .. " uptime", x.uptimePct) } end
    blocks[#blocks + 1] = { h = "Finisherek és buffok" }
    blocks[#blocks + 1] = { table = { id = "combat.fin", cols = { { "Név", 0, flex = true }, { "Fajta", 90 }, { "Érték", 220 } }, rows = rows2 } }
  end
  if #r.byLevel > 0 then
    local rows3 = {}
    for _, x in ipairs(r.byLevel) do
      rows3[#rows3 + 1] = { Cell((x.diff > 0 and "+" or "") .. x.diff, x.diff), Cell(x.fights, x.fights), Cell(F1(x.dps), x.dps), Cell(Pct(x.missPct), x.missPct) }
    end
    blocks[#blocks + 1] = { h = "Célpont szintje szerint" }
    blocks[#blocks + 1] = { table = { id = "combat.lvl", cols = { { "Szintkülönbség", 0, flex = true }, { "Harc", 70, "RIGHT" },
      { "DPS", 80, "RIGHT" }, { "Fehér miss", 90, "RIGHT" } }, rows = rows3 } }
  end
  out[#out + 1] = Section("combat.all", "Összesítés, minden harc", blocks, false, r.fights)
  -- the model behind the numbers: the engine's status for every spec of your class, the addon's
  -- own model, and the reference functions that apply to you (spec §6)
  do
    local C = WA.Combat
    local class = G.Class()
    local cm = C.CLASS_MODELS[class or ""]
    if cm then
      local spec = G.Spec and G.Spec() or {}
      local mainTab, pts = spec.tab, spec.tab and (spec.points[spec.tab] or 0) or 0
      local level = UnitLevel and UnitLevel("player") or 0
      local rows5 = {}
      for i, t in ipairs(cm.tabs) do
        local mine = mainTab == i
        rows5[#rows5 + 1] = { (mine and "> " or "") .. cm.name .. " " .. t[1], t[2],
          cm.waystone and "van (szintezési modell)" or "nincs",
          C.SIM_STATUS_TEXT[t[2]] .. (mine and (" · a modell e szerint számol (" .. pts .. " pont)") or "") }
      end
      local refs = {}
      local function Ref(label, value, from) refs[#refs + 1] = { label, value, from } end
      if class == "ROGUE" then
        local link = GetInventoryItemLink and GetInventoryItemLink("player", 16)
        local sub = link and GetItemInfoInstant and select(7, GetItemInfoInstant(link)) or nil
        local per, norm = C.REF.SinisterStrikeAp(100, sub)
        if per then
          Ref("Sinister Strike +100 AP", ("+%s"):format(F1(per)), ("100 × %s / 14 (a fő kezed normalizált sebessége; " .. C.REF.ssSource .. ")"):format(F1(norm)))
        end
      end
      if class == "HUNTER" then
        local base, pos, neg = UnitAttackPower and UnitAttackPower("player")
        local rb, rpos, rneg = UnitRangedAttackPower and UnitRangedAttackPower("player")
        local melee = (base or 0) + (pos or 0) + (neg or 0)
        local ranged = (rb or 0) + (rpos or 0) + (rneg or 0)
        Ref("Pet örökölt AP-ja", ("+%d"):format(math.floor(C.REF.HunterPetAp(melee, ranged) + 0.5)),
          ("0,10 × max(%d melee, %d ranged AP); idézéskor rögzül, újrahívásig nem változik (%s)"):format(melee, ranged, C.REF.petSource))
      end
      if class == "WARLOCK" and GetSpellBonusDamage then
        -- the game's per-school numbers already include the general bonus: S = max(shadow, fire)
        local shadow, fire = GetSpellBonusDamage(6) or 0, GetSpellBonusDamage(3) or 0
        local ap, sp, s = C.REF.WarlockDemon(0, shadow, fire)
        Ref("Démon örökölt AP / spell damage", ("+%d / +%d"):format(math.floor(ap + 0.5), math.floor(sp + 0.5)),
          ("S = max(%d shadow, %d fire) = %d (a játék iskolánkénti értéke már tartalmazza az általános bónuszt); 0,17 × S és 0,10 × S (%s)"):format(shadow, fire, s, C.REF.demonSource))
      end
      -- WA-030: which spec the model counts for and why; chosen by hand for a mixed build
      local specButtons = { { label = "Spec: automatikus", width = 140, active = not spec.manual, onClick = function()
        WA.charDB.spec = nil UI.Refresh() end } }
      for i, name in ipairs(WA.Model.SPEC_NAMES[class] or {}) do
        specButtons[#specButtons + 1] = { label = name, width = 110, active = spec.manual and spec.tab == i, onClick = function()
          WA.charDB.spec = i UI.Refresh() end }
      end
      local blocks5 = {
        { p = ("%s %s."):format(Color(HEX.gold, spec.name and ("A modell a(z) %s spec szerint számol:"):format(spec.name) or "Spec:"), spec.from or "–") },
        { buttons = specButtons },
        { p = ("WoWSims Forever (%s): a %s%s. A motor csak 60-as karaktert épít%s."):format(C.SIM_SOURCE, cm.name,
          cm.shared and (" " .. cm.shared .. " szerint modellezett") or " specjei külön modellek",
          level > 0 and level < 60 and (", ezért a te szinteden (" .. level .. ") nincs szintazonos referencia; a saját mért adataid ettől még használhatók") or ""), muted = true },
        { table = { id = "combat.models", cols = { { "Spec", 170 }, { "WoWSims", 90 }, { "Waystone", 120 }, { "Mit jelent", 0, flex = true } }, rows = rows5 } },
      }
      if cm.note then blocks5[#blocks5 + 1] = { p = cm.note, muted = true } end
      if #refs > 0 then
        blocks5[#blocks5 + 1] = { h = "Referenciafüggvények (a modell bemenetei)" }
        blocks5[#blocks5 + 1] = { table = { id = "combat.refs", cols = { { "Mi", 190 }, { "Érték", 90, "RIGHT" }, { "Miből", 0, flex = true } }, rows = refs } }
      end
      out[#out + 1] = Section("combat.models", "Modell a kasztodhoz" .. (spec.name and (" · " .. spec.name) or ""), blocks5, false, #rows5)
    end
  end
  if r.cooldowns and #r.cooldowns > 0 then
    local rows4 = {}
    for _, u in ipairs(r.cooldowns) do
      local from = ("%d harc, %d mp harcidő; ebből %d mp töltődött%s. Cooldown: %s")
        :format(u.fights, math.floor(u.seconds + 0.5), math.floor(u.active + 0.5),
          u.carried > 0 and (" (" .. math.floor(u.carried + 0.5) .. " mp az előző harcból áthúzódva)") or "", u.source)
      rows4[#rows4 + 1] = { u.name, Cell(u.cd >= 60 and (math.floor(u.cd / 60) .. " perc") or (u.cd .. " mp"), u.cd), Cell(u.casts, u.casts),
        u.pct and Cell(Pct(u.pct), u.pct) or Cell("–", -1), from }
    end
    out[#out + 1] = Section("combat.cd", "Cooldownok kihasználtsága", {
      { p = "mért, a harcnapló castjaiból: a harcidő hány százalékában töltődött a képesség (" .. WA.Combat.CD_METHOD .. "; " ..
        "azonnali képességek, ezért castidő és GCD-várakozás nincs). Csak a Foreverre ellenőrzött cooldownok, és csak az első használat " ..
        "utáni harcok. Az alacsony érték nem hiba: a harc lehet rövidebb a cooldownnál, vagy a képesség nem volt használható.", muted = true },
      { table = { id = "combat.cd", cols = { { "Képesség", 120 }, { "Cooldown", 70, "RIGHT" }, { "Cast", 50, "RIGHT" },
        { "Kihasználtság", 90, "RIGHT" }, { "Miből", 0, flex = true } }, rows = rows4 } } }, true, #rows4)
  end
  return out
end

---------------------------------------------------------------------------
-- Pet (hunters): your pet, what to teach it, the best beasts for your level, the bestiary
---------------------------------------------------------------------------
local HAPPY = { "|cffff5555elégedetlen|r", "|cffffd100elégedett|r", "|cff55ff55boldog|r" }
local function FamilyHu(name)
  local f = WA.Pets.FAMILY[name]
  return f and (f.hu .. Muted(" (" .. name .. ")")) or (name or "?")
end
local function Teaches(b)
  local list = {}
  for name, rank in pairs(b.teaches) do list[#list + 1] = name .. " " .. rank end
  table.sort(list)
  return table.concat(list, ", ")
end
local function BeastRow(e, level)
  local b = e.beast or e
  local factor = e.factor or WA.Pets.DpsFactor(b)
  local name = b.name .. (b.rare and Color(HEX.gold, " ★") or "")
  local taught = Teaches(b)
  return { cells = { Cell(name, b.name), Cell(FamilyHu(b.family), b.family),
    Cell(b.speed < 200 and Color(HEX.good, WA.Pets.SpeedLabel(b)) or WA.Pets.SpeedLabel(b), b.speed),
    Cell(("%.2f×"):format(factor), factor),
    Cell(WA.Pets.Where(b) .. ((level and b.elite) and Color(HEX.warn, " – csoporttal") or ""), b.min),
    taught },
    tip = ("%s – %s\nTámadási sebesség: %s\nTanít: %s"):format(b.name, Plain(FamilyHu(b.family)), WA.Pets.SpeedLabel(b),
      taught ~= "" and taught or "semmit") }
end
local BEAST_COLS = { { "Állat", 0, flex = true }, { "Család", 150 }, { "Támadás", 96, "RIGHT" }, { "Sebzés", 60, "RIGHT" },
  { "Hol", 230 }, { "Tanít", 0, flex = true, extra = true } }

-- Pet share of your damage in the recorded fights (the newest 50).
local function PetShare()
  local fights = G.Fights()
  table.sort(fights, function(a, b) return a.start > b.start end)
  local pet, total, n = 0, 0, 0
  for i = 1, math.min(50, #fights) do
    local f = fights[i]
    for _, a in ipairs(f.ab or {}) do
      local base = (a.name or ""):gsub(" %(dot%)$", "")
      if base:sub(1, 5) == "Pet: " or WA.Hunter.PET[base] then pet = pet + (a.dmg or 0) end
    end
    total, n = total + (f.dmg or 0), n + 1
  end
  return total > 0 and pet / total * 100 or nil, n
end

function UI.pages.pet()
  UI.head.pet = { "Pet", "Mit taníts a petednek, hol szelídíts jobbat, és mire jó melyik család" }
  if G.Class() ~= "HUNTER" then
    return { { empty = { "Csak huntereknek", "A pet oldal a hunter petjéről szól." } } }
  end
  local PT = WA.Pets
  local level = UnitLevel("player") or 1
  local pet = G.Pet()
  local out = {}
  local share, nFights = PetShare()
  local tr = pet and PT.HasData() and PT.Training({ level = level, pet = pet, taught = G.Taught() }) or nil
  out[#out + 1] = { cards = {
    { label = "Pet", value = pet and (pet.name or "?") or Muted("nincs"),
      sub = pet and ("%s, %s. szint"):format(Plain(FamilyHu(pet.family)), tostring(pet.level or "?")) or "Call Pet / Tame Beast" },
    { label = "Training point", value = tr and tostring(tr.left) or "–", sub = pet and pet.tp and ("összesen " .. pet.tp) or "" },
    { label = "Hangulat", value = pet and pet.happiness and HAPPY[pet.happiness] or "–",
      sub = pet and pet.loyalty and tostring(pet.loyalty) or "etesd, hogy boldog maradjon" },
    { label = "Pet a sebzésedből", value = share and Pct(share) or "–", sub = nFights > 0 and (nFights .. " harc alapján") or "nincs rögzített harc",
      tip = "Leveling közben egy jó pet a sebzésed 25–40%-át adja." },
  } }
  local warn = {}
  if not PT.HasData() then warn[#warn + 1] = "Hiányzik a PetData.lua (az állatok listája): node scripts/build-pets.mjs --install" end
  if not G.Taught() then warn[#warn + 1] = "Nyisd meg egyszer a Beast Training ablakot: abból látja az addon, mely rangokat tudod már tanítani." end
  if pet and not UnitExists("pet") then warn[#warn + 1] = "A pet most nincs kint: a legutóbb látott állapotát mutatom." end
  Add(out, Warnings(warn))

  if tr then
    local STATUS = { teach = Color(HEX.good, "taníts"), tame = Color(HEX.gold, "szelídíts"), done = Muted("megvan"),
      later = Muted("később"), skip = Muted("ne tanítsd") }
    local ORDER = { teach = 1, tame = 2, done = 3, later = 4, skip = 5 }
    local rows = {}
    for _, r in ipairs(tr.rows) do
      local how
      if r.status == "teach" then
        how = "Beast Training ablakban" .. (r.fits == false and Color(HEX.warn, " (nincs elég training point)") or "")
      elseif r.status == "tame" then
        local t = {}
        for _, b in ipairs(r.teachers or {}) do t[#t + 1] = b.name .. Muted(" – " .. PT.Where(b)) end
        if #t > 0 then how = "Szelídítsd: " .. table.concat(t, "; ")
        elseif r.laterTeacher then how = Muted(("%d. szinttől: "):format(r.laterTeacher.min)) .. r.laterTeacher.name .. Muted(" – " .. PT.Where(r.laterTeacher))
        else how = Muted("egyik szelídíthető állat sem tanítja") end
      elseif r.status == "later" then
        how = r.petLevel and (r.petLevel .. ". pet-szinttől") or ""
      elseif r.status == "skip" then
        how = r.hu
      else
        how = r.next and Muted(("következő rang: %d. pet-szinttől"):format(r.next.level)) or Muted("a legmagasabb rang")
      end
      local rank = r.status == "done" and tostring(r.have) or ((r.have > 0 and (r.have .. " → ") or "") .. tostring(r.rank or "?"))
      rows[#rows + 1] = { cells = { r.ability, Cell(STATUS[r.status] or r.status, ORDER[r.status] or 9), rank,
        Cell((r.tp and r.status ~= "done") and r.tp or "", r.tp or 0), how },
        tip = r.ability .. ": " .. (r.hu or "") .. (r.desc and ("\n" .. r.desc) or "") }
    end
    out[#out + 1] = Section("pet.train", "Mit taníts a petednek", { { p = ("%s, %d. szint, %d szabad training point. A pet csak olyan rangot tanulhat, " ..
      "amit egy szelídített állattól már elsajátítottál (Beast Training); az új rang visszaadja a régi pontjait."):format(Plain(FamilyHu(tr.family)), pet.level or 0, tr.left),
      muted = true },
      { table = { id = "pet.train", cols = { { "Képesség", 130 }, { "Teendő", 80 }, { "Rang", 60 }, { "TP", 40, "RIGHT" }, { "Hogyan", 0, flex = true } },
        rows = rows } } }, true, #rows)
  elseif pet then
    Add(out, { tips = { { level = "info", text = ("A pet családja (%s) nincs az adatban."):format(tostring(pet.family)) } } })
  end

  if PT.HasData() then
    local best = PT.Best(level, 8)
    local rows = {}
    for _, e in ipairs(best.dps) do rows[#rows + 1] = BeastRow(e, level) end
    out[#out + 1] = Section("pet.best", "Legjobb sebző pet a szintedhez", { { p = "Sebzés = a család szorzója × a támadási sebesség " ..
      "(a normál, 2.0 mp-es pet 1.00×). Classic szabály szerint a pet ütésenként ugyanannyit sebez, ezért a gyorsabb állat több DPS. " ..
      "Elöl a hozzád szintben közeli állatok; ★ ritka.", muted = true },
      { table = { id = "pet.best", cols = BEAST_COLS, rows = rows } } }, true, #rows)
    local tank = {}
    for _, e in ipairs(best.tank) do
      local row = BeastRow(e, level)
      row.cells[4] = Cell(("%.2f×"):format(e.factor), e.factor)
      tank[#tank + 1] = row
    end
    out[#out + 1] = Section("pet.tank", "Legjobb tank pet (elitekhez, sok mobhoz)", { { p = "Strapabírás = a család páncél × élet szorzója.", muted = true },
      { table = { id = "pet.tank", cols = { BEAST_COLS[1], BEAST_COLS[2], BEAST_COLS[3], { "Strapa", 60, "RIGHT" }, BEAST_COLS[5], BEAST_COLS[6] },
        rows = tank } } }, false, #tank)

    local fams = {}
    for name, info in pairs(PT.Families()) do
      local f = PT.FAMILY[name] or {}
      local ab = {}
      for a, rank in pairs(info.abilities) do ab[#ab + 1] = a .. " " .. rank end
      table.sort(ab)
      fams[#fams + 1] = { cells = { Cell(FamilyHu(name), name), Cell(f.dmg and ("%.2f"):format(f.dmg) or "?", f.dmg or 1),
        Cell(f.armor and ("%.2f"):format(f.armor) or "?", f.armor or 1), Cell(f.hp and ("%.2f"):format(f.hp) or "?", f.hp or 1),
        Cell(info.fastest < 200 and Color(HEX.good, ("%.1f mp"):format(info.fastest / 100)) or "2.0 mp", info.fastest),
        f.diet and table.concat(f.diet, ", ") or Muted("?"), f.role or "", table.concat(ab, ", ") },
        tip = (f.role or "") .. "\nKülönleges: " .. (f.sig or "?") .. "\n" .. info.count .. " szelídíthető állat, " .. info.minLevel .. ". szinttől" }
    end
    WA.Model.Stable(fams, function(a, b)
      if a.cells[2][2] ~= b.cells[2][2] then return a.cells[2][2] > b.cells[2][2] end
      return a.cells[5][2] < b.cells[5][2]
    end)
    out[#out + 1] = Section("pet.fam", "Családok (a legerősebb sebzőtől)", { { table = { id = "pet.fam", limit = 20, cols = { { "Család", 170 }, { "Sebzés", 56, "RIGHT" },
      { "Páncél", 56, "RIGHT" }, { "Élet", 50, "RIGHT" }, { "Leggyorsabb", 80, "RIGHT" }, { "Eszik", 120, extra = true },
      { "Mire jó", 0, flex = true }, { "Képességek", 220, extra = true } }, rows = fams } } }, true, #fams)

    local all = {}
    for _, b in ipairs(PT.Beasts()) do
      if b.min > 0 then all[#all + 1] = BeastRow({ beast = b }, nil) end
    end
    out[#out + 1] = Section("pet.all", "Bestiárium: minden szelídíthető állat", { { p = "Keress névre, családra, zónára vagy képességre " ..
      "(például \"Claw 6\", \"Wetlands\", \"Cat\").", muted = true },
      { table = { id = "pet.all", cols = BEAST_COLS, rows = all, limit = 15 } } }, false, #all)

    local abRows = {}
    for name in pairs(PT.ABILITY) do
      for _, r in ipairs(PT.Ranks(name)) do
        abRows[#abRows + 1] = { cells = { name, Cell(r.rank, r.rank), Cell(r.level, r.level), Cell(r.tp, r.tp), r.desc or "" }, tip = PT.ABILITY[name].hu }
      end
    end
    out[#out + 1] = Section("pet.ranks", "Képességek rangonként", { { table = { id = "pet.ranks", cols = { { "Képesség", 130 }, { "Rang", 44, "RIGHT" },
      { "Pet-szint", 64, "RIGHT" }, { "TP", 40, "RIGHT" }, { "Mit csinál (Wowhead)", 0, flex = true } }, rows = abRows, limit = 12 } } }, false, #abRows)
  end
  UI.status = pet and ("%s · %d. szint"):format(pet.name or "pet", pet.level or 0) or "nincs pet"
  return out
end

local function Weapon(w)
  if type(w) ~= "table" or not w.min then return "–" end
  return ("%d–%d / %.1f"):format(w.min, w.max or w.min, w.speed or 0)
end

-- Enchants for what you wear, for your role (Enchant.lua); every class, with or without a damage model.
local function EnchantBlocks(ctx)
  local r = G.EnchantReport(ctx)
  local out = {}
  local cur = WA.charDB and WA.charDB.role or nil
  local function Pick(role)
    return function()
      WA.charDB.role = role
      UI.cache = {}
      UI.Draw()
    end
  end
  out[#out + 1] = { buttons = {
    { label = "Szerep: automatikus", width = 150, active = cur == nil, onClick = Pick(nil) },
    { label = "DPS", width = 70, active = cur == "dps", onClick = Pick("dps") },
    { label = "Tank", width = 70, active = cur == "tank", onClick = Pick("tank") },
    { label = "Gyógyító", width = 90, active = cur == "healer", onClick = Pick("healer") },
  } }
  local how
  if r.useModel then how = "az érték a sebzésmodell DPS-e a jelenlegi tárgyaddal"
  elseif r.profile then how = ("az érték a %s súlya (EP, %s %s)"):format(r.profile.name, WA.Enchant.SIM, r.profile.source)
  else how = "erre a kasztra még nincs sebzésmodell és súlytábla: az enchantok pontozás nélkül nem rangsorolhatók" end
  out[#out + 1] = { p = ("%s: %s. %s."):format(Color(HEX.gold, WA.Enchant.ROLE_HU[r.role]), r.reason, how) .. (r.borrowed and (" " .. Color(HEX.warn, r.borrowed .. ".")) or "") }
  if r.missing then
    out[#out + 1] = { tips = { { level = "warn", text = "Hiányzik az Enchants.lua: node scripts/build-enchants.mjs --install" } } }
    return out, 0
  end
  local rows, n = {}, 0
  for _, s in ipairs(r.slots) do
    for i, b in ipairs(s.best) do
      if i == 1 then n = n + 1 end
      local now = i == 1 and ((s.current or "–") .. " · " .. (s.enchant and Color(HEX.good, "van rajta enchant") or Color(HEX.warn, "nincs enchant"))) or ""
      local value = r.useModel and Gain(b.value) or Color(HEX.good, F1(b.value))
      rows[#rows + 1] = { cells = { Cell(i == 1 and (WA.Model.SLOT_HU[(s.slot:gsub("_[12]$", ""))] or s.slot) or "", s.slot .. i),
        Cell(b.name:gsub("^Enchant ", ""), b.name), Cell(value, b.value), b.effect,
        Cell(b.cost and (Money(b.cost) .. (b.partial and "+?" or "")) or "?", b.cost or math.huge),
        Cell(b.skill .. (b.trainer and "" or Muted(" recept")), b.skill), now },
        tip = b.detail .. (b.partial and "\n(egy reagens ára nem ismert)" or ""), first = i == 1 }
    end
  end
  local detail = State().detail["gear.enchant"]
  local shown = {}
  for _, row in ipairs(rows) do if detail or row.first then shown[#shown + 1] = row end end
  out[#out + 1] = { table = { id = "gear.enchant", cols = { { "Hely", 92 }, { "Enchant", 0, flex = true }, { r.unit, 56, "RIGHT" },
    { "Mit ad", 170 }, { "Reagens", 92, "RIGHT" }, { "Skill", 70, "RIGHT", extra = true }, { "Most", 230, extra = true } },
    rows = shown, empty = "Erre a szerepre egyik viselt tárgyadra sincs pontozható enchant." } }
  if #r.procs > 0 then
    out[#out + 1] = { p = Muted("Proc enchantok, pontozás nélkül (a gyakoriságuk nincs megadva): " .. table.concat(r.procs, ", "):gsub("Enchant ", "")) }
  end
  if r.profile then
    local bits = {}
    for k, v in pairs(r.profile.w) do if v ~= 0 then bits[#bits + 1] = ("%s %s"):format(k, v) end end
    table.sort(bits)
    out[#out + 1] = { p = Muted(("Súlyok (%s, %s): %s. Egységek: crit/hit/haste/dodge/block ratingben (14/10/10/12/5 = 1%%), defense = rating, mhDps = fegyver-DPS."):format(
      r.profile.name, r.profile.source, table.concat(bits, ", "))), muted = true }
  end
  return out, n
end

function UI.pages.gear()
  if not G.Supported() then
    local out = NotSupported("gear", "Felszerelés")
    local blocks, n = EnchantBlocks(nil)
    out[#out + 1] = Section("gear.enchant", "Enchantok a szerepedre", blocks, true, n)
    return out
  end
  local ctx = G.Context()
  local g = WA.Model.GearReport(ctx, 3)
  local sh = g.sheet
  UI.head.gear = { "Felszerelés", "A következő fejlesztés minden helyre: mennyit ad és honnan szerzed" }
  local out = {}
  local dpsCard = { label = "Becsült DPS", value = F1(g.baseline), sub = "buffok nélkül " .. F1(g.unbuffed) .. (g.measuredDps and (" · mért " .. F1(g.measuredDps)) or "") }
  if ctx.class == "HUNTER" then
    out[#out + 1] = { cards = {
      dpsCard,
      { label = "Ranged AP", value = tostring(math.floor((sh.rap or 0) + 0.5)), sub = "távolsági " .. Weapon(sh.ranged) },
      { label = "Crit", value = Pct(sh.crit), sub = "lőszer " .. ((sh.ammo or 0) > 0 and (F1(sh.ammo) .. " DPS") or "nincs") },
      { label = "Hit", value = Pct(sh.hit), sub = (sh.haste or 1) > 1.001 and (("tegez +%d%% sebesség"):format(math.floor((sh.haste - 1) * 100 + 0.5))) or "nincs tegez" },
    } }
  elseif ctx.class == "SHAMAN" then
    out[#out + 1] = { cards = {
      dpsCard,
      { label = "Attack power", value = tostring(math.floor((sh.ap or 0) + 0.5)), sub = "fegyver " .. Weapon(sh.mh) },
      { label = "Crit", value = Pct(sh.crit), sub = "spell crit " .. Pct(sh.spellCrit or 0) },
      { label = "Spell power", value = tostring(math.floor((sh.sp or 0) + 0.5)), sub = "hit " .. Pct(sh.hit) },
    } }
  elseif ctx.class == "WARLOCK" then
    out[#out + 1] = { cards = {
      dpsCard,
      { label = "Spell power", value = tostring(math.floor((sh.sp or 0) + 0.5)), sub = "shadow" },
      { label = "Spell crit", value = Pct(sh.spellCrit or 0), sub = "spell hit " .. Pct(sh.spellHit or 0) },
      { label = "Pálca", value = F1(WA.Warlock.WandDps(sh.wand)) .. " DPS", sub = Weapon(sh.wand) },
    } }
  elseif ctx.class == "WARRIOR" then
    out[#out + 1] = { cards = {
      dpsCard,
      { label = "Attack power", value = tostring(math.floor((sh.ap or 0) + 0.5)), sub = "főkéz " .. Weapon(sh.mh) },
      { label = "Crit", value = Pct(sh.crit), sub = sh.oh and ("balkéz " .. Weapon(sh.oh)) or "nincs második fegyver" },
      { label = "Rage / mp", value = F1(WA.Warrior.WhiteRage(sh, ctx.params)), sub = "a fehér ütésekből (Forever szabály)" },
    } }
  elseif ctx.class == "PALADIN" then
    out[#out + 1] = { cards = {
      dpsCard,
      { label = "Attack power", value = tostring(math.floor((sh.ap or 0) + 0.5)), sub = "fegyver " .. Weapon(sh.mh) },
      { label = "Crit", value = Pct(sh.crit), sub = "hit " .. Pct(sh.hit) },
      { label = "Spell power", value = tostring(math.floor((sh.sp or 0) + 0.5)), sub = "holy: Holy Strike, seal" },
    } }
  elseif ctx.class == "PRIEST" then
    out[#out + 1] = { cards = {
      dpsCard,
      { label = "Spell power", value = tostring(math.floor((sh.sp or 0) + 0.5)),
        sub = ("holy %d, shadow %d"):format(math.floor((sh.spHoly or 0) + 0.5), math.floor((sh.spShadow or 0) + 0.5)) },
      { label = "Spell crit", value = Pct(sh.spellCrit or 0), sub = "spell hit " .. Pct(sh.spellHit or 0) },
      { label = "Pálca", value = F1(WA.Priest.WandDps(sh.wand)) .. " DPS", sub = Weapon(sh.wand) },
    } }
  elseif ctx.class == "MAGE" then
    out[#out + 1] = { cards = {
      dpsCard,
      { label = "Spell power", value = tostring(math.floor((sh.sp or 0) + 0.5)), sub = ctx.params.school == "fire" and "fire (Fireball)" or "frost (Frostbolt)" },
      { label = "Spell crit", value = Pct(sh.spellCrit or 0), sub = "spell hit " .. Pct(sh.spellHit or 0) },
      { label = "Pálca", value = F1(WA.Mage.WandDps(sh.wand)) .. " DPS", sub = Weapon(sh.wand) },
    } }
  elseif ctx.class == "DRUID" then
    out[#out + 1] = { cards = {
      dpsCard,
      { label = ctx.params.cat and "Attack power (Cat)" or "Attack power", value = tostring(math.floor((sh.ap or 0) + 0.5)),
        sub = ctx.params.cat and ("mancs " .. F1(WA.Druid.PawAvg(sh.mh)) .. " DPS") or ("fegyver " .. Weapon(sh.mh)) },
      { label = "Crit", value = Pct(sh.crit), sub = "spell crit " .. Pct(sh.spellCrit or 0) },
      { label = "Spell power", value = tostring(math.floor((sh.sp or 0) + 0.5)), sub = "hit " .. Pct(sh.hit) },
    } }
  else
    out[#out + 1] = { cards = {
      dpsCard,
      { label = "Attack power", value = tostring(sh.ap or 0), sub = "főkéz " .. Weapon(sh.mh) },
      { label = "Crit", value = Pct(sh.crit), sub = "balkéz " .. Weapon(sh.oh) },
      { label = "Hit", value = Pct(sh.hit), sub = "" },
    } }
  end
  if not WowAssistantData then
    out[#out + 1] = { tips = { { level = "warn", text = "Hiányzik a GameData.lua (dungeon loot): node scripts/build-addon-recipes.mjs --install" } } }
  end

  -- the best upgrade for each slot first; the next ones with "Több oszlop"
  local rows = {}
  for _, s in ipairs(g.bySlot) do
    for i, u in ipairs(s.best) do
      rows[#rows + 1] = { cells = { Cell(WA.Model.SLOT_HU[s.slot] or s.slot, s.slot .. i), Cell(Item(u.name, u.quality), u.name),
        Cell(Gain(u.gain), u.gain), u.dungeon .. (u.boss and (" · " .. u.boss) or ""), i == 1 and (s.current or "–") or "",
        Cell(Pct(u.gainPct), u.gainPct), Cell(u.dropPct and Pct(u.dropPct) or "–", u.dropPct or 0) },
        itemId = u.itemId, tip = u.detail .. (u.warning and ("\n" .. u.warning) or ""), first = i == 1 }
    end
  end
  local firsts = {}
  for _, r in ipairs(rows) do if r.first then firsts[#firsts + 1] = r end end
  table.sort(firsts, function(a, b) return (a.cells[3][2] or 0) > (b.cells[3][2] or 0) end)
  local detail = State().detail["gear.best"]
  out[#out + 1] = Section("gear.best", "Legjobb fejlesztések", { { table = { id = "gear.best", cols = { { "Hely", 92 },
    { "Tárgy", 0, flex = true }, { "DPS", 56, "RIGHT" }, { "Honnan", 230 }, { "Most", 150, extra = true }, { "%", 52, "RIGHT", extra = true },
    { "Esés", 52, "RIGHT", extra = true } }, rows = detail and rows or firsts, limit = 10 } } }, true, #firsts)

  local eblocks, en = EnchantBlocks(ctx)
  out[#out + 1] = Section("gear.enchant", "Enchantok a szerepedre", eblocks, true, en)

  local checks, on = {}, 0
  for _, b in ipairs(g.buffs) do
    if b.selected then on = on + 1 end
    checks[#checks + 1] = {
      label = b.name .. " " .. Muted(b.summary or ""), checked = b.selected, disabled = not b.effect,
      onClick = function(v)
        WA.charDB.buffs = WA.charDB.buffs or {}
        WA.charDB.buffs[b.id] = v or nil
        UI.cache = {}
        UI.Draw()
      end,
    }
  end
  out[#out + 1] = Section("gear.buffs", "Buffok és fogyóeszközök a számításban", { { checks = checks, perRow = 2 } }, false, on)

  local drows = {}
  for _, d in ipairs(g.dungeons) do
    local names = {}
    for i = 1, math.min(4, #d.upgrades) do names[i] = Item(d.upgrades[i].name, d.upgrades[i].quality) end
    drows[#drows + 1] = { d.name, d.levels, Cell(Gain(d.gain), d.gain), Cell(d.perRun and Gain(d.perRun) or "–", d.perRun or 0),
      Cell(#d.upgrades, #d.upgrades), table.concat(names, ", ") }
  end
  out[#out + 1] = Section("gear.dungeons", "Dungeonok", { { table = { id = "gear.dungeons", cols = { { "Dungeon", 0, flex = true },
    { "Szint", 60 }, { "Összes DPS", 80, "RIGHT" }, { "Futásonként", 84, "RIGHT" }, { "Tárgy", 50, "RIGHT", extra = true },
    { "Legjobbak", 0, flex = true, extra = true } }, rows = drows } } }, false, #drows)

  if #g.later > 0 then
    local lrows = {}
    for _, u in ipairs(g.later) do
      lrows[#lrows + 1] = { cells = { Cell(u.reqLevel, u.reqLevel), Cell(Item(u.name, u.quality), u.name), WA.Model.SLOT_HU[u.slot] or u.slot,
        Cell(Gain(u.gain), u.gain), u.dungeon .. (u.boss and (" · " .. u.boss) or "") }, itemId = u.itemId, tip = u.detail }
    end
    out[#out + 1] = Section("gear.later", "Pár szinttel később", { { table = { id = "gear.later", cols = { { "Szint", 50 },
      { "Tárgy", 0, flex = true }, { "Hely", 100 }, { "DPS", 56, "RIGHT" }, { "Honnan", 240, extra = true } }, rows = lrows } } }, false, #lrows)
  end
  local notes = {}
  for _, n in ipairs(g.params.notes or {}) do notes[#notes + 1] = { p = n, muted = true } end
  if #notes > 0 then out[#out + 1] = Section("gear.model", "Hogyan számol a modell", notes, false) end
  UI.status = ("%d harc kalibrálja a modellt"):format(ctx.combat and ctx.combat.fights or 0)
  return out
end

function UI.pages.prof()
  local out = {}
  UI.head.prof = { "Mesterségek", ("A legolcsóbb út %d-ig, bevásárlólistával"):format(UI.target) }
  out[#out + 1] = { buttons = {
    { label = "Cél: 225", width = 96, active = UI.target == 225, onClick = function() UI.target = 225 UI.cache.prof = nil UI.Draw() end },
    { label = "Cél: 300", width = 96, active = UI.target == 300, onClick = function() UI.target = 300 UI.cache.prof = nil UI.Draw() end },
  } }
  if not WowAssistantRecipes then
    out[#out + 1] = { tips = { { level = "warn", text = "Hiányzik a receptadat (Recipes.lua): node scripts/build-addon-recipes.mjs --install" } } }
    return out
  end
  local routes = G.Routes(UI.target)
  if #routes == 0 then
    out[#out + 1] = { empty = { "Nincs gyártó szakmád", "Vagy a kliens még nem adta meg a szintjét: nyisd meg egyszer a szakma ablakát." } }
    return out
  end
  local market = WowAssistantDB and WowAssistantDB.market
  local cards = {}
  for i, r in ipairs(routes) do
    if i <= 4 then
      cards[#cards + 1] = { label = r.profession, value = ("%d → %d"):format(r.skill, r.target),
        sub = Money(r.totalMats + r.totalTraining) .. " összesen" }
    end
  end
  out[#out + 1] = { cards = cards }
  for i, r in ipairs(routes) do
    local blocks = {}
    blocks[#blocks + 1] = { p = ("Alapanyag %s (ebből már nálad: %s) · tanítás %s · a vendor visszaad %s"):format(Money(r.totalMats), Money(r.ownedValue),
      Money(r.totalTraining), Money(r.totalVendorBack)) }
    if r.unreachableFrom then
      blocks[#blocks + 1] = { tips = { { level = "warn", text = ("%d fölött nincs ismert recept (most max %d)."):format(r.unreachableFrom, r.cap) } } }
    end
    for _, n in ipairs(r.notes or {}) do blocks[#blocks + 1] = { p = n, muted = true } end
    local rows = {}
    for _, s in ipairs(r.steps) do
      local reag = {}
      for _, rg in ipairs(s.reagents) do reag[#reag + 1] = rg.qty .. "× " .. rg.name end
      rows[#rows + 1] = { cells = { Cell(s.from .. " → " .. s.to, s.from), s.recipe .. (s.known and "" or Color(HEX.warn, " (tanulni)")), Cell(s.crafts, s.crafts),
        Cell(Money(s.matsCost), s.matsCost), Cell(s.trainingCost > 0 and Money(s.trainingCost) or "", s.trainingCost),
        Cell(s.vendorBack > 0 and Money(s.vendorBack) or "", s.vendorBack) }, tip = table.concat(reag, ", ") }
    end
    blocks[#blocks + 1] = { table = { id = "prof.steps." .. r.professionId, cols = { { "Skill", 80 }, { "Recept", 0, flex = true },
      { "Db", 44, "RIGHT" }, { "Alapanyag", 92, "RIGHT" }, { "Tanítás", 92, "RIGHT", extra = true }, { "Vendor vissza", 100, "RIGHT", extra = true } },
      rows = rows, limit = 12 } }
    out[#out + 1] = Section("prof.route." .. r.professionId, ("%s: %d → %d"):format(r.profession, r.skill, r.target), blocks, i == 1, #r.steps)
    local shop = {}
    for _, x in ipairs(r.shopping) do
      shop[#shop + 1] = { cells = { Cell(x.name, x.name), Cell(x.qty, x.qty), Cell(Money(x.total), x.total),
        Cell(x.owned > 0 and x.owned or "", x.owned), Cell(Money(x.unit), x.unit or 0),
        x.source == "vendor" and "kereskedő" or (x.source == "AH" and "AH" or Color(HEX.warn, "nincs ár")) }, itemId = x.itemId }
    end
    out[#out + 1] = Section("prof.shop." .. r.professionId, "Bevásárlólista – " .. r.profession, { { table = { id = "prof.shop." .. r.professionId,
      cols = { { "Alapanyag", 0, flex = true }, { "Kell", 56, "RIGHT" }, { "Összesen", 92, "RIGHT" }, { "Megvan", 64, "RIGHT", extra = true },
      { "Egységár", 92, "RIGHT", extra = true }, { "Honnan", 96, extra = true } }, rows = shop, limit = 12 } } }, false, #shop)
  end
  UI.status = ("Árak: %s"):format(market and market.at and ("AH-szken " .. date("%m.%d %H:%M", market.at)) or "nincs AH-szken (/wa ah)")
  return out
end

---------------------------------------------------------------------------
-- Talentek (WA-034): the trees, a plan, and each talent's worth with the gear you have
---------------------------------------------------------------------------
local function Same(a, b)
  for k, v in pairs(a) do if (b[k] or 0) ~= v then return false end end
  for k, v in pairs(b) do if (a[k] or 0) ~= v then return false end end
  return true
end
local function CopyRanks(t) local o = {} for k, v in pairs(t) do if v > 0 then o[k] = v end end return o end

-- The plan being drawn, per character (kept over a /reload): while it is the same as your
-- talents, it follows them when you learn a new one.
local draftLocal
local function Draft(class, cur)
  local c = WA.charDB
  local st = c and c.talentDraft or draftLocal
  if not st or st.class ~= class then
    st = { class = class, ranks = CopyRanks(cur), seen = CopyRanks(cur) }
  elseif st.seen and Same(st.ranks, st.seen) and not Same(st.ranks, cur) then
    st.ranks, st.saved = CopyRanks(cur), nil
  end
  st.seen = CopyRanks(cur)
  if c then c.talentDraft = st else draftLocal = st end
  return st
end

local function TalentRedraw(msg)
  UI.talentMsg = msg
  UI.cache.talent = nil
  UI.Draw()
end
UI.TalentRedraw = TalentRedraw

local function S2(n) return WA.Talent.Signed(n) end

function UI.pages.talent()
  local T = WA.Talent
  local class = G.Class()
  UI.head.talent = { "Talentek", "A Forever talentfái, a pontjaid és egy terv, minden talent értéke a mostani gearrel" }
  local tree = T.ReadTree()
  local pt = T.PlanTrees(class, tree)
  if #pt.tabs == 0 then
    return { { empty = { "Nincs talentfa", "A játék nem adott talentfát, és a talentadat (TalentData.lua) sincs meg: node scripts/build-talents.mjs --install" } } }
  end
  local total = T.PlanPoints(tree)
  local cur = T.PlanCurrent(pt)
  local st = Draft(class, cur)
  local ranks = st.ranks
  local spent, spentNow = T.PlanSpent(pt, ranks), T.PlanSpent(pt, cur)
  local free = math.max(0, total - spent)

  -- the plan's worth (the model with your gear): the whole plan, each change, each talent
  local value, err
  if G.Supported() and WA.Model and WA.Model.Context then
    local ok, v = pcall(function() return T.PlanValue(class, G.ModelInput(), WA.Model.Context, ranks, free) end)
    if ok then value = v else err = tostring(v) end
  end
  local rows = {}
  for _, row in ipairs(value and value.values and value.values.rows or {}) do rows[row.name] = row end
  local best = value and value.values and value.values.best
  if free <= 0 then best = nil end

  local out = {}
  if UI.talentMsg then Add(out, { tips = { { level = UI.talentMsg.level, title = UI.talentMsg.title, text = UI.talentMsg.text } } }) end
  local plans = T.PlanList()
  Add(out, { cards = {
    { label = "Pontok a tervben", value = ("%d / %d"):format(spent, total), sub = ("%d szabad · most %d elköltve"):format(free, spentNow),
      tip = tree.unspent and "A pontjaid: az elköltött és a szabad pontok (a játék adja)." or "A pontjaid: szint − 9 (az első pont a 10. szinten)." },
    { label = "A terv DPS-e", value = value and T.F2(value.plan) or "–",
      sub = value and ("%s (%s%%) a mostanihoz képest"):format(S2(value.diff), S2(value.diffPct)) or (G.Supported() and "nem számolható" or "ehhez a kaszthoz nincs modell"),
      tip = value and ("A modell DPS-e a mostani gearrel: most %s, a tervvel %s."):format(T.F2(value.now), T.F2(value.plan)) or err },
    { label = "Legjobb következő pont", value = best and best.name or "–",
      sub = best and ("%s DPS (%s%%)"):format(S2(best.next), S2(best.nextPct)) or (free <= 0 and "nincs szabad pont a tervben" or "egy nyitott talent sem ad most DPS-t"),
      tip = best and best.nextSource and ("Forrás: " .. best.nextSource) or nil },
    { label = "Mentett tervek", value = tostring(#plans), sub = st.saved and plans[st.saved] and ("betöltve: " .. plans[st.saved].name) or "a mostani terv nincs mentve" },
  } })

  -- what to do with the plan
  Add(out, { buttons = {
    { label = "Mostani talentek", width = 130, onClick = function() st.ranks, st.saved = CopyRanks(cur), nil TalentRedraw() end },
    { label = "Üres terv", width = 100, onClick = function() st.ranks, st.saved = {}, nil TalentRedraw() end },
    { label = "Mentés", width = 90, onClick = function()
      local name = st.saved and plans[st.saved] and plans[st.saved].name or (#plans + 1) .. ". terv"
      st.saved = T.PlanSave(name, st.ranks)
      TalentRedraw({ level = "good", title = "Mentve:", text = name })
    end },
    { label = "Mentés újként", width = 120, onClick = function()
      local name = (#plans + 1) .. ". terv"
      st.saved = T.PlanSave(name, st.ranks)
      TalentRedraw({ level = "good", title = "Mentve:", text = name })
    end },
    { label = "Törlés", width = 80, onClick = function()
      if not (st.saved and plans[st.saved]) then return TalentRedraw({ level = "warn", title = "Nincs betöltött terv,", text = "nincs mit törölni." }) end
      local name = plans[st.saved].name
      T.PlanDelete(st.saved)
      st.saved = nil
      TalentRedraw({ level = "info", title = "Törölve:", text = name })
    end },
  } })
  if #plans > 0 then
    local line = {}
    for i, p in ipairs(plans) do
      line[#line + 1] = { label = p.name, width = 90, active = st.saved == i, onClick = function()
        st.ranks, st.saved = CopyRanks(p.ranks), i
        TalentRedraw()
      end }
      if #line == 7 or i == #plans then Add(out, { buttons = line }) line = {} end
    end
  end

  -- the trees
  local function Open(name) return T.PlanOpen(pt, ranks, name, total) end
  local function Why(name)
    local _, why = T.PlanAdd(pt, ranks, name, total)
    return why
  end
  local function Tip(x, tt)
    local r, now = ranks[x.name] or 0, cur[x.name] or 0
    local usedGame = pt.client and x.index and tt.SetTalent and pcall(tt.SetTalent, tt, x.tab, x.index)
    if not usedGame then
      tt:AddLine(x.name, 1, 0.82, 0)
      tt:AddLine(("Rang: %d/%d"):format(r, x.max), 1, 1, 1)
      local d = x.data
      if d and d.desc then
        tt:AddLine(WA.Fix(d.desc[math.max(1, math.min(r, x.max))] or ""), 1, 0.82, 0.5, true)
        if r > 0 and r < x.max and d.desc[r + 1] then
          tt:AddLine(" ")
          tt:AddLine(WA.Fix("Következő rang:"), 1, 1, 1)
          tt:AddLine(WA.Fix(d.desc[r + 1]), 1, 0.82, 0.5, true)
        end
      end
    end
    tt:AddLine(" ")
    if r ~= now then tt:AddLine(WA.Fix(("Terv: %d/%d (most %d/%d)"):format(r, x.max, now, x.max)), 0.4, 0.8, 1) end
    if r < x.max and not Open(x.name) then
      local why = Why(x.name)
      if why then tt:AddLine(WA.Fix("Nem tehető bele: " .. why), 1, 0.35, 0.35, true) end
    end
    tt:AddLine(WA.Fix("Waystone, a mostani gearrel:"), 1, 0.82, 0)
    local row = rows[x.name]
    if not value then
      tt:AddLine(WA.Fix(G.Supported() and ("A modell most nem számol: " .. tostring(err)) or "Ehhez a kaszthoz még nincs DPS-modell."), 0.62, 0.57, 0.48, true)
    elseif row and row.counted then
      if row.now then tt:AddLine(WA.Fix(("A tervben lévő %d rang: %s DPS (%s%%)"):format(r, S2(row.now), S2(row.nowPct))), 1, 1, 1) end
      if row.next then tt:AddLine(WA.Fix(("A következő pont: %s DPS (%s%%)"):format(S2(row.next), S2(row.nextPct))), 1, 1, 1) end
      for _, wt in ipairs(row.weights or {}) do
        tt:AddLine(WA.Fix(("Miatta %s: %s → %s DPS / %d"):format(wt.label, T.F2(wt.without), T.F2(wt.with), wt.per)), 0.8, 0.8, 0.8)
      end
      if row.note then tt:AddLine(WA.Fix(row.note), 1, 0.6, 0.2, true) end
      local src = row.nextSource or row.source
      if src then tt:AddLine(WA.Fix("Forrás: " .. src), 0.62, 0.57, 0.48, true) end
    elseif row and row.reason then
      tt:AddLine(WA.Fix("Érték nélkül: " .. row.reason), 0.62, 0.57, 0.48, true)
    else
      local e = (T.EFFECTS[class] or {})[x.name]
      if e and e.reason then tt:AddLine(WA.Fix("Érték nélkül: " .. e.reason), 0.62, 0.57, 0.48, true)
      else tt:AddLine(WA.Fix("Az értékét akkor számolja, ha a tervben beletehetsz pontot."), 0.62, 0.57, 0.48, true) end
    end
    if best and best.name == x.name then tt:AddLine(WA.Fix("Ez most a legtöbbet érő következő pont."), 0.37, 0.88, 0.37) end
    tt:AddLine(WA.Fix("Bal klikk: +1 pont a tervbe · jobb klikk: −1 pont"), 0.62, 0.57, 0.48)
  end
  local function Click(x, button)
    local fn = button == "RightButton" and T.PlanRemove or T.PlanAdd
    local new, why = fn(pt, st.ranks, x.name, total)
    if not new then return TalentRedraw({ level = "warn", title = button == "RightButton" and "Nem vehető ki:" or "Nem tehető bele:", text = why }) end
    st.ranks = new
    TalentRedraw()
  end
  Add(out, { talents = { tabs = pt.tabs, ranks = ranks, cur = cur, open = Open, best = best and best.name, tip = Tip, onClick = Click } })
  Add(out, { p = "Bal klikk: pont a tervbe, jobb klikk: pont ki. A terv csak terv: a talentet a játék talent-ablakában te tanulod meg. Kék rang: a terv itt eltér a mostanitól; arany keret: a legtöbbet érő következő pont.", muted = true })

  -- the plan against now, change by change
  local diffRows = {}
  for _, c in ipairs(value and value.changes or {}) do
    diffRows[#diffRows + 1] = { cells = {
      c.name, Cell(("%d → %d"):format(c.from, c.to), c.to - c.from),
      c.value and Cell(S2(c.value), c.value) or Muted("–"),
      c.counted and (c.source or "") or Muted(c.reason or ""),
    }, tip = c.source or c.reason }
  end
  local diffBlocks = {}
  if value then
    Add(diffBlocks, { p = ("A modell DPS-e: most %s, a tervvel %s, a különbség %s (%s%%). Soronként: az az egy változás a mostanihoz képest; együtt eltérhetnek az összegüktől.")
      :format(T.F2(value.now), T.F2(value.plan), S2(value.diff), S2(value.diffPct)) })
  elseif err then
    Add(diffBlocks, { p = Color(HEX.bad, "A terv értéke most nem számolható: " .. err) })
  end
  Add(diffBlocks, { table = { id = "talent.diff", cols = { { "Talent", 0, flex = true }, { "Rang", 70, "RIGHT" }, { "DPS", 70, "RIGHT" }, { "Forrás", 260 } },
    rows = diffRows, empty = "A terv ugyanaz, mint a mostani talentjeid.", limit = 12 } })
  Add(out, Section("talent.diff", "A terv a mostanihoz képest", diffBlocks, true, #diffRows))

  -- sharing
  Add(out, Section("talent.share", "Megosztás szövegként", {
    { p = "Másold ki a szöveget (kattints bele, Ctrl+C), vagy illessz be egy másik tervet, és nyomd meg a Betöltést.", muted = true },
    { edit = { text = T.PlanExport(class, pt, ranks), button = "Betöltés", onEnter = function(text)
      local new, why = T.PlanImport(class, pt, text, total)
      if not new then return TalentRedraw({ level = "warn", title = "Nem tölthető be:", text = why }) end
      st.ranks, st.saved = new, nil
      TalentRedraw({ level = "good", title = "Betöltve:", text = ("%d pont"):format(T.PlanSpent(pt, new)) })
    end } },
  }, false))
  UI.talentMsg = nil
  UI.status = WowAssistantTalents and ("Talentadat: Wowhead Forever, %s"):format(WowAssistantTalents.fetched or "?") or "nincs talentadat"
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

WA.Command("plan", function() UI.Show("plan") end, "/wa – főablak · /wa plan | combat | gear | prof | pet – egy oldala")
WA.Command("combat", function() UI.Show("combat") end)
WA.Command("harc", function() UI.Show("combat") end) -- old name
WA.Command("gear", function() UI.Show("gear") end)
WA.Command("prof", function() UI.Show("prof") end)
WA.Command("pet", function() UI.Show("pet") end)
WA.Command("talentek", function() UI.Show("talent") end, "/wa talentek – a talent-kalkulátor: a fáid, egy terv és minden talent értéke")
