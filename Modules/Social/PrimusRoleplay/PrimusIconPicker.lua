--[[
    PrimusUI: PUIRoleplay Virtualized Icon Picker Modal (PUIIconPicker.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (2,020+ Icon Browser & Search Engine)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIRoleplay = Primus.PUIRoleplay or {}
Primus.PUIRoleplay = PUIRoleplay

local Sheet = PUIRoleplay.Sheet or {}
PUIRoleplay.Sheet = Sheet

local iconPickerFrame = nil
local GRID_COLS = 8
local GRID_ROWS = 6
local ROW_STEP = 42

local ICON_CATEGORIES = {
    { id = "ALL",     label = "All" },
    { id = "SPELL",   label = "Spells" },
    { id = "ABILITY", label = "Abilities" },
    { id = "GEAR",    label = "Gear" },
    { id = "ITEM",    label = "Items" },
    { id = "TRADE",   label = "Trade" }
}

local function MatchesIconCategory(iconName, category)
    if not category or category == "ALL" then return true end
    if not iconName then return false end
    if category == "SPELL" then
        return string.find(iconName, "^Spell_") ~= nil
    elseif category == "ABILITY" then
        return string.find(iconName, "^Ability_") ~= nil
    elseif category == "TRADE" then
        return string.find(iconName, "^Trade_") ~= nil
    elseif category == "GEAR" then
        return (string.find(iconName, "^INV_Sword")
            or string.find(iconName, "^INV_Axe")
            or string.find(iconName, "^INV_Mace")
            or string.find(iconName, "^INV_Shield")
            or string.find(iconName, "^INV_Helmet")
            or string.find(iconName, "^INV_Chest")
            or string.find(iconName, "^INV_Boots")
            or string.find(iconName, "^INV_Belt")
            or string.find(iconName, "^INV_Bracer")
            or string.find(iconName, "^INV_Gauntlets")
            or string.find(iconName, "^INV_Pants")
            or string.find(iconName, "^INV_Shoulder")
            or string.find(iconName, "^INV_Staff")
            or string.find(iconName, "^INV_Wand")
            or string.find(iconName, "^INV_Jewelry")
            or string.find(iconName, "^INV_Crown")
            or string.find(iconName, "^INV_Banner")
            or string.find(iconName, "^INV_Armor")
            or string.find(iconName, "^INV_Misc_Cape")
            or string.find(iconName, "^INV_Mask")
            or string.find(iconName, "^INV_Hammer")) ~= nil
    elseif category == "ITEM" then
        if string.find(iconName, "^Spell_") or string.find(iconName, "^Ability_") or string.find(iconName, "^Trade_") then
            return false
        end
        if MatchesIconCategory(iconName, "GEAR") then
            return false
        end
        return true
    end
    return true
end

function Sheet:UpdateIconPickerGrid()
    local p = iconPickerFrame
    if not p or not p.filteredIcons then return end

    local totalItems = table.getn(p.filteredIcons)
    local totalRows = math.ceil(totalItems / GRID_COLS)

    FauxScrollFrame_Update(p.scroll, totalRows, GRID_ROWS, ROW_STEP)
    local rowOffset = FauxScrollFrame_GetOffset(p.scroll)

    for slotIdx = 1, (GRID_COLS * GRID_ROWS) do
        local btn = p.buttons[slotIdx]
        local row = math.floor((slotIdx - 1) / GRID_COLS)
        local col = math.mod(slotIdx - 1, GRID_COLS)
        local dataIdx = ((rowOffset + row) * GRID_COLS) + col + 1

        if dataIdx <= totalItems then
            local item = p.filteredIcons[dataIdx]
            btn.iconIndex = item.index
            btn.iconName = item.name
            btn.tex:SetTexture("Interface\\Icons\\" .. item.name)

            if p.selectedIconIdx and p.selectedIconIdx == item.index then
                btn.selectedGlow:Show()
                btn:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
            else
                btn.selectedGlow:Hide()
                btn:SetBackdropBorderColor(0.25, 0.25, 0.32, 1.0)
            end

            btn:Show()
        else
            btn.iconIndex = nil
            btn.iconName = nil
            btn.selectedGlow:Hide()
            btn:Hide()
        end
    end

    if totalItems == 0 then
        p.statusText:SetText("|cffff5555No matching icons found|r")
    else
        p.statusText:SetText(string.format("|cff888899Showing %d of %d icons|r", totalItems, table.getn(PUIRoleplay.Icons or {})))
    end
end

function Sheet:FilterIconPicker(searchTerm)
    local p = iconPickerFrame
    if not p then return end

    p.filteredIcons = {}
    local q = string.lower(string.gsub(searchTerm or "", "^%s*(.-)%s*$", "%1"))
    local totalIcons = table.getn(PUIRoleplay.Icons or {})

    for i = 1, totalIcons do
        local iconName = PUIRoleplay.Icons[i]
        if iconName and MatchesIconCategory(iconName, p.activeCategory) then
            if q == "" or string.find(string.lower(iconName), q, 1, true) then
                table.insert(p.filteredIcons, { index = i, name = iconName })
            end
        end
    end

    FauxScrollFrame_SetOffset(p.scroll, 0)
    local scrollbar = getglobal("Primus_PUIRoleplay_IconScrollScrollBar")
    if scrollbar then scrollbar:SetValue(0) end

    Sheet:UpdateIconPickerGrid()
end

function Sheet:OpenIconPicker(onSelectCallback, currentSelectedIdx)
    local parentFrame = Sheet:BuildFrame()
    if not iconPickerFrame then
        local p = CreateFrame("Frame", "Primus_PUIRoleplay_IconPicker", parentFrame)
        p:SetWidth(410)
        p:SetHeight(380)
        p:SetPoint("CENTER", parentFrame, "CENTER", 0, 0)
        p:SetFrameStrata("DIALOG")
        p:EnableMouse(true)
        p:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        p:SetBackdropColor(0.05, 0.05, 0.07, 0.98)
        p:SetBackdropBorderColor(0.0, 0.7, 1.0, 1.0)
        table.insert(UISpecialFrames, "Primus_PUIRoleplay_IconPicker")

        local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -10)
        title:SetText("|cff00ccffSelect Profile / Trait Icon|r")

        local close = CreateFrame("Button", nil, p)
        close:SetWidth(16)
        close:SetHeight(16)
        close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, -8)
        close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
        close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
        close:SetScript("OnClick", function() p:Hide() end)

        local filterEB = CreateFrame("EditBox", nil, p)
        filterEB:SetWidth(386)
        filterEB:SetHeight(22)
        filterEB:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -28)
        filterEB:SetAutoFocus(false)
        filterEB:SetFontObject(GameFontHighlightSmall)
        filterEB:SetTextColor(1.0, 1.0, 1.0, 1.0)
        filterEB:SetTextInsets(6, 6, 2, 2)
        filterEB:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        filterEB:SetBackdropColor(0.04, 0.04, 0.07, 0.95)
        filterEB:SetBackdropBorderColor(0.35, 0.35, 0.42, 1.0)

        filterEB:SetScript("OnTextChanged", function()
            Sheet:FilterIconPicker(this:GetText())
        end)
        filterEB:SetScript("OnEscapePressed", function()
            if this:GetText() ~= "" then
                this:SetText("")
                Sheet:FilterIconPicker("")
            else
                this:ClearFocus()
                p:Hide()
            end
        end)
        p.filterEB = filterEB

        p.categoryButtons = {}
        p.activeCategory = "ALL"

        local catBar = CreateFrame("Frame", nil, p)
        catBar:SetPoint("TOPLEFT", filterEB, "BOTTOMLEFT", 0, -5)
        catBar:SetWidth(386)
        catBar:SetHeight(20)

        local btnWidth = 61
        for cIdx, cat in ipairs(ICON_CATEGORIES) do
            local catBtn = CreateFrame("Button", nil, catBar)
            catBtn:SetWidth(btnWidth)
            catBtn:SetHeight(18)
            catBtn:SetPoint("TOPLEFT", catBar, "TOPLEFT", (cIdx - 1) * (btnWidth + 4), 0)
            catBtn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false, tileSize = 0, edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 }
            })
            catBtn:SetBackdropColor(0.07, 0.07, 0.10, 0.95)
            catBtn:SetBackdropBorderColor(0.22, 0.22, 0.28, 1.0)

            local btnText = catBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btnText:SetPoint("CENTER", catBtn, "CENTER", 0, 0)
            btnText:SetText(cat.label)
            catBtn.text = btnText
            catBtn.catId = cat.id

            catBtn:SetScript("OnClick", function()
                p.activeCategory = this.catId
                for _, b in ipairs(p.categoryButtons) do
                    if b.catId == p.activeCategory then
                        b:SetBackdropColor(0.0, 0.35, 0.55, 0.95)
                        b:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
                        b.text:SetTextColor(1.0, 1.0, 1.0, 1.0)
                    else
                        b:SetBackdropColor(0.07, 0.07, 0.10, 0.95)
                        b:SetBackdropBorderColor(0.22, 0.22, 0.28, 1.0)
                        b.text:SetTextColor(0.7, 0.7, 0.7, 1.0)
                    end
                end
                Sheet:FilterIconPicker(p.filterEB:GetText())
            end)

            table.insert(p.categoryButtons, catBtn)
        end

        local scrollBg = CreateFrame("Frame", nil, p)
        scrollBg:SetPoint("TOPLEFT", catBar, "BOTTOMLEFT", 0, -4)
        scrollBg:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -12, 28)
        scrollBg:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        scrollBg:SetBackdropColor(0.03, 0.03, 0.05, 1.0)
        scrollBg:SetBackdropBorderColor(0.2, 0.2, 0.25, 1.0)

        local scroll = CreateFrame("ScrollFrame", "Primus_PUIRoleplay_IconScroll", p, "FauxScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", scrollBg, "TOPLEFT", 4, -4)
        scroll:SetPoint("BOTTOMRIGHT", scrollBg, "BOTTOMRIGHT", -26, 4)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnVerticalScroll", function()
            FauxScrollFrame_OnVerticalScroll(ROW_STEP, function()
                Sheet:UpdateIconPickerGrid()
            end)
        end)
        scroll:SetScript("OnMouseWheel", function()
            local scrollbar = getglobal("Primus_PUIRoleplay_IconScrollScrollBar")
            if scrollbar and scrollbar:IsShown() then
                local current = scrollbar:GetValue()
                if arg1 > 0 then
                    scrollbar:SetValue(math.max(0, current - (ROW_STEP * 2)))
                else
                    local minVal, maxVal = scrollbar:GetMinMaxValues()
                    scrollbar:SetValue(math.min(maxVal, current + (ROW_STEP * 2)))
                end
            end
        end)
        p.scroll = scroll

        p.buttons = {}
        for row = 0, (GRID_ROWS - 1) do
            for col = 0, (GRID_COLS - 1) do
                local slotIdx = (row * GRID_COLS) + col + 1
                local b = CreateFrame("Button", nil, scroll)
                b:SetWidth(36)
                b:SetHeight(36)
                b:SetPoint("TOPLEFT", scroll, "TOPLEFT", col * 44 + 4, -(row * ROW_STEP + 4))
                b:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8X8",
                    edgeFile = "Interface\\Buttons\\WHITE8X8",
                    tile = false, tileSize = 0, edgeSize = 1,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 }
                })
                b:SetBackdropColor(0.04, 0.04, 0.06, 1.0)
                b:SetBackdropBorderColor(0.25, 0.25, 0.32, 1.0)

                local tex = b:CreateTexture(nil, "ARTWORK")
                tex:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
                tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                b.tex = tex

                local glow = b:CreateTexture(nil, "OVERLAY")
                glow:SetAllPoints(b)
                glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
                glow:SetBlendMode("ADD")
                glow:Hide()
                b.selectedGlow = glow

                b:SetScript("OnEnter", function()
                    if this.iconName then
                        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                        GameTooltip:ClearLines()
                        GameTooltip:AddLine("|cffffffff" .. this.iconName .. "|r", 1, 1, 1)
                        GameTooltip:AddLine(string.format("|cff00ccffWire Index: #%d|r", this.iconIndex or 0), 0.4, 0.8, 1)
                        GameTooltip:Show()
                    end
                end)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                b:SetScript("OnClick", function()
                    if this.iconIndex and p.callback then
                        p.callback(this.iconIndex)
                    end
                    p:Hide()
                end)

                table.insert(p.buttons, b)
            end
        end

        local statusText = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        statusText:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 14, 8)
        statusText:SetText("|cff888899Showing 2020 icons|r")
        p.statusText = statusText

        local selectedText = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        selectedText:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -14, 8)
        p.selectedText = selectedText

        iconPickerFrame = p
    end

    iconPickerFrame.callback = onSelectCallback
    iconPickerFrame.selectedIconIdx = currentSelectedIdx

    if currentSelectedIdx and currentSelectedIdx > 0 and PUIRoleplay.Icons and PUIRoleplay.Icons[currentSelectedIdx] then
        iconPickerFrame.selectedText:SetText(string.format("|cffffd100Selected: #%d|r", currentSelectedIdx))
    else
        iconPickerFrame.selectedText:SetText("")
    end

    iconPickerFrame.activeCategory = "ALL"
    iconPickerFrame.filterEB:SetText("")
    Sheet:FilterIconPicker("")
    iconPickerFrame:Show()
    iconPickerFrame.filterEB:SetFocus()
end
