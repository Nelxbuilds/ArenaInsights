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
-- Debug logging
-- ============================================================================

local debugMode = false

function NXR.Debug(...)
    if not debugMode then return end
    print("|cff888888[NXR]|r", ...)
end

function NXR.TableCount(t)
    local n = 0
    if t then for _ in pairs(t) do n = n + 1 end end
    return n
end

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
    overlayColumns        = 1,
    overlayGroupByRole       = false,
    hideZeroRatingRows       = false,
    showOverlayProgressBar   = false,
    showOverlayTitle         = false,
    chartColor               = "default",
}

local CURRENT_SCHEMA = 1

local MIGRATIONS = {
    -- [2] = function(db) ... end,  -- add future migrations here
}

local function RunMigrations(db)
    local from = db.schemaVersion or 0
    for version = from + 1, CURRENT_SCHEMA do
        if MIGRATIONS[version] then
            MIGRATIONS[version](db)
        end
        db.schemaVersion = version
    end
end

local function InitDB()
    NelxRatedDB = NelxRatedDB or {}

    NelxRatedDB.settings              = NelxRatedDB.settings or {}
    NelxRatedDB.characters            = NelxRatedDB.characters or {}
    NelxRatedDB.challenges            = NelxRatedDB.challenges or {}
    NelxRatedDB.overlayPosition       = NelxRatedDB.overlayPosition or {}
    NelxRatedDB.schemaVersion         = NelxRatedDB.schemaVersion or 0
    NelxRatedDB.deletedChallengeUIDs  = NelxRatedDB.deletedChallengeUIDs or {}
    NelxRatedDB.syncPartners          = NelxRatedDB.syncPartners or {}

    RunMigrations(NelxRatedDB)
    NXR.Debug("InitDB complete — schema", NelxRatedDB.schemaVersion,
        "| chars:", NXR.TableCount(NelxRatedDB.characters),
        "| challenges:", #NelxRatedDB.challenges)

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
    local _, raceFileName = UnitRace("player")
    local gender = UnitSex("player")

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
    char.raceFileName     = raceFileName
    char.gender           = gender

    NelxRatedDB.characters[key] = char
    NXR.Debug("UpdateCharacterInfo:", key, classFileName or "?",
        specName and ("spec=" .. specName .. " [" .. tostring(specID) .. "]") or "spec=nil")
end

-- ============================================================================
-- Rating & MMR capture
-- ============================================================================

local HISTORY_CAP = 250

local function AppendHistory(char, historyKey, rating)
    char.ratingHistory = char.ratingHistory or {}
    local history = char.ratingHistory[historyKey]

    if not history then
        -- Seed with current rating as first entry
        char.ratingHistory[historyKey] = { { rating = rating, timestamp = time() } }
        return
    end

    -- Deduplicate: only append if rating changed
    local last = history[#history]
    if last and last.rating == rating then return end

    history[#history + 1] = { rating = rating, timestamp = time() }

    -- Cap at 250 entries — bulk trim instead of per-element shift
    if #history > HISTORY_CAP then
        local trim = #history - HISTORY_CAP
        for i = 1, HISTORY_CAP do history[i] = history[i + trim] end
        for i = HISTORY_CAP + 1, HISTORY_CAP + trim do history[i] = nil end
    end
end

function NXR.SaveBracketData(bracketIndex, rating, mmr)
    local key = NXR.currentCharKey
    if not key then
        NXR.Debug("SaveBracketData: no currentCharKey, skipping")
        return
    end

    local char = NelxRatedDB.characters[key]
    if not char then
        NXR.Debug("SaveBracketData: char not found for", key)
        return
    end

    local data = {
        rating    = rating,
        mmr       = mmr,
        updatedAt = time(),
    }

    if NXR.PER_SPEC_BRACKETS[bracketIndex] then
        local specID = char.specID
        if not specID then
            NXR.Debug("SaveBracketData: per-spec bracket", bracketIndex, "but specID is nil for", key)
            return
        end
        char.specBrackets = char.specBrackets or {}
        char.specBrackets[specID] = char.specBrackets[specID] or {}
        char.specBrackets[specID][bracketIndex] = data
        AppendHistory(char, specID .. ":" .. bracketIndex, rating)
        NXR.Debug("SaveBracketData:", key, NXR.BRACKET_NAMES[bracketIndex] or bracketIndex,
            "rating=" .. rating, "spec=" .. specID)
    else
        char.brackets[bracketIndex] = data
        AppendHistory(char, bracketIndex, rating)
        NXR.Debug("SaveBracketData:", key, NXR.BRACKET_NAMES[bracketIndex] or bracketIndex,
            "rating=" .. rating)
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

function NXR.GetRatingHistory(charKey, bracketIndex, specID)
    local char = NelxRatedDB.characters[charKey]
    if not char or not char.ratingHistory then return nil end

    if NXR.PER_SPEC_BRACKETS[bracketIndex] then
        if not specID then return nil end
        return char.ratingHistory[specID .. ":" .. bracketIndex]
    else
        return char.ratingHistory[bracketIndex]
    end
end

local function CapturePvPStats()
    if not GetPersonalRatedInfo then
        NXR.Debug("CapturePvPStats: GetPersonalRatedInfo not available")
        return
    end

    NXR.UpdateCharacterInfo()
    NXR.Debug("CapturePvPStats: scanning brackets for", NXR.currentCharKey or "?")

    local captured = 0
    for _, bracketIndex in ipairs(NXR.TRACKED_BRACKETS) do
        local rating, seasonBest, weeklyBest, seasonPlayed, seasonWon, weeklyPlayed, weeklyWon, cap = GetPersonalRatedInfo(bracketIndex)
        if rating and rating > 0 then
            NXR.SaveBracketData(bracketIndex, rating, 0)
            captured = captured + 1
        else
            NXR.Debug("  bracket", NXR.BRACKET_NAMES[bracketIndex] or bracketIndex,
                "— rating:", tostring(rating), "(skipped)")
        end
    end
    NXR.Debug("CapturePvPStats: saved", captured, "brackets")

    if NXR.RefreshOverlay then
        NXR.RefreshOverlay()
    end
    if NXR.RefreshHistoryGraph then
        NXR.RefreshHistoryGraph()
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
            NXR.Debug("ADDON_LOADED complete — specs loaded:",
                NXR.TableCount(NXR.specData), "| active challenge:",
                NXR.GetActiveChallenge and NXR.GetActiveChallenge() and NXR.GetActiveChallenge().name or "none")
            self:UnregisterEvent("ADDON_LOADED")
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        NXR.Debug("Event: PLAYER_ENTERING_WORLD")
        NXR.UpdateCharacterInfo()

    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
        NXR.Debug("Event: ACTIVE_TALENT_GROUP_CHANGED")
        NXR.UpdateCharacterInfo()

    elseif event == "PVP_RATED_STATS_UPDATE" then
        NXR.Debug("Event: PVP_RATED_STATS_UPDATE", pvpStatsTimer and "(debounced)" or "(capturing)")
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
        print("  /nxr sync — Sync with other NelxRated accounts in party")
        print("  /nxr sync selftest — Test serialize/chunk/parse/merge pipeline locally")
        print("  /nxr debug — Toggle debug logging")
        print("  /nxr help — Show this help")
        return
    end
    if cmd == "debug" then
        debugMode = not debugMode
        print("|cffE6D200NelxRated|r debug " .. (debugMode and "ON" or "OFF"))
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
    if cmd == "sync" then
        local sub = (msg or ""):lower():match("^%s*%S+%s+(%S+)") or ""
        if sub == "selftest" then
            if NXR.SyncSelfTest then NXR.SyncSelfTest() end
        else
            if NXR.InitiateSync then NXR.InitiateSync() end
        end
        return
    end
    if NXR.ToggleMainFrame then
        NXR.ToggleMainFrame()
    end
end
