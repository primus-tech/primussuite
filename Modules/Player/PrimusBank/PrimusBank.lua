--[[
    PrimusUI Module: PUIBank (Unified Bank with Offline Persistent Caching & Bag Tray)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides a modern unified bank container for main bank slots (24 base)
    and bank bags (5–10), plus offline SavedVariables caching for browsing anywhere.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIBank = Primus.PUIBank or {}
Primus.PUIBank = PUIBank
_G.PUIBank = PUIBank
Primus:RegisterModule("PUIBank", PUIBank, "Player")

local DB       = Primus.DB
local Widgets  = Primus.Widgets
local Media    = Primus.Media
local Utils    = Primus.Utils
local Events   = Primus.Events
local PUIMover = Primus.PUIMover

-- Configuration namespace
local configDB = DB:RegisterNamespace("PUIBank", {
    enabled     = true,
    cols        = 10,
    slotSize    = 34,
    spacing     = 4,
    showBagTray = true,
})

-- Quality border colors
local QUALITY_COLORS = {
    [0] = { r = 0.6, g = 0.6, b = 0.6 }, -- Poor (Grey)
    [1] = { r = 1.0, g = 1.0, b = 1.0 }, -- Common (White)
    [2] = { r = 0.1, g = 1.0, b = 0.0 }, -- Uncommon (Green)
    [3] = { r = 0.0, g = 0.4, b = 0.9 }, -- Rare (Blue)
    [4] = { r = 0.6, g = 0.2, b = 0.9 }, -- Epic (Purple)
    [5] = { r = 1.0, g = 0.5, b = 0.0 }, -- Legendary (Orange)
}

-- Character-specific bank cache
local bankDB = DB:RegisterNamespace("PUIBankCache", {
    cachedItems = {}, -- array of { texture, count, link, name, quality, bagID, slotID, locked }
    cachedBags  = {}, -- [1..6] = { texture, link, numSlots }
    lastScanned = "",
}, true)

local bankFrame    = nil
local bankSlots    = {}
local bankBagSlots = {}
local isBankOpen   = false
local searchFilter = ""

-- =========================================================================
-- BANK ITEM SLOT FACTORY
-- =========================================================================

local function CreateBankSlot(parent, index)
    local size = configDB:Get("slotSize", 34)
    local slot = CreateFrame("Button", "Primus_PUIBankSlot_" .. index, parent)
    slot:SetWidth(size)
    slot:SetHeight(size)
    slot:SetBackdrop(Media:Fetch("border", "1Pixel"))
    slot:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
    slot:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)

    -- Icon texture
    local icon = slot:CreateTexture(slot:GetName() .. "Icon", "BORDER")
    icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    slot.icon = icon

    -- Stack count
    local count = slot:CreateFontString(slot:GetName() .. "Count", "OVERLAY")
    count:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -2, 2)
    slot.count = count

    -- Highlight texture
    local highlight = slot:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")
    highlight:SetAllPoints(slot)

    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot:RegisterForDrag("LeftButton")

    slot:SetScript("OnClick", function()
        local bagID = this.bagID
        local slotID = this.slotID
        local link = this.itemLink

        if isBankOpen and bagID and slotID then
            if IsControlKeyDown() and link then
                DressUpItemLink(link)
            elseif IsShiftKeyDown() then
                if PUITalk and PUITalk.IsInputFocused and PUITalk:IsInputFocused() and link then
                    if ChatFrameEditBox then ChatFrameEditBox:Insert(link) end
                elseif this.itemCount and this.itemCount > 1 then
                    OpenStackSplitFrame(this.itemCount, this, "BOTTOMLEFT", "TOPLEFT")
                elseif link and ChatFrameEditBox then
                    ChatFrameEditBox:Insert(link)
                end
            elseif arg1 == "LeftButton" then
                PickupContainerItem(bagID, slotID)
            elseif arg1 == "RightButton" then
                UseContainerItem(bagID, slotID)
            end
        else
            -- Offline view
            if IsControlKeyDown() and link then
                DressUpItemLink(link)
            elseif IsShiftKeyDown() and link and ChatFrameEditBox then
                ChatFrameEditBox:Insert(link)
            end
        end
    end)

    slot:SetScript("OnDragStart", function()
        if isBankOpen and this.bagID and this.slotID then
            PickupContainerItem(this.bagID, this.slotID)
        end
    end)

    slot:SetScript("OnReceiveDrag", function()
        if isBankOpen and this.bagID and this.slotID then
            PickupContainerItem(this.bagID, this.slotID)
        end
    end)

    slot:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        local hasItem = false

        if isBankOpen and this.bagID and this.slotID then
            if this.bagID == -1 then
                local invSlot = this.invSlot or (BankButtonIDToInvSlotID and BankButtonIDToInvSlotID(this.slotID, nil)) or (39 + this.slotID)
                if invSlot and GetInventoryItemTexture("player", invSlot) then
                    GameTooltip:SetInventoryItem("player", invSlot)
                    GameTooltip:Show()
                    hasItem = true
                end
            else
                local texture = GetContainerItemInfo(this.bagID, this.slotID)
                if texture then
                    GameTooltip:SetBagItem(this.bagID, this.slotID)
                    GameTooltip:Show()
                    hasItem = true
                end
            end
        end

        if not hasItem and this.itemLink then
            local rawLink = Utils.ExtractLink(this.itemLink) or this.itemLink
            if rawLink then
                GameTooltip:SetHyperlink(rawLink)
                GameTooltip:Show()
                hasItem = true
            end
        end

        if not hasItem then
            GameTooltip:Hide()
        end
    end)

    slot:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    slot.SplitStack = function(self, split)
        if isBankOpen and self.bagID and self.slotID and split and split > 0 then
            SplitContainerItem(self.bagID, self.slotID, split)
        end
    end

    bankSlots[index] = slot
    return slot
end

-- Helper to safely get the player inventory slot ID for a bank bag (1..6 -> Bags 5..10)
local function GetBankBagInvSlot(bagIndex)
    local bagID = bagIndex + 4
    if ContainerIDToInventoryID then
        local invSlot = ContainerIDToInventoryID(bagID)
        if invSlot and invSlot > 0 then return invSlot end
    end
    if BankButtonIDToInvSlotID then
        local invSlot = BankButtonIDToInvSlotID(bagIndex, 1)
        if invSlot and invSlot > 0 then return invSlot end
    end
    return nil
end

-- =========================================================================
-- BANK BAG SLOT FACTORY (Bags 5 to 10)
-- =========================================================================

local function CreateBankBagSlot(parent, bagIndex)
    local slot = CreateFrame("Button", "Primus_PUIBankBagSlot_" .. bagIndex, parent)
    slot:SetWidth(28)
    slot:SetHeight(28)
    slot:SetBackdrop(Media:Fetch("border", "1Pixel"))
    slot:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
    slot:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)

    local icon = slot:CreateTexture(slot:GetName() .. "Icon", "BORDER")
    icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    slot.icon = icon

    local highlight = slot:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")
    highlight:SetAllPoints(slot)

    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot:RegisterForDrag("LeftButton")

    slot:SetScript("OnClick", function()
        if not isBankOpen then return end
        local invSlot = GetBankBagInvSlot(bagIndex)
        local numSlotsPurchased, isFull = GetNumBankSlots()

        if bagIndex > (numSlotsPurchased or 0) then
            -- Prompt to purchase slot if this is the next purchasable bag slot
            if bagIndex == (numSlotsPurchased or 0) + 1 then
                local cost = GetBankSlotCost(numSlotsPurchased)
                if GetMoney() >= cost then
                    StaticPopupDialogs["CONFIRM_BUY_BANK_SLOT_PRIMUS"] = {
                        text = string.format("Purchase a bank bag slot for %s?", Utils.FormatMoney(cost)),
                        button1 = YES,
                        button2 = NO,
                        OnAccept = function()
                            PurchaseSlot()
                        end,
                        timeout = 0,
                        whileDead = 1,
                        hideOnEscape = 1
                    }
                    StaticPopup_Show("CONFIRM_BUY_BANK_SLOT_PRIMUS")
                else
                    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[Bank]: Not enough money to purchase this bank slot.", "ff5555"))
                end
            end
        else
            if invSlot then
                if CursorHasItem() then
                    PutItemInBag(invSlot)
                else
                    PickupBagFromSlot(invSlot)
                end
            end
        end
    end)

    slot:SetScript("OnDragStart", function()
        if not isBankOpen then return end
        local invSlot = GetBankBagInvSlot(bagIndex)
        local numSlotsPurchased = GetNumBankSlots()
        if invSlot and bagIndex <= (numSlotsPurchased or 0) then
            PickupBagFromSlot(invSlot)
        end
    end)

    slot:SetScript("OnReceiveDrag", function()
        if not isBankOpen then return end
        local invSlot = GetBankBagInvSlot(bagIndex)
        local numSlotsPurchased = GetNumBankSlots()
        if invSlot and bagIndex <= (numSlotsPurchased or 0) then
            PutItemInBag(invSlot)
        end
    end)

    slot:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        local numSlotsPurchased = isBankOpen and GetNumBankSlots() or 0
        local invSlot = GetBankBagInvSlot(bagIndex)

        if isBankOpen and bagIndex > (numSlotsPurchased or 0) then
            local cost = GetBankSlotCost(numSlotsPurchased)
            GameTooltip:SetText(BANK_BAG_PURCHASE or "Purchase Bank Slot", 1.0, 0.82, 0.0)
            GameTooltip:AddLine(string.format("Cost: %s", Utils.FormatMoney(cost)), 1.0, 1.0, 1.0)
            GameTooltip:Show()
        elseif isBankOpen and invSlot then
            local hasBag = GetInventoryItemTexture("player", invSlot)
            if hasBag then
                GameTooltip:SetInventoryItem("player", invSlot)
            else
                GameTooltip:SetText(BANK_BAG or "Bank Bag Slot", 1.0, 1.0, 1.0)
            end
            GameTooltip:Show()
        elseif this.itemLink then
            local rawLink = Utils.ExtractLink(this.itemLink)
            if rawLink then
                GameTooltip:SetHyperlink(rawLink)
                GameTooltip:Show()
            end
        else
            GameTooltip:SetText(BANK_BAG or "Bank Bag Slot", 1.0, 1.0, 1.0)
            GameTooltip:Show()
        end
    end)

    slot:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    bankBagSlots[bagIndex] = slot
    return slot
end

-- =========================================================================
-- SCANNING & PERSISTENCE
-- =========================================================================

function PUIBank:ScanLiveBank()
    local items = {}
    local slotIndex = 0

    -- 1. Main Bank Container (-1) (24 base slots)
    for slotID = 1, 24 do
        slotIndex = slotIndex + 1
        local invSlot = BankButtonIDToInvSlotID and BankButtonIDToInvSlotID(slotID, nil) or (39 + slotID)
        local texture = (invSlot and GetInventoryItemTexture("player", invSlot)) or GetContainerItemInfo(-1, slotID)
        local link = (invSlot and GetInventoryItemLink("player", invSlot)) or GetContainerItemLink(-1, slotID)
        local count = (invSlot and GetInventoryItemCount("player", invSlot)) or 1
        local quality = 1
        if link then
            local _, _, q = GetItemInfo(link)
            quality = q or 1
        end
        local name = link and GetItemInfo(link) or ""

        items[slotIndex] = {
            texture = texture,
            count   = (count and count > 0) and count or 1,
            link    = link,
            name    = name or "",
            quality = quality or 1,
            bagID   = -1,
            slotID  = slotID,
            invSlot = invSlot,
            locked  = false,
        }
    end

    -- 2. Bank Bags (5 to 10)
    local bags = {}
    for bagIndex = 1, 6 do
        local bagID = bagIndex + 4 -- Bags 5..10
        local invSlot = GetBankBagInvSlot(bagIndex)
        local bagTexture = invSlot and GetInventoryItemTexture("player", invSlot)
        local bagLink = invSlot and GetInventoryItemLink("player", invSlot)
        local numSlots = GetContainerNumSlots(bagID) or 0

        bags[bagIndex] = {
            texture  = bagTexture,
            link     = bagLink,
            numSlots = numSlots,
        }

        if numSlots > 0 then
            for slotID = 1, numSlots do
                slotIndex = slotIndex + 1
                local texture, count, locked, quality = GetContainerItemInfo(bagID, slotID)
                local link = GetContainerItemLink(bagID, slotID)
                local name = link and GetItemInfo(link) or ""
                if link and not quality then
                    local _, _, q = GetItemInfo(link)
                    quality = q or 1
                end

                items[slotIndex] = {
                    texture = texture,
                    count   = count or 1,
                    link    = link,
                    name    = name or "",
                    quality = quality or 1,
                    bagID   = bagID,
                    slotID  = slotID,
                    locked  = locked,
                }
            end
        end
    end

    bankDB:Set("cachedItems", items)
    bankDB:Set("cachedBags", bags)
    bankDB:Set("lastScanned", date("%Y-%m-%d %H:%M"))

    return items, bags
end

-- =========================================================================
-- REFRESH & DYNAMIC LAYOUT
-- =========================================================================

function PUIBank:UpdateBankSlots()
    if not bankFrame or not bankFrame:IsShown() then return end

    local cols    = configDB:Get("cols", 10)
    local size    = configDB:Get("slotSize", 34)
    local spacing = configDB:Get("spacing", 4)
    local showTray = configDB:Get("showBagTray", true)

    local items, bags
    if isBankOpen then
        items, bags = self:ScanLiveBank()
    else
        items = bankDB:Get("cachedItems") or {}
        bags  = bankDB:Get("cachedBags") or {}
    end

    -- If no cache exists yet for offline view, generate 24 empty slots
    local totalItems = 0
    for idx, it in pairs(items) do
        if idx > totalItems then totalItems = idx end
    end

    if totalItems < 24 then
        totalItems = 24
        for slotID = 1, 24 do
            if not items[slotID] then
                items[slotID] = { bagID = -1, slotID = slotID }
            end
        end
    end

    local freeCount  = 0
    local totalCount = 0

    -- Layout & populate item slots
    for i = 1, totalItems do
        local slotBtn = bankSlots[i] or CreateBankSlot(bankFrame.slotContainer, i)
        local item = items[i] or { bagID = -1, slotID = i }

        totalCount = totalCount + 1
        slotBtn.bagID = item.bagID
        slotBtn.slotID = item.slotID
        slotBtn.invSlot = item.invSlot
        slotBtn.itemLink = item.link
        slotBtn.itemCount = item.count

        local row = math.floor((i - 1) / cols)
        local col = Utils.Mod(i - 1, cols)
        slotBtn:ClearAllPoints()
        slotBtn:SetPoint("TOPLEFT", bankFrame.slotContainer, "TOPLEFT", col * (size + spacing), -(row * (size + spacing)))

        if item.texture then
            slotBtn.icon:SetTexture(item.texture)
            slotBtn.icon:Show()

            if item.count and item.count > 1 then
                slotBtn.count:SetText(item.count)
                slotBtn.count:Show()
            else
                slotBtn.count:Hide()
            end

            if item.locked then
                slotBtn.icon:SetVertexColor(0.4, 0.4, 0.4)
            else
                slotBtn.icon:SetVertexColor(1, 1, 1)
            end

            if item.quality and QUALITY_COLORS[item.quality] then
                local c = QUALITY_COLORS[item.quality]
                slotBtn:SetBackdropBorderColor(c.r, c.g, c.b, 1)
            else
                slotBtn:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)
            end

            if searchFilter ~= "" and item.name then
                if string.find(string.lower(item.name), string.lower(searchFilter)) then
                    slotBtn:SetAlpha(1.0)
                else
                    slotBtn:SetAlpha(0.2)
                end
            else
                slotBtn:SetAlpha(1.0)
            end
        else
            freeCount = freeCount + 1
            slotBtn.icon:Hide()
            slotBtn.count:Hide()
            slotBtn:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)
            slotBtn:SetAlpha(searchFilter ~= "" and 0.2 or 1.0)
        end

        slotBtn:Show()
    end

    -- Hide unused slot buttons beyond totalItems
    local numExisting = table.getn(bankSlots)
    for i = totalItems + 1, numExisting do
        if bankSlots[i] then bankSlots[i]:Hide() end
    end

    -- Update Bank Bag Tray (6 bags)
    local purchasedSlots = isBankOpen and (GetNumBankSlots() or 0) or 6
    if showTray and bankFrame.bagTray then
        bankFrame.bagTray:Show()
        for bagIdx = 1, 6 do
            local bagBtn = bankBagSlots[bagIdx] or CreateBankBagSlot(bankFrame.bagTray, bagIdx)
            local bagData = bags and bags[bagIdx]

            bagBtn:ClearAllPoints()
            bagBtn:SetPoint("LEFT", bankFrame.bagTray, "LEFT", (bagIdx - 1) * 32, 0)

            if isBankOpen then
                if bagIdx <= purchasedSlots then
                    local invSlot = GetBankBagInvSlot(bagIdx)
                    local tex = invSlot and GetInventoryItemTexture("player", invSlot)
                    if tex then
                        bagBtn.icon:SetTexture(tex)
                        bagBtn.icon:Show()
                        bagBtn.icon:SetVertexColor(1.0, 1.0, 1.0)
                        bagBtn:SetBackdropBorderColor(0.3, 0.6, 0.9, 1)
                    else
                        bagBtn.icon:SetTexture("Interface\\Paperdoll\\UI-PaperDoll-Slot-Bag")
                        bagBtn.icon:Show()
                        bagBtn.icon:SetVertexColor(0.7, 0.7, 0.7)
                        bagBtn:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
                    end
                elseif bagIdx == purchasedSlots + 1 then
                    -- Next purchasable slot
                    bagBtn.icon:SetTexture("Interface\\Paperdoll\\UI-PaperDoll-Slot-Bag")
                    bagBtn.icon:Show()
                    bagBtn.icon:SetVertexColor(1.0, 0.3, 0.3)
                    bagBtn:SetBackdropBorderColor(1.0, 0.4, 0.4, 1)
                else
                    -- Locked slot
                    bagBtn.icon:SetTexture("Interface\\Paperdoll\\UI-PaperDoll-Slot-Bag")
                    bagBtn.icon:Show()
                    bagBtn.icon:SetVertexColor(0.3, 0.3, 0.3)
                    bagBtn:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)
                end
            else
                -- Offline bag tray
                if bagData and bagData.texture then
                    bagBtn.icon:SetTexture(bagData.texture)
                    bagBtn.icon:Show()
                    bagBtn.icon:SetVertexColor(1.0, 1.0, 1.0)
                    bagBtn.itemLink = bagData.link
                else
                    bagBtn.icon:SetTexture("Interface\\Paperdoll\\UI-PaperDoll-Slot-Bag")
                    bagBtn.icon:Show()
                    bagBtn.icon:SetVertexColor(0.5, 0.5, 0.5)
                    bagBtn.itemLink = nil
                end
            end
            bagBtn:Show()
        end
    elseif bankFrame.bagTray then
        bankFrame.bagTray:Hide()
    end

    -- Dynamic Window Sizing
    local numRows = math.ceil(totalItems / cols)
    local trayH = showTray and 38 or 0
    local frameW = 20 + cols * (size + spacing) - spacing
    local frameH = 60 + numRows * (size + spacing) + trayH

    bankFrame:SetWidth(math.max(frameW, 220))
    bankFrame:SetHeight(frameH)

    if bankFrame.bagTray then
        bankFrame.bagTray:ClearAllPoints()
        bankFrame.bagTray:SetPoint("BOTTOMLEFT", bankFrame, "BOTTOMLEFT", 10, 10)
    end

    -- Title & Status
    if bankFrame.title then
        if isBankOpen then
            bankFrame.title:SetText("Bank")
        else
            local last = bankDB:Get("lastScanned") or "Never"
            bankFrame.title:SetText("Bank (Offline: " .. last .. ")")
        end
    end

    if bankFrame.infoText then
        bankFrame.infoText:SetText(string.format("Free: %d / %d", freeCount, totalCount))
    end

    local mover = PUIMover or Primus.PUIMover
    if mover and mover.UpdateFrame then
        mover:UpdateFrame("PUIBank")
    end
end

-- =========================================================================
-- WINDOW CONSTRUCTOR
-- =========================================================================

function PUIBank:CreateBankUI()
    if bankFrame then return bankFrame end

    -- Main Bank Panel
    bankFrame = Widgets:CreatePanel(UIParent, "PUIBank", 360, 480)
    bankFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 50, -100)
    bankFrame:SetFrameStrata("HIGH")
    bankFrame:Hide()

    if bankFrame.closeButton then
        bankFrame.closeButton:SetScript("OnClick", function()
            if isBankOpen then
                CloseBankFrame()
            end
            bankFrame:Hide()
        end)
    end

    bankFrame:SetScript("OnHide", function()
        if isBankOpen then
            isBankOpen = false
            CloseBankFrame()
        end
    end)

    -- Register with UISpecialFrames so Escape key closes it
    table.insert(UISpecialFrames, bankFrame:GetName())

    -- Search EditBox
    local searchBox = CreateFrame("EditBox", "Primus_PUIBankSearchBox", bankFrame)
    searchBox:SetWidth(140)
    searchBox:SetHeight(20)
    searchBox:SetPoint("TOPLEFT", bankFrame, "TOPLEFT", 10, -28)
    searchBox:SetBackdrop(Media:Fetch("border", "1Pixel"))
    searchBox:SetBackdropColor(0.05, 0.05, 0.05, 0.8)
    searchBox:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
    searchBox:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    searchBox:SetAutoFocus(false)
    searchBox:SetText("Search...")

    searchBox:SetScript("OnEditFocusGained", function()
        if searchBox:GetText() == "Search..." then searchBox:SetText("") end
    end)
    searchBox:SetScript("OnTextChanged", function()
        local text = searchBox:GetText()
        searchFilter = (text == "Search...") and "" or text
        PUIBank:UpdateBankSlots()
    end)
    searchBox:SetScript("OnEscapePressed", function()
        searchBox:ClearFocus()
        searchBox:SetText("Search...")
        searchFilter = ""
        PUIBank:UpdateBankSlots()
    end)

    -- Free Space Text
    local infoText = bankFrame:CreateFontString(nil, "OVERLAY")
    infoText:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    infoText:SetPoint("TOPRIGHT", bankFrame, "TOPRIGHT", -10, -32)
    infoText:SetTextColor(0.8, 0.8, 0.8)
    bankFrame.infoText = infoText

    -- Slot Container
    local slotContainer = CreateFrame("Frame", nil, bankFrame)
    slotContainer:SetPoint("TOPLEFT", bankFrame, "TOPLEFT", 10, -56)
    slotContainer:SetPoint("BOTTOMRIGHT", bankFrame, "BOTTOMRIGHT", -10, 48)
    bankFrame.slotContainer = slotContainer

    -- Bank Bag Tray Frame
    local bagTray = CreateFrame("Frame", "Primus_PUIBankBagTray", bankFrame)
    bagTray:SetWidth(6 * 32)
    bagTray:SetHeight(32)
    bagTray:SetPoint("BOTTOMLEFT", bankFrame, "BOTTOMLEFT", 10, 10)
    bankFrame.bagTray = bagTray

    local mover = PUIMover or Primus.PUIMover
    if mover and mover.Register then
        mover:Register(bankFrame, "PUIBank", "PUIBank: Unified Bank", "PLAYER")
    end

    return bankFrame
end

-- =========================================================================
-- OPTIONS FLARE
-- =========================================================================

function PUIBank:RegisterOptionsFlare()
    local Options = Primus.Options
    if not Options or not Options.RegisterModuleOptions then return end

    Options:RegisterModuleOptions("PUIBank", "Player", {
        title = "PUIBank: Unified Bank & Offline Cache",
        description = "Unified bank interface with character inventory persistence, search, and bank bag bar.",
        fields = {
            {
                key = "enabled",
                label = "Enable Unified Bank Frame",
                type = "checkbox",
                default = true,
                get = function() return configDB:Get("enabled", true) end,
                set = function(val)
                    configDB:Set("enabled", val)
                    if val then PUIBank:OnEnable() else PUIBank:OnDisable() end
                end,
            },
            {
                key = "showBagTray",
                label = "Show Bank Bag Slot Tray",
                type = "checkbox",
                default = true,
                get = function() return configDB:Get("showBagTray", true) end,
                set = function(val)
                    configDB:Set("showBagTray", val)
                    PUIBank:UpdateBankSlots()
                end,
            },
        },
    })
end

-- =========================================================================
-- LIFECYCLE & EVENT DISPATCH
-- =========================================================================

function PUIBank:OnInitialize()
    self:RegisterOptionsFlare()

    -- Subcommand registration via Console Router
    if Primus.Console and Primus.Console.RegisterSubCommand then
        Primus.Console:RegisterSubCommand("bank", function()
            if bankFrame and bankFrame:IsShown() then
                bankFrame:Hide()
            else
                if not bankFrame then PUIBank:CreateBankUI() end
                bankFrame:Show()
                PUIBank:UpdateBankSlots()
            end
        end, "Toggle Unified Bank Frame (/pui bank)")
    end
end

function PUIBank:OnEnable()
    -- Hook Bank Events & Keep BankFrame visible off-screen for C-engine UseContainerItem routing
    Events:Register("BANKFRAME_OPENED", "PUIBank", function()
        isBankOpen = true
        if BankFrame then
            BankFrame:SetAlpha(0)
            BankFrame:ClearAllPoints()
            BankFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -2000, 2000)
            BankFrame:Show()
        end
        if not bankFrame then PUIBank:CreateBankUI() end
        bankFrame:Show()
        PUIBank:UpdateBankSlots()
    end)

    Events:Register("BANKFRAME_CLOSED", "PUIBank", function()
        isBankOpen = false
        if BankFrame then
            BankFrame:Hide()
        end
        if bankFrame then bankFrame:Hide() end
    end)

    Events:Register("PLAYERBANKSLOTS_CHANGED", "PUIBank", function()
        if isBankOpen and bankFrame and bankFrame:IsShown() then
            PUIBank:UpdateBankSlots()
        end
    end)

    Events:Register("PLAYERBANKBAGSLOTS_CHANGED", "PUIBank", function()
        if isBankOpen and bankFrame and bankFrame:IsShown() then
            PUIBank:UpdateBankSlots()
        end
    end)

    Events:Register("ITEM_LOCK_CHANGED", "PUIBank", function()
        if isBankOpen and bankFrame and bankFrame:IsShown() then
            PUIBank:UpdateBankSlots()
        end
    end)
end

function PUIBank:OnDisable()
    Events:UnregisterOwner("PUIBank")
    if bankFrame and bankFrame:IsShown() then
        bankFrame:Hide()
    end
    if BankFrame then
        BankFrame:Hide()
    end
end
