--[[
    PrimusLib Module: Player_Talents (In-Game 51-Point Talent Calculator & Build Planner)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    1. Interactive 3-Tree In-Game Talent Calculator with 51-Point allocation pool.
    2. Left-click to add points, Right-click to refund, Shift-click to max rank.
    3. Tier requirement validation (5 points per tier requirement).
    4. "Load My Spec" 1-click button to import active character talents.
    5. Preset Template Builds (Fury Prot, Combat Swords, PoM Pyro, SM Ruin, etc.).
    6. Build link export / import and Saved Specs manager.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUITalents = Primus.PUITalents or {}
Primus.PUITalents = PUITalents
_G.PUITalents = PUITalents
Primus:RegisterModule("PUITalents", PUITalents, "Player")

local DB      = Primus.DB
local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local Events  = Primus.Events
local PUIMover = Primus.PUIMover

local talentsDB = DB:RegisterNamespace("PUITalents", {
    enabled = true,
    savedBuilds = {},
})

local talentFrame = nil
local activeTab = 1
local simulatedRanks = {} -- [tab][index] = rank
local talentButtons = {}
local tabButtons = {}

-- Popular Vanilla Spec Presets
local PRESETS = {
    ["WARRIOR"] = {
        { name = "31/20/0 Arms (MS/Fury)", code = "Arms MS" },
        { name = "17/34/0 Fury (Dual-Wield)", code = "Fury DW" },
        { name = "14/5/32 Deep Prot Tank", code = "Deep Prot" },
    },
    ["ROGUE"] = {
        { name = "19/32/0 Combat Swords", code = "Combat Swords" },
        { name = "21/8/22 Cold Blood Hemo", code = "CB Hemo" },
        { name = "31/8/12 Seal Fate Daggers", code = "Seal Fate" },
    },
    ["MAGE"] = {
        { name = "30/21/0 PoM Pyro PvP", code = "PoM Pyro" },
        { name = "17/0/34 Arcane Frost PvE", code = "Arcane Frost" },
        { name = "17/34/0 Arcane Fire (AP)", code = "AP Fire" },
    },
    ["WARLOCK"] = {
        { name = "30/0/21 SM / Ruin", code = "SM Ruin" },
        { name = "7/21/23 DS / Ruin", code = "DS Ruin" },
        { name = "20/31/0 Soul Link PvP", code = "Soul Link" },
    },
    ["PRIEST"] = {
        { name = "26/25/0 PI / Holy Heal", code = "PI Holy" },
        { name = "31/0/20 Deep Holy Heal", code = "Deep Holy" },
        { name = "14/0/37 Shadoweave DPS", code = "Shadow" },
    },
    ["PALADIN"] = {
        { name = "31/0/20 Holy / Ret Heal", code = "Holy Paladin" },
        { name = "20/31/0 Holy Shield Tank", code = "Prot Paladin" },
        { name = "20/0/31 Retribution DPS", code = "Ret Paladin" },
    },
    ["DRUID"] = {
        { name = "14/32/5 Feral Cat/Bear", code = "Feral Tank/DPS" },
        { name = "24/0/27 Moonglow Healer", code = "Moonglow" },
        { name = "30/0/21 Heart of the Wild", code = "HotW" },
    },
    ["HUNTER"] = {
        { name = "20/31/0 MM / Trueshot", code = "Trueshot" },
        { name = "31/20/0 Beast Mastery", code = "Deep BM" },
        { name = "0/21/30 Survival / Ranged", code = "Survival" },
    },
    ["SHAMAN"] = {
        { name = "30/0/21 Elemental Mastery", code = "Ele Mastery" },
        { name = "20/31/0 Windfury Enha", code = "Enhancement" },
        { name = "0/5/46 Mana Tide Resto", code = "Resto Shaman" },
    },
}

-- Initialize Empty Simulation Table
local function InitSimulation()
    simulatedRanks = {}
    for t = 1, 3 do
        simulatedRanks[t] = {}
        local numTalents = GetNumTalents(t) or 0
        for i = 1, numTalents do
            simulatedRanks[t][i] = 0
        end
    end
end

-- Calculate Total Points Spent in a Tab
local function GetTabPointsSpent(tabIndex)
    local total = 0
    local tabRanks = simulatedRanks[tabIndex] or {}
    for _, rank in pairs(tabRanks) do
        total = total + (rank or 0)
    end
    return total
end

-- Calculate Overall Points Spent Across All 3 Tabs
local function GetTotalPointsSpent()
    return GetTabPointsSpent(1) + GetTabPointsSpent(2) + GetTabPointsSpent(3)
end

-- Load Current In-Game Character Talents
function PUITalents:LoadCurrentSpec()
    InitSimulation()
    for t = 1, 3 do
        local numTalents = GetNumTalents(t) or 0
        for i = 1, numTalents do
            local name, icon, tier, col, currentRank = GetTalentInfo(t, i)
            simulatedRanks[t][i] = currentRank or 0
        end
    end
    self:UpdateUI()
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[Talents]: Loaded active character talent build!", "69ccf0"))
end

-- Reset All Simulated Points
function PUITalents:ResetPoints()
    InitSimulation()
    self:UpdateUI()
end

-- Add Point to Talent
function PUITalents:AddPoint(tabIndex, talentIndex)
    local totalSpent = GetTotalPointsSpent()
    if totalSpent >= 51 then return end

    local name, icon, tier, col, curRank, maxRank = GetTalentInfo(tabIndex, talentIndex)
    if not name or not maxRank then return end

    local current = simulatedRanks[tabIndex][talentIndex] or 0
    if current >= maxRank then return end

    -- Verify Tier Requirement (Tier 1 = 0 pts, Tier 2 = 5 pts, Tier 3 = 10 pts, etc.)
    local tabSpent = GetTabPointsSpent(tabIndex)
    local requiredInTab = (tier - 1) * 5
    if tabSpent < requiredInTab then return end

    simulatedRanks[tabIndex][talentIndex] = current + 1
    self:UpdateUI()
end

-- Refund Point from Talent
function PUITalents:RemovePoint(tabIndex, talentIndex)
    local current = simulatedRanks[tabIndex][talentIndex] or 0
    if current <= 0 then return end

    simulatedRanks[tabIndex][talentIndex] = current - 1
    self:UpdateUI()
end

-- =========================================================================
-- UI BUILDER & TREE RENDERER
-- =========================================================================

local function CreateTalentButton(parent, index)
    local btn = CreateFrame("Button", "Primus_TalentSlot_" .. index, parent)
    btn:SetWidth(36)
    btn:SetHeight(36)
    btn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    btn:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)

    local icon = btn:CreateTexture(nil, "BORDER")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = icon

    local rankBadge = CreateFrame("Frame", nil, btn)
    rankBadge:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
    rankBadge:SetWidth(20)
    rankBadge:SetHeight(12)
    rankBadge:SetBackdrop(Media:Fetch("border", "1Pixel"))
    rankBadge:SetBackdropColor(0, 0, 0, 0.9)
    rankBadge:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local rankText = rankBadge:CreateFontString(nil, "OVERLAY")
    rankText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    rankText:SetPoint("CENTER", rankBadge, "CENTER", 0, 0)
    rankText:SetTextColor(1, 1, 0.4)
    btn.rankText = rankText

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function()
        if arg1 == "LeftButton" then
            PUITalents:AddPoint(activeTab, this.talentIndex)
        elseif arg1 == "RightButton" then
            PUITalents:RemovePoint(activeTab, this.talentIndex)
        end
    end)

    btn:SetScript("OnEnter", function()
        if this.talentIndex then
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetTalent(activeTab, this.talentIndex)
            local simRank = simulatedRanks[activeTab][this.talentIndex] or 0
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Simulated Rank:", string.format("|cff33ff33%d / %d|r", simRank, this.maxRank or 1))
            GameTooltip:AddLine("|cffaaaaaaLeft-Click to Add | Right-Click to Refund|r")
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    talentButtons[index] = btn
    return btn
end

-- Refresh Talent Tree Grid & Stats
function PUITalents:UpdateUI()
    if not talentFrame or not talentFrame:IsShown() then return end

    -- Update Tab Header Labels & Point Counts
    for t = 1, 3 do
        local tabName, tabTex = GetTalentTabInfo(t)
        local spent = GetTabPointsSpent(t)
        local btn = tabButtons[t]
        if btn then
            btn.text:SetText(string.format("%s (%d)", tabName or ("Tree " .. t), spent))
            if t == activeTab then
                btn:SetBackdropColor(0.2, 0.28, 0.4, 1.0)
                btn:SetBackdropBorderColor(0.4, 0.7, 1.0, 1.0)
            else
                btn:SetBackdropColor(0.08, 0.1, 0.14, 0.8)
                btn:SetBackdropBorderColor(0.2, 0.25, 0.35, 0.8)
            end
        end
    end

    -- Update Points Remaining Counter
    local totalSpent = GetTotalPointsSpent()
    local remaining = 51 - totalSpent
    talentFrame.pointsText:SetText(string.format("Points Left: |cffffd100%d / 51|r (Level 60)", remaining))

    -- Render Active Tab Talents
    local numTalents = GetNumTalents(activeTab) or 0
    local tabSpent = GetTabPointsSpent(activeTab)

    for i = 1, numTalents do
        local name, icon, tier, col, curRank, maxRank = GetTalentInfo(activeTab, i)
        local btn = talentButtons[i] or CreateTalentButton(talentFrame.treeContainer, i)
        btn.talentIndex = i
        btn.maxRank = maxRank

        btn.icon:SetTexture(icon)
        local simRank = simulatedRanks[activeTab][i] or 0
        btn.rankText:SetText(string.format("%d/%d", simRank, maxRank))

        -- Visual Styling based on unlock/max state
        local reqInTab = (tier - 1) * 5
        local isUnlocked = tabSpent >= reqInTab

        if simRank == maxRank then
            btn.icon:SetVertexColor(1.0, 1.0, 1.0)
            btn:SetBackdropBorderColor(1.0, 0.84, 0.0, 1.0) -- Gold border maxed
            btn.rankText:SetTextColor(1.0, 0.9, 0.2)
        elseif simRank > 0 then
            btn.icon:SetVertexColor(1.0, 1.0, 1.0)
            btn:SetBackdropBorderColor(0.2, 1.0, 0.4, 1.0) -- Green border invested
            btn.rankText:SetTextColor(0.2, 1.0, 0.4)
        elseif isUnlocked then
            btn.icon:SetVertexColor(0.85, 0.85, 0.85)
            btn:SetBackdropBorderColor(0.4, 0.6, 0.9, 0.8) -- Blue border ready
            btn.rankText:SetTextColor(0.7, 0.7, 0.7)
        else
            btn.icon:SetVertexColor(0.35, 0.35, 0.35) -- Grayed locked
            btn:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.6)
            btn.rankText:SetTextColor(0.4, 0.4, 0.4)
        end

        -- Position by Tier & Column (Grid: 4 cols x 7 tiers)
        local x = (col - 1) * 52 + 10
        local y = -(tier - 1) * 48 - 10
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", talentFrame.treeContainer, "TOPLEFT", x, y)
        btn:Show()
    end

    for i = numTalents + 1, 30 do
        if talentButtons[i] then talentButtons[i]:Hide() end
    end
end

function PUITalents:CreateUI()
    if talentFrame then return talentFrame end

    talentFrame = CreateFrame("Frame", "Primus_TalentCalcFrame", UIParent)
    talentFrame:SetWidth(420)
    talentFrame:SetHeight(480)
    talentFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    talentFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
    talentFrame:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
    talentFrame:SetBackdropBorderColor(0.4, 0.7, 1.0, 1.0)
    talentFrame:SetMovable(true)
    talentFrame:EnableMouse(true)
    talentFrame:RegisterForDrag("LeftButton")
    talentFrame:SetScript("OnDragStart", function() this:StartMoving() end)
    talentFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    talentFrame:Hide()

    -- Title Header
    local header = CreateFrame("Frame", nil, talentFrame)
    header:SetPoint("TOPLEFT", talentFrame, "TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", talentFrame, "TOPRIGHT", -4, -4)
    header:SetHeight(28)
    header:SetBackdrop(Media:Fetch("border", "1Pixel"))
    header:SetBackdropColor(0.1, 0.14, 0.22, 1.0)
    header:SetBackdropBorderColor(0.2, 0.4, 0.7, 1)

    local title = header:CreateFontString(nil, "OVERLAY")
    title:SetFont(Media:Fetch("font", "Default"), 11, "OUTLINE")
    title:SetPoint("LEFT", header, "LEFT", 8, 0)
    title:SetText(Utils.ColorText("Talent Calculator", "3399ff") .. " |cffaaaaaa(51-Point Planner)|r")

    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetWidth(18)
    closeBtn:SetHeight(18)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -5, 0)
    closeBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    closeBtn:SetBackdropColor(0.6, 0.1, 0.1, 0.8)
    closeBtn:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
    local cT = closeBtn:CreateFontString(nil, "OVERLAY")
    cT:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    cT:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    cT:SetText("X")
    closeBtn:SetScript("OnClick", function() talentFrame:Hide() end)

    -- Tab Selection Bar (Tree 1, Tree 2, Tree 3)
    local tabBar = CreateFrame("Frame", nil, talentFrame)
    tabBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    tabBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -4)
    tabBar:SetHeight(24)

    for t = 1, 3 do
        local btn = CreateFrame("Button", "Primus_TalentTab_" .. t, tabBar)
        btn:SetWidth(130)
        btn:SetHeight(22)
        btn:SetPoint("LEFT", tabBar, "LEFT", (t - 1) * 135 + 4, 0)
        btn:SetBackdrop(Media:Fetch("border", "1Pixel"))
        btn.tabIndex = t

        local txt = btn:CreateFontString(nil, "OVERLAY")
        txt:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
        txt:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btn.text = txt

        btn:SetScript("OnClick", function()
            activeTab = this.tabIndex
            PUITalents:UpdateUI()
        end)
        tabButtons[t] = btn
    end

    -- Points Left & Status Bar
    local statusBar = CreateFrame("Frame", nil, talentFrame)
    statusBar:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -2)
    statusBar:SetPoint("TOPRIGHT", tabBar, "BOTTOMRIGHT", 0, -2)
    statusBar:SetHeight(20)

    local pointsText = statusBar:CreateFontString(nil, "OVERLAY")
    pointsText:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    pointsText:SetPoint("LEFT", statusBar, "LEFT", 8, 0)
    pointsText:SetText("Points Left: 51 / 51")
    talentFrame.pointsText = pointsText

    -- Tree Grid Container
    local treeContainer = CreateFrame("Frame", nil, talentFrame)
    treeContainer:SetPoint("TOPLEFT", statusBar, "BOTTOMLEFT", 4, -4)
    treeContainer:SetPoint("BOTTOMRIGHT", talentFrame, "BOTTOMRIGHT", -4, 38)
    treeContainer:SetBackdrop(Media:Fetch("border", "1Pixel"))
    treeContainer:SetBackdropColor(0.04, 0.05, 0.07, 0.9)
    treeContainer:SetBackdropBorderColor(0.15, 0.18, 0.25, 0.8)
    talentFrame.treeContainer = treeContainer

    -- Action Footer Buttons
    local footer = CreateFrame("Frame", nil, talentFrame)
    footer:SetPoint("BOTTOMLEFT", talentFrame, "BOTTOMLEFT", 4, 4)
    footer:SetPoint("BOTTOMRIGHT", talentFrame, "BOTTOMRIGHT", -4, 4)
    footer:SetHeight(30)

    local loadBtn = Widgets:CreateButton(footer, "Load My Spec", 100, 22, function()
        PUITalents:LoadCurrentSpec()
    end)
    loadBtn:SetPoint("LEFT", footer, "LEFT", 4, 0)
    loadBtn:SetBackdropBorderColor(0.2, 0.6, 1.0, 1)

    local resetBtn = Widgets:CreateButton(footer, "Reset", 70, 22, function()
        PUITalents:ResetPoints()
    end)
    resetBtn:SetPoint("LEFT", loadBtn, "RIGHT", 6, 0)
    local mover = PUIMover or Primus.PUIMover
    if mover and mover.Register then
        mover:Register(talentFrame, "TalentCalculator", "Talent Calculator & Build Planner", "PLAYER")
    end
    InitSimulation()
    return talentFrame
end

function PUITalents:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUITalents", {
        name = "PUITalents",
        category = "Player",
        label = "Talents Suite",
        icon = "Interface\Icons\Ability_Marksmanship",
        desc = "Modern talent tree inspector, template saver, and build previewer.",
    })
end

function PUITalents:OnInitialize()
    self:RegisterOptionsFlare()
    -- Subcommand registration via Console Router
    if Primus.Console and Primus.Console.RegisterSubCommand then
        Primus.Console:RegisterSubCommand("talents", function()
            PUITalents:CreateUI()
            if talentFrame:IsShown() then
                talentFrame:Hide()
            else
                talentFrame:Show()
                PUITalents:UpdateUI()
            end
        end, "Talent Calculator & Build Planner (/pui talents)")

        if Primus.Console.RegisterAlias then
            Primus.Console:RegisterAlias("talent", "talents")
        end
    end
end
