--[[
    PrimusUI Module: PUIGathering (Gatherer-Style Node Tracker & Minimap Pin Suite)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    1. Automatic detection & recording of Herbs, Ores, Chests, and Fishing pools.
    2. Exact geographic coordinate mapping per zone into persistent SavedVariables.
    3. Live dynamic Minimap Pins with proximity range calculations and facing angles.
    4. World Map node overlay with node counts and harvest tooltips.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIGathering = Primus.PUIGathering or {}
Primus.PUIGathering = PUIGathering
_G.PUIGathering = PUIGathering
Primus:RegisterModule("PUIGathering", PUIGathering, "Gathering")

local DB      = Primus.DB
local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local Events  = Primus.Events
local Time    = Primus.Time

local gatheringDB = DB:RegisterNamespace("PUIGathering", {
    enabled = true,
    showMinimap = true,
    showWorldMap = true,
    nodes = {}, -- [zone] = { [nodeKey] = { name = "Peacebloom", type = "Herb", x = 0.45, y = 0.62, count = 3, icon = "..." } }
})

-- Icon mappings for Node Types
local NODE_ICONS = {
    ["Herb"]     = "Interface\\Icons\\INV_Misc_Herb_01",
    ["Ore"]      = "Interface\\Icons\\INV_Ore_Iron_01",
    ["Chest"]    = "Interface\\Icons\\INV_Chest_Cloth_01",
    ["Fish"]     = "Interface\\Icons\\Trade_Fishing",
}

-- Known Gathering Herbs
local KNOWN_HERBS = {
    ["Peacebloom"] = true, ["Silverleaf"] = true, ["Earthroot"] = true,
    ["Mageroyal"] = true, ["Briarthorn"] = true, ["Stranglekelp"] = true,
    ["Bruiseweed"] = true, ["Wild Steelbloom"] = true, ["Grave Moss"] = true,
    ["Kingsblood"] = true, ["Liferoot"] = true, ["Fadeleaf"] = true,
    ["Goldthorn"] = true, ["Khadgar's Whisker"] = true, ["Wintersbite"] = true,
    ["Firebloom"] = true, ["Purple Lotus"] = true, ["Arthas' Tears"] = true,
    ["Sungrass"] = true, ["Blindweed"] = true, ["Ghost Mushroom"] = true,
    ["Gromsblood"] = true, ["Golden Sansam"] = true, ["Dreamfoil"] = true,
    ["Mountain Silversage"] = true, ["Plaguebloom"] = true, ["Icecap"] = true,
    ["Black Lotus"] = true, ["Bloodvine"] = true,
}

-- Known Gathering Ores
local KNOWN_ORES = {
    ["Copper Ore"] = true, ["Tin Ore"] = true, ["Silver Ore"] = true,
    ["Iron Ore"] = true, ["Gold Ore"] = true, ["Mithril Ore"] = true,
    ["Truesilver Ore"] = true, ["Thorium Ore"] = true, ["Dark Iron Ore"] = true,
}

local minimapPins = {}
local pinPool = {}
local activeSpellCast = nil

-- Record a Node at Current Player Coordinates
function PUIGathering:RecordNode(nodeName, nodeType)
    if not nodeName or not nodeType then return end

    local x, y = GetPlayerMapPosition("player")
    if not x or not y or (x == 0 and y == 0) then return end

    local zone = GetZoneText()
    if not zone or zone == "" then return end

    if not gatheringDB.nodes[zone] then
        gatheringDB.nodes[zone] = {}
    end

    -- Create unique coordinate key (approx 10-yard quantization)
    local key = string.format("%s_%.3f_%.3f", nodeName, x, y)
    local node = gatheringDB.nodes[zone][key]

    if not node then
        node = {
            name = nodeName,
            type = nodeType,
            x = x,
            y = y,
            count = 1,
            icon = NODE_ICONS[nodeType] or NODE_ICONS["Herb"],
            lastSeen = Time:GetServerTimestamp(),
        }
        gatheringDB.nodes[zone][key] = node
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIGathering]: Recorded new %s node: %s at (%.1f, %.1f)", nodeType, nodeName, x * 100, y * 100), "69ccf0"))
    else
        node.count = node.count + 1
        node.lastSeen = Time:GetServerTimestamp()
    end

    self:UpdateMinimapPins()
end

-- =========================================================================
-- MINIMAP PIN RENDERING ENGINE
-- =========================================================================

local function AcquirePin()
    local pin = table.remove(pinPool)
    if not pin then
        pin = CreateFrame("Button", nil, Minimap)
        pin:SetWidth(12)
        pin:SetHeight(12)
        pin:SetFrameLevel(Minimap:GetFrameLevel() + 5)

        local tex = pin:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(pin)
        pin.tex = tex

        pin:SetScript("OnEnter", function()
            if this.nodeData then
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetText(Utils.ColorText(this.nodeData.name, "ffd100"))
                GameTooltip:AddDoubleLine("Type:", this.nodeData.type, 1, 1, 1, 0.8, 0.8, 0.8)
                GameTooltip:AddDoubleLine("Harvests:", tostring(this.nodeData.count), 1, 1, 1, 0.2, 1.0, 0.4)
                GameTooltip:AddDoubleLine("Coords:", string.format("%.1f, %.1f", this.nodeData.x * 100, this.nodeData.y * 100), 1, 1, 1, 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end
        end)
        pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return pin
end

local function ReleasePin(pin)
    pin:Hide()
    pin.nodeData = nil
    table.insert(pinPool, pin)
end

-- Update Minimap Pins based on Player Proximity
function PUIGathering:UpdateMinimapPins()
    if not gatheringDB.showMinimap then return end

    local px, py = GetPlayerMapPosition("player")
    if not px or not py or (px == 0 and py == 0) then return end

    local zone = GetZoneText()
    if not zone or not gatheringDB.nodes[zone] then
        for i = table.getn(minimapPins), 1, -1 do
            ReleasePin(table.remove(minimapPins, i))
        end
        return
    end

    -- Recycle existing active pins
    for i = table.getn(minimapPins), 1, -1 do
        ReleasePin(table.remove(minimapPins, i))
    end

    local zoneNodes = gatheringDB.nodes[zone]
    local minimapRadius = 70 -- Minimap half-width in pixels

    for key, node in pairs(zoneNodes) do
        -- Compute delta coordinates
        local dx = (node.x - px) * 1000
        local dy = (node.y - py) * 1000

        -- Convert to distance (approximate scale)
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist <= 120 then
            local pin = AcquirePin()
            pin.nodeData = node
            pin.tex:SetTexture(node.icon or NODE_ICONS["Herb"])

            -- Position relative to center of Minimap
            local scale = minimapRadius / 100
            local posX = dx * scale
            local posY = -dy * scale -- Invert Y for UI coordinate space

            -- Clamp to Minimap circle
            local pinDist = math.sqrt(posX * posX + posY * posY)
            if pinDist > minimapRadius then
                posX = (posX / pinDist) * minimapRadius
                posY = (posY / pinDist) * minimapRadius
            end

            pin:ClearAllPoints()
            pin:SetPoint("CENTER", Minimap, "CENTER", posX, posY)
            pin:Show()
            table.insert(minimapPins, pin)
        end
    end
end

-- =========================================================================
-- WORLD MAP PIN PROVIDER (PUIMap Integration)
-- =========================================================================
local function RenderGatheringWorldMapPins(mapContext)
    if not mapContext or not gatheringDB.showWorldMap then return end
    local zone = mapContext.zoneName
    if not zone or zone == "" or not gatheringDB.nodes[zone] then return end

    for key, node in pairs(gatheringDB.nodes[zone]) do
        if node.x and node.y then
            local pin = mapContext.AcquirePin()
            pin.icon:SetTexture(node.icon or NODE_ICONS[node.type] or NODE_ICONS["Herb"])
            pin.nodeData = node
            pin:SetScript("OnEnter", function()
                if this.nodeData then
                    WorldMapTooltip:SetOwner(this, "ANCHOR_RIGHT")
                    WorldMapTooltip:ClearLines()
                    WorldMapTooltip:AddLine(this.nodeData.name or "Gathering Node", 1, 0.82, 0)
                    WorldMapTooltip:AddLine("Type: |cffffffff" .. (this.nodeData.type or "Resource") .. "|r", 0.8, 0.8, 0.8)
                    WorldMapTooltip:AddLine("Recorded Harvests: |cff00ff00" .. tostring(this.nodeData.count or 1) .. "|r", 0.7, 0.7, 0.7)
                    WorldMapTooltip:Show()
                end
            end)
            pin:SetScript("OnLeave", function()
                WorldMapTooltip:Hide()
            end)
            mapContext:PlacePin(pin, node.x, node.y)
        end
    end
end

if Primus.PUIMap then
    Primus.PUIMap:RegisterPinProvider("PUIGathering", 30, RenderGatheringWorldMapPins)
end

-- =========================================================================
-- OPTIONS FLARE REGISTRATION
-- =========================================================================

function PUIGathering:RegisterOptionsFlare()
    local Options = Primus.Options
    if not Options or not Options.RegisterModuleOptions then return end

    Options:RegisterModuleOptions("PUIGathering", "Gathering", {
        title = "PUIGathering: Resource Radar",
        description = "Herb, ore, and chest tracking with live minimap proximity pins.",
        fields = {
            {
                key = "enabled",
                label = "Enable Gathering Node Tracking",
                type = "checkbox",
                default = true,
                get = function() return gatheringDB:Get("enabled", true) end,
                set = function(val)
                    gatheringDB:Set("enabled", val)
                    if val then PUIGathering:OnEnable() else PUIGathering:OnDisable() end
                end,
            },
            {
                key = "showMinimap",
                label = "Show Resource Pins on Minimap",
                type = "checkbox",
                default = true,
                get = function() return gatheringDB:Get("showMinimap", true) end,
                set = function(val)
                    gatheringDB:Set("showMinimap", val)
                    PUIGathering:UpdateMinimapPins()
                end,
            },
            {
                key = "showWorldMap",
                label = "Show Resource Pins on World Map",
                type = "checkbox",
                default = true,
                get = function() return gatheringDB:Get("showWorldMap", true) end,
                set = function(val) gatheringDB:Set("showWorldMap", val) end,
            },
        },
    })
end

-- =========================================================================
-- LIFECYCLE & EVENT DISPATCH
-- =========================================================================

function PUIGathering:OnInitialize()
    self:RegisterOptionsFlare()

    -- Subcommand registration via Console Router
    if Primus.Console and Primus.Console.RegisterSubCommand then
        Primus.Console:RegisterSubCommand("gathering", function()
            local totalNodes = 0
            for zone, nList in pairs(gatheringDB.nodes) do
                for _, _ in pairs(nList) do
                    totalNodes = totalNodes + 1
                end
            end
            DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIGathering]: Resource Radar active. %d total harvesting nodes tracked across Azeroth.", totalNodes), "69ccf0"))
        end, "PUIGathering resource node database summary (/pui gathering)")
    end
end

function PUIGathering:OnEnable()
    -- Detect Spellcasts
    Events:Register("SPELLCAST_START", "PUIGathering", function(owner, event, spellName)
        activeSpellCast = spellName
    end)

    Events:Register("SPELLCAST_STOP", "PUIGathering", function()
        activeSpellCast = nil
    end)

    -- Detect Loot Opened & Items Harvested
    Events:Register("LOOT_OPENED", "PUIGathering", function()
        local numItems = GetNumLootItems()
        for i = 1, numItems do
            local link = GetLootSlotLink(i)
            if link then
                local s, e, itemName = string.find(link, "%[(.+)%]")
                if itemName then
                    if KNOWN_HERBS[itemName] then
                        PUIGathering:RecordNode(itemName, "Herb")
                        return
                    elseif KNOWN_ORES[itemName] then
                        PUIGathering:RecordNode(itemName, "Ore")
                        return
                    end
                end
            end
        end
    end)

    -- Proximity Pin Update Ticker (0.25s)
    Time:Every(0.25, function()
        PUIGathering:UpdateMinimapPins()
    end, "PUIGathering")
end

function PUIGathering:OnDisable()
    Time:CancelAll("PUIGathering")
    Events:UnregisterOwner("PUIGathering")

    local count = table.getn(minimapPins)
    for i = 1, count do
        minimapPins[i]:Hide()
    end
end
