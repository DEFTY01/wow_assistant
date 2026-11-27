-- WoW Assistant: cheapest skill-up route per profession, ported from the web app
-- (planRoutes in src/professions.ts). Pure: Game.lua supplies the input in game, a test can
-- supply the web app's own data.
--
-- input:
--   profs   = { { id, name, skill, cap, known = { [recipe name] = true } }, ... }
--   recipes = list of { spell, prof, name, orange, yellow, grey, product (0: none), qty (average made),
--                       reagents = { id, qty, ... }, trainingCost (nil), fromTrainer }
--   book    = { unit = fn(id) -> { price, source } or nil, vendorSell = fn(id) -> copper, name = fn(id) }
--   owned   = { [itemId] = count }   bags and bank; used up across professions
--   level, target

local _, WA = ...
local L = WA.L
WA = WA or {}
local Routes = {}
WA.Routes = Routes

Routes.RANKS = {
  { name = "Apprentice", cap = 75, trainAt = 0, cost = 10 },
  { name = "Journeyman", cap = 150, trainAt = 50, cost = 500 },
  { name = "Expert", cap = 225, trainAt = 125, cost = 5000 },
  { name = "Artisan", cap = 300, trainAt = 200, cost = 50000 },
}

local BIG = 1e12 -- a point nothing can skill up on

-- Recipes of the generated Recipes.lua in the shape above (orange..grey colors from Wowhead).
function Routes.FromRecipeData(R)
  local out = {}
  for _, r in ipairs((R or WowAssistantRecipes or {}).recipes or {}) do
    out[#out + 1] = {
      spell = r[1], prof = r[2], orange = r[3], product = r[4], qty = r[4] ~= 0 and (r[5] + r[6]) / 2 or 1,
      min = r[5], max = r[6], trainingCost = r[7] >= 0 and r[7] or nil, fromTrainer = r[7] >= 0, cd = r[8],
      name = r[9], reagents = r[10], sources = r[11], yellow = r[12], grey = r[13],
    }
  end
  return out
end

-- Classic skill-up chance: 100% while orange, falling linearly from yellow to 0 at grey.
local function SkillUpChance(r, skill)
  if skill < r.orange or skill >= r.grey then return 0 end
  if skill < r.yellow then return 1 end
  return (r.grey - skill) / (r.grey - r.yellow)
end
Routes.SkillUpChance = SkillUpChance

local function CraftCost(r, book)
  local cost = 0
  for i = 1, #r.reagents, 2 do
    local u = book.unit(r.reagents[i])
    if not u then return nil end
    cost = cost + u.price * r.reagents[i + 1]
  end
  return cost
end

local function Money2(c) return ("%.2f"):format(c / 10000) end

function Routes.Plan(input)
  local book, owned = input.book, {}
  for id, n in pairs(input.owned or {}) do owned[id] = n end
  local byProf = {}
  for _, r in ipairs(input.recipes) do
    byProf[r.prof] = byProf[r.prof] or {}
    table.insert(byProf[r.prof], r)
  end
  local routes = {}
  for _, g in ipairs(input.profs) do
    local rows = byProf[g.id]
    if rows and #rows > 0 then
      local skill, cap = g.skill, g.cap
      local target = math.min(input.target or 300, 300)
      local notes = {}
      for _, rank in ipairs(Routes.RANKS) do
        if rank.cap > cap and rank.cap - 75 < target then
          notes[#notes + 1] = (L"%s rank (up to %d): learnable from skill %d, %sg at the trainer."):format(rank.name, rank.cap, rank.trainAt, Money2(rank.cost)) ..
            ((rank.name == "Artisan" and (input.level or 0) < 35) and (L" Per Classic it needs level 35 (not verified).") or "")
        end
      end

      local all = {}
      for _, r in ipairs(rows) do
        local x = {}
        for k, v in pairs(r) do x[k] = v end
        x.known = g.known[r.name] == true
        all[#all + 1] = x
      end
      local function Priced(filter)
        local out = {}
        for _, r in ipairs(all) do
          if filter(r) then
            local cost = CraftCost(r, book)
            if cost then
              local back = (r.product ~= 0 and book.vendorSell(r.product) or 0) * r.qty
              out[#out + 1] = { r = r, cost = cost, net = math.max(cost - back, cost * 0.02) }
            end
          end
        end
        return out
      end
      local known = Priced(function(r) return r.known end)
      local trainable = Priced(function(r) return not r.known and r.fromTrainer and r.trainingCost ~= nil end)
      local unpriced = {}
      for _, r in ipairs(all) do
        if r.known and r.grey > skill and CraftCost(r, book) == nil then unpriced[#unpriced + 1] = r.name end
      end
      if #unpriced > 0 then
        local first = {}
        for i = 1, math.min(8, #unpriced) do first[i] = unpriced[i] end
        notes[#notes + 1] = L"Known recipes without a price (so skipped): " .. table.concat(first, ", ") ..
          (#unpriced > 8 and (L" plus " .. (#unpriced - 8)) or "") .. "."
      end

      -- Cheapest recipe for every skill point with the recipes available so far.
      local points = math.max(0, target - skill)
      local function PointCost(x, i)
        local p = SkillUpChance(x.r, skill + i)
        return p > 0 and x.net / p or BIG
      end
      local bestCost, bestOf = {}, {}
      for i = 0, points - 1 do bestCost[i] = BIG end
      local function Adopt(x)
        for i = 0, points - 1 do
          local c = PointCost(x, i)
          if c < bestCost[i] then
            bestCost[i] = c
            bestOf[i] = x
          end
        end
      end
      local function Total(extra)
        local sum = 0
        for i = 0, points - 1 do
          local c = bestCost[i]
          if extra then c = math.min(c, PointCost(extra, i)) end
          if c >= BIG then return sum + (points - i) * BIG end
          sum = sum + c
        end
        return sum
      end
      for _, x in ipairs(known) do Adopt(x) end
      local pool = {}
      for i, x in ipairs(trainable) do pool[i] = x end
      while true do
        local current = Total()
        local bestGain, bestIdx = 0, nil
        for i, x in ipairs(pool) do
          local gain = current - (Total(x) + (x.r.trainingCost or 0))
          if gain > bestGain then bestGain, bestIdx = gain, i end
        end
        if not bestIdx then break end
        Adopt(pool[bestIdx])
        table.remove(pool, bestIdx)
      end
      local perPoint, stuckAt = {}, nil
      for i = 0, points - 1 do
        local x = bestOf[i]
        if not x or bestCost[i] >= BIG then
          stuckAt = skill + i
          break
        end
        perPoint[#perPoint + 1] = { recipe = x.r, crafts = bestCost[i] / x.net }
      end

      -- Consecutive points on the same recipe become one step.
      local steps, charged = {}, {}
      for i, pt in ipairs(perPoint) do
        local s = skill + i - 1
        local step = steps[#steps]
        if not step or step.recipe ~= pt.recipe.name then
          local firstUse = not pt.recipe.known and not charged[pt.recipe.spell]
          charged[pt.recipe.spell] = true
          local reag = {}
          for k = 1, #pt.recipe.reagents, 2 do
            local id = pt.recipe.reagents[k]
            local u = book.unit(id)
            reag[#reag + 1] = { itemId = id, name = book.name(id), qty = 0, unit = u and u.price or nil,
              source = u and u.source or "?", per = pt.recipe.reagents[k + 1] }
          end
          step = { from = s, to = s, recipe = pt.recipe.name, known = pt.recipe.known,
            trainingCost = firstUse and (pt.recipe.trainingCost or 0) or 0, crafts = 0, matsCost = 0, vendorBack = 0, reagents = reag }
          steps[#steps + 1] = step
        end
        step.to = s + 1
        step.crafts = step.crafts + pt.crafts
      end
      for _, step in ipairs(steps) do
        local r
        for _, x in ipairs(all) do if x.name == step.recipe then r = x break end end
        step.crafts = math.ceil(step.crafts)
        for _, rg in ipairs(step.reagents) do
          rg.qty = rg.per * step.crafts
          step.matsCost = step.matsCost + (rg.unit or 0) * rg.qty
          rg.per = nil
        end
        step.vendorBack = math.floor((r.product ~= 0 and book.vendorSell(r.product) or 0) * r.qty * step.crafts + 0.5)
      end

      local shop, shopOrder = {}, {}
      for _, step in ipairs(steps) do
        for _, rg in ipairs(step.reagents) do
          local row = shop[rg.itemId]
          if not row then
            row = { itemId = rg.itemId, name = rg.name, unit = rg.unit, source = rg.source, qty = 0, total = 0, owned = 0 }
            shop[rg.itemId] = row
            shopOrder[#shopOrder + 1] = row
          end
          row.qty = row.qty + rg.qty
          row.total = row.total + (rg.unit or 0) * rg.qty
        end
      end
      local ownedValue = 0
      for _, row in ipairs(shopOrder) do
        local have = math.min(row.qty, owned[row.itemId] or 0)
        if have > 0 then
          row.owned = have
          owned[row.itemId] = (owned[row.itemId] or 0) - have
          ownedValue = ownedValue + have * (row.unit or 0)
        end
      end
      WA.Model.Stable(shopOrder, function(a, b) return a.total > b.total end)

      local totalMats, totalTraining, totalBack = 0, 0, 0
      for _, s in ipairs(steps) do
        totalMats = totalMats + s.matsCost
        totalTraining = totalTraining + s.trainingCost
        totalBack = totalBack + s.vendorBack
      end
      routes[#routes + 1] = {
        ownedValue = ownedValue, profession = g.name, professionId = g.id, skill = skill, cap = cap, target = target,
        steps = steps, shopping = shopOrder, totalMats = totalMats, totalTraining = totalTraining,
        totalVendorBack = totalBack, notes = notes, unreachableFrom = stuckAt,
      }
    end
  end
  return routes
end
