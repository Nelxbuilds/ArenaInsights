local addonName, NXR = ...

-- ============================================================================
-- Settings Tab (Story 3-3)
-- ============================================================================

local panel
local accountInput
local arenaSlider, arenaValueText
local outArenaSlider, outArenaValueText
local scaleSlider, scaleValueText
local columnsSlider, columnsValueText
local groupByRoleCheckbox
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
    thumb:SetColorTexture(unpack(NXR.COLORS.CRIMSON_BRIGHT))
    slider:SetThumbTexture(thumb)

    local valueText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valueText:SetPoint("LEFT", slider, "RIGHT", 10, 0)
    valueText:SetTextColor(0.8, 0.8, 0.8)

    local initial = NelxRatedDB.settings[settingsKey] or default
    slider:SetValue(initial)
    valueText:SetText(string.format(fmt, initial * fmtMul))

    slider:SetScript("OnValueChanged", function(self, value)
        value = Round(value, step)
        NelxRatedDB.settings[settingsKey] = value
        valueText:SetText(string.format(fmt, value * fmtMul))
        if onChange then onChange(value) end
    end)

    return slider, valueText
end

function NXR.CreateSettingsPanel(parent)
    if panel then return panel end

    panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Settings")
    title:SetTextColor(unpack(NXR.COLORS.GOLD))

    local y = 40

    -- ----------------------------------------------------------------
    -- Account name
    -- ----------------------------------------------------------------
    local accLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    accLabel:SetPoint("TOPLEFT", 8, -y)
    accLabel:SetText("Account Name")
    y = y + 18

    accountInput = NXR.CreateNXRInput(panel, 200, 24)
    accountInput:SetPoint("TOPLEFT", 10, -y)

    local saveAccBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    saveAccBtn:SetSize(60, 24)
    saveAccBtn:SetPoint("LEFT", accountInput, "RIGHT", 8, 0)
    saveAccBtn:SetText("Save")
    saveAccBtn:SetNormalFontObject("GameFontNormalSmall")

    local accStatus = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    accStatus:SetPoint("LEFT", saveAccBtn, "RIGHT", 8, 0)
    accStatus:SetTextColor(0.3, 1, 0.3)

    saveAccBtn:SetScript("OnClick", function()
        NelxRatedDB.settings.accountName = accountInput:GetText()
        accStatus:SetText("Saved")
        C_Timer.After(2, function() accStatus:SetText("") end)
    end)

    y = y + 40

    -- ----------------------------------------------------------------
    -- Opacity: In Arena
    -- ----------------------------------------------------------------
    arenaSlider, arenaValueText = CreateSliderRow(panel, "Overlay Opacity (In Arena)", y,
        "opacityInArena", function()
            if NXR.Overlay and NXR.Overlay.OnOpacityChanged then
                NXR.Overlay.OnOpacityChanged()
            end
        end)
    y = y + 56

    -- ----------------------------------------------------------------
    -- Opacity: Out of Arena
    -- ----------------------------------------------------------------
    outArenaSlider, outArenaValueText = CreateSliderRow(panel, "Overlay Opacity (Out of Arena)", y,
        "opacityOutOfArena", function()
            if NXR.Overlay and NXR.Overlay.OnOpacityChanged then
                NXR.Overlay.OnOpacityChanged()
            end
        end)
    y = y + 56

    -- ----------------------------------------------------------------
    -- Overlay Scale
    -- ----------------------------------------------------------------
    scaleSlider, scaleValueText = CreateSliderRow(panel, "Overlay Scale", y,
        "overlayScale", function(value)
            if NXR.Overlay and NXR.Overlay.OnScaleChanged then
                NXR.Overlay.OnScaleChanged()
            end
        end, { min = 0.5, max = 2.0, step = 0.05, default = 1.0 })
    y = y + 56

    -- ----------------------------------------------------------------
    -- Overlay Columns (Story 9-4)
    -- ----------------------------------------------------------------
    columnsSlider, columnsValueText = CreateSliderRow(panel, "Overlay Columns", y,
        "overlayColumns", function()
            NXR.RefreshOverlay()
        end, { min = 1, max = 10, step = 1, default = 1, format = "%d", formatMultiplier = 1 })
    y = y + 56

    -- ----------------------------------------------------------------
    -- Group by Role (Story 9-5)
    -- ----------------------------------------------------------------
    groupByRoleCheckbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    groupByRoleCheckbox:SetSize(26, 26)
    groupByRoleCheckbox:SetPoint("TOPLEFT", 8, -y)

    local groupLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    groupLabel:SetPoint("LEFT", groupByRoleCheckbox, "RIGHT", 4, 0)
    groupLabel:SetText("Group overlay by role")

    groupByRoleCheckbox:SetScript("OnClick", function(self)
        NelxRatedDB.settings.overlayGroupByRole = self:GetChecked()
        NXR.RefreshOverlay()
    end)

    y = y + 34

    -- ----------------------------------------------------------------
    -- Show overlay background
    -- ----------------------------------------------------------------
    bgCheckbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    bgCheckbox:SetSize(26, 26)
    bgCheckbox:SetPoint("TOPLEFT", 8, -y)

    local bgLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bgLabel:SetPoint("LEFT", bgCheckbox, "RIGHT", 4, 0)
    bgLabel:SetText("Show overlay background & border")

    bgCheckbox:SetScript("OnClick", function(self)
        NelxRatedDB.settings.showOverlayBackground = self:GetChecked()
        if NXR.Overlay and NXR.Overlay.OnBackgroundChanged then
            NXR.Overlay.OnBackgroundChanged()
        end
    end)

    y = y + 34

    -- ----------------------------------------------------------------
    -- Lock overlay checkbox
    -- ----------------------------------------------------------------
    lockCheckbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    lockCheckbox:SetSize(26, 26)
    lockCheckbox:SetPoint("TOPLEFT", 8, -y)

    local lockLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lockLabel:SetPoint("LEFT", lockCheckbox, "RIGHT", 4, 0)
    lockLabel:SetText("Lock overlay position")

    lockCheckbox:SetScript("OnClick", function(self)
        NelxRatedDB.settings.overlayLocked = self:GetChecked()
        if NXR.Overlay and NXR.Overlay.OnLockChanged then
            NXR.Overlay.OnLockChanged()
        end
    end)

    y = y + 34

    -- ----------------------------------------------------------------
    -- Show / Hide overlay button
    -- ----------------------------------------------------------------
    overlayToggleBtn = NXR.CreateNXRButton(panel, "Show Overlay", 140, 28)
    overlayToggleBtn:SetPoint("TOPLEFT", 10, -y)
    overlayToggleBtn:SetScript("OnClick", function()
        if NXR.Overlay and NXR.Overlay.Toggle then
            NXR.Overlay.Toggle()
        end
        -- Update button text
        if NelxRatedDB.settings.showOverlay then
            overlayToggleBtn.label:SetText("Hide Overlay")
        else
            overlayToggleBtn.label:SetText("Show Overlay")
        end
    end)

    -- ----------------------------------------------------------------
    -- Graph section
    -- ----------------------------------------------------------------
    y = y + 16

    local graphHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    graphHeader:SetPoint("TOPLEFT", 8, -y)
    graphHeader:SetText("Graph")
    graphHeader:SetTextColor(unpack(NXR.COLORS.GOLD))
    y = y + 24

    local chartLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chartLabel:SetPoint("TOPLEFT", 8, -y)
    chartLabel:SetText("Chart Line Color")
    y = y + 18

    chartColorBtn = NXR.CreateNXRButton(panel, "Default (Crimson)", 180, 24)
    chartColorBtn:SetPoint("TOPLEFT", 10, -y)

    local function UpdateChartColorLabel()
        local val = NelxRatedDB.settings.chartColor or "default"
        if val == "class" then
            chartColorBtn.label:SetText("Class Color")
        else
            chartColorBtn.label:SetText("Default (Crimson)")
        end
    end

    chartColorBtn:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, rootDescription)
            rootDescription:CreateButton("Default (Crimson)", function()
                NelxRatedDB.settings.chartColor = "default"
                UpdateChartColorLabel()
                if NXR.RefreshHistoryGraph then NXR.RefreshHistoryGraph() end
            end)
            rootDescription:CreateButton("Class Color", function()
                NelxRatedDB.settings.chartColor = "class"
                UpdateChartColorLabel()
                if NXR.RefreshHistoryGraph then NXR.RefreshHistoryGraph() end
            end)
        end)
    end)

    y = y + 40

    -- Populate on show
    panel:SetScript("OnShow", function()
        accountInput:SetText(NelxRatedDB.settings.accountName or "")
        arenaSlider:SetValue(NelxRatedDB.settings.opacityInArena or 1.0)
        outArenaSlider:SetValue(NelxRatedDB.settings.opacityOutOfArena or 1.0)
        scaleSlider:SetValue(NelxRatedDB.settings.overlayScale or 1.0)
        columnsSlider:SetValue(NelxRatedDB.settings.overlayColumns or 1)
        groupByRoleCheckbox:SetChecked(NelxRatedDB.settings.overlayGroupByRole or false)
        bgCheckbox:SetChecked(NelxRatedDB.settings.showOverlayBackground)
        lockCheckbox:SetChecked(NelxRatedDB.settings.overlayLocked or false)
        if NelxRatedDB.settings.showOverlay then
            overlayToggleBtn.label:SetText("Hide Overlay")
        else
            overlayToggleBtn.label:SetText("Show Overlay")
        end
        UpdateChartColorLabel()
    end)

    return panel
end
