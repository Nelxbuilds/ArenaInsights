local addonName, AI = ...
_G.AI = AI  -- expose for /run and external tooling

-- ============================================================================
-- Bracket constants
-- ============================================================================

AI.BRACKET_2V2          = 1
AI.BRACKET_3V3          = 2
AI.BRACKET_BLITZ        = 4
AI.BRACKET_SOLO_SHUFFLE = 7

AI.BRACKET_NAMES = {
    [1] = "2v2",
    [2] = "3v3",
    [4] = "Blitz BG",
    [7] = "Solo Shuffle",
}

AI.TRACKED_BRACKETS = { 1, 2, 4, 7 }

AI.PER_SPEC_BRACKETS = {
    [4] = true,   -- Blitz BG (per-spec rating)
    [7] = true,   -- Solo Shuffle (per-spec rating)
}

-- ============================================================================
-- Color palette
-- ============================================================================

AI.COLORS = {
    CRIMSON_BRIGHT = { 0.9, 0.15, 0.15 },
    CRIMSON_MID    = { 0.7, 0.1, 0.1 },
    CRIMSON_DIM    = { 0.35, 0.05, 0.05 },
    GOLD           = { 1.0, 0.82, 0.0 },
}

-- ============================================================================
-- Debug logging
-- ============================================================================

local debugMode = false

function AI.Debug(...)
    if not debugMode then return end
    print("|cff888888[AI]|r", ...)
end

function AI.DebugInsights(...)
    if not AI.InsightsDebug then return end
    print("|cff888888[AI Insights]|r", ...)
end

function AI.TableCount(t)
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
    showMinimapButton        = true,
    disableTooltip           = false,
    minimapPosition          = {},
    hiddenCurrencies         = {},
    hiddenItems              = {},
}

local CURRENT_SCHEMA = 2

local MIGRATIONS = {
    [2] = function(db)
        db.matches = db.matches or {}
    end,
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
    ArenaInsightsDB = ArenaInsightsDB or {}

    ArenaInsightsDB.settings              = ArenaInsightsDB.settings or {}
    ArenaInsightsDB.characters            = ArenaInsightsDB.characters or {}
    ArenaInsightsDB.challenges            = ArenaInsightsDB.challenges or {}
    ArenaInsightsDB.overlayPosition       = ArenaInsightsDB.overlayPosition or {}
    ArenaInsightsDB.schemaVersion         = ArenaInsightsDB.schemaVersion or 0
    ArenaInsightsDB.deletedChallengeUIDs  = ArenaInsightsDB.deletedChallengeUIDs or {}
    ArenaInsightsDB.syncPartners          = ArenaInsightsDB.syncPartners or {}
    ArenaInsightsDB.matches               = ArenaInsightsDB.matches or {}

    RunMigrations(ArenaInsightsDB)
    AI.Debug("InitDB complete — schema", ArenaInsightsDB.schemaVersion,
        "| chars:", AI.TableCount(ArenaInsightsDB.characters),
        "| challenges:", #ArenaInsightsDB.challenges)

    for k, v in pairs(SETTINGS_DEFAULTS) do
        if ArenaInsightsDB.settings[k] == nil then
            ArenaInsightsDB.settings[k] = v
        end
    end
end

-- ============================================================================
-- Character information capture
-- ============================================================================

function AI.UpdateCharacterInfo()
    local name, realm = UnitName("player")
    realm = (realm and realm ~= "") and realm or GetRealmName()
    if not name or not realm then return end

    local key = name .. "-" .. realm
    AI.currentCharKey = key

    local classDisplayName, classFileName = UnitClass("player")
    local _, raceFileName = UnitRace("player")
    local gender = UnitSex("player")

    local specIndex = GetSpecialization()
    local specID, specName
    if specIndex then
        specID, specName = GetSpecializationInfo(specIndex)
    end

    local char = ArenaInsightsDB.characters[key] or { brackets = {}, specBrackets = {} }
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
    char.account          = ArenaInsightsDB.settings.accountName
    char.raceFileName     = raceFileName
    char.gender           = gender

    ArenaInsightsDB.characters[key] = char
    AI.Debug("UpdateCharacterInfo:", key, classFileName or "?",
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

function AI.SaveBracketData(bracketIndex, rating, mmr)
    local key = AI.currentCharKey
    if not key then
        AI.Debug("SaveBracketData: no currentCharKey, skipping")
        return
    end

    local char = ArenaInsightsDB.characters[key]
    if not char then
        AI.Debug("SaveBracketData: char not found for", key)
        return
    end

    local data = {
        rating    = rating,
        mmr       = mmr,
        updatedAt = time(),
    }

    if AI.PER_SPEC_BRACKETS[bracketIndex] then
        local specID = char.specID
        if not specID then
            AI.Debug("SaveBracketData: per-spec bracket", bracketIndex, "but specID is nil for", key)
            return
        end
        char.specBrackets = char.specBrackets or {}
        char.specBrackets[specID] = char.specBrackets[specID] or {}
        char.specBrackets[specID][bracketIndex] = data
        AppendHistory(char, specID .. ":" .. bracketIndex, rating)
        AI.Debug("SaveBracketData:", key, AI.BRACKET_NAMES[bracketIndex] or bracketIndex,
            "rating=" .. rating, "spec=" .. specID)
    else
        char.brackets[bracketIndex] = data
        AppendHistory(char, bracketIndex, rating)
        AI.Debug("SaveBracketData:", key, AI.BRACKET_NAMES[bracketIndex] or bracketIndex,
            "rating=" .. rating)
    end
end

function AI.GetRating(charKey, bracketIndex, specID)
    local char = ArenaInsightsDB.characters[charKey]
    if not char then return nil end

    if AI.PER_SPEC_BRACKETS[bracketIndex] then
        local sb = char.specBrackets and char.specBrackets[specID]
        return sb and sb[bracketIndex]
    else
        return char.brackets and char.brackets[bracketIndex]
    end
end

function AI.GetRatingHistory(charKey, bracketIndex, specID)
    local char = ArenaInsightsDB.characters[charKey]
    if not char or not char.ratingHistory then return nil end

    if AI.PER_SPEC_BRACKETS[bracketIndex] then
        if not specID then return nil end
        return char.ratingHistory[specID .. ":" .. bracketIndex]
    else
        return char.ratingHistory[bracketIndex]
    end
end

local function CapturePvPStats()
    if not GetPersonalRatedInfo then
        AI.Debug("CapturePvPStats: GetPersonalRatedInfo not available")
        return
    end

    AI.UpdateCharacterInfo()
    AI.Debug("CapturePvPStats: scanning brackets for", AI.currentCharKey or "?")

    local captured = 0
    for _, bracketIndex in ipairs(AI.TRACKED_BRACKETS) do
        local rating, seasonBest, weeklyBest, seasonPlayed, seasonWon, weeklyPlayed, weeklyWon, cap = GetPersonalRatedInfo(bracketIndex)
        if rating and rating > 0 then
            AI.SaveBracketData(bracketIndex, rating, 0)
            captured = captured + 1
        else
            AI.Debug("  bracket", AI.BRACKET_NAMES[bracketIndex] or bracketIndex,
                "— rating:", tostring(rating), "(skipped)")
        end
    end
    AI.Debug("CapturePvPStats: saved", captured, "brackets")

    if AI.RefreshOverlay then
        AI.RefreshOverlay()
    end
    if AI.RefreshHistoryGraph then
        AI.RefreshHistoryGraph()
    end
end

-- ============================================================================
-- Event handling
-- ============================================================================

StaticPopupDialogs["ARENAINSIGHTS_MIGRATION"] = {
    text = "|cffE6D200ArenaInsights|r was renamed from |cffFFFFFFNelxRated|r.\nYour old data can be recovered in one step:\n\n1. Exit the game completely\n2. Go to: WTF/Account/<Name>/SavedVariables/\n3. Rename |cffFFFFFFNelxRated.lua|r to |cffFFFFFFArenaInsights.lua|r\n4. Restart and your data will migrate automatically.\n\nIf you have no old data to recover, click Skip.",
    button1 = "Understood",
    button2 = "Skip",
    timeout = 0,
    whileDead = true,
    hideOnEscape = false,
    OnAccept = function()
        -- closes popup; shows again next login as a reminder until migration is done
    end,
    OnCancel = function()
        if ArenaInsightsDB and ArenaInsightsDB.settings then
            ArenaInsightsDB.settings.migrationDismissed = true
        end
    end,
}

local pvpStatsTimer = nil

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
eventFrame:RegisterEvent("PVP_RATED_STATS_UPDATE")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            -- Silent SavedVariables migration: NelxRatedDB -> ArenaInsightsDB
            -- Must run before InitDB() so existing user data is preserved.
            -- Guard: check for actual character data, not just table existence —
            -- WoW pre-initializes ArenaInsightsDB from the file before ADDON_LOADED,
            -- so "not ArenaInsightsDB" is always false even when the table is empty.
            local hasData = ArenaInsightsDB and ArenaInsightsDB.characters and next(ArenaInsightsDB.characters)
            if NelxRatedDB and not hasData then
                ArenaInsightsDB = NelxRatedDB
                NelxRatedDB = nil
                -- Mark migration done so the popup never shows again
                ArenaInsightsDB.settings = ArenaInsightsDB.settings or {}
                ArenaInsightsDB.settings.migrationDismissed = true
            end
            InitDB()
            if AI.BuildSpecData then AI.BuildSpecData() end
            if AI.InitChallenges then AI.InitChallenges() end
            AI.Debug("ADDON_LOADED complete — specs loaded:",
                AI.TableCount(AI.specData), "| active challenge:",
                AI.GetActiveChallenge and AI.GetActiveChallenge() and AI.GetActiveChallenge().name or "none")
            self:UnregisterEvent("ADDON_LOADED")
        end

    elseif event == "PLAYER_LOGIN" then
        if not (ArenaInsightsDB.settings and ArenaInsightsDB.settings.migrationDismissed) then
            StaticPopup_Show("ARENAINSIGHTS_MIGRATION")
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        AI.Debug("Event: PLAYER_ENTERING_WORLD")
        AI.UpdateCharacterInfo()

    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
        AI.Debug("Event: ACTIVE_TALENT_GROUP_CHANGED")
        AI.UpdateCharacterInfo()

    elseif event == "PVP_RATED_STATS_UPDATE" then
        AI.Debug("Event: PVP_RATED_STATS_UPDATE", pvpStatsTimer and "(debounced)" or "(capturing)")
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

SLASH_ARENAINSIGHTS1 = "/ai"
SlashCmdList["ARENAINSIGHTS"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S+)") or ""
    if cmd == "help" then
        print("|cffE6D200ArenaInsights|r commands:")
        print("  /ai — Open the main window")
        print("  /ai overlay — Toggle overlay visibility")
        print("  /ai lock — Lock overlay position")
        print("  /ai unlock — Unlock overlay position")
        print("  /ai sync — Sync with other ArenaInsights accounts in party")
        print("  /ai sync selftest — Test serialize/chunk/parse/merge pipeline locally")
        print("  /ai debug — Toggle debug logging")
        print("  /ai help — Show this help")
        return
    end
    if cmd == "debug" then
        debugMode = not debugMode
        print("|cffE6D200ArenaInsights|r debug " .. (debugMode and "ON" or "OFF"))
        return
    end
    if cmd == "overlay" then
        if AI.Overlay and AI.Overlay.Toggle then
            AI.Overlay.Toggle()
        end
        return
    end
    if cmd == "lock" then
        if AI.Overlay and AI.Overlay.SetLocked then
            AI.Overlay.SetLocked(true)
        end
        return
    end
    if cmd == "unlock" then
        if AI.Overlay and AI.Overlay.SetLocked then
            AI.Overlay.SetLocked(false)
        end
        return
    end
    if cmd == "sync" then
        local sub = (msg or ""):lower():match("^%s*%S+%s+(%S+)") or ""
        if sub == "selftest" then
            if AI.SyncSelfTest then AI.SyncSelfTest() end
        else
            if AI.InitiateSync then AI.InitiateSync() end
        end
        return
    end
    if AI.ToggleMainFrame then
        AI.ToggleMainFrame()
    end
end
