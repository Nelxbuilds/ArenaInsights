-- Shared spec helpers: scripted Solo Shuffle matches against the stub env.
local Stub = require("tests.wow_stub")

local H = {}

H.GUIDS = {
    player = "Player-1-ME",
    party1 = "Player-1-A1",
    party2 = "Player-1-A2",
    arena1 = "Player-1-E1",
    arena2 = "Player-1-E2",
    arena3 = "Player-1-E3",
}
local GUIDS = H.GUIDS

function H.newEnv(files)
    local w = Stub.new()
    for _, f in ipairs(files or { "core/Insights.lua" }) do
        w.load(f)
    end
    w.fire("ADDON_LOADED", "ArenaInsights")
    return w
end

function H.setupSSUnits(w)
    w.api.units.player = { guid = GUIDS.player, name = "Tester" }
    w.api.units.party1 = { guid = GUIDS.party1, name = "Allyone" }
    w.api.units.party2 = { guid = GUIDS.party2, name = "Allytwo" }
    w.api.units.arena1 = { guid = GUIDS.arena1, name = "Foeone" }
    w.api.units.arena2 = { guid = GUIDS.arena2, name = "Foetwo" }
    w.api.units.arena3 = { guid = GUIDS.arena3, name = "Foethree" }
    w.api.arenaSpecs   = { [1] = 62, [2] = 63, [3] = 71 }
    w.api.inspectSpecs = { party1 = 72, party2 = 62 }
end

function H.kill(w, guid, name)
    w.cleu(0, "UNIT_DIED", false, nil, nil, 0, 0, guid, name)
end

function H.damage(w, srcName, destGUID, destName, spell, amount)
    w.cleu(0, "SPELL_DAMAGE", false, "Player-1-X", srcName, 0, 0,
        destGUID, destName, 0, 0, 12345, spell, 4, amount)
end

-- Direct UNIT_DIED event (the Midnight death source when CLEU is protected).
function H.unitDied(w, token)
    w.fire("UNIT_DIED", token)
end

-- One SS round: engage, some damage, kills for the losing side, round end.
-- outcome "win" = enemies die, "loss" = my team dies.
-- opts.noDeaths: no CLEU traffic (live behavior: CLEU registration blocked)
-- opts.noScore:  no between-rounds scoreboard (round-outcome sampling fails)
function H.playRound(w, outcome, opts)
    opts = opts or {}
    w.api.matchState = 3
    w.fire("PVP_MATCH_STATE_CHANGED")
    w.advance(20)

    if not opts.noDeaths then
        if outcome == "win" then
            H.damage(w, "Tester", GUIDS.arena1, "Foeone", "Chaos Bolt", 50000)
            H.damage(w, "Tester", GUIDS.arena1, "Foeone", "Chaos Bolt", 60000)
            H.kill(w, GUIDS.arena1, "Foeone")
            w.advance(5)
            H.kill(w, GUIDS.arena2, "Foetwo")
            H.kill(w, GUIDS.arena3, "Foethree")
        else
            H.damage(w, "Foeone", GUIDS.player, "Tester", "Mortal Strike", 80000)
            H.kill(w, GUIDS.player, "Tester")
            w.advance(5)
            H.kill(w, GUIDS.party1, "Allyone")
            H.kill(w, GUIDS.party2, "Allytwo")
        end
    end

    if not opts.skipRoundEnd then
        w.api.matchState = 4
        w.fire("PVP_MATCH_STATE_CHANGED")
        -- Between-rounds scoreboard: the self row with cumulative wins is
        -- readable after the round ends and feeds the outcome sampling burst.
        w.ssWins = (w.ssWins or 0) + (outcome == "win" and 1 or 0)
        if not opts.noScore then
            w.api.scoreboard = { H.selfScoreRow(w.ssWins, 2400, 0) }
        end
        w.advance(1)  -- run the sampling burst timers
    end
end

-- Inter-round zone transition; IsSoloShuffle() reads false during the load screen.
function H.zoneBetweenRounds(w)
    w.fire("PLAYER_LEAVING_WORLD")
    w.api.isSoloShuffle = false
    w.fire("PVP_MATCH_ACTIVE")
    w.api.isSoloShuffle = true
end

function H.selfScoreRow(wonRounds, preMMR, postMMR)
    return {
        name = "Tester-TestRealm", isSelf = true, classToken = "WARRIOR",
        talentSpec = "Arms", faction = 0, rating = 0, ratingChange = 0,
        prematchMMR = preMMR, postmatchMMR = postMMR,
        damageDone = 1000, healingDone = 500, killingBlows = 2,
        stats = { { pvpStatValue = wonRounds } },
    }
end

function H.enemyScoreRow(i)
    return {
        name = "Foe" .. i .. "-OtherRealm", classToken = "MAGE", talentSpec = "Fire",
        faction = 1, prematchMMR = 2380, postmatchMMR = 2370,
        damageDone = 900, healingDone = 100, killingBlows = 1,
    }
end

function H.startSSMatch(w)
    H.setupSSUnits(w)
    w.ssWins = 0                       -- new match = new instance: fresh scoreboard
    w.api.scoreboard = {}
    w.fire("PLAYER_LEAVING_WORLD")     -- zoning into the arena: snapshot
    w.api.isSoloShuffle = true
    w.fire("PVP_MATCH_ACTIVE")
end

function H.finishSSMatch(w, wonRounds)
    w.fire("PVP_MATCH_COMPLETE", 0, 600)
    w.api.scoreboard = { H.selfScoreRow(wonRounds, 2400, 2412) }
    for i = 1, 5 do w.api.scoreboard[#w.api.scoreboard + 1] = H.enemyScoreRow(i) end
    w.setDBRating(7, 1825)             -- Core wrote the new rating
    w.fire("PVP_RATED_STATS_UPDATE")
    w.advance(2)                       -- run the 1.5s finalize timer
end

return H
