local addonName, NXR = ...

-- ============================================================================
-- Module-local state
-- ============================================================================

local snapshot         = {}   -- bracketIndex → rating from NelxRatedDB before match
local pendingEnemySpecs = {}  -- populated by ARENA_PREP_OPPONENT_SPECIALIZATIONS
local pendingRecord    = nil  -- partial record held between PVP_MATCH_COMPLETE and PVP_RATED_STATS_UPDATE

-- Solo Shuffle per-round tracking
local ssRounds        = {}    -- accumulated per-round records: { num, outcome, duration }
local ssRoundStart    = nil   -- GetTime() at state-3 onset for current round
local ssRoundPrevWins = 0     -- wins snapshot taken at round start
local ssActive        = false -- true only inside a confirmed SS match
local matchBracketHint = nil  -- bracket captured early as fallback for DB-diff detection

NXR.InsightsDebug = false

-- ============================================================================
-- Public accessor (I-5)
-- ============================================================================

function NXR.GetMatches()
    return NelxRatedDB.matches or {}
end

-- Only callable with InsightsDebug=true.
-- Removes records with no bracket or no rating.
-- For SS records: clears shuffle.rounds if captured rounds < 6 (keeps match-level data).
function NXR.PurgeCorruptMatches()
    if not NXR.InsightsDebug then
        print("[NXR] PurgeCorruptMatches requires InsightsDebug=true")
        return
    end
    local matches = NelxRatedDB.matches
    if not matches then print("[NXR] No match data."); return end

    local kept, removed, fixed = {}, 0, 0
    for _, r in ipairs(matches) do
        if not r.bracketIndex or not r.rating then
            removed = removed + 1
        else
            if r.shuffle and r.shuffle.rounds and #r.shuffle.rounds < 6 then
                r.shuffle.rounds = {}
                fixed = fixed + 1
            end
            kept[#kept + 1] = r
        end
    end

    NelxRatedDB.matches = kept
    print(("[NXR] Purge complete — removed %d, fixed %d SS round tables, kept %d"):format(
        removed, fixed, #kept))
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
    if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
    local n = (GetNumBattlefieldScores and GetNumBattlefieldScores()) or 0
    for i = 1, n do
        local info = C_PvP.GetScoreInfo(i)
        if not info then break end
        if NXR.InsightsDebug then
            print("[NXR Insights] score[" .. i .. "]"
                .. " name=" .. tostring(info.name)
                .. " isSelf=" .. tostring(info.isSelf)
                .. " rating=" .. tostring(info.rating)
                .. " ratingChange=" .. tostring(info.ratingChange)
                .. " prematchMMR=" .. tostring(info.prematchMMR)
                .. " mmrChange=" .. tostring(info.mmrChange))
        end
        if info.isSelf or info.name == playerName or info.name == playerFullName then
            pendingRec.rating       = info.rating
            pendingRec.ratingChange = info.ratingChange
            pendingRec.prematchMMR  = info.prematchMMR
            local pre  = tonumber(info.prematchMMR) or 0
            local post = tonumber(info.postmatchMMR) or 0
            pendingRec.mmrChange    = (pre > 0 and post > 0) and (post - pre) or (tonumber(info.mmrChange) or 0)
            -- Solo Shuffle: stats[1].pvpStatValue holds total rounds won
            if info.stats and info.stats[1] and type(info.stats[1].pvpStatValue) == "number" then
                pendingRec.wonRounds = info.stats[1].pvpStatValue
            end
            pendingRec.scoreLoaded  = true
            return
        end
    end
end

-- Read the player's current Solo Shuffle round-win count from the scoreboard.
-- Caller should invoke RequestBattlefieldScoreData() before this if available.
-- Returns a number (0 on miss) — never nil, safe to compare with ssRoundPrevWins.
local function GetMyCurrentWins()
    if not C_PvP or not C_PvP.GetScoreInfo then return 0 end
    local playerName     = UnitName("player")
    local playerFullName = playerName and (playerName .. "-" .. GetRealmName()) or nil
    local n              = (GetNumBattlefieldScores and GetNumBattlefieldScores()) or 0
    for i = 1, n do
        local info = C_PvP.GetScoreInfo(i)
        if not info then break end
        if info.isSelf or info.name == playerName or info.name == playerFullName then
            if info.stats and info.stats[1] and type(info.stats[1].pvpStatValue) == "number" then
                return info.stats[1].pvpStatValue
            end
            return 0
        end
    end
    return 0
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
        self:RegisterEvent("PVP_MATCH_ACTIVE")
        self:RegisterEvent("PLAYER_LEAVING_WORLD")
        self:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS")
        self:RegisterEvent("PVP_MATCH_STATE_CHANGED")
        self:RegisterEvent("PVP_MATCH_COMPLETE")
        self:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
        self:RegisterEvent("PVP_RATED_STATS_UPDATE")

    -- ---- SS match start: init per-round state ----
    elseif event == "PVP_MATCH_ACTIVE" then
        local isSS = C_PvP and C_PvP.IsSoloShuffle and C_PvP.IsSoloShuffle()
        -- SS fires PVP_MATCH_ACTIVE on every round zone-in; IsSoloShuffle() returns false
        -- during the zone transition. If we already confirmed this is SS (hint set from a
        -- prior round's state-change recovery), preserve accumulated rounds and re-arm.
        if not isSS and matchBracketHint == NXR.BRACKET_SOLO_SHUFFLE then
            ssActive = true
            NXR.DebugInsights("PVP_MATCH_ACTIVE: SS round zone-in, preserving state rounds=", #ssRounds)
            return
        end
        ssActive           = isSS and true or false
        matchBracketHint   = isSS and NXR.BRACKET_SOLO_SHUFFLE or nil
        ssRounds           = {}
        ssRoundStart       = nil
        ssRoundPrevWins    = 0
        NXR.DebugInsights("PVP_MATCH_ACTIVE isSS=", tostring(ssActive))

    -- ---- I-2: DB snapshot before zone transition (no API restriction risk) ----
    elseif event == "PLAYER_LEAVING_WORLD" then
        TakeDBSnapshot(NXR.currentCharKey)
        if ssActive then
            -- SS zones between every round — preserve accumulated ssRounds across zone-outs.
            -- Only clear per-round timing; ssActive re-armed at next state=3.
            ssRoundStart = nil
            ssActive     = false
            NXR.DebugInsights("PLAYER_LEAVING_WORLD: SS inter-round zone, preserving", #ssRounds, "rounds")
        end

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

    -- ---- SS round tracking via match state transitions ----
    elseif event == "PVP_MATCH_STATE_CHANGED" then
        local newState = C_PvP and C_PvP.GetActiveMatchState and C_PvP.GetActiveMatchState()
        newState = tonumber(newState)
        if not newState then return end

        local liveSS = C_PvP and C_PvP.IsSoloShuffle and C_PvP.IsSoloShuffle()
        NXR.DebugInsights("PVP_MATCH_STATE_CHANGED state=", newState,
            "ssActive=", tostring(ssActive), "liveSS=", tostring(liveSS),
            "rounds so far=", #ssRounds)

        -- IsSoloShuffle() can return false at PVP_MATCH_ACTIVE time — check live as fallback
        if not ssActive then
            if liveSS then
                ssActive         = true
                matchBracketHint = NXR.BRACKET_SOLO_SHUFFLE
            else
                return
            end
        end

        if newState == 2 then
            -- Enum.PvPMatchState.Engaged (Midnight: 2) — round starting
            ssRoundStart = GetTime()
            if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
            C_Timer.After(0.2, function()
                ssRoundPrevWins = GetMyCurrentWins()
                NXR.DebugInsights("Round start wins snapshot:", ssRoundPrevWins)
            end)

        elseif ssRoundStart ~= nil then
            -- Any non-Engaged state while a round was active = round ended.
            -- Avoids hardcoding PostRound value (3? 4?) which varies by build.
            local capturedStart = ssRoundStart
            if not capturedStart then
                NXR.DebugInsights("state", newState, "but no ssRoundStart — skipping")
                return
            end

            ssRoundStart = nil  -- clear immediately to prevent double-capture

            local roundNum  = #ssRounds + 1
            local duration  = math.floor(GetTime() - capturedStart)
            local prevWins  = ssRoundPrevWins

            if roundNum <= 6 then
                -- Insert placeholder; outcome resolved after scoreboard delay
                local roundEntry = { num = roundNum, outcome = "unknown", duration = duration }
                ssRounds[roundNum] = roundEntry

                C_Timer.After(0.6, function()
                    if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
                    C_Timer.After(0.2, function()
                        local newWins = GetMyCurrentWins()
                        roundEntry.outcome  = newWins > prevWins and "win" or "loss"
                        ssRoundPrevWins     = newWins
                        NXR.DebugInsights("Round", roundNum, "outcome:", roundEntry.outcome,
                            "wins:", prevWins, "->", newWins)
                    end)
                end)
            else
                NXR.DebugInsights("roundNum > 6, skipping (roundNum=", roundNum, ")")
            end
        end

    -- ---- I-4 Stage 1: Stash partial record ----
    elseif event == "PVP_MATCH_COMPLETE" then
        -- Match is over — no more rounds will start; stop processing state changes
        ssActive = false

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
            timestamp    = time(),
            charKey      = charKey,
            specID       = specID,
            enemySpecs   = pendingEnemySpecs,
            bracketHint  = matchBracketHint,
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

            -- Detect bracket by comparing pre-match DB snapshot vs Core.lua's new values;
            -- fall back to hint captured at match start if DB diff finds no change
            rec.bracketIndex = DetectBracketFromDB(rec.charKey) or rec.bracketHint
            rec.bracketHint  = nil
            NXR.DebugInsights("bracket detected —", tostring(rec.bracketIndex))

            -- Derive outcome: SS uses wonRounds; all other brackets use ratingChange sign
            if rec.bracketIndex == NXR.BRACKET_SOLO_SHUFFLE then
                local wr = rec.wonRounds
                if type(wr) == "number" then
                    if wr > 3 then
                        rec.outcome = "win"
                    elseif wr < 3 then
                        rec.outcome = "loss"
                    else
                        rec.outcome = "draw"
                    end
                else
                    -- wonRounds unavailable — fall back to ratingChange sign
                    NXR.DebugInsights("SS outcome fallback to ratingChange (wonRounds nil)")
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
                end
            else
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
            end

            -- SS shuffle data: trust scoreboard totals (reliable), only include
            -- rounds[] breakdown when state-change tracking captured all 6
            -- (per-round states don't fire reliably in Midnight 12.x).
            if rec.bracketIndex == NXR.BRACKET_SOLO_SHUFFLE then
                local won   = rec.wonRounds or 0
                local total = 6
                rec.shuffle = {
                    wonRounds   = won,
                    lostRounds  = total - won,
                    totalRounds = total,
                }
                if #ssRounds == total then
                    local capturedRounds = {}
                    for i = 1, total do
                        capturedRounds[i] = ssRounds[i]
                    end
                    rec.shuffle.rounds = capturedRounds
                    NXR.DebugInsights("shuffle: full per-round capture (", total, "rounds)")
                else
                    NXR.DebugInsights("shuffle: partial capture (", #ssRounds, "/", total,
                        ") — omitting rounds[], totals only")
                end
                ssRounds        = {}
                ssRoundStart    = nil
                ssRoundPrevWins = 0
                ssActive        = false
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
