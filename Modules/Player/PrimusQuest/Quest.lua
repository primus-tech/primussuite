--[[
    PrimusUI Module: PUIQuest (QuestLog Hooks & Auto-Tracking Engine)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides QuestLogFrame integration, objective parsing, and auto-tracking hooks.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIQuest = Primus.PUIQuest or {}
Primus.PUIQuest = PUIQuest
_G.PUIQuest = PUIQuest

local Quest = {}
PUIQuest.Quest = Quest

local Utils   = Primus.Utils
local Widgets = Primus.Widgets
local Events  = Primus.Events

local showBtn, cleanBtn

-- Build QuestLog Buttons
local function HookQuestLog()
    if not QuestLogFrame or showBtn then return end

    showBtn = Widgets:CreateButton(QuestLogFrame, "Show on Map", 84, 20, function()
        local selection = GetQuestLogSelection()
        if selection and selection > 0 then
            local title = GetQuestLogTitle(selection)
            if title then
                PUIQuest:FocusQuest(title)
                if not WorldMapFrame:IsVisible() then
                    ShowUIPanel(WorldMapFrame)
                end
            end
        end
    end)
    showBtn:SetPoint("BOTTOMLEFT", QuestLogFrame, "BOTTOMLEFT", 18, 14)

    cleanBtn = Widgets:CreateButton(QuestLogFrame, "Clean Map", 70, 20, function()
        PUIQuest:FocusQuest(nil)
        if PUIQuest.Map then
            PUIQuest.Map:ClearPins()
        end
    end)
    cleanBtn:SetPoint("LEFT", showBtn, "RIGHT", 6, 0)
end

function Quest:Initialize()
    HookQuestLog()
end
