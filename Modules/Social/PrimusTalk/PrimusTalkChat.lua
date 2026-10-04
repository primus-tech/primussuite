--[[
    PrimusUI Module: PUITalk (Tab 1 Chat Stream View & Message Dispatcher)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    - Tab 1 Viewport construction (Primus_PUITalkViewChat).
    - ScrollingMessageFrame stream with mousewheel fast scrolling and shift jumps.
    - Message buffering (up to 400 entries), timestamping, and URL linkification.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus or not Primus.PUITalk then return end

local PUITalk = Primus.PUITalk
local Media   = Primus.Media

-- =========================================================================
-- 1. TAB 1 CHAT VIEWPORT CONSTRUCTION
-- =========================================================================

function PUITalk:CreateChatView(viewport, master)
    if not viewport then return end

    local viewChat = CreateFrame("Frame", "Primus_PUITalkViewChat", viewport)
    viewChat:SetAllPoints(viewport)
    viewChat:SetBackdrop(Media:Fetch("border", "1Pixel"))
    viewChat:SetBackdropColor(0.04, 0.04, 0.06, 0.6)
    viewChat:SetBackdropBorderColor(0.15, 0.20, 0.30, 0.6)

    local chatMsgFrame = CreateFrame("ScrollingMessageFrame", "Primus_PUITalkChatMsgStream", viewChat)
    chatMsgFrame:SetPoint("TOPLEFT", viewChat, "TOPLEFT", 6, -4)
    chatMsgFrame:SetPoint("BOTTOMRIGHT", viewChat, "BOTTOMRIGHT", -6, 4)
    chatMsgFrame:SetFont(Media:Fetch("font", "Default"), 10, "")
    chatMsgFrame:SetJustifyH("LEFT")
    chatMsgFrame:SetFading(false)
    chatMsgFrame:SetMaxLines(500)
    chatMsgFrame:EnableMouseWheel(true)
    chatMsgFrame:SetScript("OnMouseWheel", function()
        if arg1 > 0 then
            if IsShiftKeyDown() then
                chatMsgFrame:ScrollToTop()
            else
                chatMsgFrame:ScrollUp()
                chatMsgFrame:ScrollUp()
                chatMsgFrame:ScrollUp()
            end
        else
            if IsShiftKeyDown() then
                chatMsgFrame:ScrollToBottom()
            else
                chatMsgFrame:ScrollDown()
                chatMsgFrame:ScrollDown()
                chatMsgFrame:ScrollDown()
            end
        end
    end)
    chatMsgFrame:SetScript("OnHyperlinkClick", function()
        PUITalk:HandleHyperlinkClick(arg1, arg2, arg3)
    end)
    viewChat.msgFrame = chatMsgFrame
    master.viewChat = viewChat
    return viewChat
end

-- =========================================================================
-- 2. ADD MESSAGE TO PUITALK CHAT STREAM
-- =========================================================================

function PUITalk:AddChatMessage(text, r, g, b, isRaw)
    if not text or text == "" then return end

    r = r or 1.0
    g = g or 1.0
    b = b or 1.0

    local timeStamp = self:GetTimestamp()
    local cleanText = self:CleanChatText(text)
    table.insert(self.chatBuffers[1], { time = timeStamp, text = cleanText })
    if table.getn(self.chatBuffers[1]) > 400 then
        table.remove(self.chatBuffers[1], 1)
    end

    local formatted = text
    if not isRaw then
        formatted = self:LinkifyURLs(text)
    end

    if self.masterFrame and self.masterFrame.viewChat and self.masterFrame.viewChat.msgFrame then
        local msgFrame = self.masterFrame.viewChat.msgFrame
        msgFrame:AddMessage(formatted, r, g, b)
    end
end
