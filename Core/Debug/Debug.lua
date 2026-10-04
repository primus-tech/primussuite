--[[
    PrimusLib: Bulletproof Diagnostic, Suppression Engine & Tabbed Error Catcher
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Commands: /error, /errors, /bug, /bugs, /err
    Features:
    1. Intercepts all Lua errors, syntax warnings, and Blizzard message() calls.
    2. Suppression Engine: checks against errors already in the log to suppress repeat auto-popups & FPS lag.
    3. Tabbed Interface:
       - Tab 1: Single Error Inspector (Details, Stack Trace, Occurrence Count, Next/Prev navigation)
       - Tab 2: Full Error Log (Aggregated chronological transcript of all unique errors)
    4. 1-Click 'Copy / Select All' button for instant Ctrl+C / Cmd+C export.
    5. Error history navigation, Clear All (resets suppression cache), and 1-Click Reload UI.
    6. Suppresses default Blizzard ScriptErrors dialog.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local Debug = Primus.Debug or {}
Primus.Debug = Debug

local Utils = Primus.Utils

Debug.errorLog = {}
Debug.capturedErrors = {}
Debug.errorMap = {}
Debug.totalErrorOccurrences = 0
Debug.currentIndex = 1
Debug.activeTab = 1
Debug.logCount = 0
Debug.maxLogs = 100
Debug.logLevel = 1
Debug.errorFrame = nil
Debug.autoPopup = true
Debug.lastVisualRefresh = 0

local LEVEL_COLORS = {
    [1] = "ff4444", -- Error (Red)
    [2] = "ffbb33", -- Warn  (Yellow)
    [3] = "33b5e5", -- Info  (Blue)
    [4] = "99cc00", -- Debug (Green)
}

-- Safe execution wrapper (Lua 5.0 pcall compliant)
function Debug:SafeCall(func, a1, a2, a3, a4, a5, a6, a7, a8)
    if type(func) ~= "function" then return false, "Not a function" end
    local success, err = pcall(func, a1, a2, a3, a4, a5, a6, a7, a8)
    if not success then
        local stack = debugstack and debugstack(2, 20, 20) or ""
        self:CaptureError(tostring(err), stack)
    end
    return success, err
end

-- Helper to extract Addon Name from error path
local function DetectAddonName(str)
    if not str then return "Unknown" end
    local _, _, addon = string.find(str, "AddOns\\([^\\]+)")
    if addon then return addon end
    if string.find(str, "FrameXML") then return "Blizzard FrameXML" end
    return "Custom Script"
end

-- Normalize error string & stack for duplicate suppression signature
local function NormalizeErrorSignature(msg, stack)
    local cleanMsg = string.gsub(tostring(msg or ""), "%s+", " ")
    -- Strip memory address hex pointers (e.g. 0x1234abcd) so addresses don't break grouping
    cleanMsg = string.gsub(cleanMsg, "0x%x+", "0xHEX")
    
    local cleanStack = string.gsub(tostring(stack or ""), "0x%x+", "0xHEX")
    local sigStack = string.sub(cleanStack, 1, 300)
    return cleanMsg .. "||" .. sigStack
end

-- Record and format an error in the legacy log
function Debug:Error(tag, message)
    self:Log(1, tag, message)
end

function Debug:Warn(tag, message)
    self:Log(2, tag, message)
end

function Debug:Info(tag, message)
    self:Log(3, tag, message)
end

function Debug:Log(level, tag, message)
    if type(level) == "string" and not message then
        message = tag
        tag = level
        level = 3
    end
    level = tonumber(level) or 3
    local maxLevel = tonumber(self.logLevel) or 1
    if level > maxLevel then return end

    local timestamp = date("%H:%M:%S")
    local entry = {
        level = level,
        tag = tag or "System",
        message = tostring(message or ""),
        time = timestamp,
    }

    self.logCount = self.logCount + 1
    table.insert(self.errorLog, entry)
    if table.getn(self.errorLog) > self.maxLogs then
        table.remove(self.errorLog, 1)
    end

    local colorHex = LEVEL_COLORS[level] or "ffffff"
    local prefix = string.format("|cff%s[%s][%s][%s]:|r", colorHex, timestamp, "Primus", tag)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. " " .. tostring(message))
    end
end

-- Dump a table structure for in-game inspection
function Debug:Dump(t, maxDepth, currentDepth)
    maxDepth = maxDepth or 2
    currentDepth = currentDepth or 0

    if type(t) ~= "table" then
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(tostring(t)) end
        return
    end

    local indent = string.rep("  ", currentDepth)
    for k, v in pairs(t) do
        if type(v) == "table" and currentDepth < maxDepth then
            if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(indent .. tostring(k) .. " = {") end
            self:Dump(v, maxDepth, currentDepth + 1)
            if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(indent .. "}") end
        else
            if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(indent .. tostring(k) .. " = " .. tostring(v)) end
        end
    end
end

-- =========================================================================
-- GLOBAL ERROR CATCHER, SUPPRESSION ENGINE & TABBED POP-UP INSPECTOR
-- =========================================================================

-- Show Error Popup Window immediately
function Debug:ShowErrorPopup()
    local f = self:CreateErrorFrame()
    if not f then return end
    self:RefreshErrorFrame()
    f:Show()
    f:Raise()
    if f.editBox then
        f.editBox:SetFocus()
        f.editBox:HighlightText()
    end
end

-- Capture and record a Lua error with automatic suppression
function Debug:CaptureError(msg, stack)
    msg = tostring(msg or "Unknown script error")
    stack = tostring(stack or (debugstack and debugstack(2, 20, 20) or ""))
    local timeStr = date("%H:%M:%S")

    self.totalErrorOccurrences = (self.totalErrorOccurrences or 0) + 1
    local sig = NormalizeErrorSignature(msg, stack)

    -- Suppression Engine: check if this error signature was already caught
    if not self.errorMap then self.errorMap = {} end
    local existing = self.errorMap[sig]
    if existing then
        -- Duplicate error: increment count, update timestamp, and SUPPRESS auto-popup
        existing.count = existing.count + 1
        existing.lastSeen = timeStr

        -- Rate-limited GUI refresh (max 1/sec) if error frame is currently visible
        if self.errorFrame and self.errorFrame:IsShown() then
            local now = GetTime()
            if (now - (self.lastVisualRefresh or 0)) >= 1.0 then
                self.lastVisualRefresh = now
                self:RefreshErrorFrame()
            end
        end
        return
    end

    -- New Unique Error: Register and categorize
    local addon = DetectAddonName(msg)
    if addon == "Unknown" or addon == "Custom Script" then
        addon = DetectAddonName(stack)
    end

    local entry = {
        msg = msg,
        stack = stack,
        firstSeen = timeStr,
        lastSeen = timeStr,
        count = 1,
        addon = addon,
        sig = sig,
    }

    self.errorMap[sig] = entry
    table.insert(self.capturedErrors, entry)
    self.currentIndex = table.getn(self.capturedErrors)

    -- Auto Pop-Up the Error Inspector Window immediately for new unique errors
    if self.autoPopup then
        self:ShowErrorPopup()
    else
        if self.errorFrame and self.errorFrame:IsShown() then
            self:RefreshErrorFrame()
        end
    end
end

-- Generate single error report string
function Debug:GenerateSingleErrorReport(index)
    local total = table.getn(self.capturedErrors)
    if total == 0 or not self.capturedErrors[index] then
        return "No errors captured in this session. All clear!"
    end

    local entry = self.capturedErrors[index]
    local _, pClass = UnitClass("player")
    local pLevel = UnitLevel("player") or 60
    local pZone = GetZoneText() or "Unknown"

    return string.format([[============================================================
  PRIMUS ERROR REPORT [Error %d of %d]
============================================================
Date/Time   : %s (First Seen: %s, Occurrences: %d)
AddOn/Source: %s
Player Info : Level %d %s (Zone: %s)
Client      : WoW 1.12.1 (Interface 11200)

------------------------------------------------------------
[ERROR MESSAGE]:
%s

------------------------------------------------------------
[CALL STACK]:
%s
============================================================]], index, total, entry.lastSeen, entry.firstSeen, entry.count, entry.addon, pLevel, pClass or "Unknown", pZone, entry.msg, entry.stack)
end

-- Generate full aggregated session log string
function Debug:GenerateFullLogReport()
    local total = table.getn(self.capturedErrors)
    if total == 0 then
        return "No errors captured in this session. All clear!"
    end

    local _, pClass = UnitClass("player")
    local pLevel = UnitLevel("player") or 60
    local pZone = GetZoneText() or "Unknown"

    local out = {}
    table.insert(out, "================================================================================")
    table.insert(out, "  PRIMUS ERROR CATCHER - FULL SESSION ERROR LOG")
    table.insert(out, string.format("  Total Unique Errors: %d  |  Total Occurrences: %d", total, self.totalErrorOccurrences or total))
    table.insert(out, string.format("  Player: Level %d %s (Zone: %s) | Client: WoW 1.12.1 (11200)", pLevel, pClass or "Unknown", pZone))
    table.insert(out, "================================================================================\n")

    for i = 1, total do
        local entry = self.capturedErrors[i]
        table.insert(out, string.format("[ERROR #%d of %d] ----------------------------------------------------", i, total))
        table.insert(out, string.format("Source     : %s", entry.addon or "Unknown"))
        table.insert(out, string.format("First Seen : %s", entry.firstSeen or "Unknown"))
        table.insert(out, string.format("Last Seen  : %s", entry.lastSeen or "Unknown"))
        table.insert(out, string.format("Occurrences: %d (Duplicates Suppressed: %d)", entry.count or 1, (entry.count or 1) - 1))
        table.insert(out, "\n[MESSAGE]:")
        table.insert(out, entry.msg or "")
        table.insert(out, "\n[CALL STACK]:")
        table.insert(out, entry.stack or "")
        table.insert(out, "\n--------------------------------------------------------------------------------\n")
    end

    return table.concat(out, "\n")
end

-- Create the Error Inspector GUI window with Tabs
function Debug:CreateErrorFrame()
    if self.errorFrame then return self.errorFrame end

    local parent = UIParent or WorldFrame
    local f = CreateFrame("Frame", "Primus_ErrorFrame", parent)
    f:SetWidth(640)
    f:SetHeight(460)
    f:SetPoint("CENTER", parent, "CENTER", 0, 40)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    f:SetBackdropColor(0.06, 0.06, 0.09, 0.96)
    f:SetBackdropBorderColor(0.25, 0.25, 0.30, 1.0)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:Hide()

    -- Allow ESC key to close error popup
    if UISpecialFrames then
        table.insert(UISpecialFrames, "Primus_ErrorFrame")
    end

    -- Title Bar Header
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    titleBar:SetHeight(28)
    titleBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    titleBar:SetBackdropColor(0.12, 0.12, 0.16, 1.0)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    title:SetText("|cffff4444PRIMUS ERROR CATCHER|r |cffaaaaaa// Script Diagnostic Engine|r")
    f.titleText = title

    local suppBadge = titleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    suppBadge:SetPoint("RIGHT", titleBar, "RIGHT", -34, 0)
    suppBadge:SetText("|cff00ff88[Suppression Active]|r")
    f.suppBadge = suppBadge

    local closeX = CreateFrame("Button", nil, titleBar)
    closeX:SetWidth(18)
    closeX:SetHeight(18)
    closeX:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
    closeX:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeX:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeX:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeX:SetScript("OnClick", function() f:Hide() end)

    -- Tab System Navigation (Below Title Bar)
    local tab1 = CreateFrame("Button", "Primus_ErrorTab1", f)
    tab1:SetWidth(150)
    tab1:SetHeight(22)
    tab1:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -34)
    tab1:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    local t1Text = tab1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t1Text:SetPoint("CENTER", tab1, "CENTER", 0, 0)
    t1Text:SetText("Single Error")
    tab1.text = t1Text
    tab1:SetScript("OnClick", function() Debug:SelectTab(1) end)
    f.tab1 = tab1

    local tab2 = CreateFrame("Button", "Primus_ErrorTab2", f)
    tab2:SetWidth(150)
    tab2:SetHeight(22)
    tab2:SetPoint("LEFT", tab1, "RIGHT", 6, 0)
    tab2:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    local t2Text = tab2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t2Text:SetPoint("CENTER", tab2, "CENTER", 0, 0)
    t2Text:SetText("Full Error Log")
    tab2.text = t2Text
    tab2:SetScript("OnClick", function() Debug:SelectTab(2) end)
    f.tab2 = tab2

    -- Status Subheader Line
    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -62)
    statusText:SetText("No errors captured.")
    f.statusText = statusText

    local countText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -62)
    countText:SetText("")
    f.countText = countText

    -- ScrollFrame & EditBox Container
    local editContainer = CreateFrame("Frame", nil, f)
    editContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -80)
    editContainer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 44)
    editContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    editContainer:SetBackdropColor(0.03, 0.03, 0.05, 0.98)
    editContainer:SetBackdropBorderColor(0.20, 0.20, 0.24, 1.0)

    local scroll = CreateFrame("ScrollFrame", "Primus_ErrorScrollFrame", editContainer, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", editContainer, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", editContainer, "BOTTOMRIGHT", -26, 6)
    scroll:EnableMouse(true)

    local editBox = CreateFrame("EditBox", "Primus_ErrorEditBox", scroll)
    editBox:SetWidth(580)
    editBox:SetHeight(2000)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetMaxLetters(999999)
    editBox:SetFontObject(GameFontHighlightSmall)
    editBox:SetTextColor(0.95, 0.95, 0.95, 1.0)
    editBox:SetTextInsets(4, 4, 4, 4)
    editBox:SetScript("OnEscapePressed", function() f:Hide() end)
    editBox:SetScript("OnTextChanged", function()
        if ScrollingEdit_OnTextChanged then
            ScrollingEdit_OnTextChanged(scroll)
        end
    end)
    editBox:SetScript("OnCursorChanged", function()
        local arg1, arg2, arg3, arg4 = arg1, arg2, arg3, arg4
        if ScrollingEdit_OnCursorChanged then
            ScrollingEdit_OnCursorChanged(arg1, arg2, arg3, arg4)
        end
    end)
    editBox:SetScript("OnUpdate", function()
        if ScrollingEdit_OnUpdate then
            ScrollingEdit_OnUpdate(scroll)
        end
    end)

    scroll:SetScript("OnMouseDown", function() editBox:SetFocus() end)
    editContainer:SetScript("OnMouseDown", function() editBox:SetFocus() end)
    scroll:SetScrollChild(editBox)
    f.editBox = editBox
    f.scroll = scroll

    -- Bottom Controls Footer
    local prevBtn = CreateFrame("Button", "Primus_ErrorPrevBtn", f, "UIPanelButtonTemplate")
    prevBtn:SetWidth(85)
    prevBtn:SetHeight(22)
    prevBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
    prevBtn:SetText("< Previous")
    prevBtn:SetScript("OnClick", function()
        if Debug.currentIndex > 1 then
            Debug.currentIndex = Debug.currentIndex - 1
            Debug:RefreshErrorFrame()
            if editBox then editBox:SetFocus() editBox:HighlightText() end
        end
    end)
    f.prevBtn = prevBtn

    local nextBtn = CreateFrame("Button", "Primus_ErrorNextBtn", f, "UIPanelButtonTemplate")
    nextBtn:SetWidth(85)
    nextBtn:SetHeight(22)
    nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 6, 0)
    nextBtn:SetText("Next >")
    nextBtn:SetScript("OnClick", function()
        if Debug.currentIndex < table.getn(Debug.capturedErrors) then
            Debug.currentIndex = Debug.currentIndex + 1
            Debug:RefreshErrorFrame()
            if editBox then editBox:SetFocus() editBox:HighlightText() end
        end
    end)
    f.nextBtn = nextBtn

    -- 1-Click Copy / Select All Button
    local copyBtn = CreateFrame("Button", "Primus_ErrorCopyBtn", f, "UIPanelButtonTemplate")
    copyBtn:SetWidth(135)
    copyBtn:SetHeight(22)
    copyBtn:SetPoint("LEFT", nextBtn, "RIGHT", 8, 0)
    copyBtn:SetText("Copy / Select All")
    copyBtn:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText()
        if DEFAULT_CHAT_FRAME then
            local mode = (Debug.activeTab == 2) and "Full Error Log" or "Single Error Report"
            DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[Primus Errors]: " .. mode .. " highlighted! Press Ctrl+C (Cmd+C) to copy.|r")
        end
    end)
    f.copyBtn = copyBtn

    -- Clear All Button
    local clearBtn = CreateFrame("Button", "Primus_ErrorClearBtn", f, "UIPanelButtonTemplate")
    clearBtn:SetWidth(85)
    clearBtn:SetHeight(22)
    clearBtn:SetPoint("LEFT", copyBtn, "RIGHT", 8, 0)
    clearBtn:SetText("Clear All")
    clearBtn:SetScript("OnClick", function()
        Debug:ClearErrors()
    end)

    -- Reload UI Button
    local reloadBtn = CreateFrame("Button", "Primus_ErrorReloadBtn", f, "UIPanelButtonTemplate")
    reloadBtn:SetWidth(80)
    reloadBtn:SetHeight(22)
    reloadBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -80, 12)
    reloadBtn:SetText("Reload UI")
    reloadBtn:SetScript("OnClick", function() ReloadUI() end)

    -- Close Button
    local closeMain = CreateFrame("Button", "Primus_ErrorCloseBtn", f, "UIPanelButtonTemplate")
    closeMain:SetWidth(65)
    closeMain:SetHeight(22)
    closeMain:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    closeMain:SetText("Close")
    closeMain:SetScript("OnClick", function() f:Hide() end)

    self.errorFrame = f
    self:SelectTab(1)
    return f
end

-- Select Active Tab (1 = Single Error, 2 = Full Log)
function Debug:SelectTab(tabIndex)
    self.activeTab = tabIndex
    local f = self:CreateErrorFrame()
    if not f then return end

    if tabIndex == 1 then
        f.tab1:SetBackdropColor(0.18, 0.20, 0.26, 1.0)
        f.tab1:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
        f.tab1.text:SetTextColor(0.0, 0.90, 1.0)

        f.tab2:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
        f.tab2:SetBackdropBorderColor(0.25, 0.25, 0.30, 1.0)
        f.tab2.text:SetTextColor(0.70, 0.70, 0.75)

        f.prevBtn:Show()
        f.nextBtn:Show()
        f.copyBtn:SetPoint("LEFT", f.nextBtn, "RIGHT", 8, 0)
    else
        f.tab2:SetBackdropColor(0.18, 0.20, 0.26, 1.0)
        f.tab2:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
        f.tab2.text:SetTextColor(0.0, 0.90, 1.0)

        f.tab1:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
        f.tab1:SetBackdropBorderColor(0.25, 0.25, 0.30, 1.0)
        f.tab1.text:SetTextColor(0.70, 0.70, 0.75)

        f.prevBtn:Hide()
        f.nextBtn:Hide()
        f.copyBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
    end

    self:RefreshErrorFrame()
    if f.scroll then
        f.scroll:SetVerticalScroll(0)
    end
end

-- Refresh error view
function Debug:RefreshErrorFrame()
    local f = self:CreateErrorFrame()
    if not f then return end

    local total = table.getn(self.capturedErrors)
    local totalOccurrences = self.totalErrorOccurrences or total

    f.tab1.text:SetText(string.format("Single Error (%d)", total))
    f.tab2.text:SetText(string.format("Full Log (%d)", total))

    if total == 0 then
        f.statusText:SetText("|cff888888No Lua errors captured in this session. All clear!|r")
        f.countText:SetText("")
        f.editBox:SetText("No errors captured.")
        f.prevBtn:Disable()
        f.nextBtn:Disable()
        return
    end

    if self.activeTab == 2 then
        -- Tab 2: Full Log View
        f.statusText:SetText(string.format("Aggregated Log: |cff00e5ff%d Unique Issues|r  |  Suppressed Triggers: |cffffcc00%d|r", total, totalOccurrences - total))
        f.countText:SetText(string.format("Total Errors: |cffffcc00%d|r", totalOccurrences))
        f.editBox:SetText(self:GenerateFullLogReport())
    else
        -- Tab 1: Single Error Inspector
        if self.currentIndex < 1 then self.currentIndex = 1 end
        if self.currentIndex > total then self.currentIndex = total end

        local entry = self.capturedErrors[self.currentIndex]
        f.statusText:SetText(string.format("Error %d of %d: |cff69ccf0%s|r  |  Time: |cffffffff%s|r", self.currentIndex, total, entry.addon, entry.lastSeen))
        f.countText:SetText(string.format("Occurrences: |cffffcc00%d|r", entry.count))
        f.editBox:SetText(self:GenerateSingleErrorReport(self.currentIndex))

        if self.currentIndex > 1 then f.prevBtn:Enable() else f.prevBtn:Disable() end
        if self.currentIndex < total then f.nextBtn:Enable() else f.nextBtn:Disable() end
    end
end

-- Clear all captured errors & reset suppression cache
function Debug:ClearErrors()
    if Utils and Utils.Wipe then
        Utils.Wipe(self.capturedErrors)
        Utils.Wipe(self.errorMap)
    else
        self.capturedErrors = {}
        self.errorMap = {}
    end
    self.totalErrorOccurrences = 0
    self.currentIndex = 1
    self:RefreshErrorFrame()
    if self.errorFrame then self.errorFrame:Hide() end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0[Primus Errors]: Cleared all captured error logs and suppression cache.|r")
    end
end

-- Toggle window
function Debug:ToggleErrorFrame()
    local f = self:CreateErrorFrame()
    if f:IsShown() then
        f:Hide()
    else
        self:ShowErrorPopup()
    end
end

-- =========================================================================
-- GLOBAL ERROR INTERCEPTION & SUPPRESSION ENGINE
-- =========================================================================

local function PrimusGlobalErrorHandler(errMsg)
    local stack = debugstack and debugstack(2, 20, 20) or ""
    Debug:CaptureError(errMsg, stack)
end

-- Install global error handler
local function InstallGlobalErrorHandler()
    if seterrorhandler then
        seterrorhandler(PrimusGlobalErrorHandler)
    end

    if _G.message then
        _G.message = function(msg)
            local stack = debugstack and debugstack(2, 20, 20) or ""
            Debug:CaptureError(msg, stack)
        end
    end

    if ScriptErrors_OnError then
        ScriptErrors_OnError = function(msg)
            local stack = debugstack and debugstack(2, 20, 20) or ""
            Debug:CaptureError(msg, stack)
        end
    end

    if ScriptErrors then
        ScriptErrors:UnregisterAllEvents()
        ScriptErrors:Hide()
        ScriptErrors:ClearAllPoints()
        ScriptErrors:SetPoint("BOTTOMLEFT", UIParent, "TOPLEFT", -2000, 2000)
        ScriptErrors:SetScript("OnShow", function() this:Hide() end)
    end
end

-- Initial install
InstallGlobalErrorHandler()

-- Event-driven re-installation to ensure Blizzard FrameXML does not override our handler
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("VARIABLES_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function()
    InstallGlobalErrorHandler()
end)

-- Sub-command registration via Primus Console
if Primus.Console and Primus.Console.RegisterSubCommand then
    Primus.Console:RegisterSubCommand("errors", function(argParam)
        argParam = Utils.Trim(argParam or "")
        if argParam == "clear" then
            Debug:ClearErrors()
        elseif argParam == "test" then
            error("Primus Error Catcher Test: copy/paste verification test error!")
        else
            Debug:ToggleErrorFrame()
        end
    end, "Display runtime error inspector GUI (/pui errors [clear|test])")
    
    if Primus.Console.RegisterAlias then
        Primus.Console:RegisterAlias("error", "errors")
        Primus.Console:RegisterAlias("bugs", "errors")
        Primus.Console:RegisterAlias("bug", "errors")
        Primus.Console:RegisterAlias("err", "errors")
    end
end
