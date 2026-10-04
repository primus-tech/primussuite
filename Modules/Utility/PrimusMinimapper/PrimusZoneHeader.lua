--[[
    PrimusUI Module: PUIMinimapper - PUIZoneHeader
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Subsystem: Minimap Zone Text Header Bar, Difficulty/PvP Colorization & World Map Toggle.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIMinimapper = Primus.PUIMinimapper or {}
Primus.PUIMinimapper = PUIMinimapper
_G.PUIMinimapper = PUIMinimapper

local Media = Primus.Media
local Utils = Primus.Utils

-- Update Zone Text and Dynamic PvP/Difficulty Colorization
function PUIMinimapper:UpdateZoneText()
    local text = self.zoneHeaderText
    local db = self.db
    if not text or not (db and db:Get("showZoneText", true)) then return end

    local zoneName = GetMinimapZoneText()
    if not zoneName or zoneName == "" then
        zoneName = GetSubZoneText()
    end
    if not zoneName or zoneName == "" then
        zoneName = GetZoneText()
    end
    if not zoneName or zoneName == "" then
        zoneName = "Unknown Zone"
    end

    local pvpType, factionName, isArena = GetZonePVPInfo()

    if isArena then
        text:SetTextColor(1.0, 0.4, 0.0) -- Arena Orange
    elseif pvpType == "friendly" then
        text:SetTextColor(0.1, 1.0, 0.1) -- Friendly Green
    elseif pvpType == "hostile" then
        text:SetTextColor(1.0, 0.1, 0.1) -- Hostile Red
    elseif pvpType == "contested" then
        text:SetTextColor(1.0, 0.8, 0.0) -- Contested Yellow/Gold
    elseif pvpType == "sanctuary" then
        text:SetTextColor(0.4, 0.8, 1.0) -- Sanctuary Light Blue
    else
        text:SetTextColor(1.0, 1.0, 1.0) -- Neutral White
    end

    text:SetText(zoneName)
end

-- Layout & Dimension Synchronization
function PUIMinimapper:UpdateZoneHeaderLayout()
    local header = self.zoneHeaderFrame
    local container = self.containerFrame
    if not header or not container then return end

    local db = self.db
    local size = db and db:Get("size", 160) or 160
    header:SetWidth(size)

    if db and db:Get("showZoneText", true) then
        header:Show()
    else
        header:Hide()
    end
end

-- Build Zone Header Frame
function PUIMinimapper:BuildZoneHeader()
    if self.zoneHeaderFrame then return self.zoneHeaderFrame end
    local container = self.containerFrame
    if not container then return end

    local db = self.db
    local fontSize = db and db:Get("fontSize", 9) or 9

    local header = CreateFrame("Button", "Primus_MinimapZoneHeader", container)
    header:SetHeight(20)
    header:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 0, 2)
    header:SetPoint("BOTTOMRIGHT", container, "TOPRIGHT", 0, 2)
    header:SetBackdrop(Media:Fetch("border", "1Pixel"))
    header:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
    header:SetBackdropBorderColor(0.28, 0.28, 0.35, 1.0)
    header:SetFrameStrata(container:GetFrameStrata() or "LOW")
    header:SetFrameLevel((container:GetFrameLevel() or 1) + 5)

    local fontFile = Media:Fetch("font", "Default") or "Fonts\\FRIZQT__.TTF"
    local text = header:CreateFontString(nil, "OVERLAY")
    text:SetFont(fontFile, fontSize, "OUTLINE")
    text:SetPoint("LEFT", header, "LEFT", 4, 0)
    text:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    text:SetHeight(16)
    text:SetJustifyH("CENTER")

    self.zoneHeaderFrame = header
    self.zoneHeaderText  = text

    -- Left-Click toggles WorldMapFrame (Preserves authentic Blizzard behavior)
    header:SetScript("OnClick", function()
        if ToggleWorldMap then
            ToggleWorldMap()
        end
    end)

    -- Hover highlight
    header:SetScript("OnEnter", function()
        this:SetBackdropBorderColor(0.45, 0.75, 1.0, 1.0)
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:AddLine(Utils.ColorText("Minimap Navigation", "40b0ff"))
        GameTooltip:AddLine(Utils.ColorText("Left-Click:", "ffffff") .. " Toggle World Map", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)

    header:SetScript("OnLeave", function()
        this:SetBackdropBorderColor(0.28, 0.28, 0.35, 1.0)
        GameTooltip:Hide()
    end)

    -- Permanently neutralize Blizzard native ZoneTextButton to prevent duplicate background text
    if MinimapZoneTextButton then
        MinimapZoneTextButton:Hide()
        MinimapZoneTextButton.Show = function() end
    end
    if MinimapZoneText then
        MinimapZoneText:Hide()
        MinimapZoneText.Show = function() end
        MinimapZoneText:SetText("")
    end

    self:UpdateZoneHeaderLayout()
    self:UpdateZoneText()
    return header
end
