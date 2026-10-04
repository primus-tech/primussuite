--[[
    PrimusUI Module: PUIMinimapper (Master Coordinator & Options Flare)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Subsystem: Master Module Lifecycle, Blizzard Clutter Neutralization,
               Mouse-Wheel Zoom Engine & Options Flare Handshake.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIMinimapper = Primus.PUIMinimapper or {}
Primus.PUIMinimapper = PUIMinimapper
_G.PUIMinimapper = PUIMinimapper
Primus:RegisterModule("PUIMinimapper", PUIMinimapper, "Utility")

local DB      = Primus.DB
local Events  = Primus.Events
local Time    = Primus.Time

-- =========================================================================
-- PERSISTENT DATABASE & DEFAULTS
-- =========================================================================

local mmDB = DB:RegisterNamespace("PUIMinimapper", {
    enabled             = true,
    size                = 160,
    shape               = "square",     -- "square", "round", "minimalist"
    scale               = 1.0,
    mousewheelZoom      = true,
    autoZoomReset       = true,
    zoomResetDelay      = 10,
    showCoords          = true,
    showCursorCoords    = true,
    coordsDock          = "BOTTOM",     -- "BOTTOM", "TOP", "OVERLAY"
    showZoneText        = true,
    fontSize            = 9,
    showSideDock        = true,
    buttonDockSide      = "LEFT",       -- "LEFT", "RIGHT"
    showClock           = true,
    clock24Hour         = true,
    clockUseServerTime  = false,
    showOrbit           = true,
})

PUIMinimapper.db = mmDB

-- =========================================================================
-- BLIZZARD ART STRIPPING & ELEMENT SANITIZATION
-- =========================================================================

local function StripBlizzardClutter()
    -- Hide redundant compass rings and border art
    if MinimapBorder then
        MinimapBorder:Hide()
        MinimapBorder.Show = function() end
    end
    if MinimapBorderTop then
        MinimapBorderTop:Hide()
        MinimapBorderTop.Show = function() end
    end
    if MinimapToggleButton then
        MinimapToggleButton:Hide()
        MinimapToggleButton.Show = function() end
    end
    if MinimapZoomIn then
        MinimapZoomIn:Hide()
        MinimapZoomIn.Show = function() end
    end
    if MinimapZoomOut then
        MinimapZoomOut:Hide()
        MinimapZoomOut.Show = function() end
    end

    -- Hide bulky Blizzard sun/moon GameTimeFrame (replaced by our modern clock button)
    if GameTimeFrame then
        GameTimeFrame:Hide()
        GameTimeFrame.Show = function() end
    end

    -- Strip tracking and mail border rings
    if MiniMapTrackingBorder then
        MiniMapTrackingBorder:Hide()
        MiniMapTrackingBorder.Show = function() end
    end
    if MiniMapMailBorder then
        MiniMapMailBorder:Hide()
        MiniMapMailBorder.Show = function() end
    end
    if MiniMapMeetingStoneBorder then
        MiniMapMeetingStoneBorder:Hide()
        MiniMapMeetingStoneBorder.Show = function() end
    end
    if MiniMapBattlefieldBorder then
        MiniMapBattlefieldBorder:Hide()
        MiniMapBattlefieldBorder.Show = function() end
    end

    -- Permanently neutralize native Blizzard Zone Text to prevent background ghost text
    if MinimapZoneTextButton then
        MinimapZoneTextButton:Hide()
        MinimapZoneTextButton.Show = function() end
    end
    if MinimapZoneText then
        MinimapZoneText:Hide()
        MinimapZoneText.Show = function() end
        MinimapZoneText:SetText("")
    end

    -- Suppress standalone PUIMinimapOrbit button if docked into our side rail
    local standaloneOrbit = _G["Primus_MinimapOrbitBtn"]
    if standaloneOrbit and standaloneOrbit ~= PUIMinimapper.orbitBtn then
        standaloneOrbit:Hide()
        standaloneOrbit.Show = function() end
    end
end

-- =========================================================================
-- MOUSE-WHEEL ZOOM ENGINE
-- =========================================================================

local function OnMinimapMouseWheel()
    if not mmDB:Get("mousewheelZoom", true) then return end

    local currentZoom = Minimap:GetZoom()
    local maxZoom = Minimap:GetZoomLevels() - 1

    if arg1 > 0 then
        -- Zoom In
        if currentZoom < maxZoom then
            Minimap:SetZoom(currentZoom + 1)
        end
    elseif arg1 < 0 then
        -- Zoom Out
        if currentZoom > 0 then
            Minimap:SetZoom(currentZoom - 1)
        end
    end

    -- Inactivity Auto-Reset Handler
    if mmDB:Get("autoZoomReset", true) then
        if PUIMinimapper.zoomResetTimer then
            Time:Cancel(PUIMinimapper.zoomResetTimer)
            PUIMinimapper.zoomResetTimer = nil
        end

        local newZoom = Minimap:GetZoom()
        if newZoom > 0 then
            local delay = mmDB:Get("zoomResetDelay", 10)
            PUIMinimapper.zoomResetTimer = Time:After(delay, function()
                if Minimap and Minimap.SetZoom then
                    Minimap:SetZoom(0)
                end
                PUIMinimapper.zoomResetTimer = nil
            end, "PUIMinimapper")
        end
    end
end

-- =========================================================================
-- OPTIONS FLARE REGISTRATION
-- =========================================================================

function PUIMinimapper:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end

    Primus.Options:RegisterModuleOptions("PUIMinimapper", {
        name        = "PUIMinimapper",
        category    = "Utility",
        label       = "Minimap & Navigation",
        icon        = "Interface\\Icons\\INV_Misc_Compass_01",
        desc        = "Modern square minimap shaper, dimension scaling, mouse-wheel zoom, utility side dock, and real-time coordinate HUD.",
        options = {
            {
                type    = "slider",
                key     = "size",
                label   = "Minimap Size",
                desc    = "Adjusts the width and height of the minimap viewport.",
                min     = 120,
                max     = 260,
                step    = 5,
                default = 160,
                get     = function() return mmDB:Get("size", 160) end,
                set     = function(val)
                    mmDB:Set("size", val)
                    if PUIMinimapper.ApplyGeometry then
                        PUIMinimapper:ApplyGeometry()
                    end
                end,
            },
            {
                type    = "slider",
                key     = "scale",
                label   = "Minimap Scale",
                desc    = "Applies a global scale multiplier to the minimap and overlays.",
                min     = 0.8,
                max     = 1.5,
                step    = 0.05,
                default = 1.0,
                get     = function() return mmDB:Get("scale", 1.0) end,
                set     = function(val)
                    mmDB:Set("scale", val)
                    if PUIMinimapper.ApplyGeometry then
                        PUIMinimapper:ApplyGeometry()
                    end
                end,
            },
            {
                type    = "checkbox",
                key     = "shape_square",
                label   = "Modern Square Shape",
                desc    = "Toggles between crisp modern square masking and classic circular masking.",
                default = true,
                get     = function() return mmDB:Get("shape", "square") == "square" end,
                set     = function(val)
                    mmDB:Set("shape", val and "square" or "round")
                    if PUIMinimapper.ApplyGeometry then
                        PUIMinimapper:ApplyGeometry()
                    end
                end,
            },
            {
                type    = "checkbox",
                key     = "showSideDock",
                label   = "Show Utility Side Dock",
                desc    = "Displays the 1-pixel utility dock containing the Clock, Orbit, and tracking buttons.",
                default = true,
                get     = function() return mmDB:Get("showSideDock", true) end,
                set     = function(val)
                    mmDB:Set("showSideDock", val)
                    if PUIMinimapper.RepositionSideDock then
                        PUIMinimapper:RepositionSideDock()
                    end
                end,
            },
            {
                type    = "checkbox",
                key     = "buttonDockSide_left",
                label   = "Dock Buttons on Left Side",
                desc    = "Presents the utility dock along the Left side (Checked) or Right side (Unchecked).",
                default = true,
                get     = function() return mmDB:Get("buttonDockSide", "LEFT") == "LEFT" end,
                set     = function(val)
                    mmDB:Set("buttonDockSide", val and "LEFT" or "RIGHT")
                    if PUIMinimapper.RepositionSideDock then
                        PUIMinimapper:RepositionSideDock()
                    end
                end,
            },
            {
                type    = "checkbox",
                key     = "showClock",
                label   = "Show Clock Button",
                desc    = "Displays the interactive clock button in the utility side dock.",
                default = true,
                get     = function() return mmDB:Get("showClock", true) end,
                set     = function(val)
                    mmDB:Set("showClock", val)
                    if PUIMinimapper.RepositionSideDock then
                        PUIMinimapper:RepositionSideDock()
                    end
                end,
            },
            {
                type    = "checkbox",
                key     = "clock24Hour",
                label   = "Clock: 24-Hour Format",
                desc    = "Toggles 24-hour military format vs 12-hour AM/PM format in the clock tooltip.",
                default = true,
                get     = function() return mmDB:Get("clock24Hour", true) end,
                set     = function(val)
                    mmDB:Set("clock24Hour", val)
                end,
            },
            {
                type    = "checkbox",
                key     = "showOrbit",
                label   = "Show Addon Orbit Button",
                desc    = "Displays the 1-click Addon Orbit dock button in the utility side dock.",
                default = true,
                get     = function() return mmDB:Get("showOrbit", true) end,
                set     = function(val)
                    mmDB:Set("showOrbit", val)
                    if PUIMinimapper.RepositionSideDock then
                        PUIMinimapper:RepositionSideDock()
                    end
                end,
            },
            {
                type    = "checkbox",
                key     = "mousewheelZoom",
                label   = "Mouse-Wheel Zoom",
                desc    = "Enables instant smooth zooming via mouse scroll wheel over the minimap.",
                default = true,
                get     = function() return mmDB:Get("mousewheelZoom", true) end,
                set     = function(val) mmDB:Set("mousewheelZoom", val) end,
            },
            {
                type    = "checkbox",
                key     = "autoZoomReset",
                label   = "Auto-Reset Zoom on Inactivity",
                desc    = "Automatically returns minimap view to outer zoom after inactivity.",
                default = true,
                get     = function() return mmDB:Get("autoZoomReset", true) end,
                set     = function(val) mmDB:Set("autoZoomReset", val) end,
            },
            {
                type    = "slider",
                key     = "zoomResetDelay",
                label   = "Zoom Reset Delay (Seconds)",
                desc    = "Duration of inactivity before resetting minimap zoom.",
                min     = 5,
                max     = 30,
                step    = 1,
                default = 10,
                get     = function() return mmDB:Get("zoomResetDelay", 10) end,
                set     = function(val) mmDB:Set("zoomResetDelay", val) end,
            },
            {
                type    = "checkbox",
                key     = "showZoneText",
                label   = "Show Zone Text Header",
                desc    = "Displays the stylized zone title bar above the minimap.",
                default = true,
                get     = function() return mmDB:Get("showZoneText", true) end,
                set     = function(val)
                    mmDB:Set("showZoneText", val)
                    if PUIMinimapper.ApplyGeometry then
                        PUIMinimapper:ApplyGeometry()
                    end
                    if PUIMinimapper.UpdateZoneText then
                        PUIMinimapper:UpdateZoneText()
                    end
                end,
            },
            {
                type    = "checkbox",
                key     = "showCoords",
                label   = "Show Real-Time Coordinates HUD",
                desc    = "Displays the high-precision player & cursor coordinate bar.",
                default = true,
                get     = function() return mmDB:Get("showCoords", true) end,
                set     = function(val)
                    mmDB:Set("showCoords", val)
                    if PUIMinimapper.ApplyGeometry then
                        PUIMinimapper:ApplyGeometry()
                    end
                end,
            },
            {
                type    = "checkbox",
                key     = "showCursorCoords",
                label   = "Show Cursor Hover Coordinates",
                desc    = "Calculates live coordinates under mouse cursor when hovering over minimap.",
                default = true,
                get     = function() return mmDB:Get("showCursorCoords", true) end,
                set     = function(val)
                    mmDB:Set("showCursorCoords", val)
                    local bar = PUIMinimapper.coordsBar
                    if bar and bar.cursorIcon then
                        if val then
                            bar.cursorIcon:Show()
                        else
                            bar.cursorIcon:Hide()
                        end
                    end
                end,
            },
        }
    })
end

-- =========================================================================
-- MODULE LIFECYCLE (OnInitialize, OnEnable, OnDisable)
-- =========================================================================

function PUIMinimapper:OnInitialize()
    self:RegisterOptionsFlare()

    -- Build Frames
    if self.CreateContainer then
        self:CreateContainer()
    end
    if self.BuildZoneHeader then
        self:BuildZoneHeader()
    end
    if self.BuildCoordinatesHUD then
        self:BuildCoordinatesHUD()
    end
    if self.BuildSideDock then
        self:BuildSideDock()
    end

    -- Register for Mouse-Wheel Zoom
    if Minimap then
        Minimap:EnableMouseWheel(true)
        Minimap:SetScript("OnMouseWheel", OnMinimapMouseWheel)
    end
end

function PUIMinimapper:OnEnable()
    self.isModuleEnabled = true

    if not self.containerFrame and self.OnInitialize then
        self:OnInitialize()
    end

    if self.containerFrame then
        self.containerFrame:Show()
    end
    StripBlizzardClutter()
    if self.ApplyGeometry then
        self:ApplyGeometry()
    end
    if self.UpdateZoneText then
        self:UpdateZoneText()
    end

    -- Event Listeners for Zone Header updates
    Events:Register("ZONE_CHANGED", function()
        if PUIMinimapper.UpdateZoneText then
            PUIMinimapper:UpdateZoneText()
        end
    end, self)

    Events:Register("ZONE_CHANGED_INDOORS", function()
        if PUIMinimapper.UpdateZoneText then
            PUIMinimapper:UpdateZoneText()
        end
    end, self)

    Events:Register("ZONE_CHANGED_NEW_AREA", function()
        if PUIMinimapper.UpdateZoneText then
            PUIMinimapper:UpdateZoneText()
        end
    end, self)

    Events:Register("MINIMAP_UPDATE_ZOOM", function()
        if PUIMinimapper.UpdateZoneText then
            PUIMinimapper:UpdateZoneText()
        end
    end, self)

    Events:Register("PLAYER_ENTERING_WORLD", function()
        if PUIMinimapper.UpdateZoneText then
            PUIMinimapper:UpdateZoneText()
        end
        if PUIMinimapper.ApplyGeometry then
            PUIMinimapper:ApplyGeometry()
        end
    end, self)

    -- Hook Minimap_Update to guarantee custom header updates instantly on any map change
    if Minimap_Update and not PUIMinimapper.hookedMinimapUpdate then
        local orig_Minimap_Update = Minimap_Update
        Minimap_Update = function()
            orig_Minimap_Update()
            if PUIMinimapper and PUIMinimapper.UpdateZoneText then
                PUIMinimapper:UpdateZoneText()
            end
        end
        PUIMinimapper.hookedMinimapUpdate = true
    end

    -- Coordinate Poller Ticker
    if self.StartCoordTicker then
        self:StartCoordTicker()
    end
end

function PUIMinimapper:OnDisable()
    self.isModuleEnabled = false

    -- Stop coordinate ticker
    self:StopCoordTicker()

    -- Cancel zoom reset timer
    if self.zoomResetTimer then
        Time:Cancel(self.zoomResetTimer)
        self.zoomResetTimer = nil
    end

    -- Unregister Events
    Events:UnregisterOwner(self)

    -- Restore Blizzard Mask & Native Dimensions
    if Minimap then
        Minimap:SetMaskTexture("Textures\\MinimapMask")
        if self.origBlizzState.minimapParent then
            Minimap:SetParent(self.origBlizzState.minimapParent)
        end
        if self.origBlizzState.minimapWidth and self.origBlizzState.minimapHeight then
            Minimap:SetWidth(self.origBlizzState.minimapWidth)
            Minimap:SetHeight(self.origBlizzState.minimapHeight)
        end
        Minimap:ClearAllPoints()
        Minimap:SetPoint("CENTER", MinimapCluster or UIParent, "CENTER", 0, 0)
    end

    -- Hide custom container & widgets
    if self.containerFrame then
        self.containerFrame:Hide()
    end
    if self.sideDockFrame then
        self.sideDockFrame:Hide()
    end

    -- Restore Blizzard Zone Text Button & GameTimeFrame
    if MinimapZoneTextButton then
        MinimapZoneTextButton:Show()
    end
    if GameTimeFrame then
        GameTimeFrame:Show()
    end
end
