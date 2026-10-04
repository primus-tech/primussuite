--[[
    PrimusUI Core: Centralized Item Resolver (Items.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (Lua 5.0.2)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)

    Subsystem: Single-call Item Query & Resolution Pipeline
    - Extracts item ID, name, rarity, textures, min level, equip slots, stack counts.
    - Resolves vendor buy/sell prices from static databases & learned realm caches.
    - Provides standardized quality colors, link extractors, and stat scanners.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local Items = Primus.Items or {}
Primus.Items = Items
_G.Primus.Items = Items

local Utils = Primus.Utils

-- Quality Colors Map (0 to 6)
local QUALITY_COLORS = {
    [0] = { r = 0.62, g = 0.62, b = 0.62, hex = "9d9d9d", name = "Poor" },
    [1] = { r = 1.00, g = 1.00, b = 1.00, hex = "ffffff", name = "Common" },
    [2] = { r = 0.12, g = 1.00, b = 0.00, hex = "1eff00", name = "Uncommon" },
    [3] = { r = 0.00, g = 0.44, b = 0.87, hex = "0070dd", name = "Rare" },
    [4] = { r = 0.64, g = 0.21, b = 0.93, hex = "a335ee", name = "Epic" },
    [5] = { r = 1.00, g = 0.50, b = 0.00, hex = "ff8000", name = "Legendary" },
    [6] = { r = 0.90, g = 0.80, b = 0.50, hex = "e6cc80", name = "Artifact" },
}

--------------------------------------------------------------------------------
-- Item ID & Hyperlink Parser
--------------------------------------------------------------------------------
function Items:GetID(linkOrID)
    if not linkOrID then return nil end
    if type(linkOrID) == "number" then return linkOrID end

    local num = tonumber(linkOrID)
    if num then return num end

    local _, _, id = string.find(tostring(linkOrID), "item:(%d+)")
    if id then return tonumber(id) end

    return nil
end

function Items:GetQualityColor(quality)
    quality = tonumber(quality) or 1
    return QUALITY_COLORS[quality] or QUALITY_COLORS[1]
end

function Items:FormatMoney(copper, showZero)
    copper = tonumber(copper) or 0
    if copper == 0 and not showZero then return "" end

    local gold = math.floor(copper / 10000)
    local silver = math.floor(math.mod(copper, 10000) / 100)
    local cop = math.mod(copper, 100)

    local res = ""
    if gold > 0 then
        res = res .. string.format("%d|cffffd100g|r ", gold)
    end
    if silver > 0 or gold > 0 then
        res = res .. string.format("%d|cffc7c7cfs|r ", silver)
    end
    res = res .. string.format("%d|cffeda55fc|r", cop)
    return res
end

--------------------------------------------------------------------------------
-- Vendor Sell & Base Price Resolver
--------------------------------------------------------------------------------
function Items:GetSellPrice(itemID)
    local id = self:GetID(itemID)
    if not id then return 0 end

    -- Check live realm cache if PUISellValue is loaded
    if _G.PrimusGlobalDB and _G.PrimusGlobalDB.PUISellValue and _G.PrimusGlobalDB.PUISellValue.realms then
        local realm = GetRealmName() or "Default"
        local rData = _G.PrimusGlobalDB.PUISellValue.realms[realm]
        if rData and rData.prices and rData.prices[id] then
            return tonumber(rData.prices[id]) or 0
        end
    end

    -- Check static prices DB
    if Primus.VanillaItemPrices and Primus.VanillaItemPrices[id] then
        return tonumber(Primus.VanillaItemPrices[id]) or 0
    end

    -- Check BasePriceDB
    if Primus.PUIBasePriceDB and Primus.PUIBasePriceDB[id] then
        return tonumber(Primus.PUIBasePriceDB[id]) or 0
    end

    return 0
end

--------------------------------------------------------------------------------
-- Master Item Information Query
--------------------------------------------------------------------------------
function Items:Get(linkOrID)
    if not linkOrID then return nil end

    local id = self:GetID(linkOrID)
    local name, link, quality, minLevel, itemType, itemSubType, maxStack, equipLoc, texture = GetItemInfo(linkOrID)

    if not name and id then
        name, link, quality, minLevel, itemType, itemSubType, maxStack, equipLoc, texture = GetItemInfo(id)
    end

    if not name then
        return nil
    end

    local qColor = self:GetQualityColor(quality)
    local sellPrice = id and self:GetSellPrice(id) or 0

    return {
        id = id,
        name = name,
        link = link,
        quality = quality or 1,
        qualityColor = qColor,
        minLevel = minLevel or 1,
        type = itemType or "",
        subType = itemSubType or "",
        maxStack = maxStack or 1,
        equipLoc = equipLoc or "",
        texture = texture or "Interface\\Icons\\INV_Misc_QuestionMark",
        sellPrice = sellPrice,
    }
end
