--[[
    PrimusUI Module: Utility_LogViewer (PUILogViewer.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (Universal Chat, RP, Rolls & Diagnostic Log Viewer)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUILogViewer = Primus.PUILogViewer or {}
Primus.PUILogViewer = PUILogViewer
_G.PUILogViewer = PUILogViewer
Primus:RegisterModule("PUILogViewer", PUILogViewer, "Utility")

local DB     = Primus.DB
local Events = Primus.Events
local Utils  = Primus.Utils

local logFrame = nil
local activeTab = 1
local activeFilter = "ALL"
local isPaused = false
local MAX_LOG_ENTRIES = 1000

local logViewerDB = DB:RegisterNamespace("PUILogViewer", {
    enabled = true,
    max_entries = 1000,
    timestamp_format = "%H:%M:%S",
    auto_scroll = true,
})

--------------------------------------------------------------------------------
-- Database & Storage Access
--------------------------------------------------------------------------------
local function GetLogsDB()
    if not _G.PrimusGlobalDB then _G.PrimusGlobalDB = {} end
    if not _G.PrimusGlobalDB.PUILogViewer_Logs then _G.PrimusGlobalDB.PUILogViewer_Logs = {} end
    return _G.PrimusGlobalDB.PUILogViewer_Logs
end

function PUILogViewer:AddLogEntry(category, channel, sender, text, extra)
    if not text or text == "" then return end
    local logs = GetLogsDB()
    local zone = GetZoneText() or "Unknown"
    local timestamp = date("%Y-%m-%d %H:%M:%S")
    local timeShort = date("%H:%M:%S")

    local entry = {
        time = timestamp,
        timeShort = timeShort,
        zone = zone,
        category = category or "CHAT",
        channel = channel or "SAY",
        sender = sender or UnitName("player") or "Unknown",
        text = text,
        extra = extra
    }

    table.insert(logs, entry)
    if table.getn(logs) > MAX_LOG_ENTRIES then
        table.remove(logs, 1)
    end

    if logFrame and logFrame:IsShown() and not isPaused then
        PUILogViewer:Refresh()
    end
end

--------------------------------------------------------------------------------
-- Chat Event Listeners
--------------------------------------------------------------------------------
function PUILogViewer:OnInitialize()
    if Primus.Chat then
        Primus.Chat:RegisterConsumer("PUILogViewer", 50, function(msgObj)
            local msg = msgObj.message
            if not msg or msg == "" then return end

            local event = msgObj.event
            local sender = msgObj.sender
            local channelName = msgObj.channelName

            local cat = "CHAT"
            local ch = msgObj.type or string.gsub(event, "^CHAT_MSG_", "")

            -- Category classification
            if event == "CHAT_MSG_SAY" or event == "CHAT_MSG_EMOTE" or event == "CHAT_MSG_TEXT_EMOTE" or event == "CHAT_MSG_YELL" then
                cat = "RP"
            elseif event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_WHISPER_INFORM" then
                cat = "WHISPER"
            elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
                cat = "GROUP"
            elseif event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER" then
                cat = "GUILD"
            elseif event == "CHAT_MSG_CHANNEL" then
                local cName = tostring(channelName or "")
                if string.find(cName, "OWPRP") or string.find(cName, "TTRP") or string.find(cName, "xtension") or string.find(cName, "MyRolePlay") then
                    cat = "RP"
                else
                    cat = "CHANNEL"
                end
                ch = cName
            elseif event == "CHAT_MSG_SYSTEM" then
                if string.find(msg, "rolls") or string.find(msg, "DiceMaster") or string.find(msg, "%[D%d") then
                    cat = "ROLL"
                    ch = "ROLL"
                else
                    cat = "SYSTEM"
                end
            end

            PUILogViewer:AddLogEntry(cat, ch, sender or "System", msg)
        end)
    end
end

--------------------------------------------------------------------------------
-- URL Link Extractor Helper (Vanilla WoW 1.12.1 / Lua 5.0.2)
--------------------------------------------------------------------------------
function PUILogViewer:ExtractURLs(text)
    if Utils and Utils.ExtractURLs then
        return Utils.ExtractURLs(text)
    end
    return {}
end

--------------------------------------------------------------------------------
-- Build Master Log Viewer Window
--------------------------------------------------------------------------------
function PUILogViewer:BuildFrame()
    if logFrame then return logFrame end

    local f = CreateFrame("Frame", "Primus_PUILogViewer_Frame", UIParent)
    f:SetWidth(560)
    f:SetHeight(480)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    f:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
    f:SetBackdropBorderColor(0.20, 0.22, 0.28, 1.0)
    table.insert(UISpecialFrames, "Primus_PUILogViewer_Frame")

    if Primus.PUIMover then
        Primus.PUIMover:Register(f, "PUILogViewer", "Universal Log Viewer", "UTILITY")
    end

    -- Title Bar
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    titleBar:SetHeight(28)
    titleBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    titleBar:SetBackdropColor(0.11, 0.12, 0.15, 1.0)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleText:SetText("|cff00ccffPRIMUS|r |cffffffffLOG VIEWER & STORY ARCHIVE|r")

    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetWidth(18)
    closeBtn:SetHeight(18)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Tab Bar (5 Stream Views: RP, Dice, Debug, All, URLs)
    local tabNames = { "RP & Chat", "Dice & Rolls", "Errors & Debug", "All Stream", "URLs & Links" }
    local tabs = {}
    local tabW = 104
    for i = 1, 5 do
        local tBtn = CreateFrame("Button", nil, f)
        tBtn:SetWidth(tabW)
        tBtn:SetHeight(22)
        tBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 12 + (i - 1) * (tabW + 4), -34)
        tBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 0 }
        })
        tBtn:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
        tBtn:SetBackdropBorderColor(0.22, 0.24, 0.28, 1.0)

        local tTxt = tBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tTxt:SetPoint("CENTER", tBtn, "CENTER", 0, 0)
        tTxt:SetText(tabNames[i])
        tBtn.text = tTxt
        tBtn.tabIdx = i

        tBtn:SetScript("OnClick", function()
            PUILogViewer:SelectTab(this.tabIdx)
        end)
        tabs[i] = tBtn
    end
    f.tabs = tabs

    -- Search Filter Box
    local searchEB = CreateFrame("EditBox", nil, f)
    searchEB:SetWidth(536)
    searchEB:SetHeight(22)
    searchEB:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -60)
    searchEB:SetAutoFocus(false)
    searchEB:SetFontObject(GameFontHighlightSmall)
    searchEB:SetTextColor(1.0, 1.0, 1.0, 1.0)
    searchEB:SetTextInsets(8, 8, 2, 2)
    searchEB:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    searchEB:SetBackdropColor(0.04, 0.04, 0.07, 0.95)
    searchEB:SetBackdropBorderColor(0.30, 0.30, 0.38, 1.0)
    searchEB:SetScript("OnTextChanged", function()
        PUILogViewer:Refresh()
    end)
    searchEB:SetScript("OnEscapePressed", function()
        this:SetText("")
        this:ClearFocus()
        PUILogViewer:Refresh()
    end)
    f.searchEB = searchEB

    -- Quick Filter Chips Bar (8 chips)
    local chipBar = CreateFrame("Frame", nil, f)
    chipBar:SetPoint("TOPLEFT", searchEB, "BOTTOMLEFT", 0, -4)
    chipBar:SetWidth(536)
    chipBar:SetHeight(20)

    local chipDefs = {
        { id = "ALL",     label = "All" },
        { id = "RP",      label = "Say/Emote" },
        { id = "WHISPER", label = "Whispers" },
        { id = "GROUP",   label = "Group" },
        { id = "GUILD",   label = "Guild" },
        { id = "ROLL",    label = "Rolls/D20" },
        { id = "URL",     label = "URLs" },
        { id = "ERROR",   label = "Errors" }
    }
    f.chipBtns = {}
    local cW = 63
    for cIdx, c in ipairs(chipDefs) do
        local cBtn = CreateFrame("Button", nil, chipBar)
        cBtn:SetWidth(cW)
        cBtn:SetHeight(18)
        cBtn:SetPoint("TOPLEFT", chipBar, "TOPLEFT", (cIdx - 1) * (cW + 4), 0)
        cBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        cBtn:SetBackdropColor(0.06, 0.06, 0.09, 0.95)
        cBtn:SetBackdropBorderColor(0.22, 0.22, 0.28, 1.0)

        local cTxt = cBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cTxt:SetPoint("CENTER", cBtn, "CENTER", 0, 0)
        cTxt:SetText(c.label)
        cBtn.text = cTxt
        cBtn.chipId = c.id

        cBtn:SetScript("OnClick", function()
            activeFilter = this.chipId
            if this.chipId == "RP" then activeTab = 1
            elseif this.chipId == "ROLL" then activeTab = 2
            elseif this.chipId == "ERROR" then activeTab = 3
            elseif this.chipId == "ALL" then activeTab = 4
            elseif this.chipId == "URL" then activeTab = 5
            end
            PUILogViewer:UpdateTabHighlights()
            PUILogViewer:UpdateChipHighlights()
            PUILogViewer:Refresh()
        end)
        f.chipBtns[cIdx] = cBtn
    end

    -- Scrollable Log Container
    local logBox = CreateFrame("Frame", nil, f)
    logBox:SetPoint("TOPLEFT", chipBar, "BOTTOMLEFT", 0, -4)
    logBox:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 40)
    logBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    logBox:SetBackdropColor(0.03, 0.03, 0.05, 0.95)
    logBox:SetBackdropBorderColor(0.18, 0.20, 0.24, 1.0)

    local scroll = CreateFrame("ScrollFrame", "Primus_PUILogViewer_Scroll", logBox, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", logBox, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", logBox, "BOTTOMRIGHT", -26, 6)

    local logEB = CreateFrame("EditBox", nil, scroll)
    logEB:SetWidth(500)
    logEB:SetHeight(1200)
    logEB:SetMultiLine(true)
    logEB:SetAutoFocus(false)
    logEB:SetFontObject(GameFontHighlightSmall)
    logEB:SetTextColor(0.9, 0.9, 0.95, 1.0)
    logEB:SetTextInsets(4, 4, 4, 4)
    scroll:SetScrollChild(logEB)
    f.logEB = logEB
    f.scroll = scroll

    logEB:SetScript("OnEscapePressed", function() this:ClearFocus() end)

    -- Bottom Action Bar: [Export Scene], [Tag Scene Start], [Clear Logs], [Pause Stream]
    local exportBtn = CreateFrame("Button", nil, f)
    exportBtn:SetWidth(130)
    exportBtn:SetHeight(22)
    exportBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    exportBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    exportBtn:SetBackdropColor(0.08, 0.18, 0.28, 0.95)
    exportBtn:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
    local exTxt = exportBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    exTxt:SetPoint("CENTER", exportBtn, "CENTER", 0, 0)
    exTxt:SetText("|cff00ccffCopy for Discord|r")
    exportBtn:SetScript("OnClick", function()
        PUILogViewer:ExportSceneToClipboard()
    end)

    local tagSceneBtn = CreateFrame("Button", nil, f)
    tagSceneBtn:SetWidth(120)
    tagSceneBtn:SetHeight(22)
    tagSceneBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
    tagSceneBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    tagSceneBtn:SetBackdropColor(0.18, 0.14, 0.08, 0.95)
    tagSceneBtn:SetBackdropBorderColor(1.0, 0.75, 0.2, 1.0)
    local tsTxt = tagSceneBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tsTxt:SetPoint("CENTER", tagSceneBtn, "CENTER", 0, 0)
    tsTxt:SetText("|cffffd100+ Mark Scene|r")
    tagSceneBtn:SetScript("OnClick", function()
        PUILogViewer:AddLogEntry("RP", "SCENE", "SYSTEM", "==================== SCENE MARKER ====================")
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffPrimus Log Viewer:|r Inserted Scene Marker.")
    end)

    local pauseBtn = CreateFrame("Button", nil, f)
    pauseBtn:SetWidth(90)
    pauseBtn:SetHeight(22)
    pauseBtn:SetPoint("LEFT", tagSceneBtn, "RIGHT", 8, 0)
    pauseBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    local pTxt = pauseBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pTxt:SetPoint("CENTER", pauseBtn, "CENTER", 0, 0)
    pTxt:SetText("Pause")
    pauseBtn.text = pTxt
    pauseBtn:SetScript("OnClick", function()
        isPaused = not isPaused
        this.text:SetText(isPaused and "|cffff3333Resume|r" or "Pause")
    end)
    f.pauseBtn = pauseBtn

    local clearBtn = CreateFrame("Button", nil, f)
    clearBtn:SetWidth(80)
    clearBtn:SetHeight(22)
    clearBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    clearBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    clearBtn:SetBackdropColor(0.35, 0.12, 0.12, 0.95)
    clearBtn:SetBackdropBorderColor(0.85, 0.25, 0.25, 1.0)
    local clTxt = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    clTxt:SetPoint("CENTER", clearBtn, "CENTER", 0, 0)
    clTxt:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        if _G.PrimusGlobalDB then _G.PrimusGlobalDB.PUILogViewer_Logs = {} end
        PUILogViewer:Refresh()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffPrimus Log Viewer:|r Cleared log stream.")
    end)

    logFrame = f
    self:SelectTab(1)
    return f
end

function PUILogViewer:UpdateTabHighlights()
    local f = logFrame
    if not f or not f.tabs then return end
    for i = 1, 5 do
        local tab = f.tabs[i]
        if tab then
            if i == activeTab then
                tab:SetBackdropColor(0.16, 0.18, 0.24, 1.0)
                tab:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
                tab.text:SetTextColor(0.0, 0.90, 1.0)
            else
                tab:SetBackdropColor(0.06, 0.06, 0.08, 0.9)
                tab:SetBackdropBorderColor(0.20, 0.22, 0.26, 1.0)
                tab.text:SetTextColor(0.70, 0.70, 0.75)
            end
        end
    end
end

function PUILogViewer:SelectTab(tabIdx)
    activeTab = tabIdx
    local f = self:BuildFrame()

    if tabIdx == 1 then activeFilter = "RP"
    elseif tabIdx == 2 then activeFilter = "ROLL"
    elseif tabIdx == 3 then activeFilter = "ERROR"
    elseif tabIdx == 4 then activeFilter = "ALL"
    elseif tabIdx == 5 then activeFilter = "URL"
    end

    self:UpdateTabHighlights()
    self:UpdateChipHighlights()
    self:Refresh()
end

function PUILogViewer:UpdateChipHighlights()
    local f = logFrame
    if not f or not f.chipBtns then return end
    for _, b in ipairs(f.chipBtns) do
        if b.chipId == activeFilter then
            b:SetBackdropColor(0.0, 0.45, 0.70, 0.95)
            b:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
        else
            b:SetBackdropColor(0.06, 0.06, 0.09, 0.95)
            b:SetBackdropBorderColor(0.22, 0.22, 0.28, 1.0)
        end
    end
end

function PUILogViewer:Refresh()
    local f = self:BuildFrame()
    local logs = GetLogsDB()
    local q = string.lower((f.searchEB and f.searchEB:GetText()) or "")

    local lines = {}

    -- Check if viewing error tab
    if activeFilter == "ERROR" or activeTab == 3 then
        local errLog = (_G.PrimusGlobalDB and _G.PrimusGlobalDB.ErrorLog) or {}
        for _, err in ipairs(errLog) do
            local line = string.format("[%s] ERROR: %s", err.time or "", err.message or err.msg or "Script Error")
            if err.stack then
                line = line .. "\n" .. err.stack
            end
            if q == "" or string.find(string.lower(line), q, 1, true) then
                table.insert(lines, line)
            end
        end
    elseif activeFilter == "URL" or activeTab == 5 then
        for _, entry in ipairs(logs) do
            local foundUrls = PUILogViewer:ExtractURLs(entry.text)
            if foundUrls and table.getn(foundUrls) > 0 then
                for _, u in ipairs(foundUrls) do
                    local formattedLine = string.format("[%s - %s] %s:\n  LINK: %s\n  TEXT: \"%s\"\n",
                        entry.timeShort or entry.time or "",
                        entry.channel or entry.category or "CHAT",
                        entry.sender or "Unknown",
                        u,
                        entry.text or "")

                    if q == "" or string.find(string.lower(formattedLine), q, 1, true) then
                        table.insert(lines, formattedLine)
                    end
                end
            end
        end
    else
        for _, entry in ipairs(logs) do
            local matchesFilter = false
            if activeFilter == "ALL" then
                matchesFilter = true
            elseif activeFilter == "RP" and (entry.category == "RP" or entry.channel == "SAY" or entry.channel == "EMOTE") then
                matchesFilter = true
            elseif activeFilter == "WHISPER" and entry.category == "WHISPER" then
                matchesFilter = true
            elseif activeFilter == "GROUP" and entry.category == "GROUP" then
                matchesFilter = true
            elseif activeFilter == "GUILD" and entry.category == "GUILD" then
                matchesFilter = true
            elseif activeFilter == "ROLL" and (entry.category == "ROLL" or string.find(entry.text, "roll") or string.find(entry.text, "%[D%d")) then
                matchesFilter = true
            end

            if matchesFilter then
                local formattedLine = string.format("[%s - %s] %s: %s",
                    entry.timeShort or entry.time or "",
                    entry.zone or "",
                    entry.sender or "",
                    entry.text or "")

                if q == "" or string.find(string.lower(formattedLine), q, 1, true) then
                    table.insert(lines, formattedLine)
                end
            end
        end
    end

    local text = table.concat(lines, "\n")
    if text == "" then
        if activeFilter == "URL" or activeTab == 5 then
            text = "No web links or URLs detected in the chat log stream."
        else
            text = "No log records found matching current criteria."
        end
    end
    f.logEB:SetText(text)
end

function PUILogViewer:ExportSceneToClipboard()
    local f = self:BuildFrame()
    f.logEB:HighlightText(0, string.len(f.logEB:GetText() or ""))
    f.logEB:SetFocus()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffPrimus Log Viewer:|r Log text highlighted. Press |cffffcc00Ctrl+C|r to copy.")
end

function PUILogViewer:ShowURLPopup(url)
    if Primus.PUITalk and Primus.PUITalk.ShowURLCopyPopup then
        Primus.PUITalk:ShowURLCopyPopup(url)
        return
    end
    local f = self:BuildFrame()
    f.logEB:SetText(url or "")
    f:Show()
    f.logEB:HighlightText(0, string.len(url or ""))
    f.logEB:SetFocus()
end

function PUILogViewer:Open(filter)
    local f = self:BuildFrame()
    f:Show()
    if filter then
        activeFilter = filter
        if filter == "RP" then activeTab = 1
        elseif filter == "ROLL" then activeTab = 2
        elseif filter == "ERROR" then activeTab = 3
        elseif filter == "ALL" then activeTab = 4
        elseif filter == "URL" then activeTab = 5
        end
        self:UpdateTabHighlights()
        self:UpdateChipHighlights()
    end
    self:Refresh()
end

function PUILogViewer:Toggle()
    local f = self:BuildFrame()
    if f:IsShown() then f:Hide() else f:Show(); self:Refresh() end
end

-- Slash command hooks
SLASH_PUILOG1 = "/puilog"
SLASH_PUILOG2 = "/logs"
SLASH_PUILOG3 = "/puilogs"
SLASH_PUILOG4 = "/logviewer"
SLASH_PUILOG5 = "/elephant"
SlashCmdList["PUILOG"] = function(msg)
    PUILogViewer:Toggle()
end

SLASH_PUIURL1 = "/puiurl"
SLASH_PUIURL2 = "/urls"
SLASH_PUIURL3 = "/links"
SLASH_PUIURL4 = "/urlviewer"
SlashCmdList["PUIURL"] = function(msg)
    if msg and msg ~= "" then
        PUILogViewer:ShowURLPopup(msg)
    else
        PUILogViewer:Open("URL")
    end
end

