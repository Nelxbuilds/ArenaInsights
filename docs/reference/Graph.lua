-- NelxGather/UI/Panel/Graph.lua
-- Renders a GPH-over-time line chart in the detail panel's graph section.
-- Uses CreateLine() to draw segments between sampled data points.
-- Displays "Gathering data..." when fewer than 3 data points exist.

local addonName, ns = ...

ns.PanelGraph = {}
local PanelGraph = ns.PanelGraph

local MIN_POINTS    = 3
local PADDING_LEFT  = 44   -- space for Y-axis labels
local PADDING_RIGHT = 8
local PADDING_TOP   = 10
local PADDING_BOT   = 22   -- space for X-axis labels
local LINE_COLOR    = { r = 0.2, g = 0.9, b = 0.4, a = 1.0 }
local LINE_W        = 1.5

-- ---------------------------------------------------------------------------
-- Initialize: create the canvas and placeholder text
-- ---------------------------------------------------------------------------

function PanelGraph:Initialize(parent)
    PanelGraph.parent = parent

    -- "Gathering data..." placeholder
    local placeholder = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    placeholder:SetPoint("CENTER", parent, "CENTER", 0, 0)
    placeholder:SetText("|cff808080Gathering data...|r")
    PanelGraph.placeholder = placeholder

    -- Canvas frame for drawing lines (sits inside padding)
    local canvas = CreateFrame("Frame", nil, parent)
    canvas:SetPoint("TOPLEFT",     parent, "TOPLEFT",     PADDING_LEFT,  -PADDING_TOP)
    canvas:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -PADDING_RIGHT, PADDING_BOT)
    PanelGraph.canvas = canvas

    -- Axis label pools
    PanelGraph.xLabels = {}
    PanelGraph.yLabels = {}
    PanelGraph.lines   = {}

    -- Border lines for the axes
    local axisL = parent:CreateTexture(nil, "ARTWORK")
    axisL:SetWidth(1)
    axisL:SetPoint("TOPLEFT",    parent, "TOPLEFT",    PADDING_LEFT, -PADDING_TOP)
    axisL:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", PADDING_LEFT, PADDING_BOT)
    axisL:SetColorTexture(0.5, 0.5, 0.5, 0.5)

    local axisB = parent:CreateTexture(nil, "ARTWORK")
    axisB:SetHeight(1)
    axisB:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  PADDING_LEFT,  PADDING_BOT)
    axisB:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -PADDING_RIGHT, PADDING_BOT)
    axisB:SetColorTexture(0.5, 0.5, 0.5, 0.5)

    -- Section title
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING_LEFT, 0)
    title:SetText("GPH over time")
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function GetOrCreateLine(canvas, index)
    if not PanelGraph.lines[index] then
        local line = canvas:CreateLine()
        line:SetThickness(LINE_W)
        line:SetColorTexture(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, LINE_COLOR.a)
        PanelGraph.lines[index] = line
    end
    return PanelGraph.lines[index]
end

local function HideLines(fromIndex)
    for i = fromIndex, #PanelGraph.lines do
        PanelGraph.lines[i]:Hide()
    end
end

local function GetOrCreateLabel(pool, parent, fontObj)
    for _, lbl in ipairs(pool) do
        if not lbl:IsShown() then
            lbl:Show()
            return lbl
        end
    end
    local lbl = parent:CreateFontString(nil, "OVERLAY", fontObj or "GameFontNormalSmall")
    pool[#pool + 1] = lbl
    return lbl
end

local function HideLabels(pool)
    for _, lbl in ipairs(pool) do lbl:Hide() end
end

local function FormatGPHShort(gph)
    if gph >= 1000 then
        return string.format("%.0fk", gph / 1000)
    end
    return string.format("%.0f", gph)
end

local function FormatTimeShort(seconds)
    local m = math.floor(seconds / 60)
    if m < 60 then return m .. "m" end
    return string.format("%dh%dm", math.floor(m / 60), m % 60)
end

-- ---------------------------------------------------------------------------
-- Refresh: redraw the graph from gphHistory
-- ---------------------------------------------------------------------------

function PanelGraph:Refresh()
    if not PanelGraph.canvas then return end

    local session = ns.Session and ns.Session:Current()
    local history = (session and session.gphHistory) or {}

    -- Fewer than 3 points → show placeholder
    if #history < MIN_POINTS then
        PanelGraph.placeholder:Show()
        HideLines(1)
        HideLabels(PanelGraph.xLabels)
        HideLabels(PanelGraph.yLabels)
        return
    end

    PanelGraph.placeholder:Hide()

    local canvas = PanelGraph.canvas
    local W = canvas:GetWidth()  or 1
    local H = canvas:GetHeight() or 1

    -- Find data range
    local minGPH, maxGPH = math.huge, -math.huge
    local minT,   maxT   = math.huge, -math.huge
    for _, pt in ipairs(history) do
        if pt.gph < minGPH then minGPH = pt.gph end
        if pt.gph > maxGPH then maxGPH = pt.gph end
        if pt.time < minT  then minT   = pt.time end
        if pt.time > maxT  then maxT   = pt.time end
    end

    -- Guard against flat line (all same value)
    local gphRange = maxGPH - minGPH
    if gphRange < 1 then
        minGPH = minGPH - 1
        maxGPH = maxGPH + 1
        gphRange = 2
    end
    local timeRange = maxT - minT
    if timeRange < 1 then timeRange = 1 end

    -- Map a data point to canvas pixel coordinates
    local function toCanvas(t, g)
        local x = ((t - minT) / timeRange) * W
        local y = ((g - minGPH) / gphRange) * H
        return x, y
    end

    -- Draw line segments
    local usedLines = 0
    for i = 2, #history do
        local x1, y1 = toCanvas(history[i-1].time, history[i-1].gph)
        local x2, y2 = toCanvas(history[i].time,   history[i].gph)
        usedLines = usedLines + 1
        local line = GetOrCreateLine(canvas, usedLines)
        line:SetStartPoint("BOTTOMLEFT", x1, y1)
        line:SetEndPoint(  "BOTTOMLEFT", x2, y2)
        line:Show()
    end
    HideLines(usedLines + 1)

    -- -----------------------------------------------------------------------
    -- Y-axis labels (4 ticks)
    -- -----------------------------------------------------------------------
    HideLabels(PanelGraph.yLabels)
    local yTicks = 4
    for i = 0, yTicks do
        local frac = i / yTicks
        local gph  = minGPH + frac * gphRange
        local yPx  = frac * H

        local lbl = GetOrCreateLabel(PanelGraph.yLabels, PanelGraph.parent, "GameFontNormalSmall")
        lbl:SetText("|cffaaaaaa" .. FormatGPHShort(gph) .. "g|r")
        lbl:ClearAllPoints()
        lbl:SetPoint("RIGHT", PanelGraph.parent, "BOTTOMLEFT",
            PADDING_LEFT - 2,
            PADDING_BOT + yPx)
    end

    -- -----------------------------------------------------------------------
    -- X-axis labels (up to 5 ticks)
    -- -----------------------------------------------------------------------
    HideLabels(PanelGraph.xLabels)
    local xTicks = math.min(5, #history - 1)
    for i = 0, xTicks do
        local frac = i / xTicks
        local t    = minT + frac * timeRange
        local xPx  = frac * W

        local lbl = GetOrCreateLabel(PanelGraph.xLabels, PanelGraph.parent, "GameFontNormalSmall")
        lbl:SetText("|cffaaaaaa" .. FormatTimeShort(t) .. "|r")
        lbl:ClearAllPoints()
        lbl:SetPoint("TOP", PanelGraph.parent, "BOTTOMLEFT",
            PADDING_LEFT + xPx,
            PADDING_BOT - 2)
    end
end
