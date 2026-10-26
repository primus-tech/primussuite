--[[
    PrimusUI Module: PUIMover (Categorized Mover Engine & UI Layout Orchestrator)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    1. Visual frame unlocking with categorized filter isolation (BARS, UNITS, HUD, PLAYER, CLASS, SOCIAL, UTILITY).
    2. Interactive floating mover dock with category pill buttons.
    3. Fullscreen magnetic alignment grid ([GRID]).
    4. 1-Pixel precision coordinate nudging ([▲] [▼] [◄] [►]).
    5. Persistent position serialization via SavedVariables (PUIMover namespace).
    6. Slash command routing (/pui move [category]).
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIMover = Primus.PUIMover or {}
Primus.PUIMover = PUIMover
_G.PUIMover = PUIMover
Primus:RegisterModule("PUIMover", PUIMover, "Utility")

local DB      = Primus.DB
local Media   = Primus.Media
local Utils   = Primus.Utils
local Events  = Primus.Events

local registeredFrames = {}
local moverOverlays    = {}
local isUnlocked       = false
local activeCategory   = "BARS"
local selectedKey      = nil
local moverDockFrame   = nil
local moverGridFrame   = nil
local isGridShown      = false

-- Valid Category Table
local VALID_CATEGORIES = {
    ["BARS"]    = "Action Bars",
    ["UNITS"]   = "Unit Frames",
    ["HUD"]     = "HUD & Auras",
    ["PLAYER"]  = "Player & Bags",
    ["CLASS"]   = "Class Nuance",
    ["SOCIAL"]  = "Social & Chat",
    ["UTILITY"] = "Utilities",
}

-- Persistent Database for Frame Positions & Scales
local moverDB = DB:RegisterNamespace("PUIMover", {
    positions = {},
    scales = {},
    showGrid = false,
})

-- Default dimensions for frames that have 0 width/height when inactive
local DEFAULT_DIMS = {
    ["BuffFrame"]               = { w = 180, h = 50 },
    ["DurabilityFrame"]         = { w = 60,  h = 60 },
    ["QuestWatchFrame"]         = { w = 220, h = 150 },
    ["UIErrorsFrame"]           = { w = 400, h = 40 },
    ["WorldStateAlwaysUpFrame"] = { w = 160, h = 40 },
    ["MirrorTimer1"]            = { w = 160, h = 25 },
    ["ComboFrame"]              = { w = 80,  h = 20 },
    ["PUIHotbars_Bar1"]         = { w = 476, h = 36 },
    ["PUIHotbars_Bar2"]         = { w = 476, h = 36 },
    ["PUIHotbars_Bar3"]         = { w = 476, h = 36 },
    ["PUIHotbars_Bar4"]         = { w = 36,  h = 476 },
    ["PUIHotbars_Bar5"]         = { w = 36,  h = 476 },
    ["PUIHotbars_Stance"]       = { w = 336, h = 30 },
    ["PUIHotbars_Pet"]          = { w = 336, h = 30 },
    ["PUIHotbars_XP"]           = { w = 476, h = 10 },
    ["PUIHotbars_Micro"]        = { w = 224, h = 58 },
    ["PUIHotbars_Bags"]         = { w = 210, h = 39 },
    ["PUIMinimapOrbit"]         = { w = 24,  h = 24 },
    ["PUIMinimapper"]           = { w = 160, h = 160 },
    ["PUIAuras"]                = { w = 280, h = 120 },
    ["PUIHud"]                  = { w = 360, h = 290 },
    ["Primus_Unit_player"]      = { w = 180, h = 32 },
    ["Primus_Unit_target"]      = { w = 180, h = 32 },
    ["Primus_Unit_targettarget"]= { w = 120, h = 24 },
    ["Primus_Unit_pet"]         = { w = 120, h = 24 },
    ["Primus_Unit_party1"]      = { w = 140, h = 28 },
    ["Primus_Unit_party2"]      = { w = 140, h = 28 },
    ["Primus_Unit_party3"]      = { w = 140, h = 28 },
    ["Primus_Unit_party4"]      = { w = 140, h = 28 },
    ["RaidGrid"]                = { w = 320, h = 180 },
}

-- Synchronize overlay coordinates and bounding box to match linked frame
local function SyncOverlayToFrame(overlay, frame, key)
    if not overlay or not frame then return end

    local scale = PUIMover.GetScale and PUIMover:GetScale(key) or 1.0
    if frame.SetScale and frame:GetScale() ~= scale then
        frame:SetScale(scale)
    end
    if overlay.SetScale then
        overlay:SetScale(scale)
    end

    local w = frame:GetWidth() or 0
    local h = frame:GetHeight() or 0
    local dims = DEFAULT_DIMS[key]
    if (w < 16 or h < 16) and dims then
        w = dims.w
        h = dims.h
        if frame.SetWidth and (not frame:GetWidth() or frame:GetWidth() < 16) then
            frame:SetWidth(w)
        end
        if frame.SetHeight and (not frame:GetHeight() or frame:GetHeight() < 16) then
            frame:SetHeight(h)
        end
    end

    -- If frame has 0 dimensions, attempt to compute bounding box from active children
    if (w < 16 or h < 16) and frame.GetChildren then
        local left, right, top, bottom
        local children = { frame:GetChildren() }
        local numChildren = table.getn(children)
        for i = 1, numChildren do
            local child = children[i]
            if child and child.GetLeft and child:GetLeft() and (child.IsShown and child:IsShown()) then
                local cL, cR, cT, cB = child:GetLeft(), child:GetRight(), child:GetTop(), child:GetBottom()
                if cL and cR and cT and cB then
                    left = (not left or cL < left) and cL or left
                    right = (not right or cR > right) and cR or right
                    bottom = (not bottom or cB < bottom) and cB or bottom
                    top = (not top or cT > top) and cT or top
                end
            end
        end
        if left and right and top and bottom and right > left and top > bottom then
            local fs = frame:GetEffectiveScale() or 1
            local us = UIParent:GetEffectiveScale() or 1
            w = (right - left) * (us / fs)
            h = (top - bottom) * (us / fs)
            if frame.SetWidth and (not frame:GetWidth() or frame:GetWidth() < 16) then
                frame:SetWidth(w)
            end
            if frame.SetHeight and (not frame:GetHeight() or frame:GetHeight() < 16) then
                frame:SetHeight(h)
            end
        end
    end

    if w < 16 then w = 36 if frame.SetWidth then frame:SetWidth(w) end end
    if h < 16 then h = 36 if frame.SetHeight then frame:SetHeight(h) end end
    overlay:SetWidth(w)
    overlay:SetHeight(h)

    -- Ensure target frame has valid anchor point
    local pos = moverDB and moverDB:Get("positions")
    if pos and pos[key] then
        local p = pos[key]
        frame:ClearAllPoints()
        frame:SetPoint(p.point or "CENTER", UIParent, p.relativePoint or "CENTER", p.x or 0, p.y or 0)
    elseif not frame:GetPoint() then
        local defaultAnchors = {
            ["PUIMinimapper"]           = { point = "TOPRIGHT", rel = "TOPRIGHT", x = -10, y = -10 },
            ["QuestWatchFrame"]         = { point = "TOPRIGHT", rel = "TOPRIGHT", x = -10, y = -200 },
            ["DurabilityFrame"]         = { point = "TOPRIGHT", rel = "TOPRIGHT", x = -170, y = -200 },
            ["WorldStateAlwaysUpFrame"] = { point = "TOP",      rel = "TOP",      x = 0, y = -15 },
            ["UIErrorsFrame"]           = { point = "TOP",      rel = "TOP",      x = 0, y = -120 },
            ["MirrorTimer1"]            = { point = "TOP",      rel = "TOP",      x = 0, y = -96 },
            ["ComboFrame"]              = { point = "CENTER",   rel = "CENTER",   x = 0, y = -150 },
        }
        local def = defaultAnchors[key]
        frame:ClearAllPoints()
        if def then
            frame:SetPoint(def.point, UIParent, def.rel, def.x, def.y)
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end

    -- Center overlay directly over target frame with exact matched dimensions
    overlay:ClearAllPoints()
    overlay:SetPoint("CENTER", frame, "CENTER", 0, 0)
    overlay:SetWidth(w)
    overlay:SetHeight(h)
end

-- Forward declaration for scale API
local function GetFrameScale(key)
    if not key then return 1.0 end
    local scales = moverDB and moverDB:Get("scales")
    if scales and scales[key] then
        return tonumber(scales[key]) or 1.0
    end
    local entry = registeredFrames and registeredFrames[key]
    if entry and entry.frame and entry.frame.GetScale then
        local s = entry.frame:GetScale()
        if s and s > 0 then return Utils.Round(s, 2) end
    end
    return 1.0
end

-- Update Dock Selection Text
local function UpdateDockSelectionDisplay()
    if not moverDockFrame then return end
    if not selectedKey or not registeredFrames[selectedKey] then
        if moverDockFrame.nudgeText then
            moverDockFrame.nudgeText:SetText(Utils.ColorText("Select a frame to nudge or scroll wheel to scale", "888888"))
        end
        if moverDockFrame.scaleValText then
            moverDockFrame.scaleValText:SetText("1.00x")
            moverDockFrame.scaleValText:SetTextColor(0.6, 0.6, 0.6)
        end
        return
    end

    local entry = registeredFrames[selectedKey]
    local scale = PUIMover.GetScale and PUIMover:GetScale(selectedKey) or GetFrameScale(selectedKey)
    if entry.frame then
        local point, relativeTo, relativePoint, xOfs, yOfs = entry.frame:GetPoint()
        local name = entry.name or selectedKey
        if moverDockFrame.nudgeText then
            moverDockFrame.nudgeText:SetText(string.format("%s: %s (%d, %d) | Scale: %s",
                Utils.ColorText(name, "69ccf0"),
                point or "CENTER",
                Utils.Round(xOfs or 0),
                Utils.Round(yOfs or 0),
                Utils.ColorText(string.format("%.2fx", scale), "ffd100")
            ))
        end
    end
    if moverDockFrame.scaleValText then
        moverDockFrame.scaleValText:SetText(string.format("%.2fx", scale))
        moverDockFrame.scaleValText:SetTextColor(0.4, 0.9, 1.0)
    end
end

-- Set Currently Selected Frame for Nudging
function PUIMover:SelectFrame(key)
    selectedKey = key
    for k, ov in pairs(moverOverlays) do
        if k == key then
            ov:SetBackdropBorderColor(1.0, 0.9, 0.2, 1.0) -- Selected gold border
            ov:SetBackdropColor(0.25, 0.55, 0.95, 0.65)
        else
            ov:SetBackdropBorderColor(0.3, 0.8, 1.0, 1.0) -- Normal cyan border
            ov:SetBackdropColor(0.15, 0.45, 0.85, 0.5)
        end
    end
    UpdateDockSelectionDisplay()
end

-- Nudge Selected Frame by dx, dy
function PUIMover:NudgeSelected(dx, dy)
    if not selectedKey or not moverOverlays[selectedKey] then return end
    local overlay = moverOverlays[selectedKey]
    local entry = registeredFrames[selectedKey]
    if not overlay or not entry or not entry.frame then return end

    local point, relativeTo, relativePoint, xOfs, yOfs = entry.frame:GetPoint()
    point = point or "CENTER"
    relativePoint = relativePoint or point
    xOfs = (xOfs or 0) + dx
    yOfs = (yOfs or 0) + dy

    entry.frame:ClearAllPoints()
    entry.frame:SetPoint(point, UIParent, relativePoint, xOfs, yOfs)
    if entry.frame.SetUserPlaced then
        entry.frame:SetUserPlaced(true)
    end

    local pos = moverDB:Get("positions")
    pos[selectedKey] = {
        point = point,
        relativePoint = relativePoint,
        x = Utils.Round(xOfs),
        y = Utils.Round(yOfs),
    }
    moverDB:Set("positions", pos)

    overlay:ClearAllPoints()
    overlay:SetPoint("CENTER", entry.frame, "CENTER", 0, 0)
    overlay:SetWidth(entry.frame:GetWidth() or 36)
    overlay:SetHeight(entry.frame:GetHeight() or 36)

    UpdateDockSelectionDisplay()
end

-- Create visual drag overlay for a frame
local function CreateOverlay(frame, key, friendlyName, category)
    if moverOverlays[key] then return moverOverlays[key] end

    local overlay = CreateFrame("Button", "Primus_PUIMover_" .. key, UIParent)
    overlay:SetFrameStrata("TOOLTIP")
    overlay:SetBackdrop(Media:Fetch("border", "1Pixel"))
    overlay:SetBackdropColor(0.15, 0.45, 0.85, 0.5)
    overlay:SetBackdropBorderColor(0.3, 0.8, 1.0, 1.0)
    overlay:EnableMouse(true)
    overlay:EnableMouseWheel(true)
    overlay:SetMovable(true)
    overlay:RegisterForDrag("LeftButton")
    overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    overlay:Hide()

    SyncOverlayToFrame(overlay, frame, key)

    local label = overlay:CreateFontString(nil, "OVERLAY")
    label:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    label:SetPoint("CENTER", 0, 0)
    label:SetText(friendlyName or key)
    label:SetTextColor(1, 1, 1)
    overlay.label = label
    overlay.targetFrame = frame
    overlay.targetKey = key
    overlay.targetCategory = category or "UTILITY"

    overlay:SetScript("OnClick", function()
        PUIMover:SelectFrame(key)
    end)

    overlay:SetScript("OnDragStart", function()
        PUIMover:SelectFrame(key)
        overlay:StartMoving()
    end)

    overlay:SetScript("OnMouseWheel", function()
        PUIMover:SelectFrame(key)
        local delta = arg1
        if delta then
            local step = IsShiftKeyDown() and 0.10 or 0.05
            if PUIMover.ScaleSelected then
                PUIMover:ScaleSelected(delta * step)
            end
        end
    end)

    overlay:SetScript("OnEnter", function()
        GameTooltip:SetOwner(overlay, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(Utils.ColorText(friendlyName or key, "69ccf0"))
        GameTooltip:AddLine(string.format("Category: |cffffffff%s|r", category or "UTILITY"), 0.8, 0.8, 0.8)
        local curS = PUIMover.GetScale and PUIMover:GetScale(key) or 1.0
        GameTooltip:AddLine(string.format("Scale: |cffffd100%.2fx|r", curS), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ff00Drag:|r Move Frame", 0.7, 0.9, 0.7)
        GameTooltip:AddLine("|cff00e5ffScroll Wheel:|r Scale Frame (+/-0.05x, Shift: +/-0.10x)", 0.7, 0.9, 0.7)
        GameTooltip:Show()
    end)

    overlay:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    overlay:SetScript("OnDragStop", function()
        overlay:StopMovingOrSizing()

        local point, relativeTo, relativePoint, xOfs, yOfs = overlay:GetPoint()
        
        -- Sync target frame point cleanly to UIParent with exact coordinates
        if frame then
            frame:ClearAllPoints()
            frame:SetPoint(point or "CENTER", UIParent, relativePoint or point or "CENTER", xOfs or 0, yOfs or 0)
            if frame.SetUserPlaced then
                frame:SetUserPlaced(true)
            end
        end

        -- Save position to persistent storage
        local pos = moverDB:Get("positions")
        pos[key] = {
            point = point or "CENTER",
            relativePoint = relativePoint or point or "CENTER",
            x = Utils.Round(xOfs or 0),
            y = Utils.Round(yOfs or 0),
        }
        moverDB:Set("positions", pos)

        -- Re-lock overlay directly to target frame with exact dimensions
        overlay:ClearAllPoints()
        overlay:SetPoint("CENTER", frame, "CENTER", 0, 0)
        overlay:SetWidth(frame:GetWidth() or 36)
        overlay:SetHeight(frame:GetHeight() or 36)

        UpdateDockSelectionDisplay()
    end)

    moverOverlays[key] = overlay
    return overlay
end

-- =========================================================================
-- ALIGNMENT GRID OVERLAY
-- =========================================================================

local function CreateGridOverlay()
    if moverGridFrame then return moverGridFrame end

    local grid = CreateFrame("Frame", "Primus_PUIMoverGrid", UIParent)
    grid:SetAllPoints(UIParent)
    grid:SetFrameStrata("BACKGROUND")
    grid:EnableMouse(false)
    grid:Hide()

    local screenW = GetScreenWidth() or 1024
    local screenH = GetScreenHeight() or 768
    local step = 32

    -- Vertical Grid Lines
    local xCount = math.floor(screenW / step)
    for i = 1, xCount do
        local line = grid:CreateTexture(nil, "BACKGROUND")
        line:SetTexture(Media:Fetch("statusbar", "Flat"))
        line:SetWidth(1)
        line:SetHeight(screenH)
        line:SetPoint("TOPLEFT", grid, "TOPLEFT", i * step, 0)
        if math.abs(i * step - (screenW / 2)) < (step / 2) then
            line:SetVertexColor(0.2, 0.8, 1.0, 0.45) -- Center axis cyan
            line:SetWidth(2)
        else
            line:SetVertexColor(1, 1, 1, 0.08)
        end
    end

    -- Horizontal Grid Lines
    local yCount = math.floor(screenH / step)
    for j = 1, yCount do
        local line = grid:CreateTexture(nil, "BACKGROUND")
        line:SetTexture(Media:Fetch("statusbar", "Flat"))
        line:SetHeight(1)
        line:SetWidth(screenW)
        line:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -j * step)
        if math.abs(j * step - (screenH / 2)) < (step / 2) then
            line:SetVertexColor(0.2, 0.8, 1.0, 0.45) -- Center axis cyan
            line:SetHeight(2)
        else
            line:SetVertexColor(1, 1, 1, 0.08)
        end
    end

    moverGridFrame = grid
    return grid
end

function PUIMover:ToggleGrid()
    local grid = CreateGridOverlay()
    if isGridShown then
        grid:Hide()
        isGridShown = false
    else
        grid:Show()
        isGridShown = true
    end
end

-- =========================================================================
-- FLOATING MOVER CONTROL DOCK
-- =========================================================================

local function CreateMoverDock()
    if moverDockFrame then return moverDockFrame end

    local dock = CreateFrame("Frame", "Primus_PUIMoverDock", UIParent)
    dock:SetWidth(800)
    dock:SetHeight(76)
    dock:SetPoint("TOP", UIParent, "TOP", 0, -15)
    dock:SetFrameStrata("TOOLTIP")
    dock:SetBackdrop(Media:Fetch("border", "1Pixel"))
    dock:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
    dock:SetBackdropBorderColor(0.2, 0.7, 1.0, 1.0)
    dock:EnableMouse(true)
    dock:SetMovable(true)
    dock:RegisterForDrag("LeftButton")
    dock:SetScript("OnDragStart", function() dock:StartMoving() end)
    dock:SetScript("OnDragStop", function() dock:StopMovingOrSizing() end)
    dock:Hide()

    -- Title Header
    local title = dock:CreateFontString(nil, "OVERLAY")
    title:SetFont(Media:Fetch("font", "Default"), 11, "OUTLINE")
    title:SetPoint("TOPLEFT", dock, "TOPLEFT", 12, -8)
    title:SetText(Utils.ColorText("PRIMUS UI MOVER", "69ccf0"))

    -- Nudge Info Readout Text
    local nudgeText = dock:CreateFontString(nil, "OVERLAY")
    nudgeText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    nudgeText:SetPoint("LEFT", title, "RIGHT", 14, 0)
    nudgeText:SetText(Utils.ColorText("Select a frame to nudge or scroll wheel to scale", "888888"))
    dock.nudgeText = nudgeText

    -- Close / Lock Button (Top Right)
    local lockBtn = CreateFrame("Button", "Primus_PUIMoverLockBtn", dock)
    lockBtn:SetWidth(75)
    lockBtn:SetHeight(20)
    lockBtn:SetPoint("TOPRIGHT", dock, "TOPRIGHT", -10, -6)
    lockBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    lockBtn:SetBackdropColor(0.7, 0.15, 0.15, 0.85)
    lockBtn:SetBackdropBorderColor(1.0, 0.3, 0.3, 1.0)
    local lockText = lockBtn:CreateFontString(nil, "OVERLAY")
    lockText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    lockText:SetPoint("CENTER", 0, 0)
    lockText:SetText("Lock UI")
    lockText:SetTextColor(1, 1, 1)
    lockBtn:SetScript("OnClick", function()
        PUIMover:LockAll()
    end)

    -- Grid Toggle Button
    local gridBtn = CreateFrame("Button", "Primus_PUIMoverGridBtn", dock)
    gridBtn:SetWidth(55)
    gridBtn:SetHeight(20)
    gridBtn:SetPoint("RIGHT", lockBtn, "LEFT", -6, 0)
    gridBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    gridBtn:SetBackdropColor(0.2, 0.3, 0.45, 0.85)
    gridBtn:SetBackdropBorderColor(0.3, 0.6, 1.0, 1.0)
    local gridText = gridBtn:CreateFontString(nil, "OVERLAY")
    gridText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    gridText:SetPoint("CENTER", 0, 0)
    gridText:SetText("Grid")
    gridText:SetTextColor(0.8, 0.9, 1.0)
    gridBtn:SetScript("OnClick", function()
        PUIMover:ToggleGrid()
    end)

    -- Reset Positions & Scales Button
    local resetBtn = CreateFrame("Button", "Primus_PUIMoverResetBtn", dock)
    resetBtn:SetWidth(55)
    resetBtn:SetHeight(20)
    resetBtn:SetPoint("RIGHT", gridBtn, "LEFT", -6, 0)
    resetBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    resetBtn:SetBackdropColor(0.35, 0.25, 0.15, 0.85)
    resetBtn:SetBackdropBorderColor(0.9, 0.6, 0.2, 1.0)
    local resetText = resetBtn:CreateFontString(nil, "OVERLAY")
    resetText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    resetText:SetPoint("CENTER", 0, 0)
    resetText:SetText("Reset")
    resetText:SetTextColor(1.0, 0.85, 0.4)
    resetBtn:SetScript("OnClick", function()
        PUIMover:ResetAll()
    end)

    -- Category Pill Button Bar (Row 2)
    local categories = { "BARS", "UNITS", "HUD", "PLAYER", "CLASS", "SOCIAL", "UTILITY" }
    local pillButtons = {}
    dock.pillButtons = pillButtons

    local startX = 12
    local pillW = 66
    local pillH = 22

    for i = 1, table.getn(categories) do
        local cat = categories[i]
        local pill = CreateFrame("Button", "Primus_PUIMoverPill_" .. cat, dock)
        pill:SetWidth(pillW)
        pill:SetHeight(pillH)
        pill:SetPoint("BOTTOMLEFT", dock, "BOTTOMLEFT", startX + (i - 1) * (pillW + 5), 10)
        pill:SetBackdrop(Media:Fetch("border", "1Pixel"))
        pill:SetBackdropColor(0.15, 0.2, 0.25, 0.7)
        pill:SetBackdropBorderColor(0.3, 0.4, 0.5, 0.8)

        local pText = pill:CreateFontString(nil, "OVERLAY")
        pText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
        pText:SetPoint("CENTER", 0, 0)
        pText:SetText(cat == "UTILITY" and "UTIL" or cat)
        pText:SetTextColor(0.8, 0.85, 0.9)
        pill.text = pText
        pill.categoryKey = cat

        pill:SetScript("OnClick", function()
            PUIMover:SetCategoryFilter(this.categoryKey)
        end)

        pillButtons[cat] = pill
    end

    -- Scale Control Buttons (Row 2, Center-Right)
    local function CreateScaleBtn(name, labelText, xOfs, yOfs, width, onClick)
        local btn = CreateFrame("Button", name, dock)
        btn:SetWidth(width or 20)
        btn:SetHeight(20)
        btn:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", xOfs, yOfs)
        btn:SetBackdrop(Media:Fetch("border", "1Pixel"))
        btn:SetBackdropColor(0.18, 0.25, 0.35, 0.85)
        btn:SetBackdropBorderColor(0.3, 0.6, 0.9, 1.0)
        local bText = btn:CreateFontString(nil, "OVERLAY")
        bText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
        bText:SetPoint("CENTER", 0, 0)
        bText:SetText(labelText)
        bText:SetTextColor(1, 1, 1)
        btn.text = bText
        btn:SetScript("OnClick", onClick)
        return btn
    end

    local scaleResetBtn = CreateScaleBtn("Primus_PUIScaleReset", "1x", -98, 12, 24, function()
        if selectedKey and PUIMover.SetScale then
            PUIMover:SetScale(selectedKey, 1.0)
        end
    end)

    local scalePlusBtn = CreateScaleBtn("Primus_PUIScalePlus", "+", -126, 12, 22, function()
        local step = IsShiftKeyDown() and 0.10 or 0.05
        if PUIMover.ScaleSelected then
            PUIMover:ScaleSelected(step)
        end
    end)

    local scaleValText = dock:CreateFontString(nil, "OVERLAY")
    scaleValText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    scaleValText:SetPoint("RIGHT", scalePlusBtn, "LEFT", -4, 0)
    scaleValText:SetText("1.00x")
    scaleValText:SetTextColor(0.4, 0.9, 1.0)
    dock.scaleValText = scaleValText

    local scaleMinusBtn = CreateScaleBtn("Primus_PUIScaleMinus", "-", -184, 12, 22, function()
        local step = IsShiftKeyDown() and 0.10 or 0.05
        if PUIMover.ScaleSelected then
            PUIMover:ScaleSelected(-step)
        end
    end)

    local scaleLabel = dock:CreateFontString(nil, "OVERLAY")
    scaleLabel:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    scaleLabel:SetPoint("RIGHT", scaleMinusBtn, "LEFT", -6, 0)
    scaleLabel:SetText(Utils.ColorText("Scale:", "69ccf0"))

    -- Precision Nudge Buttons (Row 2, Far Right)
    local function CreateNudgeBtn(name, labelText, xOfs, yOfs, dx, dy)
        local btn = CreateFrame("Button", name, dock)
        btn:SetWidth(20)
        btn:SetHeight(20)
        btn:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT", xOfs, yOfs)
        btn:SetBackdrop(Media:Fetch("border", "1Pixel"))
        btn:SetBackdropColor(0.18, 0.25, 0.35, 0.85)
        btn:SetBackdropBorderColor(0.3, 0.6, 0.9, 1.0)
        local bText = btn:CreateFontString(nil, "OVERLAY")
        bText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
        bText:SetPoint("CENTER", 0, 0)
        bText:SetText(labelText)
        bText:SetTextColor(1, 1, 1)

        btn:SetScript("OnClick", function()
            local step = IsShiftKeyDown() and 5 or 1
            PUIMover:NudgeSelected(dx * step, dy * step)
        end)
        return btn
    end

    CreateNudgeBtn("Primus_PUINudgeUp",    "▲", -50, 24,  0,  1)
    CreateNudgeBtn("Primus_PUINudgeDown",  "▼", -50,  2,  0, -1)
    CreateNudgeBtn("Primus_PUINudgeLeft",  "◄", -72, 13, -1,  0)
    CreateNudgeBtn("Primus_PUINudgeRight", "►", -28, 13,  1,  0)

    moverDockFrame = dock
    return dock
end

-- Refresh Pill Button Visual Highlighting
local function RefreshPillHighlights()
    if not moverDockFrame or not moverDockFrame.pillButtons then return end
    for cat, pill in pairs(moverDockFrame.pillButtons) do
        if cat == activeCategory then
            pill:SetBackdropColor(0.15, 0.55, 0.95, 0.9)
            pill:SetBackdropBorderColor(0.4, 0.9, 1.0, 1.0)
            pill.text:SetTextColor(1, 1, 1)
        else
            pill:SetBackdropColor(0.15, 0.2, 0.25, 0.7)
            pill:SetBackdropBorderColor(0.3, 0.4, 0.5, 0.8)
            pill.text:SetTextColor(0.8, 0.85, 0.9)
        end
    end
end

-- =========================================================================
-- PUBLIC MOVER API
-- =========================================================================

-- Register a frame to be movable and managed
function PUIMover:Register(frame, key, friendlyName, category)
    if not frame or not key then return end
    if frame.SetMovable then
        frame:SetMovable(true)
    end
    category = string.upper(category or "UTILITY")
    if not VALID_CATEGORIES[category] then
        category = "UTILITY"
    end

    registeredFrames[key] = {
        frame = frame,
        key = key,
        name = friendlyName or key,
        category = category,
    }

    -- Hook frame:SetScale so external/module scale changes instantly resize mover overlays
    if frame.SetScale and not frame._primusMoverScaleHooked then
        frame._primusMoverScaleHooked = true
        local origSetScale = frame.SetScale
        frame.SetScale = function(thisFrame, newScale)
            origSetScale(thisFrame, newScale)
            local ov = moverOverlays[key]
            if ov then
                if ov.SetScale and ov:GetScale() ~= newScale then
                    ov:SetScale(newScale)
                end
                ov:ClearAllPoints()
                ov:SetPoint("CENTER", thisFrame, "CENTER", 0, 0)
                ov:SetWidth(thisFrame:GetWidth() or 36)
                ov:SetHeight(thisFrame:GetHeight() or 36)
            end
        end
    end

    CreateOverlay(frame, key, friendlyName, category)

    -- Restore saved position and scale if available
    self:RestorePosition(key)
    self:RestoreScale(key)
end

-- =========================================================================
-- SCALE MANAGEMENT API
-- =========================================================================

function PUIMover:GetScale(key)
    return GetFrameScale(key)
end

function PUIMover:SetScale(key, scale, silent)
    if not key or not registeredFrames[key] then return end
    local entry = registeredFrames[key]
    if not scale or scale < 0.3 then scale = 0.3 end
    if scale > 2.5 then scale = 2.5 end
    scale = Utils.Round(scale, 2)

    local scales = moverDB:Get("scales")
    if not scales then
        scales = {}
        moverDB:Set("scales", scales)
    end
    scales[key] = scale

    if entry.frame and entry.frame.SetScale then
        entry.frame:SetScale(scale)
    end

    local overlay = moverOverlays[key]
    if overlay then
        if overlay.SetScale then
            overlay:SetScale(scale)
        end
        overlay:ClearAllPoints()
        overlay:SetPoint("CENTER", entry.frame, "CENTER", 0, 0)
        overlay:SetWidth(entry.frame:GetWidth() or 36)
        overlay:SetHeight(entry.frame:GetHeight() or 36)
    end

    -- If a hotbars element was scaled, refresh dynamic matrix layout
    if string.find(key, "^PUIHotbars_") and Primus.PUIHotbars and Primus.PUIHotbars.ApplyLayout then
        Primus.PUIHotbars:ApplyLayout()
    end

    if not silent then
        UpdateDockSelectionDisplay()
    end
end

function PUIMover:ScaleSelected(delta)
    if not selectedKey then return end
    local cur = self:GetScale(selectedKey)
    local newScale = Utils.Round(cur + delta, 2)
    self:SetScale(selectedKey, newScale)
end

function PUIMover:RestoreScale(key)
    local entry = registeredFrames[key]
    if not entry or not entry.frame then return end
    local scales = moverDB and moverDB:Get("scales")
    if scales and scales[key] then
        local s = tonumber(scales[key])
        if s and s >= 0.3 and s <= 2.5 then
            self:SetScale(key, s, true)
        end
    end
end

-- Set Active Category Filter
function PUIMover:SetCategoryFilter(category)
    category = string.upper(category or "BARS")
    if category == "UTIL" then category = "UTILITY" end
    if not VALID_CATEGORIES[category] then
        category = "BARS"
    end
    activeCategory = category
    RefreshPillHighlights()

    for key, entry in pairs(registeredFrames) do
        local overlay = moverOverlays[key]
        if overlay and entry.frame then
            if entry.category == activeCategory then
                SyncOverlayToFrame(overlay, entry.frame, key)
                overlay:Show()
            else
                overlay:Hide()
            end
        end
    end
    UpdateDockSelectionDisplay()
end

-- Clamp a frame so it never extends outside UIParent viewport
function PUIMover:ClampFrameToScreen(frame)
    if not frame then return end
    if frame.SetClampedToScreen then
        frame:SetClampedToScreen(true)
    end
end

-- Refresh a specific frame or all frame mover overlays when resized dynamically
function PUIMover:UpdateFrame(frameOrKey)
    if not frameOrKey then return end
    local key = type(frameOrKey) == "string" and frameOrKey or nil
    if not key then
        for k, entry in pairs(registeredFrames) do
            if entry.frame == frameOrKey then
                key = k
                break
            end
        end
    end
    if key and registeredFrames[key] and moverOverlays[key] then
        self:ClampFrameToScreen(registeredFrames[key].frame)
        SyncOverlayToFrame(moverOverlays[key], registeredFrames[key].frame, key)
    end
end

function PUIMover:RefreshOverlays()
    for key, entry in pairs(registeredFrames) do
        local overlay = moverOverlays[key]
        if overlay and entry.frame then
            self:ClampFrameToScreen(entry.frame)
            SyncOverlayToFrame(overlay, entry.frame, key)
        end
    end
end

-- Get saved position for a specific key
function PUIMover:GetPosition(key)
    if not key then return nil end
    local pos = moverDB and moverDB:Get("positions")
    if pos and pos[key] then
        return pos[key]
    end
    return nil
end

-- Check if a frame has a user-customized position
function PUIMover:HasCustomPosition(key)
    return self:GetPosition(key) ~= nil
end

-- Restore saved position from DB
function PUIMover:RestorePosition(key)
    local entry = registeredFrames[key]
    if not entry or not entry.frame then return end

    local pos = moverDB:Get("positions")
    if pos and pos[key] then
        local p = pos[key]
        entry.frame:ClearAllPoints()
        entry.frame:SetPoint(p.point or "CENTER", UIParent, p.relativePoint or "CENTER", p.x or 0, p.y or 0)
        if entry.frame.SetUserPlaced then
            entry.frame:SetUserPlaced(true)
        end
        self:ClampFrameToScreen(entry.frame)

        local overlay = moverOverlays[key]
        if overlay then
            overlay:ClearAllPoints()
            overlay:SetPoint("CENTER", entry.frame, "CENTER", 0, 0)
            overlay:SetWidth(entry.frame:GetWidth() or 36)
            overlay:SetHeight(entry.frame:GetHeight() or 36)
        end
    end
end

-- Restore all registered frame positions and scales
function PUIMover:RestoreAll()
    for key in pairs(registeredFrames) do
        self:RestorePosition(key)
        self:RestoreScale(key)
    end
end

-- Reset all positions and scales to defaults
function PUIMover:ResetAll()
    moverDB:Set("positions", {})
    moverDB:Set("scales", {})
    for key, entry in pairs(registeredFrames) do
        if entry.frame and entry.frame.SetScale then
            entry.frame:SetScale(1.0)
        end
        local overlay = moverOverlays[key]
        if overlay and overlay.SetScale then
            overlay:SetScale(1.0)
        end
    end
    self:RefreshOverlays()
    UpdateDockSelectionDisplay()
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PrimusUI]: PUIMover positions and scales reset. Please /reload to restore defaults.", "ffbb33"))
end

-- Unlock Frames (Optionally scoped to a category)
function PUIMover:Unlock(category)
    isUnlocked = true

    -- Auto-hide Options window so user doesn't have to organize around it
    if Primus.Options and Primus.Options.Hide then
        Primus.Options:Hide()
    elseif _G.Primus_OptionsFrame and _G.Primus_OptionsFrame.Hide then
        _G.Primus_OptionsFrame:Hide()
    end

    local dock = CreateMoverDock()
    dock:Show()

    category = string.upper(category or "BARS")
    if category == "UTIL" then category = "UTILITY" end
    if not VALID_CATEGORIES[category] then category = "BARS" end

    self:SetCategoryFilter(category)
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PrimusUI]: UI Unlocked (%s). Drag overlays or use arrow nudgers.", VALID_CATEGORIES[category] or "Action Bars"), "69ccf0"))
end

PUIMover.UnlockAll = function(self)
    self:Unlock("BARS")
end

-- Lock All Frames
function PUIMover:LockAll()
    isUnlocked = false
    activeCategory = "BARS"
    selectedKey = nil

    if moverDockFrame then
        moverDockFrame:Hide()
    end
    if moverGridFrame then
        moverGridFrame:Hide()
        isGridShown = false
    end
    for _, overlay in pairs(moverOverlays) do
        overlay:Hide()
    end
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PrimusUI]: UI Locked.", "69ccf0"))
end

PUIMover.Lock = PUIMover.LockAll
PUIMover.Toggle = PUIMover.ToggleLock

-- Toggle Move Mode
function PUIMover:ToggleLock(category)
    if isUnlocked then
        category = string.upper(category or "BARS")
        if category == "UTIL" then category = "UTILITY" end
        if category and category ~= activeCategory and VALID_CATEGORIES[category] then
            self:SetCategoryFilter(category)
        else
            self:LockAll()
        end
    else
        self:Unlock(category or "BARS")
    end
end

function PUIMover:IsUnlocked()
    return isUnlocked
end

function PUIMover:GetActiveCategory()
    return activeCategory
end

function PUIMover:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIMover", {
        name = "PUIMover",
        category = "Utility",
        label = "UI Mover & Grid",
        options = {
            {
                key = "unlockUI",
                type = "button",
                label = "Unlock UI Frames",
                desc = "Open floating mover dock and drag handles for all frames.",
                buttonText = "Unlock All",
                onClick = function()
                    if Primus.Options and Primus.Options.Hide then
                        Primus.Options:Hide()
                    end
                    PUIMover:UnlockAll()
                end,
            },
            {
                key = "toggleGrid",
                type = "button",
                label = "Toggle Alignment Grid",
                desc = "Toggle fullscreen magnetic alignment grid.",
                buttonText = "Toggle Grid",
                onClick = function()
                    PUIMover:ToggleGrid()
                end,
            },
            {
                key = "resetPositions",
                type = "button",
                label = "Reset Frame Positions",
                desc = "Reset all frame positions back to default layout coordinates.",
                buttonText = "Reset All",
                onClick = function()
                    PUIMover:ResetAll()
                end,
            },
        },
    })
end

function PUIMover:OnInitialize()
    self:RegisterOptionsFlare()

    -- Auto-restore positions on login
    Events:Register("PLAYER_ENTERING_WORLD", self, function()
        PUIMover:RestoreAll()
    end)

    -- Register console sub-commands
    if Primus.Console and Primus.Console.RegisterSubCommand then
        Primus.Console:RegisterSubCommand("move", function(msg)
            local sub = msg and Utils.Trim(msg) or ""
            if sub == "lock" then
                PUIMover:LockAll()
            elseif sub == "reset" then
                PUIMover:ResetAll()
            elseif sub ~= "" then
                PUIMover:Unlock(sub)
            else
                PUIMover:ToggleLock("BARS")
            end
        end, "Categorized UI mover (/pui move [category])")

        Primus.Console:RegisterSubCommand("unlock", function(msg)
            local sub = msg and Utils.Trim(msg) or "BARS"
            PUIMover:Unlock(sub)
        end, "Unlock UI frames for dragging (/pui unlock [category])")

        Primus.Console:RegisterSubCommand("lock", function()
            PUIMover:LockAll()
        end, "Lock all UI frames (/pui lock)")
    end
end

function PUIMover:OnEnable()
    self:RestoreAll()
end

function PUIMover:OnDisable()
    self:LockAll()
end

