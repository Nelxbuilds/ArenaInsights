-- Solo Shuffle / arena capture pipeline specs.
-- Drives the UNMODIFIED core/Insights.lua through synthetic event chains.
-- NOTE: these chains encode our current understanding of Blizzard's event
-- order. Recorded traces (/ai trace -> tests/fixtures/) supersede them.

local Stub = require("tests.wow_stub")
local H    = require("tests.helpers")
local GUIDS = H.GUIDS

test("SS happy path: 6 rounds captured with comps, outcomes, recaps", function()
    local w = H.newEnv()
    H.startSSMatch(w)
    local script = { "win", "loss", "win", "win", "loss", "win" }
    for i, outcome in ipairs(script) do
        H.playRound(w, outcome)
        if i < 6 then H.zoneBetweenRounds(w) end
    end
    H.finishSSMatch(w, 4)

    local m = w.env.ArenaInsightsDB.matches
    eq(#m, 1, "match count")
    local rec = m[1]
    eq(rec.bracketIndex, 7, "bracket")
    eq(rec.outcome, "win", "outcome")
    eq(rec.rating, 1825, "rating")
    eq(rec.ratingChange, 25, "ratingChange from DB diff")
    eq(rec.prematchMMR, 2400, "prematchMMR")
    eq(rec.mmrChange, 12, "mmrChange")
    eq(rec.wonRounds, 4, "wonRounds")
    ok(rec.shuffle and rec.shuffle.rounds, "rounds present")
    eq(#rec.shuffle.rounds, 6, "round count")
    for i, outcome in ipairs(script) do
        eq(rec.shuffle.rounds[i].outcome, outcome, "round " .. i .. " outcome")
    end
end)

test("round allySpecs contains teammates only, never self", function()
    local w = H.newEnv()
    H.startSSMatch(w)
    H.playRound(w, "win")
    H.finishSSMatch(w, 6)

    local r1 = w.env.ArenaInsightsDB.matches[1].shuffle.rounds[1]
    eq(#r1.allySpecs, 2, "ally spec count")
    eq(r1.allySpecs[1], 72, "teammate 1 spec")
    eq(r1.allySpecs[2], 62, "teammate 2 spec")
    eq(#r1.enemySpecs, 3, "enemy spec count")
end)

test("death recap aggregates damage by source+spell with killing blow", function()
    local w = H.newEnv()
    H.startSSMatch(w)
    H.playRound(w, "win")
    H.finishSSMatch(w, 6)

    local deaths = w.env.ArenaInsightsDB.matches[1].shuffle.rounds[1].deaths
    ok(#deaths >= 1, "deaths recorded")
    local first = deaths[1]
    eq(first.name, "Foeone", "victim")
    eq(first.side, "enemy", "side")
    ok(first.recap, "recap present")
    eq(first.recap.killingBlow.spell, "Chaos Bolt", "killing blow spell")
    eq(first.recap.lines[1].amount, 110000, "aggregated damage")
    eq(first.recap.lines[1].hits, 2, "hit count")
end)

test("regression: final round finalized when its end state-change never fires", function()
    local w = H.newEnv()
    H.startSSMatch(w)
    for i = 1, 5 do
        H.playRound(w, "win")
        H.zoneBetweenRounds(w)
    end
    H.playRound(w, "loss", { skipRoundEnd = true })  -- no state 4 for round 6
    H.finishSSMatch(w, 5)

    local rec = w.env.ArenaInsightsDB.matches[1]
    eq(#rec.shuffle.rounds, 6, "all six rounds kept")
    eq(rec.shuffle.rounds[6].outcome, "loss", "round 6 outcome")
end)

test("regression: stale rounds do not leak into the next SS match", function()
    local w = H.newEnv()
    H.startSSMatch(w)
    H.playRound(w, "win")
    H.zoneBetweenRounds(w)
    H.playRound(w, "win")
    -- Match ends abruptly; PVP_RATED_STATS_UPDATE never fires (left early)
    w.fire("PVP_MATCH_COMPLETE", 0, 300)
    w.fire("PLAYER_LEAVING_WORLD")

    -- New SS match queues up
    H.startSSMatch(w)
    H.playRound(w, "loss")
    H.finishSSMatch(w, 0)

    local m = w.env.ArenaInsightsDB.matches
    eq(#m, 1, "one finalized record")
    eq(#m[1].shuffle.rounds, 1, "only the new match's round")
    eq(m[1].shuffle.rounds[1].outcome, "loss", "new round outcome")
end)

test("regression: ally-only deaths give unknown outcome when enemy GUIDs are secret", function()
    local function newBlindEnv()
        local w = H.newEnv()
        H.setupSSUnits(w)
        w.api.units.arena1.guid = Stub.Secret("e1")
        w.api.units.arena2.guid = Stub.Secret("e2")
        w.api.units.arena3.guid = Stub.Secret("e3")
        w.fire("PLAYER_LEAVING_WORLD")
        w.api.isSoloShuffle = true
        w.fire("PVP_MATCH_ACTIVE")
        return w
    end

    local w = newBlindEnv()
    H.playRound(w, "loss")   -- full team wipe: certain loss even blind
    H.finishSSMatch(w, 3)
    local r1 = w.env.ArenaInsightsDB.matches[1].shuffle.rounds[1]
    eq(r1.outcome, "loss", "full ally wipe is still a certain loss")

    -- Partial ally deaths must NOT be guessed as a loss. The death-derived
    -- value is "unknown"; the scoreboard wins-delta then resolves it to the
    -- true outcome (round won despite the teammate death).
    local w2 = newBlindEnv()
    w2.api.matchState = 3
    w2.fire("PVP_MATCH_STATE_CHANGED")
    w2.advance(20)
    H.kill(w2, GUIDS.party1, "Allyone")   -- one teammate dies, we still win the round
    w2.api.matchState = 4
    w2.fire("PVP_MATCH_STATE_CHANGED")
    H.finishSSMatch(w2, 6)

    local r = w2.env.ArenaInsightsDB.matches[1].shuffle.rounds[1]
    eq(r.outcome, "win", "ally death never labels a won round as loss")
end)

test("2v2: bracket from opponent count, outcome from winner arg, rating from DB diff", function()
    local w = H.newEnv()
    w.api.units.player = { guid = GUIDS.player, name = "Tester" }
    w.api.instanceType = "arena"
    w.fire("PLAYER_LEAVING_WORLD")
    w.api.isSoloShuffle = false
    w.fire("PVP_MATCH_ACTIVE")
    w.api.numArenaOpponentSpecs = 2
    w.api.arenaSpecs = { [1] = 62, [2] = 63 }
    w.fire("ARENA_PREP_OPPONENT_SPECIALIZATIONS")

    w.api.arenaFaction = 0
    w.fire("PVP_MATCH_COMPLETE", 0, 240)  -- team 0 wins = us

    w.api.scoreboard = {
        { name = "Tester-TestRealm", isSelf = true, classToken = "WARRIOR",
          talentSpec = "Arms", faction = 0, rating = 0, ratingChange = 0,
          prematchMMR = 1500, postmatchMMR = 1510 },
        { name = "Buddy-TestRealm", classToken = "MAGE", talentSpec = "Arcane",
          faction = 0, prematchMMR = 1500, postmatchMMR = 1510 },
        { name = "Foe1-OtherRealm", classToken = "MAGE", talentSpec = "Fire",
          faction = 1, prematchMMR = 1490, postmatchMMR = 1480 },
        { name = "Foe2-OtherRealm", classToken = "WARRIOR", talentSpec = "Fury",
          faction = 1, prematchMMR = 1490, postmatchMMR = 1480 },
    }
    w.setDBRating(1, 1512)
    w.fire("PVP_RATED_STATS_UPDATE")
    w.advance(2)

    local rec = w.env.ArenaInsightsDB.matches[1]
    eq(rec.bracketIndex, 1, "bracket 2v2")
    eq(rec.outcome, "win", "outcome from winner arg")
    eq(rec.rating, 1512, "rating")
    eq(rec.ratingChange, 12, "ratingChange")
    eq(#rec.enemySpecs, 2, "enemy specs")
    eq(rec.season, 39, "season tag")
end)

test("GetLastKnownMMR: newest real match, per-spec filter, skips simulated", function()
    local w = H.newEnv()
    w.env.ArenaInsightsDB.matches = {
        { charKey = "Tester-TestRealm", bracketIndex = 7, specID = 250,
          prematchMMR = 2000, mmrChange = 20 },
        { charKey = "Tester-TestRealm", bracketIndex = 7, specID = 251,
          prematchMMR = 1800, mmrChange = -10 },
        { charKey = "Tester-TestRealm", bracketIndex = 7, specID = 250,
          prematchMMR = 2100, mmrChange = 15, simulated = true },
    }
    eq(w.AI.GetLastKnownMMR("Tester-TestRealm", 7, 250), 2020, "newest real match for spec")
    eq(w.AI.GetLastKnownMMR("Tester-TestRealm", 7, 251), 1790, "other spec")
    eq(w.AI.GetLastKnownMMR("Tester-TestRealm", 7), 1790, "no spec filter = newest real")
    eq(w.AI.GetLastKnownMMR("Tester-TestRealm", 1), nil, "no data for bracket")
end)

test("session grouping splits on 1h gaps and filters by character", function()
    local w = H.newEnv()
    local base = 1750000000
    w.env.ArenaInsightsDB.matches = {
        { charKey = "Tester-TestRealm", timestamp = base - 8000 },  -- old session
        { charKey = "Tester-TestRealm", timestamp = base - 1200 },
        { charKey = "Alt-TestRealm",    timestamp = base - 900 },   -- other char
        { charKey = "Tester-TestRealm", timestamp = base - 600 },
        { charKey = "Tester-TestRealm", timestamp = base },
    }
    local sess = w.AI.GetLatestSession("Tester-TestRealm")
    eq(#sess, 3, "session size")
    eq(sess[1].timestamp, base - 1200, "chronological start")
    eq(sess[3].timestamp, base, "chronological end")

    local all = w.AI.GetLatestSession(nil)
    eq(#all, 4, "cross-char session size")
end)

-- ----------------------------------------------------------------------------
-- Live Midnight capture conditions: CLEU registration is protected for addons
-- (no death traffic) — round outcomes must come from scoreboard wins-delta
-- sampling, with finalize-time reconciliation as the safety net.
-- ----------------------------------------------------------------------------

test("round outcomes from scoreboard wins delta when death capture is blocked", function()
    local w = H.newEnv()
    H.startSSMatch(w)
    local script = { "win", "loss", "win", "win", "loss", "win" }
    for i, outcome in ipairs(script) do
        H.playRound(w, outcome, { noDeaths = true })
        if i < 6 then H.zoneBetweenRounds(w) end
    end
    H.finishSSMatch(w, 4)

    local rec = w.env.ArenaInsightsDB.matches[1]
    eq(#rec.shuffle.rounds, 6, "round count")
    for i, outcome in ipairs(script) do
        eq(rec.shuffle.rounds[i].outcome, outcome, "round " .. i .. " outcome")
        eq(#rec.shuffle.rounds[i].deaths, 0, "round " .. i .. " has no death data")
    end
end)

test("unreadable round outcomes reconciled against total wins at finalize", function()
    local w = H.newEnv()
    H.startSSMatch(w)
    for i = 1, 6 do
        H.playRound(w, i <= 4 and "win" or "loss", { noDeaths = true, noScore = true })
        if i < 6 then H.zoneBetweenRounds(w) end
    end
    H.finishSSMatch(w, 4)

    local rounds = w.env.ArenaInsightsDB.matches[1].shuffle.rounds
    eq(#rounds, 6, "round count")
    local wins = 0
    for _, r in ipairs(rounds) do
        ok(r.outcome == "win" or r.outcome == "loss", "no unknown outcomes left")
        if r.outcome == "win" then wins = wins + 1 end
    end
    eq(wins, 4, "reconciled win count matches total")
end)

test("rounds-won resolved via victory stat ID when stat order varies", function()
    local w = H.newEnv()
    w.api.victoryStatID = 500
    H.startSSMatch(w)
    H.playRound(w, "win", { noDeaths = true, noScore = true })
    w.fire("PVP_MATCH_COMPLETE", 0, 600)
    local row = H.selfScoreRow(0, 2400, 2412)
    row.stats = {
        { pvpStatID = 900, name = "First Blood", pvpStatValue = 2 },  -- in 0-6 range: stats[1] fallback would misread
        { pvpStatID = 500, name = "Victory",     pvpStatValue = 4 },
    }
    w.api.scoreboard = { row }
    for i = 1, 5 do w.api.scoreboard[#w.api.scoreboard + 1] = H.enemyScoreRow(i) end
    w.setDBRating(7, 1825)
    w.fire("PVP_RATED_STATS_UPDATE")
    w.advance(2)

    eq(w.env.ArenaInsightsDB.matches[1].wonRounds, 4, "wonRounds from victory stat ID")
end)

test("deaths recorded via direct UNIT_DIED event when CLEU is unavailable", function()
    local w = H.newEnv()
    H.startSSMatch(w)
    w.api.matchState = 3
    w.fire("PVP_MATCH_STATE_CHANGED")
    w.advance(10)
    H.unitDied(w, "arena1")
    H.unitDied(w, "arena1")   -- double-report: must dedup
    H.unitDied(w, "party1")
    w.api.matchState = 4
    w.fire("PVP_MATCH_STATE_CHANGED")
    w.ssWins = 1
    w.api.scoreboard = { H.selfScoreRow(1, 2400, 0) }
    w.advance(1)
    H.finishSSMatch(w, 1)

    local r1 = w.env.ArenaInsightsDB.matches[1].shuffle.rounds[1]
    eq(#r1.deaths, 2, "two deaths after dedup")
    eq(r1.deaths[1].side, "enemy", "arena1 is enemy side")
    eq(r1.deaths[1].name, "Foeone", "name resolved from GUID map")
    eq(r1.deaths[2].side, "ally", "party1 is ally side")
    eq(r1.outcome, "win", "outcome from wins delta")
end)

test("round comp falls back to class tokens when specs never resolve", function()
    local w = H.newEnv()
    H.startSSMatch(w)
    w.api.arenaSpecs = {}   -- GetArenaOpponentSpec reads 0 all round
    w.api.units.arena1.classToken = "MAGE"
    w.api.units.arena2.classToken = "ROGUE"
    w.api.units.arena3.classToken = "DRUID"
    H.playRound(w, "win", { noDeaths = true })
    H.finishSSMatch(w, 6)

    local r1 = w.env.ArenaInsightsDB.matches[1].shuffle.rounds[1]
    eq(#r1.enemySpecs, 0, "no enemy specs resolved")
    ok(r1.enemyClasses, "class fallback captured")
    eq(#r1.enemyClasses, 3, "three enemy classes")
    eq(r1.enemyClasses[1], "MAGE", "first class token")
end)
