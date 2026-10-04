--[[
    PrimusUI Module: PUIMinimapper - PUIMapCore
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Subsystem: Minimap Container, Geometry Masking, Sizing & PUIMover Integration.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIMinimapper = Primus.PUIMinimapper or {}
Primus.PUIMinimapper = PUIMinimapper
_G.PUIMinimapper = PUIMinimapper

local Media = Primus.Media

-- Storage for original Blizzard frame states for clean OnDisable restoration
PUIMinimapper.origBlizzState = PUIMinimapper.origBlizzState or {
    minimapParent   = nil,
    minimapPoints   = nil,
    minimapWidth    = nil,
    minimapHeight   = nil,
    maskTexture     = nil,
    zoneTextParent  = nil,
    zoneTextPoints  = nil,
}

-- Public API to query current minimap shape (used by PUIQuest radar pin clamping)
function PUIMinimapper:GetShape()
    if not self.isModuleEnabled then return "round" end
    local db = self.db
    return db and db:Get("shape", "square") or "square"
end

function PUIMinimapper:IsSquare()
    local shape = self:GetShape()
    return (shape == "square" or shape == "minimalist")
end

-- Create the master top-level container frame
function PUIMinimapper:CreateContainer()
    if self.containerFrame then return self.containerFrame end

    local db = self.db
    local size = db and db:Get("size", 160) or 160

    -- Save original Blizzard Minimap state
    if Minimap and not self.origBlizzState.minimapParent then
        self.origBlizzState.minimapParent = Minimap:GetParent()
        self.origBlizzState.minimapWidth  = Minimap:GetWidth()
        self.origBlizzState.minimapHeight = Minimap:GetHeight()
    end

    local container = CreateFrame("Frame", "Primus_Minimap", UIParent)
    container:SetWidth(size)
    container:SetHeight(size)
    container:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -10, -10)
    container:SetFrameStrata("LOW")
    container:SetMovable(true)

    self.containerFrame = container

    -- Register with PUIMover under HUD category
    local mover = Primus.PUIMover or _G.PUIMover
    if mover and mover.Register then
        mover:Register(container, "PUIMinimapper", "Minimap", "HUD")
    end

    return container
end

-- Apply Geometry, Sizing, Scale, and Mask Texture
function PUIMinimapper:ApplyGeometry()
    local container = self.containerFrame
    if not container or not Minimap then return end

    local db = self.db
    local size  = db and db:Get("size", 160) or 160
    local scale = db and db:Get("scale", 1.0) or 1.0
    local shape = db and db:Get("shape", "square") or "square"

    container:SetWidth(size)
    container:SetHeight(size)
    container:SetScale(scale)

    -- Minimap sizing within container (2px inset for 1px glass border)
    Minimap:ClearAllPoints()
    Minimap:SetParent(container)
    Minimap:SetWidth(size - 4)
    Minimap:SetHeight(size - 4)
    Minimap:SetPoint("CENTER", container, "CENTER", 0, 0)

    -- Apply Masking Texture
    if shape == "square" or shape == "minimalist" then
        Minimap:SetMaskTexture("Interface\\ChatFrame\\ChatFrameBackground")
    else
        Minimap:SetMaskTexture("Textures\\MinimapMask")
    end

    -- Apply Container Styling
    if shape == "minimalist" then
        container:SetBackdrop(nil)
    else
        container:SetBackdrop(Media:Fetch("border", "1Pixel"))
        container:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
        container:SetBackdropBorderColor(0.28, 0.28, 0.35, 1.0)
    end

    -- Anchor MinimapCluster to containerFrame to keep all native sub-frames grouped
    if MinimapCluster then
        MinimapCluster:ClearAllPoints()
        MinimapCluster:SetParent(container)
        MinimapCluster:SetPoint("CENTER", container, "CENTER", 0, 0)
        MinimapCluster:SetWidth(size)
        MinimapCluster:SetHeight(size)
        MinimapCluster:SetScale(scale)
    end

    -- Update sub-components
    if self.UpdateZoneHeaderLayout then
        self:UpdateZoneHeaderLayout()
    end
    if self.UpdateCoordinatesLayout then
        self:UpdateCoordinatesLayout()
    end
    if self.RepositionSideDock then
        self:RepositionSideDock()
    end

    -- Synchronize PUIMover overlay dimensions
    local mover = Primus.PUIMover or _G.PUIMover
    if mover and mover.UpdateFrame then
        mover:UpdateFrame("PUIMinimapper")
    end
end
