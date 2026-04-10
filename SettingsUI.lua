local addonName, NXR = ...

-- ============================================================================
-- Settings Tab (Story 3-3)
-- ============================================================================

local panel
local accountInput
local arenaSlider, arenaValueText
local outArenaSlider, outArenaValueText
local bgCheckbox
local lockCheckbox
local overlayToggleBtn

local function Round(val, step)
    return math.floor(val / step + 0.5) * step
end

local function CreateSliderRow(parent, labelText, yOffset, settingsKey, onChange)
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
    slider:SetMinMaxValues(0, 1)
    slider:SetValueStep(0.05)
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

    local initial = NelxRatedDB.settings[settingsKey] or 1.0
    slider:SetValue(initial)
    valueText:SetText(string.format("%.0f%%", initial * 100))

    slider:SetScript("OnValueChanged", function(self, value)
        value = Round(value, 0.05)
        NelxRatedDB.settings[settingsKey] = value
        valueText:SetText(string.format("%.0f%%", value * 100))
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

    -- Populate on show
    panel:SetScript("OnShow", function()
        accountInput:SetText(NelxRatedDB.settings.accountName or "")
        arenaSlider:SetValue(NelxRatedDB.settings.opacityInArena or 1.0)
        outArenaSlider:SetValue(NelxRatedDB.settings.opacityOutOfArena or 1.0)
        bgCheckbox:SetChecked(NelxRatedDB.settings.showOverlayBackground)
        lockCheckbox:SetChecked(NelxRatedDB.settings.overlayLocked or false)
        if NelxRatedDB.settings.showOverlay then
            overlayToggleBtn.label:SetText("Hide Overlay")
        else
            overlayToggleBtn.label:SetText("Show Overlay")
        end
    end)

    return panel
end
