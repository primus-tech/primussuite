--[[
    PrimusUI: PUIRoleplay Listener & Dialogue Isolator (PUIListener.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (RP Speech & Emote Stream Isolator)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIRoleplay = Primus.PUIRoleplay or {}
Primus.PUIRoleplay = PUIRoleplay

local Listener = {}
PUIRoleplay.Listener = Listener

local listenerFrame = nil
local listenerLogs = {}
local MAX_LISTENER_LINES = 50

--------------------------------------------------------------------------------
-- Build Floating Listener Dialogue Frame
--------------------------------------------------------------------------------
function Listener:BuildFrame()
    if listenerFrame then return listenerFrame end

    local f = CreateFrame("Frame", "Primus_PUIRoleplay_Listener", UIParent)
    f:SetWidth(340)
    f:SetHeight(180)
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 240)
    f:SetFrameStrata("MEDIUM")
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
    f:SetBackdropColor(0.04, 0.05, 0.07, 0.85)
    f:SetBackdropBorderColor(0.20, 0.25, 0.32, 0.9)
    f:Hide()
    table.insert(UISpecialFrames, "Primus_PUIRoleplay_Listener")

    if Primus.PUIMover then
        Primus.PUIMover:Register(f, "PUIRPListener", "RP Dialogue Listener", "SOCIAL")
    end

    -- Header Bar
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    header:SetHeight(20)
    header:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    header:SetBackdropColor(0.09, 0.12, 0.16, 0.95)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", header, "LEFT", 8, 0)
    title:SetText("|cff00ccffRP Dialogue Listener|r")

    local close = CreateFrame("Button", nil, header)
    close:SetWidth(14)
    close:SetHeight(14)
    close:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    close:SetScript("OnClick", function() f:Hide() end)

    local clearBtn = CreateFrame("Button", nil, header)
    clearBtn:SetWidth(40)
    clearBtn:SetHeight(14)
    clearBtn:SetPoint("RIGHT", close, "LEFT", -4, 0)
    local cTxt = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cTxt:SetPoint("CENTER", clearBtn, "CENTER", 0, 0)
    cTxt:SetText("|cff888888[Clear]|r")
    clearBtn:SetScript("OnClick", function()
        listenerLogs = {}
        Listener:Refresh()
    end)

    -- Message Scrolling Container
    local msgFrame = CreateFrame("ScrollingMessageFrame", "Primus_PUIRoleplay_ListenerMsg", f)
    msgFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -24)
    msgFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    msgFrame:SetFontObject(GameFontHighlightSmall)
    msgFrame:SetJustifyH("LEFT")
    msgFrame:SetMaxLines(MAX_LISTENER_LINES)
    msgFrame:SetFading(false)
    msgFrame:EnableMouseWheel(true)
    msgFrame:SetScript("OnMouseWheel", function()
        if arg1 > 0 then
            this:ScrollUp()
        else
            this:ScrollDown()
        end
    end)
    f.msgFrame = msgFrame

    listenerFrame = f
    return f
end

function Listener:Toggle()
    local f = self:BuildFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        self:Refresh()
    end
end

function Listener:Refresh()
    local f = self:BuildFrame()
    f.msgFrame:Clear()
    for _, entry in ipairs(listenerLogs) do
        f.msgFrame:AddMessage(entry)
    end
end

function Listener:ProcessMessage(event, message, sender)
    if not message or not sender then return end
    local myProf = PUIRoleplay:GetMyProfile() or {}
    local playerName = UnitName("player")
    local myTarget = UnitName("target")

    local fName = myProf.first_name
    local nick = myProf.nickname
    local fullRP = myProf.full_name

    local isMentioned = false
    local msgLower = string.lower(message)

    if playerName and string.find(msgLower, string.lower(playerName), 1, true) then
        isMentioned = true
    elseif fName and fName ~= "" and string.find(msgLower, string.lower(fName), 1, true) then
        isMentioned = true
    elseif nick and nick ~= "" and string.find(msgLower, string.lower(nick), 1, true) then
        isMentioned = true
    elseif fullRP and fullRP ~= "" and string.find(msgLower, string.lower(fullRP), 1, true) then
        isMentioned = true
    elseif myTarget and sender == myTarget then
        isMentioned = true
    end

    if isMentioned then
        local senderData = PUIRoleplay:GetCharacterData(sender) or {}
        local senderColor = senderData.class_color or "FFFFFF"
        local senderDisplay = (senderData.full_name and senderData.full_name ~= "") and senderData.full_name or sender

        local prefix = "|cff888888[" .. date("%H:%M") .. "]|r "
        local formatted = ""

        if event == "CHAT_MSG_EMOTE" or event == "CHAT_MSG_TEXT_EMOTE" then
            formatted = prefix .. "|cffff7e40* |cff" .. senderColor .. senderDisplay .. "|r " .. message .. "|r"
        elseif event == "CHAT_MSG_SAY" then
            formatted = prefix .. "|cff" .. senderColor .. senderDisplay .. "|r says: |cffffffff" .. message .. "|r"
        elseif event == "CHAT_MSG_YELL" then
            formatted = prefix .. "|cff" .. senderColor .. senderDisplay .. "|r yells: |cffff3333" .. message .. "|r"
        elseif event == "CHAT_MSG_WHISPER" then
            formatted = prefix .. "|cffff80cc[From " .. senderDisplay .. "]|r: " .. message
        else
            formatted = prefix .. "|cff" .. senderColor .. senderDisplay .. "|r: " .. message
        end

        table.insert(listenerLogs, formatted)
        if table.getn(listenerLogs) > MAX_LISTENER_LINES then
            table.remove(listenerLogs, 1)
        end

        if Primus.Audio then
            Primus.Audio:PlaySound("Tell", 0.5)
        end

        local f = self:BuildFrame()
        if f:IsShown() then
            f.msgFrame:AddMessage(formatted)
        end
    end
end
