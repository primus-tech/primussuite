--[[
    PrimusUI Module: PUITalk (Master Frame Container, Tab Rail, Resize Grip & Pulse Engine)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    - Master container frame creation with movable & resizable properties.
    - Top 3-Tab Header Rail ([💬 Chat], [✉️ Messages], [👥 Social], [⚙️ Filters], [📋 Select]).
    - Master tab switching logic and viewport activation.
    - Interactive bottom-right corner resize grip handle.
    - Animated unread whisper tab pulse engine (OnUpdate).
    - PUIMover frame registration.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus or not Primus.PUITalk then return end

local PUITalk  = Primus.PUITalk
local Media    = Primus.Media
local Utils    = Primus.Utils
local PUIMover = Primus.PUIMover

local masterFrame = nil

-- =========================================================================
-- 1. MASTER FRAME CONSTRUCTION & LAYOUT
-- =========================================================================

function PUITalk:CreateMasterFrame()
    if masterFrame then return masterFrame end

    local f = CreateFrame("Frame", "Primus_PUITalkFrame", UIParent)
    f:SetWidth(self.db:Get("width") or 450)
    f:SetHeight(self.db:Get("height") or 230)
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 24, 36)
    f:SetBackdrop(Media:Fetch("border", "1Pixel"))
    f:SetBackdropColor(0.06, 0.07, 0.09, 0.95)
    f:SetBackdropBorderColor(0.20, 0.45, 0.85, 1.0)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:Show()

    -- ---------------------------------------------------------------------
    -- Top Master Rail (3 Master Tabs + Utility Buttons)
    -- ---------------------------------------------------------------------
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    header:SetHeight(26)
    header:SetBackdrop(Media:Fetch("border", "1Pixel"))
    header:SetBackdropColor(0.10, 0.13, 0.18, 1.0)
    header:SetBackdropBorderColor(0.20, 0.35, 0.60, 1.0)
    f.header = header

    -- Tab 1: [💬 Chat]
    local tabChat = CreateFrame("Button", "Primus_PUITalkTab_1", header)
    tabChat:SetWidth(80)
    tabChat:SetHeight(20)
    tabChat:SetPoint("LEFT", header, "LEFT", 4, 0)
    tabChat:SetBackdrop(Media:Fetch("border", "1Pixel"))
    tabChat:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local tabChatText = tabChat:CreateFontString(nil, "OVERLAY")
    tabChatText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    tabChatText:SetPoint("CENTER", 0, 0)
    tabChatText:SetText("💬 Chat")
    tabChat.text = tabChatText
    tabChat:SetScript("OnClick", function()
        if arg1 == "RightButton" then
            if PUITalk.ToggleChannelContextMenu then
                PUITalk:ToggleChannelContextMenu(this)
            end
        else
            PUITalk:SelectMasterTab(1)
        end
    end)
    tabChat:SetScript("OnEnter", function()
        this:SetBackdropColor(0.18, 0.26, 0.40, 1.0)
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:AddLine("💬 Chat Stream", 0.4, 0.85, 1.0)
        GameTooltip:AddLine("• Left-Click: Switch to Chat tab.", 1, 1, 1)
        GameTooltip:AddLine("• Right-Click: Open Channel Filter Menu.", 1, 0.85, 0.2)
        GameTooltip:Show()
    end)
    tabChat:SetScript("OnLeave", function()
        if (PUITalk.db:Get("activeMasterTab") or 1) ~= 1 then
            this:SetBackdropColor(0.08, 0.10, 0.14, 0.8)
        end
        GameTooltip:Hide()
    end)
    f.tabChat = tabChat

    -- Tab 2: [✉️ Messages]
    local tabMessages = CreateFrame("Button", "Primus_PUITalkTab_2", header)
    tabMessages:SetWidth(95)
    tabMessages:SetHeight(20)
    tabMessages:SetPoint("LEFT", tabChat, "RIGHT", 4, 0)
    tabMessages:SetBackdrop(Media:Fetch("border", "1Pixel"))
    local tabMsgText = tabMessages:CreateFontString(nil, "OVERLAY")
    tabMsgText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    tabMsgText:SetPoint("CENTER", 0, 0)
    tabMsgText:SetText("✉️ Messages")
    tabMessages.text = tabMsgText
    tabMessages:SetScript("OnClick", function() PUITalk:SelectMasterTab(2) end)
    f.tabMessages = tabMessages

    -- Tab 3: [👥 Social]
    local tabSocial = CreateFrame("Button", "Primus_PUITalkTab_3", header)
    tabSocial:SetWidth(85)
    tabSocial:SetHeight(20)
    tabSocial:SetPoint("LEFT", tabMessages, "RIGHT", 4, 0)
    tabSocial:SetBackdrop(Media:Fetch("border", "1Pixel"))
    local tabSocialText = tabSocial:CreateFontString(nil, "OVERLAY")
    tabSocialText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    tabSocialText:SetPoint("CENTER", 0, 0)
    tabSocialText:SetText("👥 Social")
    tabSocial.text = tabSocialText
    tabSocial:SetScript("OnClick", function() PUITalk:SelectMasterTab(3) end)
    f.tabSocial = tabSocial

    -- Header Controls on Right: [ 📋 Select ] & [ ⚙️ Filters ]
    local selectBtn = CreateFrame("Button", "Primus_PUITalkHeaderSelectBtn", header)
    selectBtn:SetWidth(65)
    selectBtn:SetHeight(20)
    selectBtn:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    selectBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    selectBtn:SetBackdropColor(0.12, 0.18, 0.28, 0.95)
    selectBtn:SetBackdropBorderColor(0.30, 0.60, 0.95, 1.0)
    local slText = selectBtn:CreateFontString(nil, "OVERLAY")
    slText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    slText:SetPoint("CENTER", 0, 0)
    slText:SetText("📋 Select")
    slText:SetTextColor(0.45, 0.85, 1.0)
    selectBtn.text = slText

    selectBtn:SetScript("OnEnter", function()
        this:SetBackdropColor(0.20, 0.32, 0.50, 1.0)
        this:SetBackdropBorderColor(0.50, 0.85, 1.0, 1.0)
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:AddLine("Primus Selectable Chat", 0.4, 0.85, 1.0)
        GameTooltip:AddLine("Click to toggle Selectable Text Mode in this window.", 1, 1, 1)
        GameTooltip:AddLine("• Drag mouse over text to highlight and select.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("• Press Ctrl+C (Cmd+C) to copy highlighted text to clipboard.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("• Shift-Click to open full Popout Copy Dialog.", 1, 0.85, 0.2)
        GameTooltip:Show()
    end)
    selectBtn:SetScript("OnLeave", function()
        this:SetBackdropColor(0.12, 0.18, 0.28, 0.95)
        this:SetBackdropBorderColor(0.30, 0.60, 0.95, 1.0)
        GameTooltip:Hide()
    end)
    selectBtn:SetScript("OnClick", function()
        if IsShiftKeyDown() then
            if PUITalk.OpenCopyFrame then PUITalk:OpenCopyFrame(1) end
        else
            if PUITalk.ToggleSelectableMode then PUITalk:ToggleSelectableMode() end
        end
    end)
    f.selectBtn = selectBtn

    local filterBtn = CreateFrame("Button", "Primus_PUITalkHeaderFilterBtn", header)
    filterBtn:SetWidth(65)
    filterBtn:SetHeight(20)
    filterBtn:SetPoint("RIGHT", selectBtn, "LEFT", -4, 0)
    filterBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    filterBtn:SetBackdropColor(0.12, 0.18, 0.28, 0.95)
    filterBtn:SetBackdropBorderColor(0.30, 0.60, 0.95, 1.0)
    local flText = filterBtn:CreateFontString(nil, "OVERLAY")
    flText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    flText:SetPoint("CENTER", 0, 0)
    flText:SetText("⚙️ Filters")
    flText:SetTextColor(0.45, 0.85, 1.0)
    filterBtn.text = flText

    filterBtn:SetScript("OnEnter", function()
        this:SetBackdropColor(0.20, 0.32, 0.50, 1.0)
        this:SetBackdropBorderColor(0.50, 0.85, 1.0, 1.0)
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:AddLine("⚙️ Channel Filters", 0.4, 0.85, 1.0)
        GameTooltip:AddLine("Click to open the Chat Channel Filter Menu.", 1, 1, 1)
        GameTooltip:AddLine("Toggle Say, Trade, General, Loot, Monster, etc.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    filterBtn:SetScript("OnLeave", function()
        this:SetBackdropColor(0.12, 0.18, 0.28, 0.95)
        this:SetBackdropBorderColor(0.30, 0.60, 0.95, 1.0)
        GameTooltip:Hide()
    end)
    filterBtn:SetScript("OnClick", function()
        if PUITalk.ToggleChannelContextMenu then
            PUITalk:ToggleChannelContextMenu(this)
        end
    end)
    f.filterBtn = filterBtn

    -- ---------------------------------------------------------------------
    -- Create Child Components (Input Bar & Viewports)
    -- ---------------------------------------------------------------------
    if PUITalk.CreateUniversalInput then
        PUITalk:CreateUniversalInput(f)
    end

    local viewport = CreateFrame("Frame", "Primus_PUITalkViewport", f)
    viewport:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    viewport:SetPoint("BOTTOMRIGHT", f.footer or f, "TOPRIGHT", 0, 4)
    f.viewport = viewport

    if PUITalk.CreateChatView then
        PUITalk:CreateChatView(viewport, f)
    end
    if PUITalk.CreateMessagesView then
        PUITalk:CreateMessagesView(viewport, f)
    end
    if PUITalk.CreateSocialView then
        PUITalk:CreateSocialView(viewport, f)
    end

    -- ---------------------------------------------------------------------
    -- Interactive Bottom-Right Corner Resize Grip Handle
    -- ---------------------------------------------------------------------
    f:SetResizable(true)
    f:SetMinResize(360, 180)
    f:SetMaxResize(800, 600)

    local resizeGrip = CreateFrame("Button", "Primus_PUITalkResizeGrip", f)
    resizeGrip:SetWidth(14)
    resizeGrip:SetHeight(14)
    resizeGrip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    resizeGrip:EnableMouse(true)
    resizeGrip:RegisterForDrag("LeftButton")
    resizeGrip:SetBackdrop(Media:Fetch("border", "1Pixel"))
    resizeGrip:SetBackdropColor(0.12, 0.22, 0.38, 0.6)
    resizeGrip:SetBackdropBorderColor(0.30, 0.60, 1.0, 0.8)

    local gripDot = resizeGrip:CreateTexture(nil, "OVERLAY")
    gripDot:SetWidth(6)
    gripDot:SetHeight(6)
    gripDot:SetPoint("BOTTOMRIGHT", resizeGrip, "BOTTOMRIGHT", -2, 2)
    gripDot:SetTexture("Interface\\Buttons\\WHITE8X8")
    gripDot:SetVertexColor(0.4, 0.75, 1.0, 0.9)

    resizeGrip:SetScript("OnDragStart", function()
        f:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        PUITalk.db:Set("width", f:GetWidth())
        PUITalk.db:Set("height", f:GetHeight())
    end)
    resizeGrip:SetScript("OnEnter", function()
        this:SetBackdropColor(0.20, 0.35, 0.60, 0.9)
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Resize Window", 0.4, 0.85, 1.0)
        GameTooltip:AddLine("Click and drag to resize chat container.", 1, 1, 1)
        GameTooltip:Show()
    end)
    resizeGrip:SetScript("OnLeave", function()
        this:SetBackdropColor(0.12, 0.22, 0.38, 0.6)
        GameTooltip:Hide()
    end)
    f.resizeGrip = resizeGrip

    -- ---------------------------------------------------------------------
    -- Unread Whisper Master Tab Pulse Animation (OnUpdate)
    -- ---------------------------------------------------------------------
    f:SetScript("OnUpdate", function()
        local unreads = PUITalk:GetTotalUnreadCount()
        local curTab = PUITalk.db:Get("activeMasterTab") or 1

        if unreads > 0 and curTab ~= 2 then
            local alpha = 0.40 + 0.60 * math.abs(math.sin(GetTime() * 3.5))
            f.tabMessages:SetBackdropColor(0.42 * alpha, 0.28 * alpha, 0.08 * alpha, 0.95)
            f.tabMessages:SetBackdropBorderColor(1.0 * alpha, 0.80 * alpha, 0.20 * alpha, 1.0)
            f.tabMessages.text:SetTextColor(1.0, 0.92, 0.40)
            f.tabMessages.text:SetText(string.format("✉️ Messages |cffffcc00(%d)|r", unreads))
        else
            if curTab == 2 then
                f.tabMessages:SetBackdropColor(0.18, 0.26, 0.40, 1.0)
                f.tabMessages:SetBackdropBorderColor(0.40, 0.75, 1.0, 1.0)
                f.tabMessages.text:SetTextColor(1.0, 1.0, 1.0)
            else
                f.tabMessages:SetBackdropColor(0.08, 0.10, 0.14, 0.8)
                f.tabMessages:SetBackdropBorderColor(0.20, 0.28, 0.40, 0.8)
                f.tabMessages.text:SetTextColor(0.7, 0.7, 0.7)
            end
            f.tabMessages.text:SetText("✉️ Messages")
        end
    end)

    -- Register with PUIMover
    local mover = PUIMover or Primus.PUIMover
    if mover and mover.Register then
        mover:Register(f, "PUITalk", "PUITalk: Unified Chat & Social Hub", "SOCIAL")
    end

    masterFrame = f
    self.masterFrame = f
    PUITalk:SelectMasterTab(self.db:Get("activeMasterTab") or 1)
    return f
end

-- =========================================================================
-- 2. MASTER TAB SWITCHING LOGIC
-- =========================================================================

function PUITalk:SelectMasterTab(tabIndex)
    if not masterFrame then return end
    masterFrame:Show()
    self.db:Set("activeMasterTab", tabIndex)

    -- Update Tab Button Visuals
    local tabs = { masterFrame.tabChat, masterFrame.tabMessages, masterFrame.tabSocial }
    for i = 1, 3 do
        local btn = tabs[i]
        if btn then
            if i == tabIndex then
                btn:SetBackdropColor(0.18, 0.26, 0.40, 1.0)
                btn:SetBackdropBorderColor(0.40, 0.75, 1.0, 1.0)
                if btn.text then btn.text:SetTextColor(1.0, 1.0, 1.0) end
            else
                btn:SetBackdropColor(0.08, 0.10, 0.14, 0.8)
                btn:SetBackdropBorderColor(0.20, 0.28, 0.40, 0.8)
                if btn.text then btn.text:SetTextColor(0.7, 0.7, 0.7) end
            end
        end
    end

    -- Reset selectable overlays when switching master tabs
    if masterFrame.viewChat and masterFrame.viewChat.selectOverlay then
        masterFrame.viewChat.selectOverlay:Hide()
    end
    if masterFrame.viewMessages and masterFrame.viewMessages.selectOverlay then
        masterFrame.viewMessages.selectOverlay:Hide()
    end

    -- Toggle Viewports
    if masterFrame.viewChat then masterFrame.viewChat:Hide() end
    if masterFrame.viewMessages then masterFrame.viewMessages:Hide() end
    if masterFrame.viewSocial then masterFrame.viewSocial:Hide() end

    if tabIndex == 1 then
        if masterFrame.viewChat then
            masterFrame.viewChat:Show()
            if masterFrame.viewChat.msgFrame then masterFrame.viewChat.msgFrame:Show() end
        end
        if masterFrame.contextPill and masterFrame.contextPill.text then
            masterFrame.contextPill.text:SetText("#Say")
        end
    elseif tabIndex == 2 then
        if masterFrame.viewMessages then
            masterFrame.viewMessages:Show()
            if masterFrame.viewMessages.msgFrame then masterFrame.viewMessages.msgFrame:Show() end
        end
        if self.RefreshDMTabs then self:RefreshDMTabs() end
        if masterFrame.contextPill and masterFrame.contextPill.text then
            if self.activeDMKey and self.dmTabs[self.activeDMKey] then
                masterFrame.contextPill.text:SetText("To: " .. (self.dmTabs[self.activeDMKey].name or self.activeDMKey))
            else
                masterFrame.contextPill.text:SetText("Whisper")
            end
        end
    elseif tabIndex == 3 then
        if masterFrame.viewSocial then
            masterFrame.viewSocial:Show()
        end
        if masterFrame.contextPill and masterFrame.contextPill.text then
            masterFrame.contextPill.text:SetText("Social")
        end
        if self.RefreshSocialView then self:RefreshSocialView() end
    end
end
