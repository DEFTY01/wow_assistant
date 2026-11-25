-- Shows AzerothMCP_Inbox (written by the local azeroth-mcp bridge into Data.lua) in a small window.
-- /amcp opens it; a chat line announces new content after a /reload.

local frame

local function Lines()
  local inbox = AzerothMCP_Inbox or {}
  local out = {}
  local function section(title, items)
    if type(items) ~= "table" or #items == 0 then return end
    out[#out + 1] = "|cffffd100" .. title .. "|r"
    for _, it in ipairs(items) do
      out[#out + 1] = "|cff66ccff• " .. tostring(it.title or "") .. "|r"
      out[#out + 1] = "   " .. tostring(it.text or "")
    end
    out[#out + 1] = " "
  end
  section("Célok", inbox.goals)
  section("Jegyzetek", inbox.notes)
  if #out == 0 then out[1] = "Az inbox üres. Kérd meg az AI-t, hogy küldjön ide jegyzetet (write_ingame_inbox)." end
  if inbox.generated then
    out[#out + 1] = "|cff888888Frissítve: " .. date("%Y.%m.%d %H:%M", inbox.generated) .. "|r"
  end
  return table.concat(out, "\n")
end

local function Build()
  frame = CreateFrame("Frame", "AzerothMCPInboxFrame", UIParent, "BackdropTemplate")
  frame:SetSize(380, 320)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetClampedToScreen(true)
  frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  frame:SetBackdropColor(0, 0, 0, 0.85)
  frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
  tinsert(UISpecialFrames, "AzerothMCPInboxFrame") -- Escape closes it

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -8)
  title:SetText("Azeroth MCP – Inbox")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 10, -28)
  scroll:SetPoint("BOTTOMRIGHT", -28, 10)
  local body = CreateFrame("Frame", nil, scroll)
  body:SetSize(330, 10)
  scroll:SetScrollChild(body)
  frame.text = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.text:SetPoint("TOPLEFT")
  frame.text:SetWidth(330)
  frame.text:SetJustifyH("LEFT")
  frame.text:SetSpacing(2)
  frame.body = body
end

local function Show()
  if not frame then Build() end
  frame.text:SetText(Lines())
  frame.body:SetHeight(frame.text:GetStringHeight() + 10)
  frame:Show()
  if AzerothMCP_Inbox and AzerothMCP_Inbox.generated then AzerothMCP_InboxSeen = AzerothMCP_Inbox.generated end
end

SLASH_AZEROTHMCP1 = "/amcp"
SlashCmdList.AZEROTHMCP = function()
  if frame and frame:IsShown() then frame:Hide() else Show() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  local inbox = AzerothMCP_Inbox
  if inbox and inbox.generated and inbox.generated ~= AzerothMCP_InboxSeen then
    local n = (type(inbox.notes) == "table" and #inbox.notes or 0) + (type(inbox.goals) == "table" and #inbox.goals or 0)
    print(("|cff33ccffAzeroth MCP|r: %d új jegyzet vagy cél érkezett. Megnyitás: /amcp"):format(n))
  end
end)
