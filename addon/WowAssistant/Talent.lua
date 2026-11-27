-- Waystone: the character's talent trees. The shape comes from the game client (every tab, every
-- talent with its tier, column, rank and prerequisite), the text and numbers of every rank from
-- TalentData.lua (generated from Wowhead's Forever talent calculator by scripts/build-talents.mjs;
-- not in the repo). The two are matched by talent name; where they differ (a talent the data does
-- not know, another rank count or place) the client wins and the difference is reported, so a
-- Forever patch that changes a talent shows up instead of being calculated wrong.
--
--   T.ReadTree()        -> { tabs = { { name, icon, points, talents = { { name, icon, tier, col, rank, max, req } } } },
--                            spent, unspent, level }
--   T.Data(class)       -> the generated data for a class, or nil
--   T.Match(tree, data) -> per tab: the data's tree, matched / missing / differs; and a talent's data by name
--   /wa talent          -> the trees, the points and how far the data matches the game

local _, WA = ...
WA = WA or {}
local T = {}
WA.Talent = T

local function Try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g = pcall(fn, ...)
  if ok then return a, b, c, d, e, f, g end
  return nil
end

function T.Data(class)
  local all = _G.WowAssistantTalents
  return all and class and all[class] or nil
end

-- The client's trees. GetTalentPrereqs gives the required talent's tier and column; it is turned
-- into that talent's name.
function T.ReadTree()
  local tree = { tabs = {}, spent = 0, level = Try(UnitLevel, "player") or 0 }
  local n = Try(GetNumTalentTabs) or 0
  for tab = 1, n do
    local name, icon, points = Try(GetTalentTabInfo, tab)
    local t = { name = name or ("Fa " .. tab), icon = icon, points = 0, talents = {} }
    local at = {}
    for i = 1, (Try(GetNumTalents, tab) or 0) do
      local tname, ticon, tier, col, rank, max = Try(GetTalentInfo, tab, i)
      if tname then
        local x = { index = i, name = tname, icon = ticon, tier = tonumber(tier) or 0, col = tonumber(col) or 0,
          rank = tonumber(rank) or 0, max = tonumber(max) or 0 }
        local rt, rc = Try(GetTalentPrereqs, tab, i)
        if rt and rc then x.reqAt = { tonumber(rt), tonumber(rc) } end
        t.talents[#t.talents + 1] = x
        at[x.tier .. ":" .. x.col] = x
        t.points = t.points + x.rank
      end
    end
    for _, x in ipairs(t.talents) do
      local r = x.reqAt and at[x.reqAt[1] .. ":" .. x.reqAt[2]]
      if r then x.req = r.name end
      x.reqAt = nil
    end
    -- the tab's own count where the client gives one (it includes nothing the talents do not)
    if tonumber(points) and tonumber(points) > t.points then t.points = tonumber(points) end
    tree.spent = tree.spent + t.points
    tree.tabs[tab] = t
  end
  -- unspent points: UnitCharacterPoints where the client has it
  local unspent = Try(UnitCharacterPoints, "player")
  tree.unspent = tonumber(unspent)
  return tree
end

-- Match the client's tabs to the data's trees by talent name (a tab is the tree most of its
-- talents belong to; the tab order is not assumed). For each tab: the data tree, how many talents
-- matched, the client talents the data lacks, and those whose rank count or place differ.
function T.Match(tree, data)
  local out = { tabs = {}, byName = {}, matched = 0, total = 0 }
  if not data then return out end
  local byName = {}
  for _, d in ipairs(data.talents or {}) do byName[d.name] = d end
  local treeById = {}
  for _, tr in ipairs(data.trees or {}) do treeById[tr.id] = tr end
  for tab, t in ipairs(tree.tabs or {}) do
    local votes, m = {}, { matched = 0, missing = {}, differs = {} }
    for _, x in ipairs(t.talents) do
      out.total = out.total + 1
      local d = byName[x.name]
      if not d then
        m.missing[#m.missing + 1] = x.name
      else
        votes[d.tree] = (votes[d.tree] or 0) + 1
        out.byName[x.name] = d
        if d.max ~= x.max or d.tier ~= x.tier or d.col ~= x.col then
          m.differs[#m.differs + 1] = ("%s (játék: %d rang, %d. sor %d. oszlop; adat: %d rang, %d. sor %d. oszlop)")
            :format(x.name, x.max, x.tier, x.col, d.max, d.tier, d.col)
        else
          m.matched = m.matched + 1
          out.matched = out.matched + 1
        end
      end
    end
    local best, bestN = nil, 0
    for id, k in pairs(votes) do if k > bestN or (k == bestN and best and id < best) then best, bestN = id, k end end
    m.tree = best and treeById[best] or nil
    m.count = #t.talents
    out.tabs[tab] = m
  end
  return out
end

-- The text of a rank (1..max) of a talent, from the data; nil when the data does not have it.
function T.RankText(d, rank)
  return d and d.desc and d.desc[rank] or nil
end

local function Report()
  local class = WA.Game and WA.Game.Class and WA.Game.Class() or select(2, UnitClass("player"))
  local tree = T.ReadTree()
  local data = T.Data(class)
  if #tree.tabs == 0 then
    WA.Print("A játék nem adott talentfát (a kliens talent-API-ja nem elérhető).")
    return
  end
  local m = T.Match(tree, data)
  WA.Print(("Talentek: %d elköltött pont%s, %d. szint."):format(tree.spent,
    tree.unspent and (", " .. tree.unspent .. " szabad") or "", tree.level))
  for tab, t in ipairs(tree.tabs) do
    local x = m.tabs[tab]
    local where = ""
    if data and x and x.count > 0 then
      where = x.tree and (" · Wowhead Forever: %s fa, %d/%d talent egyezik"):format(x.tree.name, x.matched, x.count)
        or (" · a Wowhead Forever adatában nincs meg (%d talent)"):format(x.count)
    end
    WA.Print(("  %d. %s: %d pont%s"):format(tab, t.name, t.points, where))
    if x then
      for i = 1, math.min(5, #x.missing) do WA.Print("    nincs az adatban: " .. x.missing[i]) end
      for i = 1, math.min(5, #x.differs) do WA.Print("    eltér: " .. x.differs[i]) end
    end
  end
  if not data then
    WA.Print("A talentadat (TalentData.lua) hiányzik: node scripts/build-talents.mjs --install")
  else
    WA.Print(("Adat: Wowhead Forever talent-kalkulátor, letöltve %s."):format(_G.WowAssistantTalents.fetched or "?"))
  end
end
T.Report = Report

if WA.Command then WA.Command("talent", Report, "/wa talent – a talentfáid, a pontjaid, és hogy a Wowhead Forever adata egyezik-e a játékkal") end
