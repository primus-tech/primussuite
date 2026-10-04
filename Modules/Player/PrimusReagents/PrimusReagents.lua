--[[
    PrimusLib Module: Reagents (Consumable, Ammo & Soul Shard Monitor)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Monitors bag quantities of class-specific reagents (Soul Shards,
    Arrows, Flash Powder, Candles, Runes, and Ankhs).
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIReagents = Primus.PUIReagents or {}
Primus.PUIReagents = PUIReagents
_G.PUIReagents = PUIReagents
Primus:RegisterModule("PUIReagents", PUIReagents, "Player")

local Events = Primus.Events

-- Count specific item in bags by name
function PUIReagents:GetCount(itemName)
    if not itemName then return 0 end
    local count = 0
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link and string.find(link, itemName) then
                local _, itemCount = GetContainerItemInfo(bag, slot)
                count = count + (itemCount or 1)
            end
        end
    end
    return count
end

function PUIReagents:GetSoulShards()
    return self:GetCount("Soul Shard")
end

function PUIReagents:GetAmmoCount()
    local hasItem = GetInventoryItemLink("player", 0) -- Ammo slot
    if hasItem then
        return GetInventoryItemCount("player", 0) or 0
    end
    return 0
end

function PUIReagents:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIReagents", {
        name = "PUIReagents",
        category = "Player",
        label = "Reagent Counter",
        icon = "Interface\Icons\INV_Misc_Gem_01",
        desc = "Tracks class reagents, poisons, soul shards, and ammunition stocks.",
    })
end

function PUIReagents:OnInitialize()
    self:RegisterOptionsFlare()
    Events:Register("BAG_UPDATE", self, function()
        Events:Fire("REAGENTS_UPDATED")
    end)
end
