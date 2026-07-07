-- Validates the record/replay machinery end-to-end without a real fixture:
-- core/Tracer.lua records a scripted match in one env; tests/replay.lua
-- replays that trace into a fresh env; both must produce the same record.
-- When this passes, a trace recorded in-game will replay the same way.

local H      = require("tests.helpers")
local Replay = require("tests.replay")

test("tracer round-trip: recorded trace replays to an identical record", function()
    local w = H.newEnv({ "core/Insights.lua", "core/Tracer.lua" })
    w.AI.TraceToggle()

    H.startSSMatch(w)
    local script = { "win", "loss", "win", "win", "loss", "win" }
    for i, outcome in ipairs(script) do
        H.playRound(w, outcome)
        if i < 6 then H.zoneBetweenRounds(w) end
    end
    H.finishSSMatch(w, 4)
    w.AI.TraceToggle()  -- stop

    local trace = w.env.ArenaInsightsDB.trace
    ok(trace and #trace.events > 0, "trace recorded")

    local w2   = Replay.replay(trace)
    local rec1 = w.env.ArenaInsightsDB.matches[1]
    local rec2 = w2.env.ArenaInsightsDB.matches[1]
    ok(rec1, "original record exists")
    ok(rec2, "replayed record exists")
    eq(rec2.bracketIndex, rec1.bracketIndex, "bracket")
    eq(rec2.outcome, rec1.outcome, "outcome")
    eq(rec2.rating, rec1.rating, "rating")
    eq(rec2.ratingChange, rec1.ratingChange, "ratingChange")
    eq(rec2.wonRounds, rec1.wonRounds, "wonRounds")
    eq(#rec2.shuffle.rounds, #rec1.shuffle.rounds, "round count")
    for i = 1, #rec1.shuffle.rounds do
        eq(rec2.shuffle.rounds[i].outcome, rec1.shuffle.rounds[i].outcome,
            "round " .. i .. " outcome")
    end
end)
