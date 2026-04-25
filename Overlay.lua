local addonName, NXR = ...

-- ============================================================================
-- Overlay Module (Epic 4)
-- ============================================================================

NXR.Overlay = {}

local overlayFrame
local rowPool = {}
local SavePosition

local ROW_HEIGHT   = 22
local ICON_SIZE    = 20
local PADDING      = 6
local MIN_WIDTH    = 50
local BAR_HEIGHT   = 14
local BAR_PADDING  = 4
local TITLE_HEIGHT = 16

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
    row.checkmark:SetPoint("CENTER", row.rating, "CENTER", 0, 0)
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

    -- Right-click: mark/unmark complete
    row:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" or not self.entryData then return end
        local ed = self.entryData
        local isCompleted
        if ed.classMode then
            isCompleted = NXR.IsClassCompleted(ed.challengeID, ed.classID)
        else
            isCompleted = NXR.IsSpecCompleted(ed.challengeID, ed.specID)
        end
        MenuUtil.CreateContextMenu(self, function(owner, rootDescription)
            if isCompleted then
                rootDescription:CreateButton("Unmark Complete", function()
                    if ed.classMode then
                        NXR.SetClassCompleted(ed.challengeID, ed.classID, false)
                    else
                        NXR.SetSpecCompleted(ed.challengeID, ed.specID, false)
                    end
                    NXR.RefreshOverlay()
                end)
            else
                rootDescription:CreateButton("Mark Complete", function()
                    if ed.classMode then
                        NXR.SetClassCompleted(ed.challengeID, ed.classID, true)
                    else
                        NXR.SetSpecCompleted(ed.challengeID, ed.specID, true)
                    end
                    NXR.RefreshOverlay()
                end)
            end
        end)
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
        -- Match current spec OR characters with historical data for this spec
        local hasHistoricalData = char.specBrackets and char.specBrackets[specID] ~= nil
        if char.specID == specID or hasHistoricalData then
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
-- Challenge progress calculation (Story: overlay progress bar)
-- ============================================================================

local function CalcChallengeProgress(challenge)
    local completed = 0
    local total = 0
    local goalRating = challenge.goalRating or 0
    local classMode = IsClassChallenge(challenge)

    if classMode then
        for classID in pairs(challenge.classes) do
            total = total + 1
            if NXR.IsClassCompleted(challenge.id, classID) then
                completed = completed + 1
            else
                local matches = FindMatchingCharactersForClass(classID, challenge)
                if matches[1] and matches[1].rating >= goalRating then
                    completed = completed + 1
                end
            end
        end
    else
        for specID in pairs(challenge.specs) do
            total = total + 1
            if NXR.IsSpecCompleted(challenge.id, specID) then
                completed = completed + 1
            else
                local matches = FindMatchingCharactersForSpec(specID, challenge)
                if matches[1] and matches[1].rating >= goalRating then
                    completed = completed + 1
                end
            end
        end
    end

    return completed, total
end

local function RefreshProgressBar(contentWidth, titleOffset)
    local pb = overlayFrame and overlayFrame.progressBar
    if not pb then return end

    local challenge = NXR.GetActiveChallenge()
    if not NelxRatedDB.settings.showOverlayProgressBar or not challenge then
        pb:Hide()
        return
    end

    local completed, total = CalcChallengeProgress(challenge)
    if total == 0 then
        pb:Hide()
        return
    end

    pb:ClearAllPoints()
    pb:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", PADDING, -(PADDING + (titleOffset or 0)))
    pb:SetWidth(contentWidth)
    pb:Show()

    local fillW = math.floor(contentWidth * completed / total)
    if fillW > 0 then
        overlayFrame.progressBarFill:SetWidth(fillW)
        overlayFrame.progressBarFill:Show()
    else
        overlayFrame.progressBarFill:Hide()
    end

    local pct = math.floor(completed / total * 100)
    overlayFrame.progressBarText:SetText(string.format("%d / %d  (%d%%)", completed, total, pct))
end

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
    -- Manual completion overrides all rating display logic
    local isManuallyCompleted = false
    if challenge and challenge.id then
        if classMode and classID then
            isManuallyCompleted = NXR.IsClassCompleted(challenge.id, classID)
        elseif specID then
            isManuallyCompleted = NXR.IsSpecCompleted(challenge.id, specID)
        end
    end

    if isManuallyCompleted then
        row.rating:SetText("")
        row.checkmark:Show()
    elseif bestMatch then
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

local ROLE_ORDER = { "HEALER", "MELEE", "RANGED", "TANK" }
local ROLE_LABELS = { HEALER = "Healers", MELEE = "Melee", RANGED = "Ranged", TANK = "Tanks" }

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
    if not specInfo then return "MELEE" end
    if specInfo.role == "DAMAGER" then
        -- Check melee vs ranged via roleSpecs lookup
        for _, s in ipairs(NXR.roleSpecs.RANGED or {}) do
            if s.specID == specID then return "RANGED" end
        end
        return "MELEE"
    end
    return specInfo.role
end

local function GetClassPrimaryRole(classID)
    local classInfo = NXR.classData[classID]
    if not classInfo then return "MELEE" end
    local roleCounts = { HEALER = 0, MELEE = 0, RANGED = 0, TANK = 0 }
    for _, s in ipairs(classInfo.specs) do
        if s.role == "DAMAGER" then
            local subRole = GetSpecRole(s.specID)
            roleCounts[subRole] = (roleCounts[subRole] or 0) + 1
        else
            local role = s.role or "MELEE"
            roleCounts[role] = (roleCounts[role] or 0) + 1
        end
    end
    local bestRole, bestCount = "MELEE", 0
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
        local role = entry.role or "MELEE"
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

    -- Title offset
    local titleOffset = 0
    if NelxRatedDB.settings.showOverlayTitle and challenge.name and challenge.name ~= "" then
        overlayFrame.titleText:SetText(challenge.name)
        overlayFrame.titleText:ClearAllPoints()
        overlayFrame.titleText:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", PADDING, -PADDING)
        overlayFrame.titleText:Show()
        titleOffset = TITLE_HEIGHT + BAR_PADDING
    else
        overlayFrame.titleText:Hide()
    end

    -- Bar offset
    local barOffset = 0
    if NelxRatedDB.settings.showOverlayProgressBar then
        local _, total = CalcChallengeProgress(challenge)
        if total > 0 then
            barOffset = BAR_HEIGHT + BAR_PADDING
        end
    end

    local topOffset = titleOffset + barOffset

    NXR.Debug("RefreshOverlay: challenge='" .. challenge.name .. "'",
        "goal=" .. tostring(challenge.goalRating),
        "classMode=" .. tostring(classMode),
        "brackets=" .. NXR.TableCount(challenge.brackets),
        classMode and ("classes=" .. NXR.TableCount(challenge.classes)) or ("specs=" .. NXR.TableCount(challenge.specs)))

    -- Build row data
    local entries = BuildRowEntries(challenge, classMode)
    if NelxRatedDB.settings.hideZeroRatingRows then
        local filtered = {}
        for _, entry in ipairs(entries) do
            if entry.bestMatch ~= nil then
                filtered[#filtered + 1] = entry
            end
        end
        entries = filtered
    end
    if #entries == 0 then
        overlayFrame:Hide()
        return
    end

    overlayFrame:Show()

    local groupByRole = NelxRatedDB.settings.overlayGroupByRole and not classMode
    local numColumns = NelxRatedDB.settings.overlayColumns or 1

    -- First pass: create rows, populate data, measure text
    local maxRatingWidth = 0
    local hasCheckmark = false
    local rowIndex = 0

    local function PrepareRow(entry)
        rowIndex = rowIndex + 1
        local row = GetRow(rowIndex)

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

        -- Store entry data for right-click context menu
        row.entryData = {
            challengeID = challenge.id,
            specID      = entry.specID,
            classID     = entry.classID,
            classMode   = classMode,
        }

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

        return row
    end

    -- Calculate column width (after measuring)
    local function CalcColWidth()
        local CHECKMARK_WIDTH = 14
        if hasCheckmark and maxRatingWidth < CHECKMARK_WIDTH then
            maxRatingWidth = CHECKMARK_WIDTH
        end
        local w = 4 + ICON_SIZE + 6 + maxRatingWidth + 12
        if w < MIN_WIDTH then w = MIN_WIDTH end
        return w
    end

    if groupByRole then
        -- ============================================================
        -- GROUPED LAYOUT: each role starts a new column
        -- ============================================================
        local groups = GroupEntriesByRole(entries)
        local numGroups = #groups

        -- Prepare all rows first (for width measurement)
        local headerIndex = 0
        local groupData = {}
        for _, group in ipairs(groups) do
            headerIndex = headerIndex + 1
            local header = GetRoleHeader(headerIndex)
            header:SetText(group.label)
            local rows = {}
            for _, entry in ipairs(group.entries) do
                table.insert(rows, PrepareRow(entry))
            end
            table.insert(groupData, { header = header, rows = rows })
        end

        local colWidth = CalcColWidth()

        -- Distribute columns: minimum = numGroups, extra go to largest groups
        local effectiveCols = math.max(numGroups, numColumns)
        local groupCols = {}
        for i = 1, numGroups do
            groupCols[i] = 1
        end

        local extraCols = effectiveCols - numGroups
        if extraCols > 0 then
            -- Distribute extra columns round-robin to groups sorted by size (largest first)
            local sortedIdx = {}
            for i = 1, numGroups do sortedIdx[i] = i end
            table.sort(sortedIdx, function(a, b)
                return #groupData[a].rows > #groupData[b].rows
            end)
            for e = 1, extraCols do
                local idx = sortedIdx[((e - 1) % numGroups) + 1]
                groupCols[idx] = groupCols[idx] + 1
            end
        end

        -- Layout each group
        local colOffset = 0
        local tallestCol = 0

        for gi, gd in ipairs(groupData) do
            local gCols = groupCols[gi]
            local numEntries = #gd.rows
            local rowsPerGCol = math.ceil(numEntries / gCols)
            if rowsPerGCol < 1 then rowsPerGCol = 1 end

            -- Header on first column of group
            gd.header:ClearAllPoints()
            gd.header:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", colOffset * colWidth + 4, -PADDING - topOffset - 6)
            gd.header:Show()

            -- Offset rows below header
            local headerOffset = ROW_HEIGHT + 6

            for ri, row in ipairs(gd.rows) do
                local entryIdx = ri - 1
                local localCol = math.floor(entryIdx / rowsPerGCol)
                local localRow = entryIdx % rowsPerGCol

                local xOff = (colOffset + localCol) * colWidth
                local yOff = -PADDING - topOffset - headerOffset - localRow * ROW_HEIGHT

                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", xOff, yOff)
                row:SetWidth(colWidth)
                row:Show()

                local colHeight = headerOffset + (localRow + 1) * ROW_HEIGHT
                if colHeight > tallestCol then tallestCol = colHeight end
            end

            -- If group is empty, still account for header
            if numEntries == 0 then
                if headerOffset > tallestCol then tallestCol = headerOffset end
            end

            colOffset = colOffset + gCols
        end

        local totalHeight = PADDING * 2 + tallestCol + topOffset
        local totalWidth = colOffset * colWidth
        overlayFrame:SetSize(totalWidth, totalHeight)
        RefreshProgressBar(totalWidth - PADDING * 2, titleOffset)
    else
        -- ============================================================
        -- FLAT LAYOUT: distribute all entries across columns
        -- ============================================================
        local preparedRows = {}
        for _, entry in ipairs(entries) do
            table.insert(preparedRows, PrepareRow(entry))
        end

        local colWidth = CalcColWidth()

        local totalItems = #preparedRows
        local effectiveCols = numColumns
        if effectiveCols > totalItems then effectiveCols = totalItems end
        if effectiveCols < 1 then effectiveCols = 1 end

        local rowsPerCol = math.ceil(totalItems / effectiveCols)

        for i, row in ipairs(preparedRows) do
            local itemIdx = i - 1
            local colIdx = math.floor(itemIdx / rowsPerCol)
            local rowInCol = itemIdx % rowsPerCol

            local xOff = colIdx * colWidth
            local yOff = -PADDING - topOffset - rowInCol * ROW_HEIGHT

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", xOff, yOff)
            row:SetWidth(colWidth)
            row:Show()
        end

        local totalHeight = PADDING * 2 + rowsPerCol * ROW_HEIGHT + topOffset
        local totalWidth = effectiveCols * colWidth
        overlayFrame:SetSize(totalWidth, totalHeight)
        RefreshProgressBar(totalWidth - PADDING * 2, titleOffset)
    end

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

    -- Progress bar sub-frames (Story: overlay progress bar)
    local pb = CreateFrame("Frame", nil, overlayFrame)
    pb:SetHeight(BAR_HEIGHT)
    pb:Hide()
    overlayFrame.progressBar = pb

    local pbBg = pb:CreateTexture(nil, "BACKGROUND")
    pbBg:SetAllPoints()
    pbBg:SetColorTexture(0.10, 0.04, 0.04, 1)

    local pbFill = pb:CreateTexture(nil, "BORDER")
    pbFill:SetPoint("TOPLEFT")
    pbFill:SetPoint("BOTTOMLEFT")
    pbFill:SetWidth(1)
    local cb = NXR.COLORS.CRIMSON_BRIGHT
    pbFill:SetColorTexture(cb[1], cb[2], cb[3], 1)
    overlayFrame.progressBarFill = pbFill

    local pbText = pb:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
    pbText:SetAllPoints()
    pbText:SetJustifyH("CENTER")
    pbText:SetJustifyV("MIDDLE")
    pbText:SetTextColor(1, 1, 1)
    overlayFrame.progressBarText = pbText

    -- Challenge title fontstring
    local titleText = overlayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleText:SetJustifyH("LEFT")
    titleText:SetTextColor(0.96, 0.92, 0.90)
    titleText:Hide()
    overlayFrame.titleText = titleText

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
