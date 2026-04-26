local addonName, NXR = ...

-- ============================================================================
-- Module-local state
-- ============================================================================

local snapshot         = {}   -- bracketIndex → seasonPlayed captured on instance entry
local pendingEnemySpecs = {}  -- populated by ARENA_PREP_OPPONENT_SPECIALIZATIONS
local pendingRecord    = nil  -- partial record held between PVP_MATCH_COMPLETE and PVP_RATED_STATS_UPDATE

NXR.InsightsDebug = false

-- ============================================================================
-- Public accessor (I-5)
-- ============================================================================

function NXR.GetMatches()
    return NelxRatedDB.matches or {}
end

-- ============================================================================
-- Internal helpers
-- ============================================================================

local function TakeSnapshot()
    if not C_PvP.GetRatedBracketInfo then
        NXR.Debug("Insights: GetRatedBracketInfo unavailable, snapshot skipped")
        return
    end
    for _, bracketIndex in ipairs(NXR.TRACKED_BRACKETS) do
        local info = C_PvP.GetRatedBracketInfo(bracketIndex)
        if info and info.seasonPlayed ~= nil then
            snapshot[bracketIndex] = info.seasonPlayed
        end
    end
    NXR.Debug("Insights: snapshot —",
        "2v2=" .. tostring(snapshot[NXR.BRACKET_2V2]),
        "3v3=" .. tostring(snapshot[NXR.BRACKET_3V3]),
        "blitz=" .. tostring(snapshot[NXR.BRACKET_BLITZ]),
        "ss=" .. tostring(snapshot[NXR.BRACKET_SOLO_SHUFFLE]))
end

local function DetectBracket()
    if not C_PvP.GetRatedBracketInfo then return nil end
    for _, bracketIndex in ipairs(NXR.TRACKED_BRACKETS) do
        local info = C_PvP.GetRatedBracketInfo(bracketIndex)
        if info and info.seasonPlayed ~= nil then
            local prev = snapshot[bracketIndex]
            if prev ~= nil and info.seasonPlayed == prev + 1 then
                return bracketIndex
            end
        end
    end
    return nil
end

-- ============================================================================
-- Event frame
-- ============================================================================

local insightsFrame = CreateFrame("Frame")
insightsFrame:RegisterEvent("ADDON_LOADED")

insightsFrame:SetScript("OnEvent", function(self, event, ...)
    -- ---- I-1: Bootstrap after addon loads ----
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_LEAVING_WORLD")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
        self:RegisterEvent("PVP_MATCH_COMPLETE")
        self:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
        self:RegisterEvent("PVP_RATED_STATS_UPDATE")

    -- ---- I-2a: Bracket snapshot before any zone transition (unrestricted context) ----
    elseif event == "PLAYER_LEAVING_WORLD" then
        TakeSnapshot()

    -- ---- I-2b: Bracket snapshot on arena/pvp entry (fallback, may be restricted) ----
    elseif event == "PLAYER_ENTERING_WORLD" then
        local _, instanceType = GetInstanceInfo()
        if instanceType == "arena" or instanceType == "pvp" then
            TakeSnapshot()
        end

    -- ---- I-3: Enemy spec capture ----
    elseif event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" then
        pendingEnemySpecs = {}
        local count = GetNumArenaOpponentSpecs()
        for i = 1, count do
            local specID = GetArenaOpponentSpec(i)
            pendingEnemySpecs[i] = (specID and specID ~= 0) and specID or 0
        end
        NXR.Debug("Insights: enemy specs captured, count=", count)

    -- ---- I-4 Stage 1: Stash partial record (API restricted here, defer detection) ----
    elseif event == "PVP_MATCH_COMPLETE" then
        local winner, duration = ...

        if NXR.InsightsDebug then
            print("[NXR Insights] PVP_MATCH_COMPLETE winner=" .. tostring(winner)
                .. " duration=" .. tostring(duration))
            local _, iType, _, iName = GetInstanceInfo()
            print("[NXR Insights] instance type=" .. tostring(iType) .. " name=" .. tostring(iName))
            for _, bi in ipairs(NXR.TRACKED_BRACKETS) do
                local info = C_PvP.GetRatedBracketInfo and C_PvP.GetRatedBracketInfo(bi)
                print("[NXR Insights] bracket " .. bi
                    .. " snapshot=" .. tostring(snapshot[bi])
                    .. " current=" .. (info and tostring(info.seasonPlayed) or "nil"))
            end
        end

        if not NXR.currentCharKey then
            NXR.Debug("Insights: no currentCharKey, skipping")
            return
        end

        local charKey = NXR.currentCharKey
        local specID
        local char = NelxRatedDB.characters[charKey]
        if char then specID = char.specID end

        pendingRecord = {
            timestamp  = time(),
            charKey    = charKey,
            specID     = specID,
            enemySpecs = pendingEnemySpecs,
        }

        pendingEnemySpecs = {}
        -- snapshot kept alive until PVP_RATED_STATS_UPDATE for DetectBracket

        NXR.Debug("Insights: Stage 1 complete — charKey=", charKey)

    -- ---- I-4 Stage 2: Accumulate score data (best-effort, may still be restricted) ----
    elseif event == "UPDATE_BATTLEFIELD_SCORE" then
        if not pendingRecord or pendingRecord.scoreLoaded then return end

        local playerName     = UnitName("player")
        local playerFullName = playerName and (playerName .. "-" .. GetRealmName()) or nil
        local i = 0

        while true do
            local info = C_PvP.GetScoreInfo(i)
            if not info then break end

            if NXR.InsightsDebug then
                print("[NXR Insights] score[" .. i .. "]"
                    .. " name=" .. tostring(info.name)
                    .. " rating=" .. tostring(info.rating)
                    .. " ratingChange=" .. tostring(info.ratingChange)
                    .. " prematchMMR=" .. tostring(info.prematchMMR)
                    .. " mmrChange=" .. tostring(info.mmrChange))
            end

            if info.name == playerName or info.name == playerFullName then
                pendingRecord.rating       = info.rating
                pendingRecord.ratingChange = info.ratingChange
                pendingRecord.prematchMMR  = info.prematchMMR
                pendingRecord.mmrChange    = info.mmrChange
                pendingRecord.scoreLoaded  = true
                break
            end
            i = i + 1
        end

        if not pendingRecord.scoreLoaded then
            NXR.Debug("Insights: score not found in UPDATE_BATTLEFIELD_SCORE, will retry")
        end

    -- ---- I-4 Stage 3: Detect bracket + finalize (API confirmed available here) ----
    elseif event == "PVP_RATED_STATS_UPDATE" then
        if not pendingRecord then return end

        -- Bracket detection: API available at this event (confirmed by Core.lua usage)
        pendingRecord.bracketIndex = DetectBracket()
        NXR.Debug("Insights: bracket detected —", tostring(pendingRecord.bracketIndex))

        -- Retry score data if UPDATE_BATTLEFIELD_SCORE didn't find it
        if not pendingRecord.scoreLoaded then
            local playerName     = UnitName("player")
            local playerFullName = playerName and (playerName .. "-" .. GetRealmName()) or nil
            local i = 0
            while true do
                local info = C_PvP.GetScoreInfo(i)
                if not info then break end
                if info.name == playerName or info.name == playerFullName then
                    pendingRecord.rating       = info.rating
                    pendingRecord.ratingChange = info.ratingChange
                    pendingRecord.prematchMMR  = info.prematchMMR
                    pendingRecord.mmrChange    = info.mmrChange
                    pendingRecord.scoreLoaded  = true
                    break
                end
                i = i + 1
            end
        end

        local rc = pendingRecord.ratingChange
        if rc == nil then
            pendingRecord.outcome = "unknown"
        elseif rc > 0 then
            pendingRecord.outcome = "win"
        elseif rc < 0 then
            pendingRecord.outcome = "loss"
        else
            pendingRecord.outcome = "draw"
        end

        pendingRecord.scoreLoaded = nil  -- don't persist internal flag

        NelxRatedDB.matches[#NelxRatedDB.matches + 1] = pendingRecord
        NXR.Debug("Insights: match recorded — bracket=", tostring(pendingRecord.bracketIndex),
            "outcome=", pendingRecord.outcome,
            "rating=", tostring(pendingRecord.rating))

        pendingRecord = nil
        snapshot = {}
    end
end)
