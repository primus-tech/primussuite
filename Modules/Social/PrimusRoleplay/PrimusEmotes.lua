--[[
    PrimusUI: PUIRoleplay Emotes & Long-Form Chat Composer (PUIEmotes.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (255-Char Limit Bypass & Segment Numbering)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIRoleplay = Primus.PUIRoleplay or {}
Primus.PUIRoleplay = PUIRoleplay

local Emotes = {}
PUIRoleplay.Emotes = Emotes

local composeFrame = nil

--------------------------------------------------------------------------------
-- Long-Form RP Message Broadcaster (>200 Chars Chunking with <1/X> Numbering)
--------------------------------------------------------------------------------
function Emotes:SendLongForm(msgType, message)
    if not message or message == "" then return end

    local chatType = msgType or "EMOTE"
    local words = {}
    for word in string.gfind(message, "%S+") do
        table.insert(words, word)
    end

    if table.getn(words) == 0 then return end

    -- First pass: Build chunks
    local rawChunks = {}
    local currentChunk = ""

    for _, word in ipairs(words) do
        local testLen = string.len(currentChunk) + string.len(word) + 1
        if testLen > 190 then
            table.insert(rawChunks, currentChunk)
            currentChunk = word
        else
            if currentChunk == "" then
                currentChunk = word
            else
                currentChunk = currentChunk .. " " .. word
            end
        end
    end
    if currentChunk ~= "" then
        table.insert(rawChunks, currentChunk)
    end

    local totalChunks = table.getn(rawChunks)

    -- Transmit chunks with segment headers if multi-part
    for idx, chunk in ipairs(rawChunks) do
        local outText = chunk
        if totalChunks > 1 then
            outText = string.format("<%d/%d> %s", idx, totalChunks, chunk)
        end

        if _G.ChatThrottleLib then
            _G.ChatThrottleLib:SendChatMessage("NORMAL", "EMOTE", outText, chatType)
        else
            SendChatMessage(outText, chatType)
        end
    end
end

--------------------------------------------------------------------------------
-- Quotation Dialogue Formatting in Chat
--------------------------------------------------------------------------------
function Emotes:FormatEmoteQuotes(msg, sender)
    if not msg or not string.find(msg, '"') then return msg end
    local formatted = string.gsub(msg, '("[^"]*")', "|cffffffff%1|cffff7e40")
    return formatted
end

--------------------------------------------------------------------------------
-- Long-Form Composer UI Window
--------------------------------------------------------------------------------
function Emotes:OpenComposer()
    if not composeFrame then
        local f = CreateFrame("Frame", "Primus_PUIRoleplay_Composer", UIParent)
        f:SetWidth(460)
        f:SetHeight(230)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
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
        f:SetBackdropColor(0.07, 0.07, 0.09, 0.96)
        f:SetBackdropBorderColor(0.22, 0.22, 0.26, 1.0)
        table.insert(UISpecialFrames, "Primus_PUIRoleplay_Composer")

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
        title:SetText("|cff00ccffRP EMOTE COMPOSER & SPLITTER|r")

        local charCounter = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        charCounter:SetPoint("TOPRIGHT", f, "TOPRIGHT", -32, -10)
        charCounter:SetText("0 Chars")
        f.charCounter = charCounter

        local close = CreateFrame("Button", nil, f)
        close:SetWidth(18)
        close:SetHeight(18)
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
        close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
        close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
        close:SetScript("OnClick", function() f:Hide() end)

        local scrollBg = CreateFrame("Frame", nil, f)
        scrollBg:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -28)
        scrollBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 42)
        scrollBg:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        scrollBg:SetBackdropColor(0.04, 0.04, 0.07, 0.95)
        scrollBg:SetBackdropBorderColor(0.28, 0.28, 0.35, 1.0)

        local scroll = CreateFrame("ScrollFrame", "Primus_PUIRoleplay_CompScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", scrollBg, "TOPLEFT", 4, -4)
        scroll:SetPoint("BOTTOMRIGHT", scrollBg, "BOTTOMRIGHT", -24, 4)

        local eb = CreateFrame("EditBox", nil, scroll)
        eb:SetWidth(400)
        eb:SetHeight(150)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(true)
        eb:SetFontObject(GameFontHighlightSmall)
        eb:SetTextColor(1.0, 1.0, 1.0, 1.0)
        eb:SetTextInsets(6, 6, 6, 6)
        scroll:SetScrollChild(eb)
        f.eb = eb

        eb:SetScript("OnTextChanged", function()
            if ScrollingEdit_OnTextChanged then ScrollingEdit_OnTextChanged(scroll) end
            local len = string.len(this:GetText() or "")
            local chunks = math.max(1, math.ceil(len / 190))
            f.charCounter:SetText(string.format("%d Chars (%d chunks)", len, chunks))
        end)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)

        -- Send Emote Button
        local sendEmoteBtn = CreateFrame("Button", nil, f)
        sendEmoteBtn:SetWidth(110)
        sendEmoteBtn:SetHeight(24)
        sendEmoteBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
        sendEmoteBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        sendEmoteBtn:SetBackdropColor(0.0, 0.45, 0.7, 0.9)
        sendEmoteBtn:SetBackdropBorderColor(0.0, 0.8, 1.0, 1.0)

        local eTxt = sendEmoteBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        eTxt:SetPoint("CENTER", sendEmoteBtn, "CENTER", 0, 0)
        eTxt:SetText("Send as Emote")
        sendEmoteBtn.text = eTxt

        sendEmoteBtn:SetScript("OnClick", function()
            local text = f.eb:GetText()
            if text and text ~= "" then
                Emotes:SendLongForm("EMOTE", text)
                f.eb:SetText("")
                f:Hide()
            end
        end)

        -- Send Say Button
        local sendSayBtn = CreateFrame("Button", nil, f)
        sendSayBtn:SetWidth(100)
        sendSayBtn:SetHeight(24)
        sendSayBtn:SetPoint("LEFT", sendEmoteBtn, "RIGHT", 10, 0)
        sendSayBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        sendSayBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.9)
        sendSayBtn:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)

        local sTxt = sendSayBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sTxt:SetPoint("CENTER", sendSayBtn, "CENTER", 0, 0)
        sTxt:SetText("Send as Say")
        sendSayBtn.text = sTxt

        sendSayBtn:SetScript("OnClick", function()
            local text = f.eb:GetText()
            if text and text ~= "" then
                Emotes:SendLongForm("SAY", text)
                f.eb:SetText("")
                f:Hide()
            end
        end)

        -- Send Yell Button
        local sendYellBtn = CreateFrame("Button", nil, f)
        sendYellBtn:SetWidth(100)
        sendYellBtn:SetHeight(24)
        sendYellBtn:SetPoint("LEFT", sendSayBtn, "RIGHT", 10, 0)
        sendYellBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        sendYellBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.9)
        sendYellBtn:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)

        local yTxt = sendYellBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        yTxt:SetPoint("CENTER", sendYellBtn, "CENTER", 0, 0)
        yTxt:SetText("Send as Yell")
        sendYellBtn.text = yTxt

        sendYellBtn:SetScript("OnClick", function()
            local text = f.eb:GetText()
            if text and text ~= "" then
                Emotes:SendLongForm("YELL", text)
                f.eb:SetText("")
                f:Hide()
            end
        end)

        composeFrame = f
    end

    composeFrame:Show()
    composeFrame.eb:SetFocus()
end
