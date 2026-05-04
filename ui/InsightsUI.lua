local addonName, NXR = ...

-- ============================================================================
-- Layout constants
-- ============================================================================

local ROW_H     = 24
local PAD       = 8
local ICON_SZ   = 14
local ICON_STEP = 16   -- icon size + 2px gap

local FILTER_H  = 28
local HEADER_H  = 20
local GAP       = 4

local ENTRY_HEIGHT        = 22
local MAX_VISIBLE_ENTRIES = 12
local DROPDOWN_WIDTH      = 240

-- Column x-offsets within each row (from row left edge)
local COL_DATE    = 0
local COL_BRACKET = 100
local COL_RESULT  = 195
local COL_DELTA   = 260
local COL_RATING  = 330
local COL_TEAM    = 410

-- ============================================================================
-- Filter state
-- ============================================================================

local insightsCharKey = nil   -- nil = show all chars
local filterBracket   = "All"
local filterOutcome   = "All"

local BRACKET_OPTIONS = { "All", "Solo Shuffle", "2v2", "3v3", "Blitz BG" }
local OUTCOME_OPTIONS = { "All", "Win", "Loss", "Draw" }

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

-- Dropdown state
local charDropdown, charDropdownEntries, charDropdownData, charDropdownOffset
local bracketDropdown, bracketDropdownEntries
local outcomeDropdown, outcomeDropdownEntries
local ddClickCatcher
local charButton, bracketButton, outcomeButton

-- Forward declarations
local RefreshRows
local RefreshCharDropdownEntries

-- ============================================================================
-- Spec helpers
-- ============================================================================

local function GetSpecIcon(specID)
    if not specID or specID == 0 then return nil end
    local sd = NXR.specData and NXR.specData[specID]
    if sd and sd.icon then return sd.icon end
    local _, _, _, icon = GetSpecializationInfoByID(specID)
    return icon
end

local function GetSpecName(specID)
    if not specID or specID == 0 then return "Unknown" end
    local sd = NXR.specData and NXR.specData[specID]
    if sd then return sd.specName or "Unknown" end
    local _, name = GetSpecializationInfoByID(specID)
    return name or "Unknown"
end

-- ============================================================================
-- Character list (same pattern as HistoryUI)
-- ============================================================================

local function BuildSortedCharList()
    local hasMatches = {}
    for _, rec in ipairs(NXR.GetMatches()) do
        if rec.charKey then hasMatches[rec.charKey] = true end
    end

    local classSortIndex = {}
    for i, classID in ipairs(NXR.sortedClassIDs) do
        local cd = NXR.classData[classID]
        if cd then classSortIndex[cd.classFileName] = i end
    end

    local list = {}
    for key, char in pairs(NelxRatedDB.characters) do
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
    local name = char.name .. " - " .. char.realm
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

local function FormatCharButtonLabel(char)
    if not char then return "All Characters" end
    local parts = {}
    local ri = FormatRaceIcon(char)
    if ri then parts[#parts + 1] = ri end
    parts[#parts + 1] = FormatCharName(char)
    return table.concat(parts, " ")
end

-- ============================================================================
-- Dropdown infrastructure (replicates HistoryUI pattern)
-- ============================================================================

local function HideAllDropdowns()
    if charDropdown    then charDropdown:Hide() end
    if bracketDropdown then bracketDropdown:Hide() end
    if outcomeDropdown then outcomeDropdown:Hide() end
    if ddClickCatcher  then ddClickCatcher:Hide() end
end

local function EnsureClickCatcher(strata, level)
    if not ddClickCatcher then
        ddClickCatcher = CreateFrame("Button", nil, UIParent)
        ddClickCatcher:SetAllPoints()
        ddClickCatcher:SetScript("OnClick", HideAllDropdowns)
    end
    ddClickCatcher:SetFrameStrata(strata)
    ddClickCatcher:SetFrameLevel(level - 1)
    ddClickCatcher:Show()
end

local function OnCharDropdownScroll(_, delta)
    if not charDropdownData then return end
    local maxOffset = math.max(0, #charDropdownData - MAX_VISIBLE_ENTRIES)
    charDropdownOffset = math.max(0, math.min(charDropdownOffset - delta, maxOffset))
    RefreshCharDropdownEntries()
end

local function GetOrCreateCharEntry(parent, index)
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
    btn:SetScript("OnMouseWheel", OnCharDropdownScroll)

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
        local entry = GetOrCreateCharEntry(charDropdown, i)
        entry.label:SetText(data.display)
        entry:SetScript("OnClick", function()
            insightsCharKey = data.key
            charButton.label:SetText(FormatCharButtonLabel(data.char))
            charButton.label:SetJustifyH("LEFT")
            RefreshRows()
            HideAllDropdowns()
        end)
        entry:Show()
    end
end

local function ShowCharDropdown(btn)
    if charDropdown and charDropdown:IsShown() then
        HideAllDropdowns()
        return
    end
    HideAllDropdowns()

    local chars = BuildSortedCharList()
    charDropdownData = {}
    charDropdownData[1] = { key = nil, char = nil, display = "All Characters" }
    for _, item in ipairs(chars) do
        charDropdownData[#charDropdownData + 1] = {
            key = item.key, char = item.char, display = FormatCharDisplay(item.char),
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
    charDropdown:SetScript("OnMouseWheel", OnCharDropdownScroll)

    RefreshCharDropdownEntries()
    EnsureClickCatcher(charDropdown:GetFrameStrata(), charDropdown:GetFrameLevel())
    charDropdown:Show()
end

-- Simple (non-scrollable) dropdown for bracket/outcome

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

local function CreateSimpleDropdown(parent)
    local dd = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    dd:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    dd:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    dd:SetBackdropBorderColor(unpack(NXR.COLORS.CRIMSON_DIM))
    dd:SetFrameStrata("TOOLTIP")
    return dd
end

local function ShowSimpleDropdown(dropdown, entries, btn, items, onClick)
    HideAllDropdowns()
    dropdown:SetSize(btn:GetWidth(), #items * ENTRY_HEIGHT + 4)
    dropdown:ClearAllPoints()
    dropdown:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)

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

    EnsureClickCatcher(dropdown:GetFrameStrata(), dropdown:GetFrameLevel())
    dropdown:Show()
end

local function ShowBracketDropdown(btn)
    if bracketDropdown and bracketDropdown:IsShown() then HideAllDropdowns(); return end
    if not bracketDropdownEntries then bracketDropdownEntries = {} end
    if not bracketDropdown then bracketDropdown = CreateSimpleDropdown(btn:GetParent()) end
    local items = {}
    for _, opt in ipairs(BRACKET_OPTIONS) do
        items[#items + 1] = { display = opt, value = opt }
    end
    ShowSimpleDropdown(bracketDropdown, bracketDropdownEntries, btn, items, function(item)
        filterBracket = item.value
        bracketButton.label:SetText("Bracket: " .. item.value)
        RefreshRows()
    end)
end

local function ShowOutcomeDropdown(btn)
    if outcomeDropdown and outcomeDropdown:IsShown() then HideAllDropdowns(); return end
    if not outcomeDropdownEntries then outcomeDropdownEntries = {} end
    if not outcomeDropdown then outcomeDropdown = CreateSimpleDropdown(btn:GetParent()) end
    local items = {}
    for _, opt in ipairs(OUTCOME_OPTIONS) do
        items[#items + 1] = { display = opt, value = opt }
    end
    ShowSimpleDropdown(outcomeDropdown, outcomeDropdownEntries, btn, items, function(item)
        filterOutcome = item.value
        outcomeButton.label:SetText("Outcome: " .. item.value)
        RefreshRows()
    end)
end

-- ============================================================================
-- Tooltip
-- ============================================================================

local function sign(n)
    if n > 0 then return "+" .. n elseif n < 0 then return tostring(n) else return "(+0)" end
end

local function ShowMatchTooltip(anchor, rec)
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")

    local dateStr = date("%b %d, %H:%M", rec.timestamp or 0)
    local bName   = NXR.BRACKET_NAMES[rec.bracketIndex] or ("Bracket " .. tostring(rec.bracketIndex))
    local isSS    = rec.bracketIndex == NXR.BRACKET_SOLO_SHUFFLE

    GameTooltip:AddLine(bName .. "  -  " .. dateStr, 1, 1, 1)
    GameTooltip:AddLine(" ")

    if isSS then
        local sh  = rec.shuffle
        local won = (sh and sh.wonRounds) or rec.wonRounds or 0
        GameTooltip:AddLine("Won " .. won .. " / 6 rounds", 1, 0.85, 0.1)
        GameTooltip:AddLine(" ")
    end

    local delta   = rec.ratingChange or 0
    local preRat  = (rec.rating or 0) - delta
    local preMMR  = rec.prematchMMR or 0
    local postMMR = preMMR + (rec.mmrChange or 0)

    GameTooltip:AddDoubleLine("Rating",
        preRat .. "  ->  " .. (rec.rating or 0) .. "  " .. sign(delta),
        0.65, 0.65, 0.65, 1, 1, 1)
    if preMMR > 0 then
        GameTooltip:AddDoubleLine("MMR",
            preMMR .. "  ->  " .. postMMR .. "  " .. sign(rec.mmrChange or 0),
            0.65, 0.65, 0.65, 1, 1, 1)
    end

    if isSS then
        local hasAny = rec.specID or (rec.enemySpecs and #rec.enemySpecs > 0)
        if hasAny then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("All specs:", 0.65, 0.65, 0.65)
            if rec.specID then
                GameTooltip:AddLine("  [You] " .. GetSpecName(rec.specID), 1, 0.82, 0.0)
            end
            for _, sid in ipairs(rec.enemySpecs or {}) do
                GameTooltip:AddLine("  " .. GetSpecName(sid), 0.85, 0.85, 0.85)
            end
        end
    else
        local hasOwn   = rec.specID ~= nil
        local hasAlly  = rec.allySpecs and #rec.allySpecs > 0
        local hasEnemy = rec.enemySpecs and #rec.enemySpecs > 0

        if hasOwn or hasAlly then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Your team:", 0.65, 0.65, 0.65)
            if hasOwn then
                GameTooltip:AddLine("  [You] " .. GetSpecName(rec.specID), 1, 0.82, 0.0)
            end
            for _, sid in ipairs(rec.allySpecs or {}) do
                if sid then
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

    if isSS then
        local sh = rec.shuffle
        if sh and sh.rounds and #sh.rounds == 6 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Round outcomes:", 0.65, 0.65, 0.65)
            for _, r in ipairs(sh.rounds) do
                local label = "  R" .. r.num .. "  " .. (r.outcome or "?"):upper()
                if r.duration then label = label .. "  (" .. r.duration .. "s)" end
                if r.outcome == "win" then
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
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row:EnableMouse(true)

    local hlTex = row:CreateTexture(nil, "BACKGROUND")
    hlTex:SetAllPoints()
    hlTex:SetColorTexture(0.14, 0.06, 0.06, 0)
    row.hlTex = hlTex

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
    row.ratingText:SetWidth(COL_TEAM - COL_RATING - 4)
    row.ratingText:SetJustifyH("LEFT")

    -- Team icons: 3 my-team slots + vs label + 5 enemy slots (enough for SS 1+5 or 3v3 3+3)
    row.myIcons = {}
    for i = 1, 3 do
        local ico = row:CreateTexture(nil, "OVERLAY")
        ico:SetSize(ICON_SZ, ICON_SZ)
        ico:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        ico:SetPoint("LEFT", row, "LEFT", COL_TEAM + PAD + (i - 1) * ICON_STEP, 0)
        ico:Hide()
        row.myIcons[i] = ico
    end

    row.vsLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
    row.vsLabel:SetText("vs")
    row.vsLabel:SetTextColor(0.45, 0.45, 0.45)
    row.vsLabel:Hide()

    row.enemyIcons = {}
    for i = 1, 5 do
        local ico = row:CreateTexture(nil, "OVERLAY")
        ico:SetSize(ICON_SZ, ICON_SZ)
        ico:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        ico:Hide()
        row.enemyIcons[i] = ico
    end

    row:SetScript("OnEnter", function(self)
        self.hlTex:SetColorTexture(0.14, 0.06, 0.06, 0.7)
        if self.matchData then ShowMatchTooltip(self, self.matchData) end
    end)
    row:SetScript("OnLeave", function(self)
        self.hlTex:SetColorTexture(0.14, 0.06, 0.06, 0)
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
-- Team icon population
-- ============================================================================

local VS_W = 14   -- approximate pixel width of "vs" text

local function PopulateTeamIcons(row, rec)
    for _, ico in ipairs(row.myIcons)    do ico:Hide() end
    for _, ico in ipairs(row.enemyIcons) do ico:Hide() end
    row.vsLabel:Hide()

    local isSS = rec.bracketIndex == NXR.BRACKET_SOLO_SHUFFLE

    if isSS then
        -- Flat list: player spec first (full brightness), then up to 5 enemy specs (dimmed)
        local flat = {}
        if rec.specID and rec.specID ~= 0 then
            flat[1] = rec.specID
        end
        for _, sid in ipairs(rec.enemySpecs or {}) do
            if sid and sid ~= 0 then
                flat[#flat + 1] = sid
            end
        end

        for i = 1, math.min(#flat, 6) do
            local icon = GetSpecIcon(flat[i])
            if icon then
                local tex = i <= 3 and row.myIcons[i] or row.enemyIcons[i - 3]
                tex:ClearAllPoints()
                tex:SetPoint("LEFT", row, "LEFT", COL_TEAM + PAD + (i - 1) * ICON_STEP, 0)
                tex:SetTexture(icon)
                tex:SetVertexColor(1, 1, 1)
                tex:Show()
            end
        end

    else
        -- Arena: [your team] vs [enemies]
        local myTeam = {}
        if rec.specID and rec.specID ~= 0 then
            myTeam[1] = rec.specID
        end
        for _, sid in ipairs(rec.allySpecs or {}) do
            if sid and sid ~= 0 and #myTeam < 3 then
                myTeam[#myTeam + 1] = sid
            end
        end

        local enemies = {}
        for _, sid in ipairs(rec.enemySpecs or {}) do
            if sid and sid ~= 0 and #enemies < 3 then
                enemies[#enemies + 1] = sid
            end
        end

        local myCount = #myTeam
        for i, sid in ipairs(myTeam) do
            local icon = GetSpecIcon(sid)
            if icon then
                row.myIcons[i]:SetTexture(icon)
                row.myIcons[i]:SetVertexColor(1, 1, 1)
                row.myIcons[i]:Show()
            end
        end

        if myCount > 0 and #enemies > 0 then
            local vsX = COL_TEAM + PAD + myCount * ICON_STEP + 2
            row.vsLabel:ClearAllPoints()
            row.vsLabel:SetPoint("LEFT", row, "LEFT", vsX, 0)
            row.vsLabel:Show()

            for i, sid in ipairs(enemies) do
                local icon = GetSpecIcon(sid)
                if icon then
                    row.enemyIcons[i]:ClearAllPoints()
                    row.enemyIcons[i]:SetPoint("LEFT", row, "LEFT", vsX + VS_W + (i - 1) * ICON_STEP, 0)
                    row.enemyIcons[i]:SetTexture(icon)
                    row.enemyIcons[i]:SetVertexColor(0.7, 0.7, 0.7)
                    row.enemyIcons[i]:Show()
                end
            end
        elseif #enemies > 0 then
            for i, sid in ipairs(enemies) do
                local icon = GetSpecIcon(sid)
                if icon then
                    row.enemyIcons[i]:ClearAllPoints()
                    row.enemyIcons[i]:SetPoint("LEFT", row, "LEFT", COL_TEAM + PAD + (i - 1) * ICON_STEP, 0)
                    row.enemyIcons[i]:SetTexture(icon)
                    row.enemyIcons[i]:SetVertexColor(0.7, 0.7, 0.7)
                    row.enemyIcons[i]:Show()
                end
            end
        end
    end
end

-- ============================================================================
-- Filter logic
-- ============================================================================

local function BuildFilteredList()
    filteredList = {}
    local all = NXR.GetMatches()
    for i = #all, 1, -1 do
        local rec  = all[i]
        local pass = true

        if insightsCharKey and rec.charKey ~= insightsCharKey then
            pass = false
        end

        if pass and filterBracket ~= "All" then
            if NXR.BRACKET_NAMES[rec.bracketIndex] ~= filterBracket then
                pass = false
            end
        end

        if pass and filterOutcome ~= "All" then
            if rec.outcome ~= filterOutcome:lower() then
                pass = false
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

RefreshRows = function()
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
            row.resultText:SetText("?")
            row.resultText:SetTextColor(0.45, 0.45, 0.45)
        end

        local d = rec.ratingChange
        if d == nil then
            row.deltaText:SetText("?")
            row.deltaText:SetTextColor(0.45, 0.45, 0.45)
        elseif d > 0 then
            row.deltaText:SetText("+" .. d)
            row.deltaText:SetTextColor(0.1, 0.88, 0.1)
        elseif d < 0 then
            row.deltaText:SetText(tostring(d))
            row.deltaText:SetTextColor(0.88, 0.1, 0.1)
        else
            row.deltaText:SetText("+0")
            row.deltaText:SetTextColor(0.45, 0.45, 0.45)
        end

        row.ratingText:SetText(rec.rating and tostring(rec.rating) or "?")
        row.ratingText:SetTextColor(1, 1, 1)

        PopulateTeamIcons(row, rec)

        row:Show()
        yOff = yOff + ROW_H
    end

    for i = count + 1, #rowPool do
        rowPool[i]:Hide()
    end

    scrollChild:SetHeight(math.max(yOff, 1))
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

    local charBtnW   = 170
    local filterBtnW = 115
    local btnGap     = 6

    charButton = NXR.CreateNXRButton(filterBar, "All Characters", charBtnW, FILTER_H - 4)
    charButton:SetPoint("LEFT", 0, 0)
    charButton.label:ClearAllPoints()
    charButton.label:SetPoint("LEFT", 4, 0)
    charButton.label:SetPoint("RIGHT", -4, 0)
    charButton.label:SetJustifyH("LEFT")
    charButton.label:SetWordWrap(false)
    charButton:SetScript("OnClick", function(self) ShowCharDropdown(self) end)

    bracketButton = NXR.CreateNXRButton(filterBar, "Bracket: All", filterBtnW, FILTER_H - 4)
    bracketButton:SetPoint("LEFT", charBtnW + btnGap, 0)
    bracketButton:SetScript("OnClick", function(self) ShowBracketDropdown(self) end)

    outcomeButton = NXR.CreateNXRButton(filterBar, "Outcome: All", filterBtnW, FILTER_H - 4)
    outcomeButton:SetPoint("LEFT", charBtnW + filterBtnW + btnGap * 2, 0)
    outcomeButton:SetScript("OnClick", function(self) ShowOutcomeDropdown(self) end)

    countLabel = filterBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLabel:SetPoint("RIGHT", filterBar, "RIGHT", 0, 0)
    countLabel:SetTextColor(0.45, 0.45, 0.45)

    -- Separator under filter bar
    local sep1 = parent:CreateTexture(nil, "BORDER")
    sep1:SetHeight(1)
    sep1:SetPoint("TOPLEFT", PAD, -(PAD + FILTER_H + GAP))
    sep1:SetPoint("TOPRIGHT", -PAD, -(PAD + FILTER_H + GAP))
    sep1:SetColorTexture(unpack(NXR.COLORS.CRIMSON_DIM))

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
    MkHeader("Date",    COL_DATE)
    MkHeader("Bracket", COL_BRACKET)
    MkHeader("Result",  COL_RESULT)
    MkHeader("Chg",     COL_DELTA)
    MkHeader("Rating",  COL_RATING)
    MkHeader("Team",    COL_TEAM)

    local hlineTop = PAD + FILTER_H + GAP + 2 + HEADER_H
    local hline = parent:CreateTexture(nil, "BORDER")
    hline:SetHeight(1)
    hline:SetPoint("TOPLEFT", PAD, -hlineTop)
    hline:SetPoint("TOPRIGHT", -PAD, -hlineTop)
    hline:SetColorTexture(0.18, 0.18, 0.18, 0.8)

    -- Explicit dark background behind scroll area (prevents frame showing default white)
    local scrollTop = hlineTop + 2
    local scrollBg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    scrollBg:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 0,
    })
    scrollBg:SetBackdropColor(0.04, 0.04, 0.04, 0.5)
    scrollBg:SetPoint("TOPLEFT", PAD, -scrollTop)
    scrollBg:SetPoint("BOTTOMRIGHT", -PAD, PAD)

    -- Scroll frame
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

    -- Empty state label
    emptyLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyLabel:SetPoint("CENTER", 0, 0)
    emptyLabel:SetText("No matches recorded yet.")
    emptyLabel:SetTextColor(0.38, 0.38, 0.38)
    emptyLabel:Hide()

    parent:SetScript("OnShow", function()
        if insightsCharKey == nil and NXR.currentCharKey then
            local char = NelxRatedDB.characters[NXR.currentCharKey]
            if char then
                insightsCharKey = NXR.currentCharKey
                charButton.label:SetText(FormatCharButtonLabel(char))
                charButton.label:SetJustifyH("LEFT")
            end
        end
        RefreshRows()
    end)

    parent:SetScript("OnHide", function()
        HideAllDropdowns()
    end)
end

function NXR.RefreshInsights()
    if not insightsPanel then return end
    RefreshRows()
end
