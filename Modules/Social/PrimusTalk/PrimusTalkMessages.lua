--[[
    PrimusUI Module: PUITalk (Direct Messages, DM Sub-Tabs & DM Context Menu)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    - Tab 2 Viewport construction (Primus_PUITalkViewMessages).
    - DM conversation sub-tabs with inline [x] close buttons and solid amber unread highlight.
    - Right-click DM player context menu (Invite, Who, Popout, Clear, Close).
    - Authoritative whisper history manager and audio chime notification.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus or not Primus.PUITalk then return end

local PUITalk = Primus.PUITalk
local Media   = Primus.Media
local Utils   = Primus.Utils

local dmContextMenu = nil

-- =========================================================================
-- 1. RIGHT-CLICK DM CONTEXT MENU
-- =========================================================================

local function CreateDMContextMenu()
    if dmContextMenu then return dmContextMenu end

    local menu = CreateFrame("Frame", "Primus_PUITalkDMMenu", UIParent)
    menu:SetWidth(150)
    menu:SetHeight(130)
    menu:SetFrameStrata("DIALOG")
    menu:SetFrameLevel(110)
    menu:SetBackdrop(Media:Fetch("border", "1Pixel"))
    menu:SetBackdropColor(0.06, 0.08, 0.12, 0.98)
    menu:SetBackdropBorderColor(0.20, 0.50, 0.90, 1.0)
    menu:EnableMouse(true)
    menu:SetClampedToScreen(true)
    menu:Hide()

    tinsert(UISpecialFrames, "Primus_PUITalkDMMenu")

    local title = menu:CreateFontString(nil, "OVERLAY")
    title:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    title:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -8)
    title:SetText(Utils.ColorText("DM Options", "69ccf0"))
    menu.title = title

    local items = {
        {
            text = "⚔️ Invite to Group",
            action = function()
                if menu.targetName then InviteByName(menu.targetName) end
            end
        },
        {
            text = "🔍 Who / Info",
            action = function()
                if menu.targetName then SendWho(menu.targetName) end
            end
        },
        {
            text = "📋 Popout History",
            action = function()
                if PUITalk.OpenCopyFrame then PUITalk:OpenCopyFrame(1) end
            end
        },
        {
            text = "🗑️ Clear History",
            action = function()
                if menu.targetKey then
                    PUITalk:ClearDMHistory(menu.targetKey)
                    if DEFAULT_CHAT_FRAME then
                        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[Primus Talk]: DM history cleared for " .. (menu.targetName or menu.targetKey), "69ccf0"))
                    end
                end
            end
        },
        {
            text = "❌ Close Conversation",
            action = function()
                if menu.targetKey then PUITalk:CloseDMConversation(menu.targetKey) end
            end
        },
    }

    local yOff = -26
    for i, it in ipairs(items) do
        local btn = CreateFrame("Button", nil, menu)
        btn:SetWidth(138)
        btn:SetHeight(18)
        btn:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, yOff)
        btn:SetBackdrop(Media:Fetch("border", "1Pixel"))
        btn:SetBackdropColor(0.08, 0.10, 0.14, 0.6)
        btn:SetBackdropBorderColor(0.15, 0.20, 0.30, 0.6)

        local bTxt = btn:CreateFontString(nil, "OVERLAY")
        bTxt:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
        bTxt:SetPoint("LEFT", btn, "LEFT", 6, 0)
        bTxt:SetText(it.text)

        btn.act = it.action
        btn:SetScript("OnEnter", function()
            this:SetBackdropColor(0.18, 0.26, 0.40, 1.0)
            this:SetBackdropBorderColor(0.40, 0.75, 1.0, 1.0)
        end)
        btn:SetScript("OnLeave", function()
            this:SetBackdropColor(0.08, 0.10, 0.14, 0.6)
            this:SetBackdropBorderColor(0.15, 0.20, 0.30, 0.6)
        end)
        btn:SetScript("OnClick", function()
            menu:Hide()
            if this.act then this.act() end
        end)

        yOff = yOff - 20
    end

    dmContextMenu = menu
    return menu
end

function PUITalk:OpenDMContextMenu(anchor, key, targetName)
    local menu = CreateDMContextMenu()
    menu.targetKey = key
    menu.targetName = targetName
    menu.title:SetText(Utils.ColorText(targetName or "Player", "69ccf0"))

    menu:ClearAllPoints()
    if anchor then
        local top = anchor:GetTop() or 0
        local screenHeight = UIParent:GetHeight() or 768
        if top > (screenHeight * 0.6) then
            menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        else
            menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
        end
    else
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        menu:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end

    menu:Show()
    menu:Raise()
end

-- =========================================================================
-- 2. TAB 2 MESSAGES VIEWPORT CONSTRUCTION
-- =========================================================================

function PUITalk:CreateMessagesView(viewport, master)
    if not viewport then return end

    local viewMessages = CreateFrame("Frame", "Primus_PUITalkViewMessages", viewport)
    viewMessages:SetAllPoints(viewport)
    viewMessages:SetBackdrop(Media:Fetch("border", "1Pixel"))
    viewMessages:SetBackdropColor(0.04, 0.04, 0.06, 0.8)
    viewMessages:SetBackdropBorderColor(0.15, 0.20, 0.30, 0.8)

    local dmTabBar = CreateFrame("Frame", "Primus_PUITalkDMTabBar", viewMessages)
    dmTabBar:SetPoint("TOPLEFT", viewMessages, "TOPLEFT", 4, -4)
    dmTabBar:SetPoint("TOPRIGHT", viewMessages, "TOPRIGHT", -4, -4)
    dmTabBar:SetHeight(22)
    viewMessages.dmTabBar = dmTabBar

    local dmMsgFrame = CreateFrame("ScrollingMessageFrame", "Primus_PUITalkDMFrame", viewMessages)
    dmMsgFrame:SetPoint("TOPLEFT", dmTabBar, "BOTTOMLEFT", 2, -4)
    dmMsgFrame:SetPoint("BOTTOMRIGHT", viewMessages, "BOTTOMRIGHT", -6, 6)
    dmMsgFrame:SetFont(Media:Fetch("font", "Default"), 10, "")
    dmMsgFrame:SetJustifyH("LEFT")
    dmMsgFrame:SetFading(false)
    dmMsgFrame:SetMaxLines(400)
    dmMsgFrame:EnableMouseWheel(true)
    dmMsgFrame:SetScript("OnMouseWheel", function()
        if arg1 > 0 then dmMsgFrame:ScrollUp() else dmMsgFrame:ScrollDown() end
    end)
    dmMsgFrame:SetScript("OnHyperlinkClick", function()
        PUITalk:HandleHyperlinkClick(arg1, arg2, arg3)
    end)
    viewMessages.msgFrame = dmMsgFrame
    master.viewMessages = viewMessages
    return viewMessages
end

-- =========================================================================
-- 3. DM SUB-TABS REFRESH & CONVERSATION CONTROLS
-- =========================================================================

function PUITalk:RefreshDMTabs()
    local masterFrame = self.masterFrame
    if not masterFrame or not masterFrame.viewMessages then return end

    local tabBar = masterFrame.viewMessages.dmTabBar
    local xOffset = 0
    local totalUnread = self:GetTotalUnreadCount()

    for key, tab in pairs(self.dmTabs) do
        local btn = tab.button
        if not btn then
            btn = CreateFrame("Button", "Primus_PUITalkDMTab_" .. key, tabBar)
            btn:SetHeight(20)
            btn:SetBackdrop(Media:Fetch("border", "1Pixel"))
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn.key = key

            local text = btn:CreateFontString(nil, "OVERLAY")
            text:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
            text:SetPoint("LEFT", btn, "LEFT", 6, 0)
            btn.text = text

            local close = CreateFrame("Button", nil, btn)
            close:SetWidth(12)
            close:SetHeight(12)
            close:SetPoint("RIGHT", btn, "RIGHT", -3, 0)
            close:SetBackdrop(Media:Fetch("border", "1Pixel"))
            close:SetBackdropColor(0.20, 0.08, 0.08, 0.8)
            close:SetBackdropBorderColor(0.50, 0.15, 0.15, 0.9)
            local cT = close:CreateFontString(nil, "OVERLAY")
            cT:SetFont(Media:Fetch("font", "Default"), 8, "")
            cT:SetPoint("CENTER", close, "CENTER", 0, 0)
            cT:SetText("x")
            cT:SetTextColor(0.9, 0.4, 0.4)
            close:SetScript("OnClick", function()
                local parentBtn = this:GetParent()
                if parentBtn and parentBtn.key then
                    PUITalk:CloseDMConversation(parentBtn.key)
                end
            end)
            btn.closeBtn = close

            btn:SetScript("OnClick", function()
                if arg1 == "RightButton" then
                    PUITalk:OpenDMContextMenu(this, this.key, this.targetName)
                else
                    PUITalk:SelectDMTab(this.key)
                end
            end)
            btn:SetScript("OnEnter", function()
                GameTooltip:SetOwner(this, "ANCHOR_TOP")
                GameTooltip:AddLine("✉️ DM: " .. (this.targetName or this.key), 0.4, 0.85, 1.0)
                GameTooltip:AddLine("• Left-Click: Select conversation.", 1, 1, 1)
                GameTooltip:AddLine("• Right-Click: Open DM player menu.", 1, 0.85, 0.2)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            tab.button = btn
        end

        btn.targetName = tab.name or key
        local unreadCount = self:GetUnreadCount(key)
        local displayName = tab.name or key

        if unreadCount > 0 then
            displayName = displayName .. string.format(" |cffffcc00(%d)|r", unreadCount)
        end

        btn.text:SetText(displayName)
        local textWidth = btn.text:GetStringWidth() or 40
        local btnWidth = math.max(65, textWidth + 24)
        btn:SetWidth(btnWidth)

        btn:ClearAllPoints()
        btn:SetPoint("LEFT", tabBar, "LEFT", xOffset, 0)
        xOffset = xOffset + btnWidth + 4

        if key == self.activeDMKey then
            btn:SetBackdropColor(0.18, 0.26, 0.40, 1.0)
            btn:SetBackdropBorderColor(0.40, 0.75, 1.0, 1.0)
            btn.text:SetTextColor(1.0, 1.0, 1.0)
        elseif unreadCount > 0 then
            btn:SetBackdropColor(0.40, 0.26, 0.08, 1.0)
            btn:SetBackdropBorderColor(1.00, 0.80, 0.20, 1.0)
            btn.text:SetTextColor(1.00, 0.92, 0.40)
        else
            btn:SetBackdropColor(0.08, 0.10, 0.14, 0.8)
            btn:SetBackdropBorderColor(0.20, 0.28, 0.40, 0.8)
            btn.text:SetTextColor(0.7, 0.7, 0.7)
        end
        btn:Show()
    end

    if masterFrame.tabMessages and masterFrame.tabMessages.text then
        if totalUnread > 0 then
            masterFrame.tabMessages.text:SetText(string.format("✉️ Messages |cffffcc00(%d)|r", totalUnread))
        else
            masterFrame.tabMessages.text:SetText("✉️ Messages")
        end
    end
end

function PUITalk:OpenDMConversation(targetName)
    if not targetName or targetName == "" then return end
    local key = string.lower(targetName)

    self:CreateMasterFrame()
    if self.masterFrame then self.masterFrame:Show() end

    if not self.dmTabs[key] then
        self.dmTabs[key] = {
            key = key,
            name = targetName,
            unread = 0,
        }
        if not self.conversationHistory[key] then
            self.conversationHistory[key] = {}
        end
    end

    self:SelectMasterTab(2)
    self:SelectDMTab(key)
end

function PUITalk:SelectDMTab(key)
    if not self.dmTabs[key] then return end
    self.activeDMKey = key
    self:MarkAsRead(key)

    local tab = self.dmTabs[key]
    if self.masterFrame and self.masterFrame.contextPill and self.masterFrame.contextPill.text then
        self.masterFrame.contextPill.text:SetText("To: " .. (tab.name or key))
    end

    if self.masterFrame and self.masterFrame.viewMessages and self.masterFrame.viewMessages.msgFrame then
        local msgFrame = self.masterFrame.viewMessages.msgFrame
        msgFrame:Clear()
        local history = self.conversationHistory[key] or {}
        local count = table.getn(history)
        for i = 1, count do
            local entry = history[i]
            msgFrame:AddMessage(entry.msg, entry.r, entry.g, entry.b)
        end
        msgFrame:ScrollToBottom()
    end

    self:RefreshDMTabs()
    if self.masterFrame and self.masterFrame.editBox and self.masterFrame:IsShown() and not UnitAffectingCombat("player") then
        self.masterFrame.editBox:SetFocus()
    end
end

function PUITalk:AddDMMessage(key, sender, text, isOutgoing, r, g, b)
    if not self.conversationHistory[key] then
        self.conversationHistory[key] = {}
    end

    local timestamp = self:GetTimestamp()
    local formattedMsg = ""

    if isOutgoing then
        formattedMsg = string.format("%s |cffffd100[You]:|r %s", timestamp, text)
        r, g, b = r or 1.0, g or 1.0, b or 0.8
    else
        formattedMsg = string.format("%s |cff00ccff[%s]:|r %s", timestamp, sender, text)
        r, g, b = r or 0.4, g or 0.9, b or 1.0
    end

    table.insert(self.conversationHistory[key], { msg = formattedMsg, r = r, g = g, b = b })

    local isViewingThisDM = self.masterFrame and self.masterFrame:IsShown() and (self.db:Get("activeMasterTab") == 2) and (self.activeDMKey == key)

    if isViewingThisDM then
        if self.masterFrame.viewMessages and self.masterFrame.viewMessages.msgFrame then
            self.masterFrame.viewMessages.msgFrame:AddMessage(formattedMsg, r, g, b)
            self.masterFrame.viewMessages.msgFrame:ScrollToBottom()
        end
    else
        if not isOutgoing then
            self:IncrementUnread(key)
        end
        self:RefreshDMTabs()
    end

    if self.db:Get("playSounds", true) and not isOutgoing then
        PlaySound("TellMessage")
    end
end
