--[[
    PrimusUI: Contextual State Machine & Combat Focus Engine ("Combat Zen")
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides intelligent state-driven interface focus transitions:
    - Smoothly fades or hides non-essential peripheral clutter during combat.
    - Strictly enforces the Action Bar Permanence Rule (rotational ability bars never hide).
    - Supports Hover-to-Peek for instant 3.0s temporary reveal of faded elements.
    - Seamlessly delegates frame management and registration to Primus.Hider.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local State   = Primus.State or {}
Primus.State  = State

local Hider   = Primus.Hider
local DB      = Primus.DB
local Events  = Primus.Events
local Anim    = Primus.Anim
local Time    = Primus.Time
local Utils   = Primus.Utils
local Console = Primus.Console

-- Persistent State Database
local stateDB = DB:RegisterNamespace("Zen", {
    enabled            = true,
    fadeMinimap        = true,
    fadeQuestTracker   = false,
    fadeCornerFrames   = false,
    fadeMicroMenu      = true,
    fadeBagBar         = true,
    fadeChat           = true,
    combatAlpha        = 0.0,
    idleAlpha          = 1.0,
    fadeDuration       = 0.25,
    peekDuration       = 3.0,
})

local inCombat = false

-- Register or update default peripheral frames in Hider
local function SyncStandardFrames()
    if not Hider or not Hider.RegisterDynamic then return end

    local combatAlpha = stateDB:Get("combatAlpha", 0.0)
    local idleAlpha   = stateDB:Get("idleAlpha", 1.0)
    local duration    = stateDB:Get("fadeDuration", 0.25)
    local peekTime    = stateDB:Get("peekDuration", 3.0)

    -- 1. Minimap & Zone Header
    if stateDB:Get("fadeMinimap", true) then
        local mm = _G["Primus_Minimap"] or MinimapCluster or Minimap
        if mm then
            Hider:RegisterDynamic(mm, "Minimap", {
                mode = "fade",
                fadeOnCombat = true,
                combatAlpha = combatAlpha,
                idleAlpha = idleAlpha,
                fadeDuration = duration,
                peekDuration = peekTime,
                enableHoverPeek = true,
            })
        end
    else
        Hider:UnregisterDynamic("Minimap")
        local mm = _G["Primus_Minimap"] or MinimapCluster or Minimap
        if mm then mm:SetAlpha(idleAlpha) end
    end

    -- 2. Quest Objective Tracker
    if stateDB:Get("fadeQuestTracker", true) then
        if QuestWatchFrame then
            Hider:RegisterDynamic(QuestWatchFrame, "QuestWatch", {
                mode = "fade",
                fadeOnCombat = true,
                combatAlpha = combatAlpha,
                idleAlpha = idleAlpha,
                fadeDuration = duration,
                peekDuration = peekTime,
                enableHoverPeek = true,
            })
        end
    else
        Hider:UnregisterDynamic("QuestWatch")
        if QuestWatchFrame then QuestWatchFrame:SetAlpha(idleAlpha) end
    end

    -- 3. Micro Menu Bar (PUIHotbars)
    local microBar = _G["Primus_PUIHotbars_MicroBar"]
    if microBar and stateDB:Get("fadeMicroMenu", true) then
        Hider:RegisterDynamic(microBar, "MicroMenu", {
            mode = "fade",
            fadeOnCombat = true,
            combatAlpha = combatAlpha,
            idleAlpha = idleAlpha,
            fadeDuration = duration,
            peekDuration = peekTime,
            enableHoverPeek = true,
        })
    elseif microBar then
        Hider:UnregisterDynamic("MicroMenu")
        microBar:SetAlpha(idleAlpha)
    end

    -- 4. Bag Bar (PUIHotbars)
    local bagBar = _G["Primus_PUIHotbars_BagBar"]
    if bagBar and stateDB:Get("fadeBagBar", true) then
        Hider:RegisterDynamic(bagBar, "BagBar", {
            mode = "fade",
            fadeOnCombat = true,
            combatAlpha = combatAlpha,
            idleAlpha = idleAlpha,
            fadeDuration = duration,
            peekDuration = peekTime,
            enableHoverPeek = true,
        })
    elseif bagBar then
        Hider:UnregisterDynamic("BagBar")
        bagBar:SetAlpha(idleAlpha)
    end

    -- 5. Chat Frame 1
    if stateDB:Get("fadeChat", true) then
        if ChatFrame1 then
            Hider:RegisterDynamic(ChatFrame1, "Chat1", {
                mode = "fade",
                fadeOnCombat = true,
                combatAlpha = combatAlpha,
                idleAlpha = idleAlpha,
                fadeDuration = duration,
                peekDuration = peekTime,
                enableHoverPeek = true,
            })
        end
    else
        Hider:UnregisterDynamic("Chat1")
        if ChatFrame1 then ChatFrame1:SetAlpha(idleAlpha) end
    end

    -- 6. Corner Legacy Frames (Optional)
    if stateDB:Get("fadeCornerFrames", false) then
        if PlayerFrame then
            Hider:RegisterDynamic(PlayerFrame, "PlayerFrame", {
                mode = "fade",
                fadeOnCombat = true,
                combatAlpha = combatAlpha,
                idleAlpha = idleAlpha,
                fadeDuration = duration,
                peekDuration = peekTime,
                enableHoverPeek = true,
            })
        end
        if TargetFrame then
            Hider:RegisterDynamic(TargetFrame, "TargetFrame", {
                mode = "fade",
                fadeOnCombat = true,
                combatAlpha = combatAlpha,
                idleAlpha = idleAlpha,
                fadeDuration = duration,
                peekDuration = peekTime,
                enableHoverPeek = true,
            })
        end
    else
        Hider:UnregisterDynamic("PlayerFrame")
        Hider:UnregisterDynamic("TargetFrame")
        if PlayerFrame then PlayerFrame:SetAlpha(idleAlpha) end
        if TargetFrame then TargetFrame:SetAlpha(idleAlpha) end
    end
end

-- Peek / Wake Up a Faded Frame temporarily
function State:PeekFrame(frame, key)
    if Hider and Hider.PeekFrame then
        Hider:PeekFrame(frame, key)
    end
end

-- Apply State Transition (Combat vs Out of Combat)
function State:ApplyState(force)
    SyncStandardFrames()

    local isEnabled = stateDB:Get("enabled", true)
    if not isEnabled and not force then return end

    local hasTarget = UnitExists and (UnitExists("target") and true or false) or false
    local isResting = IsResting and (IsResting() and true or false) or false

    if Hider and Hider.ApplyDynamicState then
        Hider:ApplyDynamicState({
            inCombat = inCombat,
            hasTarget = hasTarget,
            isResting = isResting,
            enabled = isEnabled,
        })
    end

    if Events and Events.Fire then
        Events:Fire("UI_COMBAT_STATE_CHANGED", inCombat)
    end
end

-- Enter Combat
function State:OnEnterCombat()
    inCombat = true
    self:ApplyState()
end

-- Exit Combat
function State:OnExitCombat()
    inCombat = false
    self:ApplyState()
end

-- =========================================================================
-- INITIALIZATION
-- =========================================================================

function State:OnInitialize()
    Hider = Primus.Hider

    Events:Register("PLAYER_REGEN_DISABLED", self, function()
        State:OnEnterCombat()
    end)

    Events:Register("PLAYER_REGEN_ENABLED", self, function()
        State:OnExitCombat()
    end)

    Events:Register("PLAYER_ENTERING_WORLD", self, function()
        inCombat = UnitAffectingCombat and (UnitAffectingCombat("player") and true or false) or false
        State:ApplyState(true)
    end)

    Events:Register("PLAYER_TARGET_CHANGED", self, function()
        if stateDB:Get("enabled", true) then
            State:ApplyState()
        end
    end)

    -- Register Subcommand under Master Console
    if Console and Console.RegisterSubCommand then
        Console:RegisterSubCommand("zen", function(argParam)
            argParam = Utils.Trim(argParam or "")
            if argParam == "toggle" then
                local cur = stateDB:Get("enabled", true)
                stateDB:Set("enabled", not cur)
                State:ApplyState(true)
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[Zen]: State Focus is now " .. (not cur and "ENABLED" or "DISABLED"), "69ccf0"))
            else
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("=== PrimusUI Zen Engine ===", "69ccf0"))
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("Status: ", "ffbb33") .. (stateDB:Get("enabled", true) and "|cff33ff33ACTIVE|r" or "|cffff4444DISABLED|r"))
                DEFAULT_CHAT_FRAME:AddMessage("Automatically strips peripheral clutter during combat while preserving rotational action bars.")
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("Commands: /pui zen toggle", "ffd100"))
            end
        end, "Zen Focus Engine (/pui zen [toggle])")
    end
end

-- Self-register module lifecycle
Primus:RegisterModule("Zen", State, "Core")
