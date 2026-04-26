local addonName, NXR = ...

-- ============================================================================
-- Module-local state
-- ============================================================================

local snapshot         = {}   -- bracketIndex → seasonPlayed captured on instance entry
local pendingEnemySpecs = {}  -- populated by ARENA_PREP_OPPONENT_SPECIALIZATIONS
local pendingRecord    = nil  -- partial record held between PVP_MATCH_COMPLETE and UPDATE_BATTLEFIELD_SCORE

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

    -- ---- I-4 Stage 1: Detect bracket, stash partial record ----
    elseif event == "PVP_MATCH_COMPLETE" then
        local winner, duration = ...

        if NXR.InsightsDebug then
            print("[NXR Insights] PVP_MATCH_COMPLETE winner=" .. tostring(winner)
                .. " duration=" .. tostring(duration))
            local _, iType, _, iName = GetInstanceInfo()
            print("[NXR Insights] instance type=" .. tostring(iType) .. " name=" .. tostring(iName))
            for _, bi in ipairs(NXR.TRACKED_BRACKETS) do
                local info = C_PvP.GetRatedBracketInfo(bi)
                print("[NXR Insights] bracket " .. bi
                    .. " snapshot=" .. tostring(snapshot[bi])
                    .. " current=" .. (info and tostring(info.seasonPlayed) or "nil"))
            end
        end

        if not NXR.currentCharKey then
            NXR.Debug("Insights: no currentCharKey, skipping")
            return
        end

        local bracketIndex = DetectBracket()
        local charKey      = NXR.currentCharKey
        local specID
        local char = NelxRatedDB.characters[charKey]
        if char then specID = char.specID end

        pendingRecord = {
            timestamp    = time(),
            bracketIndex = bracketIndex,
            charKey      = charKey,
            specID       = specID,
            enemySpecs   = pendingEnemySpecs,
        }

        -- Consume and clear captured state
        pendingEnemySpecs = {}
        snapshot = {}

        NXR.Debug("Insights: Stage 1 complete — bracket=", tostring(bracketIndex),
            "charKey=", charKey)

    -- ---- I-4 Stage 2: Read score data, write record ----
    elseif event == "UPDATE_BATTLEFIELD_SCORE" then
        if not pendingRecord then return end

        -- Retry bracket detection if PVP_MATCH_COMPLETE fired while API was restricted
        if pendingRecord.bracketIndex == nil then
            pendingRecord.bracketIndex = DetectBracket()
            NXR.Debug("Insights: bracket retry on UPDATE_BATTLEFIELD_SCORE —",
                tostring(pendingRecord.bracketIndex))
        end

        local playerName = UnitName("player")
        local scoreEntry = nil
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
                    .. " mmrChange=" .. tostring(info.mmrChange)
                    .. " won=" .. tostring(info.won))
            end

            if info.name == playerName then
                scoreEntry = info
            end
            i = i + 1
        end

        if scoreEntry then
            pendingRecord.rating       = scoreEntry.rating
            pendingRecord.ratingChange = scoreEntry.ratingChange
            pendingRecord.prematchMMR  = scoreEntry.prematchMMR
            pendingRecord.mmrChange    = scoreEntry.mmrChange

            local rc = scoreEntry.ratingChange
            if rc == nil then
                pendingRecord.outcome = "unknown"
            elseif rc > 0 then
                pendingRecord.outcome = "win"
            elseif rc < 0 then
                pendingRecord.outcome = "loss"
            else
                pendingRecord.outcome = "draw"
            end
        else
            pendingRecord.outcome = "unknown"
            NXR.Debug("Insights: player entry not found in scorecard")
        end

        NelxRatedDB.matches[#NelxRatedDB.matches + 1] = pendingRecord
        NXR.Debug("Insights: match recorded — bracket=", tostring(pendingRecord.bracketIndex),
            "outcome=", pendingRecord.outcome,
            "rating=", tostring(pendingRecord.rating))
        pendingRecord = nil
    end
end)
