local addonName, NXR = ...

-- ============================================================================
-- Layout constants
-- ============================================================================

local ROW_H    = 24
local PAD      = 8
local FILTER_H = 28
local HEADER_H = 20
local GAP      = 4

-- Column left-edge x offsets within each row (from row left edge)
local COL_DATE    = 0
local COL_BRACKET = 115
local COL_RESULT  = 225
local COL_DELTA   = 295
local COL_RATING  = 365

-- ============================================================================
-- Filter definitions — add entries here to extend without changing other code
-- ============================================================================

local FILTERS = {
    {
        id      = "bracket",
        label   = "Bracket",
        options = { "All", "Solo Shuffle", "2v2", "3v3", "Blitz BG" },
        default = "All",
        match   = function(rec, val)
            if val == "All" then return true end
            return NXR.BRACKET_NAMES[rec.bracketIndex] == val
        end,
    },
    {
        id      = "outcome",
        label   = "Outcome",
        options = { "All", "Win", "Loss", "Draw" },
        default = "All",
        match   = function(rec, val)
            if val == "All" then return true end
            return rec.outcome == val:lower()
        end,
    },
}

local filterValues = {}
for _, f in ipairs(FILTERS) do
    filterValues[f.id] = f.default
end

-- ============================================================================
-- Module state
-- ============================================================================

local insightsPanel  = nil
local scrollFrame    = nil
local scrollChild    = nil
local rowPool        = {}
local countLabel     = nil
local emptyLabel     = nil
local filteredList   = {}

-- ============================================================================
-- Spec name helper
-- ============================================================================

local function GetSpecName(specID)
    if not specID or specID == 0 then return "Unknown" end
    if NXR.specData and NXR.specData[specID] then
        return NXR.specData[specID].specName or "Unknown"
    end
    if GetSpecializationInfoByID then
        local _, name = GetSpecializationInfoByID(specID)
        return name or "Unknown"
    end
    return "Unknown"
end

-- ============================================================================
-- Tooltip builder
-- ============================================================================

local function ShowMatchTooltip(anchor, rec)
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")

    local dateStr    = date("%b %d, %H:%M", rec.timestamp or 0)
    local bName      = NXR.BRACKET_NAMES[rec.bracketIndex] or ("Bracket " .. tostring(rec.bracketIndex))
    local isSS       = rec.bracketIndex == NXR.BRACKET_SOLO_SHUFFLE

    GameTooltip:AddLine(bName .. "  —  " .. dateStr, 1, 1, 1)
    GameTooltip:AddLine(" ")

    -- SS round summary
    if isSS then
        local sh  = rec.shuffle
        local won = (sh and sh.wonRounds) or rec.wonRounds or 0
        GameTooltip:AddLine("Won " .. won .. " / 6 rounds", 1, 0.85, 0.1)
        GameTooltip:AddLine(" ")
    end

    -- Rating and MMR
    local delta    = rec.ratingChange or 0
    local preRat   = (rec.rating or 0) - delta
    local preMMR   = rec.prematchMMR or 0
    local postMMR  = preMMR + (rec.mmrChange or 0)
    local deltaM   = rec.mmrChange or 0

    local function sign(n)
        if n > 0 then return "+" .. n elseif n < 0 then return tostring(n) else return "±0" end
    end

    GameTooltip:AddDoubleLine("Rating",
        preRat .. "  →  " .. (rec.rating or 0) .. "  (" .. sign(delta) .. ")",
        0.65, 0.65, 0.65, 1, 1, 1)
    if preMMR > 0 then
        GameTooltip:AddDoubleLine("MMR",
            preMMR .. "  →  " .. postMMR .. "  (" .. sign(deltaM) .. ")",
            0.65, 0.65, 0.65, 1, 1, 1)
    end

    -- Spec lists
    if isSS then
        -- All 6: self + 5 enemies
        local hasAny = rec.specID or (rec.enemySpecs and #rec.enemySpecs > 0)
        if hasAny then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("All specs:", 0.65, 0.65, 0.65)
            if rec.specID then
                GameTooltip:AddLine("  \226\152\133  " .. GetSpecName(rec.specID), 1, 0.82, 0.0)
            end
            for _, sid in ipairs(rec.enemySpecs or {}) do
                GameTooltip:AddLine("  " .. GetSpecName(sid), 0.85, 0.85, 0.85)
            end
        end
    else
        -- Arena: your team then enemies
        local hasOwn   = rec.specID ~= nil
        local hasAlly  = rec.allySpecs and #rec.allySpecs > 0
        local hasEnemy = rec.enemySpecs and #rec.enemySpecs > 0

        if hasOwn or hasAlly then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Your team:", 0.65, 0.65, 0.65)
            if hasOwn then
                GameTooltip:AddLine("  \226\152\133  " .. GetSpecName(rec.specID), 1, 0.82, 0.0)
            end
            if hasAlly then
                for _, sid in ipairs(rec.allySpecs) do
                    GameTooltip:AddLine("  " .. GetSpecName(sid), 0.85, 0.85, 0.85)
                end
            end
        end

        if hasEnemy then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Enemies:", 0.65, 0.65, 0.65)
            for _, sid in ipairs(rec.enemySpecs) do
                GameTooltip:AddLine("  " .. GetSpecName(sid), 0.85, 0.85, 0.85)
            end
        end
    end

    -- SS per-round breakdown (only when all 6 captured)
    if isSS then
        local sh = rec.shuffle
        if sh and sh.rounds and #sh.rounds == 6 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Round outcomes:", 0.65, 0.65, 0.65)
            for _, r in ipairs(sh.rounds) do
                local isWin = r.outcome == "win"
                local label = "  R" .. r.num .. "  " .. (r.outcome or "?"):upper()
                if r.duration then label = label .. "  (" .. r.duration .. "s)" end
                if isWin then
                    GameTooltip:AddLine(label, 0.1, 0.9, 0.1)
                else
                    GameTooltip:AddLine(label, 0.9, 0.1, 0.1)
                end
            end
        end
    end

    GameTooltip:Show()
end

-- ============================================================================
-- Row pool
-- ============================================================================

local function CreateRow(parent)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_H)
    row:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 0,
    })
    row:SetBackdropColor(0, 0, 0, 0)
    row:EnableMouse(true)

    -- Separator at row bottom
    local sep = row:CreateTexture(nil, "BORDER")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(0.14, 0.14, 0.14, 0.7)

    row.dateText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.dateText:SetPoint("LEFT", COL_DATE + PAD, 0)
    row.dateText:SetWidth(COL_BRACKET - COL_DATE - 4)
    row.dateText:SetJustifyH("LEFT")

    row.bracketText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.bracketText:SetPoint("LEFT", COL_BRACKET + PAD, 0)
    row.bracketText:SetWidth(COL_RESULT - COL_BRACKET - 4)
    row.bracketText:SetJustifyH("LEFT")

    row.resultText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.resultText:SetPoint("LEFT", COL_RESULT + PAD, 0)
    row.resultText:SetWidth(COL_DELTA - COL_RESULT - 4)
    row.resultText:SetJustifyH("LEFT")

    row.deltaText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.deltaText:SetPoint("LEFT", COL_DELTA + PAD, 0)
    row.deltaText:SetWidth(COL_RATING - COL_DELTA - 4)
    row.deltaText:SetJustifyH("LEFT")

    row.ratingText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.ratingText:SetPoint("LEFT", COL_RATING + PAD, 0)
    row.ratingText:SetWidth(80)
    row.ratingText:SetJustifyH("LEFT")

    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.14, 0.06, 0.06, 0.7)
        if self.matchData then ShowMatchTooltip(self, self.matchData) end
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0)
        GameTooltip:Hide()
    end)

    return row
end

local function GetOrCreateRow(i)
    if not rowPool[i] then
        rowPool[i] = CreateRow(scrollChild)
    end
    return rowPool[i]
end

-- ============================================================================
-- Filter logic
-- ============================================================================

local function BuildFilteredList()
    filteredList = {}
    local all = NXR.GetMatches()
    for i = #all, 1, -1 do   -- newest first
        local rec = all[i]
        local pass = true
        for _, f in ipairs(FILTERS) do
            if not f.match(rec, filterValues[f.id]) then
                pass = false
                break
            end
        end
        if pass then
            filteredList[#filteredList + 1] = rec
        end
    end
end

-- ============================================================================
-- Refresh
-- ============================================================================

local function RefreshRows()
    BuildFilteredList()
    local count = #filteredList

    if countLabel then
        countLabel:SetText(count .. (count == 1 and " match" or " matches"))
    end
    if emptyLabel then
        emptyLabel:SetShown(count == 0)
    end

    local yOff = 0
    for i = 1, count do
        local rec = filteredList[i]
        local row = GetOrCreateRow(i)
        row:SetPoint("TOPLEFT", 0, -yOff)
        row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        row.matchData = rec

        row.dateText:SetText(date("%b %d  %H:%M", rec.timestamp or 0))
        row.dateText:SetTextColor(0.65, 0.65, 0.65)

        local bName = NXR.BRACKET_NAMES[rec.bracketIndex] or ("?" .. tostring(rec.bracketIndex))
        row.bracketText:SetText(bName)
        row.bracketText:SetTextColor(0.85, 0.85, 0.85)

        local out = rec.outcome or "unknown"
        if out == "win" then
            row.resultText:SetText("WIN")
            row.resultText:SetTextColor(0.1, 0.88, 0.1)
        elseif out == "loss" then
            row.resultText:SetText("LOSS")
            row.resultText:SetTextColor(0.88, 0.1, 0.1)
        elseif out == "draw" then
            row.resultText:SetText("DRAW")
            row.resultText:SetTextColor(0.95, 0.80, 0.20)
        else
            row.resultText:SetText("\226\128\148")
            row.resultText:SetTextColor(0.45, 0.45, 0.45)
        end

        local d = rec.ratingChange
        if d == nil then
            row.deltaText:SetText("\226\128\148")
            row.deltaText:SetTextColor(0.45, 0.45, 0.45)
        elseif d > 0 then
            row.deltaText:SetText("+" .. d)
            row.deltaText:SetTextColor(0.1, 0.88, 0.1)
        elseif d < 0 then
            row.deltaText:SetText(tostring(d))
            row.deltaText:SetTextColor(0.88, 0.1, 0.1)
        else
            row.deltaText:SetText("\194\1770")
            row.deltaText:SetTextColor(0.45, 0.45, 0.45)
        end

        row.ratingText:SetText(rec.rating and tostring(rec.rating) or "\226\128\148")
        row.ratingText:SetTextColor(1, 1, 1)

        row:Show()
        yOff = yOff + ROW_H
    end

    for i = count + 1, #rowPool do
        rowPool[i]:Hide()
    end

    scrollChild:SetHeight(math.max(yOff, 1))
end

-- ============================================================================
-- Filter button
-- ============================================================================

local function CreateFilterButton(parent, filterDef, xPos)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(128, 22)
    btn:SetPoint("LEFT", xPos, 0)
    btn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.10, 0.10, 0.10, 0.9)
    btn:SetBackdropBorderColor(0.28, 0.28, 0.28, 0.8)

    btn.lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.lbl:SetPoint("LEFT", 7, 0)
    btn.lbl:SetPoint("RIGHT", -16, 0)
    btn.lbl:SetJustifyH("LEFT")
    btn.lbl:SetTextColor(0.85, 0.85, 0.85)

    local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", -5, 0)
    arrow:SetText("\226\150\190")
    arrow:SetTextColor(0.5, 0.5, 0.5)

    local function UpdateLabel()
        btn.lbl:SetText(filterDef.label .. ": " .. filterValues[filterDef.id])
    end
    UpdateLabel()

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(NXR.COLORS.CRIMSON_MID))
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.28, 0.28, 0.28, 0.8)
    end)
    btn:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            for _, opt in ipairs(filterDef.options) do
                rootDescription:CreateButton(opt, function()
                    filterValues[filterDef.id] = opt
                    UpdateLabel()
                    RefreshRows()
                end)
            end
        end)
    end)

    return btn
end

-- ============================================================================
-- Panel creation
-- ============================================================================

function NXR.CreateInsightsPanel(parent)
    insightsPanel = parent

    -- Filter bar
    local filterBar = CreateFrame("Frame", nil, parent)
    filterBar:SetHeight(FILTER_H)
    filterBar:SetPoint("TOPLEFT", PAD, -PAD)
    filterBar:SetPoint("TOPRIGHT", -PAD, -PAD)

    local xPos = 0
    for _, f in ipairs(FILTERS) do
        CreateFilterButton(filterBar, f, xPos)
        xPos = xPos + 136
    end

    countLabel = filterBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLabel:SetPoint("RIGHT", filterBar, "RIGHT", 0, 0)
    countLabel:SetTextColor(0.45, 0.45, 0.45)

    -- Separator under filter bar
    local sep = parent:CreateTexture(nil, "BORDER")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", PAD, -(PAD + FILTER_H + GAP))
    sep:SetPoint("TOPRIGHT", -PAD, -(PAD + FILTER_H + GAP))
    sep:SetColorTexture(unpack(NXR.COLORS.CRIMSON_DIM))

    -- Column headers
    local headerRow = CreateFrame("Frame", nil, parent)
    headerRow:SetHeight(HEADER_H)
    headerRow:SetPoint("TOPLEFT", PAD, -(PAD + FILTER_H + GAP + 2))
    headerRow:SetPoint("TOPRIGHT", -PAD, -(PAD + FILTER_H + GAP + 2))

    local function MkHeader(text, xOff)
        local fs = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
        fs:SetPoint("LEFT", xOff + PAD, 0)
        fs:SetText(text:upper())
        fs:SetTextColor(0.40, 0.40, 0.40)
    end
    MkHeader("Date",     COL_DATE)
    MkHeader("Bracket",  COL_BRACKET)
    MkHeader("Result",   COL_RESULT)
    MkHeader("\206\148 Rating", COL_DELTA)
    MkHeader("Rating",   COL_RATING)

    local hline = parent:CreateTexture(nil, "BORDER")
    hline:SetHeight(1)
    local hlineTop = PAD + FILTER_H + GAP + 2 + HEADER_H
    hline:SetPoint("TOPLEFT", PAD, -hlineTop)
    hline:SetPoint("TOPRIGHT", -PAD, -hlineTop)
    hline:SetColorTexture(0.18, 0.18, 0.18, 0.8)

    -- Scroll frame
    local scrollTop = hlineTop + 2
    scrollFrame = CreateFrame("ScrollFrame", nil, parent)
    scrollFrame:SetPoint("TOPLEFT", PAD, -scrollTop)
    scrollFrame:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(cur - delta * ROW_H * 3, max)))
    end)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetHeight(1)
    scrollFrame:SetScript("OnSizeChanged", function(self, w)
        scrollChild:SetWidth(w)
    end)

    -- Empty state
    emptyLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyLabel:SetPoint("CENTER", 0, 0)
    emptyLabel:SetText("No matches recorded yet.")
    emptyLabel:SetTextColor(0.38, 0.38, 0.38)
    emptyLabel:Hide()

    -- Refresh when tab is shown
    parent:SetScript("OnShow", function()
        RefreshRows()
    end)
end

function NXR.RefreshInsights()
    if not insightsPanel then return end
    RefreshRows()
end
