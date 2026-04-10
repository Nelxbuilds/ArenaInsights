local addonName, NXR = ...

-- ============================================================================
-- Overlay Module (Epic 4)
-- ============================================================================

NXR.Overlay = {}

local overlayFrame
local rowPool = {}

local ROW_HEIGHT = 22
local ICON_SIZE  = 20
local PADDING    = 6
local MIN_WIDTH  = 160

-- ============================================================================
-- Backdrop definition (Story 4-1)
-- ============================================================================

local OVERLAY_BACKDROP = {
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
}

local OVERLAY_BG_COLOR     = { 0.06, 0.06, 0.06, 0.85 }
local OVERLAY_BORDER_COLOR = NXR.COLORS.CRIMSON_DIM

-- ============================================================================
-- Rating progress colors (Story 4-4)
-- ============================================================================

local COLOR_WHITE  = { 1.00, 1.00, 1.00 }
local COLOR_ORANGE = { 0.93, 0.55, 0.05 }
local COLOR_YELLOW = { 0.95, 0.80, 0.20 }

local CHECKMARK_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready"

local function GetProgressColor(rating, goalRating)
    if goalRating <= 0 then return COLOR_WHITE, false end
    local pct = rating / goalRating
    if pct >= 1.0 then
        return COLOR_WHITE, true -- show checkmark
    elseif pct >= 0.9 then
        return COLOR_YELLOW, false
    elseif pct >= 0.8 then
        return COLOR_ORANGE, false
    else
        return COLOR_WHITE, false
    end
end

-- ============================================================================
-- Arena / BG detection (Story 4-5)
-- ============================================================================

local function IsInRatedPvP()
    if IsActiveBattlefieldArena and IsActiveBattlefieldArena() then
        return true
    end
    if C_PvP and C_PvP.IsRatedBattleground and C_PvP.IsRatedBattleground() then
        return true
    end
    return false
end

local function GetCurrentOpacity()
    if not NelxRatedDB or not NelxRatedDB.settings then return 1.0 end
    if IsInRatedPvP() then
        return NelxRatedDB.settings.opacityInArena or 1.0
    else
        return NelxRatedDB.settings.opacityOutOfArena or 1.0
    end
end

-- ============================================================================
-- Mouse enable/disable based on opacity (Story 4-5)
-- ============================================================================

local function ApplyMouseState(opacity)
    if not overlayFrame then return end
    local enable = (opacity > 0)
    overlayFrame:EnableMouse(enable)
    for _, row in ipairs(rowPool) do
        if row:IsShown() then
            row:EnableMouse(enable)
        end
    end
end

-- ============================================================================
-- Lock / Unlock (drag toggle)
-- ============================================================================

local function ApplyLockState()
    if not overlayFrame then return end
    local locked = NelxRatedDB.settings.overlayLocked
    overlayFrame:SetMovable(not locked)
    if locked then
        overlayFrame:RegisterForDrag()  -- clear drag registration
    else
        overlayFrame:RegisterForDrag("LeftButton")
    end
end

function NXR.Overlay.OnLockChanged()
    ApplyLockState()
end

function NXR.Overlay.SetLocked(locked)
    NelxRatedDB.settings.overlayLocked = locked
    ApplyLockState()
    if locked then
        print("|cffE6D200NelxRated|r: Overlay locked")
    else
        print("|cffE6D200NelxRated|r: Overlay unlocked")
    end
end

-- ============================================================================
-- Background toggle (Story 4-1)
-- ============================================================================

local function ApplyBackground()
    if not overlayFrame then return end
    if NelxRatedDB.settings.showOverlayBackground then
        overlayFrame:SetBackdrop(OVERLAY_BACKDROP)
        overlayFrame:SetBackdropColor(unpack(OVERLAY_BG_COLOR))
        overlayFrame:SetBackdropBorderColor(unpack(OVERLAY_BORDER_COLOR))
    else
        overlayFrame:SetBackdrop(nil)
    end
end

function NXR.Overlay.OnBackgroundChanged()
    ApplyBackground()
end

-- ============================================================================
-- Opacity changed (Story 4-5)
-- ============================================================================

function NXR.Overlay.OnOpacityChanged()
    if not overlayFrame then return end
    local opacity = GetCurrentOpacity()
    overlayFrame:SetAlpha(opacity)
    ApplyMouseState(opacity)
end

-- ============================================================================
-- Show / Hide toggle
-- ============================================================================

function NXR.Overlay.SetShown(show)
    NelxRatedDB.settings.showOverlay = show
    if show then
        NXR.RefreshOverlay()
        print("|cffE6D200NelxRated|r: Overlay shown")
    else
        if overlayFrame then overlayFrame:Hide() end
        print("|cffE6D200NelxRated|r: Overlay hidden")
    end
end

function NXR.Overlay.Toggle()
    local current = NelxRatedDB.settings.showOverlay
    NXR.Overlay.SetShown(not current)
end

-- ============================================================================
-- Row creation / pooling (Story 4-2)
-- ============================================================================

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)

    -- Icon
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", 4, 0)

    -- Character name
    row.charName = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.charName:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.charName:SetTextColor(0.85, 0.85, 0.85)

    -- Rating
    row.rating = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.rating:SetPoint("RIGHT", -4, 0)

    -- Checkmark texture (for >= 100% goal)
    row.checkmark = row:CreateTexture(nil, "OVERLAY")
    row.checkmark:SetSize(14, 14)
    row.checkmark:SetPoint("RIGHT", row.rating, "LEFT", -2, 0)
    row.checkmark:SetTexture(CHECKMARK_TEXTURE)
    row.checkmark:Hide()

    -- Tooltip scripts (Story 4-3)
    row:SetScript("OnEnter", function(self)
        if not self.tooltipData then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

        -- Spec name as title
        GameTooltip:AddLine(self.tooltipData.specName, 1, 1, 1)

        if self.tooltipData.characters and #self.tooltipData.characters > 0 then
            for _, info in ipairs(self.tooltipData.characters) do
                local line = string.format("%s  %d  (%s)", info.charKey, info.rating, info.bracketName)
                GameTooltip:AddLine(line, 0.8, 0.8, 0.8)
            end

            -- Goal progress line
            if self.tooltipData.goalRating and self.tooltipData.goalRating > 0 then
                local bestRating = self.tooltipData.characters[1].rating
                local pct = bestRating / self.tooltipData.goalRating
                local color = GetProgressColor(bestRating, self.tooltipData.goalRating)
                local pctStr = string.format("Goal: %d (%.0f%%)", self.tooltipData.goalRating, pct * 100)
                GameTooltip:AddLine(pctStr, color[1], color[2], color[3])
            end
        else
            GameTooltip:AddLine("No character tracked for this spec", 0.5, 0.5, 0.5)
        end

        GameTooltip:Show()
    end)

    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return row
end

local function GetRow(index)
    if not rowPool[index] then
        rowPool[index] = CreateRow(overlayFrame, index)
    end
    return rowPool[index]
end

-- ============================================================================
-- Character matching logic (Story 4-2)
-- ============================================================================

local function FindMatchingCharacters(specID, challenge)
    local matches = {}
    if not NelxRatedDB or not NelxRatedDB.characters then return matches end

    for charKey, char in pairs(NelxRatedDB.characters) do
        if char.specID == specID then
            -- Find best rating across challenge's selected brackets
            local bestRating = 0
            local bestBracket = nil

            for bracketIdx in pairs(challenge.brackets) do
                local data = NXR.GetRating(charKey, bracketIdx, specID)
                if data and data.rating and data.rating > bestRating then
                    bestRating = data.rating
                    bestBracket = bracketIdx
                end
            end

            if bestRating > 0 then
                table.insert(matches, {
                    charKey     = charKey,
                    rating      = bestRating,
                    bracketIdx  = bestBracket,
                    bracketName = NXR.BRACKET_NAMES[bestBracket] or "Unknown",
                })
            end
        end
    end

    -- Sort by rating descending
    table.sort(matches, function(a, b) return a.rating > b.rating end)
    return matches
end

-- ============================================================================
-- Collect sorted spec IDs from challenge (specs is a hash table)
-- ============================================================================

local function GetSortedSpecIDs(challenge)
    local specIDs = {}
    for specID in pairs(challenge.specs) do
        table.insert(specIDs, specID)
    end
    -- Sort by class name then spec name for consistent ordering
    table.sort(specIDs, function(a, b)
        local sa = NXR.specData[a]
        local sb = NXR.specData[b]
        if not sa or not sb then return a < b end
        if sa.className ~= sb.className then
            return sa.className < sb.className
        end
        return sa.specName < sb.specName
    end)
    return specIDs
end

-- ============================================================================
-- Refresh overlay (Story 4-2, 4-3, 4-4)
-- ============================================================================

function NXR.RefreshOverlay()
    if not overlayFrame then return end

    -- Respect show/hide setting
    if NelxRatedDB.settings.showOverlay == false then
        overlayFrame:Hide()
        return
    end

    local challenge = NXR.GetActiveChallenge()

    -- Hide all rows first
    for _, row in ipairs(rowPool) do
        row:Hide()
    end

    -- If no active challenge, hide overlay
    if not challenge or not challenge.specs then
        overlayFrame:Hide()
        return
    end

    -- Collect spec IDs from the hash table
    local specIDs = GetSortedSpecIDs(challenge)
    if #specIDs == 0 then
        overlayFrame:Hide()
        return
    end

    overlayFrame:Show()

    local maxNameWidth = 0
    local maxRatingWidth = 0
    local rowIndex = 0

    for _, specID in ipairs(specIDs) do
        rowIndex = rowIndex + 1
        local row = GetRow(rowIndex)

        -- Determine icon: class icon if class challenge, else spec icon
        local specInfo = NXR.specData[specID]
        local iconTexture
        if specInfo then
            local isClassChallenge = false
            if challenge.classes then
                for classID in pairs(challenge.classes) do
                    if classID == specInfo.classID then
                        isClassChallenge = true
                        break
                    end
                end
            end

            if isClassChallenge then
                iconTexture = specInfo.icon  -- use spec icon for clarity
            else
                iconTexture = specInfo.icon
            end
        end

        row.icon:SetTexture(iconTexture or "Interface\\Icons\\INV_Misc_QuestionMark")

        -- Find matching characters
        local matches = FindMatchingCharacters(specID, challenge)
        local bestMatch = matches[1]

        if bestMatch then
            row.charName:SetText(bestMatch.charKey)
            row.rating:SetText(tostring(bestMatch.rating))

            -- Apply progress color (Story 4-4)
            local color, showCheck = GetProgressColor(bestMatch.rating, challenge.goalRating or 0)
            row.rating:SetTextColor(color[1], color[2], color[3])
            if showCheck then
                row.checkmark:Show()
            else
                row.checkmark:Hide()
            end
        else
            row.charName:SetText("")
            row.rating:SetText("\226\128\148") -- em dash
            row.rating:SetTextColor(0.5, 0.5, 0.5)
            row.checkmark:Hide()
        end

        -- Tooltip data (Story 4-3)
        row.tooltipData = {
            specName   = specInfo and specInfo.specName or ("Spec " .. specID),
            characters = matches,
            goalRating = challenge.goalRating,
        }

        -- Layout
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", 0, -PADDING - (rowIndex - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", overlayFrame, "RIGHT", 0, 0)
        row:Show()

        -- Track widths for dynamic sizing
        local nw = row.charName:GetStringWidth() or 0
        local rw = row.rating:GetStringWidth() or 0
        if nw > maxNameWidth then maxNameWidth = nw end
        if rw > maxRatingWidth then maxRatingWidth = rw end
    end

    -- Resize overlay dynamically
    local totalHeight = PADDING * 2 + rowIndex * ROW_HEIGHT
    local totalWidth = ICON_SIZE + 4 + 6 + maxNameWidth + 20 + maxRatingWidth + 20 + 4
    if totalWidth < MIN_WIDTH then totalWidth = MIN_WIDTH end

    overlayFrame:SetSize(totalWidth, totalHeight)

    -- Re-apply opacity and mouse state
    NXR.Overlay.OnOpacityChanged()
end

-- ============================================================================
-- Position persistence (Story 4-1)
-- ============================================================================

local function SavePosition()
    if not overlayFrame then return end
    local point, _, relPoint, x, y = overlayFrame:GetPoint()
    NelxRatedDB.overlayPosition = {
        point    = point,
        relPoint = relPoint,
        x        = x,
        y        = y,
    }
end

local function RestorePosition()
    if not overlayFrame then return end
    local pos = NelxRatedDB.overlayPosition
    if pos and pos.point then
        overlayFrame:ClearAllPoints()
        overlayFrame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        overlayFrame:ClearAllPoints()
        overlayFrame:SetPoint("CENTER", UIParent, "CENTER", 150, 0)
    end
end

-- ============================================================================
-- Frame creation (Story 4-1)
-- ============================================================================

local function CreateOverlayFrame()
    overlayFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    overlayFrame:SetSize(MIN_WIDTH, 60)
    overlayFrame:SetFrameStrata("MEDIUM")
    overlayFrame:SetClampedToScreen(true)

    -- Dragging
    overlayFrame:SetMovable(true)
    overlayFrame:EnableMouse(true)
    overlayFrame:RegisterForDrag("LeftButton")
    overlayFrame:SetScript("OnDragStart", function(self)
        if not NelxRatedDB.settings.overlayLocked then
            self:StartMoving()
        end
    end)
    overlayFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)

    -- Apply backdrop
    ApplyBackground()

    -- Restore position
    RestorePosition()

    -- Apply lock state
    ApplyLockState()

    -- Initial refresh
    NXR.RefreshOverlay()
end

-- ============================================================================
-- Event handling (Story 4-1, 4-5)
-- ============================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            -- Defer creation slightly so DB is initialized by Core.lua first
            C_Timer.After(0, function()
                CreateOverlayFrame()
            end)
            self:UnregisterEvent("ADDON_LOADED")
        end

    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        -- Re-evaluate opacity for arena/BG state (Story 4-5)
        NXR.Overlay.OnOpacityChanged()
    end
end)
