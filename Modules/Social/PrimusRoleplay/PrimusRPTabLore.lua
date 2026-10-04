--[[
    PrimusUI: PUIRoleplay Profile Tab 4 - Lore & History (PUIRPTabLore.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (Lore Origins & 6-Chapter History Log)
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
-- Build Tab Panel 4: Lore & Origins
--------------------------------------------------------------------------------
function SheetTabs:BuildPanel4(parent, f)
    local p4 = CreateFrame("Frame", nil, parent)
    p4:SetAllPoints(parent)
    p4:Hide()
    f.panel4 = p4

    local bCityLabel = p4:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bCityLabel:SetPoint("TOPLEFT", p4, "TOPLEFT", 10, -8)
    bCityLabel:SetText("|cff00e5ffBirth City / Origin:|r")
    local bCityEB = self:CreateStyledEditBox(p4, 230, 20)
    bCityEB:SetPoint("TOPLEFT", bCityLabel, "BOTTOMLEFT", 0, -2)
    bCityEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.birth_city = this:GetText()
            p.keyL = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p4.bCityEB = bCityEB

    local hCityLabel = p4:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hCityLabel:SetPoint("TOPLEFT", bCityLabel, "TOPLEFT", 245, 0)
    hCityLabel:SetText("|cff00e5ffHome City / Residence:|r")
    local hCityEB = self:CreateStyledEditBox(p4, 234, 20)
    hCityEB:SetPoint("TOPLEFT", hCityLabel, "BOTTOMLEFT", 0, -2)
    hCityEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.home_city = this:GetText()
            p.keyL = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p4.hCityEB = hCityEB

    local mottoLabel = p4:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mottoLabel:SetPoint("TOPLEFT", bCityEB, "BOTTOMLEFT", 0, -6)
    mottoLabel:SetText("|cff00e5ffPersonal Motto / Creed / Battlecry:|r")
    local mottoEB = self:CreateStyledEditBox(p4, 479, 20)
    mottoEB:SetPoint("TOPLEFT", mottoLabel, "BOTTOMLEFT", 0, -2)
    mottoEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.motto = this:GetText()
            p.keyL = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p4.mottoEB = mottoEB

    local facLabel = p4:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    facLabel:SetPoint("TOPLEFT", mottoEB, "BOTTOMLEFT", 0, -6)
    facLabel:SetText("|cff00e5ffFaction / Clan / Order Allegiance:|r")
    local facEB = self:CreateStyledEditBox(p4, 479, 20)
    facEB:SetPoint("TOPLEFT", facLabel, "BOTTOMLEFT", 0, -2)
    facEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.faction_clan = this:GetText()
            p.keyL = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p4.facEB = facEB

    local histHeader = p4:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    histHeader:SetPoint("TOPLEFT", facEB, "BOTTOMLEFT", 0, -10)
    histHeader:SetText("|cffffd100CHARACTER CHRONICLES & HISTORY (6 Chapters):|r")

    local chBtns = {}
    for i = 1, 6 do
        local cBtn = CreateFrame("Button", nil, p4)
        cBtn:SetWidth(76)
        cBtn:SetHeight(20)
        cBtn:SetPoint("TOPLEFT", histHeader, "BOTTOMLEFT", (i - 1) * 80, -4)
        cBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        cBtn:SetBackdropColor(0.06, 0.06, 0.09, 0.95)
        cBtn:SetBackdropBorderColor(0.25, 0.25, 0.32, 1.0)

        local cbTxt = cBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cbTxt:SetPoint("CENTER", cBtn, "CENTER", 0, 0)
        cbTxt:SetText("Ch " .. i)
        cBtn.text = cbTxt
        cBtn.chapterIdx = i

        cBtn:SetScript("OnClick", function()
            Sheet:SelectLoreChapter(this.chapterIdx)
        end)
        chBtns[i] = cBtn
    end
    p4.chBtns = chBtns

    local chTitleLabel = p4:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chTitleLabel:SetPoint("TOPLEFT", chBtns[1], "BOTTOMLEFT", 0, -8)
    chTitleLabel:SetText("|cff00e5ffChapter 1: Early Years / Origins|r")
    p4.chTitleLabel = chTitleLabel

    local chCount = p4:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chCount:SetPoint("TOPRIGHT", p4, "TOPRIGHT", -12, -210)
    chCount:SetText("0 / 1000")
    p4.chCount = chCount

    local chScrollBg = self:Create1PxBackdrop(p4, 0.04, 0.04, 0.07, 0.95, 0.28, 0.28, 0.35, 1.0)
    chScrollBg:SetPoint("TOPLEFT", chTitleLabel, "BOTTOMLEFT", 0, -2)
    chScrollBg:SetWidth(479)
    chScrollBg:SetHeight(180)

    local chScroll = CreateFrame("ScrollFrame", "Primus_PUIRPSheet_ChScroll", p4, "UIPanelScrollFrameTemplate")
    chScroll:SetPoint("TOPLEFT", chScrollBg, "TOPLEFT", 4, -4)
    chScroll:SetPoint("BOTTOMRIGHT", chScrollBg, "BOTTOMRIGHT", -22, 4)

    local chEB = CreateFrame("EditBox", nil, chScroll)
    chEB:SetWidth(446)
    chEB:SetHeight(800)
    chEB:SetMultiLine(true)
    chEB:SetMaxLetters(1000)
    chEB:SetAutoFocus(false)
    chEB:SetFontObject(GameFontHighlightSmall)
    chEB:SetTextColor(1.0, 1.0, 1.0, 1.0)
    chEB:SetTextInsets(4, 4, 4, 4)
    chScroll:SetScrollChild(chEB)
    p4.chEB = chEB

    chScrollBg:SetScript("OnMouseDown", function() if Sheet:IsViewingSelf() then chEB:SetFocus() end end)
    chEB:SetScript("OnTextChanged", function()
        if ScrollingEdit_OnTextChanged then ScrollingEdit_OnTextChanged(chScroll) end
        local len = string.len(this:GetText() or "")
        p4.chCount:SetText(len .. " / 1000")
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            if not p.history then p.history = {} end
            p.history["chapter" .. (Sheet.activeLoreChapter or 1)] = this:GetText()
            p.keyL = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    chEB:SetScript("OnEscapePressed", function() this:ClearFocus() end)
end
