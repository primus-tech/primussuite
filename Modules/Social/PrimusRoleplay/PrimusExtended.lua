--[[
    PrimusUI: PUIRoleplay TotalRP3 Extended Items, Documents & Stash Engine (PUIExtended.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (Custom RP Bag, Item Forge, Parchment Letters & Stashes)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIRoleplay = Primus.PUIRoleplay or {}
Primus.PUIRoleplay = PUIRoleplay

local Extended = {}
PUIRoleplay.Extended = Extended

local bagFrame = nil
local forgeFrame = nil
local docFrame = nil
local selectedBagSlot = nil

-- Item Quality Color Palette
Extended.QualityColors = {
    [0] = { hex = "9d9d9d", name = "Poor",        r = 0.62, g = 0.62, b = 0.62 },
    [1] = { hex = "ffffff", name = "Common",      r = 1.00, g = 1.00, b = 1.00 },
    [2] = { hex = "1eff00", name = "Uncommon",    r = 0.12, g = 1.00, b = 0.00 },
    [3] = { hex = "0070dd", name = "Rare",        r = 0.00, g = 0.44, b = 0.87 },
    [4] = { hex = "a335ee", name = "Epic",        r = 0.64, g = 0.21, b = 0.93 },
    [5] = { hex = "ff8000", name = "Legendary",   r = 1.00, g = 0.50, b = 0.00 },
    [6] = { hex = "e6cc80", name = "Artifact",    r = 0.90, g = 0.80, b = 0.50 },
}

-- Default Sample RP Items
Extended.DefaultItems = {
    [1] = {
        name = "Old Adventurer's Journal",
        icon = "INV_Misc_Book_09",
        quality = 3,
        category = "Book / Document",
        stack = 1,
        weight = "0.5 lbs",
        desc = "A leather-bound journal weathered by years of exploration across the Eastern Kingdoms.",
        useText = "leafs through the yellowed pages of an old journal, murmuring thoughtfully."
    },
    [2] = {
        name = "Dwarven Spiced Stout",
        icon = "INV_Drink_04",
        quality = 2,
        category = "Consumable",
        stack = 3,
        weight = "1.0 lb",
        desc = "A foaming flagon of spiced dark stout brewed in the heart of Ironforge.",
        useText = "takes a deep swig from a flagon of Dwarven Spiced Stout, sighing with satisfaction."
    },
    [3] = {
        name = "Mysterious Wax-Sealed Letter",
        icon = "INV_Misc_Note_01",
        quality = 4,
        category = "Book / Document",
        stack = 1,
        weight = "0.1 lbs",
        desc = "A heavy vellum missive bearing the crimson wax seal of a secret noble syndicate.",
        useText = "breaks the crimson wax seal and carefully reads the contents of the letter."
    }
}

--------------------------------------------------------------------------------
-- Storage & Inventory Model
--------------------------------------------------------------------------------
function Extended:GetInventory()
    local p = PUIRoleplay:GetMyProfile()
    if not p.rp_inventory then
        p.rp_inventory = {}
        for i = 1, 3 do
            p.rp_inventory[i] = Extended.DefaultItems[i]
        end
        PUIRoleplay:SaveMyProfile(p)
    end
    return p.rp_inventory
end

function Extended:SaveItem(slotIdx, itemData)
    local inv = self:GetInventory()
    inv[slotIdx] = itemData
    PUIRoleplay:SaveMyProfile(PUIRoleplay:GetMyProfile())
    self:RefreshBag()
end

function Extended:DeleteItem(slotIdx)
    local inv = self:GetInventory()
    inv[slotIdx] = nil
    PUIRoleplay:SaveMyProfile(PUIRoleplay:GetMyProfile())
    self:RefreshBag()
end

function Extended:UseItem(slotIdx)
    local inv = self:GetInventory()
    local item = inv[slotIdx]
    if not item then return end

    local useEmote = item.useText
    if not useEmote or useEmote == "" then
        useEmote = "uses " .. item.name .. "."
    end

    SendChatMessage(useEmote, "EMOTE")
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[RP Item Used]:|r " .. item.name)
end

--------------------------------------------------------------------------------
-- Item Tooltip Helper
--------------------------------------------------------------------------------
function Extended:ShowItemTooltip(frame, item)
    if not item then return end
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")

    local q = Extended.QualityColors[item.quality or 1] or Extended.QualityColors[1]
    GameTooltip:AddLine(item.name or "Unnamed Item", q.r, q.g, q.b)

    if item.category and item.category ~= "" then
        GameTooltip:AddLine(item.category .. ((item.stack and item.stack > 1) and (" (x" .. item.stack .. ")") or ""), 0.8, 0.8, 0.8)
    end

    if item.weight and item.weight ~= "" then
        GameTooltip:AddLine("Weight: " .. item.weight, 0.6, 0.6, 0.6)
    end

    if item.desc and item.desc ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("\"" .. item.desc .. "\"", 1.0, 0.82, 0.0, true)
    end

    if item.useText and item.useText ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Use: " .. item.useText, 0.2, 1.0, 0.2, true)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cff00ccffLeft-Click:|r Inspect / Edit   |cff00ff88Right-Click:|r Use Item", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Build Extended RP Bag Frame (20 Slots)
--------------------------------------------------------------------------------
function Extended:BuildBagFrame()
    if bagFrame then return bagFrame end

    local f = CreateFrame("Frame", "Primus_PUIRoleplay_BagFrame", UIParent)
    f:SetWidth(380)
    f:SetHeight(440)
    f:SetPoint("CENTER", UIParent, "CENTER", -200, 40)
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
    f:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
    f:SetBackdropBorderColor(0.20, 0.22, 0.28, 1.0)
    table.insert(UISpecialFrames, "Primus_PUIRoleplay_BagFrame")

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
    titleText:SetText("|cff00ccffRP EXTENDED|r |cffffffffINVENTORY POUCH|r")

    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetWidth(18)
    closeBtn:SetHeight(18)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Top Action Buttons: + Create New Item, Open Documents
    local newBtn = CreateFrame("Button", nil, f)
    newBtn:SetWidth(170)
    newBtn:SetHeight(22)
    newBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -34)
    newBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    newBtn:SetBackdropColor(0.10, 0.18, 0.28, 0.95)
    newBtn:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
    local nTxt = newBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nTxt:SetPoint("CENTER", newBtn, "CENTER", 0, 0)
    nTxt:SetText("|cff00ccff+ Create New RP Item|r")
    newBtn:SetScript("OnClick", function()
        Extended:OpenItemForge()
    end)

    local docBtn = CreateFrame("Button", nil, f)
    docBtn:SetWidth(170)
    docBtn:SetHeight(22)
    docBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -34)
    docBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    docBtn:SetBackdropColor(0.20, 0.15, 0.08, 0.95)
    docBtn:SetBackdropBorderColor(1.0, 0.75, 0.2, 1.0)
    local dTxt = docBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dTxt:SetPoint("CENTER", docBtn, "CENTER", 0, 0)
    dTxt:SetText("|cffffd100Parchment Letters / Docs|r")
    docBtn:SetScript("OnClick", function()
        Extended:OpenDocumentEngine()
    end)

    -- 20 Slot Grid (4 Columns x 5 Rows)
    local slots = {}
    local slotSize = 64
    local cols = 4
    for idx = 1, 20 do
        local col = math.mod(idx - 1, cols)
        local row = math.floor((idx - 1) / cols)

        local slot = CreateFrame("Button", nil, f)
        slot:SetWidth(slotSize)
        slot:SetHeight(slotSize)
        slot:SetPoint("TOPLEFT", f, "TOPLEFT", 16 + col * (slotSize + 24), -66 - row * (slotSize + 10))
        slot:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        slot:SetBackdropColor(0.04, 0.04, 0.06, 0.95)
        slot:SetBackdropBorderColor(0.25, 0.25, 0.32, 1.0)

        local icon = slot:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -2, 2)
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        slot.icon = icon

        local stackTxt = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        stackTxt:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -4, 4)
        slot.stackTxt = stackTxt

        slot.slotIdx = idx
        slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        slot:SetScript("OnEnter", function()
            this:SetBackdropColor(0.12, 0.20, 0.30, 1.0)
            local inv = Extended:GetInventory()
            local item = inv[this.slotIdx]
            if item then
                Extended:ShowItemTooltip(this, item)
            else
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Empty RP Bag Slot " .. this.slotIdx, 0.7, 0.7, 0.7)
                GameTooltip:AddLine("Click to craft an item in this slot.", 0.5, 0.8, 1.0)
                GameTooltip:Show()
            end
        end)

        slot:SetScript("OnLeave", function()
            GameTooltip:Hide()
            Extended:RefreshBag()
        end)

        slot:SetScript("OnClick", function()
            if arg1 == "RightButton" then
                Extended:UseItem(this.slotIdx)
            else
                local inv = Extended:GetInventory()
                if inv[this.slotIdx] then
                    Extended:OpenItemForge(this.slotIdx, inv[this.slotIdx])
                else
                    Extended:OpenItemForge(this.slotIdx, nil)
                end
            end
        end)

        slots[idx] = slot
    end
    f.slots = slots

    bagFrame = f
    self:RefreshBag()
    return f
end

function Extended:RefreshBag()
    local f = bagFrame
    if not f then return end

    local inv = self:GetInventory()
    for idx = 1, 20 do
        local slot = f.slots[idx]
        local item = inv[idx]
        if item and item.name and item.name ~= "" then
            slot.icon:SetTexture("Interface\\Icons\\" .. (item.icon or "INV_Misc_QuestionMark"))
            slot.icon:Show()

            local q = Extended.QualityColors[item.quality or 1] or Extended.QualityColors[1]
            slot:SetBackdropBorderColor(q.r, q.g, q.b, 1.0)

            if item.stack and item.stack > 1 then
                slot.stackTxt:SetText(tostring(item.stack))
                slot.stackTxt:Show()
            else
                slot.stackTxt:Hide()
            end
        else
            slot.icon:Hide()
            slot.stackTxt:Hide()
            slot:SetBackdropBorderColor(0.20, 0.22, 0.26, 0.8)
        end
    end
end

--------------------------------------------------------------------------------
-- Item Forge (Creator & Inspector Modal)
--------------------------------------------------------------------------------
function Extended:OpenItemForge(slotIdx, existingItem)
    slotIdx = slotIdx or 1
    selectedBagSlot = slotIdx

    local f = forgeFrame
    if not f then
        f = CreateFrame("Frame", "Primus_PUIRoleplay_ItemForge", UIParent)
        f:SetWidth(360)
        f:SetHeight(420)
        f:SetPoint("CENTER", UIParent, "CENTER", 100, 20)
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        f:SetBackdropColor(0.06, 0.06, 0.09, 0.98)
        f:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
        table.insert(UISpecialFrames, "Primus_PUIRoleplay_ItemForge")

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
        title:SetText("|cff00ccffITEM FORGE & INSPECTOR|r")

        local closeBtn = CreateFrame("Button", nil, f)
        closeBtn:SetWidth(16)
        closeBtn:SetHeight(16)
        closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
        closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
        closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        -- Icon Selector Button
        local iconBtn = CreateFrame("Button", nil, f)
        iconBtn:SetWidth(44)
        iconBtn:SetHeight(44)
        iconBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -36)
        iconBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        iconBtn:SetBackdropColor(0, 0, 0, 1)
        iconBtn:SetBackdropBorderColor(0.4, 0.4, 0.5, 1)
        local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
        iconTex:SetPoint("TOPLEFT", iconBtn, "TOPLEFT", 1, -1)
        iconTex:SetPoint("BOTTOMRIGHT", iconBtn, "BOTTOMRIGHT", -1, 1)
        iconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        iconBtn.tex = iconTex
        f.iconBtn = iconBtn

        iconBtn:SetScript("OnClick", function()
            PUIRoleplay.Sheet:OpenIconPicker(function(iconIdx)
                local file = PUIRoleplay.Icons[iconIdx] or "INV_Misc_QuestionMark"
                f.selectedIcon = file
                f.iconBtn.tex:SetTexture("Interface\\Icons\\" .. file)
            end)
        end)

        -- Item Name EditBox
        local nameLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameLabel:SetPoint("TOPLEFT", iconBtn, "TOPRIGHT", 10, 0)
        nameLabel:SetText("|cff00e5ffItem Name:|r")
        local nameEB = CreateFrame("EditBox", nil, f)
        nameEB:SetWidth(270)
        nameEB:SetHeight(20)
        nameEB:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -2)
        nameEB:SetFontObject(GameFontHighlightSmall)
        nameEB:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        nameEB:SetBackdropColor(0.04, 0.04, 0.07, 0.95)
        nameEB:SetBackdropBorderColor(0.30, 0.30, 0.38, 1.0)
        nameEB:SetTextInsets(4, 4, 2, 2)
        f.nameEB = nameEB

        -- Category & Quality
        local catLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        catLabel:SetPoint("TOPLEFT", iconBtn, "BOTTOMLEFT", 0, -10)
        catLabel:SetText("|cff00e5ffCategory / Type:|r")
        local catEB = CreateFrame("EditBox", nil, f)
        catEB:SetWidth(155)
        catEB:SetHeight(20)
        catEB:SetPoint("TOPLEFT", catLabel, "BOTTOMLEFT", 0, -2)
        catEB:SetFontObject(GameFontHighlightSmall)
        catEB:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        catEB:SetBackdropColor(0.04, 0.04, 0.07, 0.95)
        catEB:SetBackdropBorderColor(0.30, 0.30, 0.38, 1.0)
        catEB:SetTextInsets(4, 4, 2, 2)
        f.catEB = catEB

        local qualLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        qualLabel:SetPoint("TOPLEFT", catLabel, "TOPLEFT", 170, 0)
        qualLabel:SetText("|cff00e5ffQuality Tier (0-6):|r")
        local qualEB = CreateFrame("EditBox", nil, f)
        qualEB:SetWidth(155)
        qualEB:SetHeight(20)
        qualEB:SetPoint("TOPLEFT", qualLabel, "BOTTOMLEFT", 0, -2)
        qualEB:SetFontObject(GameFontHighlightSmall)
        qualEB:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        qualEB:SetBackdropColor(0.04, 0.04, 0.07, 0.95)
        qualEB:SetBackdropBorderColor(0.30, 0.30, 0.38, 1.0)
        qualEB:SetTextInsets(4, 4, 2, 2)
        f.qualEB = qualEB

        -- Lore Description
        local descLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        descLabel:SetPoint("TOPLEFT", catEB, "BOTTOMLEFT", 0, -10)
        descLabel:SetText("|cff00e5ffLore Description / Flavor Text:|r")
        local descEB = CreateFrame("EditBox", nil, f)
        descEB:SetWidth(330)
        descEB:SetHeight(70)
        descEB:SetMultiLine(true)
        descEB:SetPoint("TOPLEFT", descLabel, "BOTTOMLEFT", 0, -2)
        descEB:SetFontObject(GameFontHighlightSmall)
        descEB:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        descEB:SetBackdropColor(0.04, 0.04, 0.07, 0.95)
        descEB:SetBackdropBorderColor(0.30, 0.30, 0.38, 1.0)
        descEB:SetTextInsets(6, 6, 6, 6)
        f.descEB = descEB

        -- On-Use Emote Action
        local useLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        useLabel:SetPoint("TOPLEFT", descEB, "BOTTOMLEFT", 0, -10)
        useLabel:SetText("|cff00e5ffOn-Use Emote Action Script:|r")
        local useEB = CreateFrame("EditBox", nil, f)
        useEB:SetWidth(330)
        useEB:SetHeight(40)
        useEB:SetMultiLine(true)
        useEB:SetPoint("TOPLEFT", useLabel, "BOTTOMLEFT", 0, -2)
        useEB:SetFontObject(GameFontHighlightSmall)
        useEB:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        useEB:SetBackdropColor(0.04, 0.04, 0.07, 0.95)
        useEB:SetBackdropBorderColor(0.30, 0.30, 0.38, 1.0)
        useEB:SetTextInsets(6, 6, 6, 6)
        f.useEB = useEB

        -- Save & Delete Buttons
        local saveBtn = CreateFrame("Button", nil, f)
        saveBtn:SetWidth(150)
        saveBtn:SetHeight(24)
        saveBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 14)
        saveBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        saveBtn:SetBackdropColor(0.0, 0.45, 0.70, 0.95)
        saveBtn:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
        local sTxt = saveBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sTxt:SetPoint("CENTER", saveBtn, "CENTER", 0, 0)
        sTxt:SetText("Save to Slot")
        saveBtn:SetScript("OnClick", function()
            Extended:SaveItem(selectedBagSlot, {
                name = f.nameEB:GetText() or "Custom Item",
                icon = f.selectedIcon or "INV_Misc_QuestionMark",
                quality = tonumber(f.qualEB:GetText()) or 1,
                category = f.catEB:GetText() or "General",
                stack = 1,
                weight = "1.0 lb",
                desc = f.descEB:GetText() or "",
                useText = f.useEB:GetText() or ""
            })
            f:Hide()
        end)

        local delBtn = CreateFrame("Button", nil, f)
        delBtn:SetWidth(150)
        delBtn:SetHeight(24)
        delBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
        delBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        delBtn:SetBackdropColor(0.40, 0.12, 0.12, 0.95)
        delBtn:SetBackdropBorderColor(0.85, 0.25, 0.25, 1.0)
        local dTxt = delBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        dTxt:SetPoint("CENTER", delBtn, "CENTER", 0, 0)
        dTxt:SetText("Delete Item")
        delBtn:SetScript("OnClick", function()
            Extended:DeleteItem(selectedBagSlot)
            f:Hide()
        end)

        forgeFrame = f
    end

    local f = forgeFrame
    if existingItem then
        f.selectedIcon = existingItem.icon or "INV_Misc_QuestionMark"
        f.iconBtn.tex:SetTexture("Interface\\Icons\\" .. f.selectedIcon)
        f.nameEB:SetText(existingItem.name or "")
        f.catEB:SetText(existingItem.category or "")
        f.qualEB:SetText(tostring(existingItem.quality or 1))
        f.descEB:SetText(existingItem.desc or "")
        f.useEB:SetText(existingItem.useText or "")
    else
        f.selectedIcon = "INV_Misc_QuestionMark"
        f.iconBtn.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        f.nameEB:SetText("New Custom RP Item")
        f.catEB:SetText("Trinket / Relic")
        f.qualEB:SetText("2")
        f.descEB:SetText("")
        f.useEB:SetText("")
    end

    f:Show()
end

--------------------------------------------------------------------------------
-- Parchment Documents & Letters Engine
--------------------------------------------------------------------------------
function Extended:OpenDocumentEngine()
    local f = docFrame
    if not f then
        f = CreateFrame("Frame", "Primus_PUIRoleplay_DocFrame", UIParent)
        f:SetWidth(420)
        f:SetHeight(520)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        f:SetFrameStrata("DIALOG")
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
        f:SetBackdropColor(0.12, 0.10, 0.08, 0.98)
        f:SetBackdropBorderColor(0.85, 0.65, 0.20, 1.0)
        table.insert(UISpecialFrames, "Primus_PUIRoleplay_DocFrame")

        local titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleText:SetPoint("TOP", f, "TOP", 0, -12)
        titleText:SetText("|cffffd100PARCHMENT DOCUMENT & LETTER ENGINE|r")

        local closeBtn = CreateFrame("Button", nil, f)
        closeBtn:SetWidth(16)
        closeBtn:SetHeight(16)
        closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
        closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
        closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        local titleEB = CreateFrame("EditBox", nil, f)
        titleEB:SetWidth(380)
        titleEB:SetHeight(22)
        titleEB:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -36)
        titleEB:SetFontObject(GameFontNormal)
        titleEB:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        titleEB:SetBackdropColor(0.06, 0.05, 0.04, 0.9)
        titleEB:SetBackdropBorderColor(0.5, 0.4, 0.2, 1)
        titleEB:SetText("Document Title")
        f.titleEB = titleEB

        local scroll = CreateFrame("ScrollFrame", "Primus_PUIRoleplay_DocScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", titleEB, "BOTTOMLEFT", 0, -10)
        scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -36, 50)

        local docEB = CreateFrame("EditBox", nil, scroll)
        docEB:SetWidth(360)
        docEB:SetHeight(600)
        docEB:SetMultiLine(true)
        docEB:SetFontObject(GameFontHighlightSmall)
        docEB:SetTextInsets(8, 8, 8, 8)
        scroll:SetScrollChild(docEB)
        f.docEB = docEB

        local readBtn = CreateFrame("Button", nil, f)
        readBtn:SetWidth(180)
        readBtn:SetHeight(24)
        readBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 14)
        readBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        readBtn:SetBackdropColor(0.25, 0.18, 0.08, 0.95)
        readBtn:SetBackdropBorderColor(1.0, 0.75, 0.2, 1.0)
        local rt = readBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rt:SetPoint("CENTER", readBtn, "CENTER", 0, 0)
        rt:SetText("Emote Read Letter")
        readBtn:SetScript("OnClick", function()
            SendChatMessage("unfolds a parchment document titled '" .. (f.titleEB:GetText() or "Letter") .. "' and begins to read.", "EMOTE")
        end)

        docFrame = f
    end

    docFrame:Show()
end

function Extended:OpenBag()
    local f = self:BuildBagFrame()
    f:Show()
    self:RefreshBag()
end

function Extended:ToggleBag()
    local f = self:BuildBagFrame()
    if f:IsShown() then f:Hide() else f:Show(); self:RefreshBag() end
end

-- Slash command hooks
SLASH_PUIBAG1 = "/puibag"
SLASH_PUIBAG2 = "/rpbag"
SLASH_PUIBAG3 = "/puiitems"
SlashCmdList["PUIBAG"] = function()
    Extended:ToggleBag()
end

SLASH_PUIDOC1 = "/puidoc"
SLASH_PUIDOC2 = "/letter"
SLASH_PUIDOC3 = "/book"
SlashCmdList["PUIDOC"] = function()
    Extended:OpenDocumentEngine()
end
