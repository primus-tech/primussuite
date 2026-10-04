--[[
    PrimusUI Module: PUIQuest (Minimap Radar & Dual 2D/3D HUD Navigation Arrow Engine)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Features:
    1. Dual 2D/3D Navigation Arrow: High-definition rotating arrow texture (360° affine SetTexCoord)
       with 108-frame 3D sprite sheet and real-time distance in yards.
    2. Dynamic Proximity & Angle Tinting: Real-time emerald/gold/amber coloring based on player bearing.
    3. Multi-Zone Objective Resolution: Accurately maps standard zones and custom subzones (including Turtle WoW).
    4. Smart Objective Priority & Progress Awareness: Evaluates quest log leaderboards to filter out
       already-completed sub-objectives, targeting only active goals or turn-ins.
    5. Minimap Perimeter Radar: Calibrated radial & square boundary clamping across various minimap
       geometries (Circle, Square, Auto) without unnatural sliding or orbiting.
    6. Cross-Zone Guidance: Shows destination zone when objective is in another area.
    7. PUIMover Support: Move and anchor the HUD navigation arrow anywhere.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIQuest = Primus.PUIQuest or {}
Primus.PUIQuest = PUIQuest
_G.PUIQuest = PUIQuest

local Tracker = {}
PUIQuest.Tracker = Tracker

local Utils    = Primus.Utils
local Media    = Primus.Media
local Events   = Primus.Events
local PUIMover = Primus.PUIMover

-- State Variables
local hudArrow          = nil
local hudArrowHolder    = nil
local hudArrowTex       = nil
local hudDistText       = nil
local hudTitleText      = nil
local minimapPin        = nil
local minimapTex        = nil

local manualFocusQuest  = nil
local currentActiveData = nil
local lastPlayerX       = 0
local lastPlayerY       = 0
local estimatedFacing   = 0

local minimapPlayerModel = nil
local lastFacingSource   = "None"

-- Minimap zoom constants for 1.12.1
local MINIMAP_ZOOM_TABLE = {
    [0] = { [0] = 300, [1] = 240, [2] = 180, [3] = 120, [4] = 80, [5] = 50 }, -- Indoor
    [1] = { [0] = 466.667, [1] = 400, [2] = 333.333, [3] = 266.333, [4] = 200, [5] = 133.333 }, -- Outdoor
}

local function GetMinimapIndoorState()
    local tempzoom = 0
    local state = 1
    if GetCVar then
        local ok1, mz = pcall(GetCVar, "minimapZoom")
        local ok2, miz = pcall(GetCVar, "minimapInsideZoom")
        if ok1 and ok2 and mz and miz and mz == miz then
            local n = tonumber(miz) or 0
            if n >= 3 then
                Minimap:SetZoom(Minimap:GetZoom() - 1)
                tempzoom = 1
            else
                Minimap:SetZoom(Minimap:GetZoom() + 1)
                tempzoom = -1
            end
        end
        local ok3, curInside = pcall(GetCVar, "minimapInsideZoom")
        if ok3 and (tonumber(curInside) or 0) == Minimap:GetZoom() then
            state = 0
        end
        Minimap:SetZoom(Minimap:GetZoom() + tempzoom)
    end
    return state
end

local function GetRealPlayerFacing()
    -- 1. Try global GetPlayerFacing API
    if GetPlayerFacing then
        local ok, f = pcall(GetPlayerFacing)
        if ok and type(f) == "number" then
            lastFacingSource = "GetPlayerFacing API"
            return f
        end
    end

    -- 2. Try cached minimap model
    if minimapPlayerModel then
        local ok, f = pcall(function() return minimapPlayerModel:GetFacing() end)
        if ok and type(f) == "number" then
            lastFacingSource = "Minimap Arrow (Cached)"
            return f
        end
        minimapPlayerModel = nil
    end

    -- 3. Check Minimap Child #9 FIRST (Standard Blizzard 1.12.1 Minimap Arrow Model)
    if Minimap then
        local children = { Minimap:GetChildren() }
        local c9 = children[9]
        if c9 and c9.GetFacing then
            local ok, f = pcall(function() return c9:GetFacing() end)
            if ok and type(f) == "number" then
                minimapPlayerModel = c9
                lastFacingSource = "Minimap Arrow (Child #9)"
                return f
            end
        end

        -- 4. Search other Minimap children for Model frames with GetFacing (skip child #1 / CompassRing)
        local n = table.getn(children)
        for i = n, 2, -1 do
            local child = children[i]
            if child and child.GetFacing and child ~= children[1] then
                local name = (child.GetName and child:GetName()) or ""
                local nameLower = string.lower(name)
                if not string.find(nameLower, "compass") and not string.find(nameLower, "ring") then
                    local ok, f = pcall(function() return child:GetFacing() end)
                    if ok and type(f) == "number" then
                        minimapPlayerModel = child
                        lastFacingSource = string.format("Minimap Model (Child #%d)", i)
                        return f
                    end
                end
            end
        end
    end

    -- 5. Fallback to movement displacement delta
    lastFacingSource = "Motion Displacement Delta"
    return estimatedFacing or 0
end

function Tracker:ResetFacingModel()
    minimapPlayerModel = nil
end

function Tracker:GetFacingInfo()
    local pf = GetRealPlayerFacing()
    return pf, lastFacingSource
end

-- =========================================================================
-- 3D SPRITE ARROW ENGINE (108-FRAME CELL RESOLVER)
-- =========================================================================

local ARROW_TEXTURE_PATH = "Interface\\AddOns\\PrimusUI\\Media\\Textures\\3darrow.tga"

local function Set3DArrowAngle(tex, angle)
    if not tex then return end
    local twoPi = 2 * math.pi
    local a = math.mod(angle, twoPi)
    if a < 0 then a = a + twoPi end

    -- 108 frames across 2*pi radians (9 columns x 12 rows, 3.33° per frame)
    -- Frame 0 is centered at 0 rad (Forward / North)
    local frame = math.mod(math.floor((a / (twoPi / 108)) + 0.5), 108)
    
    local col = math.mod(frame, 9)
    local row = math.floor(frame / 9)

    -- Inset by 0.001 to prevent texture bleeding from neighboring cells
    local left = col * (1 / 9) + 0.001
    local right = (col + 1) * (1 / 9) - 0.001
    local top = row * (1 / 12) + 0.001
    local bottom = (row + 1) * (1 / 12) - 0.001

    tex:SetTexCoord(left, right, top, bottom)
end

-- =========================================================================
-- WIDGET CREATION (HUD ARROW & MINIMAP RADAR)
-- =========================================================================

local function CreateHUDArrow()
    if hudArrow then return hudArrow end

    hudArrow = CreateFrame("Frame", "PUIQuestHUDArrow", UIParent)
    hudArrow:SetWidth(156)
    hudArrow:SetHeight(68)
    hudArrow:SetPoint("CENTER", UIParent, "CENTER", 0, -130)
    hudArrow:SetFrameStrata("BACKGROUND")
    hudArrow:SetClampedToScreen(true)
    hudArrow:EnableMouse(false)

    -- Glassmorphic pill backdrop
    hudArrow:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    hudArrow:SetBackdropColor(0.04, 0.06, 0.09, 0.88)
    hudArrow:SetBackdropBorderColor(0.20, 0.35, 0.55, 0.90)

    -- Arrow Container Frame (4:3 aspect ratio matching 316x237 cell dimensions)
    local arrowHolder = CreateFrame("Frame", nil, hudArrow)
    arrowHolder:SetWidth(44)
    arrowHolder:SetHeight(33)
    arrowHolder:SetPoint("TOP", hudArrow, "TOP", 0, -3)
    arrowHolder:EnableMouse(false)
    hudArrowHolder = arrowHolder

    -- 3D Rotating Texture Arrow (108-frame rendered sprite sheet)
    local arrowTex = arrowHolder:CreateTexture(nil, "ARTWORK")
    arrowTex:SetTexture(ARROW_TEXTURE_PATH)
    arrowTex:SetAllPoints(arrowHolder)
    arrowTex:SetVertexColor(1.0, 0.85, 0.1, 1.0)
    Set3DArrowAngle(arrowTex, 0)
    hudArrowTex = arrowTex

    -- Distance FontString
    local dist = hudArrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dist:SetPoint("TOP", arrowHolder, "BOTTOM", 0, 0)
    local distFont = (Media and Media.Fetch and Media:Fetch("font", "Default")) or "Fonts\\FRIZQT__.TTF"
    dist:SetFont(distFont, 11, "OUTLINE")
    dist:SetTextColor(1.0, 1.0, 1.0)
    hudDistText = dist

    -- Quest / Objective Title FontString
    local title = hudArrow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", dist, "BOTTOM", 0, -1)
    local titleFont = (Media and Media.Fetch and Media:Fetch("font", "Default")) or "Fonts\\FRIZQT__.TTF"
    title:SetFont(titleFont, 10, "OUTLINE")
    title:SetTextColor(0.9, 0.8, 0.5)
    title:SetWidth(150)
    title:SetJustifyH("CENTER")
    hudTitleText = title

    -- Self-driving real-time update loop (throttled to 0.03s for super-smooth 60fps tracking)
    local updateElapsed = 0
    hudArrow:SetScript("OnUpdate", function()
        updateElapsed = updateElapsed + (arg1 or 0.03)
        if updateElapsed >= 0.03 then
            updateElapsed = 0
            Tracker:Update()
        end
    end)

    -- Register with PUIMover
    if PUIMover and PUIMover.Register then
        PUIMover:Register(hudArrow, "PUIQuestHUDArrow", "Quest Navigation Arrow", "HUD")
    end

    hudArrow:Hide()
    return hudArrow
end

local function CreateMinimapPin()
    if minimapPin then return minimapPin end

    minimapPin = CreateFrame("Button", "PUIQuest_MinimapNavArrow", Minimap)
    minimapPin:SetWidth(24)
    minimapPin:SetHeight(18)
    minimapPin:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
    minimapPin:SetFrameLevel(Minimap:GetFrameLevel() + 10)

    local tex = minimapPin:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(ARROW_TEXTURE_PATH)
    tex:SetAllPoints(minimapPin)
    Set3DArrowAngle(tex, 0)
    minimapTex = tex

    minimapPin:SetScript("OnClick", function()
        if currentActiveData and currentActiveData.title then
            if not QuestLogFrame:IsVisible() then ShowUIPanel(QuestLogFrame) end
        end
    end)

    minimapPin:Hide()
    return minimapPin
end

-- =========================================================================
-- ZONE ALIASES & MULTI-ZONE COORDINATE RESOLVER
-- =========================================================================

local function GetPlayerZoneAliases()
    local aliases = {}

    local mapContinent = GetCurrentMapContinent()
    local mapZone = GetCurrentMapZone()
    if mapContinent > 0 and mapZone > 0 then
        local zoneNames = { GetMapZones(mapContinent) }
        local mzName = zoneNames[mapZone]
        if mzName and mzName ~= "" then
            aliases[string.lower(mzName)] = true
        end
    end

    local z = GetZoneText and GetZoneText()
    if z and z ~= "" then aliases[string.lower(z)] = true end

    local rz = GetRealZoneText and GetRealZoneText()
    if rz and rz ~= "" then aliases[string.lower(rz)] = true end

    local sz = GetSubZoneText and GetSubZoneText()
    if sz and sz ~= "" then aliases[string.lower(sz)] = true end

    local mz = GetMinimapZoneText and GetMinimapZoneText()
    if mz and mz ~= "" then aliases[string.lower(mz)] = true end

    -- Expand parent zones: If any current alias matches a subzone in DB, also add the parent zone name
    local DB = PUIQuest.DB
    if DB and DB["zones"] then
        local zonesLoc = DB["zones"]["enUS"] or DB["zones"]["loc"]
        local zonesData = DB["zones"]["data"]
        if zonesLoc and zonesData then
            for zID, name in pairs(zonesLoc) do
                if aliases[string.lower(name)] then
                    local zInfo = zonesData[zID]
                    if zInfo then
                        local pID = zInfo[1]
                        if pID and pID > 0 and zonesLoc[pID] then
                            aliases[string.lower(zonesLoc[pID])] = true
                        end
                    end
                end
            end
        end
    end

    return aliases, mapZone
end

local function ExtractZoneCoords(spawnsTbl, playerZones, currentMapZoneID)
    if not spawnsTbl then return {}, {} end
    local coordsList = spawnsTbl.coords or (type(spawnsTbl[1]) == "table" and spawnsTbl)
    if not coordsList then return {}, {} end

    local DB = PUIQuest.DB
    if not DB or not DB["zones"] then return {}, {} end

    local zonesLoc = DB["zones"]["enUS"] or DB["zones"]["loc"]
    local zonesData = DB["zones"]["data"]
    if not zonesLoc then return {}, {} end

    local localResults = {}
    local worldResults = {}

    for _, c in pairs(coordsList) do
        local x = c[1]
        local y = c[2]
        local zID = c[3]

        if zID and x and y then
            local zName = zonesLoc[zID]
            local isLocal = false
            local resolvedX = x / 100
            local resolvedY = y / 100
            local resolvedZoneName = zName or "Zone"

            -- Direct zone match
            if zName and playerZones[string.lower(zName)] then
                isLocal = true
            elseif currentMapZoneID and currentMapZoneID > 0 and zID == currentMapZoneID then
                isLocal = true
            elseif zonesData and zonesData[zID] then
                -- Parent zone projection
                local pID, w, h, ox, oy = unpack(zonesData[zID])
                if pID and pID > 0 then
                    local pName = zonesLoc[pID]
                    if pName and (playerZones[string.lower(pName)] or (currentMapZoneID and pID == currentMapZoneID)) then
                        resolvedX = ((x * (w or 100) / 100) + (ox or 0)) / 100
                        resolvedY = ((y * (h or 100) / 100) + (oy or 0)) / 100
                        resolvedZoneName = pName
                        isLocal = true
                    end
                end
            end

            local entry = {
                x = resolvedX,
                y = resolvedY,
                zoneID = zID,
                zoneName = resolvedZoneName,
            }

            if isLocal then
                table.insert(localResults, entry)
            else
                table.insert(worldResults, entry)
            end
        end
    end

    return localResults, worldResults
end

-- Scan quest log leaderboards to build a completion map for sub-objectives
local function GetQuestObjectiveProgress(questTitle)
    local numEntries = GetNumQuestLogEntries() or 0
    local qlogid = nil
    local isComplete = false

    for i = 1, numEntries do
        local title, _, _, isHeader, _, comp = GetQuestLogTitle(i)
        if not isHeader and title and string.lower(title) == string.lower(questTitle) then
            qlogid = i
            isComplete = (comp == 1 or comp == true)
            break
        end
    end

    local finishedObjs = {}
    if qlogid then
        local numObjectives = GetNumQuestLeaderBoards(qlogid) or 0
        if numObjectives == 0 and isComplete then
            -- No leaderboards, quest is complete
            return true, finishedObjs, qlogid
        end

        local allDone = (numObjectives > 0)
        for i = 1, numObjectives do
            local text, objType, finished = GetQuestLogLeaderBoard(i, qlogid)
            if finished then
                if text then
                    finishedObjs[string.lower(text)] = true
                    local _, _, name = string.find(text, "^(.-):")
                    if name then
                        finishedObjs[string.lower(Utils.Trim(name))] = true
                    end
                end
            else
                allDone = false
            end
        end

        if allDone and numObjectives > 0 then
            isComplete = true
        end
    end

    return isComplete, finishedObjs, qlogid
end

-- Find the best objective coordinate for a given quest
local function ResolveQuestObjective(questTitle, playerZones, currentMapZoneID, playerX, playerY)
    if not questTitle or questTitle == "" then return nil end
    local q = PUIQuest.Database:FindQuest(questTitle)
    if not q or not q.data then return nil end

    local isComplete, finishedObjs, qlogid = GetQuestObjectiveProgress(questTitle)

    local bestLocalCoord = nil
    local bestLocalDist = 999999
    local bestLocalText = nil

    local firstWorldCoord = nil
    local firstWorldText = nil

    local function Evaluate(spawns, labelText, objIdentifier)
        if not spawns then return end

        -- Skip if this sub-objective is already marked finished in the quest log
        if objIdentifier and finishedObjs[string.lower(objIdentifier)] then
            return
        end

        local localCoords, worldCoords = ExtractZoneCoords(spawns, playerZones, currentMapZoneID)

        for _, coord in ipairs(localCoords) do
            local dx = coord.x - playerX
            local dy = coord.y - playerY
            local distSq = dx * dx + dy * dy
            if distSq < bestLocalDist then
                bestLocalDist = distSq
                bestLocalCoord = coord
                bestLocalText = labelText
            end
        end

        if not firstWorldCoord and table.getn(worldCoords) > 0 then
            firstWorldCoord = worldCoords[1]
            firstWorldText = labelText
        end
    end

    -- If Quest is COMPLETE: Point to Turn-in NPC / Object
    if isComplete then
        local endUnits = q.data["end"] and q.data["end"]["U"]
        if endUnits then
            for _, uID in pairs(endUnits) do
                local unit = PUIQuest.Database:FindUnit(uID)
                if unit and unit.spawns then
                    Evaluate(unit.spawns, "Turn in: " .. unit.name)
                end
            end
        end
        local endObjects = q.data["end"] and q.data["end"]["O"]
        if endObjects then
            for _, oID in pairs(endObjects) do
                local obj = PUIQuest.Database:FindObject(oID)
                if obj and obj.spawns then
                    Evaluate(obj.spawns, "Turn in: " .. obj.name)
                end
            end
        end
    else
        -- If Quest is IN PROGRESS: Check Slay/Interact/Loot objectives FIRST

        -- 1. Unit Objectives (Slay / Talk)
        local objUnits = q.data["obj"] and q.data["obj"]["U"]
        if objUnits then
            for _, uID in pairs(objUnits) do
                local unit = PUIQuest.Database:FindUnit(uID)
                if unit and unit.spawns then
                    Evaluate(unit.spawns, "Slay: " .. unit.name, unit.name)
                end
            end
        end

        -- 2. Object Objectives (Interact / Nodes)
        local objObjects = q.data["obj"] and q.data["obj"]["O"]
        if objObjects then
            for _, oID in pairs(objObjects) do
                local obj = PUIQuest.Database:FindObject(oID)
                if obj and obj.spawns then
                    Evaluate(obj.spawns, "Interact: " .. obj.name, obj.name)
                end
            end
        end

        -- 3. Item Objectives (Drops / Chests / Vendors)
        local objItems = q.data["obj"] and q.data["obj"]["I"]
        if objItems then
            for _, iID in pairs(objItems) do
                local item = PUIQuest.Database:FindItem(iID)
                if item and item.data then
                    -- Dropped by Units
                    if item.data["U"] then
                        for uID in pairs(item.data["U"]) do
                            local unit = PUIQuest.Database:FindUnit(uID)
                            if unit and unit.spawns then
                                Evaluate(unit.spawns, "Loot: " .. item.name .. " (" .. unit.name .. ")", item.name)
                            end
                        end
                    end
                    -- Looted from Objects / Containers
                    if item.data["O"] then
                        for oID in pairs(item.data["O"]) do
                            local obj = PUIQuest.Database:FindObject(oID)
                            if obj and obj.spawns then
                                Evaluate(obj.spawns, "Gather: " .. item.name, item.name)
                            end
                        end
                    end
                    -- Purchased from Vendors
                    if item.data["V"] then
                        for vID in pairs(item.data["V"]) do
                            local vendor = PUIQuest.Database:FindUnit(vID)
                            if vendor and vendor.spawns then
                                Evaluate(vendor.spawns, "Buy: " .. item.name, item.name)
                            end
                        end
                    end
                end
            end
        end

        -- 4. Fallback if all sub-objectives complete or no specific objective coords: Check Turn-In
        if not bestLocalCoord and not firstWorldCoord then
            local endUnits = q.data["end"] and q.data["end"]["U"]
            if endUnits then
                for _, uID in pairs(endUnits) do
                    local unit = PUIQuest.Database:FindUnit(uID)
                    if unit and unit.spawns then
                        Evaluate(unit.spawns, "Turn in: " .. unit.name)
                    end
                end
            end
            local endObjects = q.data["end"] and q.data["end"]["O"]
            if endObjects then
                for _, oID in pairs(endObjects) do
                    local obj = PUIQuest.Database:FindObject(oID)
                    if obj and obj.spawns then
                        Evaluate(obj.spawns, "Turn in: " .. obj.name)
                    end
                end
            end
        end

        -- 5. Final Fallback: Starter NPC
        if not bestLocalCoord and not firstWorldCoord then
            local startUnits = q.data["start"] and q.data["start"]["U"]
            if startUnits then
                for _, uID in pairs(startUnits) do
                    local unit = PUIQuest.Database:FindUnit(uID)
                    if unit and unit.spawns then
                        Evaluate(unit.spawns, "Start: " .. unit.name)
                    end
                end
            end
        end
    end

    if bestLocalCoord then
        return {
            x = bestLocalCoord.x,
            y = bestLocalCoord.y,
            title = questTitle,
            text = bestLocalText or questTitle,
            zoneID = bestLocalCoord.zoneID,
            zoneName = bestLocalCoord.zoneName,
            isDifferentZone = false,
        }
    elseif firstWorldCoord then
        return {
            x = firstWorldCoord.x,
            y = firstWorldCoord.y,
            title = questTitle,
            text = firstWorldText or questTitle,
            zoneID = firstWorldCoord.zoneID,
            zoneName = firstWorldCoord.zoneName,
            isDifferentZone = true,
        }
    end

    return nil
end

-- =========================================================================
-- PUBLIC API & FOCUS MANAGEMENT
-- =========================================================================

function Tracker:SetFocus(questTitle)
    manualFocusQuest = questTitle
    self:Update()
end

function Tracker:GetFocus()
    return manualFocusQuest
end

function Tracker:GetActiveTarget()
    return currentActiveData
end

-- =========================================================================
-- LIVE REAL-TIME RADAR & ARROW UPDATE
-- =========================================================================

function Tracker:Update()
    if not PUIQuest.db or not PUIQuest.db:Get("enabled", true) or not PUIQuest.db:Get("showMinimapPins", true) then
        if hudArrow then hudArrow:Hide() end
        if minimapPin then minimapPin:Hide() end
        currentActiveData = nil
        return
    end

    local px, py = GetPlayerMapPosition("player")
    if (not px or px == 0) and (not py or py == 0) then
        if not WorldMapFrame or not WorldMapFrame:IsVisible() then
            SetMapToCurrentZone()
            px, py = GetPlayerMapPosition("player")
        end
    end
    px = px or 0
    py = py or 0

    -- Estimate player facing if GetPlayerFacing is unavailable (CCW radians)
    if px > 0 and py > 0 and (px ~= lastPlayerX or py ~= lastPlayerY) then
        local mdx = px - lastPlayerX
        local mdy = py - lastPlayerY
        if (mdx * mdx + mdy * mdy) > 0.0000000001 then
            estimatedFacing = -math.atan2(mdx, -mdy)
        end
        lastPlayerX = px
        lastPlayerY = py
    end

    local playerZones, mapZone = GetPlayerZoneAliases()

    -- Find target: either manual focus, tracked list, or active quest log
    local resolvedTarget = nil

    if manualFocusQuest then
        resolvedTarget = ResolveQuestObjective(manualFocusQuest, playerZones, mapZone, px, py)
    else
        local trackedList = Primus.PUIQuestWatch and Primus.PUIQuestWatch.GetTrackedList and Primus.PUIQuestWatch:GetTrackedList() or {}
        local nearestLocalTarget = nil
        local nearestLocalDist = 999999
        local fallbackWorldTarget = nil

        for qTitle in pairs(trackedList) do
            local cand = ResolveQuestObjective(qTitle, playerZones, mapZone, px, py)
            if cand then
                if not cand.isDifferentZone then
                    local cdx = cand.x - px
                    local cdy = cand.y - py
                    local cdist = cdx * cdx + cdy * cdy
                    if cdist < nearestLocalDist then
                        nearestLocalDist = cdist
                        nearestLocalTarget = cand
                    end
                elseif not fallbackWorldTarget then
                    fallbackWorldTarget = cand
                end
            end
        end

        -- Fallback: If no target found from tracked list, check all active Quest Log entries
        if not nearestLocalTarget and not fallbackWorldTarget then
            local numEntries = GetNumQuestLogEntries() or 0
            for i = 1, numEntries do
                local title, _, _, isHeader = GetQuestLogTitle(i)
                if not isHeader and title then
                    local cand = ResolveQuestObjective(title, playerZones, mapZone, px, py)
                    if cand then
                        if not cand.isDifferentZone then
                            local cdx = cand.x - px
                            local cdy = cand.y - py
                            local cdist = cdx * cdx + cdy * cdy
                            if cdist < nearestLocalDist then
                                nearestLocalDist = cdist
                                nearestLocalTarget = cand
                            end
                        elseif not fallbackWorldTarget then
                            fallbackWorldTarget = cand
                        end
                    end
                end
            end
        end

        resolvedTarget = nearestLocalTarget or fallbackWorldTarget
    end

    if not resolvedTarget then
        if hudArrow then hudArrow:Hide() end
        if minimapPin then minimapPin:Hide() end
        currentActiveData = nil
        return
    end

    -- 1. UPDATE 3D/2D HUD NAVIGATION ARROW
    local arrow = CreateHUDArrow()
    arrow:Show()

    if resolvedTarget.isDifferentZone then
        resolvedTarget.yards = nil
        currentActiveData = resolvedTarget

        if hudArrowTex then
            hudArrowTex:Show()
            Set3DArrowAngle(hudArrowTex, 0)
            hudArrowTex:SetVertexColor(1.0, 0.75, 0.2, 1.0)
        end
        hudDistText:SetText(string.format("|cffffbb33In %s|r", resolvedTarget.zoneName or "Other Area"))
        hudTitleText:SetText(resolvedTarget.text or resolvedTarget.title or "Quest Objective")
        if minimapPin then minimapPin:Hide() end
        return
    end

    -- Query Zone Dimensions & Minimap Zoom Data
    local realZone = GetRealZoneText and GetRealZoneText() or ""
    local mapID = (PUIQuest.Database and PUIQuest.Database.GetMapIDByName and PUIQuest.Database:GetMapIDByName(realZone)) or mapZone
    local indoorState = GetMinimapIndoorState()
    local mZoom = (Minimap and Minimap.GetZoom and Minimap:GetZoom()) or 0
    local mapZoom = (MINIMAP_ZOOM_TABLE[indoorState] and MINIMAP_ZOOM_TABLE[indoorState][mZoom]) or 300

    local DB = PUIQuest.DB
    local minimapSizes = DB and DB["minimap"]
    local mapWidth = (minimapSizes and mapID and minimapSizes[mapID] and minimapSizes[mapID][1]) or 0
    local mapHeight = (minimapSizes and mapID and minimapSizes[mapID] and minimapSizes[mapID][2]) or 0

    local tx = resolvedTarget.x
    local ty = resolvedTarget.y
    local rawDx = tx - px
    local rawDy = ty - py

    -- Calculate Yard Distance
    local yards = 0
    if mapWidth > 0 and mapHeight > 0 then
        local dxYd = rawDx * mapWidth
        local dyYd = rawDy * mapHeight
        yards = math.floor(math.sqrt(dxYd * dxYd + dyYd * dyYd) + 0.5)
    else
        local distEst = math.sqrt((rawDx * 1.5) * (rawDx * 1.5) + rawDy * rawDy)
        yards = math.floor(distEst * 1800 + 0.5)
    end

    resolvedTarget.yards = yards
    currentActiveData = resolvedTarget

    -- Calculate Compass Bearing (CW) & CCW Target Angle
    local targetBearingCW = math.atan2(rawDx * 1.5, -rawDy)
    local targetBearingCCW = -targetBearingCW
    local playerFacingCCW = GetRealPlayerFacing()
    local relativeAngleCCW = targetBearingCCW - playerFacingCCW

    -- Dynamic Color & Text based on bearing angle & distance
    local r, g, b = 1.0, 1.0, 1.0
    if yards < 15 then
        hudDistText:SetText("|cff00ff00Arrived!|r")
        r, g, b = 0.0, 1.0, 0.5
    else
        local absAngle = math.abs(math.mod(relativeAngleCCW + math.pi, 2 * math.pi) - math.pi)
        if absAngle < 0.35 then
            hudDistText:SetText(string.format("|cff00ff00%d yd|r", yards))
            r, g, b = 0.1, 1.0, 0.2
        elseif absAngle < 1.0 then
            hudDistText:SetText(string.format("|cffffd100%d yd|r", yards))
            r, g, b = 1.0, 0.85, 0.1
        else
            hudDistText:SetText(string.format("|cffff6622%d yd|r", yards))
            r, g, b = 1.0, 0.40, 0.1
        end
    end

    hudTitleText:SetText(resolvedTarget.text or resolvedTarget.title or "Quest Objective")

    -- Rotate HUD Arrow
    if hudArrowTex then
        hudArrowTex:Show()
        Set3DArrowAngle(hudArrowTex, relativeAngleCCW)
        hudArrowTex:SetVertexColor(r, g, b, 1.0)
    end

    -- 2. UPDATE MINIMAP RADAR PIN
    local mPin = CreateMinimapPin()
    mPin:Show()

    -- Calculate Minimap Drawing Offsets
    local xDraw, yDraw
    if mapWidth > 0 and mapHeight > 0 then
        local xScale = mapZoom / mapWidth
        local yScale = mapZoom / mapHeight
        xDraw = Minimap:GetWidth() / xScale / 100
        yDraw = Minimap:GetHeight() / yScale / 100
    else
        local fallbackScale = mapZoom * 1.2
        xDraw = fallbackScale / 100 * 1.5
        yDraw = fallbackScale / 100
    end

    local xPos = rawDx * 100 * xDraw
    local yPos = rawDy * 100 * yDraw

    -- Check if Minimap Rotation is enabled
    local isRotating = false
    if GetCVar then
        local ok, val = pcall(GetCVar, "rotateMinimap")
        if ok and val == "1" then
            isRotating = true
        end
    end

    local dxScreen, dyScreen
    if isRotating then
        local cosF = math.cos(playerFacingCCW)
        local sinF = math.sin(playerFacingCCW)
        dxScreen = xPos * cosF + (-yPos) * sinF
        dyScreen = -xPos * sinF + (-yPos) * cosF
    else
        dxScreen = xPos
        dyScreen = -yPos
    end

    -- Detect Minimap Shape (Square vs Round)
    local shapeMode = PUIQuest.db and PUIQuest.db:Get("minimapShape", "auto") or "auto"
    local isSquare = false
    if shapeMode == "square" then
        isSquare = true
    elseif shapeMode == "auto" then
        if Primus.PUIMinimapper or _G.pfUI and _G.pfUI.minimap then
            isSquare = true
        end
    end

    local mw = Minimap:GetWidth()
    local mh = Minimap:GetHeight()
    local margin = 10
    local nx, ny

    if isSquare then
        -- Clamping to Square / Rectangular Bounding Box
        local hw = (mw / 2) - margin
        local hh = (mh / 2) - margin
        if math.abs(dxScreen) <= hw and math.abs(dyScreen) <= hh then
            nx = dxScreen
            ny = dyScreen
        else
            local scaleX = hw / math.max(math.abs(dxScreen), 0.0001)
            local scaleY = hh / math.max(math.abs(dyScreen), 0.0001)
            local scale = math.min(scaleX, scaleY)
            nx = dxScreen * scale
            ny = dyScreen * scale
        end
    else
        -- Clamping to Circular Perimeter
        local radius = (math.min(mw, mh) / 2) - margin
        local distOnMap = math.sqrt(dxScreen * dxScreen + dyScreen * dyScreen)
        if distOnMap > radius then
            nx = (dxScreen / distOnMap) * radius
            ny = (dyScreen / distOnMap) * radius
        else
            nx = dxScreen
            ny = dyScreen
        end
    end

    -- Orient the perimeter arrow to point towards the objective
    local pinAngleCCW = math.atan2(-dxScreen, dyScreen)
    if minimapTex then
        minimapTex:Show()
        Set3DArrowAngle(minimapTex, pinAngleCCW)
        minimapTex:SetVertexColor(r, g, b, 1.0)
    end

    mPin:ClearAllPoints()
    mPin:SetPoint("CENTER", Minimap, "CENTER", nx, ny)
end
