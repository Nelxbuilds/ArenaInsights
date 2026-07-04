local addonName, AI = ...

-- ============================================================================
-- Queue overlay
-- Small movable frame listing active PvP queues with elapsed queue time.
-- Shown automatically while queued; hidden otherwise. Toggle in Settings.
-- ============================================================================

AI.QueueOverlay = {}

local FRAME_W  = 230
local TITLE_H  = 18
local LINE_H   = 16
local PAD      = 8
local MAX_LINES = 6

local frame
local lines  = {}
local queues = {}   -- { {index, name, ready}, ... } refreshed on status events

local function IsSecretV(v)
    return v ~= nil and issecretvalue and issecretvalue(v)
end

local function SavePosition()
    local point, _, _, x, y = frame:GetPoint()
    ArenaInsightsDB.settings.queueOverlayPos = { point = point, x = x, y = y }
end

local function RestorePosition()
    local pos = ArenaInsightsDB.settings and ArenaInsightsDB.settings.queueOverlayPos
    frame:ClearAllPoints()
    if pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -180)
    end
end

local function BuildFrame()
    frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetWidth(FRAME_W)
    frame:SetFrameStrata("MEDIUM")
    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.04, 0.04, 0.06, 0.90)
    frame:SetBackdropBorderColor(0.28, 0.08, 0.06, 1)

    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("ArenaInsights Queue Timer", 1, 1, 1)
        GameTooltip:AddLine("Drag to move. Disable in Settings.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
    frame.title:SetPoint("TOPLEFT", PAD, -4)
    frame.title:SetText("IN QUEUE")
    frame.title:SetTextColor(0.60, 0.15, 0.12)

    for i = 1, MAX_LINES do
        local ln = {}
        ln.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ln.name:SetPoint("TOPLEFT", PAD, -(TITLE_H + (i - 1) * LINE_H))
        ln.name:SetWidth(FRAME_W - 70)
        ln.name:SetJustifyH("LEFT")
        ln.name:SetWordWrap(false)
        ln.name:SetTextColor(0.78, 0.75, 0.73)
        ln.time = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ln.time:SetPoint("TOPRIGHT", -PAD, -(TITLE_H + (i - 1) * LINE_H))
        ln.time:SetJustifyH("RIGHT")
        ln.time:SetTextColor(1, 1, 1)
        lines[i] = ln
    end

    -- Elapsed-time ticker, throttled to twice a second
    local acc = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.5 then return end
        acc = 0
        for i, q in ipairs(queues) do
            if i > MAX_LINES then break end
            if q.ready then
                lines[i].time:SetText("Ready!")
                lines[i].time:SetTextColor(0.13, 0.80, 0.13)
            else
                local ms = GetBattlefieldTimeWaited and GetBattlefieldTimeWaited(q.index)
                if IsSecretV(ms) or type(ms) ~= "number" then
                    lines[i].time:SetText("?")
                    lines[i].time:SetTextColor(0.48, 0.45, 0.43)
                else
                    local s = math.floor(ms / 1000)
                    lines[i].time:SetText(string.format("%d:%02d", math.floor(s / 60), s % 60))
                    lines[i].time:SetTextColor(1, 1, 1)
                end
            end
        end
    end)

    RestorePosition()
    frame:Hide()
end

local function CollectQueues()
    local out = {}
    local maxId = (GetMaxBattlefieldID and GetMaxBattlefieldID()) or 0
    for i = 1, maxId do
        local ok, status, mapName = pcall(GetBattlefieldStatus, i)
        if ok and (status == "queued" or status == "confirm") then
            if IsSecretV(mapName) or type(mapName) ~= "string" or mapName == "" then
                mapName = "Unknown queue"
            end
            out[#out + 1] = { index = i, name = mapName, ready = (status == "confirm") }
        end
    end
    return out
end

function AI.QueueOverlay.Refresh()
    if not ArenaInsightsDB or not ArenaInsightsDB.settings then return end
    queues = CollectQueues()

    local enabled = ArenaInsightsDB.settings.queueOverlayEnabled
    if not enabled or #queues == 0 then
        if frame then frame:Hide() end
        return
    end

    if not frame then BuildFrame() end

    local n = math.min(#queues, MAX_LINES)
    for i = 1, MAX_LINES do
        local q = queues[i]
        if i <= n and q then
            lines[i].name:SetText(q.name)
            lines[i].time:SetText(q.ready and "Ready!" or "0:00")
            lines[i].name:Show()
            lines[i].time:Show()
        else
            lines[i].name:Hide()
            lines[i].time:Hide()
        end
    end
    frame:SetHeight(TITLE_H + n * LINE_H + 6)
    frame:Show()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
eventFrame:SetScript("OnEvent", function()
    AI.QueueOverlay.Refresh()
end)
