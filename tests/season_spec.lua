-- Season separation: rollover detection (core/Core.lua) and the timestamp-based
-- season index + aggregator filter (core/Insights.lua).

local Stub = require("tests.wow_stub")
local H    = require("tests.helpers")

-- Drive one CapturePvPStats pass for `charKey` with per-bracket seasonPlayed.
-- currentCharKey survives UpdateCharacterInfo (no player unit -> early return).
local function capture(w, charKey, seasonPlayedByBracket)
    w.AI.currentCharKey = charKey
    w.api.ratedInfo = {}
    for bracket, sp in pairs(seasonPlayedByBracket) do
        w.api.ratedInfo[bracket] = { rating = 0, seasonPlayed = sp }
    end
    w.fire("PVP_RATED_STATS_UPDATE")
    w.advance(0.6)  -- run the 0.5s capture debounce timer
end

local function newCoreEnv()
    local w = Stub.new()
    w.load("core/Core.lua")
    w.fire("ADDON_LOADED", "ArenaInsights")
    return w
end

test("season rollover: seasonPlayed dropping to 0 appends one boundary", function()
    local w = newCoreEnv()
    local db = w.env.ArenaInsightsDB

    -- Season 1: counts climb, no boundary.
    capture(w, "Main-R", { [7] = 40, [2] = 20 })
    capture(w, "Main-R", { [7] = 55, [2] = 25 })
    eq(#db.seasonBoundaries, 0, "no boundary while seasonPlayed grows")

    -- New season: all brackets reset to 0 -> exactly one boundary.
    capture(w, "Main-R", { [7] = 0, [2] = 0 })
    eq(#db.seasonBoundaries, 1, "one boundary on reset (not one per bracket)")

    -- Season 2 climbs again: no further boundary.
    capture(w, "Main-R", { [7] = 3, [2] = 1 })
    eq(#db.seasonBoundaries, 1, "no extra boundary as season 2 grows")
end)

test("season rollover: partial reset (one bracket unplayed) still fires once", function()
    local w = newCoreEnv()
    local db = w.env.ArenaInsightsDB

    capture(w, "Main-R", { [7] = 60, [2] = 10 })
    -- Only the bracket you actually replayed reports the reset (2v2 unplayed = 0).
    capture(w, "Main-R", { [7] = 2, [2] = 0 })
    eq(#db.seasonBoundaries, 1, "single boundary")
end)

test("season rollover: switching to a fresh alt does NOT append a boundary", function()
    local w = newCoreEnv()
    local db = w.env.ArenaInsightsDB

    -- Main has lots of games this season.
    capture(w, "Main-R", { [7] = 80, [2] = 40 })
    -- Switch to an alt with far fewer games in the SAME season.
    capture(w, "Alt-R",  { [7] = 3,  [2] = 0 })
    capture(w, "Alt-R",  { [7] = 5,  [2] = 1 })
    -- Back to main.
    capture(w, "Main-R", { [7] = 82, [2] = 41 })
    eq(#db.seasonBoundaries, 0, "alt switches never look like a reset")
end)

test("season rollover: an alt behind by a season catches up without a 2nd boundary", function()
    local w = newCoreEnv()
    local db = w.env.ArenaInsightsDB

    capture(w, "Main-R", { [7] = 80 })
    capture(w, "Alt-R",  { [7] = 30 })

    -- Real rollover detected on main first.
    capture(w, "Main-R", { [7] = 1 })
    eq(#db.seasonBoundaries, 1, "rollover recorded once on main")

    -- The alt (last seen in the previous season) now resets too — it's catching
    -- up to the already-recorded rollover, not a new season.
    capture(w, "Alt-R",  { [7] = 2 })
    eq(#db.seasonBoundaries, 1, "alt catch-up adds no second boundary")
end)

test("GetSeasonIndex maps timestamps around boundaries", function()
    local w = H.newEnv()  -- loads core/Insights.lua
    w.env.ArenaInsightsDB.seasonBoundaries = { 2000, 5000 }

    eq(w.AI.GetSeasonCount(), 3, "two boundaries = three seasons")
    eq(w.AI.GetSeasonIndex(1500), 1, "before first boundary = season 1")
    eq(w.AI.GetSeasonIndex(2000), 2, "at boundary = new season")
    eq(w.AI.GetSeasonIndex(4999), 2, "between boundaries = season 2")
    eq(w.AI.GetSeasonIndex(9000), 3, "after last boundary = current")
    eq(w.AI.GetSeasonIndex(nil), 3, "nil timestamp = current season")
end)

test("GetShuffleSpecStats seasonIndex filter isolates seasons", function()
    local w = H.newEnv()
    local AI = w.AI
    w.env.ArenaInsightsDB.seasonBoundaries = { 5000 }
    w.env.ArenaInsightsDB.matches = {
        -- Season 1 (before 5000): a win vs spec 63
        { bracketIndex = 7, timestamp = 1000, shuffle = { rounds = {
            { outcome = "win", enemySpecs = { 63 } },
        } } },
        -- Season 2 (>= 5000): a loss vs spec 63
        { bracketIndex = 7, timestamp = 6000, shuffle = { rounds = {
            { outcome = "loss", enemySpecs = { 63 } },
        } } },
    }

    local function statFor(list, sid)
        for _, e in ipairs(list) do if e.specID == sid then return e end end
    end

    local s1 = statFor(AI.GetShuffleSpecStats(nil, nil, 1), 63)
    eq(s1.w, 1, "season 1: one win"); eq(s1.l, 0, "season 1: no loss")

    local s2 = statFor(AI.GetShuffleSpecStats(nil, nil, 2), 63)
    eq(s2.w, 0, "season 2: no win"); eq(s2.l, 1, "season 2: one loss")

    local all = statFor(AI.GetShuffleSpecStats(nil, nil, nil), 63)
    eq(all.w, 1, "all seasons: one win"); eq(all.l, 1, "all seasons: one loss")
end)
