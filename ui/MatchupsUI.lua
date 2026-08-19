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
local SPEC_SZ   = 20
local SPEC_GAP  = 4
local CHAR_BTN_W = 200

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
local mode          = "SHUFFLE"  -- "2V2" | "3V3" | "SHUFFLE"
local easiestFirst  = true
local seasonAll     = false  -- false = current season only; true = all seasons

local filterCharKey = nil  -- nil = all characters
local filterSpecID  = nil  -- nil = all specs
local specBarCharKey = nil -- char the spec bar was last built for (auto-select guard)
local initialized   = false -- default-to-current-char applied once

local scrollFrame, scrollChild
local rowPool    = {}
local modeBtns   = {}
local sortBtn    = nil
local seasonBtn  = nil
local charButton = nil
local specBar    = nil
local specIconBtns = {}
local emptyLabel = nil
local hdrNames, hdrGames = nil, nil
local scopeText  = "All characters"

local function IsArena() return mode ~= "SHUFFLE" end

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
-- Character filter helpers (same char list / label conventions as InsightsUI)
-- ============================================================================

local function GetClassIDFromFileName(classFileName)
    if not classFileName or not AI.classData then return nil end
    for classID, cd in pairs(AI.classData) do
        if cd.classFileName == classFileName then return classID end
    end
    return nil
end

local function BuildSortedCharList()
    local hasMatches = {}
    for _, rec in ipairs(AI.GetMatches()) do
        if rec.charKey then hasMatches[rec.charKey] = true end
    end

    local classSortIndex = {}
    for i, classID in ipairs(AI.sortedClassIDs) do
        local cd = AI.classData[classID]
        if cd then classSortIndex[cd.classFileName] = i end
    end

    local list = {}
    for key, char in pairs(ArenaInsightsDB.characters or {}) do
        if hasMatches[key] then
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
        local g = char.gender == 2 and "male" or char.gender == 3 and "female" or nil
        if g then
            return "|A:raceicon-" .. strlower(char.raceFileName) .. "-" .. g .. ":14:14|a"
        end
    end
    return nil
end

local function FormatCharName(char)
    local name = (char.name or "?") .. " - " .. (char.realm or "?")
    local cc = char.classFileName and RAID_CLASS_COLORS and RAID_CLASS_COLORS[char.classFileName]
    if cc and cc.colorStr then
        name = "|c" .. cc.colorStr .. name .. "|r"
    end
    return name
end

local function FormatCharDisplay(char)
    local parts = {}
    local ri = FormatRaceIcon(char)
    if ri then parts[#parts + 1] = ri end
    parts[#parts + 1] = FormatCharName(char)
    return table.concat(parts, " ")
end

-- Short name for the tooltip scope line: "Frostmage" or "All characters".
local function CharShortName(key)
    if not key then return "All characters" end
    local char = ArenaInsightsDB.characters and ArenaInsightsDB.characters[key]
    return char and char.name or (key:match("^(.+)-") or key)
end

-- ============================================================================
-- Data
-- ============================================================================

local function BuildEntries()
    local entries
    -- Default to the current season so a new season's data doesn't blend with
    -- the last one; "All seasons" (seasonAll) removes the filter.
    local si = seasonAll and nil or AI.GetCurrentSeasonId()
    if IsArena() then
        local bi = (mode == "2V2") and AI.BRACKET_2V2 or AI.BRACKET_3V3
        entries = AI.GetArenaCompStats(bi, filterCharKey, filterSpecID, si)
    else
        entries = AI.GetShuffleSpecStats(filterCharKey, filterSpecID, si)
    end
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
    if IsArena() then
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
    GameTooltip:AddLine(scopeText, 0.40, 0.40, 0.40)
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

    -- Tooltip scope line: reflects the active character/spec filter.
    local who = CharShortName(filterCharKey)
    if filterSpecID then
        local sd = AI.specData and AI.specData[filterSpecID]
        who = who .. " (" .. (sd and sd.specName or "spec") .. ")"
    end
    local multiSeason = AI.HasMultipleSeasons()
    scopeText = who .. ((not multiSeason or seasonAll) and ", entire match history."
        or ", current season only.")

    -- Season toggle only appears once a rollover has been recorded.
    if seasonBtn then
        if multiSeason then
            seasonBtn:Show()
            seasonBtn.label:SetText(seasonAll and "All seasons" or "This season")
        else
            seasonBtn:Hide()
        end
    end

    if hdrNames then
        hdrNames:SetText(IsArena() and "ENEMY COMP" or "ENEMY SPEC")
    end
    if hdrGames then
        hdrGames:SetText(IsArena() and "GAMES" or "ROUNDS")
    end
    if emptyLabel then
        if IsArena() then
            emptyLabel:SetText("No " .. mode:lower() .. " matches with enemy comp data yet.")
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

        if IsArena() then
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
-- Character + spec filter (spec icon bar mirrors InsightsUI)
-- ============================================================================

local function UpdateSpecToggleAppearance()
    local anyActive = filterSpecID ~= nil
    for _, btn in ipairs(specIconBtns) do
        if btn:IsShown() then
            if filterSpecID == btn.specID then
                btn:SetBackdropColor(0.7, 0.1, 0.1, 0.8)
                btn:SetBackdropBorderColor(0.9, 0.15, 0.15, 1)
                btn.iconTex:SetVertexColor(1, 1, 1)
            else
                btn:SetBackdropColor(0.10, 0.10, 0.10, 0.6)
                btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
                local d = anyActive and 0.45 or 1
                btn.iconTex:SetVertexColor(d, d, d)
            end
        end
    end
end

local function UpdateSpecBar()
    for _, btn in ipairs(specIconBtns) do btn:Hide() end

    -- Auto-select the active spec only when the bar is (re)built for a
    -- different character; re-running for the same char must not clobber a
    -- filter the user explicitly cleared.
    local isNewChar = filterCharKey ~= specBarCharKey
    specBarCharKey  = filterCharKey

    if not specBar or not filterCharKey then return end

    local char = ArenaInsightsDB.characters[filterCharKey]
    if not char or not char.classFileName then return end

    local classID = GetClassIDFromFileName(char.classFileName)
    if not classID then return end

    local numSpecs = GetNumSpecializationsForClassID(classID)
    if not numSpecs or numSpecs == 0 then return end

    local activeSpecID = nil
    if filterCharKey == AI.currentCharKey then
        local specIndex = GetSpecialization()
        if specIndex then
            activeSpecID = select(1, GetSpecializationInfo(specIndex))
        end
    end

    local x = 0
    for i = 1, numSpecs do
        local specID, specName, _, icon = GetSpecializationInfoForClassID(classID, i)
        if not specIconBtns[i] then
            local btn = CreateFrame("Button", nil, specBar, "BackdropTemplate")
            btn:SetSize(SPEC_SZ, SPEC_SZ)
            btn:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            btn.iconTex = btn:CreateTexture(nil, "ARTWORK")
            btn.iconTex:SetPoint("TOPLEFT",     btn, "TOPLEFT",      1, -1)
            btn.iconTex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1,  1)
            btn.iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.specName or "Unknown", 1, 1, 1)
                GameTooltip:AddLine("Filter to matches played on this spec", 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            btn:SetScript("OnClick", function(self)
                filterSpecID = (filterSpecID == self.specID) and nil or self.specID
                UpdateSpecToggleAppearance()
                RefreshList()
            end)
            specIconBtns[i] = btn
        end

        local btn = specIconBtns[i]
        btn.specID   = specID
        btn.specName = specName or "Unknown"
        btn.iconTex:SetTexture(icon)
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", specBar, "LEFT", x, 0)
        btn:Show()

        if isNewChar and filterSpecID == nil and activeSpecID and specID == activeSpecID then
            filterSpecID = specID
        end

        x = x + SPEC_SZ + SPEC_GAP
    end

    UpdateSpecToggleAppearance()
end

local function SelectChar(key)
    filterCharKey = key
    filterSpecID  = nil
    local char = key and ArenaInsightsDB.characters[key]
    if charButton then
        charButton.label:SetText(char and FormatCharDisplay(char) or "All Characters")
        charButton.label:SetJustifyH("LEFT")
    end
    UpdateSpecBar()
    RefreshList()
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

    local function MkModeBtn(key, text, width, xOff, tip)
        local btn = MkToggle(text, width, xOff)
        btn:SetScript("OnClick", function()
            mode = key
            UpdateModeButtons()
            RefreshList()
        end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tip[1], 1, 1, 1)
            for i = 2, #tip do GameTooltip:AddLine(tip[i], 0.7, 0.7, 0.7) end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        modeBtns[key] = btn
        return btn
    end

    MkModeBtn("2V2", "2v2", 54, 0,
        { "2v2 matchups", "Your record vs each exact enemy comp in 2v2." })
    MkModeBtn("3V3", "3v3", 54, 58,
        { "3v3 matchups", "Your record vs each exact enemy comp in 3v3." })
    MkModeBtn("SHUFFLE", "Solo Shuffle", 100, 116,
        { "Solo Shuffle matchups", "Your round winrate vs each spec on the",
          "enemy team, from captured rounds." })

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

    -- Season toggle: left of the sort toggle. Hidden until a rollover exists
    -- (RefreshList manages visibility + label).
    seasonBtn = MkToggle("This season", 96, 0)
    seasonBtn:ClearAllPoints()
    seasonBtn:SetPoint("TOPRIGHT", sortBtn, "TOPLEFT", -GAP, 0)
    seasonBtn:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
    seasonBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
    seasonBtn.label:SetTextColor(0.7, 0.7, 0.7)
    seasonBtn:Hide()
    seasonBtn:SetScript("OnClick", function()
        seasonAll = not seasonAll
        RefreshList()
    end)
    seasonBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Season scope", 1, 1, 1)
        GameTooltip:AddLine("Show only the current season's record, or", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("your entire history across all seasons.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    seasonBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Row 2: character dropdown + spec icon bar
    local row2Top = PAD + FILTER_H + GAP

    charButton = AI.CreateAIButton(parent, "All Characters", CHAR_BTN_W, FILTER_H - 4)
    charButton:SetPoint("TOPLEFT", PAD, -row2Top)
    charButton.label:ClearAllPoints()
    charButton.label:SetPoint("LEFT", 6, 0)
    charButton.label:SetPoint("RIGHT", -6, 0)
    charButton.label:SetJustifyH("LEFT")
    charButton.label:SetWordWrap(false)
    charButton:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateButton("All Characters", function() SelectChar(nil) end)
            for _, item in ipairs(BuildSortedCharList()) do
                root:CreateButton(FormatCharDisplay(item.char), function() SelectChar(item.key) end)
            end
        end)
    end)

    specBar = CreateFrame("Frame", nil, parent)
    specBar:SetSize(1, SPEC_SZ)
    specBar:SetPoint("LEFT", charButton, "RIGHT", PAD, 0)

    -- Column headers
    local hdrTop = PAD + 2 * (FILTER_H + GAP)
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
        -- Default to the current character + current spec on first open.
        if not initialized then
            initialized = true
            if AI.currentCharKey and ArenaInsightsDB.characters
                and ArenaInsightsDB.characters[AI.currentCharKey] then
                SelectChar(AI.currentCharKey)
                return
            end
        end
        RefreshList()
    end)

    return parent
end

function AI.RefreshMatchups()
    if not matchupsPanel or not matchupsPanel:IsShown() then return end
    RefreshList()
end
