--[[
    PrimusLib Module: PUIUnitBase (Atomic Unit Frame Primitive)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides the core template and dynamic updater for all UnitFrames:
    Health & Power bars, smooth animations, HealComm prediction, Aura grids,
    classification tags, and Mover integration.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIUnitBase = Primus.PUIUnitBase or {}
Primus.PUIUnitBase = PUIUnitBase
_G.PUIUnitBase = PUIUnitBase
Primus:RegisterModule("PUIUnitBase", PUIUnitBase, "Units")

local Widgets  = Primus.Widgets
local Media    = Primus.Media
local Utils    = Primus.Utils
local Events   = Primus.Events
local PUIMover = Primus.PUIMover
local HealComm = Primus.PUIHealComm
local DB       = Primus.DB

local unitFrameCounter = 0
local activeUnitFrames = {}

-- =========================================================================
-- CLASS-CURATED CLICK-CASTING DEFAULTS & FALLBACKS
-- =========================================================================

local CLASS_CLICK_DEFAULTS = {
    ["PRIEST"] = {
        ["shift-LeftButton"]  = { spell = "Dispel Magic", fallbacks = {} },
        ["shift-RightButton"] = { spell = "Power Word: Shield", fallbacks = {} },
        ["ctrl-LeftButton"]   = { spell = "Flash Heal", fallbacks = { "Lesser Heal", "Heal" } },
        ["ctrl-RightButton"]  = { spell = "Greater Heal", fallbacks = { "Heal", "Lesser Heal" } },
        ["alt-LeftButton"]    = { spell = "Renew", fallbacks = {} },
    },
    ["DRUID"] = {
        ["shift-LeftButton"]  = { spell = "Rejuvenation", fallbacks = {} },
        ["shift-RightButton"] = { spell = "Healing Touch", fallbacks = {} },
        ["ctrl-LeftButton"]   = { spell = "Remove Curse", fallbacks = {} },
        ["ctrl-RightButton"]  = { spell = "Abolish Poison", fallbacks = { "Cure Poison" } },
        ["alt-LeftButton"]    = { spell = "Regrowth", fallbacks = {} },
    },
    ["PALADIN"] = {
        ["shift-LeftButton"]  = { spell = "Flash of Light", fallbacks = { "Holy Light" } },
        ["shift-RightButton"] = { spell = "Holy Light", fallbacks = {} },
        ["ctrl-LeftButton"]   = { spell = "Cleanse", fallbacks = { "Purify" } },
        ["ctrl-RightButton"]  = { spell = "Blessing of Protection", fallbacks = {} },
    },
    ["SHAMAN"] = {
        ["shift-LeftButton"]  = { spell = "Lesser Healing Wave", fallbacks = { "Healing Wave" } },
        ["shift-RightButton"] = { spell = "Healing Wave", fallbacks = {} },
        ["ctrl-LeftButton"]   = { spell = "Cure Poison", fallbacks = {} },
        ["ctrl-RightButton"]  = { spell = "Cure Disease", fallbacks = {} },
        ["alt-LeftButton"]    = { spell = "Chain Heal", fallbacks = { "Healing Wave" } },
    },
    ["MAGE"] = {
        ["ctrl-LeftButton"]   = { spell = "Remove Lesser Curse", fallbacks = {} },
        ["alt-LeftButton"]    = { spell = "Arcane Intellect", fallbacks = {} },
    },
    ["WARLOCK"] = {
        ["ctrl-LeftButton"]   = { spell = "Unending Breath", fallbacks = {} },
    },
}

local DEBUFF_COLORS = {
    ["Curse"]   = { r = 0.60, g = 0.00, b = 1.00 },
    ["Magic"]   = { r = 0.20, g = 0.60, b = 1.00 },
    ["Poison"]  = { r = 0.00, g = 0.60, b = 0.00 },
    ["Disease"] = { r = 0.60, g = 0.40, b = 0.00 },
}

local CLASS_DEBUFF_PRIORITY = {
    ["PRIEST"]  = { "Magic", "Disease", "Curse", "Poison" },
    ["PALADIN"] = { "Magic", "Poison", "Disease", "Curse" },
    ["DRUID"]   = { "Curse", "Poison", "Magic", "Disease" },
    ["MAGE"]    = { "Curse", "Magic", "Poison", "Disease" },
    ["SHAMAN"]  = { "Poison", "Disease", "Magic", "Curse" },
}

-- =========================================================================
-- CLICK-CAST HANDLER
-- =========================================================================

function PUIUnitBase:HandleUnitClick(unit, button)
    if not unit or not UnitExists(unit) then return end

    local isShift = IsShiftKeyDown()
    local isCtrl  = IsControlKeyDown()
    local isAlt   = IsAltKeyDown()

    local modStr = ""
    if isShift then modStr = modStr .. "shift-" end
    if isCtrl then modStr = modStr .. "ctrl-" end
    if isAlt then modStr = modStr .. "alt-" end

    local comboKey = modStr .. (button or "LeftButton")

    -- Check click-casting if any modifier is active or if bound
    if modStr ~= "" then
        local _, playerClass = UnitClass("player")
        playerClass = playerClass or "WARRIOR"

        local classDefs = CLASS_CLICK_DEFAULTS[playerClass]
        local binding = classDefs and classDefs[comboKey]

        if binding then
            local spellToCast = nil
            if Utils.IsSpellKnown(binding.spell) then
                spellToCast = binding.spell
            elseif binding.fallbacks then
                local fCount = table.getn(binding.fallbacks)
                for f = 1, fCount do
                    local fb = binding.fallbacks[f]
                    if Utils.IsSpellKnown(fb) then
                        spellToCast = fb
                        break
                    end
                end
            end

            if spellToCast then
                Utils.CastOnUnit(unit, spellToCast)
                return
            end
        end
    end

    -- Default Click Targeting / Context Menus
    if button == "LeftButton" then
        TargetUnit(unit)
    elseif button == "RightButton" then
        if unit == "player" and PlayerFrameDropDown then
            ToggleDropDownMenu(1, nil, PlayerFrameDropDown, "cursor", 0, 0)
        elseif unit == "target" and TargetFrameDropDown then
            ToggleDropDownMenu(1, nil, TargetFrameDropDown, "cursor", 0, 0)
        elseif string.sub(unit, 1, 5) == "party" then
            local idx = string.sub(unit, 6, 6)
            local pMenu = _G["PartyMemberFrame" .. idx .. "DropDown"]
            if pMenu then
                ToggleDropDownMenu(1, nil, pMenu, "cursor", 0, 0)
            end
        end
    end
end

-- =========================================================================
-- UNIT FRAME FACTORY
-- =========================================================================

function PUIUnitBase:CreateUnitFrame(parent, unit, width, height, customName)
    parent = parent or UIParent
    unit   = unit or "player"
    width  = width or 180
    height = height or 38
    unitFrameCounter = unitFrameCounter + 1

    local frameName = customName or string.format("Primus_UnitFrame_%s_%d", unit, unitFrameCounter)
    local f = CreateFrame("Button", frameName, parent)
    f:SetWidth(width)
    f:SetHeight(height)
    f:SetPoint("CENTER", 0, 0)
    f:SetBackdrop(Media:Fetch("border", "1Pixel"))
    f:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    f:SetBackdropBorderColor(0.20, 0.20, 0.25, 1.0)
    f:EnableMouse(true)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp", "Button4Up", "Button5Up")
    f.unit = unit

    -- Universal Click-Casting Dispatcher
    f:SetScript("OnClick", function()
        PUIUnitBase:HandleUnitClick(f.unit, arg1)
    end)

    -- Health Bar
    local health = Widgets:CreateStatusBar(f, width - 4, height - 16, 0, 100)
    health:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    health:SetStatusBarColor(0.20, 0.80, 0.20, 1.0)
    f.healthBar = health

    -- Heal Prediction Bar (Incoming Heals)
    local healPred = CreateFrame("StatusBar", nil, health)
    healPred:SetAllPoints(health)
    healPred:SetStatusBarTexture(Media:Fetch("statusbar", "Default"))
    healPred:SetStatusBarColor(0.20, 1.00, 0.40, 0.60)
    healPred:SetMinMaxValues(0, 100)
    healPred:SetValue(0)
    healPred:SetFrameLevel(health:GetFrameLevel() - 1)
    f.healPredBar = healPred

    -- Power Bar (Mana / Rage / Energy)
    local power = Widgets:CreateStatusBar(f, width - 4, 10, 0, 100)
    power:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -2)
    power:SetStatusBarColor(0.20, 0.40, 1.00, 1.0)
    f.powerBar = power

    -- Unit Name & Level Text
    local nameText = health:CreateFontString(nil, "OVERLAY")
    nameText:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    nameText:SetPoint("LEFT", health, "LEFT", 4, 0)
    f.nameText = nameText

    -- Health Value Text
    local hpText = health:CreateFontString(nil, "OVERLAY")
    hpText:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    hpText:SetPoint("RIGHT", health, "RIGHT", -4, 0)
    f.hpText = hpText

    -- Pet Happiness Icon (for Pet Frame)
    if unit == "pet" then
        local hap = CreateFrame("Button", nil, f)
        hap:SetWidth(16)
        hap:SetHeight(16)
        hap:SetPoint("RIGHT", f, "LEFT", -4, 0)
        
        local hTex = hap:CreateTexture(nil, "ARTWORK")
        hTex:SetAllPoints(hap)
        hTex:SetTexture("Interface\\PetPaperDollFrame\\UI-PetHappiness")
        hap.tex = hTex
        
        hap:SetScript("OnEnter", function()
            local happiness, damagePercentage, loyaltyRate = GetPetHappiness()
            if not happiness then return end
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            local hapNames = { "Unhappy (75% Damage)", "Content (100% Damage)", "Happy (125% Damage)" }
            local hapColors = { {1.0, 0.2, 0.2}, {1.0, 0.8, 0.2}, {0.2, 1.0, 0.4} }
            local col = hapColors[happiness] or {1, 1, 1}
            GameTooltip:AddLine(hapNames[happiness] or "Pet Happiness", col[1], col[2], col[3])
            if damagePercentage then
                GameTooltip:AddLine(string.format("Damage: %d%%", damagePercentage), 0.9, 0.9, 0.9)
            end
            if loyaltyRate and loyaltyRate > 0 then
                GameTooltip:AddLine("Gaining Loyalty", 0.2, 1.0, 0.4)
            elseif loyaltyRate and loyaltyRate < 0 then
                GameTooltip:AddLine("Losing Loyalty", 1.0, 0.2, 0.2)
            end
            GameTooltip:Show()
        end)
        hap:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        f.happinessIcon = hap
    end

    -- Real-time Updater
    function f:Update()
        if not UnitExists(self.unit) then
            self:Hide()
            return
        end
        self:Show()

        local u = self.unit
        local curHP, maxHP, pctHP, isEstimated = Utils.GetUnitHealth(u)
        local curPwr = UnitMana(u) or 0
        local maxPwr = UnitManaMax(u) or 1
        local pwrType = UnitPowerType(u) or 0

        -- Health & Text
        self.healthBar:SetMinMaxValues(0, maxHP)
        self.healthBar:SetSmoothValue(curHP)
        if isEstimated or UnitIsPlayer(u) or maxHP > 100 then
            self.hpText:SetText(string.format("%d / %d", curHP, maxHP))
        else
            self.hpText:SetText(string.format("%d%%", pctHP))
        end

        -- Name & Classification
        local name = UnitName(u) or ""
        local level = UnitLevel(u) or 0
        local class = UnitClassification(u)
        local tag = ""
        if class == "elite" or class == "worldboss" then tag = "+"
        elseif class == "rare" or class == "rareelite" then tag = "r" end
        self.nameText:SetText(string.format("[%d%s] %s", level, tag, name))

        -- Power Bar
        self.powerBar:SetMinMaxValues(0, maxPwr)
        self.powerBar:SetSmoothValue(curPwr)

        if pwrType == 1 then
            self.powerBar:SetStatusBarColor(0.90, 0.20, 0.20, 1.0) -- Rage Red
        elseif pwrType == 3 then
            self.powerBar:SetStatusBarColor(1.00, 0.90, 0.20, 1.0) -- Energy Yellow
        else
            self.powerBar:SetStatusBarColor(0.20, 0.40, 1.00, 1.0) -- Mana Blue
        end

        -- Class / Reaction Color for Health
        if UnitIsPlayer(u) then
            local _, cls = UnitClass(u)
            local r, g, b = Utils.GetClassColor(cls)
            self.healthBar:SetStatusBarColor(r, g, b, 1.0)
        else
            if UnitIsEnemy("player", u) then
                self.healthBar:SetStatusBarColor(0.80, 0.20, 0.20, 1.0)
            elseif UnitIsFriend("player", u) then
                self.healthBar:SetStatusBarColor(0.20, 0.80, 0.20, 1.0)
            else
                self.healthBar:SetStatusBarColor(0.80, 0.80, 0.20, 1.0)
            end
        end

        -- Class-Aware Debuff Highlight Border Engine via Central Primus.Auras
        local foundDebuffType = nil
        local _, playerClass = UnitClass("player")
        playerClass = playerClass or "WARRIOR"
        local priorityList = CLASS_DEBUFF_PRIORITY[playerClass] or { "Magic", "Curse", "Poison", "Disease" }

        local CoreAuras = Primus.Auras
        local unitAuras = CoreAuras and CoreAuras:GetUnitAuras(u)
        if unitAuras and unitAuras.totalDebuffs and unitAuras.totalDebuffs > 0 then
            local activeDebuffs = {}
            for d = 1, unitAuras.totalDebuffs do
                local deb = unitAuras.debuffs[d]
                if deb and deb.dispelType and deb.dispelType ~= "None" and deb.dispelType ~= "none" then
                    activeDebuffs[deb.dispelType] = true
                end
            end

            -- Pick highest priority debuff based on class
            local pCount = table.getn(priorityList)
            for p = 1, pCount do
                local dType = priorityList[p]
                if activeDebuffs[dType] then
                    foundDebuffType = dType
                    break
                end
            end
        end

        if foundDebuffType and DEBUFF_COLORS[foundDebuffType] then
            local dc = DEBUFF_COLORS[foundDebuffType]
            self:SetBackdropBorderColor(dc.r, dc.g, dc.b, 1.0)
        else
            self:SetBackdropBorderColor(0.20, 0.20, 0.25, 1.0)
        end

        -- Heal Prediction Sync
        if HealComm then
            local incoming = HealComm:GetIncomingHeal(name)
            if incoming > 0 and maxHP > 0 then
                local predHP = math.min(maxHP, curHP + incoming)
                self.healPredBar:SetMinMaxValues(0, maxHP)
                self.healPredBar:SetValue(predHP)
                self.healPredBar:Show()
            else
                self.healPredBar:Hide()
            end
        end

        -- Pet Happiness Icon Update
        if self.happinessIcon then
            if UnitExists(self.unit) and UnitExists("pet") then
                local happiness = GetPetHappiness()
                if happiness == 1 then
                    self.happinessIcon.tex:SetTexCoord(0.375, 0.5625, 0, 0.359375) -- Red frown
                    self.happinessIcon:Show()
                elseif happiness == 2 then
                    self.happinessIcon.tex:SetTexCoord(0.1875, 0.375, 0, 0.359375) -- Yellow neutral
                    self.happinessIcon:Show()
                elseif happiness == 3 then
                    self.happinessIcon.tex:SetTexCoord(0, 0.1875, 0, 0.359375) -- Green smile
                    self.happinessIcon:Show()
                else
                    self.happinessIcon:Hide()
                end
            else
                self.happinessIcon:Hide()
            end
        end
    end

    -- Register with PUIMover
    local mover = PUIMover or Primus.PUIMover
    if mover and mover.Register then
        mover:Register(f, frameName, string.format("Unit Frame: %s", unit), "UNITS")
    end

    table.insert(activeUnitFrames, f)
    return f
end

-- =========================================================================
-- INITIALIZATION & EVENT HOOKS
-- =========================================================================

function PUIUnitBase:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIUnitBase", {
        name = "PUIUnitBase",
        category = "Units",
        label = "Unit Frame Core",
        icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02",
        desc = "Underlying status bar engine and health/mana math for all unit frames.",
    })
end

function PUIUnitBase:OnInitialize()
    self:RegisterOptionsFlare()
    local unitEvents = {
        "UNIT_HEALTH",
        "UNIT_MAXHEALTH",
        "UNIT_MANA",
        "UNIT_MAXMANA",
        "UNIT_RAGE",
        "UNIT_ENERGY",
        "UNIT_HAPPINESS",
        "PET_UI_UPDATE",
        "UNIT_PET",
        "PET_BAR_UPDATE",
        "PLAYER_TARGET_CHANGED",
        "PARTY_MEMBERS_CHANGED",
        "RAID_ROSTER_UPDATE",
        "PLAYER_ENTERING_WORLD",
        "SPELLS_CHANGED",
    }

    local count = table.getn(unitEvents)
    for i = 1, count do
        Events:Register(unitEvents[i], self, function()
            local frameCount = table.getn(activeUnitFrames)
            for j = 1, frameCount do
                activeUnitFrames[j]:Update()
            end
        end)
    end

    Events:Listen("HEAL_PREDICTION_UPDATED", self, function(owner, targetName)
        local frameCount = table.getn(activeUnitFrames)
        for j = 1, frameCount do
            if UnitName(activeUnitFrames[j].unit) == targetName then
                activeUnitFrames[j]:Update()
            end
        end
    end)
end
