--[[
    PrimusUI Module: PUIQuestWatch (Bulletproof Quest Objective Tracker & Persistence Engine)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Features:
    1. Foldable Quest Tracker with Sleek Title Bar:
       - 1-Click Fold/Unfold button ([−] / [+]) and interactive title bar.
       - Displays active tracked count badge: Quests (3).
       - Fully persistent collapsed state across sessions and /reload.
    2. Permanent Quest Tracking: Fixes Blizzard's 5-minute AutoQuestWatch expiration bug and tremove table key bug.
    3. Title-Based SavedVariables Persistence: Retains tracked quests across sessions, /reload, and quest log index shifts.
    4. Multi-Anchor Conflict Fix: Prevents UIParent_ManageFramePositions from dual-anchoring and distorting QuestWatchFrame.
    5. Enhanced Visuals:
       - Difficulty-colored quest titles with level brackets: [11] Quest Title.
       - Clean objective status bullets with (Complete) highlights.
       - Displays "Ready for turn-in" for quests without leaderboards so they never disappear on completion.
    6. Interactive Clickable Headers:
       - Left-Click on quest header: Opens Quest Log and selects that quest.
       - Shift-Click on quest header: Inserts quest link in chat or untracks quest.
       - Alt-Click on quest header: Locks Navigation Arrow / Route on that quest.
    7. Zen Engine & PUIMover Integration:
       - Works smoothly with State.lua / Hider.lua combat fading and hover-to-peek.
       - Full support for PUIMover custom positioning without position snapping.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIQuestWatch = Primus.PUIQuestWatch or {}
Primus.PUIQuestWatch = PUIQuestWatch
_G.PUIQuestWatch = PUIQuestWatch
Primus:RegisterModule("PUIQuestWatch", PUIQuestWatch, "Player")

local DB       = Primus.DB
local Utils    = Primus.Utils
local Events   = Primus.Events
local Media    = Primus.Media
local PUIMover = Primus.PUIMover

-- Persistent Database for Quest Tracking
local questDB = DB:RegisterNamespace("PUIQuestWatch", {
    enabled               = true,
    trackedQuests         = {},     -- [questTitle] = true
    isCollapsed           = false,  -- Folded / Minimized state
    showTitleBar          = true,   -- Display sleek title bar header
    autoWatchNew          = true,   -- Automatically watch newly accepted quests
    autoWatchProgress     = true,   -- Automatically watch quests when objectives update
    showLevels            = true,   -- Display [Level] in front of quest titles
    maxWatches            = 10,     -- Support up to 10 watched quests
    lineSpacing           = 2,      -- Spacing between objective lines
    questSpacing          = 6,      -- Spacing between distinct quests
})

-- Internal Runtime State
PUIQuestWatch.headerButtons    = {}
PUIQuestWatch.allocatedLines   = 25
PUIQuestWatch.isReconciling    = false
PUIQuestWatch.isInitialized    = false
PUIQuestWatch.knownQuests      = {}
PUIQuestWatch.titleBar         = nil

-- Quest Difficulty Colors (Matches Blizzard standard with refined contrast)
local DIFFICULTY_COLORS = {
    ["impossible"]    = { r = 1.00, g = 0.15, b = 0.15 }, -- Red (+5 or higher)
    ["verydifficult"] = { r = 1.00, g = 0.50, b = 0.20 }, -- Orange (+3 to +4)
    ["difficult"]     = { r = 1.00, g = 0.85, b = 0.10 }, -- Yellow (-2 to +2)
    ["standard"]      = { r = 0.25, g = 0.85, b = 0.25 }, -- Green (Green range)
    ["trivial"]       = { r = 0.60, g = 0.60, b = 0.60 }, -- Gray (Trivial / Low level)
    ["header"]        = { r = 0.90, g = 0.80, b = 0.50 }, -- Gold Header
}

-- =========================================================================
-- UTILITY & LOOKUP HELPERS
-- =========================================================================

function PUIQuestWatch:GetQuestColor(level)
    if not level or level <= 0 then
        return DIFFICULTY_COLORS["standard"]
    end
    local playerLevel = UnitLevel("player") or 1
    local levelDiff = level - playerLevel
    if levelDiff >= 5 then
        return DIFFICULTY_COLORS["impossible"]
    elseif levelDiff >= 3 then
        return DIFFICULTY_COLORS["verydifficult"]
    elseif levelDiff >= -2 then
        return DIFFICULTY_COLORS["difficult"]
    elseif -levelDiff <= (GetQuestGreenRange and GetQuestGreenRange() or 5) then
        return DIFFICULTY_COLORS["standard"]
    else
        return DIFFICULTY_COLORS["trivial"]
    end
end

function PUIQuestWatch:FindQuestLogIndex(targetTitle)
    if not targetTitle or targetTitle == "" then return nil end
    local numEntries = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, level, questTag, isHeader, isCollapsed, isComplete = GetQuestLogTitle(i)
        if not isHeader and title and title == targetTitle then
            return i, level, questTag, isComplete
        end
    end
    return nil
end

-- =========================================================================
-- PERSISTENCE & TRACKING ENGINE
-- =========================================================================

function PUIQuestWatch:GetTrackedList()
    local list = questDB:Get("trackedQuests")
    if type(list) ~= "table" then
        list = {}
        questDB:Set("trackedQuests", list)
    end
    return list
end

function PUIQuestWatch:IsTracked(questIndexOrTitle)
    local title = questIndexOrTitle
    if type(questIndexOrTitle) == "number" then
        title = GetQuestLogTitle(questIndexOrTitle)
    end
    if not title then return false end
    local tracked = self:GetTrackedList()
    return tracked[title] == true
end

function PUIQuestWatch:TrackQuest(questIndexOrTitle)
    local questIndex, title
    if type(questIndexOrTitle) == "number" then
        questIndex = questIndexOrTitle
        title = GetQuestLogTitle(questIndex)
    else
        title = questIndexOrTitle
        questIndex = self:FindQuestLogIndex(title)
    end

    if not title or title == "" then return false end

    local tracked = self:GetTrackedList()
    local maxWatches = questDB:Get("maxWatches", 10)

    local count = 0
    for _ in pairs(tracked) do count = count + 1 end

    if count >= maxWatches and not tracked[title] then
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage(string.format("Quest Tracker: Cannot track more than %d quests.", maxWatches), 1.0, 0.2, 0.2, 1.0)
        end
        return false
    end

    tracked[title] = true
    questDB:Set("trackedQuests", tracked)

    if questIndex and questIndex > 0 then
        if not IsQuestWatched(questIndex) then
            AddQuestWatch(questIndex)
        end
    end

    self:UpdateTracker()
    return true
end

function PUIQuestWatch:UntrackQuest(questIndexOrTitle)
    local questIndex, title
    if type(questIndexOrTitle) == "number" then
        questIndex = questIndexOrTitle
        title = GetQuestLogTitle(questIndex)
    else
        title = questIndexOrTitle
        questIndex = self:FindQuestLogIndex(title)
    end

    if not title or title == "" then return false end

    local tracked = self:GetTrackedList()
    tracked[title] = nil
    questDB:Set("trackedQuests", tracked)

    if questIndex and questIndex > 0 then
        if IsQuestWatched(questIndex) then
            RemoveQuestWatch(questIndex)
        end
    end

    self:UpdateTracker()
    return true
end

function PUIQuestWatch:ToggleQuest(questIndexOrTitle)
    if self:IsTracked(questIndexOrTitle) then
        return self:UntrackQuest(questIndexOrTitle)
    else
        return self:TrackQuest(questIndexOrTitle)
    end
end

function PUIQuestWatch:ClearAllTracked()
    questDB:Set("trackedQuests", {})
    for i = 1, (GetNumQuestWatches and GetNumQuestWatches() or 0) do
        local qIndex = GetQuestIndexForWatch(1)
        if qIndex then
            RemoveQuestWatch(qIndex)
        end
    end
    self:UpdateTracker()
end

-- Reconcile tracked quests with active Quest Log entries
function PUIQuestWatch:ReconcileQuests()
    if self.isReconciling then return end
    self.isReconciling = true

    local numEntries = GetNumQuestLogEntries()
    if not numEntries or numEntries == 0 then
        -- Quest log not loaded yet; preserve SavedVariables and exit
        self.isReconciling = false
        return
    end

    local tracked = self:GetTrackedList()
    local maxWatches = questDB:Get("maxWatches", 10)
    local currentLogTitles = {}
    local trackedCount = 0

    for _ in pairs(tracked) do trackedCount = trackedCount + 1 end

    for i = 1, numEntries do
        local title, _, _, isHeader = GetQuestLogTitle(i)
        if not isHeader and title then
            currentLogTitles[title] = i

            -- Check if this is a newly accepted quest not in our knownQuests cache
            if questDB:Get("autoWatchNew", true) and not self.knownQuests[title] and trackedCount < maxWatches then
                tracked[title] = true
                trackedCount = trackedCount + 1
            end

            -- Sync native WoW watch state
            if tracked[title] then
                if not IsQuestWatched(i) then
                    AddQuestWatch(i)
                end
            end
        end
    end

    -- If tracked list is completely empty, auto-populate all current active quests
    if trackedCount == 0 and questDB:Get("autoWatchNew", true) then
        for i = 1, numEntries do
            local title, _, _, isHeader = GetQuestLogTitle(i)
            if not isHeader and title and trackedCount < maxWatches then
                tracked[title] = true
                trackedCount = trackedCount + 1
                if not IsQuestWatched(i) then
                    AddQuestWatch(i)
                end
            end
        end
    end

    -- Clean up quests that were turned in or abandoned (no longer in quest log)
    for savedTitle in pairs(tracked) do
        if not currentLogTitles[savedTitle] then
            tracked[savedTitle] = nil
        end
    end

    -- Update knownQuests cache
    self.knownQuests = currentLogTitles
    questDB:Set("trackedQuests", tracked)

    self.isReconciling = false
    self:UpdateTracker()
end

-- =========================================================================
-- TITLE BAR & COLLAPSE CONTROLLER
-- =========================================================================

function PUIQuestWatch:GetTitleBar()
    if self.titleBar then return self.titleBar end
    if not QuestWatchFrame then return nil end

    local bar = CreateFrame("Button", "PUIQuestWatchTitleBar", QuestWatchFrame)
    bar:SetHeight(20)
    bar:SetPoint("TOPLEFT", QuestWatchFrame, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", QuestWatchFrame, "TOPRIGHT", 0, 0)
    bar:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Sleek glassmorphic backdrop
    bar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    bar:SetBackdropColor(0.06, 0.08, 0.12, 0.85)
    bar:SetBackdropBorderColor(0.20, 0.25, 0.35, 0.90)

    -- Icon
    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(12)
    icon:SetHeight(12)
    icon:SetPoint("LEFT", bar, "LEFT", 5, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_08")
    bar.icon = icon

    local titleFont = (Media and Media.Fetch and Media:Fetch("font", "Default")) or "Fonts\\FRIZQT__.TTF"

    -- Title text: "Quest Tracker"
    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("LEFT", icon, "RIGHT", 5, 0)
    title:SetFont(titleFont, 10, "OUTLINE")
    title:SetTextColor(0.90, 0.82, 0.50)
    title:SetText("Quest Tracker")
    bar.title = title

    -- Tracked Count Badge: "(3)"
    local count = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("LEFT", title, "RIGHT", 4, 0)
    count:SetFont(titleFont, 10, "OUTLINE")
    count:SetTextColor(0.40, 0.85, 1.0)
    bar.count = count

    -- Collapse / Expand toggle button on right
    local toggleBtn = CreateFrame("Button", "PUIQuestWatchCollapseButton", bar)
    toggleBtn:SetWidth(18)
    toggleBtn:SetHeight(18)
    toggleBtn:SetPoint("RIGHT", bar, "RIGHT", -3, 0)

    local toggleText = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    toggleText:SetFont(titleFont, 11, "OUTLINE")
    toggleText:SetPoint("CENTER", toggleBtn, "CENTER", 0, 0)
    toggleText:SetText("−")
    toggleText:SetTextColor(0.85, 0.85, 0.85)
    toggleBtn.text = toggleText
    bar.toggleBtn = toggleBtn

    local function ToggleFold()
        local isCollapsed = questDB:Get("isCollapsed", false)
        questDB:Set("isCollapsed", not isCollapsed)
        PUIQuestWatch:UpdateTracker()
    end

    toggleBtn:SetScript("OnClick", function()
        ToggleFold()
    end)
    toggleBtn:SetScript("OnEnter", function()
        toggleText:SetTextColor(1.0, 0.82, 0.0)
    end)
    toggleBtn:SetScript("OnLeave", function()
        toggleText:SetTextColor(0.85, 0.85, 0.85)
    end)

    bar:SetScript("OnClick", function()
        if arg1 == "RightButton" then
            if not QuestLogFrame:IsVisible() then
                ShowUIPanel(QuestLogFrame)
            end
        else
            ToggleFold()
        end
    end)

    bar:SetScript("OnEnter", function()
        bar:SetBackdropBorderColor(0.40, 0.65, 1.0, 1.0)
        if GameTooltip then
            GameTooltip:SetOwner(bar, "ANCHOR_TOPLEFT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Quest Tracker", 1.0, 0.82, 0.0)
            local isCollapsed = questDB:Get("isCollapsed", false)
            GameTooltip:AddLine(isCollapsed and "Left-Click: Unfold / Expand Tracker" or "Left-Click: Fold / Minimize Tracker", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Right-Click: Open Quest Log", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)

    bar:SetScript("OnLeave", function()
        bar:SetBackdropBorderColor(0.20, 0.25, 0.35, 0.90)
        if GameTooltip then GameTooltip:Hide() end
    end)

    self.titleBar = bar
    return bar
end

-- =========================================================================
-- DYNAMIC FONTSTRING ALLOCATOR & INTERACTIVE HEADERS
-- =========================================================================

function PUIQuestWatch:GetWatchLine(index)
    local line = _G["QuestWatchLine" .. index]
    if not line and QuestWatchFrame then
        line = QuestWatchFrame:CreateFontString("QuestWatchLine" .. index, "ARTWORK", "QuestWatchFontTemplate")
        if not line then
            line = QuestWatchFrame:CreateFontString("QuestWatchLine" .. index, "ARTWORK", "GameFontHighlight")
        end
        self.allocatedLines = math.max(self.allocatedLines, index)
    end
    return line
end

function PUIQuestWatch:GetHeaderButton(index)
    local btn = self.headerButtons[index]
    if not btn and QuestWatchFrame then
        btn = CreateFrame("Button", "PUIQuestWatchHeaderButton" .. index, QuestWatchFrame)
        btn:SetHeight(16)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
        hl:SetBlendMode("ADD")
        hl:SetAlpha(0.25)
        hl:SetAllPoints(btn)
        btn.highlight = hl

        btn:SetScript("OnClick", function()
            if not btn.questIndex or not btn.questTitle then return end

            if IsShiftKeyDown() then
                -- Shift-Click: Insert quest link in chat, or untrack
                if ChatFrameEditBox and ChatFrameEditBox:IsVisible() then
                    local link = "[" .. btn.questTitle .. "]"
                    ChatFrameEditBox:Insert(link)
                else
                    PUIQuestWatch:UntrackQuest(btn.questTitle)
                end
            elseif IsAltKeyDown() then
                -- Alt-Click: Lock navigation focus
                if Primus.PUIQuest and Primus.PUIQuest.FocusQuest then
                    Primus.PUIQuest:FocusQuest(btn.questTitle)
                end
            else
                -- Left-Click: Open Quest Log & Focus Navigation Target
                if Primus.PUIQuest and Primus.PUIQuest.FocusQuest then
                    Primus.PUIQuest:FocusQuest(btn.questTitle)
                end
                if not QuestLogFrame:IsVisible() then
                    ShowUIPanel(QuestLogFrame)
                end
                local curIndex = PUIQuestWatch:FindQuestLogIndex(btn.questTitle) or btn.questIndex
                if curIndex and curIndex > 0 then
                    QuestLog_SetSelection(curIndex)
                    QuestLog_Update()
                end
            end
        end)

        btn:SetScript("OnEnter", function()
            if btn.titleLine then
                btn.titleLine:SetTextColor(1.0, 0.90, 0.30)
            end
            if GameTooltip and btn.questTitle then
                GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
                GameTooltip:ClearLines()
                local qIndex = PUIQuestWatch:FindQuestLogIndex(btn.questTitle) or btn.questIndex
                local _, level, questTag = GetQuestLogTitle(qIndex or 0)
                local headerText = (level and ("[" .. level .. "] ") or "") .. btn.questTitle
                if questTag and questTag ~= "" then
                    headerText = headerText .. " (" .. questTag .. ")"
                end
                GameTooltip:AddLine(headerText, 1.0, 0.82, 0.0)
                GameTooltip:AddLine("Left-Click: Open in Quest Log & Focus Navigation", 0.7, 0.7, 0.7)
                GameTooltip:AddLine("Alt-Click: Lock Objective Pointer", 0.4, 0.85, 1.0)
                GameTooltip:AddLine("Shift-Click: Untrack / Link in Chat", 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end
        end)

        btn:SetScript("OnLeave", function()
            if btn.titleLine and btn.originalColor then
                local c = btn.originalColor
                btn.titleLine:SetTextColor(c.r, c.g, c.b)
            end
            if GameTooltip then GameTooltip:Hide() end
        end)

        self.headerButtons[index] = btn
    end
    return btn
end

-- =========================================================================
-- BULLETPROOF QUEST TRACKER RENDERER (QuestWatch_Update Overhaul)
-- =========================================================================

function PUIQuestWatch:UpdateTracker()
    if not QuestWatchFrame then return end
    if not questDB:Get("enabled", true) then
        QuestWatchFrame:Hide()
        return
    end

    local tracked = self:GetTrackedList()
    local isCollapsed = questDB:Get("isCollapsed", false)
    local showTitleBar = questDB:Get("showTitleBar", true)
    local showLevels = questDB:Get("showLevels", true)
    local lineSpacing = questDB:Get("lineSpacing", 2)
    local questSpacing = questDB:Get("questSpacing", 6)

    local lineIndex = 1
    local headerIndex = 1
    local questWatchMaxWidth = 0
    local prevLine = nil

    -- Gather all active tracked quests
    local numEntries = GetNumQuestLogEntries()
    local activeTracked = {}

    if numEntries and numEntries > 0 then
        for i = 1, numEntries do
            local title, level, questTag, isHeader, isCollapsedState, isComplete = GetQuestLogTitle(i)
            if not isHeader and title and tracked[title] then
                table.insert(activeTracked, {
                    index = i,
                    title = title,
                    level = level,
                    questTag = questTag,
                    isComplete = isComplete,
                })
            end
        end
    end

    -- If no tracked quests, hide frame
    if table.getn(activeTracked) == 0 then
        QuestWatchFrame:Hide()
        return
    end

    QuestWatchFrame:Show()

    -- Title Bar Handling
    local titleBar = self:GetTitleBar()
    if showTitleBar and titleBar then
        titleBar:Show()
        titleBar.count:SetText(string.format("(%d)", table.getn(activeTracked)))
        titleBar.toggleBtn.text:SetText(isCollapsed and "+" or "−")
    elseif titleBar then
        titleBar:Hide()
    end

    -- If Collapsed (Folded Up), hide all lines and shrink frame
    if isCollapsed then
        for i = 1, self.allocatedLines do
            local line = _G["QuestWatchLine" .. i]
            if line then line:Hide() end
        end
        for i = 1, table.getn(self.headerButtons) do
            local btn = self.headerButtons[i]
            if btn then btn:Hide() end
        end
        QuestWatchFrame:SetHeight(22)
        QuestWatchFrame:SetWidth(180)
        self:StabilizeAnchor()
        return
    end

    -- Render each tracked quest
    for qIdx, qData in ipairs(activeTracked) do
        local questIndex = qData.index
        local title = qData.title
        local level = qData.level
        local questTag = qData.questTag
        local isComplete = qData.isComplete
        local numObjectives = GetNumQuestLeaderBoards(questIndex) or 0

        -- 1. TITLE LINE
        local titleLine = self:GetWatchLine(lineIndex)
        if titleLine then
            local tagStr = ""
            if questTag and questTag ~= "" then
                if questTag == "ELITE" or questTag == "Elite" then
                    tagStr = "+"
                elseif questTag == "DUNGEON" or questTag == "Dungeon" then
                    tagStr = " [D]"
                elseif questTag == "RAID" or questTag == "Raid" then
                    tagStr = " [R]"
                elseif questTag == "PVP" or questTag == "PvP" then
                    tagStr = " [PvP]"
                end
            end

            local levelPrefix = ""
            if showLevels and level and level > 0 then
                levelPrefix = "[" .. level .. tagStr .. "] "
            end

            titleLine:SetText(levelPrefix .. title)
            local color = self:GetQuestColor(level)
            titleLine:SetTextColor(color.r, color.g, color.b)

            titleLine:ClearAllPoints()
            if lineIndex == 1 then
                if showTitleBar then
                    titleLine:SetPoint("TOPLEFT", QuestWatchFrame, "TOPLEFT", 4, -26)
                else
                    titleLine:SetPoint("TOPLEFT", QuestWatchFrame, "TOPLEFT", 0, -2)
                end
            else
                titleLine:SetPoint("TOPLEFT", prevLine, "BOTTOMLEFT", 0, -questSpacing)
            end
            titleLine:Show()

            local titleWidth = titleLine:GetWidth() or 0
            if titleWidth > questWatchMaxWidth then
                questWatchMaxWidth = titleWidth
            end

            -- Overlay clickable header button
            local headerBtn = self:GetHeaderButton(headerIndex)
            if headerBtn then
                headerBtn:ClearAllPoints()
                headerBtn:SetPoint("TOPLEFT", titleLine, "TOPLEFT", -2, 2)
                headerBtn:SetWidth(math.max(titleWidth + 4, 120))
                headerBtn:SetHeight((titleLine:GetHeight() or 14) + 4)
                headerBtn.questIndex = questIndex
                headerBtn.questTitle = title
                headerBtn.titleLine = titleLine
                headerBtn.originalColor = color
                headerBtn:Show()
                headerIndex = headerIndex + 1
            end

            prevLine = titleLine
            lineIndex = lineIndex + 1

            -- 2. OBJECTIVES LINES
            local objectivesFinished = 0
            if numObjectives > 0 then
                for j = 1, numObjectives do
                    local objText, objType, finished = GetQuestLogLeaderBoard(j, questIndex)
                    local objLine = self:GetWatchLine(lineIndex)
                    if objLine and objText and objText ~= "" then
                        objLine:SetText("  • " .. objText)

                        if finished then
                            objLine:SetTextColor(0.40, 1.00, 0.40) -- Bright light green
                            objectivesFinished = objectivesFinished + 1
                        else
                            objLine:SetTextColor(0.85, 0.85, 0.85) -- Light gray
                        end

                        objLine:ClearAllPoints()
                        objLine:SetPoint("TOPLEFT", prevLine, "BOTTOMLEFT", 0, -lineSpacing)
                        objLine:Show()

                        local objWidth = objLine:GetWidth() or 0
                        if objWidth > questWatchMaxWidth then
                            questWatchMaxWidth = objWidth
                        end

                        prevLine = objLine
                        lineIndex = lineIndex + 1
                    end
                end
            else
                -- Quest has no leaderboards (e.g. talk to NPC) or ready to turn in
                local objLine = self:GetWatchLine(lineIndex)
                if objLine then
                    if isComplete then
                        objLine:SetText("  • Complete (Ready to turn in)")
                        objLine:SetTextColor(0.20, 1.00, 0.20)
                    else
                        objLine:SetText("  • Speak with questgiver")
                        objLine:SetTextColor(1.00, 0.85, 0.30)
                    end

                    objLine:ClearAllPoints()
                    objLine:SetPoint("TOPLEFT", prevLine, "BOTTOMLEFT", 0, -lineSpacing)
                    objLine:Show()

                    local objWidth = objLine:GetWidth() or 0
                    if objWidth > questWatchMaxWidth then
                        questWatchMaxWidth = objWidth
                    end

                    prevLine = objLine
                    lineIndex = lineIndex + 1
                end
            end

            -- Highlight complete header if all objectives finished
            if numObjectives > 0 and objectivesFinished == numObjectives then
                titleLine:SetText(levelPrefix .. title .. " (Complete)")
                titleLine:SetTextColor(1.00, 0.85, 0.20)
            end
        end
    end

    -- Hide unused watch lines
    for i = lineIndex, self.allocatedLines do
        local line = _G["QuestWatchLine" .. i]
        if line then line:Hide() end
    end

    -- Hide unused header buttons
    for i = headerIndex, table.getn(self.headerButtons) do
        local btn = self.headerButtons[i]
        if btn then btn:Hide() end
    end

    -- Update tracking indicator in Quest Log
    if QuestLogTrackTracking then
        if table.getn(activeTracked) > 0 then
            QuestLogTrackTracking:SetVertexColor(0, 1.0, 0)
        else
            QuestLogTrackTracking:SetVertexColor(1.0, 0, 0)
        end
    end

    -- Frame Sizing
    local calculatedHeight = (lineIndex - 1) * 14 + (table.getn(activeTracked) * questSpacing) + 12
    if showTitleBar then
        calculatedHeight = calculatedHeight + 26
    end
    local calculatedWidth = math.max(questWatchMaxWidth + 20, 200)
    QuestWatchFrame:SetHeight(calculatedHeight)
    QuestWatchFrame:SetWidth(calculatedWidth)

    self:StabilizeAnchor()
end

-- =========================================================================
-- ANCHOR STABILIZATION & MOVER PRESERVATION
-- =========================================================================

function PUIQuestWatch:StabilizeAnchor()
    if not QuestWatchFrame then return end

    local mover = PUIMover or Primus.PUIMover
    local moverPos = mover and mover.GetPosition and mover:GetPosition("QuestWatchFrame")

    if moverPos and moverPos.point then
        QuestWatchFrame:ClearAllPoints()
        QuestWatchFrame:SetPoint(moverPos.point or "TOPRIGHT", UIParent, moverPos.relativePoint or "TOPRIGHT", moverPos.x or -10, moverPos.y or -200)
        if QuestWatchFrame.SetUserPlaced then
            QuestWatchFrame:SetUserPlaced(true)
        end
    else
        local point, relativeTo = QuestWatchFrame:GetPoint()
        if not point or point ~= "TOPRIGHT" or relativeTo ~= MinimapCluster then
            QuestWatchFrame:ClearAllPoints()
            local anchorFrame = MinimapCluster or UIParent
            QuestWatchFrame:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", -10, -15)
        end
    end
end

-- =========================================================================
-- BLIZZARD BUG OVERRIDES & INTERCEPTIONS
-- =========================================================================

local function InterceptBlizzardQuestWatch()
    -- 1. Neutralize Blizzard's 5-minute AutoQuestWatch countdown
    _G.AutoQuestWatch_OnUpdate = function(elapsed)
        -- Quests never expire on a timer in PrimusUI
    end

    -- 2. Override AutoQuestWatch_Insert to prevent table key corruption
    _G.AutoQuestWatch_Insert = function(questIndex, watchTimer)
        if not questIndex or questIndex <= 0 then return end
        PUIQuestWatch:TrackQuest(questIndex)
    end

    -- 3. Override AutoQuestWatch_Update
    _G.AutoQuestWatch_Update = function(questIndex)
        if not questIndex or questIndex <= 0 then return end
        if questDB:Get("autoWatchProgress", true) then
            PUIQuestWatch:TrackQuest(questIndex)
        else
            PUIQuestWatch:UpdateTracker()
        end
    end

    -- 4. Override AutoQuestWatch_CheckDeleted to safely clean up removed quests
    _G.AutoQuestWatch_CheckDeleted = function()
        PUIQuestWatch:ReconcileQuests()
    end

    -- 5. Override global QuestWatch_Update with our enhanced renderer
    _G.QuestWatch_Update = function()
        PUIQuestWatch:UpdateTracker()
    end

    -- 6. Hook QuestLogTitleButton_OnClick for Shift-Click tracking toggle
    if QuestLogTitleButton_OnClick then
        local origTitleClick = QuestLogTitleButton_OnClick
        _G.QuestLogTitleButton_OnClick = function(button)
            if IsShiftKeyDown() and not this.isHeader then
                if ChatFrameEditBox and ChatFrameEditBox:IsVisible() then
                    origTitleClick(button)
                    return
                end

                local questIndex = this:GetID() + (FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(QuestLogListScrollFrame) or 0)
                PUIQuestWatch:ToggleQuest(questIndex)

                QuestLog_SetSelection(questIndex)
                QuestLog_Update()
                return
            end
            origTitleClick(button)
        end
    end

    -- 7. Hook UIParent_ManageFramePositions so it doesn't corrupt QuestWatchFrame anchors
    if UIParent_ManageFramePositions then
        local origManage = UIParent_ManageFramePositions
        _G.UIParent_ManageFramePositions = function()
            if origManage then origManage() end
            PUIQuestWatch:StabilizeAnchor()
        end
    end
end

-- =========================================================================
-- OPTIONS FLARE REGISTRATION
-- =========================================================================

function PUIQuestWatch:RegisterOptionsFlare()
    local Options = Primus.Options
    if not Options or not Options.RegisterModuleOptions then return end

    Options:RegisterModuleOptions("PUIQuestWatch", "Player", {
        title = "PUIQuestWatch: Quest Tracker",
        description = "Bulletproof quest objective tracker with title bar folding, persistence, level badges, and interactive headers.",
        icon = "Interface\\Icons\\INV_Misc_Book_08",
        fields = {
            {
                key = "enabled",
                label = "Enable Quest Objective Tracker",
                type = "checkbox",
                default = true,
                get = function() return questDB:Get("enabled", true) end,
                set = function(val)
                    questDB:Set("enabled", val)
                    if val then
                        PUIQuestWatch:UpdateTracker()
                    elseif QuestWatchFrame then
                        QuestWatchFrame:Hide()
                    end
                end,
            },
            {
                key = "showTitleBar",
                label = "Show Tracker Title Bar Header",
                type = "checkbox",
                default = true,
                get = function() return questDB:Get("showTitleBar", true) end,
                set = function(val)
                    questDB:Set("showTitleBar", val)
                    PUIQuestWatch:UpdateTracker()
                end,
            },
            {
                key = "isCollapsed",
                label = "Fold / Minimize Quest Tracker",
                type = "checkbox",
                default = false,
                get = function() return questDB:Get("isCollapsed", false) end,
                set = function(val)
                    questDB:Set("isCollapsed", val)
                    PUIQuestWatch:UpdateTracker()
                end,
            },
            {
                key = "autoWatchNew",
                label = "Auto-Watch Newly Accepted Quests",
                type = "checkbox",
                default = true,
                get = function() return questDB:Get("autoWatchNew", true) end,
                set = function(val) questDB:Set("autoWatchNew", val) end,
            },
            {
                key = "autoWatchProgress",
                label = "Auto-Watch Quests on Objective Progress",
                type = "checkbox",
                default = true,
                get = function() return questDB:Get("autoWatchProgress", true) end,
                set = function(val) questDB:Set("autoWatchProgress", val) end,
            },
            {
                key = "showLevels",
                label = "Show Quest Level Badges ([12] Title)",
                type = "checkbox",
                default = true,
                get = function() return questDB:Get("showLevels", true) end,
                set = function(val)
                    questDB:Set("showLevels", val)
                    PUIQuestWatch:UpdateTracker()
                end,
            },
            {
                key = "maxWatches",
                label = "Max Watched Quests (1..20)",
                type = "slider",
                min = 1,
                max = 20,
                step = 1,
                default = 10,
                get = function() return questDB:Get("maxWatches", 10) end,
                set = function(val)
                    questDB:Set("maxWatches", val)
                    PUIQuestWatch:UpdateTracker()
                end,
            },
            {
                key = "lineSpacing",
                label = "Objective Line Spacing",
                type = "slider",
                min = 0,
                max = 8,
                step = 1,
                default = 2,
                get = function() return questDB:Get("lineSpacing", 2) end,
                set = function(val)
                    questDB:Set("lineSpacing", val)
                    PUIQuestWatch:UpdateTracker()
                end,
            },
            {
                key = "questSpacing",
                label = "Spacing Between Quests",
                type = "slider",
                min = 2,
                max = 14,
                step = 1,
                default = 6,
                get = function() return questDB:Get("questSpacing", 6) end,
                set = function(val)
                    questDB:Set("questSpacing", val)
                    PUIQuestWatch:UpdateTracker()
                end,
            },
        },
    })
end

-- =========================================================================
-- INITIALIZATION & EVENT ROUTING
-- =========================================================================

function PUIQuestWatch:OnInitialize()
    self:RegisterOptionsFlare()
    InterceptBlizzardQuestWatch()

    if PUIMover and PUIMover.Register and QuestWatchFrame then
        PUIMover:Register(QuestWatchFrame, "QuestWatchFrame", "Quest Tracker", "UTILITY")
    end
end

function PUIQuestWatch:OnEnable()
    Events:Register("PLAYER_ENTERING_WORLD", "PUIQuestWatch", function()
        self:ReconcileQuests()
        self:StabilizeAnchor()
    end)

    Events:Register("QUEST_LOG_UPDATE", "PUIQuestWatch", function()
        self:ReconcileQuests()
    end)

    Events:Register("UNIT_QUEST_LOG_CHANGED", "PUIQuestWatch", function(unit)
        if unit == "player" then self:ReconcileQuests() end
    end)

    Events:Register("QUEST_WATCH_UPDATE", "PUIQuestWatch", function(qIndex)
        if questDB:Get("autoWatchProgress", true) and qIndex then
            self:TrackQuest(qIndex)
        else
            self:UpdateTracker()
        end
    end)

    Events:Register("QUEST_FINISHED", "PUIQuestWatch", function()
        self:ReconcileQuests()
    end)

    Events:Register("QUEST_COMPLETE", "PUIQuestWatch", function()
        self:ReconcileQuests()
    end)

    Events:Register("UI_INFO_MESSAGE", "PUIQuestWatch", function()
        self:ReconcileQuests()
    end)

    self:ReconcileQuests()
end

function PUIQuestWatch:OnDisable()
    Events:UnregisterOwner("PUIQuestWatch")
    if QuestWatchFrame then
        QuestWatchFrame:Hide()
    end
end

function PUIQuestWatch:Initialize()
    self:OnInitialize()
    self:OnEnable()
end
