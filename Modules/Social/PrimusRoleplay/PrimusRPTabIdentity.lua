--[[
    PrimusUI: PUIRoleplay Profile Tab 1 - Identity & Demographics (PUIRPTabIdentity.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (Nomenclature, Pronouns, LGBTQIA+, Orientation)
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
-- Build Tab Panel 1: Identity & Demographics
--------------------------------------------------------------------------------
function SheetTabs:BuildPanel1(parent, f)
    local p1 = CreateFrame("Frame", nil, parent)
    p1:SetAllPoints(parent)
    f.panel1 = p1

    -- Row 1: First Name & Middle Name
    local fnLabel = p1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fnLabel:SetPoint("TOPLEFT", p1, "TOPLEFT", 10, -8)
    fnLabel:SetText("|cff00e5ffFirst Name:|r")
    local fnEB = self:CreateStyledEditBox(p1, 230, 20)
    fnEB:SetPoint("TOPLEFT", fnLabel, "BOTTOMLEFT", 0, -2)
    fnEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.first_name = this:GetText()
            p.full_name = PUIRoleplay:ComposeFullName(p)
            p.keyM = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p1.fnEB = fnEB

    local mnLabel = p1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mnLabel:SetPoint("TOPLEFT", fnLabel, "TOPLEFT", 245, 0)
    mnLabel:SetText("|cff00e5ffMiddle Name:|r")
    local mnEB = self:CreateStyledEditBox(p1, 234, 20)
    mnEB:SetPoint("TOPLEFT", mnLabel, "BOTTOMLEFT", 0, -2)
    mnEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.middle_name = this:GetText()
            p.full_name = PUIRoleplay:ComposeFullName(p)
            p.keyM = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p1.mnEB = mnEB

    -- Row 2: Last Name & Nickname / Alias
    local lnLabel = p1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lnLabel:SetPoint("TOPLEFT", fnEB, "BOTTOMLEFT", 0, -6)
    lnLabel:SetText("|cff00e5ffLast Name / Surname:|r")
    local lnEB = self:CreateStyledEditBox(p1, 230, 20)
    lnEB:SetPoint("TOPLEFT", lnLabel, "BOTTOMLEFT", 0, -2)
    lnEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.last_name = this:GetText()
            p.full_name = PUIRoleplay:ComposeFullName(p)
            p.keyM = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p1.lnEB = lnEB

    local nickLabel = p1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nickLabel:SetPoint("TOPLEFT", lnLabel, "TOPLEFT", 245, 0)
    nickLabel:SetText("|cff00e5ffNickname / Alias:|r")
    local nickEB = self:CreateStyledEditBox(p1, 234, 20)
    nickEB:SetPoint("TOPLEFT", nickLabel, "BOTTOMLEFT", 0, -2)
    nickEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.nickname = this:GetText()
            p.keyM = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p1.nickEB = nickEB

    -- Row 3: Prefix & Title / Office / Role
    local pfxLabel = p1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pfxLabel:SetPoint("TOPLEFT", lnEB, "BOTTOMLEFT", 0, -6)
    pfxLabel:SetText("|cff00e5ffPrefix (e.g. Sir, Lady, Captain):|r")
    local pfxEB = self:CreateStyledEditBox(p1, 230, 20)
    pfxEB:SetPoint("TOPLEFT", pfxLabel, "BOTTOMLEFT", 0, -2)
    pfxEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.prefix = this:GetText()
            p.keyM = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p1.pfxEB = pfxEB

    local ttlLabel = p1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ttlLabel:SetPoint("TOPLEFT", pfxLabel, "TOPLEFT", 245, 0)
    ttlLabel:SetText("|cff00e5ffTitle / Office (e.g. Archmage, Knight):|r")
    local ttlEB = self:CreateStyledEditBox(p1, 234, 20)
    ttlEB:SetPoint("TOPLEFT", ttlLabel, "BOTTOMLEFT", 0, -2)
    ttlEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.title = this:GetText()
            p.keyM = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p1.ttlEB = ttlEB

    -- Row 4: Suffix / Epithet & House / Bloodline / Tribe / Clan
    local epLabel = p1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    epLabel:SetPoint("TOPLEFT", pfxEB, "BOTTOMLEFT", 0, -6)
    epLabel:SetText("|cff00e5ffSuffix / Epithet (e.g. the Dragonslayer):|r")
    local epEB = self:CreateStyledEditBox(p1, 230, 20)
    epEB:SetPoint("TOPLEFT", epLabel, "BOTTOMLEFT", 0, -2)
    epEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.epithet = this:GetText()
            p.suffix = this:GetText()
            p.keyM = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p1.epEB = epEB

    local houseLabel = p1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    houseLabel:SetPoint("TOPLEFT", epLabel, "TOPLEFT", 245, 0)
    houseLabel:SetText("|cff00e5ffHouse / Bloodline / Tribe / Clan:|r")
    local houseEB = self:CreateStyledEditBox(p1, 234, 20)
    houseEB:SetPoint("TOPLEFT", houseLabel, "BOTTOMLEFT", 0, -2)
    houseEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.house_name = this:GetText()
            p.bloodline = this:GetText()
            p.tribe = this:GetText()
            p.clan = this:GetText()
            p.keyM = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p1.houseEB = houseEB

    -- Demographics Header Divider
    local demoHeader = p1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    demoHeader:SetPoint("TOPLEFT", epEB, "BOTTOMLEFT", 0, -10)
    demoHeader:SetText("|cffffd100DEMOGRAPHICS, SEX, GENDER & PRONOUNS:|r")

    -- Row 5: Apparent Age, Biological Sex, Gender Identity, IC Pronouns
    local ageLabel = p1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ageLabel:SetPoint("TOPLEFT", demoHeader, "BOTTOMLEFT", 0, -4)
    ageLabel:SetText("|cff00e5ffApparent Age:|r")
    local ageEB = self:CreateStyledEditBox(p1, 75, 20)
    ageEB:SetPoint("TOPLEFT", ageLabel, "BOTTOMLEFT", 0, -2)
    ageEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.apparent_age = this:GetText()
            p.keyM = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p1.ageEB = ageEB

    local sexLabel = p1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sexLabel:SetPoint("TOPLEFT", ageLabel, "TOPLEFT", 85, 0)
    sexLabel:SetText("|cff00e5ffBiological Sex:|r")
    local sexDropdown = self:CreateStyledDropdown(p1, 125, 22, PUIRoleplay.DropdownOptions.sex or {}, function(optKey, optVal)
        local p = PUIRoleplay:GetMyProfile()
        p.biological_sex = optVal
        p.keyM = PUIRoleplay:GenerateKey()
        PUIRoleplay:SaveMyProfile(p)
    end)
    sexDropdown:SetPoint("TOPLEFT", sexLabel, "BOTTOMLEFT", 0, -2)
    p1.sexDropdown = sexDropdown

    local genderLabel = p1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    genderLabel:SetPoint("TOPLEFT", sexLabel, "TOPLEFT", 135, 0)
    genderLabel:SetText("|cff00e5ffGender Identity:|r")
    local genderDropdown = self:CreateStyledDropdown(p1, 150, 22, PUIRoleplay.DropdownOptions.gender or {}, function(optKey, optVal)
        local p = PUIRoleplay:GetMyProfile()
        p.gender_identity = optVal
        p.keyM = PUIRoleplay:GenerateKey()
        PUIRoleplay:SaveMyProfile(p)
    end)
    genderDropdown:SetPoint("TOPLEFT", genderLabel, "BOTTOMLEFT", 0, -2)
    p1.genderDropdown = genderDropdown

    local icPrLabel = p1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    icPrLabel:SetPoint("TOPLEFT", genderLabel, "TOPLEFT", 160, 0)
    icPrLabel:SetText("|cff00e5ffIC Pronouns:|r")
    local icPrEB = self:CreateStyledEditBox(p1, 95, 20)
    icPrEB:SetPoint("TOPLEFT", icPrLabel, "BOTTOMLEFT", 0, -2)
    icPrEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.ic_pronouns = this:GetText()
            p.keyM = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p1.icPrEB = icPrEB

    -- Row 6: OOC Pronouns, Orientation, Show Orientation
    local oocPrLabel = p1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    oocPrLabel:SetPoint("TOPLEFT", ageEB, "BOTTOMLEFT", 0, -6)
    oocPrLabel:SetText("|cff00e5ffOOC Pronouns (Player):|r")
    local oocPrEB = self:CreateStyledEditBox(p1, 135, 20)
    oocPrEB:SetPoint("TOPLEFT", oocPrLabel, "BOTTOMLEFT", 0, -2)
    oocPrEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.ooc_pronouns = this:GetText()
            p.keyM = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p1.oocPrEB = oocPrEB

    local oriLabel = p1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    oriLabel:SetPoint("TOPLEFT", oocPrLabel, "TOPLEFT", 145, 0)
    oriLabel:SetText("|cff00e5ffOrientation / Attraction Preference:|r")
    local oriDropdown = self:CreateStyledDropdown(p1, 200, 22, PUIRoleplay.DropdownOptions.orientation or {}, function(optKey, optVal)
        local p = PUIRoleplay:GetMyProfile()
        p.orientation = optVal
        p.keyM = PUIRoleplay:GenerateKey()
        PUIRoleplay:SaveMyProfile(p)
    end)
    oriDropdown:SetPoint("TOPLEFT", oriLabel, "BOTTOMLEFT", 0, -2)
    p1.oriDropdown = oriDropdown

    local showOriBox = self:CreateStyledCheckbox(p1, "Show on Public Card", function(checked)
        local p = PUIRoleplay:GetMyProfile()
        p.show_orientation = checked
        p.keyM = PUIRoleplay:GenerateKey()
        PUIRoleplay:SaveMyProfile(p)
    end)
    showOriBox:SetPoint("LEFT", oriDropdown, "RIGHT", 8, 0)
    p1.showOriBox = showOriBox

    -- Row 7: LGBTQIA+ Safe Space Friendly Checkbox
    local lgbtqBox = self:CreateStyledCheckbox(p1, "|cffff0000[|cffff7f00LGBTQIA+|cff9400d3 Friendly / Ally Safe Space]|r", function(checked)
        local p = PUIRoleplay:GetMyProfile()
        p.lgbtqia_friendly = checked
        p.keyM = PUIRoleplay:GenerateKey()
        PUIRoleplay:SaveMyProfile(p)
    end)
    lgbtqBox:SetPoint("TOPLEFT", oocPrEB, "BOTTOMLEFT", 0, -10)
    p1.lgbtqBox = lgbtqBox
end
