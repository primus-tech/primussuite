--[[
    PrimusUI Module: PUIMerchant (Native FrameXML Market Cluster Bar Graph Engine)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    1. Native 3-Tier Box-Plot Bar Graph Component:
       - Green Base: Low Tier (Cheapest 35% - Sniping/Bargain Floor)
       - Gold/Cyan Middle: Core Market Cluster (Median +- 15% Fair Value)
       - Coral Red Top: High Tier (Top 35% - Overpriced Ceiling)
       - Solid Horizontal Line: 7-Day Running Average
       - Interactive Column Hover Tooltips with exact statistical breakdowns.
    2. Mini Tooltip Sparklines (Shift+Hover GameTooltip integration).
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIMerchant = Primus.PUIMerchant or {}
Primus.PUIMerchant = PUIMerchant

local Media = Primus.Media
local Utils = Primus.Utils
local Items = Primus.Items

local graphIDCounter = 0
local function NextGraphName(prefix)
    graphIDCounter = graphIDCounter + 1
    return string.format("PrimusMarketGraph_%s_%d", prefix or "Element", graphIDCounter)
end

-- =========================================================================
-- BAR GRAPH BUILDER
-- =========================================================================

function PUIMerchant:CreateMarketBarGraph(parent, width, height, maxDays)
    parent = parent or UIParent
    width  = width or 240
    height = height or 90
    maxDays = maxDays or 14

    local container = CreateFrame("Frame", NextGraphName("Container"), parent)
    container:SetWidth(width)
    container:SetHeight(height)
    container:SetBackdrop(Media:Fetch("border", "1Pixel"))
    container:SetBackdropColor(0.05, 0.05, 0.08, 0.90)
    container:SetBackdropBorderColor(0.20, 0.20, 0.25, 1.0)

    -- Header / Title Label
    local title = container:CreateFontString(nil, "OVERLAY")
    title:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    title:SetPoint("TOPLEFT", container, "TOPLEFT", 6, -4)
    title:SetTextColor(0.4, 0.8, 1.0)
    title:SetText("Price History & Market Distribution (14-Day)")
    container.title = title

    -- Running Average Indicator Label
    local avgLabel = container:CreateFontString(nil, "OVERLAY")
    avgLabel:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    avgLabel:SetPoint("TOPRIGHT", container, "TOPRIGHT", -6, -4)
    avgLabel:SetTextColor(1.0, 0.84, 0.0)
    avgLabel:SetText("Run Avg: --")
    container.avgLabel = avgLabel

    -- Inner Plot Area
    local plotArea = CreateFrame("Frame", nil, container)
    plotArea:SetPoint("TOPLEFT", container, "TOPLEFT", 6, -18)
    plotArea:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -6, 6)
    container.plotArea = plotArea

    -- Running Average Horizontal Line
    local avgLine = plotArea:CreateTexture(nil, "OVERLAY")
    avgLine:SetTexture(Media:Fetch("texture", "Solid") or "Interface\\Buttons\\WHITE8X8")
    avgLine:SetVertexColor(1.0, 0.84, 0.0, 0.85)
    avgLine:SetHeight(1)
    avgLine:SetPoint("LEFT", plotArea, "LEFT", 0, 0)
    avgLine:SetPoint("RIGHT", plotArea, "RIGHT", 0, 0)
    avgLine:Hide()
    container.avgLine = avgLine

    -- Columns Setup
    local columns = {}
    local colSpacing = 2
    local totalPlotWidth = width - 12
    local colWidth = math.floor((totalPlotWidth - (colSpacing * (maxDays - 1))) / maxDays)
    if colWidth < 4 then colWidth = 4 end

    for i = 1, maxDays do
        local col = CreateFrame("Frame", nil, plotArea)
        col:SetWidth(colWidth)
        col:SetHeight(height - 24)
        col:SetPoint("BOTTOMLEFT", plotArea, "BOTTOMLEFT", (i - 1) * (colWidth + colSpacing), 0)
        col:EnableMouse(true)

        -- High Tier Bar (Red / Top)
        local highBar = col:CreateTexture(nil, "ARTWORK")
        highBar:SetTexture(Media:Fetch("texture", "Solid") or "Interface\\Buttons\\WHITE8X8")
        highBar:SetVertexColor(0.95, 0.30, 0.30, 0.85)
        highBar:SetPoint("TOPLEFT", col, "TOPLEFT", 0, 0)
        highBar:SetPoint("TOPRIGHT", col, "TOPRIGHT", 0, 0)
        highBar:SetHeight(0)
        col.highBar = highBar

        -- Core Median Band (Gold / Middle)
        local coreBar = col:CreateTexture(nil, "ARTWORK")
        coreBar:SetTexture(Media:Fetch("texture", "Solid") or "Interface\\Buttons\\WHITE8X8")
        coreBar:SetVertexColor(0.95, 0.80, 0.20, 0.90)
        coreBar:SetPoint("TOPLEFT", highBar, "BOTTOMLEFT", 0, 0)
        coreBar:SetPoint("TOPRIGHT", highBar, "BOTTOMRIGHT", 0, 0)
        coreBar:SetHeight(0)
        col.coreBar = coreBar

        -- Low Tier Bar (Green / Bottom)
        local lowBar = col:CreateTexture(nil, "ARTWORK")
        lowBar:SetTexture(Media:Fetch("texture", "Solid") or "Interface\\Buttons\\WHITE8X8")
        lowBar:SetVertexColor(0.20, 0.85, 0.35, 0.85)
        lowBar:SetPoint("TOPLEFT", coreBar, "BOTTOMLEFT", 0, 0)
        lowBar:SetPoint("TOPRIGHT", coreBar, "BOTTOMRIGHT", 0, 0)
        lowBar:SetPoint("BOTTOMLEFT", col, "BOTTOMLEFT", 0, 0)
        lowBar:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", 0, 0)
        col.lowBar = lowBar

        -- Column Hover Script
        col:SetScript("OnEnter", function()
            if not this.dayData then return end
            GameTooltip:SetOwner(this, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(string.format("|cff69ccf0Day %s|r", tostring(this.dayKey or "Unknown")))
            GameTooltip:AddDoubleLine("Total Scanned Volume:", string.format("|cffffffff%d items|r", this.dayData.totalVolume or 0))
            GameTooltip:AddDoubleLine("Daily Mean (Average):", Utils.FormatMoney(this.dayData.mean or 0))
            GameTooltip:AddDoubleLine("Core Fair Value (±15%):", string.format("%s - %s", Utils.FormatMoney(this.dayData.coreMin or 0), Utils.FormatMoney(this.dayData.coreMax or 0)))
            GameTooltip:AddDoubleLine("Core Cluster Volume:", string.format("|cffffd100%d items|r", this.dayData.coreVolume or 0))
            GameTooltip:AddDoubleLine("Low Tier (35% Sniping):", string.format("%s (|cff1eff00%d items|r)", Utils.FormatMoney(this.dayData.lowAvg or 0), this.dayData.lowVolume or 0))
            GameTooltip:AddDoubleLine("High Tier (35% Ceiling):", string.format("%s (|cffff4444%d items|r)", Utils.FormatMoney(this.dayData.highAvg or 0), this.dayData.highVolume or 0))
            GameTooltip:Show()
        end)
        col:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        columns[i] = col
    end

    container.columns = columns
    container.maxDays = maxDays

    return container
end

-- Update Graph Data with Item Metrics Record
function PUIMerchant:UpdateMarketBarGraph(graphFrame, itemMetrics)
    if not graphFrame or not graphFrame.columns then return end

    if not itemMetrics or not itemMetrics.history then
        graphFrame.title:SetText("No Historical Market Data")
        graphFrame.avgLabel:SetText("")
        graphFrame.avgLine:Hide()
        for i = 1, graphFrame.maxDays do
            graphFrame.columns[i].lowBar:SetHeight(0)
            graphFrame.columns[i].coreBar:SetHeight(0)
            graphFrame.columns[i].highBar:SetHeight(0)
            graphFrame.columns[i].dayData = nil
            graphFrame.columns[i]:Hide()
        end
        return
    end

    local cleanName = itemMetrics.name or "Item"
    graphFrame.title:SetText(string.format("|cffffffff%s|r Market Trend", cleanName))

    local runningAvg = itemMetrics.runningAvg7d or itemMetrics.latestMinBuyout or 0
    graphFrame.avgLabel:SetText(string.format("7d Avg: %s", Utils.FormatMoney(runningAvg)))

    -- Extract sorted day keys
    local dayKeys = {}
    for dayKey, _ in pairs(itemMetrics.history) do
        table.insert(dayKeys, dayKey)
    end
    table.sort(dayKeys)

    local numRecorded = table.getn(dayKeys)
    local startIdx = (numRecorded > graphFrame.maxDays) and (numRecorded - graphFrame.maxDays + 1) or 1

    -- Find maximum price ceiling across the displayed days to scale the graph
    local maxPrice = runningAvg
    for i = startIdx, numRecorded do
        local dKey = dayKeys[i]
        local dStat = itemMetrics.history[dKey]
        if dStat then
            if dStat.highMax and dStat.highMax > maxPrice then maxPrice = dStat.highMax end
            if dStat.highAvg and dStat.highAvg > maxPrice then maxPrice = dStat.highAvg end
            if dStat.coreMax and dStat.coreMax > maxPrice then maxPrice = dStat.coreMax end
            if dStat.mean and dStat.mean > maxPrice then maxPrice = dStat.mean end
        end
    end
    if maxPrice <= 0 then maxPrice = 1 end

    local plotH = graphFrame.plotArea:GetHeight()
    if plotH <= 0 then plotH = 60 end

    -- Position Running Average Horizontal Line
    if runningAvg > 0 then
        local avgY = math.floor((runningAvg / maxPrice) * plotH)
        if avgY < 1 then avgY = 1 end
        if avgY > plotH then avgY = plotH end
        graphFrame.avgLine:ClearAllPoints()
        graphFrame.avgLine:SetPoint("BOTTOMLEFT", graphFrame.plotArea, "BOTTOMLEFT", 0, avgY)
        graphFrame.avgLine:SetPoint("BOTTOMRIGHT", graphFrame.plotArea, "BOTTOMRIGHT", 0, avgY)
        graphFrame.avgLine:Show()
    else
        graphFrame.avgLine:Hide()
    end

    -- Render Columns
    local colIndex = 1
    for i = startIdx, numRecorded do
        local dKey = dayKeys[i]
        local dStat = itemMetrics.history[dKey]
        local col = graphFrame.columns[colIndex]

        if col and dStat and dStat.totalVolume and dStat.totalVolume > 0 then
            col.dayKey = dKey
            col.dayData = dStat

            local totalColH = math.floor((math.max(dStat.highAvg, dStat.mean) / maxPrice) * plotH)
            if totalColH < 4 then totalColH = 4 end
            if totalColH > plotH then totalColH = plotH end
            col:SetHeight(totalColH)

            local lowH = math.floor((dStat.lowAvg / maxPrice) * plotH)
            if lowH < 2 then lowH = 2 end
            if lowH > totalColH then lowH = totalColH end

            local coreH = math.floor(((dStat.coreMax - dStat.coreMin) / maxPrice) * plotH)
            if coreH < 2 then coreH = 2 end
            if (lowH + coreH) > totalColH then coreH = totalColH - lowH end
            if coreH < 1 then coreH = 1 end

            local highH = totalColH - lowH - coreH
            if highH < 0 then highH = 0 end

            col.highBar:SetHeight(highH)
            col.coreBar:SetHeight(coreH)
            col.lowBar:SetHeight(lowH)
            col:Show()

            colIndex = colIndex + 1
        end
    end

    -- Hide unused columns
    for i = colIndex, graphFrame.maxDays do
        local col = graphFrame.columns[i]
        if col then
            col.dayData = nil
            col:Hide()
        end
    end
end

-- =========================================================================
-- MINI SPARKLINE BUILDER (Compact 7-Day Strip for Tooltips & Tables)
-- =========================================================================

function PUIMerchant:CreateMiniSparkline(parent, width, height)
    parent = parent or UIParent
    width  = width or 120
    height = height or 20

    local spark = CreateFrame("Frame", NextGraphName("Sparkline"), parent)
    spark:SetWidth(width)
    spark:SetHeight(height)
    spark:SetBackdrop(Media:Fetch("border", "1Pixel"))
    spark:SetBackdropColor(0.04, 0.04, 0.06, 0.85)
    spark:SetBackdropBorderColor(0.18, 0.18, 0.22, 0.9)

    local numBars = 7
    local barSpacing = 1
    local barW = math.floor((width - 4 - (barSpacing * (numBars - 1))) / numBars)
    if barW < 2 then barW = 2 end

    local bars = {}
    for i = 1, numBars do
        local bar = spark:CreateTexture(nil, "ARTWORK")
        bar:SetTexture(Media:Fetch("texture", "Solid") or "Interface\\Buttons\\WHITE8X8")
        bar:SetVertexColor(0.20, 0.75, 1.0, 0.85)
        bar:SetWidth(barW)
        bar:SetHeight(2)
        bar:SetPoint("BOTTOMLEFT", spark, "BOTTOMLEFT", 2 + ((i - 1) * (barW + barSpacing)), 1)
        bars[i] = bar
    end
    spark.bars = bars
    spark.numBars = numBars

    return spark
end

function PUIMerchant:UpdateMiniSparkline(sparkFrame, itemMetrics)
    if not sparkFrame or not sparkFrame.bars then return end

    if not itemMetrics or not itemMetrics.history then
        for i = 1, sparkFrame.numBars do
            sparkFrame.bars[i]:SetHeight(1)
            sparkFrame.bars[i]:SetVertexColor(0.3, 0.3, 0.3, 0.5)
        end
        return
    end

    local dayKeys = {}
    for dayKey, _ in pairs(itemMetrics.history) do
        table.insert(dayKeys, dayKey)
    end
    table.sort(dayKeys)

    local numRecorded = table.getn(dayKeys)
    local startIdx = (numRecorded > sparkFrame.numBars) and (numRecorded - sparkFrame.numBars + 1) or 1

    local maxMean = 1
    for i = startIdx, numRecorded do
        local dStat = itemMetrics.history[dayKeys[i]]
        if dStat and dStat.mean and dStat.mean > maxMean then
            maxMean = dStat.mean
        end
    end

    local maxH = sparkFrame:GetHeight() - 2
    local barIndex = 1
    for i = startIdx, numRecorded do
        local dStat = itemMetrics.history[dayKeys[i]]
        local bar = sparkFrame.bars[barIndex]
        if bar and dStat and dStat.mean then
            local h = math.floor((dStat.mean / maxMean) * maxH)
            if h < 2 then h = 2 end
            if h > maxH then h = maxH end
            bar:SetHeight(h)
            bar:SetVertexColor(0.20, 0.75, 1.0, 0.85)
            barIndex = barIndex + 1
        end
    end

    for i = barIndex, sparkFrame.numBars do
        sparkFrame.bars[i]:SetHeight(1)
        sparkFrame.bars[i]:SetVertexColor(0.2, 0.2, 0.2, 0.4)
    end
end
