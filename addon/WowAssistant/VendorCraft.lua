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
local R = WowAssistantRecipes
local VC = {}
WowAssistantVC = VC
WA.VC = VC

local MAX_CRAFTS = 1000
local GIVE_UP_AFTER = 25
local ROWS = 14
local SOURCE = { ["2"] = "drop", ["4"] = "quest", ["5"] = "receptárus", ["6"] = "tréner", ["7"] = "felfedezés" }

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

local function OnCommodityResults(itemID)
  if not VC.reagents[itemID] then return end
  local AH = C_AuctionHouse
  local list = {}
  for i = 1, AH.GetNumCommoditySearchResults(itemID) or 0 do
    local r = AH.GetCommoditySearchResultInfo(itemID, i)
    if r and r.unitPrice and r.unitPrice > 0 and r.quantity then list[#list + 1] = { r.unitPrice, r.quantity, 0 } end
  end
  UpdateBook(itemID, list, AH.HasFullCommoditySearchResults and AH.HasFullCommoditySearchResults(itemID))
end

local function OnItemResults(itemKey)
  if not itemKey or not VC.reagents[itemKey.itemID] then return end
  local AH = C_AuctionHouse
  local list = {}
  for i = 1, AH.GetNumItemSearchResults(itemKey) or 0 do
    local r = AH.GetItemSearchResultInfo(itemKey, i)
    local qty = r and r.quantity or 1
    if r and r.buyoutAmount and r.buyoutAmount > 0 then
      list[#list + 1] = { r.buyoutAmount / qty, qty, qty > 1 and 1 or 0 }
    end
  end
  UpdateBook(itemKey.itemID, list, AH.HasFullItemSearchResults and AH.HasFullItemSearchResults(itemKey))
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
      local made, profit, cost, first
      local want = f.qty and math.max(1, math.min(MAX_CRAFTS, f.qty)) or nil
      if r.cd > 0 then want = want and 1 end
      if want then
        made, cost, first = CostOf(r.reagents, want)
        profit = income * made - cost
      else
        made, profit, cost, first = Simulate(r.reagents, income, r.cd > 0 and 1 or MAX_CRAFTS, true)
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
          if isKnown then status = "|cff40ff40ismered|r"
          elseif skill and r.orange > skill then status = r.orange .. " skill kell"
          elseif r.trainer >= 0 then status = "tréner"
          else
            local s = {}
            for code in (r.sources or ""):gmatch("%d+") do if SOURCE[code] then s[#s + 1] = SOURCE[code] end end
            status = #s > 0 and ("recept: " .. table.concat(s, ", ")) or "recept kell"
          end
          local items = made * r.min
          results[#results + 1] = {
            r = r, each = each, exact = exact, first = first, firstProfit = income - first,
            avgCost = avgCost, avgProfit = avgProfit, crafts = made, cost = cost,
            income = income * made, profit = profit, status = status, items = items,
            costEach = cost / items, gainEach = profit / items, product = ItemName(r.product),
            capped = not want and r.cd == 0 and made >= MAX_CRAFTS,
            short = want and made < want,
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
local queue, waiting = {}, nil

local function AHOpen() return AuctionHouseFrame and AuctionHouseFrame:IsShown() end

local function SendNext()
  if waiting or #queue == 0 or not AHOpen() then return end
  local AH = C_AuctionHouse
  if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then return end
  local id = table.remove(queue, 1)
  waiting = id
  local sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
  local ok = pcall(AH.SendSearchQuery, AH.MakeItemKey(id), sorts, true)
  if not ok then waiting = nil end
  C_Timer.After(3, function() if waiting == id then waiting = nil SendNext() end end)
end

function VC.RequestPrices(ids, quiet)
  if not AHOpen() then
    if not quiet then Print("Az élő árakhoz nyisd meg az aukciósházat.") end
    return
  end
  local queued = {}
  for _, id in ipairs(queue) do queued[id] = true end
  for _, id in ipairs(ids) do
    if not queued[id] and id ~= waiting then queue[#queue + 1] = id queued[id] = true end
  end
  SendNext()
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
      Print(("%d alapanyag élő árát kérem le: %d szakma legjobb %d gyártása (%d recept)."):format(#ids, profs, TOP, crafts))
    end
  end
  return #ids, profs, crafts
end

local function Received(id)
  if waiting == id then
    waiting = nil
    C_Timer.After(0.2, SendNext)
  end
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
local COLS = {
  { "Recept", 222, "LEFT", "A recept, a szakma és hogy honnan tanulod." },
  { "Termék", 150, "LEFT", "Amit gyártasz és eladsz." },
  { "Vendor / db", 70, "RIGHT", "Ennyit fizet a kereskedő egy darabért (a játék saját adata)." },
  { "Költség / db", 74, "RIGHT", "Az alapanyag ára egy darabra, a legolcsóbb AH-hirdetésektől felfelé." },
  { "Haszon / db", 72, "RIGHT", "Vendorár mínusz költség, darabonként." },
  { "Darab", 52, "RIGHT", "Ennyi darabot adsz el. Narancs: ennyire elég az AH kínálata." },
  { "Eladás", 80, "RIGHT", "Ennyit fizet a kereskedő az egészért." },
  { "Tiszta haszon", 90, "RIGHT", "Eladás mínusz az alapanyagok ára: ennyivel lesz több pénzed." },
}
local W = 900
local ROW_H = 20

-- Dropdown choices.
local function ProfItems()
  local list = { { "mine", "Saját szakmáim" }, { "all", "Minden szakma" } }
  local ids = {}
  for id in pairs(R.professions) do ids[#ids + 1] = id end
  table.sort(ids, function(a, b) return R.professions[a] < R.professions[b] end)
  for _, id in ipairs(ids) do list[#list + 1] = { id, R.professions[id] } end
  return list
end
local function SkillItems()
  return { { "current", "Amit most tudok (skill)" }, { "max", "Minden recept 300-ig" } }
end

local function Build()
  local St = WA.Style
  local f = St.Window("WowAssistantVendorFrame", W, 0, "Gyártás vendornak")
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
  local known = St.Check(f, "csak amit ismerek", function(on) VC.filter.known = on dirty = true VC.Refresh() end)
  known:SetPoint("LEFT", f.skill, "RIGHT", f.skill.SetupMenu and 10 or -6, 0)
  local search = St.Search(f, "Keresés:", 150, function(text) VC.filter.text = text dirty = true VC.Refresh() end)
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
  ql:SetText("Hányszor gyártod:")
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
  for _, p in ipairs({ { 1, "1" }, { 5, "5" }, { 20, "20" }, { nil, "Legjobb adag" } }) do
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
      GameTooltip:AddLine(WA.Fix(c[4] .. " Kattints: rendezés."), 1, 1, 1, true)
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
  f.refresh = St.Button(f, "Árak frissítése", 230, function()
    local res
    for _, x2 in ipairs(results) do if x2.r.spell == f.sel then res = x2 end end
    if not res then return end
    local ids = {}
    for i = 1, #res.r.reagents, 2 do if not R.vendor[res.r.reagents[i]] then ids[#ids + 1] = res.r.reagents[i] end end
    VC.RequestPrices(ids)
  end)
  f.refresh:SetPoint("TOPRIGHT", -inset, top)
  f.topBtn = St.Button(f, "Szakmánként legjobb 10 élő ára", 230, function() VC.RefreshTop(false) end)
  f.topBtn:SetPoint("TOPRIGHT", -inset, top - 26)
  f.note = f:CreateFontString(nil, "OVERLAY", "WowAssistantFontDisableSmall")
  f.note:SetPoint("BOTTOMLEFT", inset, St.Wow() and 16 or 8)
  f.note:SetPoint("RIGHT", -inset, 0)
  f.note:SetJustifyH("LEFT")
  f.note:SetText("Írd be, hányszor gyártasz, és minden sor arra számol. Legjobb adag: receptenként annyi, amennyi a legolcsóbb hirdetésekből még hasznot hoz. Shift + –/+: tízesével. Kattints egy sorra a bevásárlólistáért.")
  f:Hide()
  return f
end

local function Detail(res)
  local r = res.r
  local lines = {}
  lines[1] = ("|cffffd100%s|r → %s%s, vendor %s / db%s%s"):format(r.name, ItemName(r.product),
    r.min == r.max and (r.min > 1 and (" ×" .. r.min) or "") or (" ×" .. r.min .. "–" .. r.max),
    Coins(res.each), res.exact and "" or " |cffff9933(a kliens még nem töltötte be, becsült)|r",
    r.cd > 0 and (" · cooldown " .. math.floor(r.cd / 60) .. " perc") or "")
  if res.crafts > 0 then
    local _, _, _, buyers = CostOf(r.reagents, res.crafts)
    lines[2] = ("%d gyártás = %d db: alapanyag %s, a kereskedő fizet %s, tiszta haszon |cff40ff40%s|r%s"):format(res.crafts, res.items,
      Coins(res.cost), Coins(res.income), Coins(res.profit),
      res.short and (" |cffff9933(csak ennyire elég az AH kínálata)|r") or "")
    for k, B in ipairs(buyers) do
      local id = r.reagents[k * 2 - 1]
      local parts = {}
      if B.ahUnits > 0 then parts[#parts + 1] = ("AH: %d db, %s, max %s/db"):format(B.ahUnits, Coins(B.ahCost), Coins(B.ahMax or 0)) end
      if B.vUnits > 0 then parts[#parts + 1] = ("kereskedő: %d db, %s"):format(B.vUnits, Coins(B.vCost)) end
      if B.held > 0 then parts[#parts + 1] = ("%d db marad"):format(B.held) end
      local live = Market().live[id]
      lines[#lines + 1] = ("  %s: %s%s"):format(ItemName(id), table.concat(parts, " · "),
        live and (" |cff66ccff(élő ár " .. date("%H:%M", live) .. ")|r") or "")
    end
  else
    lines[2] = "A legolcsóbb kint lévő alapanyagokkal most nem hoz hasznot, csak átlagáron."
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
  frame.status:SetText(("%d recept hoz hasznot"):format(#results))
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
  c1.label:SetText("LEGJOBB EGY ELADÁSRA")
  c1.value:SetText(best and best.r.name or "|cff9e917a–|r")
  c1.sub:SetText(best and ("|cff5ee05e+" .. Short(best.profit) .. "|r tisztán · " .. best.items .. " db → " .. Short(best.income)) or "egyik sem hoz most hasznot")
  c2.label:SetText("MEGÉRI")
  c2.value:SetText(("%d recept"):format(worth))
  c2.sub:SetText(f.qty and (f.qty .. "× gyártva, receptenként") or "legjobb adaggal, receptenként")
  c3.label:SetText("ÁRAK")
  c3.value:SetText(m.at and date("%m.%d %H:%M", m.at) or "|cffff9933nincs ár|r")
  c3.sub:SetText(m.at and ((m.src == "web" and "webapp AH-adat" or "saját AH-szken") .. (live > 0 and (" · élő: " .. live) or "")) or "fusson a feltöltő, vagy /wa ah")
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
      c[4]:SetText(Short(res.costEach))
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
    local msg = #results == 0 and "Ezzel a szűréssel most egy recept sem hoz hasznot vendornál." or "Kattints egy receptre a bevásárlólistáért."
    if not m.at then msg = msg .. "\nÁrak kellenek: fusson a feltöltő (a webapp óránkénti AH-adata, /reload után), vagy az aukciósháznál /wa ah." end
    if unpriced > 0 then msg = msg .. ("\n%d receptnek most nincs elég alapanyaga az AH-ban."):format(unpriced) end
    frame.detail:SetText(msg)
    frame.refresh:Hide()
  end
end

function VC.Toggle()
  if not R then Print("Hiányzik a receptadat (Recipes.lua): node scripts/build-addon-recipes.mjs --install") return end
  frame = frame or Build()
  if frame:IsShown() then frame:Hide() return end
  VC.filter.qty = WowAssistantDB and WowAssistantDB.vcQty or VC.filter.qty
  frame.qtyBox.setting = true
  frame.qtyBox:SetText(VC.filter.qty and tostring(VC.filter.qty) or "")
  frame.qtyBox.setting = false
  frame:ClearAllPoints()
  if AHOpen() then frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0) else frame:SetPoint("CENTER") end
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
  if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    local id = ...
    pcall(OnCommodityResults, id)
    Received(id)
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    local key = ...
    pcall(OnItemResults, key)
    if key then Received(key.itemID) end
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    SendNext()
  elseif event == "AUCTION_HOUSE_SHOW" then
    if not ahButton and AuctionHouseFrame then
      ahButton = CreateFrame("Button", nil, AuctionHouseFrame, "UIPanelButtonTemplate")
      ahButton:SetSize(130, 22)
      ahButton:SetPoint("TOPRIGHT", AuctionHouseFrame, "TOPRIGHT", -30, -1)
      ahButton:SetText("Vendorra gyártás")
      ahButton:SetScript("OnClick", VC.Toggle)
    end
    if frame and frame:IsShown() then
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
      VC.Refresh()
      VC.RefreshTop(true)
    end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    queue, waiting = {}, nil
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
for _, e in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
  "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE",
  "CRAFT_SHOW", "CRAFT_UPDATE", "GET_ITEM_INFO_RECEIVED", "SKILL_LINES_CHANGED" }) do
  pcall(ev.RegisterEvent, ev, e)
end

WA.Command("vendor", function() VC.Toggle() end, "/wa vendor – mit érdemes legyártani vendornak")
