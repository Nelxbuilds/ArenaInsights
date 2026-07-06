local addonName, AI = ...

-- ============================================================================
-- Dev tooling: fabricate complete match records and push them through the
-- same write path + UI hooks as live capture, so every UI surface (Insights
-- list/detail/round tooltips, session popup, filters, stats) is testable
-- without queueing. Does NOT exercise live event capture — that still needs
-- one real match with /ai debug on.
--
-- Every record is tagged simulated=true. Remove all with /ai sim clear.
-- ============================================================================

local SIM_SPELLS = {
    "Mortal Strike", "Chaos Bolt", "Execute", "Kill Shot",
    "Death Coil", "Pyroblast", "Templar's Verdict", "Eviscerate",
}
local SIM_NAMES = {
    "Simfoe", "Simbad", "Simmer", "Simple", "Simian", "Simurgh",
}

local function RandomSpecID()
    local pool = {}
    for sid in pairs(AI.specData or {}) do pool[#pool + 1] = sid end
    if #pool == 0 then return 71 end  -- Arms fallback if spec data not built yet
    return pool[math.random(#pool)]
end

local function RandomSpecs(n)
    local t = {}
    for i = 1, n do t[i] = RandomSpecID() end
    return t
end

local function SimName(i)
    return SIM_NAMES[((i - 1) % #SIM_NAMES) + 1] .. i
end

local function BuildRecap(victimName)
    local lines = {}
    for i = 1, math.random(2, 4) do
        lines[i] = {
            src    = SimName(math.random(1, 3)),
            spell  = SIM_SPELLS[math.random(#SIM_SPELLS)],
            hits   = math.random(1, 6),
            amount = math.random(80000, 900000),
        }
    end
    table.sort(lines, function(a, b) return a.amount > b.amount end)
    return {
        window      = (ArenaInsightsDB.settings and ArenaInsightsDB.settings.deathRecapWindow) or 8,
        killingBlow = { src = lines[1].src, spell = lines[1].spell, amount = lines[1].amount },
        lines       = lines,
    }
end

local function BuildRounds(wonRounds)
    local rounds = {}
    local outcomes = {}
    for i = 1, wonRounds do outcomes[#outcomes + 1] = "win" end
    while #outcomes < 6 do outcomes[#outcomes + 1] = "loss" end
    -- shuffle the outcome order
    for i = #outcomes, 2, -1 do
        local j = math.random(i)
        outcomes[i], outcomes[j] = outcomes[j], outcomes[i]
    end
    for i = 1, 6 do
        local deaths = {}
        for d = 1, math.random(1, 2) do
            local side = (outcomes[i] == "win") and "enemy" or "ally"
            if d == 2 then side = (side == "enemy") and "ally" or "enemy" end
            local nm = SimName(math.random(1, 6))
            deaths[d] = {
                name   = nm,
                specID = RandomSpecID(),
                side   = side,
                t      = math.random(15, 80),
                recap  = BuildRecap(nm),
            }
        end
        table.sort(deaths, function(a, b) return a.t < b.t end)
        rounds[i] = {
            num        = i,
            outcome    = outcomes[i],
            duration   = math.random(25, 95),
            allySpecs  = RandomSpecs(2),
            enemySpecs = RandomSpecs(3),
            deaths     = deaths,
        }
    end
    return rounds
end

local function BuildPlayers(n, mmrBase)
    local out = {}
    for i = 1, n do
        out[i] = {
            name         = SimName(i),
            realm        = "SimRealm",
            charKey      = SimName(i) .. "-SimRealm",
            specID       = RandomSpecID(),
            prematchMMR  = mmrBase + math.random(-120, 120),
            mmrChange    = math.random(-20, 20),
            damageDone   = math.random(2000000, 60000000),
            healingDone  = math.random(500000, 40000000),
            killingBlows = math.random(0, 5),
        }
    end
    return out
end

local function LastRating(charKey, bracket)
    local matches = AI.GetMatches()
    for i = #matches, 1, -1 do
        local r = matches[i]
        if r.charKey == charKey and r.bracketIndex == bracket and r.rating then
            return r.rating
        end
    end
    return 1400 + math.random(0, 600)
end

local function SimulateOne(timestamp)
    local brackets = AI.TRACKED_BRACKETS or { 1, 2, 4, 7 }
    local bracket  = brackets[math.random(#brackets)]
    local isSS     = bracket == AI.BRACKET_SOLO_SHUFFLE

    local charKey = AI.currentCharKey or "Tester-SimRealm"
    local char    = ArenaInsightsDB.characters and ArenaInsightsDB.characters[charKey]
    local specID  = (char and char.specID) or RandomSpecID()

    local prevRating = LastRating(charKey, bracket)
    local won        = math.random() < 0.5
    local delta      = math.random(8, 24) * (won and 1 or -1)
    local mmr        = prevRating + math.random(-80, 150)

    local rec = {
        timestamp    = timestamp,
        simulated    = true,
        charKey      = charKey,
        specID       = specID,
        bracketIndex = bracket,
        outcome      = won and "win" or "loss",
        rating       = math.max(0, prevRating + delta),
        ratingChange = delta,
        prematchMMR  = mmr,
        mmrChange    = math.random(5, 25) * (won and 1 or -1),
        damageDone   = math.random(5000000, 80000000),
        healingDone  = math.random(1000000, 30000000),
        killingBlows = math.random(0, 6),
    }
    rec.season = (GetCurrentArenaSeason and GetCurrentArenaSeason()) or nil

    if isSS then
        local wonRounds = won and math.random(4, 6) or math.random(0, 2)
        rec.wonRounds = wonRounds
        rec.shuffle = {
            wonRounds   = wonRounds,
            lostRounds  = 6 - wonRounds,
            totalRounds = 6,
            rounds      = BuildRounds(wonRounds),
        }
        rec.enemySpecs   = RandomSpecs(5)
        rec.enemyPlayers = BuildPlayers(5, mmr)
    else
        local enemies = (bracket == AI.BRACKET_2V2) and 2 or 3
        rec.enemySpecs   = RandomSpecs(enemies)
        rec.enemyPlayers = BuildPlayers(enemies, mmr)
        if bracket ~= AI.BRACKET_BLITZ then
            rec.allySpecs   = RandomSpecs(enemies - 1)
            rec.allyPlayers = BuildPlayers(enemies - 1, mmr)
        end
    end

    ArenaInsightsDB.matches = ArenaInsightsDB.matches or {}
    ArenaInsightsDB.matches[#ArenaInsightsDB.matches + 1] = rec
    return rec
end

-- Public: add n simulated matches (default 1), spread minutes apart so they
-- form one session, then fire the same UI hooks as live capture.
function AI.SimulateMatches(n)
    n = math.max(1, math.min(tonumber(n) or 1, 50))
    local now = time()
    local last
    for i = 1, n do
        last = SimulateOne(now - (n - i) * 180)
    end
    print(("|cffE6D200ArenaInsights|r added %d simulated match%s (/ai sim clear to remove)")
        :format(n, n == 1 and "" or "es"))
    if AI.RefreshInsights then AI.RefreshInsights() end
    if AI.RefreshMatchups then AI.RefreshMatchups() end
    if AI.OnMatchRecorded and last then AI.OnMatchRecorded(last) end
end

-- Public: remove every simulated record.
function AI.ClearSimulatedMatches()
    local matches = ArenaInsightsDB.matches
    if not matches then return end
    local kept, removed = {}, 0
    for _, r in ipairs(matches) do
        if r.simulated then
            removed = removed + 1
        else
            kept[#kept + 1] = r
        end
    end
    ArenaInsightsDB.matches = kept
    print(("|cffE6D200ArenaInsights|r removed %d simulated match%s")
        :format(removed, removed == 1 and "" or "es"))
    if AI.RefreshInsights then AI.RefreshInsights() end
    if AI.RefreshMatchups then AI.RefreshMatchups() end
end
