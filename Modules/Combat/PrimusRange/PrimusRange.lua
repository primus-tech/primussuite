--[[
    PrimusLib Module: RangeEngine (Distance & Proximity Checker)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Determines distance/proximity to targets and party/raid members using
    interaction distance and class spell ranges.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIRange = Primus.PUIRange or {}
Primus.PUIRange = PUIRange
_G.PUIRange = PUIRange
Primus:RegisterModule("PUIRange", PUIRange, "Combat")

-- Check standard interaction distances (Trade: ~10y, Duel: ~10y, Inspect: ~30y)
function PUIRange:IsInRange(unit, rangeTier)
    if not unit or not UnitExists(unit) then return false end
    rangeTier = rangeTier or 30

    if rangeTier <= 10 then
        return CheckInteractDistance(unit, 2) and true or false -- Trade range (~11y)
    elseif rangeTier <= 30 then
        return CheckInteractDistance(unit, 1) and true or false -- Inspect range (~28y)
    elseif rangeTier <= 40 then
        -- Use UnitIsVisible for 40-yard range check in 1.12
        return UnitIsVisible(unit) and true or false
    end

    return false
end

-- Check if unit is in range for friendly healing/buffs
function PUIRange:IsUnitInRange(unit)
    return self:IsInRange(unit, 30)
end

function PUIRange:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIRange", {
        name = "PUIRange",
        category = "Combat",
        label = "Range & Distance",
        icon = "Interface\Icons\Ability_Hunter_EagleEye",
        desc = "Calculates precise spell and attack range indicators based on unit tooltips.",
    })
end

function PUIRange:OnInitialize()
    self:RegisterOptionsFlare()
end
