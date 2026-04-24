local addonName, NXR = ...

-- ============================================================================
-- Import/Export Tab (Story 3-4)
-- ============================================================================

local HEADER_V1 = "NelxRated-Export-v1"
local HEADER_V2 = "NelxRated-Export-v2"
local panel

-- ============================================================================
-- Character serialization
-- ============================================================================

local function SerializeCharacterLines(lines)
    table.insert(lines, "[BEGIN_CHARS]")
    for key, char in pairs(NelxRatedDB.characters) do
        table.insert(lines, "[BEGIN_CHAR]")
        table.insert(lines, "key=" .. key)
        table.insert(lines, "name=" .. (char.name or ""))
        table.insert(lines, "realm=" .. (char.realm or ""))
        table.insert(lines, "account=" .. (char.account or ""))
        table.insert(lines, "classFileName=" .. (char.classFileName or ""))
        table.insert(lines, "classDisplayName=" .. (char.classDisplayName or ""))
        table.insert(lines, "specID=" .. tostring(char.specID or ""))
        table.insert(lines, "specName=" .. (char.specName or ""))

        if char.brackets then
            for bi, data in pairs(char.brackets) do
                table.insert(lines, "bracket_" .. bi .. "_rating=" .. (data.rating or 0))
                table.insert(lines, "bracket_" .. bi .. "_mmr=" .. (data.mmr or 0))
            end
        end

        if char.specBrackets then
            for specID, brackets in pairs(char.specBrackets) do
                for bi, data in pairs(brackets) do
                    table.insert(lines, "specbracket_" .. specID .. "_" .. bi .. "_rating=" .. (data.rating or 0))
                    table.insert(lines, "specbracket_" .. specID .. "_" .. bi .. "_mmr=" .. (data.mmr or 0))
                end
            end
        end

        table.insert(lines, "[END_CHAR]")
    end
    table.insert(lines, "[END_CHARS]")
end

-- ============================================================================
-- Challenge serialization
-- ============================================================================

local function SerializeHashKeys(tbl)
    local keys = {}
    for k in pairs(tbl) do
        table.insert(keys, tostring(k))
    end
    return table.concat(keys, ",")
end

local function SerializeChallengeLines(lines)
    table.insert(lines, "[BEGIN_CHALLENGES]")
    for _, c in ipairs(NelxRatedDB.challenges) do
        table.insert(lines, "[BEGIN_CHALLENGE]")
        table.insert(lines, "uid=" .. (c.uid or ""))
        table.insert(lines, "name=" .. (c.name or ""))
        table.insert(lines, "goalRating=" .. (c.goalRating or 0))
        table.insert(lines, "active=" .. tostring(c.active or false))
        table.insert(lines, "specs=" .. SerializeHashKeys(c.specs or {}))
        table.insert(lines, "classes=" .. SerializeHashKeys(c.classes or {}))
        table.insert(lines, "brackets=" .. SerializeHashKeys(c.brackets or {}))
        table.insert(lines, "[END_CHALLENGE]")
    end
    table.insert(lines, "[END_CHALLENGES]")
end

-- ============================================================================
-- Settings serialization
-- ============================================================================

local function SerializeSettingsLines(lines)
    table.insert(lines, "[BEGIN_SETTINGS]")
    for k, v in pairs(NelxRatedDB.settings) do
        table.insert(lines, k .. "=" .. tostring(v))
    end
    table.insert(lines, "[END_SETTINGS]")
end

-- ============================================================================
-- Full export (v2)
-- ============================================================================

local function SerializeAll()
    local lines = { HEADER_V2 }
    SerializeCharacterLines(lines)
    SerializeChallengeLines(lines)
    SerializeSettingsLines(lines)
    return table.concat(lines, "\n")
end

-- ============================================================================
-- Import parsing
-- ============================================================================

local function ParseLines(text)
    local lines = {}
    for line in text:gmatch("[^\n]+") do
        table.insert(lines, line:match("^%s*(.-)%s*$"))
    end
    return lines
end

local function ParseCharacterBlock(lines, startIdx)
    local current = { brackets = {}, specBrackets = {} }
    for i = startIdx, #lines do
        local line = lines[i]
        if line == "[END_CHAR]" then
            return current, i
        end
        local k, v = line:match("^(.-)=(.*)$")
        if k and v then
            local specID, bi, field = k:match("^specbracket_(%d+)_(%d+)_(%a+)$")
            if specID and bi and field then
                specID = tonumber(specID)
                bi = tonumber(bi)
                current.specBrackets[specID] = current.specBrackets[specID] or {}
                current.specBrackets[specID][bi] = current.specBrackets[specID][bi] or {}
                current.specBrackets[specID][bi][field] = tonumber(v) or 0
                current.specBrackets[specID][bi].updatedAt = current.specBrackets[specID][bi].updatedAt or time()
            else
                local bracketIdx, bracketField = k:match("^bracket_(%d+)_(%a+)$")
                if bracketIdx and bracketField then
                    bracketIdx = tonumber(bracketIdx)
                    current.brackets[bracketIdx] = current.brackets[bracketIdx] or {}
                    current.brackets[bracketIdx][bracketField] = tonumber(v) or 0
                    current.brackets[bracketIdx].updatedAt = current.brackets[bracketIdx].updatedAt or time()
                elseif k == "specID" then
                    current[k] = tonumber(v)
                elseif k == "key" then
                    current.key = v
                else
                    current[k] = v
                end
            end
        end
    end
    return current, #lines
end

local function DeserializeHashKeys(str)
    local tbl = {}
    if str and str ~= "" then
        for val in str:gmatch("[^,]+") do
            local num = tonumber(val)
            if num then tbl[num] = true end
        end
    end
    return tbl
end

local function ParseChallengeBlock(lines, startIdx)
    local c = {}
    for i = startIdx, #lines do
        local line = lines[i]
        if line == "[END_CHALLENGE]" then
            return c, i
        end
        local k, v = line:match("^(.-)=(.*)$")
        if k and v then
            if k == "goalRating" then
                c.goalRating = tonumber(v) or 0
            elseif k == "active" then
                c.active = (v == "true")
            elseif k == "specs" then
                c.specs = DeserializeHashKeys(v)
            elseif k == "classes" then
                c.classes = DeserializeHashKeys(v)
            elseif k == "brackets" then
                c.brackets = DeserializeHashKeys(v)
            else
                c[k] = v
            end
        end
    end
    return c, #lines
end

local function ParseSettingsBlock(lines, startIdx)
    local settings = {}
    for i = startIdx, #lines do
        local line = lines[i]
        if line == "[END_SETTINGS]" then
            return settings, i
        end
        local k, v = line:match("^(.-)=(.*)$")
        if k and v then
            -- Coerce types
            if v == "true" then
                settings[k] = true
            elseif v == "false" then
                settings[k] = false
            elseif tonumber(v) then
                settings[k] = tonumber(v)
            else
                settings[k] = v
            end
        end
    end
    return settings, #lines
end

local function DeserializeV1(lines)
    local chars = {}
    local i = 2
    while i <= #lines do
        if lines[i] == "[BEGIN_CHAR]" then
            local char, endIdx = ParseCharacterBlock(lines, i + 1)
            if char and char.key then
                chars[char.key] = char
                char.key = nil
            end
            i = endIdx + 1
        else
            i = i + 1
        end
    end
    return { characters = chars }
end

local function DeserializeV2(lines)
    local result = { characters = {}, challenges = {}, settings = nil }
    local i = 2
    while i <= #lines do
        local line = lines[i]
        if line == "[BEGIN_CHAR]" then
            local char, endIdx = ParseCharacterBlock(lines, i + 1)
            if char and char.key then
                result.characters[char.key] = char
                char.key = nil
            end
            i = endIdx + 1
        elseif line == "[BEGIN_CHALLENGE]" then
            local c, endIdx = ParseChallengeBlock(lines, i + 1)
            table.insert(result.challenges, c)
            i = endIdx + 1
        elseif line == "[BEGIN_SETTINGS]" then
            local s, endIdx = ParseSettingsBlock(lines, i + 1)
            result.settings = s
            i = endIdx + 1
        else
            i = i + 1
        end
    end
    return result
end

local function DeserializeAll(text)
    local lines = ParseLines(text)
    if #lines == 0 then
        return nil, "Empty import data"
    end

    local header = lines[1]
    if header == HEADER_V2 then
        return DeserializeV2(lines)
    elseif header == HEADER_V1 then
        return DeserializeV1(lines)
    else
        return nil, "Invalid format: unrecognized header '" .. tostring(header) .. "'"
    end
end

-- ============================================================================
-- Merge logic
-- ============================================================================

local function ValidateCharacter(key, char)
    if type(key) ~= "string" or not key:find("-.+") then return false end
    if type(char) ~= "table" then return false end
    if char.name and type(char.name) ~= "string" then return false end
    if char.realm and type(char.realm) ~= "string" then return false end
    if char.brackets and type(char.brackets) ~= "table" then return false end
    if char.specBrackets and type(char.specBrackets) ~= "table" then return false end
    return true
end

local function MergeCharacters(imported)
    local added, skipped = 0, 0
    for key, char in pairs(imported) do
        if not ValidateCharacter(key, char) then
            NXR.Debug("Import: skipping invalid entry:", tostring(key))
            skipped = skipped + 1
        elseif NelxRatedDB.characters[key] then
            skipped = skipped + 1
        else
            NelxRatedDB.characters[key] = char
            added = added + 1
        end
    end
    return added, skipped
end

local function MergeChallenges(imported)
    local added, skipped = 0, 0
    local existingUIDs = {}
    for _, c in ipairs(NelxRatedDB.challenges) do
        if c.uid then existingUIDs[c.uid] = true end
    end

    for _, c in ipairs(imported) do
        if c.uid and existingUIDs[c.uid] then
            skipped = skipped + 1
        else
            -- Add as inactive to preserve single-active rule
            c.active = false
            NXR.AddChallenge({
                uid        = c.uid,
                name       = c.name,
                goalRating = c.goalRating,
                brackets   = c.brackets or {},
                specs      = c.specs or {},
                classes    = c.classes or {},
            })
            added = added + 1
        end
    end
    return added, skipped
end

local function MergeSettings(imported)
    for k, v in pairs(imported) do
        NelxRatedDB.settings[k] = v
    end
end

-- ============================================================================
-- UI
-- ============================================================================

function NXR.CreateImportExportPanel(parent)
    if panel then return panel end

    panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Import / Export")
    title:SetTextColor(unpack(NXR.COLORS.GOLD))

    -- ----------------------------------------------------------------
    -- Export section
    -- ----------------------------------------------------------------
    local exportLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    exportLabel:SetPoint("TOPLEFT", 8, -36)
    exportLabel:SetText("Export")

    local exportBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    exportBtn:SetSize(80, 24)
    exportBtn:SetPoint("LEFT", exportLabel, "RIGHT", 12, 0)
    exportBtn:SetText("Export")
    exportBtn:SetNormalFontObject("GameFontNormalSmall")

    local exportScroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate,BackdropTemplate")
    exportScroll:SetPoint("TOPLEFT", 8, -60)
    exportScroll:SetPoint("RIGHT", panel, "RIGHT", -28, 0)
    exportScroll:SetHeight(120)
    exportScroll:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    exportScroll:SetBackdropColor(0.06, 0.06, 0.06, 0.9)
    exportScroll:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.6)

    local exportBox = CreateFrame("EditBox", nil, exportScroll)
    exportBox:SetWidth(exportScroll:GetWidth() or 400)
    exportBox:SetFontObject("ChatFontSmall")
    exportBox:SetTextInsets(6, 6, 6, 6)
    exportBox:SetAutoFocus(false)
    exportBox:SetMultiLine(true)
    exportBox:EnableMouse(true)
    exportScroll:SetScrollChild(exportBox)

    -- Resize editbox width when scroll frame resizes
    exportScroll:SetScript("OnSizeChanged", function(self, w)
        exportBox:SetWidth(w)
    end)

    -- Make read-only: restore text if user types
    local exportText = ""
    exportBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(exportText)
        end
    end)
    exportBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Select all on focus
    exportBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)

    exportBtn:SetScript("OnClick", function()
        exportText = SerializeAll()
        exportBox:SetText(exportText)
        exportBox:SetFocus()
        exportBox:HighlightText()
    end)

    -- ----------------------------------------------------------------
    -- Import section
    -- ----------------------------------------------------------------
    local importLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    importLabel:SetPoint("TOPLEFT", 8, -192)
    importLabel:SetText("Import")

    local importScroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate,BackdropTemplate")
    importScroll:SetPoint("TOPLEFT", 8, -212)
    importScroll:SetPoint("RIGHT", panel, "RIGHT", -28, 0)
    importScroll:SetHeight(120)
    importScroll:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    importScroll:SetBackdropColor(0.06, 0.06, 0.06, 0.9)
    importScroll:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.6)

    local importBox = CreateFrame("EditBox", nil, importScroll)
    importBox:SetWidth(importScroll:GetWidth() or 400)
    importBox:SetFontObject("ChatFontSmall")
    importBox:SetTextInsets(6, 6, 6, 6)
    importBox:SetAutoFocus(false)
    importBox:SetMultiLine(true)
    importBox:EnableMouse(true)
    importScroll:SetScrollChild(importBox)

    importScroll:SetScript("OnSizeChanged", function(self, w)
        importBox:SetWidth(w)
    end)
    importBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("TOPLEFT", 8, -344)

    local importBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    importBtn:SetSize(80, 24)
    importBtn:SetPoint("LEFT", importLabel, "RIGHT", 12, 0)
    importBtn:SetText("Import")
    importBtn:SetNormalFontObject("GameFontNormalSmall")

    importBtn:SetScript("OnClick", function()
        local text = importBox:GetText()
        if not text or text == "" then
            statusText:SetTextColor(1, 0.3, 0.3)
            statusText:SetText("Paste export data above first.")
            return
        end

        local data, err = DeserializeAll(text)
        if not data then
            statusText:SetTextColor(1, 0.3, 0.3)
            statusText:SetText(err)
            return
        end

        local parts = {}

        -- Characters
        if data.characters then
            local added, skipped = MergeCharacters(data.characters)
            table.insert(parts, added .. " char(s) added, " .. skipped .. " skipped")
        end

        -- Challenges
        if data.challenges and #data.challenges > 0 then
            local added, skipped = MergeChallenges(data.challenges)
            table.insert(parts, added .. " challenge(s) added, " .. skipped .. " skipped")
        end

        -- Settings — apply with confirmation via StaticPopup
        if data.settings then
            StaticPopupDialogs["NELXRATED_IMPORT_SETTINGS"] = {
                text = "Import settings? This will overwrite your current settings.",
                button1 = "Yes",
                button2 = "No",
                OnAccept = function()
                    MergeSettings(data.settings)
                    NXR.Overlay.OnOpacityChanged()
                    NXR.Overlay.OnScaleChanged()
                    NXR.Overlay.OnBackgroundChanged()
                    NXR.Overlay.OnLockChanged()
                    NXR.RefreshOverlay()
                    print("|cffE6D200NelxRated|r: Settings imported.")
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            StaticPopup_Show("NELXRATED_IMPORT_SETTINGS")
        end

        statusText:SetTextColor(0.3, 1, 0.3)
        statusText:SetText("Imported: " .. table.concat(parts, " | "))

        if NXR.RefreshOverlay then NXR.RefreshOverlay() end

        importBox:SetText("")
    end)

    return panel
end
