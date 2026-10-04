--[[
    PrimusLib Module: Class_Shaman (4-Element Totems, Jesus Rezz / Ankh & Shield Suite)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Tracks:
    1. 4-Element Totem bar (Earth, Fire, Water, Air) with live expiration timers.
    2. "Jesus Rezz" (Reincarnation cooldown) and Ankh reagent inventory counter.
    3. Lightning Shield / Water Shield active charges & duration.
    4. Dual-hand Weapon Imbues (Windfury, Rockbiter, Flametongue, Frostbrand).
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local _, playerClass = UnitClass("player")
if playerClass ~= "SHAMAN" then return end

local PUIShaman = Primus.PUIShaman or {}
Primus.PUIShaman = PUIShaman
_G.PUIShaman = PUIShaman
Primus:RegisterModule("PUIShaman", PUIShaman, "Classes")

local DB      = Primus.DB
local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local Events  = Primus.Events
local Time    = Primus.Time
local PUIMover = Primus.PUIMover

local shamanDB = DB:RegisterNamespace("PUIShaman", {
    enabled = true,
})

local hudFrame = nil
local totemSlots = {}

-- Totem database: Element index (1: Earth, 2: Fire, 3: Water, 4: Air)
local TOTEMS = {
    -- Earth
    ["Stoneskin Totem"]          = { elem = 1, dur = 120, icon = "Spell_Nature_StoneSkinTotem" },
    ["Tremor Totem"]             = { elem = 1, dur = 120, icon = "Spell_Nature_TremorTotem" },
    ["Earthbind Totem"]          = { elem = 1, dur = 45,  icon = "Spell_Nature_StrengthOfEarthTotem02" },
    ["Strength of Earth Totem"]  = { elem = 1, dur = 120, icon = "Spell_Nature_EarthBindTotem" },
    ["Stoneclaw Totem"]          = { elem = 1, dur = 15,  icon = "Spell_Nature_StoneClawTotem" },

    -- Fire
    ["Searing Totem"]            = { elem = 2, dur = 55,  icon = "Spell_Fire_SearingTotem" },
    ["Magma Totem"]              = { elem = 2, dur = 20,  icon = "Spell_Fire_SelfDestruct" },
    ["Fire Nova Totem"]          = { elem = 2, dur = 5,   icon = "Spell_Fire_SealOfFire" },
    ["Frost Resistance Totem"]   = { elem = 2, dur = 120, icon = "Spell_FrostFragility" },
    ["Flametongue Totem"]        = { elem = 2, dur = 120, icon = "Spell_Nature_GuardianWard" },

    -- Water
    ["Healing Stream Totem"]     = { elem = 3, dur = 120, icon = "INV_Spear_04" },
    ["Mana Spring Totem"]        = { elem = 3, dur = 120, icon = "Spell_Nature_ManaRegenTotem" },
    ["Poison Cleansing Totem"]   = { elem = 3, dur = 120, icon = "Spell_Nature_PoisonCleansing_Totem" },
    ["Disease Cleansing Totem"]  = { elem = 3, dur = 120, icon = "Spell_Nature_DiseaseCleansing_Totem" },
    ["Fire Resistance Totem"]    = { elem = 3, dur = 120, icon = "Spell_Fire_FireArmor" },

    -- Air
    ["Windfury Totem"]           = { elem = 4, dur = 120, icon = "Spell_Nature_Windfury" },
    ["Grace of Air Totem"]       = { elem = 4, dur = 120, icon = "Spell_Nature_InvisibilityTotem" },
    ["Grounding Totem"]          = { elem = 4, dur = 45,  icon = "Spell_Nature_GroundingTotem" },
    ["Nature Resistance Totem"]  = { elem = 4, dur = 120, icon = "Spell_Nature_NatureResistanceTotem" },
    ["Windwall Totem"]           = { elem = 4, dur = 120, icon = "Spell_Nature_EarthBind" },
    ["Tranquil Air Totem"]       = { elem = 4, dur = 120, icon = "Spell_Nature_Brilliance" },
}

local ELEMENT_COLORS = {
    [1] = { 0.6, 0.4, 0.2 }, -- Earth Brown
    [2] = { 1.0, 0.3, 0.1 }, -- Fire Red/Orange
    [3] = { 0.2, 0.6, 1.0 }, -- Water Blue
    [4] = { 0.7, 0.9, 0.9 }, -- Air Cyan
}

local activeTotems = {}

-- Count Ankhs in Bags
function PUIShaman:GetAnkhCount()
    local count = 0
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots > 0 then
            for slot = 1, numSlots do
                local link = GetContainerItemLink(bag, slot)
                if link and string.find(link, "Ankh") then
                    local _, itemCount = GetContainerItemInfo(bag, slot)
                    count = count + (itemCount or 1)
                end
            end
        end
    end
    return count
end

local SHAMAN_BIG_SPELLS = {
    { name = "Reincarnation",       short = "Rezz",     tex = "Spell_Nature_Reincarnation" },
    { name = "Mana Tide Totem",     short = "MTide",    tex = "Spell_Frost_SummonWaterElemental" },
    { name = "Nature's Swiftness",  short = "NS",       tex = "Spell_Nature_RavenForm" },
    { name = "Elemental Mastery",   short = "EMastery", tex = "Spell_Nature_WispHeal" },
    { name = "Earth Shock",         short = "EShock",   tex = "Spell_Nature_EarthShock" },
}

local knownSpells = {}

function PUIShaman:ScanSpellbook()
    knownSpells = {}
    local i = 1
    local numBig = table.getn(SHAMAN_BIG_SPELLS)
    while true do
        local spellName = GetSpellName(i, BOOKTYPE_SPELL)
        if not spellName then break end
        local texture = GetSpellTexture(i, BOOKTYPE_SPELL)
        for idx = 1, numBig do
            local bigSpell = SHAMAN_BIG_SPELLS[idx]
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

function PUIShaman:GetMajorCooldowns()
    local list = {}
    local numBig = table.getn(SHAMAN_BIG_SPELLS)
    for idx = 1, numBig do
        local def = SHAMAN_BIG_SPELLS[idx]
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

-- Find Reincarnation Spell ID & Cooldown
function PUIShaman:GetReincarnationCD()
    local info = knownSpells["Reincarnation"]
    if info then
        local start, duration = GetSpellCooldown(info.spellID, BOOKTYPE_SPELL)
        if start and start > 0 and duration and duration > 0 then
            local cdLeft = (start + duration) - GetTime()
            return cdLeft > 0 and cdLeft or 0, duration
        end
        return 0, 0
    end
    local i = 1
    while true do
        local name = GetSpellName(i, BOOKTYPE_SPELL)
        if not name then break end
        if name == "Reincarnation" then
            local start, duration = GetSpellCooldown(i, BOOKTYPE_SPELL)
            if start and start > 0 and duration and duration > 0 then
                local cdLeft = (start + duration) - GetTime()
                return cdLeft > 0 and cdLeft or 0, duration
            end
            return 0, 0
        end
        i = i + 1
    end
    return 0, 0
end

-- Scan Lightning / Water Shield Buff on Player
function PUIShaman:GetShieldStatus()
    for i = 1, 32 do
        local tex = UnitBuff("player", i)
        if not tex then break end
        if string.find(tex, "Spell_Nature_LightningShield") then
            local _, charges = GetPlayerBuffApplications(i)
            return "Lightning", charges or 3, tex
        elseif string.find(tex, "Ability_Shaman_WaterShield") then
            local _, charges = GetPlayerBuffApplications(i)
            return "Water", charges or 3, tex
        end
    end
    return nil, 0, nil
end

-- Update Shaman Suite Display
function PUIShaman:UpdateHUD()
    if not hudFrame or not hudFrame:IsShown() then return end

    -- 1. Totem Slots (1: Earth, 2: Fire, 3: Water, 4: Air)
    local now = GetTime()
    for i = 1, 4 do
        local t = activeTotems[i]
        local slot = totemSlots[i]
        if t and t.expires > now then
            local left = t.expires - now
            slot.icon:SetTexture(t.icon)
            slot.icon:Show()
            slot.timer:SetText(string.format("%.0fs", left))
            if left <= 10 then
                slot.timer:SetTextColor(1.0, 0.2, 0.2) -- Red flashing
                slot:SetBackdropBorderColor(1.0, 0.2, 0.2, 1)
            else
                slot.timer:SetTextColor(1.0, 1.0, 0.4)
                local c = ELEMENT_COLORS[i]
                slot:SetBackdropBorderColor(c[1], c[2], c[3], 1)
            end
        else
            activeTotems[i] = nil
            slot.icon:Hide()
            slot.timer:SetText("")
            local c = ELEMENT_COLORS[i]
            slot:SetBackdropBorderColor(c[1] * 0.4, c[2] * 0.4, c[3] * 0.4, 0.6)
        end
    end

    -- 2. "Jesus Rezz" (Reincarnation + Ankhs)
    local ankhs = self:GetAnkhCount()
    local rezzCD = self:GetReincarnationCD()

    if rezzCD > 0 then
        hudFrame.ankhText:SetText(string.format("Jesus Rezz: %s (%d)", Time:FormatShort(rezzCD), ankhs))
        hudFrame.ankhText:SetTextColor(1.0, 0.3, 0.3)
    elseif ankhs == 0 then
        hudFrame.ankhText:SetText("Jesus Rezz: NO ANKH")
        hudFrame.ankhText:SetTextColor(1.0, 0.5, 0.2)
    else
        hudFrame.ankhText:SetText(string.format("Jesus Rezz: READY (%d)", ankhs))
        hudFrame.ankhText:SetTextColor(0.2, 1.0, 0.4)
    end

    -- 3. Shield Status
    local shieldType, charges = self:GetShieldStatus()
    if shieldType then
        hudFrame.shieldText:SetText(string.format("%s Shield: %d", shieldType, charges))
        if charges <= 1 then
            hudFrame.shieldText:SetTextColor(1.0, 0.8, 0.2) -- Warning 1 charge
        else
            hudFrame.shieldText:SetTextColor(0.2, 0.8, 1.0)
        end
    else
        hudFrame.shieldText:SetText("Shield: MISSING")
        hudFrame.shieldText:SetTextColor(1.0, 0.2, 0.2)
    end

    -- 4. Weapon Imbues
    local hasMH, mhExp, _, hasOH = GetWeaponEnchantInfo()
    if hasMH then
        local mins = math.floor((mhExp or 0) / 60000)
        hudFrame.weaponText:SetText(string.format("Wep: Active (%dm)", mins))
        hudFrame.weaponText:SetTextColor(0.2, 1.0, 0.4)
    else
        hudFrame.weaponText:SetText("Wep: NO IMBUE")
        hudFrame.weaponText:SetTextColor(1.0, 0.2, 0.2)
    end
end

local function CreateTotemSlot(elemIndex, parent)
    local btn = CreateFrame("Frame", "Primus_TotemSlot_" .. elemIndex, parent)
    btn:SetWidth(34)
    btn:SetHeight(34)
    btn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    btn:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
    local c = ELEMENT_COLORS[elemIndex] or { 0.4, 0.4, 0.4 }
    btn:SetBackdropBorderColor(c[1], c[2], c[3], 1)

    local icon = btn:CreateTexture(nil, "BORDER")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = icon

    local timer = btn:CreateFontString(nil, "OVERLAY")
    timer:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    timer:SetPoint("BOTTOM", btn, "BOTTOM", 0, 1)
    timer:SetTextColor(1, 1, 0.4)
    btn.timer = timer

    totemSlots[elemIndex] = btn
    return btn
end

function PUIShaman:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIShaman", {
        name = "Class_Shaman",
        category = "Classes",
        label = "Shaman Nuances",
        options = {
            {
                key = "enabled",
                type = "checkbox",
                label = "Enable Shaman Suite",
                desc = "Show 4-Element Totem bar, Jesus Rezz / Ankh tracker, Shield status, and Weapon Imbues.",
                default = true,
                get = function() return shamanDB:Get("enabled") end,
                set = function(v)
                    shamanDB:Set("enabled", v)
                    if v then hudFrame:Show() else hudFrame:Hide() end
                end,
            },
        },
    })
end

function PUIShaman:OnInitialize()
    -- Create Shaman HUD Frame
    hudFrame = CreateFrame("Frame", "Primus_ShamanHUD", UIParent)
    hudFrame:SetWidth(270)
    hudFrame:SetHeight(86)
    hudFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 180)
    hudFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
    hudFrame:SetBackdropColor(0.06, 0.08, 0.12, 0.9)
    hudFrame:SetBackdropBorderColor(0.0, 0.44, 0.87, 1) -- Shaman Blue

    -- Header Title
    local title = hudFrame:CreateFontString(nil, "OVERLAY")
    title:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    title:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 6, -6)
    title:SetText(Utils.ColorText("Shaman Suite", "0070de"))
    hudFrame.title = title

    -- "Jesus Rezz" Text (Header Right)
    local ankhText = hudFrame:CreateFontString(nil, "OVERLAY")
    ankhText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    ankhText:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -6, -6)
    ankhText:SetText("Jesus Rezz: READY (0)")
    hudFrame.ankhText = ankhText

    -- 4 Totem Slots Container
    local totemContainer = CreateFrame("Frame", nil, hudFrame)
    totemContainer:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 6, -22)
    totemContainer:SetWidth(152)
    totemContainer:SetHeight(36)
    hudFrame.totemContainer = totemContainer

    for i = 1, 4 do
        local slot = CreateTotemSlot(i, totemContainer)
        slot:SetPoint("LEFT", totemContainer, "LEFT", (i - 1) * 38, 0)
    end

    -- Shield Status Text
    local shieldText = hudFrame:CreateFontString(nil, "OVERLAY")
    shieldText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    shieldText:SetPoint("LEFT", totemContainer, "RIGHT", 8, 8)
    shieldText:SetText("Shield: MISSING")
    hudFrame.shieldText = shieldText

    -- Weapon Imbue Status Text
    local weaponText = hudFrame:CreateFontString(nil, "OVERLAY")
    weaponText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    weaponText:SetPoint("LEFT", totemContainer, "RIGHT", 8, -8)
    weaponText:SetText("Wep: NO IMBUE")
    hudFrame.weaponText = weaponText

    local mover = PUIMover or Primus.PUIMover
    if mover and mover.Register then
        mover:Register(hudFrame, "ShamanHUD", "Shaman Suite (Totems & Reincarnation)", "CLASS")
    end

    self:RegisterOptionsFlare()
end

function PUIShaman:OnEnable()
    if hudFrame and shamanDB:Get("enabled") then
        hudFrame:Show()
    end

    -- Track Totem Casts
    Events:Register("SPELLCAST_START", self, function(owner, event, spellName)
        local tInfo = TOTEMS[spellName]
        if tInfo then
            activeTotems[tInfo.elem] = {
                name = spellName,
                icon = "Interface\\Icons\\" .. tInfo.icon,
                expires = GetTime() + tInfo.dur,
                duration = tInfo.dur,
            }
            PUIShaman:UpdateHUD()
        end
    end)

    Events:Register("SPELLCAST_STOP", self, function()
        PUIShaman:UpdateHUD()
    end)

    -- Spellbook & Cooldown Events
    self:ScanSpellbook()
    Events:Register("SPELLS_CHANGED", self, function() PUIShaman:ScanSpellbook() PUIShaman:UpdateHUD() end)
    Events:Register("LEARNED_SPELL_IN_TAB", self, function() PUIShaman:ScanSpellbook() PUIShaman:UpdateHUD() end)
    Events:Register("SPELL_UPDATE_COOLDOWN", self, function() PUIShaman:UpdateHUD() end)
    Events:Register("PLAYER_ENTERING_WORLD", self, function() PUIShaman:ScanSpellbook() PUIShaman:UpdateHUD() end)

    Events:Register("UNIT_AURA", self, function()
        PUIShaman:UpdateHUD()
    end)

    Events:Register("BAG_UPDATE", self, function()
        PUIShaman:UpdateHUD()
    end)

    -- Live 0.5s HUD Refresh Ticker
    Time:Every(0.5, function()
        PUIShaman:UpdateHUD()
    end, self)

    self:UpdateHUD()
end

function PUIShaman:OnDisable()
    Time:CancelAll(self)
    Events:UnregisterOwner(self)
    activeTotems = {}
    if hudFrame then hudFrame:Hide() end
end

