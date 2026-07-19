local addonName, AI = ...

-- ============================================================================
-- Session summary popup
-- Shows after leaving arena when a match was recorded this session.
-- Session = matches with < 1h gap (AI.GetLatestSession in core/Insights.lua).
-- ============================================================================

local POPUP_W     = 340
local ROW_H       = 20
local CHART_H     = 110
local PLOT_PAD_L  = 34   -- left gutter for Y-axis rating labels
local PLOT_PAD_R  = 8
local PLOT_PAD_T  = 8
local PLOT_PAD_B  = 16   -- bottom gutter for X-axis match labels
local MARKER_SIZE = 5
local PAD         = 12

local popup
local bracketRows  = {}
local chartLines   = {}
local chartMarkers = {}
local chartGrid    = {}  -- horizontal rating gridlines
local chartYLabels = {}  -- rating labels on the Y-axis
local chartXLabels = {}  -- match-index labels on the X-axis
local pendingCharKey = nil  -- set when a match records while still inside the arena

local OUTCOME_COLOR = {
    win     = { 0.13, 0.70, 0.13 },
    loss    = { 0.75, 0.13, 0.13 },
    draw    = { 0.85, 0.72, 0.15 },
    unknown = { 0.40, 0.40, 0.40 },
}

-- Per-bracket line colour (doubles as the swatch on each summary row)
local BRACKET_COLOR = {
    [AI.BRACKET_2V2]          = { 0.36, 0.72, 0.95 },
    [AI.BRACKET_3V3]          = { 0.55, 0.85, 0.45 },
    [AI.BRACKET_BLITZ]        = { 0.82, 0.55, 0.98 },
    [AI.BRACKET_SOLO_SHUFFLE] = { 0.93, 0.42, 0.28 },
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
                s = { games = 0, w = 0, l = 0, d = 0, rw = 0, rl = 0, dr = 0 }
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
        end
    end
    return per
end

local function RestorePopupPosition()
    local pos = ArenaInsightsDB.settings and ArenaInsightsDB.settings.sessionPopupPos
    popup:ClearAllPoints()
    if pos and pos.point then
        popup:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
    else
        popup:SetPoint("CENTER", 0, 120)
    end
end

local function BuildPopup()
    popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetWidth(POPUP_W)
    popup:SetFrameStrata("DIALOG")
    popup:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    popup:SetBackdropColor(0.04, 0.04, 0.06, 0.95)
    popup:SetBackdropBorderColor(0.60, 0.15, 0.12, 1)
    popup:EnableMouse(true)  -- absorb clicks under the popup

    popup:SetMovable(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", function(self) self:StartMoving() end)
    popup:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        ArenaInsightsDB.settings.sessionPopupPos = { point = point, x = x, y = y }
    end)
    popup:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Drag to move", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    popup:SetScript("OnLeave", function() GameTooltip:Hide() end)
    RestorePopupPosition()

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

    -- Rating trajectory chart (one line per bracket, each on its own scale)
    popup.chart = CreateFrame("Frame", nil, popup)
    popup.chart:SetHeight(CHART_H)
    local cbg = popup.chart:CreateTexture(nil, "BACKGROUND")
    cbg:SetAllPoints()
    cbg:SetColorTexture(0.09, 0.08, 0.10, 0.6)
    popup.chart:Hide()

    popup:Hide()
    return popup
end

local function GetChartLine(i)
    if chartLines[i] then return chartLines[i] end
    local ln = popup.chart:CreateLine(nil, "ARTWORK")
    ln:SetThickness(2)
    chartLines[i] = ln
    return ln
end

local function GetChartMarker(i)
    if chartMarkers[i] then return chartMarkers[i] end
    local m = popup.chart:CreateTexture(nil, "OVERLAY")
    m:SetSize(MARKER_SIZE, MARKER_SIZE)
    chartMarkers[i] = m
    return m
end

local function GetChartGrid(i)
    if chartGrid[i] then return chartGrid[i] end
    local ln = popup.chart:CreateLine(nil, "BACKGROUND")
    ln:SetThickness(1)
    ln:SetColorTexture(1, 1, 1, 0.06)
    chartGrid[i] = ln
    return ln
end

local function GetChartYLabel(i)
    if chartYLabels[i] then return chartYLabels[i] end
    local fs = popup.chart:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
    fs:SetTextColor(0.55, 0.55, 0.55)
    fs:SetJustifyH("RIGHT")
    chartYLabels[i] = fs
    return fs
end

local function GetChartXLabel(i)
    if chartXLabels[i] then return chartXLabels[i] end
    local fs = popup.chart:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
    fs:SetTextColor(0.55, 0.55, 0.55)
    chartXLabels[i] = fs
    return fs
end

-- Draw one rating line per bracket on a single shared rating scale (global
-- min/max across all brackets), with a numbered Y-axis + gridlines and X-axis
-- match-index labels (History-style). Markers coloured by match outcome.
-- Returns the new content Y offset.
local function RenderChart(session, y)
    for _, l in ipairs(chartLines)   do l:Hide() end
    for _, m in ipairs(chartMarkers) do m:Hide() end
    for _, g in ipairs(chartGrid)    do g:Hide() end
    for _, t in ipairs(chartYLabels) do t:Hide() end
    for _, t in ipairs(chartXLabels) do t:Hide() end

    local series, order = {}, {}
    local minR, maxR
    for _, rec in ipairs(session) do
        local bi, rating = rec.bracketIndex, rec.rating
        if bi and type(rating) == "number" then
            local s = series[bi]
            if not s then
                s = { pts = {} }
                series[bi] = s
                order[#order + 1] = bi
            end
            -- Each bracket is its own sequence starting at match 1, so brackets
            -- share the X-axis rather than being scattered by global order.
            s.pts[#s.pts + 1] = { x = #s.pts + 1, v = rating, outcome = rec.outcome }
            if not minR or rating < minR then minR = rating end
            if not maxR or rating > maxR then maxR = rating end
        end
    end
    if #order == 0 then
        popup.chart:Hide()
        return y
    end

    local N = 0
    for _, bi in ipairs(order) do
        N = math.max(N, #series[bi].pts)
    end

    -- Snap the shared scale to clean interval boundaries (History convention)
    local interval
    local rawRange = maxR - minR
    if rawRange <= 300 then interval = 50
    elseif rawRange <= 600 then interval = 100
    else interval = 200 end
    minR = math.floor(minR / interval) * interval
    maxR = math.ceil(maxR / interval) * interval
    if maxR == minR then maxR = minR + interval end
    local ratingRange = maxR - minR

    popup.chart:ClearAllPoints()
    popup.chart:SetPoint("TOPLEFT", PAD, -y)
    popup.chart:SetPoint("TOPRIGHT", -PAD, -y)
    popup.chart:Show()

    local plotW = (POPUP_W - 2 * PAD) - PLOT_PAD_L - PLOT_PAD_R
    local plotH = CHART_H - PLOT_PAD_T - PLOT_PAD_B
    local function xPos(idx)
        if N <= 1 then return PLOT_PAD_L + plotW / 2 end
        return PLOT_PAD_L + (idx - 1) / (N - 1) * plotW
    end
    local function yPos(v)
        return PLOT_PAD_B + (v - minR) / ratingRange * plotH
    end

    -- Y-axis: gridlines + rating labels at each interval milestone
    local gi = 0
    for ms = minR, maxR, interval do
        gi = gi + 1
        local gy = yPos(ms)
        local g = GetChartGrid(gi)
        g:SetStartPoint("BOTTOMLEFT", PLOT_PAD_L, gy)
        g:SetEndPoint("BOTTOMLEFT", PLOT_PAD_L + plotW, gy)
        g:Show()

        local lbl = GetChartYLabel(gi)
        lbl:SetText(tostring(ms))
        lbl:ClearAllPoints()
        lbl:SetPoint("RIGHT", popup.chart, "BOTTOMLEFT", PLOT_PAD_L - 4, gy)
        lbl:Show()
    end

    -- X-axis: match-index labels (up to ~5 ticks)
    local xTicks = math.min(5, N - 1)
    if xTicks > 0 then
        for i = 0, xTicks do
            local frac = i / xTicks
            local idx  = math.floor(frac * (N - 1)) + 1
            local lbl = GetChartXLabel(i + 1)
            lbl:SetText(tostring(idx))
            lbl:ClearAllPoints()
            lbl:SetPoint("TOP", popup.chart, "BOTTOMLEFT", xPos(idx), PLOT_PAD_B - 3)
            lbl:Show()
        end
    end

    local li, mi = 0, 0
    for _, bi in ipairs(order) do
        local s = series[bi]
        local col = BRACKET_COLOR[bi] or { 0.88, 0.22, 0.18 }
        for k = 2, #s.pts do
            li = li + 1
            local ln = GetChartLine(li)
            ln:SetStartPoint("BOTTOMLEFT", xPos(s.pts[k - 1].x), yPos(s.pts[k - 1].v))
            ln:SetEndPoint("BOTTOMLEFT", xPos(s.pts[k].x), yPos(s.pts[k].v))
            ln:SetColorTexture(col[1], col[2], col[3], 0.9)
            ln:Show()
        end
        for _, p in ipairs(s.pts) do
            mi = mi + 1
            local m = GetChartMarker(mi)
            local oc = OUTCOME_COLOR[p.outcome or "unknown"] or OUTCOME_COLOR.unknown
            m:SetColorTexture(oc[1], oc[2], oc[3], 1)
            m:ClearAllPoints()
            m:SetPoint("CENTER", popup.chart, "BOTTOMLEFT", xPos(p.x), yPos(p.v))
            m:Show()
        end
    end

    return y + CHART_H
end

local function GetBracketRow(i)
    if bracketRows[i] then return bracketRows[i] end
    local r = {}
    r.swatch = popup:CreateTexture(nil, "OVERLAY")
    r.swatch:SetSize(10, 10)
    r.name = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetWidth(90)
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
    for _, r in ipairs(bracketRows) do r.swatch:Hide() r.name:Hide() r.score:Hide() r.delta:Hide() end
    for _, bi in ipairs(AI.TRACKED_BRACKETS) do
        local s = per[bi]
        if s then
            shown = shown + 1
            local r = GetBracketRow(shown)
            r.swatch:ClearAllPoints()
            r.swatch:SetPoint("TOPLEFT", PAD, -(y + 4))
            local col = BRACKET_COLOR[bi] or { 0.88, 0.22, 0.18 }
            r.swatch:SetColorTexture(col[1], col[2], col[3], 1)
            r.name:ClearAllPoints()
            r.name:SetPoint("TOPLEFT", PAD + 16, -y)
            r.score:ClearAllPoints()
            r.score:SetPoint("TOPLEFT", PAD + 112, -y)
            r.delta:ClearAllPoints()
            r.delta:SetPoint("TOPRIGHT", -PAD, -y)

            r.name:SetText(AI.BRACKET_NAMES[bi] or ("Bracket " .. bi))
            r.name:SetTextColor(col[1], col[2], col[3])
            if bi == AI.BRACKET_SOLO_SHUFFLE and (s.rw + s.rl) > 0 then
                r.score:SetText(s.rw .. "-" .. s.rl)
            else
                r.score:SetText(s.w .. "-" .. s.l)
            end
            r.score:SetTextColor(1, 1, 1)
            -- MMR from prematchMMR diff across the session (scoreboard
            -- post-match MMR is 0 in Midnight; see AI.GetSessionMMRDelta)
            local dm = AI.GetSessionMMRDelta(session, bi)
            r.delta:SetText(SignText(s.dr) .. " rating  " .. SignText(dm or 0) .. " MMR")
            r.swatch:Show() r.name:Show() r.score:Show() r.delta:Show()
            y = y + ROW_H
        end
    end

    -- Rating trajectory chart (replaces the flat outcome strip)
    y = y + 6
    y = RenderChart(session, y)

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
