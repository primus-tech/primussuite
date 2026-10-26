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
-- Sorting Hierarchy:
-- Hearthstone -> Tradeskill Tools -> Quest Objects -> Bound Gear -> BoE Gear -> Consumables -> Mats -> White Things / Utility -> Trash / Grey
Categories.PRIORITY = {
    HEARTHSTONE = 1,  -- Hearthstone
    TOOLS       = 2,  -- Tradeskill & Profession Tools (Skinning Knife, Blacksmith Hammer, Mining Pick, etc.)
    QUEST       = 3,  -- Quest Items
    BOUND_GEAR  = 4,  -- Soulbound Equipment (Armor, Weapons, Trinkets, Rings, Shields)
    BOE_GEAR    = 5,  -- Bind on Equip / Unbound Equipment
    CONSUMABLE  = 6,  -- Food, Drink, Potions, Bandages, Elixirs, Flasks, Scrolls
    TRADE_GOODS = 7,  -- Cloth, Leather, Ore, Herbs, Gems, Meat, Elemental, Enchanting
    UTILITY     = 8,  -- White Things, Keys, Recipes, Manuals, Books, Common Misc
    JUNK        = 9,  -- Grey / Poor Quality Items (Trash)
    EMPTY       = 10, -- Free Unoccupied Slots
}

Categories.CATEGORY_NAMES = {
    [1] = "Hearthstone",
    [2] = "Tradeskill Tools",
    [3] = "Quest Items",
    [4] = "Soulbound Gear",
    [5] = "BoE Gear",
    [6] = "Consumables",
    [7] = "Trade Goods & Reagents",
    [8] = "Utility & Common Items",
    [9] = "Junk",
    [10] = "Free Slots",
}

Categories.CATEGORY_ICONS = {
    [1] = "Interface\\Icons\\INV_Misc_Rune_01",
    [2] = "Interface\\Icons\\INV_Hammer_20",
    [3] = "Interface\\Icons\\INV_Misc_Book_08",
    [4] = "Interface\\Icons\\INV_Chest_Chain",
    [5] = "Interface\\Icons\\INV_Sword_04",
    [6] = "Interface\\Icons\\INV_Potion_51",
    [7] = "Interface\\Icons\\INV_Fabric_Silk_02",
    [8] = "Interface\\Icons\\INV_Misc_Key_03",
    [9] = "Interface\\Icons\\INV_Misc_Ruin_01",
    [10] = "Interface\\Icons\\INV_Misc_QuestionMark",
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

-- Private Tooltip Scanner for Bag Item Flags
local scanTooltip = CreateFrame("GameTooltip", "PUIBags_CategoryScanTooltip", UIParent, "GameTooltipTemplate")
scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")

local function ScanBagItemFlags(bagID, slotID)
    local isSoulbound = false
    local isQuest = false

    scanTooltip:ClearLines()
    scanTooltip:SetBagItem(bagID, slotID)
    local numLines = scanTooltip:NumLines() or 0

    for i = 1, numLines do
        local leftLine = _G["PUIBags_CategoryScanTooltipTextLeft" .. i]
        if leftLine then
            local text = leftLine:GetText()
            if text then
                if text == ITEM_SOULBOUND or text == ITEM_BIND_ON_PICKUP or string.find(text, "Soulbound", 1, true) or string.find(text, "picked up", 1, true) then
                    isSoulbound = true
                end
                if text == ITEM_BIND_QUEST or string.find(text, "Quest Item", 1, true) or string.find(text, "Begin a Quest", 1, true) then
                    isQuest = true
                end
            end
        end
    end

    return isSoulbound, isQuest
end

-- =========================================================================
-- SPECIAL CONTAINER DETECTION & MATCHING
-- =========================================================================

-- Complete lookup of all Vanilla WoW 1.12.1 herbalism reagents
local HERB_NAMES = {
    ["peacebloom"] = true, ["silverleaf"] = true, ["earthroot"] = true,
    ["mageroyal"] = true, ["briarthorn"] = true, ["stranglekelp"] = true,
    ["bruiseweed"] = true, ["wild steelbloom"] = true, ["grave moss"] = true,
    ["kingsblood"] = true, ["liferoot"] = true, ["fadeleaf"] = true,
    ["goldthorn"] = true, ["khadgar's whisker"] = true, ["wintersbite"] = true,
    ["firebloom"] = true, ["purple lotus"] = true, ["arthas' tears"] = true,
    ["sungrass"] = true, ["blindweed"] = true, ["ghost mushroom"] = true,
    ["gromsblood"] = true, ["golden sansam"] = true, ["dreamfoil"] = true,
    ["mountain silversage"] = true, ["plaguebloom"] = true, ["icecap"] = true,
    ["black lotus"] = true, ["bloodvine"] = true,
}

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

    -- Tooltip line scan for 100% accurate container type identification
    scanTooltip:ClearLines()
    scanTooltip:SetInventoryItem("player", invSlot)
    local numLines = scanTooltip:NumLines() or 0
    local fullTooltipText = ""
    for i = 1, numLines do
        local leftLine = _G["PUIBags_CategoryScanTooltipTextLeft" .. i]
        if leftLine then
            local t = leftLine:GetText()
            if t then
                fullTooltipText = fullTooltipText .. " " .. string.lower(t)
            end
        end
    end

    if nameLower == "" then
        local line1 = _G["PUIBags_CategoryScanTooltipTextLeft1"]
        nameLower = line1 and string.lower(line1:GetText() or "") or ""
    end

    -- Explicit exclusions for regular bags that might contain "pouch" or similar
    if nameLower == "small brown pouch" or nameLower == "small pouch" then
        return nil
    end

    -- 1. Quiver
    if subLower == "quiver" or string.find(subLower, "quiver", 1, true) or string.find(nameLower, "quiver", 1, true) or string.find(fullTooltipText, "quiver", 1, true) then
        return "QUIVER", Categories.SPECIAL_CONTAINERS.QUIVER
    end

    -- 2. Ammo Pouch (Bullets/Shot)
    if subLower == "ammo pouch" or string.find(subLower, "ammo", 1, true) or string.find(nameLower, "ammo pouch", 1, true) or string.find(nameLower, "bandolier", 1, true) or string.find(fullTooltipText, "ammo pouch", 1, true) then
        return "AMMO_POUCH", Categories.SPECIAL_CONTAINERS.AMMO_POUCH
    end

    -- 3. Soul Bag (Warlock Soul Shards)
    if subLower == "soul bag" or string.find(subLower, "soul", 1, true) or string.find(nameLower, "soul", 1, true) or string.find(nameLower, "felcloth bag", 1, true) or string.find(nameLower, "box of souls", 1, true) or string.find(fullTooltipText, "soul bag", 1, true) then
        return "SOUL_BAG", Categories.SPECIAL_CONTAINERS.SOUL_BAG
    end

    -- 4. Herb Bag
    if subLower == "herb bag" or string.find(subLower, "herb", 1, true) or string.find(nameLower, "herb bag", 1, true) or string.find(nameLower, "cenarion", 1, true) or string.find(fullTooltipText, "herb bag", 1, true) then
        return "HERB_BAG", Categories.SPECIAL_CONTAINERS.HERB_BAG
    end

    -- 5. Mining Bag / Sack
    if subLower == "mining bag" or string.find(subLower, "mining", 1, true) or string.find(nameLower, "mining bag", 1, true) or string.find(nameLower, "mining sack", 1, true) or string.find(nameLower, "mammoth", 1, true) or string.find(fullTooltipText, "mining bag", 1, true) or string.find(fullTooltipText, "mining sack", 1, true) then
        return "MINING_BAG", Categories.SPECIAL_CONTAINERS.MINING_BAG
    end

    -- 6. Enchanting Bag
    if subLower == "enchanting bag" or string.find(subLower, "enchanting", 1, true) or string.find(nameLower, "enchanting bag", 1, true) or string.find(nameLower, "spellfire", 1, true) or string.find(fullTooltipText, "enchanting bag", 1, true) then
        return "ENCHANTING_BAG", Categories.SPECIAL_CONTAINERS.ENCHANTING_BAG
    end

    return nil
end

-- Checks if an item belongs in a specialized container type
function Categories:GetItemSpecialContainerType(itemLink, itemName, itemType, itemSubType, itemID)
    if not itemLink and not itemID then return nil end
    local name = itemName or ""
    local iType = itemType or ""
    local sType = itemSubType or ""
    local nameLower = string.lower(name)
    local subLower = string.lower(sType)

    -- 1. Quivers (Arrows only)
    if subLower == "arrow" or string.find(nameLower, "arrow", 1, true) or nameLower == "doomshot" then
        return "QUIVER"
    end

    -- 2. Ammo Pouches (Bullets / Shot only)
    if (subLower == "bullet" or string.find(nameLower, "shot", 1, true) or string.find(nameLower, "bullet", 1, true) or string.find(nameLower, "shell", 1, true) or string.find(nameLower, "cannon ball", 1, true)) and nameLower ~= "doomshot" then
        return "AMMO_POUCH"
    end

    -- 3. Soul Bags (Soul Shards only)
    if itemID == 6265 or nameLower == "soul shard" or string.find(nameLower, "soul shard", 1, true) then
        return "SOUL_BAG"
    end

    -- 4. Herb Bags (Herbs only)
    if HERB_NAMES[nameLower] or subLower == "herb" or subLower == "herbalism" or string.find(subLower, "herb", 1, true) then
        return "HERB_BAG"
    end
    if (iType == "Trade Goods" or iType == "Reagent" or iType == "") and (string.find(nameLower, "leaf", 1, true) or string.find(nameLower, "bloom", 1, true) or string.find(nameLower, "lotus", 1, true) or string.find(nameLower, "weed", 1, true) or string.find(nameLower, "kelp", 1, true) or string.find(nameLower, "grass", 1, true)) then
        return "HERB_BAG"
    end

    -- 5. Mining Bags (Ore, Stone, Metal, Bars, Gems)
    if subLower == "metal & stone" or subLower == "mining" or string.find(subLower, "stone", 1, true) or string.find(subLower, "metal", 1, true) then
        return "MINING_BAG"
    end
    if (iType == "Trade Goods" or iType == "") and (string.find(nameLower, "ore", 1, true) or string.find(nameLower, "bar", 1, true) or string.find(nameLower, "stone", 1, true) or string.find(nameLower, "nugget", 1, true)) then
        return "MINING_BAG"
    end

    -- 6. Enchanting Bags (Dust, Essence, Shard, Crystal, Rod)
    if subLower == "enchanting" or string.find(subLower, "enchanting", 1, true) then
        return "ENCHANTING_BAG"
    end
    if (iType == "Trade Goods" or iType == "") and (string.find(nameLower, "dust", 1, true) or string.find(nameLower, "essence", 1, true) or string.find(nameLower, "shard", 1, true) or string.find(nameLower, "nexus crystal", 1, true)) and nameLower ~= "soul shard" then
        return "ENCHANTING_BAG"
    end

    return nil
end

-- =========================================================================
-- TRADESKILL & PROFESSION TOOLS DEFINITIONS
-- =========================================================================

local TRADESKILL_TOOL_IDS = {
    [7005]  = true, -- Skinning Knife
    [12709] = true, -- Pip's Skinner
    [19727] = true, -- Finkle's Skinner
    [5956]  = true, -- Blacksmith Hammer
    [2901]  = true, -- Mining Pick
    [1819]  = true, -- Mining Pick
    [6219]  = true, -- Arclight Spanner
    [10498] = true, -- Gyromatic Micro-Adjustor
    [6218]  = true, -- Runed Copper Rod
    [6339]  = true, -- Runed Silver Rod
    [11130] = true, -- Runed Golden Rod
    [11145] = true, -- Runed Truesilver Rod
    [16207] = true, -- Runed Arcanite Rod
    [9149]  = true, -- Philosopher's Stone
    [13503] = true, -- Alchemist's Stone
    [4471]  = true, -- Flint and Tinder
    [5060]  = true, -- Thieves' Tools
    [6256]  = true, -- Fishing Pole
    [6365]  = true, -- Strong Fishing Pole
    [6367]  = true, -- Big Iron Fishing Pole
    [19970] = true, -- Nat Pagle's Extreme Angler FC-5000
    [12225] = true, -- Blix's Eyesore Rod
}

local function IsTradeskillTool(itemID, nameLower, itemSubType)
    if itemID and TRADESKILL_TOOL_IDS[itemID] then return true end
    local subLower = string.lower(itemSubType or "")
    if subLower == "fishing poles" or string.find(subLower, "fishing pole", 1, true) then
        return true
    end
    if string.find(nameLower, "skinning knife", 1, true)
        or string.find(nameLower, "blacksmith hammer", 1, true)
        or string.find(nameLower, "mining pick", 1, true)
        or string.find(nameLower, "arclight spanner", 1, true)
        or string.find(nameLower, "gyromatic", 1, true)
        or string.find(nameLower, "philosopher's stone", 1, true)
        or string.find(nameLower, "thieves' tools", 1, true)
        or string.find(nameLower, "flint and tinder", 1, true)
        or string.find(nameLower, "fishing pole", 1, true)
        or string.find(nameLower, "fishing rod", 1, true)
        or (string.find(nameLower, "runed ", 1, true) and string.find(nameLower, " rod", 1, true))
        or string.find(nameLower, "skinner", 1, true)
    then
        return true
    end
    return false
end

-- =========================================================================
-- ITEM CLASSIFICATION
-- =========================================================================

-- Classifies an item into priority category (1..9) and returns sort key metadata
function Categories:ClassifyItem(bagID, slotID)
    local texture, itemCount, locked, quality = GetContainerItemInfo(bagID, slotID)
    if not texture then
        return Categories.PRIORITY.EMPTY, "Empty Slot", 0, 0, "", false
    end

    local itemLink = GetContainerItemLink(bagID, slotID)
    if not itemLink then
        return Categories.PRIORITY.UTILITY, "Unknown", quality or 1, 0, "", false
    end

    -- Extract Item ID
    local _, _, itemIDStr = string.find(itemLink, "item:(%d+)")
    local itemID = tonumber(itemIDStr) or 0

    -- Query GetItemInfo (Vanilla 1.12.1 returns 9 values)
    local itemName, _, itemQuality, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTex = GetItemInfo(itemLink)
    
    itemName = itemName or ("Item #" .. itemID)
    if string.sub(itemName, 1, 6) == "Item #" then
        scanTooltip:ClearLines()
        scanTooltip:SetBagItem(bagID, slotID)
        local line1 = _G["PUIBags_CategoryScanTooltipTextLeft1"]
        local tipName = line1 and line1:GetText()
        if tipName and tipName ~= "" then
            itemName = tipName
        end
    end
    itemQuality = itemQuality or quality or 1
    itemMinLevel = itemMinLevel or 0
    itemType = itemType or ""
    itemSubType = itemSubType or ""
    itemEquipLoc = itemEquipLoc or ""

    local nameLower = string.lower(itemName)

    -- 1. Junk / Poor Quality (Grey) - always sorted to the end
    if itemQuality == 0 then
        return Categories.PRIORITY.JUNK, itemName, itemQuality, itemMinLevel, itemType, false
    end

    -- 2. Hearthstone (Highest priority, top-left of bags)
    if itemID == 6948 or nameLower == "hearthstone" or string.find(nameLower, "hearthstone", 1, true) then
        return Categories.PRIORITY.HEARTHSTONE, itemName, itemQuality, itemMinLevel, itemType, true
    end

    -- Scan tooltip flags for Soulbound and Quest
    local isSoulbound, isQuestTooltip = ScanBagItemFlags(bagID, slotID)

    -- 3. Tradeskill & Profession Tools (After Hearthstone, before Quest Objects)
    if IsTradeskillTool(itemID, nameLower, itemSubType) then
        return Categories.PRIORITY.TOOLS, itemName, itemQuality, itemMinLevel, itemType, isSoulbound
    end

    -- 4. Quest Items
    if itemType == "Quest" or isQuestTooltip or (itemQuality == 4 and string.find(nameLower, "quest", 1, true)) then
        return Categories.PRIORITY.QUEST, itemName, itemQuality, itemMinLevel, itemType, isSoulbound
    end

    -- 4. Equipment (Wearable Weapons, Armor, Shields, Accessories)
    local isEquip = (itemType == "Armor" or itemType == "Weapon" or (itemEquipLoc and itemEquipLoc ~= ""))
    if isEquip then
        if isSoulbound then
            return Categories.PRIORITY.BOUND_GEAR, itemName, itemQuality, itemMinLevel, itemType, true
        else
            return Categories.PRIORITY.BOE_GEAR, itemName, itemQuality, itemMinLevel, itemType, false
        end
    end

    -- 5. Consumables
    if itemType == "Consumable" or itemSubType == "Food & Drink" or itemSubType == "Potion" or itemSubType == "Elixir" or itemSubType == "Flask" or itemSubType == "Bandage" or itemSubType == "Scroll" then
        return Categories.PRIORITY.CONSUMABLE, itemName, itemQuality, itemMinLevel, itemType, isSoulbound
    end

    -- 6. Trade Goods & Crafting Reagents (Mats)
    if itemType == "Trade Goods" or itemType == "Reagent" or itemSubType == "Cloth" or itemSubType == "Leather" or itemSubType == "Herb" or itemSubType == "Metal & Stone" or itemSubType == "Meat" or itemSubType == "Elemental" or itemSubType == "Parts" or itemSubType == "Enchanting" or itemSubType == "Jewelcrafting" then
        return Categories.PRIORITY.TRADE_GOODS, itemName, itemQuality, itemMinLevel, itemType, isSoulbound
    end

    -- 7. White Things / Utility / Tools / Recipes / Miscellaneous Common Items
    return Categories.PRIORITY.UTILITY, itemName, itemQuality, itemMinLevel, itemType, isSoulbound
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
