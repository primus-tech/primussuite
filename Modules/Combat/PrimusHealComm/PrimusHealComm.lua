--[[
    PrimusLib Module: HealComm (Incoming Heal Predictor & Sync)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Predicts and broadcasts incoming healing amounts across healers
    to display green heal prediction bars on unit frames.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIHealComm = Primus.PUIHealComm or {}
Primus.PUIHealComm = PUIHealComm
_G.PUIHealComm = PUIHealComm
Primus:RegisterModule("PUIHealComm", PUIHealComm, "Combat")

local Events = Primus.Events
local Comm   = Primus.Comm
local Time   = Primus.Time
local Utils  = Primus.Utils

-- Active incoming heals: [targetName] = { [healerName] = amount }
local incomingHeals = {}

-- Estimated base heal amounts for Vanilla 1.12 spells
local HEAL_ESTIMATES = {
    ["Flash Heal"]          = 800,
    ["Greater Heal"]        = 2200,
    ["Heal"]                = 1100,
    ["Healing Touch"]       = 2400,
    ["Regrowth"]            = 1200,
    ["Holy Light"]          = 1800,
    ["Flash of Light"]      = 500,
    ["Healing Wave"]        = 1900,
    ["Lesser Healing Wave"] = 700,
    ["Chain Heal"]          = 1100,
}

-- Get total incoming heals on a target unit
function PUIHealComm:GetIncomingHeal(targetName)
    if not targetName or not incomingHeals[targetName] then return 0 end
    local total = 0
    for _, amount in pairs(incomingHeals[targetName]) do
        total = total + amount
    end
    return total
end

-- Broadcast heal start
function PUIHealComm:CastStarted(spellName, targetName)
    if not spellName or not targetName then return end
    local estAmount = HEAL_ESTIMATES[spellName]
    if not estAmount then return end

    if not incomingHeals[targetName] then
        incomingHeals[targetName] = {}
    end
    incomingHeals[targetName][UnitName("player")] = estAmount

    Comm:Send("HEAL_START", {
        target = targetName,
        amount = estAmount,
    }, "RAID")

    Events:Fire("HEAL_PREDICTION_UPDATED", targetName, self:GetIncomingHeal(targetName))
end

-- Broadcast heal finish or cancel
function PUIHealComm:CastEnded(targetName)
    targetName = targetName or UnitName("target") or UnitName("player")
    if incomingHeals[targetName] then
        incomingHeals[targetName][UnitName("player")] = nil
    end

    Comm:Send("HEAL_STOP", {
        target = targetName,
    }, "RAID")

    Events:Fire("HEAL_PREDICTION_UPDATED", targetName, self:GetIncomingHeal(targetName))
end

function PUIHealComm:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIHealComm", {
        name = "PUIHealComm",
        category = "Combat",
        label = "Heal Communication",
        icon = "Interface\Icons\Spell_Holy_Heal",
        desc = "Predictive incoming heal estimation and cross-client heal broadcasting.",
    })
end

function PUIHealComm:OnInitialize()
    self:RegisterOptionsFlare()
    -- Hook spellcast events for player
    Events:Register("SPELLCAST_START", self, function(owner, event, spellName, castDuration)
        local targetName = UnitName("target") or UnitName("player")
        PUIHealComm:CastStarted(spellName, targetName)
    end)

    Events:Register("SPELLCAST_STOP", self, function()
        PUIHealComm:CastEnded()
    end)

    Events:Register("SPELLCAST_INTERRUPTED", self, function()
        PUIHealComm:CastEnded()
    end)

    -- Receive Comm signals from group members
    Comm:RegisterPrefix("HEAL_START", function(owner, subPrefix, data, sender)
        if data.target and data.amount then
            if not incomingHeals[data.target] then
                incomingHeals[data.target] = {}
            end
            incomingHeals[data.target][sender] = tonumber(data.amount) or 0
            Events:Fire("HEAL_PREDICTION_UPDATED", data.target, PUIHealComm:GetIncomingHeal(data.target))
        end
    end, self)

    Comm:RegisterPrefix("HEAL_STOP", function(owner, subPrefix, data, sender)
        if data.target and incomingHeals[data.target] then
            incomingHeals[data.target][sender] = nil
            Events:Fire("HEAL_PREDICTION_UPDATED", data.target, PUIHealComm:GetIncomingHeal(data.target))
        end
    end, self)
end
