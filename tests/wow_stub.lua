-- Headless WoW environment for testing addon logic outside the game.
-- Loads addon files unmodified into a sandboxed global table with stubbed
-- WoW API. Test code controls every API return and fires events exactly the
-- way the WoW client dispatches them.
--
-- Secrets: represent a secret value in fixtures as Secret("x") — the stubbed
-- issecretvalue() recognizes it.

local M = {}

local SECRET_MT = { __tostring = function() return "<<SECRET>>" end }

function M.Secret(v)
    return setmetatable({ value = v }, SECRET_MT)
end

function M.new()
    local env  = {}   -- sandbox _G for addon chunks
    local self = { env = env }

    -- ---- fake clock + timer queue ----
    local now    = 1750000000.0
    local timers = {}
    function self.now() return now end
    function self.advance(dt)
        local target = now + dt
        while true do
            local best
            for i, t in ipairs(timers) do
                if t.at <= target and (not best or t.at < timers[best].at) then best = i end
            end
            if not best then break end
            local t = table.remove(timers, best)
            now = t.at
            t.fn()
        end
        now = target
    end

    -- ---- configurable API state (mutate from tests) ----
    self.api = {
        isSoloShuffle          = false,
        isRatedSoloRBG         = false,
        matchState             = nil,
        units                  = {},   -- token -> { guid, name, exists }
        arenaSpecs             = {},   -- index -> specID (GetArenaOpponentSpec)
        numArenaOpponentSpecs  = 0,
        inspectSpecs           = {},   -- token -> specID
        playerSpecID           = 250,
        scoreboard             = {},   -- array of C_PvP.GetScoreInfo-shaped tables
        teamInfo               = {},   -- faction -> mmr
        arenaFaction           = 0,
        instanceType           = "arena",
        currentArenaSeason     = 39,
        isActiveBattlefieldArena = false,
        numArenaOpponents      = 0,
        cleu                   = nil,  -- payload for CombatLogGetCurrentEventInfo
        victoryStatID          = 1012, -- C_PvP.GetCustomVictoryStatID (live SS value)
    }
    local api = self.api

    -- ---- frames + event dispatch ----
    local frames = {}
    local NOOP = function() end
    local frameMT = { __index = function() return NOOP end }
    local function NewFrame()
        local f = { __events = {}, __scripts = {} }
        f.RegisterEvent   = function(fr, e) fr.__events[e] = true end
        f.UnregisterEvent = function(fr, e) fr.__events[e] = nil end
        f.SetScript       = function(fr, k, fn) fr.__scripts[k] = fn end
        f.GetScript       = function(fr, k) return fr.__scripts[k] end
        f.CreateFontString = function() return NewFrame() end
        f.CreateTexture    = function() return NewFrame() end
        setmetatable(f, frameMT)
        frames[#frames + 1] = f
        return f
    end

    function self.fire(event, ...)
        for _, f in ipairs(frames) do
            if f.__events[event] and f.__scripts.OnEvent then
                f.__scripts.OnEvent(f, event, ...)
            end
        end
    end

    function self.cleu(...)
        api.cleu = { ... }
        self.fire("COMBAT_LOG_EVENT_UNFILTERED")
    end

    -- ---- stubbed WoW globals ----
    env.CreateFrame  = function() return NewFrame() end
    env.UIParent     = NewFrame()
    env.GameTooltip  = NewFrame()
    env.GetTime      = function() return now end
    env.time         = function() return math.floor(now) end
    env.date         = os.date
    env.C_Timer      = { After = function(d, fn) timers[#timers + 1] = { at = now + d, fn = fn } end }
    env.issecretvalue = function(v) return getmetatable(v) == SECRET_MT end

    env.C_PvP = {
        IsSoloShuffle       = function() return api.isSoloShuffle end,
        IsRatedSoloRBG      = function() return api.isRatedSoloRBG end,
        GetActiveMatchState = function() return api.matchState end,
        GetScoreInfo        = function(i) return api.scoreboard[i] end,
        GetCustomVictoryStatID = function() return api.victoryStatID end,
        GetScoreInfoByPlayerGuid = function(guid)
            local p = api.units.player
            if api.selfScore and p and guid == p.guid then return api.selfScore end
            for _, row in ipairs(api.scoreboard) do
                if row.guid == guid then return row end
            end
            return nil
        end,
    }

    env.UnitExists   = function(tok) local u = api.units[tok]; return (u and u.exists ~= false) or false end
    env.UnitGUID     = function(tok) local u = api.units[tok]; return u and u.guid end
    env.UnitName     = function(tok) local u = api.units[tok]; return u and u.name end
    env.UnitClass    = function(tok)
        local u = api.units[tok]
        return u and u.className, u and u.classToken
    end
    env.UnitFullName = function(tok)
        local u = api.units[tok]
        if not u then return nil end
        return u.name, u.realm or "TestRealm"
    end
    env.GetRealmName = function() return "TestRealm" end

    env.GetSpecialization        = function() return 1 end
    env.GetSpecializationInfo    = function() return api.playerSpecID, "TestSpec" end
    env.GetInspectSpecialization = function(tok) return api.inspectSpecs[tok] or 0 end

    env.GetArenaOpponentSpec      = function(i) return api.arenaSpecs[i] or 0 end
    env.GetNumArenaOpponentSpecs  = function() return api.numArenaOpponentSpecs end
    env.GetNumArenaOpponents      = function() return api.numArenaOpponents end
    env.IsActiveBattlefieldArena  = function() return api.isActiveBattlefieldArena end

    env.RequestBattlefieldScoreData = NOOP
    env.GetNumBattlefieldScores     = function() return #api.scoreboard end
    env.GetBattlefieldScore         = function(i)
        local s = api.scoreboard[i]
        if not s then return nil end
        return s.name, s.killingBlows, nil, nil, nil, s.faction, nil, nil,
            s.classToken, s.damageDone, s.healingDone
    end
    env.GetBattlefieldTeamInfo    = function(fac) return nil, nil, nil, api.teamInfo[fac] end
    env.GetBattlefieldArenaFaction = function() return api.arenaFaction end
    env.GetMaxBattlefieldID       = function() return 1 end
    env.GetBattlefieldStatus      = function() return "none" end
    env.GetBattlefieldTimeWaited  = function() return 0 end

    env.GetInstanceInfo = function() return "TestArena", api.instanceType, nil, "TestArena" end
    env.IsInInstance    = function() return api.instanceType ~= "none", api.instanceType end
    env.GetCurrentArenaSeason = function() return api.currentArenaSeason end
    env.GetBuildInfo    = function() return "12.0.7", "99999", "test", 120007 end

    env.CombatLogGetCurrentEventInfo = function()
        local c = api.cleu or {}
        return c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10],
            c[11], c[12], c[13], c[14], c[15]
    end

    -- Class/spec enumeration: two classes x two specs, enough for ResolveSpecID
    local CLASSES = {
        { token = "WARRIOR", id = 1, specs = { { 71, "Arms" }, { 72, "Fury" } } },
        { token = "MAGE",    id = 8, specs = { { 62, "Arcane" }, { 63, "Fire" } } },
    }
    env.GetNumClasses = function() return #CLASSES end
    env.GetClassInfo  = function(i)
        local c = CLASSES[i]
        if not c then return nil end
        return c.token, c.token, c.id
    end
    env.C_SpecializationInfo = {
        GetNumSpecializationsForClassID = function(classID)
            for _, c in ipairs(CLASSES) do
                if c.id == classID then return #c.specs end
            end
            return 0
        end,
    }
    env.GetNumSpecializationsForClassID = env.C_SpecializationInfo.GetNumSpecializationsForClassID
    env.GetSpecializationInfoForClassID = function(classID, si)
        for _, c in ipairs(CLASSES) do
            if c.id == classID and c.specs[si] then
                return c.specs[si][1], c.specs[si][2], nil, 134400
            end
        end
        return nil
    end

    env.print   = NOOP  -- override from a test to capture output
    env.unpack  = table.unpack
    env.wipe    = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.tinsert = table.insert
    env.format  = string.format
    env.SlashCmdList = {}
    setmetatable(env, { __index = _G })

    -- ---- minimal AI surface Insights.lua consumes from Core/Challenges ----
    local AI = {}
    self.AI = AI
    AI.BRACKET_2V2          = 1
    AI.BRACKET_3V3          = 2
    AI.BRACKET_BLITZ        = 4
    AI.BRACKET_SOLO_SHUFFLE = 7
    AI.TRACKED_BRACKETS     = { 1, 2, 4, 7 }
    AI.PER_SPEC_BRACKETS    = { [4] = true, [7] = true }
    AI.BRACKET_NAMES        = { [1] = "2v2", [2] = "3v3", [4] = "Blitz", [7] = "Solo Shuffle" }
    AI.currentCharKey       = "Tester-TestRealm"
    AI.DebugInsights        = NOOP
    function AI.TableCount(t)
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end

    env.ArenaInsightsDB = {
        settings   = {},
        matches    = {},
        challenges = {},
        characters = {
            ["Tester-TestRealm"] = {
                specID = 250,
                specBrackets = { [250] = { [7] = { rating = 1800 } } },
                brackets = { [1] = { rating = 1500 }, [2] = { rating = 1600 } },
            },
        },
    }

    -- Write a rating into the fake DB the way Core.lua would on
    -- PVP_RATED_STATS_UPDATE (per-spec for SS/Blitz, flat otherwise).
    function self.setDBRating(bracket, rating)
        local char = env.ArenaInsightsDB.characters[AI.currentCharKey]
        if AI.PER_SPEC_BRACKETS[bracket] then
            char.specBrackets[char.specID] = char.specBrackets[char.specID] or {}
            char.specBrackets[char.specID][bracket] = { rating = rating }
        else
            char.brackets[bracket] = { rating = rating }
        end
    end

    -- Load an addon file unmodified, passing the WoW vararg contract.
    function self.load(path)
        local chunk, err = loadfile(path, "t", env)
        assert(chunk, err)
        chunk("ArenaInsights", AI)
    end

    return self
end

return M
