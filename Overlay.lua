local addonName, NXR = ...

-- ============================================================================
-- Overlay Module (Epic 4)
-- ============================================================================

NXR.Overlay = {}

local overlayFrame
local rowPool = {}
local SavePosition

local ROW_HEIGHT = 22
local ICON_SIZE  = 20
local PADDING    = 6
local MIN_WIDTH  = 50

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
local COLOR_GOLD = { 1.0, 0.82, 0.0, 0.8 }

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
-- Scale changed (IMP-4)
-- ============================================================================

local function ApplyScale()
    if not overlayFrame then return end
    local scale = NelxRatedDB.settings.overlayScale or 1.0
    overlayFrame:SetScale(scale)
end

function NXR.Overlay.OnScaleChanged()
    ApplyScale()
end

-- ============================================================================
-- Opacity changed (Story 4-5)
-- ============================================================================

function NXR.Overlay.OnOpacityChanged()
    if not overlayFrame then return end
    local inPvP = IsInRatedPvP()
    local opacity = GetCurrentOpacity()
    NXR.Debug("Overlay opacity:", opacity, "| inPvP:", tostring(inPvP))
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

    -- Rating
    row.rating = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.rating:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.rating:SetPoint("RIGHT", -8, 0)

    -- Gold border for logged-in character indicator (Story 9-3)
    row.activeGlow = row:CreateTexture(nil, "BACKGROUND")
    row.activeGlow:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -2, 2)
    row.activeGlow:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 2, -2)
    row.activeGlow:SetColorTexture(COLOR_GOLD[1], COLOR_GOLD[2], COLOR_GOLD[3], COLOR_GOLD[4])
    row.activeGlow:Hide()

    -- Checkmark texture (for >= 100% goal) — replaces rating text when shown
    row.checkmark = row:CreateTexture(nil, "OVERLAY")
    row.checkmark:SetSize(14, 14)
    row.checkmark:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.checkmark:SetTexture(CHECKMARK_TEXTURE)
    row.checkmark:Hide()

    -- Tooltip scripts (Story 4-3)
    row:SetScript("OnEnter", function(self)
        if not self.tooltipData then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

        -- Title line
        GameTooltip:AddLine(self.tooltipData.title, 1, 1, 1)

        if self.tooltipData.characters and #self.tooltipData.characters > 0 then
            for _, info in ipairs(self.tooltipData.characters) do
                local line
                if self.tooltipData.classMode then
                    -- Class challenge: show spec name alongside character
                    line = string.format("%s  %s  %d  (%s)",
                        info.charKey, info.specName, info.rating, info.bracketName)
                else
                    line = string.format("%s  %d  (%s)",
                        info.charKey, info.rating, info.bracketName)
                end
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
            local noDataMsg = self.tooltipData.classMode
                and "No character tracked for this class"
                or "No character tracked for this spec"
            GameTooltip:AddLine(noDataMsg, 0.5, 0.5, 0.5)
        end

        GameTooltip:Show()
    end)

    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Forward drag events to the overlay so rows don't block dragging
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function()
        if not NelxRatedDB.settings.overlayLocked then
            overlayFrame:StartMoving()
        end
    end)
    row:SetScript("OnDragStop", function()
        overlayFrame:StopMovingOrSizing()
        SavePosition()
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
-- Class icon helper
-- ============================================================================

local function SetClassIcon(tex, classFileName)
    local ok = pcall(function()
        tex:SetAtlas("classicon-" .. classFileName:lower())
    end)
    if not ok then
        tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes")
        if CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFileName] then
            tex:SetTexCoord(unpack(CLASS_ICON_TCOORDS[classFileName]))
        end
    end
end

-- ============================================================================
-- Character matching logic (Story 4-2)
-- ============================================================================

-- Find characters matching a single specID with rating in challenge brackets
local function FindMatchingCharactersForSpec(specID, challenge)
    local matches = {}
    if not NelxRatedDB or not NelxRatedDB.characters then return matches end

    for charKey, char in pairs(NelxRatedDB.characters) do
        if char.specID == specID then
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
                    specID      = specID,
                    specName    = NXR.specData[specID] and NXR.specData[specID].specName or "",
                })
            end
        end
    end

    table.sort(matches, function(a, b) return a.rating > b.rating end)
    return matches
end

-- Find all characters of any spec belonging to a class, best rating across all specs & brackets
local function FindMatchingCharactersForClass(classID, challenge)
    local matches = {}
    if not NelxRatedDB or not NelxRatedDB.characters then return matches end

    local classInfo = NXR.classData[classID]
    if not classInfo then return matches end

    -- Collect all specIDs belonging to this class
    local classSpecIDs = {}
    for _, s in ipairs(classInfo.specs) do
        classSpecIDs[s.specID] = true
    end

    for charKey, char in pairs(NelxRatedDB.characters) do
        -- Check if this character's class matches (via specID -> classID lookup)
        local charSpec = char.specID and NXR.specData[char.specID]
        if charSpec and charSpec.classID == classID then
            local bestRating = 0
            local bestBracket = nil
            local bestSpecID = nil

            -- Check all specs this character might have data for
            for specID in pairs(classSpecIDs) do
                for bracketIdx in pairs(challenge.brackets) do
                    local data = NXR.GetRating(charKey, bracketIdx, specID)
                    if data and data.rating and data.rating > bestRating then
                        bestRating = data.rating
                        bestBracket = bracketIdx
                        bestSpecID = specID
                    end
                end
            end

            if bestRating > 0 then
                table.insert(matches, {
                    charKey     = charKey,
                    rating      = bestRating,
                    bracketIdx  = bestBracket,
                    bracketName = NXR.BRACKET_NAMES[bestBracket] or "Unknown",
                    specID      = bestSpecID,
                    specName    = NXR.specData[bestSpecID] and NXR.specData[bestSpecID].specName or "",
                })
            end
        end
    end

    table.sort(matches, function(a, b) return a.rating > b.rating end)
    return matches
end

-- ============================================================================
-- Determine if this is a class challenge
-- ============================================================================

local function IsClassChallenge(challenge)
    if not challenge.classes then return false end
    for _ in pairs(challenge.classes) do return true end
    return false
end

-- ============================================================================
-- Collect sorted class IDs from challenge
-- ============================================================================

local function GetSortedClassIDs(challenge)
    local classIDs = {}
    for classID in pairs(challenge.classes) do
        table.insert(classIDs, classID)
    end
    table.sort(classIDs, function(a, b)
        local ca = NXR.classData[a]
        local cb = NXR.classData[b]
        if not ca or not cb then return a < b end
        return ca.className < cb.className
    end)
    return classIDs
end

-- ============================================================================
-- Collect sorted spec IDs from challenge (specs is a hash table)
-- ============================================================================

local function GetSortedSpecIDs(challenge)
    local specIDs = {}
    for specID in pairs(challenge.specs) do
        table.insert(specIDs, specID)
    end
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

-- ============================================================================
-- Populate a single row with match data
-- ============================================================================

local function IsLoggedInRow(specID, classID, classMode)
    local charKey = NXR.currentCharKey
    if not charKey then return false end
    local char = NelxRatedDB.characters and NelxRatedDB.characters[charKey]
    if not char then return false end

    if classMode then
        local charSpec = char.specID and NXR.specData[char.specID]
        return charSpec and charSpec.classID == classID
    else
        return char.specID == specID
    end
end

local function PopulateRow(row, bestMatch, challenge, specID, classID, classMode)
    if bestMatch then
        local color, showCheck = GetProgressColor(bestMatch.rating, challenge.goalRating or 0)
        if showCheck then
            row.rating:SetText("")
            row.checkmark:Show()
        else
            row.rating:SetText(tostring(bestMatch.rating))
            row.rating:SetTextColor(color[1], color[2], color[3])
            row.checkmark:Hide()
        end
    else
        row.rating:SetText("\226\128\148") -- em dash
        row.rating:SetTextColor(0.5, 0.5, 0.5)
        row.checkmark:Hide()
    end

    -- Logged-in character indicator (Story 9-3)
    if IsLoggedInRow(specID, classID, classMode) then
        row.activeGlow:Show()
    else
        row.activeGlow:Hide()
    end
end

-- ============================================================================
-- Role grouping helpers (Story 9-5)
-- ============================================================================

local ROLE_ORDER = { "HEALER", "DAMAGER", "TANK" }
local ROLE_LABELS = { HEALER = "Healers", DAMAGER = "DPS", TANK = "Tanks" }

local roleHeaderPool = {}

local function GetRoleHeader(index)
    if not roleHeaderPool[index] then
        local header = overlayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
        header:SetTextColor(0.48, 0.45, 0.43)
        roleHeaderPool[index] = header
    end
    return roleHeaderPool[index]
end

local function GetSpecRole(specID)
    local specInfo = NXR.specData[specID]
    return specInfo and specInfo.role or "DAMAGER"
end

local function GetClassPrimaryRole(classID)
    local classInfo = NXR.classData[classID]
    if not classInfo then return "DAMAGER" end
    local roleCounts = { HEALER = 0, DAMAGER = 0, TANK = 0 }
    for _, s in ipairs(classInfo.specs) do
        local role = s.role or "DAMAGER"
        roleCounts[role] = (roleCounts[role] or 0) + 1
    end
    local bestRole, bestCount = "DAMAGER", 0
    for role, count in pairs(roleCounts) do
        if count > bestCount then
            bestRole = role
            bestCount = count
        end
    end
    return bestRole
end

-- ============================================================================
-- Build row entries from challenge data
-- ============================================================================

local function BuildRowEntries(challenge, classMode)
    local entries = {}

    if classMode then
        local classIDs = GetSortedClassIDs(challenge)
        for _, classID in ipairs(classIDs) do
            local classInfo = NXR.classData[classID]
            local matches = FindMatchingCharactersForClass(classID, challenge)
            table.insert(entries, {
                type       = "class",
                classID    = classID,
                classInfo  = classInfo,
                matches    = matches,
                bestMatch  = matches[1],
                role       = GetClassPrimaryRole(classID),
            })
        end
    else
        local specIDs = GetSortedSpecIDs(challenge)
        for _, specID in ipairs(specIDs) do
            local specInfo = NXR.specData[specID]
            local matches = FindMatchingCharactersForSpec(specID, challenge)
            table.insert(entries, {
                type       = "spec",
                specID     = specID,
                specInfo   = specInfo,
                matches    = matches,
                bestMatch  = matches[1],
                role       = GetSpecRole(specID),
            })
        end
    end

    return entries
end

-- ============================================================================
-- Group entries by role
-- ============================================================================

local function GroupEntriesByRole(entries)
    local groups = {}
    local byRole = {}
    for _, role in ipairs(ROLE_ORDER) do
        byRole[role] = {}
    end
    for _, entry in ipairs(entries) do
        local role = entry.role or "DAMAGER"
        if not byRole[role] then byRole[role] = {} end
        table.insert(byRole[role], entry)
    end
    for _, role in ipairs(ROLE_ORDER) do
        if #byRole[role] > 0 then
            table.insert(groups, { role = role, label = ROLE_LABELS[role], entries = byRole[role] })
        end
    end
    return groups
end

-- ============================================================================
-- Refresh overlay (Story 4-2, 4-3, 4-4, 9-1 through 9-5)
-- ============================================================================

function NXR.RefreshOverlay()
    if not overlayFrame then
        NXR.Debug("RefreshOverlay: frame not created yet")
        return
    end

    -- Respect show/hide setting
    if NelxRatedDB.settings.showOverlay == false then
        NXR.Debug("RefreshOverlay: overlay hidden by setting")
        overlayFrame:Hide()
        return
    end

    local challenge = NXR.GetActiveChallenge()

    -- Hide all rows and role headers
    for _, row in ipairs(rowPool) do
        row:Hide()
    end
    for _, header in ipairs(roleHeaderPool) do
        header:Hide()
    end

    -- If no active challenge, hide overlay
    if not challenge or not challenge.specs then
        NXR.Debug("RefreshOverlay: no active challenge")
        overlayFrame:Hide()
        return
    end

    local classMode = IsClassChallenge(challenge)
    NXR.Debug("RefreshOverlay: challenge='" .. challenge.name .. "'",
        "goal=" .. tostring(challenge.goalRating),
        "classMode=" .. tostring(classMode),
        "brackets=" .. NXR.TableCount(challenge.brackets),
        classMode and ("classes=" .. NXR.TableCount(challenge.classes)) or ("specs=" .. NXR.TableCount(challenge.specs)))

    -- Build row data
    local entries = BuildRowEntries(challenge, classMode)
    if #entries == 0 then
        overlayFrame:Hide()
        return
    end

    overlayFrame:Show()

    local groupByRole = NelxRatedDB.settings.overlayGroupByRole
    local numColumns = NelxRatedDB.settings.overlayColumns or 1

    -- Build layout items: either flat or grouped
    -- Each layout item is { type="row", entry=... } or { type="header", label=... }
    local layoutItems = {}

    if groupByRole then
        local groups = GroupEntriesByRole(entries)
        for _, group in ipairs(groups) do
            table.insert(layoutItems, { type = "header", label = group.label })
            for _, entry in ipairs(group.entries) do
                table.insert(layoutItems, { type = "row", entry = entry })
            end
        end
    else
        for _, entry in ipairs(entries) do
            table.insert(layoutItems, { type = "row", entry = entry })
        end
    end

    -- Render all items and measure widths
    local maxRatingWidth = 0
    local hasCheckmark = false
    local rowIndex = 0
    local headerIndex = 0

    -- First pass: create rows/headers, populate data, measure text
    local renderedItems = {} -- { type, row/header, layoutIndex }
    for i, item in ipairs(layoutItems) do
        if item.type == "header" then
            headerIndex = headerIndex + 1
            local header = GetRoleHeader(headerIndex)
            header:SetText(item.label)
            table.insert(renderedItems, { type = "header", element = header, layoutIndex = i })
        else
            rowIndex = rowIndex + 1
            local row = GetRow(rowIndex)
            local entry = item.entry

            -- Set icon
            if entry.type == "class" then
                if entry.classInfo then
                    SetClassIcon(row.icon, entry.classInfo.classFileName)
                else
                    row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                end
            else
                row.icon:SetTexture(entry.specInfo and entry.specInfo.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            end

            -- Populate rating/checkmark/glow
            PopulateRow(row, entry.bestMatch, challenge,
                entry.specID, entry.classID, classMode)

            -- Tooltip
            if entry.type == "class" then
                row.tooltipData = {
                    title      = entry.classInfo and entry.classInfo.className or ("Class " .. entry.classID),
                    classMode  = true,
                    characters = entry.matches,
                    goalRating = challenge.goalRating,
                }
            else
                row.tooltipData = {
                    title      = entry.specInfo and entry.specInfo.specName or ("Spec " .. entry.specID),
                    classMode  = false,
                    characters = entry.matches,
                    goalRating = challenge.goalRating,
                }
            end

            -- Measure
            if row.checkmark:IsShown() then
                hasCheckmark = true
            else
                local rw = row.rating:GetStringWidth() or 0
                if rw > maxRatingWidth then maxRatingWidth = rw end
            end

            table.insert(renderedItems, { type = "row", element = row, layoutIndex = i })
        end
    end

    -- Calculate column width
    local CHECKMARK_WIDTH = 14
    if hasCheckmark and maxRatingWidth < CHECKMARK_WIDTH then
        maxRatingWidth = CHECKMARK_WIDTH
    end
    local colWidth = 4 + ICON_SIZE + 6 + maxRatingWidth + 12
    if colWidth < MIN_WIDTH then colWidth = MIN_WIDTH end

    -- Layout: distribute items across columns
    local totalItems = #renderedItems
    local effectiveCols = numColumns
    if effectiveCols > totalItems then effectiveCols = totalItems end
    if effectiveCols < 1 then effectiveCols = 1 end

    local rowsPerCol = math.ceil(totalItems / effectiveCols)

    for i, rendered in ipairs(renderedItems) do
        local itemIdx = i - 1
        local colIdx = math.floor(itemIdx / rowsPerCol)
        local rowInCol = itemIdx % rowsPerCol

        local xOff = colIdx * colWidth
        local yOff = -PADDING - rowInCol * ROW_HEIGHT

        if rendered.type == "header" then
            local header = rendered.element
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", xOff + 4, yOff - 4)
            header:Show()
        else
            local row = rendered.element
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", xOff, yOff)
            row:SetWidth(colWidth)
            row:Show()
        end
    end

    -- Resize overlay
    local totalHeight = PADDING * 2 + rowsPerCol * ROW_HEIGHT
    local totalWidth = effectiveCols * colWidth

    overlayFrame:SetSize(totalWidth, totalHeight)

    -- Re-apply opacity and mouse state
    NXR.Overlay.OnOpacityChanged()
end

-- ============================================================================
-- Position persistence (Story 4-1)
-- ============================================================================

SavePosition = function()
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

    -- Apply scale
    ApplyScale()

    -- Restore position
    RestorePosition()

    -- Apply lock state
    ApplyLockState()

    -- Initial refresh
    NXR.Debug("Overlay frame created, restoring position and refreshing")
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
