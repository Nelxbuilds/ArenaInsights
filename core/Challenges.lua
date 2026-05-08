local addonName, AI = ...

-- ============================================================================
-- Spec & class metadata (built at ADDON_LOADED)
-- ============================================================================

AI.classData      = {}   -- classID -> { classID, className, classFileName, specs }
AI.specData       = {}   -- specID  -> { specID, specName, icon, role, classID, className, classFileName }
AI.roleSpecs      = {}   -- role    -> sorted array of spec entries
AI.sortedClassIDs = {}   -- ordered array of classIDs

-- Ranged DPS specIDs (WoW 12.x) — all other DAMAGER specs are melee
local RANGED_SPEC_IDS = {
    [102]  = true,  -- Balance Druid
    [253]  = true,  -- Beast Mastery Hunter
    [254]  = true,  -- Marksmanship Hunter
    [62]   = true,  -- Arcane Mage
    [63]   = true,  -- Fire Mage
    [64]   = true,  -- Frost Mage
    [258]  = true,  -- Shadow Priest
    [262]  = true,  -- Elemental Shaman
    [265]  = true,  -- Affliction Warlock
    [266]  = true,  -- Demonology Warlock
    [267]  = true,  -- Destruction Warlock
    [1467] = true,  -- Devastation Evoker
    [1473] = true,  -- Augmentation Evoker
}

function AI.BuildSpecData()
    wipe(AI.classData)
    wipe(AI.specData)
    wipe(AI.roleSpecs)
    wipe(AI.sortedClassIDs)

    AI.roleSpecs.HEALER  = {}
    AI.roleSpecs.DAMAGER = {}
    AI.roleSpecs.MELEE   = {}
    AI.roleSpecs.RANGED  = {}
    AI.roleSpecs.TANK    = {}

    for i = 1, GetNumClasses() do
        local className, classFileName, classID = GetClassInfo(i)
        if classID then
            table.insert(AI.sortedClassIDs, classID)
            local entry = {
                classID       = classID,
                className     = className,
                classFileName = classFileName,
                specs         = {},
            }

            for j = 1, GetNumSpecializationsForClassID(classID) do
                local specID, specName, _, icon, role =
                    GetSpecializationInfoForClassID(classID, j)
                if specID then
                    local s = {
                        specID        = specID,
                        specName      = specName,
                        icon          = icon,
                        role          = role,
                        classID       = classID,
                        className     = className,
                        classFileName = classFileName,
                    }
                    table.insert(entry.specs, s)
                    AI.specData[specID] = s
                    if role == "DAMAGER" then
                        table.insert(AI.roleSpecs.DAMAGER, s)
                        if RANGED_SPEC_IDS[specID] then
                            table.insert(AI.roleSpecs.RANGED, s)
                        else
                            table.insert(AI.roleSpecs.MELEE, s)
                        end
                    elseif AI.roleSpecs[role] then
                        table.insert(AI.roleSpecs[role], s)
                    end
                end
            end

            AI.classData[classID] = entry
        end
    end

    -- Sort each role group by class name then spec name
    local sortFn = function(a, b)
        if a.className == b.className then
            return a.specName < b.specName
        end
        return a.className < b.className
    end
    for _, role in ipairs({"HEALER", "DAMAGER", "MELEE", "RANGED", "TANK"}) do
        table.sort(AI.roleSpecs[role], sortFn)
    end

    AI.Debug("BuildSpecData:", AI.TableCount(AI.specData), "specs across",
        #AI.sortedClassIDs, "classes |",
        #AI.roleSpecs.HEALER, "healers,",
        #AI.roleSpecs.MELEE, "melee,",
        #AI.roleSpecs.RANGED, "ranged,",
        #AI.roleSpecs.TANK, "tanks")
end

-- ============================================================================
-- Challenge CRUD (Story 2-1)
-- ============================================================================

local function NextID()
    local max = 0
    for _, c in ipairs(ArenaInsightsDB.challenges) do
        if c.id > max then max = c.id end
    end
    return max + 1
end

local function GenerateUID()
    return time() .. "-" .. math.random(100000, 999999)
end

function AI.AddChallenge(data)
    local isFirst = #ArenaInsightsDB.challenges == 0
    local c = {
        id         = NextID(),
        uid        = data.uid or GenerateUID(),
        name       = data.name or "Untitled",
        goalRating = data.goalRating or 1800,
        brackets   = data.brackets or {},
        specs      = data.specs or {},
        classes    = data.classes or {},
    }
    if data.active ~= nil then
        c.active = data.active
    else
        c.active = isFirst
    end
    table.insert(ArenaInsightsDB.challenges, c)
    AI.Debug("AddChallenge: id=" .. c.id, "'" .. c.name .. "'",
        "goal=" .. c.goalRating,
        "brackets=" .. AI.TableCount(c.brackets),
        "specs=" .. AI.TableCount(c.specs),
        "active=" .. tostring(c.active))
    if isFirst and AI.RefreshOverlay then
        AI.RefreshOverlay()
    end
    return c
end

function AI.RemoveChallenge(id)
    local wasActive = false
    for i, c in ipairs(ArenaInsightsDB.challenges) do
        if c.id == id then
            wasActive = c.active
            if c.uid then
                ArenaInsightsDB.deletedChallengeUIDs = ArenaInsightsDB.deletedChallengeUIDs or {}
                ArenaInsightsDB.deletedChallengeUIDs[c.uid] = true
            end
            table.remove(ArenaInsightsDB.challenges, i)
            break
        end
    end
    if wasActive and AI.RefreshOverlay then
        AI.RefreshOverlay()
    end
end

function AI.UpdateChallenge(id, data)
    for _, c in ipairs(ArenaInsightsDB.challenges) do
        if c.id == id then
            if data.name ~= nil then c.name = data.name end
            if data.goalRating ~= nil then c.goalRating = data.goalRating end
            if data.brackets then c.brackets = data.brackets end
            if data.specs then c.specs = data.specs end
            if data.classes then c.classes = data.classes end
            if c.active and AI.RefreshOverlay then
                AI.RefreshOverlay()
            end
            return c
        end
    end
end

function AI.SetActiveChallenge(id)
    AI.Debug("SetActiveChallenge: id=" .. tostring(id))
    for _, c in ipairs(ArenaInsightsDB.challenges) do
        c.active = (c.id == id)
    end
    if AI.RefreshOverlay then
        AI.RefreshOverlay()
    end
end

function AI.GetActiveChallenge()
    for _, c in ipairs(ArenaInsightsDB.challenges) do
        if c.active then return c end
    end
    return nil
end

-- ============================================================================
-- Manual spec/class completion (Story: Manual Spec Completion)
-- ============================================================================

function AI.SetSpecCompleted(challengeID, specID, completed)
    for _, c in ipairs(ArenaInsightsDB.challenges) do
        if c.id == challengeID then
            c.completedSpecs = c.completedSpecs or {}
            c.completedSpecs[specID] = completed and true or nil
            return
        end
    end
end

function AI.IsSpecCompleted(challengeID, specID)
    for _, c in ipairs(ArenaInsightsDB.challenges) do
        if c.id == challengeID then
            return c.completedSpecs and c.completedSpecs[specID] == true
        end
    end
    return false
end

function AI.SetClassCompleted(challengeID, classID, completed)
    for _, c in ipairs(ArenaInsightsDB.challenges) do
        if c.id == challengeID then
            c.completedClasses = c.completedClasses or {}
            c.completedClasses[classID] = completed and true or nil
            return
        end
    end
end

function AI.IsClassCompleted(challengeID, classID)
    for _, c in ipairs(ArenaInsightsDB.challenges) do
        if c.id == challengeID then
            return c.completedClasses and c.completedClasses[classID] == true
        end
    end
    return false
end

-- ============================================================================
-- Initialization (called from Core.lua ADDON_LOADED)
-- ============================================================================

function AI.InitChallenges()
    local challenges = ArenaInsightsDB.challenges

    -- Backfill UIDs for pre-9-6 challenges
    for _, c in ipairs(challenges) do
        if not c.uid then
            c.uid = GenerateUID()
            AI.Debug("InitChallenges: backfilled uid for '" .. c.name .. "': " .. c.uid)
        end
    end

    if #challenges > 0 and not AI.GetActiveChallenge() then
        challenges[1].active = true
        AI.Debug("InitChallenges: auto-activated '" .. challenges[1].name .. "'")
    end
    AI.Debug("InitChallenges:", #challenges, "challenges loaded")
end
