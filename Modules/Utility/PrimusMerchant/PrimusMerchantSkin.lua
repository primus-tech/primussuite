--[[
    PrimusUI Module: PUIMerchant (Auction House Dark Glass Skin & Dockable Control Flyout)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    1. PrimusUI Dark Glass 1-Pixel Theme for AuctionFrame (Browse, Bids, Auctions).
    2. User-Chosen Dockable Flyout Control Drawer (Left or Right side).
    3. Real-time Scanner UI with 15s Countdown, Progress Bar, and Scope Presets.
    4. Quick Shortcuts (Market Explorer, Deal Sniper, DB Pruning).
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIMerchant = Primus.PUIMerchant or {}
Primus.PUIMerchant = PUIMerchant

local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local Items   = Primus.Items
local Skinner = Primus.Skinner

local flyoutFrame = nil
local flyoutToggleBtn = nil
local scanActionButton = nil
local stopScanBtn = nil
local resetScanBtn = nil
local scanStatusLabel = nil
local scanCountdownLabel = nil
local scanProgressBar = nil
local pacingButtons = {}
local scopeDropdownBtn = nil
local scopeKeywordBox = nil

-- =========================================================================
-- AUCTION HOUSE FRAME DARK GLASS RESKIN
-- =========================================================================

local function SkinEditBox(editBox)
    if not editBox or editBox.primusSkinned then return end
    if Skinner and Skinner.SkinEditBox then
        Skinner:SkinEditBox(editBox)
    else
        editBox:SetBackdrop(Media:Fetch("border", "1Pixel"))
        editBox:SetBackdropColor(0.04, 0.04, 0.06, 0.90)
        editBox:SetBackdropBorderColor(0.25, 0.25, 0.30, 1.0)
        editBox:SetTextInsets(4, 4, 0, 0)
        editBox.primusSkinned = true
    end
end

local function SkinButton(btn, text, isAccent)
    if not btn or btn.primusSkinned then return end
    if Skinner and Skinner.SkinButton then
        Skinner:SkinButton(btn, text, isAccent)
    else
        btn:SetBackdrop(Media:Fetch("border", "1Pixel"))
        btn:SetBackdropColor(0.12, 0.12, 0.16, 0.95)
        btn:SetBackdropBorderColor(0.25, 0.25, 0.30, 1.0)
        if text and btn.SetText then btn:SetText(text) end

        btn:SetScript("OnEnter", function()
            btn:SetBackdropColor(0.20, 0.22, 0.28, 1.0)
            btn:SetBackdropBorderColor(0.40, 0.70, 1.00, 1.0)
        end)
        btn:SetScript("OnLeave", function()
            btn:SetBackdropColor(0.12, 0.12, 0.16, 0.95)
            btn:SetBackdropBorderColor(0.25, 0.25, 0.30, 1.0)
        end)
        btn.primusSkinned = true
    end
end

local function SkinTab(tab)
    if not tab or tab.primusSkinned then return end
    if Skinner and Skinner.SkinTab then
        Skinner:SkinTab(tab)
    else
        local tabName = tab:GetName()
        if _G[tabName .. "Left"] then _G[tabName .. "Left"]:Hide() end
        if _G[tabName .. "Middle"] then _G[tabName .. "Middle"]:Hide() end
        if _G[tabName .. "Right"] then _G[tabName .. "Right"]:Hide() end
        if _G[tabName .. "LeftDisabled"] then _G[tabName .. "LeftDisabled"]:Hide() end
        if _G[tabName .. "MiddleDisabled"] then _G[tabName .. "MiddleDisabled"]:Hide() end
        if _G[tabName .. "RightDisabled"] then _G[tabName .. "RightDisabled"]:Hide() end

        tab:SetBackdrop(Media:Fetch("border", "1Pixel"))
        tab:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
        tab:SetBackdropBorderColor(0.25, 0.25, 0.30, 1.0)

        -- Cyan active indicator underline
        local indicator = tab:CreateTexture(nil, "OVERLAY")
        indicator:SetTexture(Media:Fetch("texture", "Solid") or "Interface\\Buttons\\WHITE8X8")
        indicator:SetVertexColor(0.20, 0.75, 1.0, 1.0)
        indicator:SetHeight(2)
        indicator:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 2, 1)
        indicator:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -2, 1)
        indicator:Hide()
        tab.primusIndicator = indicator

        tab.primusSkinned = true
    end
end

function PUIMerchant:SkinAuctionHouse()
    if not AuctionFrame or AuctionFrame.primusSkinned then return end

    -- Hide Blizzard standard textures
    local texturesToHide = {
        "AuctionFrameTopLeft", "AuctionFrameTop", "AuctionFrameTopRight",
        "AuctionFrameBotLeft", "AuctionFrameBot", "AuctionFrameBotRight",
    }
    for _, texName in ipairs(texturesToHide) do
        local tex = _G[texName]
        if tex then tex:Hide() end
    end

    if AuctionPortraitTexture then AuctionPortraitTexture:Hide() end

    -- Main AuctionFrame Container
    if Skinner and Skinner.SkinFrame then
        Skinner:SkinFrame(AuctionFrame)
    else
        AuctionFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
        AuctionFrame:SetBackdropColor(0.06, 0.06, 0.09, 0.96)
        AuctionFrame:SetBackdropBorderColor(0.20, 0.20, 0.25, 1.0)
    end

    -- Title Styling
    if AuctionTitleText then
        AuctionTitleText:SetFont(Media:Fetch("font", "Default"), 13, "OUTLINE")
        AuctionTitleText:SetTextColor(0.4, 0.8, 1.0)
        AuctionTitleText:ClearAllPoints()
        AuctionTitleText:SetPoint("TOPLEFT", AuctionFrame, "TOPLEFT", 18, -12)
    end

    -- Close Button
    if AuctionFrameCloseButton then
        AuctionFrameCloseButton:SetPoint("TOPRIGHT", AuctionFrame, "TOPRIGHT", 2, -10)
    end

    -- Tabs
    for i = 1, 3 do
        local tab = _G["AuctionFrameTab" .. i]
        if tab then
            SkinTab(tab)
        end
    end

    -- Browse Tab Elements
    SkinEditBox(BrowseName)
    SkinEditBox(BrowseMinLevel)
    SkinEditBox(BrowseMaxLevel)
    SkinButton(BrowseSearchButton, "Search")
    SkinButton(BrowseResetButton, "Reset")
    SkinButton(BrowseBidButton, "Bid")
    SkinButton(BrowseBuyoutButton, "Buyout")
    SkinButton(BrowseCloseButton, "Close")

    -- Auctions Tab Elements
    if StartPriceGold then SkinEditBox(StartPriceGold) end
    if StartPriceSilver then SkinEditBox(StartPriceSilver) end
    if StartPriceCopper then SkinEditBox(StartPriceCopper) end
    if BuyoutPriceGold then SkinEditBox(BuyoutPriceGold) end
    if BuyoutPriceSilver then SkinEditBox(BuyoutPriceSilver) end
    if BuyoutPriceCopper then SkinEditBox(BuyoutPriceCopper) end
    if AuctionsCreateAuctionButton then SkinButton(AuctionsCreateAuctionButton, "Create Auction") end
    if AuctionsCancelAuctionButton then SkinButton(AuctionsCancelAuctionButton, "Cancel Auction") end
    if AuctionsCloseButton then SkinButton(AuctionsCloseButton, "Close") end

    -- Bids Tab Elements
    if BidBidButton then SkinButton(BidBidButton, "Bid") end
    if BidBuyoutButton then SkinButton(BidBuyoutButton, "Buyout") end
    if BidCloseButton then SkinButton(BidCloseButton, "Close") end

    -- Create 1-Click Price Step-Down Undercut Bar
    PUIMerchant:CreateAuctionUndercutBar()

    AuctionFrame.primusSkinned = true
end

-- =========================================================================
-- DOCKABLE FLYOUT CONTROL DRAWER (LEFT / RIGHT)
-- =========================================================================

function PUIMerchant:UpdateFlyoutAnchor()
    if not flyoutFrame or not AuctionFrame then return end

    local side = PUIMerchant.db:Get("flyoutSide", "RIGHT")
    flyoutFrame:ClearAllPoints()

    if side == "LEFT" then
        flyoutFrame:SetPoint("TOPRIGHT", AuctionFrame, "TOPLEFT", -2, 0)
        flyoutFrame:SetPoint("BOTTOMRIGHT", AuctionFrame, "BOTTOMLEFT", -2, 0)
        if flyoutToggleBtn then
            flyoutToggleBtn:ClearAllPoints()
            flyoutToggleBtn:SetPoint("TOPRIGHT", flyoutFrame, "TOPLEFT", -1, -20)
            flyoutToggleBtn.text:SetText(PUIMerchant.db:Get("flyoutOpen", true) and "<" or ">")
        end
    else
        flyoutFrame:SetPoint("TOPLEFT", AuctionFrame, "TOPRIGHT", 2, 0)
        flyoutFrame:SetPoint("BOTTOMLEFT", AuctionFrame, "BOTTOMRIGHT", 2, 0)
        if flyoutToggleBtn then
            flyoutToggleBtn:ClearAllPoints()
            flyoutToggleBtn:SetPoint("TOPLEFT", flyoutFrame, "TOPRIGHT", 1, -20)
            flyoutToggleBtn.text:SetText(PUIMerchant.db:Get("flyoutOpen", true) and ">" or "<")
        end
    end
end

function PUIMerchant:ToggleFlyout(forceState)
    if not flyoutFrame then return end
    local isOpen = (forceState ~= nil) and forceState or not PUIMerchant.db:Get("flyoutOpen", true)
    PUIMerchant.db:Set("flyoutOpen", isOpen)

    if isOpen then
        flyoutFrame:Show()
    else
        flyoutFrame:Hide()
    end

    self:UpdateFlyoutAnchor()
end

-- =========================================================================
-- DEDICATED DARK GLASS SCOPE DROPDOWN MENU
-- =========================================================================

local scopeMenuFrame = nil
local menuCatcher = nil
local scopeMenuRows = {}
local NUM_MENU_ROWS = 12
local MENU_ROW_HEIGHT = 20

function PUIMerchant:SelectDropdownScope(item)
    if not item then return end
    if item.isBrowse then
        self:UseBlizzardBrowseScope()
    else
        self:SetScanScope(item.classId or 0, item.subClassId or 0, item.keyword or "", item.label, item.icon)
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: Target scan scope set to %s.", item.label), "69ccf0"))
    end
    if scopeMenuFrame then
        scopeMenuFrame:Hide()
    end
    if menuCatcher then
        menuCatcher:Hide()
    end
end

function PUIMerchant:CreateScopeDropdownMenu()
    if scopeMenuFrame then return scopeMenuFrame end

    -- Fullscreen click catcher
    menuCatcher = CreateFrame("Button", "PUIMerchant_ScopeMenuCatcher", UIParent)
    menuCatcher:SetFrameStrata("DIALOG")
    menuCatcher:SetFrameLevel(240)
    menuCatcher:SetAllPoints(UIParent)
    menuCatcher:EnableMouse(true)
    menuCatcher:Hide()
    menuCatcher:SetScript("OnClick", function()
        if scopeMenuFrame then scopeMenuFrame:Hide() end
        menuCatcher:Hide()
    end)

    -- Floating Menu Container
    local f = CreateFrame("Frame", "PUIMerchantScopeMenu", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(250)
    f:SetWidth(224)
    f:SetHeight(NUM_MENU_ROWS * MENU_ROW_HEIGHT + 12)
    f:SetBackdrop(Media:Fetch("border", "1Pixel"))
    f:SetBackdropColor(0.06, 0.07, 0.10, 0.98)
    f:SetBackdropBorderColor(0.20, 0.50, 0.85, 0.95)
    f:EnableMouse(true)
    f:Hide()

    -- Scroll Frame
    local sf = CreateFrame("ScrollFrame", "PUIMerchantScopeMenuScroll", f, "FauxScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -6)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, 6)
    sf:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(MENU_ROW_HEIGHT, function()
            PUIMerchant:UpdateScopeDropdownMenu()
        end)
    end)
    f.scrollFrame = sf

    -- Populate Menu Item Rows
    for i = 1, NUM_MENU_ROWS do
        local row = CreateFrame("Button", "PUIMerchantScopeMenuRow" .. i, f)
        row:SetHeight(MENU_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -6 - (i - 1) * MENU_ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -22, -6 - (i - 1) * MENU_ROW_HEIGHT)
        row:SetBackdrop(Media:Fetch("border", "1Pixel"))
        row:SetBackdropColor(0, 0, 0, 0)
        row:SetBackdropBorderColor(0, 0, 0, 0)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(14)
        icon:SetHeight(14)
        icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.icon = icon

        local check = row:CreateFontString(nil, "OVERLAY")
        check:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
        check:SetPoint("LEFT", row, "LEFT", 4, 0)
        check:SetText("|cff00ff00✓|r")
        row.check = check

        local label = row:CreateFontString(nil, "OVERLAY")
        label:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
        label:SetPoint("LEFT", row, "LEFT", 22, 0)
        label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        label:SetJustifyH("LEFT")
        label:SetTextColor(0.9, 0.9, 0.9)
        row.label = label

        local rightLabel = row:CreateFontString(nil, "OVERLAY")
        rightLabel:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
        rightLabel:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        rightLabel:SetJustifyH("RIGHT")
        rightLabel:SetTextColor(0.5, 0.7, 0.9)
        row.rightLabel = rightLabel

        local headerBg = row:CreateTexture(nil, "BACKGROUND")
        headerBg:SetAllPoints(row)
        headerBg:SetTexture(Media:Fetch("texture", "Solid") or "Interface\\Buttons\\WHITE8X8")
        headerBg:SetVertexColor(0.18, 0.14, 0.04, 0.65)
        headerBg:Hide()
        row.headerBg = headerBg

        local sepLine = row:CreateTexture(nil, "ARTWORK")
        sepLine:SetHeight(1)
        sepLine:SetPoint("LEFT", row, "LEFT", 4, 0)
        sepLine:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        sepLine:SetTexture(Media:Fetch("texture", "Solid") or "Interface\\Buttons\\WHITE8X8")
        sepLine:SetVertexColor(0.25, 0.30, 0.40, 0.7)
        sepLine:Hide()
        row.sepLine = sepLine

        row:SetScript("OnEnter", function()
            if not this.isHeader and not this.isSeparator then
                this:SetBackdropColor(0.18, 0.35, 0.65, 0.90)
                this:SetBackdropBorderColor(0.40, 0.75, 1.0, 0.8)
                this.label:SetTextColor(1, 1, 1)
            end
        end)
        row:SetScript("OnLeave", function()
            if not this.isHeader and not this.isSeparator then
                this:SetBackdropColor(0, 0, 0, 0)
                this:SetBackdropBorderColor(0, 0, 0, 0)
                if this.isSelected then
                    this.label:SetTextColor(0.20, 0.85, 1.0)
                else
                    this.label:SetTextColor(0.9, 0.9, 0.9)
                end
            end
        end)
        row:SetScript("OnClick", function()
            if this.itemData and not this.isHeader and not this.isSeparator then
                PUIMerchant:SelectDropdownScope(this.itemData)
            end
        end)

        scopeMenuRows[i] = row
    end

    scopeMenuFrame = f
    return f
end

function PUIMerchant:UpdateScopeDropdownMenu()
    if not scopeMenuFrame or not scopeMenuFrame.scrollFrame then return end

    local items = self.DROPDOWN_MENU_ITEMS or {}
    local totalItems = table.getn(items)
    FauxScrollFrame_Update(scopeMenuFrame.scrollFrame, totalItems, NUM_MENU_ROWS, MENU_ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(scopeMenuFrame.scrollFrame) or 0

    local curClass = PUIMerchant.scannerState.scopeClass or 0
    local curSub = PUIMerchant.scannerState.scopeSubClass or 0
    local curKw = PUIMerchant.scannerState.scopeName or ""

    for i = 1, NUM_MENU_ROWS do
        local row = scopeMenuRows[i]
        local idx = offset + i

        if row and idx <= totalItems then
            local item = items[idx]
            row.itemData = item
            row.isHeader = item.isHeader
            row.isSeparator = item.isSeparator

            if item.isSeparator then
                row.label:Hide()
                row.icon:Hide()
                row.check:Hide()
                row.rightLabel:Hide()
                row.headerBg:Hide()
                row.sepLine:Show()
                row:EnableMouse(false)
                row:SetBackdropColor(0, 0, 0, 0)
                row:SetBackdropBorderColor(0, 0, 0, 0)
            elseif item.isHeader then
                row.sepLine:Hide()
                row.icon:Hide()
                row.check:Hide()
                row.rightLabel:Hide()
                row.headerBg:Show()
                row.label:Show()
                row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
                row.label:SetText(Utils.ColorText("• " .. item.label, item.color or "ffd100"))
                row:EnableMouse(false)
                row:SetBackdropColor(0, 0, 0, 0)
                row:SetBackdropBorderColor(0, 0, 0, 0)
            else
                row.sepLine:Hide()
                row.headerBg:Hide()
                row:EnableMouse(true)

                local isMatch = false
                if item.isBrowse then
                    isMatch = false
                else
                    isMatch = (curClass == (item.classId or 0) and curSub == (item.subClassId or 0) and (item.keyword or "") == curKw)
                end
                row.isSelected = isMatch

                if isMatch then
                    row.icon:Hide()
                    row.check:Show()
                    row.label:SetPoint("LEFT", row, "LEFT", 22, 0)
                    row.label:SetTextColor(0.20, 0.85, 1.0)
                else
                    row.check:Hide()
                    if item.icon then
                        row.icon:SetTexture(item.icon)
                        row.icon:Show()
                        row.label:SetPoint("LEFT", row, "LEFT", 22, 0)
                    else
                        row.icon:Hide()
                        row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
                    end
                    row.label:SetTextColor(0.9, 0.9, 0.9)
                end

                row.label:Show()
                row.label:SetText(item.label or "")

                if item.keyword and item.keyword ~= "" then
                    row.rightLabel:SetText(string.format("[%s]", item.keyword))
                    row.rightLabel:Show()
                else
                    row.rightLabel:Hide()
                end

                row:SetBackdropColor(0, 0, 0, 0)
                row:SetBackdropBorderColor(0, 0, 0, 0)
            end

            row:Show()
        else
            if row then row:Hide() end
        end
    end
end

function PUIMerchant:ToggleScopeDropdownMenu(anchor)
    anchor = anchor or scopeDropdownBtn
    if not anchor then return end

    if not scopeMenuFrame then
        self:CreateScopeDropdownMenu()
    end
    if not scopeMenuFrame then return end

    if scopeMenuFrame:IsShown() then
        scopeMenuFrame:Hide()
        if menuCatcher then menuCatcher:Hide() end
    else
        scopeMenuFrame:ClearAllPoints()
        scopeMenuFrame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)

        -- Find active item index and scroll to it
        local items = self.DROPDOWN_MENU_ITEMS or {}
        local curClass = PUIMerchant.scannerState.scopeClass or 0
        local curSub = PUIMerchant.scannerState.scopeSubClass or 0
        local curKw = PUIMerchant.scannerState.scopeName or ""
        local matchIdx = 1
        for idx = 1, table.getn(items) do
            local it = items[idx]
            if not it.isHeader and not it.isSeparator and not it.isBrowse then
                if curClass == (it.classId or 0) and curSub == (it.subClassId or 0) and (it.keyword or "") == curKw then
                    matchIdx = idx
                    break
                end
            end
        end

        local totalItems = table.getn(items)
        local targetOffset = math.max(0, math.min(matchIdx - 3, totalItems - NUM_MENU_ROWS))
        FauxScrollFrame_SetOffset(scopeMenuFrame.scrollFrame, targetOffset)
        scopeMenuFrame.scrollFrame.offset = targetOffset

        self:UpdateScopeDropdownMenu()
        if menuCatcher then menuCatcher:Show() end
        scopeMenuFrame:Show()
    end
end

function PUIMerchant:CreateFlyoutDrawer()
    if flyoutFrame or not AuctionFrame then return end

    flyoutFrame = CreateFrame("Frame", "PUIMerchantFlyoutFrame", AuctionFrame)
    flyoutFrame:SetWidth(194)
    if Skinner and Skinner.SkinFrame then
        Skinner:SkinFrame(flyoutFrame)
    else
        flyoutFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
        flyoutFrame:SetBackdropColor(0.06, 0.06, 0.09, 0.96)
        flyoutFrame:SetBackdropBorderColor(0.20, 0.20, 0.25, 1.0)
    end
    flyoutFrame:EnableMouse(true)

    -- Toggle Tab Button (Attached to outer edge)
    flyoutToggleBtn = CreateFrame("Button", "PUIMerchantFlyoutToggleBtn", AuctionFrame)
    flyoutToggleBtn:SetWidth(16)
    flyoutToggleBtn:SetHeight(36)
    flyoutToggleBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    flyoutToggleBtn:SetBackdropColor(0.12, 0.12, 0.16, 0.95)
    flyoutToggleBtn:SetBackdropBorderColor(0.30, 0.30, 0.35, 1.0)

    local toggleText = flyoutToggleBtn:CreateFontString(nil, "OVERLAY")
    toggleText:SetFont(Media:Fetch("font", "Default"), 12, "OUTLINE")
    toggleText:SetPoint("CENTER", 0, 0)
    toggleText:SetText(">")
    toggleText:SetTextColor(0.4, 0.8, 1.0)
    flyoutToggleBtn.text = toggleText

    flyoutToggleBtn:SetScript("OnClick", function()
        PUIMerchant:ToggleFlyout()
    end)

    -- Header Title
    local header = flyoutFrame:CreateFontString(nil, "OVERLAY")
    header:SetFont(Media:Fetch("font", "Default"), 11, "OUTLINE")
    header:SetPoint("TOPLEFT", flyoutFrame, "TOPLEFT", 10, -10)
    header:SetText(Utils.ColorText("PUIMerchant Controls", "69ccf0"))

    -- Dock Switch Button (Toggle Left / Right)
    local dockSwitchBtn = Widgets:CreateButton(flyoutFrame, "Dock", 42, 18, function()
        local cur = PUIMerchant.db:Get("flyoutSide", "RIGHT")
        local newSide = (cur == "RIGHT") and "LEFT" or "RIGHT"
        PUIMerchant.db:Set("flyoutSide", newSide)
        PUIMerchant:UpdateFlyoutAnchor()
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: Flyout docked to %s.", newSide), "69ccf0"))
    end)
    dockSwitchBtn:SetPoint("TOPRIGHT", flyoutFrame, "TOPRIGHT", -8, -8)

    -- Separator Line 1
    local sep1 = flyoutFrame:CreateTexture(nil, "ARTWORK")
    sep1:SetTexture(Media:Fetch("texture", "Solid") or "Interface\\Buttons\\WHITE8X8")
    sep1:SetVertexColor(0.20, 0.20, 0.25, 0.8)
    sep1:SetHeight(1)
    sep1:SetPoint("TOPLEFT", flyoutFrame, "TOPLEFT", 8, -32)
    sep1:SetPoint("TOPRIGHT", flyoutFrame, "TOPRIGHT", -8, -32)

    -- Section: Adaptive AH Scanner
    local scanSectionLabel = flyoutFrame:CreateFontString(nil, "OVERLAY")
    scanSectionLabel:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    scanSectionLabel:SetPoint("TOPLEFT", flyoutFrame, "TOPLEFT", 10, -38)
    scanSectionLabel:SetTextColor(0.9, 0.8, 0.4)
    scanSectionLabel:SetText("Adaptive AH Scanner")

    -- Pacing Presets Rail (5 buttons)
    pacingButtons = {}
    local pacingModes = {
        { mode = "ADAPTIVE", label = "⚡Auto", width = 38 },
        { mode = "PATIENT",  label = "10s",   width = 30 },
        { mode = "STANDARD", label = "5.0s",  width = 32 },
        { mode = "FAST",     label = "2.5s",  width = 32 },
        { mode = "TURBO",    label = "1.0s",  width = 32 },
    }
    local prevPBtn = nil
    for _, pInfo in ipairs(pacingModes) do
        local modeKey = pInfo.mode
        local pBtn = Widgets:CreateButton(flyoutFrame, pInfo.label, pInfo.width, 16, function()
            PUIMerchant:SetPacingMode(modeKey)
            DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: Scanner pacing set to %s (%0.1fs).", modeKey, PUIMerchant:GetPacingDelay()), "69ccf0"))
        end)
        if not prevPBtn then
            pBtn:SetPoint("TOPLEFT", flyoutFrame, "TOPLEFT", 9, -52)
        else
            pBtn:SetPoint("LEFT", prevPBtn, "RIGHT", 2, 0)
        end
        pacingButtons[modeKey] = pBtn
        prevPBtn = pBtn
    end

    -- Scan Action Button (Start / Pause / Resume / Stop)
    scanActionButton = Widgets:CreateButton(flyoutFrame, "Scan AH", 176, 22, function()
        PUIMerchant:StartScan()
    end)
    scanActionButton:SetPoint("TOPLEFT", flyoutFrame, "TOPLEFT", 9, -72)
    scanActionButton:SetBackdropBorderColor(1.0, 0.84, 0.0, 1.0)

    -- Stop Scan Button (Left)
    stopScanBtn = Widgets:CreateButton(flyoutFrame, "Stop", 86, 18, function()
        PUIMerchant:StopScan()
    end)
    stopScanBtn:SetPoint("TOPLEFT", flyoutFrame, "TOPLEFT", 9, -96)
    stopScanBtn:SetBackdropBorderColor(0.8, 0.2, 0.2, 0.8)

    -- Start Fresh / New Scan Button (Right)
    resetScanBtn = Widgets:CreateButton(flyoutFrame, "New Scan", 86, 18, function()
        PUIMerchant:ClearScanCheckpoint()
        PUIMerchant:StartScan(nil, true)
    end)
    resetScanBtn:SetPoint("LEFT", stopScanBtn, "RIGHT", 4, 0)
    resetScanBtn:SetBackdropBorderColor(0.20, 0.75, 1.0, 0.8)

    -- Progress Bar
    scanProgressBar = CreateFrame("StatusBar", nil, flyoutFrame)
    scanProgressBar:SetWidth(176)
    scanProgressBar:SetHeight(10)
    scanProgressBar:SetPoint("TOPLEFT", flyoutFrame, "TOPLEFT", 9, -118)
    scanProgressBar:SetStatusBarTexture(Media:Fetch("texture", "Solid") or "Interface\\Buttons\\WHITE8X8")
    scanProgressBar:SetStatusBarColor(0.20, 0.75, 1.0, 0.85)
    scanProgressBar:SetMinMaxValues(0, 100)
    scanProgressBar:SetValue(0)
    scanProgressBar:SetBackdrop(Media:Fetch("border", "1Pixel"))
    scanProgressBar:SetBackdropColor(0.04, 0.04, 0.06, 0.90)
    scanProgressBar:SetBackdropBorderColor(0.20, 0.20, 0.25, 1.0)

    -- Scan Status Text
    scanStatusLabel = flyoutFrame:CreateFontString(nil, "OVERLAY")
    scanStatusLabel:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    scanStatusLabel:SetPoint("TOPLEFT", flyoutFrame, "TOPLEFT", 10, -131)
    scanStatusLabel:SetTextColor(0.7, 0.7, 0.7)
    scanStatusLabel:SetText("Ready to scan")

    -- Scan Countdown Text (Live 1s timer)
    scanCountdownLabel = flyoutFrame:CreateFontString(nil, "OVERLAY")
    scanCountdownLabel:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    scanCountdownLabel:SetPoint("TOPLEFT", flyoutFrame, "TOPLEFT", 10, -144)
    scanCountdownLabel:SetTextColor(1.0, 0.84, 0.0)
    scanCountdownLabel:SetText("")

    -- Scope Dropdown Section Label
    local scopeSectionLabel = flyoutFrame:CreateFontString(nil, "OVERLAY")
    scopeSectionLabel:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    scopeSectionLabel:SetPoint("TOPLEFT", flyoutFrame, "TOPLEFT", 10, -158)
    scopeSectionLabel:SetTextColor(0.8, 0.8, 0.8)
    scopeSectionLabel:SetText("Scan Target / Category:")

    -- Dedicated Dark Glass Scope Dropdown Button
    scopeDropdownBtn = CreateFrame("Button", "PUIMerchantScopeDropdown", flyoutFrame)
    scopeDropdownBtn:SetWidth(176)
    scopeDropdownBtn:SetHeight(24)
    scopeDropdownBtn:SetPoint("TOPLEFT", flyoutFrame, "TOPLEFT", 9, -170)
    scopeDropdownBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    scopeDropdownBtn:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
    scopeDropdownBtn:SetBackdropBorderColor(0.25, 0.50, 0.85, 0.9)

    local scopeDropdownIcon = scopeDropdownBtn:CreateTexture(nil, "ARTWORK")
    scopeDropdownIcon:SetWidth(14)
    scopeDropdownIcon:SetHeight(14)
    scopeDropdownIcon:SetPoint("LEFT", scopeDropdownBtn, "LEFT", 6, 0)
    scopeDropdownIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    scopeDropdownIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    scopeDropdownBtn.icon = scopeDropdownIcon

    local scopeDropdownText = scopeDropdownBtn:CreateFontString(nil, "OVERLAY")
    scopeDropdownText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    scopeDropdownText:SetPoint("LEFT", scopeDropdownBtn, "LEFT", 24, 0)
    scopeDropdownText:SetPoint("RIGHT", scopeDropdownBtn, "RIGHT", -18, 0)
    scopeDropdownText:SetJustifyH("LEFT")
    scopeDropdownText:SetTextColor(0.95, 0.95, 0.95)
    scopeDropdownText:SetText("All Categories (Full Scan)")
    scopeDropdownBtn.text = scopeDropdownText

    local scopeDropdownArrow = scopeDropdownBtn:CreateFontString(nil, "OVERLAY")
    scopeDropdownArrow:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    scopeDropdownArrow:SetPoint("RIGHT", scopeDropdownBtn, "RIGHT", -6, 0)
    scopeDropdownArrow:SetTextColor(0.4, 0.8, 1.0)
    scopeDropdownArrow:SetText("▼")
    scopeDropdownBtn.arrow = scopeDropdownArrow

    scopeDropdownBtn:SetScript("OnClick", function()
        PUIMerchant:ToggleScopeDropdownMenu(scopeDropdownBtn)
    end)
    scopeDropdownBtn:SetScript("OnEnter", function()
        this:SetBackdropColor(0.14, 0.18, 0.26, 1.0)
        this:SetBackdropBorderColor(0.40, 0.80, 1.0, 1.0)
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Scan Target / Category", 1, 0.84, 0)
        GameTooltip:AddLine("Click to choose AH Category (Trade, Consumables, Gear...) and Sub-categories.", 0.8, 0.8, 0.8, 1)
        GameTooltip:Show()
    end)
    scopeDropdownBtn:SetScript("OnLeave", function()
        this:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
        this:SetBackdropBorderColor(0.25, 0.50, 0.85, 0.9)
        GameTooltip:Hide()
    end)
    PUIMerchant.scopeDropdownBtn = scopeDropdownBtn
    PUIMerchant.scopeSelectorBtn = scopeDropdownBtn

    -- Scope Keyword Search EditBox
    scopeKeywordBox = CreateFrame("EditBox", "PUIMerchantFlyoutKeywordBox", flyoutFrame)
    scopeKeywordBox:SetWidth(176)
    scopeKeywordBox:SetHeight(18)
    scopeKeywordBox:SetPoint("TOPLEFT", flyoutFrame, "TOPLEFT", 9, -196)
    scopeKeywordBox:SetBackdrop(Media:Fetch("border", "1Pixel"))
    scopeKeywordBox:SetBackdropColor(0.04, 0.04, 0.06, 0.90)
    scopeKeywordBox:SetBackdropBorderColor(0.25, 0.25, 0.30, 1.0)
    scopeKeywordBox:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    scopeKeywordBox:SetAutoFocus(false)
    scopeKeywordBox:SetTextInsets(6, 6, 0, 0)

    local kwPlaceholder = scopeKeywordBox:CreateFontString(nil, "OVERLAY")
    kwPlaceholder:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    kwPlaceholder:SetPoint("LEFT", scopeKeywordBox, "LEFT", 6, 0)
    kwPlaceholder:SetTextColor(0.45, 0.45, 0.45)
    kwPlaceholder:SetText("Optional filter (e.g. Leather)...")

    scopeKeywordBox:SetScript("OnEditFocusGained", function() kwPlaceholder:Hide() end)
    scopeKeywordBox:SetScript("OnEditFocusLost", function()
        if scopeKeywordBox:GetText() == "" then kwPlaceholder:Show() end
    end)
    scopeKeywordBox:SetScript("OnEnterPressed", function()
        local txt = scopeKeywordBox:GetText() or ""
        PUIMerchant:SetScanScope(PUIMerchant.scannerState.scopeClass or 0, PUIMerchant.scannerState.scopeSubClass or 0, txt)
        scopeKeywordBox:ClearFocus()
    end)
    scopeKeywordBox:SetScript("OnEscapePressed", function()
        scopeKeywordBox:SetText("")
        PUIMerchant:SetScanScope(PUIMerchant.scannerState.scopeClass or 0, PUIMerchant.scannerState.scopeSubClass or 0, "")
        scopeKeywordBox:ClearFocus()
    end)
    PUIMerchant.scopeKeywordBox = scopeKeywordBox

    -- Separator Line 2
    local sep2 = flyoutFrame:CreateTexture(nil, "ARTWORK")
    sep2:SetTexture(Media:Fetch("texture", "Solid") or "Interface\\Buttons\\WHITE8X8")
    sep2:SetVertexColor(0.20, 0.20, 0.25, 0.8)
    sep2:SetHeight(1)
    sep2:SetPoint("TOPLEFT", flyoutFrame, "TOPLEFT", 8, -220)
    sep2:SetPoint("TOPRIGHT", flyoutFrame, "TOPRIGHT", -8, -220)

    -- Section: Quick Shortcuts & Analytics
    local toolsLabel = flyoutFrame:CreateFontString(nil, "OVERLAY")
    toolsLabel:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    toolsLabel:SetPoint("TOPLEFT", flyoutFrame, "TOPLEFT", 10, -230)
    toolsLabel:SetTextColor(0.9, 0.8, 0.4)
    toolsLabel:SetText("Market Tools & Explorer")

    -- Open Offline Explorer Button
    local openExplorerBtn = Widgets:CreateButton(flyoutFrame, "Offline Market Explorer", 176, 20, function()
        if PUIMerchant.ToggleMarketExplorer then
            PUIMerchant:ToggleMarketExplorer()
        end
    end)
    openExplorerBtn:SetPoint("TOPLEFT", flyoutFrame, "TOPLEFT", 9, -246)
    openExplorerBtn:SetBackdropBorderColor(0.20, 0.75, 1.0, 0.85)

    -- Open Deal Finder / Sniping Flyout Button
    local openDealsBtn = Widgets:CreateButton(flyoutFrame, "Deal Finder & Sniper", 176, 20, function()
        PUIMerchant:ToggleDealFlyout()
    end)
    openDealsBtn:SetPoint("TOPLEFT", flyoutFrame, "TOPLEFT", 9, -270)
    openDealsBtn:SetBackdropBorderColor(0.20, 0.85, 0.35, 0.85)

    -- Prune DB Button
    local pruneBtn = Widgets:CreateButton(flyoutFrame, "Prune Old History (>14d)", 176, 18, function()
        local purged = PUIMerchant:PruneOldHistory(nil, 14)
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: Pruned %d stale entries older than 14 days.", purged), "69ccf0"))
    end)
    pruneBtn:SetPoint("TOPLEFT", flyoutFrame, "TOPLEFT", 9, -294)

    -- Toggles
    local qbCheck = Widgets:CreateCheckButton(flyoutFrame, "Shift+Click Quick Buyout", 12, function(selfChecked)
        PUIMerchant.db:Set("quickBuyout", selfChecked)
    end)
    qbCheck:SetPoint("TOPLEFT", flyoutFrame, "TOPLEFT", 10, -316)
    qbCheck:SetChecked(PUIMerchant.db:Get("quickBuyout", true))

    local ttCheck = Widgets:CreateCheckButton(flyoutFrame, "Show Prices in Tooltips", 12, function(selfChecked)
        PUIMerchant.db:Set("showTooltipPrices", selfChecked)
    end)
    ttCheck:SetPoint("TOPLEFT", flyoutFrame, "TOPLEFT", 10, -336)
    ttCheck:SetChecked(PUIMerchant.db:Get("showTooltipPrices", true))

    local sparkCheck = Widgets:CreateCheckButton(flyoutFrame, "Shift-Hover Sparkline", 12, function(selfChecked)
        PUIMerchant.db:Set("showTooltipSparkline", selfChecked)
    end)
    sparkCheck:SetPoint("TOPLEFT", flyoutFrame, "TOPLEFT", 10, -356)
    sparkCheck:SetChecked(PUIMerchant.db:Get("showTooltipSparkline", true))

    PUIMerchant.flyoutFrame = flyoutFrame
    PUIMerchant:UpdateFlyoutAnchor()

    -- Create and dock Deal Finder Flyout
    PUIMerchant:CreateDealFlyoutDrawer()

    if not PUIMerchant.db:Get("flyoutOpen", true) then
        flyoutFrame:Hide()
    end
end

-- =========================================================================
-- DEAL FINDER & SNIPING DOCKED FLYOUT
-- =========================================================================

local dealFlyoutFrame = nil
local dealRows = {}
local NUM_DEAL_ROWS = 10
local dealFilterMode = 70 -- 70 = <=70% MV, 50 = <=50% MV, 0 = Vendor Snipes, "EXPIRING" = <30m
local cachedDealsList = {}

function PUIMerchant:UpdateDealFlyoutAnchor()
    if not dealFlyoutFrame or not flyoutFrame then return end

    local side = PUIMerchant.db:Get("flyoutSide", "RIGHT")
    dealFlyoutFrame:ClearAllPoints()

    if side == "LEFT" then
        dealFlyoutFrame:SetPoint("TOPRIGHT", flyoutFrame, "TOPLEFT", -2, 0)
        dealFlyoutFrame:SetPoint("BOTTOMRIGHT", flyoutFrame, "BOTTOMLEFT", -2, 0)
    else
        dealFlyoutFrame:SetPoint("TOPLEFT", flyoutFrame, "TOPRIGHT", 2, 0)
        dealFlyoutFrame:SetPoint("BOTTOMLEFT", flyoutFrame, "BOTTOMRIGHT", 2, 0)
    end
end

function PUIMerchant:ToggleDealFlyout(forceState)
    if not dealFlyoutFrame then
        self:CreateDealFlyoutDrawer()
    end
    if not dealFlyoutFrame then return end

    local shouldShow = (forceState ~= nil) and forceState or not dealFlyoutFrame:IsShown()
    if shouldShow then
        dealFlyoutFrame:Show()
        self:UpdateDealFlyoutAnchor()
        self:RefreshDealFlyoutData()
    else
        dealFlyoutFrame:Hide()
    end
end

function PUIMerchant:RefreshDealFlyoutData()
    if not dealFlyoutFrame or not dealFlyoutFrame:IsShown() then return end

    cachedDealsList = {}
    local realm = GetRealmName() or "Default"
    local realmData = self:GetRealmPriceData(realm)
    if not realmData or not realmData.priceData then return end

    for itemName, pData in pairs(realmData.priceData) do
        local minB = pData.latestMinBuyout or 0
        local runMed = pData.runningMedian7d or pData.runningAvg7d or 0
        local isDeal = false
        local mvPct = 100
        local profitEst = 0
        local timeLeft = pData.latestTimeLeft or 4

        if runMed > 0 and minB > 0 then
            mvPct = math.floor((minB / runMed) * 100)
            if type(dealFilterMode) == "number" and dealFilterMode > 0 and mvPct <= dealFilterMode then
                isDeal = true
                profitEst = runMed - minB
            end
        end

        -- Vendor Arbitrage Sniping
        local itemID = Items:GetID(itemName)
        if itemID and VanillaItemPrices and VanillaItemPrices[itemID] then
            local vSell = VanillaItemPrices[itemID].s or 0
            if vSell > 0 and minB > 0 and minB < vSell then
                if dealFilterMode == 0 or (type(dealFilterMode) == "number" and dealFilterMode >= 0) then
                    isDeal = true
                    profitEst = vSell - minB
                    mvPct = 0 -- Top priority
                end
            end
        end

        -- Expiring Soon (<30m) Filter Mode
        if dealFilterMode == "EXPIRING" then
            if timeLeft == 1 and minB > 0 then
                isDeal = true
                profitEst = (runMed > minB) and (runMed - minB) or 0
            else
                isDeal = false
            end
        end

        if isDeal then
            table.insert(cachedDealsList, {
                data = pData,
                name = itemName,
                minB = minB,
                runMed = runMed,
                mvPct = mvPct,
                profitEst = profitEst,
                timeLeft = timeLeft,
            })
        end
    end

    -- Sort by best discount % or expiring soonest
    table.sort(cachedDealsList, function(a, b)
        if dealFilterMode == "EXPIRING" then
            if a.timeLeft ~= b.timeLeft then
                return a.timeLeft < b.timeLeft
            end
        end
        return a.mvPct < b.mvPct
    end)

    self:UpdateDealFlyoutTable()
end

function PUIMerchant:UpdateDealFlyoutTable()
    if not dealFlyoutFrame or not dealFlyoutFrame.scrollFrame then return end

    local totalDeals = table.getn(cachedDealsList)
    FauxScrollFrame_Update(dealFlyoutFrame.scrollFrame, totalDeals, NUM_DEAL_ROWS, 34)
    local offset = FauxScrollFrame_GetOffset(dealFlyoutFrame.scrollFrame) or 0

    for i = 1, NUM_DEAL_ROWS do
        local row = dealRows[i]
        local idx = offset + i

        if row and idx <= totalDeals then
            local deal = cachedDealsList[idx]
            local pData = deal.data

            row.deal = deal
            row.itemName = deal.name

            if pData.texture then
                row.icon:SetTexture(pData.texture)
            else
                row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end

            local qColor = Items:GetQualityColor(pData.quality or 1)
            row.nameText:SetText(deal.name)
            row.nameText:SetTextColor(qColor.r, qColor.g, qColor.b)

            row.priceText:SetText(Utils.FormatMoney(deal.minB))
            
            if deal.mvPct == 0 then
                row.mvText:SetText("|cff1eff00[VENDOR!]|r")
            else
                row.mvText:SetText(string.format("|cff1eff00%d%%|r", deal.mvPct))
            end

            if row.timeLeftBadge then
                row.timeLeftBadge:SetText(PUIMerchant:FormatTimeLeftBadge(deal.timeLeft))
            end

            row:Show()
        else
            if row then row:Hide() end
        end
    end
end

function PUIMerchant:CreateDealFlyoutDrawer()
    if dealFlyoutFrame or not flyoutFrame then return end

    dealFlyoutFrame = CreateFrame("Frame", "PUIMerchantDealFlyoutFrame", flyoutFrame)
    dealFlyoutFrame:SetWidth(230)
    if Skinner and Skinner.SkinFrame then
        Skinner:SkinFrame(dealFlyoutFrame)
    else
        dealFlyoutFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
        dealFlyoutFrame:SetBackdropColor(0.06, 0.06, 0.09, 0.96)
        dealFlyoutFrame:SetBackdropBorderColor(0.20, 0.85, 0.35, 1.0)
    end
    dealFlyoutFrame:EnableMouse(true)
    dealFlyoutFrame:Hide()

    -- Header
    local title = dealFlyoutFrame:CreateFontString(nil, "OVERLAY")
    title:SetFont(Media:Fetch("font", "Default"), 11, "OUTLINE")
    title:SetPoint("TOPLEFT", dealFlyoutFrame, "TOPLEFT", 10, -10)
    title:SetText(Utils.ColorText("Deal Finder & Sniper", "1eff00"))

    -- Close Button
    local closeBtn = CreateFrame("Button", nil, dealFlyoutFrame)
    closeBtn:SetWidth(16)
    closeBtn:SetHeight(16)
    closeBtn:SetPoint("TOPRIGHT", dealFlyoutFrame, "TOPRIGHT", -6, -8)
    local closeTxt = closeBtn:CreateFontString(nil, "OVERLAY")
    closeTxt:SetFont(Media:Fetch("font", "Default"), 11, "OUTLINE")
    closeTxt:SetPoint("CENTER", 0, 0)
    closeTxt:SetText("x")
    closeTxt:SetTextColor(0.8, 0.8, 0.8)
    closeBtn:SetScript("OnClick", function() dealFlyoutFrame:Hide() end)

    -- Filter Buttons (5 buttons across header)
    local f70Btn = Widgets:CreateButton(dealFlyoutFrame, "<=70%", 40, 18, function()
        dealFilterMode = 70
        PUIMerchant:RefreshDealFlyoutData()
    end)
    f70Btn:SetPoint("TOPLEFT", dealFlyoutFrame, "TOPLEFT", 6, -32)

    local f50Btn = Widgets:CreateButton(dealFlyoutFrame, "<=50%", 40, 18, function()
        dealFilterMode = 50
        PUIMerchant:RefreshDealFlyoutData()
    end)
    f50Btn:SetPoint("LEFT", f70Btn, "RIGHT", 3, 0)

    local fVendBtn = Widgets:CreateButton(dealFlyoutFrame, "Vendor", 44, 18, function()
        dealFilterMode = 0
        PUIMerchant:RefreshDealFlyoutData()
    end)
    fVendBtn:SetPoint("LEFT", f50Btn, "RIGHT", 3, 0)

    local fExpBtn = Widgets:CreateButton(dealFlyoutFrame, "<30m ⏳", 44, 18, function()
        dealFilterMode = "EXPIRING"
        PUIMerchant:RefreshDealFlyoutData()
    end)
    fExpBtn:SetPoint("LEFT", fVendBtn, "RIGHT", 3, 0)

    local refBtn = Widgets:CreateButton(dealFlyoutFrame, "Scan", 36, 18, function()
        PUIMerchant:RefreshDealFlyoutData()
    end)
    refBtn:SetPoint("LEFT", fExpBtn, "RIGHT", 3, 0)

    -- Scroll Frame
    local sFrame = CreateFrame("ScrollFrame", "PUIMerchantDealFlyoutScroll", dealFlyoutFrame, "FauxScrollFrameTemplate")
    sFrame:SetWidth(206)
    sFrame:SetHeight(340)
    sFrame:SetPoint("TOPLEFT", dealFlyoutFrame, "TOPLEFT", 8, -56)
    dealFlyoutFrame.scrollFrame = sFrame

    sFrame:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(34, function()
            PUIMerchant:UpdateDealFlyoutTable()
        end)
    end)

    -- Build Rows
    for i = 1, NUM_DEAL_ROWS do
        local row = CreateFrame("Button", nil, dealFlyoutFrame)
        row:SetWidth(214)
        row:SetHeight(32)
        row:SetPoint("TOPLEFT", dealFlyoutFrame, "TOPLEFT", 8, -56 - ((i - 1) * 34))
        row:SetBackdrop(Media:Fetch("border", "1Pixel"))
        row:SetBackdropColor(0.08, 0.08, 0.11, 0.85)
        row:SetBackdropBorderColor(0.18, 0.18, 0.22, 0.8)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(22)
        icon:SetHeight(22)
        icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon = icon

        local nameText = row:CreateFontString(nil, "OVERLAY")
        nameText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
        nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -1)
        nameText:SetWidth(110)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        local mvText = row:CreateFontString(nil, "OVERLAY")
        mvText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
        mvText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -1)
        row.mvText = mvText

        local priceText = row:CreateFontString(nil, "OVERLAY")
        priceText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
        priceText:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 6, 2)
        priceText:SetTextColor(0.85, 0.85, 0.85)
        row.priceText = priceText

        local timeLeftBadge = row:CreateFontString(nil, "OVERLAY")
        timeLeftBadge:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
        timeLeftBadge:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 2)
        row.timeLeftBadge = timeLeftBadge

        -- 1-Click Search & Snipe on Click
        row:SetScript("OnClick", function()
            if this.itemName and BrowseName and BrowseSearchButton then
                if AuctionFrameTab1 then AuctionFrameTab1:Click() end
                BrowseName:SetText(this.itemName)
                BrowseSearchButton:Click()
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: Searching AH for deal: %s", this.itemName), "1eff00"))
            end
        end)

        row:SetScript("OnEnter", function()
            if this.deal and this.deal.data then
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                local qColor = Items:GetQualityColor(this.deal.data.quality or 1)
                GameTooltip:AddLine(this.deal.name, qColor.r, qColor.g, qColor.b)
                GameTooltip:AddDoubleLine("Current Buyout:", Utils.FormatMoney(this.deal.minB))
                GameTooltip:AddDoubleLine("7-Day Core Median:", Utils.FormatMoney(this.deal.runMed))
                GameTooltip:AddDoubleLine("Est. Profit Margin:", string.format("|cff1eff00+%s|r", Utils.FormatMoney(this.deal.profitEst)))
                GameTooltip:AddDoubleLine("Time Remaining:", PUIMerchant:GetTimeLeftText(this.deal.timeLeft))
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cff69ccf0Click to 1-click search & buy in AH!|r")
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        dealRows[i] = row
    end

    PUIMerchant.dealFlyoutFrame = dealFlyoutFrame
    PUIMerchant:UpdateDealFlyoutAnchor()
end

-- =========================================================================
-- 1-CLICK UNDERCUT STEP-DOWN CONTROL RAIL (AuctionFrameAuctions)
-- =========================================================================

function PUIMerchant:CreateAuctionUndercutBar()
    if not AuctionFrameAuctions or AuctionFrameAuctions.primusUndercutBar then return end

    local bar = CreateFrame("Frame", "PUIMerchantAuctionUndercutFrame", AuctionFrameAuctions)
    bar:SetWidth(194)
    bar:SetHeight(76)
    bar:SetPoint("TOPLEFT", AuctionFrameAuctions, "TOPLEFT", 18, -242)

    if Skinner and Skinner.SkinFrame then
        Skinner:SkinFrame(bar)
    else
        bar:SetBackdrop(Media:Fetch("border", "1Pixel"))
        bar:SetBackdropColor(0.06, 0.06, 0.09, 0.96)
        bar:SetBackdropBorderColor(0.20, 0.20, 0.25, 1.0)
    end

    local title = bar:CreateFontString(nil, "OVERLAY")
    title:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    title:SetPoint("TOPLEFT", bar, "TOPLEFT", 8, -6)
    title:SetText(Utils.ColorText("1-Click Undercut Step-Down", "69ccf0"))

    local floorLabel = bar:CreateFontString(nil, "OVERLAY")
    floorLabel:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    floorLabel:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -8, -6)
    floorLabel:SetTextColor(0.20, 0.85, 0.35)
    floorLabel:SetText("Floor Safe")
    bar.floorLabel = floorLabel

    -- Row 1: [-1c], [-1%], [-5%]
    local btn1c = Widgets:CreateButton(bar, "-1c 📉", 56, 18, function()
        PUIMerchant:ApplyUndercutStepDown("COPPER", 1)
    end)
    btn1c:SetPoint("TOPLEFT", bar, "TOPLEFT", 8, -22)

    local btn1p = Widgets:CreateButton(bar, "-1%", 56, 18, function()
        PUIMerchant:ApplyUndercutStepDown("PERCENT", 1)
    end)
    btn1p:SetPoint("LEFT", btn1c, "RIGHT", 4, 0)

    local btn5p = Widgets:CreateButton(bar, "-5%", 56, 18, function()
        PUIMerchant:ApplyUndercutStepDown("PERCENT", 5)
    end)
    btn5p:SetPoint("LEFT", btn1p, "RIGHT", 4, 0)

    -- Row 2: [Match], [Median], [Reset]
    local btnMatch = Widgets:CreateButton(bar, "Match 🎯", 56, 18, function()
        PUIMerchant:ApplyUndercutStepDown("MATCH")
    end)
    btnMatch:SetPoint("TOPLEFT", bar, "TOPLEFT", 8, -44)

    local btnMedian = Widgets:CreateButton(bar, "Median 📊", 56, 18, function()
        PUIMerchant:ApplyUndercutStepDown("MEDIAN")
    end)
    btnMedian:SetPoint("LEFT", btnMatch, "RIGHT", 4, 0)

    local btnReset = Widgets:CreateButton(bar, "Reset ↺", 56, 18, function()
        PUIMerchant:ApplyUndercutStepDown("RESET")
    end)
    btnReset:SetPoint("LEFT", btnMedian, "RIGHT", 4, 0)

    AuctionFrameAuctions.primusUndercutBar = bar
end

-- Reactive UI Update Loop for Flyout Scanner Status
function PUIMerchant:UpdateFlyoutScannerUI()
    if not flyoutFrame or not scanActionButton then return end

    local state = PUIMerchant.scannerState
    if not state then return end

    -- Update pacing button active borders
    local curMode = state.pacingMode or (PUIMerchant.db and PUIMerchant.db:Get("scanPacingMode", "ADAPTIVE")) or "ADAPTIVE"
    if pacingButtons then
        for modeKey, btn in pairs(pacingButtons) do
            if modeKey == curMode then
                btn:SetBackdropBorderColor(0.20, 0.75, 1.0, 1.0)
                btn:SetBackdropColor(0.18, 0.25, 0.35, 0.95)
            else
                btn:SetBackdropBorderColor(0.25, 0.25, 0.30, 0.8)
                btn:SetBackdropColor(0.10, 0.10, 0.14, 0.90)
            end
        end
    end

    -- Update scope dropdown button label and icon
    if scopeDropdownBtn then
        if scopeDropdownBtn.text then
            local scopeLbl = PUIMerchant.GetScopeLabel and PUIMerchant:GetScopeLabel() or "All Categories"
            if string.len(scopeLbl) > 24 then
                scopeLbl = string.sub(scopeLbl, 1, 22) .. ".."
            end
            scopeDropdownBtn.text:SetText(scopeLbl)
        end
        if scopeDropdownBtn.icon and PUIMerchant.GetScopeIcon then
            local curClass = state.scopeClass or 0
            local curSub = state.scopeSubClass or 0
            local curKw = state.scopeName or ""
            local icon = PUIMerchant:GetScopeIcon(curClass, curSub, curKw)
            scopeDropdownBtn.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_Book_09")
        end
    end

    if state.isScanning then
        if state.isPaused then
            scanActionButton:SetText("Resume Scan")
            scanActionButton:SetBackdropBorderColor(1.0, 0.84, 0.0, 1.0)
            scanCountdownLabel:SetText(string.format("|cffffbb33[Paused]|r • ETA: |cff69ccf0%s|r", state.etaText or "--"))
        else
            scanActionButton:SetText("Pause Scan")
            scanActionButton:SetBackdropBorderColor(0.20, 0.75, 1.0, 1.0)
            local rateStr = (state.measuredPageRate and state.measuredPageRate > 0) and string.format("%0.1fs/p", state.measuredPageRate) or string.format("%0.1fs", state.currentCooldown)
            if state.isWaitingServerGate then
                scanCountdownLabel:SetText(string.format("|cffff9900[Server Gate: %s]|r • ETA: |cff69ccf0%s|r", rateStr, state.etaText or "--"))
            elseif state.remainingCooldown > 0 then
                scanCountdownLabel:SetText(string.format("Next: |cffffd100%ds|r (⚡ %s) • ETA: |cff69ccf0%s|r", state.remainingCooldown, rateStr, state.etaText or "--"))
            else
                scanCountdownLabel:SetText(string.format("|cff1eff00Querying AH...|r (⚡ %s)", rateStr))
            end
        end

        local pct = 0
        if state.totalPages and state.totalPages > 0 then
            pct = math.floor((state.scanPage / state.totalPages) * 100)
            if pct > 100 then pct = 100 end
        end
        scanProgressBar:SetValue(pct)
        scanStatusLabel:SetText(string.format("Page %d/%d (%d items • %d%%)", state.scanPage, state.totalPages, state.totalCataloged, pct))

        if stopScanBtn then
            stopScanBtn:SetWidth(176)
            stopScanBtn:SetText("Stop Scan")
            stopScanBtn:SetScript("OnClick", function()
                PUIMerchant:StopScan()
            end)
            stopScanBtn:Show()
        end
        if resetScanBtn then resetScanBtn:Hide() end
    else
        local cp = PUIMerchant.GetScanCheckpoint and PUIMerchant:GetScanCheckpoint()
        if cp and cp.page and cp.page > 0 then
            local resumePage = math.max(1, cp.page - 1)
            scanActionButton:SetText(string.format("Resume (p.%d)", resumePage))
            scanActionButton:SetBackdropBorderColor(0.20, 0.85, 0.35, 1.0)
            scanCountdownLabel:SetText("|cff1eff00[Checkpoint Available]|r")
            scanStatusLabel:SetText(string.format("Saved: Page %d/%d (%s)", cp.page, cp.totalPages or 1, cp.scopeLabel or PUIMerchant:GetScopeName(cp.scopeClass or cp.scope or 0)))

            if stopScanBtn then
                stopScanBtn:SetWidth(86)
                stopScanBtn:SetText("Clear CP")
                stopScanBtn:SetScript("OnClick", function()
                    PUIMerchant:ClearScanCheckpoint()
                    PUIMerchant:UpdateFlyoutScannerUI()
                    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIMerchant]: Scan checkpoint cleared.", "ffbb33"))
                end)
                stopScanBtn:Show()
            end
            if resetScanBtn then
                resetScanBtn:SetWidth(86)
                resetScanBtn:SetText("New Scan")
                resetScanBtn:Show()
            end
        else
            local shortScope = PUIMerchant.GetScopeShortName and PUIMerchant:GetScopeShortName() or "All"
            scanActionButton:SetText("Scan: " .. shortScope)
            scanActionButton:SetBackdropBorderColor(1.0, 0.84, 0.0, 1.0)
            local pacingTag = (curMode == "ADAPTIVE") and "⚡ Adaptive (5s->1s)" or string.format("%0.1fs Fixed", PUIMerchant:GetPacingDelay())
            scanCountdownLabel:SetText(string.format("|cff888888Pacing: %s|r", pacingTag))
            scanStatusLabel:SetText(state.statusText or "Ready to scan")

            if stopScanBtn then
                stopScanBtn:SetWidth(176)
                stopScanBtn:SetText("Stop")
                stopScanBtn:SetScript("OnClick", function()
                    PUIMerchant:StopScan()
                end)
                stopScanBtn:Show()
            end
            if resetScanBtn then resetScanBtn:Hide() end
        end
        scanProgressBar:SetValue(0)
    end
end
