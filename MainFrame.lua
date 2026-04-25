local addonName, NXR = ...

-- ============================================================================
-- Shared backdrop & widget helpers
-- ============================================================================

NXR.NXR_BACKDROP = {
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 2,
}

NXR.COLORS.BG_BASE   = { 0.06, 0.06, 0.06, 0.95 }
NXR.COLORS.BG_RAISED = { 0.10, 0.10, 0.10, 0.95 }

function NXR.CreateNXRButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 120, height or 28)
    btn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)

    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.label:SetPoint("CENTER")
    btn.label:SetText(text or "")

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(NXR.COLORS.CRIMSON_MID))
    end)
    btn:SetScript("OnLeave", function(self)
        if not self.nxrActive then
            self:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
        end
    end)

    return btn
end

function NXR.CreateNXRInput(parent, width, height)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width or 200, height or 24)
    box:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    box:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
    box:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
    box:SetFontObject("ChatFontNormal")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

-- ============================================================================
-- Main Frame & Sidebar Navigation (Story 3-1)
-- ============================================================================

local SIDEBAR_WIDTH = 140
local FRAME_W, FRAME_H = 700, 520

local mainFrame
local contentArea
local navButtons = {}
local tabPanels  = {}
local activeTab  = nil

local TAB_ORDER = { "Home", "History", "Challenges", "Characters", "Settings" }

local function SelectTab(tabName)
    if activeTab == tabName then return end
    activeTab = tabName

    for name, btn in pairs(navButtons) do
        if name == tabName then
            btn:SetBackdropColor(0.15, 0.05, 0.05, 0.6)
            btn:SetBackdropBorderColor(0, 0, 0, 0)
            btn.label:SetTextColor(1, 1, 1)
            btn.nxrActive = true
            btn.accent:Show()
        else
            btn:SetBackdropColor(0, 0, 0, 0)
            btn:SetBackdropBorderColor(0, 0, 0, 0)
            btn.label:SetTextColor(0.6, 0.6, 0.6)
            btn.nxrActive = false
            btn.accent:Hide()
        end
    end

    for name, panel in pairs(tabPanels) do
        if name == tabName then
            panel:Show()
        else
            panel:Hide()
        end
    end
end

local function CreateSidebar(parent)
    local sidebar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    sidebar:SetWidth(SIDEBAR_WIDTH)
    sidebar:SetPoint("TOPLEFT", 2, -2)
    sidebar:SetPoint("BOTTOMLEFT", 2, 2)
    sidebar:SetBackdrop(NXR.NXR_BACKDROP)
    sidebar:SetBackdropColor(unpack(NXR.COLORS.BG_RAISED))
    sidebar:SetBackdropBorderColor(0, 0, 0, 0)

    -- Right edge separator
    local sep = sidebar:CreateTexture(nil, "BORDER")
    sep:SetWidth(1)
    sep:SetPoint("TOPRIGHT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(unpack(NXR.COLORS.CRIMSON_DIM))

    -- Title
    local title = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -16)
    title:SetText("NelxRated")
    title:SetTextColor(unpack(NXR.COLORS.GOLD))

    -- Nav buttons
    local TAB_HEIGHT = 44
    local TAB_GAP = 4
    local yOff = -50
    for _, tabName in ipairs(TAB_ORDER) do
        local btn = CreateFrame("Button", nil, sidebar, "BackdropTemplate")
        btn:SetHeight(TAB_HEIGHT)
        btn:SetPoint("TOPLEFT", 0, yOff)
        btn:SetPoint("RIGHT", sidebar, "RIGHT", -1, 0)
        btn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 0,
        })
        btn:SetBackdropColor(0, 0, 0, 0)
        btn:SetBackdropBorderColor(0, 0, 0, 0)

        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.label:SetPoint("LEFT", 14, 0)
        btn.label:SetText(tabName)
        btn.label:SetTextColor(0.6, 0.6, 0.6)

        -- Crimson left accent bar
        btn.accent = btn:CreateTexture(nil, "OVERLAY")
        btn.accent:SetWidth(3)
        btn.accent:SetPoint("TOPLEFT", 0, 0)
        btn.accent:SetPoint("BOTTOMLEFT", 0, 0)
        btn.accent:SetColorTexture(unpack(NXR.COLORS.CRIMSON_BRIGHT))
        btn.accent:Hide()

        btn:SetScript("OnEnter", function(self)
            if not self.nxrActive then
                self:SetBackdropColor(0.15, 0.15, 0.15, 0.5)
                self.label:SetTextColor(0.85, 0.85, 0.85)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if not self.nxrActive then
                self:SetBackdropColor(0, 0, 0, 0)
                self.label:SetTextColor(0.6, 0.6, 0.6)
            end
        end)

        btn:SetScript("OnClick", function() SelectTab(tabName) end)

        navButtons[tabName] = btn
        yOff = yOff - TAB_HEIGHT - TAB_GAP
    end

    return sidebar
end

local function CreateMainFrame()
    local f = CreateFrame("Frame", "NelxRatedMainFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER")
    f:SetBackdrop(NXR.NXR_BACKDROP)
    f:SetBackdropColor(unpack(NXR.COLORS.BG_BASE))
    f:SetBackdropBorderColor(unpack(NXR.COLORS.CRIMSON_DIM))
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    tinsert(UISpecialFrames, "NelxRatedMainFrame")

    -- Close button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    -- Sidebar
    CreateSidebar(f)

    -- Content area (right of sidebar)
    contentArea = CreateFrame("Frame", nil, f)
    contentArea:SetPoint("TOPLEFT", SIDEBAR_WIDTH + 16, -8)
    contentArea:SetPoint("BOTTOMRIGHT", -8, 8)

    -- Create tab panels
    for _, tabName in ipairs(TAB_ORDER) do
        local panel = CreateFrame("Frame", nil, contentArea)
        panel:SetAllPoints()
        panel:Hide()
        tabPanels[tabName] = panel
    end

    -- Embed Home panel
    NXR.CreateHomePanel(tabPanels["Home"])

    -- Embed Challenges panel
    NXR.CreateChallengesPanel(tabPanels["Challenges"])

    -- Build other tabs
    if NXR.CreateCharactersPanel then
        NXR.CreateCharactersPanel(tabPanels["Characters"])
    end
    if NXR.CreateSettingsPanel then
        NXR.CreateSettingsPanel(tabPanels["Settings"])
    end
    if NXR.CreateHistoryPanel then
        NXR.CreateHistoryPanel(tabPanels["History"])
    end
    -- Default to Home tab
    SelectTab("Home")

    mainFrame = f
    NXR.mainFrame = f
end

function NXR.ToggleMainFrame()
    if not mainFrame then
        CreateMainFrame()
        return -- already visible on creation
    end

    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
    end
end
