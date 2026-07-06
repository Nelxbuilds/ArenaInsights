local addonName, AI = ...

-- ============================================================================
-- Trace recorder (dev tooling): /ai trace [clear]
-- Records the event stream the Insights capture pipeline consumes, plus a
-- snapshot of exactly the API values it reads at each event — in the same
-- shape as tests/wow_stub.lua's api table, so a recorded trace replays 1:1
-- through the headless test harness (tests/replay.lua).
--
-- The trace lives in ArenaInsightsDB.trace. After logging out, copy the table
-- from WTF/Account/<acc>/SavedVariables/ArenaInsights.lua into a file under
-- tests/fixtures/ that does `return { ...trace table... }`.
--
-- Secret values are recorded as the string "<<SECRET>>" — this both keeps the
-- trace serializable and documents where Midnight restricts data.
-- ============================================================================

local MAX_EVENTS = 4000

local recording  = false
local traceStart = 0

local TRACKED_EVENTS = {
    "PVP_MATCH_ACTIVE",
    "PLAYER_LEAVING_WORLD",
    "PLAYER_ENTERING_WORLD",
    "ARENA_PREP_OPPONENT_SPECIALIZATIONS",
    "PVP_MATCH_STATE_CHANGED",
    "PVP_MATCH_COMPLETE",
    "UPDATE_BATTLEFIELD_SCORE",
    "PVP_RATED_STATS_UPDATE",
    "COMBAT_LOG_EVENT_UNFILTERED",
    "UNIT_DIED",
}

local function Scrub(v)
    if issecretvalue and issecretvalue(v) then return "<<SECRET>>" end
    return v
end

local function SnapUnit(tok)
    if not UnitExists(tok) then return nil end
    return { guid = Scrub(UnitGUID(tok)), name = Scrub(UnitName(tok)) }
end

local function SnapUnits()
    local units = { player = SnapUnit("player") }
    for i = 1, 4 do units["party" .. i] = SnapUnit("party" .. i) end
    for i = 1, 5 do units["arena" .. i] = SnapUnit("arena" .. i) end
    return units
end

local function SnapSpecs()
    local arenaSpecs, inspectSpecs = {}, {}
    for i = 1, 5 do
        local sid = GetArenaOpponentSpec and GetArenaOpponentSpec(i)
        if sid and sid ~= 0 then arenaSpecs[i] = Scrub(sid) end
    end
    for i = 1, 4 do
        local tok = "party" .. i
        if UnitExists(tok) then
            local sid = GetInspectSpecialization and GetInspectSpecialization(tok)
            if sid and sid ~= 0 then inspectSpecs[tok] = Scrub(sid) end
        end
    end
    return arenaSpecs, inspectSpecs
end

local function SnapScoreboard()
    local rows = {}
    local n = (GetNumBattlefieldScores and GetNumBattlefieldScores()) or 0
    for i = 1, math.min(n, 40) do
        local info = C_PvP and C_PvP.GetScoreInfo and C_PvP.GetScoreInfo(i)
        if info then
            local stats
            if info.stats then
                stats = {}
                for k, st in ipairs(info.stats) do
                    stats[k] = {
                        pvpStatID    = Scrub(st.pvpStatID),
                        name         = Scrub(st.name),
                        pvpStatValue = Scrub(st.pvpStatValue),
                    }
                end
            end
            rows[#rows + 1] = {
                name = Scrub(info.name), isSelf = Scrub(info.isSelf),
                classToken = Scrub(info.classToken), talentSpec = Scrub(info.talentSpec),
                faction = Scrub(info.faction),
                rating = Scrub(info.rating), ratingChange = Scrub(info.ratingChange),
                prematchMMR = Scrub(info.prematchMMR), postmatchMMR = Scrub(info.postmatchMMR),
                mmrChange = Scrub(info.mmrChange),
                damageDone = Scrub(info.damageDone), healingDone = Scrub(info.healingDone),
                killingBlows = Scrub(info.killingBlows),
                stats = stats,
            }
        end
    end
    return rows
end

local function SnapDBRatings()
    local char = ArenaInsightsDB.characters and ArenaInsightsDB.characters[AI.currentCharKey]
    if not char then return nil end
    local out = {}
    for _, bi in ipairs(AI.TRACKED_BRACKETS) do
        local data
        if AI.PER_SPEC_BRACKETS[bi] then
            local sid = char.specID
            data = sid and char.specBrackets and char.specBrackets[sid]
                and char.specBrackets[sid][bi]
        else
            data = char.brackets and char.brackets[bi]
        end
        out[bi] = data and data.rating or nil
    end
    return out
end

local tracerFrame = CreateFrame("Frame")

local function Record(event, ...)
    local trace = ArenaInsightsDB.trace
    if not trace or #trace.events >= MAX_EVENTS then return end

    local entry = { t = GetTime() - traceStart, e = event }

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local c = { CombatLogGetCurrentEventInfo() }
        local subevent = Scrub(c[2])
        local destGUID = Scrub(c[8])
        -- Volume control: only rows the pipeline consumes — player deaths and
        -- damage taken by players.
        local isPlayerDest = type(destGUID) == "string" and destGUID:find("^Player%-")
        if subevent ~= "UNIT_DIED" and not (isPlayerDest and type(subevent) == "string"
            and (subevent:find("_DAMAGE$") or subevent == "SWING_DAMAGE")) then
            return
        end
        local cleu = {}
        for i = 1, 15 do cleu[i] = Scrub(c[i]) end
        entry.cleu = cleu
    else
        entry.args = { ... }
        entry.api = {
            isSoloShuffle = Scrub(C_PvP and C_PvP.IsSoloShuffle and C_PvP.IsSoloShuffle()),
            matchState    = Scrub(C_PvP and C_PvP.GetActiveMatchState and C_PvP.GetActiveMatchState()),
            instanceType  = select(2, GetInstanceInfo()),
        }
        if event == "PVP_MATCH_STATE_CHANGED" then
            entry.api.units = SnapUnits()
            entry.api.arenaSpecs, entry.api.inspectSpecs = SnapSpecs()
        elseif event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" then
            entry.api.numArenaOpponentSpecs = GetNumArenaOpponentSpecs()
            entry.api.arenaSpecs, entry.api.inspectSpecs = SnapSpecs()
            entry.api.units = SnapUnits()
        elseif event == "PVP_MATCH_COMPLETE" or event == "UPDATE_BATTLEFIELD_SCORE"
            or event == "PVP_RATED_STATS_UPDATE" then
            entry.api.scoreboard   = SnapScoreboard()
            entry.api.arenaFaction = GetBattlefieldArenaFaction and Scrub(GetBattlefieldArenaFaction()) or nil
            if event == "PVP_RATED_STATS_UPDATE" then
                entry.api.dbRatings = SnapDBRatings()
            end
        elseif event == "UNIT_DIED" then
            -- Direct death event (unit token arg): snapshot the resolved unit
            -- + the between-rounds scoreboard so the rounds-won sampling and
            -- death attribution can be verified from the trace.
            local tok = ...
            if type(tok) == "string" then entry.api.diedUnit = SnapUnit(tok) end
            entry.api.scoreboard = SnapScoreboard()
        end
        if C_PvP and C_PvP.GetCustomVictoryStatID then
            entry.api.victoryStatID = Scrub(C_PvP.GetCustomVictoryStatID())
        end
    end

    trace.events[#trace.events + 1] = entry
end

tracerFrame:SetScript("OnEvent", function(_, event, ...)
    Record(event, ...)
end)

function AI.TraceToggle()
    if recording then
        recording = false
        for _, e in ipairs(TRACKED_EVENTS) do
            pcall(tracerFrame.UnregisterEvent, tracerFrame, e)
        end
        local n = ArenaInsightsDB.trace and #ArenaInsightsDB.trace.events or 0
        print("|cffE6D200ArenaInsights|r trace STOPPED - " .. n .. " events recorded.")
        print("  Log out, then copy ArenaInsightsDB.trace from your SavedVariables")
        print("  file into tests/fixtures/<name>.lua (see tests/replay.lua).")
    else
        recording  = true
        traceStart = GetTime()
        ArenaInsightsDB.trace = {
            interface = select(4, GetBuildInfo()),
            recorded  = time(),
            charKey   = AI.currentCharKey,
            events    = {},
        }
        for _, e in ipairs(TRACKED_EVENTS) do
            pcall(tracerFrame.RegisterEvent, tracerFrame, e)
        end
        print("|cffE6D200ArenaInsights|r trace STARTED - play one match, then /ai trace to stop.")
    end
end

function AI.TraceClear()
    recording = false
    for _, e in ipairs(TRACKED_EVENTS) do
        pcall(tracerFrame.UnregisterEvent, tracerFrame, e)
    end
    ArenaInsightsDB.trace = nil
    print("|cffE6D200ArenaInsights|r trace cleared.")
end
