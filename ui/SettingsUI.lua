local addonName, AI = ...

-- ============================================================================
-- Settings Tab (Story 3-3)
-- ============================================================================

local panel
local accountInput
local arenaSlider, arenaValueText
local outArenaSlider, outArenaValueText
local scaleSlider, scaleValueText
local columnsSlider, columnsValueText
local showMinimapCheckbox
local disableTooltipCheckbox
local groupByRoleCheckbox
local hideZeroCheckbox
local progressBarCheckbox
local titleCheckbox
local bgCheckbox
local lockCheckbox
local overlayToggleBtn
local chartColorBtn

local function Round(val, step)
    return math.floor(val / step + 0.5) * step
end

local function CreateSliderRow(parent, labelText, yOffset, settingsKey, onChange, opts)
    opts = opts or {}
    local minVal  = opts.min or 0
    local maxVal  = opts.max or 1
    local step    = opts.step or 0.05
    local default = opts.default or 1.0
    local fmt     = opts.format or "%.0f%%"
    local fmtMul  = opts.formatMultiplier or 100

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 8, -yOffset)
    label:SetText(labelText)

    local slider = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    slider:SetSize(200, 16)
    slider:SetPoint("TOPLEFT", 10, -(yOffset + 20))
    slider:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    slider:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
    slider:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetOrientation("HORIZONTAL")

    -- Thumb texture
    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(12, 20)
    thumb:SetColorTexture(unpack(AI.COLORS.CRIMSON_BRIGHT))
    slider:SetThumbTexture(thumb)

    local valueText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valueText:SetPoint("LEFT", slider, "RIGHT", 10, 0)
    valueText:SetTextColor(0.8, 0.8, 0.8)

    local initial = ArenaInsightsDB.settings[settingsKey] or default
    slider:SetValue(initial)
    valueText:SetText(string.format(fmt, initial * fmtMul))

    slider:SetScript("OnValueChanged", function(self, value)
        value = Round(value, step)
        ArenaInsightsDB.settings[settingsKey] = value
        valueText:SetText(string.format(fmt, value * fmtMul))
        if onChange then onChange(value) end
    end)

    return slider, valueText
end

local function CreateCheckRow(parent, labelText, yOffset, settingsKey, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", 8, -yOffset)

    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    lbl:SetText(labelText)

    cb:SetScript("OnClick", function(self)
        ArenaInsightsDB.settings[settingsKey] = self:GetChecked()
        if onChange then onChange(self:GetChecked()) end
    end)

    return cb
end

-- ============================================================================
-- Tab system
-- ============================================================================

local TAB_NAMES  = { "General", "Overlay", "History", "Currency", "Import/Export" }
local tabButtons        = {}
local tabContent        = {}
local activeTab         = 1
local currencyCheckboxes = {}

local function SelectTab(idx)
    activeTab = idx
    for i, btn in ipairs(tabButtons) do
        if i == idx then
            btn.label:SetTextColor(unpack(AI.COLORS.CRIMSON_BRIGHT))
            btn.activeLine:Show()
        else
            btn.label:SetTextColor(0.55, 0.52, 0.50)
            btn.activeLine:Hide()
        end
    end
    for i, content in ipairs(tabContent) do
        if i == idx then
            content:Show()
        else
            content:Hide()
        end
    end
end

local function CreateTabStrip(parent, yAnchor)
    local TAB_W = 80
    local TAB_H = 26
    for i, name in ipairs(TAB_NAMES) do
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(TAB_W, TAB_H)
        btn:SetPoint("TOPLEFT", (i - 1) * TAB_W + 8, yAnchor)

        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.label:SetAllPoints()
        btn.label:SetJustifyH("CENTER")
        btn.label:SetText(name)

        -- Bottom active indicator
        btn.activeLine = btn:CreateTexture(nil, "OVERLAY")
        btn.activeLine:SetHeight(2)
        btn.activeLine:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 4, 0)
        btn.activeLine:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -4, 0)
        btn.activeLine:SetColorTexture(unpack(AI.COLORS.CRIMSON_BRIGHT))
        btn.activeLine:Hide()

        local tabIdx = i
        btn:SetScript("OnClick", function() SelectTab(tabIdx) end)
        btn:SetScript("OnEnter", function(self)
            if activeTab ~= tabIdx then
                self.label:SetTextColor(0.78, 0.75, 0.73)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if activeTab ~= tabIdx then
                self.label:SetTextColor(0.55, 0.52, 0.50)
            end
        end)

        tabButtons[i] = btn
    end
end

-- ============================================================================
-- Build content frames
-- ============================================================================

local function BuildOverlayContent(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", 0, 0)

    -- Left column: checkboxes + toggle button
    local leftCol = CreateFrame("Frame", nil, f)
    leftCol:SetPoint("TOPLEFT", 0, 0)
    leftCol:SetPoint("BOTTOMLEFT", 0, 0)
    leftCol:SetWidth(210)

    -- Right column: sliders
    local rightCol = CreateFrame("Frame", nil, f)
    rightCol:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", 8, 0)
    rightCol:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)

    -- Left: checkboxes
    local ly = 8

    bgCheckbox = CreateCheckRow(leftCol, "Show background & border", ly,
        "showOverlayBackground", function()
            if AI.Overlay and AI.Overlay.OnBackgroundChanged then
                AI.Overlay.OnBackgroundChanged()
            end
        end)
    ly = ly + 34

    lockCheckbox = CreateCheckRow(leftCol, "Lock overlay position", ly,
        "overlayLocked", function()
            if AI.Overlay and AI.Overlay.OnLockChanged then
                AI.Overlay.OnLockChanged()
            end
        end)
    ly = ly + 34

    groupByRoleCheckbox = CreateCheckRow(leftCol, "Group by role", ly,
        "overlayGroupByRole", function()
            AI.RefreshOverlay()
        end)
    ly = ly + 34

    hideZeroCheckbox = CreateCheckRow(leftCol, "Hide unrated rows", ly,
        "hideZeroRatingRows", function()
            AI.RefreshOverlay()
        end)
    ly = ly + 34

    progressBarCheckbox = CreateCheckRow(leftCol, "Show progress bar", ly,
        "showOverlayProgressBar", function()
            AI.RefreshOverlay()
        end)
    ly = ly + 34

    titleCheckbox = CreateCheckRow(leftCol, "Show challenge title", ly,
        "showOverlayTitle", function()
            AI.RefreshOverlay()
        end)
    ly = ly + 42

    overlayToggleBtn = AI.CreateAIButton(leftCol, "Show Overlay", 140, 28)
    overlayToggleBtn:SetPoint("TOPLEFT", 10, -ly)
    overlayToggleBtn:SetScript("OnClick", function()
        if AI.Overlay and AI.Overlay.Toggle then
            AI.Overlay.Toggle()
        end
        if ArenaInsightsDB.settings.showOverlay then
            overlayToggleBtn.label:SetText("Hide Overlay")
        else
            overlayToggleBtn.label:SetText("Show Overlay")
        end
    end)

    -- Right: sliders
    local ry = 8

    arenaSlider, arenaValueText = CreateSliderRow(rightCol, "Opacity (In Arena)", ry,
        "opacityInArena", function()
            if AI.Overlay and AI.Overlay.OnOpacityChanged then
                AI.Overlay.OnOpacityChanged()
            end
        end)
    ry = ry + 56

    outArenaSlider, outArenaValueText = CreateSliderRow(rightCol, "Opacity (Out of Arena)", ry,
        "opacityOutOfArena", function()
            if AI.Overlay and AI.Overlay.OnOpacityChanged then
                AI.Overlay.OnOpacityChanged()
            end
        end)
    ry = ry + 56

    scaleSlider, scaleValueText = CreateSliderRow(rightCol, "Scale", ry,
        "overlayScale", function()
            if AI.Overlay and AI.Overlay.OnScaleChanged then
                AI.Overlay.OnScaleChanged()
            end
        end, { min = 0.5, max = 2.0, step = 0.05, default = 1.0 })
    ry = ry + 56

    columnsSlider, columnsValueText = CreateSliderRow(rightCol, "Columns", ry,
        "overlayColumns", function()
            AI.RefreshOverlay()
        end, { min = 1, max = 10, step = 1, default = 1, format = "%d", formatMultiplier = 1 })

    return f
end

local function BuildHistoryContent(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", 0, 0)

    local y = 8

    local chartLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chartLabel:SetPoint("TOPLEFT", 8, -y)
    chartLabel:SetText("Chart Line Color")
    y = y + 18

    chartColorBtn = AI.CreateAIButton(f, "Default (Crimson)", 180, 24)
    chartColorBtn:SetPoint("TOPLEFT", 10, -y)

    local function UpdateChartColorLabel()
        local val = ArenaInsightsDB.settings.chartColor or "default"
        if val == "class" then
            chartColorBtn.label:SetText("Class Color")
        else
            chartColorBtn.label:SetText("Default (Crimson)")
        end
    end

    chartColorBtn:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            rootDescription:CreateButton("Default (Crimson)", function()
                ArenaInsightsDB.settings.chartColor = "default"
                UpdateChartColorLabel()
                if AI.RefreshHistoryGraph then AI.RefreshHistoryGraph() end
            end)
            rootDescription:CreateButton("Class Color", function()
                ArenaInsightsDB.settings.chartColor = "class"
                UpdateChartColorLabel()
                if AI.RefreshHistoryGraph then AI.RefreshHistoryGraph() end
            end)
        end)
    end)

    -- Store for OnShow refresh
    f.UpdateChartColorLabel = UpdateChartColorLabel

    return f
end

local function BuildGeneralContent(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", 0, 0)

    local y = 8

    -- Account Name
    local accLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    accLabel:SetPoint("TOPLEFT", 8, -y)
    accLabel:SetText("Account Name")
    y = y + 18

    accountInput = AI.CreateAIInput(f, 200, 24)
    accountInput:SetPoint("TOPLEFT", 10, -y)

    local saveAccBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    saveAccBtn:SetSize(60, 24)
    saveAccBtn:SetPoint("LEFT", accountInput, "RIGHT", 8, 0)
    saveAccBtn:SetText("Save")
    saveAccBtn:SetNormalFontObject("GameFontNormalSmall")

    local accStatus = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    accStatus:SetPoint("LEFT", saveAccBtn, "RIGHT", 8, 0)
    accStatus:SetTextColor(0.3, 1, 0.3)

    saveAccBtn:SetScript("OnClick", function()
        ArenaInsightsDB.settings.accountName = accountInput:GetText()
        accStatus:SetText("Saved")
        C_Timer.After(2, function() accStatus:SetText("") end)
    end)

    y = y + 36

    -- Divider
    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -y)
    divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -y)
    divider:SetColorTexture(unpack(AI.COLORS.CRIMSON_DIM))
    y = y + 14

    -- Party Sync header
    local syncHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    syncHeader:SetPoint("TOPLEFT", 8, -y)
    syncHeader:SetText("Party Sync")
    syncHeader:SetTextColor(0.96, 0.92, 0.90)
    y = y + 20

    -- Description
    local syncDesc = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    syncDesc:SetPoint("TOPLEFT", 10, -y)
    syncDesc:SetWidth(460)
    syncDesc:SetJustifyH("LEFT")
    syncDesc:SetWordWrap(true)
    syncDesc:SetNonSpaceWrap(false)
    syncDesc:SetTextColor(0.78, 0.75, 0.73)
    syncDesc:SetText(
        "Merges character rating data across all ArenaInsights accounts in your party.\n" ..
        "Designed for multi-account play — join a party with your alt account, press\n" ..
        "Sync, and both accounts end up with the combined data. Newer ratings win."
    )
    y = y + 52

    -- Sync button
    local syncBtn = AI.CreateAIButton(f, "Sync", 80, 24)
    syncBtn:SetPoint("TOPLEFT", 10, -y)
    syncBtn:SetScript("OnClick", function()
        if AI.InitiateSync then
            AI.InitiateSync()
        end
    end)
    y = y + 32

    -- Status text (updated by AI.UpdateSyncStatusUI in Sync.lua)
    local syncStatusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    syncStatusText:SetPoint("TOPLEFT", 10, -y)
    syncStatusText:SetText("")
    syncStatusText:SetTextColor(0.78, 0.75, 0.73)
    AI._syncStatusText = syncStatusText
    y = y + 28

    -- Divider
    local divider2 = f:CreateTexture(nil, "ARTWORK")
    divider2:SetHeight(1)
    divider2:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -y)
    divider2:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -y)
    divider2:SetColorTexture(unpack(AI.COLORS.CRIMSON_DIM))
    y = y + 14

    local currencyHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    currencyHeader:SetPoint("TOPLEFT", 8, -y)
    currencyHeader:SetText("Currency")
    currencyHeader:SetTextColor(0.96, 0.92, 0.90)
    y = y + 28

    showMinimapCheckbox = CreateCheckRow(f, "Show minimap button", y,
        "showMinimapButton", function(checked)
            local LDBIcon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)
            if LDBIcon then
                if checked then
                    LDBIcon:Show("ArenaInsights")
                else
                    LDBIcon:Hide("ArenaInsights")
                end
            end
        end)
    y = y + 34

    disableTooltipCheckbox = CreateCheckRow(f, "Disable currency tooltip", y,
        "disableTooltip", nil)

    return f
end

local function BuildCurrencySettingsContent(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", 0, 0)

    local y = 8

    local function SectionHeader(text)
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", 8, -y)
        lbl:SetText(text)
        lbl:SetTextColor(0.96, 0.92, 0.90)
        y = y + 24
    end

    local function Divider()
        local div = f:CreateTexture(nil, "ARTWORK")
        div:SetHeight(1)
        div:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -y)
        div:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -y)
        div:SetColorTexture(unpack(AI.COLORS.CRIMSON_DIM))
        y = y + 14
    end

    SectionHeader("Currencies")
    for _, entry in ipairs(AI.TRACKED_CURRENCIES) do
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", 8, -y)

        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        lbl:SetText(entry.name)

        local entryId = entry.id
        cb:SetScript("OnClick", function(self)
            ArenaInsightsDB.settings.hiddenCurrencies = ArenaInsightsDB.settings.hiddenCurrencies or {}
            if not self:GetChecked() then
                ArenaInsightsDB.settings.hiddenCurrencies[entryId] = true
            else
                ArenaInsightsDB.settings.hiddenCurrencies[entryId] = nil
            end
            if AI.RefreshCurrencyPanel then AI.RefreshCurrencyPanel() end
        end)

        table.insert(currencyCheckboxes, { cb = cb, ctype = "currency", id = entryId })
        y = y + 34
    end

    Divider()
    SectionHeader("Items")
    for _, item in ipairs(AI.TRACKED_ITEMS) do
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", 8, -y)

        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        lbl:SetText(item.name)

        local itemId = item.id
        cb:SetScript("OnClick", function(self)
            ArenaInsightsDB.settings.hiddenItems = ArenaInsightsDB.settings.hiddenItems or {}
            if not self:GetChecked() then
                ArenaInsightsDB.settings.hiddenItems[itemId] = true
            else
                ArenaInsightsDB.settings.hiddenItems[itemId] = nil
            end
            if AI.RefreshCurrencyPanel then AI.RefreshCurrencyPanel() end
        end)

        table.insert(currencyCheckboxes, { cb = cb, ctype = "item", id = itemId })
        y = y + 34
    end

    f.RefreshChecks = function()
        local s = ArenaInsightsDB and ArenaInsightsDB.settings or {}
        for _, entry in ipairs(currencyCheckboxes) do
            local isHidden = false
            if entry.ctype == "currency" then
                isHidden = s.hiddenCurrencies and s.hiddenCurrencies[entry.id]
            else
                isHidden = s.hiddenItems and s.hiddenItems[entry.id]
            end
            entry.cb:SetChecked(not isHidden)
        end
    end

    return f
end

local function BuildImportExportContent(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", 0, 0)
    AI.CreateImportExportPanel(f)
    return f
end

-- ============================================================================
-- Public: create settings panel
-- ============================================================================

function AI.CreateSettingsPanel(parent)
    if panel then return panel end

    panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Settings")
    title:SetTextColor(unpack(AI.COLORS.GOLD))

    -- Tab strip (below title)
    local TAB_H = 26
    local TAB_Y = -30  -- from top of panel
    CreateTabStrip(panel, TAB_Y)

    -- Divider line below tab strip
    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, TAB_Y - TAB_H)
    divider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, TAB_Y - TAB_H)
    divider:SetColorTexture(unpack(AI.COLORS.CRIMSON_DIM))

    -- Content area below tab strip + divider
    local contentFrame = CreateFrame("Frame", nil, panel)
    contentFrame:SetPoint("TOPLEFT", 0, TAB_Y - TAB_H - 4)
    contentFrame:SetPoint("BOTTOMRIGHT", 0, 0)

    tabContent[1] = BuildGeneralContent(contentFrame)
    tabContent[2] = BuildOverlayContent(contentFrame)
    tabContent[3] = BuildHistoryContent(contentFrame)
    tabContent[4] = BuildCurrencySettingsContent(contentFrame)
    tabContent[5] = BuildImportExportContent(contentFrame)

    -- Default to General tab
    SelectTab(1)

    panel:SetScript("OnShow", function()
        -- Overlay tab state
        arenaSlider:SetValue(ArenaInsightsDB.settings.opacityInArena or 1.0)
        outArenaSlider:SetValue(ArenaInsightsDB.settings.opacityOutOfArena or 1.0)
        scaleSlider:SetValue(ArenaInsightsDB.settings.overlayScale or 1.0)
        columnsSlider:SetValue(ArenaInsightsDB.settings.overlayColumns or 1)
        bgCheckbox:SetChecked(ArenaInsightsDB.settings.showOverlayBackground)
        lockCheckbox:SetChecked(ArenaInsightsDB.settings.overlayLocked or false)
        groupByRoleCheckbox:SetChecked(ArenaInsightsDB.settings.overlayGroupByRole or false)
        hideZeroCheckbox:SetChecked(ArenaInsightsDB.settings.hideZeroRatingRows or false)
        progressBarCheckbox:SetChecked(ArenaInsightsDB.settings.showOverlayProgressBar or false)
        titleCheckbox:SetChecked(ArenaInsightsDB.settings.showOverlayTitle or false)
        if ArenaInsightsDB.settings.showOverlay then
            overlayToggleBtn.label:SetText("Hide Overlay")
        else
            overlayToggleBtn.label:SetText("Show Overlay")
        end
        -- History tab state
        tabContent[3].UpdateChartColorLabel()
        -- Currency settings tab state
        tabContent[4].RefreshChecks()
        -- General tab state
        accountInput:SetText(ArenaInsightsDB.settings.accountName or "")
        showMinimapCheckbox:SetChecked(ArenaInsightsDB.settings.showMinimapButton ~= false)
        disableTooltipCheckbox:SetChecked(ArenaInsightsDB.settings.disableTooltip or false)
    end)

    return panel
end
