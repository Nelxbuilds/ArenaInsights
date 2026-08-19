-- Season separation via rec.season (GetCurrentArenaSeason stamped per match).

local Stub = require("tests.wow_stub")
local H    = require("tests.helpers")

test("GetCurrentSeasonId uses the live API, falls back to newest rec.season", function()
    local w = H.newEnv()
    local AI = w.AI
    w.env.ArenaInsightsDB.matches = {
        { season = 39 }, { season = 40 },
    }

    w.api.currentArenaSeason = 40
    eq(AI.GetCurrentSeasonId(), 40, "live API wins")

    w.api.currentArenaSeason = nil
    eq(AI.GetCurrentSeasonId(), 40, "fallback = highest stamped season")
end)

test("HasMultipleSeasons true only when matches span more than the current", function()
    local w = H.newEnv()
    local AI = w.AI
    w.api.currentArenaSeason = 40

    w.env.ArenaInsightsDB.matches = { { season = 40 }, { season = 40 } }
    eq(AI.HasMultipleSeasons(), false, "all current season")

    w.env.ArenaInsightsDB.matches = { { season = 39 }, { season = 40 } }
    eq(AI.HasMultipleSeasons(), true, "previous + current season present")

    w.env.ArenaInsightsDB.matches = { { season = nil }, { season = 40 } }
    eq(AI.HasMultipleSeasons(), true, "untagged legacy match counts as other season")
end)

test("GetCurrentSeasonStart is the earliest current-season match timestamp", function()
    local w = H.newEnv()
    local AI = w.AI
    w.api.currentArenaSeason = 42
    w.env.ArenaInsightsDB.matches = {
        { season = 41, timestamp = 100 },
        { season = 42, timestamp = 500 },  -- earliest of season 42
        { season = 42, timestamp = 900 },
    }
    eq(AI.GetCurrentSeasonStart(), 500, "earliest season-42 timestamp")

    w.env.ArenaInsightsDB.matches = { { season = 41, timestamp = 100 } }
    eq(AI.GetCurrentSeasonStart(), nil, "nil when no current-season match")
end)

test("PrintSeasonInfo tolerates untagged (nil-season) matches", function()
    local w = H.newEnv()
    local AI = w.AI
    w.api.currentArenaSeason = 42
    w.env.ArenaInsightsDB.matches = {
        { season = nil }, { season = 41 }, { season = 42 },
    }
    local lines = {}
    w.env.print = function(...) lines[#lines + 1] = table.concat({ ... }, " ") end
    local okCall = pcall(AI.PrintSeasonInfo)
    ok(okCall, "PrintSeasonInfo does not error on a nil rec.season")
    ok(#lines > 0, "it printed a breakdown")
end)

test("GetShuffleSpecStats seasonId filter isolates seasons", function()
    local w = H.newEnv()
    local AI = w.AI
    w.env.ArenaInsightsDB.matches = {
        -- Season 39: a win vs spec 63
        { bracketIndex = 7, season = 39, shuffle = { rounds = {
            { outcome = "win", enemySpecs = { 63 } },
        } } },
        -- Season 40: a loss vs spec 63
        { bracketIndex = 7, season = 40, shuffle = { rounds = {
            { outcome = "loss", enemySpecs = { 63 } },
        } } },
    }

    local function statFor(list, sid)
        for _, e in ipairs(list) do if e.specID == sid then return e end end
    end

    local s39 = statFor(AI.GetShuffleSpecStats(nil, nil, 39), 63)
    eq(s39.w, 1, "season 39: one win"); eq(s39.l, 0, "season 39: no loss")

    local s40 = statFor(AI.GetShuffleSpecStats(nil, nil, 40), 63)
    eq(s40.w, 0, "season 40: no win"); eq(s40.l, 1, "season 40: one loss")

    local all = statFor(AI.GetShuffleSpecStats(nil, nil, nil), 63)
    eq(all.w, 1, "all seasons: one win"); eq(all.l, 1, "all seasons: one loss")
end)
