--[[
    PrimusUI Module: PUIHotbars (Master Action Bar Virtualization & 120-Slot Paging Engine)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Features:
    1. 120-Slot Shared Action Pool & Dynamic Paging Tunnels:
       - Eliminates duplicate frame stacking (e.g. BonusActionBarFrame on top of MainMenuBar).
       - Evaluates stances, stealth, modifiers, and pages to dynamically route button slot IDs.
    2. Dynamic Matrix Layout Engine:
       - Independent Rows (1..12) and Columns (1..12) sliders for Bars 1-5, Stance Bar, and Pet Bar.
    3. Decoupled Independent Anchors:
       - Eliminates cascading anchor collapses across Bars 1-5, Stance, and Pet bars.
    4. Blizzard FrameXML MultiActionBar Neutralization:
       - Prevents default UI from force-hiding enabled bars.
    5. Integrated Multi-Faction Reputation Watchbar & Options Flare Hub.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIHotbars = Primus.PUIHotbars or {}
Primus.PUIHotbars = PUIHotbars
_G.PUIHotbars = PUIHotbars
Primus:RegisterModule("PUIHotbars", PUIHotbars, "Bars")

local DB       = Primus.DB
local Widgets  = Primus.Widgets
local Media    = Primus.Media
local Utils    = Primus.Utils
local Events   = Primus.Events
local Time     = Primus.Time
local PUIMover = Primus.PUIMover

-- =========================================================================
-- DATABASE NAMESPACE REGISTRATION
-- =========================================================================

local hotbarsDB = DB:RegisterNamespace("PUIHotbars", {
    enabled = true,
    buttonSize = 36,
    buttonSpacing = 4,

    -- Explicit Bar Toggles
    showBar1 = true,
    showBar2 = true,
    showBar3 = true,
    showBar4 = true,
    showBar5 = false,
    showStance = true,
    showPet = true,
    showMicro = true,
    showBags = true,
    singleBag = false,
    showKeyring = true,
    showXPBar = true,

    -- Dynamic Matrix Rows & Columns
    bar1Rows = 1,  bar1Cols = 12,
    bar2Rows = 1,  bar2Cols = 12,
    bar3Rows = 1,  bar3Cols = 12,
    bar4Rows = 12, bar4Cols = 1,
    bar5Rows = 12, bar5Cols = 1,
    stanceRows = 1, stanceCols = 10,
    petRows = 1,   petCols = 10,

    -- Visual Features
    rangeTint = true,
    manaTint = true,
    macroNames = false,
    hotkeys = true,

    -- Multi-Faction Reputation Watchbar
    trackedFactions   = {},          -- [factionName] = true
    activeFaction     = nil,         -- Active faction for Cycle/Split mode
    repDisplayMode    = "STACKED",   -- "STACKED" | "CYCLE" | "SPLIT"
    maxStackedBars    = 2,           -- 1 .. 4
    repBarHeight      = 8,
    xpHeight          = 8,
    repSpacing        = 2,
    autoSwitchOnGain  = true,
    forceShowXP       = false,       -- Show XP bar even at Level 60
    textDisplayMode   = "VERBOSE",   -- "VERBOSE" | "PERCENT" | "VALUES" | "HOVER_ONLY"
})

-- Frame Anchors (Independent Decoupled Anchors on UIParent)
local bar1Anchor   = nil
local bar2Anchor   = nil
local bar3Anchor   = nil
local bar4Anchor   = nil
local bar5Anchor   = nil
local stanceAnchor = nil
local petAnchor    = nil

local isApplyingLayout = false

-- =========================================================================
-- 120-SLOT PAGING TUNNEL RESOLVER
-- =========================================================================

function PUIHotbars:ResolveActivePage(barIndex)
    if barIndex == 1 then
        local bonusOffset = GetBonusBarOffset()
        if bonusOffset and bonusOffset > 0 then
            -- Maps Stances (Warrior Battle/Def/Berserker, Druid Bear/Cat/Prowl, Rogue Stealth)
            -- to Pages 7, 8, 9 (Slots 73..108)
            return 6 + bonusOffset
        end
        local curPage = CURRENT_ACTIONBAR_PAGE or 1
        return curPage
    elseif barIndex == 2 then
        return 2 -- Slots 13..24 (Secondary Action Bar / MultiBarBottomLeft)
    elseif barIndex == 3 then
        return 5 -- Slots 49..60 (MultiBarBottomRight)
    elseif barIndex == 4 then
        return 3 -- Slots 25..36 (MultiBarRight)
    elseif barIndex == 5 then
        return 4 -- Slots 37..48 (MultiBarLeft)
    end
    return barIndex
end

function PUIHotbars:GetButtonActionID(barIndex, buttonIndex)
    local activePage = self:ResolveActivePage(barIndex)
    return (activePage - 1) * 12 + buttonIndex
end

-- =========================================================================
-- MASTER BLIZZARD ARTWORK SUPPRESSION
-- =========================================================================

local function StripBlizzardArt()
    local texList = {
        "MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3",
        "MainMenuMaxLevelBar0", "MainMenuMaxLevelBar1", "MainMenuMaxLevelBar2", "MainMenuMaxLevelBar3",
        "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
        "ShapeshiftBarLeft", "ShapeshiftBarMiddle", "ShapeshiftBarRight",
        "SlidingActionBarTexture0", "SlidingActionBarTexture1",
        "PetActionBarFrameSlidingActionBarTexture0", "PetActionBarFrameSlidingActionBarTexture1",
        "BonusActionBarTexture0", "BonusActionBarTexture1",
    }

    local tCount = table.getn(texList)
    for i = 1, tCount do
        local tex = _G[texList[i]]
        if tex then
            if type(tex.SetTexture) == "function" then tex:SetTexture("") end
            if type(tex.SetAlpha) == "function" then tex:SetAlpha(0) end
            if type(tex.Hide) == "function" then tex:Hide() end
        end
    end

    if MainMenuBarArtFrame then
        MainMenuBarArtFrame:Show()
        MainMenuBarArtFrame:SetAlpha(1)
        if MainMenuBarArtFrame.EnableMouse then MainMenuBarArtFrame:EnableMouse(false) end
    end

    if MainMenuBarOverlayFrame then
        MainMenuBarOverlayFrame:Hide()
        MainMenuBarOverlayFrame:SetAlpha(0)
        if MainMenuBarOverlayFrame.EnableMouse then MainMenuBarOverlayFrame:EnableMouse(false) end
    end

    if MainMenuExpBar then MainMenuExpBar:Hide(); MainMenuExpBar:SetAlpha(0) end
    if ReputationWatchBar then ReputationWatchBar:Hide(); ReputationWatchBar:SetAlpha(0) end
    if ActionBarUpButton then ActionBarUpButton:Hide() end
    if ActionBarDownButton then ActionBarDownButton:Hide() end
    if MainMenuBarPageNumber then MainMenuBarPageNumber:Hide() end
    if MainMenuBarPerformanceBarFrame then MainMenuBarPerformanceBarFrame:Hide() end
end

-- =========================================================================
-- DYNAMIC MATRIX GRID LAYOUT HELPER
-- =========================================================================

function PUIHotbars:LayoutMatrix(container, frameWrapper, buttonPrefix, numButtons, cols, rows, size, spacing)
    cols = math.max(1, math.min(numButtons, cols or numButtons))
    rows = math.max(1, math.min(numButtons, rows or 1))

    local totalW = cols * size + (cols - 1) * spacing
    local totalH = rows * size + (rows - 1) * spacing

    container:SetWidth(totalW)
    container:SetHeight(totalH)

    if frameWrapper then
        if frameWrapper.SetParent then
            frameWrapper:SetParent(container)
        end
        frameWrapper:ClearAllPoints()
        frameWrapper:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        frameWrapper:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
        frameWrapper:SetWidth(totalW)
        frameWrapper:SetHeight(totalH)
    end

    for i = 1, numButtons do
        local btn = _G[buttonPrefix .. i]
        if btn then
            self:StyleButton(btn, size)
            btn:ClearAllPoints()
            local colIdx = Utils.Mod(i - 1, cols)
            local rowIdx = math.floor((i - 1) / cols)
            local xOffset = colIdx * (size + spacing)
            local yOffset = -rowIdx * (size + spacing)
            btn:SetPoint("TOPLEFT", frameWrapper or container, "TOPLEFT", xOffset, yOffset)

            btn.showgrid = 1
            if (string.find(buttonPrefix, "^ActionButton") or string.find(buttonPrefix, "^MultiBar")) and ActionButton_ShowGrid then
                ActionButton_ShowGrid(btn)
            end
            btn:Show()
        end
    end
end

-- =========================================================================
-- MASTER ACTION BAR LAYOUT & ALIGNMENT
-- =========================================================================

function PUIHotbars:ApplyLayout()
    if not hotbarsDB:Get("enabled", true) or isApplyingLayout then return end
    isApplyingLayout = true

    local size    = hotbarsDB:Get("buttonSize", 36)
    local spacing = hotbarsDB:Get("buttonSpacing", 4)

    -- Synchronize Blizzard FrameXML multi-action bar state variables
    SHOW_MULTI_ACTIONBAR_1 = hotbarsDB:Get("showBar2", true) and 1 or nil
    SHOW_MULTI_ACTIONBAR_2 = hotbarsDB:Get("showBar3", true) and 1 or nil
    SHOW_MULTI_ACTIONBAR_3 = hotbarsDB:Get("showBar4", true) and 1 or nil
    SHOW_MULTI_ACTIONBAR_4 = hotbarsDB:Get("showBar5", false) and 1 or nil
    ALWAYS_SHOW_MULTIBARS  = 1

    -- 1. Integrated XP & Multi-Faction Watchbar
    self:BuildXPBar()
    if self.xpBarFrame then
        local bar1Cols = hotbarsDB:Get("bar1Cols", 12)
        local xpW = bar1Cols * size + (bar1Cols - 1) * spacing
        self.xpBarFrame:SetWidth(xpW)
        if hotbarsDB:Get("showXPBar", true) then 
            self.xpBarFrame:Show() 
        else 
            self.xpBarFrame:Hide() 
        end
    end

    -- 2. Bar 1 Anchor & MainMenuBar
    local b1Cols = hotbarsDB:Get("bar1Cols", 12)
    local b1Rows = hotbarsDB:Get("bar1Rows", 1)
    if not bar1Anchor then
        bar1Anchor = CreateFrame("Frame", "Primus_PUIHotbars_Bar1", UIParent)
        bar1Anchor:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 18)
        local mover = PUIMover or Primus.PUIMover
        if mover and mover.Register then
            mover:Register(bar1Anchor, "PUIHotbars_Bar1", "PUIHotbars: Main Bar", "BARS")
        end
    end

    self:LayoutMatrix(bar1Anchor, MainMenuBar, "ActionButton", 12, b1Cols, b1Rows, size, spacing)
    if hotbarsDB:Get("showBar1", true) then
        bar1Anchor:Show()
        if MainMenuBar then MainMenuBar:Show() end
    else
        bar1Anchor:Hide()
        if MainMenuBar then MainMenuBar:Hide() end
    end

    if BonusActionBarFrame then
        BonusActionBarFrame:ClearAllPoints()
        BonusActionBarFrame:SetPoint("TOPLEFT", bar1Anchor, "TOPLEFT", 0, 0)
        BonusActionBarFrame:SetPoint("BOTTOMRIGHT", bar1Anchor, "BOTTOMRIGHT", 0, 0)
        for i = 1, 12 do
            local bBtn = _G["BonusActionButton" .. i]
            if bBtn then
                self:StyleButton(bBtn, size)
                bBtn:ClearAllPoints()
                local colIdx = Utils.Mod(i - 1, b1Cols)
                local rowIdx = math.floor((i - 1) / b1Cols)
                bBtn:SetPoint("TOPLEFT", BonusActionBarFrame, "TOPLEFT", colIdx * (size + spacing), -rowIdx * (size + spacing))
                if not (BonusActionBarFrame:IsShown()) then
                    bBtn:Hide()
                end
            end
        end
    end

    -- 3. Bar 2 (MultiBarBottomLeft) - Decoupled Independent Anchor
    local b2Cols = hotbarsDB:Get("bar2Cols", 12)
    local b2Rows = hotbarsDB:Get("bar2Rows", 1)
    if not bar2Anchor then
        bar2Anchor = CreateFrame("Frame", "Primus_PUIHotbars_Bar2", UIParent)
        bar2Anchor:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 58)
        local mover = PUIMover or Primus.PUIMover
        if mover and mover.Register then
            mover:Register(bar2Anchor, "PUIHotbars_Bar2", "PUIHotbars: Secondary Bar", "BARS")
        end
    end

    self:LayoutMatrix(bar2Anchor, MultiBarBottomLeft, "MultiBarBottomLeftButton", 12, b2Cols, b2Rows, size, spacing)
    if hotbarsDB:Get("showBar2", true) then
        if MultiBarBottomLeft then MultiBarBottomLeft:Show() end
        bar2Anchor:Show()
    else
        if MultiBarBottomLeft then MultiBarBottomLeft:Hide() end
        bar2Anchor:Hide()
    end

    -- 4. Bar 3 (MultiBarBottomRight) - Decoupled Independent Anchor
    local b3Cols = hotbarsDB:Get("bar3Cols", 12)
    local b3Rows = hotbarsDB:Get("bar3Rows", 1)
    if not bar3Anchor then
        bar3Anchor = CreateFrame("Frame", "Primus_PUIHotbars_Bar3", UIParent)
        bar3Anchor:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 98)
        local mover = PUIMover or Primus.PUIMover
        if mover and mover.Register then
            mover:Register(bar3Anchor, "PUIHotbars_Bar3", "PUIHotbars: Third Bar", "BARS")
        end
    end

    self:LayoutMatrix(bar3Anchor, MultiBarBottomRight, "MultiBarBottomRightButton", 12, b3Cols, b3Rows, size, spacing)
    if hotbarsDB:Get("showBar3", true) then
        if MultiBarBottomRight then MultiBarBottomRight:Show() end
        bar3Anchor:Show()
    else
        if MultiBarBottomRight then MultiBarBottomRight:Hide() end
        bar3Anchor:Hide()
    end

    -- 5. Bar 4 (MultiBarRight) - Decoupled Independent Anchor
    local b4Cols = hotbarsDB:Get("bar4Cols", 1)
    local b4Rows = hotbarsDB:Get("bar4Rows", 12)
    if not bar4Anchor then
        bar4Anchor = CreateFrame("Frame", "Primus_PUIHotbars_Bar4", UIParent)
        bar4Anchor:SetPoint("RIGHT", UIParent, "RIGHT", -6, 0)
        local mover = PUIMover or Primus.PUIMover
        if mover and mover.Register then
            mover:Register(bar4Anchor, "PUIHotbars_Bar4", "PUIHotbars: Right Bar 1", "BARS")
        end
    end

    self:LayoutMatrix(bar4Anchor, MultiBarRight, "MultiBarRightButton", 12, b4Cols, b4Rows, size, spacing)
    if hotbarsDB:Get("showBar4", true) then
        if MultiBarRight then MultiBarRight:Show() end
        bar4Anchor:Show()
    else
        if MultiBarRight then MultiBarRight:Hide() end
        bar4Anchor:Hide()
    end

    -- 6. Bar 5 (MultiBarLeft) - Decoupled Independent Anchor
    local b5Cols = hotbarsDB:Get("bar5Cols", 1)
    local b5Rows = hotbarsDB:Get("bar5Rows", 12)
    if not bar5Anchor then
        bar5Anchor = CreateFrame("Frame", "Primus_PUIHotbars_Bar5", UIParent)
        bar5Anchor:SetPoint("RIGHT", UIParent, "RIGHT", -46, 0)
        local mover = PUIMover or Primus.PUIMover
        if mover and mover.Register then
            mover:Register(bar5Anchor, "PUIHotbars_Bar5", "PUIHotbars: Right Bar 2", "BARS")
        end
    end

    self:LayoutMatrix(bar5Anchor, MultiBarLeft, "MultiBarLeftButton", 12, b5Cols, b5Rows, size, spacing)
    if hotbarsDB:Get("showBar5", false) then
        if MultiBarLeft then MultiBarLeft:Show() end
        bar5Anchor:Show()
    else
        if MultiBarLeft then MultiBarLeft:Hide() end
        bar5Anchor:Hide()
    end

    -- 7. Stance Bar - Decoupled Independent Anchor
    local stanceSize = math.floor(size * 0.85)
    local numForms = GetNumShapeshiftForms() or 0
    local stCols = hotbarsDB:Get("stanceCols", 10)
    local stRows = hotbarsDB:Get("stanceRows", 1)

    if not stanceAnchor then
        stanceAnchor = CreateFrame("Frame", "Primus_PUIHotbars_StanceBar", UIParent)
        stanceAnchor:SetPoint("BOTTOM", UIParent, "BOTTOM", -140, 138)
        stanceAnchor:SetFrameStrata("MEDIUM")
        local mover = PUIMover or Primus.PUIMover
        if mover and mover.Register then
            mover:Register(stanceAnchor, "PUIHotbars_Stance", "PUIHotbars: Stance / Shapeshift Bar", "BARS")
        end
    end

    if ShapeshiftBarFrame then
        ShapeshiftBarFrame:SetParent(UIParent)
        ShapeshiftBarFrame:SetFrameStrata("MEDIUM")
        ShapeshiftBarFrame:SetFrameLevel(stanceAnchor:GetFrameLevel() + 1)
        ShapeshiftBarFrame:ClearAllPoints()
        ShapeshiftBarFrame:SetPoint("TOPLEFT", stanceAnchor, "TOPLEFT", 0, 0)

        local totalW = stCols * stanceSize + (stCols - 1) * spacing
        local totalH = stRows * stanceSize + (stRows - 1) * spacing
        stanceAnchor:SetWidth(totalW)
        stanceAnchor:SetHeight(totalH)
        ShapeshiftBarFrame:SetWidth(totalW)
        ShapeshiftBarFrame:SetHeight(totalH)

        for i = 1, 10 do
            local btn = _G["ShapeshiftButton" .. i]
            if btn then
                self:StyleButton(btn, stanceSize)
                btn:ClearAllPoints()
                local colIdx = Utils.Mod(i - 1, stCols)
                local rowIdx = math.floor((i - 1) / stCols)
                local xOffset = colIdx * (stanceSize + spacing)
                local yOffset = -rowIdx * (stanceSize + spacing)
                btn:SetPoint("TOPLEFT", stanceAnchor, "TOPLEFT", xOffset, yOffset)
                btn:SetFrameStrata("MEDIUM")
                btn:SetFrameLevel(ShapeshiftBarFrame:GetFrameLevel() + 2)

                if i <= numForms and hotbarsDB:Get("showStance", true) then
                    btn:Show()
                else
                    btn:Hide()
                end
            end
        end

        if numForms > 0 and hotbarsDB:Get("showStance", true) then
            ShapeshiftBarFrame:Show()
            stanceAnchor:Show()
        else
            ShapeshiftBarFrame:Hide()
            stanceAnchor:Hide()
        end
    end

    -- 8. Pet Bar - Decoupled Independent Anchor
    local petSize = math.floor(size * 0.85)
    local petCols = hotbarsDB:Get("petCols", 10)
    local petRows = hotbarsDB:Get("petRows", 1)

    if not petAnchor then
        petAnchor = CreateFrame("Frame", "Primus_PUIHotbars_PetBar", UIParent)
        petAnchor:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 138)
        petAnchor:SetFrameStrata("MEDIUM")
        local mover = PUIMover or Primus.PUIMover
        if mover and mover.Register then
            mover:Register(petAnchor, "PUIHotbars_Pet", "PUIHotbars: Pet Bar", "BARS")
        end
    end

    if PetActionBarFrame then
        PetActionBarFrame:SetParent(UIParent)
        PetActionBarFrame:SetFrameStrata("MEDIUM")
        PetActionBarFrame:SetFrameLevel(petAnchor:GetFrameLevel() + 1)
        PetActionBarFrame:ClearAllPoints()
        PetActionBarFrame:SetPoint("TOPLEFT", petAnchor, "TOPLEFT", 0, 0)
        
        local totalW = petCols * petSize + (petCols - 1) * spacing
        local totalH = petRows * petSize + (petRows - 1) * spacing
        petAnchor:SetWidth(totalW)
        petAnchor:SetHeight(totalH)
        PetActionBarFrame:SetWidth(totalW)
        PetActionBarFrame:SetHeight(totalH)

        for i = 1, 10 do
            local btn = _G["PetActionButton" .. i]
            if btn then
                self:StyleButton(btn, petSize)
                btn:ClearAllPoints()
                local colIdx = Utils.Mod(i - 1, petCols)
                local rowIdx = math.floor((i - 1) / petCols)
                local xOffset = colIdx * (petSize + spacing)
                local yOffset = -rowIdx * (petSize + spacing)
                btn:SetPoint("TOPLEFT", petAnchor, "TOPLEFT", xOffset, yOffset)
                btn:SetFrameStrata("MEDIUM")
                btn:SetFrameLevel(PetActionBarFrame:GetFrameLevel() + 2)

                if (PetHasActionBar() or UnitExists("pet")) and hotbarsDB:Get("showPet", true) then
                    btn:Show()
                else
                    btn:Hide()
                end
            end
        end

        if (PetHasActionBar() or UnitExists("pet")) and hotbarsDB:Get("showPet", true) then
            PetActionBarFrame:Show()
            petAnchor:Show()
        else
            PetActionBarFrame:Hide()
            petAnchor:Hide()
        end
    end

    -- 9. Micro Menu & Bag Bar
    self:BuildMicroBar()
    self:BuildBagBar()

    -- 10. Strip Blizzard Art & Update Multi-Faction Watchbar
    StripBlizzardArt()
    self:UpdateXP()

    if ShapeshiftBar_Update then ShapeshiftBar_Update() end
    if PetActionBar_Update then PetActionBar_Update() end

    -- Real-time update of PUIMover drag overlays so they reshape immediately
    local mover = PUIMover or Primus.PUIMover
    if mover and mover.UpdateFrame then
        mover:UpdateFrame("PUIHotbars_Bar1")
        mover:UpdateFrame("PUIHotbars_Bar2")
        mover:UpdateFrame("PUIHotbars_Bar3")
        mover:UpdateFrame("PUIHotbars_Bar4")
        mover:UpdateFrame("PUIHotbars_Bar5")
        mover:UpdateFrame("PUIHotbars_Stance")
        mover:UpdateFrame("PUIHotbars_Pet")
        mover:UpdateFrame("PUIHotbars_XP")
        mover:UpdateFrame("PUIHotbars_Micro")
        mover:UpdateFrame("PUIHotbars_Bags")
    end

    isApplyingLayout = false
end

-- =========================================================================
-- MASTER OPTIONS FLARE & CONFIGURATION GUI
-- =========================================================================

local function BuildHotbarsOptionsPanel(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetWidth(500)
    p:SetHeight(520)

    local title = p:CreateFontString(nil, "OVERLAY")
    title:SetFont(Media:Fetch("font", "Default"), 11, "OUTLINE")
    title:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -10)
    title:SetText(Utils.ColorText("Action Bars & Multi-Faction Watch (/pui hotbars)", "ffd100"))

    -- =====================================================================
    -- LEFT COLUMN: ACTION BAR VISIBILITY TOGGLES
    -- =====================================================================
    local barSecTitle = p:CreateFontString(nil, "OVERLAY")
    barSecTitle:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    barSecTitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    barSecTitle:SetText(Utils.ColorText("Bar Visibility & Display", "69ccf0"))

    local cbBar1 = Widgets:CreateCheckButton(p, "Show Action Bar 1 (Main)", hotbarsDB:Get("showBar1", true), function(checked)
        hotbarsDB:Set("showBar1", checked)
        PUIHotbars:ApplyLayout()
    end)
    cbBar1:SetPoint("TOPLEFT", barSecTitle, "BOTTOMLEFT", 0, -6)

    local cbBar2 = Widgets:CreateCheckButton(p, "Show Action Bar 2 (Bottom Left)", hotbarsDB:Get("showBar2", true), function(checked)
        hotbarsDB:Set("showBar2", checked)
        PUIHotbars:ApplyLayout()
    end)
    cbBar2:SetPoint("TOPLEFT", cbBar1, "BOTTOMLEFT", 0, -4)

    local cbBar3 = Widgets:CreateCheckButton(p, "Show Action Bar 3 (Bottom Right)", hotbarsDB:Get("showBar3", true), function(checked)
        hotbarsDB:Set("showBar3", checked)
        PUIHotbars:ApplyLayout()
    end)
    cbBar3:SetPoint("TOPLEFT", cbBar2, "BOTTOMLEFT", 0, -4)

    local cbBar4 = Widgets:CreateCheckButton(p, "Show Action Bar 4 (Right Bar 1)", hotbarsDB:Get("showBar4", true), function(checked)
        hotbarsDB:Set("showBar4", checked)
        PUIHotbars:ApplyLayout()
    end)
    cbBar4:SetPoint("TOPLEFT", cbBar3, "BOTTOMLEFT", 0, -4)

    local cbBar5 = Widgets:CreateCheckButton(p, "Show Action Bar 5 (Right Bar 2)", hotbarsDB:Get("showBar5", false), function(checked)
        hotbarsDB:Set("showBar5", checked)
        PUIHotbars:ApplyLayout()
    end)
    cbBar5:SetPoint("TOPLEFT", cbBar4, "BOTTOMLEFT", 0, -4)

    local cbStance = Widgets:CreateCheckButton(p, "Show Stance / Form Bar", hotbarsDB:Get("showStance", true), function(checked)
        hotbarsDB:Set("showStance", checked)
        PUIHotbars:ApplyLayout()
    end)
    cbStance:SetPoint("TOPLEFT", cbBar5, "BOTTOMLEFT", 0, -4)

    local cbPet = Widgets:CreateCheckButton(p, "Show Pet Action Bar", hotbarsDB:Get("showPet", true), function(checked)
        hotbarsDB:Set("showPet", checked)
        PUIHotbars:ApplyLayout()
    end)
    cbPet:SetPoint("TOPLEFT", cbStance, "BOTTOMLEFT", 0, -4)

    local cbXP = Widgets:CreateCheckButton(p, "Show XP & Faction Watchbar", hotbarsDB:Get("showXPBar", true), function(checked)
        hotbarsDB:Set("showXPBar", checked)
        PUIHotbars:ApplyLayout()
    end)
    cbXP:SetPoint("TOPLEFT", cbPet, "BOTTOMLEFT", 0, -4)

    local cbMicro = Widgets:CreateCheckButton(p, "Show Micro Menu Bar", hotbarsDB:Get("showMicro", true), function(checked)
        hotbarsDB:Set("showMicro", checked)
        PUIHotbars:ApplyLayout()
    end)
    cbMicro:SetPoint("TOPLEFT", cbXP, "BOTTOMLEFT", 0, -4)

    local cbBags = Widgets:CreateCheckButton(p, "Show Bag & Keyring Bar", hotbarsDB:Get("showBags", true), function(checked)
        hotbarsDB:Set("showBags", checked)
        PUIHotbars:ApplyLayout()
    end)
    cbBags:SetPoint("TOPLEFT", cbMicro, "BOTTOMLEFT", 0, -4)

    local cbSingleBag = Widgets:CreateCheckButton(p, "Single Bag Mode (Backpack Only)", hotbarsDB:Get("singleBag", false), function(checked)
        hotbarsDB:Set("singleBag", checked)
        PUIHotbars:ApplyLayout()
    end)
    cbSingleBag:SetPoint("TOPLEFT", cbBags, "BOTTOMLEFT", 14, -2)

    local cbKeyring = Widgets:CreateCheckButton(p, "Show Keyring in Single Bag Mode", hotbarsDB:Get("showKeyring", true), function(checked)
        hotbarsDB:Set("showKeyring", checked)
        PUIHotbars:ApplyLayout()
    end)
    cbKeyring:SetPoint("TOPLEFT", cbSingleBag, "BOTTOMLEFT", 0, -2)

    -- Sizing & Tints
    local sSize = Widgets:CreateSlider(p, "Button Size", 24, 48, 2, hotbarsDB:Get("buttonSize", 36), function(val)
        hotbarsDB:Set("buttonSize", val)
        PUIHotbars:ApplyLayout()
    end)
    sSize:SetPoint("TOPLEFT", cbKeyring, "BOTTOMLEFT", -14, -12)

    local sSpacing = Widgets:CreateSlider(p, "Button Spacing", 0, 10, 1, hotbarsDB:Get("buttonSpacing", 4), function(val)
        hotbarsDB:Set("buttonSpacing", val)
        PUIHotbars:ApplyLayout()
    end)
    sSpacing:SetPoint("TOPLEFT", sSize, "BOTTOMLEFT", 0, -12)

    local cbRange = Widgets:CreateCheckButton(p, "Out-of-Range Red Icon Tinting", hotbarsDB:Get("rangeTint", true), function(checked)
        hotbarsDB:Set("rangeTint", checked)
    end)
    cbRange:SetPoint("TOPLEFT", sSpacing, "BOTTOMLEFT", 0, -8)

    local cbMana = Widgets:CreateCheckButton(p, "Out-of-Mana Blue Icon Tinting", hotbarsDB:Get("manaTint", true), function(checked)
        hotbarsDB:Set("manaTint", checked)
    end)
    cbMana:SetPoint("TOPLEFT", cbRange, "BOTTOMLEFT", 0, -4)

    -- =====================================================================
    -- RIGHT COLUMN: DYNAMIC MATRIX (ROWS X COLS)
    -- =====================================================================
    local matrixTitle = p:CreateFontString(nil, "OVERLAY")
    matrixTitle:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    matrixTitle:SetPoint("TOPLEFT", p, "TOPLEFT", 250, -34)
    matrixTitle:SetText(Utils.ColorText("Dynamic Matrix (Columns 1..12)", "69ccf0"))

    local sB1Cols = Widgets:CreateSlider(p, "Bar 1 Columns", 1, 12, 1, hotbarsDB:Get("bar1Cols", 12), function(val)
        hotbarsDB:Set("bar1Cols", val)
        hotbarsDB:Set("bar1Rows", math.ceil(12 / val))
        PUIHotbars:ApplyLayout()
    end)
    sB1Cols:SetPoint("TOPLEFT", matrixTitle, "BOTTOMLEFT", 0, -8)

    local sB2Cols = Widgets:CreateSlider(p, "Bar 2 Columns", 1, 12, 1, hotbarsDB:Get("bar2Cols", 12), function(val)
        hotbarsDB:Set("bar2Cols", val)
        hotbarsDB:Set("bar2Rows", math.ceil(12 / val))
        PUIHotbars:ApplyLayout()
    end)
    sB2Cols:SetPoint("TOPLEFT", sB1Cols, "BOTTOMLEFT", 0, -10)

    local sB3Cols = Widgets:CreateSlider(p, "Bar 3 Columns", 1, 12, 1, hotbarsDB:Get("bar3Cols", 12), function(val)
        hotbarsDB:Set("bar3Cols", val)
        hotbarsDB:Set("bar3Rows", math.ceil(12 / val))
        PUIHotbars:ApplyLayout()
    end)
    sB3Cols:SetPoint("TOPLEFT", sB2Cols, "BOTTOMLEFT", 0, -10)

    local sB4Cols = Widgets:CreateSlider(p, "Bar 4 Columns", 1, 12, 1, hotbarsDB:Get("bar4Cols", 1), function(val)
        hotbarsDB:Set("bar4Cols", val)
        hotbarsDB:Set("bar4Rows", math.ceil(12 / val))
        PUIHotbars:ApplyLayout()
    end)
    sB4Cols:SetPoint("TOPLEFT", sB3Cols, "BOTTOMLEFT", 0, -10)

    local sB5Cols = Widgets:CreateSlider(p, "Bar 5 Columns", 1, 12, 1, hotbarsDB:Get("bar5Cols", 1), function(val)
        hotbarsDB:Set("bar5Cols", val)
        hotbarsDB:Set("bar5Rows", math.ceil(12 / val))
        PUIHotbars:ApplyLayout()
    end)
    sB5Cols:SetPoint("TOPLEFT", sB4Cols, "BOTTOMLEFT", 0, -10)

    -- =====================================================================
    -- MULTI-FACTION WATCHBAR SETTINGS
    -- =====================================================================
    local repSecTitle = p:CreateFontString(nil, "OVERLAY")
    repSecTitle:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    repSecTitle:SetPoint("TOPLEFT", sB5Cols, "BOTTOMLEFT", 0, -14)
    repSecTitle:SetText(Utils.ColorText("XP & Reputation Watch Options", "ffd100"))

    local cbAutoGain = Widgets:CreateCheckButton(p, "Auto-Focus on Rep Gain", hotbarsDB:Get("autoSwitchOnGain", true), function(checked)
        hotbarsDB:Set("autoSwitchOnGain", checked)
    end)
    cbAutoGain:SetPoint("TOPLEFT", repSecTitle, "BOTTOMLEFT", 0, -6)

    local cbForceXP = Widgets:CreateCheckButton(p, "Force Show XP at Level 60", hotbarsDB:Get("forceShowXP", false), function(checked)
        hotbarsDB:Set("forceShowXP", checked)
        PUIHotbars:UpdateXP()
    end)
    cbForceXP:SetPoint("TOPLEFT", cbAutoGain, "BOTTOMLEFT", 0, -4)

    local sMaxRep = Widgets:CreateSlider(p, "Max Stacked Faction Bars", 1, 4, 1, hotbarsDB:Get("maxStackedBars", 2), function(val)
        hotbarsDB:Set("maxStackedBars", val)
        PUIHotbars:UpdateXP()
    end)
    sMaxRep:SetPoint("TOPLEFT", cbForceXP, "BOTTOMLEFT", 0, -10)

    return p
end

-- =========================================================================
-- MODULE LIFECYCLE & INITIALIZATION
-- =========================================================================

function PUIHotbars:OnInitialize()
    ALWAYS_SHOW_MULTIBARS = 1
    if SetActionButtonsShowGrid then
        SetActionButtonsShowGrid(1)
    end

    -- Hook ActionButton_GetPagedID safely for seamless 120-slot stance paging
    local orig_ActionButton_GetPagedID = ActionButton_GetPagedID
    ActionButton_GetPagedID = function(button)
        if button and button:GetID() then
            local slot = button:GetID()
            local parent = button:GetParent()
            local parentName = parent and parent:GetName()
            if parentName == "MainMenuBar" or parentName == "MainMenuBarArtFrame" or parentName == "BonusActionBarFrame" then
                return PUIHotbars:GetButtonActionID(1, slot)
            end
        end
        if orig_ActionButton_GetPagedID then
            return orig_ActionButton_GetPagedID(button)
        end
        return button and button:GetID() or 1
    end

    -- Hook ActionButton_ShowGrid to safeguard against missing NormalTextures
    if ActionButton_ShowGrid then
        local orig_ActionButton_ShowGrid = ActionButton_ShowGrid
        ActionButton_ShowGrid = function(button)
            if not button then button = this end
            if not button then return end
            button.showgrid = (button.showgrid or 0) + 1
            local norm = _G[button:GetName() .. "NormalTexture"] or (button.GetNormalTexture and button:GetNormalTexture())
            if norm and type(norm.SetVertexColor) == "function" then
                norm:SetVertexColor(1.0, 1.0, 1.0, 0.4)
            end
            button:Show()
        end
    end

    -- Hook ActionButton_HideGrid for safe grid toggles
    if ActionButton_HideGrid then
        local orig_ActionButton_HideGrid = ActionButton_HideGrid
        ActionButton_HideGrid = function(button)
            if not button then button = this end
            if not button then return end
            button.showgrid = math.max(0, (button.showgrid or 1) - 1)
            local pagedID = ActionButton_GetPagedID and ActionButton_GetPagedID(button) or button:GetID() or 1
            if button.showgrid == 0 and not HasAction(pagedID) then
                button:Hide()
            end
        end
    end

    -- Hook ActionButton_Update to protect against nil Border objects on non-standard buttons
    if ActionButton_Update then
        local orig_ActionButton_Update = ActionButton_Update
        ActionButton_Update = function()
            local btn = this
            if btn and btn:GetName() then
                local bName = btn:GetName() .. "Border"
                if not _G[bName] then
                    _G[bName] = {
                        SetVertexColor = function() end,
                        Show = function() end,
                        Hide = function() end,
                    }
                end
            end
            if orig_ActionButton_Update then
                orig_ActionButton_Update()
            end
        end
    end

    -- Neutralize Blizzard's MultiActionBar_Update to prevent hiding active bars
    if MultiActionBar_Update then
        local origMultiUpdate = MultiActionBar_Update
        MultiActionBar_Update = function()
            if origMultiUpdate then origMultiUpdate() end
            PUIHotbars:ApplyLayout()
        end
    end

    -- Send up Options Flare to Core Options Hub
    if Primus.Options and Primus.Options.RegisterModuleOptions then
        Primus.Options:RegisterModuleOptions("PUIHotbars", {
            title = "Action Bars & Watchbar",
            category = "Action Bars",
            icon = "Interface\\Icons\\Ability_DualWield",
            desc = "120-Slot virtualized action bars, multi-faction reputation watch, and dynamic matrix layout.",
            order = 2,
        }, BuildHotbarsOptionsPanel)
    end

    -- Decouple PetActionBarFrame and ShapeshiftBarFrame from Blizzard's sliding & MainMenuBar
    if PetActionBarFrame then
        PetActionBarFrame:SetParent(UIParent)
        PetActionBarFrame:SetScript("OnUpdate", nil)
    end
    if ShapeshiftBarFrame then
        ShapeshiftBarFrame:SetParent(UIParent)
        ShapeshiftBarFrame:SetScript("OnUpdate", nil)
    end
    if UIPARENT_MANAGED_FRAME_POSITIONS then
        UIPARENT_MANAGED_FRAME_POSITIONS["PetActionBarFrame"] = nil
        UIPARENT_MANAGED_FRAME_POSITIONS["ShapeshiftBarFrame"] = nil
        UIPARENT_MANAGED_FRAME_POSITIONS["PETACTIONBAR_YPOS"] = nil
        UIPARENT_MANAGED_FRAME_POSITIONS["MultiBarBottomLeft"] = nil
    end
    ShapeshiftBar_UpdatePosition = function() end
    ShowPetActionBar = function()
        if (PetHasActionBar() or UnitExists("pet")) and hotbarsDB:Get("showPet", true) then
            if PetActionBarFrame then PetActionBarFrame:Show() end
            if petAnchor then petAnchor:Show() end
            for i = 1, 10 do
                local btn = _G["PetActionButton" .. i]
                if btn then btn:Show() end
            end
        end
    end
    HidePetActionBar = function()
        if not (PetHasActionBar() or UnitExists("pet")) or not hotbarsDB:Get("showPet", true) then
            if PetActionBarFrame then PetActionBarFrame:Hide() end
            if petAnchor then petAnchor:Hide() end
        end
    end

    self:ApplyLayout()

    -- Hook UIParent_ManageFramePositions
    if UIParent_ManageFramePositions then
        local origManage = UIParent_ManageFramePositions
        UIParent_ManageFramePositions = function()
            if origManage then origManage() end
            PUIHotbars:ApplyLayout()
        end
    end

    if MainMenuBar then
        local origMainShow = MainMenuBar:GetScript("OnShow")
        MainMenuBar:SetScript("OnShow", function()
            if origMainShow then origMainShow() end
            StripBlizzardArt()
        end)
    end

    if ShowBonusActionBar then
        local origShow = ShowBonusActionBar
        ShowBonusActionBar = function()
            if origShow then origShow() end
            StripBlizzardArt()
        end
    end

    if HideBonusActionBar then
        local origHide = HideBonusActionBar
        HideBonusActionBar = function()
            if origHide then origHide() end
            StripBlizzardArt()
        end
    end

    -- Hook CharacterFrame / ReputationFrame to auto-scan factions
    if ReputationFrame then
        Events:HookScript(ReputationFrame, "OnShow", function()
            PUIHotbars:ScanFactions()
            PUIHotbars:UpdateXP()
        end)
    end

    -- Subcommand routing via Console
    if Primus.Console and Primus.Console.RegisterSubCommand then
        Primus.Console:RegisterSubCommand("hotbars", function(argParam)
            argParam = Utils.Trim(argParam or "")
            local mover = PUIMover or Primus.PUIMover
            if argParam == "" or argParam == "unlock" or argParam == "mover" then
                if mover and mover.Unlock then mover:Unlock("BARS") end
            elseif argParam == "lock" then
                if mover and mover.Lock then mover:Lock() end
            elseif argParam == "reset" then
                if mover and mover.ResetAll then mover:ResetAll() end
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIHotbars]: Bar positions reset to default.", "69ccf0"))
            else
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIHotbars]: Commands: /pui hotbars [unlock | lock | reset]", "69ccf0"))
            end
        end, "PUI HotBars action bar management (/pui hotbars [unlock|lock|reset])")
    end
end

function PUIHotbars:OnEnable()
    -- Event Registrations
    Events:Register("PLAYER_XP_UPDATE", self, function() PUIHotbars:UpdateXP() end)
    Events:Register("UPDATE_EXHAUSTION", self, function() PUIHotbars:UpdateXP() end)
    Events:Register("UPDATE_FACTION", self, function() 
        PUIHotbars:ScanFactions()
        PUIHotbars:UpdateXP() 
    end)
    Events:Register("PLAYER_LEVEL_UP", self, function() PUIHotbars:UpdateXP() end)
    Events:Register("ACTIONBAR_PAGE_CHANGED", self, function() PUIHotbars:ApplyLayout() end)
    Events:Register("PLAYER_ENTERING_WORLD", self, function() 
        PUIHotbars:ScanFactions()
        PUIHotbars:ApplyLayout() 
    end)
    Events:Register("UPDATE_BONUS_ACTIONBAR", self, function() PUIHotbars:ApplyLayout() end)
    Events:Register("UPDATE_SHAPESHIFT_FORMS", self, function() PUIHotbars:ApplyLayout() end)
    Events:Register("PET_BAR_UPDATE", self, function() PUIHotbars:ApplyLayout() end)
    Events:Register("PET_BAR_UPDATE_COOLDOWN", self, function() if PetActionBar_UpdateCooldowns then PetActionBar_UpdateCooldowns() end end)
    Events:Register("PET_UI_UPDATE", self, function() PUIHotbars:ApplyLayout() end)
    Events:Register("UNIT_PET", self, function(unit) if unit == "player" then PUIHotbars:ApplyLayout() end end)

    -- Real-time Range & Mana State Ticker (0.15s) with owner tracking for clean unhooking
    Time:Every(0.15, function()
        PUIHotbars:UpdateButtonStates()
    end, nil, self)

    self:ScanFactions()
    self:ApplyLayout()
end

function PUIHotbars:OnDisable()
    if bar1Anchor then bar1Anchor:Hide() end
    if bar2Anchor then bar2Anchor:Hide() end
    if bar3Anchor then bar3Anchor:Hide() end
    if bar4Anchor then bar4Anchor:Hide() end
    if bar5Anchor then bar5Anchor:Hide() end
    if stanceAnchor then stanceAnchor:Hide() end
    if petAnchor then petAnchor:Hide() end
    if self.xpBarFrame then self.xpBarFrame:Hide() end
    if self.microAnchor then self.microAnchor:Hide() end
    if self.bagAnchor then self.bagAnchor:Hide() end
end
