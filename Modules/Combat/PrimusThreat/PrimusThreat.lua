--[[
    PrimusLib Module: ThreatEngine (Vanilla Threat Calculation & Sync)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Computes real-time threat values for abilities, stances, and modifiers,
    and synchronizes threat tables across party/raid over CommBus.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIThreat = Primus.PUIThreat or {}
Primus.PUIThreat = PUIThreat
_G.PUIThreat = PUIThreat
Primus:RegisterModule("PUIThreat", PUIThreat, "Combat")

local Events = Primus.Events
local Comm   = Primus.Comm
local Memory = Primus.Memory
local Utils  = Primus.Utils
local Time   = Primus.Time

-- Threat Tables: [targetName] = { [playerName] = threatValue }
local threatTables = {}
local dirtyTargets = {}

-- Flat bonus threat for 1.12 abilities
local FLAT_BONUS = {
    ["Sunder Armor"]    = 260,
    ["Heroic Strike"]   = 145,
    ["Revenge"]         = 315,
    ["Shield Slam"]     = 250,
    ["Taunt"]           = 0,
    ["Earth Shock"]     = 200,
    ["Mind Blast"]      = 150,
    ["Holy Shield"]     = 100,
    ["Feint"]           = -600,
}

-- Calculate threat multiplier from stance/buffs
function PUIThreat:GetMultiplier()
    local mult = 1.0
    local _, playerClass = UnitClass("player")

    if playerClass == "WARRIOR" then
        -- Check stance
        for i = 1, 3 do
            local _, _, active = GetShapeshiftFormInfo(i)
            if active then
                if i == 2 then mult = 1.30 end -- Defensive Stance
                if i == 1 or i == 3 then mult = 0.80 end -- Battle / Berserker
                break
            end
        end
    elseif playerClass == "DRUID" then
        for i = 1, 4 do
            local _, _, active = GetShapeshiftFormInfo(i)
            if active and i == 1 then -- Bear Form
            mult = 1.30
            break
        end
    end
    elseif playerClass == "ROGUE" then
        mult = 0.71
    end

    return mult
end

-- Record threat action and mark dirty for batched broadcast
function PUIThreat:AddThreat(target, amount, abilityName)
    if not target or amount == 0 then return end

    local flat = (abilityName and FLAT_BONUS[abilityName]) or 0
    local totalThreat = (amount + flat) * self:GetMultiplier()

    if not threatTables[target] then
        threatTables[target] = {}
    end

    local current = threatTables[target][UnitName("player")] or 0
    threatTables[target][UnitName("player")] = math.max(0, current + totalThreat)
    dirtyTargets[target] = true
end

-- Periodic broadcast to group over CommBus
function PUIThreat:BroadcastThreat()
    if GetNumPartyMembers() == 0 and GetNumRaidMembers() == 0 then
        dirtyTargets = {}
        return
    end

    local pName = UnitName("player")
    local dist = GetNumRaidMembers() > 0 and "RAID" or "PARTY"
    for target in pairs(dirtyTargets) do
        if threatTables[target] and threatTables[target][pName] then
            Comm:Send("THREAT", {
                target = target,
                threat = threatTables[target][pName],
            }, dist)
        end
    end
    dirtyTargets = {}
end

-- Get current threat on a target
function PUIThreat:GetThreat(target, unitName)
    unitName = unitName or UnitName("player")
    if threatTables[target] then
        return threatTables[target][unitName] or 0
    end
    return 0
end

function PUIThreat:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIThreat", {
        name = "PUIThreat",
        category = "Combat",
        label = "Threat & Aggro",
        icon = "Interface\Icons\Spell_Fire_FireArmor",
        desc = "Multi-target threat tracking, aggro warnings, and threat meter telemetry.",
    })
end

function PUIThreat:OnInitialize()
    self:RegisterOptionsFlare()
    -- Listen for combat events from CombatLog module
    Events:Listen("PRIMUS_COMBAT_EVENT", self, function(owner, data)
        if data.source == UnitName("player") and data.target then
            if data.eventType == "SWING_DAMAGE" or data.eventType == "SPELL_DAMAGE" then
                PUIThreat:AddThreat(data.target, data.amount, data.spellName)
            elseif data.eventType == "SPELL_HEAL" then
                -- 0.5 threat per effective heal in Vanilla, divided among active mobs
                PUIThreat:AddThreat(data.target, data.amount * 0.5, data.spellName)
            end
        end
    end)

    -- Periodic 1.5s broadcast ticker to eliminate network flooding
    if Time and Time.Every then
        Time:Every(1.5, function()
            PUIThreat:BroadcastThreat()
        end)
    end

    -- Receive threat sync from group members
    Comm:RegisterPrefix("THREAT", function(owner, subPrefix, data, sender)
        if data.target and data.threat then
            if not threatTables[data.target] then
                threatTables[data.target] = {}
            end
            threatTables[data.target][sender] = tonumber(data.threat) or 0
        end
    end, self)
end
