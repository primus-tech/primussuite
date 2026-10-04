--[[
    PrimusUI: PUITooltip Anchor & Positioning Engine (PUITooltipAnchor.lua)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUITooltip = Primus.PUITooltip or {}
Primus.PUITooltip = PUITooltip

local Anchor = {}
PUITooltip.Anchor = Anchor

local moverAnchor = nil

--------------------------------------------------------------------------------
-- Build / Retrieve Draggable Mover Anchor
--------------------------------------------------------------------------------
function Anchor:GetMoverAnchor()
    if moverAnchor then return moverAnchor end
    
    local f = CreateFrame("Frame", "Primus_PUITooltip_Anchor", UIParent)
    f:SetWidth(200)
    f:SetHeight(80)
    f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -24, 60)
    f:SetFrameStrata("TOOLTIP")
    f:Hide()
    
    -- PUIMover registration
    if Primus.PUIMover and Primus.PUIMover.RegisterFrame then
        Primus.PUIMover:RegisterFrame("Primus_PUITooltip_Anchor", "Tooltip Anchor", "Utility")
    end
    
    moverAnchor = f
    return f
end

--------------------------------------------------------------------------------
-- Master GameTooltip_SetDefaultAnchor Hook
--------------------------------------------------------------------------------
function Anchor:SetDefaultAnchor(tooltip, parent)
    if not tooltip or not parent then return end
    
    local settings = PUITooltip:GetSettings()
    local mode = settings.anchorMode or "SMART_CORNER"
    
    if mode == "CURSOR" then
        tooltip:SetOwner(parent, "ANCHOR_CURSOR")
    elseif mode == "MOVER" then
        local anc = self:GetMoverAnchor()
        tooltip:SetOwner(anc, "ANCHOR_NONE")
        tooltip:ClearAllPoints()
        tooltip:SetPoint("BOTTOMRIGHT", anc, "BOTTOMRIGHT", 0, 0)
    else -- "SMART_CORNER"
        tooltip:SetOwner(parent, "ANCHOR_NONE")
        tooltip:ClearAllPoints()
        tooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -24, 60)
    end
    
    tooltip.default = 1
end

--------------------------------------------------------------------------------
-- Initialize Hook
--------------------------------------------------------------------------------
function Anchor:Initialize()
    self:GetMoverAnchor()
    
    -- Hook native GameTooltip_SetDefaultAnchor
    if not Anchor.hooked then
        local origSetDefaultAnchor = _G.GameTooltip_SetDefaultAnchor
        _G.GameTooltip_SetDefaultAnchor = function(tooltip, parent)
            if PUITooltip:IsEnabled() then
                Anchor:SetDefaultAnchor(tooltip, parent)
            else
                if origSetDefaultAnchor then origSetDefaultAnchor(tooltip, parent) end
            end
        end
        Anchor.hooked = true
    end
end
