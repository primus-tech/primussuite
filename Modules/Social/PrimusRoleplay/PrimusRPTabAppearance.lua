--[[
    PrimusUI: PUIRoleplay Profile Tab 2 - Appearance & Glances (PUIRPTabAppearance.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (Physical Description & 5 At-A-Glance Slots)
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

--------------------------------------------------------------------------------
-- Build Tab Panel 2: Physical Traits & At-A-Glance Cards
--------------------------------------------------------------------------------
function SheetTabs:BuildPanel2(parent, f)
    local p2 = CreateFrame("Frame", nil, parent)
    p2:SetAllPoints(parent)
    p2:Hide()
    f.panel2 = p2

    local eyeLabel = p2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    eyeLabel:SetPoint("TOPLEFT", p2, "TOPLEFT", 10, -8)
    eyeLabel:SetText("|cff00e5ffEye Color:|r")
    local eyeEB = self:CreateStyledEditBox(p2, 112, 20)
    eyeEB:SetPoint("TOPLEFT", eyeLabel, "BOTTOMLEFT", 0, -2)
    eyeEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.eye_color = this:GetText()
            p.keyD = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p2.eyeEB = eyeEB

    local hLabel = p2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hLabel:SetPoint("TOPLEFT", p2, "TOPLEFT", 130, -8)
    hLabel:SetText("|cff00e5ffHeight:|r")
    local hEB = self:CreateStyledEditBox(p2, 112, 20)
    hEB:SetPoint("TOPLEFT", hLabel, "BOTTOMLEFT", 0, -2)
    hEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.height = this:GetText()
            p.keyD = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p2.hEB = hEB

    local wLabel = p2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wLabel:SetPoint("TOPLEFT", p2, "TOPLEFT", 250, -8)
    wLabel:SetText("|cff00e5ffWeight:|r")
    local wEB = self:CreateStyledEditBox(p2, 112, 20)
    wEB:SetPoint("TOPLEFT", wLabel, "BOTTOMLEFT", 0, -2)
    wEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.weight = this:GetText()
            p.keyD = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p2.wEB = wEB

    local bLabel = p2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bLabel:SetPoint("TOPLEFT", p2, "TOPLEFT", 370, -8)
    bLabel:SetText("|cff00e5ffBody Build:|r")
    local bEB = self:CreateStyledEditBox(p2, 118, 20)
    bEB:SetPoint("TOPLEFT", bLabel, "BOTTOMLEFT", 0, -2)
    bEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.body_build = this:GetText()
            p.keyD = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p2.bEB = bEB

    local emoLabel = p2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    emoLabel:SetPoint("TOPLEFT", eyeEB, "BOTTOMLEFT", 0, -6)
    emoLabel:SetText("|cff00e5ffCurrent Emotion / Expression:|r")
    local emoEB = self:CreateStyledEditBox(p2, 478, 20)
    emoEB:SetPoint("TOPLEFT", emoLabel, "BOTTOMLEFT", 0, -2)
    emoEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.current_emotion = this:GetText()
            p.keyD = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p2.emoEB = emoEB

    local descLabel = p2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descLabel:SetPoint("TOPLEFT", emoEB, "BOTTOMLEFT", 0, -6)
    descLabel:SetText("|cff55ff88Physical Appearance Description:|r")

    local descCount = p2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    descCount:SetPoint("TOPRIGHT", p2, "TOPRIGHT", -12, -74)
    descCount:SetText("0 / 1000")
    p2.descCount = descCount

    local descScrollBg = self:Create1PxBackdrop(p2, 0.04, 0.04, 0.07, 0.95, 0.28, 0.28, 0.35, 1.0)
    descScrollBg:SetPoint("TOPLEFT", descLabel, "BOTTOMLEFT", 0, -2)
    descScrollBg:SetWidth(478)
    descScrollBg:SetHeight(75)

    local descScroll = CreateFrame("ScrollFrame", "Primus_PUIRPSheet_DescScroll", p2, "UIPanelScrollFrameTemplate")
    descScroll:SetPoint("TOPLEFT", descScrollBg, "TOPLEFT", 4, -4)
    descScroll:SetPoint("BOTTOMRIGHT", descScrollBg, "BOTTOMRIGHT", -22, 4)

    local descEB = CreateFrame("EditBox", nil, descScroll)
    descEB:SetWidth(446)
    descEB:SetHeight(500)
    descEB:SetMultiLine(true)
    descEB:SetMaxLetters(1000)
    descEB:SetAutoFocus(false)
    descEB:SetFontObject(GameFontHighlightSmall)
    descEB:SetTextColor(1.0, 1.0, 1.0, 1.0)
    descEB:SetTextInsets(4, 4, 4, 4)
    descScroll:SetScrollChild(descEB)
    p2.descEB = descEB

    descScrollBg:SetScript("OnMouseDown", function() if Sheet:IsViewingSelf() then descEB:SetFocus() end end)
    descEB:SetScript("OnTextChanged", function()
        if ScrollingEdit_OnTextChanged then ScrollingEdit_OnTextChanged(descScroll) end
        local len = string.len(this:GetText() or "")
        p2.descCount:SetText(len .. " / 1000")
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.appearance_desc = this:GetText()
            p.keyD = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    descEB:SetScript("OnEscapePressed", function() this:ClearFocus() end)

    local glanceHeader = p2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    glanceHeader:SetPoint("TOPLEFT", descScrollBg, "BOTTOMLEFT", 0, -8)
    glanceHeader:SetText("|cffffd100AT A GLANCE TRAITS (5 Visual Cards):|r")

    p2.glanceCards = {}
    for i = 1, 5 do
        local card = self:Create1PxBackdrop(p2, 0.05, 0.05, 0.07, 0.95, 0.22, 0.24, 0.28, 1.0)
        card:SetWidth(478)
        card:SetHeight(44)
        card:SetPoint("TOPLEFT", glanceHeader, "BOTTOMLEFT", 0, -4 - (i - 1) * 48)

        local gBtn = CreateFrame("Button", nil, card)
        gBtn:SetWidth(32)
        gBtn:SetHeight(32)
        gBtn:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -6)
        gBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        gBtn:SetBackdropColor(0, 0, 0, 1)
        gBtn:SetBackdropBorderColor(0.4, 0.4, 0.5, 1)

        local gTex = gBtn:CreateTexture(nil, "ARTWORK")
        gTex:SetPoint("TOPLEFT", gBtn, "TOPLEFT", 1, -1)
        gTex:SetPoint("BOTTOMRIGHT", gBtn, "BOTTOMRIGHT", -1, 1)
        gTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        gBtn.tex = gTex
        gBtn.cardIndex = i

        gBtn:SetScript("OnClick", function()
            if Sheet:IsViewingSelf() then
                local idx = this.cardIndex
                Sheet:OpenIconPicker(function(selectedIconIndex)
                    local p = PUIRoleplay:GetMyProfile()
                    if not p.glances then p.glances = {} end
                    if not p.glances[idx] then p.glances[idx] = {} end
                    local iconName = PUIRoleplay.Icons[selectedIconIndex] or "INV_Misc_QuestionMark"
                    p.glances[idx].icon = iconName
                    p["atAGlance" .. idx .. "Icon"] = tostring(selectedIconIndex)
                    p.keyT = PUIRoleplay:GenerateKey()
                    PUIRoleplay:SaveMyProfile(p)
                    Sheet:Refresh()
                end)
            end
        end)
        card.iconBtn = gBtn

        local gTitleEB = self:CreateStyledEditBox(card, 340, 16)
        gTitleEB:SetPoint("TOPLEFT", gBtn, "TOPRIGHT", 8, 0)
        gTitleEB:SetTextColor(1.0, 0.90, 0.30, 1.0)
        gTitleEB.cardIndex = i
        gTitleEB:SetScript("OnTextChanged", function()
            if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
                local p = PUIRoleplay:GetMyProfile()
                if not p.glances then p.glances = {} end
                if not p.glances[this.cardIndex] then p.glances[this.cardIndex] = {} end
                p.glances[this.cardIndex].title = this:GetText()
                p["atAGlance" .. this.cardIndex .. "Title"] = this:GetText()
                p.keyT = PUIRoleplay:GenerateKey()
                PUIRoleplay:SaveMyProfile(p)
            end
        end)
        card.titleEB = gTitleEB

        local gDescEB = self:CreateStyledEditBox(card, 340, 16)
        gDescEB:SetPoint("TOPLEFT", gTitleEB, "BOTTOMLEFT", 0, -2)
        gDescEB:SetTextColor(1.0, 1.0, 1.0, 1.0)
        gDescEB.cardIndex = i
        gDescEB:SetScript("OnTextChanged", function()
            if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
                local p = PUIRoleplay:GetMyProfile()
                if not p.glances then p.glances = {} end
                if not p.glances[this.cardIndex] then p.glances[this.cardIndex] = {} end
                p.glances[this.cardIndex].text = this:GetText()
                p["atAGlance" .. this.cardIndex] = this:GetText()
                p.keyT = PUIRoleplay:GenerateKey()
                PUIRoleplay:SaveMyProfile(p)
            end
        end)
        card.descEB = gDescEB

        local activeCB = self:CreateStyledCheckbox(card, "Active", function(checked)
            local p = PUIRoleplay:GetMyProfile()
            if not p.glances then p.glances = {} end
            if not p.glances[i] then p.glances[i] = {} end
            p.glances[i].active = checked
            p.keyT = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end)
        activeCB:SetPoint("RIGHT", card, "RIGHT", -60, 0)
        card.activeCB = activeCB

        p2.glanceCards[i] = card
    end
end
