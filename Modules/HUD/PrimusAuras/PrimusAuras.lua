--[[
    PrimusUI Module: PUIAuras (Modern Virtual Buff & Debuff Grid)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Replaces Blizzard's legacy 2006 BuffFrame with a sleek, customizable aura grid
    featuring live duration countdowns, weapon enchant tracking, dispel borders,
    right-click buff cancellation, and native Mover integration.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIAuras = Primus.PUIAuras or {}
Primus.PUIAuras = PUIAuras
_G.PUIAuras = PUIAuras
Primus:RegisterModule("PUIAuras", PUIAuras, "HUD")

local DB      = Primus.DB
local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local Events  = Primus.Events
local Time    = Primus.Time
local PUIMover = Primus.PUIMover
local Auras   = Primus.PUICombatAuras
local Console = Primus.Console

local aurasDB = DB:RegisterNamespace("PUIAuras", {
    iconSize = 30,
    spacing = 4,
    buffsPerRow = 8,
    growthDirection = "LEFT", -- LEFT or RIGHT
    hideWithHud = true,       -- Auto-hide when PUIHud is active
})

local auraButtons = {}
local containerFrame = nil
local maxAuraSlots = 32

-- Check if PUIHud is active and enabled
function PUIAuras:IsHudActive()
    local hud = Primus.PUIHud
    if hud then
        if hud.IsHudActive then
            return hud:IsHudActive()
        end
        local hudDB = DB:GetNamespace("PUIHud")
        if hudDB and hudDB:Get("enabled", true) then
            return true
        end
    end
    return false
end

-- Format remaining duration (seconds to string)
local function FormatDuration(seconds)
    return Utils.FormatAuraDuration(seconds)
end

-- Create an individual aura slot button
local function CreateAuraButton(index, parent)
    local size = aurasDB:Get("iconSize", 30) or 30
    local btn = CreateFrame("Button", "Primus_PUIAuraBtn_" .. index, parent)
    btn:SetWidth(size)
    btn:SetHeight(size)
    btn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    btn:SetBackdropColor(0.05, 0.05, 0.08, 0.9)
    btn:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)
    btn:RegisterForClicks("RightButtonUp")
    btn:Hide()

    -- Icon texture
    local icon = btn:CreateTexture(nil, "BORDER")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = icon

    -- Duration text
    local duration = btn:CreateFontString(nil, "OVERLAY")
    duration:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    duration:SetPoint("TOP", btn, "BOTTOM", 0, -2)
    duration:SetTextColor(1, 1, 0.4)
    btn.duration = duration

    -- Stack count
    local count = btn:CreateFontString(nil, "OVERLAY")
    count:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    count:SetTextColor(1, 1, 1)
    btn.count = count

    -- Tooltip & Cancel interaction
    btn:SetScript("OnEnter", function()
        if btn.buffIndex then
            GameTooltip:SetOwner(btn, "ANCHOR_BOTTOMLEFT")
            GameTooltip:SetPlayerBuff(btn.buffIndex)
        elseif btn.isWeaponEnchant then
            GameTooltip:SetOwner(btn, "ANCHOR_BOTTOMLEFT")
            GameTooltip:SetInventoryItem("player", btn.weaponSlot)
        end
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    btn:SetScript("OnClick", function()
        if arg1 == "RightButton" and btn.buffIndex and not btn.isDebuff then
            CancelPlayerBuff(btn.buffIndex)
        end
    end)

    auraButtons[index] = btn
    return btn
end

-- Refresh and update all player aura icons
function PUIAuras:UpdateAuras()
    if not containerFrame then return end

    -- Auto-hide when PUIHud is active and hideWithHud option is enabled
    if aurasDB:Get("hideWithHud", true) and self:IsHudActive() then
        if containerFrame:IsShown() then
            containerFrame:Hide()
        end
        return
    else
        if not containerFrame:IsShown() then
            containerFrame:Show()
        end
    end

    local CoreAuras = Primus.Auras
    local size = aurasDB:Get("iconSize", 30) or 30
    local spacing = aurasDB:Get("spacing", 4) or 4
    local perRow = aurasDB:Get("buffsPerRow", 8) or 8
    local activeSlot = 0

    -- 1. Check Temporary Weapon Enchants via Central Primus.Auras Service
    local enchants = CoreAuras and CoreAuras:GetWeaponEnchants()
    if enchants and enchants.hasMainHand then
        activeSlot = activeSlot + 1
        local btn = auraButtons[activeSlot] or CreateAuraButton(activeSlot, containerFrame)
        btn.buffIndex = nil
        btn.isDebuff = false
        btn.isWeaponEnchant = true
        btn.weaponSlot = 16
        btn.icon:SetTexture(GetInventoryItemTexture("player", 16) or "Interface\\Icons\\INV_Sword_04")
        local durSec = enchants.mainHandExp or 0
        btn.duration:SetText(Utils.FormatAuraDuration(durSec))
        local dr, dg, db = Utils.GetAuraDurationColor(durSec)
        btn.duration:SetTextColor(dr, dg, db)
        btn.count:SetText("")
        btn:SetBackdropBorderColor(0.8, 0.4, 0.0, 1) -- Orange border for weapon buff
        btn:Show()
    end

    if enchants and enchants.hasOffHand then
        activeSlot = activeSlot + 1
        local btn = auraButtons[activeSlot] or CreateAuraButton(activeSlot, containerFrame)
        btn.buffIndex = nil
        btn.isDebuff = false
        btn.isWeaponEnchant = true
        btn.weaponSlot = 17
        btn.icon:SetTexture(GetInventoryItemTexture("player", 17) or "Interface\\Icons\\INV_Sword_04")
        local durSec = enchants.offHandExp or 0
        btn.duration:SetText(Utils.FormatAuraDuration(durSec))
        local dr, dg, db = Utils.GetAuraDurationColor(durSec)
        btn.duration:SetTextColor(dr, dg, db)
        btn.count:SetText("")
        btn:SetBackdropBorderColor(0.8, 0.4, 0.0, 1)
        btn:Show()
    end

    -- 2. Query Cached Player Buffs & Debuffs from Primus.Auras
    local playerAuras = CoreAuras and CoreAuras:GetUnitAuras("player")
    if playerAuras then
        if playerAuras.totalBuffs and playerAuras.totalBuffs > 0 then
            for i = 1, playerAuras.totalBuffs do
                local buff = playerAuras.buffs[i]
                if buff and buff.texture then
                    activeSlot = activeSlot + 1
                    local btn = auraButtons[activeSlot] or CreateAuraButton(activeSlot, containerFrame)
                    btn.buffIndex = buff.buffIndex
                    btn.isDebuff = false
                    btn.isWeaponEnchant = false

                    btn.icon:SetTexture(buff.texture)
                    btn.duration:SetText(Utils.FormatAuraDuration(buff.timeLeft))
                    local dr, dg, db = Utils.GetAuraDurationColor(buff.timeLeft)
                    btn.duration:SetTextColor(dr, dg, db)
                    btn.count:SetText((buff.stacks and buff.stacks > 1) and tostring(buff.stacks) or "")
                    btn:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)
                    btn:Show()
                end
            end
        end

        if playerAuras.totalDebuffs and playerAuras.totalDebuffs > 0 then
            for i = 1, playerAuras.totalDebuffs do
                local debuff = playerAuras.debuffs[i]
                if debuff and debuff.texture then
                    activeSlot = activeSlot + 1
                    local btn = auraButtons[activeSlot] or CreateAuraButton(activeSlot, containerFrame)
                    btn.buffIndex = debuff.buffIndex
                    btn.isDebuff = true
                    btn.isWeaponEnchant = false

                    btn.icon:SetTexture(debuff.texture)
                    btn.duration:SetText(Utils.FormatAuraDuration(debuff.timeLeft))
                    local dr, dg, db = Utils.GetAuraDurationColor(debuff.timeLeft)
                    btn.duration:SetTextColor(dr, dg, db)
                    btn.count:SetText((debuff.stacks and debuff.stacks > 1) and tostring(debuff.stacks) or "")

                    local dc = CoreAuras:GetDispelColor(debuff.dispelType)
                    btn:SetBackdropBorderColor(dc.r, dc.g, dc.b, 1)
                    btn:Show()
                end
            end
        end
    end

    -- Hide remaining unused buttons
    for i = activeSlot + 1, maxAuraSlots do
        if auraButtons[i] then
            auraButtons[i]:Hide()
        end
    end

    -- Arrange visible buttons in grid
    for i = 1, activeSlot do
        local btn = auraButtons[i]
        local row = math.floor((i - 1) / perRow)
        local col = Utils.Mod(i - 1, perRow)

        btn:ClearAllPoints()
        local xOfs = -(col * (size + spacing))
        local yOfs = -(row * (size + spacing + 14))
        btn:SetPoint("TOPRIGHT", containerFrame, "TOPRIGHT", xOfs, yOfs)
    end
end

function PUIAuras:RegisterOptionsFlare()
    local optionsHub = Primus.Options
    if not optionsHub or not optionsHub.RegisterModuleOptions then return end

    optionsHub:RegisterModuleOptions("PUIAuras", "HUD", {
        title = "PUIAuras: Buff & Debuff Grid",
        description = "Modern player buff, debuff, and weapon enchant display with live duration sweeps.",
        icon = "Interface\\Icons\\Spell_Holy_AuraMastery",
        fields = {
            {
                key = "hideWithHud",
                label = "Hide When PUIHud Is Active",
                type = "checkbox",
                desc = "Automatically hide the top-right aura grid while the central combat HUD is active.",
                default = true,
                get = function() return aurasDB:Get("hideWithHud", true) end,
                set = function(val)
                    aurasDB:Set("hideWithHud", val)
                    PUIAuras:UpdateAuras()
                end,
            },
            {
                key = "buffsPerRow",
                label = "Buffs Per Row",
                type = "slider",
                min = 4,
                max = 16,
                step = 1,
                default = 8,
                get = function() return aurasDB:Get("buffsPerRow", 8) end,
                set = function(val)
                    aurasDB:Set("buffsPerRow", val)
                    PUIAuras:UpdateAuras()
                end,
            },
            {
                key = "iconSize",
                label = "Icon Size (px)",
                type = "slider",
                min = 20,
                max = 48,
                step = 2,
                default = 30,
                get = function() return aurasDB:Get("iconSize", 30) end,
                set = function(val)
                    aurasDB:Set("iconSize", val)
                    PUIAuras:UpdateAuras()
                end,
            },
            {
                key = "spacing",
                label = "Icon Spacing (px)",
                type = "slider",
                min = 1,
                max = 10,
                step = 1,
                default = 4,
                get = function() return aurasDB:Get("spacing", 4) end,
                set = function(val)
                    aurasDB:Set("spacing", val)
                    PUIAuras:UpdateAuras()
                end,
            },
        },
    })
end

function PUIAuras:OnInitialize()
    self:RegisterOptionsFlare()
    -- 1. Cleanly disable Blizzard's legacy Buff frames
    if BuffFrame then
        BuffFrame:Hide()
        BuffFrame:UnregisterAllEvents()
    end
    if TemporaryEnchantFrame then
        TemporaryEnchantFrame:Hide()
        TemporaryEnchantFrame:UnregisterAllEvents()
    end

    -- 2. Create Master Primus PUIAuras Container Frame
    containerFrame = CreateFrame("Frame", "Primus_PUIAuras", UIParent)
    containerFrame:SetWidth(280)
    containerFrame:SetHeight(120)
    containerFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -180, -13)
    containerFrame:SetMovable(true)

    -- Register with PUIMover
    local mover = PUIMover or Primus.PUIMover
    if mover and mover.Register then
        mover:Register(containerFrame, "PUIAuras", "PUIAuras: Buff & Debuff Grid", "HUD")
    end

    -- 3. Register Events & Update Tickers
    Events:Register("PLAYER_AURAS_CHANGED", self, function()
        PUIAuras:UpdateAuras()
    end)

    -- 1-second ticker for smooth duration countdowns
    Time:Every(1.0, function()
        PUIAuras:UpdateAuras()
    end)

    -- 4. Listen for module state transitions
    Events:Listen("MODULE_ENABLED", self, function(owner, modName)
        if modName == "PUIHud" then
            PUIAuras:UpdateAuras()
        end
    end)
    Events:Listen("MODULE_DISABLED", self, function(owner, modName)
        if modName == "PUIHud" then
            PUIAuras:UpdateAuras()
        end
    end)

    -- Subcommand registration via Console Router
    if Console and Console.RegisterSubCommand then
        Console:RegisterSubCommand("auras", function()
            local mover = PUIMover or Primus.PUIMover
            if mover and mover.Unlock then mover:Unlock("HUD") end
        end, "PUIAuras buff & debuff tracker (/pui auras)")
    end

    -- Initial render
    self:UpdateAuras()
end
