--[[
    PrimusUI Module: PUIMerchant (15-Second Patient Scanner Engine & Ingestion Pipeline)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    1. Server-Safe 15.0s Patient AH Scanner Loop (strictly respecting OctoWoW DDoS rate limiters).
    2. Streaming Page-by-Page Ingestion (Zero memory backlog, zero frame freezes at scan finish).
    3. Real-time 1-second countdown updates for UI displays.
    4. Asynchronous page query watchdog (25.0s timeout with 3 retries).
    5. Automatic 3-way economy detection (Alliance / Horde / Neutral).
    6. Tier 2 Passive Browse Sniffer for organic auction browsing.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIMerchant = Primus.PUIMerchant or {}
Primus.PUIMerchant = PUIMerchant

local DB    = Primus.DB
local Utils = Primus.Utils
local Time  = Primus.Time
local Items = Primus.Items
local Widgets = Primus.Widgets

-- Scanner State Variables
local isScanning = false
local isPaused = false
local scanPage = 0
local totalPages = 1
local totalAuctionsCataloged = 0
local isWaitingForNextPage = false
local isWaitingForServerGate = false
local lastQueryTime = 0
local queryDispatchTime = 0
local pageCooldownEnd = 0
local pageRetries = 0
local maxRetries = 3
local currentScope = 0 -- 0 = All, 6 = Trade Goods, 4 = Consumables, 1 = Weapons, 2 = Armor
local measuredAvgCycleTime = 0
local measuredServerGate = 0
local pagesSampled = 0

-- Adaptive Step-Down Throttle Configuration
local PACING_PRESETS = {
    ["PATIENT"]  = 10.0,
    ["STANDARD"] = 5.0,
    ["FAST"]     = 2.5,
    ["TURBO"]    = 1.0,
}
local MIN_COOLDOWN_FLOOR = 1.0
local MAX_COOLDOWN_CEIL  = 12.0
local STEP_DOWN_DELTA    = 0.5  -- -0.5s after 2 consecutive clean pages
local STEP_UP_BACKOFF    = 2.5  -- +2.5s on throttle/retry
local currentEffectiveCooldown = 5.0
local consecutiveSuccessPages = 0

local SCAN_TIMEOUT = 25.0  -- 25-second watchdog for slow server responses

PUIMerchant.scannerState = {
    isScanning = false,
    isPaused = false,
    scanPage = 0,
    totalPages = 1,
    totalCataloged = 0,
    remainingCooldown = 0,
    currentCooldown = 5.0,
    measuredPageRate = 5.0,
    isWaitingServerGate = false,
    pacingMode = "ADAPTIVE",
    etaSeconds = 0,
    etaText = "--",
    statusText = "Ready",
}

-- Calculate Active Pacing Delay
function PUIMerchant:GetPacingDelay()
    local mode = self.db and self.db:Get("scanPacingMode", "ADAPTIVE") or "ADAPTIVE"
    if mode == "ADAPTIVE" then
        return currentEffectiveCooldown
    elseif PACING_PRESETS[mode] then
        return PACING_PRESETS[mode]
    else
        return 5.0
    end
end

-- Get Empirical Measured Speed (Real Server Roundtrip & Gate Rate)
function PUIMerchant:GetMeasuredPageRate()
    if measuredAvgCycleTime > 0 then
        return measuredAvgCycleTime
    end
    return self:GetPacingDelay()
end

-- Set User Pacing Preset
function PUIMerchant:SetPacingMode(mode)
    if not mode then mode = "ADAPTIVE" end
    if self.db then
        self.db:Set("scanPacingMode", mode)
    end
    if mode == "ADAPTIVE" then
        currentEffectiveCooldown = 5.0
        consecutiveSuccessPages = 0
    elseif PACING_PRESETS[mode] then
        currentEffectiveCooldown = PACING_PRESETS[mode]
    end
    PUIMerchant.scannerState.pacingMode = mode
    PUIMerchant.scannerState.currentCooldown = currentEffectiveCooldown
    if self.UpdateFlyoutScannerUI then
        self:UpdateFlyoutScannerUI()
    end
end

-- Step Down Delay on Consecutive Clean Pages
function PUIMerchant:StepDownCooldown()
    local mode = self.db and self.db:Get("scanPacingMode", "ADAPTIVE") or "ADAPTIVE"
    if mode ~= "ADAPTIVE" then return end

    consecutiveSuccessPages = consecutiveSuccessPages + 1
    if consecutiveSuccessPages >= 2 then
        consecutiveSuccessPages = 0
        if currentEffectiveCooldown > MIN_COOLDOWN_FLOOR then
            currentEffectiveCooldown = math.max(MIN_COOLDOWN_FLOOR, currentEffectiveCooldown - STEP_DOWN_DELTA)
        end
    end
end

-- Step Up Backoff on Throttle or Dropped Query
function PUIMerchant:StepUpBackoff()
    local mode = self.db and self.db:Get("scanPacingMode", "ADAPTIVE") or "ADAPTIVE"
    consecutiveSuccessPages = 0
    if mode == "ADAPTIVE" then
        currentEffectiveCooldown = math.min(MAX_COOLDOWN_CEIL, currentEffectiveCooldown + STEP_UP_BACKOFF)
    end
end

-- Format Seconds into Human-Readable ETA (e.g., 2h 15m or 4m 30s)
function PUIMerchant:FormatETA(seconds)
    seconds = seconds or 0
    if seconds <= 0 then return "0s" end
    if seconds >= 3600 then
        local hours = math.floor(seconds / 3600)
        local mins = math.floor(math.mod(seconds, 3600) / 60)
        return string.format("%dh %02dm", hours, mins)
    elseif seconds >= 60 then
        local mins = math.floor(seconds / 60)
        local secs = math.mod(seconds, 60)
        return string.format("%dm %02ds", mins, secs)
    else
        return string.format("%ds", seconds)
    end
end

-- Update scanner state snapshot for UI components
local function UpdateScannerState(statusMsg)
    PUIMerchant.scannerState.isScanning = isScanning
    PUIMerchant.scannerState.isPaused = isPaused
    PUIMerchant.scannerState.scanPage = scanPage
    PUIMerchant.scannerState.totalPages = totalPages
    PUIMerchant.scannerState.totalCataloged = totalAuctionsCataloged
    
    local now = GetTime()
    local rem = math.floor(pageCooldownEnd - now + 0.5)
    if rem < 0 then rem = 0 end
    PUIMerchant.scannerState.remainingCooldown = rem
    PUIMerchant.scannerState.currentCooldown = PUIMerchant:GetPacingDelay()
    PUIMerchant.scannerState.pacingMode = PUIMerchant.db and PUIMerchant.db:Get("scanPacingMode", "ADAPTIVE") or "ADAPTIVE"

    -- True Empirical Page Rate & Dynamic Real-World ETA
    local effectiveRate = PUIMerchant:GetPacingDelay()
    if measuredAvgCycleTime > 0 then
        effectiveRate = measuredAvgCycleTime
    end
    if measuredServerGate > effectiveRate then
        effectiveRate = measuredServerGate
    end

    local remainingPages = totalPages - scanPage
    if remainingPages < 0 then remainingPages = 0 end
    local totalEtaSeconds = math.ceil(remainingPages * effectiveRate)
    if not isScanning or scanPage == 0 then totalEtaSeconds = 0 end

    PUIMerchant.scannerState.measuredPageRate = effectiveRate
    PUIMerchant.scannerState.isWaitingServerGate = isWaitingForServerGate
    PUIMerchant.scannerState.etaSeconds = totalEtaSeconds
    PUIMerchant.scannerState.etaText = PUIMerchant:FormatETA(totalEtaSeconds)

    if statusMsg then
        PUIMerchant.scannerState.statusText = statusMsg
    end

    if PUIMerchant.UpdateFlyoutScannerUI then
        PUIMerchant:UpdateFlyoutScannerUI()
    end
end

-- Scope Variables
local currentScopeClass = 0      -- 0 = All, 1..10
local currentScopeSubClass = 0   -- 0 = All, 1..N
local currentScopeName = ""      -- Optional text search filter (e.g. "Leather", "Swiftthistle")
local currentScopeLabel = "All Categories"

-- =========================================================================
-- MASTER AUCTION HOUSE CATEGORY & SUB-CATEGORY REGISTRY
-- =========================================================================

PUIMerchant.CATEGORY_DATA = {
    {
        id = 0,
        name = "All Categories",
        icon = "Interface\\Icons\\INV_Misc_Book_09",
    },
    {
        id = 5,
        name = "Trade Goods",
        icon = "Interface\\Icons\\INV_Fabric_Silk_02",
        subclasses = {
            { id = 0, name = "All Trade Goods" },
            { id = 0, name = "Herbalism & Herbs", keyword = "Herb" },
            { id = 0, name = "Skinning & Leather", keyword = "Leather" },
            { id = 0, name = "Mining & Ores", keyword = "Ore" },
            { id = 0, name = "Metal Bars & Smelting", keyword = "Bar" },
            { id = 0, name = "Cloth & Tailoring Bolts", keyword = "Cloth" },
            { id = 0, name = "Enchanting Materials", keyword = "Dust" },
            { id = 0, name = "Elemental & Essences", keyword = "Essence" },
            { id = 1, name = "Parts & Devices" },
            { id = 2, name = "Explosives" },
            { id = 0, name = "Other Trade Goods" },
        }
    },
    {
        id = 4,
        name = "Consumables",
        icon = "Interface\\Icons\\INV_Potion_51",
        subclasses = {
            { id = 0, name = "All Consumables" },
            { id = 0, name = "Health Potions", keyword = "Health Potion" },
            { id = 0, name = "Mana Potions", keyword = "Mana Potion" },
            { id = 0, name = "All Potions & Elixirs", keyword = "Potion" },
            { id = 0, name = "Flasks", keyword = "Flask" },
            { id = 0, name = "Food & Drink" },
            { id = 0, name = "Bandages", keyword = "Bandage" },
            { id = 0, name = "Scrolls", keyword = "Scroll" },
            { id = 0, name = "Item Enhancements", keyword = "Stone" },
            { id = 0, name = "Other Consumables" },
        }
    },
    {
        id = 1,
        name = "Weapons",
        icon = "Interface\\Icons\\INV_Sword_04",
        subclasses = {
            { id = 0, name = "All Weapons" },
            { id = 8, name = "1H Swords (One-Handed)" },
            { id = 9, name = "2H Swords (Two-Handed)" },
            { id = 13, name = "Daggers" },
            { id = 1, name = "1H Axes" },
            { id = 2, name = "2H Axes" },
            { id = 5, name = "1H Maces" },
            { id = 6, name = "2H Maces" },
            { id = 7, name = "Polearms" },
            { id = 10, name = "Staves" },
            { id = 3, name = "Bows" },
            { id = 4, name = "Guns" },
            { id = 15, name = "Crossbows" },
            { id = 16, name = "Wands" },
            { id = 11, name = "Fist Weapons" },
            { id = 14, name = "Thrown" },
            { id = 17, name = "Fishing Poles" },
            { id = 12, name = "Miscellaneous Weapons" },
        }
    },
    {
        id = 2,
        name = "Armor",
        icon = "Interface\\Icons\\INV_Chest_Chain_05",
        subclasses = {
            { id = 0, name = "All Armor" },
            { id = 2, name = "Cloth Armor" },
            { id = 3, name = "Leather Armor" },
            { id = 4, name = "Mail Armor" },
            { id = 5, name = "Plate Armor" },
            { id = 6, name = "Shields" },
            { id = 7, name = "Librams / Idols / Totems" },
            { id = 1, name = "Miscellaneous Armor" },
        }
    },
    {
        id = 8,
        name = "Recipes",
        icon = "Interface\\Icons\\INV_Scroll_03",
        subclasses = {
            { id = 0, name = "All Recipes" },
            { id = 7, name = "Alchemy" },
            { id = 5, name = "Blacksmithing" },
            { id = 9, name = "Enchanting" },
            { id = 4, name = "Engineering" },
            { id = 2, name = "Leatherworking" },
            { id = 3, name = "Tailoring" },
            { id = 6, name = "Cooking" },
            { id = 8, name = "First Aid" },
            { id = 1, name = "Books" },
            { id = 10, name = "Fishing" },
        }
    },
    {
        id = 3,
        name = "Containers & Bags",
        icon = "Interface\\Icons\\INV_Misc_Bag_08",
        subclasses = {
            { id = 0, name = "All Bags" },
            { id = 1, name = "General Bags" },
            { id = 3, name = "Herb Bags" },
            { id = 4, name = "Enchanting Bags" },
            { id = 2, name = "Soul Bags" },
            { id = 5, name = "Engineering Bags" },
        }
    },
    {
        id = 6,
        name = "Projectiles & Ammo",
        icon = "Interface\\Icons\\INV_Ammo_Arrow_02",
        subclasses = {
            { id = 0, name = "All Projectiles" },
            { id = 1, name = "Arrows" },
            { id = 2, name = "Bullets" },
        }
    },
    {
        id = 7,
        name = "Quivers",
        icon = "Interface\\Icons\\INV_Misc_Bag_08",
    },
    {
        id = 9,
        name = "Quest Items",
        icon = "Interface\\Icons\\INV_Misc_QuestionMark",
    },
    {
        id = 10,
        name = "Miscellaneous",
        icon = "Interface\\Icons\\INV_Misc_Gear_01",
        subclasses = {
            { id = 0, name = "All Miscellaneous" },
            { id = 1, name = "Junk" },
            { id = 2, name = "Reagents" },
            { id = 3, name = "Pet" },
            { id = 4, name = "Holiday" },
            { id = 6, name = "Mount" },
            { id = 5, name = "Other" },
        }
    },
}

PUIMerchant.DROPDOWN_MENU_ITEMS = {
    -- Master / General
    { label = "All Categories (Full Scan)", classId = 0, subClassId = 0, keyword = "", icon = "Interface\\Icons\\INV_Misc_Book_09" },
    { label = "Active AH Browse Filter", isBrowse = true, icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
    { isSeparator = true },

    -- TRADE GOODS (Vanilla 1.12.1 Class 5)
    { isHeader = true, label = "TRADE GOODS", color = "ffd100" },
    { label = "All Trade Goods", classId = 5, subClassId = 0, keyword = "", icon = "Interface\\Icons\\INV_Fabric_Silk_02" },
    { label = "Metal Bars & Smelting", classId = 5, subClassId = 0, keyword = "Bar", icon = "Interface\\Icons\\INV_Ingot_Steel" },
    { label = "Mining & Ores", classId = 5, subClassId = 0, keyword = "Ore", icon = "Interface\\Icons\\INV_Ore_Iron_01" },
    { label = "Herbalism & Herbs", classId = 5, subClassId = 0, keyword = "Herb", icon = "Interface\\Icons\\INV_Misc_Herb_01" },
    { label = "Skinning & Leather", classId = 5, subClassId = 0, keyword = "Leather", icon = "Interface\\Icons\\INV_Misc_MonsterScales_01" },
    { label = "Cloth & Tailoring Bolts", classId = 5, subClassId = 0, keyword = "Cloth", icon = "Interface\\Icons\\INV_Fabric_Silk_02" },
    { label = "Enchanting Materials", classId = 5, subClassId = 0, keyword = "Dust", icon = "Interface\\Icons\\INV_Enchant_Disenchant" },
    { label = "Elemental & Essences", classId = 5, subClassId = 0, keyword = "Essence", icon = "Interface\\Icons\\Spell_Fire_Volcano" },
    { label = "Engineering Parts", classId = 5, subClassId = 1, keyword = "", icon = "Interface\\Icons\\INV_Gizmo_02" },
    { label = "Explosives", classId = 5, subClassId = 2, keyword = "", icon = "Interface\\Icons\\Spell_Fire_SelfDestruct" },
    { isSeparator = true },

    -- CONSUMABLES (Vanilla 1.12.1 Class 4)
    { isHeader = true, label = "CONSUMABLES", color = "ffd100" },
    { label = "All Consumables", classId = 4, subClassId = 0, keyword = "", icon = "Interface\\Icons\\INV_Potion_51" },
    { label = "Health Potions", classId = 4, subClassId = 0, keyword = "Health Potion", icon = "Interface\\Icons\\INV_Potion_52" },
    { label = "Mana Potions", classId = 4, subClassId = 0, keyword = "Mana Potion", icon = "Interface\\Icons\\INV_Potion_76" },
    { label = "All Potions & Elixirs", classId = 4, subClassId = 0, keyword = "Potion", icon = "Interface\\Icons\\INV_Potion_51" },
    { label = "Flasks", classId = 4, subClassId = 0, keyword = "Flask", icon = "Interface\\Icons\\INV_Potion_41" },
    { label = "Food & Drink", classId = 4, subClassId = 0, keyword = "", icon = "Interface\\Icons\\INV_Misc_Food_14" },
    { label = "Bandages", classId = 4, subClassId = 0, keyword = "Bandage", icon = "Interface\\Icons\\INV_Misc_Bandage_08" },
    { label = "Scrolls", classId = 4, subClassId = 0, keyword = "Scroll", icon = "Interface\\Icons\\INV_Scroll_02" },
    { label = "Item Enhancements", classId = 4, subClassId = 0, keyword = "Stone", icon = "Interface\\Icons\\INV_Stone_SharpeningStone_01" },
    { isSeparator = true },

    -- WEAPONS (GEAR) (Vanilla 1.12.1 Class 1)
    { isHeader = true, label = "WEAPONS (GEAR)", color = "ffd100" },
    { label = "All Weapons", classId = 1, subClassId = 0, keyword = "", icon = "Interface\\Icons\\INV_Sword_04" },
    { label = "1H Swords (One-Handed)", classId = 1, subClassId = 8, keyword = "", icon = "Interface\\Icons\\INV_Sword_04" },
    { label = "2H Swords (Two-Handed)", classId = 1, subClassId = 9, keyword = "", icon = "Interface\\Icons\\INV_Sword_39" },
    { label = "Daggers", classId = 1, subClassId = 13, keyword = "", icon = "Interface\\Icons\\INV_Weapon_ShortBlade_05" },
    { label = "1H Axes", classId = 1, subClassId = 1, keyword = "", icon = "Interface\\Icons\\INV_Axe_02" },
    { label = "2H Axes", classId = 1, subClassId = 2, keyword = "", icon = "Interface\\Icons\\INV_Axe_09" },
    { label = "1H Maces", classId = 1, subClassId = 5, keyword = "", icon = "Interface\\Icons\\INV_Mace_01" },
    { label = "2H Maces", classId = 1, subClassId = 6, keyword = "", icon = "Interface\\Icons\\INV_Mace_04" },
    { label = "Bows & Crossbows", classId = 1, subClassId = 3, keyword = "", icon = "Interface\\Icons\\INV_Weapon_Bow_05" },
    { label = "Guns", classId = 1, subClassId = 4, keyword = "", icon = "Interface\\Icons\\INV_Weapon_Rifle_01" },
    { label = "Staves", classId = 1, subClassId = 10, keyword = "", icon = "Interface\\Icons\\INV_Staff_08" },
    { label = "Polearms", classId = 1, subClassId = 7, keyword = "", icon = "Interface\\Icons\\INV_Spear_05" },
    { label = "Wands", classId = 1, subClassId = 16, keyword = "", icon = "Interface\\Icons\\INV_Wand_01" },
    { isSeparator = true },

    -- ARMOR (GEAR) (Vanilla 1.12.1 Class 2)
    { isHeader = true, label = "ARMOR (GEAR)", color = "ffd100" },
    { label = "All Armor", classId = 2, subClassId = 0, keyword = "", icon = "Interface\\Icons\\INV_Chest_Chain_05" },
    { label = "Cloth Armor", classId = 2, subClassId = 2, keyword = "", icon = "Interface\\Icons\\INV_Chest_Cloth_21" },
    { label = "Leather Armor", classId = 2, subClassId = 3, keyword = "", icon = "Interface\\Icons\\INV_Chest_Leather_09" },
    { label = "Mail Armor", classId = 2, subClassId = 4, keyword = "", icon = "Interface\\Icons\\INV_Chest_Chain_15" },
    { label = "Plate Armor", classId = 2, subClassId = 5, keyword = "", icon = "Interface\\Icons\\INV_Chest_Plate03" },
    { label = "Shields", classId = 2, subClassId = 6, keyword = "", icon = "Interface\\Icons\\INV_Shield_04" },
    { label = "Librams / Totems / Idols", classId = 2, subClassId = 7, keyword = "", icon = "Interface\\Icons\\INV_Misc_Book_11" },
    { isSeparator = true },

    -- RECIPES (Vanilla 1.12.1 Class 8)
    { isHeader = true, label = "RECIPES & PATTERNS", color = "ffd100" },
    { label = "All Recipes", classId = 8, subClassId = 0, keyword = "", icon = "Interface\\Icons\\INV_Scroll_03" },
    { label = "Alchemy Recipes", classId = 8, subClassId = 7, keyword = "", icon = "Interface\\Icons\\INV_Potion_51" },
    { label = "Blacksmithing Plans", classId = 8, subClassId = 5, keyword = "", icon = "Interface\\Icons\\INV_Hammer_16" },
    { label = "Enchanting Formulas", classId = 8, subClassId = 9, keyword = "", icon = "Interface\\Icons\\INV_Enchant_Disenchant" },
    { label = "Engineering Schematics", classId = 8, subClassId = 4, keyword = "", icon = "Interface\\Icons\\INV_Gizmo_02" },
    { label = "Leatherworking Patterns", classId = 8, subClassId = 2, keyword = "", icon = "Interface\\Icons\\INV_Misc_MonsterScales_01" },
    { label = "Tailoring Patterns", classId = 8, subClassId = 3, keyword = "", icon = "Interface\\Icons\\INV_Fabric_Silk_02" },
    { label = "Cooking Recipes", classId = 8, subClassId = 6, keyword = "", icon = "Interface\\Icons\\INV_Misc_Food_14" },
    { label = "First Aid Books", classId = 8, subClassId = 8, keyword = "", icon = "Interface\\Icons\\INV_Misc_Bandage_08" },
    { isSeparator = true },

    -- CONTAINERS & BAGS (Vanilla 1.12.1 Class 3)
    { isHeader = true, label = "CONTAINERS & BAGS", color = "ffd100" },
    { label = "All Bags", classId = 3, subClassId = 0, keyword = "", icon = "Interface\\Icons\\INV_Misc_Bag_08" },
    { label = "General Bags", classId = 3, subClassId = 1, keyword = "", icon = "Interface\\Icons\\INV_Misc_Bag_08" },
    { label = "Herb Bags", classId = 3, subClassId = 3, keyword = "", icon = "Interface\\Icons\\INV_Misc_Bag_14" },
    { label = "Enchanting Bags", classId = 3, subClassId = 4, keyword = "", icon = "Interface\\Icons\\INV_Misc_Bag_19" },
    { label = "Soul Bags", classId = 3, subClassId = 2, keyword = "", icon = "Interface\\Icons\\INV_Misc_Bag_10" },
}

function PUIMerchant:GetScopeIcon(classIdx, subClassIdx, nameFilter)
    classIdx = tonumber(classIdx) or 0
    subClassIdx = tonumber(subClassIdx) or 0
    nameFilter = nameFilter or ""

    if nameFilter == "Health Potion" then return "Interface\\Icons\\INV_Potion_52" end
    if nameFilter == "Mana Potion" then return "Interface\\Icons\\INV_Potion_76" end
    if nameFilter == "Flask" then return "Interface\\Icons\\INV_Potion_41" end
    if nameFilter == "Ore" then return "Interface\\Icons\\INV_Ore_Iron_01" end
    if nameFilter == "Bar" then return "Interface\\Icons\\INV_Ingot_Steel" end
    if nameFilter == "Herb" then return "Interface\\Icons\\INV_Misc_Herb_01" end
    if nameFilter == "Leather" then return "Interface\\Icons\\INV_Misc_MonsterScales_01" end
    if nameFilter == "Cloth" then return "Interface\\Icons\\INV_Fabric_Silk_02" end
    if nameFilter == "Dust" then return "Interface\\Icons\\INV_Enchant_Disenchant" end
    if nameFilter == "Essence" then return "Interface\\Icons\\Spell_Fire_Volcano" end
    if nameFilter == "Bandage" then return "Interface\\Icons\\INV_Misc_Bandage_08" end
    if nameFilter == "Scroll" then return "Interface\\Icons\\INV_Scroll_02" end
    if nameFilter == "Stone" then return "Interface\\Icons\\INV_Stone_SharpeningStone_01" end
    if nameFilter == "Potion" then return "Interface\\Icons\\INV_Potion_51" end

    if classIdx == 5 then -- Trade Goods
        if subClassIdx == 1 then return "Interface\\Icons\\INV_Gizmo_02" end
        if subClassIdx == 2 then return "Interface\\Icons\\Spell_Fire_SelfDestruct" end
        return "Interface\\Icons\\INV_Fabric_Silk_02"
    elseif classIdx == 4 then -- Consumables
        if subClassIdx == 1 then return "Interface\\Icons\\INV_Potion_51" end
        if subClassIdx == 2 then return "Interface\\Icons\\INV_Potion_41" end
        if subClassIdx == 3 then return "Interface\\Icons\\INV_Misc_Food_14" end
        if subClassIdx == 5 then return "Interface\\Icons\\INV_Misc_Bandage_08" end
        if subClassIdx == 4 then return "Interface\\Icons\\INV_Scroll_02" end
        if subClassIdx == 6 then return "Interface\\Icons\\INV_Stone_SharpeningStone_01" end
        return "Interface\\Icons\\INV_Potion_51"
    elseif classIdx == 1 then -- Weapons
        if subClassIdx == 8 then return "Interface\\Icons\\INV_Sword_04" end
        if subClassIdx == 9 then return "Interface\\Icons\\INV_Sword_39" end
        if subClassIdx == 13 then return "Interface\\Icons\\INV_Weapon_ShortBlade_05" end
        if subClassIdx == 1 or subClassIdx == 2 then return "Interface\\Icons\\INV_Axe_02" end
        if subClassIdx == 5 or subClassIdx == 6 then return "Interface\\Icons\\INV_Mace_01" end
        if subClassIdx == 3 or subClassIdx == 15 then return "Interface\\Icons\\INV_Weapon_Bow_05" end
        if subClassIdx == 4 then return "Interface\\Icons\\INV_Weapon_Rifle_01" end
        if subClassIdx == 10 then return "Interface\\Icons\\INV_Staff_08" end
        if subClassIdx == 7 then return "Interface\\Icons\\INV_Spear_05" end
        if subClassIdx == 16 then return "Interface\\Icons\\INV_Wand_01" end
        return "Interface\\Icons\\INV_Sword_04"
    elseif classIdx == 2 then -- Armor
        if subClassIdx == 2 then return "Interface\\Icons\\INV_Chest_Cloth_21" end
        if subClassIdx == 3 then return "Interface\\Icons\\INV_Chest_Leather_09" end
        if subClassIdx == 4 then return "Interface\\Icons\\INV_Chest_Chain_15" end
        if subClassIdx == 5 then return "Interface\\Icons\\INV_Chest_Plate03" end
        if subClassIdx == 6 then return "Interface\\Icons\\INV_Shield_04" end
        if subClassIdx == 7 then return "Interface\\Icons\\INV_Misc_Book_11" end
        return "Interface\\Icons\\INV_Chest_Chain_05"
    elseif classIdx == 8 then -- Recipes
        if subClassIdx == 7 then return "Interface\\Icons\\INV_Potion_51" end
        if subClassIdx == 5 then return "Interface\\Icons\\INV_Hammer_16" end
        if subClassIdx == 9 then return "Interface\\Icons\\INV_Enchant_Disenchant" end
        if subClassIdx == 4 then return "Interface\\Icons\\INV_Gizmo_02" end
        if subClassIdx == 2 then return "Interface\\Icons\\INV_Misc_MonsterScales_01" end
        if subClassIdx == 3 then return "Interface\\Icons\\INV_Fabric_Silk_02" end
        if subClassIdx == 6 then return "Interface\\Icons\\INV_Misc_Food_14" end
        if subClassIdx == 8 then return "Interface\\Icons\\INV_Misc_Bandage_08" end
        return "Interface\\Icons\\INV_Scroll_03"
    elseif classIdx == 3 then -- Containers & Bags
        if subClassIdx == 3 then return "Interface\\Icons\\INV_Misc_Bag_14" end
        if subClassIdx == 4 then return "Interface\\Icons\\INV_Misc_Bag_19" end
        if subClassIdx == 2 then return "Interface\\Icons\\INV_Misc_Bag_10" end
        return "Interface\\Icons\\INV_Misc_Bag_08"
    elseif classIdx == 6 then -- Projectiles & Ammo
        if subClassIdx == 1 then return "Interface\\Icons\\INV_Ammo_Arrow_02" end
        if subClassIdx == 2 then return "Interface\\Icons\\INV_Ammo_Bullet_01" end
        return "Interface\\Icons\\INV_Ammo_Arrow_02"
    end
    return "Interface\\Icons\\INV_Misc_Book_09"
end

function PUIMerchant:GetClassName(classIdx)
    classIdx = tonumber(classIdx) or 0
    for _, cat in ipairs(self.CATEGORY_DATA) do
        if cat.id == classIdx then
            return cat.name
        end
    end
    return (classIdx == 0) and "All Categories" or ("Category " .. classIdx)
end

function PUIMerchant:GetSubClassName(classIdx, subClassIdx)
    classIdx = tonumber(classIdx) or 0
    subClassIdx = tonumber(subClassIdx) or 0
    for _, cat in ipairs(self.CATEGORY_DATA) do
        if cat.id == classIdx and cat.subclasses then
            for _, sc in ipairs(cat.subclasses) do
                if sc.id == subClassIdx then
                    return sc.name
                end
            end
        end
    end
    return (subClassIdx == 0) and "All" or ("Subclass " .. subClassIdx)
end

function PUIMerchant:GetScopeLabel()
    return currentScopeLabel or "All Categories"
end

function PUIMerchant:GetScopeShortName()
    if currentScopeName and currentScopeName ~= "" then
        return currentScopeName
    elseif currentScopeSubClass > 0 then
        return self:GetSubClassName(currentScopeClass, currentScopeSubClass)
    elseif currentScopeClass > 0 then
        return self:GetClassName(currentScopeClass)
    else
        return "All"
    end
end

-- Get Category Scope Display Name (Backwards compatible)
function PUIMerchant:GetScopeName(scope)
    return self:GetClassName(scope)
end

-- Set Target Scan Scope
function PUIMerchant:SetScanScope(classIdx, subClassIdx, nameFilter, customLabel, customIcon)
    currentScopeClass = tonumber(classIdx) or 0
    currentScopeSubClass = tonumber(subClassIdx) or 0
    currentScopeName = nameFilter or ""
    
    if customLabel then
        currentScopeLabel = customLabel
    elseif currentScopeClass == 0 and (not currentScopeName or currentScopeName == "") then
        currentScopeLabel = "All Categories"
    elseif currentScopeName and currentScopeName ~= "" then
        if currentScopeClass > 0 then
            currentScopeLabel = string.format("%s: \"%s\"", self:GetClassName(currentScopeClass), currentScopeName)
        else
            currentScopeLabel = string.format("Search: \"%s\"", currentScopeName)
        end
    elseif currentScopeSubClass > 0 then
        currentScopeLabel = string.format("%s > %s", self:GetClassName(currentScopeClass), self:GetSubClassName(currentScopeClass, currentScopeSubClass))
    else
        currentScopeLabel = self:GetClassName(currentScopeClass)
    end

    PUIMerchant.scannerState.scopeClass = currentScopeClass
    PUIMerchant.scannerState.scopeSubClass = currentScopeSubClass
    PUIMerchant.scannerState.scopeName = currentScopeName
    PUIMerchant.scannerState.scopeLabel = currentScopeLabel

    if self.UpdateFlyoutScannerUI then
        self:UpdateFlyoutScannerUI()
    end
end

-- Open Interactive Scope Selection Context Menu
function PUIMerchant:OpenScopeCategoryMenu(anchor)
    local items = {
        { text = "SELECT AH SCAN CATEGORY", isTitle = true },
        {
            text = "🌐 All Categories (Full Scan)",
            func = function()
                PUIMerchant:SetScanScope(0, 0, "", "All Categories")
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIMerchant]: Target scan scope set to All Categories (Full AH).", "69ccf0"))
            end,
            checked = (currentScopeClass == 0 and (not currentScopeName or currentScopeName == "")),
        },
        { isSeparator = true },
    }

    for _, cat in ipairs(self.CATEGORY_DATA) do
        if cat.id > 0 then
            local cId = cat.id
            local cName = cat.name
            local cIcon = cat.icon
            local hasSub = cat.subclasses and table.getn(cat.subclasses) > 1

            table.insert(items, {
                text = cName,
                icon = cIcon,
                rightText = hasSub and "Sub-menus >" or "",
                func = function()
                    if hasSub then
                        PUIMerchant:OpenSubCategoryMenu(cId, anchor)
                    else
                        PUIMerchant:SetScanScope(cId, 0, "", cName)
                        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: Target scan scope set to %s.", cName), "69ccf0"))
                    end
                end,
                checked = (currentScopeClass == cId and currentScopeSubClass == 0 and (not currentScopeName or currentScopeName == "")),
            })
        end
    end

    table.insert(items, { isSeparator = true })
    table.insert(items, {
        text = "🎯 Use Current AH Browse Filter",
        func = function()
            PUIMerchant:UseBlizzardBrowseScope()
        end,
    })

    Widgets:ShowContextMenu(anchor, items)
end

-- Open Sub-Category Context Menu
function PUIMerchant:OpenSubCategoryMenu(classIdx, anchor)
    classIdx = tonumber(classIdx) or 0
    local cat = nil
    for _, c in ipairs(self.CATEGORY_DATA) do
        if c.id == classIdx then cat = c; break end
    end
    if not cat or not cat.subclasses then return end

    local items = {
        { text = string.upper(cat.name) .. " SUB-CATEGORIES", isTitle = true },
        {
            text = "📁 All " .. cat.name,
            icon = cat.icon,
            func = function()
                PUIMerchant:SetScanScope(classIdx, 0, "", cat.name)
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: Target scan scope set to All %s.", cat.name), "69ccf0"))
            end,
            checked = (currentScopeClass == classIdx and currentScopeSubClass == 0 and (not currentScopeName or currentScopeName == "")),
        },
        { isSeparator = true },
    }

    for _, sc in ipairs(cat.subclasses) do
        if sc.id > 0 or (sc.keyword and sc.keyword ~= "") then
            local scId = sc.id
            local scName = sc.name
            local scKw = sc.keyword or ""
            local label = string.format("%s > %s", cat.name, scName)
            table.insert(items, {
                text = scName,
                rightText = (scKw ~= "") and string.format("[\"%s\"]", scKw) or "",
                func = function()
                    PUIMerchant:SetScanScope(classIdx, scId, scKw, label)
                    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: Target scan scope set to %s.", label), "69ccf0"))
                end,
                checked = (currentScopeClass == classIdx and currentScopeSubClass == scId and (scKw == "" or currentScopeName == scKw)),
            })
        end
    end

    table.insert(items, { isSeparator = true })
    table.insert(items, {
        text = "« Back to All Categories",
        func = function()
            PUIMerchant:OpenScopeCategoryMenu(anchor)
        end,
    })

    Widgets:ShowContextMenu(anchor, items)
end

-- Use Blizzard Browse Selection
function PUIMerchant:UseBlizzardBrowseScope()
    local text = BrowseName and BrowseName:GetText() or ""
    text = Utils.Trim(text)

    if text ~= "" then
        PUIMerchant:SetScanScope(0, 0, text, string.format("Filter: \"%s\"", text))
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: Target scan scope set to search query \"%s\".", text), "69ccf0"))
    else
        PUIMerchant:SetScanScope(0, 0, "", "All Categories")
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIMerchant]: Target scan scope set to All Categories.", "69ccf0"))
    end
end

-- =========================================================================
-- SCAN CHECKPOINT MANAGEMENT
-- =========================================================================

function PUIMerchant:GetScanCheckpoint()
    if not self.db then return nil end
    local cp = self.db:Get("scanCheckpoint", nil)
    if cp and cp.page and cp.page > 0 then
        return cp
    end
    return nil
end

function PUIMerchant:SaveScanCheckpoint()
    if not self.db or not isScanning or scanPage <= 0 then return end
    self.db:Set("scanCheckpoint", {
        page = scanPage,
        totalPages = totalPages,
        totalCataloged = totalAuctionsCataloged,
        scopeClass = currentScopeClass,
        scopeSubClass = currentScopeSubClass,
        scopeName = currentScopeName,
        scopeLabel = currentScopeLabel,
        savedAt = Time:GetServerTimestamp(),
    })
end

function PUIMerchant:ClearScanCheckpoint()
    if self.db then
        self.db:Set("scanCheckpoint", nil)
    end
end

-- =========================================================================
-- START SCAN
-- =========================================================================

function PUIMerchant:StartScan(scopeClass, forceFresh, scopeSubClass, scopeName, customLabel)
    if not AuctionFrame or not AuctionFrame:IsShown() then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIMerchant]: Please open the Auction House to scan.", "ff5555"))
        return
    end

    if isScanning then
        if isPaused then
            self:ResumeScan()
        else
            self:PauseScan()
        end
        return
    end

    -- Update scope if provided or sync with active keyword box
    if scopeClass ~= nil then
        self:SetScanScope(scopeClass, scopeSubClass or 0, scopeName or "", customLabel)
    elseif PUIMerchant.scopeKeywordBox then
        local kw = Utils.Trim(PUIMerchant.scopeKeywordBox:GetText() or "")
        if kw ~= "" and currentScopeName ~= kw then
            self:SetScanScope(currentScopeClass, currentScopeSubClass, kw)
        end
    end

    -- Check for checkpoint resumption
    local cp = not forceFresh and self:GetScanCheckpoint() or nil
    if cp and cp.page and cp.page > 0 then
        scanPage = math.max(0, cp.page - 1)
        totalPages = cp.totalPages or 1
        totalAuctionsCataloged = cp.totalCataloged or 0
        if cp.scopeClass ~= nil then
            currentScopeClass = cp.scopeClass
            currentScopeSubClass = cp.scopeSubClass or 0
            currentScopeName = cp.scopeName or ""
            currentScopeLabel = cp.scopeLabel or self:GetClassName(currentScopeClass)
        end
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: Resuming %s scan from checkpoint at page %d/%d...", currentScopeLabel, scanPage + 1, totalPages), "69ccf0"))
    else
        scanPage = 0
        totalPages = 1
        totalAuctionsCataloged = 0
        pageRetries = 0
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: Starting fresh %s scan...", currentScopeLabel), "69ccf0"))
    end

    isScanning = true
    isPaused = false
    isWaitingForNextPage = false
    isWaitingForServerGate = false
    consecutiveSuccessPages = 0
    pagesSampled = 0
    measuredAvgCycleTime = 0
    measuredServerGate = 0

    local now = GetTime()
    queryDispatchTime = now
    lastQueryTime = now
    pageCooldownEnd = now + self:GetPacingDelay()

    UpdateScannerState(string.format("Querying Page %d...", scanPage + 1))

    if CanSendAuctionQuery() then
        QueryAuctionItems(currentScopeName or "", 0, 0, 0, currentScopeClass or 0, currentScopeSubClass or 0, scanPage, 0, 0)
    else
        isWaitingForNextPage = true
        isWaitingForServerGate = true
    end
end

-- Pause Active Scan
function PUIMerchant:PauseScan()
    if not isScanning or isPaused then return end
    isPaused = true
    self:SaveScanCheckpoint()
    UpdateScannerState("Scan Paused")
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIMerchant]: AH scan paused. Checkpoint saved. Click Resume to continue.", "ffbb33"))
end

-- Resume Paused Scan
function PUIMerchant:ResumeScan()
    if not isScanning or not isPaused then return end
    isPaused = false
    local now = GetTime()
    lastQueryTime = now
    pageCooldownEnd = now + self:GetPacingDelay()
    isWaitingForNextPage = true
    UpdateScannerState(string.format("Resuming at Page %d/%d...", scanPage + 1, totalPages))
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIMerchant]: Resuming AH scan...", "69ccf0"))
end

-- Stop Active Scan
function PUIMerchant:StopScan()
    if not isScanning then return end
    isScanning = false
    isPaused = false
    isWaitingForNextPage = false
    isWaitingForServerGate = false

    self:SaveScanCheckpoint()

    local realm = GetRealmName() or "Default"
    local ahType = self:GetCurrentAHType()
    local realmData = self:GetRealmPriceData(realm, ahType)
    realmData.lastScan = Time:GetServerTimestamp()
    realmData.totalListings = totalAuctionsCataloged

    UpdateScannerState(string.format("Stopped (Page %d/%d saved)", scanPage, totalPages))
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: AH scan stopped at page %d/%d. %d listings cataloged. Checkpoint saved.", scanPage, totalPages, totalAuctionsCataloged), "ffbb33"))
end

-- Process Returned Auction Batch (Streaming Ingestion - Instant per-page processing)
function PUIMerchant:ProcessScanResults()
    if not isScanning or isPaused then return end
    if isWaitingForNextPage then return end

    local numBatchAuctions, totalAuctions = GetNumAuctionItems("list")

    -- Initial query latency / empty results fallback with retry
    if (not totalAuctions or totalAuctions == 0) and numBatchAuctions == 0 and scanPage == 0 then
        if pageRetries < maxRetries then
            pageRetries = pageRetries + 1
            self:StepUpBackoff()
            isWaitingForNextPage = true
            lastQueryTime = GetTime()
            pageCooldownEnd = lastQueryTime + self:GetPacingDelay()
            UpdateScannerState(string.format("Waiting on AH server (retry %d)...", pageRetries))
            return
        else
            self:FinishScan()
            return
        end
    end

    if totalAuctions and totalAuctions > 0 then
        totalPages = math.ceil(totalAuctions / (NUM_AUCTION_ITEMS_PER_PAGE or 50))
    end

    local realm = GetRealmName() or "Default"
    local ahType = self:GetCurrentAHType()

    -- Stream each auction listing directly into daily storage without memory buffering
    if numBatchAuctions and numBatchAuctions > 0 then
        for i = 1, numBatchAuctions do
            local name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice = GetAuctionItemInfo("list", i)
            local timeLeft = GetAuctionItemTimeLeft("list", i)
            if name and count and count > 0 then
                local unitPrice = 0
                if buyoutPrice and buyoutPrice > 0 then
                    unitPrice = math.floor(buyoutPrice / count)
                elseif minBid and minBid > 0 then
                    unitPrice = math.floor(minBid / count)
                end

                if unitPrice > 0 then
                    self:RecordAuctionListing(name, unitPrice, {
                        texture = texture,
                        quality = quality or 1,
                        itemLevel = level or 1,
                        timeLeft = timeLeft,
                    }, realm, ahType)
                    totalAuctionsCataloged = totalAuctionsCataloged + 1
                end
            end
        end
    end

    scanPage = scanPage + 1
    pageRetries = 0
    self:SaveScanCheckpoint()

    if scanPage >= totalPages or (numBatchAuctions == 0 and scanPage > 1) then
        self:FinishScan()
    else
        isWaitingForNextPage = true
        local now = GetTime()
        local pacingDelay = self:GetPacingDelay()
        local remPacing = (queryDispatchTime > 0) and ((queryDispatchTime + pacingDelay) - now) or 0
        if remPacing < 0 then remPacing = 0 end
        pageCooldownEnd = now + remPacing

        local rateStr = (measuredAvgCycleTime > 0) and string.format("%0.1fs/p", measuredAvgCycleTime) or string.format("%0.1fs", pacingDelay)
        UpdateScannerState(string.format("Page %d/%d (%d items • %s)...", scanPage, totalPages, totalAuctionsCataloged, rateStr))
    end
end

-- Complete Scan (Instantaneous - 0ms freeze)
function PUIMerchant:FinishScan()
    isScanning = false
    isPaused = false
    isWaitingForNextPage = false
    isWaitingForServerGate = false

    self:ClearScanCheckpoint()

    local realm = GetRealmName() or "Default"
    local ahType = self:GetCurrentAHType()
    local realmData = self:GetRealmPriceData(realm, ahType)
    realmData.lastScan = Time:GetServerTimestamp()
    realmData.totalListings = totalAuctionsCataloged

    UpdateScannerState(string.format("Scan Complete! (%d cataloged)", totalAuctionsCataloged))
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: AH Scan Complete! %d auction listings cataloged across %d pages.", totalAuctionsCataloged, scanPage), "69ccf0"))
end

-- =========================================================================
-- PASSIVE BROWSE SNIFFER (Tier 2 Ingestion)
-- =========================================================================

function PUIMerchant:SniffBrowsePage()
    if isScanning then return end
    if not AuctionFrame or not AuctionFrame:IsShown() then return end

    local numBatchAuctions = GetNumAuctionItems("list")
    if not numBatchAuctions or numBatchAuctions == 0 then return end

    local realm = GetRealmName() or "Default"
    local ahType = self:GetCurrentAHType()

    for i = 1, numBatchAuctions do
        local name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice = GetAuctionItemInfo("list", i)
        local timeLeft = GetAuctionItemTimeLeft("list", i)
        if name and count and count > 0 then
            local unitPrice = 0
            if buyoutPrice and buyoutPrice > 0 then
                unitPrice = math.floor(buyoutPrice / count)
            elseif minBid and minBid > 0 then
                unitPrice = math.floor(minBid / count)
            end

            if unitPrice > 0 then
                self:RecordAuctionListing(name, unitPrice, {
                    texture = texture,
                    quality = quality or 1,
                    itemLevel = level or 1,
                    timeLeft = timeLeft,
                }, realm, ahType)
            end
        end
    end
end

-- =========================================================================
-- ASYNCHRONOUS SCANNER TICKER & WATCHDOG
-- =========================================================================

function PUIMerchant:InitScannerTicker()
    -- Fast 0.10s loop for immediate query dispatch when server rate limit clears
    Time:Every(0.10, function()
        if not isScanning or isPaused then return end

        local now = GetTime()

        -- Auto-abort if player closes AH mid-scan
        if not AuctionFrame or not AuctionFrame:IsShown() then
            PUIMerchant:StopScan()
            return
        end

        -- Dispatch next page once pacing elapsed AND server gate clears
        if isWaitingForNextPage then
            local pacingDelay = PUIMerchant:GetPacingDelay()
            local pacingElapsed = (queryDispatchTime == 0) or ((now - queryDispatchTime) >= pacingDelay)
            local canQuery = CanSendAuctionQuery()

            if pacingElapsed then
                if canQuery then
                    local totalCycleTime = (queryDispatchTime > 0) and (now - queryDispatchTime) or pacingDelay
                    if totalCycleTime > 0.3 and totalCycleTime < 30.0 then
                        if measuredAvgCycleTime == 0 then
                            measuredAvgCycleTime = totalCycleTime
                        else
                            measuredAvgCycleTime = (measuredAvgCycleTime * 0.70) + (totalCycleTime * 0.30)
                        end
                        pagesSampled = pagesSampled + 1
                    end

                    -- In ADAPTIVE mode: adapt baseline if server enforced a slower throttle, else step down
                    if PUIMerchant.scannerState.pacingMode == "ADAPTIVE" then
                        if totalCycleTime > (currentEffectiveCooldown + 0.8) then
                            currentEffectiveCooldown = math.min(MAX_COOLDOWN_CEIL, math.max(currentEffectiveCooldown, totalCycleTime))
                        else
                            PUIMerchant:StepDownCooldown()
                        end
                    end

                    isWaitingForNextPage = false
                    isWaitingForServerGate = false
                    queryDispatchTime = now
                    lastQueryTime = now
                    pageCooldownEnd = now + PUIMerchant:GetPacingDelay()

                    local rateStr = (measuredAvgCycleTime > 0) and string.format("%0.1fs/p", measuredAvgCycleTime) or string.format("%0.1fs", PUIMerchant:GetPacingDelay())
                    UpdateScannerState(string.format("Querying Page %d/%d (%d items • %s)...", scanPage + 1, totalPages, totalAuctionsCataloged, rateStr))
                    QueryAuctionItems(currentScopeName or "", 0, 0, 0, currentScopeClass or 0, currentScopeSubClass or 0, scanPage, 0, 0)
                else
                    isWaitingForServerGate = true
                    local serverWait = (queryDispatchTime > 0) and (now - queryDispatchTime) or 0
                    measuredServerGate = serverWait
                    UpdateScannerState(string.format("Page %d/%d - Server Gate Active (%0.1fs)...", scanPage, totalPages, serverWait))
                end
            end
        else
            -- Watchdog: detect dropped packets or server lag (> SCAN_TIMEOUT seconds)
            if (now - lastQueryTime) > SCAN_TIMEOUT then
                if pageRetries < maxRetries then
                    pageRetries = pageRetries + 1
                    PUIMerchant:StepUpBackoff()
                    lastQueryTime = now
                    queryDispatchTime = now
                    pageCooldownEnd = now + PUIMerchant:GetPacingDelay()
                    if CanSendAuctionQuery() then
                        UpdateScannerState(string.format("Retrying Page %d/%d (attempt %d)...", scanPage + 1, totalPages, pageRetries))
                        QueryAuctionItems(currentScopeName or "", 0, 0, 0, currentScopeClass or 0, currentScopeSubClass or 0, scanPage, 0, 0)
                    else
                        isWaitingForNextPage = true
                        isWaitingForServerGate = true
                    end
                else
                    PUIMerchant:FinishScan()
                end
            end
        end
    end, "PUIMerchantScanner")

    -- 0.5s UI Countdown Ticker (Smooth step-down visual updates)
    Time:Every(0.5, function()
        if not isScanning then return end
        if isWaitingForNextPage and not isPaused then
            local now = GetTime()
            local curPacing = PUIMerchant:GetPacingDelay()
            local rateStr = (measuredAvgCycleTime > 0) and string.format("%0.1fs/p", measuredAvgCycleTime) or string.format("%0.1fs", curPacing)
            
            if isWaitingForServerGate then
                local gateElapsed = (queryDispatchTime > 0) and (now - queryDispatchTime) or 0
                UpdateScannerState(string.format("Page %d/%d (%d items) - Server Gate (%0.1fs) • ETA %s", scanPage, totalPages, totalAuctionsCataloged, gateElapsed, PUIMerchant.scannerState.etaText or "--"))
            else
                local rem = math.floor(pageCooldownEnd - now + 0.5)
                if rem < 0 then rem = 0 end
                UpdateScannerState(string.format("Page %d/%d (%d items) - Next in %ds (⚡ %s) • ETA %s", scanPage, totalPages, totalAuctionsCataloged, rem, rateStr, PUIMerchant.scannerState.etaText or "--"))
            end
        end
    end, "PUIMerchantCountdown")
end
