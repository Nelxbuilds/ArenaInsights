local addonName, AI = ...

-- ============================================================================
-- Module-local state
-- ============================================================================

local snapshot          = {}   -- bracketIndex → rating from ArenaInsightsDB before match
local pendingEnemySpecs = {}  -- populated by ARENA_PREP_OPPONENT_SPECIALIZATIONS
local pendingAllySpecs  = {}  -- teammate specs captured at ARENA_PREP (best-effort, inspect cache)
local pendingRecord    = nil  -- partial record held between PVP_MATCH_COMPLETE and PVP_RATED_STATS_UPDATE

-- Solo Shuffle per-round tracking
local ssRounds        = {}    -- accumulated per-round records: { num, outcome, duration, allySpecs, enemySpecs }
local ssRoundStart    = nil   -- GetTime() at state-3 onset for current round
local ssRoundPrevWins = 0     -- wins snapshot taken at round start
local ssRoundComp     = nil   -- { allySpecs={}, enemySpecs={} } captured at round start
local ssActive        = false -- true only inside a confirmed SS match
local matchBracketHint = nil  -- bracket captured early as fallback for DB-diff detection

AI.InsightsDebug = false

-- ============================================================================
-- Public accessor (I-5)
-- ============================================================================

function AI.GetMatches()
    return ArenaInsightsDB.matches or {}
end

-- Only callable with InsightsDebug=true.
-- Removes records with no bracket or no rating.
-- For SS records: clears shuffle.rounds if captured rounds < 6 (keeps match-level data).
function AI.PurgeCorruptMatches()
    if not AI.InsightsDebug then
        print("[AI] PurgeCorruptMatches requires InsightsDebug=true")
        return
    end
    local matches = ArenaInsightsDB.matches
    if not matches then print("[AI] No match data."); return end

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

    ArenaInsightsDB.matches = kept
    print(("[AI] Purge complete — removed %d, fixed %d SS round tables, kept %d"):format(
        removed, fixed, #kept))
end

-- ============================================================================
-- Internal helpers
-- ============================================================================

-- Identify the bracket of the currently active rated match using live PvP API.
-- Priority: SS/Blitz boolean checks, then arena opponent count (most authoritative
-- for 2v2 vs 3v3), then GetBattlefieldStatus.teamSize as last resort.
-- Returns nil if no active rated match identifiable.
local function DetectActiveBracket()
    if C_PvP and C_PvP.IsSoloShuffle and C_PvP.IsSoloShuffle() then
        return AI.BRACKET_SOLO_SHUFFLE
    end
    if C_PvP and C_PvP.IsRatedSoloRBG and C_PvP.IsRatedSoloRBG() then
        return AI.BRACKET_BLITZ
    end
    if IsActiveBattlefieldArena and IsActiveBattlefieldArena() then
        local opp = (GetNumArenaOpponents and GetNumArenaOpponents()) or 0
        if opp == 2 then return AI.BRACKET_2V2 end
        if opp == 3 then return AI.BRACKET_3V3 end
        local maxId = (GetMaxBattlefieldID and GetMaxBattlefieldID()) or 10
        for i = 1, maxId do
            local status, _, teamSize = GetBattlefieldStatus(i)
            if status == "active" then
                if teamSize == 2 then return AI.BRACKET_2V2 end
                if teamSize == 3 then return AI.BRACKET_3V3 end
            end
        end
    end
    return nil
end

-- Read current rating from DB for a given char/bracket.
local function GetDBRating(charKey, bi)
    local char = ArenaInsightsDB
        and ArenaInsightsDB.characters
        and ArenaInsightsDB.characters[charKey]
    if not char then return nil end
    local data
    if AI.PER_SPEC_BRACKETS[bi] then
        local specID = char.specID
        if specID and char.specBrackets and char.specBrackets[specID] then
            data = char.specBrackets[specID][bi]
        end
    elseif char.brackets then
        data = char.brackets[bi]
    end
    return data and data.rating
end

-- Read current saved ratings from ArenaInsightsDB into snapshot.
-- No WoW PvP API calls — safe at any time, including during zone transitions.
local function TakeDBSnapshot(charKey)
    local char = charKey
        and ArenaInsightsDB
        and ArenaInsightsDB.characters
        and ArenaInsightsDB.characters[charKey]
    snapshot = {}
    if not char then
        AI.DebugInsights("TakeDBSnapshot: no char data for", tostring(charKey))
        return
    end
    for _, bi in ipairs(AI.TRACKED_BRACKETS) do
        local data
        if AI.PER_SPEC_BRACKETS[bi] then
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
    AI.DebugInsights("TakeDBSnapshot:",
        "2v2=" .. tostring(snapshot[AI.BRACKET_2V2]),
        "3v3=" .. tostring(snapshot[AI.BRACKET_3V3]),
        "blitz=" .. tostring(snapshot[AI.BRACKET_BLITZ]),
        "ss=" .. tostring(snapshot[AI.BRACKET_SOLO_SHUFFLE]))
end

-- Compare current ArenaInsightsDB ratings vs snapshot to find the bracket that changed.
-- Called one frame after PVP_RATED_STATS_UPDATE so Core.lua has already written new values.
local function DetectBracketFromDB(charKey)
    local char = charKey
        and ArenaInsightsDB
        and ArenaInsightsDB.characters
        and ArenaInsightsDB.characters[charKey]
    if not char then return nil end

    for _, bi in ipairs(AI.TRACKED_BRACKETS) do
        local prev = snapshot[bi]
        if prev ~= nil then
            local data
            if AI.PER_SPEC_BRACKETS[bi] then
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
                AI.DebugInsights("DetectBracketFromDB: bracket", bi,
                    "changed", prev, "->", current)
                return bi
            end
        end
    end
    return nil
end

-- Lazy-built lookup: classToken + lower(specName) -> specID
-- C_PvP.GetScoreInfo().talentSpec is a localized spec NAME string, not an ID.
local specLookup
local function BuildSpecLookup()
    specLookup = {}
    local numClasses = (GetNumClasses and GetNumClasses()) or 0
    for ci = 1, numClasses do
        local _, classToken, classID = GetClassInfo(ci)
        if classToken and classID then
            local numSpecs = 0
            if C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID then
                numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
            end
            for si = 1, numSpecs do
                if GetSpecializationInfoForClassID then
                    local specID, specName = GetSpecializationInfoForClassID(classID, si)
                    if specID and specName then
                        specLookup[classToken:upper() .. "_" .. specName:lower()] = specID
                    end
                end
            end
        end
    end
end

local function ResolveSpecID(classToken, talentSpecName)
    if not classToken or not talentSpecName or talentSpecName == "" then return nil end
    if not specLookup then BuildSpecLookup() end
    return specLookup[classToken:upper() .. "_" .. tostring(talentSpecName):lower()]
end

local function IsSecret(v)
    return v ~= nil and issecretvalue and issecretvalue(v)
end

-- Safe split: name "X-Realm" -> "X","Realm". Tainted/secret values guarded.
local function SplitName(full)
    if not full or IsSecret(full) then return nil, nil end
    local ok, n, r = pcall(function()
        local nm, rl = full:match("^(.+)-(.+)$")
        return nm, rl
    end)
    if not ok then return nil, nil end
    return n or full, r
end

-- Pull rating, MMR, specs, and ally/enemy split entirely from scoreboard.
-- Mirrors the working ArenaHistoryAnalytics approach: combine C_PvP.GetScoreInfo
-- with legacy GetBattlefieldScore for faction; resolve specID from talentSpec name;
-- fallback MMR to GetBattlefieldTeamInfo for arena 2v2/3v3.
-- Returns true on success (self row found and parsed).
local function CaptureFromScoreboard(rec)
    if not C_PvP or not C_PvP.GetScoreInfo then return false end
    if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
    local n = (GetNumBattlefieldScores and GetNumBattlefieldScores()) or 0
    if n == 0 then return false end

    local _, playerRealm = UnitFullName("player")
    local playerName     = UnitName("player")
    local playerFull     = (playerName and playerRealm and playerRealm ~= "")
        and (playerName .. "-" .. playerRealm) or playerName

    local entries  = {}
    local selfRow

    for i = 1, n do
        local info = C_PvP.GetScoreInfo(i)
        local bfName, bfKB, _, bfDeaths, _, bfFac, _, _, bfClass, bfDmg, bfHeal = GetBattlefieldScore(i)
        local rawName    = (info and info.name) or bfName
        if rawName then
            -- Append player's realm to bare names (cross-realm matchup data has full name)
            local name = rawName
            if not IsSecret(name) and not name:find("-", 1, true) and playerRealm and playerRealm ~= "" then
                name = name .. "-" .. playerRealm
            end
            local shortName, realm = SplitName(name)
            local classToken = (info and info.classToken) or bfClass or ""
            local talentSpec = info and info.talentSpec
            local specID     = ResolveSpecID(classToken, talentSpec)
            local faction    = tonumber((info and info.faction) or bfFac) or -1
            local rating       = tonumber(info and info.rating) or 0
            local ratingChange = tonumber(info and info.ratingChange) or 0
            local preMMR       = tonumber(info and info.prematchMMR) or 0
            local postMMR      = tonumber(info and info.postmatchMMR) or 0
            local mmrChange    = (preMMR > 0 and postMMR > 0) and (postMMR - preMMR)
                or (tonumber(info and info.mmrChange) or 0)

            local isSelf = (info and info.isSelf)
                or (shortName and shortName == playerName)
                or (name == playerFull)

            if AI.InsightsDebug then
                print("[AI Insights] score[" .. i .. "]"
                    .. " name=" .. tostring(name)
                    .. " classToken=" .. tostring(classToken)
                    .. " talentSpec=" .. tostring(talentSpec)
                    .. " specID=" .. tostring(specID)
                    .. " faction=" .. tostring(faction)
                    .. " isSelf=" .. tostring(isSelf)
                    .. " rating=" .. tostring(rating)
                    .. " ratingChange=" .. tostring(ratingChange)
                    .. " prematchMMR=" .. tostring(preMMR)
                    .. " postmatchMMR=" .. tostring(postMMR))
            end

            local row = {
                name        = shortName or name,
                realm       = realm,
                charKey     = (shortName and realm) and (shortName .. "-" .. realm) or nil,
                classToken  = classToken,
                specID      = specID,
                faction     = faction,
                isSelf      = isSelf,
                rating      = rating,
                ratingChange= ratingChange,
                prematchMMR = preMMR,
                mmrChange   = mmrChange,
                damageDone  = tonumber(info and info.damageDone)  or nil,
                healingDone = tonumber(info and info.healingDone) or nil,
                killingBlows = tonumber(info and info.killingBlows) or nil,
            }
            -- SS: stats[1].pvpStatValue is round-win count
            if info and info.stats and info.stats[1]
                and type(info.stats[1].pvpStatValue) == "number" then
                row.roundsWon = info.stats[1].pvpStatValue
            end
            entries[#entries + 1] = row
            if isSelf then selfRow = row end
        end
    end

    if not selfRow then return false end

    rec.rating       = selfRow.rating
    rec.ratingChange = selfRow.ratingChange
    rec.prematchMMR  = selfRow.prematchMMR
    rec.mmrChange    = selfRow.mmrChange
    if selfRow.roundsWon ~= nil then rec.wonRounds = selfRow.roundsWon end
    if selfRow.damageDone  then rec.damageDone  = selfRow.damageDone  end
    if selfRow.healingDone then rec.healingDone = selfRow.healingDone end
    if selfRow.killingBlows then rec.killingBlows = selfRow.killingBlows end

    -- Partition by faction (arena team index 0/1).
    -- SS has no stable teams — faction reflects last-round assignment only,
    -- so skip faction gating and treat all 5 other players as participants.
    local isSS = (rec.bracketHint == AI.BRACKET_SOLO_SHUFFLE)
        or (C_PvP and C_PvP.IsSoloShuffle and C_PvP.IsSoloShuffle())
    local myFac = selfRow.faction
    local allies, enemies = {}, {}
    for _, row in ipairs(entries) do
        if not row.isSelf then
            if isSS then
                enemies[#enemies + 1] = row
            elseif myFac ~= -1 and row.faction == myFac then
                allies[#allies + 1] = row
            elseif myFac ~= -1 and row.faction ~= -1 then
                enemies[#enemies + 1] = row
            end
        end
    end

    -- MMR fallback for arena 2v2/3v3: per-player prematchMMR is often 0;
    -- GetBattlefieldTeamInfo returns team-level MMR.
    if (rec.prematchMMR == nil or rec.prematchMMR == 0)
        and GetBattlefieldTeamInfo
        and GetBattlefieldArenaFaction
    then
        local myArenaFac = tonumber(GetBattlefieldArenaFaction()) or 0
        local _, _, _, myMMR  = GetBattlefieldTeamInfo(myArenaFac)
        myMMR = tonumber(myMMR)
        if myMMR and myMMR > 0 then
            rec.prematchMMR = myMMR
        end
    end

    -- Build legacy spec-id arrays + new player-info arrays.
    -- Only overwrite existing rec.* if scoreboard partition yielded entries
    -- (preserves ARENA_PREP fallback when scoreboard partition fails).
    if #allies > 0 then
        local allySpecs, allyPlayers = {}, {}
        for _, row in ipairs(allies) do
            allySpecs[#allySpecs + 1] = row.specID or 0
            allyPlayers[#allyPlayers + 1] = {
                name = row.name, realm = row.realm, charKey = row.charKey,
                classToken = row.classToken, specID = row.specID,
                prematchMMR = row.prematchMMR, mmrChange = row.mmrChange,
                rating = row.rating, ratingChange = row.ratingChange,
                damageDone = row.damageDone, healingDone = row.healingDone,
                killingBlows = row.killingBlows,
            }
        end
        rec.allySpecs   = allySpecs
        rec.allyPlayers = allyPlayers
    end
    if #enemies > 0 then
        local enemySpecs, enemyPlayers = {}, {}
        for _, row in ipairs(enemies) do
            enemySpecs[#enemySpecs + 1] = row.specID or 0
            enemyPlayers[#enemyPlayers + 1] = {
                name = row.name, realm = row.realm, charKey = row.charKey,
                classToken = row.classToken, specID = row.specID,
                prematchMMR = row.prematchMMR, mmrChange = row.mmrChange,
                rating = row.rating, ratingChange = row.ratingChange,
                damageDone = row.damageDone, healingDone = row.healingDone,
                killingBlows = row.killingBlows,
            }
        end
        rec.enemySpecs   = enemySpecs
        rec.enemyPlayers = enemyPlayers
        rec.opponentCount = #enemies
    end

    rec.scoreLoaded = true
    return true
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
        -- SS fires PVP_MATCH_ACTIVE on every round zone-in. Preserve accumulated rounds
        -- whenever we have prior rounds AND this looks like SS — handles both the case
        -- where IsSoloShuffle() returns false (brief loading screen) AND true (fast zone-in).
        -- Guard on #ssRounds > 0 so a fresh non-SS match after SS resets correctly.
        if #ssRounds > 0 and (isSS or matchBracketHint == AI.BRACKET_SOLO_SHUFFLE) then
            ssActive         = true
            matchBracketHint = AI.BRACKET_SOLO_SHUFFLE
            AI.DebugInsights("PVP_MATCH_ACTIVE: SS round zone-in, preserving state rounds=", #ssRounds)
            return
        end
        ssActive           = isSS and true or false
        matchBracketHint   = DetectActiveBracket() or (isSS and AI.BRACKET_SOLO_SHUFFLE or nil)
        ssRounds           = {}
        ssRoundStart       = nil
        ssRoundPrevWins    = 0
        ssRoundComp        = nil
        AI.DebugInsights("PVP_MATCH_ACTIVE isSS=", tostring(ssActive))

    -- ---- I-2: DB snapshot before zone transition (no API restriction risk) ----
    elseif event == "PLAYER_LEAVING_WORLD" then
        TakeDBSnapshot(AI.currentCharKey)
        if ssActive then
            -- SS zones between every round — preserve accumulated ssRounds across zone-outs.
            -- Only clear per-round timing; ssActive re-armed at next state=3.
            ssRoundStart = nil
            ssActive     = false
            AI.DebugInsights("PLAYER_LEAVING_WORLD: SS inter-round zone, preserving", #ssRounds, "rounds")
        end

    -- ---- I-3: Enemy spec capture ----
    elseif event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" then
        pendingEnemySpecs = {}
        local count = GetNumArenaOpponentSpecs()
        for i = 1, count do
            local specID = GetArenaOpponentSpec(i)
            pendingEnemySpecs[i] = (specID and specID ~= 0) and specID or 0
        end
        AI.DebugInsights("enemy specs captured, count=", count)
        -- IsSoloShuffle() may return true during prep even if false at PVP_MATCH_ACTIVE.
        -- count==2 is NOT a reliable 2v2 signal: SS also shows 2 opponents per round in prep.
        -- Leave 2v2 bracket detection to DetectActiveBracket() at PVP_RATED_STATS_UPDATE.
        local isSSNow = C_PvP and C_PvP.IsSoloShuffle and C_PvP.IsSoloShuffle()
        if isSSNow then
            matchBracketHint = AI.BRACKET_SOLO_SHUFFLE
            ssActive         = true
            AI.DebugInsights("ARENA_PREP: SS detected via IsSoloShuffle, ssActive armed")
        elseif count == 3 then
            matchBracketHint = AI.BRACKET_3V3
        end
        -- Ally specs: best-effort — inspect cache may not be populated at prep time
        pendingAllySpecs = {}
        for i = 1, 4 do
            local tok = "party" .. i
            if UnitExists(tok) then
                local sid = GetInspectSpecialization and GetInspectSpecialization(tok)
                pendingAllySpecs[#pendingAllySpecs + 1] = (sid and sid ~= 0) and sid or nil
            end
        end
        AI.DebugInsights("ally specs captured, count=", #pendingAllySpecs)
        -- Refresh snapshot in case PLAYER_LEAVING_WORLD missed the char
        if not snapshot[AI.BRACKET_SOLO_SHUFFLE] and not snapshot[AI.BRACKET_2V2] then
            TakeDBSnapshot(AI.currentCharKey)
        end

    -- ---- SS round tracking via match state transitions ----
    elseif event == "PVP_MATCH_STATE_CHANGED" then
        local newState = C_PvP and C_PvP.GetActiveMatchState and C_PvP.GetActiveMatchState()
        newState = tonumber(newState)
        if not newState then return end

        local liveSS = C_PvP and C_PvP.IsSoloShuffle and C_PvP.IsSoloShuffle()
        AI.DebugInsights("PVP_MATCH_STATE_CHANGED state=", newState,
            "ssActive=", tostring(ssActive), "liveSS=", tostring(liveSS),
            "rounds so far=", #ssRounds)

        -- IsSoloShuffle() can return false at PVP_MATCH_ACTIVE time — check live as fallback
        if not ssActive then
            if liveSS then
                ssActive         = true
                matchBracketHint = AI.BRACKET_SOLO_SHUFFLE
            else
                return
            end
        end

        if newState == 3 then
            -- Enum.PvPMatchState.Engaged (Midnight: 3) — round starting
            ssRoundStart = GetTime()
            ssRoundComp  = nil
            if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
            C_Timer.After(0.2, function()
                ssRoundPrevWins = GetMyCurrentWins()
                AI.DebugInsights("Round start wins snapshot:", ssRoundPrevWins)
                -- Capture per-round 3v3 team comp from scoreboard faction field
                local myFac = GetBattlefieldArenaFaction and tonumber(GetBattlefieldArenaFaction()) or -1
                local allies, enemies = {}, {}
                local n = GetNumBattlefieldScores and GetNumBattlefieldScores() or 0
                for i = 1, n do
                    local si = C_PvP.GetScoreInfo and C_PvP.GetScoreInfo(i)
                    if si and not si.isSelf then
                        local fac = tonumber(si.faction) or -1
                        if myFac ~= -1 and fac == myFac then
                            allies[#allies + 1] = si.specID
                        elseif myFac ~= -1 and fac ~= -1 and fac ~= myFac then
                            enemies[#enemies + 1] = si.specID
                        end
                    end
                end
                ssRoundComp = { allySpecs = allies, enemySpecs = enemies }
                AI.DebugInsights("Round comp: allies=", #allies, "enemies=", #enemies)
            end)

        elseif ssRoundStart ~= nil then
            -- Any non-Engaged state while a round was active = round ended.
            -- Avoids hardcoding PostRound value (3? 4?) which varies by build.
            local capturedStart = ssRoundStart
            if not capturedStart then
                AI.DebugInsights("state", newState, "but no ssRoundStart — skipping")
                return
            end

            ssRoundStart = nil  -- clear immediately to prevent double-capture

            local roundNum  = #ssRounds + 1
            local duration  = math.floor(GetTime() - capturedStart)
            local prevWins  = ssRoundPrevWins

            if roundNum <= 6 then
                -- Insert placeholder; outcome resolved after scoreboard delay
                local roundEntry = {
                    num        = roundNum,
                    outcome    = "unknown",
                    duration   = duration,
                    allySpecs  = ssRoundComp and ssRoundComp.allySpecs or {},
                    enemySpecs = ssRoundComp and ssRoundComp.enemySpecs or {},
                }
                ssRoundComp = nil
                ssRounds[roundNum] = roundEntry

                C_Timer.After(0.6, function()
                    if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
                    C_Timer.After(0.2, function()
                        local newWins = GetMyCurrentWins()
                        local ok, won = pcall(function() return newWins > prevWins end)
                        roundEntry.outcome = ok and (won and "win" or "loss") or "unknown"
                        ssRoundPrevWins    = newWins
                        AI.DebugInsights("Round", roundNum, "outcome:", roundEntry.outcome,
                            "wins:", prevWins, "->", newWins)
                    end)
                end)
            else
                AI.DebugInsights("roundNum > 6, skipping (roundNum=", roundNum, ")")
            end
        end

    -- ---- I-4 Stage 1: Stash partial record ----
    elseif event == "PVP_MATCH_COMPLETE" then
        -- Match is over — no more rounds will start; stop processing state changes
        ssActive = false

        local winner, duration = ...

        if AI.InsightsDebug then
            print("[AI Insights] PVP_MATCH_COMPLETE winner=" .. tostring(winner)
                .. " duration=" .. tostring(duration))
            local _, iType, _, iName = GetInstanceInfo()
            print("[AI Insights] instance type=" .. tostring(iType) .. " name=" .. tostring(iName))
            for _, bi in ipairs(AI.TRACKED_BRACKETS) do
                print("[AI Insights] bracket " .. bi .. " snapshot=" .. tostring(snapshot[bi]))
            end
        end

        if not AI.currentCharKey then
            AI.DebugInsights("no currentCharKey, skipping")
            return
        end

        local charKey = AI.currentCharKey
        local specID
        local char = ArenaInsightsDB.characters[charKey]
        if char then specID = char.specID end

        -- Refresh hint at completion in case PVP_MATCH_ACTIVE detection missed
        -- (e.g. C_PvP.IsSoloShuffle returning false during zone transition).
        matchBracketHint = matchBracketHint or DetectActiveBracket()

        -- Derive outcome directly from team index: 0=purple, 1=gold.
        -- GetBattlefieldArenaFaction() returns which team the player is on.
        -- No draws in 2v2/3v3; this field is ignored for SS (wonRounds used instead).
        local directOutcome
        if type(winner) == "number" then
            local myTeam = GetBattlefieldArenaFaction()
            if type(myTeam) == "number" then
                directOutcome = (winner == myTeam) and "win" or "loss"
            end
        end

        pendingRecord = {
            timestamp     = time(),
            charKey       = charKey,
            specID        = specID,
            enemySpecs    = pendingEnemySpecs,
            allySpecs     = pendingAllySpecs,
            bracketHint   = matchBracketHint,
            directOutcome = directOutcome,
        }

        pendingEnemySpecs = {}
        pendingAllySpecs  = {}
        AI.DebugInsights("Stage 1 complete — charKey=", charKey)

    -- ---- I-4 Stage 2: Accumulate score data (best-effort) ----
    elseif event == "UPDATE_BATTLEFIELD_SCORE" then
        if not pendingRecord or pendingRecord.scoreLoaded then return end
        CaptureFromScoreboard(pendingRecord)
        if not pendingRecord.scoreLoaded then
            AI.DebugInsights("score not found in UPDATE_BATTLEFIELD_SCORE, will retry")
        end

    -- ---- I-4 Stage 3: Finalize one frame after Core.lua writes new ratings ----
    elseif event == "PVP_RATED_STATS_UPDATE" then
        if not pendingRecord then return end

        local rec = pendingRecord
        pendingRecord = nil  -- clear now; timer callback captures rec

        -- Delay finalize ~1.5s: per-player scoreboard MMR fields and faction
        -- partitioning aren't reliably populated immediately after
        -- PVP_RATED_STATS_UPDATE. ArenaHistoryAnalytics uses the same delay.
        C_Timer.After(1.5, function()
            -- Final scoreboard read (always re-capture; scoreboard now stable)
            CaptureFromScoreboard(rec)

            -- Bracket detection priority:
            --   1. Scoreboard opponent count (2 = 2v2, 3 = 3v3) — most reliable for arena
            --   2. SS / Blitz boolean checks (don't rely on opponent count)
            --   3. DB rating diff
            --   4. ARENA_PREP-time hint
            --   5. Live-API DetectActiveBracket() at finalize
            local function bracketFromScoreboard()
                if C_PvP and C_PvP.IsSoloShuffle and C_PvP.IsSoloShuffle() then
                    return AI.BRACKET_SOLO_SHUFFLE
                end
                if C_PvP and C_PvP.IsRatedSoloRBG and C_PvP.IsRatedSoloRBG() then
                    return AI.BRACKET_BLITZ
                end
                if rec.opponentCount == 2 then return AI.BRACKET_2V2 end
                if rec.opponentCount == 3 then return AI.BRACKET_3V3 end
                return nil
            end

            rec.bracketIndex = bracketFromScoreboard()
                or DetectBracketFromDB(rec.charKey)
                or rec.bracketHint
                or DetectActiveBracket()
            rec.bracketHint   = nil
            rec.opponentCount = nil
            AI.DebugInsights("bracket detected —", tostring(rec.bracketIndex))

            -- Authoritative rating + ratingChange from DB diff: scoreboard sometimes
            -- returns 0/nil ratingChange (mislabels losses as draws). DB has ground truth.
            if rec.bracketIndex then
                local curRating = GetDBRating(rec.charKey, rec.bracketIndex)
                local prev      = snapshot[rec.bracketIndex]
                if curRating then
                    -- DB has authoritative post-match rating (written by Core from
                    -- C_PvP.GetRatedBracketInfo on PVP_RATED_STATS_UPDATE). Scoreboard
                    -- rating field returns stale data in Midnight 12.x — overwrite.
                    rec.rating = curRating
                    if prev then
                        local diff = curRating - prev
                        if diff ~= 0 and (rec.ratingChange == nil or rec.ratingChange == 0) then
                            rec.ratingChange = diff
                            AI.DebugInsights("ratingChange overridden from DB diff:", diff)
                        end
                    end
                end
            end

            -- Derive outcome:
            --   SS  → wonRounds (>3 win, <3 loss, ==3 draw), fallback to ratingChange
            --   2v2/3v3/Blitz → directOutcome from PVP_MATCH_COMPLETE winner arg,
            --                   fallback to ratingChange sign
            if rec.bracketIndex == AI.BRACKET_SOLO_SHUFFLE then
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
                    AI.DebugInsights("SS outcome fallback to ratingChange (wonRounds nil)")
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
            elseif rec.directOutcome then
                rec.outcome = rec.directOutcome
                AI.DebugInsights("outcome from winner arg:", rec.outcome)
            else
                AI.DebugInsights("outcome fallback to ratingChange sign")
                local rc = rec.ratingChange
                if rc == nil then
                    rec.outcome = "unknown"
                elseif rc > 0 then
                    rec.outcome = "win"
                else
                    rec.outcome = "loss"
                end
            end
            rec.directOutcome = nil

            -- SS shuffle data: trust scoreboard totals (reliable), include rounds[]
            -- for any partial capture (per-round states don't fire for every round
            -- in Midnight 12.x, so we store whatever was captured rather than all-or-nothing).
            if rec.bracketIndex == AI.BRACKET_SOLO_SHUFFLE then
                local won   = rec.wonRounds or 0
                local total = 6
                rec.shuffle = {
                    wonRounds   = won,
                    lostRounds  = total - won,
                    totalRounds = total,
                }
                if #ssRounds == 6 then
                    local capturedRounds = {}
                    for i = 1, #ssRounds do
                        capturedRounds[i] = ssRounds[i]
                    end
                    rec.shuffle.rounds = capturedRounds
                    AI.DebugInsights("shuffle: per-round capture (", #ssRounds, "/", total, "rounds)")
                else
                    AI.DebugInsights("shuffle: no round state transitions captured — totals only")
                end
                ssRounds        = {}
                ssRoundStart    = nil
                ssRoundPrevWins = 0
                ssActive        = false
            end

            rec.scoreLoaded = nil  -- don't persist internal flag

            ArenaInsightsDB.matches[#ArenaInsightsDB.matches + 1] = rec
            AI.DebugInsights("match recorded — bracket=", tostring(rec.bracketIndex),
                "outcome=", rec.outcome,
                "rating=", tostring(rec.rating))

            snapshot = {}
        end)
    end
end)
