--[[
    PrimusUI Module: Utility_Map (PUIMap.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (Lua 5.0.2)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims, Pooled Pins)

    Subsystem: Centralized World Map & Overlay Pin Framework
    - Single owner of WORLD_MAP_UPDATE event.
    - Pooled button frame and route dot allocators with zero GC churn.
    - Automatic pin clustering & radial separation for co-located objectives/nodes/players.
    - Unified pin provider registry for PUIQuest, PUIRoleplay, and PUIGathering.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIMap = Primus.PUIMap or {}
Primus.PUIMap = PUIMap
_G.PUIMap = PUIMap
Primus:RegisterModule("PUIMap", PUIMap, "Utility")

local DB     = Primus.DB
local Events = Primus.Events
local Utils  = Primus.Utils
local Media  = Primus.Media

-- Configuration
local mapDB = DB:RegisterNamespace("PUIMap", {
    enabled = true,
    pinScale = 1.0,
    clusterSeparation = true,
    showRouteLines = true,
})

-- Pin Pools & Active Pin Registry
local pinPool = {}
local activePins = {}
local pinIndex = 0

-- Route Dot Pools & Active Dots
local dotPool = {}
local activeDots = {}
local dotIndex = 0

-- Provider Registry: array of { id = id, priority = priority, callback = callback }
local pinProviders = {}

-- Collision Tracking for Radial Separation
local placedPositions = {}

--------------------------------------------------------------------------------
-- Pool Allocators
--------------------------------------------------------------------------------
local function CreatePinFrame()
    pinIndex = pinIndex + 1
    local parent = WorldMapButton or WorldMapDetailFrame or UIParent
    local pin = CreateFrame("Button", "PUIMap_Pin_" .. pinIndex, parent)
    pin:SetWidth(18)
    pin:SetHeight(18)
    pin:SetFrameLevel(parent:GetFrameLevel() + 6)
    pin:EnableMouse(true)

    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(pin)
    pin.icon = icon

    local label = pin:CreateFontString(nil, "OVERLAY")
    local font = (Media and Media.Fetch and Media:Fetch("font", "Default")) or "Fonts\\FRIZQT__.TTF"
    label:SetFont(font, 11, "OUTLINE")
    label:SetPoint("CENTER", pin, "CENTER", 0, 0)
    pin.label = label

    return pin
end

local function AcquirePin()
    local pin = table.remove(pinPool)
    if not pin then
        pin = CreatePinFrame()
    end
    pin:ClearAllPoints()
    pin:SetWidth(18)
    pin:SetHeight(18)
    pin:SetAlpha(1.0)
    pin:SetScale(1.0)
    pin.icon:SetTexture(nil)
    pin.icon:SetTexCoord(0, 1, 0, 1)
    pin.icon:SetVertexColor(1, 1, 1, 1)
    pin.label:SetText("")
    pin.label:SetTextColor(1, 1, 1, 1)
    pin.data = nil
    pin.charName = nil
    pin.fullName = nil
    pin.isIC = nil
    pin:SetScript("OnEnter", nil)
    pin:SetScript("OnLeave", nil)
    pin:SetScript("OnClick", nil)
    table.insert(activePins, pin)
    return pin
end

local function CreateDotFrame()
    dotIndex = dotIndex + 1
    local parent = WorldMapButton or WorldMapDetailFrame or UIParent
    local dot = CreateFrame("Frame", "PUIMap_RouteDot_" .. dotIndex, parent)
    dot:SetWidth(6)
    dot:SetHeight(6)
    dot:SetFrameLevel(parent:GetFrameLevel() + 4)

    local tex = dot:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(dot)
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    dot.texture = tex
    return dot
end

local function AcquireDot()
    local dot = table.remove(dotPool)
    if not dot then
        dot = CreateDotFrame()
    end
    dot:ClearAllPoints()
    dot:SetWidth(6)
    dot:SetHeight(6)
    dot:SetAlpha(1.0)
    dot.texture:SetVertexColor(1, 1, 1, 1)
    table.insert(activeDots, dot)
    return dot
end

--------------------------------------------------------------------------------
-- Pin Placement & Radial Cluster Resolution
--------------------------------------------------------------------------------
local function PlacePinWithOffset(pin, xPct, yPct, mapW, mapH)
    -- Normalize coordinates (handle both 0..1 float and 0..100 percentage)
    local nx = (xPct > 1.0) and (xPct / 100.0) or xPct
    local ny = (yPct > 1.0) and (yPct / 100.0) or yPct

    local px = nx * mapW
    local py = -ny * mapH

    -- Collision detection key (rounded to 8px grid)
    local gridKey = string.format("%d_%d", math.floor(px / 8), math.floor(py / 8))
    local count = placedPositions[gridKey] or 0
    placedPositions[gridKey] = count + 1

    if count > 0 then
        -- Radial spiral displacement for clustered pins
        local angle = (count - 1) * 1.047 -- ~60 degrees per pin
        local radius = 10 + math.floor(count / 6) * 6
        px = px + math.cos(angle) * radius
        py = py + math.sin(angle) * radius
    end

    local parent = WorldMapButton or WorldMapDetailFrame
    pin:SetPoint("CENTER", parent, "TOPLEFT", px, py)
    pin:Show()
end

--------------------------------------------------------------------------------
-- Route Line Drawing (Dotted Trail)
--------------------------------------------------------------------------------
local function DrawRouteLine(x1, y1, x2, y2, r, g, b, a)
    local mapW = WorldMapButton and WorldMapButton:GetWidth() or (WorldMapDetailFrame and WorldMapDetailFrame:GetWidth()) or 1002
    local mapH = WorldMapButton and WorldMapButton:GetHeight() or (WorldMapDetailFrame and WorldMapDetailFrame:GetHeight()) or 668

    local nx1 = (x1 > 1.0) and (x1 / 100.0) or x1
    local ny1 = (y1 > 1.0) and (y1 / 100.0) or y1
    local nx2 = (x2 > 1.0) and (x2 / 100.0) or x2
    local ny2 = (y2 > 1.0) and (y2 / 100.0) or y2

    local px1 = nx1 * mapW
    local py1 = -ny1 * mapH
    local px2 = nx2 * mapW
    local py2 = -ny2 * mapH

    local dx = px2 - px1
    local dy = py2 - py1
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 5 then return end

    local step = 14 -- dot spacing in pixels
    local numDots = math.floor(dist / step)
    if numDots > 60 then numDots = 60 end -- throttle long trails

    local parent = WorldMapButton or WorldMapDetailFrame
    for i = 1, numDots do
        local t = i / (numDots + 1)
        local curX = px1 + dx * t
        local curY = py1 + dy * t

        local dot = AcquireDot()
        dot.texture:SetVertexColor(r or 0.2, g or 0.8, b or 1.0, a or 0.8)
        dot:SetPoint("CENTER", parent, "TOPLEFT", curX, curY)
        dot:Show()
    end
end

--------------------------------------------------------------------------------
-- Provider Management
--------------------------------------------------------------------------------
function PUIMap:RegisterPinProvider(id, priority, callback)
    if not id or type(callback) ~= "function" then return end
    priority = priority or 50

    -- Remove existing provider with same id
    self:UnregisterPinProvider(id)

    local entry = { id = id, priority = priority, callback = callback }
    table.insert(pinProviders, entry)

    -- Sort ascending by priority
    table.sort(pinProviders, function(a, b)
        return (a.priority or 50) < (b.priority or 50)
    end)

    if WorldMapFrame and WorldMapFrame:IsVisible() then
        self:Refresh()
    end
end

function PUIMap:UnregisterPinProvider(id)
    if not id then return end
    for i = table.getn(pinProviders), 1, -1 do
        if pinProviders[i].id == id then
            table.remove(pinProviders, i)
        end
    end
end

--------------------------------------------------------------------------------
-- Master Map Refresh Pipeline
--------------------------------------------------------------------------------
local isRefreshing = false

function PUIMap:ReleaseAll()
    for i = 1, table.getn(activePins) do
        local pin = activePins[i]
        pin:Hide()
        table.insert(pinPool, pin)
    end
    for k in pairs(activePins) do activePins[k] = nil end

    for i = 1, table.getn(activeDots) do
        local dot = activeDots[i]
        dot:Hide()
        table.insert(dotPool, dot)
    end
    for k in pairs(activeDots) do activeDots[k] = nil end

    for k in pairs(placedPositions) do placedPositions[k] = nil end
end

function PUIMap:Refresh()
    if not WorldMapFrame or not WorldMapFrame:IsVisible() then return end
    if isRefreshing then return end
    isRefreshing = true

    self:ReleaseAll()

    local mapW = WorldMapButton and WorldMapButton:GetWidth() or (WorldMapDetailFrame and WorldMapDetailFrame:GetWidth()) or 1002
    local mapH = WorldMapButton and WorldMapButton:GetHeight() or (WorldMapDetailFrame and WorldMapDetailFrame:GetHeight()) or 668
    local curMapZone = GetCurrentMapZone()
    local continent = GetCurrentMapContinent()
    local zones = { GetMapZones(continent) }
    local currentZoneName = zones[curMapZone] or ""

    local mapContext = {
        continent = continent,
        zone = curMapZone,
        zoneName = currentZoneName,
        mapWidth = mapW,
        mapHeight = mapH,
        AcquirePin = AcquirePin,
        PlacePin = function(ctxSelf, pin, x, y)
            PlacePinWithOffset(pin, x, y, mapW, mapH)
        end,
        DrawRouteLine = DrawRouteLine,
    }

    local numProviders = table.getn(pinProviders)
    for i = 1, numProviders do
        local provider = pinProviders[i]
        if provider and provider.callback then
            local success, err = pcall(provider.callback, mapContext)
            if not success and Primus.Log then
                Primus:Log("PUIMap provider error [" .. tostring(provider.id) .. "]: " .. tostring(err), "ERROR")
            end
        end
    end

    isRefreshing = false
end

--------------------------------------------------------------------------------
-- Event Initialization
--------------------------------------------------------------------------------
function PUIMap:OnInitialize()
    Events:Register("WORLD_MAP_UPDATE", self, function()
        PUIMap:Refresh()
    end)

    if WorldMapFrame then
        local origOnShow = WorldMapFrame:GetScript("OnShow")
        WorldMapFrame:SetScript("OnShow", function()
            if origOnShow then origOnShow() end
            PUIMap:Refresh()
        end)

        local origOnHide = WorldMapFrame:GetScript("OnHide")
        WorldMapFrame:SetScript("OnHide", function()
            if origOnHide then origOnHide() end
            PUIMap:ReleaseAll()
        end)
    end
end
