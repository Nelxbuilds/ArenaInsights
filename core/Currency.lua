local addonName, AI = ...

AI.TRACKED_CURRENCIES = {
    { id = 1792, name = "Honor" },
    { id = 1602, name = "Conquest" },
    { id = 2123, name = "Bloody Tokens" },
}

AI.TRACKED_ITEMS = {
    { id = 137642, name = "Mark of Honor" },
    { id = 241334, name = "Flask of Honor" },
    { id = 258622, name = "Medal of Conquest" },
}

local function CaptureCurrencyData()
    local key = AI.currentCharKey
    if not key then return end

    local char = ArenaInsightsDB.characters[key]
    if not char then return end

    char.currencies = char.currencies or {}
    for _, entry in ipairs(AI.TRACKED_CURRENCIES) do
        local info = C_CurrencyInfo.GetCurrencyInfo(entry.id)
        if info then
            char.currencies[entry.id] = {
                amount      = info.quantity,
                maxQuantity = info.maxQuantity,
            }
        end
    end

    char.items = char.items or {}
    for _, entry in ipairs(AI.TRACKED_ITEMS) do
        char.items[entry.id] = { count = GetItemCount(entry.id, true) }
    end
end

local currencyFrame = CreateFrame("Frame")
currencyFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
currencyFrame:RegisterEvent("BAG_UPDATE_DELAYED")
currencyFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

currencyFrame:SetScript("OnEvent", function(self, event)
    CaptureCurrencyData()
end)
