--[[
    PrimusUI: Master Runtime Anchor & Lifecycle Orchestrator
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Coordinates the final boot phase, initializes all registered addons
    and modules, and provides the public API facade.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local registry = Primus:GetRegistry()
local Events   = Primus.Events
local Debug    = Primus.Debug
local Utils    = Primus.Utils

-- Boot Finalization Sequence
local function InitializeAll()
    if registry.state == "READY" then return end
    registry.state = "INITIALIZING"

    -- Register "Modules" namespace for enable/disable persistence
    local moduleDB = Primus.DB and Primus.DB:RegisterNamespace("Modules", {})

    -- Phase 1: Initialize all registered Addons
    for addonName, addon in pairs(registry.addons) do
        if addon.OnInitialize and type(addon.OnInitialize) == "function" then
            Debug:SafeCall(addon.OnInitialize, addon)
        end
    end

    -- Phase 2: Initialize all registered Modules
    for moduleName, moduleObj in pairs(registry.modules) do
        if moduleObj.OnInitialize and type(moduleObj.OnInitialize) == "function" then
            Debug:SafeCall(moduleObj.OnInitialize, moduleObj)
        end
    end

    -- Phase 3: Enable all Addons and active Modules
    for addonName, addon in pairs(registry.addons) do
        if addon.OnEnable and type(addon.OnEnable) == "function" then
            Debug:SafeCall(addon.OnEnable, addon)
            addon.enabled = true
        end
    end

    for moduleName, moduleObj in pairs(registry.modules) do
        local isEnabled = true
        if moduleDB and moduleDB:Get(moduleName) ~= nil then
            isEnabled = moduleDB:Get(moduleName)
        elseif moduleObj.defaultDisabled then
            isEnabled = false
        end

        if isEnabled then
            Primus:EnableModule(moduleName)
        else
            moduleObj.enabled = false
        end
    end

    registry.state = "READY"
    local major, minor = Primus:GetVersion()
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PrimusSuite]: Suite v%s (build %d) Initialized.", major, minor), "69ccf0"))
end

-- Hook login events for staged startup
Events:Register("PLAYER_LOGIN", Primus, function()
    InitializeAll()
end)
