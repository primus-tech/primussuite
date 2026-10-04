--[[
    PrimusLib: PUIBasePriceDB (Canonical Item Valuation & Price Database)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Acts as the centralized Core database for vendor sell & buy prices.
    Seamlessly integrates and unifies VanillaItemPrices, SellValue datasets,
    and built-in Vanilla 1.12.1 item economy baselines across all PrimusUI modules.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIBasePriceDB = Primus.PUIBasePriceDB or {}
Primus.PUIBasePriceDB = PUIBasePriceDB
_G.PUIBasePriceDB = PUIBasePriceDB

-- Direct bridge to VanillaItemPrices global dataset (13,321 items)
_G.VanillaItemPrices = _G.VanillaItemPrices or {}
local VanillaItemPrices = _G.VanillaItemPrices
PUIBasePriceDB.Data = VanillaItemPrices

-- Storage Tables
PUIBasePriceDB.SellPrices = PUIBasePriceDB.SellPrices or {}
PUIBasePriceDB.BuyPrices  = PUIBasePriceDB.BuyPrices or {}
PUIBasePriceDB.NameToID   = PUIBasePriceDB.NameToID or {}

local NameToID = PUIBasePriceDB.NameToID
local isIndexBuilt = false

local function BuildNameIndex()
    if isIndexBuilt then return end
    if Primus.PUIQuest and Primus.PUIQuest.DB and Primus.PUIQuest.DB["items"] and Primus.PUIQuest.DB["items"]["enUS"] then
        local enUS = Primus.PUIQuest.DB["items"]["enUS"]
        for id, name in pairs(enUS) do
            if type(name) == "string" and name ~= "" then
                local clean = string.lower(name)
                if not NameToID[clean] then
                    NameToID[clean] = id
                end
            end
        end
        isIndexBuilt = true
    end
end

-- =========================================================================
-- DATABASE ACCESSORS & NAME RESOLUTION
-- =========================================================================

function PUIBasePriceDB:GetItemID(itemOrName)
    if not itemOrName then return nil end
    if type(itemOrName) == "number" then return itemOrName end
    local _, _, idStr = string.find(itemOrName, "item:(%d+)")
    if idStr then return tonumber(idStr) end
    local num = tonumber(itemOrName)
    if num then return num end

    -- String / Name Resolution
    if type(itemOrName) == "string" and itemOrName ~= "" then
        local clean = string.gsub(itemOrName, "|c%x%x%x%x%x%x%x%x", "")
        clean = string.gsub(clean, "|r", "")
        clean = string.gsub(clean, "|H.-|h", "")
        clean = string.gsub(clean, "|h", "")
        clean = string.gsub(clean, "^%s*(.-)%s*$", "%1")
        clean = string.gsub(clean, "^%[(.-)%]$", "%1")
        local lower = string.lower(clean)

        if not isIndexBuilt then BuildNameIndex() end
        if NameToID[lower] then return NameToID[lower] end

        -- Client cache fallback
        local _, link = GetItemInfo(clean)
        if link then
            local _, _, idFromLink = string.find(link, "item:(%d+)")
            if idFromLink then
                local id = tonumber(idFromLink)
                NameToID[lower] = id
                return id
            end
        end
    end
    return nil
end

function PUIBasePriceDB:GetSellPrice(itemOrName)
    if not itemOrName then return nil end
    local itemID = self:GetItemID(itemOrName)
    if not itemID then return nil end

    if self.SellPrices[itemID] ~= nil then
        return self.SellPrices[itemID]
    end

    local vip = _G.VanillaItemPrices or VanillaItemPrices
    if vip and vip[itemID] ~= nil then
        local val = vip[itemID]
        if type(val) == "number" then
            return val
        elseif type(val) == "table" then
            return val.s or val.sell or val.sellPrice or val.price or val[1]
        end
    end

    return nil
end

function PUIBasePriceDB:GetBuyPrice(itemOrName)
    if not itemOrName then return nil end
    local itemID = self:GetItemID(itemOrName)
    if not itemID then return nil end

    if self.BuyPrices[itemID] ~= nil then
        return self.BuyPrices[itemID]
    end

    local vip = _G.VanillaItemPrices or VanillaItemPrices
    if vip and vip[itemID] ~= nil and type(vip[itemID]) == "table" then
        local val = vip[itemID]
        return val.b or val.buy or val.buyPrice or val[2]
    end

    return nil
end

function PUIBasePriceDB:RegisterSellPrice(itemID, price)
    if not itemID or not price then return end
    itemID = tonumber(itemID)
    price = tonumber(price)
    if itemID and price then
        self.SellPrices[itemID] = price
    end
end

function PUIBasePriceDB:RegisterBuyPrice(itemID, price)
    if not itemID or not price then return end
    itemID = tonumber(itemID)
    price = tonumber(price)
    if itemID and price then
        self.BuyPrices[itemID] = price
    end
end

function PUIBasePriceDB:Import(dataset)
    if type(dataset) ~= "table" then return 0 end
    local count = 0
    for k, v in pairs(dataset) do
        local id = tonumber(k)
        if id then
            if type(v) == "number" then
                self:RegisterSellPrice(id, v)
                count = count + 1
            elseif type(v) == "table" then
                local sPrice = v.s or v.sell or v.sellPrice or v.price or v[1]
                local bPrice = v.b or v.buy or v.buyPrice or v[2]
                if sPrice then self:RegisterSellPrice(id, sPrice) end
                if bPrice then self:RegisterBuyPrice(id, bPrice) end
                count = count + 1
            end
        end
    end
    return count
end

-- =========================================================================
-- STATIC BASELINE VENDOR SELL & BUY DATASET SEED
-- =========================================================================

-- Herbalism & Consumables
local SEED_SELL = {
    [765]   = 5,     -- Silverleaf
    [2447]  = 5,     -- Peacebloom
    [2449]  = 10,    -- Earthroot
    [785]   = 12,    -- Mageroyal
    [2450]  = 20,    -- Briarthorn
    [2452]  = 35,    -- Bruiseweed
    [3820]  = 35,    -- Stranglekelp
    [3355]  = 60,    -- Wild Steelbloom
    [3369]  = 75,    -- Grave Moss
    [3356]  = 100,   -- Kingsblood
    [3357]  = 125,   -- Liferoot
    [3818]  = 150,   -- Fadeleaf
    [3358]  = 175,   -- Khadgar's Whisker
    [3819]  = 200,   -- Wintersbite
    [4625]  = 250,   -- Firebloom
    [8831]  = 300,   -- Purple Lotus
    [8836]  = 350,   -- Arthas' Tears
    [8838]  = 400,   -- Sungrass
    [8839]  = 450,   -- Blindweed
    [8845]  = 500,   -- Ghost Mushroom
    [8846]  = 550,   -- Gromsblood
    [13463] = 600,   -- Golden Sansam
    [13464] = 700,   -- Dreamfoil
    [13465] = 800,   -- Mountain Silversage
    [13466] = 850,   -- Sorrowmoss
    [13467] = 900,   -- Icecap
    [13468] = 5000,  -- Black Lotus
    [2453]  = 1,     -- Minor Healing Potion
    [858]   = 60,    -- Lesser Healing Potion
    [929]   = 200,   -- Healing Potion
    [1710]  = 750,   -- Greater Healing Potion
    [3928]  = 2000,  -- Superior Healing Potion
    [13446] = 5000,  -- Major Healing Potion
    [2455]  = 12,    -- Minor Mana Potion
    [3385]  = 60,    -- Lesser Mana Potion
    [3827]  = 200,   -- Mana Potion
    [6149]  = 750,   -- Greater Mana Potion
    [13443] = 2000,  -- Superior Mana Potion
    [13444] = 5000,  -- Major Mana Potion
    [5634]  = 1000,  -- Free Action Potion
    [20008] = 3000,  -- Living Action Potion
    [2459]  = 250,   -- Swiftness Potion
    [9172]  = 1500,  -- Invisibility Potion
    [9030]  = 2000,  -- Restorative Potion
    [13452] = 4000,  -- Elixir of the Mongoose
    [9206]  = 1500,  -- Elixir of Giants
    [9187]  = 1200,  -- Elixir of Greater Agility
    [9264]  = 2000,  -- Elixir of Shadow Power
    [13454] = 4000,  -- Greater Arcane Elixir
    [13510] = 25000, -- Flask of the Titans
    [13511] = 25000, -- Flask of Distilled Wisdom
    [13512] = 25000, -- Flask of Supreme Power
    [13513] = 25000, -- Flask of Chromatic Resistance

    -- Mining, Bars & Gems
    [2770]  = 5,     -- Copper Ore
    [2840]  = 10,    -- Copper Bar
    [2835]  = 2,     -- Rough Stone
    [2771]  = 15,    -- Tin Ore
    [3576]  = 30,    -- Tin Bar
    [2836]  = 10,    -- Heavy Stone
    [2841]  = 50,    -- Bronze Bar
    [2775]  = 50,    -- Silver Ore
    [2842]  = 100,   -- Silver Bar
    [2772]  = 50,    -- Iron Ore
    [3575]  = 100,   -- Iron Bar
    [3859]  = 200,   -- Steel Bar
    [7912]  = 25,    -- Solid Stone
    [2776]  = 250,   -- Gold Ore
    [3577]  = 500,   -- Gold Bar
    [3858]  = 150,   -- Mithril Ore
    [3860]  = 300,   -- Mithril Bar
    [7911]  = 500,   -- Truesilver Ore
    [6037]  = 1000,  -- Truesilver Bar
    [12365] = 50,    -- Dense Stone
    [10620] = 400,   -- Thorium Ore
    [12359] = 800,   -- Thorium Bar
    [12360] = 12500, -- Arcanite Bar
    [12363] = 7500,  -- Arcane Crystal
    [11370] = 1000,  -- Dark Iron Ore
    [11371] = 2000,  -- Dark Iron Bar
    [818]   = 5,     -- Tigerseye
    [1210]  = 10,    -- Shadowgem
    [774]   = 10,    -- Malachite
    [1206]  = 25,    -- Moss Agate
    [1705]  = 50,    -- Lesser Moonstone
    [3864]  = 150,   -- Citrine
    [7909]  = 350,   -- Aquamarine
    [7910]  = 500,   -- Star Ruby
    [7971]  = 750,   -- Black Pearl
    [13926] = 1000,  -- Golden Pearl
    [12800] = 2000,  -- Azerothian Diamond
    [12799] = 1500,  -- Large Opal
    [12809] = 2000,  -- Blue Sapphire
    [12810] = 2500,  -- Huge Emerald
    [11754] = 5000,  -- Black Diamond
    [18335] = 15000, -- Pristine Black Diamond

    -- Cloth
    [2589]  = 13,    -- Linen Cloth
    [2996]  = 25,    -- Bolt of Linen Cloth
    [2592]  = 43,    -- Wool Cloth
    [2997]  = 100,   -- Bolt of Woolen Cloth
    [4306]  = 150,   -- Silk Cloth
    [4305]  = 600,   -- Bolt of Silk Cloth
    [4338]  = 375,   -- Mageweave Cloth
    [4337]  = 1500,  -- Bolt of Mageweave
    [14047] = 1000,  -- Runecloth
    [14048] = 5000,  -- Bolt of Runecloth
    [14256] = 2000,  -- Felcloth
    [14342] = 10000, -- Mooncloth

    -- Leather & Skins
    [2934]  = 1,     -- Ruined Leather Scraps
    [2318]  = 15,    -- Light Leather
    [2319]  = 40,    -- Medium Leather
    [4234]  = 150,   -- Heavy Leather
    [4304]  = 375,   -- Thick Leather
    [8170]  = 1000,  -- Rugged Leather
    [4232]  = 25,    -- Medium Hide
    [4235]  = 100,   -- Heavy Hide
    [8169]  = 250,   -- Thick Hide
    [8171]  = 750,   -- Rugged Hide
    [15407] = 5000,  -- Cured Rugged Hide
    [15417] = 2500,  -- Devilsaur Leather
    [17012] = 5000,  -- Core Leather
    [15419] = 2500,  -- Devilsaur Hide

    -- Enchanting
    [10940] = 7,     -- Strange Dust
    [11083] = 30,    -- Soul Dust
    [11137] = 125,   -- Vision Dust
    [11176] = 375,   -- Dream Dust
    [16204] = 1250,  -- Illusion Dust
    [10938] = 15,    -- Lesser Magic Essence
    [10939] = 50,    -- Greater Magic Essence
    [10998] = 75,    -- Lesser Astral Essence
    [11082] = 250,   -- Greater Astral Essence
    [11134] = 350,   -- Lesser Mystic Essence
    [11135] = 1000,  -- Greater Mystic Essence
    [11174] = 1250,  -- Lesser Nether Essence
    [11175] = 3750,  -- Greater Nether Essence
    [16202] = 4000,  -- Lesser Eternal Essence
    [16203] = 12000, -- Greater Eternal Essence
    [10978] = 50,    -- Small Glimmering Shard
    [11084] = 150,   -- Large Glimmering Shard
    [11138] = 400,   -- Small Glowing Shard
    [11139] = 1200,  -- Large Glowing Shard
    [11177] = 1500,  -- Small Radiant Shard
    [11178] = 4500,  -- Large Radiant Shard
    [14343] = 4000,  -- Small Brilliant Shard
    [14344] = 12000, -- Large Brilliant Shard
    [20725] = 25000, -- Nexus Crystal
    [12811] = 15000, -- Righteous Orb

    -- Food, Drink & Supplies
    [4540]  = 5,     -- Tough Jerky
    [4541]  = 20,    -- Freshly Baked Bread
    [4542]  = 100,   -- Moist Cornbread
    [4544]  = 300,   -- Mulgore Spice Bread
    [4601]  = 1000,  -- Soft Banana Bread
    [159]   = 1,     -- Refreshing Spring Water
    [1179]  = 5,     -- Ice Cold Milk
    [1205]  = 25,    -- Melon Juice
    [1708]  = 100,   -- Sweet Nectar
    [1645]  = 300,   -- Moonberry Juice
    [8766]  = 1000,  -- Morning Glory Dew
    [2512]  = 1,     -- Rough Arrow
    [2515]  = 4,     -- Sharp Arrow
    [3030]  = 15,    -- Razor Arrow
    [11285] = 50,    -- Jagged Arrow
    [19316] = 150,   -- Thorium Headed Arrow
    [2516]  = 1,     -- Light Shot
    [2519]  = 4,     -- Heavy Shot
    [3033]  = 15,    -- Solid Shot
    [11284] = 50,    -- Accurate Slugs
    [19317] = 150,   -- Thorium Shells
}

local SEED_BUY = {
    [159]   = 25,     -- Refreshing Spring Water
    [1179]  = 125,    -- Ice Cold Milk
    [1205]  = 250,    -- Melon Juice
    [1708]  = 500,    -- Sweet Nectar
    [1645]  = 1500,   -- Moonberry Juice
    [8766]  = 5000,   -- Morning Glory Dew
    [4540]  = 25,     -- Tough Jerky
    [4541]  = 100,    -- Freshly Baked Bread
    [4542]  = 500,    -- Moist Cornbread
    [4544]  = 1500,   -- Mulgore Spice Bread
    [4601]  = 5000,   -- Soft Banana Bread
    [2512]  = 10,     -- Rough Arrow
    [2515]  = 40,     -- Sharp Arrow
    [3030]  = 150,    -- Razor Arrow
    [11285] = 500,    -- Jagged Arrow
    [19316] = 1500,   -- Thorium Headed Arrow
    [2516]  = 10,     -- Light Shot
    [2519]  = 40,     -- Heavy Shot
    [3033]  = 150,    -- Solid Shot
    [11284] = 500,    -- Accurate Slugs
    [19317] = 1500,   -- Thorium Shells
    [17020] = 1000,   -- Arcane Powder
    [17031] = 1000,   -- Wild Thornroot
    [17032] = 1000,   -- Wild Berries
    [17033] = 2000,   -- Ironwood Seed
    [17034] = 2000,   -- Maple Seed
    [17035] = 1000,   -- Stranglethorn Seed
    [17036] = 1000,   -- Ashwood Seed
    [17037] = 1000,   -- Hornbeam Seed
    [17038] = 1000,   -- Ironwood Tree Seed
    [17056] = 2000,   -- Light Feather
    [17057] = 2000,   -- Fish Oil
    [17058] = 4000,   -- Shiny Fish Scales
    [17030] = 2000,   -- Ankh
    [17028] = 2000,   -- Holy Candle
    [17029] = 10000,  -- Sacred Candle
    [17026] = 1000,   -- Symbol of Divinity
    [21177] = 2000,   -- Symbol of Kings
    [17039] = 10000,  -- Rune of Teleportation
    [17040] = 20000,  -- Rune of Portals
    [5173]  = 10,     -- Flash Powder
    [5174]  = 100,    -- Blinding Powder
    [5060]  = 2500,   -- Thieves' Tools
    [16583] = 10000,  -- Infernal Stone
    [16584] = 15000,  -- Demonic Figurine
    [5956]  = 500,    -- Blacksmith Hammer
    [2901]  = 1000,   -- Mining Pick
    [7005]  = 1000,   -- Skinning Knife
    [6256]  = 250,    -- Fishing Pole
    [6365]  = 5000,   -- Strong Fishing Pole
    [4470]  = 100,    -- Simple Wood
    [4471]  = 500,    -- Flint and Tinder
    [2320]  = 10,     -- Coarse Thread
    [2321]  = 100,    -- Fine Thread
    [4291]  = 500,    -- Silken Thread
    [8343]  = 2000,   -- Heavy Silken Thread
    [14341] = 5000,   -- Rune Thread
    [2324]  = 100,    -- Bleach
    [2325]  = 250,    -- Black Dye
    [2604]  = 100,    -- Red Dye
    [2605]  = 250,    -- Green Dye
    [4357]  = 500,    -- Rough Blasting Powder
    [4360]  = 1000,   -- Heavy Blasting Powder
    [4377]  = 2000,   -- Solid Blasting Powder
    [10505] = 4000,   -- Dense Blasting Powder
    [3371]  = 150,    -- Empty Vial
    [3372]  = 400,    -- Leaded Vial
    [8925]  = 1000,   -- Crystal Vial
    [2678]  = 50,     -- Mild Spices
    [30817] = 200,    -- Simple Flour
    [4496]  = 500,    -- Small Brown Pouch
    [4497]  = 2500,   -- Heavy Brown Bag
    [4498]  = 10000,  -- Brown Leather Satchel
    [4499]  = 50000,  -- Huge Brown Sack
    [4500]  = 100000, -- Travelers Backpack
}

for id, price in pairs(SEED_SELL) do
    PUIBasePriceDB.SellPrices[id] = price
end

for id, price in pairs(SEED_BUY) do
    PUIBasePriceDB.BuyPrices[id] = price
end
