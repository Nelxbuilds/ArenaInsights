local addonName, NXR = ...

-- ============================================================================
-- Spec & class metadata (built at ADDON_LOADED)
-- ============================================================================

NXR.classData      = {}   -- classID -> { classID, className, classFileName, specs }
NXR.specData       = {}   -- specID  -> { specID, specName, icon, role, classID, className, classFileName }
NXR.roleSpecs      = {}   -- role    -> sorted array of spec entries
NXR.sortedClassIDs = {}   -- ordered array of classIDs

function NXR.BuildSpecData()
    wipe(NXR.classData)
    wipe(NXR.specData)
    wipe(NXR.roleSpecs)
    wipe(NXR.sortedClassIDs)

    NXR.roleSpecs.HEALER  = {}
    NXR.roleSpecs.DAMAGER = {}
    NXR.roleSpecs.TANK    = {}

    for i = 1, GetNumClasses() do
        local className, classFileName, classID = GetClassInfo(i)
        if classID then
            table.insert(NXR.sortedClassIDs, classID)
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
                    NXR.specData[specID] = s
                    if NXR.roleSpecs[role] then
                        table.insert(NXR.roleSpecs[role], s)
                    end
                end
            end

            NXR.classData[classID] = entry
        end
    end

    -- Sort each role group by class name then spec name
    for _, role in ipairs({"HEALER", "DAMAGER", "TANK"}) do
        table.sort(NXR.roleSpecs[role], function(a, b)
            if a.className == b.className then
                return a.specName < b.specName
            end
            return a.className < b.className
        end)
    end

    NXR.Debug("BuildSpecData:", NXR.TableCount(NXR.specData), "specs across",
        #NXR.sortedClassIDs, "classes |",
        #NXR.roleSpecs.HEALER, "healers,",
        #NXR.roleSpecs.DAMAGER, "dps,",
        #NXR.roleSpecs.TANK, "tanks")
end

-- ============================================================================
-- Challenge CRUD (Story 2-1)
-- ============================================================================

local function NextID()
    local max = 0
    for _, c in ipairs(NelxRatedDB.challenges) do
        if c.id > max then max = c.id end
    end
    return max + 1
end

local function GenerateUID()
    return time() .. "-" .. math.random(100000, 999999)
end

function NXR.AddChallenge(data)
    local isFirst = #NelxRatedDB.challenges == 0
    local c = {
        id         = NextID(),
        uid        = data.uid or GenerateUID(),
        name       = data.name or "Untitled",
        goalRating = data.goalRating or 1800,
        brackets   = data.brackets or {},
        specs      = data.specs or {},
        classes    = data.classes or {},
        active     = isFirst,
    }
    table.insert(NelxRatedDB.challenges, c)
    NXR.Debug("AddChallenge: id=" .. c.id, "'" .. c.name .. "'",
        "goal=" .. c.goalRating,
        "brackets=" .. NXR.TableCount(c.brackets),
        "specs=" .. NXR.TableCount(c.specs),
        "active=" .. tostring(c.active))
    if isFirst and NXR.RefreshOverlay then
        NXR.RefreshOverlay()
    end
    return c
end

function NXR.RemoveChallenge(id)
    local wasActive = false
    for i, c in ipairs(NelxRatedDB.challenges) do
        if c.id == id then
            wasActive = c.active
            table.remove(NelxRatedDB.challenges, i)
            break
        end
    end
    if wasActive and NXR.RefreshOverlay then
        NXR.RefreshOverlay()
    end
end

function NXR.UpdateChallenge(id, data)
    for _, c in ipairs(NelxRatedDB.challenges) do
        if c.id == id then
            if data.name ~= nil then c.name = data.name end
            if data.goalRating ~= nil then c.goalRating = data.goalRating end
            if data.brackets then c.brackets = data.brackets end
            if data.specs then c.specs = data.specs end
            if data.classes then c.classes = data.classes end
            if c.active and NXR.RefreshOverlay then
                NXR.RefreshOverlay()
            end
            return c
        end
    end
end

function NXR.SetActiveChallenge(id)
    NXR.Debug("SetActiveChallenge: id=" .. tostring(id))
    for _, c in ipairs(NelxRatedDB.challenges) do
        c.active = (c.id == id)
    end
    if NXR.RefreshOverlay then
        NXR.RefreshOverlay()
    end
end

function NXR.GetActiveChallenge()
    for _, c in ipairs(NelxRatedDB.challenges) do
        if c.active then return c end
    end
    return nil
end

-- ============================================================================
-- Initialization (called from Core.lua ADDON_LOADED)
-- ============================================================================

function NXR.InitChallenges()
    local challenges = NelxRatedDB.challenges

    -- Backfill UIDs for pre-9-6 challenges
    for _, c in ipairs(challenges) do
        if not c.uid then
            c.uid = GenerateUID()
            NXR.Debug("InitChallenges: backfilled uid for '" .. c.name .. "': " .. c.uid)
        end
    end

    if #challenges > 0 and not NXR.GetActiveChallenge() then
        challenges[1].active = true
        NXR.Debug("InitChallenges: auto-activated '" .. challenges[1].name .. "'")
    end
    NXR.Debug("InitChallenges:", #challenges, "challenges loaded")
end
