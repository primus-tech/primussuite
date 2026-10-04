--[[
    PrimusLib Module: Class_Rogue (Energy Ticker, Combo Points, Pickpocket & Auto-Lockpick Suite)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Tracks:
    1. Exact 2.0-second server Energy tick bar & real-time Energy.
    2. 5 visual Combo Point indicators with finisher alerts.
    3. Stealth Pickpocket assistant for Humanoid / Undead targets.
    4. Smart Bag Lockbox Scanner with 1-click Lockpicking action.
    5. Main-hand & Off-hand Poison charges and expiration monitors.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local _, playerClass = UnitClass("player")
if playerClass ~= "ROGUE" then return end

local PUIRogue = Primus.PUIRogue or {}
Primus.PUIRogue = PUIRogue
_G.PUIRogue = PUIRogue
Primus:RegisterModule("PUIRogue", PUIRogue, "Classes")

local DB      = Primus.DB
local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local Events  = Primus.Events
local Time    = Primus.Time
local PUIMover = Primus.PUIMover

local rogueDB = DB:RegisterNamespace("PUIRogue", {
    enabled = true,
})

local hudFrame = nil
local energyBar = nil
local cpPips = {}

local lastEnergy = 0
local lastTickTime = 0

local ROGUE_BIG_SPELLS = {
    { name = "Vanish",          short = "Vanish",  tex = "Ability_Vanish" },
    { name = "Blind",           short = "Blind",   tex = "Spell_Shadow_MindSteal" },
    { name = "Evasion",         short = "Evasion", tex = "Spell_Shadow_ShadowWard" },
    { name = "Sprint",          short = "Sprint",  tex = "Ability_Rogue_Sprint" },
    { name = "Preparation",     short = "Prep",    tex = "Spell_Shadow_AntiShadow" },
    { name = "Adrenaline Rush", short = "ARush",   tex = "Spell_Shadow_ShadowWordDominate" },
    { name = "Blade Flurry",    short = "Flurry",  tex = "Ability_Warrior_PunishingBlow" },
    { name = "Kick",            short = "Kick",    tex = "Ability_Kick" },
}

local knownSpells = {}

function PUIRogue:ScanSpellbook()
    knownSpells = {}
    local i = 1
    local numBig = table.getn(ROGUE_BIG_SPELLS)
    while true do
        local spellName = GetSpellName(i, BOOKTYPE_SPELL)
        if not spellName then break end
        local texture = GetSpellTexture(i, BOOKTYPE_SPELL)
        for idx = 1, numBig do
            local bigSpell = ROGUE_BIG_SPELLS[idx]
            if string.find(spellName, bigSpell.name) or (texture and string.find(texture, bigSpell.tex)) then
                if not knownSpells[bigSpell.name] then
                    knownSpells[bigSpell.name] = {
                        spellID = i,
                        name    = bigSpell.name,
                        texture = texture,
                        short   = bigSpell.short,
                        tex     = bigSpell.tex,
                    }
                end
            end
        end
        i = i + 1
    end
end

function PUIRogue:GetMajorCooldowns()
    local list = {}
    local numBig = table.getn(ROGUE_BIG_SPELLS)
    for idx = 1, numBig do
        local def = ROGUE_BIG_SPELLS[idx]
        local info = knownSpells[def.name]
        if info then
            local start, duration = GetSpellCooldown(info.spellID, BOOKTYPE_SPELL)
            local remaining = 0
            if start and start > 0 and duration and duration > 0 then
                remaining = (start + duration) - GetTime()
                if remaining < 0 then remaining = 0 end
            end
            table.insert(list, {
                name = def.name,
                short = def.short,
                tex = def.tex,
                icon = info.texture or ("Interface\\Icons\\" .. def.tex),
                duration = duration or 0,
                remaining = remaining,
                isReady = (remaining <= 0),
                spellId = info.spellID,
            })
        end
    end
    return list
end

-- Hidden Tooltip for Lockbox Scanning
local scanTooltip = CreateFrame("GameTooltip", "Primus_RogueScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")

-- Check if Bag Item is a Locked Box
local function IsItemLocked(bag, slot)
    scanTooltip:ClearLines()
    scanTooltip:SetBagItem(bag, slot)
    for i = 1, scanTooltip:NumLines() do
        local line = _G["Primus_RogueScanTooltipTextLeft" .. i]
        if line and line:GetText() then
            local text = line:GetText()
            if string.find(text, "Locked") then
                return true
            end
        end
    end
    return false
end

-- Find Locked Box in Inventory
function PUIRogue:FindLockedBox()
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots > 0 then
            for slot = 1, numSlots do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    if IsItemLocked(bag, slot) then
                        local itemName = Utils.ExtractItemName and Utils.ExtractItemName(link) or link
                        local texture, count = GetContainerItemInfo(bag, slot)
                        return bag, slot, itemName, texture, count or 1
                    end
                end
            end
        end
    end
    return nil, nil, nil, nil, 0
end

-- Check if Player is in Stealth
function PUIRogue:IsStealthed()
    for i = 1, 32 do
        local tex = UnitBuff("player", i)
        if not tex then break end
        if string.find(tex, "Ability_Stealth") then
            return true
        end
    end
    return false
end

-- Update Rogue Suite HUD
function PUIRogue:UpdateHUD()
    if not hudFrame or not hudFrame:IsShown() then return end

    -- 1. Combo Points (1 to 5)
    local cp = GetComboPoints("player", "target") or 0
    for i = 1, 5 do
        local pip = cpPips[i]
        if pip then
            if i <= cp then
                pip:Show()
                if cp == 5 then
                    pip:SetBackdropColor(1.0, 0.2, 0.2, 1.0) -- Red 5-CP finisher ready
                    pip:SetBackdropBorderColor(1.0, 0.4, 0.4, 1.0)
                else
                    pip:SetBackdropColor(1.0, 0.85, 0.1, 1.0) -- Yellow CP
                    pip:SetBackdropBorderColor(1.0, 0.95, 0.3, 1.0)
                end
            else
                pip:Hide()
            end
        end
    end

    -- 2. Poison Monitor (MH & OH)
    local hasMH, mhExp, mhCharges, hasOH, ohExp, ohCharges = GetWeaponEnchantInfo()
    if hasMH then
        local mins = math.floor(mhExp / 60000)
        hudFrame.mhPoison:SetText(string.format("MH: %d (%dm)", mhCharges or 0, mins))
        hudFrame.mhPoison:SetTextColor(0.2, 1.0, 0.4)
    else
        hudFrame.mhPoison:SetText("MH: MISSING")
        hudFrame.mhPoison:SetTextColor(1.0, 0.3, 0.3)
    end

    if hasOH then
        local mins = math.floor(ohExp / 60000)
        hudFrame.ohPoison:SetText(string.format("OH: %d (%dm)", ohCharges or 0, mins))
        hudFrame.ohPoison:SetTextColor(0.2, 1.0, 0.4)
    else
        hudFrame.ohPoison:SetText("OH: MISSING")
        hudFrame.ohPoison:SetTextColor(1.0, 0.3, 0.3)
    end

    -- 3. Pickpocket Helper
    if self:IsStealthed() and UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then
        local creatureType = UnitCreatureType("target")
        if creatureType == "Humanoid" or creatureType == "Undead" then
            hudFrame.pickpocketBtn:Show()
        else
            hudFrame.pickpocketBtn:Hide()
        end
    else
        hudFrame.pickpocketBtn:Hide()
    end

    -- 4. Smart Lockbox Assistant
    local lBag, lSlot, lName, lTex, lCount = self:FindLockedBox()
    if lBag and lSlot then
        hudFrame.lockpickBtn.bag = lBag
        hudFrame.lockpickBtn.slot = lSlot
        hudFrame.lockpickBtn.text:SetText(string.format("Pick: %s", string.sub(lName or "Box", 1, 10)))
        hudFrame.lockpickBtn:Show()
    else
        hudFrame.lockpickBtn:Hide()
    end
end

function PUIRogue:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIRogue", {
        name = "Class_Rogue",
        category = "Classes",
        label = "Rogue Nuances",
        options = {
            {
                key = "enabled",
                type = "checkbox",
                label = "Enable Rogue Suite",
                desc = "Show 2.0s Energy ticker, Combo points, Poison timers, and Pickpocket/Lockpick buttons.",
                default = true,
                get = function() return rogueDB:Get("enabled") end,
                set = function(v)
                    rogueDB:Set("enabled", v)
                    if v then hudFrame:Show() else hudFrame:Hide() end
                end,
            },
        },
    })
end

function PUIRogue:OnInitialize()
    -- Create Rogue HUD Frame
    hudFrame = CreateFrame("Frame", "Primus_RogueHUD", UIParent)
    hudFrame:SetWidth(260)
    hudFrame:SetHeight(82)
    hudFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 180)
    hudFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
    hudFrame:SetBackdropColor(0.08, 0.08, 0.06, 0.9)
    hudFrame:SetBackdropBorderColor(1.0, 0.96, 0.41, 1) -- Rogue Yellow

    -- Header Title
    local title = hudFrame:CreateFontString(nil, "OVERLAY")
    title:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    title:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 6, -6)
    title:SetText(Utils.ColorText("Rogue Suite", "fff569"))
    hudFrame.title = title

    -- Combo Points Container
    local cpContainer = CreateFrame("Frame", nil, hudFrame)
    cpContainer:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -6, -6)
    cpContainer:SetWidth(100)
    cpContainer:SetHeight(12)
    hudFrame.cpContainer = cpContainer

    for i = 1, 5 do
        local pip = CreateFrame("Frame", "Primus_RogueCP_" .. i, cpContainer)
        pip:SetWidth(16)
        pip:SetHeight(10)
        pip:SetPoint("LEFT", cpContainer, "LEFT", (i - 1) * 19, 0)
        pip:SetBackdrop(Media:Fetch("border", "1Pixel"))
        pip:SetBackdropColor(1.0, 0.85, 0.1, 1.0)
        pip:SetBackdropBorderColor(1.0, 0.95, 0.3, 1.0)
        pip:Hide()
        cpPips[i] = pip
    end

    -- 2.0s Energy Ticker Bar
    energyBar = Widgets:CreateStatusBar(hudFrame, 248, 14, 0, 2.0)
    energyBar:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 6, -22)
    energyBar:SetStatusBarColor(1.0, 0.9, 0.2, 1.0)
    energyBar.text:SetText("Energy: 100")
    hudFrame.energyBar = energyBar

    -- Poison Status Text (MH & OH)
    local mhPoison = hudFrame:CreateFontString(nil, "OVERLAY")
    mhPoison:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    mhPoison:SetPoint("TOPLEFT", energyBar, "BOTTOMLEFT", 0, -4)
    mhPoison:SetText("MH: MISSING")
    hudFrame.mhPoison = mhPoison

    local ohPoison = hudFrame:CreateFontString(nil, "OVERLAY")
    ohPoison:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    ohPoison:SetPoint("LEFT", mhPoison, "RIGHT", 12, 0)
    ohPoison:SetText("OH: MISSING")
    hudFrame.ohPoison = ohPoison

    -- 1-Click Pickpocket Button
    local pickpocketBtn = CreateFrame("Button", "Primus_PickpocketBtn", hudFrame)
    pickpocketBtn:SetWidth(118)
    pickpocketBtn:SetHeight(20)
    pickpocketBtn:SetPoint("BOTTOMLEFT", hudFrame, "BOTTOMLEFT", 6, 4)
    pickpocketBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    pickpocketBtn:SetBackdropColor(0.12, 0.15, 0.2, 0.9)
    pickpocketBtn:SetBackdropBorderColor(0.3, 0.6, 1.0, 1)

    local ppText = pickpocketBtn:CreateFontString(nil, "OVERLAY")
    ppText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    ppText:SetPoint("CENTER", pickpocketBtn, "CENTER", 0, 0)
    ppText:SetTextColor(0.4, 0.8, 1.0)
    ppText:SetText("PICKPOCKET")
    pickpocketBtn.text = ppText

    pickpocketBtn:SetScript("OnClick", function()
        CastSpellByName("Pick Pocket")
    end)
    pickpocketBtn:Hide()
    hudFrame.pickpocketBtn = pickpocketBtn

    -- 1-Click Auto-Lockpick Button
    local lockpickBtn = CreateFrame("Button", "Primus_AutoLockpickBtn", hudFrame)
    lockpickBtn:SetWidth(122)
    lockpickBtn:SetHeight(20)
    lockpickBtn:SetPoint("BOTTOMRIGHT", hudFrame, "BOTTOMRIGHT", -6, 4)
    lockpickBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    lockpickBtn:SetBackdropColor(0.18, 0.14, 0.06, 0.9)
    lockpickBtn:SetBackdropBorderColor(1.0, 0.8, 0.2, 1)

    local lpText = lockpickBtn:CreateFontString(nil, "OVERLAY")
    lpText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    lpText:SetPoint("CENTER", lockpickBtn, "CENTER", 0, 0)
    lpText:SetTextColor(1.0, 0.9, 0.3)
    lpText:SetText("PICK LOCK")
    lockpickBtn.text = lpText

    lockpickBtn:SetScript("OnClick", function()
        if this.bag and this.slot then
            CastSpellByName("Pick Lock")
            UseContainerItem(this.bag, this.slot)
        end
    end)
    lockpickBtn:Hide()
    local mover = PUIMover or Primus.PUIMover
    if mover and mover.Register then
        mover:Register(hudFrame, "RogueHUD", "Rogue Suite (Energy, Combo & Lockpick)", "CLASS")
    end

    self:RegisterOptionsFlare()
end

function PUIRogue:OnEnable()
    if hudFrame and rogueDB:Get("enabled") then
        hudFrame:Show()
    end

    -- Energy Tick Detection
    Events:Register("UNIT_ENERGY", self, function(owner, event, unit)
        if unit ~= "player" then return end
        local cur = UnitMana("player")
        if cur > lastEnergy then
            lastTickTime = GetTime()
        end
        lastEnergy = cur
        PUIRogue:UpdateHUD()
    end)

    -- Spellbook & Cooldown Events
    self:ScanSpellbook()
    Events:Register("SPELLS_CHANGED", self, function() PUIRogue:ScanSpellbook() PUIRogue:UpdateHUD() end)
    Events:Register("LEARNED_SPELL_IN_TAB", self, function() PUIRogue:ScanSpellbook() PUIRogue:UpdateHUD() end)
    Events:Register("SPELL_UPDATE_COOLDOWN", self, function() PUIRogue:UpdateHUD() end)
    Events:Register("PLAYER_ENTERING_WORLD", self, function() PUIRogue:ScanSpellbook() PUIRogue:UpdateHUD() end)

    -- Events
    Events:Register("PLAYER_TARGET_CHANGED", self, function() PUIRogue:UpdateHUD() end)
    Events:Register("PLAYER_COMBO_POINTS", self, function() PUIRogue:UpdateHUD() end)
    Events:Register("PLAYER_AURAS_CHANGED", self, function() PUIRogue:UpdateHUD() end)
    Events:Register("BAG_UPDATE", self, function() PUIRogue:UpdateHUD() end)
    Events:Register("UNIT_INVENTORY_CHANGED", self, function() PUIRogue:UpdateHUD() end)

    -- Smooth 2.0s Energy Animation Ticker
    Time:Every(0.04, function()
        if lastTickTime > 0 then
            local elapsed = GetTime() - lastTickTime
            if elapsed <= 2.0 then
                energyBar:SetValue(elapsed)
            else
                lastTickTime = GetTime()
                energyBar:SetValue(0)
            end
        end
        local cur = UnitMana("player")
        local max = UnitManaMax("player")
        if max == 0 then max = 100 end
        energyBar.text:SetText(string.format("Energy: %d / %d", cur, max))
    end, self)

    -- Periodic Refresh (1s)
    Time:Every(1.0, function()
        PUIRogue:UpdateHUD()
    end, self)

    self:UpdateHUD()
end

function PUIRogue:OnDisable()
    Time:CancelAll(self)
    Events:UnregisterOwner(self)
    if hudFrame then hudFrame:Hide() end
end

