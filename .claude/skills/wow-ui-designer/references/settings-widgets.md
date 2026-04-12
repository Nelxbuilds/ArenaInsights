# Settings Panel Widgets — WoW Midnight 12.x

Reference for building settings panels using the modern `Settings` API and canvas-layout panels.

---

## Slider

```lua
-- Manual slider with Midnight styling
local function CreateMidnightSlider(parent, label, minVal, maxVal, step, currentVal, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(48)

    local lbl = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    lbl:SetTextColor(0.88, 0.84, 0.78)
    lbl:SetText(label)

    local valDisplay = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valDisplay:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    valDisplay:SetTextColor(1, 1, 1)
    valDisplay:SetText(tostring(currentVal))

    local slider = CreateFrame("Slider", nil, container, "MinimalSliderTemplate")
    slider:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    slider:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    slider:SetHeight(16)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetValue(currentVal)
    slider:SetObeyStepOnDrag(true)

    slider:SetScript("OnValueChanged", function(self, value)
        valDisplay:SetText(string.format("%.2g", value))
        if onChange then onChange(value) end
    end)

    return container, slider
end
```

---

## Checkbox

```lua
local function CreateMidnightCheckbox(parent, label, currentValue, onChange)
    local btn = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    btn:SetSize(24, 24)
    -- The template adds a .text fontstring automatically
    btn.text:SetText(label)
    btn.text:SetTextColor(0.88, 0.84, 0.78)
    btn:SetChecked(currentValue)
    btn:SetScript("OnClick", function(self)
        if onChange then onChange(self:GetChecked()) end
    end)
    return btn
end
```

---

## Dropdown (Modern — EditModeDropdownSystem or simple custom)

For simple dropdowns (3–8 choices), a custom popup is cleaner than UIDropDownMenu:

```lua
-- Creates a labelled button that opens a popup list on click
local function CreateSimpleDropdown(parent, label, options, currentKey, onChange)
    -- options = { { key="opt1", label="Option 1" }, ... }
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(28)

    local lbl = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", container, "LEFT", 0, 0)
    lbl:SetTextColor(0.88, 0.84, 0.78)
    lbl:SetText(label .. ": ")

    local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
    btn:SetSize(120, 22)
    btn:SetPoint("LEFT", lbl, "RIGHT", 4, 0)
    btn:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1 })
    btn:SetBackdropColor(0.08, 0.04, 0.14, 1)
    btn:SetBackdropBorderColor(0.45, 0.35, 0.12, 1)

    local btnLabel = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btnLabel:SetAllPoints()
    btnLabel:SetJustifyH("CENTER")
    btnLabel:SetTextColor(1, 1, 1)

    -- Find and display current option label
    local function SetCurrent(key)
        for _, opt in ipairs(options) do
            if opt.key == key then
                btnLabel:SetText(opt.label)
                return
            end
        end
    end
    SetCurrent(currentKey)

    -- Popup menu (built on click) — uses MenuUtil (12.x), NOT EasyMenu
    btn:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(ownerRegion, rootDescription)
            for _, opt in ipairs(options) do
                local o = opt  -- upvalue capture
                rootDescription:CreateButton(o.label, function()
                    SetCurrent(o.key)
                    if onChange then onChange(o.key) end
                end)
            end
        end)
    end)

    return container, btn
end
```

---

## Input / EditBox

```lua
local function CreateMidnightInput(parent, w, placeholder)
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    eb:SetSize(w, 24)
    eb:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1 })
    eb:SetBackdropColor(0.04, 0.02, 0.08, 1)
    eb:SetBackdropBorderColor(0.45, 0.35, 0.12, 1)
    eb:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    eb:SetTextColor(0.88, 0.84, 0.78)
    eb:SetTextInsets(6, 6, 0, 0)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(64)
    eb:EnableMouse(true)

    -- Placeholder text
    if placeholder then
        local ph = eb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ph:SetAllPoints()
        ph:SetJustifyH("LEFT")
        ph:SetTextInsets(6, 0, 0, 0)  -- match EditBox insets
        ph:SetTextColor(0.45, 0.42, 0.38)
        ph:SetText(placeholder)
        eb:SetScript("OnTextChanged", function(self)
            ph:SetShown(self:GetText() == "")
        end)
        eb:SetScript("OnShow", function(self)
            ph:SetShown(self:GetText() == "")
        end)
        ph:SetShown(true)
    end

    -- Highlight on focus
    eb:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(0.92, 0.78, 0.32, 1)
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0.45, 0.35, 0.12, 1)
    end)

    return eb
end
```

---

## Laying Out a Settings Panel (Canvas Layout)

Canvas panels have no automatic layout — you position everything manually.
Use a simple cursor approach:

```lua
local function BuildSettingsPanel(panel)
    local y = -PAD_OUTER  -- current Y cursor (negative = downward)
    local X = PAD_OUTER

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", X, y)
    title:SetTextColor(0.92, 0.78, 0.32)
    title:SetText("Display Settings")
    y = y - 24 - PAD_INNER

    -- Separator
    local sep = panel:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", panel, "TOPLEFT", X, y)
    sep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -X, y)
    sep:SetColorTexture(0.45, 0.35, 0.12, 0.5)
    y = y - PAD_INNER - 1

    -- Checkbox example
    local cb = CreateMidnightCheckbox(panel, "Show overlay on login", ns.db.settings.overlayShowOnLoad, function(val)
        ns.db.settings.overlayShowOnLoad = val
    end)
    cb:SetPoint("TOPLEFT", panel, "TOPLEFT", X, y)
    y = y - 28

    -- Slider example
    local sliderContainer, slider = CreateMidnightSlider(panel, "Overlay Scale", 0.5, 2.0, 0.05,
        ns.db.settings.overlayScale,
        function(val)
            ns.db.settings.overlayScale = val
            if ns.Overlay then ns.Overlay:SetScale(val) end
        end)
    sliderContainer:SetPoint("TOPLEFT", panel, "TOPLEFT", X, y)
    sliderContainer:SetWidth(300)
    y = y - 52

    return y  -- return final cursor position for further additions
end
```