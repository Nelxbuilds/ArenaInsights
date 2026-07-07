-- Replays every recorded trace in tests/fixtures/ and asserts the pipeline
-- produced a sane match record. Skips silently when no fixtures exist yet —
-- record one in-game with /ai trace (see core/Tracer.lua).

local Replay = require("tests.replay")

local fixtures = {}
local p = io.popen('ls tests/fixtures/*.lua 2>/dev/null')
if p then
    for line in p:lines() do fixtures[#fixtures + 1] = line end
    p:close()
end

for _, file in ipairs(fixtures) do
    test("replay " .. file .. " produces a complete match record", function()
        local trace = Replay.loadFixture(file)
        local w = Replay.replay(trace)
        local m = w.env.ArenaInsightsDB.matches
        ok(#m >= 1, "at least one match recorded")
        local rec = m[#m]
        ok(rec.bracketIndex, "bracket detected")
        ok(rec.outcome and rec.outcome ~= "unknown", "outcome derived")
        ok(rec.rating, "rating captured")
        if rec.bracketIndex == 7 then
            ok(rec.shuffle, "shuffle data present")
        end
    end)
end
