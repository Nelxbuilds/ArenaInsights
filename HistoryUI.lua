local addonName, NXR = ...

-- ============================================================================
-- History Tab (Epic 6 — Stories 6-3 through 6-6)
-- ============================================================================

local PADDING       = 8
local PADDING_LEFT  = 44
local PADDING_RIGHT = 8
local PADDING_TOP   = 10
local PADDING_BOT   = 22
local LINE_W        = 1.5
local MIN_POINTS    = 3
local GOAL_LINE_COLOR = { 1.0, 0.82, 0.0, 0.8 }

-- State
local graphFrame, canvas, placeholder
local lines = {}
local xLabels = {}
local yLabels = {}
local goalLine, goalLabel
local filterCharKey, filterSpecID, filterBracketIndex
local charButton, specButton, bracketButton

-- ============================================================================
-- Object pooling helpers
-- ============================================================================

local function GetOrCreateLine(parent, index)
    if not lines[index] then
        local line = parent:CreateLine()
        line:SetThickness(LINE_W)
        line:SetColorTexture(unpack(NXR.COLORS.CRIMSON_BRIGHT))
        lines[index] = line
    end
    return lines[index]
end

local function HideLines(fromIndex)
    for i = fromIndex, #lines do
        lines[i]:Hide()
    end
end

local function GetOrCreateLabel(pool, parent)
    for _, lbl in ipairs(pool) do
        if not lbl:IsShown() then
            lbl:Show()
            return lbl
        end
    end
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pool[#pool + 1] = lbl
    return lbl
end

local function HideLabels(pool)
    for _, lbl in ipairs(pool) do lbl:Hide() end
end

-- ============================================================================
-- Graph rendering (Story 6-4)
-- ============================================================================

local function RefreshGraph()
    if not canvas then return end

    local history = NXR.GetRatingHistory(filterCharKey, filterBracketIndex, filterSpecID)

    if not history or #history < MIN_POINTS then
        placeholder:Show()
        HideLines(1)
        HideLabels(xLabels)
        HideLabels(yLabels)
        if goalLine then goalLine:Hide() end
        if goalLabel then goalLabel:Hide() end
        return
    end

    placeholder:Hide()

    local W = canvas:GetWidth() or 1
    local H = canvas:GetHeight() or 1

    -- Data range
    local minR, maxR = math.huge, -math.huge
    for _, pt in ipairs(history) do
        if pt.rating < minR then minR = pt.rating end
        if pt.rating > maxR then maxR = pt.rating end
    end

    -- Story 6-5: Extend range to include goal if applicable
    local goalRating
    local challenge = NXR.GetActiveChallenge and NXR.GetActiveChallenge()
    if challenge then
        local bracketMatch = false
        for _, b in ipairs(challenge.brackets or {}) do
            if b == filterBracketIndex then bracketMatch = true; break end
        end
        if bracketMatch then
            goalRating = challenge.goalRating
            if goalRating and goalRating > maxR then
                maxR = goalRating
            end
        end
    end

    -- Guard against flat line
    local ratingRange = maxR - minR
    if ratingRange < 1 then
        minR = minR - 1
        maxR = maxR + 1
        ratingRange = 2
    end

    local function toCanvas(index, rating)
        local x = ((index - 1) / (#history - 1)) * W
        local y = ((rating - minR) / ratingRange) * H
        return x, y
    end

    -- Draw line segments
    local usedLines = 0
    for i = 2, #history do
        local x1, y1 = toCanvas(i - 1, history[i - 1].rating)
        local x2, y2 = toCanvas(i, history[i].rating)
        usedLines = usedLines + 1
        local line = GetOrCreateLine(canvas, usedLines)
        line:SetStartPoint("BOTTOMLEFT", x1, y1)
        line:SetEndPoint("BOTTOMLEFT", x2, y2)
        line:Show()
    end
    HideLines(usedLines + 1)

    -- Y-axis labels (5 ticks)
    HideLabels(yLabels)
    local yTicks = 4
    for i = 0, yTicks do
        local frac = i / yTicks
        local rating = minR + frac * ratingRange
        local yPx = frac * H

        local lbl = GetOrCreateLabel(yLabels, graphFrame)
        lbl:SetText("|cffaaaaaa" .. math.floor(rating + 0.5) .. "|r")
        lbl:ClearAllPoints()
        lbl:SetPoint("RIGHT", graphFrame, "BOTTOMLEFT",
            PADDING_LEFT - 4, PADDING_BOT + yPx)
    end

    -- X-axis labels (every ~50th point, up to 5 labels)
    HideLabels(xLabels)
    local total = #history
    local xTicks = math.min(5, total - 1)
    if xTicks > 0 then
        for i = 0, xTicks do
            local frac = i / xTicks
            local idx = math.floor(frac * (total - 1)) + 1
            local xPx = frac * W

            local lbl = GetOrCreateLabel(xLabels, graphFrame)
            lbl:SetText("|cffaaaaaa" .. idx .. "|r")
            lbl:ClearAllPoints()
            lbl:SetPoint("TOP", graphFrame, "BOTTOMLEFT",
                PADDING_LEFT + xPx, PADDING_BOT - 2)
        end
    end

    -- Story 6-5: Goal line
    if goalRating then
        if not goalLine then
            goalLine = graphFrame:CreateLine()
            goalLine:SetThickness(1)
            goalLine:SetColorTexture(unpack(GOAL_LINE_COLOR))
        end
        local _, goalY = toCanvas(1, goalRating)
        goalLine:SetStartPoint("BOTTOMLEFT", graphFrame, PADDING_LEFT, PADDING_BOT + goalY)
        goalLine:SetEndPoint("BOTTOMLEFT", graphFrame, PADDING_LEFT + W, PADDING_BOT + goalY)
        goalLine:Show()

        if not goalLabel then
            goalLabel = graphFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        end
        goalLabel:SetText("|cffFFD100" .. goalRating .. "|r")
        goalLabel:ClearAllPoints()
        goalLabel:SetPoint("LEFT", graphFrame, "BOTTOMLEFT",
            PADDING_LEFT + W + 4, PADDING_BOT + goalY)
        goalLabel:Show()
    else
        if goalLine then goalLine:Hide() end
        if goalLabel then goalLabel:Hide() end
    end
end

-- ============================================================================
-- Filter controls (Story 6-6)
-- ============================================================================

local function UpdateSpecButtonState()
    if NXR.PER_SPEC_BRACKETS[filterBracketIndex] then
        specButton:Enable()
        specButton:SetAlpha(1)
    else
        specButton:Disable()
        specButton:SetAlpha(0.4)
    end
end

local function SetFilterDefaults()
    filterCharKey = NXR.currentCharKey
    filterBracketIndex = NXR.BRACKET_SOLO_SHUFFLE

    local char = filterCharKey and NelxRatedDB.characters[filterCharKey]
    filterSpecID = char and char.specID

    if charButton then
        local c = char
        charButton.label:SetText(c and (c.name .. " - " .. c.realm) or "Select")
    end
    if specButton then
        local specInfo = filterSpecID and NXR.specData and NXR.specData[filterSpecID]
        specButton.label:SetText(specInfo and specInfo.specName or "Select")
    end
    if bracketButton then
        bracketButton.label:SetText(NXR.BRACKET_NAMES[filterBracketIndex] or "Select")
    end
end

local function CreateDropdownButton(parent, labelText, width, yOffset, xOffset)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", xOffset, yOffset)
    lbl:SetText(labelText)
    lbl:SetTextColor(0.7, 0.7, 0.7)

    local btn = NXR.CreateNXRButton(parent, "Select", width, 24)
    btn:SetPoint("TOPLEFT", xOffset, yOffset - 16)
    return btn
end

local function ShowCharacterMenu(btn)
    MenuUtil.CreateContextMenu(btn, function(_, rootDescription)
        for key, char in pairs(NelxRatedDB.characters) do
            local display = char.name .. " - " .. char.realm
            rootDescription:CreateButton(display, function()
                filterCharKey = key
                btn.label:SetText(display)
                -- Update spec filter for new character
                local c = NelxRatedDB.characters[key]
                if c and c.specID then
                    filterSpecID = c.specID
                    local specInfo = NXR.specData and NXR.specData[filterSpecID]
                    specButton.label:SetText(specInfo and specInfo.specName or "Unknown")
                end
                RefreshGraph()
            end)
        end
    end)
end

local function ShowSpecMenu(btn)
    if not filterCharKey then return end
    local char = NelxRatedDB.characters[filterCharKey]
    if not char then return end

    -- Collect specs from specBrackets keys + class spec list
    local specIDs = {}
    local seen = {}

    -- From specBrackets data
    if char.specBrackets then
        for sid, _ in pairs(char.specBrackets) do
            if not seen[sid] then
                seen[sid] = true
                specIDs[#specIDs + 1] = sid
            end
        end
    end

    -- From class spec list
    if char.classFileName and NXR.classData then
        for _, classEntry in pairs(NXR.classData) do
            if classEntry.classFileName == char.classFileName then
                for _, spec in ipairs(classEntry.specs) do
                    if not seen[spec.specID] then
                        seen[spec.specID] = true
                        specIDs[#specIDs + 1] = spec.specID
                    end
                end
            end
        end
    end

    MenuUtil.CreateContextMenu(btn, function(_, rootDescription)
        for _, sid in ipairs(specIDs) do
            local specInfo = NXR.specData and NXR.specData[sid]
            local name = specInfo and specInfo.specName or ("Spec " .. sid)
            rootDescription:CreateButton(name, function()
                filterSpecID = sid
                btn.label:SetText(name)
                RefreshGraph()
            end)
        end
    end)
end

local function ShowBracketMenu(btn)
    MenuUtil.CreateContextMenu(btn, function(_, rootDescription)
        for _, bracketIndex in ipairs(NXR.TRACKED_BRACKETS) do
            local name = NXR.BRACKET_NAMES[bracketIndex]
            rootDescription:CreateButton(name, function()
                filterBracketIndex = bracketIndex
                btn.label:SetText(name)
                UpdateSpecButtonState()
                RefreshGraph()
            end)
        end
    end)
end

-- ============================================================================
-- History tab creation (Story 6-3)
-- ============================================================================

function NXR.CreateHistoryPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    local y = -PADDING

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", PADDING, y)
    title:SetText("Rating History")
    title:SetTextColor(unpack(NXR.COLORS.GOLD))
    y = y - 28

    -- Filter row
    local filterWidth = 150
    local gap = 10

    charButton = CreateDropdownButton(panel, "Character", filterWidth, y, PADDING)
    charButton:SetScript("OnClick", function(self) ShowCharacterMenu(self) end)

    specButton = CreateDropdownButton(panel, "Spec", filterWidth, y, PADDING + filterWidth + gap)
    specButton:SetScript("OnClick", function(self) ShowSpecMenu(self) end)

    bracketButton = CreateDropdownButton(panel, "Bracket", filterWidth, y, PADDING + (filterWidth + gap) * 2)
    bracketButton:SetScript("OnClick", function(self) ShowBracketMenu(self) end)

    y = y - 44

    -- Graph area
    graphFrame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    graphFrame:SetPoint("TOPLEFT", PADDING, y)
    graphFrame:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    graphFrame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    graphFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.6)
    graphFrame:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.4)

    -- Canvas inside padding
    canvas = CreateFrame("Frame", nil, graphFrame)
    canvas:SetPoint("TOPLEFT", graphFrame, "TOPLEFT", PADDING_LEFT, -PADDING_TOP)
    canvas:SetPoint("BOTTOMRIGHT", graphFrame, "BOTTOMRIGHT", -PADDING_RIGHT, PADDING_BOT)

    -- Axis border lines
    local axisL = graphFrame:CreateTexture(nil, "ARTWORK")
    axisL:SetWidth(1)
    axisL:SetPoint("TOPLEFT", graphFrame, "TOPLEFT", PADDING_LEFT, -PADDING_TOP)
    axisL:SetPoint("BOTTOMLEFT", graphFrame, "BOTTOMLEFT", PADDING_LEFT, PADDING_BOT)
    axisL:SetColorTexture(0.5, 0.5, 0.5, 0.5)

    local axisB = graphFrame:CreateTexture(nil, "ARTWORK")
    axisB:SetHeight(1)
    axisB:SetPoint("BOTTOMLEFT", graphFrame, "BOTTOMLEFT", PADDING_LEFT, PADDING_BOT)
    axisB:SetPoint("BOTTOMRIGHT", graphFrame, "BOTTOMRIGHT", -PADDING_RIGHT, PADDING_BOT)
    axisB:SetColorTexture(0.5, 0.5, 0.5, 0.5)

    -- Placeholder text
    placeholder = graphFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    placeholder:SetPoint("CENTER")
    placeholder:SetText("|cff808080Play rated games to build history|r")

    -- Set defaults and draw on show
    panel:SetScript("OnShow", function()
        SetFilterDefaults()
        UpdateSpecButtonState()
        RefreshGraph()
    end)

    return panel
end

-- Allow external refresh (e.g. after new data arrives)
NXR.RefreshHistoryGraph = RefreshGraph
