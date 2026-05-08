local addonName, AI = ...

-- ============================================================================
-- Characters Tab (Story 3-2)
-- ============================================================================

local ROW_HEIGHT = 28
local ROW_GAP    = 2

local panel
local scrollChild
local rows = {}
local emptyLabel

local function RefreshCharacterList()
    for _, row in ipairs(rows) do row:Hide() end

    local characters = ArenaInsightsDB and ArenaInsightsDB.characters or {}

    -- Collect keys and sort
    local keys = {}
    for k in pairs(characters) do
        table.insert(keys, k)
    end
    table.sort(keys)

    if #keys == 0 then
        emptyLabel:Show()
        scrollChild:SetHeight(1)
        return
    end
    emptyLabel:Hide()

    local yOff = 0
    for i, key in ipairs(keys) do
        local char = characters[key]
        if not rows[i] then
            rows[i] = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
            rows[i]:SetHeight(ROW_HEIGHT)
            rows[i]:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })

            rows[i].nameStr = rows[i]:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            rows[i].nameStr:SetPoint("LEFT", 8, 0)

            rows[i].ratingsStr = rows[i]:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            rows[i].ratingsStr:SetPoint("LEFT", 200, 0)
            rows[i].ratingsStr:SetTextColor(0.7, 0.7, 0.7)

            rows[i].removeBtn = CreateFrame("Button", nil, rows[i], "UIPanelButtonTemplate")
            rows[i].removeBtn:SetSize(60, 20)
            rows[i].removeBtn:SetPoint("RIGHT", -6, 0)
            rows[i].removeBtn:SetText("Remove")
            rows[i].removeBtn:SetNormalFontObject("GameFontNormalSmall")
            rows[i].removeBtn:SetHighlightFontObject("GameFontHighlightSmall")
        end

        local row = rows[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -yOff)
        row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)

        -- Alternating row colors
        if i % 2 == 0 then
            row:SetBackdropColor(0.12, 0.12, 0.12, 0.5)
        else
            row:SetBackdropColor(0.08, 0.08, 0.08, 0.5)
        end
        row:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.3)

        -- Name, account, class/spec
        local label = key
        if char.account and char.account ~= "" then
            label = label .. "  |  " .. char.account
        end
        if char.classDisplayName then
            local specPart = char.specName and (char.specName .. " ") or ""
            label = label .. "  |  " .. specPart .. char.classDisplayName
        end
        row.nameStr:SetText(label)

        -- Class color for name
        if char.classFileName and RAID_CLASS_COLORS and RAID_CLASS_COLORS[char.classFileName] then
            local cc = RAID_CLASS_COLORS[char.classFileName]
            row.nameStr:SetTextColor(cc.r, cc.g, cc.b)
        else
            row.nameStr:SetTextColor(0.8, 0.8, 0.8)
        end

        -- Ratings per bracket
        local rParts = {}
        for _, bi in ipairs(AI.TRACKED_BRACKETS) do
            local data = char.brackets and char.brackets[bi]
            if data then
                table.insert(rParts, AI.BRACKET_NAMES[bi] .. ": " .. data.rating)
            end
        end
        -- Show per-spec brackets for ALL specs with data (not just current spec)
        if char.specBrackets then
            for sid, sb in pairs(char.specBrackets) do
                local specLabel = AI.specData and AI.specData[sid] and AI.specData[sid].specName or tostring(sid)
                for _, bi in ipairs(AI.TRACKED_BRACKETS) do
                    if AI.PER_SPEC_BRACKETS[bi] and sb[bi] then
                        table.insert(rParts, specLabel .. " " .. AI.BRACKET_NAMES[bi] .. ": " .. sb[bi].rating)
                    end
                end
            end
        end
        row.ratingsStr:SetText(table.concat(rParts, "  |  "))

        -- Remove button
        local charKey = key
        row.removeBtn:SetScript("OnClick", function()
            ArenaInsightsDB.characters[charKey] = nil
            RefreshCharacterList()
        end)

        row:Show()
        yOff = yOff + ROW_HEIGHT + ROW_GAP
    end

    -- Hide excess rows
    for j = #keys + 1, #rows do
        rows[j]:Hide()
    end

    scrollChild:SetHeight(math.max(yOff, 1))
end

function AI.CreateCharactersPanel(parent)
    if panel then return panel end

    panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Characters")
    title:SetTextColor(unpack(AI.COLORS.GOLD))

    -- Empty state
    emptyLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyLabel:SetPoint("CENTER", 0, 0)
    emptyLabel:SetText("No characters tracked yet.\nPlay a rated game to start tracking automatically.")
    emptyLabel:SetTextColor(0.55, 0.55, 0.55)
    emptyLabel:SetJustifyH("CENTER")
    emptyLabel:Hide()

    -- Scroll area
    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", 0, -32)
    scroll:SetPoint("BOTTOMRIGHT", 0, 4)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(cur - delta * 40, max)))
    end)

    scrollChild = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(scrollChild)
    scrollChild:SetHeight(1)
    scroll:SetScript("OnSizeChanged", function(self, w)
        scrollChild:SetWidth(w)
    end)

    -- Refresh when tab becomes visible
    panel:SetScript("OnShow", function() RefreshCharacterList() end)

    return panel
end
