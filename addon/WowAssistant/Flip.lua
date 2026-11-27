-- Waystone: auction house → vendor.
--
-- Auctions whose buyout is below what a merchant pays for the same items. Buying one and selling
-- it to any merchant is pure profit: the buyer pays no auction house fee, and the merchant pays the
-- item's full sell price.
--   * The candidates come from the full auction house scan (/wa ah, Exporter.lua): every auction is
--     compared with the merchant price the client itself reports (GetItemInfo), never an estimate.
--     Gear is priced by its own link (a random suffix can change it). Items the client has not
--     loaded yet are loaded after the scan, for as long as they keep arriving.
--   * Your own auctions are left out: you cannot buy them.
--   * Nothing is bought from the scan. A click searches the item again (AHLine.lua), and Buy takes
--     only what that search shows still there, still under the merchant price, and within your
--     gold. Gear: one auction a click (PlaceBid at its buyout, the price of ONE auction).
--     Stackable items: the game quotes its total first (StartCommoditiesPurchase), and the purchase
--     is confirmed only with a second click, only while that total is still below what the
--     merchant pays, and only if it is the total the button showed.
--   * The ledger: what was bought this way, units and what they cost. A sale at a merchant (with the
--     button or by hand) is read from the bags, so the ledger always holds what is still to sell,
--     and the result counts only what was really sold.
--
-- /wa flip opens the window; at the auction house there is a button for it too.

local _, WA = ...
local L = WA.L
local F = {}
WA.Flip = F

local ROWS = 12
local ROW_H = 20
local W = 720
local RESOLVE_STALLS = 2     -- rounds without a newly loaded item before the scan is stored
local RESOLVE_MAX = 40       -- rounds at most (2 s each)
local BUY_WAIT = 10          -- seconds for a purchase's answer
local LATE = 60              -- seconds a purchase that lost its answer may still land
local MAIL_SETTLE = 3600     -- a purchase this recent may still be on its way to the mailbox
local SETTLE_CLICK = 1.5     -- seconds the confirm button waits after the game's total moved

local function Print(msg) WA.Print(msg) end
local function Plain(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local frame, selected, offset = nil, nil, 0 -- the window, the item shown in it, its scroll

local function Line() return WA.AHLine end
local function AHOpen() return WA.AHLine and WA.AHLine.IsOpen() end

local function DB()
  WA.db.flip = WA.db.flip or {}
  local d = WA.db.flip
  d.items = d.items or {}
  d.held = d.held or {}
  d.stats = d.stats or {}
  local s = d.stats
  s.spent, s.earned, s.costSold, s.buys, s.sold = s.spent or 0, s.earned or 0, s.costSold or 0, s.buys or 0, s.sold or 0
  -- 2.37.0 kept only a count
  if d.bought then
    for id, n in pairs(d.bought) do d.held[id] = { units = n, cost = 0, at = 0 } end
    d.bought = nil
  end
  return d
end
F.DB = DB

local function Info(x) return (C_Item and C_Item.GetItemInfo or GetItemInfo)(x) end

-- What a merchant pays for one, from the client; nil while the item is not loaded, 0 when no
-- merchant buys it. A link gives the exact variant.
local function SellOf(x)
  local sell = Plain(select(11, Info(x)))
  return type(sell) == "number" and sell or nil
end
F.SellOf = SellOf

local function ItemName(id)
  local name = (C_Item and C_Item.GetItemNameByID and Plain(C_Item.GetItemNameByID(id))) or Plain(Info(id))
  return name or ("Item #" .. id)
end

local function IsGear(id)
  local equipLoc = select(4, (C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant)(id))
  return type(equipLoc) == "string" and equipLoc ~= "" and equipLoc ~= "INVTYPE_AMMO"
end

local function Money()
  local m = GetMoney and Plain(GetMoney())
  return type(m) == "number" and m or nil
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

local function IsMine(owner)
  owner = Plain(owner)
  if type(owner) ~= "string" or owner == "" then return false end
  return (owner:match("^[^-]+") or owner) == UnitName("player")
end
F.IsMine = IsMine

-- Listings are flat triplets: cost, units, value (what a merchant pays for those units).
local function Add3(list, cost, units, value)
  local n = #list
  list[n + 1], list[n + 2], list[n + 3] = cost, units, value
end

local function SortListings(list)
  local t = {}
  for i = 1, #list, 3 do t[#t + 1] = { list[i], list[i + 1], list[i + 2] } end
  -- best value for the money first
  table.sort(t, function(a, b)
    local x, y = (a[3] - a[1]) / a[2], (b[3] - b[1]) / b[2]
    if x == y then return a[1] / a[2] < b[1] / b[2] end
    return x > y
  end)
  local out = {}
  for _, p in ipairs(t) do Add3(out, p[1], p[2], p[3]) end
  return out
end

---------------------------------------------------------------------------
-- collecting from the full scan
---------------------------------------------------------------------------
local scan

function F.Begin()
  scan = { items = {}, unknown = {}, sell = {}, linkSell = {}, auctions = 0, own = 0, rounds = 0 }
end

-- One auction of the full scan: itemID, total buyout, count, the seller (may be nil), and the
-- auction's index in the list (for its link while the list is there).
function F.Add(itemID, buyout, count, owner, index, hasAll)
  local s = scan
  if not s then return end
  itemID, buyout, count = Plain(itemID), Plain(buyout), Plain(count)
  if type(itemID) ~= "number" or type(buyout) ~= "number" or buyout <= 0 then return end
  count = (type(count) == "number" and count > 0) and count or 1
  s.auctions = s.auctions + 1
  if IsMine(owner) then s.own = s.own + 1 return end
  local sell = s.sell[itemID]
  if sell == nil then
    sell = SellOf(itemID) or false
    s.sell[itemID] = sell
    if sell == false and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
  end
  if sell == false then
    local u = s.unknown[itemID]
    if not u then u = {} s.unknown[itemID] = u end
    local n = #u
    u[n + 1], u[n + 2] = buyout, count
    return
  end
  if sell == 0 then return end
  -- gear: the variant's own price, when its link is there
  if index and hasAll and IsGear(itemID) and C_AuctionHouse.GetReplicateItemLink then
    local link = Plain(C_AuctionHouse.GetReplicateItemLink(index))
    if type(link) == "string" then
      local ls = s.linkSell[link]
      if ls == nil then ls = SellOf(link) or false s.linkSell[link] = ls end
      if ls then sell = ls end
    end
  end
  if buyout < sell * count then
    local list = s.items[itemID]
    if not list then list = {} s.items[itemID] = list end
    Add3(list, buyout, count, sell * count)
  end
end

local function Store(s, at, unresolved)
  if scan ~= s then return end
  scan = nil
  local d = DB()
  d.items, d.at, d.auctions, d.own, d.unresolved, d.partial = {}, at, s.auctions, s.own, unresolved, s.partial
  for id, list in pairs(s.items) do
    d.items[id] = { sell = s.sell[id] or nil, l = SortListings(list) }
  end
  local rows, total = F.List()
  Print((L"AH → vendor: %d items below the merchant price, %s profit in total. /wa flip"):format(#rows, Short(total)))
  if F.Refresh then F.Refresh() end
end

-- Items the client had not loaded: looked at again every 2 s while they keep arriving; when none
-- came for RESOLVE_STALLS rounds (they are asked for again each time), the rest are counted and
-- the scan is stored.
local function Resolve(s, at, stalls)
  if scan ~= s then return end
  local left, progress = 0, false
  for id, list in pairs(s.unknown) do
    local sell = SellOf(id)
    if sell then
      progress = true
      s.sell[id] = sell
      s.unknown[id] = nil
      if sell > 0 then
        for i = 1, #list, 2 do
          if list[i] < sell * list[i + 1] then
            local l = s.items[id]
            if not l then l = {} s.items[id] = l end
            Add3(l, list[i], list[i + 1], sell * list[i + 1])
          end
        end
      end
    else
      left = left + 1
      if not progress and stalls > 0 and C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, id)
      end
    end
  end
  stalls = progress and 0 or stalls + 1
  s.rounds = s.rounds + 1
  if left > 0 and stalls <= RESOLVE_STALLS and s.rounds < RESOLVE_MAX then
    C_Timer.After(2, function() Resolve(s, at, stalls) end)
    return
  end
  Store(s, at, left)
end

function F.Finish(at, partial)
  local s = scan
  if not s then return end
  s.partial = partial and true or nil
  Resolve(s, at or time(), 0)
end

---------------------------------------------------------------------------
-- the list
---------------------------------------------------------------------------
-- rows: { id, name, sell, n (listings), units, cost, value, profit, live }, best first; total profit.
function F.List()
  local rows, total = {}, 0
  local d = WA.db and WA.db.flip
  if not d or not d.items then return rows, 0 end
  for id, e in pairs(d.items) do
    local units, cost, value = 0, 0, 0
    for i = 1, #e.l, 3 do
      cost, units, value = cost + e.l[i], units + e.l[i + 1], value + e.l[i + 2]
    end
    if units > 0 and value > cost then
      rows[#rows + 1] = { id = id, name = ItemName(id), sell = e.sell, n = math.floor(#e.l / 3), units = units,
        cost = cost, value = value, profit = value - cost, live = e.live }
      total = total + value - cost
    end
  end
  table.sort(rows, function(a, b)
    if a.profit == b.profit then return a.id < b.id end
    return a.profit > b.profit
  end)
  return rows, total
end

---------------------------------------------------------------------------
-- live check
---------------------------------------------------------------------------
-- state.phase: nil | "search" | "ready" | "failed" | "buying" | "quote" | "confirm"
local state = {}
F.state = state

local function Busy() return state.phase == "buying" or state.phase == "quote" or state.phase == "confirm" end

local function OnLive(id, res, reason)
  if state.id ~= id or state.phase ~= "search" then return end
  if not res then
    state.phase, state.reason = "failed", reason
    if F.Refresh then F.Refresh() end
    return
  end
  local d = DB()
  local base = SellOf(id) or (d.items[id] and d.items[id].sell)
  if not base then
    state.phase, state.reason = "failed", "uncached"
    if F.Refresh then F.Refresh() end
    return
  end
  local flat, cheap = {}, {}
  if res.commodity then
    for _, r in ipairs(res.rows) do
      local units = r.qty - r.own
      if base and base > 0 and units > 0 and r.unit < base then
        Add3(flat, r.unit * units, units, base * units)
        cheap[#cheap + 1] = { unit = r.unit, units = units }
      end
    end
  else
    for _, r in ipairs(res.rows) do
      if r.buyout and not r.own then
        local sell = (r.link and SellOf(r.link)) or base
        if sell and sell > 0 and r.buyout < sell then
          -- the row holds r.qty auctions at this price, one item each
          Add3(flat, r.buyout * r.qty, r.qty, sell * r.qty)
          cheap[#cheap + 1] = { auctionID = r.auctionID, buyout = r.buyout, value = sell, qty = r.qty }
        end
      end
    end
  end
  table.sort(cheap, function(a, b)
    if res.commodity then return a.unit < b.unit end
    return (a.value - a.buyout) > (b.value - b.buyout)
  end)
  if #flat > 0 then
    d.items[id] = { sell = base, l = SortListings(flat), live = time() }
  elseif #res.rows > 0 or res.full then
    -- the cheap end was seen, and nothing in it pays any more
    d.items[id] = nil
  else
    -- an empty answer that does not say it is complete: keep what the scan saw
    state.reason = "empty"
  end
  state.phase, state.commodity, state.cheap, state.sell = "ready", res.commodity, cheap, base
  if F.Refresh then F.Refresh() end
end

-- Search the item again; what comes back replaces what the scan saw.
function F.Check(id)
  if not AHOpen() then Print(L"Open the auction house for live prices.") return end
  if Busy() then return end
  selected = id
  state.id, state.phase, state.cheap, state.reason, state.pending = id, "search", nil, nil, nil
  local d = DB()
  local base = SellOf(id) or (d.items[id] and d.items[id].sell)
  -- gear variants can pay more than the base item: read on up to the best one the scan saw
  local below = base
  local e = d.items[id]
  for i = 1, e and #e.l or 0, 3 do
    local each = e.l[i + 2] / e.l[i + 1]
    if not below or each > below then below = each end
  end
  Line().Search(id, function(res, reason) OnLive(id, res, reason) end, { priority = true, below = below })
  if F.Refresh then F.Refresh() end
end

-- What one click buys now: { units, cost, value, afford } or nil.
function F.NextBuy()
  if state.phase ~= "ready" or not state.cheap or not state.cheap[1] then return nil end
  local money = Money()
  if not state.commodity then
    -- the best auction you can pay for
    for _, x in ipairs(state.cheap) do
      if not money or x.buyout <= money then return { units = 1, cost = x.buyout, value = x.value, afford = true, x = x } end
    end
    local x = state.cheap[1]
    return { units = 1, cost = x.buyout, value = x.value, afford = false, x = x }
  end
  local units, cost = 0, 0
  for _, x in ipairs(state.cheap) do
    local n = x.units
    if money then n = math.min(n, math.floor((money - cost) / x.unit)) end
    if n <= 0 then break end
    units, cost = units + n, cost + x.unit * n
    if n < x.units then break end
  end
  return { units = units, cost = cost, value = (state.sell or 0) * units, afford = units > 0 }
end

---------------------------------------------------------------------------
-- buying
---------------------------------------------------------------------------
-- Purchases whose answer did not come in time: { kind, id, auctionID, units, cost, value, at }.
-- The game can still report them (up to LATE seconds later); then they are counted.
local lost = {}
local function Lose(p)
  lost[#lost + 1] = { kind = p.kind, id = p.id, auctionID = p.auctionID, units = p.units, cost = p.cost, value = p.value, at = GetTime() }
end
local function Found(kind, auctionID)
  local now = GetTime()
  for i = #lost, 1, -1 do
    local l = lost[i]
    if now - l.at > LATE then
      table.remove(lost, i)
    elseif l.kind == kind and (kind ~= "item" or l.auctionID == auctionID) then
      table.remove(lost, i)
      return l
    end
  end
end

local function Bought(id, units, cost, value)
  local d = DB()
  local h = d.held[id] or { units = 0, cost = 0, value = 0 }
  -- value: what a merchant pays for them, gear variants included
  h.units, h.cost, h.at = h.units + units, h.cost + cost, time()
  if h.value then h.value = h.value + value end
  d.held[id] = h
  d.stats.spent = d.stats.spent + cost
  d.stats.buys = d.stats.buys + 1
  Print((L"Bought %d × %s for %s; a merchant pays %s (+%s)."):format(units, ItemName(id), Short(cost), Short(value), Short(value - cost)))
end

-- The purchase ended: ok true (bought), false (not), nil (no answer: may land later). The item
-- is searched again, unless quiet (the player moved on).
local function Done(ok, why, quiet)
  local p = state.pending
  if not p then return end
  state.pending = nil
  if p.release then p.release() end
  if ok then
    Bought(p.id, p.units, p.cost, p.value)
  elseif ok == nil then
    Lose(p)
    Print(L"No answer to the purchase yet; if it goes through within a minute it is counted.")
  elseif why then
    Print(why)
  end
  if p.kind == "commodity" and not ok and not p.confirmed and C_AuctionHouse.CancelCommoditiesPurchase then
    pcall(C_AuctionHouse.CancelCommoditiesPurchase)
  end
  state.phase = nil
  if AHOpen() and not quiet then F.Check(p.id) elseif F.Refresh then F.Refresh() end
end

-- A timer for the purchase in flight; nothing once it ended.
local function Expect(p, seconds, fn)
  C_Timer.After(seconds, function() if state.pending == p then fn() end end)
end

-- One click: buy the best auction (gear), or ask the game's total for the cheap units, or
-- confirm that total.
function F.Buy()
  local AH = C_AuctionHouse
  if not AHOpen() then return end
  local p = state.pending
  if state.phase == "confirm" and p then
    -- only the total the button showed, only while it pays, only before the quote runs out
    if p.total ~= p.shown or (p.moved and GetTime() - p.moved < SETTLE_CLICK) then F.Refresh() return end
    if not (p.total < p.value) then return Done(false, L"The price changed and it no longer pays: nothing was bought.") end
    local money = Money()
    if money and p.total > money then Print(L"Not enough gold") return end
    if AH.GetQuoteDurationRemaining then
      local left = Plain(AH.GetQuoteDurationRemaining())
      if type(left) == "number" and left <= 0 then return Done(false, L"The game's price ran out; checking the item again.") end
    end
    local can = Line().CanAct()
    if not can then Print(L"The auction house is busy, click again in a moment.") return end
    p.release = Line().Reserve()
    p.confirmed, p.cost = true, p.total
    state.phase = "buying"
    local ok = pcall(AH.ConfirmCommoditiesPurchase, p.id, p.units)
    if not ok then return Done(false, L"The purchase did not go through.") end
    Expect(p, BUY_WAIT, function() Done(nil) end)
    if F.Refresh then F.Refresh() end
    return
  end
  local nb = F.NextBuy()
  if not nb or not nb.afford or nb.units == 0 or nb.cost >= nb.value then return end
  local can = Line().CanAct()
  if not can then Print(L"The auction house is busy, click again in a moment.") return end
  if not state.commodity then
    if not AH.PlaceBid then Print(L"This client cannot buy from an addon.") return end
    local x = nb.x
    p = { kind = "item", id = state.id, auctionID = x.auctionID, units = 1, cost = x.buyout, value = x.value }
    p.release = Line().Reserve()
    state.pending, state.phase = p, "buying"
    local ok = pcall(AH.PlaceBid, x.auctionID, x.buyout)
    if not ok then return Done(false, L"The purchase did not go through.") end
    Expect(p, BUY_WAIT, function() Done(nil) end)
  else
    if not (AH.StartCommoditiesPurchase and AH.ConfirmCommoditiesPurchase) then Print(L"This client cannot buy from an addon.") return end
    p = { kind = "commodity", id = state.id, units = nb.units, cost = nb.cost, value = nb.value }
    p.release = Line().Reserve()
    state.pending, state.phase = p, "quote"
    -- the unit price the game's own buy frame passes: the average, rounded up
    local ok = pcall(AH.StartCommoditiesPurchase, p.id, p.units, math.ceil(nb.cost / nb.units))
    if not ok then return Done(false, L"The purchase did not go through.") end
    Expect(p, BUY_WAIT, function() if state.phase == "quote" then Done(false, L"No answer from the auction house; checking the item again.") end end)
  end
  if F.Refresh then F.Refresh() end
end

-- The game's total for the units (again when it moves while you look).
local function OnPrice(unitPrice, total)
  local p = state.pending
  total = Plain(total)
  if not p or p.kind ~= "commodity" or p.confirmed or type(total) ~= "number" then return end
  if p.release then p.release() p.release = nil end -- the quote waits for the player; the line is free
  local money = Money()
  if total < p.value and (not money or total <= money) then
    -- a total that moves while you look is shown a moment before the button takes it
    if p.total and p.total ~= total then
      p.moved = GetTime()
      C_Timer.After(SETTLE_CLICK + 0.05, function() if state.pending == p and F.Refresh then F.Refresh() end end)
    end
    p.total = total
    state.phase = "confirm"
  elseif money and total > money then
    Done(false, L"Not enough gold")
    return
  else
    Done(false, L"The price changed and it no longer pays: nothing was bought.")
    return
  end
  if F.Refresh then F.Refresh() end
end

-- Leaving an item while its quote is held lets the quote go.
function F.Cancel()
  if state.pending and state.pending.kind == "commodity" and not state.pending.confirmed then
    Done(false, nil, true)
  end
end

---------------------------------------------------------------------------
-- the ledger: selling and keeping count
---------------------------------------------------------------------------
local function LastBag()
  local last = NUM_BAG_SLOTS or 4
  local reagent = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
  if type(reagent) == "number" and reagent > last then last = reagent end
  return last
end

-- Every stack in the bags: { bag, slot, id, count, locked }.
local function Stacks()
  local list = {}
  local C = C_Container
  if not (C and C.GetContainerNumSlots) then return list end
  for bag = 0, LastBag() do
    for slot = 1, Plain(C.GetContainerNumSlots(bag)) or 0 do
      local info = C.GetContainerItemInfo(bag, slot)
      local id = type(info) == "table" and Plain(info.itemID)
      local count = type(info) == "table" and Plain(info.stackCount)
      if type(id) == "number" and type(count) == "number" then
        list[#list + 1] = { bag = bag, slot = slot, id = id, count = count, locked = info.isLocked == true }
      end
    end
  end
  return list
end

local function BagCounts()
  local t = {}
  for _, s in ipairs(Stacks()) do t[s.id] = (t[s.id] or 0) + s.count end
  return t
end
F.BagCounts = BagCounts

-- Stacks wholly made of what was bought this way.
function F.SellableStacks()
  local d = DB()
  local left = {}
  for id, h in pairs(d.held) do left[id] = h.units end
  local list = {}
  for _, s in ipairs(Stacks()) do
    if left[s.id] and left[s.id] >= s.count and not s.locked then
      left[s.id] = left[s.id] - s.count
      list[#list + 1] = s
    end
  end
  return list
end

-- What a merchant pays for the held units of id.
local function HeldValue(id, h)
  return h.value or (SellOf(id) or 0) * h.units
end

-- k units of id left the ledger: sold (true) or gone some other way. Their share of the cost and
-- of the merchant value is the average over what is held.
local function Release(id, k, sold)
  local d = DB()
  local h = d.held[id]
  if not h or k <= 0 then return 0, 0, 0 end
  k = math.min(k, h.units)
  local share = h.units > 0 and h.cost * k / h.units or 0
  local worth = h.units > 0 and HeldValue(id, h) * k / h.units or 0
  h.units, h.cost = h.units - k, h.cost - share
  if h.value then h.value = h.value - worth end
  if h.units <= 0 then d.held[id] = nil end
  if sold then
    d.stats.earned = d.stats.earned + worth
    d.stats.costSold = d.stats.costSold + share
    d.stats.sold = d.stats.sold + k
    return k, share, worth
  end
  return k, share, 0
end

-- At a merchant: every drop of a held item in the bags is a sale (the button's or yours), and
-- what comes back from the buyback tab is held again.
local watch
local function WatchMerchant()
  if not watch then return end
  local d = DB()
  local now = BagCounts()
  for id, before in pairs(watch.counts) do
    local n = now[id] or 0
    if n < before and d.held[id] then
      local k, share, earn = Release(id, before - n, true)
      if k > 0 then
        local r = watch.removed[id] or { units = 0, cost = 0, earn = 0 }
        r.units, r.cost, r.earn = r.units + k, r.cost + share, r.earn + earn
        watch.removed[id] = r
      end
    elseif n > before and watch.removed[id] and watch.removed[id].units > 0 then
      local r = watch.removed[id]
      local k = math.min(n - before, r.units)
      local share, earn = r.cost * k / r.units, r.earn * k / r.units
      local h = d.held[id] or { units = 0, cost = 0, value = 0, at = time() }
      h.units, h.cost = h.units + k, h.cost + share
      if h.value then h.value = h.value + earn end
      d.held[id] = h
      d.stats.earned, d.stats.costSold, d.stats.sold = d.stats.earned - earn, d.stats.costSold - share, d.stats.sold - k
      r.units, r.cost, r.earn = r.units - k, r.cost - share, r.earn - earn
    end
    watch.counts[id] = n
  end
end

function F.SellAll()
  if not (MerchantFrame and MerchantFrame:IsShown()) then return end
  local n, value = 0, 0
  for _, s in ipairs(F.SellableStacks()) do
    if n >= 12 then break end -- the buyback tab holds 12: a mistake stays recoverable
    C_Container.UseContainerItem(s.bag, s.slot)
    n, value = n + 1, value + (SellOf(s.id) or 0) * s.count
  end
  if n > 0 then Print((L"Sold %d stacks bought on the AH for %s."):format(n, Short(value))) end
end

-- After the mailbox: what is neither in the bags nor in the mail (nor in the bank, when it is
-- known) was used up or given away, so it is no longer to sell. Purchases from the last hour are
-- left alone, their mail may still be on its way.
local inbox
local function ReadInbox()
  if not (GetInboxNumItems and GetInboxItem) then return end
  local shown, total = GetInboxNumItems()
  shown, total = Plain(shown), Plain(total)
  if type(shown) ~= "number" or (type(total) == "number" and total > shown) then inbox = nil return end
  local t = {}
  for i = 1, shown do
    for a = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
      local _, id, _, count = GetInboxItem(i, a)
      id, count = Plain(id), Plain(count)
      if type(id) == "number" and type(count) == "number" then t[id] = (t[id] or 0) + count end
    end
  end
  inbox = t
end

local function Reconcile()
  if not inbox then return end
  -- without the bank's contents an item stored there would look used up
  if not (WA.char and WA.char.bankAt) then inbox = nil return end
  local d = DB()
  local bags = BagCounts()
  local bank = WA.char and WA.char.bank or {}
  for id, h in pairs(d.held) do
    if (h.at or 0) < time() - MAIL_SETTLE then
      local have = (bags[id] or 0) + (inbox[id] or 0) + (bank[id] or 0)
      if have < h.units then Release(id, h.units - have, false) end
    end
  end
  inbox = nil
end
F.ReadInbox, F.Reconcile = ReadInbox, Reconcile

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
    WA.Style.Tint(zebra, "hover", i % 2 == 0 and 0.035 or 0)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    WA.Style.Tint(hl, "hover", 0.08)
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    WA.Style.Tint(row.sel, "accent", 0.16)
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
      if not b.data or Busy() and state.phase ~= "confirm" then return end
      F.Cancel()
      selected = b.data.id
      if AHOpen() then F.Check(selected) else state.phase, state.id = nil, nil end
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
  f.check = St.Button(f, L"Check live", 240, function() if selected and not Busy() then F.Check(selected) end end)
  f.check:SetPoint("TOPRIGHT", -inset, top)
  f.buy = St.Button(f, L"Buy", 240, function() F.Buy() end)
  f.buy:SetPoint("TOPRIGHT", -inset, top - 26)
  f.note = f:CreateFontString(nil, "OVERLAY", "WowAssistantFontDisableSmall")
  f.note:SetPoint("BOTTOMLEFT", inset, St.Wow() and 16 or 8)
  f.note:SetPoint("RIGHT", -inset, 0)
  f.note:SetJustifyH("LEFT")
  f.note:SetText(L"Auctions cheaper than what a merchant pays, from the full AH scan (/wa ah). Click a row: the item is searched again, and Buy takes only what is still there and still pays. Bought items arrive in your mailbox; at a merchant, \"Sell AH buys\" sells exactly what you bought here.")
  f:SetScript("OnHide", function()
    F.Cancel()
    if WA.AHLine then WA.AHLine.SetPaused(false) end
  end)
  f:Hide()
  return f
end

local function Ago(t)
  local m = math.floor((time() - t) / 60)
  if m < 1 then return L"now" end
  if m < 60 then return (L"%d min ago"):format(m) end
  return (L"%d h ago"):format(math.floor(m / 60))
end

local REASONS = {
  closed = "Open the auction house for live prices.",
  uncached = "The game did not load this item; try again in a moment.",
  timeout = "No answer from the auction house; checking the item again.",
  error = "The purchase did not go through.",
}

local function Detail(r)
  local lines = {}
  lines[1] = (L"|cffffd100%s|r: a merchant pays %s each."):format(r.name, Short(r.sell))
  local e = DB().items[r.id]
  local shown, n = 0, e and math.floor(#e.l / 3) or 0
  for i = 1, e and #e.l or 0, 3 do
    if shown >= 5 then
      lines[#lines + 1] = (L"  ... and %d more auctions"):format(n - shown)
      break
    end
    local cost, units, value = e.l[i], e.l[i + 1], e.l[i + 2]
    lines[#lines + 1] = (L"  %d × for %s (%s each), merchant %s: |cff40ff40+%s|r"):format(units, Short(cost), Short(cost / units),
      Short(value), Short(value - cost))
    shown = shown + 1
  end
  if state.id == r.id then
    if state.phase == "search" then lines[#lines + 1] = L"|cff66ccffSearching the auction house...|r"
    elseif state.phase == "buying" or state.phase == "quote" then lines[#lines + 1] = L"|cff66ccffBuying...|r"
    elseif state.phase == "confirm" and state.pending then
      lines[#lines + 1] = (L"|cff66ccffThe game's price: %d for %s. Click Confirm to buy.|r"):format(state.pending.units, Short(state.pending.total))
    elseif state.phase == "failed" then
      lines[#lines + 1] = "|cffff9933" .. L(REASONS[state.reason] or REASONS.error) .. "|r"
    elseif state.reason == "empty" then
      lines[#lines + 1] = L"|cffff9933The auction house answered with nothing; the scan's listings are kept. Check again.|r"
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
  local listings = 0
  for _, r in ipairs(rows) do listings = listings + r.n end
  c1.sub:SetText((L"%d items, %d auctions"):format(#rows, listings))
  c2.label:SetText(L"YOUR RESULT")
  c2.value:SetText(Short(d.stats.earned - d.stats.costSold))
  local heldUnits, heldValue = 0, 0
  for id, h in pairs(d.held) do
    heldUnits = heldUnits + h.units
    heldValue = heldValue + HeldValue(id, h)
  end
  c2.sub:SetText((L"%d sold · to sell: %d (%s at the merchant)"):format(d.stats.sold, heldUnits, Short(heldValue)))
  c3.label:SetText(L"SCAN")
  c3.value:SetText(d.at and Ago(d.at) or (L"|cffff9933no scan yet|r"))
  c3.sub:SetText(d.at and ((L"%d auctions, %d of them yours (left out)"):format(d.auctions or 0, d.own or 0)
    .. ((d.unresolved or 0) > 0 and (L", %d items unknown"):format(d.unresolved) or "")
    .. (d.partial and L", partial" or "")) or (L"/wa ah at the auction house"))
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
      c[6]:SetText(r.live and ("|cff66ccff" .. L"live " .. date("%H:%M", math.floor(r.live)) .. "|r") or (L"scan"))
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
  elseif selected and state.id == selected and state.phase == "ready" then
    frame.detail:SetText(L"Checked again: nothing of it is below the merchant price any more.")
  elseif not d.at then
    frame.detail:SetText(L"No scan yet. At the auction house type /wa ah: one full scan finds every auction below the merchant price.")
  elseif #rows == 0 then
    frame.detail:SetText(L"No auction is below the merchant price in the last scan.")
  else
    frame.detail:SetText(L"Click an item to see its auctions.")
  end
  local line = WA.AHLine
  local can = line and line.CanAct()
  frame.check:SetEnabled(AHOpen() and sel ~= nil and not Busy() or false)
  local p = state.pending
  if state.phase == "confirm" and p and state.id == selected then
    p.shown = p.total
    frame.buy:SetText((L"Confirm: %d for %s (+%s)"):format(p.units, Short(p.total), Short(p.value - p.total)))
    frame.buy:SetEnabled(can and true or false)
  else
    local nb = sel and state.id == sel.id and F.NextBuy()
    if nb and nb.units > 0 then
      frame.buy:SetText((L"Buy %d for %s (+%s)"):format(nb.units, Short(nb.cost), Short(nb.value - nb.cost)))
      frame.buy:SetEnabled(nb.afford and can and nb.cost < nb.value and true or false)
    else
      frame.buy:SetText(nb and (L"Not enough gold") or (Busy() and L"Buying..." or L"Buy"))
      frame.buy:SetEnabled(false)
    end
  end
end

function F.Toggle()
  frame = frame or Build()
  if frame:IsShown() then frame:Hide() return end
  frame:ClearAllPoints()
  if AHOpen() and AuctionHouseFrame and AuctionHouseFrame:IsShown() then
    frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
  else
    frame:SetPoint("CENTER")
  end
  frame:Show()
  -- while you buy, background price searches wait
  if WA.AHLine then WA.AHLine.SetPaused(true) end
  F.Refresh()
end

---------------------------------------------------------------------------
-- merchant button
---------------------------------------------------------------------------
local sellButton
function F.UpdateMerchant()
  if not sellButton then return end
  local stacks = F.SellableStacks()
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
local function Safe(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and geterrorhandler then geterrorhandler()(err) end
end
ev:SetScript("OnEvent", function(_, event, ...)
  if event == "COMMODITY_PRICE_UPDATED" then
    Safe(OnPrice, ...)
  elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
    local p = state.pending
    if p and p.kind == "commodity" and not p.confirmed then Done(false, L"The game cannot hold that price now; checking the item again.") end
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    local p = state.pending
    if p and p.kind == "commodity" and p.confirmed then
      Done(true)
    else
      local l = Found("commodity")
      if l then
        Bought(l.id, l.units, l.cost, l.value)
        if F.Refresh then F.Refresh() end
      end
    end
  elseif event == "COMMODITY_PURCHASE_FAILED" then
    local p = state.pending
    if p and p.kind == "commodity" and p.confirmed then
      Done(false, L"The purchase did not go through: the auctions were gone.")
    else
      Found("commodity")
    end
  elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
    local auctionID = Plain(...)
    local p = state.pending
    if p and p.kind == "item" and auctionID == p.auctionID then
      Done(true)
    else
      local l = Found("item", auctionID)
      if l then
        Bought(l.id, l.units, l.cost, l.value)
        if F.Refresh then F.Refresh() end
      end
    end
  elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
    local p = state.pending
    if p and (p.kind == "item" or p.confirmed or state.phase == "quote") then
      Done(false, L"The purchase did not go through: the auctions were gone.")
    end
  elseif event == "AUCTION_HOUSE_SHOW" then
    if not ahButton and AuctionHouseFrame then
      ahButton = CreateFrame("Button", nil, AuctionHouseFrame, "UIPanelButtonTemplate")
      ahButton:SetSize(110, 22)
      ahButton:SetPoint("TOPRIGHT", AuctionHouseFrame, "TOPRIGHT", -164, -1)
      ahButton:SetText(L"AH → vendor")
      ahButton:SetScript("OnClick", F.Toggle)
    end
    if frame and frame:IsShown() and WA.AHLine then WA.AHLine.SetPaused(true) end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    -- a held quote goes with the window; a confirmed purchase may still land (LATE)
    local p = state.pending
    if p then
      state.pending = nil
      if p.kind == "item" or p.confirmed then Lose(p) end
    end
    state.phase = nil
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
    local d = DB()
    watch = { counts = {}, removed = {} }
    local now = BagCounts()
    for id in pairs(d.held) do watch.counts[id] = now[id] or 0 end
    F.UpdateMerchant()
  elseif event == "MERCHANT_CLOSED" then
    Safe(WatchMerchant)
    watch = nil
  elseif event == "BAG_UPDATE_DELAYED" then
    if watch then
      Safe(WatchMerchant)
      F.UpdateMerchant()
      if frame and frame:IsShown() then F.Refresh() end
    end
  elseif event == "MAIL_INBOX_UPDATE" then
    Safe(ReadInbox)
  elseif event == "MAIL_CLOSED" then
    -- the bags settle a moment after the last item is taken
    C_Timer.After(2, function() Safe(Reconcile) end)
  end
end)
for _, e in ipairs({ "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED",
  "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_SHOW_ERROR", "AUCTION_HOUSE_SHOW",
  "AUCTION_HOUSE_CLOSED", "MERCHANT_SHOW", "MERCHANT_CLOSED", "BAG_UPDATE_DELAYED", "MAIL_INBOX_UPDATE", "MAIL_CLOSED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
if WA.AHLine then WA.AHLine.OnChange(function() if frame and frame:IsShown() then F.Refresh() end end) end

WA.Command("flip", function() F.Toggle() end, L"/wa flip – auctions below the merchant price (AH → vendor)")
