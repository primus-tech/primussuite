--[[
    PrimusUI Module: PUIQuest (World Map POI Overlay & Route Line Engine)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    Architecture: Strict TRUTH.md compliance (Centralized PUIMap Provider)

    Features:
    1. Pooled POI Pins: Available (!), Turn-in (?), and Objective (1, 2, 3) markers.
    2. Dynamic Route Connection Lines: Dotted trails connecting player -> active quest targets.
    3. Multi-Zone & Turtle WoW Support: Database resolution for standard zones and custom regions.
    4. Sub-Objective Progress Awareness: Dynamically hides pins for completed sub-objectives.
    5. Interactive Tooltips & Navigation Lock: Click any map pin to focus HUD navigation.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIQuest = Primus.PUIQuest or {}
Primus.PUIQuest = PUIQuest
_G.PUIQuest = PUIQuest

local Map = {}
PUIQuest.Map = Map

local Utils  = Primus.Utils
local Media  = Primus.Media
local Events = Primus.Events

-- Difficulty Colors
local DIFFICULTY_COLORS = {
    ["impossible"]    = { r = 1.00, g = 0.15, b = 0.15 }, -- Red
    ["verydifficult"] = { r = 1.00, g = 0.50, b = 0.20 }, -- Orange
    ["difficult"]     = { r = 1.00, g = 0.85, b = 0.10 }, -- Yellow
    ["standard"]      = { r = 0.25, g = 0.85, b = 0.25 }, -- Green
    ["trivial"]       = { r = 0.60, g = 0.60, b = 0.60 }, -- Gray
}

local function GetDifficultyColor(level)
    if not level or level <= 0 then return DIFFICULTY_COLORS["standard"] end
    local pLevel = UnitLevel("player") or 1
    local diff = level - pLevel
    if diff >= 5 then
        return DIFFICULTY_COLORS["impossible"]
    elseif diff >= 3 then
        return DIFFICULTY_COLORS["verydifficult"]
    elseif diff >= -2 then
        return DIFFICULTY_COLORS["difficult"]
    elseif -diff <= (GetQuestGreenRange and GetQuestGreenRange() or 5) then
        return DIFFICULTY_COLORS["standard"]
    else
        return DIFFICULTY_COLORS["trivial"]
    end
end

local function SetupPinScripts(pin)
    pin:SetScript("OnEnter", function()
        if not this.data then return end
        WorldMapTooltip:SetOwner(this, "ANCHOR_RIGHT")
        WorldMapTooltip:ClearLines()

        local d = this.data
        local col = GetDifficultyColor(d.level)
        WorldMapTooltip:AddLine(string.format("[%d] %s", d.level or 0, d.title or "Quest"), col.r, col.g, col.b)

        if d.pinType == "AVAILABLE" then
            WorldMapTooltip:AddLine(string.format("Quest Giver: |cffffffff%s|r", d.npcName or "NPC"), 1, 0.82, 0)
            WorldMapTooltip:AddLine("Status: |cffffd100Available Quest|r", 0.7, 0.7, 0.7)
            if d.minLevel and d.minLevel > 1 then
                WorldMapTooltip:AddLine(string.format("Requires Level: %d", d.minLevel), 0.6, 0.6, 0.6)
            end
        elseif d.pinType == "TURNIN" then
            WorldMapTooltip:AddLine(string.format("Turn In: |cffffffff%s|r", d.npcName or "NPC"), 1, 0.82, 0)
            WorldMapTooltip:AddLine("Status: |cff00ff00Ready for Turn-in|r", 0.7, 1.0, 0.7)
        elseif d.pinType == "OBJECTIVE" then
            WorldMapTooltip:AddLine(string.format("Objective: |cffffffff%s|r", d.objText or "Objective"), 0.4, 0.85, 1.0)
            if d.targetName then
                WorldMapTooltip:AddLine(string.format("Target: |cffffffff%s|r", d.targetName), 0.8, 0.8, 0.8)
            end
            if d.spawnCount and d.spawnCount > 1 then
                WorldMapTooltip:AddLine(string.format("Cluster: |cff69ccf0%d spawns in area|r", d.spawnCount), 0.7, 0.7, 0.7)
            end
        elseif d.pinType == "TRACK" then
            WorldMapTooltip:AddLine(string.format("Node: |cffffffff%s|r", d.targetName or "Tracked Node"), 0.2, 1.0, 0.4)
        end

        WorldMapTooltip:AddLine("Left-Click: Focus Navigation Arrow & Route", 0.5, 0.5, 0.5)
        WorldMapTooltip:Show()
    end)

    pin:SetScript("OnLeave", function()
        WorldMapTooltip:Hide()
    end)

    pin:SetScript("OnClick", function()
        if this.data and this.data.title then
            PUIQuest:FocusQuest(this.data.title)
        end
    end)
end

--------------------------------------------------------------------------------
-- Zone Coordinates Extractor
--------------------------------------------------------------------------------
local function GetZoneCoords(spawnsTbl, currentZoneName, currentZoneID)
    if not spawnsTbl or not spawnsTbl.coords then return {} end
    local DB = PUIQuest.DB
    if not DB or not DB["zones"] then return {} end

    local zonesLoc = DB["zones"]["enUS"] or DB["zones"]["loc"]
    local zonesData = DB["zones"]["data"]
    if not zonesLoc then return {} end

    local targetLower = currentZoneName and string.lower(currentZoneName) or ""
    local results = {}

    for _, c in pairs(spawnsTbl.coords) do
        local x = c[1]
        local y = c[2]
        local zID = c[3]

        if zID and x and y then
            local zName = zonesLoc[zID]
            local zLower = zName and string.lower(zName) or ""

            if (targetLower ~= "" and zLower == targetLower) or (currentZoneID and zID == currentZoneID) then
                table.insert(results, { x = x, y = y, zoneID = zID })
            elseif zonesData and zonesData[zID] then
                local pID, w, h, ox, oy = unpack(zonesData[zID])
                if pID and zonesLoc[pID] and string.lower(zonesLoc[pID]) == targetLower then
                    local parentX = ox + (x * (w / 100))
                    local parentY = oy + (y * (h / 100))
                    table.insert(results, { x = parentX, y = parentY, zoneID = pID })
                end
            end
        end
    end
    return results
end

--------------------------------------------------------------------------------
-- Quest Log Progress Helper
--------------------------------------------------------------------------------
local function GetQuestLogProgress(questTitle)
    local numEntries = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local title, level, questTag, isHeader, isCollapsed, isComplete = GetQuestLogTitle(i)
        if not isHeader and title == questTitle then
            SelectQuestLogEntry(i)
            local numLeaderboards = GetNumQuestLeaderBoards()
            local finished = {}
            local allDone = (isComplete == 1 or (numLeaderboards > 0 and true))

            if numLeaderboards == 0 then
                allDone = (isComplete == 1)
            else
                for j = 1, numLeaderboards do
                    local desc, qType, isDone = GetQuestLogLeaderBoard(j)
                    if isDone then
                        if desc then
                            local itemName = string.gsub(desc, ":%s*%d+/%d+", "")
                            itemName = string.gsub(itemName, "^%s*", "")
                            itemName = string.gsub(itemName, "%s*$", "")
                            finished[string.lower(itemName)] = true
                        end
                    else
                        allDone = false
                    end
                end
            end
            return allDone, finished
        end
    end
    return false, {}
end

--------------------------------------------------------------------------------
-- Render Quest Pins onto PUIMap Context
--------------------------------------------------------------------------------
function Map:RenderQuestPins(mapContext)
    if not mapContext then return end
    if not PUIQuest.db or not PUIQuest.db:Get("showWorldMapPins", true) or not PUIQuest.db:Get("enabled", true) then
        return
    end

    local mapContinent = mapContext.continent
    local mapZone = mapContext.zone
    local currentZoneName = mapContext.zoneName
    if not mapContinent or mapContinent <= 0 or not mapZone or mapZone <= 0 then return end
    if not currentZoneName or currentZoneName == "" then return end

    local DB = PUIQuest.DB
    if not DB then return end

    -- 1. Scan Active Quests in Log
    local numEntries = GetNumQuestLogEntries()
    for qIndex = 1, numEntries do
        local title, level, questTag, isHeader, isCollapsed, isComplete = GetQuestLogTitle(qIndex)
        if not isHeader and title then
            local q = PUIQuest.Database:FindQuest(title)
            if q and q.data then
                local questDone, finishedObjs = GetQuestLogProgress(title)

                -- Turn-in pin if completed
                if questDone and PUIQuest.db:Get("showTurnIns", true) then
                    local endUnits = q.data["end"] and q.data["end"]["U"]
                    if endUnits then
                        for _, uID in pairs(endUnits) do
                            local unit = PUIQuest.Database:FindUnit(uID)
                            if unit and unit.spawns then
                                local coords = GetZoneCoords(unit.spawns, currentZoneName, mapZone)
                                for _, coord in pairs(coords) do
                                    local pin = mapContext.AcquirePin()
                                    pin.icon:SetTexture(nil)
                                    pin.label:SetText("?")
                                    pin.label:SetTextColor(1.0, 0.82, 0.0)
                                    pin.data = {
                                        title = title,
                                        level = level,
                                        npcName = unit.name,
                                        pinType = "TURNIN",
                                        x = coord.x,
                                        y = coord.y,
                                    }
                                    SetupPinScripts(pin)
                                    mapContext:PlacePin(pin, coord.x, coord.y)
                                end
                            end
                        end
                    end
                    local endObjects = q.data["end"] and q.data["end"]["O"]
                    if endObjects then
                        for _, oID in pairs(endObjects) do
                            local obj = PUIQuest.Database:FindObject(oID)
                            if obj and obj.spawns then
                                local coords = GetZoneCoords(obj.spawns, currentZoneName, mapZone)
                                for _, coord in pairs(coords) do
                                    local pin = mapContext.AcquirePin()
                                    pin.icon:SetTexture(nil)
                                    pin.label:SetText("?")
                                    pin.label:SetTextColor(1.0, 0.82, 0.0)
                                    pin.data = {
                                        title = title,
                                        level = level,
                                        npcName = obj.name,
                                        pinType = "TURNIN",
                                        x = coord.x,
                                        y = coord.y,
                                    }
                                    SetupPinScripts(pin)
                                    mapContext:PlacePin(pin, coord.x, coord.y)
                                end
                            end
                        end
                    end
                elseif not questDone then
                    -- In-progress Unit Objectives
                    local objUnits = q.data["obj"] and q.data["obj"]["U"]
                    if objUnits then
                        for oIdx, uID in pairs(objUnits) do
                            local unit = PUIQuest.Database:FindUnit(uID)
                            if unit and unit.spawns and not finishedObjs[string.lower(unit.name)] then
                                local coords = GetZoneCoords(unit.spawns, currentZoneName, mapZone)
                                local numCoords = table.getn(coords)
                                for _, coord in pairs(coords) do
                                    local pin = mapContext.AcquirePin()
                                    pin.icon:SetTexture(nil)
                                    pin.label:SetText(tostring(oIdx))
                                    pin.label:SetTextColor(0.4, 0.85, 1.0)
                                    pin.data = {
                                        title = title,
                                        level = level,
                                        targetName = unit.name,
                                        objText = "Slay " .. unit.name,
                                        pinType = "OBJECTIVE",
                                        spawnCount = numCoords,
                                        x = coord.x,
                                        y = coord.y,
                                    }
                                    SetupPinScripts(pin)
                                    mapContext:PlacePin(pin, coord.x, coord.y)
                                end
                            end
                        end
                    end

                    -- In-progress Object Objectives
                    local objObjects = q.data["obj"] and q.data["obj"]["O"]
                    if objObjects then
                        for oIdx, oID in pairs(objObjects) do
                            local obj = PUIQuest.Database:FindObject(oID)
                            if obj and obj.spawns and not finishedObjs[string.lower(obj.name)] then
                                local coords = GetZoneCoords(obj.spawns, currentZoneName, mapZone)
                                local numCoords = table.getn(coords)
                                for _, coord in pairs(coords) do
                                    local pin = mapContext.AcquirePin()
                                    pin.icon:SetTexture(nil)
                                    pin.label:SetText(tostring(oIdx))
                                    pin.label:SetTextColor(0.4, 0.85, 1.0)
                                    pin.data = {
                                        title = title,
                                        level = level,
                                        targetName = obj.name,
                                        objText = "Interact with " .. obj.name,
                                        pinType = "OBJECTIVE",
                                        spawnCount = numCoords,
                                        x = coord.x,
                                        y = coord.y,
                                    }
                                    SetupPinScripts(pin)
                                    mapContext:PlacePin(pin, coord.x, coord.y)
                                end
                            end
                        end
                    end

                    -- In-progress Item Loot Objectives
                    local objItems = q.data["obj"] and q.data["obj"]["I"]
                    if objItems then
                        for oIdx, iID in pairs(objItems) do
                            local item = PUIQuest.Database:FindItem(iID)
                            if item and not finishedObjs[string.lower(item.name)] then
                                if item.data and item.data["U"] then
                                    for uID in pairs(item.data["U"]) do
                                        local unit = PUIQuest.Database:FindUnit(uID)
                                        if unit and unit.spawns then
                                            local coords = GetZoneCoords(unit.spawns, currentZoneName, mapZone)
                                            local numCoords = table.getn(coords)
                                            for _, coord in pairs(coords) do
                                                local pin = mapContext.AcquirePin()
                                                pin.icon:SetTexture(nil)
                                                pin.label:SetText(tostring(oIdx))
                                                pin.label:SetTextColor(0.4, 0.85, 1.0)
                                                pin.data = {
                                                    title = title,
                                                    level = level,
                                                    targetName = unit.name,
                                                    objText = "Loot " .. item.name .. " from " .. unit.name,
                                                    pinType = "OBJECTIVE",
                                                    spawnCount = numCoords,
                                                    x = coord.x,
                                                    y = coord.y,
                                                }
                                                SetupPinScripts(pin)
                                                mapContext:PlacePin(pin, coord.x, coord.y)
                                            end
                                        end
                                    end
                                end
                                if item.data and item.data["O"] then
                                    for oID in pairs(item.data["O"]) do
                                        local obj = PUIQuest.Database:FindObject(oID)
                                        if obj and obj.spawns then
                                            local coords = GetZoneCoords(obj.spawns, currentZoneName, mapZone)
                                            local numCoords = table.getn(coords)
                                            for _, coord in pairs(coords) do
                                                local pin = mapContext.AcquirePin()
                                                pin.icon:SetTexture(nil)
                                                pin.label:SetText(tostring(oIdx))
                                                pin.label:SetTextColor(0.4, 0.85, 1.0)
                                                pin.data = {
                                                    title = title,
                                                    level = level,
                                                    targetName = obj.name,
                                                    objText = "Gather " .. item.name .. " from " .. obj.name,
                                                    pinType = "OBJECTIVE",
                                                    spawnCount = numCoords,
                                                    x = coord.x,
                                                    y = coord.y,
                                                }
                                                SetupPinScripts(pin)
                                                mapContext:PlacePin(pin, coord.x, coord.y)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 2. Available Quests in Zone
    if PUIQuest.db:Get("showAvailableQuests", true) then
        local pLevel = UnitLevel("player") or 1
        local questData = DB["quests"] and DB["quests"]["data"]
        if questData then
            for qID, qInfo in pairs(questData) do
                local minLvl = qInfo["min"] or 1
                local qLvl = qInfo["lvl"] or minLvl
                local isComplete = PUIQuest.IsQuestCompleted and PUIQuest:IsQuestCompleted(qID)
                local prereqsMet = (not PUIQuest.ArePrereqsCompleted) or PUIQuest:ArePrereqsCompleted(qID)

                if not isComplete and prereqsMet and pLevel >= minLvl then
                    local qEntry = PUIQuest.Database:FindQuest(qID)
                    local qTitle = qEntry and qEntry.title or ("Quest #" .. qID)
                    local inLog = false
                    for i = 1, numEntries do
                        if GetQuestLogTitle(i) == qTitle then inLog = true; break end
                    end

                    if not inLog then
                        -- Check Unit Quest Givers
                        if qInfo["start"] and qInfo["start"]["U"] then
                            for _, uID in pairs(qInfo["start"]["U"]) do
                                local unit = PUIQuest.Database:FindUnit(uID)
                                if unit and unit.spawns then
                                    local coords = GetZoneCoords(unit.spawns, currentZoneName, mapZone)
                                    for _, coord in pairs(coords) do
                                        local pin = mapContext.AcquirePin()
                                        pin.icon:SetTexture(nil)
                                        local col = GetDifficultyColor(qLvl)
                                        pin.label:SetText("!")
                                        pin.label:SetTextColor(col.r, col.g, col.b)
                                        pin.data = {
                                            title = qTitle,
                                            level = qLvl,
                                            minLevel = minLvl,
                                            npcName = unit.name,
                                            pinType = "AVAILABLE",
                                            x = coord.x,
                                            y = coord.y,
                                        }
                                        SetupPinScripts(pin)
                                        mapContext:PlacePin(pin, coord.x, coord.y)
                                    end
                                end
                            end
                        end

                        -- Check Object Quest Givers
                        if qInfo["start"] and qInfo["start"]["O"] then
                            for _, oID in pairs(qInfo["start"]["O"]) do
                                local obj = PUIQuest.Database:FindObject(oID)
                                if obj and obj.spawns then
                                    local coords = GetZoneCoords(obj.spawns, currentZoneName, mapZone)
                                    for _, coord in pairs(coords) do
                                        local pin = mapContext.AcquirePin()
                                        pin.icon:SetTexture(nil)
                                        local col = GetDifficultyColor(qLvl)
                                        pin.label:SetText("!")
                                        pin.label:SetTextColor(col.r, col.g, col.b)
                                        pin.data = {
                                            title = qTitle,
                                            level = qLvl,
                                            minLevel = minLvl,
                                            npcName = obj.name,
                                            pinType = "AVAILABLE",
                                            x = coord.x,
                                            y = coord.y,
                                        }
                                        SetupPinScripts(pin)
                                        mapContext:PlacePin(pin, coord.x, coord.y)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 3. Draw Route Connection Line from Player to Active Target
    if PUIQuest.db:Get("showRouteLines", true) and mapContext.DrawRouteLine then
        local px, py = GetPlayerMapPosition("player")
        if px and py and (px > 0 or py > 0) then
            local target = PUIQuest.Tracker and PUIQuest.Tracker.GetActiveTarget and PUIQuest.Tracker:GetActiveTarget()
            if target and target.x and target.y and not target.isDifferentZone then
                mapContext.DrawRouteLine(px * 100, py * 100, target.x * 100, target.y * 100, 0.25, 0.85, 1.0, 0.85)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Public API & Provider Registration
--------------------------------------------------------------------------------
if Primus.PUIMap then
    Primus.PUIMap:RegisterPinProvider("PUIQuest", 10, function(mapContext)
        Map:RenderQuestPins(mapContext)
    end)
end

function Map:Update()
    if Primus.PUIMap then
        Primus.PUIMap:Refresh()
    end
end

function Map:ClearPins()
    if Primus.PUIMap then
        Primus.PUIMap:Refresh()
    end
end

function Map:ClearRoute()
    if Primus.PUIMap then
        Primus.PUIMap:Refresh()
    end
end

function Map:DrawRouteLine(x1, y1, x2, y2, r, g, b, a)
    -- Deprecated direct call; automatically handled by PUIMap provider
end
