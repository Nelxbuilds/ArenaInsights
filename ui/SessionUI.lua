local addonName, AI = ...

-- ============================================================================
-- Session summary popup
-- Shows after leaving arena when a match was recorded this session.
-- Session = matches with < 1h gap (AI.GetLatestSession in core/Insights.lua).
-- ============================================================================

local POPUP_W     = 340
local ROW_H       = 20
local BLOCK_W     = 8
local BLOCK_H     = 14
local BLOCK_GAP   = 2
local MAX_BLOCKS  = 34
local PAD         = 12

local popup
local bracketRows = {}
local blockPool   = {}
local pendingCharKey = nil  -- set when a match records while still inside the arena

local OUTCOME_COLOR = {
    win     = { 0.13, 0.70, 0.13 },
    loss    = { 0.75, 0.13, 0.13 },
    draw    = { 0.85, 0.72, 0.15 },
    unknown = { 0.40, 0.40, 0.40 },
}

local function SignText(n)
    if n > 0 then return "|cff22cc22+" .. n .. "|r" end
    if n < 0 then return "|cffcc2222" .. n .. "|r" end
    return "|cff777777+0|r"
end

local function Summarize(session)
    local per = {}
    for _, rec in ipairs(session) do
        local bi = rec.bracketIndex
        if bi then
            local s = per[bi]
            if not s then
                s = { games = 0, w = 0, l = 0, d = 0, rw = 0, rl = 0, dr = 0, dm = 0 }
                per[bi] = s
            end
            s.games = s.games + 1
            if rec.outcome == "win" then
                s.w = s.w + 1
            elseif rec.outcome == "loss" then
                s.l = s.l + 1
            elseif rec.outcome == "draw" then
                s.d = s.d + 1
            end
            if bi == AI.BRACKET_SOLO_SHUFFLE then
                local wr = (rec.shuffle and rec.shuffle.wonRounds) or rec.wonRounds
                if type(wr) == "number" then
                    s.rw = s.rw + wr
                    s.rl = s.rl + (6 - wr)
                end
            end
            s.dr = s.dr + (rec.ratingChange or 0)
            s.dm = s.dm + (rec.mmrChange or 0)
        end
    end
    return per
end

local function BuildPopup()
    popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetWidth(POPUP_W)
    popup:SetPoint("CENTER", 0, 120)
    popup:SetFrameStrata("DIALOG")
    popup:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    popup:SetBackdropColor(0.04, 0.04, 0.06, 0.95)
    popup:SetBackdropBorderColor(0.60, 0.15, 0.12, 1)
    popup:EnableMouse(true)  -- absorb clicks under the popup

    popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    popup.title:SetPoint("TOPLEFT", PAD, -PAD)
    popup.title:SetText("Session Summary")
    popup.title:SetTextColor(0.96, 0.92, 0.90)

    popup.subtitle = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    popup.subtitle:SetPoint("TOPLEFT", PAD, -(PAD + 22))
    popup.subtitle:SetTextColor(0.48, 0.45, 0.43)

    local closeBtn = CreateFrame("Button", nil, popup)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    closeBtn.label = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeBtn.label:SetAllPoints()
    closeBtn.label:SetText("X")
    closeBtn.label:SetTextColor(0.48, 0.45, 0.43)
    closeBtn:SetScript("OnClick", function() popup:Hide() end)
    closeBtn:SetScript("OnEnter", function(self)
        self.label:SetTextColor(0.88, 0.22, 0.18)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Close", 1, 1, 1)
        GameTooltip:Show()
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self.label:SetTextColor(0.48, 0.45, 0.43)
        GameTooltip:Hide()
    end)

    popup:Hide()
    return popup
end

local function GetBracketRow(i)
    if bracketRows[i] then return bracketRows[i] end
    local r = {}
    r.name = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetWidth(110)
    r.name:SetJustifyH("LEFT")
    r.name:SetTextColor(0.78, 0.75, 0.73)
    r.score = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    r.score:SetWidth(70)
    r.score:SetJustifyH("LEFT")
    r.delta = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.delta:SetWidth(130)
    r.delta:SetJustifyH("RIGHT")
    bracketRows[i] = r
    return r
end

local function GetBlock(i)
    if blockPool[i] then return blockPool[i] end
    local t = popup:CreateTexture(nil, "ARTWORK")
    t:SetSize(BLOCK_W, BLOCK_H)
    blockPool[i] = t
    return t
end

-- Public: show the summary for the latest session (charKey nil = all chars).
-- Callable manually for testing: /run AI.ShowSessionSummary()
function AI.ShowSessionSummary(charKey)
    local session = AI.GetLatestSession(charKey)
    if #session == 0 then return end
    if not popup then BuildPopup() end

    local per = Summarize(session)

    local who = charKey and (charKey:match("^(.+)-") or charKey) or "All characters"
    local sub = who .. "  -  " .. #session
        .. (#session == 1 and " match" or " matches") .. " this session"

    -- Current streak: trailing run of same win/loss outcome
    local streakOutcome = session[#session] and session[#session].outcome
    local streak = 0
    if streakOutcome == "win" or streakOutcome == "loss" then
        for i = #session, 1, -1 do
            if session[i].outcome == streakOutcome then
                streak = streak + 1
            else
                break
            end
        end
    end
    if streak >= 2 then
        if streakOutcome == "win" then
            sub = sub .. "  |cff22cc22W" .. streak .. " streak|r"
        else
            sub = sub .. "  |cffcc2222L" .. streak .. " streak|r"
        end
    end
    popup.subtitle:SetText(sub)

    local y = PAD + 44
    local shown = 0
    for _, r in ipairs(bracketRows) do r.name:Hide() r.score:Hide() r.delta:Hide() end
    for _, bi in ipairs(AI.TRACKED_BRACKETS) do
        local s = per[bi]
        if s then
            shown = shown + 1
            local r = GetBracketRow(shown)
            r.name:ClearAllPoints()
            r.name:SetPoint("TOPLEFT", PAD, -y)
            r.score:ClearAllPoints()
            r.score:SetPoint("TOPLEFT", PAD + 112, -y)
            r.delta:ClearAllPoints()
            r.delta:SetPoint("TOPRIGHT", -PAD, -y)

            r.name:SetText(AI.BRACKET_NAMES[bi] or ("Bracket " .. bi))
            if bi == AI.BRACKET_SOLO_SHUFFLE and (s.rw + s.rl) > 0 then
                r.score:SetText(s.rw .. "-" .. s.rl)
            else
                r.score:SetText(s.w .. "-" .. s.l)
            end
            r.score:SetTextColor(1, 1, 1)
            r.delta:SetText(SignText(s.dr) .. " rating  " .. SignText(s.dm) .. " MMR")
            r.name:Show() r.score:Show() r.delta:Show()
            y = y + ROW_H
        end
    end

    -- Per-match outcome strip, chronological
    y = y + 6
    for _, t in ipairs(blockPool) do t:Hide() end
    local n = math.min(#session, MAX_BLOCKS)
    local firstIdx = #session - n + 1
    for i = 1, n do
        local rec = session[firstIdx + i - 1]
        local blk = GetBlock(i)
        blk:ClearAllPoints()
        blk:SetPoint("TOPLEFT", PAD + (i - 1) * (BLOCK_W + BLOCK_GAP), -y)
        local c = OUTCOME_COLOR[rec.outcome or "unknown"] or OUTCOME_COLOR.unknown
        blk:SetColorTexture(c[1], c[2], c[3], 1)
        blk:Show()
    end
    y = y + BLOCK_H

    popup:SetHeight(y + PAD)
    popup:Show()
end

-- ============================================================================
-- Trigger: match recorded -> popup once the player is out of the arena
-- ============================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
local function InPvPInstance()
    local _, instanceType = IsInInstance()
    return instanceType == "arena" or instanceType == "pvp"
end

eventFrame:SetScript("OnEvent", function()
    if not pendingCharKey then return end
    if InPvPInstance() then return end
    local charKey = pendingCharKey
    pendingCharKey = nil
    AI.ShowSessionSummary(charKey)
end)

-- Called by core/Insights.lua after a match record is written (nil-guarded there)
function AI.OnMatchRecorded(rec)
    if not (ArenaInsightsDB.settings and ArenaInsightsDB.settings.sessionPopupEnabled) then return end
    if InPvPInstance() then
        pendingCharKey = rec.charKey
    else
        AI.ShowSessionSummary(rec.charKey)
    end
end
