-- WoW Assistant: crafting to sell to a vendor, worked out in game.
--
-- Which recipes make something a vendor buys for more than the reagents cost on the auction
-- house (or from a vendor, when that is cheaper). The same calculation as the web app's
-- "Vendor" page, but with what the game itself knows:
--   * the vendor price of the product comes from the client (GetItemInfo), so it is exact;
--   * reagent prices are an order book: every listing, from the newest of the web app's hourly
--     download (Market.lua, written by the uploader) and the in-game full scan (/wa ah), replaced
--     live whenever the auction house shows the listings of a reagent (your own search, the
--     "Árak frissítése" button, or the reagents of the best crafts when the window opens there);
--   * your professions and skill come from the skill list, the recipes you know from the
--     profession window (open it once per profession).
-- Costs are bought listing by listing, cheapest first; a batch ends at the craft where buying
-- more would cost more than the vendor pays. A listing that is not a commodity is bought whole.
--
-- /wa vendor opens the window; at the auction house there is a button for it too.

local _, WA = ...
local L = WA.L
local R = WowAssistantRecipes
local VC = {}
WowAssistantVC = VC
WA.VC = VC

local MAX_CRAFTS = 1000
local GIVE_UP_AFTER = 25
local ROWS = 14
local SOURCE = WA.LR { ["2"] = "drop", ["4"] = "quest", ["5"] = L"recipe vendor", ["6"] = L"trainer", ["7"] = L"discovery" }

local function Print(msg) WA.Print(msg) end

---------------------------------------------------------------------------
-- data
---------------------------------------------------------------------------
VC.reagents = {}
local recipes = {} -- parsed rows
if R then
  for _, r in ipairs(R.recipes) do
    local reag = r[10]
    if r[4] ~= 0 then -- recipes without a product (enchants) are only for skill routes
    recipes[#recipes + 1] = {
      spell = r[1], prof = r[2], orange = r[3], product = r[4], min = r[5], max = r[6],
      trainer = r[7], cd = r[8], name = r[9], reagents = reag, sources = r[11],
    }
    for i = 1, #reag, 2 do VC.reagents[reag[i]] = true end
    end
  end
end

local function Market()
  WowAssistantDB = WowAssistantDB or {}
  WowAssistantDB.market = WowAssistantDB.market or { books = {}, live = {} }
  local m = WowAssistantDB.market
  m.books = m.books or {}
  m.live = m.live or {}
  return m
end

local function CharDB()
  WowAssistantCharDB = WowAssistantCharDB or {}
  WowAssistantCharDB.known = WowAssistantCharDB.known or {}
  return WowAssistantCharDB
end

local function ItemName(id)
  local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or GetItemInfo(id)
  return name or (R and R.names[id]) or ("Item #" .. id)
end

-- Vendor price of one piece: the client's own value when the item is loaded.
local requested = {}
local function SellPrice(id)
  local sell = select(11, GetItemInfo(id))
  if sell then return sell, true end
  if not requested[id] and C_Item and C_Item.RequestLoadItemDataByID then
    requested[id] = true
    pcall(C_Item.RequestLoadItemDataByID, id)
  end
  return R and R.sell[id], false
end

---------------------------------------------------------------------------
-- order books: flat { unitPrice, quantity, whole, ... }, cheapest first
---------------------------------------------------------------------------
local function Flatten(list)
  table.sort(list, function(a, b) return a[1] < b[1] end)
  local out = {}
  for _, l in ipairs(list) do
    local n = #out
    if n > 0 and l[3] == 0 and out[n] == 0 and out[n - 2] == l[1] then
      out[n - 1] = out[n - 1] + l[2]
    else
      out[n + 1], out[n + 2], out[n + 3] = l[1], l[2], l[3]
    end
  end
  return out
end

local version = 0
local dirty = true

-- From the full scan: books[itemID] = { {unit, qty, whole}, ... }.
function VC.SetBooks(books, at)
  local m = Market()
  m.books, m.live, m.at, m.src, m.avg = {}, {}, at or time(), "scan", nil
  for id, list in pairs(books) do m.books[id] = Flatten(list) end
  version, dirty = version + 1, true
  if VC.Refresh then VC.Refresh() end
end

-- Live listings of one item. When the auction house sent only the cheapest part, the dearer
-- listings from the scan are kept above the highest live price.
local function UpdateBook(id, list, complete)
  if #list == 0 and not complete then return end
  local m = Market()
  local book = Flatten(list)
  if not complete then
    local top = book[#book - 2] or 0
    local old = m.books[id]
    if old then
      for i = 1, #old, 3 do
        if old[i] > top then book[#book + 1], book[#book + 2], book[#book + 3] = old[i], old[i + 1], old[i + 2] end
      end
    end
  end
  m.books[id] = book
  m.live[id] = time()
  version, dirty = version + 1, true
  if VC.Refresh then VC.Refresh() end
end

-- One live search's answer (AHLine.lua). Your own units cannot be bought. An item row is a set of
-- like auctions, one item each, at the row's buyout (the price of ONE).
local function OnLive(id, res)
  if not res or not VC.reagents[id] then return end
  local list = {}
  for _, r in ipairs(res.rows) do
    if res.commodity then
      local qty = r.qty - r.own
      if r.unit > 0 and qty > 0 then list[#list + 1] = { r.unit, qty, 0 } end
    elseif r.buyout and not r.own then
      list[#list + 1] = { r.buyout, r.qty, 0 }
    end
  end
  UpdateBook(id, list, res.full)
end

-- Quantity-weighted average, ignoring listings over 3x the median.
local avgCache, avgVersion = {}, -1
local function AvgPrice(id)
  if avgVersion ~= version then avgCache, avgVersion = {}, version end
  local v = avgCache[id]
  if v ~= nil then return v or nil end
  local m = Market()
  -- the web app's average covers every listing; a live search replaces it with what the game saw
  if m.avg and m.avg[id] and not m.live[id] then avgCache[id] = m.avg[id] return m.avg[id] end
  local b = m.books[id]
  if not b or #b == 0 then avgCache[id] = false return nil end
  local total = 0
  for i = 2, #b, 3 do total = total + b[i] end
  local seen, median = 0, b[1]
  for i = 1, #b, 3 do
    seen = seen + b[i + 1]
    if seen * 2 >= total then median = b[i] break end
  end
  local units, sum = 0, 0
  for i = 1, #b, 3 do
    if b[i] > median * 3 then break end
    units, sum = units + b[i + 1], sum + b[i] * b[i + 1]
  end
  v = units > 0 and sum / units or nil
  avgCache[id] = v or false
  return v
end

-- The web app's order books (Market.lua from the uploader), when newer than what the game has.
table.insert(WA.onLoad, function()
  local file = WowAssistantMarketFile
  if type(file) ~= "table" or type(file.books) ~= "table" or not file.at then return end
  local m = Market()
  if m.at and m.at >= file.at then return end
  m.books, m.live, m.at, m.src, m.avg = file.books, {}, file.at, "web", file.avg
  version, dirty = version + 1, true
end)

---------------------------------------------------------------------------
-- the calculation
---------------------------------------------------------------------------
local function NewBuyer(id)
  local book = Market().books[id] or {}
  local vendor = R.vendor[id]
  return { b = book, i = 1, left = book[2] or 0, vendor = vendor, held = 0,
    ahUnits = 0, ahCost = 0, ahMax = nil, vUnits = 0, vCost = 0 }
end

-- Cost of the next `units`, or nil when they cannot be bought.
local function Take(B, units)
  local cost = 0
  local fromHeld = math.min(B.held, units)
  B.held, units = B.held - fromHeld, units - fromHeld
  while units > 0 do
    local price = B.b[B.i]
    if B.vendor and (not price or B.vendor <= price) then
      cost = cost + B.vendor * units
      B.vUnits, B.vCost = B.vUnits + units, B.vCost + B.vendor * units
      return cost
    end
    if not price then return nil end
    local whole = B.b[B.i + 2] == 1
    local n = whole and B.left or math.min(B.left, units)
    cost = cost + price * n
    B.ahUnits, B.ahCost = B.ahUnits + n, B.ahCost + price * n
    B.ahMax = math.max(B.ahMax or 0, price)
    B.left = B.left - n
    if n > units then B.held = B.held + n - units end
    units = units - math.min(n, units)
    if B.left == 0 then
      B.i = B.i + 3
      B.left = B.b[B.i + 1] or 0
    end
  end
  return cost
end

local function Simulate(reag, incomeEach, crafts, stopWhenLosing)
  local buyers = {}
  for i = 1, #reag, 2 do buyers[#buyers + 1] = NewBuyer(reag[i]) end
  local cum, spent, losing = 0, 0, 0
  local bestN, bestProfit, bestCost, first = 0, 0, 0, nil
  for n = 1, crafts do
    local c = 0
    for k, B in ipairs(buyers) do
      local x = Take(B, reag[k * 2])
      if not x then return bestN, bestProfit, bestCost, first, buyers end
      c = c + x
    end
    first = first or c
    spent = spent + c
    cum = cum + incomeEach - c
    if cum > bestProfit then
      bestN, bestProfit, bestCost, losing = n, cum, spent, 0
    elseif stopWhenLosing then
      losing = losing + 1
      if losing >= GIVE_UP_AFTER then break end
    end
  end
  return bestN, bestProfit, bestCost, first, buyers
end

-- Exactly `crafts` crafts, cheapest listings first: how many could be bought, their cost, the
-- cost of the first one, and the buyers (for the shopping list).
local function CostOf(reag, crafts)
  local buyers = {}
  for i = 1, #reag, 2 do buyers[#buyers + 1] = NewBuyer(reag[i]) end
  local spent, first = 0, nil
  for n = 1, crafts do
    local c = 0
    for k, B in ipairs(buyers) do
      local x = Take(B, reag[k * 2])
      if not x then return n - 1, spent, first, buyers end
      c = c + x
    end
    first = first or c
    spent = spent + c
  end
  return crafts, spent, first, buyers
end

-- When the AH prices a craft uses were seen: the oldest of the reagents bought on the AH (a live
-- search, or the scan / the web app's data). nil when everything comes from a merchant.
local STALE = 3600
local function PricesAt(reag, buyers)
  local m = Market()
  local oldest
  for k, B in ipairs(buyers or {}) do
    if B.ahUnits > 0 then
      local t = m.live[reag[k * 2 - 1]] or m.at
      if t and (not oldest or t < oldest) then oldest = t end
    end
  end
  return oldest
end
VC.STALE = STALE

-- How many of `crafts` your gold pays for, cheapest listings first.
local function Affordable(reag, crafts, money)
  local buyers = {}
  for i = 1, #reag, 2 do buyers[#buyers + 1] = NewBuyer(reag[i]) end
  local spent = 0
  for n = 1, crafts do
    local c = 0
    for k, B in ipairs(buyers) do
      local x = Take(B, reag[k * 2])
      if not x then return n - 1 end
      c = c + x
    end
    if spent + c > money then return n - 1 end
    spent = spent + c
  end
  return crafts
end
VC.Affordable = Affordable

-- Your professions and skill (Game.lua: skill lines or the profession API, whichever the client has).
local function MyProfessions()
  local mine = {}
  for _, p in ipairs(WA.Game.Professions()) do mine[p.id] = p.skill end
  return mine
end

-- qty: how many times you craft each recipe for one trip to the vendor; nil = the best batch
-- (as many as still make money with the cheapest listings).
VC.filter = { prof = "mine", skill = "current", known = false, text = "", sort = 8, dir = -1, qty = nil }
local SORT_KEYS = { "name", "product", "each", "costEach", "gainEach", "items", "income", "profit" }

local results = {}
local unpriced = 0
local function Compute()
  results, unpriced = {}, 0
  if not R then return end
  local f = VC.filter
  local mine = MyProfessions()
  local known = CharDB().known
  local text = (f.text or ""):lower()
  for _, r in ipairs(recipes) do
    local skill = mine[r.prof]
    local pass = true
    if f.prof == "mine" then pass = skill ~= nil
    elseif f.prof ~= "all" then pass = r.prof == f.prof end
    if pass and f.skill == "current" then pass = skill ~= nil and r.orange <= skill end
    local isKnown = known[r.prof] and known[r.prof][r.name] or false
    if pass and f.known then pass = isKnown end
    if pass and text ~= "" then
      pass = r.name:lower():find(text, 1, true) ~= nil or ItemName(r.product):lower():find(text, 1, true) ~= nil
    end
    local each, exact = nil, false
    if pass then
      each, exact = SellPrice(r.product)
      pass = each and each > 0
    end
    if pass then
      local income = each * r.min
      local made, profit, cost, first, buyers
      local want = f.qty and math.max(1, math.min(MAX_CRAFTS, f.qty)) or nil
      if r.cd > 0 then want = want and 1 end
      if want then
        made, cost, first, buyers = CostOf(r.reagents, want)
        profit = income * made - cost
      else
        made, profit, cost, first, buyers = Simulate(r.reagents, income, r.cd > 0 and 1 or MAX_CRAFTS, true)
      end
      if not first then
        unpriced = unpriced + 1
      elseif made > 0 and profit > 0 then
        local avgCost = 0
        for i = 1, #r.reagents, 2 do
          local id, q = r.reagents[i], r.reagents[i + 1]
          local avg, vendor = AvgPrice(id), R.vendor[id]
          local unit = (vendor and (not avg or vendor <= avg)) and vendor or avg
          if not unit then avgCost = nil break end
          avgCost = avgCost + unit * q
        end
        local avgProfit = avgCost and (each * (r.min + r.max) / 2 - avgCost)
        do
          local status
          if isKnown then status = L"|cff40ff40known|r"
          elseif skill and r.orange > skill then status = r.orange .. L" skill needed"
          elseif r.trainer >= 0 then status = L"trainer"
          else
            local s = {}
            for code in (r.sources or ""):gmatch("%d+") do if SOURCE[code] then s[#s + 1] = SOURCE[code] end end
            status = #s > 0 and (L"recipe: " .. table.concat(s, ", ")) or (L"recipe needed")
          end
          local items = made * r.min
          results[#results + 1] = {
            r = r, each = each, exact = exact, first = first, firstProfit = income - first,
            avgCost = avgCost, avgProfit = avgProfit, crafts = made, cost = cost,
            income = income * made, profit = profit, status = status, items = items,
            costEach = cost / items, gainEach = profit / items, product = ItemName(r.product),
            capped = not want and r.cd == 0 and made >= MAX_CRAFTS,
            short = want and made < want,
            pricesAt = PricesAt(r.reagents, buyers),
          }
        end
      end
    end
  end
  local key = SORT_KEYS[f.sort] or "profit"
  table.sort(results, function(a, b)
    local x, y = a[key], b[key]
    if key == "name" then x, y = a.r.name, b.r.name end
    if x == nil and y == nil then return a.r.spell < b.r.spell end
    if x == nil then return false end
    if y == nil then return true end
    if x == y then return a.r.spell < b.r.spell end
    if f.dir > 0 then return x < y end
    return x > y
  end)
  dirty = false
end

-- For tests outside the game.
function VC.Compute() Compute() return results, unpriced end

-- Recipes you know, read whenever a profession window is open.
local function ScanKnown()
  local name, rank
  if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillLine then
    local _, n = C_TradeSkillUI.GetTradeSkillLine()
    name = n
  end
  if not name and GetTradeSkillLine then name = GetTradeSkillLine() end
  local list = {}
  if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
    for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
      local info = C_TradeSkillUI.GetRecipeInfo(id)
      if info and info.learned and info.name then list[info.name] = true end
    end
  elseif GetNumTradeSkills then
    for i = 1, GetNumTradeSkills() do
      local rname, kind = GetTradeSkillInfo(i)
      if rname and kind ~= "header" then list[rname] = true end
    end
  end
  VC.StoreKnown(name, list)
end

local function ScanKnownCraft() -- Enchanting uses the craft window in this era
  if not GetNumCrafts then return end
  local list = {}
  for i = 1, GetNumCrafts() do
    local rname, _, kind = GetCraftInfo(i)
    if rname and kind ~= "header" then list[rname] = true end
  end
  VC.StoreKnown(GetCraftDisplaySkillLine and GetCraftDisplaySkillLine() or "Enchanting", list)
end

function VC.StoreKnown(profName, list)
  if not profName or not R then return end
  for id, n in pairs(R.professions) do
    if n == profName and next(list) then
      CharDB().known[id] = list
      dirty = true
      if VC.Refresh then VC.Refresh() end
      return
    end
  end
end

---------------------------------------------------------------------------
-- live price requests ("Árak frissítése")
---------------------------------------------------------------------------
local function AHOpen() return WA.AHLine and WA.AHLine.IsOpen() end

function VC.RequestPrices(ids, quiet)
  if not AHOpen() then
    if not quiet then Print(L"Open the auction house for live prices.") end
    return
  end
  -- background searches: one at a time, after anything the player clicked
  for _, id in ipairs(ids) do
    WA.AHLine.Search(id, function(res) OnLive(id, res) end)
  end
end

-- Live prices for the reagents of the best crafts of every profession, whatever the filter
-- shows: the hourly data can be an hour old, and the list is only right when the cheapest
-- listings are still there. Rank 1 of every profession is asked first, then rank 2, and so on.
local TOP = 10
function VC.RefreshTop(quiet)
  local f = VC.filter
  local saved = { f.prof, f.skill, f.known, f.text }
  f.prof, f.skill, f.known, f.text = "all", "max", false, ""
  Compute()
  local byProf, profs = {}, 0
  for _, x in ipairs(results) do
    local p = x.r.prof
    if not byProf[p] then byProf[p] = {} profs = profs + 1 end
    table.insert(byProf[p], x)
  end
  f.prof, f.skill, f.known, f.text = saved[1], saved[2], saved[3], saved[4]
  Compute()
  local lists = {}
  for _, list in pairs(byProf) do
    table.sort(list, function(a, b) return a.profit > b.profit end)
    lists[#lists + 1] = list
  end
  table.sort(lists, function(a, b) return a[1].r.prof < b[1].r.prof end)
  local ids, seen, crafts = {}, {}, 0
  for rank = 1, TOP do
    for _, list in ipairs(lists) do
      local x = list[rank]
      if x then
        crafts = crafts + 1
        local reag = x.r.reagents
        for k = 1, #reag, 2 do
          local id = reag[k]
          if not seen[id] and not (R.vendorReagents and R.vendorReagents[id] and R.vendor[id]) then
            seen[id] = true
            ids[#ids + 1] = id
          end
        end
      end
    end
  end
  if #ids > 0 then
    VC.RequestPrices(ids, quiet)
    if not quiet then
      Print((L"Requesting live prices for %d materials: %d professions, the best %d crafts of each (%d recipes)."):format(#ids, profs, TOP, crafts))
    end
  end
  return #ids, profs, crafts
end

---------------------------------------------------------------------------
-- window
---------------------------------------------------------------------------
local frame
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
local function Coins(c) return GetCoinTextureString and GetCoinTextureString(math.floor(c + 0.5)) or Short(c) end
local function Signed(c)
  if not c then return "|cff888888–|r" end
  return c >= 0 and ("|cff40ff40+|r" .. Short(c)) or Short(c)
end

-- { title, width, justify, tooltip }; the last two are what one trip to the vendor brings
local COLS = WA.LR {
  { L"Recipe", 222, "LEFT", L"The recipe, the profession and where you learn it." },
  { L"Product", 150, "LEFT", L"What you craft and sell." },
  { L"Vendor / ea", 70, "RIGHT", L"What the merchant pays for one (the game's own data)." },
  { L"Cost / ea", 74, "RIGHT", L"The materials' price for one, from the cheapest AH listings upward, without your own auctions. Orange *: the AH price is over an hour old." },
  { L"Profit / ea", 72, "RIGHT", L"Vendor price minus cost, per item." },
  { L"Qty", 52, "RIGHT", L"How many you sell. Orange: the AH supply covers only this many." },
  { L"Sale", 80, "RIGHT", L"What the merchant pays for all of it." },
  { L"Net profit", 90, "RIGHT", L"Sale minus the materials' price: this much more money." },
}
local W = 900
local ROW_H = 20

-- Dropdown choices.
local function ProfItems()
  local list = { { "mine", L"My professions" }, { "all", L"All professions" } }
  local ids = {}
  for id in pairs(R.professions) do ids[#ids + 1] = id end
  table.sort(ids, function(a, b) return R.professions[a] < R.professions[b] end)
  for _, id in ipairs(ids) do list[#list + 1] = { id, R.professions[id] } end
  return list
end
local function SkillItems()
  return { { "current", L"What I can make now (skill)" }, { "max", L"Every recipe up to 300" } }
end

local function Build()
  local St = WA.Style
  local f = St.Window("WowAssistantVendorFrame", W, 0, L"Crafting for the vendor")
  local inset = f.inset
  local y0 = -f.top
  f:SetHeight(f.top + 150 + ROWS * ROW_H + 124)
  f.offset, f.sel = 0, nil

  -- filters: profession, skill, known only, search
  f.prof = St.Dropdown(f, 190, ProfItems, function() return VC.filter.prof end, function(v)
    VC.filter.prof = v
    if v ~= "mine" and type(v) ~= "number" then VC.filter.skill = "max" end
    dirty = true
    VC.Refresh()
  end)
  f.prof:SetPoint("TOPLEFT", inset - (f.prof.SetupMenu and 0 or 14), y0)
  f.skill = St.Dropdown(f, 190, SkillItems, function() return VC.filter.skill end, function(v)
    VC.filter.skill = v
    dirty = true
    VC.Refresh()
  end)
  f.skill:SetPoint("LEFT", f.prof, "RIGHT", f.prof.SetupMenu and 8 or -16, 0)
  local known = St.Check(f, L"only what I know", function(on) VC.filter.known = on dirty = true VC.Refresh() end)
  known:SetPoint("LEFT", f.skill, "RIGHT", f.skill.SetupMenu and 10 or -6, 0)
  local search = St.Search(f, L"Search:", 150, function(text) VC.filter.text = text dirty = true VC.Refresh() end)
  search:SetPoint("TOPRIGHT", -inset, y0 - 2)

  -- the three numbers that matter, as cards
  f.cards = {}
  local cw = math.floor((W - 2 * inset - 20) / 3)
  for i = 1, 3 do
    local c = CreateFrame("Frame", nil, f, "BackdropTemplate")
    St.Panel(c, St.C.card, St.C.edge, 0.4)
    c:SetSize(cw, 60)
    c:SetPoint("TOPLEFT", inset + (i - 1) * (cw + 10), y0 - 34)
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

  -- how many times you craft: one number for every recipe, the values follow it
  local qy = y0 - 104
  local ql = f:CreateFontString(nil, "OVERLAY", "WowAssistantFontNormalSmall")
  ql:SetPoint("TOPLEFT", inset, qy - 4)
  ql:SetText(L"How many crafts:")
  local function SetQty(n)
    VC.filter.qty = n and math.max(1, math.min(MAX_CRAFTS, math.floor(n))) or nil
    WowAssistantDB.vcQty = VC.filter.qty
    f.qtyBox.setting = true
    f.qtyBox:SetText(VC.filter.qty and tostring(VC.filter.qty) or "")
    f.qtyBox.setting = false
    dirty = true
    VC.Refresh()
  end
  f.SetQty = SetQty
  local minus = St.Button(f, "–", 24, function() SetQty((VC.filter.qty or 2) - (IsShiftKeyDown() and 10 or 1)) end)
  minus:SetPoint("LEFT", ql, "RIGHT", 8, 0)
  local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  box:SetSize(46, 20)
  box:SetPoint("LEFT", minus, "RIGHT", 8, 0)
  box:SetAutoFocus(false)
  box:SetNumeric(true)
  box:SetMaxLetters(4)
  box:SetFontObject("WowAssistantFontHighlightSmall")
  box:SetJustifyH("CENTER")
  box:SetScript("OnTextChanged", function(self)
    if self.setting then return end
    local n = tonumber(self:GetText() or "")
    VC.filter.qty = n and n > 0 and math.min(MAX_CRAFTS, n) or nil
    WowAssistantDB.vcQty = VC.filter.qty
    dirty = true
    VC.Refresh()
  end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  f.qtyBox = box
  local plus = St.Button(f, "+", 24, function() SetQty((VC.filter.qty or 0) + (IsShiftKeyDown() and 10 or 1)) end)
  plus:SetPoint("LEFT", box, "RIGHT", 4, 0)
  f.presets = {}
  local px = plus
  for _, p in ipairs({ { 1, "1" }, { 5, "5" }, { 20, "20" }, { nil, L"Best batch" } }) do
    local b = St.Button(f, p[2], p[1] and 34 or 104, function() SetQty(p[1]) end)
    b:SetPoint("LEFT", px, "RIGHT", px == plus and 12 or 4, 0)
    b.qty = p[1]
    f.presets[#f.presets + 1] = b
    px = b
  end

  f.status = f:CreateFontString(nil, "OVERLAY", "WowAssistantFontDisableSmall")
  f.status:SetPoint("TOPRIGHT", -inset, qy - 6)
  f.status:SetWidth(220)
  f.status:SetJustifyH("RIGHT")
  f.status:SetWordWrap(false)

  -- column headers: click to sort
  local x = inset
  local headY = y0 - 136
  f.heads = {}
  for i, c in ipairs(COLS) do
    local h = CreateFrame("Button", nil, f)
    h:SetSize(c[2], 18)
    h:SetPoint("TOPLEFT", x, headY)
    local t = h:CreateFontString(nil, "OVERLAY", "WowAssistantFontDisableSmall")
    t:SetAllPoints()
    t:SetJustifyH(c[3])
    t:SetWordWrap(false)
    h.text = t
    h:SetScript("OnClick", function()
      if VC.filter.sort == i then VC.filter.dir = -VC.filter.dir
      else VC.filter.sort, VC.filter.dir = i, (i == 1 or i == 2) and 1 or -1 end
      dirty = true
      VC.Refresh()
    end)
    h:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(WA.Fix(c[1]), 1, 0.82, 0)
      GameTooltip:AddLine(WA.Fix(c[4] .. L" Click: sort."), 1, 1, 1, true)
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
    row:SetScript("OnClick", function(b) if b.res then f.sel = b.res.r.spell VC.Refresh() end end)
    f.rows[i] = row
  end
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta)
    f.offset = math.max(0, math.min(math.max(0, #results - ROWS), f.offset - delta * 3))
    VC.Refresh()
  end)

  -- details of the selected recipe, and the price buttons on the right
  local top = headY - 32 - ROWS * ROW_H
  f.detail = f:CreateFontString(nil, "OVERLAY", "WowAssistantFontHighlightSmall")
  f.detail:SetPoint("TOPLEFT", inset, top)
  f.detail:SetPoint("RIGHT", -(inset + 236), 0)
  f.detail:SetJustifyH("LEFT")
  f.detail:SetJustifyV("TOP")
  f.refresh = St.Button(f, L"Refresh prices", 230, function()
    local res
    for _, x2 in ipairs(results) do if x2.r.spell == f.sel then res = x2 end end
    if not res then return end
    local ids = {}
    for i = 1, #res.r.reagents, 2 do if not R.vendor[res.r.reagents[i]] then ids[#ids + 1] = res.r.reagents[i] end end
    VC.RequestPrices(ids)
  end)
  f.refresh:SetPoint("TOPRIGHT", -inset, top)
  f.topBtn = St.Button(f, L"Live prices of the best 10 per profession", 230, function() VC.RefreshTop(false) end)
  f.topBtn:SetPoint("TOPRIGHT", -inset, top - 26)
  f.note = f:CreateFontString(nil, "OVERLAY", "WowAssistantFontDisableSmall")
  f.note:SetPoint("BOTTOMLEFT", inset, St.Wow() and 16 or 8)
  f.note:SetPoint("RIGHT", -inset, 0)
  f.note:SetJustifyH("LEFT")
  f.note:SetText(L"Type how many times you craft, and every row counts with that. Best batch: per recipe, as many as still make a profit from the cheapest listings. Shift + –/+: by tens. Click a row for the shopping list. Orange *: the price is over an hour old. No fees: the AH buyout is all you pay, and the merchant pays the full price.")
  f:Hide()
  return f
end

local function Detail(res)
  local r = res.r
  local lines = {}
  lines[1] = (L"|cffffd100%s|r → %s%s, vendor %s / ea%s%s"):format(r.name, ItemName(r.product),
    r.min == r.max and (r.min > 1 and (" ×" .. r.min) or "") or (" ×" .. r.min .. "–" .. r.max),
    Coins(res.each), res.exact and "" or (L" |cffff9933(the client has not loaded it yet, estimated)|r"),
    r.cd > 0 and (" · cooldown " .. math.floor(r.cd / 60) .. L" min") or "")
  if res.crafts > 0 then
    local _, _, _, buyers = CostOf(r.reagents, res.crafts)
    lines[2] = (L"%d crafts = %d items: materials %s, the merchant pays %s, net profit |cff40ff40%s|r%s"):format(res.crafts, res.items,
      Coins(res.cost), Coins(res.income), Coins(res.profit),
      res.short and (L" |cffff9933(the AH supply covers only this many)|r") or "")
    for k, B in ipairs(buyers) do
      local id = r.reagents[k * 2 - 1]
      local parts = {}
      if B.ahUnits > 0 then parts[#parts + 1] = (L"AH: %d items, %s, max %s/ea"):format(B.ahUnits, Coins(B.ahCost), Coins(B.ahMax or 0)) end
      if B.vUnits > 0 then parts[#parts + 1] = (L"merchant: %d items, %s"):format(B.vUnits, Coins(B.vCost)) end
      if B.held > 0 then parts[#parts + 1] = (L"%d left over"):format(B.held) end
      local live = Market().live[id]
      local seen = ""
      if live then
        seen = L" |cff66ccff(live price " .. date("%H:%M", live) .. ")|r"
      elseif B.ahUnits > 0 and Market().at then
        local age = time() - Market().at
        seen = (age > STALE and " |cffff9933" or " |cff9e917a") .. (L"(AH data %s, %d min old)"):format(date("%H:%M", Market().at), math.floor(age / 60)) .. "|r"
      end
      lines[#lines + 1] = ("  %s: %s%s"):format(ItemName(id), table.concat(parts, " · "), seen)
    end
    local money = GetMoney and GetMoney() or 0
    if res.cost > money then
      lines[#lines + 1] = (L"|cffff9933You have %s: it pays for %d of the %d crafts.|r"):format(Coins(money),
        Affordable(r.reagents, res.crafts, money), res.crafts)
    end
    if res.pricesAt and time() - res.pricesAt > STALE then
      lines[#lines + 1] = L"|cffff9933The prices are over an hour old: the cheapest listings may be gone. Refresh prices before buying.|r"
    end
  else
    lines[2] = L"With the cheapest materials listed now it makes no profit, only at the average price."
  end
  return table.concat(lines, "\n")
end

function VC.Refresh()
  if not frame or not frame:IsShown() then return end
  if dirty then Compute() end
  local f = VC.filter
  frame.prof:Refresh()
  frame.skill:Refresh()
  for i, h in ipairs(frame.heads) do
    h.text:SetText(WA.Style.Upper(COLS[i][1]) .. (f.sort == i and (f.dir > 0 and " ↑" or " ↓") or ""))
  end
  local m = Market()
  local live = 0
  for _ in pairs(m.live) do live = live + 1 end
  frame.topBtn:SetEnabled(AHOpen() and true or false)
  frame.status:SetText((L"%d recipes make a profit"):format(#results))
  for _, b in ipairs(frame.presets) do
    if b.qty == f.qty then b:LockHighlight() else b:UnlockHighlight() end
  end
  -- cards: the best craft now, how many are worth it, how fresh the prices are
  local best, worth = nil, 0
  for _, x in ipairs(results) do
    if x.crafts > 0 and x.profit > 0 then
      worth = worth + 1
      if not best or x.profit > best.profit then best = x end
    end
  end
  local c1, c2, c3 = frame.cards[1], frame.cards[2], frame.cards[3]
  c1.label:SetText(L"BEST FOR ONE SALE")
  c1.value:SetText(best and best.r.name or "|cff9e917a–|r")
  c1.sub:SetText(best and ("|cff5ee05e+" .. Short(best.profit) .. L"|r net · " .. best.items .. L" items → " .. Short(best.income)) or (L"none makes a profit now"))
  c2.label:SetText(L"WORTH IT")
  c2.value:SetText((L"%d recipes"):format(worth))
  c2.sub:SetText(f.qty and (f.qty .. L"× crafted, per recipe") or (L"with the best batch, per recipe"))
  c3.label:SetText(L"PRICES")
  c3.value:SetText(m.at and date(L"%m/%d %H:%M", m.at) or (L"|cffff9933no price|r"))
  c3.sub:SetText(m.at and ((m.src == "web" and (L"web app AH data") or (L"own AH scan")) .. (live > 0 and (L" · live: " .. live) or "")) or (L"run the uploader, or /wa ah"))
  frame.offset = math.min(frame.offset, math.max(0, #results - ROWS))
  local selRes
  for i, row in ipairs(frame.rows) do
    local res = results[frame.offset + i]
    row.res = res
    if res then
      local r = res.r
      local c = row.cells
      c[1]:SetText(r.name .. " |cff888888" .. (R.professions[r.prof] or "") .. " " .. r.orange .. " · " .. res.status .. "|r")
      c[2]:SetText(res.product .. (r.min > 1 and (" |cff888888×" .. r.min .. "|r") or ""))
      c[3]:SetText(Short(res.each) .. (res.exact and "" or "|cffff9933?|r"))
      local stale = res.pricesAt and time() - res.pricesAt > STALE
      c[4]:SetText(Short(res.costEach) .. (stale and "|cffff9933*|r" or ""))
      c[5]:SetText(Signed(res.gainEach))
      c[6]:SetText((res.short and "|cffff9933" or "") .. res.items .. (res.capped and "+" or "") .. (res.short and "|r" or ""))
      c[7]:SetText(Short(res.income))
      c[8]:SetText("|cff40ff40" .. Short(res.profit) .. "|r")
      row.sel:SetShown(r.spell == frame.sel)
      if r.spell == frame.sel then selRes = res end
      row:Show()
    else
      row:Hide()
    end
  end
  if not selRes then
    for _, x in ipairs(results) do if x.r.spell == frame.sel then selRes = x end end
  end
  if selRes then
    frame.detail:SetText(Detail(selRes))
    frame.refresh:Show()
    frame.refresh:SetEnabled(AHOpen() and true or false)
  else
    local msg = #results == 0 and (L"With this filter no recipe makes a profit at the vendor now.") or (L"Click a recipe for the shopping list.")
    if not m.at then msg = msg .. L"\nPrices are needed: run the uploader (the web app's hourly AH data, after /reload), or /wa ah at the auction house." end
    if unpriced > 0 then msg = msg .. (L"\n%d recipes do not have enough materials on the AH now."):format(unpriced) end
    frame.detail:SetText(msg)
    frame.refresh:Hide()
  end
end

function VC.Toggle()
  if not R then Print(L"Recipe data is missing (Recipes.lua): node scripts/build-addon-recipes.mjs --install") return end
  frame = frame or Build()
  if frame:IsShown() then frame:Hide() return end
  VC.filter.qty = WowAssistantDB and WowAssistantDB.vcQty or VC.filter.qty
  frame.qtyBox.setting = true
  frame.qtyBox:SetText(VC.filter.qty and tostring(VC.filter.qty) or "")
  frame.qtyBox.setting = false
  frame:ClearAllPoints()
  if AHOpen() and AuctionHouseFrame then frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0) else frame:SetPoint("CENTER") end
  dirty = true
  frame:Show()
  VC.Refresh()
  if AHOpen() then VC.RefreshTop(true) end
end

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local pendingRefresh = false
local function SoonRefresh()
  if pendingRefresh then return end
  pendingRefresh = true
  C_Timer.After(0.5, function() pendingRefresh = false dirty = true VC.Refresh() end)
end

local ahButton
ev:SetScript("OnEvent", function(_, event, ...)
  if event == "AUCTION_HOUSE_SHOW" then
    if not ahButton and AuctionHouseFrame then
      ahButton = CreateFrame("Button", nil, AuctionHouseFrame, "UIPanelButtonTemplate")
      ahButton:SetSize(130, 22)
      ahButton:SetPoint("TOPRIGHT", AuctionHouseFrame, "TOPRIGHT", -30, -1)
      ahButton:SetText(L"Crafting for the vendor")
      ahButton:SetScript("OnClick", VC.Toggle)
    end
    if frame and frame:IsShown() then
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
      VC.Refresh()
      -- after the game's own first searches (and once the line knows the house is open)
      C_Timer.After(0.5, function() if AHOpen() then VC.RefreshTop(true) end end)
    end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    if frame and frame:IsShown() then VC.Refresh() end
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" or event == "TRADE_SKILL_UPDATE" then
    pcall(ScanKnown)
  elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
    pcall(ScanKnownCraft)
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    if frame and frame:IsShown() then SoonRefresh() end
  elseif event == "SKILL_LINES_CHANGED" then
    dirty = true
  end
end)
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE",
  "CRAFT_SHOW", "CRAFT_UPDATE", "GET_ITEM_INFO_RECEIVED", "SKILL_LINES_CHANGED" }) do
  pcall(ev.RegisterEvent, ev, e)
end

WA.Command("vendor", function() VC.Toggle() end, L"/wa vendor – what is worth crafting for the vendor")
