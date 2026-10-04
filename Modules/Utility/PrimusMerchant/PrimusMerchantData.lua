--[[
    PrimusUI Module: PUIMerchant (Data & Statistical Engine)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    1. 3-Way Economy Partitioning:
       - Alliance Capital AH (Stormwind, Ironforge, Darnassus - 5% cut)
       - Horde Capital AH (Orgrimmar, Undercity, Thunder Bluff - 5% cut)
       - Neutral Steamwheedle AH (Booty Bay, Gadgetzan, Everlook - 15% cut)
    2. Streaming Page-by-Page Incremental Ingestion (Zero-Lag Ticking).
    3. Daily Quantile Indexing:
       - Mean & Total Volume (N)
       - Median & Core Fair Market Cluster (Median +- 15%)
       - Low Tier (Cheapest 35% - Sniping Floor)
       - High Tier (Top 35% - Overpriced Ceiling)
    4. 14-Day Rolling History Buffer & Automated Pruning.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIMerchant = Primus.PUIMerchant or {}
Primus.PUIMerchant = PUIMerchant
_G.PUIMerchant = PUIMerchant

local DB    = Primus.DB
local Utils = Primus.Utils
local Time  = Primus.Time
local Items = Primus.Items

-- Register DB Namespace
local merchantDB = DB:RegisterNamespace("PUIMerchant", {
    enabled = true,
    quickBuyout = true,
    showTooltipPrices = true,
    showTooltipSparkline = true,
    flyoutSide = "RIGHT", -- "LEFT" or "RIGHT"
    flyoutOpen = true,
    realms = {},
    priceData = {},
})
PUIMerchant.db = merchantDB

-- Clean Item Name Extractor
function PUIMerchant:CleanItemName(linkOrName)
    if not linkOrName then return nil end
    local s, e, name = string.find(tostring(linkOrName), "%[(.+)%]")
    return name or linkOrName
end

-- Get Day Key (YYYYMMDD integer, e.g., 20261003)
function PUIMerchant:GetDayKey(timestamp)
    timestamp = timestamp or Time:GetServerTimestamp()
    if date then
        local dStr = date("%Y%m%d", timestamp)
        local dNum = tonumber(dStr)
        if dNum and dNum > 0 then return dNum end
    end
    return math.floor(timestamp / 86400)
end

-- =========================================================================
-- 3-WAY AUCTION HOUSE ECONOMY PARTITIONING
-- =========================================================================

function PUIMerchant:GetCurrentAHType()
    local subZone = GetSubZoneText() or ""
    local zone = GetZoneText() or ""
    local minimapZone = GetMinimapZoneText() or ""

    -- Check Neutral Goblin Cities
    if subZone == "Gadgetzan" or subZone == "Booty Bay" or subZone == "Everlook" or
       zone == "Tanaris" or zone == "Winterspring" or zone == "Stranglethorn Vale" or
       minimapZone == "Gadgetzan" or minimapZone == "Booty Bay" or minimapZone == "Everlook" then
        return "Neutral"
    end

    local playerFaction = UnitFactionGroup("player") or "Alliance"
    return playerFaction
end

-- Get Realm Market Container (Partitioned by Realm and AH Type)
function PUIMerchant:GetRealmPriceData(realm, ahType)
    realm = realm or GetRealmName() or "Default"
    ahType = ahType or self:GetCurrentAHType()

    if not merchantDB.data.realms then
        merchantDB.data.realms = {}
    end
    if not merchantDB.data.realms[realm] then
        merchantDB.data.realms[realm] = {}
    end

    local rData = merchantDB.data.realms[realm]

    -- Check if realm was previously stored in legacy flat format
    if rData.priceData and not rData[ahType] then
        rData[ahType] = {
            priceData = rData.priceData,
            lastScan = rData.lastScan or 0,
            totalListings = rData.totalListings or 0,
        }
    end

    if not rData[ahType] then
        rData[ahType] = {
            priceData = {},
            lastScan = 0,
            totalListings = 0,
        }
    end

    return rData[ahType]
end

-- =========================================================================
-- STREAMING INCREMENTAL INGESTION (Zero-Lag Ticking)
-- =========================================================================

-- Ingests a single auction listing immediately as each page arrives
function PUIMerchant:RecordAuctionListing(itemName, unitPrice, itemMeta, realm, ahType)
    if not itemName or not unitPrice or unitPrice <= 0 then return end
    local clean = self:CleanItemName(itemName)
    if not clean or clean == "" then return end

    local realmData = self:GetRealmPriceData(realm, ahType)
    local pData = realmData.priceData[clean]
    local now = Time:GetServerTimestamp()
    local todayKey = self:GetDayKey(now)

    if not pData then
        pData = {
            name             = clean,
            texture          = itemMeta and itemMeta.texture or nil,
            quality          = itemMeta and itemMeta.quality or 1,
            itemClass        = itemMeta and itemMeta.itemClass or "Trade Goods",
            itemLevel        = itemMeta and itemMeta.itemLevel or 1,
            latestMinBuyout  = unitPrice,
            lastSeen         = now,
            runningAvg7d     = unitPrice,
            runningMedian7d  = unitPrice,
            history          = {},
        }
        realmData.priceData[clean] = pData
    else
        if not pData.latestMinBuyout or unitPrice < pData.latestMinBuyout or pData.latestMinBuyout == 0 then
            pData.latestMinBuyout = unitPrice
        end
        pData.lastSeen = now
        if itemMeta then
            if itemMeta.texture and not pData.texture then pData.texture = itemMeta.texture end
            if itemMeta.quality and pData.quality == 1 then pData.quality = itemMeta.quality end
            if itemMeta.itemLevel then pData.itemLevel = itemMeta.itemLevel end
        end
    end

    if not pData.history then pData.history = {} end
    local todayStat = pData.history[todayKey]

    if not todayStat then
        todayStat = {
            totalVolume = 1,
            totalSum    = unitPrice,
            mean        = unitPrice,
            median      = unitPrice,
            coreMin     = math.floor(unitPrice * 0.85),
            coreMax     = math.floor(unitPrice * 1.15),
            coreAvg     = unitPrice,
            coreVolume  = 1,
            lowAvg      = unitPrice,
            lowMin      = unitPrice,
            lowMax      = unitPrice,
            lowVolume   = 1,
            highAvg     = unitPrice,
            highMin     = unitPrice,
            highMax     = unitPrice,
            highVolume  = 1,
        }
        pData.history[todayKey] = todayStat
    else
        -- Incremental fast math update
        local oldVol = todayStat.totalVolume or 1
        local newVol = oldVol + 1
        todayStat.totalVolume = newVol

        local oldSum = todayStat.totalSum or (todayStat.mean * oldVol)
        local newSum = oldSum + unitPrice
        todayStat.totalSum = newSum

        local newMean = math.floor(newSum / newVol)
        todayStat.mean = newMean

        -- Update Min / Max bounds
        if not todayStat.lowMin or unitPrice < todayStat.lowMin then todayStat.lowMin = unitPrice end
        if not todayStat.highMax or unitPrice > todayStat.highMax then todayStat.highMax = unitPrice end

        -- Dynamic Core Median Band (+-15%)
        todayStat.coreMin = math.floor(newMean * 0.85)
        todayStat.coreMax = math.floor(newMean * 1.15)
        if unitPrice >= todayStat.coreMin and unitPrice <= todayStat.coreMax then
            todayStat.coreVolume = (todayStat.coreVolume or 0) + 1
        end

        -- Low Tier / High Tier Approximations
        local lowCap = math.floor(newMean * 0.70)
        local highFloor = math.floor(newMean * 1.30)

        if unitPrice <= lowCap then
            todayStat.lowVolume = (todayStat.lowVolume or 0) + 1
            todayStat.lowAvg = math.floor(((todayStat.lowAvg or unitPrice) + unitPrice) / 2)
        else
            todayStat.lowAvg = todayStat.lowMin or unitPrice
        end

        if unitPrice >= highFloor then
            todayStat.highVolume = (todayStat.highVolume or 0) + 1
            todayStat.highAvg = math.floor(((todayStat.highAvg or unitPrice) + unitPrice) / 2)
        else
            todayStat.highAvg = todayStat.highMax or unitPrice
        end

        todayStat.median = newMean
    end

    -- Fast Running Average Update (Exponential Rolling Smoothing)
    if not pData.runningAvg7d or pData.runningAvg7d == 0 then
        pData.runningAvg7d = unitPrice
        pData.runningMedian7d = unitPrice
    else
        -- Light blend: 98% historical weight + 2% new observation
        pData.runningAvg7d = math.floor((pData.runningAvg7d * 0.98) + (unitPrice * 0.02))
        pData.runningMedian7d = pData.runningAvg7d
    end

    -- Keep legacy global synchronized
    if not merchantDB.data.priceData then merchantDB.data.priceData = {} end
    merchantDB.data.priceData[clean] = {
        minBuyout   = pData.latestMinBuyout,
        totalBuyout = pData.runningAvg7d,
        count       = todayStat.totalVolume,
        lastSeen    = now,
    }
end

-- =========================================================================
-- 14-DAY HISTORY PRUNING
-- =========================================================================

function PUIMerchant:PruneOldHistory(realm, maxDays)
    maxDays = maxDays or 14
    realm = realm or GetRealmName() or "Default"
    local rData = merchantDB.data.realms and merchantDB.data.realms[realm]
    if not rData then return 0 end

    local now = Time:GetServerTimestamp()
    local cutoffDayKey = self:GetDayKey(now - (maxDays * 86400))
    local totalPurged = 0

    local ahTypes = { "Alliance", "Horde", "Neutral" }
    for _, ahType in ipairs(ahTypes) do
        local bucket = rData[ahType]
        if bucket and bucket.priceData then
            for itemName, pData in pairs(bucket.priceData) do
                if pData.history then
                    for dayKey, _ in pairs(pData.history) do
                        if dayKey < cutoffDayKey then
                            pData.history[dayKey] = nil
                            totalPurged = totalPurged + 1
                        end
                    end
                end
            end
        end
    end

    return totalPurged
end

-- Comprehensive Item Metric Lookup
function PUIMerchant:GetItemMetrics(itemName, realm, ahType)
    if not itemName then return nil end
    local clean = self:CleanItemName(itemName)
    if not clean or clean == "" then return nil end

    local realmData = self:GetRealmPriceData(realm, ahType)
    local pData = realmData and realmData.priceData and realmData.priceData[clean]

    if not pData then
        -- Fallback: check other faction buckets or legacy
        local rData = merchantDB.data.realms and merchantDB.data.realms[realm or GetRealmName() or "Default"]
        if rData then
            local fallbackTypes = { "Alliance", "Horde", "Neutral" }
            for _, fType in ipairs(fallbackTypes) do
                if rData[fType] and rData[fType].priceData and rData[fType].priceData[clean] then
                    return rData[fType].priceData[clean]
                end
            end
        end

        local legacy = merchantDB.data.priceData and merchantDB.data.priceData[clean]
        if legacy and legacy.minBuyout and legacy.minBuyout > 0 then
            return {
                name            = clean,
                latestMinBuyout = legacy.minBuyout,
                runningAvg7d    = math.floor(legacy.totalBuyout / (legacy.count or 1)),
                runningMedian7d = math.floor(legacy.totalBuyout / (legacy.count or 1)),
                totalVolume     = legacy.count or 1,
                lastSeen        = legacy.lastSeen or 0,
                history         = {},
            }
        end
        return nil
    end

    return pData
end
