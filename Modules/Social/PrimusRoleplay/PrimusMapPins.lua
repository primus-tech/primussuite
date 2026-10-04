--[[
    PrimusUI: PUIRoleplay World Map Pins Engine (PUIMapPins.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (RP Character World Map Pin Overlays)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims, Pooled PUIMap Provider)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIRoleplay = Primus.PUIRoleplay or {}
Primus.PUIRoleplay = PUIRoleplay

local Directory = PUIRoleplay.Directory or {}
PUIRoleplay.Directory = Directory

--------------------------------------------------------------------------------
-- World Map RP Location Pin Provider Callback
--------------------------------------------------------------------------------
local function RenderRPPins(mapContext)
    if not mapContext then return end

    local currentZoneName = mapContext.zoneName or ""
    local allChars = (PUIRoleplay.GetAllKnownCharacters and PUIRoleplay:GetAllKnownCharacters()) or {}

    for name, data in pairs(allChars) do
        if name ~= UnitName("player") and data.zoneX and data.zoneY then
            local zX = tonumber(data.zoneX)
            local zY = tonumber(data.zoneY)

            local dZone = PUIRoleplay.Protocols and PUIRoleplay.Protocols.DrunkDecode and PUIRoleplay.Protocols:DrunkDecode(data.zone or "") or (data.zone or "")
            if zX and zY and (dZone == currentZoneName or currentZoneName == "" or not currentZoneName) then
                local pin = mapContext.AcquirePin()
                pin.icon:SetTexture("Interface\\Icons\\INV_Misc_GroupNeedMore")
                pin.charName = name
                pin.fullName = data.full_name
                pin.isIC = (data.currently_ic == "1")

                pin:SetScript("OnEnter", function()
                    if this.charName then
                        WorldMapTooltip:SetOwner(this, "ANCHOR_RIGHT")
                        WorldMapTooltip:AddLine(this.fullName or this.charName, 0.0, 0.8, 1.0)
                        WorldMapTooltip:AddLine(this.isIC and "Status: In Character (IC)" or "Status: Out of Character (OOC)", 0.8, 0.8, 0.8)
                        WorldMapTooltip:Show()
                    end
                end)
                pin:SetScript("OnLeave", function()
                    WorldMapTooltip:Hide()
                end)
                pin:SetScript("OnClick", function()
                    if this.charName and Directory.ShowPlayerFlyout then
                        Directory:ShowPlayerFlyout(this.charName)
                    end
                end)

                mapContext:PlacePin(pin, zX, zY)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Registration with Centralized PUIMap
--------------------------------------------------------------------------------
if Primus.PUIMap then
    Primus.PUIMap:RegisterPinProvider("PUIRoleplay", 40, RenderRPPins)
end

function Directory:UpdateWorldMapPins()
    if Primus.PUIMap then
        Primus.PUIMap:Refresh()
    end
end
