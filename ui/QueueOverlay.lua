local addonName, AI = ...

-- ============================================================================
-- Queue overlay
-- Small movable frame listing active PvP queues with elapsed queue time.
-- Shown automatically while queued; hidden otherwise. Toggle in Settings.
-- ============================================================================

AI.QueueOverlay = {}

local FRAME_W  = 190
local TITLE_H  = 16   -- vertical space consumed by the "IN QUEUE" title
local NAME_H   = 15   -- bracket-name row
local TIME_H   = 22   -- large hero timer row
local INFO_H   = 13   -- dim CR/MMR footer row
local BLOCK_GAP = 4   -- gap between stacked queue blocks
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
        GameTooltip:AddLine("MMR is your last recorded value - the game", 0.48, 0.45, 0.43)
        GameTooltip:AddLine("exposes no live MMR while queued.", 0.48, 0.45, 0.43)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
    frame.title:SetPoint("TOPLEFT", PAD, -4)
    frame.title:SetText("IN QUEUE")
    frame.title:SetTextColor(0.60, 0.15, 0.12)

    for i = 1, MAX_LINES do
        local ln = {}
        -- Bracket name gets the full width now that nothing shares its row
        ln.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ln.name:SetWidth(FRAME_W - PAD * 2)
        ln.name:SetJustifyH("LEFT")
        ln.name:SetWordWrap(false)
        ln.name:SetTextColor(0.78, 0.75, 0.73)
        -- Elapsed queue time - the hero number, large and bright
        ln.time = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        ln.time:SetJustifyH("LEFT")
        ln.time:SetTextColor(1, 1, 1)
        -- Estimated wait, small and dim, trailing the timer on the same baseline
        ln.est = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
        ln.est:SetJustifyH("LEFT")
        ln.est:SetTextColor(0.48, 0.45, 0.43)
        ln.est:SetPoint("BOTTOMLEFT", ln.time, "BOTTOMRIGHT", 6, 2)
        -- Rating / last-known MMR for rated queues (dim footer row)
        ln.info = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
        ln.info:SetJustifyH("LEFT")
        ln.info:SetTextColor(0.48, 0.45, 0.43)
        lines[i] = ln
    end

    local function FmtMS(ms)
        local s = math.floor(ms / 1000)
        return string.format("%d:%02d", math.floor(s / 60), s % 60)
    end

    -- Elapsed-time ticker, throttled to twice a second
    local acc = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.5 then return end
        acc = 0
        for i, q in ipairs(queues) do
            if i > MAX_LINES then break end
            local ln = lines[i]
            if q.ready then
                ln.time:SetText("Ready!")
                ln.time:SetTextColor(0.13, 0.80, 0.13)
                ln.est:SetText("")
            else
                local ms = GetBattlefieldTimeWaited and GetBattlefieldTimeWaited(q.index)
                if IsSecretV(ms) or type(ms) ~= "number" then
                    ln.time:SetText("?")
                    ln.time:SetTextColor(0.48, 0.45, 0.43)
                    ln.est:SetText("")
                else
                    ln.time:SetText(FmtMS(ms))
                    ln.time:SetTextColor(1, 1, 1)
                    -- Average wait, same source the default client tooltip uses
                    local avg = GetBattlefieldEstimatedWaitTime
                        and GetBattlefieldEstimatedWaitTime(q.index)
                    if not IsSecretV(avg) and type(avg) == "number" and avg > 0 then
                        ln.est:SetText("~" .. FmtMS(avg) .. " est")
                    else
                        ln.est:SetText("")
                    end
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

-- Queue name -> bracket index, best-effort substring match on the localized
-- queue name. Unknown names simply get no rating/MMR line.
local BRACKET_PATTERNS = {
    { "shuffle", 7 },
    { "blitz",   4 },
    { "2v2",     1 },
    { "3v3",     2 },
}

local function GuessBracket(name)
    local n = name:lower()
    for _, p in ipairs(BRACKET_PATTERNS) do
        if n:find(p[1], 1, true) then return p[2] end
    end
    return nil
end

local function BuildInfoText(q)
    local bi = GuessBracket(q.name)
    if not bi or not AI.currentCharKey then return nil end

    local specID
    if AI.PER_SPEC_BRACKETS and AI.PER_SPEC_BRACKETS[bi] then
        local idx = GetSpecialization and GetSpecialization()
        specID = idx and GetSpecializationInfo and GetSpecializationInfo(idx) or nil
        if not specID then return nil end
    end

    local parts = {}
    local data = AI.GetRating and AI.GetRating(AI.currentCharKey, bi, specID)
    if data and data.rating then
        parts[#parts + 1] = "CR " .. data.rating
    end
    local mmr = AI.GetLastKnownMMR and AI.GetLastKnownMMR(AI.currentCharKey, bi, specID)
    if mmr then
        parts[#parts + 1] = "MMR ~" .. mmr
    end
    if #parts == 0 then return nil end
    return table.concat(parts, "   ")
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
    local y = TITLE_H
    for i = 1, MAX_LINES do
        local q  = queues[i]
        local ln = lines[i]
        if i <= n and q then
            ln.name:ClearAllPoints()
            ln.name:SetPoint("TOPLEFT", PAD, -y)
            ln.name:SetText(q.name)
            ln.name:Show()
            y = y + NAME_H

            ln.time:ClearAllPoints()
            ln.time:SetPoint("TOPLEFT", PAD, -y)
            ln.time:SetText(q.ready and "Ready!" or "0:00")
            ln.time:Show()
            ln.est:SetText("")   -- populated by the OnUpdate ticker
            ln.est:Show()
            y = y + TIME_H

            local info = BuildInfoText(q)
            if info then
                ln.info:ClearAllPoints()
                ln.info:SetPoint("TOPLEFT", PAD, -y)
                ln.info:SetText(info)
                ln.info:Show()
                y = y + INFO_H
            else
                ln.info:Hide()
            end

            if i < n then y = y + BLOCK_GAP end
        else
            ln.name:Hide()
            ln.time:Hide()
            ln.est:Hide()
            ln.info:Hide()
        end
    end
    frame:SetHeight(y + PAD)
    frame:Show()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
eventFrame:SetScript("OnEvent", function()
    AI.QueueOverlay.Refresh()
end)
