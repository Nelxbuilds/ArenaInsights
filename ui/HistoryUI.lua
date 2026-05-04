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
local DOT_SIZE        = 6
local GOAL_LINE_COLOR = { 1.0, 0.82, 0.0, 0.8 }
local GRID_COLOR      = { 0.3, 0.3, 0.3, 0.4 }
local ENTRY_HEIGHT        = 22
local MAX_VISIBLE_ENTRIES = 12
local DROPDOWN_WIDTH      = 240
local BRACKET_PRIORITY    = { 7, 2, 1, 4 }  -- Solo Shuffle, 3v3, 2v2, Blitz

-- State
local graphFrame, canvas, placeholder
local lines = {}
local dots = {}
local xLabels = {}
local gridLines = {}
local gridLabels = {}
local goalLine, goalLabel, goalLabelBg
local goalLineFrame, goalLabelFrame
local filterCharKey, filterSpecID, filterBracketIndex
local charButton, specButton, bracketButton
local charDropdown, charDropdownEntries, charDropdownData, charDropdownOffset
local specDropdown, specDropdownEntries
local bracketDropdown, bracketDropdownEntries
local ddClickCatcher
local RefreshCharDropdownEntries  -- forward declaration (used by OnDropdownScroll)
local UpdateSpecButtonState       -- forward declaration (used by dropdown OnClick)

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

local function GetOrCreateGridLine(parent, index)
    if not gridLines[index] then
        local line = parent:CreateLine(nil, "BACKGROUND")
        line:SetThickness(1)
        line:SetColorTexture(unpack(GRID_COLOR))
        gridLines[index] = line
    end
    return gridLines[index]
end

local function HideGridLines(fromIndex)
    for i = fromIndex, #gridLines do
        gridLines[i]:Hide()
    end
end

local function GetOrCreateDot(parent, index)
    if not dots[index] then
        local dot = CreateFrame("Frame", nil, parent)
        dot:SetSize(DOT_SIZE, DOT_SIZE)
        dot:SetFrameStrata("DIALOG")

        local tex = dot:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        tex:SetColorTexture(1, 1, 1)
        dot.tex = tex

        dot:SetScript("OnEnter", function(self)
            if self.tipRating then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(self.tipRating, 1, 1, 1)
                if self.tipDate then
                    GameTooltip:AddLine(self.tipDate, 0.7, 0.7, 0.7)
                end
                GameTooltip:Show()
            end
        end)
        dot:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        dots[index] = dot
    end
    return dots[index]
end

local function HideDots(fromIndex)
    for i = fromIndex, #dots do
        dots[i]:Hide()
    end
end

-- ============================================================================
-- Graph rendering (Story 6-4)
-- ============================================================================

local function ResolveLineColor()
    local setting = NelxRatedDB.settings.chartColor or "default"
    if setting == "class" and filterCharKey then
        local char = NelxRatedDB.characters[filterCharKey]
        if char and char.classFileName and RAID_CLASS_COLORS then
            local cc = RAID_CLASS_COLORS[char.classFileName]
            if cc then return cc.r, cc.g, cc.b end
        end
    end
    return unpack(NXR.COLORS.CRIMSON_BRIGHT)
end

local function RefreshGraph()
    if not canvas then return end

    local history = NXR.GetRatingHistory(filterCharKey, filterBracketIndex, filterSpecID)

    if not history or #history < MIN_POINTS then
        placeholder:Show()
        HideLines(1)
        HideDots(1)
        HideLabels(xLabels)
        HideGridLines(1)
        HideLabels(gridLabels)
        if goalLine then goalLine:Hide() end
        if goalLabel then goalLabel:Hide() end
        if goalLabelBg then goalLabelBg:Hide() end
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
        for b, _ in pairs(challenge.brackets or {}) do
            if b == filterBracketIndex then bracketMatch = true; break end
        end
        if bracketMatch then
            goalRating = challenge.goalRating
            if goalRating and goalRating > maxR then
                maxR = goalRating
            end
            if goalRating and goalRating < minR then
                minR = goalRating
            end
        end
    end

    -- Choose grid interval based on raw data range
    local rawRange = maxR - minR
    if rawRange < 1 then rawRange = 2 end
    local interval
    if rawRange <= 300 then interval = 50
    elseif rawRange <= 600 then interval = 100
    else interval = 200
    end

    -- Snap minR/maxR to interval boundaries for clean labels
    minR = math.floor(minR / interval) * interval
    maxR = math.ceil(maxR / interval) * interval
    -- Ensure at least one interval of padding on each side
    local dataMin, dataMax = math.huge, -math.huge
    for _, pt in ipairs(history) do
        if pt.rating < dataMin then dataMin = pt.rating end
        if pt.rating > dataMax then dataMax = pt.rating end
    end
    if minR >= dataMin then minR = minR - interval end
    if maxR <= dataMax then maxR = maxR + interval end

    local ratingRange = maxR - minR

    local function toCanvas(index, rating)
        local x = ((index - 1) / (#history - 1)) * W
        local y = ((rating - minR) / ratingRange) * H
        return x, y
    end

    -- Grid lines at rating milestones (with labels)
    HideGridLines(1)
    HideLabels(gridLabels)

    local usedGrid = 0
    local firstMilestone = math.ceil(minR / interval) * interval
    for ms = firstMilestone, maxR, interval do
        usedGrid = usedGrid + 1
        local gl = GetOrCreateGridLine(canvas, usedGrid)
        local _, msY = toCanvas(1, ms)
        gl:SetStartPoint("BOTTOMLEFT", 0, msY)
        gl:SetEndPoint("BOTTOMLEFT", W, msY)
        gl:Show()

        local lbl = GetOrCreateLabel(gridLabels, graphFrame)
        lbl:SetText("|cffaaaaaa" .. ms .. "|r")
        lbl:ClearAllPoints()
        lbl:SetPoint("RIGHT", graphFrame, "BOTTOMLEFT",
            PADDING_LEFT - 4, PADDING_BOT + msY)
    end
    HideGridLines(usedGrid + 1)

    -- Draw line segments (Story 6-8: resolve color)
    local lr, lg, lb = ResolveLineColor()
    local usedLines = 0
    for i = 2, #history do
        local x1, y1 = toCanvas(i - 1, history[i - 1].rating)
        local x2, y2 = toCanvas(i, history[i].rating)
        usedLines = usedLines + 1
        local line = GetOrCreateLine(canvas, usedLines)
        line:SetColorTexture(lr, lg, lb)
        line:SetStartPoint("BOTTOMLEFT", x1, y1)
        line:SetEndPoint("BOTTOMLEFT", x2, y2)
        line:Show()
    end
    HideLines(usedLines + 1)

    -- Data point dots with tooltips
    for i = 1, #history do
        local pt = history[i]
        local px, py = toCanvas(i, pt.rating)
        local dot = GetOrCreateDot(canvas, i)
        dot.tex:SetColorTexture(lr, lg, lb)
        dot:ClearAllPoints()
        dot:SetPoint("CENTER", canvas, "BOTTOMLEFT", px, py)
        dot.tipRating = "Rating: " .. pt.rating
        dot.tipDate = pt.timestamp and date("%Y-%m-%d %H:%M", pt.timestamp) or nil
        dot:Show()
    end
    HideDots(#history + 1)

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
            goalLine = goalLineFrame:CreateLine()
            goalLine:SetThickness(1)
            goalLine:SetColorTexture(unpack(GOAL_LINE_COLOR))
        end
        local _, goalY = toCanvas(1, goalRating)
        goalLine:SetStartPoint("BOTTOMLEFT", graphFrame, PADDING_LEFT, PADDING_BOT + goalY)
        goalLine:SetEndPoint("BOTTOMLEFT", graphFrame, PADDING_LEFT + W, PADDING_BOT + goalY)
        goalLine:Show()

        if not goalLabel then
            goalLabel = goalLabelFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        end
        if not goalLabelBg then
            goalLabelBg = goalLabelFrame:CreateTexture(nil, "BACKGROUND")
            goalLabelBg:SetColorTexture(0, 0, 0, 0.85)
        end
        goalLabel:SetText("|cffFFD100" .. goalRating .. "|r")
        goalLabel:ClearAllPoints()
        goalLabel:SetPoint("RIGHT", graphFrame, "BOTTOMRIGHT",
            -PADDING_RIGHT + 2, PADDING_BOT + goalY)
        goalLabel:Show()
        goalLabelBg:ClearAllPoints()
        goalLabelBg:SetPoint("TOPLEFT", goalLabel, "TOPLEFT", -2, 2)
        goalLabelBg:SetPoint("BOTTOMRIGHT", goalLabel, "BOTTOMRIGHT", 2, -2)
        goalLabelBg:Show()
    else
        if goalLine then goalLine:Hide() end
        if goalLabel then goalLabel:Hide() end
        if goalLabelBg then goalLabelBg:Hide() end
    end
end

-- ============================================================================
-- Character dropdown helpers (Epic 7)
-- ============================================================================

local function HasAnyHistory(char)
    if not char.ratingHistory then return false end
    for _, arr in pairs(char.ratingHistory) do
        if #arr > 0 then return true end
    end
    return false
end

local function BuildSortedCharList()
    local classSortIndex = {}
    for i, classID in ipairs(NXR.sortedClassIDs) do
        local cd = NXR.classData[classID]
        if cd then classSortIndex[cd.classFileName] = i end
    end

    local list = {}
    for key, char in pairs(NelxRatedDB.characters) do
        if HasAnyHistory(char) then
            list[#list + 1] = { key = key, char = char }
        end
    end

    table.sort(list, function(a, b)
        local ai = classSortIndex[a.char.classFileName] or 999
        local bi = classSortIndex[b.char.classFileName] or 999
        if ai ~= bi then return ai < bi end
        return (a.char.name or "") < (b.char.name or "")
    end)

    return list
end

local function FormatRaceIcon(char)
    if char.raceFileName and char.gender then
        local genderStr = char.gender == 2 and "male" or char.gender == 3 and "female" or nil
        if genderStr then
            return "|A:raceicon-" .. strlower(char.raceFileName) .. "-" .. genderStr .. ":14:14|a"
        end
    end
    return nil
end

local function FormatCharName(char)
    local name = char.name .. " - " .. char.realm
    local cc = char.classFileName and RAID_CLASS_COLORS and RAID_CLASS_COLORS[char.classFileName]
    if cc and cc.colorStr then
        name = "|c" .. cc.colorStr .. name .. "|r"
    end
    return name
end

local function FormatCharDisplay(char)
    local parts = {}
    local raceIcon = FormatRaceIcon(char)
    if raceIcon then parts[#parts + 1] = raceIcon end
    parts[#parts + 1] = FormatCharName(char)
    return table.concat(parts, " ")
end

local function FormatCharButtonLabel(char)
    if not char then return "Select" end
    local parts = {}
    local raceIcon = FormatRaceIcon(char)
    if raceIcon then parts[#parts + 1] = raceIcon end
    parts[#parts + 1] = FormatCharName(char)
    return table.concat(parts, " ")
end

local function AutoSelectBracketForChar(charKey)
    local char = NelxRatedDB.characters[charKey]
    if not char or not char.ratingHistory then return end

    for _, bi in ipairs(BRACKET_PRIORITY) do
        if NXR.PER_SPEC_BRACKETS[bi] then
            local bestSpec, bestCount = nil, 0
            for histKey, arr in pairs(char.ratingHistory) do
                if type(histKey) == "string" then
                    local specStr, bracketStr = strsplit(":", histKey)
                    if tonumber(bracketStr) == bi and #arr > bestCount then
                        bestSpec = tonumber(specStr)
                        bestCount = #arr
                    end
                end
            end
            if bestSpec then
                filterBracketIndex = bi
                filterSpecID = bestSpec
                if specButton then
                    local specInfo = NXR.specData and NXR.specData[filterSpecID]
                    specButton.label:SetText(specInfo and specInfo.specName or "Unknown")
                end
                if bracketButton then
                    bracketButton.label:SetText(NXR.BRACKET_NAMES[bi] or "Select")
                end
                return
            end
        else
            local arr = char.ratingHistory[bi]
            if arr and #arr > 0 then
                filterBracketIndex = bi
                filterSpecID = char.specID
                if specButton then
                    local specInfo = filterSpecID and NXR.specData and NXR.specData[filterSpecID]
                    specButton.label:SetText(specInfo and specInfo.specName or "Select")
                end
                if bracketButton then
                    bracketButton.label:SetText(NXR.BRACKET_NAMES[bi] or "Select")
                end
                return
            end
        end
    end
end

local function HideAllDropdowns()
    if charDropdown then charDropdown:Hide() end
    if specDropdown then specDropdown:Hide() end
    if bracketDropdown then bracketDropdown:Hide() end
    if ddClickCatcher then ddClickCatcher:Hide() end
end

local function OnDropdownScroll(_, delta)
    if not charDropdownData then return end
    local maxOffset = math.max(0, #charDropdownData - MAX_VISIBLE_ENTRIES)
    charDropdownOffset = math.max(0, math.min(charDropdownOffset - delta, maxOffset))
    RefreshCharDropdownEntries()
end

local function GetOrCreateDropdownEntry(parent, index)
    if not charDropdownEntries then charDropdownEntries = {} end
    if charDropdownEntries[index] then return charDropdownEntries[index] end

    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(ENTRY_HEIGHT)
    btn:SetPoint("TOPLEFT", 2, -(index - 1) * ENTRY_HEIGHT - 2)
    btn:SetPoint("RIGHT", parent, "RIGHT", -2, 0)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(NXR.COLORS.CRIMSON_DIM[1], NXR.COLORS.CRIMSON_DIM[2], NXR.COLORS.CRIMSON_DIM[3], 0.3)

    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.label:SetPoint("LEFT", 6, 0)
    btn.label:SetPoint("RIGHT", -6, 0)
    btn.label:SetJustifyH("LEFT")
    btn.label:SetWordWrap(false)

    btn:EnableMouseWheel(true)
    btn:SetScript("OnMouseWheel", OnDropdownScroll)

    charDropdownEntries[index] = btn
    return btn
end

RefreshCharDropdownEntries = function()
    if not charDropdownData or not charDropdown then return end
    local visibleCount = math.min(#charDropdownData, MAX_VISIBLE_ENTRIES)

    if charDropdownEntries then
        for _, e in pairs(charDropdownEntries) do e:Hide() end
    end

    for i = 1, visibleCount do
        local dataIdx = charDropdownOffset + i
        if dataIdx > #charDropdownData then break end
        local data = charDropdownData[dataIdx]
        local entry = GetOrCreateDropdownEntry(charDropdown, i)
        entry.label:SetText(data.display)
        entry:SetScript("OnClick", function()
            filterCharKey = data.key
            charButton.label:SetText(FormatCharButtonLabel(data.char))
            AutoSelectBracketForChar(data.key)
            UpdateSpecButtonState()
            RefreshGraph()
            HideAllDropdowns()
        end)
        entry:Show()
    end
end

-- ============================================================================
-- Filter controls (Story 6-6)
-- ============================================================================

UpdateSpecButtonState = function()
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
    local char = filterCharKey and NelxRatedDB.characters[filterCharKey]
    filterSpecID = char and char.specID
    filterBracketIndex = NXR.BRACKET_SOLO_SHUFFLE

    if charButton then
        charButton.label:SetText(FormatCharButtonLabel(char))
    end

    -- Auto-select best bracket (also updates spec/bracket button labels)
    if char and char.ratingHistory then
        AutoSelectBracketForChar(filterCharKey)
    else
        if specButton then
            local specInfo = filterSpecID and NXR.specData and NXR.specData[filterSpecID]
            specButton.label:SetText(specInfo and specInfo.specName or "Select")
        end
        if bracketButton then
            bracketButton.label:SetText(NXR.BRACKET_NAMES[filterBracketIndex] or "Select")
        end
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

-- Reusable dropdown helper for simple (non-scrollable) dropdowns
local function CreateOrGetSimpleDropdown(dropdown, parent)
    if not dropdown then
        dropdown = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        dropdown:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        dropdown:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
        dropdown:SetBackdropBorderColor(unpack(NXR.COLORS.CRIMSON_DIM))
        dropdown:SetFrameStrata("TOOLTIP")
    end
    return dropdown
end

local function GetOrCreateSimpleEntry(pool, parent, index)
    if pool[index] then return pool[index] end

    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(ENTRY_HEIGHT)
    btn:SetPoint("TOPLEFT", 2, -(index - 1) * ENTRY_HEIGHT - 2)
    btn:SetPoint("RIGHT", parent, "RIGHT", -2, 0)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(NXR.COLORS.CRIMSON_DIM[1], NXR.COLORS.CRIMSON_DIM[2], NXR.COLORS.CRIMSON_DIM[3], 0.3)

    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.label:SetPoint("LEFT", 6, 0)
    btn.label:SetPoint("RIGHT", -6, 0)
    btn.label:SetJustifyH("LEFT")
    btn.label:SetWordWrap(false)

    pool[index] = btn
    return btn
end

local function ShowSimpleDropdown(dropdown, entries, btn, items, onClick)
    HideAllDropdowns()

    local count = #items
    dropdown:SetSize(btn:GetWidth(), count * ENTRY_HEIGHT + 4)
    dropdown:ClearAllPoints()
    dropdown:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)

    -- Hide existing entries
    if entries then
        for _, e in pairs(entries) do e:Hide() end
    end

    for i, item in ipairs(items) do
        local entry = GetOrCreateSimpleEntry(entries, dropdown, i)
        entry.label:SetText(item.display)
        entry:SetScript("OnClick", function()
            onClick(item)
            HideAllDropdowns()
        end)
        entry:Show()
    end

    if not ddClickCatcher then
        ddClickCatcher = CreateFrame("Button", nil, UIParent)
        ddClickCatcher:SetAllPoints()
        ddClickCatcher:SetScript("OnClick", HideAllDropdowns)
    end
    ddClickCatcher:SetFrameStrata(dropdown:GetFrameStrata())
    ddClickCatcher:SetFrameLevel(dropdown:GetFrameLevel() - 1)
    ddClickCatcher:Show()
    dropdown:Show()
end

local function ShowCharacterMenu(btn)
    if charDropdown and charDropdown:IsShown() then
        HideAllDropdowns()
        return
    end
    HideAllDropdowns()

    local chars = BuildSortedCharList()
    if #chars == 0 then return end

    charDropdownData = {}
    for _, item in ipairs(chars) do
        charDropdownData[#charDropdownData + 1] = {
            key = item.key,
            char = item.char,
            display = FormatCharDisplay(item.char),
        }
    end
    charDropdownOffset = 0

    if not charDropdown then
        charDropdown = CreateFrame("Frame", nil, btn:GetParent(), "BackdropTemplate")
        charDropdown:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        charDropdown:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
        charDropdown:SetBackdropBorderColor(unpack(NXR.COLORS.CRIMSON_DIM))
        charDropdown:SetFrameStrata("TOOLTIP")
        charDropdown:SetClipsChildren(true)
    end

    local visibleCount = math.min(#charDropdownData, MAX_VISIBLE_ENTRIES)
    charDropdown:SetSize(DROPDOWN_WIDTH, visibleCount * ENTRY_HEIGHT + 4)
    charDropdown:ClearAllPoints()
    charDropdown:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    charDropdown:SetScript("OnMouseWheel", OnDropdownScroll)

    RefreshCharDropdownEntries()

    if not ddClickCatcher then
        ddClickCatcher = CreateFrame("Button", nil, UIParent)
        ddClickCatcher:SetAllPoints()
        ddClickCatcher:SetScript("OnClick", HideAllDropdowns)
    end
    ddClickCatcher:SetFrameStrata(charDropdown:GetFrameStrata())
    ddClickCatcher:SetFrameLevel(charDropdown:GetFrameLevel() - 1)
    ddClickCatcher:Show()
    charDropdown:Show()
end

local function ShowSpecMenu(btn)
    if specDropdown and specDropdown:IsShown() then
        HideAllDropdowns()
        return
    end

    if not filterCharKey then return end
    local char = NelxRatedDB.characters[filterCharKey]
    if not char then return end

    local specIDs = {}
    local seen = {}

    if char.specBrackets then
        for sid, _ in pairs(char.specBrackets) do
            if not seen[sid] then
                seen[sid] = true
                specIDs[#specIDs + 1] = sid
            end
        end
    end

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

    local items = {}
    for _, sid in ipairs(specIDs) do
        local specInfo = NXR.specData and NXR.specData[sid]
        items[#items + 1] = {
            display = specInfo and specInfo.specName or ("Spec " .. sid),
            specID = sid,
        }
    end

    if not specDropdownEntries then specDropdownEntries = {} end
    specDropdown = CreateOrGetSimpleDropdown(specDropdown, btn:GetParent())
    ShowSimpleDropdown(specDropdown, specDropdownEntries, btn, items, function(item)
        filterSpecID = item.specID
        btn.label:SetText(item.display)
        RefreshGraph()
    end)
end

local function ShowBracketMenu(btn)
    if bracketDropdown and bracketDropdown:IsShown() then
        HideAllDropdowns()
        return
    end

    local items = {}
    for _, bracketIndex in ipairs(NXR.TRACKED_BRACKETS) do
        items[#items + 1] = {
            display = NXR.BRACKET_NAMES[bracketIndex],
            bracketIndex = bracketIndex,
        }
    end

    if not bracketDropdownEntries then bracketDropdownEntries = {} end
    bracketDropdown = CreateOrGetSimpleDropdown(bracketDropdown, btn:GetParent())
    ShowSimpleDropdown(bracketDropdown, bracketDropdownEntries, btn, items, function(item)
        filterBracketIndex = item.bracketIndex
        btn.label:SetText(item.display)
        UpdateSpecButtonState()
        RefreshGraph()
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
    charButton.label:ClearAllPoints()
    charButton.label:SetPoint("LEFT", 4, 0)
    charButton.label:SetPoint("RIGHT", -4, 0)
    charButton.label:SetJustifyH("LEFT")
    charButton.label:SetWordWrap(false)
    charButton:SetScript("OnClick", function(self) ShowCharacterMenu(self) end)

    specButton = CreateDropdownButton(panel, "Spec", filterWidth, y, PADDING + filterWidth + gap)
    specButton:SetScript("OnClick", function(self) ShowSpecMenu(self) end)

    bracketButton = CreateDropdownButton(panel, "Bracket", filterWidth, y, PADDING + (filterWidth + gap) * 2)
    bracketButton:SetScript("OnClick", function(self) ShowBracketMenu(self) end)

    y = y - 44

    -- Graph area
    graphFrame = CreateFrame("Frame", nil, panel)
    graphFrame:SetPoint("TOPLEFT", PADDING, y)
    graphFrame:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)

    -- Canvas inside padding
    canvas = CreateFrame("Frame", nil, graphFrame)
    canvas:SetPoint("TOPLEFT", graphFrame, "TOPLEFT", PADDING_LEFT, -PADDING_TOP)
    canvas:SetPoint("BOTTOMRIGHT", graphFrame, "BOTTOMRIGHT", -PADDING_RIGHT, PADDING_BOT)

    -- Goal line/label overlay frames — must sit above canvas (child frames always render above parent)
    goalLineFrame = CreateFrame("Frame", nil, graphFrame)
    goalLineFrame:SetAllPoints(graphFrame)
    goalLineFrame:SetFrameLevel(canvas:GetFrameLevel() + 10)

    goalLabelFrame = CreateFrame("Frame", nil, graphFrame)
    goalLabelFrame:SetAllPoints(graphFrame)
    goalLabelFrame:SetFrameLevel(canvas:GetFrameLevel() + 20)

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

    panel:SetScript("OnHide", function()
        HideAllDropdowns()
    end)

    return panel
end

-- Allow external refresh (e.g. after new data arrives)
NXR.RefreshHistoryGraph = RefreshGraph
