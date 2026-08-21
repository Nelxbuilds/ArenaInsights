-- Season scoping for challenges: "Reset each season" challenges only count
-- ratings stamped with the current season, lifetime challenges count any.

local H = require("tests.helpers")

local FILES = { "core/Core.lua", "core/Insights.lua", "core/Challenges.lua" }

local function newEnv(season)
    local w = H.newEnv(FILES)
    w.api.currentArenaSeason = season
    w.env.ArenaInsightsDB.challenges = {}
    return w
end

test("SaveBracketData stamps the current season on the snapshot", function()
    local w = newEnv(42)
    local AI = w.AI
    AI.currentCharKey = "Tester-TestRealm"
    AI.SaveBracketData(2, 1900, 0)
    eq(AI.GetRating("Tester-TestRealm", 2).season, 42, "season stamped")
end)

test("GetRating with a seasonId hides other-season and untagged snapshots", function()
    local w = newEnv(42)
    local AI = w.AI
    local char = w.env.ArenaInsightsDB.characters["Tester-TestRealm"]
    char.brackets[2] = { rating = 2400, season = 41 }
    char.brackets[1] = { rating = 2100 }  -- pre-season-stamping snapshot

    ok(AI.GetRating("Tester-TestRealm", 2), "no filter returns last season's rating")
    eq(AI.GetRating("Tester-TestRealm", 2, nil, 42), nil, "season 41 rating filtered out")
    eq(AI.GetRating("Tester-TestRealm", 1, nil, 42), nil, "untagged rating filtered out")

    char.brackets[2].season = 42
    eq(AI.GetRating("Tester-TestRealm", 2, nil, 42).rating, 2400, "current season passes")
end)

test("GetChallengeSeason is nil for lifetime challenges, current for season-reset", function()
    local w = newEnv(42)
    local AI = w.AI
    eq(AI.GetChallengeSeason({ }), nil, "lifetime challenge -> no season filter")
    eq(AI.GetChallengeSeason({ seasonReset = true }), 42, "season-reset -> current season")
end)

test("manual completions on a season-reset challenge start over each season", function()
    local w = newEnv(42)
    local AI = w.AI
    local c = AI.AddChallenge({ name = "S", goalRating = 1800, seasonReset = true })

    AI.SetSpecCompleted(c.id, 250, true)
    AI.SetClassCompleted(c.id, 6, true)
    ok(AI.IsSpecCompleted(c.id, 250), "completed this season")
    ok(AI.IsClassCompleted(c.id, 6), "class completed this season")

    w.api.currentArenaSeason = 43
    eq(AI.IsSpecCompleted(c.id, 250), false, "cleared after rollover")
    eq(AI.IsClassCompleted(c.id, 6), false, "class cleared after rollover")

    w.api.currentArenaSeason = 42
    ok(AI.IsSpecCompleted(c.id, 250), "last season's ticks are kept, not destroyed")
end)

test("manual completions on a lifetime challenge survive a rollover", function()
    local w = newEnv(42)
    local AI = w.AI
    local c = AI.AddChallenge({ name = "L", goalRating = 1800 })

    AI.SetSpecCompleted(c.id, 250, true)
    w.api.currentArenaSeason = 43
    ok(AI.IsSpecCompleted(c.id, 250), "still completed in the new season")
end)

test("reading completions never writes a season bucket", function()
    local w = newEnv(42)
    local AI = w.AI
    local c = AI.AddChallenge({ name = "S", goalRating = 1800, seasonReset = true })
    eq(AI.IsSpecCompleted(c.id, 250), false, "not completed")
    eq(c.seasonProgress, nil, "no bucket created by a read")
end)
