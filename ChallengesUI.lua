local addonName, NXR = ...

-- ============================================================================
-- Constants
-- ============================================================================

local ROW_HEIGHT     = 64
local ROW_GAP        = 4
local ICON_SIZE      = 20
local ICON_GAP       = 2
local MAX_ICONS      = 6
local SPEC_ROW_H     = 24
local SPEC_COL_W     = 210
local SPEC_COL_GAP   = 20
local CB_SIZE        = 22
local CLASS_BTN_SIZE = 28
local CLASS_BTN_GAP  = 4

-- ============================================================================
-- Local state
-- ============================================================================

local panel, listFrame, formFrame
local listScroll, listScrollChild
local listRows = {}
local emptyLabel

-- Form state
local editingID   = nil
local formState   = {}
local formScrollChild
local nameInput, ratingInput
local bracketBtns = {}
local specCBs     = {}
local classBtns   = {}
local nameErr, bracketErr, ratingErr, specErr
local formBuilt   = false

-- Forward declarations
local ShowList, ShowForm, RefreshList

-- ============================================================================
-- Helpers
-- ============================================================================

local function CountKeys(t)
    local n = 0
    if t then for _ in pairs(t) do n = n + 1 end end
    return n
end

local function CopyTable(t)
    local copy = {}
    if t then for k, v in pairs(t) do copy[k] = v end end
    return copy
end

local function SetClassIcon(tex, classFileName)
    local ok = pcall(function()
        tex:SetAtlas("classicon-" .. classFileName:lower())
    end)
    if not ok then
        tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes")
        if CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFileName] then
            tex:SetTexCoord(unpack(CLASS_ICON_TCOORDS[classFileName]))
        end
    end
end

-- ============================================================================
-- Challenge List — reusable rows (Story 2-2)
-- ============================================================================

local function CreateReusableRow(parent)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    -- Buttons (top-right)
    row.activeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.activeBtn:SetSize(72, 22)
    row.activeBtn:SetPoint("TOPRIGHT", -6, -6)
    row.activeBtn:SetNormalFontObject("GameFontNormalSmall")
    row.activeBtn:SetHighlightFontObject("GameFontHighlightSmall")

    row.editBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.editBtn:SetSize(44, 22)
    row.editBtn:SetPoint("RIGHT", row.activeBtn, "LEFT", -4, 0)
    row.editBtn:SetText("Edit")
    row.editBtn:SetNormalFontObject("GameFontNormalSmall")
    row.editBtn:SetHighlightFontObject("GameFontHighlightSmall")

    row.deleteBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.deleteBtn:SetSize(52, 22)
    row.deleteBtn:SetPoint("RIGHT", row.editBtn, "LEFT", -4, 0)
    row.deleteBtn:SetText("Delete")
    row.deleteBtn:SetNormalFontObject("GameFontNormalSmall")
    row.deleteBtn:SetHighlightFontObject("GameFontHighlightSmall")

    -- Name and subtitle (left side, constrained to not overlap buttons)
    row.nameStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.nameStr:SetPoint("TOPLEFT", 8, -6)
    row.nameStr:SetPoint("RIGHT", row.deleteBtn, "LEFT", -8, 0)
    row.nameStr:SetJustifyH("LEFT")
    row.nameStr:SetWordWrap(false)

    row.subStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.subStr:SetPoint("TOPLEFT", 8, -24)
    row.subStr:SetPoint("RIGHT", row.deleteBtn, "LEFT", -8, 0)
    row.subStr:SetJustifyH("LEFT")
    row.subStr:SetWordWrap(false)
    row.subStr:SetTextColor(0.55, 0.55, 0.55)

    -- Pre-create icon textures (bottom row, left-aligned)
    row.icons = {}
    for i = 1, MAX_ICONS do
        local ic = row:CreateTexture(nil, "ARTWORK")
        ic:SetSize(ICON_SIZE, ICON_SIZE)
        ic:SetPoint("BOTTOMLEFT", 8 + ((i - 1) * (ICON_SIZE + ICON_GAP)), 4)
        ic:Hide()
        row.icons[i] = ic
    end

    row:Hide()
    return row
end

local function UpdateRow(row, challenge)
    -- Style based on active state
    if challenge.active then
        row:SetBackdropColor(0.35, 0.05, 0.05, 0.6)
        row:SetBackdropBorderColor(0.7, 0.1, 0.1, 0.8)
        row.nameStr:SetTextColor(unpack(NXR.COLORS.CRIMSON_BRIGHT))
        row.activeBtn:SetText("Active")
        row.activeBtn:SetSize(60, 22)
        row.activeBtn:Disable()
    else
        row:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        row:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.5)
        row.nameStr:SetTextColor(unpack(NXR.COLORS.GOLD))
        row.activeBtn:SetText("Set Active")
        row.activeBtn:SetSize(72, 22)
        row.activeBtn:Enable()
    end

    row.nameStr:SetText(challenge.name)

    -- Subtitle
    local parts = {}
    table.insert(parts, "Rating \226\137\165 " .. (challenge.goalRating or 0))

    local bnames = {}
    for _, bi in ipairs(NXR.TRACKED_BRACKETS) do
        if challenge.brackets[bi] then
            table.insert(bnames, NXR.BRACKET_NAMES[bi])
        end
    end
    if #bnames > 0 then
        table.insert(parts, table.concat(bnames, ", "))
    end

    local classCount = CountKeys(challenge.classes)
    local specCount  = CountKeys(challenge.specs)
    if classCount > 0 then
        table.insert(parts, classCount .. " class(es)")
    else
        table.insert(parts, specCount .. " spec(s)")
    end
    row.subStr:SetText(table.concat(parts, "  |  "))

    -- Icons
    for _, ic in ipairs(row.icons) do
        ic:SetTexCoord(0, 1, 0, 1)
        ic:SetAtlas("")
        ic:SetTexture(nil)
        ic:Hide()
    end

    local idx = 1
    if classCount > 0 then
        for classID in pairs(challenge.classes) do
            if idx > MAX_ICONS then break end
            local cd = NXR.classData[classID]
            if cd then
                SetClassIcon(row.icons[idx], cd.classFileName)
                row.icons[idx]:Show()
                idx = idx + 1
            end
        end
    else
        for specID in pairs(challenge.specs) do
            if idx > MAX_ICONS then break end
            local sd = NXR.specData[specID]
            if sd and sd.icon then
                row.icons[idx]:SetTexture(sd.icon)
                row.icons[idx]:Show()
                idx = idx + 1
            end
        end
    end

    -- Button callbacks
    local id = challenge.id
    row.activeBtn:SetScript("OnClick", function()
        NXR.SetActiveChallenge(id)
        RefreshList()
    end)
    row.editBtn:SetScript("OnClick", function() ShowForm(id) end)
    row.deleteBtn:SetScript("OnClick", function()
        NXR.RemoveChallenge(id)
        RefreshList()
    end)

    row:Show()
end

RefreshList = function()
    for _, row in ipairs(listRows) do row:Hide() end

    local challenges = NelxRatedDB.challenges
    if not challenges or #challenges == 0 then
        emptyLabel:Show()
        listScrollChild:SetHeight(1)
        return
    end
    emptyLabel:Hide()

    local yOff = 0
    for i, challenge in ipairs(challenges) do
        if not listRows[i] then
            listRows[i] = CreateReusableRow(listScrollChild)
        end
        local row = listRows[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -yOff)
        row:SetPoint("RIGHT", listScrollChild, "RIGHT", 0, 0)
        UpdateRow(row, challenge)
        yOff = yOff + ROW_HEIGHT + ROW_GAP
    end

    -- Hide excess rows
    for i = #challenges + 1, #listRows do
        listRows[i]:Hide()
    end

    listScrollChild:SetHeight(math.max(yOff, 1))
end

-- ============================================================================
-- Create / Edit Form (Story 2-3)
-- ============================================================================

local function ResetFormState()
    formState = {
        name       = "",
        goalRating = 1800,
        brackets   = {},
        specs      = {},
        classes    = {},
    }
end

local function UpdateBracketButtons()
    for bi, btn in pairs(bracketBtns) do
        if formState.brackets[bi] then
            btn:SetBackdropColor(0.7, 0.1, 0.1, 0.8)
            btn:SetBackdropBorderColor(0.9, 0.15, 0.15, 1)
            btn.label:SetTextColor(1, 1, 1)
        else
            btn:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
            btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
            btn.label:SetTextColor(0.5, 0.5, 0.5)
        end
    end
end

local function UpdateSpecCheckboxes()
    for specID, cb in pairs(specCBs) do
        cb:SetChecked(formState.specs[specID] == true)
    end
end

local function UpdateClassButtons()
    for classID, btn in pairs(classBtns) do
        if formState.classes[classID] then
            btn:SetBackdropBorderColor(0.9, 0.15, 0.15, 1)
        else
            btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.3)
        end
    end
end

local function HideErrors()
    if nameErr then nameErr:SetText("") end
    if bracketErr then bracketErr:SetText("") end
    if ratingErr then ratingErr:SetText("") end
    if specErr then specErr:SetText("") end
end

local function ValidateForm()
    local valid = true
    HideErrors()

    if formState.name == "" then
        nameErr:SetText("Name is required")
        valid = false
    end

    if CountKeys(formState.brackets) == 0 then
        bracketErr:SetText("Select at least one bracket")
        valid = false
    end

    local rating = tonumber(formState.goalRating)
    if not rating or rating <= 0 then
        ratingErr:SetText("Enter a valid rating")
        valid = false
    end

    if CountKeys(formState.specs) == 0 then
        specErr:SetText("Select at least one spec")
        valid = false
    end

    return valid
end

local function SaveForm()
    if not ValidateForm() then return end

    local rating = tonumber(formState.goalRating)
    if not rating or rating <= 0 then return end

    local data = {
        name       = formState.name,
        goalRating = rating,
        brackets   = CopyTable(formState.brackets),
        specs      = CopyTable(formState.specs),
        classes    = CopyTable(formState.classes),
    }

    if editingID then
        NXR.UpdateChallenge(editingID, data)
    else
        NXR.AddChallenge(data)
    end

    ShowList()
end

-- Build form UI (called once, lazily)
local function BuildForm()
    if formBuilt then return end
    formBuilt = true

    -- Back button (fixed, above scroll)
    local backBtn = CreateFrame("Button", nil, formFrame, "UIPanelButtonTemplate")
    backBtn:SetSize(80, 24)
    backBtn:SetPoint("TOPLEFT", 4, -4)
    backBtn:SetText("< Back")
    backBtn:SetNormalFontObject("GameFontNormalSmall")
    backBtn:SetScript("OnClick", function() ShowList() end)

    formFrame.titleText = formFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    formFrame.titleText:SetPoint("LEFT", backBtn, "RIGHT", 8, 0)
    formFrame.titleText:SetTextColor(unpack(NXR.COLORS.GOLD))

    -- Scroll area for form content
    local scroll = CreateFrame("ScrollFrame", nil, formFrame)
    scroll:SetPoint("TOPLEFT", 0, -34)
    scroll:SetPoint("BOTTOMRIGHT", 0, 8)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(cur - delta * 40, max)))
    end)

    formScrollChild = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(formScrollChild)
    formScrollChild:SetHeight(1)
    scroll:SetScript("OnSizeChanged", function(self, w)
        formScrollChild:SetWidth(w)
    end)

    local p = formScrollChild -- shorthand parent
    local y = 8

    -- ----------------------------------------------------------------
    -- Name input
    -- ----------------------------------------------------------------
    local nameLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", 8, -y)
    nameLabel:SetText("Challenge Name")
    y = y + 16

    nameInput = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    nameInput:SetSize(250, 22)
    nameInput:SetPoint("TOPLEFT", 10, -y)
    nameInput:SetAutoFocus(false)
    nameInput:SetScript("OnTextChanged", function(self)
        formState.name = self:GetText()
    end)
    nameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    nameInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    nameErr = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameErr:SetPoint("LEFT", nameInput, "RIGHT", 8, 0)
    nameErr:SetTextColor(1, 0.3, 0.3)
    y = y + 32

    -- ----------------------------------------------------------------
    -- Bracket toggles
    -- ----------------------------------------------------------------
    local bracketLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bracketLabel:SetPoint("TOPLEFT", 8, -y)
    bracketLabel:SetText("Brackets")
    y = y + 18

    local bx = 10
    for _, bi in ipairs(NXR.TRACKED_BRACKETS) do
        local btn = CreateFrame("Button", nil, p, "BackdropTemplate")
        btn:SetSize(94, 24)
        btn:SetPoint("TOPLEFT", bx, -y)
        btn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })

        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.label:SetPoint("CENTER")
        btn.label:SetText(NXR.BRACKET_NAMES[bi])

        btn:SetScript("OnClick", function()
            formState.brackets[bi] = not formState.brackets[bi] or nil
            UpdateBracketButtons()
        end)

        bracketBtns[bi] = btn
        bx = bx + 98
    end

    bracketErr = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bracketErr:SetPoint("TOPLEFT", 8, -(y + 26))
    bracketErr:SetTextColor(1, 0.3, 0.3)
    y = y + 36

    -- ----------------------------------------------------------------
    -- Goal rating
    -- ----------------------------------------------------------------
    local ratingLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ratingLabel:SetPoint("TOPLEFT", 8, -y)
    ratingLabel:SetText("Goal Rating")
    y = y + 16

    ratingInput = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    ratingInput:SetSize(100, 22)
    ratingInput:SetPoint("TOPLEFT", 10, -y)
    ratingInput:SetAutoFocus(false)
    ratingInput:SetNumeric(true)
    ratingInput:SetScript("OnTextChanged", function(self)
        formState.goalRating = tonumber(self:GetText()) or 0
    end)
    ratingInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ratingInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    ratingErr = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ratingErr:SetPoint("LEFT", ratingInput, "RIGHT", 8, 0)
    ratingErr:SetTextColor(1, 0.3, 0.3)
    y = y + 34

    -- ----------------------------------------------------------------
    -- Class picker
    -- ----------------------------------------------------------------
    local classLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    classLabel:SetPoint("TOPLEFT", 8, -y)
    classLabel:SetText("Classes")
    classLabel:SetTextColor(unpack(NXR.COLORS.GOLD))
    y = y + 20

    local cx = 10
    for _, classID in ipairs(NXR.sortedClassIDs) do
        local cd = NXR.classData[classID]
        if cd then
            local btn = CreateFrame("Button", nil, p, "BackdropTemplate")
            btn:SetSize(CLASS_BTN_SIZE, CLASS_BTN_SIZE)
            btn:SetPoint("TOPLEFT", cx, -y)
            btn:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 2,
            })
            btn:SetBackdropColor(0, 0, 0, 0)
            btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.3)

            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", 2, -2)
            icon:SetPoint("BOTTOMRIGHT", -2, 2)
            SetClassIcon(icon, cd.classFileName)

            btn:SetScript("OnClick", function()
                if formState.classes[classID] then
                    formState.classes[classID] = nil
                    for _, s in ipairs(cd.specs) do
                        formState.specs[s.specID] = nil
                    end
                else
                    formState.classes[classID] = true
                    for _, s in ipairs(cd.specs) do
                        formState.specs[s.specID] = true
                    end
                end
                UpdateClassButtons()
                UpdateSpecCheckboxes()
            end)

            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:SetText(cd.className)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            classBtns[classID] = btn
            cx = cx + CLASS_BTN_SIZE + CLASS_BTN_GAP
        end
    end

    y = y + CLASS_BTN_SIZE + 16

    -- ----------------------------------------------------------------
    -- Spec picker (grouped by role)
    -- ----------------------------------------------------------------
    local specTitle = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    specTitle:SetPoint("TOPLEFT", 8, -y)
    specTitle:SetText("Specs included in this challenge:")
    specTitle:SetTextColor(unpack(NXR.COLORS.GOLD))
    y = y + 20

    local roleOrder = {
        { key = "HEALER",  label = "Healers" },
        { key = "DAMAGER", label = "DPS" },
        { key = "TANK",    label = "Tanks" },
    }

    for _, roleInfo in ipairs(roleOrder) do
        local specs = NXR.roleSpecs[roleInfo.key]
        if specs and #specs > 0 then
            -- Section header
            local header = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            header:SetPoint("TOPLEFT", 8, -y)
            header:SetText(roleInfo.label)
            header:SetTextColor(1, 0.82, 0)

            -- All / None buttons
            local allBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
            allBtn:SetSize(40, 20)
            allBtn:SetPoint("LEFT", header, "RIGHT", 12, 0)
            allBtn:SetText("All")
            allBtn:SetNormalFontObject("GameFontNormalSmall")
            allBtn:SetScript("OnClick", function()
                for _, s in ipairs(specs) do
                    formState.specs[s.specID] = true
                end
                UpdateSpecCheckboxes()
            end)

            local noneBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
            noneBtn:SetSize(44, 20)
            noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 4, 0)
            noneBtn:SetText("None")
            noneBtn:SetNormalFontObject("GameFontNormalSmall")
            noneBtn:SetScript("OnClick", function()
                for _, s in ipairs(specs) do
                    formState.specs[s.specID] = nil
                end
                UpdateSpecCheckboxes()
            end)

            y = y + 24

            -- Two-column layout
            local n    = #specs
            local half = math.ceil(n / 2)

            for i, s in ipairs(specs) do
                local col = (i <= half) and 0 or 1
                local row = (i <= half) and (i - 1) or (i - half - 1)

                local sx = 10 + col * (SPEC_COL_W + SPEC_COL_GAP)
                local sy = y + row * SPEC_ROW_H

                local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
                cb:SetSize(CB_SIZE, CB_SIZE)
                cb:SetPoint("TOPLEFT", sx, -sy)
                cb:SetScript("OnClick", function(self)
                    if self:GetChecked() then
                        formState.specs[s.specID] = true
                    else
                        formState.specs[s.specID] = nil
                    end
                end)

                local ic = cb:CreateTexture(nil, "ARTWORK")
                ic:SetSize(18, 18)
                ic:SetPoint("LEFT", cb, "RIGHT", 2, 0)
                if s.icon then ic:SetTexture(s.icon) end

                local nm = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                nm:SetPoint("LEFT", ic, "RIGHT", 4, 0)
                nm:SetText(s.specName)
                local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[s.classFileName]
                if cc then nm:SetTextColor(cc.r, cc.g, cc.b) end

                specCBs[s.specID] = cb
            end

            y = y + half * SPEC_ROW_H + 10
        end
    end

    -- Spec validation error
    specErr = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    specErr:SetPoint("TOPLEFT", 8, -y)
    specErr:SetTextColor(1, 0.3, 0.3)
    y = y + 18

    -- ----------------------------------------------------------------
    -- Save / Cancel
    -- ----------------------------------------------------------------
    local saveBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    saveBtn:SetSize(120, 28)
    saveBtn:SetPoint("TOPLEFT", 8, -y)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", SaveForm)

    local cancelBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 28)
    cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() ShowList() end)

    y = y + 44
    formScrollChild:SetHeight(y)
end

local function PopulateFormForEdit(challengeID)
    for _, c in ipairs(NelxRatedDB.challenges) do
        if c.id == challengeID then
            formState.name       = c.name
            formState.goalRating = c.goalRating
            formState.brackets   = CopyTable(c.brackets)
            formState.specs      = CopyTable(c.specs)
            formState.classes    = CopyTable(c.classes)
            return
        end
    end
end

ShowForm = function(challengeID)
    editingID = challengeID
    BuildForm()
    ResetFormState()

    if challengeID then
        PopulateFormForEdit(challengeID)
        formFrame.titleText:SetText("Edit Challenge")
    else
        formFrame.titleText:SetText("Create Challenge")
    end

    nameInput:SetText(formState.name)
    ratingInput:SetText(tostring(formState.goalRating))
    UpdateBracketButtons()
    UpdateSpecCheckboxes()
    UpdateClassButtons()
    HideErrors()

    listFrame:Hide()
    formFrame:Show()
end

ShowList = function()
    formFrame:Hide()
    listFrame:Show()
    RefreshList()
end

-- ============================================================================
-- Public API
-- ============================================================================

function NXR.RefreshChallengeList()
    if panel and listFrame and listFrame:IsShown() then
        RefreshList()
    end
end

function NXR.CreateChallengesPanel(parent)
    if panel then return panel end

    panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    -- List frame
    listFrame = CreateFrame("Frame", nil, panel)
    listFrame:SetAllPoints()

    local createBtn = CreateFrame("Button", nil, listFrame, "UIPanelButtonTemplate")
    createBtn:SetSize(180, 28)
    createBtn:SetPoint("TOPLEFT", 8, -8)
    createBtn:SetText("Create New Challenge")
    createBtn:SetScript("OnClick", function() ShowForm(nil) end)

    emptyLabel = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyLabel:SetPoint("CENTER", 0, -20)
    emptyLabel:SetText("No challenges yet. Create one below.")
    emptyLabel:SetTextColor(0.55, 0.55, 0.55)
    emptyLabel:Hide()

    -- Scroll area for challenge list
    listScroll = CreateFrame("ScrollFrame", nil, listFrame)
    listScroll:SetPoint("TOPLEFT", 0, -44)
    listScroll:SetPoint("BOTTOMRIGHT", 0, 4)
    listScroll:EnableMouseWheel(true)
    listScroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(cur - delta * 40, max)))
    end)

    listScrollChild = CreateFrame("Frame", nil, listScroll)
    listScroll:SetScrollChild(listScrollChild)
    listScrollChild:SetHeight(1)
    listScroll:SetScript("OnSizeChanged", function(self, w)
        listScrollChild:SetWidth(w)
    end)

    -- Form frame
    formFrame = CreateFrame("Frame", nil, panel)
    formFrame:SetAllPoints()
    formFrame:Hide()

    ShowList()
    return panel
end

