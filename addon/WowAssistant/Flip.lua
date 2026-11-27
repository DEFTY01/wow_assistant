-- Waystone: auction house → vendor.
--
-- Auctions whose buyout is below what a merchant pays for the same items. Buying one and selling
-- it to any merchant is pure profit: the buyer pays no auction house fee, and the merchant pays the
-- item's full sell price.
--   * The listings come from the full auction house scan (/wa ah, Exporter.lua): every auction is
--     compared with the merchant price the client itself reports (GetItemInfo), never an estimate.
--     Items the client has not loaded yet are loaded after the scan and checked then.
--   * Your own auctions are left out: you cannot buy them.
--   * Before buying, the item is searched again on the auction house, so only listings that are
--     still there, at that price, are bought. Every purchase is one click of yours.
--   * What you bought this way is remembered; at a merchant one button sells exactly those.
--
-- /wa flip opens the window; at the auction house there is a button for it too.

local _, WA = ...
local L = WA.L
local F = {}
WA.Flip = F

local ROWS = 12
local ROW_H = 20
local W = 720
local RESOLVE_TRIES = 4

local function Print(msg) WA.Print(msg) end

local frame, selected, offset = nil, nil, 0 -- the window, the item shown in it, its scroll

local function DB()
  WA.db.flip = WA.db.flip or {}
  local d = WA.db.flip
  d.items = d.items or {}
  d.bought = d.bought or {}
  d.stats = d.stats or { spent = 0, earned = 0, buys = 0 }
  return d
end

-- What a merchant pays for one, from the client; nil while the item is not loaded, 0 when no
-- merchant buys it. A link gives the exact variant (random suffix items).
local function SellOf(idOrLink)
  local sell = select(11, GetItemInfo(idOrLink))
  return sell
end

local function ItemName(id)
  local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or GetItemInfo(id)
  return name or ("Item #" .. id)
end

local function Short(c)
  if not c then return "|cff888888–|r" end
  local neg = c < 0
  c = math.floor(math.abs(c) + 0.5)
  local g, s, k = math.floor(c / 10000), math.floor(c % 10000 / 100), c % 100
  local t
  if g > 0 then t = ("%d|cffffd700g|r %02d|cffc7c7cfs|r"):format(g, s)
  elseif s > 0 then t = ("%d|cffc7c7cfs|r %02d|cffeda55fc|r"):format(s, k)
  else t = ("%d|cffeda55fc|r"):format(k) end
  return neg and ("|cffff5050-|r" .. t) or t
end
F.Short = Short

local function AHOpen() return AuctionHouseFrame and AuctionHouseFrame:IsShown() end

local function MyName() return UnitName("player") end
local function IsMine(owner)
  if not owner or owner == "" then return false end
  return (owner:match("^[^-]+") or owner) == MyName()
end
F.IsMine = IsMine

---------------------------------------------------------------------------
-- collecting from the full scan
---------------------------------------------------------------------------
local scan

-- Listings are flat: buyout, count, buyout, count, ...
local function Keep(list, buyout, count)
  list[#list + 1] = buyout
  list[#list + 1] = count
end

function F.Begin()
  scan = { items = {}, unknown = {}, sell = {}, auctions = 0, own = 0 }
end

-- One auction of the full scan. owner may be nil (the client did not send it).
function F.Add(itemID, buyout, count, owner)
  if not scan or not itemID or not buyout or buyout <= 0 then return end
  count = (count and count > 0) and count or 1
  scan.auctions = scan.auctions + 1
  if IsMine(owner) then scan.own = scan.own + 1 return end
  local sell = scan.sell[itemID]
  if sell == nil then
    sell = SellOf(itemID) or false
    scan.sell[itemID] = sell
    if sell == false and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
  end
  if sell == false then
    local u = scan.unknown[itemID]
    if not u then u = {} scan.unknown[itemID] = u end
    Keep(u, buyout, count)
  elseif sell > 0 and buyout < sell * count then
    local list = scan.items[itemID]
    if not list then list = {} scan.items[itemID] = list end
    Keep(list, buyout, count)
  end
end

-- Cheapest per item first.
local function SortListings(list)
  local pairsList = {}
  for i = 1, #list, 2 do pairsList[#pairsList + 1] = { list[i], list[i + 1] } end
  table.sort(pairsList, function(a, b) return a[1] / a[2] < b[1] / b[2] end)
  local out = {}
  for _, p in ipairs(pairsList) do Keep(out, p[1], p[2]) end
  return out
end

local function Store(at, unresolved)
  local d = DB()
  d.items, d.at, d.auctions, d.own, d.unresolved = {}, at, scan.auctions, scan.own, unresolved
  for id, list in pairs(scan.items) do
    d.items[id] = { sell = scan.sell[id], l = SortListings(list) }
  end
  scan = nil
  local rows, total = F.List()
  Print((L"AH → vendor: %d items below the merchant price, %s profit in total. /wa flip"):format(#rows, Short(total)))
  if F.Refresh then F.Refresh() end
end

-- Items the client had not loaded: ask for them, look again a few times, then store.
local function Resolve(at, tries)
  if not scan then return end
  local left = 0
  for id, list in pairs(scan.unknown) do
    local sell = SellOf(id)
    if sell then
      scan.sell[id] = sell
      scan.unknown[id] = nil
      if sell > 0 then
        for i = 1, #list, 2 do
          if list[i] < sell * list[i + 1] then
            local l = scan.items[id]
            if not l then l = {} scan.items[id] = l end
            Keep(l, list[i], list[i + 1])
          end
        end
      end
    else
      left = left + 1
    end
  end
  if left > 0 and tries < RESOLVE_TRIES then
    C_Timer.After(3, function() Resolve(at, tries + 1) end)
    return
  end
  Store(at, left)
end

function F.Finish(at)
  if not scan then return end
  Resolve(at or time(), 0)
end

---------------------------------------------------------------------------
-- the list
---------------------------------------------------------------------------
-- rows: { id, name, sell, n (auctions), units, cost, value, profit }, best first; total profit.
function F.List()
  local rows, total = {}, 0
  local d = WA.db and WA.db.flip
  if not d or not d.items then return rows, 0 end
  for id, e in pairs(d.items) do
    local units, cost = 0, 0
    for i = 1, #e.l, 2 do
      cost, units = cost + e.l[i], units + e.l[i + 1]
    end
    if units > 0 then
      local value = e.sell * units
      local profit = value - cost
      if profit > 0 then
        rows[#rows + 1] = { id = id, name = ItemName(id), sell = e.sell, n = math.floor(#e.l / 2), units = units, cost = cost,
          value = value, profit = profit, live = e.live }
        total = total + profit
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.profit == b.profit then return a.id < b.id end
    return a.profit > b.profit
  end)
  return rows, total
end

---------------------------------------------------------------------------
-- live check and buying
---------------------------------------------------------------------------
-- state.phase: nil | "browse" | "search" | "ready" | "buying" | "confirm"
local state = {}
F.state = state

local function Sorts()
  local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
  return { { sortOrder = order, reverseSort = false } }
end

local function Ready()
  local AH = C_AuctionHouse
  return not (AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady())
end

local function SetLive(id, kind, listings)
  local d = DB()
  local sell = state.sell
  if #listings == 0 then
    d.items[id] = nil
  else
    d.items[id] = { sell = sell, l = listings, live = time() }
  end
  state.kind, state.phase = kind, "ready"
  if F.Refresh then F.Refresh() end
end

local function SearchKey(key)
  state.key = key
  state.phase = "search"
  local ok = pcall(C_AuctionHouse.SendSearchQuery, key, Sorts(), true)
  if not ok then state.phase = nil end
end

-- Search the item again; the results replace what the scan saw.
function F.Check(id)
  if not AHOpen() then Print(L"Open the auction house for live prices.") return end
  if not Ready() then
    -- asked again when the auction house is ready (AUCTION_HOUSE_THROTTLED_SYSTEM_READY)
    state.retry = id
    return
  end
  state.retry = nil
  selected = id
  state.id, state.kind, state.items, state.commodity, state.keys = id, nil, {}, nil, nil
  state.sell = SellOf(id) or (DB().items[id] and DB().items[id].sell)
  local equipLoc = select(4, GetItemInfoInstant(id))
  if equipLoc and equipLoc ~= "" and C_AuctionHouse.SendBrowseQuery then
    -- gear: the search needs the exact item key (item level, random suffix), so browse by name first
    state.phase = "browse"
    pcall(C_AuctionHouse.SendBrowseQuery, { searchString = ItemName(id), sorts = Sorts(), filters = {}, itemClassFilters = {} })
  else
    SearchKey(C_AuctionHouse.MakeItemKey(id))
  end
  if F.Refresh then F.Refresh() end
end

local function OnBrowse()
  if state.phase ~= "browse" then return end
  local keys = {}
  for _, r in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
    if r.itemKey and r.itemKey.itemID == state.id then keys[#keys + 1] = r.itemKey end
  end
  if #keys == 0 then return SetLive(state.id, "item", {}) end
  state.keys, state.keyIndex = keys, 1
  SearchKey(keys[1])
end

-- Gear and other non-stackable items: every auction separately.
local function OnItemResults(itemKey)
  if state.phase ~= "search" or not itemKey or itemKey.itemID ~= state.id then return end
  local AH = C_AuctionHouse
  for i = 1, AH.GetNumItemSearchResults(itemKey) or 0 do
    local r = AH.GetItemSearchResultInfo(itemKey, i)
    local qty = r and r.quantity or 1
    local buyout = r and r.buyoutAmount
    if buyout and buyout > 0 and not r.containsOwnerItem then
      local sell = (r.itemLink and SellOf(r.itemLink)) or state.sell
      if sell and sell > 0 and buyout < sell * qty then
        state.items[#state.items + 1] = { auctionID = r.auctionID, buyout = buyout, qty = qty, sell = sell }
      end
    end
  end
  if state.keys and state.keyIndex < #state.keys then
    state.keyIndex = state.keyIndex + 1
    SearchKey(state.keys[state.keyIndex])
    return
  end
  table.sort(state.items, function(a, b) return a.buyout / a.qty < b.buyout / b.qty end)
  local flat = {}
  for _, x in ipairs(state.items) do Keep(flat, x.buyout, x.qty) end
  SetLive(state.id, "item", flat)
end

-- Stackable items: the units below the merchant price, cheapest first.
local function OnCommodityResults(itemID)
  if state.phase ~= "search" or itemID ~= state.id then return end
  local AH = C_AuctionHouse
  local sell = state.sell
  local flat, units = {}, 0
  for i = 1, AH.GetNumCommoditySearchResults(itemID) or 0 do
    local r = AH.GetCommoditySearchResultInfo(itemID, i)
    if r and r.unitPrice and sell and r.unitPrice < sell then
      local qty = (r.quantity or 0) - (r.numOwnerItems or 0)
      if qty > 0 then
        Keep(flat, r.unitPrice * qty, qty)
        units = units + qty
      end
    end
  end
  state.units = units
  SetLive(itemID, "commodity", flat)
end

local AfterPurchase

-- What one click buys now: { cost, value, units, afford } or nil.
function F.NextBuy()
  if state.phase ~= "ready" or not state.id then return nil end
  local money = GetMoney()
  if state.kind == "item" then
    local x = state.items[1]
    if not x then return nil end
    return { cost = x.buyout, value = x.sell * x.qty, units = x.qty, afford = x.buyout <= money }
  elseif state.kind == "commodity" then
    local e = DB().items[state.id]
    if not e then return nil end
    -- as many of the cheap units as the money covers
    local units, cost = 0, 0
    for i = 1, #e.l, 2 do
      local unit = e.l[i] / e.l[i + 1]
      local n = math.min(e.l[i + 1], math.floor((money - cost) / unit))
      if n <= 0 then break end
      units, cost = units + n, cost + unit * n
      if n < e.l[i + 1] then break end
    end
    if units == 0 then return { cost = 0, value = 0, units = 0, afford = false } end
    return { cost = cost, value = e.sell * units, units = units, afford = true }
  end
end

local function Bought(id, units, cost, value)
  local d = DB()
  d.bought[id] = (d.bought[id] or 0) + units
  d.stats.spent = d.stats.spent + cost
  d.stats.buys = d.stats.buys + 1
  Print((L"Bought %d × %s for %s; a merchant pays %s (+%s)."):format(units, ItemName(id), Short(cost), Short(value), Short(value - cost)))
end

-- One click: buy the cheapest auction (gear), or start / confirm the purchase of the cheap units.
function F.Buy()
  local AH = C_AuctionHouse
  if not AHOpen() then return end
  if state.phase == "confirm" then
    local p = state.pending
    if p and AH.ConfirmCommoditiesPurchase then
      state.phase = "buying"
      AH.ConfirmCommoditiesPurchase(p.id, p.units)
    end
    return
  end
  local nb = F.NextBuy()
  if not nb or not nb.afford or nb.units == 0 then return end
  if nb.cost >= nb.value then return end -- never buy what does not pay
  if state.kind == "item" then
    local x = state.items[1]
    if not AH.PlaceBid then Print(L"This client cannot buy from an addon.") return end
    state.phase = "buying"
    local p = { id = state.id, auctionID = x.auctionID, units = x.qty, cost = x.buyout, value = x.sell * x.qty }
    state.pending = p
    AH.PlaceBid(x.auctionID, x.buyout)
    -- no answer at all: look again instead of waiting forever
    C_Timer.After(8, function()
      if state.pending == p and state.phase == "buying" then
        Print(L"No answer from the auction house; checking the item again.")
        AfterPurchase(false)
      end
    end)
  else
    if not AH.StartCommoditiesPurchase then Print(L"This client cannot buy from an addon.") return end
    state.phase = "buying"
    state.pending = { id = state.id, units = nb.units, cost = nb.cost, value = nb.value }
    AH.StartCommoditiesPurchase(state.id, nb.units)
  end
  if F.Refresh then F.Refresh() end
end

-- The game's final price for the units: confirm only while it still pays.
local function OnCommodityPrice(unitPrice, totalPrice)
  local p = state.pending
  if state.phase ~= "buying" or not p or state.kind ~= "commodity" then return end
  if totalPrice and totalPrice < p.value then
    p.cost = totalPrice
    state.phase = "confirm"
  else
    if C_AuctionHouse.CancelCommoditiesPurchase then C_AuctionHouse.CancelCommoditiesPurchase() end
    Print(L"The price changed and it no longer pays: nothing was bought.")
    state.phase, state.pending = nil, nil
    F.Check(p.id)
  end
  if F.Refresh then F.Refresh() end
end

function AfterPurchase(ok)
  local p = state.pending
  state.pending = nil
  if ok and p then Bought(p.id, p.units, p.cost, p.value) end
  state.phase = nil
  if p then F.Check(p.id) end
end

---------------------------------------------------------------------------
-- selling at a merchant
---------------------------------------------------------------------------
-- Stacks in the bags that are wholly bought this way: { bag, slot, id, count }.
local function SellableStacks()
  local d = DB()
  local left = {}
  for id, n in pairs(d.bought) do left[id] = n end
  local list = {}
  local C = C_Container
  if not C or not C.GetContainerNumSlots then return list end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, C.GetContainerNumSlots(bag) or 0 do
      local info = C.GetContainerItemInfo(bag, slot)
      local id = info and info.itemID
      local count = info and info.stackCount or 0
      if id and left[id] and left[id] >= count and not info.isLocked then
        left[id] = left[id] - count
        list[#list + 1] = { bag = bag, slot = slot, id = id, count = count }
      end
    end
  end
  return list
end
F.SellableStacks = SellableStacks

function F.SellAll()
  if not (MerchantFrame and MerchantFrame:IsShown()) then return end
  local d = DB()
  local earned, n = 0, 0
  for _, s in ipairs(SellableStacks()) do
    if n >= 12 then break end -- the buyback tab holds 12: a mistake stays recoverable
    local sell = SellOf(s.id) or 0
    C_Container.UseContainerItem(s.bag, s.slot)
    d.bought[s.id] = d.bought[s.id] - s.count
    if d.bought[s.id] <= 0 then d.bought[s.id] = nil end
    earned, n = earned + sell * s.count, n + 1
  end
  d.stats.earned = d.stats.earned + earned
  if n > 0 then Print((L"Sold %d stacks bought on the AH for %s."):format(n, Short(earned))) end
  if F.UpdateMerchant then F.UpdateMerchant() end
end

---------------------------------------------------------------------------
-- window
---------------------------------------------------------------------------
local COLS = WA.LR {
  { L"Item", 230, "LEFT", L"The item, and how many auctions of it are below the merchant price." },
  { L"Units", 50, "RIGHT", L"How many items those auctions hold." },
  { L"Cost", 90, "RIGHT", L"Their buyouts together. Buying on the AH has no fee." },
  { L"Merchant pays", 100, "RIGHT", L"The merchant price the client reports, for all of them." },
  { L"Profit", 90, "RIGHT", L"Merchant price minus cost." },
  { L"Seen", 80, "RIGHT", L"When the listings were seen: in the full scan, or live (checked again)." },
}

local rows, total = {}, 0

local function Build()
  local St = WA.Style
  local f = St.Window("WowAssistantFlipFrame", W, 0, L"AH → vendor")
  local inset, y0 = f.inset, -f.top
  f:SetHeight(f.top + 96 + ROWS * ROW_H + 150)

  f.cards = {}
  local cw = math.floor((W - 2 * inset - 20) / 3)
  for i = 1, 3 do
    local c = CreateFrame("Frame", nil, f, "BackdropTemplate")
    St.Panel(c, St.C.card, St.C.edge, 0.4)
    c:SetSize(cw, 56)
    c:SetPoint("TOPLEFT", inset + (i - 1) * (cw + 10), y0)
    c.label = c:CreateFontString(nil, "OVERLAY", "WowAssistantFontDisableSmall")
    c.label:SetPoint("TOPLEFT", 10, -7)
    c.value = c:CreateFontString(nil, "OVERLAY", "WowAssistantFontHeader")
    c.value:SetPoint("TOPLEFT", c.label, "BOTTOMLEFT", 0, -4)
    c.value:SetPoint("RIGHT", -8, 0)
    c.value:SetJustifyH("LEFT")
    c.value:SetWordWrap(false)
    c.sub = c:CreateFontString(nil, "OVERLAY", "WowAssistantFontMuted")
    c.sub:SetPoint("BOTTOMLEFT", 10, 6)
    c.sub:SetPoint("RIGHT", -8, 0)
    c.sub:SetJustifyH("LEFT")
    c.sub:SetWordWrap(false)
    f.cards[i] = c
  end

  local x, headY = inset, y0 - 70
  f.heads = {}
  for i, c in ipairs(COLS) do
    local h = CreateFrame("Button", nil, f)
    h:SetSize(c[2], 18)
    h:SetPoint("TOPLEFT", x, headY)
    local t = h:CreateFontString(nil, "OVERLAY", "WowAssistantFontDisableSmall")
    t:SetAllPoints()
    t:SetJustifyH(c[3])
    t:SetText(St.Upper(c[1]))
    h:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(WA.Fix(c[1]), 1, 0.82, 0)
      GameTooltip:AddLine(WA.Fix(c[4]), 1, 1, 1, true)
      GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.heads[i] = h
    x = x + c[2] + 4
  end

  f.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, f)
    row:SetSize(W - 2 * inset, ROW_H)
    row:SetPoint("TOPLEFT", inset, headY - 22 - (i - 1) * ROW_H)
    local zebra = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    zebra:SetAllPoints()
    zebra:SetColorTexture(1, 0.9, 0.7, i % 2 == 0 and 0.035 or 0)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.9, 0.7, 0.08)
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(1, 0.82, 0, 0.16)
    row.cells = {}
    local cx = 0
    for k, c in ipairs(COLS) do
      local t = row:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlightSmall")
      t:SetPoint("LEFT", cx, 0)
      t:SetWidth(c[2])
      t:SetJustifyH(c[3])
      t:SetWordWrap(false)
      row.cells[k] = t
      cx = cx + c[2] + 4
    end
    row:SetScript("OnClick", function(b)
      if not b.data then return end
      selected = b.data.id
      state.phase, state.id = nil, nil
      if AHOpen() then F.Check(selected) end
      F.Refresh()
    end)
    row:SetScript("OnEnter", function(b)
      if not b.data then return end
      GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
      if GameTooltip.SetItemByID then GameTooltip:SetItemByID(b.data.id) else GameTooltip:AddLine(b.data.name) end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.rows[i] = row
  end
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta)
    offset = math.max(0, math.min(math.max(0, #rows - ROWS), offset - delta * 3))
    F.Refresh()
  end)

  local top = headY - 32 - ROWS * ROW_H
  f.detail = f:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlightSmall")
  f.detail:SetPoint("TOPLEFT", inset, top)
  f.detail:SetPoint("RIGHT", -(inset + 246), 0)
  f.detail:SetJustifyH("LEFT")
  f.detail:SetJustifyV("TOP")
  f.check = St.Button(f, L"Check live", 240, function() if selected then F.Check(selected) end end)
  f.check:SetPoint("TOPRIGHT", -inset, top)
  f.buy = St.Button(f, L"Buy", 240, function() F.Buy() end)
  f.buy:SetPoint("TOPRIGHT", -inset, top - 26)
  f.note = f:CreateFontString(nil, "OVERLAY", "WowAssistantFontDisableSmall")
  f.note:SetPoint("BOTTOMLEFT", inset, St.Wow() and 16 or 8)
  f.note:SetPoint("RIGHT", -inset, 0)
  f.note:SetJustifyH("LEFT")
  f.note:SetText(L"Auctions cheaper than what a merchant pays, from the full AH scan (/wa ah). Click a row: the item is searched again, and Buy takes only what is still there and still pays. Bought items arrive in your mailbox; at a merchant, \"Sell AH buys\" sells exactly what you bought here.")
  f:Hide()
  return f
end

local function Ago(t)
  local m = math.floor((time() - t) / 60)
  if m < 1 then return L"now" end
  if m < 60 then return (L"%d min ago"):format(m) end
  return (L"%d h ago"):format(math.floor(m / 60))
end

local function Detail(r)
  local lines = {}
  lines[1] = (L"|cffffd100%s|r: a merchant pays %s each."):format(r.name, Short(r.sell))
  local e = DB().items[r.id]
  local shown = 0
  for i = 1, #e.l, 2 do
    if shown >= 5 then
      lines[#lines + 1] = (L"  ... and %d more auctions"):format(math.floor(#e.l / 2) - shown)
      break
    end
    local buyout, qty = e.l[i], e.l[i + 1]
    lines[#lines + 1] = (L"  %d × for %s (%s each), merchant %s: |cff40ff40+%s|r"):format(qty, Short(buyout), Short(buyout / qty),
      Short(r.sell * qty), Short(r.sell * qty - buyout))
    shown = shown + 1
  end
  if state.id == r.id then
    if state.phase == "browse" or state.phase == "search" then lines[#lines + 1] = L"|cff66ccffSearching the auction house...|r"
    elseif state.phase == "buying" then lines[#lines + 1] = L"|cff66ccffBuying...|r"
    elseif state.phase == "confirm" and state.pending then
      lines[#lines + 1] = (L"|cff66ccffThe game's price: %d for %s. Click Confirm to buy.|r"):format(state.pending.units, Short(state.pending.cost))
    end
  elseif not AHOpen() then
    lines[#lines + 1] = L"|cff9e917aAt the auction house, click the row to check it live and buy.|r"
  end
  return table.concat(lines, "\n")
end

function F.Refresh()
  if not frame or not frame:IsShown() then return end
  rows, total = F.List()
  local d = DB()
  local c1, c2, c3 = frame.cards[1], frame.cards[2], frame.cards[3]
  c1.label:SetText(L"PROFIT ON THE AH NOW")
  c1.value:SetText(#rows > 0 and ("|cff5ee05e+" .. Short(total) .. "|r") or "|cff9e917a–|r")
  c1.sub:SetText((L"%d items, %d auctions"):format(#rows, (function() local n = 0 for _, r in ipairs(rows) do n = n + r.n end return n end)()))
  c2.label:SetText(L"YOUR RESULT")
  c2.value:SetText(Short(d.stats.earned - d.stats.spent))
  local inBags = 0
  for _, n in pairs(d.bought) do inBags = inBags + n end
  c2.sub:SetText((L"spent %s, sold %s · %d to sell"):format(Short(d.stats.spent), Short(d.stats.earned), inBags))
  c3.label:SetText(L"SCAN")
  c3.value:SetText(d.at and Ago(d.at) or (L"|cffff9933no scan yet|r"))
  c3.sub:SetText(d.at and ((L"%d auctions, %d of them yours (left out)"):format(d.auctions or 0, d.own or 0)
    .. ((d.unresolved or 0) > 0 and (L", %d items unknown"):format(d.unresolved) or "")) or (L"/wa ah at the auction house"))
  offset = math.min(offset, math.max(0, #rows - ROWS))
  local sel
  for i, row in ipairs(frame.rows) do
    local r = rows[offset + i]
    row.data = r
    if r then
      local c = row.cells
      c[1]:SetText(r.name .. " |cff888888" .. (r.n == 1 and L"1 auction" or (L"%d auctions"):format(r.n)) .. "|r")
      c[2]:SetText(r.units)
      c[3]:SetText(Short(r.cost))
      c[4]:SetText(Short(r.value))
      c[5]:SetText("|cff40ff40+" .. Short(r.profit) .. "|r")
      c[6]:SetText(r.live and ("|cff66ccff" .. L"live " .. date("%H:%M", r.live) .. "|r") or (L"scan"))
      row.sel:SetShown(r.id == selected)
      row:Show()
    else
      row:Hide()
    end
    if r and r.id == selected then sel = r end
  end
  if not sel and selected then for _, r in ipairs(rows) do if r.id == selected then sel = r end end end
  if sel then
    frame.detail:SetText(Detail(sel))
  elseif not d.at then
    frame.detail:SetText(L"No scan yet. At the auction house type /wa ah: one full scan finds every auction below the merchant price.")
  elseif #rows == 0 then
    frame.detail:SetText(L"No auction is below the merchant price in the last scan.")
  else
    frame.detail:SetText(L"Click an item to see its auctions.")
  end
  frame.check:SetEnabled(AHOpen() and sel ~= nil or false)
  local nb = sel and state.id == sel.id and F.NextBuy()
  if state.phase == "confirm" and state.pending and state.id == (sel and sel.id) then
    frame.buy:SetText((L"Confirm: %d for %s"):format(state.pending.units, Short(state.pending.cost)))
    frame.buy:SetEnabled(true)
  elseif nb and nb.units > 0 then
    frame.buy:SetText((L"Buy %d for %s (+%s)"):format(nb.units, Short(nb.cost), Short(nb.value - nb.cost)))
    frame.buy:SetEnabled(nb.afford and AHOpen() and true or false)
  else
    frame.buy:SetText(nb and nb.units == 0 and (L"Not enough gold") or (L"Buy"))
    frame.buy:SetEnabled(false)
  end
end

function F.Toggle()
  frame = frame or Build()
  if frame:IsShown() then frame:Hide() return end
  frame:ClearAllPoints()
  if AHOpen() then frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0) else frame:SetPoint("CENTER") end
  frame:Show()
  F.Refresh()
end

---------------------------------------------------------------------------
-- merchant button
---------------------------------------------------------------------------
local sellButton
function F.UpdateMerchant()
  if not sellButton then return end
  local stacks = SellableStacks()
  if #stacks == 0 then sellButton:Hide() return end
  local value = 0
  for _, s in ipairs(stacks) do value = value + (SellOf(s.id) or 0) * s.count end
  sellButton:SetText((L"Sell AH buys (%s)"):format(Short(value)))
  sellButton:Show()
end

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local ahButton
ev:SetScript("OnEvent", function(_, event, ...)
  if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
    pcall(OnBrowse)
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    pcall(OnItemResults, ...)
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    pcall(OnCommodityResults, ...)
  elseif event == "COMMODITY_PRICE_UPDATED" then
    pcall(OnCommodityPrice, ...)
  elseif event == "COMMODITY_PRICE_UNAVAILABLE" or event == "COMMODITY_PURCHASE_FAILED" then
    if state.pending then
      Print(L"The purchase did not go through: the auctions were gone.")
      AfterPurchase(false)
    end
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    if state.pending and state.kind == "commodity" then AfterPurchase(true) end
  elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
    local auctionID = ...
    if state.pending and state.kind == "item" and (not auctionID or auctionID == state.pending.auctionID) then AfterPurchase(true) end
  elseif event == "CHAT_MSG_SYSTEM" then
    -- the classic confirmation of a won auction, when the purchase event does not come
    local msg = ...
    if state.pending and state.phase == "buying" and state.kind == "item" and ERR_AUCTION_WON_S and msg then
      local pat = "^" .. ERR_AUCTION_WON_S:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", ".+") .. "$"
      if msg:find(pat) then AfterPurchase(true) end
    end
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    if state.retry then F.Check(state.retry) end
  elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
    if state.pending and state.phase == "buying" then AfterPurchase(false) end
  elseif event == "AUCTION_HOUSE_SHOW" then
    if not ahButton and AuctionHouseFrame then
      ahButton = CreateFrame("Button", nil, AuctionHouseFrame, "UIPanelButtonTemplate")
      ahButton:SetSize(110, 22)
      ahButton:SetPoint("TOPRIGHT", AuctionHouseFrame, "TOPRIGHT", -164, -1)
      ahButton:SetText(L"AH → vendor")
      ahButton:SetScript("OnClick", F.Toggle)
    end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    state.phase, state.pending = nil, nil
    if frame and frame:IsShown() then F.Refresh() end
  elseif event == "MERCHANT_SHOW" then
    if not sellButton and MerchantFrame then
      sellButton = CreateFrame("Button", nil, MerchantFrame, "UIPanelButtonTemplate")
      sellButton:SetSize(170, 22)
      sellButton:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -30, -26)
      sellButton:SetScript("OnClick", F.SellAll)
      sellButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(WA.Fix(L"Sells only whole stacks you bought with Waystone's AH → vendor, up to 12 at a time (the buyback tab can undo them)."), 1, 1, 1, true)
        GameTooltip:Show()
      end)
      sellButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    F.UpdateMerchant()
  elseif event == "BAG_UPDATE_DELAYED" then
    if MerchantFrame and MerchantFrame:IsShown() then F.UpdateMerchant() end
  end
end)
for _, e in ipairs({ "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_UPDATED",
  "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_FAILED", "COMMODITY_PURCHASE_SUCCEEDED",
  "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_SHOW_ERROR", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
  "MERCHANT_SHOW", "BAG_UPDATE_DELAYED", "CHAT_MSG_SYSTEM", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" }) do
  pcall(ev.RegisterEvent, ev, e)
end

WA.Command("flip", function() F.Toggle() end, L"/wa flip – auctions below the merchant price (AH → vendor)")
