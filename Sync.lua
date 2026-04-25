local addonName, NXR = ...

-- ============================================================================
-- Party Sync
-- ============================================================================

local SYNC_PREFIX       = "NXR_SYNC"
local CHUNK_SIZE        = 200
local RESPONSE_TIMEOUT  = 5
local BUFFER_TIMEOUT    = 30

-- Session state (reset on each NXR.InitiateSync call)
local syncInProgress          = false
local sessionRespondedSenders = {}

-- Inbound reassembly buffers
-- key: sessionID .. "::" .. sender
-- value: { chunks={[idx]=data}, total=N, startedAt=time() }
local inboundBuffers = {}

-- ============================================================================
-- Helpers
-- ============================================================================

local function GetMyName()
    if NXR.currentCharKey then
        return NXR.currentCharKey:match("^(.-)%-") or NXR.currentCharKey
    end
    return UnitName("player") or ""
end

local function IsSelf(sender)
    local senderName = sender:match("^(.-)%-") or sender
    return senderName == GetMyName()
end

local function CleanOldBuffers()
    local now = time()
    for key, buf in pairs(inboundBuffers) do
        if (now - (buf.startedAt or 0)) > BUFFER_TIMEOUT then
            inboundBuffers[key] = nil
        end
    end
end

-- ============================================================================
-- Chunking / send
-- ============================================================================

local function SendChunks(sessionID)
    if not NXR.SerializeCharactersForSync then return end
    local payload = NXR.SerializeCharactersForSync()
    local chunks  = {}
    local pos     = 1
    while pos <= #payload do
        table.insert(chunks, payload:sub(pos, pos + CHUNK_SIZE - 1))
        pos = pos + CHUNK_SIZE
    end

    local total = #chunks
    for i, data in ipairs(chunks) do
        local msg = "CHUNK:" .. sessionID .. ":" .. i .. "/" .. total .. ":" .. data
        C_ChatInfo.SendAddonMessage(SYNC_PREFIX, msg, "PARTY")
    end
end

-- ============================================================================
-- Receive / reassembly
-- ============================================================================

local statusTimer = nil

local function HandleCompletePayload(sender, payload)
    if not NXR.ParseCharactersForSync or not NXR.MergeCharacters then return end

    local characters = NXR.ParseCharactersForSync(payload)
    if not characters then
        NXR.Debug("Sync: failed to parse payload from", sender)
        return
    end

    NXR.MergeCharacters(characters)

    NelxRatedDB.syncPartners = NelxRatedDB.syncPartners or {}
    NelxRatedDB.syncPartners[sender] = time()

    if syncInProgress then
        sessionRespondedSenders[sender] = true
    end

    if NXR.RefreshOverlay then NXR.RefreshOverlay() end

    NXR.Debug("Sync: merged data from", sender)

    -- Responder path: we received an initiation from someone else, send our data back
    if not syncInProgress then
        local replyID = tostring(time()) .. "-" .. tostring(math.random(10000, 99999))
        SendChunks(replyID)
    end
end

local function HandleChunk(sender, msg)
    -- Format: CHUNK:<sessionID>:<chunkIndex>/<totalChunks>:<data>
    local sessionID, idxStr, totalStr, data =
        msg:match("^CHUNK:([^:]+):(%d+)/(%d+):(.*)$")
    if not sessionID then return end

    local idx   = tonumber(idxStr)
    local total = tonumber(totalStr)
    if not idx or not total or idx < 1 or idx > total then return end

    local bufKey = sessionID .. "::" .. sender
    if not inboundBuffers[bufKey] then
        inboundBuffers[bufKey] = { chunks = {}, total = total, startedAt = time() }
    end

    local buf = inboundBuffers[bufKey]
    buf.chunks[idx] = data

    -- Count received chunks
    local count = 0
    for _ in pairs(buf.chunks) do count = count + 1 end

    if count == total then
        -- Reassemble in order; abort if any chunk is missing
        local parts = {}
        for i = 1, total do
            if not buf.chunks[i] then return end
            parts[i] = buf.chunks[i]
        end
        inboundBuffers[bufKey] = nil
        HandleCompletePayload(sender, table.concat(parts))
    end
end

-- ============================================================================
-- Status timer
-- ============================================================================

local function StartStatusTimer()
    if statusTimer then return end
    statusTimer = C_Timer.After(RESPONSE_TIMEOUT, function()
        statusTimer = nil
        syncInProgress = false
        local n = 0
        for _ in pairs(sessionRespondedSenders) do n = n + 1 end
        if n > 0 then
            NXR.UpdateSyncStatusUI("Synced with " .. n .. " partner(s)", false)
        else
            NXR.UpdateSyncStatusUI("No response from party members.", false)
        end
    end)
end

-- ============================================================================
-- Event frame
-- ============================================================================

local syncFrame = CreateFrame("Frame")

syncFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        C_ChatInfo.RegisterAddonMessagePrefix(SYNC_PREFIX)

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if prefix ~= SYNC_PREFIX then return end
        if IsSelf(sender) then return end
        CleanOldBuffers()
        if msg:sub(1, 6) == "CHUNK:" then
            HandleChunk(sender, msg)
        end
    end
end)

syncFrame:RegisterEvent("PLAYER_LOGIN")
syncFrame:RegisterEvent("CHAT_MSG_ADDON")

-- ============================================================================
-- Public API
-- ============================================================================

function NXR.InitiateSync()
    if GetNumGroupMembers() == 0 then
        NXR.UpdateSyncStatusUI("Not in a party.", true)
        return
    end

    sessionRespondedSenders = {}
    syncInProgress = true
    NXR.UpdateSyncStatusUI("Syncing\226\128\166", false)

    local sessionID = tostring(time()) .. "-" .. tostring(math.random(10000, 99999))
    SendChunks(sessionID)
    StartStatusTimer()
end

function NXR.SyncSelfTest()
    if not NXR.SerializeCharactersForSync or not NXR.ParseCharactersForSync or not NXR.MergeCharacters then
        print("|cffE6D200NelxRated|r sync selftest: helpers not available")
        return
    end

    local payload   = NXR.SerializeCharactersForSync()
    local charCount = 0
    for _ in pairs(NelxRatedDB.characters or {}) do charCount = charCount + 1 end

    -- Simulate chunking
    local chunks = {}
    local pos = 1
    while pos <= #payload do
        table.insert(chunks, payload:sub(pos, pos + CHUNK_SIZE - 1))
        pos = pos + CHUNK_SIZE
    end

    -- Reassemble
    local reassembled = table.concat(chunks)
    if reassembled ~= payload then
        print("|cffE6D200NelxRated|r sync selftest: FAIL — chunk reassembly mismatch")
        return
    end

    -- Parse
    local characters = NXR.ParseCharactersForSync(reassembled)
    if not characters then
        print("|cffE6D200NelxRated|r sync selftest: FAIL — parse returned nil")
        return
    end

    local parsedCount = 0
    for _ in pairs(characters) do parsedCount = parsedCount + 1 end

    -- Merge (no-op since data is identical — updatedAt timestamps won't advance)
    local added, updated, skipped = NXR.MergeCharacters(characters)

    print(string.format(
        "|cffE6D200NelxRated|r sync selftest: OK — %d chars serialized, %d chunks, %d parsed, merge: +%d ~%d skip%d",
        charCount, #chunks, parsedCount, added, updated, skipped
    ))
end

function NXR.GetSyncStatus()
    if syncInProgress then return "syncing" end
    local n = 0
    for _ in pairs(sessionRespondedSenders) do n = n + 1 end
    if n > 0 then return "synced", n end
    return "idle"
end

function NXR.UpdateSyncStatusUI(text, isError)
    if not NXR._syncStatusText then return end
    NXR._syncStatusText:SetText(text or "")
    if isError then
        NXR._syncStatusText:SetTextColor(unpack(NXR.COLORS.CRIMSON_BRIGHT))
    else
        NXR._syncStatusText:SetTextColor(0.78, 0.75, 0.73)
    end
end
