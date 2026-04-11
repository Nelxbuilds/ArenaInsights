local addonName, NXR = ...

-- ============================================================================
-- Home Tab (Story 5-1)
-- ============================================================================

local function CreateCopyableLink(parent, label, url, yOffset)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", 0, yOffset)
    lbl:SetText(label)
    lbl:SetTextColor(0.7, 0.7, 0.7)

    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(320, 22)
    box:SetPoint("TOPLEFT", 0, yOffset - 16)
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
    box:SetText(url)
    box:SetCursorPosition(0)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnChar", function(self) self:SetText(url); self:HighlightText() end)

    return -16 - 22 - 10 -- height consumed
end

function NXR.CreateHomePanel(parent)
    local scroll = CreateFrame("Frame", nil, parent)
    scroll:SetAllPoints()

    local y = 0

    -- Addon name
    local title = scroll:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 0, y)
    title:SetText("NelxRated")
    title:SetTextColor(unpack(NXR.COLORS.GOLD))
    y = y - 22

    -- Version
    local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
    local ver = scroll:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ver:SetPoint("TOPLEFT", 0, y)
    ver:SetText("Version " .. version)
    ver:SetTextColor(0.6, 0.6, 0.6)
    y = y - 24

    -- Description
    local desc = scroll:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    desc:SetPoint("TOPLEFT", 0, y)
    desc:SetPoint("RIGHT", scroll, "RIGHT", -8, 0)
    desc:SetJustifyH("LEFT")
    desc:SetSpacing(2)
    desc:SetText("Personal PvP rating challenge tracker for Solo Shuffle, 2v2, 3v3, and Blitz BG. Track ratings and MMR by spec or class across multiple characters and accounts.")
    desc:SetTextColor(0.8, 0.8, 0.8)
    y = y - (desc:GetStringHeight() or 40) - 20

    -- Getting Started section
    local gsTitle = scroll:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    gsTitle:SetPoint("TOPLEFT", 0, y)
    gsTitle:SetText("Getting Started")
    gsTitle:SetTextColor(unpack(NXR.COLORS.GOLD))
    y = y - 24

    local steps = {
        "Play a rated PvP game to start tracking ratings.",
        "Open the Challenges tab to create rating goals.",
        "Set a challenge as active to see it on the overlay.",
        "Use Import/Export to share data across accounts.",
    }

    for _, step in ipairs(steps) do
        local bullet = scroll:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        bullet:SetPoint("TOPLEFT", 8, y)
        bullet:SetPoint("RIGHT", scroll, "RIGHT", -8, 0)
        bullet:SetJustifyH("LEFT")
        bullet:SetText("|cff999999-|r  " .. step)
        bullet:SetTextColor(0.8, 0.8, 0.8)
        y = y - 20
    end

    y = y - 16

    -- Links section
    local linksTitle = scroll:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    linksTitle:SetPoint("TOPLEFT", 0, y)
    linksTitle:SetText("Links")
    linksTitle:SetTextColor(unpack(NXR.COLORS.GOLD))
    y = y - 24

    CreateCopyableLink(scroll, "CurseForge", "https://www.curseforge.com/wow/addons/nelxrated", y)
    y = y - 48

    CreateCopyableLink(scroll, "GitHub", "https://github.com/Nelxbuilds/NelxRated", y)
end
