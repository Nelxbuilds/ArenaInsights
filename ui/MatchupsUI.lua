local addonName, AI = ...

-- ============================================================================
-- Matchups tab: how you perform against every enemy comp (2v2/3v3) and every
-- enemy spec (Solo Shuffle, round-level). Aggregated on demand from the full
-- match dataset across all characters via AI.GetArenaCompStats() /
-- AI.GetShuffleSpecStats() — nothing stored in SavedVariables.
-- ============================================================================

local ROW_H     = 24
local PAD       = 8
local ICON_SZ   = 16
local ICON_STEP = 18
local FILTER_H  = 28
local HEADER_H  = 20
local GAP       = 4

-- Column x-offsets within each row
local COL_BRACKET = 0
local COL_ICONS   = 42
local COL_NAMES   = 42 + 3 * ICON_STEP + 4
local COL_GAMES   = 316
local COL_WL      = 362
local COL_PCT     = 420
local BAR_W       = 55
local BAR_H       = 8

-- ============================================================================
-- Module state
-- ============================================================================

local matchupsPanel = nil
local mode          = "ARENA"  -- "ARENA" | "SHUFFLE"
local easiestFirst  = true

local scrollFrame, scrollChild
local rowPool    = {}
local modeBtns   = {}
local sortBtn    = nil
local emptyLabel = nil
local hdrNames, hdrGames = nil, nil

-- ============================================================================
-- Helpers
-- ============================================================================

local function GetSpecIcon(specID)
    local sd = AI.specData and AI.specData[specID]
    if sd and sd.icon then return sd.icon end
    local _, _, _, icon = GetSpecializationInfoByID(specID)
    return icon
end

-- Spec name colored by class color; plain name when class color unavailable
local function SpecLabel(specID, withClass)
    local sd = AI.specData and AI.specData[specID]
    local name = sd and sd.specName
    if not name then
        local _, n = GetSpecializationInfoByID(specID)
        name = n or ("Spec " .. tostring(specID))
    end
    if withClass and sd and sd.className then
        name = name .. " " .. sd.className
    end
    local c = sd and sd.classFileName
        and RAID_CLASS_COLORS and RAID_CLASS_COLORS[sd.classFileName]
    if c and c.colorStr then
        return "|c" .. c.colorStr .. name .. "|r"
    end
    return name
end

local BRACKET_SHORT = { [AI.BRACKET_2V2] = "2v2", [AI.BRACKET_3V3] = "3v3" }

-- ============================================================================
-- Data
-- ============================================================================

local function BuildEntries()
    local entries = (mode == "ARENA") and AI.GetArenaCompStats() or AI.GetShuffleSpecStats()
    for _, e in ipairs(entries) do
        e.total = e.w + e.l
        e.pct   = e.total > 0 and (e.w / e.total) or 0
    end
    table.sort(entries, function(a, b)
        if a.pct ~= b.pct then
            if easiestFirst then return a.pct > b.pct end
            return a.pct < b.pct
        end
        if a.total ~= b.total then return a.total > b.total end
        return (a.key or a.specID or 0) < (b.key or b.specID or 0)
    end)
    return entries
end

-- ============================================================================
-- Row pool
-- ============================================================================

local function ShowRowTooltip(row)
    local e = row.entry
    if not e then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if mode == "ARENA" then
        GameTooltip:AddLine((BRACKET_SHORT[e.bracketIndex] or "?") .. " enemy comp", 0.96, 0.92, 0.90)
        for _, sid in ipairs(e.specs) do
            GameTooltip:AddLine(SpecLabel(sid, true))
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Matches: |cffffffff" .. e.total .. "|r  ("
            .. e.w .. " won, " .. e.l .. " lost)", 0.65, 0.65, 0.65)
    else
        GameTooltip:AddLine(SpecLabel(e.specID, true))
        GameTooltip:AddLine("Rounds with this spec on the enemy team:", 0.65, 0.65, 0.65)
        GameTooltip:AddLine("|cffffffff" .. e.total .. "|r  ("
            .. e.w .. " won, " .. e.l .. " lost)", 0.65, 0.65, 0.65)
        GameTooltip:AddLine("Only matches with per-round capture count.", 0.40, 0.40, 0.40)
    end
    GameTooltip:AddLine("All characters, entire match history.", 0.40, 0.40, 0.40)
    GameTooltip:Show()
end

local function CreateRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row:EnableMouse(true)

    local hlTex = row:CreateTexture(nil, "BACKGROUND")
    hlTex:SetAllPoints()
    hlTex:SetColorTexture(0, 0, 0, 0)
    row.hlTex = hlTex

    local sep = row:CreateTexture(nil, "BORDER")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(0.14, 0.14, 0.14, 0.7)

    local hY = -(ROW_H / 2)

    row.bracketText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.bracketText:SetPoint("LEFT", row, "TOPLEFT", COL_BRACKET + PAD, hY)
    row.bracketText:SetWidth(COL_ICONS - COL_BRACKET - 4)
    row.bracketText:SetJustifyH("LEFT")
    row.bracketText:SetTextColor(0.55, 0.55, 0.55)

    row.icons = {}
    for i = 1, 3 do
        local ico = row:CreateTexture(nil, "OVERLAY")
        ico:SetSize(ICON_SZ, ICON_SZ)
        ico:SetPoint("LEFT", row, "TOPLEFT", COL_ICONS + PAD + (i - 1) * ICON_STEP, hY)
        ico:Hide()
        row.icons[i] = ico
    end

    row.namesText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.namesText:SetPoint("LEFT", row, "TOPLEFT", COL_NAMES + PAD, hY)
    row.namesText:SetWidth(COL_GAMES - COL_NAMES - 8)
    row.namesText:SetJustifyH("LEFT")
    row.namesText:SetWordWrap(false)

    row.gamesText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.gamesText:SetPoint("LEFT", row, "TOPLEFT", COL_GAMES + PAD, hY)
    row.gamesText:SetWidth(COL_WL - COL_GAMES - 4)
    row.gamesText:SetJustifyH("LEFT")
    row.gamesText:SetTextColor(0.78, 0.75, 0.73)

    row.wlText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.wlText:SetPoint("LEFT", row, "TOPLEFT", COL_WL + PAD, hY)
    row.wlText:SetWidth(COL_PCT - COL_WL - 4)
    row.wlText:SetJustifyH("LEFT")

    row.pctText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.pctText:SetPoint("LEFT", row, "TOPLEFT", COL_PCT + PAD, hY)
    row.pctText:SetWidth(44)
    row.pctText:SetJustifyH("LEFT")
    row.pctText:SetTextColor(1, 1, 1)

    -- Winrate bar, anchored to the right edge
    row.barTrack = row:CreateTexture(nil, "ARTWORK")
    row.barTrack:SetSize(BAR_W, BAR_H)
    row.barTrack:SetPoint("RIGHT", row, "TOPRIGHT", -PAD, hY)
    row.barTrack:SetColorTexture(0.13, 0.13, 0.13, 1)

    row.barFill = row:CreateTexture(nil, "OVERLAY")
    row.barFill:SetHeight(BAR_H)
    row.barFill:SetPoint("LEFT", row.barTrack, "LEFT", 0, 0)

    row:SetScript("OnEnter", function(self)
        self.hlTex:SetColorTexture(0.10, 0.10, 0.10, 0.75)
        ShowRowTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.hlTex:SetColorTexture(0, 0, 0, 0)
        GameTooltip:Hide()
    end)

    return row
end

local function GetOrCreateRow(i)
    if rowPool[i] then return rowPool[i] end
    local row = CreateRow(scrollChild)
    rowPool[i] = row
    return row
end

-- ============================================================================
-- Refresh
-- ============================================================================

local function RefreshList()
    local entries = BuildEntries()

    if hdrNames then
        hdrNames:SetText(mode == "ARENA" and "ENEMY COMP" or "ENEMY SPEC")
    end
    if hdrGames then
        hdrGames:SetText(mode == "ARENA" and "GAMES" or "ROUNDS")
    end
    if emptyLabel then
        if mode == "ARENA" then
            emptyLabel:SetText("No 2v2/3v3 matches with enemy comp data yet.")
        else
            emptyLabel:SetText("No Solo Shuffle rounds captured yet.")
        end
        emptyLabel:SetShown(#entries == 0)
    end

    local yOff = 0
    for i, e in ipairs(entries) do
        local row = GetOrCreateRow(i)
        row:SetPoint("TOPLEFT", 0, -yOff)
        row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        row.entry = e

        for _, ico in ipairs(row.icons) do ico:Hide() end

        if mode == "ARENA" then
            row.bracketText:SetText(BRACKET_SHORT[e.bracketIndex] or "?")
            local names = {}
            for j, sid in ipairs(e.specs) do
                if j <= 3 then
                    local icon = GetSpecIcon(sid)
                    if icon then
                        AI.SetSpecIcon(row.icons[j], icon)
                        row.icons[j]:Show()
                    end
                end
                names[#names + 1] = SpecLabel(sid)
            end
            row.namesText:SetText(table.concat(names, "  "))
        else
            row.bracketText:SetText("")
            local icon = GetSpecIcon(e.specID)
            if icon then
                AI.SetSpecIcon(row.icons[1], icon)
                row.icons[1]:Show()
            end
            row.namesText:SetText(SpecLabel(e.specID, true))
        end

        row.gamesText:SetText(tostring(e.total))
        row.wlText:SetText("|cff22cc22" .. e.w .. "|r-|cffcc2222" .. e.l .. "|r")
        row.pctText:SetFormattedText("%d%%", math.floor(e.pct * 100 + 0.5))

        local fillW = math.max(e.pct * BAR_W, e.w > 0 and 1 or 0.001)
        row.barFill:SetWidth(fillW)
        if e.pct >= 0.5 then
            row.barFill:SetColorTexture(0.22, 0.80, 0.22, 1)
        else
            row.barFill:SetColorTexture(0.80, 0.22, 0.22, 1)
        end

        row:Show()
        yOff = yOff + ROW_H
    end

    for i = #entries + 1, #rowPool do
        rowPool[i]:Hide()
    end

    scrollChild:SetHeight(math.max(yOff, 1))
    scrollFrame:SetVerticalScroll(0)
end

local function UpdateModeButtons()
    for m, btn in pairs(modeBtns) do
        if m == mode then
            btn:SetBackdropColor(0.7, 0.1, 0.1, 0.8)
            btn:SetBackdropBorderColor(0.9, 0.15, 0.15, 1)
            btn.label:SetTextColor(1, 1, 1)
        else
            btn:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
            btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
            btn.label:SetTextColor(0.7, 0.7, 0.7)
        end
    end
    if sortBtn then
        sortBtn.label:SetText(easiestFirst and "Easiest first" or "Hardest first")
    end
end

-- ============================================================================
-- Panel
-- ============================================================================

function AI.CreateMatchupsPanel(parent)
    matchupsPanel = parent

    -- Mode toggle (Arena / Solo Shuffle) + sort toggle
    local function MkToggle(text, width, xOff)
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(width, FILTER_H - 4)
        btn:SetPoint("TOPLEFT", PAD + xOff, -PAD)
        btn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.label:SetPoint("CENTER")
        btn.label:SetText(text)
        return btn
    end

    local arenaBtn = MkToggle("Arena", 70, 0)
    arenaBtn:SetScript("OnClick", function()
        mode = "ARENA"
        UpdateModeButtons()
        RefreshList()
    end)
    arenaBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Arena matchups", 1, 1, 1)
        GameTooltip:AddLine("Your record vs each exact enemy comp", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("in 2v2 and 3v3.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    arenaBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    modeBtns.ARENA = arenaBtn

    local ssBtn = MkToggle("Solo Shuffle", 100, 74)
    ssBtn:SetScript("OnClick", function()
        mode = "SHUFFLE"
        UpdateModeButtons()
        RefreshList()
    end)
    ssBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Solo Shuffle matchups", 1, 1, 1)
        GameTooltip:AddLine("Your round winrate vs each spec on the", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("enemy team, from captured rounds.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    ssBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    modeBtns.SHUFFLE = ssBtn

    sortBtn = MkToggle("Easiest first", 96, 0)
    sortBtn:ClearAllPoints()
    sortBtn:SetPoint("TOPRIGHT", -PAD, -PAD)
    sortBtn:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
    sortBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
    sortBtn.label:SetTextColor(0.7, 0.7, 0.7)
    sortBtn:SetScript("OnClick", function()
        easiestFirst = not easiestFirst
        UpdateModeButtons()
        RefreshList()
    end)
    sortBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Sort order", 1, 1, 1)
        GameTooltip:AddLine("Toggle between your best and worst", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("matchups first.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    sortBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Column headers
    local hdrTop = PAD + FILTER_H + GAP
    local headerRow = CreateFrame("Frame", nil, parent)
    headerRow:SetHeight(HEADER_H)
    headerRow:SetPoint("TOPLEFT", PAD, -hdrTop)
    headerRow:SetPoint("TOPRIGHT", -PAD, -hdrTop)

    local function MkHeader(text, xOff)
        local fs = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
        fs:SetPoint("LEFT", xOff + PAD, 0)
        fs:SetText(text)
        fs:SetTextColor(0.40, 0.40, 0.40)
        return fs
    end
    MkHeader("VS", COL_BRACKET)
    hdrNames = MkHeader("ENEMY COMP", COL_ICONS)
    hdrGames = MkHeader("GAMES", COL_GAMES)
    MkHeader("W-L", COL_WL)
    MkHeader("WIN%", COL_PCT)

    local hlineTop = hdrTop + HEADER_H
    local hline = parent:CreateTexture(nil, "BORDER")
    hline:SetHeight(1)
    hline:SetPoint("TOPLEFT", PAD, -hlineTop)
    hline:SetPoint("TOPRIGHT", -PAD, -hlineTop)
    hline:SetColorTexture(0.18, 0.18, 0.18, 0.8)

    -- Dark background behind scroll area
    local scrollTop = hlineTop + 2
    local scrollBgTex = parent:CreateTexture(nil, "BACKGROUND")
    scrollBgTex:SetColorTexture(0.04, 0.04, 0.04, 1.0)
    scrollBgTex:SetPoint("TOPLEFT", PAD, -scrollTop)
    scrollBgTex:SetPoint("BOTTOMRIGHT", -PAD, PAD)

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

    emptyLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyLabel:SetPoint("CENTER", 0, 0)
    emptyLabel:SetText("No matches recorded yet.")
    emptyLabel:SetTextColor(0.38, 0.38, 0.38)
    emptyLabel:Hide()

    UpdateModeButtons()

    parent:SetScript("OnShow", function()
        RefreshList()
    end)

    return parent
end

function AI.RefreshMatchups()
    if not matchupsPanel or not matchupsPanel:IsShown() then return end
    RefreshList()
end
