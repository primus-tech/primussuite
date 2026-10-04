--[[
    PrimusUI Module: PUITalk (Selectable Overlay, Copy Dialog & URL Popup)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    - In-place drag-highlight selectable chat overlay (ToggleSelectableMode).
    - Popout full copy modal dialog (Primus_ChatCopyFrame).
    - Clickable web link URL copy popup modal (Primus_URLCopyFrame).
    - Safe ScrollFrame vertical scrolling helper.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus or not Primus.PUITalk then return end

local PUITalk = Primus.PUITalk
local Media   = Primus.Media
local Utils   = Primus.Utils

local copyFrame = nil
local urlFrame  = nil

-- =========================================================================
-- 1. SAFE SCROLLFRAME VERTICAL HELPER
-- =========================================================================

local function ScrollFrameToBottom(scrollFrame)
    if not scrollFrame then return end
    if scrollFrame.UpdateScrollChildRect then
        scrollFrame:UpdateScrollChildRect()
    end
    local maxScroll = scrollFrame:GetVerticalScrollRange() or 0
    scrollFrame:SetVerticalScroll(maxScroll)
    local sName = scrollFrame:GetName()
    if sName then
        local sb = _G[sName .. "ScrollBar"]
        if sb and sb.SetValue then
            sb:SetValue(maxScroll)
        end
    end
end

-- =========================================================================
-- 2. IN-PLACE SELECTABLE CHAT OVERLAY
-- =========================================================================

function PUITalk:CreateSelectableOverlay(parent, modeName)
    if not parent then return nil end
    if parent.selectOverlay then return parent.selectOverlay end

    local overlay = CreateFrame("Frame", "Primus_PUITalkSelectOverlay_" .. (modeName or "Chat"), parent)
    overlay:SetAllPoints(parent)
    overlay:SetFrameLevel(parent:GetFrameLevel() + 15)
    overlay:SetBackdrop(Media:Fetch("border", "1Pixel"))
    overlay:SetBackdropColor(0.04, 0.05, 0.07, 0.98)
    overlay:SetBackdropBorderColor(0.20, 0.50, 0.90, 1.0)
    overlay:EnableMouse(true)
    overlay:Hide()

    local topBar = CreateFrame("Frame", nil, overlay)
    topBar:SetPoint("TOPLEFT", overlay, "TOPLEFT", 4, -4)
    topBar:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", -4, -4)
    topBar:SetHeight(20)
    topBar:SetBackdrop(Media:Fetch("border", "1Pixel"))
    topBar:SetBackdropColor(0.10, 0.14, 0.22, 1.0)
    topBar:SetBackdropBorderColor(0.25, 0.45, 0.75, 1.0)

    local backBtn = CreateFrame("Button", nil, topBar)
    backBtn:SetWidth(110)
    backBtn:SetHeight(16)
    backBtn:SetPoint("LEFT", topBar, "LEFT", 2, 0)
    backBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    backBtn:SetBackdropColor(0.15, 0.20, 0.30, 1.0)
    backBtn:SetBackdropBorderColor(0.30, 0.60, 0.90, 1.0)
    local bkTxt = backBtn:CreateFontString(nil, "OVERLAY")
    bkTxt:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    bkTxt:SetPoint("CENTER", 0, 0)
    bkTxt:SetText("◀ Return to Live")
    backBtn.text = bkTxt
    backBtn:SetScript("OnClick", function()
        PUITalk:ToggleSelectableMode()
    end)

    local selectAllBtn = CreateFrame("Button", nil, topBar)
    selectAllBtn:SetWidth(75)
    selectAllBtn:SetHeight(16)
    selectAllBtn:SetPoint("LEFT", backBtn, "RIGHT", 4, 0)
    selectAllBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    selectAllBtn:SetBackdropColor(0.15, 0.25, 0.15, 1.0)
    selectAllBtn:SetBackdropBorderColor(0.30, 0.80, 0.30, 1.0)
    local saTxt = selectAllBtn:CreateFontString(nil, "OVERLAY")
    saTxt:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    saTxt:SetPoint("CENTER", 0, 0)
    saTxt:SetText("Select All")
    selectAllBtn.text = saTxt

    local infoText = topBar:CreateFontString(nil, "OVERLAY")
    infoText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    infoText:SetPoint("LEFT", selectAllBtn, "RIGHT", 6, 0)
    infoText:SetPoint("RIGHT", topBar, "RIGHT", -4, 0)
    infoText:SetJustifyH("LEFT")
    infoText:SetText(Utils.ColorText("Selectable Mode", "69ccf0") .. " |cffaaaaaa// Drag to highlight, Ctrl+C to copy|r")

    local scroll = CreateFrame("ScrollFrame", "Primus_PUITalkSelectScroll_" .. (modeName or "Chat"), overlay, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -24, 6)

    local editBox = CreateFrame("EditBox", "Primus_PUITalkSelectEdit_" .. (modeName or "Chat"), scroll)
    editBox:SetWidth(380)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFont(Media:Fetch("font", "Default"), 10, "")
    editBox:SetTextColor(0.95, 0.95, 0.95, 1.0)
    editBox:SetScript("OnEscapePressed", function()
        PUITalk:ToggleSelectableMode()
    end)
    editBox:SetScript("OnTextChanged", function()
        local s = this:GetParent()
        if s and s.UpdateScrollChildRect then
            s:UpdateScrollChildRect()
        end
    end)
    scroll:SetScrollChild(editBox)

    selectAllBtn:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText(0)
    end)

    overlay.scroll = scroll
    overlay.editBox = editBox
    overlay.topBar = topBar
    parent.selectOverlay = overlay
    return overlay
end

function PUITalk:ToggleSelectableMode(tabIndex)
    tabIndex = tabIndex or self.db:Get("activeMasterTab") or 1
    local masterFrame = self.masterFrame
    if not masterFrame then return end

    if tabIndex == 1 then
        local viewChat = masterFrame.viewChat
        if not viewChat then return end
        local overlay = viewChat.selectOverlay or self:CreateSelectableOverlay(viewChat, "Chat")

        if overlay:IsShown() then
            overlay:Hide()
            if viewChat.msgFrame then viewChat.msgFrame:Show() end
        else
            local buffer = self.chatBuffers[1] or {}
            local totalLines = table.getn(buffer)
            local lines = {}
            for i = 1, totalLines do
                local entry = buffer[i]
                local clean = self:CleanChatText(entry.text)
                table.insert(lines, string.format("[%s] %s", entry.time, clean))
            end
            local fullText = table.concat(lines, "\n")
            overlay.editBox:SetText(fullText)
            overlay:Show()
            if viewChat.msgFrame then viewChat.msgFrame:Hide() end
            overlay.editBox:SetFocus()
            ScrollFrameToBottom(overlay.scroll)
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[Primus Talk]: Selectable chat mode active! Click & drag mouse to highlight, Ctrl+C to copy.", "69ccf0"))
            end
        end
    elseif tabIndex == 2 then
        local viewMessages = masterFrame.viewMessages
        if not viewMessages then return end
        local overlay = viewMessages.selectOverlay or self:CreateSelectableOverlay(viewMessages, "Messages")

        if overlay:IsShown() then
            overlay:Hide()
            if viewMessages.msgFrame then viewMessages.msgFrame:Show() end
        else
            local activeKey = self.activeDMKey or ""
            local history = self.conversationHistory[activeKey] or {}
            local count = table.getn(history)
            local lines = {}
            for i = 1, count do
                local entry = history[i]
                local clean = self:CleanChatText(entry.msg)
                table.insert(lines, clean)
            end
            local fullText = table.concat(lines, "\n")
            overlay.editBox:SetText(fullText)
            overlay:Show()
            if viewMessages.msgFrame then viewMessages.msgFrame:Hide() end
            overlay.editBox:SetFocus()
            ScrollFrameToBottom(overlay.scroll)
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[Primus Talk]: Selectable messages mode active! Click & drag mouse to highlight, Ctrl+C to copy.", "69ccf0"))
            end
        end
    end
end

-- =========================================================================
-- 3. POPOUT COPY MODAL & URL DIALOG
-- =========================================================================

function PUITalk:CreateCopyFrame()
    if copyFrame then return copyFrame end

    local f = CreateFrame("Frame", "Primus_ChatCopyFrame", UIParent)
    f:SetWidth(580)
    f:SetHeight(420)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop(Media:Fetch("border", "1Pixel"))
    f:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
    f:SetBackdropBorderColor(0.20, 0.45, 0.85, 1.0)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:Hide()

    tinsert(UISpecialFrames, "Primus_ChatCopyFrame")

    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    header:SetHeight(28)
    header:SetBackdrop(Media:Fetch("border", "1Pixel"))
    header:SetBackdropColor(0.10, 0.14, 0.22, 1.0)
    header:SetBackdropBorderColor(0.20, 0.40, 0.70, 1.0)

    local title = header:CreateFontString(nil, "OVERLAY")
    title:SetFont(Media:Fetch("font", "Default"), 11, "OUTLINE")
    title:SetPoint("LEFT", header, "LEFT", 8, 0)
    title:SetText(Utils.ColorText("Primus Chat Copy", "69ccf0") .. " |cffaaaaaa// Select text & Press Ctrl+C|r")
    f.titleText = title

    local closeX = CreateFrame("Button", nil, header)
    closeX:SetWidth(18)
    closeX:SetHeight(18)
    closeX:SetPoint("RIGHT", header, "RIGHT", -5, 0)
    closeX:SetBackdrop(Media:Fetch("border", "1Pixel"))
    closeX:SetBackdropColor(0.6, 0.1, 0.1, 0.8)
    closeX:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
    local cX = closeX:CreateFontString(nil, "OVERLAY")
    cX:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    cX:SetPoint("CENTER", closeX, "CENTER", 0, 0)
    cX:SetText("X")
    closeX:SetScript("OnClick", function() f:Hide() end)

    local editContainer = CreateFrame("Frame", nil, f)
    editContainer:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    editContainer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 40)
    editContainer:SetBackdrop(Media:Fetch("border", "1Pixel"))
    editContainer:SetBackdropColor(0.03, 0.04, 0.05, 1.0)
    editContainer:SetBackdropBorderColor(0.18, 0.22, 0.30, 1.0)

    local scroll = CreateFrame("ScrollFrame", "Primus_ChatCopyScrollFrame", editContainer, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", editContainer, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", editContainer, "BOTTOMRIGHT", -26, 6)

    local editBox = CreateFrame("EditBox", "Primus_ChatCopyEditBox", scroll)
    editBox:SetWidth(520)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFont(Media:Fetch("font", "Default"), 10, "")
    editBox:SetTextColor(0.95, 0.95, 0.95, 1.0)
    editBox:SetScript("OnEscapePressed", function() f:Hide() end)
    editBox:SetScript("OnTextChanged", function()
        local s = this:GetParent()
        if s and s.UpdateScrollChildRect then
            s:UpdateScrollChildRect()
        end
    end)
    scroll:SetScrollChild(editBox)
    f.editBox = editBox
    f.scroll = scroll

    local footer = CreateFrame("Frame", nil, f)
    footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 4)
    footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    footer:SetHeight(32)

    local selectBtn = CreateFrame("Button", nil, footer)
    selectBtn:SetWidth(130)
    selectBtn:SetHeight(22)
    selectBtn:SetPoint("LEFT", footer, "LEFT", 4, 0)
    selectBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    selectBtn:SetBackdropColor(0.15, 0.25, 0.15, 1.0)
    selectBtn:SetBackdropBorderColor(0.30, 0.80, 0.30, 1.0)
    local sTxt = selectBtn:CreateFontString(nil, "OVERLAY")
    sTxt:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    sTxt:SetPoint("CENTER", 0, 0)
    sTxt:SetText("Select All / Copy")
    selectBtn:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText(0)
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[Primus Talk]: Text highlighted! Press Ctrl+C to copy.", "69ccf0"))
        end
    end)

    local closeBtn = CreateFrame("Button", nil, footer)
    closeBtn:SetWidth(75)
    closeBtn:SetHeight(22)
    closeBtn:SetPoint("RIGHT", footer, "RIGHT", -4, 0)
    closeBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    closeBtn:SetBackdropColor(0.15, 0.15, 0.18, 1.0)
    closeBtn:SetBackdropBorderColor(0.35, 0.35, 0.40, 1.0)
    local clMainTxt = closeBtn:CreateFontString(nil, "OVERLAY")
    clMainTxt:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    clMainTxt:SetPoint("CENTER", 0, 0)
    clMainTxt:SetText("Close")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    copyFrame = f
    return f
end

function PUITalk:OpenCopyFrame(chatIndex)
    local f = self:CreateCopyFrame()
    local buffer = self.chatBuffers[1] or {}
    local totalLines = table.getn(buffer)
    local lines = {}
    for i = 1, totalLines do
        local entry = buffer[i]
        local clean = self:CleanChatText(entry.text)
        table.insert(lines, string.format("[%s] %s", entry.time, clean))
    end
    local fullText = table.concat(lines, "\n")
    f.editBox:SetText(fullText)
    f:Show()
    f:Raise()
    f.editBox:SetFocus()
    f.editBox:HighlightText(0)
end

function PUITalk:ShowURLCopyPopup(url)
    if Utils and Utils.ShowURLDialog then
        Utils.ShowURLDialog(url, "Primus Web Link Copy")
    end
end
