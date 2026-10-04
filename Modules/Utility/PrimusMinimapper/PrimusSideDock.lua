--[[
    PrimusUI Module: PUIMinimapper - PUISideDock
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Subsystem: Side Utility Dock, Clock Button, Minimap Orbit Button & Tracking Integration.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIMinimapper = Primus.PUIMinimapper or {}
Primus.PUIMinimapper = PUIMinimapper
_G.PUIMinimapper = PUIMinimapper

local Media = Primus.Media
local Utils = Primus.Utils

-- Update Clock Tooltip on Hover
function PUIMinimapper:UpdateClockTooltip()
    local btn = self.clockBtn
    if not btn or not GameTooltip:IsOwned(btn) then return end

    local db = self.db
    local sHour, sMin = GetGameTime()
    local lTime = date("%I:%M:%S %p")
    local lDate = date("%A, %B %d, %Y")
    local sTime = string.format("%02d:%02d", sHour or 0, sMin or 0)
    local is24h = db and db:Get("clock24Hour", true)

    if is24h then
        lTime = date("%H:%M:%S")
    end

    GameTooltip:ClearLines()
    GameTooltip:AddLine(Utils.ColorText("Time & Schedule", "40b0ff"))
    GameTooltip:AddDoubleLine(Utils.ColorText("Local Time:", "ffffff"), lTime, 1, 1, 1, 0.9, 0.9, 0.2)
    GameTooltip:AddDoubleLine(Utils.ColorText("Server Time:", "ffffff"), sTime, 1, 1, 1, 0.4, 0.8, 1.0)
    GameTooltip:AddDoubleLine(Utils.ColorText("Date:", "ffffff"), lDate, 1, 1, 1, 0.8, 0.8, 0.8)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(Utils.ColorText("Left-Click:", "ffffff") .. " Toggle 24h / 12h Format (" .. (is24h and "24h" or "12h") .. ")", 0.7, 0.7, 0.7)
    GameTooltip:AddLine(Utils.ColorText("Right-Click:", "ffffff") .. " Toggle Local / Server Display", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

-- Layout & Dimension Synchronization
function PUIMinimapper:RepositionSideDock()
    local dock = self.sideDockFrame
    local container = self.containerFrame
    if not dock or not container then return end

    local db = self.db
    local showDock = db and db:Get("showSideDock", true)
    if not showDock then
        dock:Hide()
        return
    end

    local side = db and db:Get("buttonDockSide", "LEFT") or "LEFT"
    dock:ClearAllPoints()

    if side == "LEFT" then
        dock:SetPoint("TOPRIGHT", container, "TOPLEFT", -2, 0)
        dock:SetPoint("BOTTOMRIGHT", container, "BOTTOMLEFT", -2, 0)
    else
        dock:SetPoint("TOPLEFT", container, "TOPRIGHT", 2, 0)
        dock:SetPoint("BOTTOMLEFT", container, "BOTTOMRIGHT", 2, 0)
    end
    dock:Show()

    -- Layout buttons vertically inside sideDockFrame
    local curAnchor = dock
    local curPoint  = "TOP"
    local curOffset = -2

    -- 1. Clock Button
    if self.clockBtn then
        if db:Get("showClock", true) then
            self.clockBtn:ClearAllPoints()
            self.clockBtn:SetPoint("TOP", curAnchor, curPoint, 0, curOffset)
            self.clockBtn:Show()
            curAnchor = self.clockBtn
            curPoint  = "BOTTOM"
            curOffset = -2
        else
            self.clockBtn:Hide()
        end
    end

    -- 2. Minimap Orbit Button
    if self.orbitBtn then
        if db:Get("showOrbit", true) then
            self.orbitBtn:ClearAllPoints()
            self.orbitBtn:SetPoint("TOP", curAnchor, curPoint, 0, curOffset)
            self.orbitBtn:Show()
            curAnchor = self.orbitBtn
            curPoint  = "BOTTOM"
            curOffset = -2
        else
            self.orbitBtn:Hide()
        end
    end

    -- 3. Blizzard Tracking Frame
    if MiniMapTrackingFrame then
        MiniMapTrackingFrame:ClearAllPoints()
        MiniMapTrackingFrame:SetParent(dock)
        MiniMapTrackingFrame:SetPoint("TOP", curAnchor, curPoint, 0, curOffset)
        MiniMapTrackingFrame:SetScale(0.72)
        MiniMapTrackingFrame:SetFrameLevel(dock:GetFrameLevel() + 5)
        curAnchor = MiniMapTrackingFrame
        curPoint  = "BOTTOM"
        curOffset = -2
    end

    -- 4. Blizzard Mail Icon
    if MiniMapMailFrame then
        MiniMapMailFrame:ClearAllPoints()
        MiniMapMailFrame:SetParent(dock)
        MiniMapMailFrame:SetPoint("TOP", curAnchor, curPoint, 0, curOffset)
        MiniMapMailFrame:SetScale(0.8)
        MiniMapMailFrame:SetFrameLevel(dock:GetFrameLevel() + 5)
        curAnchor = MiniMapMailFrame
        curPoint  = "BOTTOM"
        curOffset = -2
    end

    -- 5. Meeting Stone Icon
    if MiniMapMeetingStoneFrame then
        MiniMapMeetingStoneFrame:ClearAllPoints()
        MiniMapMeetingStoneFrame:SetParent(dock)
        MiniMapMeetingStoneFrame:SetPoint("TOP", curAnchor, curPoint, 0, curOffset)
        MiniMapMeetingStoneFrame:SetScale(0.72)
        MiniMapMeetingStoneFrame:SetFrameLevel(dock:GetFrameLevel() + 5)
        curAnchor = MiniMapMeetingStoneFrame
        curPoint  = "BOTTOM"
        curOffset = -2
    end

    -- 6. Battlefield / PVP Icon
    if MiniMapBattlefieldFrame then
        MiniMapBattlefieldFrame:ClearAllPoints()
        MiniMapBattlefieldFrame:SetParent(dock)
        MiniMapBattlefieldFrame:SetPoint("TOP", curAnchor, curPoint, 0, curOffset)
        MiniMapBattlefieldFrame:SetScale(0.72)
        MiniMapBattlefieldFrame:SetFrameLevel(dock:GetFrameLevel() + 5)
    end

    -- Re-anchor active orbit flyout drawer if open
    local orbDock = _G["Primus_MinimapOrbitDock"]
    if orbDock and orbDock:IsShown() and self.orbitBtn then
        orbDock:ClearAllPoints()
        orbDock:SetParent(UIParent)
        orbDock:SetFrameStrata("DIALOG")
        orbDock:SetFrameLevel(100)
        if side == "LEFT" then
            orbDock:SetPoint("TOPRIGHT", self.orbitBtn, "TOPLEFT", -4, 0)
        else
            orbDock:SetPoint("TOPLEFT", self.orbitBtn, "TOPRIGHT", 4, 0)
        end
    end
end

-- Build Side Dock Frame
function PUIMinimapper:BuildSideDock()
    if self.sideDockFrame then return self.sideDockFrame end
    local container = self.containerFrame
    if not container then return end

    local dock = CreateFrame("Frame", "Primus_MinimapSideDock", container)
    dock:SetWidth(24)
    dock:SetBackdrop(Media:Fetch("border", "1Pixel"))
    dock:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
    dock:SetBackdropBorderColor(0.28, 0.28, 0.35, 1.0)
    dock:SetFrameLevel(container:GetFrameLevel() + 1)

    -- 1. Clock Button
    local clock = CreateFrame("Button", "Primus_MinimapClockBtn", dock)
    clock:SetWidth(20)
    clock:SetHeight(20)
    clock:SetBackdrop(Media:Fetch("border", "1Pixel"))
    clock:SetBackdropColor(0.10, 0.10, 0.12, 0.95)
    clock:SetBackdropBorderColor(0.28, 0.28, 0.35, 1.0)
    clock:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local cIcon = clock:CreateTexture(nil, "ARTWORK")
    cIcon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    cIcon:SetPoint("TOPLEFT", clock, "TOPLEFT", 2, -2)
    cIcon:SetPoint("BOTTOMRIGHT", clock, "BOTTOMRIGHT", -2, 2)
    cIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    clock:SetScript("OnEnter", function()
        this:SetBackdropBorderColor(0.45, 0.75, 1.0, 1.0)
        PUIMinimapper:UpdateClockTooltip()
    end)

    clock:SetScript("OnLeave", function()
        this:SetBackdropBorderColor(0.28, 0.28, 0.35, 1.0)
        GameTooltip:Hide()
    end)

    clock:SetScript("OnClick", function()
        local db = PUIMinimapper.db
        if not db then return end
        if arg1 == "RightButton" then
            local cur = db:Get("clockUseServerTime", false)
            db:Set("clockUseServerTime", not cur)
        else
            local cur24 = db:Get("clock24Hour", true)
            db:Set("clock24Hour", not cur24)
        end
        PUIMinimapper:UpdateClockTooltip()
    end)

    -- 2. Minimap Orbit Button
    local orbit = CreateFrame("Button", "Primus_MinimapOrbitDockBtn", dock)
    orbit:SetWidth(20)
    orbit:SetHeight(20)
    orbit:SetBackdrop(Media:Fetch("border", "1Pixel"))
    orbit:SetBackdropColor(0.10, 0.10, 0.12, 0.95)
    orbit:SetBackdropBorderColor(0.30, 0.60, 1.00, 1.0)
    orbit:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local oIcon = orbit:CreateTexture(nil, "ARTWORK")
    oIcon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
    oIcon:SetPoint("TOPLEFT", orbit, "TOPLEFT", 2, -2)
    oIcon:SetPoint("BOTTOMRIGHT", orbit, "BOTTOMRIGHT", -2, 2)
    oIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    orbit:SetScript("OnEnter", function()
        this:SetBackdropBorderColor(0.50, 0.85, 1.0, 1.0)
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:AddLine(Utils.ColorText("Primus Minimap Orbit", "40b0ff"))
        GameTooltip:AddLine("Consolidates 3rd-party addon minimap buttons.", 0.8, 0.8, 0.8)
        local orbDock = _G["Primus_MinimapOrbitDock"]
        local isShown = orbDock and orbDock:IsShown()
        GameTooltip:AddLine(Utils.ColorText("Left-Click:", "ffffff") .. " Toggle Addon Dock (" .. (isShown and "Open" or "Closed") .. ")", 0.9, 0.9, 0.9)
        GameTooltip:AddLine(Utils.ColorText("Right-Click:", "ffffff") .. " Rescan Addon Buttons", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)

    orbit:SetScript("OnLeave", function()
        this:SetBackdropBorderColor(0.30, 0.60, 1.00, 1.0)
        GameTooltip:Hide()
    end)

    orbit:SetScript("OnClick", function()
        local orbitMod = Primus.PUIMinimapOrbit or _G.PUIMinimapOrbit
        local db       = PUIMinimapper.db
        local side     = db and db:Get("buttonDockSide", "LEFT") or "LEFT"

        if arg1 == "RightButton" then
            if orbitMod and orbitMod.CollectButtons then
                orbitMod:CollectButtons()
            end
            if Primus.Console and Primus.Console.Print then
                Primus.Console:Print("Minimap Orbit rescanned and consolidated buttons.")
            end
        else
            if orbitMod and orbitMod.ToggleDock then
                orbitMod:ToggleDock(this, side)
            else
                local orbDock = _G["Primus_MinimapOrbitDock"]
                local orbitDB = Primus.DB and Primus.DB:GetNamespace("PUIMinimapOrbit")
                if orbDock then
                    if orbDock:IsShown() then
                        orbDock:Hide()
                        if orbitDB then orbitDB:Set("collapsed", true) end
                    else
                        if orbitMod and orbitMod.CollectButtons then
                            orbitMod:CollectButtons()
                        end
                        orbDock:ClearAllPoints()
                        orbDock:SetParent(UIParent)
                        orbDock:SetFrameStrata("DIALOG")
                        orbDock:SetFrameLevel(100)
                        if side == "LEFT" then
                            orbDock:SetPoint("TOPRIGHT", this, "TOPLEFT", -4, 0)
                        else
                            orbDock:SetPoint("TOPLEFT", this, "TOPRIGHT", 4, 0)
                        end
                        orbDock:Show()
                        if orbitDB then orbitDB:Set("collapsed", false) end
                    end
                end
            end
        end
    end)

    self.sideDockFrame = dock
    self.clockBtn      = clock
    self.clockIcon     = cIcon
    self.orbitBtn      = orbit
    self.orbitIcon     = oIcon

    self:RepositionSideDock()
    return dock
end
