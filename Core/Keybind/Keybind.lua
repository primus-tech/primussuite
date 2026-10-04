--[[
    PrimusLib: Keybinding Manager & HoverBind Engine
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides programmatic keybinding management and an interactive
    hover-to-bind mode for any action button or UI frame.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local Keybind = Primus.Keybind
local Utils   = Primus.Utils
local Events  = Primus.Events

local isHoverBinding = false
local hoverFrame = nil

-- Create HoverBind Prompt Window
local promptFrame = CreateFrame("Frame", "Primus_HoverBindPrompt", UIParent)
promptFrame:SetWidth(280)
promptFrame:SetHeight(70)
promptFrame:SetPoint("TOP", UIParent, "TOP", 0, -50)
promptFrame:SetBackdrop(Primus.Media:Fetch("border", "1Pixel"))
promptFrame:SetBackdropColor(0.1, 0.1, 0.12, 0.95)
promptFrame:SetBackdropBorderColor(1, 0.8, 0.2, 1)
promptFrame:SetFrameStrata("TOOLTIP")
promptFrame:Hide()

local promptText = promptFrame:CreateFontString(nil, "OVERLAY")
promptText:SetFont(Primus.Media:Fetch("font", "Default"), 11, "OUTLINE")
promptText:SetPoint("CENTER", promptFrame, "CENTER", 0, 0)
promptText:SetText(Utils.ColorText("HoverBind Active!\n", "ffbb33") .. "Hover over a button and press a key.\nPress ESC to cancel / unbind.")

-- Keyboard capture frame
local keyCapture = CreateFrame("Frame", "Primus_KeyCaptureFrame", UIParent)
keyCapture:EnableKeyboard(true)
keyCapture:Hide()

keyCapture:SetScript("OnKeyDown", function()
    local keyPressed = arg1
    if not isHoverBinding or not hoverFrame then return end

    if keyPressed == "ESCAPE" then
        Keybind:StopHoverBind()
        return
    end

    local action = hoverFrame.action or hoverFrame:GetName()
    if action then
        SetBinding(keyPressed, action)
        SaveBindings(GetCurrentBindingSet())
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[Primus]: Bound [%s] to %s", keyPressed, action), "69ccf0"))
    end
end)

function Keybind:StartHoverBind()
    isHoverBinding = true
    promptFrame:Show()
    keyCapture:Show()
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[Primus]: HoverBind enabled. Hover over buttons and press keys.", "ffbb33"))
end

function Keybind:StopHoverBind()
    isHoverBinding = false
    promptFrame:Hide()
    keyCapture:Hide()
    hoverFrame = nil
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[Primus]: HoverBind disabled.", "ffbb33"))
end

function Keybind:ToggleHoverBind()
    if isHoverBinding then
        self:StopHoverBind()
    else
        self:StartHoverBind()
    end
end

local registeredHoverButtons = {}

-- Hook game buttons to track hover target
function Keybind:RegisterHoverTarget(buttonFrame)
    if not buttonFrame or registeredHoverButtons[buttonFrame] then return end
    registeredHoverButtons[buttonFrame] = true

    Events:HookScript(buttonFrame, "OnEnter", function()
        if isHoverBinding then
            hoverFrame = buttonFrame
        end
    end)
    Events:HookScript(buttonFrame, "OnLeave", function()
        if isHoverBinding and hoverFrame == buttonFrame then
            hoverFrame = nil
        end
    end)
end
