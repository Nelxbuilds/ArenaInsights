-- Replays a trace recorded in-game by core/Tracer.lua (/ai trace) through
-- the headless stub environment, driving the UNMODIFIED addon code with the
-- exact event order and API values the real client produced.
--
-- Fixture format: a Lua file under tests/fixtures/ doing
--   return { interface = ..., recorded = ..., charKey = ..., events = { ... } }
-- i.e. the ArenaInsightsDB.trace table copied verbatim from SavedVariables.

local Stub = require("tests.wow_stub")

local M = {}

-- Recorded "<<SECRET>>" strings become stub Secret values so issecretvalue()
-- behaves like the live client did.
local function Rehydrate(v)
    if v == "<<SECRET>>" then return Stub.Secret("recorded") end
    if type(v) == "table" then
        local out = {}
        for k, val in pairs(v) do out[k] = Rehydrate(val) end
        return out
    end
    return v
end

-- Replay a trace into a fresh env. Returns the stub env for assertions.
function M.replay(trace, loadFiles)
    local w = Stub.new()
    for _, f in ipairs(loadFiles or { "core/Insights.lua" }) do
        w.load(f)
    end
    w.fire("ADDON_LOADED", "ArenaInsights")
    if trace.charKey then
        w.AI.currentCharKey = trace.charKey
        w.env.ArenaInsightsDB.characters[trace.charKey] =
            w.env.ArenaInsightsDB.characters[trace.charKey]
            or { specID = 250, specBrackets = {}, brackets = {} }
    end

    local lastT = 0
    for _, entry in ipairs(trace.events) do
        local t = entry.t or lastT
        if t > lastT then
            w.advance(t - lastT)
            lastT = t
        end

        if entry.cleu then
            w.cleu(table.unpack(Rehydrate(entry.cleu), 1, 15))
        else
            local api = Rehydrate(entry.api or {})
            for k, v in pairs(api) do
                if k == "dbRatings" then
                    for bi, rating in pairs(v) do
                        w.setDBRating(bi, rating)
                    end
                else
                    w.api[k] = v
                end
            end
            w.fire(entry.e, table.unpack(Rehydrate(entry.args or {})))
        end
    end

    -- Let any pending finalize timers run
    w.advance(5)
    return w
end

function M.loadFixture(path)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    return chunk()
end

return M
