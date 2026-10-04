--[[
    PrimusUI Module: PUIQuest (Canonical Multi-Indexed Database Engine)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides high-speed lookups across items, quests, NPCs, objects, coordinates,
    pin clustering, and zone projections directly on PUIQuest.DB with zero legacy globals.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIQuest = Primus.PUIQuest or {}
Primus.PUIQuest = PUIQuest
_G.PUIQuest = PUIQuest

local Database = {}
PUIQuest.Database = Database

local Utils = Primus.Utils

-- Reverse name lookup indices: [lowerName] = id
local itemIndex = {}
local questIndex = {}
local unitIndex = {}
local objectIndex = {}
local isIndexed = false

-- Cluster calculation cache
local clusterCache = {}

function Database:BuildIndices()
    local DB = PUIQuest.DB
    if not DB then return end

    -- Ensure Turtle WoW delta patches are applied if enabled
    if PUIQuest.Patchtable and PUIQuest.Patchtable.Apply and not PUIQuest.Patchtable:IsPatched() then
        if not PUIQuest.db or PUIQuest.db:Get("turtleMode", true) then
            PUIQuest.Patchtable:Apply()
        end
    end

    -- 1. Index Items
    local itemLoc = DB["items"] and (DB["items"]["enUS"] or DB["items"]["loc"])
    if itemLoc then
        for id, name in pairs(itemLoc) do
            if type(name) == "string" and name ~= "_" then
                itemIndex[string.lower(name)] = id
            end
        end
    end

    -- 2. Index Quests (Supports both standard [1]="Title" and Turtle ["T"]="Title")
    local questLoc = DB["quests"] and (DB["quests"]["enUS"] or DB["quests"]["loc"])
    if questLoc then
        for id, qData in pairs(questLoc) do
            local title = type(qData) == "table" and (qData[1] or qData["T"] or qData["title"]) or qData
            if type(title) == "string" and title ~= "_" then
                questIndex[string.lower(title)] = id
            end
        end
    end

    -- 3. Index Units
    local unitLoc = DB["units"] and (DB["units"]["enUS"] or DB["units"]["loc"])
    if unitLoc then
        for id, name in pairs(unitLoc) do
            if type(name) == "string" and name ~= "_" then
                unitIndex[string.lower(name)] = id
            end
        end
    end

    -- 4. Index Objects
    local objectLoc = DB["objects"] and (DB["objects"]["enUS"] or DB["objects"]["loc"])
    if objectLoc then
        for id, name in pairs(objectLoc) do
            if type(name) == "string" and name ~= "_" then
                objectIndex[string.lower(name)] = id
            end
        end
    end

    isIndexed = true
end

function Database:Reload()
    itemIndex = {}
    questIndex = {}
    unitIndex = {}
    objectIndex = {}
    clusterCache = {}
    self:BuildIndices()
end

local function CleanName(str)
    if not str or type(str) ~= "string" then return "" end
    local clean = string.gsub(str, "|c%x%x%x%x%x%x%x%x", "")
    clean = string.gsub(clean, "|r", "")
    clean = string.gsub(clean, "%b[]", "")
    clean = string.gsub(clean, "^%s*(.-)%s*$", "%1")
    return string.lower(clean)
end

-- =========================================================================
-- QUERY PRIMITIVES
-- =========================================================================

function Database:FindItem(nameOrID)
    if not isIndexed then self:BuildIndices() end
    local DB = PUIQuest.DB
    if not DB or not DB["items"] then return nil end

    local id = tonumber(nameOrID)
    if not id and type(nameOrID) == "string" then
        local raw = string.lower(nameOrID)
        id = itemIndex[raw] or itemIndex[CleanName(nameOrID)]
    end
    if not id then return nil end

    local data = DB["items"]["data"] and DB["items"]["data"][id]
    local loc = DB["items"]["enUS"] and DB["items"]["enUS"][id]
    return {
        id = id,
        name = loc or ("Item #" .. id),
        data = data or {},
    }
end

function Database:FindQuest(nameOrID)
    if not isIndexed then self:BuildIndices() end
    local DB = PUIQuest.DB
    if not DB or not DB["quests"] then return nil end

    local id = tonumber(nameOrID)
    if not id and type(nameOrID) == "string" then
        local raw = string.lower(nameOrID)
        id = questIndex[raw]
        if not id then
            local clean = CleanName(nameOrID)
            id = questIndex[clean]
            if not id and clean ~= "" then
                for qName, qID in pairs(questIndex) do
                    if string.find(clean, qName, 1, true) or string.find(qName, clean, 1, true) then
                        id = qID
                        break
                    end
                end
            end
        end
    end
    if not id then return nil end

    local data = DB["quests"]["data"] and DB["quests"]["data"][id]
    local loc = DB["quests"]["enUS"] and DB["quests"]["enUS"][id]
    local title = type(loc) == "table" and (loc[1] or loc["T"] or loc["title"]) or loc
    local desc = type(loc) == "table" and (loc[2] or loc["D"] or loc["desc"]) or ""
    local objText = type(loc) == "table" and (loc[3] or loc["O"] or loc["objText"]) or ""

    return {
        id = id,
        title = title or ("Quest #" .. id),
        desc = desc,
        objText = objText,
        data = data or {},
    }
end

function Database:FindUnit(nameOrID)
    if not isIndexed then self:BuildIndices() end
    local DB = PUIQuest.DB
    if not DB or not DB["units"] then return nil end

    local id = tonumber(nameOrID)
    if not id and type(nameOrID) == "string" then
        id = unitIndex[string.lower(nameOrID)]
    end
    if not id then return nil end

    local data = DB["units"]["data"] and DB["units"]["data"][id]
    local loc = DB["units"]["enUS"] and DB["units"]["enUS"][id]

    return {
        id = id,
        name = loc or ("Unit #" .. id),
        spawns = data or {},
    }
end

function Database:FindObject(nameOrID)
    if not isIndexed then self:BuildIndices() end
    local DB = PUIQuest.DB
    if not DB or not DB["objects"] then return nil end

    local id = tonumber(nameOrID)
    if not id and type(nameOrID) == "string" then
        id = objectIndex[string.lower(nameOrID)]
    end
    if not id then return nil end

    local data = DB["objects"]["data"] and DB["objects"]["data"][id]
    local loc = DB["objects"]["enUS"] and DB["objects"]["enUS"][id]

    return {
        id = id,
        name = loc or ("Object #" .. id),
        spawns = data or {},
    }
end

-- Resolve vendor price if item is sold by vendors
function Database:GetItemVendorPrice(itemID)
    local item = self:FindItem(itemID)
    if not item or not item.data then return nil end

    local v = item.data["V"]
    if v then
        for vendorID, count in pairs(v) do
            return tonumber(count) or 0
        end
    end
    return nil
end

-- =========================================================================
-- PIN CLUSTERING & DENSITY RESOLUTION
-- =========================================================================

-- Return the best density centroid point for a list of coordinates
function Database:GetCluster(coordsList, key)
    if not coordsList or table.getn(coordsList) == 0 then return nil, nil, 0 end
    local n = table.getn(coordsList)
    if n == 1 then
        return coordsList[1][1], coordsList[1][2], 1
    end

    local cacheKey = string.format("%s:%d", tostring(key or "def"), n)
    if clusterCache[cacheKey] then
        return clusterCache[cacheKey][1], clusterCache[cacheKey][2], clusterCache[cacheKey][3]
    end

    local bestIndex = 1
    local bestNeighbors = -1
    local count = 0

    for i = 1, n do
        local c = coordsList[i]
        local x = c[1]
        local y = c[2]
        local xmin, xmax = x - 5.0, x + 5.0
        local ymin, ymax = y - 5.0, y + 5.0
        local neighbors = 0
        count = count + 1

        for j = 1, n do
            local other = coordsList[j]
            if other[1] >= xmin and other[1] <= xmax and other[2] >= ymin and other[2] <= ymax then
                neighbors = neighbors + 1
            end
        end

        if neighbors > bestNeighbors then
            bestNeighbors = neighbors
            bestIndex = i
        end
    end

    local bestCoord = coordsList[bestIndex]
    local resX = bestCoord[1]
    local resY = bestCoord[2]

    clusterCache[cacheKey] = { resX, resY, count }
    return resX, resY, count
end

-- =========================================================================
-- TEXT FORMATTING & ZONE LOOKUPS
-- =========================================================================

function Database:FormatQuestText(questText)
    if not questText or type(questText) ~= "string" then return "" end
    questText = string.gsub(questText, "$[Nn]", UnitName("player") or "Hero")
    questText = string.gsub(questText, "$[Cc]", string.lower(UnitClass("player") or "Adventurer"))
    questText = string.gsub(questText, "$[Rr]", string.lower(UnitRace("player") or "Mortal"))
    questText = string.gsub(questText, "$[Bb]", "\n")
    local sex = UnitSex("player") or 2
    questText = string.gsub(questText, "($[Gg])([^:]+):([^;]+);", "%" .. sex)
    return questText
end

function Database:GetMapIDByName(search)
    if not search or search == "" then return nil end
    local DB = PUIQuest.DB
    if not DB or not DB["zones"] then return nil end
    local zonesLoc = DB["zones"]["enUS"] or DB["zones"]["loc"]
    if not zonesLoc then return nil end

    local sLower = string.lower(search)
    for id, name in pairs(zonesLoc) do
        if type(name) == "string" and string.lower(name) == sLower then
            return tonumber(id)
        end
    end
    return nil
end

local mapZoneCache = {}
function Database:GetMapID(cid, mid)
    cid = cid or GetCurrentMapContinent()
    mid = mid or GetCurrentMapZone()
    if cid <= 0 or mid <= 0 then return nil end

    if not mapZoneCache[cid] then
        mapZoneCache[cid] = { GetMapZones(cid) }
    end

    local list = mapZoneCache[cid]
    local name = list[mid]
    if not name then return nil end

    return self:GetMapIDByName(name)
end

function Database:GetQuestIDs(qlogid)
    if not qlogid or qlogid <= 0 then return nil end
    local title, level, _, isHeader = GetQuestLogTitle(qlogid)
    if isHeader or not title then return nil end

    if not isIndexed then self:BuildIndices() end
    local qID = questIndex[string.lower(title)]
    if qID then
        return { qID }
    end
    return nil
end

-- Search entities by prefix or keyword
function Database:Search(query, category, maxResults)
    if not query or query == "" then return {} end
    if not isIndexed then self:BuildIndices() end

    maxResults = maxResults or 50
    category = category and string.lower(category) or "all"
    query = string.lower(query)

    local results = {}
    local count = 0

    local function CheckMatch(tbl, catName)
        for name, id in pairs(tbl) do
            if string.find(name, query, 1, true) then
                count = count + 1
                table.insert(results, { id = id, name = name, category = catName })
                if count >= maxResults then return true end
            end
        end
        return false
    end

    if category == "all" or category == "quests" then
        if CheckMatch(questIndex, "Quests") then return results end
    end
    if category == "all" or category == "items" then
        if CheckMatch(itemIndex, "Items") then return results end
    end
    if category == "all" or category == "units" then
        if CheckMatch(unitIndex, "Units") then return results end
    end
    if category == "all" or category == "objects" then
        if CheckMatch(objectIndex, "Objects") then return results end
    end

    return results
end

function Database:IsQuestCompleted(qid)
    return PUIQuest.IsQuestCompleted and PUIQuest:IsQuestCompleted(qid)
end

function Database:QueryServer()
    if PUIQuest.QueryServer then
        PUIQuest:QueryServer()
    end
end

