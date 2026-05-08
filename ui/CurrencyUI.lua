local addonName, AI = ...

local ROW_HEIGHT = 28
local ROW_GAP    = 2
local HEADER_H   = 24
local HBAR_H     = 14

local COL_CHAR_W     = 140
local COL_CURRENCY_W = 68
local COL_ITEM_W     = 108

local sortKey      = "char"
local sortAsc      = true
local currPanel    = nil
local hScrollFrame = nil
local hScrollChild = nil
local vScrollFrame = nil
local scrollChild  = nil
local hBar         = nil
local headerFrame  = nil
local rows         = {}
local emptyLabel   = nil
local headerBtns   = {}  -- keyed by col.key

-- All possible columns (built once at load time; filtered at runtime)
local ALL_COLUMNS = { { key = "char", label = "Character" } }
for _, c in ipairs(AI.TRACKED_CURRENCIES) do
    table.insert(ALL_COLUMNS, { key = "currency_" .. c.id, label = c.name, currencyId = c.id })
end
for _, item in ipairs(AI.TRACKED_ITEMS) do
    table.insert(ALL_COLUMNS, { key = "item_" .. item.id, label = item.name, itemId = item.id })
end

local function GetColWidth(col)
    if col.key == "char" then return COL_CHAR_W end
    if col.itemId then return COL_ITEM_W end
    return COL_CURRENCY_W
end

local function GetVisibleColumns()
    local result = {}
    local s = ArenaInsightsDB and ArenaInsightsDB.settings
    for _, col in ipairs(ALL_COLUMNS) do
        local hidden = false
        if col.currencyId and s and s.hiddenCurrencies then
            hidden = s.hiddenCurrencies[col.currencyId]
        elseif col.itemId and s and s.hiddenItems then
            hidden = s.hiddenItems[col.itemId]
        end
        if not hidden then
            table.insert(result, col)
        end
    end
    return result
end

local function GetTotalWidth(cols)
    local w = 0
    for _, col in ipairs(cols) do w = w + GetColWidth(col) end
    return w
end

local function GetCharValue(char, col)
    if col.currencyId then
        local c = char.currencies and char.currencies[col.currencyId]
        if c then return c.amount or 0 end
    elseif col.itemId then
        local it = char.items and char.items[col.itemId]
        if it then return it.count or 0 end
    end
    return nil
end

local function HasAnyCurrencyData(characters)
    for _, char in pairs(characters) do
        if char.currencies or char.items then return true end
    end
    return false
end

local function UpdateHeaderHighlights()
    for key, btn in pairs(headerBtns) do
        if key == sortKey then
            btn.label:SetTextColor(unpack(AI.COLORS.CRIMSON_BRIGHT))
        else
            btn.label:SetTextColor(0.7, 0.7, 0.7)
        end
    end
end

local function UpdateHBar(totalW)
    if not hScrollFrame or not hBar then return end
    local viewW = hScrollFrame:GetWidth() or 0
    if viewW == 0 then return end
    local maxScroll = math.max(0, totalW - viewW)
    hBar:SetMinMaxValues(0, maxScroll)
    if maxScroll <= 0 then
        hScrollFrame:SetHorizontalScroll(0)
        hBar:Hide()
    else
        hBar:Show()
    end
end

local function Refresh()
    if not scrollChild then return end
    for _, row in ipairs(rows) do row:Hide() end

    local characters = ArenaInsightsDB and ArenaInsightsDB.characters or {}
    local visibleCols = GetVisibleColumns()
    local totalW = GetTotalWidth(visibleCols)

    -- Visibility set for O(1) lookup
    local visibleSet = {}
    for _, col in ipairs(visibleCols) do visibleSet[col.key] = true end

    -- Reposition / hide header buttons
    local hxOff = 0
    for _, col in ipairs(ALL_COLUMNS) do
        local btn = headerBtns[col.key]
        if btn then
            if visibleSet[col.key] then
                local w = GetColWidth(col)
                btn:ClearAllPoints()
                btn:SetWidth(w)
                btn:SetPoint("LEFT", headerFrame, "LEFT", hxOff, 0)
                btn:Show()
                hxOff = hxOff + w
            else
                btn:Hide()
            end
        end
    end

    -- Update table widths and scrollbar
    headerFrame:SetWidth(math.max(totalW, 1))
    hScrollChild:SetWidth(math.max(totalW, 1))
    scrollChild:SetWidth(math.max(totalW, 1))
    UpdateHBar(totalW)

    if not HasAnyCurrencyData(characters) then
        emptyLabel:Show()
        scrollChild:SetHeight(1)
        return
    end
    emptyLabel:Hide()

    -- Collect and sort character keys
    local keys = {}
    for k in pairs(characters) do
        local hidden = ArenaInsightsDB.settings and
            ArenaInsightsDB.settings.hiddenCharacters and
            ArenaInsightsDB.settings.hiddenCharacters[k]
        if not hidden then table.insert(keys, k) end
    end
    table.sort(keys, function(a, b)
        if sortKey == "char" then
            local va, vb = a:lower(), b:lower()
            if sortAsc then return va < vb else return va > vb end
        end
        local valA, valB = -1, -1
        for _, col in ipairs(visibleCols) do
            if col.key == sortKey then
                valA = GetCharValue(characters[a], col) or -1
                valB = GetCharValue(characters[b], col) or -1
                break
            end
        end
        if sortAsc then return valA < valB else return valA > valB end
    end)

    local yOff = 0
    for i, key in ipairs(keys) do
        local char = characters[key]

        if not rows[i] then
            local row = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
            row:SetHeight(ROW_HEIGHT)
            row:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            row.cols = {}
            for _, col in ipairs(ALL_COLUMNS) do
                local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                fs:SetJustifyH(col.key == "char" and "LEFT" or "CENTER")
                row.cols[col.key] = fs
            end
            rows[i] = row
        end

        local row = rows[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOff)
        row:SetWidth(totalW)

        if i % 2 == 0 then
            row:SetBackdropColor(0.12, 0.12, 0.12, 0.5)
        else
            row:SetBackdropColor(0.08, 0.08, 0.08, 0.5)
        end
        row:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.3)

        -- Position visible cells, hide invisible, set values
        local rxOff = 0
        for _, col in ipairs(ALL_COLUMNS) do
            local fs = row.cols[col.key]
            if fs then
                if visibleSet[col.key] then
                    local w = GetColWidth(col)
                    local padL = (col.key == "char") and 8 or 4
                    fs:ClearAllPoints()
                    fs:SetPoint("LEFT", row, "LEFT", rxOff + padL, 0)
                    fs:SetWidth(w - padL - 4)

                    if col.key == "char" then
                        fs:SetText(key)
                        if char.classFileName and RAID_CLASS_COLORS and RAID_CLASS_COLORS[char.classFileName] then
                            local cc = RAID_CLASS_COLORS[char.classFileName]
                            fs:SetTextColor(cc.r, cc.g, cc.b)
                        else
                            fs:SetTextColor(0.8, 0.8, 0.8)
                        end
                    else
                        local val = GetCharValue(char, col)
                        if val ~= nil then
                            fs:SetText(tostring(val))
                            fs:SetTextColor(1, 1, 1)
                        else
                            fs:SetText("--")
                            fs:SetTextColor(0.4, 0.4, 0.4)
                        end
                    end

                    fs:Show()
                    rxOff = rxOff + w
                else
                    fs:Hide()
                end
            end
        end

        row:Show()
        yOff = yOff + ROW_HEIGHT + ROW_GAP
    end

    for j = #keys + 1, #rows do rows[j]:Hide() end
    scrollChild:SetHeight(math.max(yOff, 1))
end

function AI.RefreshCurrencyPanel()
    if currPanel and currPanel:IsShown() then Refresh() end
end

function AI.CreateCurrencyPanel(parent)
    if currPanel then return currPanel end

    currPanel = CreateFrame("Frame", nil, parent)
    currPanel:SetAllPoints()

    -- Title
    local title = currPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Currency")
    title:SetTextColor(unpack(AI.COLORS.GOLD))

    -- Empty state label
    emptyLabel = currPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyLabel:SetPoint("CENTER", 0, 0)
    emptyLabel:SetText("No data -- play a game or reload")
    emptyLabel:SetTextColor(0.55, 0.55, 0.55)
    emptyLabel:SetJustifyH("CENTER")
    emptyLabel:Hide()

    -- Horizontal scrollbar (reserved space at bottom)
    hBar = CreateFrame("Slider", nil, currPanel, "BackdropTemplate")
    hBar:SetPoint("BOTTOMLEFT", currPanel, "BOTTOMLEFT", 0, 4)
    hBar:SetPoint("BOTTOMRIGHT", currPanel, "BOTTOMRIGHT", 0, 4)
    hBar:SetHeight(HBAR_H)
    hBar:SetOrientation("HORIZONTAL")
    hBar:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    hBar:SetBackdropColor(0.06, 0.04, 0.04, 0.9)
    hBar:SetBackdropBorderColor(unpack(AI.COLORS.CRIMSON_DIM))
    hBar:SetMinMaxValues(0, 0)
    hBar:SetValue(0)
    local thumb = hBar:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(40, HBAR_H - 4)
    thumb:SetColorTexture(unpack(AI.COLORS.CRIMSON_DIM))
    hBar:SetThumbTexture(thumb)
    hBar:SetScript("OnValueChanged", function(self, val)
        if hScrollFrame then hScrollFrame:SetHorizontalScroll(val) end
    end)
    hBar:Hide()

    -- Horizontal scroll frame (below title, above hbar)
    hScrollFrame = CreateFrame("ScrollFrame", nil, currPanel)
    hScrollFrame:SetPoint("TOPLEFT", 0, -32)
    hScrollFrame:SetPoint("BOTTOMRIGHT", 0, HBAR_H + 8)
    hScrollFrame:EnableMouseWheel(true)
    hScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        if IsShiftKeyDown() then
            local cur = hScrollFrame:GetHorizontalScroll()
            local _, maxH = hBar:GetMinMaxValues()
            hBar:SetValue(math.max(0, math.min(cur - delta * 40, maxH)))
        else
            local cur = vScrollFrame:GetVerticalScroll()
            local maxV = vScrollFrame:GetVerticalScrollRange()
            vScrollFrame:SetVerticalScroll(math.max(0, math.min(cur - delta * 40, maxV)))
        end
    end)

    -- Horizontal scroll child (sized to table width; height tracks scroll frame)
    hScrollChild = CreateFrame("Frame", nil, hScrollFrame)
    hScrollFrame:SetScrollChild(hScrollChild)
    hScrollChild:SetWidth(1)
    hScrollChild:SetHeight(1)
    hScrollFrame:SetScript("OnSizeChanged", function(self, w, h)
        hScrollChild:SetHeight(h)
        Refresh()
    end)

    -- Header frame inside hScrollChild
    headerFrame = CreateFrame("Frame", nil, hScrollChild, "BackdropTemplate")
    headerFrame:SetPoint("TOPLEFT", hScrollChild, "TOPLEFT", 0, 0)
    headerFrame:SetHeight(HEADER_H)
    headerFrame:SetWidth(1)
    headerFrame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    headerFrame:SetBackdropColor(0.06, 0.04, 0.04, 0.9)
    headerFrame:SetBackdropBorderColor(unpack(AI.COLORS.CRIMSON_DIM))

    -- Header buttons for all columns (positioned/hidden in Refresh)
    for _, col in ipairs(ALL_COLUMNS) do
        local w = GetColWidth(col)
        local btn = CreateFrame("Button", nil, headerFrame)
        btn:SetHeight(HEADER_H)
        btn:SetWidth(w)
        btn.colKey = col.key

        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.label:SetPoint("CENTER")
        btn.label:SetText(col.label)
        btn.label:SetTextColor(0.7, 0.7, 0.7)

        btn:SetScript("OnClick", function()
            if sortKey == col.key then
                sortAsc = not sortAsc
            else
                sortKey = col.key
                sortAsc = true
            end
            UpdateHeaderHighlights()
            Refresh()
        end)
        btn:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1) end)
        btn:SetScript("OnLeave", function(self) UpdateHeaderHighlights() end)

        headerBtns[col.key] = btn
    end
    UpdateHeaderHighlights()

    -- Vertical scroll frame inside hScrollChild (below header)
    vScrollFrame = CreateFrame("ScrollFrame", nil, hScrollChild)
    vScrollFrame:SetPoint("TOPLEFT", hScrollChild, "TOPLEFT", 0, -(HEADER_H + 2))
    vScrollFrame:SetPoint("BOTTOMRIGHT", hScrollChild, "BOTTOMRIGHT", 0, 0)

    scrollChild = CreateFrame("Frame", nil, vScrollFrame)
    vScrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetHeight(1)
    scrollChild:SetWidth(1)

    currPanel:SetScript("OnShow", function() Refresh() end)

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    eventFrame:SetScript("OnEvent", function()
        if currPanel and currPanel:IsShown() then Refresh() end
    end)

    function currPanel:Refresh() Refresh() end

    return currPanel
end
