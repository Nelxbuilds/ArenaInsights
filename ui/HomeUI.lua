local addonName, AI = ...

-- ============================================================================
-- How-To Tab
-- ============================================================================

local PADDING = 10
local SECTION_GAP = 18
local PARA_WIDTH_INSET = PADDING * 2

local function AddHeading(parent, text, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", PADDING, y)
    fs:SetText(text)
    fs:SetTextColor(unpack(AI.COLORS.GOLD))
    return y - 18
end

local function AddParagraph(parent, text, y, maxWidth)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", PADDING, y)
    fs:SetWidth(maxWidth - PARA_WIDTH_INSET)
    fs:SetJustifyH("LEFT")
    fs:SetSpacing(2)
    fs:SetText(text)
    fs:SetTextColor(0.78, 0.75, 0.73)
    fs:SetWordWrap(true)
    -- GetStringHeight unreliable before layout; use a fixed estimate
    return y - (fs:GetStringHeight() or 40) - 6
end

local function AddSeparator(parent, y)
    local sep = parent:CreateTexture(nil, "BORDER")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", PADDING, y - 6)
    sep:SetPoint("RIGHT", parent, "RIGHT", -PADDING, 0)
    sep:SetColorTexture(0.18, 0.12, 0.10, 0.6)
    return y - 18
end

local function CreateCopyableLink(parent, label, url, y)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", PADDING, y)
    lbl:SetText(label)
    lbl:SetTextColor(0.65, 0.65, 0.65)
    y = y - 16

    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(320, 22)
    box:SetPoint("TOPLEFT", PADDING, y)
    box:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    box:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
    box:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
    box:SetFontObject("ChatFontNormal")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetAutoFocus(false)
    box:SetText(url)
    box:SetCursorPosition(0)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnEditFocusLost",   function(self) self:HighlightText(0, 0) end)
    box:SetScript("OnEscapePressed",   function(self) self:ClearFocus() end)
    box:SetScript("OnChar", function(self) self:SetText(url); self:HighlightText() end)
    return y - 22 - 10
end

function AI.CreateHowToPanel(parent)
    -- Scroll frame so content doesn't clip
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent)
    scrollFrame:SetAllPoints()
    scrollFrame:EnableMouseWheel(true)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    scrollFrame:SetScript("OnSizeChanged", function(self, w, h)
        scrollChild:SetWidth(w)
    end)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(cur - delta * 20, max)))
    end)

    local panelW = parent:GetWidth() > 0 and parent:GetWidth() or 540

    local y = -PADDING

    -- Title
    local title = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", PADDING, y)
    title:SetText("How to Use ArenaInsights")
    title:SetTextColor(unpack(AI.COLORS.GOLD))
    y = y - 22

    local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"
    local ver = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ver:SetPoint("TOPLEFT", PADDING, y)
    ver:SetText("Version " .. version)
    ver:SetTextColor(0.48, 0.45, 0.43)
    y = y - SECTION_GAP

    -- Overlay
    y = AddHeading(scrollChild, "Overlay", y)
    y = AddParagraph(scrollChild,
        "A movable frame showing spec rows from your active challenge, with per-spec best rating across all your tracked characters. Opacity is adjustable in Settings; at zero the overlay hides entirely and disables mouse interaction.",
        y, panelW)
    y = AddParagraph(scrollChild,
        "Lock or unlock the overlay position with |cffffd700/ai lock|r and |cffffd700/ai unlock|r.",
        y, panelW)
    y = AddSeparator(scrollChild, y)

    -- Challenges
    y = AddHeading(scrollChild, "Challenges", y)
    y = AddParagraph(scrollChild,
        "Create rating goals per spec or class and choose which brackets count toward each goal. Only one challenge can be active at a time, and the overlay always reflects the active challenge.",
        y, panelW)
    y = AddParagraph(scrollChild,
        "Class challenges roll up all specs of that class. Multi-bracket challenges count your highest rating across the selected brackets.",
        y, panelW)
    y = AddSeparator(scrollChild, y)

    -- Insights & History
    y = AddHeading(scrollChild, "Insights and History", y)
    y = AddParagraph(scrollChild,
        "Match data is captured automatically after every rated game. Insights shows your match history with rating changes, MMR, specs, and outcome. History shows rating progression over time as a chart.",
        y, panelW)
    y = AddParagraph(scrollChild,
        "No setup required. Both tabs populate as soon as you play rated matches.",
        y, panelW)
    y = AddSeparator(scrollChild, y)

    -- Characters
    y = AddHeading(scrollChild, "Characters", y)
    y = AddParagraph(scrollChild,
        "Lists all tracked characters with their current ratings per bracket. Characters are added automatically when you play rated matches on them. Ratings update after each match.",
        y, panelW)
    y = AddSeparator(scrollChild, y)

    -- Import / Export
    y = AddHeading(scrollChild, "Import and Export", y)
    y = AddParagraph(scrollChild,
        "Share challenge and character data across accounts or between alts. Export produces a compact string you can paste into another account's Import box. Import merges incoming data without overwriting any existing ratings or challenges on the receiving account.",
        y, panelW)
    y = AddSeparator(scrollChild, y)

    -- Party Sync
    y = AddHeading(scrollChild, "Party Sync", y)
    y = AddParagraph(scrollChild,
        "Syncs challenge and rating data with party members who also have ArenaInsights installed. Run |cffffd700/ai sync|r while in a party to broadcast your data and receive theirs.",
        y, panelW)
    y = AddSeparator(scrollChild, y)

    -- Slash Commands
    y = AddHeading(scrollChild, "Slash Commands", y)
    local cmds = {
        { "/ai",              "Open the main window" },
        { "/ai overlay",      "Toggle overlay visibility" },
        { "/ai lock",         "Lock overlay position" },
        { "/ai unlock",       "Unlock overlay position" },
        { "/ai sync",         "Sync data with party members" },
        { "/ai debug",        "Toggle debug logging" },
        { "/ai help",         "Show slash command help in chat" },
    }
    for _, pair in ipairs(cmds) do
        local row = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row:SetPoint("TOPLEFT", PADDING, y)
        row:SetWidth(panelW - PARA_WIDTH_INSET)
        row:SetJustifyH("LEFT")
        row:SetText("|cffffd700" .. pair[1] .. "|r  -  " .. pair[2])
        row:SetTextColor(0.78, 0.75, 0.73)
        y = y - 18
    end
    y = AddSeparator(scrollChild, y)

    -- Links
    y = AddHeading(scrollChild, "Links", y)
    y = CreateCopyableLink(scrollChild, "CurseForge",
        "https://www.curseforge.com/wow/addons/arena-insights", y)
    y = CreateCopyableLink(scrollChild, "GitHub",
        "https://github.com/Nelxbuilds/ArenaInsights", y)

    y = y - PADDING
    scrollChild:SetHeight(math.abs(y) + 20)
end
