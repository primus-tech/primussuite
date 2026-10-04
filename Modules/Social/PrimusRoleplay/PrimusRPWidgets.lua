--[[
    PrimusUI: PUIRoleplay UI Widgets & Controls (PUIRPWidgets.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (Custom Styled Form Controls)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIRoleplay = Primus.PUIRoleplay or {}
Primus.PUIRoleplay = PUIRoleplay

local Sheet = PUIRoleplay.Sheet or {}
PUIRoleplay.Sheet = Sheet

local SheetTabs = Sheet.Tabs or {}
Sheet.Tabs = SheetTabs

local openDropdownMenu = nil

--------------------------------------------------------------------------------
-- UI Component Factory Helpers
--------------------------------------------------------------------------------
function SheetTabs:Create1PxBackdrop(parent, r, g, b, a, borderR, borderG, borderB, borderA)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    frame:SetBackdropColor(r or 0.08, g or 0.08, b or 0.10, a or 0.95)
    frame:SetBackdropBorderColor(borderR or 0.25, borderG or 0.25, borderB or 0.28, borderA or 1.0)
    return frame
end

function SheetTabs:CreateStyledEditBox(parent, width, height)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetWidth(width)
    eb:SetHeight(height)
    eb:SetAutoFocus(false)
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetTextColor(1.0, 1.0, 1.0, 1.0)
    eb:SetTextInsets(6, 6, 2, 2)
    eb:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    eb:SetBackdropColor(0.04, 0.04, 0.07, 0.95)
    eb:SetBackdropBorderColor(0.35, 0.35, 0.42, 1.0)

    eb:SetScript("OnEditFocusGained", function()
        this:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
        this:SetBackdropColor(0.10, 0.10, 0.14, 1.0)
    end)
    eb:SetScript("OnEditFocusLost", function()
        this:SetBackdropBorderColor(0.35, 0.35, 0.42, 1.0)
        this:SetBackdropColor(0.04, 0.04, 0.07, 0.95)
    end)
    eb:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    return eb
end

function SheetTabs:CreateStyledCheckbox(parent, text, onClickCallback)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetWidth(18)
    cb:SetHeight(18)
    cb:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    cb:SetBackdropColor(0.04, 0.04, 0.07, 0.95)
    cb:SetBackdropBorderColor(0.35, 0.35, 0.42, 1.0)

    local checkTex = cb:CreateTexture(nil, "ARTWORK")
    checkTex:SetPoint("CENTER", cb, "CENTER", 0, 0)
    checkTex:SetWidth(14)
    checkTex:SetHeight(14)
    checkTex:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    checkTex:Hide()
    cb.checkTex = checkTex

    if text then
        local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        lbl:SetText(text)
        cb.label = lbl
    end

    cb:SetScript("OnClick", function()
        if not Sheet:IsViewingSelf() then return end
        local isChecked = not (this.isChecked == true)
        this.isChecked = isChecked
        if isChecked then
            this.checkTex:Show()
            this:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
        else
            this.checkTex:Hide()
            this:SetBackdropBorderColor(0.35, 0.35, 0.42, 1.0)
        end
        if onClickCallback then onClickCallback(isChecked) end
    end)

    function cb:SetChecked(checked)
        self.isChecked = (checked == true or checked == "1" or checked == 1)
        if self.isChecked then
            self.checkTex:Show()
            self:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
        else
            self.checkTex:Hide()
            self:SetBackdropBorderColor(0.35, 0.35, 0.42, 1.0)
        end
    end

    return cb
end

function SheetTabs:CreateStyledDropdown(parent, width, height, optionsList, onSelectCallback)
    local ddWidth = width or 180
    local ddHeight = height or 22

    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(ddWidth)
    btn:SetHeight(ddHeight)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    btn:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    btn:SetBackdropBorderColor(0.30, 0.30, 0.38, 1.0)

    local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txt:SetPoint("LEFT", btn, "LEFT", 8, 0)
    txt:SetPoint("RIGHT", btn, "RIGHT", -20, 0)
    txt:SetJustifyH("LEFT")
    txt:SetText("Select...")
    btn.text = txt

    local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    arrow:SetText("|cff00ccffv|r")
    btn.arrow = arrow

    -- Ensure global screen click-catcher exists for closing dropdown on outside click
    if not SheetTabs.dropdownCloser then
        local closer = CreateFrame("Button", "Primus_PUIRoleplay_DropdownCloser", UIParent)
        closer:SetFrameStrata("TOOLTIP")
        closer:SetAllPoints(UIParent)
        closer:EnableMouse(true)
        closer:Hide()
        closer:SetScript("OnClick", function()
            if openDropdownMenu then
                openDropdownMenu:Hide()
                openDropdownMenu = nil
            end
            this:Hide()
        end)
        SheetTabs.dropdownCloser = closer
    end

    local menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetWidth(ddWidth)
    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    menu:SetBackdropColor(0.06, 0.06, 0.09, 0.98)
    menu:SetBackdropBorderColor(0.0, 0.75, 1.0, 1.0)
    menu:Hide()
    btn.menu = menu

    btn:SetScript("OnClick", function()
        if not Sheet:IsViewingSelf() then return end
        if openDropdownMenu and openDropdownMenu == menu then
            menu:Hide()
            if SheetTabs.dropdownCloser then SheetTabs.dropdownCloser:Hide() end
            openDropdownMenu = nil
            return
        end

        if openDropdownMenu then
            openDropdownMenu:Hide()
            openDropdownMenu = nil
        end

        menu:ClearAllPoints()
        local bottom = btn:GetBottom() or 0
        local menuH = menu:GetHeight() or 100
        if bottom - menuH < 40 then
            menu:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 2)
        else
            menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
        end

        menu:SetFrameLevel(100)
        if SheetTabs.dropdownCloser then
            SheetTabs.dropdownCloser:SetFrameLevel(98)
            SheetTabs.dropdownCloser:Show()
        end

        if menu.itemButtons then
            for _, b in ipairs(menu.itemButtons) do
                b:SetFrameLevel(102)
            end
        end

        menu:Show()
        openDropdownMenu = menu
    end)

    function btn:SetOptions(opts, currentKey)
        self.options = opts or {}
        local count = 0
        for _ in pairs(self.options) do count = count + 1 end
        menu:SetHeight(math.min(260, math.max(26, count * 20 + 6)))

        if menu.itemButtons then
            for _, b in ipairs(menu.itemButtons) do b:Hide() end
        end
        menu.itemButtons = {}

        local sortedKeys = {}
        for k in pairs(self.options) do table.insert(sortedKeys, k) end
        table.sort(sortedKeys)

        local rowIdx = 0
        for _, k in ipairs(sortedKeys) do
            local valText = self.options[k]
            local itemBtn = CreateFrame("Button", nil, menu)
            itemBtn:SetWidth(ddWidth - 4)
            itemBtn:SetHeight(18)
            itemBtn:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -(rowIdx * 19 + 3))
            itemBtn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false, tileSize = 0, edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 }
            })
            itemBtn:SetBackdropColor(0.06, 0.06, 0.09, 0.0)
            itemBtn:SetBackdropBorderColor(0, 0, 0, 0)
            itemBtn:EnableMouse(true)
            itemBtn:RegisterForClicks("LeftButtonUp")

            local iTxt = itemBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            iTxt:SetPoint("LEFT", itemBtn, "LEFT", 6, 0)
            iTxt:SetPoint("RIGHT", itemBtn, "RIGHT", -6, 0)
            iTxt:SetJustifyH("LEFT")
            iTxt:SetText(valText)
            itemBtn.text = iTxt
            itemBtn.optKey = k
            itemBtn.optVal = valText

            itemBtn:SetScript("OnEnter", function()
                this:SetBackdropColor(0.0, 0.45, 0.75, 0.95)
                this:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
                this.text:SetTextColor(1.0, 1.0, 1.0)
            end)
            itemBtn:SetScript("OnLeave", function()
                this:SetBackdropColor(0.06, 0.06, 0.09, 0.0)
                this:SetBackdropBorderColor(0, 0, 0, 0)
                this.text:SetTextColor(0.85, 0.85, 0.90)
            end)
            itemBtn:SetScript("OnClick", function()
                btn.selectedKey = this.optKey
                btn.text:SetText(this.optVal)
                menu:Hide()
                if SheetTabs.dropdownCloser then SheetTabs.dropdownCloser:Hide() end
                openDropdownMenu = nil
                if onSelectCallback then onSelectCallback(this.optKey, this.optVal) end
            end)

            table.insert(menu.itemButtons, itemBtn)
            rowIdx = rowIdx + 1
        end

        if currentKey then
            self:SetSelected(currentKey)
        end
    end

    function btn:SetSelected(keyOrVal, fallbackText)
        self.selectedKey = keyOrVal
        if not self.options then
            self.text:SetText(fallbackText or tostring(keyOrVal or "Select..."))
            return
        end
        -- Direct key match
        if self.options[keyOrVal] then
            self.text:SetText(self.options[keyOrVal])
            return
        end
        -- Direct value match
        for k, v in pairs(self.options) do
            if v == keyOrVal or string.lower(tostring(v)) == string.lower(tostring(keyOrVal or "")) then
                self.selectedKey = k
                self.text:SetText(v)
                return
            end
        end
        self.text:SetText(fallbackText or tostring(keyOrVal or "Select..."))
    end

    if optionsList then
        btn:SetOptions(optionsList)
    end

    return btn
end
