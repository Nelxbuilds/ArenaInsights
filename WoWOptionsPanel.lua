local addonName, NXR = ...

-- ============================================================================
-- WoW Native Settings Panel — Discovery / Launch Page
-- ============================================================================
-- Registers an entry under Settings > AddOns so users can find the addon
-- without knowing the /nxr slash command. Static launch page only —
-- not a mirror of SettingsUI.lua.
-- ============================================================================

local function BuildOptionsFrame()
    local f = CreateFrame("Frame")
    f:SetSize(700, 500)

    -- Title
    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("NelxRated")
    title:SetTextColor(unpack(NXR.COLORS.CRIMSON_BRIGHT))

    -- Tagline
    local tagline = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    tagline:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    tagline:SetText("Personal PvP Rating & Challenge Tracker")
    tagline:SetTextColor(0.78, 0.75, 0.73)

    -- Divider
    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetWidth(360)
    divider:SetPoint("TOPLEFT", tagline, "BOTTOMLEFT", 0, -10)
    divider:SetColorTexture(
        NXR.COLORS.CRIMSON_BRIGHT[1],
        NXR.COLORS.CRIMSON_BRIGHT[2],
        NXR.COLORS.CRIMSON_BRIGHT[3],
        0.4
    )

    -- Description
    local desc = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    desc:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -14)
    desc:SetWidth(420)
    desc:SetJustifyH("LEFT")
    desc:SetSpacing(3)
    desc:SetTextColor(0.78, 0.75, 0.73)
    desc:SetText(
        "Track PvP ratings and MMR across Solo Shuffle, 2v2, 3v3, and Blitz BG\n" ..
        "— for every spec and character on your account.\n\n" ..
        "Set rating challenges, view progress history, and compare specs\n" ..
        "side-by-side with the in-game overlay.\n\n" ..
        "Slash command: |cffE6D200/nxr|r"
    )

    -- Launch button
    -- NXR.CreateNXRButton is defined in MainFrame.lua. BuildOptionsFrame() is
    -- only called inside ADDON_LOADED (after all files load), so it's safe.
    local btn = NXR.CreateNXRButton(f, "Open NelxRated", 200, 32)
    btn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -20)
    btn:SetScript("OnClick", function()
        if SettingsPanel then SettingsPanel:Hide() end
        NXR.ToggleMainFrame()
    end)

    return f
end

-- Defer registration to ADDON_LOADED (UI system must be ready)
local regFrame = CreateFrame("Frame")
regFrame:RegisterEvent("ADDON_LOADED")
regFrame:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")

    local optionsFrame = BuildOptionsFrame()
    local category = Settings.RegisterCanvasLayoutCategory(optionsFrame, "NelxRated")
    Settings.RegisterAddOnCategory(category)
    NXR.wowOptionsCategoryID = category:GetID()
end)
