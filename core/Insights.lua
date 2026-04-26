local addonName, NXR = ...

-- ============================================================================
-- Module-local state
-- ============================================================================

local snapshot         = {}   -- bracketIndex → rating from NelxRatedDB before match
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

-- Read current saved ratings from NelxRatedDB into snapshot.
-- No WoW PvP API calls — safe at any time, including during zone transitions.
local function TakeDBSnapshot(charKey)
    local char = charKey
        and NelxRatedDB
        and NelxRatedDB.characters
        and NelxRatedDB.characters[charKey]
    snapshot = {}
    if not char then
        NXR.DebugInsights("TakeDBSnapshot: no char data for", tostring(charKey))
        return
    end
    for _, bi in ipairs(NXR.TRACKED_BRACKETS) do
        local data
        if NXR.PER_SPEC_BRACKETS[bi] then
            local specID = char.specID
            if specID and char.specBrackets and char.specBrackets[specID] then
                data = char.specBrackets[specID][bi]
            end
        else
            if char.brackets then
                data = char.brackets[bi]
            end
        end
        snapshot[bi] = data and data.rating
    end
    NXR.DebugInsights("TakeDBSnapshot:",
        "2v2=" .. tostring(snapshot[NXR.BRACKET_2V2]),
        "3v3=" .. tostring(snapshot[NXR.BRACKET_3V3]),
        "blitz=" .. tostring(snapshot[NXR.BRACKET_BLITZ]),
        "ss=" .. tostring(snapshot[NXR.BRACKET_SOLO_SHUFFLE]))
end

-- Compare current NelxRatedDB ratings vs snapshot to find the bracket that changed.
-- Called one frame after PVP_RATED_STATS_UPDATE so Core.lua has already written new values.
local function DetectBracketFromDB(charKey)
    local char = charKey
        and NelxRatedDB
        and NelxRatedDB.characters
        and NelxRatedDB.characters[charKey]
    if not char then return nil end

    for _, bi in ipairs(NXR.TRACKED_BRACKETS) do
        local prev = snapshot[bi]
        if prev ~= nil then
            local data
            if NXR.PER_SPEC_BRACKETS[bi] then
                local specID = char.specID
                if specID and char.specBrackets and char.specBrackets[specID] then
                    data = char.specBrackets[specID][bi]
                end
            else
                if char.brackets then
                    data = char.brackets[bi]
                end
            end

            local current = data and data.rating
            if current ~= nil and current ~= prev then
                NXR.DebugInsights("DetectBracketFromDB: bracket", bi,
                    "changed", prev, "->", current)
                return bi
            end
        end
    end
    return nil
end

local function FindScoreEntry(pendingRec)
    if not C_PvP.GetScoreInfo then return end
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
            pendingRec.rating       = info.rating
            pendingRec.ratingChange = info.ratingChange
            pendingRec.prematchMMR  = info.prematchMMR
            pendingRec.mmrChange    = info.mmrChange
            pendingRec.scoreLoaded  = true
            return
        end
        i = i + 1
    end
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
        self:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
        self:RegisterEvent("PVP_MATCH_COMPLETE")
        self:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
        self:RegisterEvent("PVP_RATED_STATS_UPDATE")

    -- ---- I-2: DB snapshot before zone transition (no API restriction risk) ----
    elseif event == "PLAYER_LEAVING_WORLD" then
        TakeDBSnapshot(NXR.currentCharKey)

    -- ---- I-3: Enemy spec capture ----
    elseif event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" then
        pendingEnemySpecs = {}
        local count = GetNumArenaOpponentSpecs()
        for i = 1, count do
            local specID = GetArenaOpponentSpec(i)
            pendingEnemySpecs[i] = (specID and specID ~= 0) and specID or 0
        end
        NXR.DebugInsights("enemy specs captured, count=", count)
        -- Refresh snapshot in case PLAYER_LEAVING_WORLD missed the char
        if not snapshot[NXR.BRACKET_SOLO_SHUFFLE] and not snapshot[NXR.BRACKET_2V2] then
            TakeDBSnapshot(NXR.currentCharKey)
        end

    -- ---- I-4 Stage 1: Stash partial record ----
    elseif event == "PVP_MATCH_COMPLETE" then
        local winner, duration = ...

        if NXR.InsightsDebug then
            print("[NXR Insights] PVP_MATCH_COMPLETE winner=" .. tostring(winner)
                .. " duration=" .. tostring(duration))
            local _, iType, _, iName = GetInstanceInfo()
            print("[NXR Insights] instance type=" .. tostring(iType) .. " name=" .. tostring(iName))
            for _, bi in ipairs(NXR.TRACKED_BRACKETS) do
                print("[NXR Insights] bracket " .. bi .. " snapshot=" .. tostring(snapshot[bi]))
            end
        end

        if not NXR.currentCharKey then
            NXR.DebugInsights("no currentCharKey, skipping")
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
        NXR.DebugInsights("Stage 1 complete — charKey=", charKey)

    -- ---- I-4 Stage 2: Accumulate score data (best-effort) ----
    elseif event == "UPDATE_BATTLEFIELD_SCORE" then
        if not pendingRecord or pendingRecord.scoreLoaded then return end
        FindScoreEntry(pendingRecord)
        if not pendingRecord.scoreLoaded then
            NXR.DebugInsights("score not found in UPDATE_BATTLEFIELD_SCORE, will retry")
        end

    -- ---- I-4 Stage 3: Finalize one frame after Core.lua writes new ratings ----
    elseif event == "PVP_RATED_STATS_UPDATE" then
        if not pendingRecord then return end

        local rec = pendingRecord
        pendingRecord = nil  -- clear now; timer callback captures rec

        C_Timer.After(0, function()
            -- Retry score data if still missing
            if not rec.scoreLoaded then
                FindScoreEntry(rec)
            end

            -- Detect bracket by comparing pre-match DB snapshot vs Core.lua's new values
            rec.bracketIndex = DetectBracketFromDB(rec.charKey)
            NXR.DebugInsights("bracket detected —", tostring(rec.bracketIndex))

            local rc = rec.ratingChange
            if rc == nil then
                rec.outcome = "unknown"
            elseif rc > 0 then
                rec.outcome = "win"
            elseif rc < 0 then
                rec.outcome = "loss"
            else
                rec.outcome = "draw"
            end

            rec.scoreLoaded = nil  -- don't persist internal flag

            NelxRatedDB.matches[#NelxRatedDB.matches + 1] = rec
            NXR.DebugInsights("match recorded — bracket=", tostring(rec.bracketIndex),
                "outcome=", rec.outcome,
                "rating=", tostring(rec.rating))

            snapshot = {}
        end)
    end
end)
