--[[
    PrimusLib Module: MinimapOrbit (Minimap Button Bag / MBB)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Discovers, intercepts, and docks scattered 3rd-party minimap buttons
    into a sleek, collapsible button drawer without disturbing Blizzard HUD
    frames (Zone Text Header, Tracking, Mail, Minimap Cluster).
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIMinimapOrbit = Primus.PUIMinimapOrbit or {}
Primus.PUIMinimapOrbit = PUIMinimapOrbit
_G.PUIMinimapOrbit = PUIMinimapOrbit
Primus:RegisterModule("PUIMinimapOrbit", PUIMinimapOrbit, "Utility")

local DB      = Primus.DB
local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local Events  = Primus.Events
local Time    = Primus.Time

local orbitDB = DB:RegisterNamespace("PUIMinimapOrbit", {
    enabled = true,
    collapsed = true,
    buttonSize = 28,
})

local dockedButtons = {}
local savedState = {}
local dockFrame = nil
local toggleButton = nil

-- Explicit blacklist of Blizzard HUD elements and core Primus frames
local BLACKLIST = {
    -- Blizzard Core Frames
    ["Minimap"] = true,
    ["MinimapCluster"] = true,
    ["MinimapBackdrop"] = true,
    ["MinimapBorderTop"] = true,
    ["MinimapBorder"] = true,
    ["MinimapZoneTextButton"] = true,
    ["MinimapZoneText"] = true,
    ["MinimapToggleButton"] = true,
    ["MinimapZoomIn"] = true,
    ["MinimapZoomOut"] = true,
    ["MiniMapTrackingFrame"] = true,
    ["MiniMapTrackingButton"] = true,
    ["MiniMapTrackingBorder"] = true,
    ["MiniMapTrackingIcon"] = true,
    ["MiniMapMeetingStoneFrame"] = true,
    ["MiniMapMeetingStoneBorder"] = true,
    ["MiniMapMeetingStoneIcon"] = true,
    ["MiniMapMailFrame"] = true,
    ["MiniMapMailBorder"] = true,
    ["MiniMapMailIcon"] = true,
    ["MiniMapBattlefieldFrame"] = true,
    ["MiniMapBattlefieldBorder"] = true,
    ["MiniMapBattlefieldIcon"] = true,
    ["MiniMapBattlefieldDropDown"] = true,
    ["BattlegroundShine"] = true,
    ["MiniMapPing"] = true,
    ["GameTimeFrame"] = true,
    ["TimeManagerClockButton"] = true,
    ["WorldMapFrame"] = true,
    ["UIParent"] = true,
    
    -- Primus Internal Frames
    ["Primus_MinimapOrbitBtn"] = true,
    ["Primus_MinimapOrbitDock"] = true,
    ["PUIQuestRadarPin"] = true,
    ["PUIQuestMinimapPin"] = true,
}

-- Known 3rd-party minimap button frames
local KNOWN_BUTTONS = {
    ["AtlasButton"] = true,
    ["Gatherer_MinimapOptionsButton"] = true,
    ["KLHTM_MinimapButton"] = true,
    ["WIM_IconFrame"] = true,
    ["CT_RASets_MinimapButton"] = true,
    ["ItemRack_MinimapFrame"] = true,
    ["ItemRack_Minimap"] = true,
    ["SCTD_MinimapButton"] = true,
    ["OutfitterMinimapButton"] = true,
    ["SW_Minimap_Button"] = true,
    ["DecursiveMinimapButton"] = true,
    ["MetaMapMinimapButton"] = true,
    ["FuBarMinimapContainer"] = true,
    ["TitanPanelMinimap"] = true,
    ["DBMMinimapButton"] = true,
    ["BigWigsMinimapButton"] = true,
    ["FishingBuddyMinimapButton"] = true,
    ["SuperMacroMinimapButton"] = true,
    ["DamageMeters_MinimapButton"] = true,
}

-- Verify whether a frame is a genuine 3rd-party minimap button
local function IsMinimapButton(name, frame)
    if not frame or type(frame) ~= "table" then return false end

    -- Must be a frame object (Button or Frame), never a Texture or FontString
    if not frame.GetObjectType then return false end
    local objType = frame:GetObjectType()
    if objType ~= "Button" and objType ~= "Frame" then
        return false
    end

    -- Must possess standard Frame methods
    if not frame.GetFrameStrata or not frame.SetFrameStrata or 
       not frame.GetFrameLevel or not frame.SetFrameLevel or
       not frame.SetPoint or not frame.GetParent then
        return false
    end

    if name and BLACKLIST[name] then return false end
    if frame == Minimap or frame == MinimapCluster or frame == MinimapBackdrop or frame == toggleButton or frame == dockFrame then
        return false
    end

    -- Never touch Blizzard zone text button or tracking
    if name == "MinimapZoneTextButton" or name == "MinimapZoneText" then return false end

    -- Exclusion substrings (pins, radar, coords, clusters, zone headers)
    if name and type(name) == "string" then
        local lower = string.lower(name)
        if string.find(lower, "zonetext") or string.find(lower, "toggle") or 
           string.find(lower, "zoom") or string.find(lower, "coord") or 
           string.find(lower, "compass") or string.find(lower, "ping") or 
           string.find(lower, "arrow") or string.find(lower, "radar") or 
           string.find(lower, "pin") or string.find(lower, "cluster") or 
           string.find(lower, "backdrop") or string.find(lower, "border") or 
           string.find(lower, "time") or string.find(lower, "clock") or 
           string.find(lower, "primus") or string.find(lower, "pui") or 
           string.find(lower, "pfminimappin") or string.find(lower, "pfmap") or 
           string.find(lower, "gathernote") or string.find(lower, "cartographer") or
           string.find(lower, "astrolabe") or string.find(lower, "flightmap") or
           string.find(lower, "mapnotes") then
            return false
        end

        -- Explicit known button match
        if KNOWN_BUTTONS[name] then
            return true
        end

        -- Pattern match for addon minimap buttons
        if string.find(lower, "minimapbutton") or string.find(lower, "_minimapbutton") or 
           string.find(lower, "minimap_button") or string.find(lower, "minimapicon") or 
           string.find(lower, "_minimapicon") or string.find(lower, "_minimapframe") or 
           string.find(lower, "libdbicon") or string.find(lower, "fubarplugin.*minimap") then
            return true
        end
    end

    -- Parent-based heuristics for anonymous or uniquely named addon buttons anchored to Minimap
    local parent = frame:GetParent()
    if parent == Minimap or parent == MinimapCluster or parent == MinimapBackdrop then
        local w = (frame.GetWidth and frame:GetWidth()) or 0
        local h = (frame.GetHeight and frame:GetHeight()) or 0
        if w >= 16 and w <= 48 and h >= 16 and h <= 48 then
            -- Verify it has interactive button characteristics
            if frame.GetNormalTexture or (frame.GetScript and (frame:GetScript("OnClick") or frame:GetScript("OnMouseDown") or frame:GetScript("OnMouseUp"))) then
                return true
            end
        end
    end

    return false
end

-- Safely restore Blizzard default frames (e.g. Zone Text Button) to their standard anchor
local function RestoreBlizzardFrames()
    local minimapper = Primus.PUIMinimapper or _G.PUIMinimapper
    if minimapper and minimapper.isModuleEnabled then
        return
    end

    if MinimapZoneTextButton then
        if MinimapZoneTextButton.GetParent and MinimapZoneTextButton:GetParent() ~= MinimapCluster then
            MinimapZoneTextButton:SetParent(MinimapCluster)
        end
        if MinimapZoneTextButton.ClearAllPoints and MinimapZoneTextButton.SetPoint then
            MinimapZoneTextButton:ClearAllPoints()
            MinimapZoneTextButton:SetPoint("CENTER", MinimapCluster, "CENTER", -3, 83)
        end
        if MinimapZoneTextButton.Show then
            MinimapZoneTextButton:Show()
        end
        if MinimapZoneText then
            if MinimapZoneText.Show then MinimapZoneText:Show() end
            if GetMinimapZoneText and MinimapZoneText.SetText then
                MinimapZoneText:SetText(GetMinimapZoneText())
            end
        end
    end

    if MinimapToggleButton and MinimapToggleButton.GetParent and MinimapToggleButton:GetParent() ~= MinimapCluster then
        MinimapToggleButton:SetParent(MinimapCluster)
        if MinimapToggleButton.ClearAllPoints and MinimapToggleButton.SetPoint then
            MinimapToggleButton:ClearAllPoints()
            MinimapToggleButton:SetPoint("CENTER", MinimapCluster, "TOPRIGHT", -15, -13)
        end
        if MinimapToggleButton.Show then MinimapToggleButton:Show() end
    end
end

-- Save original frame state before docking
local function SaveButtonState(btn)
    if not btn or savedState[btn] then return end

    local numPoints = (btn.GetNumPoints and btn:GetNumPoints()) or 1
    local points = {}
    if btn.GetPoint then
        for p = 1, numPoints do
            local point, relativeTo, relativePoint, xOfs, yOfs = btn:GetPoint(p)
            if point then
                table.insert(points, {
                    point = point,
                    relativeTo = relativeTo,
                    relativePoint = relativePoint,
                    xOfs = xOfs,
                    yOfs = yOfs
                })
            end
        end
    end

    savedState[btn] = {
        parent = btn.GetParent and btn:GetParent(),
        points = points,
        width = (btn.GetWidth and btn:GetWidth()) or 28,
        height = (btn.GetHeight and btn:GetHeight()) or 28,
        strata = (btn.GetFrameStrata and btn:GetFrameStrata()) or "MEDIUM",
        level = (btn.GetFrameLevel and btn:GetFrameLevel()) or 1,
        hiddenTextures = {},
    }
end

-- Skin and standardize docked button appearance
local function SkinDockedButton(btn)
    if not btn then return end

    local btnSize = orbitDB:Get("buttonSize", 28)
    if btn.SetWidth then btn:SetWidth(btnSize) end
    if btn.SetHeight then btn:SetHeight(btnSize) end
    if btn.SetFrameStrata then btn:SetFrameStrata("HIGH") end
    if btn.SetFrameLevel and dockFrame and dockFrame.GetFrameLevel then
        btn:SetFrameLevel(dockFrame:GetFrameLevel() + 5)
    end

    -- Process child textures to hide oversized circular borders and enhance icon faces
    local state = savedState[btn]
    if btn.GetRegions then
        local regions = { btn:GetRegions() }
        for _, region in ipairs(regions) do
            if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                local texPath = region:GetTexture()
                local tw = (region.GetWidth and region:GetWidth()) or 0
                local th = (region.GetHeight and region:GetHeight()) or 0
                local isBorder = false

                if texPath and type(texPath) == "string" then
                    local lowerTex = string.lower(texPath)
                    if string.find(lowerTex, "trackingborder") or 
                       string.find(lowerTex, "minimap-border") or 
                       string.find(lowerTex, "ui-minimap-border") or 
                       string.find(lowerTex, "minimap_border") then
                        isBorder = true
                    end
                end

                if tw > 36 or th > 36 then
                    isBorder = true
                end

                if isBorder then
                    region:Hide()
                    if state and state.hiddenTextures then
                        table.insert(state.hiddenTextures, region)
                    end
                else
                    -- Ensure icon texture is positioned and drawn crisply
                    if texPath and region.SetDrawLayer then
                        region:SetDrawLayer("ARTWORK")
                        if region.ClearAllPoints and region.SetPoint then
                            region:ClearAllPoints()
                            region:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
                            region:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
                        end
                        region:Show()
                    end
                end
            end
        end
    end

    -- Normal texture styling
    if btn.GetNormalTexture and btn:GetNormalTexture() then
        local norm = btn:GetNormalTexture()
        if norm.SetDrawLayer then norm:SetDrawLayer("ARTWORK") end
        if norm.ClearAllPoints and norm.SetPoint then
            norm:ClearAllPoints()
            norm:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
            norm:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
        end
        if norm.Show then norm:Show() end
    end

    -- Backdrop for consistent sleek look
    if btn.SetBackdrop then
        btn:SetBackdrop(Media:Fetch("border", "1Pixel"))
        btn:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
        btn:SetBackdropBorderColor(0.28, 0.28, 0.35, 1.0)
    end
    if btn.Show then btn:Show() end
end

-- Restore all docked buttons to their original state
function PUIMinimapOrbit:RestoreButtons()
    for btn, state in pairs(savedState) do
        if btn and state then
            if btn.SetParent then btn:SetParent(state.parent or Minimap) end
            if btn.ClearAllPoints then btn:ClearAllPoints() end
            if state.points and table.getn(state.points) > 0 and btn.SetPoint then
                for _, pt in ipairs(state.points) do
                    btn:SetPoint(pt.point, pt.relativeTo or state.parent or Minimap, pt.relativePoint or pt.point, pt.xOfs or 0, pt.yOfs or 0)
                end
            elseif btn.SetPoint then
                btn:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
            end
            if state.width and state.height then
                if btn.SetWidth then btn:SetWidth(state.width) end
                if btn.SetHeight then btn:SetHeight(state.height) end
            end
            if state.strata and btn.SetFrameStrata then btn:SetFrameStrata(state.strata) end
            if state.level and btn.SetFrameLevel then btn:SetFrameLevel(state.level) end

            -- Restore hidden textures
            if state.hiddenTextures then
                for _, tex in ipairs(state.hiddenTextures) do
                    if tex and tex.Show then tex:Show() end
                end
            end
        end
    end
    dockedButtons = {}
    savedState = {}
end

-- Collect and dock discovered addon minimap buttons
-- Collect and dock discovered addon minimap buttons
function PUIMinimapOrbit:CollectButtons()
    if not dockFrame or not orbitDB:Get("enabled") then return end

    -- Always ensure Blizzard HUD frames are intact
    RestoreBlizzardFrames()

    dockedButtons = {}
    local seen = {}

    for globalName, obj in pairs(_G) do
        if type(obj) == "table" and type(globalName) == "string" and obj.SetPoint and not seen[obj] then
            if IsMinimapButton(globalName, obj) then
                seen[obj] = true
                SaveButtonState(obj)
                table.insert(dockedButtons, obj)
            end
        end
    end

    if not dockFrame.emptyText then
        local et = dockFrame:CreateFontString(nil, "OVERLAY")
        et:SetFont(Media:Fetch("font", "Default") or "Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        et:SetPoint("CENTER", dockFrame, "CENTER", 0, 0)
        et:SetTextColor(0.6, 0.6, 0.7)
        et:SetText("No Addon Buttons")
        dockFrame.emptyText = et
    end

    local count = table.getn(dockedButtons)
    if count == 0 then
        dockFrame:SetWidth(110)
        dockFrame:SetHeight(28)
        dockFrame.emptyText:Show()
        return
    end

    dockFrame.emptyText:Hide()

    -- Responsive grid layout: 1 column for <= 6 buttons, 2 columns for > 6 buttons
    local cols = (count > 6) and 2 or 1
    local btnSize = orbitDB:Get("buttonSize", 28)
    local gap = 4
    local pad = 4
    local cellSpan = btnSize + gap

    for i = 1, count do
        local btn = dockedButtons[i]
        local col = math.mod(i - 1, cols)
        local row = math.floor((i - 1) / cols)
        local x = pad + col * cellSpan
        local y = -pad - row * cellSpan

        btn:ClearAllPoints()
        btn:SetParent(dockFrame)
        btn:SetPoint("TOPLEFT", dockFrame, "TOPLEFT", x, y)
        SkinDockedButton(btn)
        btn:Show()
    end

    local numRows = math.ceil(count / cols)
    dockFrame:SetWidth(pad * 2 + cols * btnSize + (cols - 1) * gap)
    dockFrame:SetHeight(pad * 2 + numRows * btnSize + (numRows - 1) * gap)
end

-- Public Toggle Method for Dock Flyout Drawer
function PUIMinimapOrbit:ToggleDock(anchorBtn, side)
    if not dockFrame then return end
    anchorBtn = anchorBtn or toggleButton

    if dockFrame:IsShown() then
        dockFrame:Hide()
        orbitDB:Set("collapsed", true)
    else
        self:CollectButtons()
        dockFrame:ClearAllPoints()
        dockFrame:SetParent(UIParent)
        dockFrame:SetFrameStrata("DIALOG")
        dockFrame:SetFrameLevel(100)

        side = side or "LEFT"
        if side == "LEFT" then
            dockFrame:SetPoint("TOPRIGHT", anchorBtn, "TOPLEFT", -4, 0)
        elseif side == "RIGHT" then
            dockFrame:SetPoint("TOPLEFT", anchorBtn, "TOPRIGHT", 4, 0)
        elseif side == "BOTTOM" then
            dockFrame:SetPoint("TOPRIGHT", anchorBtn, "BOTTOMRIGHT", 0, -4)
        else
            dockFrame:SetPoint("TOPRIGHT", anchorBtn, "TOPLEFT", -4, 0)
        end

        dockFrame:Show()
        orbitDB:Set("collapsed", false)
    end
end

function PUIMinimapOrbit:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIMinimapOrbit", {
        name = "PUIMinimapOrbit",
        category = "Utility",
        label = "Minimap Orbit",
        icon = "Interface\\Icons\\INV_Misc_Bag_10",
        desc = "Consolidates add-on minimap buttons into a sleek expandable orbit dock.",
    })
end

function PUIMinimapOrbit:OnInitialize()
    self:RegisterOptionsFlare()

    -- Ensure Blizzard zone text is restored immediately if not managed by PUIMinimapper
    RestoreBlizzardFrames()

    -- Create Main Orbit Toggle Button on UIParent (defaults anchored to Minimap)
    toggleButton = CreateFrame("Button", "Primus_MinimapOrbitBtn", UIParent)
    toggleButton:SetWidth(24)
    toggleButton:SetHeight(24)
    toggleButton:SetPoint("TOPRIGHT", Minimap or UIParent, "TOPRIGHT", -2, -2)
    toggleButton:SetFrameStrata("HIGH")
    toggleButton:SetFrameLevel(25)
    toggleButton:SetMovable(true)
    toggleButton:SetBackdrop(Media:Fetch("border", "1Pixel"))
    toggleButton:SetBackdropColor(0.1, 0.1, 0.12, 0.95)
    toggleButton:SetBackdropBorderColor(0.3, 0.6, 1.0, 1.0)
    toggleButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local icon = toggleButton:CreateTexture(nil, "OVERLAY")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
    icon:SetPoint("TOPLEFT", toggleButton, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", toggleButton, "BOTTOMRIGHT", -2, 2)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Register with PUIMover under UTILITY
    local mover = Primus.PUIMover or PUIMover
    if mover and mover.Register then
        mover:Register(toggleButton, "PUIMinimapOrbit", "Minimap Orbit Pill", "UTILITY")
    end

    -- Create Dock Container Frame on UIParent so it is never suppressed by hidden parents
    dockFrame = CreateFrame("Frame", "Primus_MinimapOrbitDock", UIParent)
    dockFrame:SetFrameStrata("DIALOG")
    dockFrame:SetFrameLevel(100)
    dockFrame:SetWidth(36)
    dockFrame:SetHeight(36)
    dockFrame:SetPoint("TOPRIGHT", toggleButton, "BOTTOMRIGHT", 0, -4)
    dockFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
    dockFrame:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
    dockFrame:SetBackdropBorderColor(0.25, 0.25, 0.32, 1.0)
    dockFrame:Hide()
    PUIMinimapOrbit.dockFrame = dockFrame

    -- Hover highlight & Tooltips
    toggleButton:SetScript("OnEnter", function()
        this:SetBackdropBorderColor(0.5, 0.8, 1.0, 1.0)
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:AddLine(Utils.ColorText("Primus Minimap Orbit", "40b0ff"))
        GameTooltip:AddLine("Consolidates addon minimap buttons.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine(Utils.ColorText("Left-Click:", "ffffff") .. " Toggle Addon Dock (" .. (dockFrame:IsShown() and "Open" or "Closed") .. ")", 0.9, 0.9, 0.9)
        GameTooltip:AddLine(Utils.ColorText("Right-Click:", "ffffff") .. " Rescan Addon Buttons", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)

    toggleButton:SetScript("OnLeave", function()
        this:SetBackdropBorderColor(0.3, 0.6, 1.0, 1.0)
        GameTooltip:Hide()
    end)

    toggleButton:SetScript("OnClick", function()
        if arg1 == "RightButton" then
            PUIMinimapOrbit:CollectButtons()
            if Primus.Console and Primus.Console.Print then
                Primus.Console:Print("Minimap Orbit rescanned and consolidated buttons.")
            end
        else
            PUIMinimapOrbit:ToggleDock(toggleButton, "BOTTOM")
        end
    end)

    -- Delayed initial scan after addons have initialized
    Time:After(3.0, function()
        RestoreBlizzardFrames()
        if orbitDB:Get("enabled", true) then
            PUIMinimapOrbit:CollectButtons()
            if not orbitDB:Get("collapsed", true) then
                dockFrame:Show()
            end
        end
    end)
end
