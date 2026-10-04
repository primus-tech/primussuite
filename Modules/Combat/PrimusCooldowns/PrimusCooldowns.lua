--[[
    PrimusLib Module: CooldownEngine (Spells, Items & Internal Cooldowns)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Unified cooldown tracking for player abilities, inventory items,
    trinkets, potions, and internal proc timers (ICDs).
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUICooldowns = Primus.PUICooldowns or {}
Primus.PUICooldowns = PUICooldowns
_G.PUICooldowns = PUICooldowns
Primus:RegisterModule("PUICooldowns", PUICooldowns, "Combat")

local Events = Primus.Events
local Time   = Primus.Time

-- Known Internal Cooldowns (ICDs) in Vanilla 1.12
local PROC_ICDS = {
    ["Windfury Attack"]     = 3.0, -- Windfury Weapon ICD
    ["Holy Strength"]       = 10.0, -- Crusader enchant
    ["Epiphany"]            = 45.0, -- Darkmoon Card: Blue Dragon
    ["Enigma's Answer"]     = 30.0, -- Enigma Set Proc
}

-- Check spell cooldown by name
function PUICooldowns:GetSpellCooldownByName(spellName)
    if not spellName then return 0, 0 end
    local i = 1
    while true do
        local name = GetSpellName(i, BOOKTYPE_SPELL)
        if not name then break end
        if name == spellName then
            local start, duration, enabled = GetSpellCooldown(i, BOOKTYPE_SPELL)
            return start or 0, duration or 0, enabled
        end
        i = i + 1
    end
    return 0, 0, 0
end

-- Check inventory slot cooldown
function PUICooldowns:GetInventoryCooldown(slotID)
    if not slotID then return 0, 0 end
    local start, duration, enabled = GetInventoryItemCooldown("player", slotID)
    return start or 0, duration or 0, enabled
end

-- Check bag slot cooldown
function PUICooldowns:GetContainerCooldown(bagID, slotID)
    if not bagID or not slotID then return 0, 0 end
    local start, duration, enabled = GetContainerItemCooldown(bagID, slotID)
    return start or 0, duration or 0, enabled
end

function PUICooldowns:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUICooldowns", {
        name = "PUICooldowns",
        category = "Combat",
        label = "Cooldown Tracker",
        icon = "Interface\Icons\Spell_Nature_TimeStop",
        desc = "Tracks spell, item, and pet cooldown timers with pulse alerts.",
    })
end

function PUICooldowns:OnInitialize()
    self:RegisterOptionsFlare()
    -- Listen for proc aura gains to trigger ICDs
    Events:Listen("PRIMUS_COMBAT_EVENT", self, function(owner, data)
        if data.eventType == "SPELL_AURA_APPLIED" and data.target == UnitName("player") then
            local icd = PROC_ICDS[data.spellName]
            if icd then
                Events:Fire("ICD_TRIGGERED", data.spellName, icd)
            end
        end
    end)
end
