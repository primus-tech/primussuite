--[[
    PrimusUI: PUIRoleplay Profile Tab 6 - Matchmaking & 18+ ERP (PUIRPTabMatchmaking.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (Relationship, Seeking Badges, 18+ Adult RP & Boundaries)
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
-- Build Tab Panel 6: Matchmaking, Dating & 18+ Adult RP
--------------------------------------------------------------------------------
function SheetTabs:BuildPanel6(parent, f)
    local p6 = CreateFrame("Frame", nil, parent)
    p6:SetAllPoints(parent)
    p6:Hide()
    f.panel6 = p6

    local relLabel = p6:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    relLabel:SetPoint("TOPLEFT", p6, "TOPLEFT", 10, -8)
    relLabel:SetText("|cff00e5ffIC Relationship Status:|r")
    local relDropdown = self:CreateStyledDropdown(p6, 230, 22, PUIRoleplay.DropdownOptions.relationship or {}, function(optKey, optVal)
        local p = PUIRoleplay:GetMyProfile()
        p.relationship_status = optVal
        p.keyX = PUIRoleplay:GenerateKey()
        PUIRoleplay:SaveMyProfile(p)
    end)
    relDropdown:SetPoint("TOPLEFT", relLabel, "BOTTOMLEFT", 0, -2)
    p6.relDropdown = relDropdown

    local lfLabel = p6:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lfLabel:SetPoint("TOPLEFT", relDropdown, "BOTTOMLEFT", 0, -10)
    lfLabel:SetText("|cffffd100Looking For / Open To (Directory Badges):|r")

    local lookingForList = {
        { key = "adventure", label = "|cff00ff88[Adventure & Quests]|r" },
        { key = "romance", label = "|cffff80cc[Romance & Dating]|r" },
        { key = "casual_tavern", label = "|cffffcc00[Casual Tavern RP]|r" },
        { key = "combat", label = "|cffff4444[Combat & Sparring]|r" },
        { key = "political_guild", label = "|cff00ccff[Guild & Politics]|r" },
        { key = "mentorship", label = "|cffb080ff[Mentorship / Student]|r" }
    }

    p6.lfCheckboxes = {}
    for idx, item in ipairs(lookingForList) do
        local col = math.mod(idx - 1, 2)
        local row = math.floor((idx - 1) / 2)
        local cb = self:CreateStyledCheckbox(p6, item.label, function(checked)
            local p = PUIRoleplay:GetMyProfile()
            if not p.looking_for then p.looking_for = {} end
            p.looking_for[item.key] = checked
            p.keyX = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end)
        cb:SetPoint("TOPLEFT", lfLabel, "BOTTOMLEFT", col * 240, -4 - row * 22)
        p6.lfCheckboxes[item.key] = cb
    end

    local adultCard = self:Create1PxBackdrop(p6, 0.08, 0.04, 0.05, 0.95, 0.50, 0.18, 0.22, 1.0)
    adultCard:SetWidth(478)
    adultCard:SetHeight(160)
    adultCard:SetPoint("TOPLEFT", lfLabel, "BOTTOMLEFT", 0, -80)

    local adultTitle = adultCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    adultTitle:SetPoint("TOPLEFT", adultCard, "TOPLEFT", 8, -6)
    adultTitle:SetText("|cffff335518+ ADULT-ORIENTED RP & ERP BOUNDARIES:|r")

    local adultFlagCB = self:CreateStyledCheckbox(adultCard, "|cffff4466[18+] Explicit Adult-Oriented Roleplay Profile|r", function(checked)
        local p = PUIRoleplay:GetMyProfile()
        p.adult_18plus_flag = checked
        if not p.looking_for then p.looking_for = {} end
        p.looking_for.adult_18plus = checked
        p.keyX = PUIRoleplay:GenerateKey()
        PUIRoleplay:SaveMyProfile(p)
    end)
    adultFlagCB:SetPoint("TOPLEFT", adultTitle, "BOTTOMLEFT", 0, -4)
    p6.adultFlagCB = adultFlagCB

    local erpLabel = adultCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    erpLabel:SetPoint("TOPLEFT", adultFlagCB, "BOTTOMLEFT", 0, -6)
    erpLabel:SetText("|cff00e5ffERP Preference & Tone:|r")

    local erpDropdown = self:CreateStyledDropdown(adultCard, 460, 20, PUIRoleplay.DropdownOptions.erp or {}, function(optKey, optVal)
        local p = PUIRoleplay:GetMyProfile()
        p.erp_preference = optVal
        p.keyX = PUIRoleplay:GenerateKey()
        PUIRoleplay:SaveMyProfile(p)
    end)
    erpDropdown:SetPoint("TOPLEFT", erpLabel, "BOTTOMLEFT", 0, -2)
    p6.erpDropdown = erpDropdown

    local bndLabel = adultCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bndLabel:SetPoint("TOPLEFT", erpDropdown, "BOTTOMLEFT", 0, -6)
    bndLabel:SetText("|cffffaa44OOC Safety, Triggers & Comfort Boundaries:|r")

    local bndEB = self:CreateStyledEditBox(adultCard, 460, 20)
    bndEB:SetPoint("TOPLEFT", bndLabel, "BOTTOMLEFT", 0, -2)
    bndEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.ooc_boundaries = this:GetText()
            p.keyX = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p6.bndEB = bndEB
end
