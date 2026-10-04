--[[
    PrimusUI Module: PUIMinimapper - PUICoordinates
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Subsystem: Real-Time High-Precision Player & Cursor Coordinates HUD Engine.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIMinimapper = Primus.PUIMinimapper or {}
Primus.PUIMinimapper = PUIMinimapper
_G.PUIMinimapper = PUIMinimapper

local Media = Primus.Media
local Time  = Primus.Time

-- Zone yard dimensions (Vanilla 1.12.1 zoom level yard radii)
local INDOOR_MINIMAP_RADII = {
    [0] = 200,
    [1] = 150,
    [2] = 115,
    [3] = 75,
    [4] = 50,
    [5] = 30,
}

local OUTDOOR_MINIMAP_RADII = {
    [0] = 466.66,
    [1] = 355.55,
    [2] = 266.66,
    [3] = 177.77,
    [4] = 118.51,
    [5] = 74.07,
}

-- Calculate world coordinates under the mouse cursor while hovering over the minimap
local function GetCursorMinimapCoords(playerX, playerY)
    if not Minimap or not Minimap:IsVisible() then return nil, nil end
    if not MouseIsOver(Minimap) then return nil, nil end

    local uiScale = UIParent:GetEffectiveScale() or 1
    local cursorX, cursorY = GetCursorPosition()
    cursorX = cursorX / uiScale
    cursorY = cursorY / uiScale

    local mapCenterX, mapCenterY = Minimap:GetCenter()
    if not mapCenterX or not mapCenterY then return nil, nil end

    local deltaX = cursorX - mapCenterX
    local deltaY = cursorY - mapCenterY

    -- Get Minimap radius in yards based on indoor/outdoor and zoom level
    local zoom = Minimap:GetZoom() or 0
    local isIndoor = GetCVar("minimapInsideZoom") == "1"
    local radiusTable = isIndoor and INDOOR_MINIMAP_RADII or OUTDOOR_MINIMAP_RADII
    local radiusYards = radiusTable[zoom] or 466.66

    -- Compute map width in pixels
    local mapWidth = Minimap:GetWidth() or 160
    local yardsPerPixel = (radiusYards * 2) / mapWidth

    local yardOffsetX = deltaX * yardsPerPixel
    local yardOffsetY = deltaY * yardsPerPixel

    -- Query PUIQuest DB for exact zone dimensions if available
    local zoneWidth = 10000
    local zoneHeight = 10000
    if Primus.PUIQuest and Primus.PUIQuest.DB and Primus.PUIQuest.DB.minimap then
        local currentZone = GetZoneText() or ""
        local zoneData = Primus.PUIQuest.DB.minimap[currentZone]
        if zoneData and zoneData[1] and zoneData[2] then
            zoneWidth = zoneData[1]
            zoneHeight = zoneData[2]
        end
    end

    local cursorWorldX = (playerX * 100) + (yardOffsetX / zoneWidth) * 100
    local cursorWorldY = (playerY * 100) - (yardOffsetY / zoneHeight) * 100

    cursorWorldX = math.max(0, math.min(100, cursorWorldX))
    cursorWorldY = math.max(0, math.min(100, cursorWorldY))

    return cursorWorldX, cursorWorldY
end

-- Telemetry polling update
function PUIMinimapper:UpdateCoordinates()
    local bar = self.coordsBar
    local db = self.db
    if not bar or not (db and db:Get("showCoords", true)) then return end

    -- Avoid overriding user-browsed map zone when WorldMapFrame is open
    if not WorldMapFrame or not WorldMapFrame:IsShown() then
        SetMapToCurrentZone()
    end

    local px, py = GetPlayerMapPosition("player")

    -- Update Player Coordinates Readout
    if self.playerCoordText then
        if px and py and (px > 0 or py > 0) then
            self.playerCoordText:SetText(string.format("%.1f, %.1f", px * 100, py * 100))
            self.playerCoordText:SetTextColor(0.9, 0.9, 1.0)
        else
            self.playerCoordText:SetText("--.-, --.-")
            self.playerCoordText:SetTextColor(0.5, 0.5, 0.5)
        end
    end

    -- Update Cursor Coordinates Readout
    if self.cursorCoordText and db:Get("showCursorCoords", true) then
        if px and py and (px > 0 or py > 0) and MouseIsOver(Minimap) then
            local cx, cy = GetCursorMinimapCoords(px, py)
            if cx and cy then
                self.cursorCoordText:SetText(string.format("%.1f, %.1f", cx, cy))
                self.cursorCoordText:SetTextColor(1.0, 0.82, 0.2)
            else
                self.cursorCoordText:SetText("")
            end
        else
            self.cursorCoordText:SetText("")
        end
    end
end

-- Layout & Dimension Synchronization
function PUIMinimapper:UpdateCoordinatesLayout()
    local bar = self.coordsBar
    local container = self.containerFrame
    if not bar or not container then return end

    local db = self.db
    local size = db and db:Get("size", 160) or 160
    bar:SetWidth(size)
    bar:ClearAllPoints()

    local dock = db and db:Get("coordsDock", "BOTTOM") or "BOTTOM"
    if dock == "TOP" then
        bar:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 0, 2)
        bar:SetPoint("BOTTOMRIGHT", container, "TOPRIGHT", 0, 2)
    elseif dock == "OVERLAY" then
        bar:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 2, 2)
        bar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -2, 2)
        bar:SetFrameLevel(Minimap:GetFrameLevel() + 10)
    else
        -- Default BOTTOM
        bar:SetPoint("TOPLEFT", container, "BOTTOMLEFT", 0, -2)
        bar:SetPoint("TOPRIGHT", container, "BOTTOMRIGHT", 0, -2)
    end

    if db and db:Get("showCoords", true) then
        bar:Show()
    else
        bar:Hide()
    end
end

-- Start Coordinate Polling Ticker
function PUIMinimapper:StartCoordTicker()
    if self.coordTicker then return end
    self.coordTicker = Time:Every(0.08, function()
        PUIMinimapper:UpdateCoordinates()
    end, self)
end

-- Stop Coordinate Polling Ticker
function PUIMinimapper:StopCoordTicker()
    if self.coordTicker then
        Time:Cancel(self.coordTicker)
        self.coordTicker = nil
    end
end

-- Build Coordinates HUD Frame
function PUIMinimapper:BuildCoordinatesHUD()
    if self.coordsBar then return self.coordsBar end
    local container = self.containerFrame
    if not container then return end

    local db = self.db
    local fontSize = db and db:Get("fontSize", 9) or 9

    local bar = CreateFrame("Frame", "Primus_MinimapCoordsBar", container)
    bar:SetHeight(18)
    bar:SetBackdrop(Media:Fetch("border", "1Pixel"))
    bar:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
    bar:SetBackdropBorderColor(0.28, 0.28, 0.35, 1.0)

    -- Player Coordinates (Left)
    local playerIcon = bar:CreateFontString(nil, "OVERLAY")
    playerIcon:SetFont(Media:Fetch("font", "Default"), fontSize, "")
    playerIcon:SetPoint("LEFT", bar, "LEFT", 6, 0)
    playerIcon:SetTextColor(0.4, 0.8, 1.0)
    playerIcon:SetText("P:")

    local playerText = bar:CreateFontString(nil, "OVERLAY")
    playerText:SetFont(Media:Fetch("font", "Default"), fontSize, "OUTLINE")
    playerText:SetPoint("LEFT", playerIcon, "RIGHT", 3, 0)
    playerText:SetText("--.-, --.-")

    -- Cursor Coordinates (Right)
    local cursorText = bar:CreateFontString(nil, "OVERLAY")
    cursorText:SetFont(Media:Fetch("font", "Default"), fontSize, "OUTLINE")
    cursorText:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    cursorText:SetText("")

    local cursorIcon = bar:CreateFontString(nil, "OVERLAY")
    cursorIcon:SetFont(Media:Fetch("font", "Default"), fontSize, "")
    cursorIcon:SetPoint("RIGHT", cursorText, "LEFT", -3, 0)
    cursorIcon:SetTextColor(1.0, 0.82, 0.2)
    cursorIcon:SetText("C:")
    if db and db:Get("showCursorCoords", true) then
        cursorIcon:Show()
    else
        cursorIcon:Hide()
    end

    bar.cursorIcon = cursorIcon
    self.coordsBar = bar
    self.playerCoordText = playerText
    self.cursorCoordText = cursorText

    self:UpdateCoordinatesLayout()
    return bar
end
