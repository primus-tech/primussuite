--[[
    PrimusUI Module: PUIBags (Item Categorization & Special Container Engine)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    1. Item Priority Ranking & Category Classification for sorting and categorized layouts.
    2. Special Container Detection (Quivers, Ammo Pouches, Soul Bags, Herb Bags, Mining Sacks, Enchanting Bags).
    3. Specialized Slot Color Tinting & Badges.
    4. Free Slot Telemetry & Allocation Breakdown.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIBags = Primus.PUIBags or {}
Primus.PUIBags = PUIBags
_G.PUIBags = PUIBags

local Categories = {}
PUIBags.Categories = Categories

local Utils = Primus.Utils

-- =========================================================================
-- CATEGORY CONSTANTS & PRIORITY RANKINGS
-- =========================================================================

-- Lower priority number = sorted first (towards top-left of inventory)
Categories.PRIORITY = {
    QUEST       = 1, -- Quest Items
    CONSUMABLE  = 2, -- Food, Drink, Potions, Bandages, Elixirs, Scrolls
    TRADE_GOODS = 3, -- Cloth, Leather, Ore, Herbs, Gems, Meat, Elemental
    EQUIPMENT   = 4, -- Weapons, Armor, Rings, Trinkets, Shields, Off-hands
    UTILITY     = 5, -- Hearthstone, Keys, Mining Pick, Skinning Knife, Tools
    RECIPE      = 6, -- Recipes, Formulas, Plans, Manuals, Patterns
    MISC        = 7, -- Books, Toys, Pet Tokens, Miscellaneous
    JUNK        = 8, -- Grey / Poor Quality Items
    EMPTY       = 9, -- Free Unoccupied Slots
}

Categories.CATEGORY_NAMES = {
    [1] = "Quest Items",
    [2] = "Consumables",
    [3] = "Trade Goods",
    [4] = "Equipment",
    [5] = "Utility & Tools",
    [6] = "Recipes & Plans",
    [7] = "Miscellaneous",
    [8] = "Junk",
    [9] = "Free Slots",
}

Categories.CATEGORY_ICONS = {
    [1] = "Interface\\Icons\\INV_Misc_Book_08",
    [2] = "Interface\\Icons\\INV_Potion_51",
    [3] = "Interface\\Icons\\INV_Fabric_Silk_02",
    [4] = "Interface\\Icons\\INV_Sword_04",
    [5] = "Interface\\Icons\\INV_Misc_Key_03",
    [6] = "Interface\\Icons\\INV_Scroll_03",
    [7] = "Interface\\Icons\\INV_Misc_Bag_08",
    [8] = "Interface\\Icons\\INV_Misc_Ruin_01",
    [9] = "Interface\\Icons\\INV_Misc_QuestionMark",
}

-- Special Container Types & Color Tints
Categories.SPECIAL_CONTAINERS = {
    QUIVER = {
        name = "Quiver",
        short = "Ammo",
        r = 0.95, g = 0.55, b = 0.15, a = 0.30,
        borderColor = { r = 0.95, g = 0.60, b = 0.10 },
    },
    AMMO_POUCH = {
        name = "Ammo Pouch",
        short = "Ammo",
        r = 0.95, g = 0.55, b = 0.15, a = 0.30,
        borderColor = { r = 0.95, g = 0.60, b = 0.10 },
    },
    SOUL_BAG = {
        name = "Soul Bag",
        short = "Soul",
        r = 0.70, g = 0.20, b = 0.90, a = 0.30,
        borderColor = { r = 0.75, g = 0.25, b = 0.95 },
    },
    HERB_BAG = {
        name = "Herb Bag",
        short = "Herb",
        r = 0.20, g = 0.85, b = 0.25, a = 0.30,
        borderColor = { r = 0.25, g = 0.90, b = 0.30 },
    },
    MINING_BAG = {
        name = "Mining Bag",
        short = "Mining",
        r = 0.55, g = 0.55, b = 0.65, a = 0.30,
        borderColor = { r = 0.60, g = 0.60, b = 0.70 },
    },
    ENCHANTING_BAG = {
        name = "Enchanting Bag",
        short = "Enchanting",
        r = 0.20, g = 0.70, b = 1.00, a = 0.30,
        borderColor = { r = 0.25, g = 0.75, b = 1.00 },
    },
}

-- =========================================================================
-- SPECIAL CONTAINER DETECTION
-- =========================================================================

-- Detect if a bag (1..4) is a specialized container
function Categories:GetSpecialContainerType(bagID)
    if not bagID or bagID <= 0 or bagID > 4 then return nil end
    local invSlot = ContainerIDToInventoryID and ContainerIDToInventoryID(bagID)
    if not invSlot then return nil end

    local bagLink = GetInventoryItemLink("player", invSlot)
    if not bagLink then return nil end

    local name, _, _, _, itemType, itemSubType = GetItemInfo(bagLink)
    local subLower = itemSubType and string.lower(itemSubType) or ""
    local nameLower = name and string.lower(name) or ""

    if subLower == "quiver" or string.find(nameLower, "quiver", 1, true) then
        return "QUIVER", Categories.SPECIAL_CONTAINERS.QUIVER
    elseif subLower == "ammo pouch" or string.find(nameLower, "pouch", 1, true) or string.find(nameLower, "ammo", 1, true) or string.find(nameLower, "bandolier", 1, true) or string.find(nameLower, "shot", 1, true) then
        return "AMMO_POUCH", Categories.SPECIAL_CONTAINERS.AMMO_POUCH
    elseif subLower == "soul bag" or string.find(nameLower, "soul", 1, true) or string.find(nameLower, "felcloth bag", 1, true) or string.find(nameLower, "core felcloth bag", 1, true) or string.find(nameLower, "box of souls", 1, true) then
        return "SOUL_BAG", Categories.SPECIAL_CONTAINERS.SOUL_BAG
    elseif subLower == "herb bag" or string.find(nameLower, "herb", 1, true) or string.find(nameLower, "cenarion", 1, true) then
        return "HERB_BAG", Categories.SPECIAL_CONTAINERS.HERB_BAG
    elseif subLower == "mining bag" or string.find(nameLower, "mining", 1, true) or string.find(nameLower, "miner", 1, true) or string.find(nameLower, "mammoth", 1, true) then
        return "MINING_BAG", Categories.SPECIAL_CONTAINERS.MINING_BAG
    elseif subLower == "enchanting bag" or string.find(nameLower, "enchanting", 1, true) or string.find(nameLower, "spellfire", 1, true) then
        return "ENCHANTING_BAG", Categories.SPECIAL_CONTAINERS.ENCHANTING_BAG
    end

    return nil
end

-- =========================================================================
-- ITEM CLASSIFICATION
-- =========================================================================

-- Classifies an item into priority category (1..8) and returns sort key metadata
function Categories:ClassifyItem(bagID, slotID)
    local texture, itemCount, locked, quality = GetContainerItemInfo(bagID, slotID)
    if not texture then
        return Categories.PRIORITY.EMPTY, "Empty Slot", 0, 0, ""
    end

    local itemLink = GetContainerItemLink(bagID, slotID)
    if not itemLink then
        return Categories.PRIORITY.MISC, "Unknown", quality or 1, 0, ""
    end

    -- Extract Item ID
    local _, _, itemIDStr = string.find(itemLink, "item:(%d+)")
    local itemID = tonumber(itemIDStr) or 0

    -- Query GetItemInfo (Vanilla 1.12.1 returns 9 values)
    local itemName, _, itemQuality, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTex = GetItemInfo(itemLink)
    
    itemName = itemName or ("Item #" .. itemID)
    itemQuality = itemQuality or quality or 1
    itemMinLevel = itemMinLevel or 0
    itemType = itemType or ""
    itemSubType = itemSubType or ""
    itemEquipLoc = itemEquipLoc or ""

    -- 1. Junk / Poor Quality (Grey)
    if itemQuality == 0 then
        return Categories.PRIORITY.JUNK, itemName, itemQuality, itemMinLevel, itemType
    end

    -- 2. Quest Items
    if itemType == "Quest" or itemQuality == 4 and string.find(string.lower(itemName), "quest", 1, true) then
        return Categories.PRIORITY.QUEST, itemName, itemQuality, itemMinLevel, itemType
    end

    -- Special Utility Item Check: Hearthstone & Primary Keys/Tools
    local nameLower = string.lower(itemName)
    if nameLower == "hearthstone" or nameLower == "skeleton key" or string.find(nameLower, "key", 1, true) or string.find(nameLower, "pick", 1, true) or string.find(nameLower, "knife", 1, true) or string.find(nameLower, "flint", 1, true) then
        return Categories.PRIORITY.UTILITY, itemName, itemQuality, itemMinLevel, itemType
    end

    -- 3. Consumables
    if itemType == "Consumable" or itemSubType == "Food & Drink" or itemSubType == "Potion" or itemSubType == "Elixir" or itemSubType == "Flask" or itemSubType == "Bandage" or itemSubType == "Scroll" then
        return Categories.PRIORITY.CONSUMABLE, itemName, itemQuality, itemMinLevel, itemType
    end

    -- 4. Recipes & Plans
    if itemType == "Recipe" or itemSubType == "Book" or string.find(nameLower, "recipe:", 1, true) or string.find(nameLower, "pattern:", 1, true) or string.find(nameLower, "plans:", 1, true) or string.find(nameLower, "schematic:", 1, true) or string.find(nameLower, "formula:", 1, true) or string.find(nameLower, "manual:", 1, true) then
        return Categories.PRIORITY.RECIPE, itemName, itemQuality, itemMinLevel, itemType
    end

    -- 5. Trade Goods & Crafting Reagents
    if itemType == "Trade Goods" or itemType == "Reagent" or itemSubType == "Cloth" or itemSubType == "Leather" or itemSubType == "Herb" or itemSubType == "Metal & Stone" or itemSubType == "Meat" or itemSubType == "Elemental" or itemSubType == "Parts" or itemSubType == "Enchanting" or itemSubType == "Jewelcrafting" then
        return Categories.PRIORITY.TRADE_GOODS, itemName, itemQuality, itemMinLevel, itemType
    end

    -- 6. Wearable Equipment (Weapons, Armor, Shields, Accessories)
    if itemType == "Armor" or itemType == "Weapon" or (itemEquipLoc and itemEquipLoc ~= "") then
        return Categories.PRIORITY.EQUIPMENT, itemName, itemQuality, itemMinLevel, itemType
    end

    -- 7. Miscellaneous
    return Categories.PRIORITY.MISC, itemName, itemQuality, itemMinLevel, itemType
end

-- =========================================================================
-- FREE SLOT BREAKDOWN TELEMETRY
-- =========================================================================

function Categories:GetFreeSlotSummary()
    local totalFree = 0
    local totalSlots = 0
    local regularFree = 0
    local regularTotal = 0
    local specialBreakdown = {}

    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        if numSlots > 0 then
            totalSlots = totalSlots + numSlots
            local bagFree = 0
            for slotID = 1, numSlots do
                local tex = GetContainerItemInfo(bagID, slotID)
                if not tex then
                    bagFree = bagFree + 1
                    totalFree = totalFree + 1
                end
            end

            local isSpecial, specInfo = self:GetSpecialContainerType(bagID)
            if isSpecial and specInfo then
                local shortName = specInfo.short or specInfo.name
                specialBreakdown[shortName] = (specialBreakdown[shortName] or 0) + bagFree
            else
                regularFree = regularFree + bagFree
                regularTotal = regularTotal + numSlots
            end
        end
    end

    -- Format summary string: "22 Free (4 Ammo, 2 Soul)" or "22 Free"
    local text = string.format("%d Free", totalFree)
    local parts = {}
    for specName, count in pairs(specialBreakdown) do
        if count > 0 then
            table.insert(parts, string.format("%d %s", count, specName))
        end
    end
    if table.getn(parts) > 0 then
        text = string.format("%d Free (%s)", totalFree, table.concat(parts, ", "))
    end

    return totalFree, totalSlots, text, specialBreakdown
end
