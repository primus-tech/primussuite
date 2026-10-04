--[[
    PrimusUI Module: PUITalk (Universal Docked Input, Channel Switcher & Slash Router)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    - Docked bottom universal EditBox with history buffer.
    - Context pill with quick channel selector popup menu (#Say, #Yell, #Party, #Raid, #Guild, #Officer).
    - Chat slash routing (/s, /y, /p, /ra, /g, /o, /w, /r) and fallback to ChatEdit_SendText.
    - Roster name tab-completion.
    - Global Enter keybind redirection (ChatFrame_OpenChatBox hook).
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus or not Primus.PUITalk then return end

local PUITalk = Primus.PUITalk
local Media   = Primus.Media
local Utils   = Primus.Utils

local activeChannelType = "SAY"
local activeChannelNumber = 0
local channelSelectMenu = nil

-- =========================================================================
-- 1. CHANNEL SELECTOR POPUP MENU
-- =========================================================================

local function OpenChannelSelectMenu(anchor)
    if not channelSelectMenu then
        local m = CreateFrame("Frame", "Primus_PUITalkChannelSelectMenu", UIParent)
        m:SetWidth(120)
        m:SetHeight(200)
        m:SetFrameStrata("DIALOG")
        m:SetFrameLevel(110)
        m:SetBackdrop(Media:Fetch("border", "1Pixel"))
        m:SetBackdropColor(0.06, 0.08, 0.12, 0.98)
        m:SetBackdropBorderColor(0.20, 0.50, 0.90, 1.0)
        m:EnableMouse(true)
        m:SetClampedToScreen(true)
        tinsert(UISpecialFrames, "Primus_PUITalkChannelSelectMenu")

        m.buttons = {}
        channelSelectMenu = m
    end

    local m = channelSelectMenu

    -- Build channel list dynamically
    local chList = {
        { tag = "#Say",     chan = "SAY",     num = 0 },
        { tag = "#Yell",    chan = "YELL",    num = 0 },
        { tag = "#Party",   chan = "PARTY",   num = 0 },
        { tag = "#Raid",    chan = "RAID",    num = 0 },
        { tag = "#Guild",   chan = "GUILD",   num = 0 },
        { tag = "#Officer", chan = "OFFICER", num = 0 },
    }

    -- Add currently joined numbered & custom channels
    local chanList = { GetChannelList() }
    if chanList and table.getn(chanList) > 0 then
        for i = 1, table.getn(chanList), 2 do
            local num = tonumber(chanList[i]) or 0
            local rawName = tostring(chanList[i+1] or "")
            local cleanName = rawName
            local dashPos = string.find(rawName, " %- ")
            if dashPos then cleanName = string.sub(rawName, 1, dashPos - 1) end

            if num > 0 and cleanName ~= "" then
                local shortTag = string.len(cleanName) > 8 and (string.sub(cleanName, 1, 7) .. "..") or cleanName
                table.insert(chList, {
                    tag = string.format("#%d %s", num, shortTag),
                    chan = "CHANNEL",
                    num = num,
                    fullName = cleanName,
                })
            end
        end
    end

    -- Hide existing buttons
    for _, btn in ipairs(m.buttons) do
        btn:Hide()
    end

    local yOff = -4
    for i, c in ipairs(chList) do
        local b = m.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, m)
            b:SetWidth(112)
            b:SetHeight(18)
            b:SetBackdrop(Media:Fetch("border", "1Pixel"))
            b:SetBackdropColor(0.08, 0.10, 0.14, 0.6)
            b:SetBackdropBorderColor(0.15, 0.20, 0.30, 0.6)

            local bt = b:CreateFontString(nil, "OVERLAY")
            bt:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
            bt:SetPoint("LEFT", b, "LEFT", 6, 0)
            b.text = bt

            b:SetScript("OnEnter", function()
                this:SetBackdropColor(0.18, 0.26, 0.40, 1.0)
                this:SetBackdropBorderColor(0.40, 0.75, 1.0, 1.0)
            end)
            b:SetScript("OnLeave", function()
                this:SetBackdropColor(0.08, 0.10, 0.14, 0.6)
                this:SetBackdropBorderColor(0.15, 0.20, 0.30, 0.6)
            end)
            b:SetScript("OnClick", function()
                activeChannelType = this.chan
                activeChannelNumber = this.chanNum or 0
                if PUITalk.masterFrame and PUITalk.masterFrame.contextPill then
                    PUITalk.masterFrame.contextPill.text:SetText(this.tag)
                end
                m:Hide()
            end)

            m.buttons[i] = b
        end

        b:SetPoint("TOPLEFT", m, "TOPLEFT", 4, yOff)
        b.chan = c.chan
        b.chanNum = c.num
        b.tag = c.tag
        b.text:SetText(c.tag)
        b:Show()

        yOff = yOff - 20
    end

    m:SetHeight(math.abs(yOff) + 4)

    if m:IsShown() then
        m:Hide()
    else
        m:ClearAllPoints()
        m:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
        m:Show()
        m:Raise()
    end
end

-- =========================================================================
-- 2. UNIVERSAL INPUT BAR CREATION
-- =========================================================================

function PUITalk:CreateUniversalInput(f)
    if not f then return end

    local footer = CreateFrame("Frame", nil, f)
    footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 4)
    footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    footer:SetHeight(24)
    footer:SetBackdrop(Media:Fetch("border", "1Pixel"))
    footer:SetBackdropColor(0.04, 0.05, 0.07, 1.0)
    footer:SetBackdropBorderColor(0.20, 0.35, 0.60, 1.0)
    f.footer = footer

    local contextPill = CreateFrame("Button", "Primus_PUITalkContextPill", footer)
    contextPill:SetPoint("LEFT", footer, "LEFT", 2, 0)
    contextPill:SetWidth(80)
    contextPill:SetHeight(20)
    contextPill:SetBackdrop(Media:Fetch("border", "1Pixel"))
    contextPill:SetBackdropColor(0.12, 0.16, 0.24, 1.0)
    contextPill:SetBackdropBorderColor(0.3, 0.6, 1.0, 0.8)
    local contextText = contextPill:CreateFontString(nil, "OVERLAY")
    contextText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    contextText:SetPoint("CENTER", 0, 0)
    contextText:SetText("#Say")
    contextPill.text = contextText
    contextPill:SetScript("OnClick", function()
        local curTab = PUITalk.db:Get("activeMasterTab") or 1
        if curTab == 1 then
            OpenChannelSelectMenu(this)
        end
    end)
    contextPill:SetScript("OnEnter", function()
        this:SetBackdropColor(0.18, 0.26, 0.40, 1.0)
        this:SetBackdropBorderColor(0.50, 0.85, 1.0, 1.0)
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:AddLine("Active Target / Channel", 0.4, 0.85, 1.0)
        GameTooltip:AddLine("Click to switch default broadcast channel.", 1, 1, 1)
        GameTooltip:Show()
    end)
    contextPill:SetScript("OnLeave", function()
        this:SetBackdropColor(0.12, 0.16, 0.24, 1.0)
        this:SetBackdropBorderColor(0.3, 0.6, 1.0, 0.8)
        GameTooltip:Hide()
    end)
    f.contextPill = contextPill

    local editBox = CreateFrame("EditBox", "Primus_PUITalkUniversalInput", footer)
    editBox:SetPoint("LEFT", contextPill, "RIGHT", 4, 0)
    editBox:SetPoint("RIGHT", footer, "RIGHT", -4, 0)
    editBox:SetHeight(20)
    editBox:SetFont(Media:Fetch("font", "Default"), 10, "")
    editBox:SetAutoFocus(false)
    editBox:SetHistoryLines(30)
    editBox:SetScript("OnEditFocusGained", function()
        this.hasFocus = true
    end)
    editBox:SetScript("OnEditFocusLost", function()
        this.hasFocus = false
    end)
    editBox:SetScript("OnUpdate", function()
        if this.pendingText ~= nil then
            this:SetText(this.pendingText)
            this.pendingText = nil
        end
    end)
    editBox:SetScript("OnEnterPressed", function()
        this.hasFocus = false
        local text = this:GetText()
        if text and text ~= "" then
            PUITalk:HandleInputSubmit(text)
            this:AddHistoryLine(text)
            this:SetText("")
        end
        this:ClearFocus()
    end)
    editBox:SetScript("OnEscapePressed", function()
        this.hasFocus = false
        this.pendingText = nil
        this:SetText("")
        this:ClearFocus()
    end)
    editBox:SetScript("OnTabPressed", function()
        local text = this:GetText() or ""
        if text == "" then return end

        local lastSpace = 0
        local len = string.len(text)
        for i = len, 1, -1 do
            if string.sub(text, i, i) == " " then
                lastSpace = i
                break
            end
        end

        local prefix = string.sub(text, 1, lastSpace)
        local partial = string.lower(string.sub(text, lastSpace + 1))
        if partial == "" then return end

        local names = PUITalk:GetRosterNames()
        for _, name in ipairs(names) do
            if string.sub(string.lower(name), 1, string.len(partial)) == partial then
                this:SetText(prefix .. name .. " ")
                return
            end
        end
    end)
    f.editBox = editBox
end

-- =========================================================================
-- 3. INPUT SUBMISSION & SLASH ROUTING
-- =========================================================================

function PUITalk:HandleInputSubmit(text)
    if not text or text == "" then return end

    -- 1. Check if input is a slash command (/s, /p, /w, /pui, /who, /dance, /cast, etc.)
    if string.sub(text, 1, 1) == "/" then
        local spacePos = string.find(text, " ")
        local cmd = spacePos and string.sub(text, 2, spacePos - 1) or string.sub(text, 2)
        local rest = spacePos and string.sub(text, spacePos + 1) or ""
        cmd = string.lower(cmd)

        if cmd == "s" or cmd == "say" then
            activeChannelType = "SAY"
            if self.masterFrame and self.masterFrame.contextPill then self.masterFrame.contextPill.text:SetText("#Say") end
            if rest ~= "" then SendChatMessage(rest, "SAY") end
            return
        elseif cmd == "y" or cmd == "yell" then
            activeChannelType = "YELL"
            if self.masterFrame and self.masterFrame.contextPill then self.masterFrame.contextPill.text:SetText("#Yell") end
            if rest ~= "" then SendChatMessage(rest, "YELL") end
            return
        elseif cmd == "p" or cmd == "party" then
            activeChannelType = "PARTY"
            if self.masterFrame and self.masterFrame.contextPill then self.masterFrame.contextPill.text:SetText("#Party") end
            if rest ~= "" then SendChatMessage(rest, "PARTY") end
            return
        elseif cmd == "g" or cmd == "guild" then
            activeChannelType = "GUILD"
            if self.masterFrame and self.masterFrame.contextPill then self.masterFrame.contextPill.text:SetText("#Guild") end
            if rest ~= "" then SendChatMessage(rest, "GUILD") end
            return
        elseif cmd == "ra" or cmd == "raid" then
            activeChannelType = "RAID"
            if self.masterFrame and self.masterFrame.contextPill then self.masterFrame.contextPill.text:SetText("#Raid") end
            if rest ~= "" then SendChatMessage(rest, "RAID") end
            return
        elseif cmd == "o" or cmd == "officer" then
            activeChannelType = "OFFICER"
            if self.masterFrame and self.masterFrame.contextPill then self.masterFrame.contextPill.text:SetText("#Officer") end
            if rest ~= "" then SendChatMessage(rest, "OFFICER") end
            return
        elseif cmd == "w" or cmd == "whisper" or cmd == "tell" or cmd == "t" then
            local sp2 = string.find(rest, " ")
            local target = sp2 and string.sub(rest, 1, sp2 - 1) or rest
            local msg = sp2 and string.sub(rest, sp2 + 1) or ""
            if target and target ~= "" then
                PUITalk:OpenDMConversation(target)
                if msg ~= "" then
                    SendChatMessage(msg, "WHISPER", nil, target)
                end
            end
            return
        elseif cmd == "r" or cmd == "reply" then
            if PUITalk.lastWhisperSender then
                PUITalk:OpenDMConversation(PUITalk.lastWhisperSender)
                if rest ~= "" then
                    SendChatMessage(rest, "WHISPER", nil, PUITalk.lastWhisperSender)
                end
            end
            return
        end

        local numCmd = tonumber(cmd)
        if numCmd and numCmd >= 1 and numCmd <= 10 then
            activeChannelType = "CHANNEL"
            activeChannelNumber = numCmd
            if self.masterFrame and self.masterFrame.contextPill then
                self.masterFrame.contextPill.text:SetText("#" .. numCmd)
            end
            if rest ~= "" then
                SendChatMessage(rest, "CHANNEL", nil, numCmd)
            end
            return
        end

        -- Fallback to default Blizzard ChatEdit_SendText for all game/addon slash commands (/pui, /dance, /who, /played, /macro, etc.)
        if ChatFrameEditBox then
            ChatFrameEditBox:SetText(text)
            ChatEdit_SendText(ChatFrameEditBox)
        end
        return
    end

    -- 2. Regular non-slash text message
    local currentTab = self.db:Get("activeMasterTab") or 1

    if currentTab == 2 and self.activeDMKey and self.dmTabs[self.activeDMKey] then
        local targetName = self.dmTabs[self.activeDMKey].name or self.activeDMKey
        SendChatMessage(text, "WHISPER", nil, targetName)
        return
    end

    if activeChannelType == "CHANNEL" and activeChannelNumber and activeChannelNumber > 0 then
        SendChatMessage(text, "CHANNEL", nil, activeChannelNumber)
        return
    end

    SendChatMessage(text, activeChannelType or "SAY")
end

-- =========================================================================
-- 4. GLOBAL ENTER & SLASH KEYBIND HOOK (ChatFrame_OpenChat)
-- =========================================================================

function PUITalk:FocusInput(text)
    if not self.masterFrame then
        self:CreateMasterFrame()
    end
    if not self.masterFrame or not self.masterFrame.editBox then return end

    if not self.masterFrame:IsShown() then
        self.masterFrame:Show()
    end

    local editBox = self.masterFrame.editBox

    if text and text ~= "" then
        -- Check if it's a whisper command e.g. "/w Name " or "/whisper Name "
        local _, _, cmd, target = string.find(text, "^/(%a+)%s+([^%s]+)%s*$")
        if (cmd == "w" or cmd == "whisper" or cmd == "tell" or cmd == "t") and target and self.db:Get("divertWhispers", true) then
            self:OpenDMConversation(target)
            self:SelectMasterTab(2)
            editBox.pendingText = ""
            editBox:SetText("")
        else
            editBox.pendingText = text
            editBox:SetText("")
        end
    end

    editBox.hasFocus = true
    editBox:SetFocus()

    -- Ensure default Blizzard ChatFrameEditBox stays hidden
    if ChatFrameEditBox and ChatFrameEditBox:IsShown() then
        ChatFrameEditBox:Hide()
    end
end

function PUITalk:HookChatKeybind()
    if not _G.Primus_OriginalChatFrame_OpenChat then
        _G.Primus_OriginalChatFrame_OpenChat = ChatFrame_OpenChat
        ChatFrame_OpenChat = function(text, chatFrame)
            if PUITalk.masterFrame and PUITalk.masterFrame.editBox then
                PUITalk:FocusInput(text)
                if chatFrame and chatFrame.editBox and chatFrame.editBox:IsShown() then
                    chatFrame.editBox:Hide()
                end
                return
            end
            if _G.Primus_OriginalChatFrame_OpenChat then
                return _G.Primus_OriginalChatFrame_OpenChat(text, chatFrame)
            end
        end
    end
end
