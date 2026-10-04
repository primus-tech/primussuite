--[[
    PrimusUI: PUIRoleplay Elephant RP Conversation Logger (PUIElephant.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (Persistent RP Chat Logs)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIRoleplay = Primus.PUIRoleplay or {}
Primus.PUIRoleplay = PUIRoleplay

local Elephant = {}
PUIRoleplay.Elephant = Elephant

local logFrame = nil
local MAX_STORED_LOGS = 500

--------------------------------------------------------------------------------
-- Database & Storage Access
--------------------------------------------------------------------------------
local function GetLogsDB()
    if not _G.PrimusGlobalDB then _G.PrimusGlobalDB = {} end
    if not _G.PrimusGlobalDB.PUIRP_Logs then _G.PrimusGlobalDB.PUIRP_Logs = {} end
    return _G.PrimusGlobalDB.PUIRP_Logs
end

function Elephant:LogMessage(event, message, sender)
    if not message or not sender then return end
    local logs = GetLogsDB()
    local zone = GetZoneText() or "Unknown Zone"
    local timestamp = date("%Y-%m-%d %H:%M:%S")

    local entry = {
        time = timestamp,
        zone = zone,
        event = event,
        sender = sender,
        text = message
    }

    table.insert(logs, entry)
    if table.getn(logs) > MAX_STORED_LOGS then
        table.remove(logs, 1)
    end
end

--------------------------------------------------------------------------------
-- Build Elephant RP Logger UI Window
--------------------------------------------------------------------------------
function Elephant:BuildFrame()
    if logFrame then return logFrame end

    local f = CreateFrame("Frame", "Primus_PUIRoleplay_Elephant", UIParent)
    f:SetWidth(500)
    f:SetHeight(420)
    f:SetPoint("CENTER", UIParent, "CENTER", 50, 0)
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
    f:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
    f:SetBackdropBorderColor(0.20, 0.22, 0.26, 1.0)
    table.insert(UISpecialFrames, "Primus_PUIRoleplay_Elephant")

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
    titleText:SetText("|cff00ccffPRIMUS|r |cffffffffRP ELEPHANT CHAT LOGS|r")

    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetWidth(18)
    closeBtn:SetHeight(18)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local clearBtn = CreateFrame("Button", nil, titleBar)
    clearBtn:SetWidth(60)
    clearBtn:SetHeight(18)
    clearBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    clearBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    clearBtn:SetBackdropColor(0.12, 0.14, 0.18, 0.9)
    clearBtn:SetBackdropBorderColor(0.25, 0.30, 0.38, 1.0)
    local cTxt = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cTxt:SetPoint("CENTER", clearBtn, "CENTER", 0, 0)
    cTxt:SetText("|cff888888[Clear All]|r")
    clearBtn:SetScript("OnClick", function()
        if _G.PrimusGlobalDB then _G.PrimusGlobalDB.PUIRP_Logs = {} end
        Elephant:Refresh()
    end)

    -- Search Filter EditBox
    local searchEB = CreateFrame("EditBox", nil, f)
    searchEB:SetWidth(476)
    searchEB:SetHeight(22)
    searchEB:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -34)
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
        Elephant:Refresh(this:GetText())
    end)
    searchEB:SetScript("OnEscapePressed", function()
        this:SetText("")
        this:ClearFocus()
        Elephant:Refresh("")
    end)
    f.searchEB = searchEB

    -- Scrollable Log Text Box
    local scrollBg = CreateFrame("Frame", nil, f)
    scrollBg:SetPoint("TOPLEFT", searchEB, "BOTTOMLEFT", 0, -6)
    scrollBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    scrollBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    scrollBg:SetBackdropColor(0.04, 0.04, 0.06, 0.95)
    scrollBg:SetBackdropBorderColor(0.20, 0.22, 0.28, 1.0)

    local scroll = CreateFrame("ScrollFrame", "Primus_PUIRPSheet_ElephScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", scrollBg, "TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", scrollBg, "BOTTOMRIGHT", -24, 4)

    local logEB = CreateFrame("EditBox", nil, scroll)
    logEB:SetWidth(446)
    logEB:SetHeight(800)
    logEB:SetMultiLine(true)
    logEB:SetAutoFocus(false)
    logEB:SetFontObject(GameFontHighlightSmall)
    logEB:SetTextColor(0.9, 0.9, 0.95, 1.0)
    logEB:SetTextInsets(4, 4, 4, 4)
    scroll:SetScrollChild(logEB)
    f.logEB = logEB

    logEB:SetScript("OnEscapePressed", function() this:ClearFocus() end)

    logFrame = f
    return f
end

function Elephant:OpenLogs()
    if Primus.PUILogViewer then
        Primus.PUILogViewer:Open("RP")
    else
        local f = self:BuildFrame()
        f:Show()
        self:Refresh("")
    end
end

function Elephant:Toggle()
    if Primus.PUILogViewer then
        Primus.PUILogViewer:Toggle()
    else
        local f = self:BuildFrame()
        if f:IsShown() then f:Hide() else f:Show(); self:Refresh("") end
    end
end

function Elephant:Refresh(filterText)
    local f = self:BuildFrame()
    local logs = GetLogsDB()
    local q = string.lower(filterText or (f.searchEB and f.searchEB:GetText()) or "")

    local lines = {}
    for _, entry in ipairs(logs) do
        local fullLine = string.format("[%s - %s] %s: %s", entry.time or "", entry.zone or "", entry.sender or "", entry.text or "")
        if q == "" or string.find(string.lower(fullLine), q, 1, true) then
            table.insert(lines, fullLine)
        end
    end

    local text = table.concat(lines, "\n")
    if text == "" then text = "No logged roleplay conversations found matching query." end
    f.logEB:SetText(text)
end
