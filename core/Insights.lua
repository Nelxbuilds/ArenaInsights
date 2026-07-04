local addonName, AI = ...

-- ============================================================================
-- Module-local state
-- ============================================================================

local snapshot          = {}   -- bracketIndex → rating from ArenaInsightsDB before match
local pendingEnemySpecs = {}  -- populated by ARENA_PREP_OPPONENT_SPECIALIZATIONS
local pendingAllySpecs  = {}  -- teammate specs captured at ARENA_PREP (best-effort, inspect cache)
local pendingRecord    = nil  -- partial record held between PVP_MATCH_COMPLETE and PVP_RATED_STATS_UPDATE

-- Solo Shuffle per-round tracking
local ssRounds        = {}    -- accumulated per-round records: { num, outcome, duration, allySpecs, enemySpecs, deaths }
local ssRoundStart    = nil   -- GetTime() at state-3 onset for current round
local ssRoundComp     = nil   -- { allySpecs={}, enemySpecs={} } captured at round start
local ssRoundDeaths   = nil   -- ordered death list for current round: { {name, specID, side, t}, ... }
local ssAllyGUIDs     = nil   -- GUID -> { name, specID } for player + party1/party2 this round
local ssEnemyGUIDs    = nil   -- GUID -> { name, specID } for arena1..N this round
local ssDeadGUIDs     = nil   -- set of GUIDs already recorded dead this round (dedup)
local ssDmgBuffer     = nil   -- rolling damage-taken buffer for death recaps (nil = recap disabled)
local ssActive        = false -- true only inside a confirmed SS match
local ssMatchOver     = false -- set at PVP_MATCH_COMPLETE; next PVP_MATCH_ACTIVE is a new match, never a round zone-in
local matchBracketHint = nil  -- bracket captured early as fallback for DB-diff detection

AI.InsightsDebug = false

-- ============================================================================
-- Public accessor (I-5)
-- ============================================================================

function AI.GetMatches()
    return ArenaInsightsDB.matches or {}
end

-- A session = consecutive matches with less than SESSION_GAP between them.
local SESSION_GAP = 3600

-- Matches of the most recent play session, chronological order.
-- charKey filters to one character; nil = across all characters.
function AI.GetLatestSession(charKey)
    local matches = AI.GetMatches()
    local session = {}
    local prevTs
    for i = #matches, 1, -1 do
        local rec = matches[i]
        if not charKey or rec.charKey == charKey then
            local ts = rec.timestamp or 0
            if prevTs and (prevTs - ts) > SESSION_GAP then break end
            session[#session + 1] = rec
            prevTs = ts
        end
    end
    for i = 1, math.floor(#session / 2) do
        session[i], session[#session - i + 1] = session[#session - i + 1], session[i]
    end
    return session
end

-- Only callable with InsightsDebug=true.
-- Removes records with no bracket or no rating.
-- For SS records: clears shuffle.rounds captured by the legacy scoreboard-based
-- tracker (entries lack the deaths field; their outcomes are unreliable).
-- Partial round captures from the live tracker are valid and kept.
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
            if r.shuffle and r.shuffle.rounds and #r.shuffle.rounds > 0
                and not r.shuffle.rounds[1].deaths then
                r.shuffle.rounds = nil
                fixed = fixed + 1
            end
            kept[#kept + 1] = r
        end
    end

    ArenaInsightsDB.matches = kept
    print(("[AI] Purge complete - removed %d, fixed %d SS round tables, kept %d"):format(
        removed, fixed, #kept))
end

-- Capture-quality summary: how many recorded matches have full data vs holes.
-- Simulated records excluded. Wired to /ai health.
function AI.PrintCaptureHealth()
    local total, unknownOut, noRating, noMMR = 0, 0, 0, 0
    local ssTotal, ssFull, ssPartial = 0, 0, 0
    for _, r in ipairs(AI.GetMatches()) do
        if not r.simulated then
            total = total + 1
            if not r.outcome or r.outcome == "unknown" then unknownOut = unknownOut + 1 end
            if not r.rating then noRating = noRating + 1 end
            if not r.prematchMMR or r.prematchMMR == 0 then noMMR = noMMR + 1 end
            if r.bracketIndex == AI.BRACKET_SOLO_SHUFFLE then
                ssTotal = ssTotal + 1
                local rounds = r.shuffle and r.shuffle.rounds
                if rounds and #rounds >= 6 then
                    ssFull = ssFull + 1
                elseif rounds and #rounds > 0 then
                    ssPartial = ssPartial + 1
                end
            end
        end
    end
    print("|cffE6D200ArenaInsights|r capture health (" .. total .. " matches):")
    if total == 0 then
        print("  no live matches recorded yet")
        return
    end
    local function line(label, bad)
        local pct = math.floor(bad / total * 100 + 0.5)
        print(("  %s: %d (%d%%)"):format(label, bad, pct))
    end
    line("unknown outcome", unknownOut)
    line("missing rating", noRating)
    line("missing MMR", noMMR)
    if ssTotal > 0 then
        print(("  SS round capture: %d/%d full, %d partial, %d none")
            :format(ssFull, ssTotal, ssPartial, ssTotal - ssFull - ssPartial))
    end
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
    if not classToken or not talentSpecName then return nil end
    if issecretvalue and issecretvalue(talentSpecName) then return nil end
    if talentSpecName == "" then return nil end
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
-- Combine C_PvP.GetScoreInfo with legacy GetBattlefieldScore for faction;
-- resolve specID from talentSpec name; fallback MMR to GetBattlefieldTeamInfo
-- for arena 2v2/3v3.
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

-- Capture the current SS round's comp and per-player GUID->{name, specID} maps
-- from live unit APIs. The battlefield scoreboard is NOT populated mid-round, so
-- per-round data must come from arena/party units, not C_PvP.GetScoreInfo.
-- Enemy specs from GetArenaOpponentSpec (paired by arena index); ally specs are
-- best-effort (player's own is reliable, teammates depend on the inspect cache).
local function StartRoundCapture()
    local allyGUIDs, enemyGUIDs = {}, {}
    local allySpecs, enemySpecs = {}, {}

    -- Player (self) — GUID map only. allySpecs holds teammates exclusively:
    -- the UI renders the player's own spec from rec.specID, so including it
    -- here would draw the self icon twice and drop the second teammate.
    local pGUID = UnitGUID("player")
    local specIdx = GetSpecialization and GetSpecialization()
    local pSpecID = specIdx and GetSpecializationInfo(specIdx) or nil
    if pGUID then
        allyGUIDs[pGUID] = { name = UnitName("player"), specID = pSpecID }
    end

    -- Teammates party1/party2 — spec best-effort via inspect cache.
    -- Midnight secret-value guard: a secret GUID/name is useless for death
    -- attribution (can't be compared), so skip rather than store it.
    for i = 1, 2 do
        local tok = "party" .. i
        if UnitExists(tok) then
            local g   = UnitGUID(tok)
            local nm  = UnitName(tok)
            if IsSecret(nm) then nm = nil end
            local sid = GetInspectSpecialization and GetInspectSpecialization(tok)
            sid = (sid and sid ~= 0) and sid or nil
            if g and not IsSecret(g) then allyGUIDs[g] = { name = nm, specID = sid } end
            if sid then allySpecs[#allySpecs + 1] = sid end
        end
    end

    -- Enemies arena1..5 — GUID read straight off the unit token (reliable for any
    -- existing unit). GetArenaOpponentSpec is best-effort for the spec ID only: its
    -- index range is the prep-phase opponent-spec system and can read 0 mid-round, so
    -- it must NOT gate enemy GUID capture — death attribution depends on those GUIDs.
    for i = 1, 5 do
        local tok = "arena" .. i
        if UnitExists(tok) then
            local g   = UnitGUID(tok)
            local nm  = UnitName(tok)
            if IsSecret(nm) then nm = nil end
            local sid = GetArenaOpponentSpec and GetArenaOpponentSpec(i)
            sid = (sid and sid ~= 0) and sid or nil
            if g and not IsSecret(g) then enemyGUIDs[g] = { name = nm, specID = sid } end
            if sid then enemySpecs[#enemySpecs + 1] = sid end
        end
    end

    ssRoundComp   = { allySpecs = allySpecs, enemySpecs = enemySpecs }
    ssAllyGUIDs   = allyGUIDs
    ssEnemyGUIDs  = enemyGUIDs
    ssRoundDeaths = {}
    ssDeadGUIDs   = {}
    local recapOn = ArenaInsightsDB.settings and ArenaInsightsDB.settings.deathRecapEnabled
    ssDmgBuffer   = recapOn and {} or nil
    AI.DebugInsights("Round capture: allySpecs=", #allySpecs, "enemySpecs=", #enemySpecs,
        "allyGUIDs=", AI.TableCount(allyGUIDs), "enemyGUIDs=", AI.TableCount(enemyGUIDs))
end

local function GetRecapWindow()
    local w = ArenaInsightsDB.settings and ArenaInsightsDB.settings.deathRecapWindow
    return (type(w) == "number" and w >= 1) and w or 8
end

-- Aggregate the damage buffer for one victim GUID over the recap window into
-- a compact recap: top damage lines by total + the killing blow. Returns nil
-- when nothing was buffered for the victim (recap disabled, or all damage
-- fields were secret/unreadable).
local function BuildDeathRecap(guid)
    if not ssDmgBuffer then return nil end
    local cutoff = GetTime() - GetRecapWindow()
    local agg, order, last = {}, {}, nil
    for _, e in ipairs(ssDmgBuffer) do
        if e.dest == guid and e.t >= cutoff then
            local key = (e.src or "?") .. "|" .. e.spell
            local a = agg[key]
            if not a then
                a = { src = e.src, spell = e.spell, hits = 0, amount = 0 }
                agg[key] = a
                order[#order + 1] = a
            end
            a.hits   = a.hits + 1
            a.amount = a.amount + e.amt
            last = e
        end
    end
    if not last then return nil end
    table.sort(order, function(a, b) return a.amount > b.amount end)
    local lines = {}
    for i = 1, math.min(#order, 6) do lines[i] = order[i] end
    return {
        window      = GetRecapWindow(),
        killingBlow = { src = last.src, spell = last.spell, amount = last.amt },
        lines       = lines,
    }
end

-- Close out the engaged round: derive outcome from recorded deaths, append to
-- ssRounds, clear per-round state. No-op when no round is engaged, so it is
-- safe to call from both the round-end state transition and (defensively)
-- PVP_MATCH_COMPLETE — whichever fires first wins, the other is skipped.
local function FinalizeRound()
    if not ssRoundStart then return end
    local duration = math.floor(GetTime() - ssRoundStart)
    ssRoundStart = nil  -- clear immediately to prevent double-capture
    local roundNum = #ssRounds + 1

    if roundNum <= 6 then
        local allyDead, enemyDead = 0, 0
        for _, d in ipairs(ssRoundDeaths or {}) do
            if d.side == "ally" then
                allyDead = allyDead + 1
            elseif d.side == "enemy" then
                enemyDead = enemyDead + 1
            end
        end
        -- A round ends when one full team is eliminated. Prefer full-wipe
        -- detection (ally side is reliably mapped: self always logs UNIT_DIED
        -- and party GUIDs are stable), and fall back to raw death-count compare.
        local allySize  = AI.TableCount(ssAllyGUIDs or {})
        local enemySize = AI.TableCount(ssEnemyGUIDs or {})
        local allyWiped  = allySize  > 0 and allyDead  >= allySize
        local enemyWiped = enemySize > 0 and enemyDead >= enemySize
        local outcome = "unknown"
        if enemyWiped and not allyWiped then
            outcome = "win"
        elseif allyWiped and not enemyWiped then
            outcome = "loss"
        elseif allySize > 0 and enemySize > 0 then
            -- Raw death-count compare is only meaningful when BOTH teams' GUIDs
            -- were identifiable. If enemy identity was restricted (secret values,
            -- enemyGUIDs empty), ally deaths alone would mislabel won rounds as
            -- losses — leave outcome "unknown" instead.
            if enemyDead > allyDead then
                outcome = "win"
            elseif allyDead > enemyDead then
                outcome = "loss"
            end
        end

        ssRounds[roundNum] = {
            num        = roundNum,
            outcome    = outcome,
            duration   = duration,
            allySpecs  = ssRoundComp and ssRoundComp.allySpecs or {},
            enemySpecs = ssRoundComp and ssRoundComp.enemySpecs or {},
            deaths     = ssRoundDeaths or {},
        }
        AI.DebugInsights("Round", roundNum, "outcome:", outcome,
            "allyDead:", allyDead, "enemyDead:", enemyDead,
            "deaths:", #(ssRoundDeaths or {}))
    else
        AI.DebugInsights("roundNum > 6, skipping (roundNum=", roundNum, ")")
    end

    ssRoundComp   = nil
    ssRoundDeaths = nil
    ssAllyGUIDs   = nil
    ssEnemyGUIDs  = nil
    ssDeadGUIDs   = nil
    ssDmgBuffer   = nil
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
        -- ssMatchOver: the previous SS match completed but may not have finalized
        -- (left before PVP_RATED_STATS_UPDATE) — this ACTIVE is a new match, so any
        -- leftover ssRounds are stale and must NOT be preserved.
        if not ssMatchOver and #ssRounds > 0 and (isSS or matchBracketHint == AI.BRACKET_SOLO_SHUFFLE) then
            ssActive         = true
            matchBracketHint = AI.BRACKET_SOLO_SHUFFLE
            AI.DebugInsights("PVP_MATCH_ACTIVE: SS round zone-in, preserving state rounds=", #ssRounds)
            return
        end
        ssMatchOver        = false
        ssActive           = isSS and true or false
        matchBracketHint   = DetectActiveBracket() or (isSS and AI.BRACKET_SOLO_SHUFFLE or nil)
        ssRounds           = {}
        ssRoundStart       = nil
        ssRoundComp        = nil
        ssRoundDeaths      = nil
        ssAllyGUIDs        = nil
        ssEnemyGUIDs       = nil
        ssDeadGUIDs        = nil
        ssDmgBuffer        = nil
        AI.DebugInsights("PVP_MATCH_ACTIVE isSS=", tostring(ssActive))

    -- ---- I-2: DB snapshot before zone transition (no API restriction risk) ----
    elseif event == "PLAYER_LEAVING_WORLD" then
        TakeDBSnapshot(AI.currentCharKey)
        if ssActive then
            -- SS zones between every round — preserve accumulated ssRounds across zone-outs.
            -- Only clear per-round timing; ssActive re-armed at next state=3.
            pcall(self.UnregisterEvent, self, "COMBAT_LOG_EVENT_UNFILTERED")
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

        -- Match already completed — round was finalized at PVP_MATCH_COMPLETE;
        -- don't let post-match state changes re-arm tracking.
        if ssMatchOver then return end

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
            -- Enum.PvPMatchState.Engaged (Midnight: 3) — round combat begins.
            -- Capture comp + per-player GUIDs from live unit APIs, then listen for
            -- deaths. The scoreboard is empty mid-round, so it cannot be used here.
            ssRoundStart = GetTime()
            StartRoundCapture()
            -- Midnight 12.0 API notes claim CLEU registration can error in some
            -- contexts. pcall so a blocked combat log only disables death capture
            -- (outcomes fall back to "unknown") instead of breaking round tracking.
            local ok = pcall(self.RegisterEvent, self, "COMBAT_LOG_EVENT_UNFILTERED")
            if not ok then
                AI.DebugInsights("CLEU registration blocked - death capture disabled this round")
            end

        elseif ssRoundStart ~= nil then
            -- Any non-Engaged state while a round was active = round ended.
            -- Avoids hardcoding PostRound value (3? 4?) which varies by build.
            pcall(self.UnregisterEvent, self, "COMBAT_LOG_EVENT_UNFILTERED")
            FinalizeRound()
        end

    -- ---- SS per-round death capture (live, only while a round is engaged) ----
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not ssRoundStart then return end
        local _, subevent, _, _, srcName, _, _, destGUID, destName, _, _, p1, p2, _, p4 =
            CombatLogGetCurrentEventInfo()
        if IsSecret(subevent) then return end
        -- Secret destGUID can't be compared against captured unit GUIDs (and
        -- would be unusable as a table key) — drop the event.
        if not destGUID or IsSecret(destGUID) then return end
        local tracked = (ssAllyGUIDs and ssAllyGUIDs[destGUID])
            or (ssEnemyGUIDs and ssEnemyGUIDs[destGUID])

        -- Death recap: buffer damage taken by any of the 6 tracked players.
        if ssDmgBuffer and tracked then
            local spell, amount
            if subevent == "SWING_DAMAGE" then
                spell, amount = "Melee", p1
            elseif subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE"
                or subevent == "RANGE_DAMAGE" then
                spell, amount = p2, p4
            end
            if spell then
                if IsSecret(spell) or type(spell) ~= "string" then spell = "Unknown" end
                if IsSecret(amount) or type(amount) ~= "number" then amount = 0 end
                if IsSecret(srcName) or type(srcName) ~= "string" then srcName = nil end
                ssDmgBuffer[#ssDmgBuffer + 1] = {
                    t = GetTime(), dest = destGUID, src = srcName, spell = spell, amt = amount,
                }
                -- Bound memory: drop entries older than the recap window
                if #ssDmgBuffer > 400 then
                    local cutoff = GetTime() - (GetRecapWindow() + 2)
                    local kept = {}
                    for _, e in ipairs(ssDmgBuffer) do
                        if e.t >= cutoff then kept[#kept + 1] = e end
                    end
                    ssDmgBuffer = kept
                end
            end
        end

        if subevent ~= "UNIT_DIED" then return end
        if IsSecret(destName) then destName = nil end
        if ssDeadGUIDs and ssDeadGUIDs[destGUID] then return end

        local side, info
        if ssAllyGUIDs and ssAllyGUIDs[destGUID] then
            side, info = "ally", ssAllyGUIDs[destGUID]
        elseif ssEnemyGUIDs and ssEnemyGUIDs[destGUID] then
            side, info = "enemy", ssEnemyGUIDs[destGUID]
        else
            return  -- pet/totem/non-participant
        end

        ssDeadGUIDs   = ssDeadGUIDs or {}
        ssRoundDeaths = ssRoundDeaths or {}
        ssDeadGUIDs[destGUID] = true
        ssRoundDeaths[#ssRoundDeaths + 1] = {
            name   = info.name or destName,
            specID = info.specID,
            side   = side,
            t      = math.floor(GetTime() - ssRoundStart),
            recap  = BuildDeathRecap(destGUID),
        }
        AI.DebugInsights("Death:", info.name or destName, side, "t=", math.floor(GetTime() - ssRoundStart))

    -- ---- I-4 Stage 1: Stash partial record ----
    elseif event == "PVP_MATCH_COMPLETE" then
        -- Match is over — no more rounds will start; stop processing state changes.
        -- If the final round is still engaged (its end state-change never fired),
        -- finalize it now so it isn't lost.
        pcall(self.UnregisterEvent, self, "COMBAT_LOG_EVENT_UNFILTERED")
        FinalizeRound()
        ssActive    = false
        ssMatchOver = true

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
        AI.DebugInsights("Stage 1 complete - charKey=", charKey)

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
        -- PVP_RATED_STATS_UPDATE.
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
            AI.DebugInsights("bracket detected -", tostring(rec.bracketIndex))

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
                if #ssRounds > 0 then
                    local capturedRounds = {}
                    for i = 1, #ssRounds do
                        capturedRounds[i] = ssRounds[i]
                    end
                    rec.shuffle.rounds = capturedRounds
                    AI.DebugInsights("shuffle: per-round capture (", #ssRounds, "/", total, "rounds)")
                    if AI.InsightsDebug then
                        local derivedWins = 0
                        for _, r in ipairs(capturedRounds) do
                            if r.outcome == "win" then derivedWins = derivedWins + 1 end
                        end
                        if derivedWins ~= won then
                            AI.DebugInsights("WARN: per-round wins", derivedWins,
                                "!= scoreboard wonRounds", won, "(per-round outcomes suspect)")
                        end
                    end
                else
                    AI.DebugInsights("shuffle: no round state transitions captured - totals only")
                end
                ssRounds      = {}
                ssRoundStart  = nil
                ssRoundComp   = nil
                ssRoundDeaths = nil
                ssAllyGUIDs   = nil
                ssEnemyGUIDs  = nil
                ssDeadGUIDs   = nil
                ssActive      = false
            end

            rec.scoreLoaded = nil  -- don't persist internal flag

            -- Season tag for future archiving/pruning (nil if API unavailable)
            rec.season = (GetCurrentArenaSeason and GetCurrentArenaSeason()) or nil

            ArenaInsightsDB.matches[#ArenaInsightsDB.matches + 1] = rec
            AI.DebugInsights("match recorded - bracket=", tostring(rec.bracketIndex),
                "outcome=", rec.outcome,
                "rating=", tostring(rec.rating))

            -- Nil-guarded UI hooks — no load-order coupling to ui/
            if AI.OnMatchRecorded then AI.OnMatchRecorded(rec) end
            if AI.RefreshInsights then AI.RefreshInsights() end

            snapshot = {}
        end)
    end
end)
