local addonName, AI = ...

local MAX_ROWS = 10

local function AppendCharRows(tooltip, getAmount)
    if not ArenaInsightsDB then return end
    if ArenaInsightsDB.settings and ArenaInsightsDB.settings.disableTooltip then return end

    local rows = {}
    for _, char in pairs(ArenaInsightsDB.characters) do
        local amount = getAmount(char)
        if amount and amount > 0 then
            rows[#rows + 1] = { name = char.name or "?", amount = amount, classFileName = char.classFileName }
        end
    end

    if #rows == 0 then return end

    table.sort(rows, function(a, b) return a.amount > b.amount end)

    tooltip:AddLine("ArenaInsights", 0.88, 0.22, 0.18)

    local shown = math.min(#rows, MAX_ROWS)
    for i = 1, shown do
        local row = rows[i]
        local color = RAID_CLASS_COLORS and row.classFileName and RAID_CLASS_COLORS[row.classFileName]
        local r, g, b = 1, 1, 1
        if color then r, g, b = color.r, color.g, color.b end
        tooltip:AddDoubleLine(row.name, tostring(row.amount), r, g, b, 1, 1, 1)
    end

    if #rows > MAX_ROWS then
        tooltip:AddLine("+ " .. (#rows - MAX_ROWS) .. " more", 0.48, 0.45, 0.43)
    end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Currency, function(tooltip, data)
    if not data or not data.id then return end
    local tracked = false
    for _, entry in ipairs(AI.TRACKED_CURRENCIES) do
        if entry.id == data.id then tracked = true; break end
    end
    if not tracked then return end

    AppendCharRows(tooltip, function(char)
        if not char.currencies then return nil end
        local c = char.currencies[data.id]
        return c and c.amount
    end)
end)

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if not data or not data.id then return end
    local tracked = false
    for _, entry in ipairs(AI.TRACKED_ITEMS) do
        if entry.id == data.id then tracked = true; break end
    end
    if not tracked then return end

    AppendCharRows(tooltip, function(char)
        if not char.items then return nil end
        local item = char.items[data.id]
        return item and item.count
    end)
end)
