local addonName, NXR = ...

-- ============================================================================
-- Bracket constants
-- ============================================================================

NXR.BRACKET_2V2          = 1
NXR.BRACKET_3V3          = 2
NXR.BRACKET_BLITZ        = 4
NXR.BRACKET_SOLO_SHUFFLE = 7

NXR.BRACKET_NAMES = {
    [1] = "2v2",
    [2] = "3v3",
    [4] = "Blitz BG",
    [7] = "Solo Shuffle",
}

NXR.TRACKED_BRACKETS = { 1, 2, 4, 7 }

NXR.PER_SPEC_BRACKETS = {
    [4] = true,   -- Blitz BG (per-spec rating)
    [7] = true,   -- Solo Shuffle (per-spec rating)
}

-- ============================================================================
-- Color palette
-- ============================================================================

NXR.COLORS = {
    CRIMSON_BRIGHT = { 0.9, 0.15, 0.15 },
    CRIMSON_MID    = { 0.7, 0.1, 0.1 },
    CRIMSON_DIM    = { 0.35, 0.05, 0.05 },
    GOLD           = { 1.0, 0.82, 0.0 },
}

-- ============================================================================
-- SavedVariables initialization (only after ADDON_LOADED)
-- ============================================================================

local SETTINGS_DEFAULTS = {
    accountName           = "",
    opacityInArena        = 1.0,
    opacityOutOfArena     = 1.0,
    showOverlayBackground = true,
    showOverlay           = true,
    overlayLocked         = false,
    overlayScale          = 1.0,
}

local function InitDB()
    NelxRatedDB = NelxRatedDB or {}

    NelxRatedDB.settings        = NelxRatedDB.settings or {}
    NelxRatedDB.characters      = NelxRatedDB.characters or {}
    NelxRatedDB.challenges      = NelxRatedDB.challenges or {}
    NelxRatedDB.overlayPosition = NelxRatedDB.overlayPosition or {}
    NelxRatedDB.schemaVersion   = NelxRatedDB.schemaVersion or 1

    for k, v in pairs(SETTINGS_DEFAULTS) do
        if NelxRatedDB.settings[k] == nil then
            NelxRatedDB.settings[k] = v
        end
    end
end

-- ============================================================================
-- Character information capture
-- ============================================================================

function NXR.UpdateCharacterInfo()
    local name, realm = UnitName("player")
    realm = (realm and realm ~= "") and realm or GetRealmName()
    if not name or not realm then return end

    local key = name .. "-" .. realm
    NXR.currentCharKey = key

    local classDisplayName, classFileName = UnitClass("player")

    local specIndex = GetSpecialization()
    local specID, specName
    if specIndex then
        specID, specName = GetSpecializationInfo(specIndex)
    end

    local char = NelxRatedDB.characters[key] or { brackets = {}, specBrackets = {} }
    char.name             = name
    char.realm            = realm
    char.classFileName    = classFileName
    char.classDisplayName = classDisplayName
    -- Preserve existing specID/specName when GetSpecialization() returns nil
    -- (common during loading screens after matches)
    if specID then
        char.specID   = specID
        char.specName = specName
    end
    char.account          = NelxRatedDB.settings.accountName

    NelxRatedDB.characters[key] = char
end

-- ============================================================================
-- Rating & MMR capture
-- ============================================================================

function NXR.SaveBracketData(bracketIndex, rating, mmr)
    local key = NXR.currentCharKey
    if not key then return end

    local char = NelxRatedDB.characters[key]
    if not char then return end

    local data = {
        rating    = rating,
        mmr       = mmr,
        updatedAt = time(),
    }

    if NXR.PER_SPEC_BRACKETS[bracketIndex] then
        local specID = char.specID
        if not specID then return end
        char.specBrackets = char.specBrackets or {}
        char.specBrackets[specID] = char.specBrackets[specID] or {}
        char.specBrackets[specID][bracketIndex] = data
    else
        char.brackets[bracketIndex] = data
    end
end

function NXR.GetRating(charKey, bracketIndex, specID)
    local char = NelxRatedDB.characters[charKey]
    if not char then return nil end

    if NXR.PER_SPEC_BRACKETS[bracketIndex] then
        local sb = char.specBrackets and char.specBrackets[specID]
        return sb and sb[bracketIndex]
    else
        return char.brackets and char.brackets[bracketIndex]
    end
end

local function CapturePvPStats()
    if not GetPersonalRatedInfo then return end

    NXR.UpdateCharacterInfo()

    for _, bracketIndex in ipairs(NXR.TRACKED_BRACKETS) do
        local rating, seasonBest, weeklyBest, seasonPlayed, seasonWon, weeklyPlayed, weeklyWon, cap = GetPersonalRatedInfo(bracketIndex)
        if rating and rating > 0 then
            NXR.SaveBracketData(bracketIndex, rating, 0)
        end
    end

    if NXR.RefreshOverlay then
        NXR.RefreshOverlay()
    end
end

-- ============================================================================
-- Event handling
-- ============================================================================

local pvpStatsTimer = nil

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
eventFrame:RegisterEvent("PVP_RATED_STATS_UPDATE")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            InitDB()
            if NXR.BuildSpecData then NXR.BuildSpecData() end
            if NXR.InitChallenges then NXR.InitChallenges() end
            self:UnregisterEvent("ADDON_LOADED")
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        NXR.UpdateCharacterInfo()

    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
        NXR.UpdateCharacterInfo()

    elseif event == "PVP_RATED_STATS_UPDATE" then
        if pvpStatsTimer then return end
        pvpStatsTimer = C_Timer.After(0.5, function()
            pvpStatsTimer = nil
            CapturePvPStats()
        end)
    end
end)

-- ============================================================================
-- Slash command
-- ============================================================================

SLASH_NELXRATED1 = "/nxr"
SLASH_NELXRATED2 = "/nelxrated"
SlashCmdList["NELXRATED"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S+)") or ""
    if cmd == "help" then
        print("|cffE6D200NelxRated|r commands:")
        print("  /nxr — Open the main window")
        print("  /nxr overlay — Toggle overlay visibility")
        print("  /nxr lock — Lock overlay position")
        print("  /nxr unlock — Unlock overlay position")
        print("  /nxr help — Show this help")
        return
    end
    if cmd == "overlay" then
        if NXR.Overlay and NXR.Overlay.Toggle then
            NXR.Overlay.Toggle()
        end
        return
    end
    if cmd == "lock" then
        if NXR.Overlay and NXR.Overlay.SetLocked then
            NXR.Overlay.SetLocked(true)
        end
        return
    end
    if cmd == "unlock" then
        if NXR.Overlay and NXR.Overlay.SetLocked then
            NXR.Overlay.SetLocked(false)
        end
        return
    end
    if NXR.ToggleMainFrame then
        NXR.ToggleMainFrame()
    end
end
