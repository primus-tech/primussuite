--[[
    PrimusUI Module: PUIHotbars - Multi-Faction XP & Reputation Watchbar Engine
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Features:
    1. Silent Character Sheet Poller:
       - Non-destructively scans ReputationFrame, temporarily expanding collapsed
         headers and restoring them, discovering 100% of character factions without
         disrupting UI state.
    2. Multi-Track Presentation Modes:
       - Mode A (Stacked): XP bar (1-59) + up to 4 stacked faction reputation bars.
       - Mode B (Cycle): Single adaptive bar with Left-Click / MouseWheel cycling.
       - Mode C (Split): Dual-tier layout (active faction on top, XP on bottom).
    3. Session Reputation Telemetry:
       - Intercepts CHAT_MSG_COMBAT_FACTION_CHANGE to track session deltas (+/- rep).
       - Auto-focus on reputation gains.
    4. Interactive Quick-Select Menu:
       - Right-click popup checklist to toggle tracked factions on the fly.
    5. Shift-Click Chat Announcer & Dual-Column Rich Tooltip.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIHotbars = Primus.PUIHotbars or {}
Primus.PUIHotbars = PUIHotbars

local Media    = Primus.Media
local Utils    = Primus.Utils
local DB       = Primus.DB
local PUIMover = Primus.PUIMover
local Memory   = Primus.Memory
local Anim     = Primus.Anim
local Events   = Primus.Events

-- =========================================================================
-- REPUTATION STANDING THEMES & CONSTANTS
-- =========================================================================

local STANDING_COLORS = {
    [1] = { r = 0.80, g = 0.20, b = 0.20, hex = "cc3333", label = "Hated" },
    [2] = { r = 0.80, g = 0.30, b = 0.22, hex = "cc4d38", label = "Hostile" },
    [3] = { r = 0.75, g = 0.27, b = 0.00, hex = "c04500", label = "Unfriendly" },
    [4] = { r = 0.90, g = 0.70, b = 0.00, hex = "e6b300", label = "Neutral" },
    [5] = { r = 0.00, g = 0.60, b = 0.10, hex = "009919", label = "Friendly" },
    [6] = { r = 0.00, g = 0.70, b = 0.20, hex = "00b333", label = "Honored" },
    [7] = { r = 0.00, g = 0.80, b = 0.40, hex = "00cc66", label = "Revered" },
    [8] = { r = 0.00, g = 0.90, b = 0.70, hex = "00e6b8", label = "Exalted" },
}

PUIHotbars.STANDING_COLORS = STANDING_COLORS

-- Internal Telemetry & Cache
local knownFactions   = {}  -- [factionName] = dataTable
local orderedFactions = {}  -- Array of faction names
local sessionGains    = {}  -- [factionName] = totalSessionRep
local activeCycleIdx  = 1

local xpBarContainer  = nil
local xpBarFrame      = nil
local restedBarFrame  = nil
local repBarPool      = {}  -- [1..4] status bar frames
local quickMenuFrame  = nil

-- =========================================================================
-- SILENT CHARACTER SHEET REPUTATION TAB POLLER
-- =========================================================================

function PUIHotbars:ScanFactions()
    local numFactions = GetNumFactions()
    if not numFactions or numFactions <= 0 then return knownFactions end

    -- 1. Acquire temporary table to record initially collapsed headers
    local collapsed = Memory:AcquireTable()
    for i = 1, numFactions do
        local name, _, _, _, _, _, _, _, isHeader, isCollapsed = GetFactionInfo(i)
        if isHeader and isCollapsed then
            table.insert(collapsed, name)
        end
    end

    -- 2. Temporarily expand all collapsed headers synchronously
    if table.getn(collapsed) > 0 then
        for i = 1, GetNumFactions() do
            local name, _, _, _, _, _, _, _, isHeader, isCollapsed = GetFactionInfo(i)
            if isHeader and isCollapsed then
                ExpandFactionHeader(i)
            end
        end
    end

    -- 3. Read full expanded faction catalog
    local total = GetNumFactions()
    local currentHeader = "Other"
    Utils.Wipe(orderedFactions)

    for i = 1, total do
        local name, desc, standingID, barMin, barMax, barValue, atWarWith, canToggleAtWar, isHeader, isCollapsed, isWatched = GetFactionInfo(i)
        if isHeader then
            currentHeader = name or "Other"
        elseif name then
            local span = (barMax or 1) - (barMin or 0)
            if span <= 0 then span = 1 end
            local val = (barValue or 0) - (barMin or 0)
            if val < 0 then val = 0 end
            local pct = Utils.Round((val / span) * 100, 1)

            local gender = UnitSex("player")
            local standingText = (GetText and GetText("FACTION_STANDING_LABEL" .. (standingID or 4), gender)) 
                or (STANDING_COLORS[standingID] and STANDING_COLORS[standingID].label) 
                or "Neutral"

            local data = knownFactions[name] or {}
            data.name           = name
            data.category       = currentHeader
            data.standingID     = standingID or 4
            data.standingText   = standingText
            data.min            = barMin or 0
            data.max            = barMax or 1
            data.cur            = barValue or 0
            data.normalizedVal  = val
            data.normalizedMax  = span
            data.pct            = pct
            data.atWarWith      = atWarWith
            data.canToggleAtWar = canToggleAtWar
            data.isWatched      = isWatched
            knownFactions[name] = data

            table.insert(orderedFactions, name)
        end
    end

    -- 4. Restore initial header collapse state so player's UI is untouched
    if table.getn(collapsed) > 0 then
        for c = 1, table.getn(collapsed) do
            local collName = collapsed[c]
            for i = 1, GetNumFactions() do
                local name, _, _, _, _, _, _, _, isHeader = GetFactionInfo(i)
                if isHeader and name == collName then
                    CollapseFactionHeader(i)
                    break
                end
            end
        end
    end

    Memory:ReleaseTable(collapsed)
    return knownFactions
end

function PUIHotbars:GetKnownFactions()
    if table.getn(orderedFactions) == 0 then
        self:ScanFactions()
    end
    return knownFactions, orderedFactions
end

-- =========================================================================
-- TRACKED FACTION MANAGEMENT & TELEMETRY
-- =========================================================================

function PUIHotbars:GetTrackedFactionsList()
    local hotbarsDB = DB:GetNamespace("PUIHotbars")
    local tracked = hotbarsDB and hotbarsDB:Get("trackedFactions") or {}
    local list = Memory:AcquireTable()
    
    for i = 1, table.getn(orderedFactions) do
        local fName = orderedFactions[i]
        if tracked[fName] and knownFactions[fName] then
            table.insert(list, fName)
        end
    end
    
    -- If no faction manually tracked, fallback to Blizzard's watched faction
    if table.getn(list) == 0 then
        local wName = GetWatchedFactionInfo()
        if wName and knownFactions[wName] then
            table.insert(list, wName)
        end
    end
    return list
end

function PUIHotbars:ToggleTrackedFaction(factionName)
    if not factionName then return end
    local hotbarsDB = DB:GetNamespace("PUIHotbars")
    if not hotbarsDB then return end
    
    local tracked = hotbarsDB:Get("trackedFactions") or {}
    local newTracked = Utils.Copy(tracked)
    
    if newTracked[factionName] then
        newTracked[factionName] = nil
    else
        newTracked[factionName] = true
    end
    
    hotbarsDB:Set("trackedFactions", newTracked)
    self:UpdateXP()
    if quickMenuFrame and quickMenuFrame:IsShown() then
        self:RefreshQuickMenu()
    end
end

function PUIHotbars:IsFactionTracked(factionName)
    local hotbarsDB = DB:GetNamespace("PUIHotbars")
    local tracked = hotbarsDB and hotbarsDB:Get("trackedFactions") or {}
    return tracked[factionName] == true
end

function PUIHotbars:OnReputationGained(factionName, amount)
    if not factionName then return end
    local hotbarsDB = DB:GetNamespace("PUIHotbars")
    
    -- Auto switch active watched faction on gain
    if hotbarsDB and hotbarsDB:Get("autoSwitchOnGain", true) then
        hotbarsDB:Set("activeFaction", factionName)
        local tracked = hotbarsDB:Get("trackedFactions") or {}
        if not tracked[factionName] then
            local newTracked = Utils.Copy(tracked)
            newTracked[factionName] = true
            hotbarsDB:Set("trackedFactions", newTracked)
        end
    end
    
    self:ScanFactions()
    self:UpdateXP()
end

-- =========================================================================
-- XP & REPUTATION BAR ARRAY BUILDER
-- =========================================================================

local function CreateSingleStatusBar(parent, namePrefix)
    local bar = CreateFrame("StatusBar", namePrefix, parent)
    bar:SetStatusBarTexture(Media:Fetch("statusbar", "Default"))
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    bar:EnableMouse(false)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetTexture(Media:Fetch("statusbar", "Default"))
    bg:SetVertexColor(0.08, 0.08, 0.10, 0.85)
    bar.bg = bg

    local border = CreateFrame("Frame", nil, bar)
    border:SetAllPoints(bar)
    border:SetBackdrop(Media:Fetch("border", "1Pixel"))
    border:SetBackdropColor(0, 0, 0, 0)
    border:SetBackdropBorderColor(0.25, 0.25, 0.30, 1.0)
    bar.border = border

    local text = bar:CreateFontString(nil, "OVERLAY")
    text:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    text:SetTextColor(1, 1, 1)
    bar.text = text

    return bar
end

function PUIHotbars:BuildXPBar()
    if xpBarContainer then return xpBarContainer end

    local hotbarsDB = DB:GetNamespace("PUIHotbars")
    local size      = hotbarsDB and hotbarsDB:Get("buttonSize", 36) or 36
    local spacing   = hotbarsDB and hotbarsDB:Get("buttonSpacing", 4) or 4
    local cols      = hotbarsDB and hotbarsDB:Get("bar1Cols", 12) or 12
    local width     = cols * size + (cols - 1) * spacing
    local height    = hotbarsDB and hotbarsDB:Get("xpHeight", 8) or 8

    -- Master Container Frame (Movable Anchor)
    xpBarContainer = CreateFrame("Frame", "Primus_PUIHotbars_XPBar", UIParent)
    xpBarContainer:SetWidth(width)
    xpBarContainer:SetHeight(height)
    xpBarContainer:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 4)
    xpBarContainer:EnableMouse(true)
    xpBarContainer:EnableMouseWheel(true)

    -- 1. Rested XP Sub-Bar (Underneath Main XP)
    restedBarFrame = CreateSingleStatusBar(xpBarContainer, "Primus_PUIHotbars_RestedBar")
    restedBarFrame:SetStatusBarColor(0.30, 0.40, 0.80, 0.50)
    restedBarFrame:SetFrameLevel(xpBarContainer:GetFrameLevel() + 1)
    xpBarContainer.restedBar = restedBarFrame

    -- 2. Main XP Status Bar
    xpBarFrame = CreateSingleStatusBar(xpBarContainer, "Primus_PUIHotbars_MainXPBar")
    xpBarFrame:SetStatusBarColor(0.58, 0.30, 0.85, 1.0)
    xpBarFrame:SetFrameLevel(xpBarContainer:GetFrameLevel() + 2)
    xpBarContainer.mainBar = xpBarFrame

    -- 3. Reputation Status Bar Pool (Up to 4 stacked bars)
    for i = 1, 4 do
        local repBar = CreateSingleStatusBar(xpBarContainer, "Primus_PUIHotbars_RepBar" .. i)
        repBar:SetFrameLevel(xpBarContainer:GetFrameLevel() + 3 + i)
        repBar:Hide()
        table.insert(repBarPool, repBar)
    end
    xpBarContainer.repBars = repBarPool

    -- Tooltip & Mouse Interaction Handlers
    xpBarContainer:SetScript("OnEnter", function()
        PUIHotbars:ShowXPTooltip(this)
    end)

    xpBarContainer:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    xpBarContainer:SetScript("OnMouseUp", function()
        if arg1 == "RightButton" then
            PUIHotbars:ToggleQuickMenu(this)
        elseif arg1 == "LeftButton" then
            if IsShiftKeyDown() then
                PUIHotbars:AnnounceProgress()
            else
                PUIHotbars:CycleActiveFaction(1)
            end
        end
    end)

    xpBarContainer:SetScript("OnMouseWheel", function()
        if arg1 > 0 then
            PUIHotbars:CycleActiveFaction(-1)
        else
            PUIHotbars:CycleActiveFaction(1)
        end
    end)

    -- Register with PUIMover
    local mover = PUIMover or Primus.PUIMover
    if mover and mover.Register then
        mover:Register(xpBarContainer, "PUIHotbars_XP", "PUIHotbars: XP & Reputation Bar", "BARS")
    end

    self.xpBarFrame = xpBarContainer
    return xpBarContainer
end

function PUIHotbars:GetXPBar()
    return xpBarContainer or self:BuildXPBar()
end

-- =========================================================================
-- REAL-TIME DATA UPDATE & PRESENTATION MODES
-- =========================================================================

function PUIHotbars:CycleActiveFaction(delta)
    local hotbarsDB = DB:GetNamespace("PUIHotbars")
    local mode = hotbarsDB and hotbarsDB:Get("repDisplayMode", "STACKED") or "STACKED"
    
    local list = self:GetTrackedFactionsList()
    local count = table.getn(list)
    if count == 0 then
        Memory:ReleaseTable(list)
        return
    end

    activeCycleIdx = activeCycleIdx + (delta or 1)
    if activeCycleIdx > count then activeCycleIdx = 1 end
    if activeCycleIdx < 1 then activeCycleIdx = count end

    local chosen = list[activeCycleIdx]
    if hotbarsDB and chosen then
        hotbarsDB:Set("activeFaction", chosen)
    end
    Memory:ReleaseTable(list)
    
    self:UpdateXP()
end

function PUIHotbars:UpdateXP()
    if not xpBarContainer then return end

    local hotbarsDB = DB:GetNamespace("PUIHotbars")
    local enabled   = hotbarsDB and hotbarsDB:Get("showXPBar", true)
    if not enabled then
        xpBarContainer:Hide()
        return
    end

    self:ScanFactions()

    local level       = UnitLevel("player") or 1
    local mode        = hotbarsDB and hotbarsDB:Get("repDisplayMode", "STACKED") or "STACKED"
    local forceShowXP = hotbarsDB and hotbarsDB:Get("forceShowXP", false) or false
    local xpHeight    = hotbarsDB and hotbarsDB:Get("xpHeight", 8) or 8
    local repHeight   = hotbarsDB and hotbarsDB:Get("repBarHeight", 8) or 8
    local repSpacing  = hotbarsDB and hotbarsDB:Get("repSpacing", 2) or 2
    local maxStacked  = hotbarsDB and hotbarsDB:Get("maxStackedBars", 2) or 2
    local textFmt     = hotbarsDB and hotbarsDB:Get("textDisplayMode", "VERBOSE") or "VERBOSE"
    local showXP      = (level < 60 or forceShowXP)

    local trackedList = self:GetTrackedFactionsList()
    local totalTracked = table.getn(trackedList)
    local totalHeight = 0

    -- ---------------------------------------------------------------------
    -- 1. Main XP & Rested Status Bar Update
    -- ---------------------------------------------------------------------
    if showXP then
        local curXP  = UnitXP("player") or 0
        local maxXP  = UnitXPMax("player") or 1
        local restXP = GetXPExhaustion() or 0

        xpBarFrame:ClearAllPoints()
        xpBarFrame:SetPoint("TOPLEFT", xpBarContainer, "TOPLEFT", 0, 0)
        xpBarFrame:SetPoint("TOPRIGHT", xpBarContainer, "TOPRIGHT", 0, 0)
        xpBarFrame:SetHeight(xpHeight)
        xpBarFrame:SetMinMaxValues(0, maxXP)
        if Anim and Anim.SmoothBar then
            Anim:SmoothBar(xpBarFrame, curXP, 0.25)
        else
            xpBarFrame:SetValue(curXP)
        end
        xpBarFrame:SetStatusBarColor(0.58, 0.30, 0.85, 1.0)
        xpBarFrame:Show()

        restedBarFrame:ClearAllPoints()
        restedBarFrame:SetPoint("TOPLEFT", xpBarFrame, "TOPLEFT", 0, 0)
        restedBarFrame:SetPoint("BOTTOMRIGHT", xpBarFrame, "BOTTOMRIGHT", 0, 0)
        if restXP > 0 then
            restedBarFrame:SetMinMaxValues(0, maxXP)
            restedBarFrame:SetValue(math.min(maxXP, curXP + restXP))
            restedBarFrame:Show()
        else
            restedBarFrame:Hide()
        end

        local xpPct = maxXP > 0 and math.floor((curXP / maxXP) * 100) or 0
        if textFmt == "PERCENT" then
            xpBarFrame.text:SetText(string.format("XP: %d%%", xpPct))
        elseif textFmt == "VALUES" then
            xpBarFrame.text:SetText(string.format("%s / %s", Utils.FormatNumber(curXP), Utils.FormatNumber(maxXP)))
        elseif textFmt == "HOVER_ONLY" then
            xpBarFrame.text:SetText("")
        else
            if restXP > 0 then
                xpBarFrame.text:SetText(string.format("XP: %s / %s (%d%%) [Rested: +%s]", Utils.FormatNumber(curXP), Utils.FormatNumber(maxXP), xpPct, Utils.FormatNumber(restXP)))
            else
                xpBarFrame.text:SetText(string.format("XP: %s / %s (%d%%)", Utils.FormatNumber(curXP), Utils.FormatNumber(maxXP), xpPct))
            end
        end
        totalHeight = totalHeight + xpHeight
    else
        xpBarFrame:Hide()
        restedBarFrame:Hide()
    end

    -- ---------------------------------------------------------------------
    -- 2. Reputation Status Bars Rendering (Stacked / Cycle / Split)
    -- ---------------------------------------------------------------------
    for i = 1, 4 do
        repBarPool[i]:Hide()
    end

    if mode == "STACKED" then
        local numToDisplay = math.min(maxStacked, totalTracked)
        local prevAnchor = showXP and xpBarFrame or nil

        for i = 1, numToDisplay do
            local fName = trackedList[i]
            local fData = knownFactions[fName]
            local repBar = repBarPool[i]

            if fData and repBar then
                repBar:ClearAllPoints()
                if prevAnchor then
                    repBar:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -repSpacing)
                    repBar:SetPoint("TOPRIGHT", prevAnchor, "BOTTOMRIGHT", 0, -repSpacing)
                else
                    repBar:SetPoint("TOPLEFT", xpBarContainer, "TOPLEFT", 0, 0)
                    repBar:SetPoint("TOPRIGHT", xpBarContainer, "TOPRIGHT", 0, 0)
                end
                repBar:SetHeight(repHeight)

                local color = STANDING_COLORS[fData.standingID] or STANDING_COLORS[4]
                repBar:SetMinMaxValues(0, fData.normalizedMax)
                if Anim and Anim.SmoothBar then
                    Anim:SmoothBar(repBar, fData.normalizedVal, 0.25)
                else
                    repBar:SetValue(fData.normalizedVal)
                end
                repBar:SetStatusBarColor(color.r, color.g, color.b, 1.0)

                local sGain = sessionGains[fName] and sessionGains[fName] ~= 0 and string.format(" [%s%d|r]", sessionGains[fName] > 0 and "|cff00ff00+" or "|cffff3333", sessionGains[fName]) or ""
                if textFmt == "PERCENT" then
                    repBar.text:SetText(string.format("%s: %s (%.1f%%)", fName, fData.standingText, fData.pct))
                elseif textFmt == "VALUES" then
                    repBar.text:SetText(string.format("%s: %s / %s", fName, Utils.FormatNumber(fData.normalizedVal), Utils.FormatNumber(fData.normalizedMax)))
                elseif textFmt == "HOVER_ONLY" then
                    repBar.text:SetText("")
                else
                    repBar.text:SetText(string.format("%s: %s %s / %s (%.1f%%)%s", fName, fData.standingText, Utils.FormatNumber(fData.normalizedVal), Utils.FormatNumber(fData.normalizedMax), fData.pct, sGain))
                end

                repBar:Show()
                prevAnchor = repBar
                totalHeight = totalHeight + repHeight + (prevAnchor and repSpacing or 0)
            end
        end

    elseif mode == "CYCLE" or mode == "SPLIT" then
        local activeFaction = hotbarsDB and hotbarsDB:Get("activeFaction")
        if not activeFaction or not knownFactions[activeFaction] then
            activeFaction = trackedList[1] or GetWatchedFactionInfo()
        end

        local fData = knownFactions[activeFaction]
        local repBar = repBarPool[1]

        if fData and repBar then
            repBar:ClearAllPoints()
            if showXP then
                repBar:SetPoint("TOPLEFT", xpBarFrame, "BOTTOMLEFT", 0, -repSpacing)
                repBar:SetPoint("TOPRIGHT", xpBarFrame, "BOTTOMRIGHT", 0, -repSpacing)
                totalHeight = totalHeight + repHeight + repSpacing
            else
                repBar:SetPoint("TOPLEFT", xpBarContainer, "TOPLEFT", 0, 0)
                repBar:SetPoint("TOPRIGHT", xpBarContainer, "TOPRIGHT", 0, 0)
                totalHeight = totalHeight + repHeight
            end
            repBar:SetHeight(repHeight)

            local color = STANDING_COLORS[fData.standingID] or STANDING_COLORS[4]
            repBar:SetMinMaxValues(0, fData.normalizedMax)
            if Anim and Anim.SmoothBar then
                Anim:SmoothBar(repBar, fData.normalizedVal, 0.25)
            else
                repBar:SetValue(fData.normalizedVal)
            end
            repBar:SetStatusBarColor(color.r, color.g, color.b, 1.0)

            local sGain = sessionGains[activeFaction] and sessionGains[activeFaction] ~= 0 and string.format(" [%s%d|r]", sessionGains[activeFaction] > 0 and "|cff00ff00+" or "|cffff3333", sessionGains[activeFaction]) or ""
            repBar.text:SetText(string.format("[%d/%d] %s: %s %s / %s (%.1f%%)%s", activeCycleIdx, math.max(1, totalTracked), fData.name, fData.standingText, Utils.FormatNumber(fData.normalizedVal), Utils.FormatNumber(fData.normalizedMax), fData.pct, sGain))
            repBar:Show()
        end
    end

    Memory:ReleaseTable(trackedList)
    xpBarContainer:SetHeight(math.max(8, totalHeight))
    xpBarContainer:Show()
end

-- =========================================================================
-- TOOLTIP & CHAT ANNOUNCER
-- =========================================================================

function PUIHotbars:ShowXPTooltip(ownerFrame)
    local level = UnitLevel("player") or 1
    GameTooltip:SetOwner(ownerFrame or xpBarContainer, "ANCHOR_TOP")
    GameTooltip:ClearLines()

    -- 1. Leveling Stats (Level < 60 or forced)
    local curXP  = UnitXP("player") or 0
    local maxXP  = UnitXPMax("player") or 1
    local restXP = GetXPExhaustion() or 0
    local xpPct  = maxXP > 0 and (curXP / maxXP) * 100 or 0

    if level < 60 then
        GameTooltip:AddLine(string.format("Level %d Experience", level), 1, 0.85, 0.1)
        GameTooltip:AddDoubleLine("Current XP:", string.format("%s / %s (%.1f%%)", Utils.FormatNumber(curXP), Utils.FormatNumber(maxXP), xpPct), 1, 1, 1, 0.8, 0.8, 0.8)
        GameTooltip:AddDoubleLine("Remaining:", Utils.FormatNumber(maxXP - curXP), 1, 1, 1, 1, 0.4, 0.4)
        if restXP > 0 then
            local restPct = (restXP / maxXP) * 100
            local restBars = Utils.Round(restXP / (maxXP * 0.05), 1)
            GameTooltip:AddDoubleLine("Rested Bonus:", string.format("%s (%.1f%% | %.1f bars)", Utils.FormatNumber(restXP), restPct, restBars), 0.3, 0.8, 1.0, 0.3, 0.8, 1.0)
        end
    else
        GameTooltip:AddLine("Character Status (Level 60 - Max Level)", 1, 0.85, 0.1)
    end

    -- 2. Tracked Factions Overview Table
    local trackedList = self:GetTrackedFactionsList()
    local tCount = table.getn(trackedList)

    if tCount > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Utils.ColorText("Tracked Factions:", "69ccf0"), 1, 1, 1)
        for i = 1, tCount do
            local fName = trackedList[i]
            local data = knownFactions[fName]
            if data then
                local col = STANDING_COLORS[data.standingID] or STANDING_COLORS[4]
                local sGain = sessionGains[fName] and sessionGains[fName] ~= 0 and string.format(" (%s%d|r)", sessionGains[fName] > 0 and "|cff00ff00+" or "|cffff3333", sessionGains[fName]) or ""
                GameTooltip:AddDoubleLine(
                    string.format("|cff%s%s|r", col.hex, fName),
                    string.format("%s: %s / %s (%.1f%%)%s", data.standingText, Utils.FormatNumber(data.normalizedVal), Utils.FormatNumber(data.normalizedMax), data.pct, sGain),
                    1, 1, 1, col.r, col.g, col.b
                )
            end
        end
    else
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Utils.ColorText("No factions tracked. Right-click bar to select.", "888888"), 0.8, 0.8, 0.8)
    end

    Memory:ReleaseTable(trackedList)

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(Utils.ColorText("<Left-Click>: Cycle Tracked | <Right-Click>: Faction Menu | <Shift-Click>: Link to Chat", "69ccf0"), 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function PUIHotbars:AnnounceProgress()
    local level = UnitLevel("player") or 1
    local hotbarsDB = DB:GetNamespace("PUIHotbars")
    local activeFaction = hotbarsDB and hotbarsDB:Get("activeFaction")
    local fData = activeFaction and knownFactions[activeFaction]
    
    local msg = ""
    if fData then
        local sGain = sessionGains[fData.name] and sessionGains[fData.name] ~= 0 and string.format(" [Session: %+d]", sessionGains[fData.name]) or ""
        msg = string.format("[PrimusUI] %s: %s %s / %s (%.1f%%)%s", fData.name, fData.standingText, Utils.FormatNumber(fData.normalizedVal), Utils.FormatNumber(fData.normalizedMax), fData.pct, sGain)
    else
        local curXP  = UnitXP("player") or 0
        local maxXP  = UnitXPMax("player") or 1
        local xpPct  = maxXP > 0 and (curXP / maxXP) * 100 or 0
        msg = string.format("[PrimusUI] Level %d Experience: %s / %s (%.1f%%)", level, Utils.FormatNumber(curXP), Utils.FormatNumber(maxXP), xpPct)
    end

    if ChatFrameEditBox and ChatFrameEditBox:IsShown() then
        ChatFrameEditBox:Insert(msg)
    else
        -- Send to Party, Guild, or Say
        local chan = "SAY"
        if GetNumRaidMembers() > 0 then chan = "RAID"
        elseif GetNumPartyMembers() > 0 then chan = "PARTY"
        elseif IsInGuild() then chan = "GUILD" end
        SendChatMessage(msg, chan)
    end
end

-- =========================================================================
-- INTERACTIVE RIGHT-CLICK QUICK FACTION PICKER MENU (Widgets:ShowContextMenu)
-- =========================================================================

function PUIHotbars:ToggleQuickMenu(anchorFrame)
    if Widgets and Widgets.IsContextMenuShown and Widgets:IsContextMenuShown() then
        Widgets:HideContextMenu()
        return
    end

    self:ScanFactions()
    local items = {}
    table.insert(items, { text = "TRACKED FACTIONS", isTitle = true })
    table.insert(items, { isSeparator = true })

    local total = table.getn(orderedFactions)
    if total == 0 then
        table.insert(items, { text = "No Factions Discovered", disabled = true })
    else
        for i = 1, total do
            local fName = orderedFactions[i]
            local fData = knownFactions[fName]
            if fData then
                local isChecked = self:IsFactionTracked(fName)
                local col = STANDING_COLORS[fData.standingID] or STANDING_COLORS[4]
                table.insert(items, {
                    text = fName,
                    rightText = string.format("%s (%.0f%%)", fData.standingText, fData.pct),
                    checked = isChecked,
                    keepShown = true,
                    func = function()
                        PUIHotbars:ToggleTrackedFaction(fName)
                        PUIHotbars:ToggleQuickMenu(anchorFrame)
                    end,
                })
            end
        end
    end

    table.insert(items, { isSeparator = true })
    local hotbarsDB = DB:GetNamespace("PUIHotbars")
    local isAutoTrack = hotbarsDB and hotbarsDB:Get("autoTrackRep", true)
    table.insert(items, {
        text = "Auto-Track on Gain",
        checked = isAutoTrack,
        keepShown = true,
        func = function()
            if hotbarsDB then
                hotbarsDB:Set("autoTrackRep", not isAutoTrack)
                PUIHotbars:ToggleQuickMenu(anchorFrame)
            end
        end
    })

    if Widgets and Widgets.ShowContextMenu then
        Widgets:ShowContextMenu(anchorFrame or xpBarContainer, items, {
            point = "BOTTOM",
            relPoint = "TOP",
            yOffset = 8,
            minWidth = 240,
        })
    end
end

-- =========================================================================
-- REPUTATION EVENT LISTENER
-- =========================================================================

Events:Register("CHAT_MSG_COMBAT_FACTION_CHANGE", PUIHotbars, function(event, msg)
    if not msg then return end
    local _, _, fNameInc, amtInc = string.find(msg, "Reputation with (.+) increased by (%d+)")
    if fNameInc and amtInc then
        PUIHotbars:OnReputationGained(fNameInc, tonumber(amtInc) or 0)
        return
    end

    local _, _, fNameDec, amtDec = string.find(msg, "Reputation with (.+) decreased by (%d+)")
    if fNameDec and amtDec then
        PUIHotbars:OnReputationGained(fNameDec, -(tonumber(amtDec) or 0))
        return
    end
end)
