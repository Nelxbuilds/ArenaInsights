local addonName, AI = ...

local minimapFrame = CreateFrame("Frame")
minimapFrame:RegisterEvent("PLAYER_LOGIN")
minimapFrame:SetScript("OnEvent", function(self, event)
    if event ~= "PLAYER_LOGIN" then return end
    self:UnregisterEvent("PLAYER_LOGIN")

    if not ArenaInsightsDB or not ArenaInsightsDB.settings then return end

    ArenaInsightsDB.settings.minimapPosition = ArenaInsightsDB.settings.minimapPosition or {}

    local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    local LDBIcon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)

    if not LDB or not LDBIcon then return end

    local dataObject = LDB:NewDataObject("ArenaInsights", {
        type  = "launcher",
        icon  = "Interface\\AddOns\\ArenaInsights\\images\\logo",
        label = "ArenaInsights",

        OnClick = function(_, button)
            if button == "LeftButton" then
                AI.ToggleMainFrame()
            elseif button == "RightButton" then
                AI.SelectTab("Settings")
            end
        end,

        OnTooltipShow = function(tooltip)
            tooltip:SetText("ArenaInsights", 1, 0.82, 0)
            tooltip:AddLine("Left-click: Toggle window", 1, 1, 1)
            tooltip:AddLine("Right-click: Settings", 1, 1, 1)
            tooltip:Show()
        end,
    })

    LDBIcon:Register("ArenaInsights", dataObject, ArenaInsightsDB.settings.minimapPosition)

    local show = ArenaInsightsDB.settings.showMinimapButton
    if show == nil then show = true end
    if show then
        LDBIcon:Show("ArenaInsights")
    else
        LDBIcon:Hide("ArenaInsights")
    end
end)
