local addonName, AI = ...

-- ============================================================================
-- Layout constants
-- ============================================================================

local ROW_H     = 24
local PAD       = 8
local ICON_SZ   = 14
local ICON_STEP = 16   -- icon size + 2px gap

local FILTER_H      = 28
local STATS_BAR_H   = 46
local HEADER_H      = 20
local GAP           = 4

local ENTRY_HEIGHT        = 22
local MAX_VISIBLE_ENTRIES = 12
local DROPDOWN_WIDTH      = 240

local DETAIL_PAD_V   = 4
local DETAIL_HDR_H   = 14
local DETAIL_PLINE_H = 15
local ROUND_ROW_H    = 20
local ROUND_ICON_S   = 14

-- Column x-offsets within the detail frame
local PLINE_NAME_X = 18
local PLINE_DMG_X  = 162
local PLINE_HEAL_X = 230
local PLINE_KB_X   = 298
local PLINE_MMR_X  = 348

-- Column x-offsets within each row (from row left edge)
local COL_DATE    = 0
local COL_BRACKET = 100
local COL_DELTA   = 180
local COL_RATING  = 240
local COL_MMR     = 305
local COL_TEAM    = 370

local BRACKET_SHORT = { [7] = "Shuffle", [4] = "Blitz", [1] = "2v2", [2] = "3v3" }

-- Row background colors per outcome — subtle tints, not eye-burning
local OUTCOME_BASE = {
    win     = { 0.04, 0.12, 0.04, 0.80 },
    loss    = { 0.14, 0.04, 0.04, 0.80 },
    draw    = { 0.12, 0.09, 0.02, 0.80 },
    unknown = { 0.04, 0.04, 0.04, 0.60 },
}
local OUTCOME_HOVER = {
    win     = { 0.06, 0.18, 0.06, 0.90 },
    loss    = { 0.20, 0.06, 0.06, 0.90 },
    draw    = { 0.18, 0.13, 0.03, 0.90 },
    unknown = { 0.10, 0.10, 0.10, 0.75 },
}

-- ============================================================================
-- Filter state
-- ============================================================================

local insightsCharKey = nil   -- nil = show all chars
local filterBrackets  = {}    -- [bracketIndex]=true; empty set = show all

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
local expandedIndex  = nil

-- Dropdown / filter UI state
local charDropdown, charDropdownEntries, charDropdownData, charDropdownOffset
local ddClickCatcher
local charButton
local bracketToggleBtns = {}
local bracketStatBlocks = {}

-- Forward declarations
local RefreshRows
local RefreshCharDropdownEntries

-- ============================================================================
-- Spec helpers
-- ============================================================================

local function GetSpecIcon(specID)
    if not specID or specID == 0 then return nil end
    local sd = AI.specData and AI.specData[specID]
    if sd and sd.icon then return sd.icon end
    local _, _, _, icon = GetSpecializationInfoByID(specID)
    return icon
end

local function GetSpecName(specID)
    if not specID or specID == 0 then return "Unknown" end
    local sd = AI.specData and AI.specData[specID]
    if sd then return sd.specName or "Unknown" end
    local _, name = GetSpecializationInfoByID(specID)
    return name or "Unknown"
end

-- ============================================================================
-- Character list (same pattern as HistoryUI)
-- ============================================================================

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
    for key, char in pairs(ArenaInsightsDB.characters) do
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
    if charDropdown   then charDropdown:Hide() end
    if ddClickCatcher then ddClickCatcher:Hide() end
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
    hl:SetColorTexture(AI.COLORS.CRIMSON_DIM[1], AI.COLORS.CRIMSON_DIM[2], AI.COLORS.CRIMSON_DIM[3], 0.3)

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
            expandedIndex = nil
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
        charDropdown:SetBackdropBorderColor(unpack(AI.COLORS.CRIMSON_DIM))
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

local function UpdateBracketToggles()
    local anyActive = next(filterBrackets) ~= nil
    for bi, btn in pairs(bracketToggleBtns) do
        if filterBrackets[bi] then
            btn:SetBackdropColor(0.7, 0.1, 0.1, 0.8)
            btn:SetBackdropBorderColor(0.9, 0.15, 0.15, 1)
            btn.label:SetTextColor(1, 1, 1)
        else
            btn:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
            btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
            local dim = anyActive and 0.4 or 0.7
            btn.label:SetTextColor(dim, dim, dim)
        end
    end
end

-- ============================================================================
-- Tooltip
-- ============================================================================

local function sign(n)
    if n > 0 then return "+" .. n elseif n < 0 then return tostring(n) else return "(+0)" end
end

local function FormatStat(n)
    if n == nil then return "-" end
    if n == 0   then return "0" end  -- tostring(-0.0) returns "-0" in Lua
    if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
    if n >= 1000    then return string.format("%.0fk", n / 1000) end
    return tostring(n)
end

local function ShowMatchTooltip(anchor, rec)
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    local bName = AI.BRACKET_NAMES[rec.bracketIndex] or ("Bracket " .. tostring(rec.bracketIndex))
    GameTooltip:AddLine(bName .. "  -  " .. date("%b %d, %H:%M", rec.timestamp or 0), 0.65, 0.65, 0.65)
    GameTooltip:AddLine("Click to expand", 0.40, 0.40, 0.40)
    GameTooltip:Show()
end

-- ============================================================================
-- Detail player sort/render
-- ============================================================================

local function PopulateDetailPlayers(detail)
    local players = detail.playerData
    if not players then return end

    local sorted = {}
    for _, p in ipairs(players) do sorted[#sorted + 1] = p end

    local sk = detail.sortKey
    if sk then
        local dir = detail.sortDir or "desc"
        table.sort(sorted, function(a, b)
            if not a or not b then return b == nil end
            local av = (sk == "dmg"  and (a.damageDone   or 0))
                    or (sk == "heal" and (a.healingDone   or 0))
                    or (sk == "kb"   and (a.killingBlows  or 0))
                    or (sk == "mmr"  and (a.prematchMMR   or 0)) or 0
            local bv = (sk == "dmg"  and (b.damageDone   or 0))
                    or (sk == "heal" and (b.healingDone   or 0))
                    or (sk == "kb"   and (b.killingBlows  or 0))
                    or (sk == "mmr"  and (b.prematchMMR   or 0)) or 0
            if dir == "desc" then return av > bv else return av < bv end
        end)
    end

    local count = math.min(#sorted, 6)
    for li = 1, 6 do
        local pl = detail.playerLines[li]
        if li <= count then
            local p = sorted[li]
            local icon = GetSpecIcon(p.specID)
            if icon then AI.SetSpecIcon(pl.icon, icon) pl.icon:Show()
            else pl.icon:Hide() end
            if p.isSelf then
                pl.nameText:SetText(p.name or "You")
                pl.nameText:SetTextColor(unpack(AI.COLORS.GOLD))
            else
                pl.nameText:SetText(p.name or "?")
                pl.nameText:SetTextColor(0.70, 0.70, 0.70)
            end
            pl.dmgText:SetText(FormatStat(p.damageDone))
            pl.healText:SetText(FormatStat(p.healingDone))
            pl.kbText:SetText(FormatStat(p.killingBlows))
            if detail.isSS then
                local mmr = p.prematchMMR
                if mmr and mmr > 0 then
                    pl.mmrText:SetText(tostring(mmr))
                    pl.mmrText:SetTextColor(sk == "mmr" and 0.92 or 0.65, sk == "mmr" and 0.92 or 0.65, sk == "mmr" and 0.92 or 0.65)
                else
                    pl.mmrText:SetText("--")
                    pl.mmrText:SetTextColor(0.30, 0.30, 0.30)
                end
            else
                pl.mmrText:SetText("")
            end
            pl.dmgText:SetTextColor( sk == "dmg"  and 0.92 or 0.65, sk == "dmg"  and 0.92 or 0.65, sk == "dmg"  and 0.92 or 0.65)
            pl.healText:SetTextColor(sk == "heal" and 0.92 or 0.65, sk == "heal" and 0.92 or 0.65, sk == "heal" and 0.92 or 0.65)
            pl.kbText:SetTextColor(  sk == "kb"   and 0.92 or 0.65, sk == "kb"   and 0.92 or 0.65, sk == "kb"   and 0.92 or 0.65)
        else
            pl.icon:Hide()
            pl.nameText:SetText("") pl.dmgText:SetText("") pl.healText:SetText("")
            pl.kbText:SetText("") pl.mmrText:SetText("")
        end
    end

    if detail.hdrDmg then
        detail.hdrDmg:SetTextColor( sk == "dmg"  and 0.96 or 0.38, sk == "dmg"  and 0.92 or 0.38, sk == "dmg"  and 0.90 or 0.38)
        detail.hdrHeal:SetTextColor(sk == "heal" and 0.96 or 0.38, sk == "heal" and 0.92 or 0.38, sk == "heal" and 0.90 or 0.38)
        detail.hdrKB:SetTextColor(  sk == "kb"   and 0.96 or 0.38, sk == "kb"   and 0.92 or 0.38, sk == "kb"   and 0.90 or 0.38)
        if detail.isSS then
            detail.hdrMMR:Show()
            detail.hdrMMR:SetTextColor(sk == "mmr" and 0.96 or 0.38, sk == "mmr" and 0.92 or 0.38, sk == "mmr" and 0.90 or 0.38)
        else
            detail.hdrMMR:Hide()
        end
    end
end

-- ============================================================================
-- SS per-round comp rows
-- ============================================================================

local VS_W = 18  -- pixel width of "vs" separator area
local ROUND_ALLY_START  = 24 + ROUND_ICON_S + 2  -- x of first ally icon
local ROUND_ENEMY_START = 24 + 3 * (ROUND_ICON_S + 2) + VS_W  -- x of first enemy icon
local ROUND_OUTCOME_X   = 24 + 6 * (ROUND_ICON_S + 2) + VS_W + 8
local ROUND_DUR_X       = ROUND_OUTCOME_X + 40

local function GetOrCreateRoundRow(detail, idx)
    if detail.roundRows[idx] then return detail.roundRows[idx] end

    local rr = {}

    rr.label = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
    rr.label:SetWidth(22)
    rr.label:SetJustifyH("LEFT")
    rr.label:SetTextColor(0.40, 0.40, 0.40)

    rr.myIcon = detail:CreateTexture(nil, "OVERLAY")
    rr.myIcon:SetSize(ROUND_ICON_S, ROUND_ICON_S)

    rr.allyIcons = {}
    for i = 1, 2 do
        local ico = detail:CreateTexture(nil, "OVERLAY")
        ico:SetSize(ROUND_ICON_S, ROUND_ICON_S)
        rr.allyIcons[i] = ico
    end

    rr.vsLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
    rr.vsLabel:SetText("vs")
    rr.vsLabel:SetTextColor(0.35, 0.35, 0.35)

    rr.enemyIcons = {}
    for i = 1, 3 do
        local ico = detail:CreateTexture(nil, "OVERLAY")
        ico:SetSize(ROUND_ICON_S, ROUND_ICON_S)
        rr.enemyIcons[i] = ico
    end

    rr.outcomeText = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
    rr.outcomeText:SetWidth(36)
    rr.outcomeText:SetJustifyH("LEFT")

    rr.durText = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
    rr.durText:SetWidth(40)
    rr.durText:SetJustifyH("LEFT")
    rr.durText:SetTextColor(0.38, 0.38, 0.38)

    detail.roundRows[idx] = rr
    return rr
end

local function PositionRoundRow(rr, yOff)
    rr.label:ClearAllPoints()
    rr.label:SetPoint("TOPLEFT", 0, yOff - 3)
    rr.myIcon:ClearAllPoints()
    rr.myIcon:SetPoint("TOPLEFT", 24, yOff - 2)
    for i = 1, 2 do
        rr.allyIcons[i]:ClearAllPoints()
        rr.allyIcons[i]:SetPoint("TOPLEFT", ROUND_ALLY_START + (i - 1) * (ROUND_ICON_S + 2), yOff - 2)
    end
    rr.vsLabel:ClearAllPoints()
    rr.vsLabel:SetPoint("TOPLEFT", 24 + 3 * (ROUND_ICON_S + 2) + 2, yOff - 3)
    for i = 1, 3 do
        rr.enemyIcons[i]:ClearAllPoints()
        rr.enemyIcons[i]:SetPoint("TOPLEFT", ROUND_ENEMY_START + (i - 1) * (ROUND_ICON_S + 2), yOff - 2)
    end
    rr.outcomeText:ClearAllPoints()
    rr.outcomeText:SetPoint("TOPLEFT", ROUND_OUTCOME_X, yOff - 3)
    rr.durText:ClearAllPoints()
    rr.durText:SetPoint("TOPLEFT", ROUND_DUR_X, yOff - 3)
end

local function PopulateRoundRows(detail, rec, playerCount)
    local sh = rec.shuffle
    if not (sh and sh.rounds and #sh.rounds > 0) then return end

    local myIcon = GetSpecIcon(rec.specID)
    local baseY  = -(DETAIL_PAD_V + DETAIL_HDR_H + playerCount * DETAIL_PLINE_H + 4)

    for i, r in ipairs(sh.rounds) do
        local rr   = GetOrCreateRoundRow(detail, i)
        local yOff = baseY - (i - 1) * ROUND_ROW_H
        PositionRoundRow(rr, yOff)

        rr.label:SetText("R" .. r.num)

        if myIcon then AI.SetSpecIcon(rr.myIcon, myIcon) rr.myIcon:Show()
        else rr.myIcon:Hide() end

        local allySpecs = r.allySpecs or {}
        for j = 1, 2 do
            local ico = rr.allyIcons[j]
            local sid = allySpecs[j]
            local specIcon = sid and GetSpecIcon(sid)
            if specIcon then AI.SetSpecIcon(ico, specIcon) ico:Show()
            else ico:Hide() end
        end

        local enemySpecs = r.enemySpecs or {}
        for j = 1, 3 do
            local ico = rr.enemyIcons[j]
            local sid = enemySpecs[j]
            local specIcon = sid and GetSpecIcon(sid)
            if specIcon then AI.SetSpecIcon(ico, specIcon) ico:Show()
            else ico:Hide() end
        end

        if r.outcome == "win" then
            rr.outcomeText:SetText("WIN")
            rr.outcomeText:SetTextColor(0.13, 0.80, 0.13)
        elseif r.outcome == "loss" then
            rr.outcomeText:SetText("LOSS")
            rr.outcomeText:SetTextColor(0.80, 0.13, 0.13)
        else
            rr.outcomeText:SetText("?")
            rr.outcomeText:SetTextColor(0.45, 0.45, 0.45)
        end

        rr.durText:SetText(r.duration and ("(" .. r.duration .. "s)") or "")
    end
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
    hlTex:SetColorTexture(0, 0, 0, 0)
    row.hlTex = hlTex

    local sep = row:CreateTexture(nil, "BORDER")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(0.14, 0.14, 0.14, 0.7)

    local hY = -(ROW_H / 2)  -- y offset to keep items centered in the header strip

    row.dateText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.dateText:SetPoint("LEFT", row, "TOPLEFT", COL_DATE + PAD, hY)
    row.dateText:SetWidth(COL_BRACKET - COL_DATE - 4)
    row.dateText:SetJustifyH("LEFT")

    row.bracketText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.bracketText:SetPoint("LEFT", row, "TOPLEFT", COL_BRACKET + PAD, hY)
    row.bracketText:SetWidth(COL_DELTA - COL_BRACKET - 4)
    row.bracketText:SetJustifyH("LEFT")

    row.deltaText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.deltaText:SetPoint("LEFT", row, "TOPLEFT", COL_DELTA + PAD, hY)
    row.deltaText:SetWidth(COL_RATING - COL_DELTA - 4)
    row.deltaText:SetJustifyH("LEFT")

    row.ratingText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.ratingText:SetPoint("LEFT", row, "TOPLEFT", COL_RATING + PAD, hY)
    row.ratingText:SetWidth(COL_MMR - COL_RATING - 4)
    row.ratingText:SetJustifyH("LEFT")

    row.mmrText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.mmrText:SetPoint("LEFT", row, "TOPLEFT", COL_MMR + PAD, hY)
    row.mmrText:SetWidth(COL_TEAM - COL_MMR - 4)
    row.mmrText:SetJustifyH("LEFT")

    -- Team icons: 3 my-team slots + vs label + 5 enemy slots (enough for SS 1+5 or 3v3 3+3)
    row.myIcons = {}
    for i = 1, 3 do
        local ico = row:CreateTexture(nil, "OVERLAY")
        ico:SetSize(ICON_SZ, ICON_SZ)
        ico:SetPoint("LEFT", row, "TOPLEFT", COL_TEAM + PAD + (i - 1) * ICON_STEP, hY)
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
        ico:Hide()
        row.enemyIcons[i] = ico
    end

    -- Expand indicator (far right of header row)
    row.expandIndicator = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.expandIndicator:SetPoint("RIGHT", row, "TOPRIGHT", -PAD, hY)
    row.expandIndicator:SetText("+")
    row.expandIndicator:SetTextColor(0.40, 0.40, 0.40)

    -- Detail sub-frame (hidden by default; shown when row is expanded)
    row.detail = CreateFrame("Frame", nil, row)
    row.detail:SetPoint("TOPLEFT", PAD, -ROW_H)
    row.detail:SetPoint("RIGHT", -PAD, 0)
    row.detail:Hide()

    -- Column header labels (stored on detail for sort highlighting)
    row.detail.hdrDmg = row.detail:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
    row.detail.hdrDmg:SetPoint("TOPLEFT", PLINE_DMG_X, -DETAIL_PAD_V)
    row.detail.hdrDmg:SetText("DMG")
    row.detail.hdrDmg:SetTextColor(0.38, 0.38, 0.38)

    row.detail.hdrHeal = row.detail:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
    row.detail.hdrHeal:SetPoint("TOPLEFT", PLINE_HEAL_X, -DETAIL_PAD_V)
    row.detail.hdrHeal:SetText("HEAL")
    row.detail.hdrHeal:SetTextColor(0.38, 0.38, 0.38)

    row.detail.hdrKB = row.detail:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
    row.detail.hdrKB:SetPoint("TOPLEFT", PLINE_KB_X, -DETAIL_PAD_V)
    row.detail.hdrKB:SetText("KB")
    row.detail.hdrKB:SetTextColor(0.38, 0.38, 0.38)

    row.detail.hdrMMR = row.detail:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
    row.detail.hdrMMR:SetPoint("TOPLEFT", PLINE_MMR_X, -DETAIL_PAD_V)
    row.detail.hdrMMR:SetText("MMR")
    row.detail.hdrMMR:SetTextColor(0.38, 0.38, 0.38)

    -- Clickable sort zones over each column header
    row.detail.sortKey = nil
    row.detail.sortDir = "desc"
    local function MkSortBtn(x, w, key)
        local btn = CreateFrame("Frame", nil, row.detail)
        btn:SetPoint("TOPLEFT", x - 2, 0)
        btn:SetSize(w, DETAIL_PAD_V + DETAIL_HDR_H)
        btn:EnableMouse(true)
        btn:SetScript("OnMouseDown", function()
            if row.detail.sortKey == key then
                row.detail.sortDir = row.detail.sortDir == "desc" and "asc" or "desc"
            else
                row.detail.sortKey = key
                row.detail.sortDir = "desc"
            end
            PopulateDetailPlayers(row.detail)
        end)
    end
    MkSortBtn(PLINE_DMG_X,  PLINE_HEAL_X - PLINE_DMG_X,  "dmg")
    MkSortBtn(PLINE_HEAL_X, PLINE_KB_X   - PLINE_HEAL_X, "heal")
    MkSortBtn(PLINE_KB_X,   PLINE_MMR_X  - PLINE_KB_X,   "kb")
    MkSortBtn(PLINE_MMR_X,  55,                           "mmr")

    -- Absorb clicks on the detail area so they don't collapse the row
    row.detail:EnableMouse(true)
    row.detail:SetScript("OnMouseDown", function() end)
    row.detail:SetScript("OnEnter", function() GameTooltip:Hide() end)
    row.detail:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Pre-create 6 player lines (max for SS / 3v3)
    row.detail.playerLines = {}
    for i = 1, 6 do
        local lineY = -(DETAIL_PAD_V + DETAIL_HDR_H + (i - 1) * DETAIL_PLINE_H)
        local pl = {}

        pl.icon = row.detail:CreateTexture(nil, "OVERLAY")
        pl.icon:SetSize(12, 12)
        pl.icon:SetPoint("TOPLEFT", 0, lineY - 1)
        pl.icon:Hide()

        pl.nameText = row.detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pl.nameText:SetPoint("TOPLEFT", PLINE_NAME_X, lineY)
        pl.nameText:SetWidth(PLINE_DMG_X - PLINE_NAME_X - 4)
        pl.nameText:SetJustifyH("LEFT")
        pl.nameText:SetWordWrap(false)

        pl.dmgText = row.detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pl.dmgText:SetPoint("TOPLEFT", PLINE_DMG_X, lineY)
        pl.dmgText:SetWidth(PLINE_HEAL_X - PLINE_DMG_X - 4)
        pl.dmgText:SetJustifyH("LEFT")

        pl.healText = row.detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pl.healText:SetPoint("TOPLEFT", PLINE_HEAL_X, lineY)
        pl.healText:SetWidth(PLINE_KB_X - PLINE_HEAL_X - 4)
        pl.healText:SetJustifyH("LEFT")

        pl.kbText = row.detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pl.kbText:SetPoint("TOPLEFT", PLINE_KB_X, lineY)
        pl.kbText:SetWidth(PLINE_MMR_X - PLINE_KB_X - 4)
        pl.kbText:SetJustifyH("LEFT")

        pl.mmrText = row.detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pl.mmrText:SetPoint("TOPLEFT", PLINE_MMR_X, lineY)
        pl.mmrText:SetWidth(55)
        pl.mmrText:SetJustifyH("LEFT")

        row.detail.playerLines[i] = pl
    end

    -- SS per-round rows (created lazily, max 6)
    row.detail.roundRows = {}

    -- Fallback summary shown when shuffle.rounds is nil (no per-round state data)
    row.detail.wonRoundsText = row.detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.detail.wonRoundsText:SetJustifyH("LEFT")
    row.detail.wonRoundsText:Hide()

    row:SetScript("OnMouseDown", function(self)
        local idx = self.rowIndex
        if not idx then return end
        if expandedIndex == idx then
            expandedIndex = nil
        else
            expandedIndex = idx
        end
        RefreshRows()
    end)

    row:SetScript("OnEnter", function(self)
        if self.hoverColor then
            self.hlTex:SetColorTexture(unpack(self.hoverColor))
        end
        if self.matchData then ShowMatchTooltip(self, self.matchData) end
    end)
    row:SetScript("OnLeave", function(self)
        if self.baseColor then
            self.hlTex:SetColorTexture(unpack(self.baseColor))
        end
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

    local isSS = rec.bracketIndex == AI.BRACKET_SOLO_SHUFFLE

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
                tex:SetPoint("LEFT", row, "TOPLEFT", COL_TEAM + PAD + (i - 1) * ICON_STEP, -(ROW_H / 2))
                AI.SetSpecIcon(tex, icon)
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
                AI.SetSpecIcon(row.myIcons[i], icon)
                row.myIcons[i]:Show()
            end
        end

        if myCount > 0 and #enemies > 0 then
            local vsX = COL_TEAM + PAD + myCount * ICON_STEP + 2
            row.vsLabel:ClearAllPoints()
            row.vsLabel:SetPoint("LEFT", row, "TOPLEFT", vsX, -(ROW_H / 2))
            row.vsLabel:Show()

            for i, sid in ipairs(enemies) do
                local icon = GetSpecIcon(sid)
                if icon then
                    row.enemyIcons[i]:ClearAllPoints()
                    row.enemyIcons[i]:SetPoint("LEFT", row, "TOPLEFT", vsX + VS_W + (i - 1) * ICON_STEP, -(ROW_H / 2))
                    AI.SetSpecIcon(row.enemyIcons[i], icon)
                    row.enemyIcons[i]:Show()
                end
            end
        elseif #enemies > 0 then
            for i, sid in ipairs(enemies) do
                local icon = GetSpecIcon(sid)
                if icon then
                    row.enemyIcons[i]:ClearAllPoints()
                    row.enemyIcons[i]:SetPoint("LEFT", row, "TOPLEFT", COL_TEAM + PAD + (i - 1) * ICON_STEP, -(ROW_H / 2))
                    AI.SetSpecIcon(row.enemyIcons[i], icon)
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
    local all = AI.GetMatches()
    for i = #all, 1, -1 do
        local rec  = all[i]
        local pass = true

        if insightsCharKey and rec.charKey ~= insightsCharKey then
            pass = false
        end

        if pass and next(filterBrackets) then
            if not filterBrackets[rec.bracketIndex] then
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

local function RefreshStats()
    local anyFilter = next(filterBrackets) ~= nil
    for _, bi in ipairs(AI.TRACKED_BRACKETS) do
        local blk = bracketStatBlocks[bi]
        if blk then
            local w, l = 0, 0
            local isSS = (bi == AI.BRACKET_SOLO_SHUFFLE)
            for _, rec in ipairs(AI.GetMatches()) do
                if (not insightsCharKey or rec.charKey == insightsCharKey) and rec.bracketIndex == bi then
                    if isSS then
                        local won = (rec.shuffle and rec.shuffle.wonRounds) or rec.wonRounds
                        if won ~= nil then
                            w = w + won
                            l = l + (6 - won)
                        end
                    else
                        if     rec.outcome == "win"  then w = w + 1
                        elseif rec.outcome == "loss" then l = l + 1
                        end
                    end
                end
            end
            local total = w + l
            local wr = total > 0 and math.floor(w / total * 100 + 0.5) or 0

            blk.statData.w     = w
            blk.statData.l     = l
            blk.statData.total = total
            if total == 0 then
                blk.wrText:SetText("--")
                blk.wrText:SetTextColor(0.48, 0.45, 0.43)
                blk.winVal:SetText("--")
                blk.lossVal:SetText("--")
                blk.winVal:SetTextColor(0.48, 0.45, 0.43)
                blk.lossVal:SetTextColor(0.48, 0.45, 0.43)
            else
                blk.wrText:SetFormattedText("%d%%", wr)
                blk.wrText:SetTextColor(0.96, 0.92, 0.90)
                blk.winVal:SetText(tostring(w))
                blk.lossVal:SetText(tostring(l))
                blk.winVal:SetTextColor(0.22, 0.80, 0.22)
                blk.lossVal:SetTextColor(0.80, 0.22, 0.22)
            end

            blk:SetAlpha((not anyFilter or filterBrackets[bi]) and 1.0 or 0.25)
        end
    end
end

RefreshRows = function()
    BuildFilteredList()
    RefreshStats()
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
        row.rowIndex  = i

        row.dateText:SetText(date("%b %d  %H:%M", rec.timestamp or 0))
        row.dateText:SetTextColor(0.65, 0.65, 0.65)

        local out = rec.outcome or "unknown"
        local baseColor  = OUTCOME_BASE[out]  or OUTCOME_BASE.unknown
        local hoverColor = OUTCOME_HOVER[out] or OUTCOME_HOVER.unknown
        row.baseColor  = baseColor
        row.hoverColor = hoverColor
        row.hlTex:SetColorTexture(unpack(baseColor))

        local bName = BRACKET_SHORT[rec.bracketIndex] or AI.BRACKET_NAMES[rec.bracketIndex] or "Unknown"
        row.bracketText:SetText(bName)
        row.bracketText:SetTextColor(0.85, 0.85, 0.85)

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

        local preMMR = rec.prematchMMR or 0
        if preMMR > 0 then
            row.mmrText:SetText(tostring(preMMR + (rec.mmrChange or 0)))
            row.mmrText:SetTextColor(0.75, 0.75, 0.75)
        else
            row.mmrText:SetText("Skirm")
            row.mmrText:SetTextColor(0.35, 0.35, 0.35)
        end

        PopulateTeamIcons(row, rec)

        -- Expand indicator and detail frame
        local isExpanded = (expandedIndex == i)
        if isExpanded then
            row.expandIndicator:SetText("-")
            row.expandIndicator:SetTextColor(0.70, 0.70, 0.70)

            local isSS = rec.bracketIndex == AI.BRACKET_SOLO_SHUFFLE

            -- Build ordered player list: self, then allies (2v2/3v3), then enemies
            local players = {}
            players[1] = {
                specID       = rec.specID,
                isSelf       = true,
                name         = rec.charKey and rec.charKey:match("^(.+)-") or "You",
                damageDone   = rec.damageDone,
                healingDone  = rec.healingDone,
                killingBlows = rec.killingBlows,
                prematchMMR  = rec.prematchMMR,
            }
            if not isSS then
                for _, p in ipairs(rec.allyPlayers or {}) do
                    players[#players + 1] = p
                end
            end
            for _, p in ipairs(rec.enemyPlayers or {}) do
                players[#players + 1] = p
            end

            row.detail.playerData = players
            row.detail.isSS = isSS
            PopulateDetailPlayers(row.detail)
            local playerCount = math.min(#players, 6)

            -- SS per-round comp rows below player list
            local sh = rec.shuffle
            local hasRounds = isSS and sh and sh.rounds and #sh.rounds > 0
            local roundCount = hasRounds and #sh.rounds or 0
            local detailH = DETAIL_PAD_V + DETAIL_HDR_H + playerCount * DETAIL_PLINE_H + DETAIL_PAD_V

            if hasRounds then
                row.detail.wonRoundsText:Hide()
                PopulateRoundRows(row.detail, rec, playerCount)
                detailH = detailH + roundCount * ROUND_ROW_H + 4
            elseif isSS and sh and sh.wonRounds ~= nil then
                -- No per-round state data — show won/lost summary as fallback
                local summaryY = -(DETAIL_PAD_V + DETAIL_HDR_H + playerCount * DETAIL_PLINE_H + 4)
                local won  = sh.wonRounds or 0
                local lost = (sh.totalRounds or 6) - won
                row.detail.wonRoundsText:ClearAllPoints()
                row.detail.wonRoundsText:SetPoint("TOPLEFT", 0, summaryY)
                row.detail.wonRoundsText:SetText(
                    "|cff22cc22" .. won .. " W|r  |cffcc2222" .. lost .. " L|r  (round detail unavailable)")
                row.detail.wonRoundsText:Show()
                detailH = detailH + ROUND_ROW_H
            else
                row.detail.wonRoundsText:Hide()
            end

            row.detail:SetHeight(detailH)
            row.detail:Show()
            row:SetHeight(ROW_H + detailH)
            yOff = yOff + ROW_H + detailH
        else
            row.expandIndicator:SetText("+")
            row.expandIndicator:SetTextColor(0.40, 0.40, 0.40)
            row.detail:Hide()
            row:SetHeight(ROW_H)
            yOff = yOff + ROW_H
        end

        row:Show()
    end

    for i = count + 1, #rowPool do
        rowPool[i]:Hide()
    end

    scrollChild:SetHeight(math.max(yOff, 1))
end

-- ============================================================================
-- Panel creation
-- ============================================================================

function AI.CreateInsightsPanel(parent)
    insightsPanel = parent

    -- Filter bar
    local filterBar = CreateFrame("Frame", nil, parent)
    filterBar:SetHeight(FILTER_H)
    filterBar:SetPoint("TOPLEFT", PAD, -PAD)
    filterBar:SetPoint("TOPRIGHT", -PAD, -PAD)

    local charBtnW  = 170
    local toggleW   = 62
    local toggleH   = FILTER_H - 4
    local toggleGap = 4

    charButton = AI.CreateAIButton(filterBar, "All Characters", charBtnW, toggleH)
    charButton:SetPoint("LEFT", 0, 0)
    charButton.label:ClearAllPoints()
    charButton.label:SetPoint("LEFT", 4, 0)
    charButton.label:SetPoint("RIGHT", -4, 0)
    charButton.label:SetJustifyH("LEFT")
    charButton.label:SetWordWrap(false)
    charButton:SetScript("OnClick", function(self) ShowCharDropdown(self) end)

    local toggleX = charBtnW + 6
    for _, bi in ipairs(AI.TRACKED_BRACKETS) do
        local btn = CreateFrame("Button", nil, filterBar, "BackdropTemplate")
        btn:SetSize(toggleW, toggleH)
        btn:SetPoint("LEFT", toggleX, 0)
        btn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)

        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.label:SetPoint("CENTER")
        btn.label:SetText(BRACKET_SHORT[bi] or AI.BRACKET_NAMES[bi])
        btn.label:SetTextColor(0.7, 0.7, 0.7)

        btn:SetScript("OnClick", function()
            filterBrackets[bi] = not filterBrackets[bi] or nil
            expandedIndex = nil
            UpdateBracketToggles()
            RefreshRows()
            local saved = {}
            for k, v in pairs(filterBrackets) do saved[k] = v end
            ArenaInsightsDB.settings.insightsBracketFilter = saved
        end)
        bracketToggleBtns[bi] = btn
        toggleX = toggleX + toggleW + toggleGap
    end

    countLabel = filterBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLabel:SetPoint("RIGHT", filterBar, "RIGHT", 0, 0)
    countLabel:SetTextColor(0.45, 0.45, 0.45)

    -- Stats bar (W/D/L per bracket, below filter bar)
    local statsBar = CreateFrame("Frame", nil, parent)
    statsBar:SetHeight(STATS_BAR_H)
    statsBar:SetPoint("TOPLEFT", PAD, -(PAD + FILTER_H + GAP))
    statsBar:SetPoint("TOPRIGHT", -PAD, -(PAD + FILTER_H + GAP))

    local bracketCount = #AI.TRACKED_BRACKETS
    for i, bi in ipairs(AI.TRACKED_BRACKETS) do
        local blk = CreateFrame("Frame", nil, statsBar)
        blk:SetHeight(STATS_BAR_H)

        blk.nameText = blk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        blk.nameText:SetPoint("TOPLEFT", 6, -5)
        blk.nameText:SetText(BRACKET_SHORT[bi] or AI.BRACKET_NAMES[bi])
        blk.nameText:SetTextColor(0.55, 0.55, 0.55)

        blk.wrText = blk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        blk.wrText:SetPoint("TOPRIGHT", -8, -5)
        blk.wrText:SetJustifyH("RIGHT")
        blk.wrText:SetText("--")
        blk.wrText:SetTextColor(0.48, 0.45, 0.43)

        -- Two invisible half-panes so Win/Loss can CENTER-anchor regardless of block width
        blk.leftPane = CreateFrame("Frame", nil, blk)
        blk.leftPane:SetPoint("TOPLEFT", 0, -18)
        blk.leftPane:SetPoint("BOTTOMLEFT", 0, 0)

        blk.rightPane = CreateFrame("Frame", nil, blk)
        blk.rightPane:SetPoint("TOPRIGHT", 0, -18)
        blk.rightPane:SetPoint("BOTTOMRIGHT", 0, 0)

        blk.winLbl = blk:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
        blk.winLbl:SetPoint("TOP", blk.leftPane, "TOP", 0, -4)
        blk.winLbl:SetJustifyH("CENTER")
        blk.winLbl:SetText("Win")
        blk.winLbl:SetTextColor(0.40, 0.40, 0.40)

        blk.lossLbl = blk:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
        blk.lossLbl:SetPoint("TOP", blk.rightPane, "TOP", 0, -4)
        blk.lossLbl:SetJustifyH("CENTER")
        blk.lossLbl:SetText("Loss")
        blk.lossLbl:SetTextColor(0.40, 0.40, 0.40)

        blk.winVal = blk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        blk.winVal:SetPoint("TOP", blk.leftPane, "TOP", 0, -15)
        blk.winVal:SetJustifyH("CENTER")
        blk.winVal:SetText("--")
        blk.winVal:SetTextColor(0.48, 0.45, 0.43)

        blk.lossVal = blk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        blk.lossVal:SetPoint("TOP", blk.rightPane, "TOP", 0, -15)
        blk.lossVal:SetJustifyH("CENTER")
        blk.lossVal:SetText("--")
        blk.lossVal:SetTextColor(0.48, 0.45, 0.43)

        if i < bracketCount then
            local sep = blk:CreateTexture(nil, "BORDER")
            sep:SetWidth(1)
            sep:SetPoint("TOPRIGHT", 0, -4)
            sep:SetPoint("BOTTOMRIGHT", 0, 4)
            sep:SetColorTexture(unpack(AI.COLORS.CRIMSON_DIM))
            blk.sepTex = sep
        end

        blk.statData = { w = 0, l = 0, total = 0 }
        bracketStatBlocks[bi] = blk
    end

    statsBar:SetScript("OnSizeChanged", function(self, w)
        local bw = w / 4
        local hw = bw / 2
        for i, bi in ipairs(AI.TRACKED_BRACKETS) do
            local blk = bracketStatBlocks[bi]
            blk:ClearAllPoints()
            blk:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * bw, 0)
            blk:SetWidth(bw)
            blk.leftPane:SetWidth(hw)
            blk.rightPane:SetWidth(hw)
        end
    end)

    -- Separator under stats bar
    local sep1 = parent:CreateTexture(nil, "BORDER")
    sep1:SetHeight(1)
    sep1:SetPoint("TOPLEFT", PAD, -(PAD + FILTER_H + GAP + STATS_BAR_H + GAP))
    sep1:SetPoint("TOPRIGHT", -PAD, -(PAD + FILTER_H + GAP + STATS_BAR_H + GAP))
    sep1:SetColorTexture(unpack(AI.COLORS.CRIMSON_DIM))

    -- Column headers
    local headerRow = CreateFrame("Frame", nil, parent)
    headerRow:SetHeight(HEADER_H)
    headerRow:SetPoint("TOPLEFT", PAD, -(PAD + FILTER_H + GAP + STATS_BAR_H + GAP + 2))
    headerRow:SetPoint("TOPRIGHT", -PAD, -(PAD + FILTER_H + GAP + STATS_BAR_H + GAP + 2))

    local function MkHeader(text, xOff)
        local fs = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
        fs:SetPoint("LEFT", xOff + PAD, 0)
        fs:SetText(text:upper())
        fs:SetTextColor(0.40, 0.40, 0.40)
    end
    MkHeader("Date",    COL_DATE)
    MkHeader("Bracket", COL_BRACKET)
    MkHeader("Change",  COL_DELTA)
    MkHeader("Rating",  COL_RATING)
    MkHeader("MMR",     COL_MMR)
    MkHeader("Team",    COL_TEAM)

    local hlineTop = PAD + FILTER_H + GAP + STATS_BAR_H + GAP + 2 + HEADER_H
    local hline = parent:CreateTexture(nil, "BORDER")
    hline:SetHeight(1)
    hline:SetPoint("TOPLEFT", PAD, -hlineTop)
    hline:SetPoint("TOPRIGHT", -PAD, -hlineTop)
    hline:SetColorTexture(0.18, 0.18, 0.18, 0.8)

    -- Explicit dark background behind scroll area — texture is more reliable than BackdropTemplate
    local scrollTop = hlineTop + 2
    local scrollBgTex = parent:CreateTexture(nil, "BACKGROUND")
    scrollBgTex:SetColorTexture(0.04, 0.04, 0.04, 1.0)
    scrollBgTex:SetPoint("TOPLEFT", PAD, -scrollTop)
    scrollBgTex:SetPoint("BOTTOMRIGHT", -PAD, PAD)

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
        -- Restore saved bracket filter (first open only; preserve in-session changes)
        if next(filterBrackets) == nil then
            local saved = ArenaInsightsDB.settings.insightsBracketFilter
            if saved then
                for k, v in pairs(saved) do filterBrackets[k] = v end
                UpdateBracketToggles()
            end
        end
        if insightsCharKey == nil and AI.currentCharKey then
            local char = ArenaInsightsDB.characters[AI.currentCharKey]
            if char then
                insightsCharKey = AI.currentCharKey
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

function AI.RefreshInsights()
    if not insightsPanel then return end
    RefreshRows()
end
