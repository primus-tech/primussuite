--[[
    PrimusLib Module: Class_Paladin (Party/Raid Blessing Matrix Engine)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Tracks party and raid member blessings, active durations, class assignments,
    expiring buff warnings (< 2 min), and Symbol of Kings reagent availability.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local _, playerClass = UnitClass("player")
if playerClass ~= "PALADIN" then return end

local PUIPaladin = Primus.PUIPaladin or {}
Primus.PUIPaladin = PUIPaladin
_G.PUIPaladin = PUIPaladin
Primus:RegisterModule("PUIPaladin", PUIPaladin, "Classes")

local DB      = Primus.DB
local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local Events  = Primus.Events
local Time    = Primus.Time
local PUIMover = Primus.PUIMover

local paladinDB = DB:RegisterNamespace("PUIPaladin", {
    enabled = true,
})

local hudFrame = nil
local rowButtons = {}

-- All Paladin Blessing Textures
local BLESSING_TEXTURES = {
    -- Greater Blessings (15 min)
    ["Spell_Holy_GreaterBlessingofKings"]     = { name = "GBOK", short = "Kings",  tex = "Spell_Magic_MageArmor" },
    ["Spell_Holy_GreaterBlessingofWisdom"]    = { name = "GBOW", short = "Wisdom", tex = "Spell_Holy_GreaterBlessingofWisdom" },
    ["Spell_Holy_GreaterBlessingofSanctuary"] = { name = "GBOSan", short = "Sanct", tex = "Spell_Holy_GreaterBlessingofSanctuary" },
    ["Spell_Holy_GreaterBlessingofSalvation"] = { name = "GBOSal", short = "Salva", tex = "Spell_Holy_GreaterBlessingofSalvation" },
    ["Spell_Holy_GreaterBlessingofLight"]     = { name = "GBOL", short = "Light",  tex = "Spell_Holy_GreaterBlessingofLight" },
    ["Spell_Holy_GreaterBlessingofKings"]     = { name = "GBOK", short = "Kings",  tex = "Spell_Magic_MageArmor" },

    -- Regular Blessings (5 min)
    ["Spell_Holy_FistOfJustice"]              = { name = "BOM",  short = "Might",  tex = "Spell_Holy_FistOfJustice" },
    ["Spell_Holy_SealOfWisdom"]               = { name = "BOW",  short = "Wisdom", tex = "Spell_Holy_SealOfWisdom" },
    ["Spell_Magic_MageArmor"]                 = { name = "BOK",  short = "Kings",  tex = "Spell_Magic_MageArmor" },
    ["Spell_Holy_BlessingOfSanctuary"]        = { name = "BOSan", short = "Sanct", tex = "Spell_Holy_BlessingOfSanctuary" },
    ["Spell_Holy_SealOfSalvation"]            = { name = "BOSal", short = "Salva", tex = "Spell_Holy_SealOfSalvation" },
    ["Spell_Holy_PrayerOfHealing02"]          = { name = "BOL",  short = "Light",  tex = "Spell_Holy_PrayerOfHealing02" },
}

local RAID_CLASSES = {
    "WARRIOR", "ROGUE", "HUNTER", "MAGE", "WARLOCK", "PRIEST", "DRUID", "PALADIN"
}

-- Count Symbol of Kings in Bags
function PUIPaladin:GetSymbolOfKingsCount()
    local count = 0
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots > 0 then
            for slot = 1, numSlots do
                local link = GetContainerItemLink(bag, slot)
                if link and string.find(link, "Symbol of Kings") then
                    local _, itemCount = GetContainerItemInfo(bag, slot)
                    count = count + (itemCount or 1)
                end
            end
        end
    end
    return count
end

-- Scan Active Blessings for a Unit
function PUIPaladin:GetUnitBlessing(unit)
    if not UnitExists(unit) then return nil end

    for i = 1, 32 do
        local texture = UnitBuff(unit, i)
        if not texture then break end

        for texKey, info in pairs(BLESSING_TEXTURES) do
            if string.find(texture, texKey) then
                return info.short, texture
            end
        end
    end
    return nil, nil
end

-- Create Row for Blessing Matrix
local function CreateMatrixRow(parent, index)
    local row = CreateFrame("Button", "Primus_PallyRow_" .. index, parent)
    row:SetWidth(170)
    row:SetHeight(20)
    row:SetBackdrop(Media:Fetch("border", "1Pixel"))
    row:SetBackdropColor(0.08, 0.08, 0.10, 0.8)
    row:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)

    -- Class / Member Label
    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    label:SetPoint("LEFT", row, "LEFT", 4, 0)
    label:SetWidth(65)
    label:SetJustifyH("LEFT")
    row.label = label

    -- Blessing Icon
    local icon = row:CreateTexture(nil, "BORDER")
    icon:SetWidth(16)
    icon:SetHeight(16)
    icon:SetPoint("LEFT", label, "RIGHT", 4, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon = icon

    -- Blessing Name & Timer Text
    local statusText = row:CreateFontString(nil, "OVERLAY")
    statusText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    statusText:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    statusText:SetTextColor(0.8, 0.8, 0.8)
    row.statusText = statusText

    rowButtons[index] = row
    return row
end

-- Update Blessing Matrix
function PUIPaladin:UpdateMatrix()
    if not hudFrame or not hudFrame:IsShown() then return end

    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    local rowCount = 0

    -- 1. Raid Mode (Grouped by Class)
    if numRaid > 0 then
        for _, className in ipairs(RAID_CLASSES) do
            local countInClass = 0
            local activeBlessing = nil
            local blessingTex = nil

            for r = 1, numRaid do
                local unit = "raid" .. r
                local _, uClass = UnitClass(unit)
                if uClass == className and UnitExists(unit) and not UnitIsDeadOrGhost(unit) then
                    countInClass = countInClass + 1
                    local bName, bTex = self:GetUnitBlessing(unit)
                    if bName then
                        activeBlessing = bName
                        blessingTex = bTex
                    end
                end
            end

            if countInClass > 0 then
                rowCount = rowCount + 1
                local row = rowButtons[rowCount] or CreateMatrixRow(hudFrame.container, rowCount)
                local r, g, b = Utils.GetClassColor(className)

                row.label:SetText(string.sub(className, 1, 4) .. string.format(" (%d)", countInClass))
                row.label:SetTextColor(r, g, b)

                if activeBlessing then
                    row.icon:SetTexture(blessingTex)
                    row.icon:Show()
                    row.statusText:SetText(activeBlessing)
                    row.statusText:SetTextColor(0.2, 1.0, 0.4) -- Green active
                    row:SetBackdropBorderColor(0.2, 0.8, 0.3, 0.8)
                else
                    row.icon:Hide()
                    row.statusText:SetText("MISSING")
                    row.statusText:SetTextColor(1.0, 0.2, 0.2) -- Red missing
                    row:SetBackdropBorderColor(0.8, 0.2, 0.2, 0.8)
                end

                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", hudFrame.container, "TOPLEFT", 0, -(rowCount - 1) * 22)
                row:Show()
            end
        end

    -- 2. Party Mode (Player + Party 1..4)
    elseif numParty > 0 then
        local units = { "player", "party1", "party2", "party3", "party4" }
        for _, unit in ipairs(units) do
            if UnitExists(unit) then
                rowCount = rowCount + 1
                local row = rowButtons[rowCount] or CreateMatrixRow(hudFrame.container, rowCount)
                local name = UnitName(unit) or unit
                local _, uClass = UnitClass(unit)
                local r, g, b = Utils.GetClassColor(uClass or "PALADIN")

                row.label:SetText(string.sub(name, 1, 7))
                row.label:SetTextColor(r, g, b)

                local bName, bTex = self:GetUnitBlessing(unit)
                if bName then
                    row.icon:SetTexture(bTex)
                    row.icon:Show()
                    row.statusText:SetText(bName)
                    row.statusText:SetTextColor(0.2, 1.0, 0.4)
                    row:SetBackdropBorderColor(0.2, 0.8, 0.3, 0.8)
                else
                    row.icon:Hide()
                    row.statusText:SetText("MISSING")
                    row.statusText:SetTextColor(1.0, 0.2, 0.2)
                    row:SetBackdropBorderColor(0.8, 0.2, 0.2, 0.8)
                end

                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", hudFrame.container, "TOPLEFT", 0, -(rowCount - 1) * 22)
                row:Show()
            end
        end

    -- 3. Solo Mode
    else
        rowCount = 1
        local row = rowButtons[1] or CreateMatrixRow(hudFrame.container, 1)
        row.label:SetText("Player")
        row.label:SetTextColor(0.96, 0.55, 0.73)

        local bName, bTex = self:GetUnitBlessing("player")
        if bName then
            row.icon:SetTexture(bTex)
            row.icon:Show()
            row.statusText:SetText(bName)
            row.statusText:SetTextColor(0.2, 1.0, 0.4)
            row:SetBackdropBorderColor(0.2, 0.8, 0.3, 0.8)
        else
            row.icon:Hide()
            row.statusText:SetText("MISSING")
            row.statusText:SetTextColor(1.0, 0.2, 0.2)
            row:SetBackdropBorderColor(0.8, 0.2, 0.2, 0.8)
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", hudFrame.container, "TOPLEFT", 0, 0)
        row:Show()
    end

    -- Hide unused rows
    for i = rowCount + 1, 10 do
        if rowButtons[i] then
            rowButtons[i]:Hide()
        end
    end

    -- Update Kings Reagent Count
    local kings = self:GetSymbolOfKingsCount()
    hudFrame.kingsText:SetText(string.format("Kings: %d", kings))
    if kings <= 5 then
        hudFrame.kingsText:SetTextColor(1.0, 0.2, 0.2)
    else
        hudFrame.kingsText:SetTextColor(1.0, 0.8, 0.2)
    end

    -- Update Bubble & Hearthstone Trackers
    self:UpdateRetreatStatus()

    -- Dynamic Panel Sizing (Matrix rows + header + footer)
    hudFrame:SetHeight(rowCount * 22 + 70)
end

-- Find Spell ID in Spellbook by Name
local function FindSpellID(spellName)
    local i = 1
    while true do
        local name = GetSpellName(i, BOOKTYPE_SPELL)
        if not name then break end
        if name == spellName then
            return i
        end
        i = i + 1
    end
    return nil
end

local PALLY_BIG_SPELLS = {
    { name = "Blessing of Protection",  short = "BoP",      tex = "Spell_Holy_SealOfProtection" },
    { name = "Divine Shield",           short = "Bubble",   tex = "Spell_Holy_DivineIntervention" },
    { name = "Divine Protection",       short = "Prot",     tex = "Spell_Holy_Restoration" },
    { name = "Blessing of Freedom",     short = "Freedom",  tex = "Spell_Holy_SealOfValor" },
    { name = "Hammer of Justice",       short = "HoJ",      tex = "Spell_Holy_SealOfMight" },
    { name = "Lay on Hands",            short = "LoH",      tex = "Spell_Holy_LayOnHands" },
    { name = "Divine Intervention",     short = "DI",       tex = "Spell_Nature_TimeStop" },
}

function PUIPaladin:GetMajorCooldowns()
    local list = {}
    for i = 1, table.getn(PALLY_BIG_SPELLS) do
        local def = PALLY_BIG_SPELLS[i]
        local spellId = FindSpellID(def.name)
        if spellId then
            local start, duration = GetSpellCooldown(spellId, BOOKTYPE_SPELL)
            local remaining = 0
            if start and start > 0 and duration and duration > 0 then
                remaining = (start + duration) - GetTime()
                if remaining < 0 then remaining = 0 end
            end
            table.insert(list, {
                name = def.name,
                short = def.short,
                tex = def.tex,
                icon = "Interface\\Icons\\" .. def.tex,
                duration = duration or 0,
                remaining = remaining,
                isReady = (remaining <= 0),
                spellId = spellId,
            })
        end
    end
    return list
end

-- Get Bubble Spell Info & Cooldown
function PUIPaladin:GetBubbleInfo()
    local spellId = FindSpellID("Divine Shield") or FindSpellID("Divine Protection")
    local spellName = spellId and (GetSpellName(spellId, BOOKTYPE_SPELL)) or "Divine Shield"
    if not spellId then
        return spellName, 0, 0, false
    end

    local start, duration = GetSpellCooldown(spellId, BOOKTYPE_SPELL)
    local cdLeft = 0
    if start and start > 0 and duration and duration > 0 then
        cdLeft = (start + duration) - GetTime()
        if cdLeft < 0 then cdLeft = 0 end
    end

    -- Check if active on player
    local isActive = false
    for i = 1, 32 do
        local tex = UnitBuff("player", i)
        if not tex then break end
        if string.find(tex, "Spell_Holy_DivineIntervention") or string.find(tex, "Spell_Holy_Restoration") then
            isActive = true
            break
        end
    end

    return spellName, cdLeft, duration or 0, isActive
end

-- Find Hearthstone in Bags & Get Cooldown
function PUIPaladin:GetHearthstoneInfo()
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots > 0 then
            for slot = 1, numSlots do
                local link = GetContainerItemLink(bag, slot)
                if link and string.find(link, "Hearthstone") then
                    local start, duration = GetContainerItemCooldown(bag, slot)
                    local cdLeft = 0
                    if start and start > 0 and duration and duration > 0 then
                        cdLeft = (start + duration) - GetTime()
                        if cdLeft < 0 then cdLeft = 0 end
                    end
                    return bag, slot, cdLeft, duration or 0
                end
            end
        end
    end
    return nil, nil, 0, 0
end

-- Update Bubble / Hearthstone HUD Status
function PUIPaladin:UpdateRetreatStatus()
    if not hudFrame or not hudFrame.retreatBar or not hudFrame.panicBtn or not hudFrame.bubbleBtn or not hudFrame.hearthBtn then return end

    local bubbleName, bubbleCD, _, bubbleActive = self:GetBubbleInfo()
    local hsBag, hsSlot, hsCD = self:GetHearthstoneInfo()

    -- 1. Bubble Indicator
    if bubbleActive then
        hudFrame.bubbleBtn.text:SetText("ACTIVE")
        hudFrame.bubbleBtn.text:SetTextColor(0.2, 1.0, 0.4)
        hudFrame.bubbleBtn:SetBackdropBorderColor(0.2, 1.0, 0.4, 1)
    elseif bubbleCD > 0 then
        hudFrame.bubbleBtn.text:SetText(Time:FormatShort(bubbleCD))
        hudFrame.bubbleBtn.text:SetTextColor(1.0, 0.3, 0.3)
        hudFrame.bubbleBtn:SetBackdropBorderColor(0.6, 0.2, 0.2, 0.8)
    else
        hudFrame.bubbleBtn.text:SetText("READY")
        hudFrame.bubbleBtn.text:SetTextColor(1.0, 0.9, 0.3)
        hudFrame.bubbleBtn:SetBackdropBorderColor(0.8, 0.7, 0.2, 1)
    end

    -- 2. Hearthstone Indicator
    if not hsBag then
        hudFrame.hearthBtn.text:SetText("NO HS")
        hudFrame.hearthBtn.text:SetTextColor(0.5, 0.5, 0.5)
        hudFrame.hearthBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    elseif hsCD > 0 then
        hudFrame.hearthBtn.text:SetText(Time:FormatShort(hsCD))
        hudFrame.hearthBtn.text:SetTextColor(1.0, 0.3, 0.3)
        hudFrame.hearthBtn:SetBackdropBorderColor(0.6, 0.2, 0.2, 0.8)
    else
        hudFrame.hearthBtn.text:SetText("READY")
        hudFrame.hearthBtn.text:SetTextColor(0.2, 0.8, 1.0)
        hudFrame.hearthBtn:SetBackdropBorderColor(0.2, 0.6, 0.9, 1)
    end

    -- 3. Bubble-Hearth Button Status
    local canBubbleHearth = (bubbleCD == 0 or bubbleActive) and (hsBag ~= nil and hsCD == 0)
    if canBubbleHearth then
        hudFrame.panicBtn:SetBackdropBorderColor(1.0, 0.84, 0.0, 1)
        hudFrame.panicBtn.text:SetTextColor(1.0, 0.9, 0.1)
    else
        hudFrame.panicBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
        hudFrame.panicBtn.text:SetTextColor(0.6, 0.6, 0.6)
    end
end

function PUIPaladin:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIPaladin", {
        name = "Class_Paladin",
        category = "Classes",
        label = "Paladin Nuances",
        options = {
            {
                key = "enabled",
                type = "checkbox",
                label = "Enable Blessing Suite",
                desc = "Show Party/Raid blessing matrix, Kings counter, and Bubble-Hearth emergency trigger.",
                default = true,
                get = function() return paladinDB:Get("enabled") end,
                set = function(v)
                    paladinDB:Set("enabled", v)
                    if v then hudFrame:Show() else hudFrame:Hide() end
                end,
            },
        },
    })
end

function PUIPaladin:OnInitialize()
    -- Create Paladin Blessing Monitor Panel
    hudFrame = CreateFrame("Frame", "Primus_PaladinHUD", UIParent)
    hudFrame:SetWidth(180)
    hudFrame:SetHeight(160)
    hudFrame:SetPoint("LEFT", UIParent, "LEFT", 20, 0)
    hudFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
    hudFrame:SetBackdropColor(0.06, 0.06, 0.08, 0.9)
    hudFrame:SetBackdropBorderColor(0.96, 0.55, 0.73, 1)

    -- Header Title
    local title = hudFrame:CreateFontString(nil, "OVERLAY")
    title:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    title:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 6, -6)
    title:SetText(Utils.ColorText("Blessings", "f58cba"))
    hudFrame.title = title

    -- Kings Reagent Counter Text
    local kingsText = hudFrame:CreateFontString(nil, "OVERLAY")
    kingsText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    kingsText:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -6, -7)
    kingsText:SetText("Kings: 0")
    hudFrame.kingsText = kingsText

    -- Container for matrix rows
    local container = CreateFrame("Frame", nil, hudFrame)
    container:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 5, -24)
    container:SetPoint("BOTTOMRIGHT", hudFrame, "BOTTOMRIGHT", -5, 34)
    hudFrame.container = container

    for i = 1, 10 do
        local row = CreateMatrixRow(container, i)
        row:Hide()
    end

    -- Tactical Retreat / Bubble Hearth Bar (Footer)
    local retreatBar = CreateFrame("Frame", "Primus_PallyRetreat", hudFrame)
    retreatBar:SetPoint("BOTTOMLEFT", hudFrame, "BOTTOMLEFT", 4, 4)
    retreatBar:SetPoint("BOTTOMRIGHT", hudFrame, "BOTTOMRIGHT", -4, 4)
    retreatBar:SetHeight(26)
    hudFrame.retreatBar = retreatBar

    -- Bubble Indicator Button
    local bubbleBtn = CreateFrame("Button", "Primus_PallyBubbleBtn", retreatBar)
    bubbleBtn:SetWidth(42)
    bubbleBtn:SetHeight(22)
    bubbleBtn:SetPoint("LEFT", retreatBar, "LEFT", 0, 0)
    bubbleBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    bubbleBtn:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
    bubbleBtn:SetBackdropBorderColor(0.8, 0.7, 0.2, 1)

    local bText = bubbleBtn:CreateFontString(nil, "OVERLAY")
    bText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    bText:SetPoint("CENTER", bubbleBtn, "CENTER", 0, 0)
    bText:SetText("BUBBLE")
    bubbleBtn.text = bText

    bubbleBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        local name, cdLeft, _, active = PUIPaladin:GetBubbleInfo()
        GameTooltip:SetText("|cfff58cba" .. name .. "|r")
        if active then
            GameTooltip:AddLine("|cff33ff33ACTIVE ON PLAYER|r")
        elseif cdLeft > 0 then
            GameTooltip:AddLine(string.format("|cffff3333Cooldown: %.1fs|r", cdLeft))
        else
            GameTooltip:AddLine("|cff33ff33READY|r")
        end
        GameTooltip:Show()
    end)
    bubbleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hudFrame.bubbleBtn = bubbleBtn

    -- Hearthstone Indicator Button
    local hearthBtn = CreateFrame("Button", "Primus_PallyHearthBtn", retreatBar)
    hearthBtn:SetWidth(42)
    hearthBtn:SetHeight(22)
    hearthBtn:SetPoint("LEFT", bubbleBtn, "RIGHT", 3, 0)
    hearthBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    hearthBtn:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
    hearthBtn:SetBackdropBorderColor(0.2, 0.6, 0.9, 1)

    local hText = hearthBtn:CreateFontString(nil, "OVERLAY")
    hText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    hText:SetPoint("CENTER", hearthBtn, "CENTER", 0, 0)
    hText:SetText("HEARTH")
    hearthBtn.text = hText

    hearthBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        local bag, slot, cdLeft = PUIPaladin:GetHearthstoneInfo()
        GameTooltip:SetText("|cff33ccffHearthstone|r")
        if not bag then
            GameTooltip:AddLine("|cff888888No Hearthstone found in bags!|r")
        elseif cdLeft > 0 then
            GameTooltip:AddLine(string.format("|cffff3333Cooldown: %.1fs|r", cdLeft))
        else
            GameTooltip:AddLine("|cff33ff33READY|r")
        end
        GameTooltip:Show()
    end)
    hearthBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hudFrame.hearthBtn = hearthBtn

    -- Tongue-in-Cheek "Bubble Hearth" Panic Button
    local panicBtn = CreateFrame("Button", "Primus_PallyPanicBtn", retreatBar)
    panicBtn:SetWidth(78)
    panicBtn:SetHeight(22)
    panicBtn:SetPoint("LEFT", hearthBtn, "RIGHT", 3, 0)
    panicBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    panicBtn:SetBackdropColor(0.15, 0.12, 0.05, 0.9)
    panicBtn:SetBackdropBorderColor(1.0, 0.84, 0.0, 1)

    local pText = panicBtn:CreateFontString(nil, "OVERLAY")
    pText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    pText:SetPoint("CENTER", panicBtn, "CENTER", 0, 0)
    pText:SetText("BUBBLE HEARTH")
    panicBtn.text = pText

    panicBtn:SetScript("OnClick", function()
        local name, cdLeft, _, active = PUIPaladin:GetBubbleInfo()
        local hsBag, hsSlot = PUIPaladin:GetHearthstoneInfo()

        -- 1. Pop Bubble if not already active and available
        if not active and cdLeft == 0 then
            CastSpellByName(name)
        end

        -- 2. Channel Hearthstone
        if hsBag and hsSlot then
            UseContainerItem(hsBag, hsSlot)
        end
    end)

    panicBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("|cffffd100Tactical Retreat (Bubble Hearth)|r")
        GameTooltip:AddLine("|cffaaaaaaThe classic Paladin emergency protocol.|r", 1, 1, 1, 1)
        GameTooltip:AddLine(" ")

        local name, cdLeft, _, active = PUIPaladin:GetBubbleInfo()
        local hsBag, hsSlot, hsCD = PUIPaladin:GetHearthstoneInfo()

        if active then
            GameTooltip:AddDoubleLine("Bubble:", "|cff33ff33ACTIVE|r")
        elseif cdLeft == 0 then
            GameTooltip:AddDoubleLine("Bubble:", "|cff33ff33READY|r")
        else
            GameTooltip:AddDoubleLine("Bubble:", string.format("|cffff3333%.0fs|r", cdLeft))
        end

        if not hsBag then
            GameTooltip:AddDoubleLine("Hearthstone:", "|cff888888Missing|r")
        elseif hsCD == 0 then
            GameTooltip:AddDoubleLine("Hearthstone:", "|cff33ff33READY|r")
        else
            GameTooltip:AddDoubleLine("Hearthstone:", string.format("|cffff3333%.0fs|r", hsCD))
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffaa00Click to cast Bubble & channel Hearthstone!|r")
        GameTooltip:Show()
    end)
    panicBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hudFrame.panicBtn = panicBtn

    local mover = PUIMover or Primus.PUIMover
    if mover and mover.Register then
        mover:Register(hudFrame, "PaladinHUD", "Paladin Blessing Matrix", "CLASS")
    end

    self:RegisterOptionsFlare()
end

function PUIPaladin:OnEnable()
    if hudFrame and paladinDB:Get("enabled") then
        hudFrame:Show()
    end

    -- Events
    Events:Register("PARTY_MEMBERS_CHANGED", self, function()
        PUIPaladin:UpdateMatrix()
    end)
    Events:Register("RAID_ROSTER_UPDATE", self, function()
        PUIPaladin:UpdateMatrix()
    end)
    Events:Register("UNIT_AURA", self, function()
        PUIPaladin:UpdateMatrix()
    end)
    Events:Register("BAG_UPDATE", self, function()
        PUIPaladin:UpdateMatrix()
    end)

    -- 1s Ticker for Matrix & Cooldown Refresh
    Time:Every(1.0, function()
        PUIPaladin:UpdateMatrix()
    end, self)

    self:UpdateMatrix()
end

function PUIPaladin:OnDisable()
    Time:CancelAll(self)
    Events:UnregisterOwner(self)
    if hudFrame then hudFrame:Hide() end
end


