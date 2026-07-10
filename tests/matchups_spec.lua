-- Specs for session MMR delta and Matchups aggregation (core/Insights.lua).
-- These operate on ArenaInsightsDB.matches directly — no event chains needed.

local H = require("tests.helpers")

local function envWithMatches(matches)
    local w = H.newEnv()
    w.env.ArenaInsightsDB.matches = matches
    return w
end

-- ----------------------------------------------------------------------------
-- AI.GetSessionMMRDelta
-- ----------------------------------------------------------------------------

test("session MMR delta derived from prematchMMR when mmrChange is 0", function()
    local session = {
        { bracketIndex = 7, specID = 250, prematchMMR = 2400, mmrChange = 0 },
        { bracketIndex = 7, specID = 250, prematchMMR = 2450, mmrChange = 0 },
        { bracketIndex = 7, specID = 250, prematchMMR = 2480, mmrChange = 0 },
    }
    local w = H.newEnv()
    eq(w.AI.GetSessionMMRDelta(session, 7), 80, "SS delta")
end)

test("session MMR delta includes newest match's mmrChange when captured", function()
    local session = {
        { bracketIndex = 1, prematchMMR = 1500, mmrChange = 0 },
        { bracketIndex = 1, prematchMMR = 1520, mmrChange = 15 },
    }
    local w = H.newEnv()
    eq(w.AI.GetSessionMMRDelta(session, 1), 35, "2v2 delta")
end)

test("session MMR delta per-spec bracket ignores other specs", function()
    local session = {
        { bracketIndex = 7, specID = 251, prematchMMR = 1200, mmrChange = 0 },
        { bracketIndex = 7, specID = 250, prematchMMR = 2400, mmrChange = 0 },
        { bracketIndex = 7, specID = 250, prematchMMR = 2440, mmrChange = 0 },
    }
    local w = H.newEnv()
    eq(w.AI.GetSessionMMRDelta(session, 7), 40, "only spec 250 compared")
end)

test("session MMR delta nil without MMR data, 0-ish with single match", function()
    local w = H.newEnv()
    eq(w.AI.GetSessionMMRDelta({}, 7), nil, "empty session")
    eq(w.AI.GetSessionMMRDelta(
        { { bracketIndex = 7, specID = 250, prematchMMR = 0, mmrChange = 0 } }, 7),
        nil, "no usable MMR")
    eq(w.AI.GetSessionMMRDelta(
        { { bracketIndex = 7, specID = 250, prematchMMR = 2400, mmrChange = 0 } }, 7),
        0, "single match, change unknowable")
end)

-- ----------------------------------------------------------------------------
-- AI.GetArenaCompStats
-- ----------------------------------------------------------------------------

test("arena comp stats aggregate by bracket + sorted enemy specs", function()
    local w = envWithMatches({
        { bracketIndex = 2, outcome = "win",  enemySpecs = { 70, 253, 264 } },
        { bracketIndex = 2, outcome = "loss", enemySpecs = { 264, 70, 253 } }, -- same comp, different order
        { bracketIndex = 1, outcome = "win",  enemySpecs = { 259, 105 } },
        { bracketIndex = 7, outcome = "win",  enemySpecs = { 1, 2, 3, 4, 5 } }, -- SS ignored
        { bracketIndex = 2, outcome = "win",  enemySpecs = { 70 } },            -- <2 known specs ignored
    })
    local stats = w.AI.GetArenaCompStats()
    eq(#stats, 2, "comp count")
    local byKey = {}
    for _, e in ipairs(stats) do byKey[e.key] = e end
    local trio = byKey["2:70-253-264"]
    ok(trio, "3v3 comp present")
    eq(trio.w, 1, "trio wins")
    eq(trio.l, 1, "trio losses")
    local duo = byKey["1:105-259"]
    ok(duo, "2v2 comp present")
    eq(duo.w, 1, "duo wins")
end)

test("arena comp stats: live and simulated never mix; sim used only when no live", function()
    local w = envWithMatches({
        { bracketIndex = 1, outcome = "win", enemySpecs = { 259, 105 } },
        { bracketIndex = 1, outcome = "win", enemySpecs = { 259, 105 }, simulated = true },
    })
    local stats = w.AI.GetArenaCompStats()
    eq(#stats, 1, "one comp")
    eq(stats[1].w, 1, "sim record not mixed in")

    local w2 = envWithMatches({
        { bracketIndex = 1, outcome = "win", enemySpecs = { 259, 105 }, simulated = true },
    })
    local stats2 = w2.AI.GetArenaCompStats()
    eq(#stats2, 1, "sim-only dataset used when no live data")
end)

test("arena comp stats filter by bracket, character, and spec", function()
    local w = envWithMatches({
        { bracketIndex = 1, outcome = "win",  charKey = "A-R", specID = 250, enemySpecs = { 259, 105 } },
        { bracketIndex = 2, outcome = "win",  charKey = "A-R", specID = 250, enemySpecs = { 259, 105, 70 } },
        { bracketIndex = 1, outcome = "loss", charKey = "B-R", specID = 251, enemySpecs = { 259, 105 } },
        { bracketIndex = 1, outcome = "win",  charKey = "A-R", specID = 252, enemySpecs = { 259, 105 } },
    })
    -- bracket only: 2v2 excludes the 3v3 record
    eq(#w.AI.GetArenaCompStats(1), 1, "2v2 comps across all chars")
    eq(#w.AI.GetArenaCompStats(2), 1, "3v3 comps across all chars")
    -- bracket + char
    local a2v2 = w.AI.GetArenaCompStats(1, "A-R")
    eq(#a2v2, 1, "A-R 2v2 comps")
    eq(a2v2[1].w, 2, "both A-R 2v2 wins on this comp (specs 250 + 252)")
    eq(#w.AI.GetArenaCompStats(1, "B-R"), 1, "B-R 2v2 comps")
    -- bracket + char + spec
    local a250 = w.AI.GetArenaCompStats(1, "A-R", 250)
    eq(a250[1].w, 1, "only the spec-250 win counts")
end)

test("shuffle spec stats filter by character and spec", function()
    local w = envWithMatches({
        {
            bracketIndex = 7, outcome = "win", charKey = "A-R", specID = 250,
            shuffle = { rounds = { { num = 1, outcome = "win", enemySpecs = { 62 } } } },
        },
        {
            bracketIndex = 7, outcome = "loss", charKey = "B-R", specID = 251,
            shuffle = { rounds = { { num = 1, outcome = "loss", enemySpecs = { 62 } } } },
        },
    })
    eq(#w.AI.GetShuffleSpecStats(), 1, "one enemy spec across all chars")
    local all = w.AI.GetShuffleSpecStats()
    eq(all[1].w, 1, "1 win"); eq(all[1].l, 1, "1 loss")
    local a = w.AI.GetShuffleSpecStats("A-R")
    eq(a[1].w, 1, "A-R win"); eq(a[1].l, 0, "no A-R loss")
    eq(#w.AI.GetShuffleSpecStats("A-R", 999), 0, "no matches on unplayed spec")
end)

-- ----------------------------------------------------------------------------
-- AI.GetShuffleSpecStats
-- ----------------------------------------------------------------------------

test("shuffle spec stats credit round outcomes to each enemy spec", function()
    local w = envWithMatches({
        {
            bracketIndex = 7, outcome = "win",
            shuffle = { wonRounds = 4, lostRounds = 2, totalRounds = 6, rounds = {
                { num = 1, outcome = "win",     enemySpecs = { 62, 63, 71 } },
                { num = 2, outcome = "loss",    enemySpecs = { 62, 65, 71 } },
                { num = 3, outcome = "unknown", enemySpecs = { 62, 63, 71 } }, -- ignored
            } },
        },
        { bracketIndex = 7, outcome = "win", shuffle = { wonRounds = 4, lostRounds = 2, totalRounds = 6 } }, -- no rounds: ignored
    })
    local stats = w.AI.GetShuffleSpecStats()
    local bySpec = {}
    for _, e in ipairs(stats) do bySpec[e.specID] = e end
    eq(bySpec[62].w, 1, "spec 62 wins")
    eq(bySpec[62].l, 1, "spec 62 losses")
    eq(bySpec[63].w, 1, "spec 63 wins")
    eq(bySpec[63].l, 0, "spec 63 losses")
    eq(bySpec[65].l, 1, "spec 65 losses")
    ok(bySpec[71], "spec 71 present")
end)
