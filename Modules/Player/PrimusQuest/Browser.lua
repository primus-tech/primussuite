--[[
    PrimusUI Module: PUIQuest (Dark Glassmorphic In-Game Database Browser GUI)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides an interactive in-game database search UI for Quests, Items, NPCs,
    and Objects with 1-pixel borders and live filtering.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIQuest = Primus.PUIQuest or {}
Primus.PUIQuest = PUIQuest
_G.PUIQuest = PUIQuest

local Browser = {}
PUIQuest.Browser = Browser

local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils

local browserFrame = nil
local activeCategory = "quests"
local searchInput = nil
local resultButtons = {}
local currentResults = {}

local function CreateResultButton(parent, index)
    local btn = CreateFrame("Button", "PUIQuest_BrowserRow_" .. index, parent)
    btn:SetWidth(400)
    btn:SetHeight(22)
    btn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    btn:SetBackdropColor(0.12, 0.14, 0.18, 0.6)
    btn:SetBackdropBorderColor(0.2, 0.25, 0.35, 0.5)

    local text = btn:CreateFontString(nil, "OVERLAY")
    text:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    text:SetPoint("LEFT", btn, "LEFT", 8, 0)
    btn.text = text

    btn:SetScript("OnEnter", function()
        btn:SetBackdropColor(0.2, 0.3, 0.5, 0.8)
        if btn.data and GameTooltip then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            if btn.data.category == "Items" then
                GameTooltip:SetHyperlink("item:" .. btn.data.id .. ":0:0:0")
            elseif btn.data.category == "Quests" then
                local q = PUIQuest.Database:FindQuest(btn.data.id)
                if q then
                    GameTooltip:AddLine(q.title, 1.0, 0.82, 0.0)
                    if q.desc and q.desc ~= "" then
                        GameTooltip:AddLine(q.desc, 0.8, 0.8, 0.8, 1)
                    end
                end
            else
                GameTooltip:AddLine(btn.data.name, 1.0, 0.82, 0.0)
                GameTooltip:AddLine(string.format("Category: %s (ID #%d)", btn.data.category, btn.data.id), 0.6, 0.6, 0.6)
            end
            GameTooltip:AddLine("Click: Focus on World Map", 0.4, 0.85, 1.0)
            GameTooltip:Show()
        end
    end)

    btn:SetScript("OnLeave", function()
        btn:SetBackdropColor(0.12, 0.14, 0.18, 0.6)
        if GameTooltip then GameTooltip:Hide() end
    end)

    btn:SetScript("OnClick", function()
        if btn.data and btn.data.name then
            PUIQuest:FocusQuest(btn.data.name)
            if not WorldMapFrame:IsVisible() then
                ShowUIPanel(WorldMapFrame)
            end
        end
    end)

    return btn
end

local function BuildBrowserWindow()
    if browserFrame then return browserFrame end

    local f = Widgets:CreateBackdropFrame("PUIQuest_BrowserFrame", UIParent, 440, 360, "HIGH", "1Pixel")
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetBackdropColor(0.08, 0.09, 0.12, 0.95)
    f:SetBackdropBorderColor(0.3, 0.6, 0.9, 1.0)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

    -- Header Title
    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(Media:Fetch("font", "Default"), 12, "OUTLINE")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
    title:SetText(Utils.ColorText("PrimusUI: Database Browser", "69ccf0"))

    -- Close Button
    local closeBtn = Widgets:CreateButton(f, "X", 22, 20, function()
        f:Hide()
    end)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -8)

    -- Search Box
    local edit = CreateFrame("EditBox", "PUIQuest_SearchBox", f)
    edit:SetWidth(412)
    edit:SetHeight(24)
    edit:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -38)
    edit:SetBackdrop(Media:Fetch("border", "1Pixel"))
    edit:SetBackdropColor(0.05, 0.06, 0.08, 0.9)
    edit:SetBackdropBorderColor(0.3, 0.4, 0.6, 0.8)
    edit:SetFont(Media:Fetch("font", "Default"), 10, "NONE")
    edit:SetTextInsets(6, 6, 0, 0)
    edit:SetAutoFocus(false)
    edit:SetScript("OnTextChanged", function()
        Browser:PerformSearch(this:GetText())
    end)
    edit:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    searchInput = edit

    -- Category Tab Buttons
    local cats = { { id = "quests", text = "Quests" }, { id = "items", text = "Items" }, { id = "units", text = "NPCs" }, { id = "objects", text = "Objects" } }
    local prev = nil
    for i = 1, table.getn(cats) do
        local c = cats[i]
        local btn = Widgets:CreateButton(f, c.text, 98, 20, function()
            activeCategory = c.id
            Browser:PerformSearch(searchInput and searchInput:GetText() or "")
        end)
        if not prev then
            btn:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -8)
        else
            btn:SetPoint("LEFT", prev, "RIGHT", 6, 0)
        end
        prev = btn
    end

    -- Scroll Area for Results
    local resultsContainer = CreateFrame("Frame", "PUIQuest_ResultsContainer", f)
    resultsContainer:SetWidth(412)
    resultsContainer:SetHeight(230)
    resultsContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -98)

    for i = 1, 10 do
        local btn = CreateResultButton(resultsContainer, i)
        if i == 1 then
            btn:SetPoint("TOPLEFT", resultsContainer, "TOPLEFT", 0, 0)
        else
            btn:SetPoint("TOPLEFT", resultButtons[i - 1], "BOTTOMLEFT", 0, -2)
        end
        resultButtons[i] = btn
    end

    browserFrame = f
    browserFrame:Hide()
    return browserFrame
end

function Browser:PerformSearch(query)
    if not query or query == "" then
        for i = 1, 10 do
            if resultButtons[i] then resultButtons[i]:Hide() end
        end
        return
    end

    currentResults = PUIQuest.Database:Search(query, activeCategory, 10)
    for i = 1, 10 do
        local res = currentResults[i]
        local btn = resultButtons[i]
        if btn then
            if res then
                btn.data = res
                btn.text:SetText(string.format("[%s] %s |cff888888(#%d)|r", res.category, res.name, res.id))
                btn:Show()
            else
                btn:Hide()
            end
        end
    end
end

function Browser:Toggle()
    local f = BuildBrowserWindow()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        if searchInput then searchInput:SetFocus() end
    end
end
