-- Waystone: the line to the auction house.
--
-- Every search Waystone sends goes through here, one at a time, and purchases wait for the line
-- to be free. What the Forever client needs (seen in play, and in other addons written for it):
--   * one message out at a time (C_AuctionHouse.IsThrottledMessageSystemReady), and at most 100
--     searches a minute;
--   * an item key the client knows: MakeItemKey(itemID) is searched only once GetItemKeyInfo has
--     the item (ITEM_KEY_ITEM_INFO_RECEIVED); a search sent before that never answers;
--   * gear that does not stack is found with SendSellSearchQuery and a key with level and suffix
--     cleared (every variant comes back); SendSearchQuery with such a key finds nothing;
--   * the first answer can be empty although there are auctions: an empty answer that does not
--     say it is complete is asked once more;
--   * results come cheapest first, a page at a time (RequestMore* for the next).
--
--   Line.Search(itemID, onDone(res, reason), opts) -- opts.priority: ahead of background searches;
--     opts.below: read more pages while the cheapest prices are still under this (copper each).
--     res = { commodity, full, at, rows }, rows cheapest first:
--       commodity: { unit, qty, own }                    qty includes own (numOwnerItems) units
--       item:      { auctionID, buyout, qty, own, link }  buyout is the price of ONE auction, qty
--                  how many such auctions the row holds; one PlaceBid buys one
--     reason without res: "closed", "uncached", "timeout", "error"
--   Line.IsOpen(), Line.CanAct() -> ok, why, Line.Reserve() -> release()
--   Line.SetPaused(on): background (not priority) searches wait

local _, WA = ...
local Line = {}
WA.AHLine = Line

Line.TIMEOUT = 6      -- seconds for an answer
Line.KEY_WAIT = 8     -- seconds for the client to learn an item's key
Line.PER_MINUTE = 95  -- searches a minute (the game allows 100)
Line.MAX_PAGES = 10

local open = false
local queue, active = {}, nil
local sentAt = {}
local reserved = nil
local paused = false
local listeners = {}

local function Plain(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end
Line.Plain = Plain

local function Changed()
  for _, fn in ipairs(listeners) do pcall(fn) end
end
function Line.OnChange(fn) listeners[#listeners + 1] = fn end

function Line.IsOpen() return open end

local function Ready()
  local AH = C_AuctionHouse
  if not AH then return false end
  if AH.IsThrottledMessageSystemReady then return AH.IsThrottledMessageSystemReady() == true end
  return true
end

local function SearchAllowed()
  local now = GetTime()
  while sentAt[1] and now - sentAt[1] >= 61 do table.remove(sentAt, 1) end
  return #sentAt < Line.PER_MINUTE
end

-- Whether a purchase can go out now (inside the player's click).
function Line.CanAct()
  if not open then return false, "closed" end
  if active or reserved then return false, "busy" end
  if not Ready() then return false, "throttled" end
  return true
end

-- Holds the line for a purchase: no search goes out until release() is called.
function Line.Reserve()
  local token = {}
  reserved = token
  Changed()
  return function()
    if reserved == token then
      reserved = nil
      Changed()
      if Line.Pump then Line.Pump() end
    end
  end
end

function Line.SetPaused(on)
  paused = on and true or false
  if not paused and Line.Pump then Line.Pump() end
end

local Pump

-- A timer that does nothing once the job moved on.
local function Arm(job, seconds, fn)
  job.token = (job.token or 0) + 1
  local token = job.token
  C_Timer.After(seconds, function()
    if job.token == token and not job.done then fn(job) end
  end)
end

local function Finish(job, res, reason)
  if job.done then return end
  job.done = true
  job.token = (job.token or 0) + 1
  if active == job then active = nil end
  for _, cb in ipairs(job.callbacks) do
    local ok, err = pcall(cb, res, reason)
    if not ok and geterrorhandler then geterrorhandler()(err) end
  end
  Changed()
  Pump()
end

local function Sorts()
  local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price
  if order == nil then return {} end
  return { { sortOrder = order, reverseSort = false } }
end

local function Count(job)
  local AH = C_AuctionHouse
  if job.commodity then return Plain(AH.GetNumCommoditySearchResults(job.itemID)) or 0 end
  return Plain(AH.GetNumItemSearchResults(job.key)) or 0
end

local function Full(job)
  local AH = C_AuctionHouse
  if job.commodity then
    return AH.HasFullCommoditySearchResults and AH.HasFullCommoditySearchResults(job.itemID) == true or false
  end
  return AH.HasFullItemSearchResults and AH.HasFullItemSearchResults(job.key) == true or false
end

local function Row(job, i)
  local AH = C_AuctionHouse
  if job.commodity then
    local r = AH.GetCommoditySearchResultInfo(job.itemID, i)
    if type(r) ~= "table" then return nil end
    local unit, qty = Plain(r.unitPrice), Plain(r.quantity)
    if type(unit) ~= "number" or type(qty) ~= "number" or qty <= 0 then return nil end
    local own = Plain(r.numOwnerItems)
    if type(own) ~= "number" then own = (r.containsOwnerItem == true) and qty or 0 end
    return { unit = unit, qty = qty, own = math.min(own, qty) }
  end
  local r = AH.GetItemSearchResultInfo(job.key, i)
  if type(r) ~= "table" then return nil end
  local qty = Plain(r.quantity)
  if type(qty) ~= "number" or qty <= 0 then return nil end
  local buyout = Plain(r.buyoutAmount)
  return { auctionID = r.auctionID, buyout = (type(buyout) == "number" and buyout > 0) and buyout or nil, qty = qty,
    own = r.containsOwnerItem == true, link = Plain(r.itemLink), unit = (type(buyout) == "number" and buyout > 0) and buyout or nil }
end

local function ReadAll(job)
  local rows = {}
  for i = 1, Count(job) do
    local r = Row(job, i)
    if r then rows[#rows + 1] = r end
  end
  return rows
end

local Send

local function OnTimeout(job)
  if job.state == "more" then
    -- the next page never came: what was read is still the cheap end
    return Finish(job, { commodity = job.commodity, full = false, at = time(), rows = ReadAll(job) })
  end
  if not job.resent then
    job.resent = true
    return Send(job)
  end
  Finish(job, nil, "timeout")
end

-- An answer to the job's search (or to its next page).
local function OnAnswer(job)
  local n, full = Count(job), Full(job)
  if n == 0 and not full and not job.retried then
    job.retried = true
    job.state = "again"
    Arm(job, 1, Send)
    return
  end
  -- the cheap end may go on past this page
  if not full and n > 0 and job.below and job.pages < Line.MAX_PAGES then
    local last = Row(job, n)
    if last and last.unit and last.unit < job.below then
      local AH = C_AuctionHouse
      local more = job.commodity and AH.RequestMoreCommoditySearchResults or AH.RequestMoreItemSearchResults
      if more then
        job.pages = job.pages + 1
        job.state = "more"
        local ok, already = pcall(more, job.commodity and job.itemID or job.key)
        if ok and already ~= true then
          Arm(job, Line.TIMEOUT, OnTimeout)
          return
        end
      end
    end
  end
  Finish(job, { commodity = job.commodity, full = full, at = time(), rows = ReadAll(job) })
end

Send = function(job)
  if job.done then return end
  if not open then return Finish(job, nil, "closed") end
  if reserved or not Ready() or not SearchAllowed() then
    job.state = "waiting"
    Arm(job, 1, Send) -- the throttle's ready event comes too; this is the fallback
    return
  end
  local AH = C_AuctionHouse
  local fn = job.equipment and AH.SendSellSearchQuery or AH.SendSearchQuery
  if not fn then return Finish(job, nil, "error") end
  sentAt[#sentAt + 1] = GetTime()
  job.state = "out"
  job.pages = 1
  local ok = pcall(fn, job.key, Sorts(), true)
  if not ok then return Finish(job, nil, "error") end
  Arm(job, Line.TIMEOUT, OnTimeout)
end

-- What kind of search the item needs; false while the client does not know its key.
local function Decide(job)
  local AH = C_AuctionHouse
  local info = AH.GetItemKeyInfo and AH.GetItemKeyInfo(job.key)
  if AH.GetItemKeyInfo and type(info) ~= "table" then return false end
  local maxStack = Plain(select(8, (C_Item and C_Item.GetItemInfo or GetItemInfo)(job.itemID)))
  local stacks = type(maxStack) == "number" and maxStack > 1
  if type(info) == "table" then
    job.commodity = info.isCommodity == true
    job.equipment = info.isEquipment == true and not job.commodity and not stacks
  else
    -- no key info in this client: stackables are commodities, gear is searched as gear
    local equipLoc = select(4, (C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant)(job.itemID))
    job.commodity = stacks
    job.equipment = not stacks and type(equipLoc) == "string" and equipLoc ~= ""
  end
  if job.equipment then
    job.key = { itemID = job.itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
  end
  return true
end

local function Start(job)
  local AH = C_AuctionHouse
  job.key = AH.MakeItemKey and AH.MakeItemKey(job.itemID) or { itemID = job.itemID }
  if Decide(job) then return Send(job) end
  job.state = "key"
  if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, job.itemID) end
  Arm(job, Line.KEY_WAIT, function(j)
    if not Decide(j) then return Finish(j, nil, "uncached") end
    Send(j)
  end)
end

Pump = function()
  if active or reserved or not open then return end
  for i, job in ipairs(queue) do
    if job.priority or not paused then
      table.remove(queue, i)
      active = job
      Changed()
      return Start(job)
    end
  end
end
Line.Pump = Pump

function Line.Search(itemID, onDone, opts)
  opts = opts or {}
  if not open then
    if onDone then pcall(onDone, nil, "closed") end
    return false
  end
  local function Join(job)
    job.callbacks[#job.callbacks + 1] = onDone
    if opts.below and (not job.below or opts.below > job.below) then job.below = opts.below end
  end
  if active and active.itemID == itemID and not active.done then Join(active) return true end
  for i, job in ipairs(queue) do
    if job.itemID == itemID then
      Join(job)
      if opts.priority and not job.priority then
        job.priority = true
        table.remove(queue, i)
        table.insert(queue, 1, job)
      end
      return true
    end
  end
  local job = { itemID = itemID, callbacks = { onDone }, below = opts.below, priority = opts.priority == true, pages = 0 }
  if job.priority then
    local at = #queue + 1
    for i, q in ipairs(queue) do if not q.priority then at = i break end end
    table.insert(queue, at, job)
  else
    queue[#queue + 1] = job
  end
  Pump()
  return true
end

-- Background searches waiting (not counting the one out).
function Line.Waiting() return #queue end
function Line.Busy() return active ~= nil or reserved ~= nil end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, a, b)
  if event == "AUCTION_HOUSE_SHOW" then
    open = true
    Changed()
    Pump()
  elseif event == "AUCTION_HOUSE_CLOSED" then
    open = false
    local was, waiting = active, queue
    queue, active, reserved = {}, nil, nil
    if was then Finish(was, nil, "closed") end
    for _, job in ipairs(waiting) do Finish(job, nil, "closed") end
    Changed()
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    if active and active.state == "waiting" then Send(active) else Pump() end
    Changed()
  elseif not active then
    return
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
    if (active.state == "out" or active.state == "more") and a == active.itemID then
      active.commodity = true
      OnAnswer(active)
    end
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
    if (active.state == "out" or active.state == "more") and type(a) == "table" and a.itemID == active.itemID then
      if active.commodity then
        -- the client answered as an item after all
        active.commodity = false
      end
      if not active.equipment then active.key = a end
      OnAnswer(active)
    end
  elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" or event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
    if active.state == "key" and a == active.itemID then
      if (event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT") and b == false then
        return Finish(active, nil, "uncached")
      end
      if Decide(active) then Send(active) end
    end
  end
end)
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
  "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED", "ITEM_SEARCH_RESULTS_UPDATED",
  "ITEM_SEARCH_RESULTS_ADDED", "ITEM_KEY_ITEM_INFO_RECEIVED", "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }) do
  pcall(ev.RegisterEvent, ev, e)
end
