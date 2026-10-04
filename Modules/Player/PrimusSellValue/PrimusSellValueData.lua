--[[
    PrimusUI: PUISellValue Static Tier 1 Database
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Fast numeric key-value store (itemID -> copperPrice) seeded with standard
    Vanilla 1.12.1 items, trade goods, herbs, ores, gems, potions, and equipment.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUISellValue = Primus.PUISellValue or {}
Primus.PUISellValue = PUISellValue
_G.PUISellValue = PUISellValue

PUISellValue.StaticDB = PUISellValue.StaticDB or {
    -- =========================================================================
    -- HERBALISM & REAGENTS
    -- =========================================================================
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

    -- =========================================================================
    -- MINING, ORES, BARS & GEMS
    -- =========================================================================
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

    -- =========================================================================
    -- CLOTH & TAILORING REAGENTS
    -- =========================================================================
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

    -- =========================================================================
    -- LEATHERWORKING & SKINS
    -- =========================================================================
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

    -- =========================================================================
    -- ENCHANTING REAGENTS
    -- =========================================================================
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

    -- =========================================================================
    -- ELEMENTAL & CRAFTING COMPONENTS
    -- =========================================================================
    [7067]  = 500,   -- Elemental Water
    [7068]  = 500,   -- Elemental Fire
    [7069]  = 500,   -- Elemental Air
    [7078]  = 500,   -- Elemental Earth
    [7076]  = 1500,  -- Core of Earth
    [7077]  = 1500,  -- Heart of Fire
    [7080]  = 1500,  -- Globe of Water
    [7082]  = 1500,  -- Breath of Wind
    [12803] = 4500,  -- Essence of Water
    [12804] = 3000,  -- Essence of Undeath
    [12805] = 3000,  -- Living Essence
    [7081]  = 4500,  -- Essence of Air
    [12808] = 4500,  -- Essence of Earth
    [17011] = 5000,  -- Lava Core
    [17010] = 5000,  -- Fiery Core
    [18567] = 50000, -- Elementium Ore
    [18562] = 100000,-- Elementium Bar
    [18563] = 50000, -- Bindings of the Windseeker (Left)
    [18564] = 50000, -- Bindings of the Windseeker (Right)

    -- =========================================================================
    -- FOOD, DRINK, REAGENTS & AMMUNITION
    -- =========================================================================
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
    [17020] = 250,   -- Arcane Powder
    [17031] = 250,   -- Wild Thornroot
    [17032] = 250,   -- Wild Berries
    [17033] = 500,   -- Ironwood Seed
    [17034] = 500,   -- Maple Seed
    [17035] = 250,   -- Stranglethorn Seed
    [17036] = 250,   -- Ashwood Seed
    [17037] = 250,   -- Hornbeam Seed
    [17038] = 250,   -- Ironwood Tree Seed
    [17056] = 500,   -- Light Feather
    [17057] = 500,   -- Fish Oil
    [17058] = 1000,  -- Shiny Fish Scales

    -- =========================================================================
    -- VENDOR TRASH & COMMON GREY JUNK
    -- =========================================================================
    [7073]  = 12,    -- Broken Fang
    [7074]  = 45,    -- Large Fang
    [4865]  = 65,    -- Sharp Claw
    [4867]  = 15,    -- Soft Fur
    [4869]  = 80,    -- Thick Fur
    [3770]  = 5,     -- Mutton Chop
    [3771]  = 20,    -- Wild Hog Shank
    [7075]  = 100,   -- Wicked Claw
    [4470]  = 10,    -- Small Silk Pack
    [4496]  = 50,    -- Small Brown Pouch
    [4497]  = 100,   -- Heavy Brown Bag
    [4498]  = 250,   -- Brown Leather Satchel
    [4499]  = 500,   -- Huge Brown Sack
    [4500]  = 1000,  -- Travelers Backpack
    [828]   = 4,     -- Rabbit Foot
    [756]   = 8,     -- Ruined Pelt
    [755]   = 25,    -- Light Hide
    [4863]  = 30,    -- Restless Bones
    [5134]  = 85,    -- Severed Talon
    [5135]  = 120,   -- Fine Pointed Talon
    [5136]  = 250,   -- Razor Sharp Talon
    [1529]  = 35,    -- Small Venom Sac
    [1288]  = 150,   -- Large Venom Sac
    [3172]  = 350,   -- Giant Venom Sac
    [1475]  = 50,    -- Spider Webbing
    [10285] = 1200,  -- Shadow Silk
    [14227] = 2500,  -- Ironweb Spider Silk

    -- =========================================================================
    -- ICONIC EQUIPMENT & GEAR
    -- =========================================================================
    [19019] = 200000,-- Thunderfury, Blessed Blade of the Windseeker
    [17182] = 250000,-- Sulfuras, Hand of Ragnaros
    [22589] = 300000,-- Atiesh, Greatstaff of the Guardian
    [19375] = 95000, -- Mish'undare, Circlet of the Mind Flayer
    [19379] = 87500, -- Neltharion's Tear
    [19382] = 92000, -- Pure Elementium Band
    [19364] = 98000, -- Ashkandi, Greatsword of the Brotherhood
    [19334] = 88000, -- The Untamed Blade
    [19351] = 95000, -- Maladath, Runed Blade of the Black Flight
    [19352] = 92000, -- Chromatically Tempered Sword
    [19355] = 91000, -- Shadow Wing Focus Staff
    [19360] = 89000, -- Lok'amir il Romathis
    [19363] = 96000, -- Crul'shorukh, Edge of Chaos
    [18803] = 75000, -- Finkle's Lava Dredger
    [17075] = 68000, -- Vis'kag the Bloodletter
    [17076] = 72000, -- Bonereaver's Edge
    [17103] = 65000, -- Azuresong Mageblade
    [17105] = 67000, -- Aurastone Hammer
    [17109] = 69000, -- Gutgore Ripper
    [17111] = 71000, -- Spinal Reaper
    [17104] = 68000, -- Spinebreaker
    [18816] = 74000, -- Perdition's Blade
    [18822] = 76000, -- Obsidian Edged Blade
    [19321] = 85000, -- The Black Book
    [19376] = 90000, -- Archimtiros' Ring of Reckoning
    [19377] = 90000, -- Prestor's Talisman of Concurrency
    [19380] = 88000, -- Boots of the Shadow Flame
    [19387] = 89000, -- Chromatic Boots
    [19395] = 91000, -- Rejuvenating Gem
    [19407] = 94000, -- Ebony Flame Gloves
    [19434] = 85000, -- Band of Dark Dominion
    [19438] = 87000, -- Ring of Blackrock
    [19439] = 88000, -- Interlaced Shadow Jerkin
    [19436] = 86000, -- Cloak of the Brood Lord
    [19430] = 85000, -- Heartstriker
    [19431] = 86000, -- Dragonbreath Hand Cannon
    [19432] = 87000, -- Circle of Applied Metaphysics
    [19433] = 88000, -- Emberweave Leggings
    [19437] = 89000, -- Boots of the Pure Thought
    [21126] = 120000,-- Staff of the Shadow Flame
    [21128] = 115000,-- Claw of the Chromaggus
    [21134] = 125000,-- Dark Edge of Insanity
    [21183] = 110000,-- Eye of C'Thun
    [21214] = 130000,-- Gauntlets of Annihilation
    [21370] = 118000,-- Death's Bargain
    [21499] = 122000,-- Vestments of the Shifting Sands
    [21501] = 119000,-- Runes of the Guard Captain
    [22798] = 145000,-- Might of Menethil
    [22802] = 140000,-- Kingsfall
    [22800] = 138000,-- Brimstone Staff
    [22801] = 135000,-- The Castigator
    [22803] = 139000,-- Soulstring
    [22804] = 142000,-- The Hungering Cold
    [22806] = 140000,-- Widows Remorse
    [22807] = 136000,-- Severance
    [22808] = 138000,-- Iblis, Blade of the Fallen Seraph
    [22809] = 141000,-- Maexxna's Femur
    [22810] = 137000,-- Gressil, Dawn of Ruin
    [22811] = 143000,-- Nerubian Slavemaker
    [22812] = 139000,-- Doomfinger
    [22813] = 140000,-- Claymore of Unholy Might
    [22814] = 135000,-- Corrupted Ashbringer
    [22815] = 142000,-- Kiss of the Spider
    [22818] = 140000,-- The Restrained Essence of Sapphiron
    [22820] = 145000,-- Wand of the Whispering Dead
    [22821] = 142000,-- Eye of Diminution
}

-- =========================================================================
-- VENDOR BUY PRICES (STATIC BASELINE FOR COMMON MERCHANT GOODS)
-- =========================================================================
PUISellValue.BuyStaticDB = PUISellValue.BuyStaticDB or {
    -- Drinks & Water
    [159]   = 25,     -- Refreshing Spring Water (5c sell -> 25c buy)
    [1179]  = 125,    -- Ice Cold Milk
    [1205]  = 250,    -- Melon Juice
    [1708]  = 500,    -- Sweet Nectar
    [1645]  = 1500,   -- Moonberry Juice
    [8766]  = 5000,   -- Morning Glory Dew

    -- Food & Bread
    [4540]  = 25,     -- Tough Jerky
    [4541]  = 100,    -- Freshly Baked Bread
    [4542]  = 500,    -- Moist Cornbread
    [4544]  = 1500,   -- Mulgore Spice Bread
    [4601]  = 5000,   -- Soft Banana Bread

    -- Hunter Ammunition
    [2512]  = 10,     -- Rough Arrow (x200 = 20s)
    [2515]  = 40,     -- Sharp Arrow (x200 = 80s)
    [3030]  = 150,    -- Razor Arrow (x200 = 3g)
    [11285] = 500,    -- Jagged Arrow (x200 = 10g)
    [19316] = 1500,   -- Thorium Headed Arrow
    [2516]  = 10,     -- Light Shot (x200 = 20s)
    [2519]  = 40,     -- Heavy Shot (x200 = 80s)
    [3033]  = 150,    -- Solid Shot (x200 = 3g)
    [11284] = 500,    -- Accurate Slugs (x200 = 10g)
    [19317] = 1500,   -- Thorium Shells

    -- Class Reagents
    [17020] = 1000,   -- Arcane Powder (Mage Arcane Intellect)
    [17031] = 1000,   -- Wild Thornroot (Druid Gift of the Wild)
    [17032] = 1000,   -- Wild Berries (Druid Mark of the Wild)
    [17033] = 2000,   -- Ironwood Seed (Druid Rebirth)
    [17034] = 2000,   -- Maple Seed
    [17035] = 1000,   -- Stranglethorn Seed
    [17036] = 1000,   -- Ashwood Seed
    [17037] = 1000,   -- Hornbeam Seed
    [17038] = 1000,   -- Ironwood Tree Seed
    [17056] = 2000,   -- Light Feather (Mage/Priest Slow Fall / Levitate)
    [17057] = 2000,   -- Fish Oil (Shaman Water Walking)
    [17058] = 4000,   -- Shiny Fish Scales (Shaman Water Breathing)
    [17030] = 2000,   -- Ankh (Shaman Reincarnation)
    [17028] = 2000,   -- Holy Candle (Priest Prayer of Fortitude)
    [17029] = 10000,  -- Sacred Candle (Priest Prayer of Spirit/Shadow)
    [17026] = 1000,   -- Symbol of Divinity (Paladin Divine Intervention)
    [21177] = 2000,   -- Symbol of Kings (Paladin Greater Blessing)
    [17039] = 10000,  -- Rune of Teleportation (Mage)
    [17040] = 20000,  -- Rune of Portals (Mage)
    [5173]  = 10,     -- Flash Powder (Rogue Vanish)
    [5174]  = 100,    -- Blinding Powder (Rogue Blind)
    [5060]  = 2500,   -- Thieves' Tools (Rogue Pick Lock)
    [16583] = 10000,  -- Infernal Stone (Warlock Inferno)
    [16584] = 15000,  -- Demonic Figurine (Warlock Doomguard)

    -- Profession Basics & Tools
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

    -- Vendor Bags
    [4496]  = 500,    -- Small Brown Pouch (6 slot = 5s)
    [4497]  = 2500,   -- Heavy Brown Bag (8 slot = 25s)
    [4498]  = 10000,  -- Brown Leather Satchel (10 slot = 1g)
    [4499]  = 50000,  -- Huge Brown Sack (12 slot = 5g)
    [4500]  = 100000, -- Travelers Backpack (14 slot = 10g)
}

