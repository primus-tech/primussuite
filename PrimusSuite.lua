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

    -- Phase 1: Initialize all registered Addons (deduplicated)
    local visitedAddons = {}
    for addonName, addon in pairs(registry.addons) do
        if addon and not visitedAddons[addon] then
            visitedAddons[addon] = true
            if addon.OnInitialize and type(addon.OnInitialize) == "function" and not addon.__initialized then
                addon.__initialized = true
                if Debug and Debug.SafeCall then
                    Debug:SafeCall(addon.OnInitialize, addon)
                else
                    addon:OnInitialize()
                end
            end
        end
    end

    -- Phase 2: Initialize all registered Modules (deduplicated across alias pointers)
    local visitedModules = {}
    for moduleName, moduleObj in pairs(registry.modules) do
        if moduleObj and not visitedModules[moduleObj] then
            visitedModules[moduleObj] = true
            if moduleObj.OnInitialize and type(moduleObj.OnInitialize) == "function" and not moduleObj.__initialized then
                moduleObj.__initialized = true
                if Debug and Debug.SafeCall then
                    Debug:SafeCall(moduleObj.OnInitialize, moduleObj)
                else
                    moduleObj:OnInitialize()
                end
            end
        end
    end

    -- Phase 3: Enable all Addons and active Modules
    for addon, _ in pairs(visitedAddons) do
        if addon.OnEnable and type(addon.OnEnable) == "function" and not addon.enabled then
            if Debug and Debug.SafeCall then
                Debug:SafeCall(addon.OnEnable, addon)
            else
                addon:OnEnable()
            end
            addon.enabled = true
        end
    end

    for moduleObj, _ in pairs(visitedModules) do
        local canonicalName = moduleObj.name or "Unknown"
        local isEnabled = true
        if moduleDB and moduleDB:Get(canonicalName) ~= nil then
            isEnabled = moduleDB:Get(canonicalName)
        elseif moduleObj.defaultDisabled then
            isEnabled = false
        end

        if isEnabled then
            Primus:EnableModule(canonicalName)
        else
            moduleObj.enabled = false
        end
    end

    registry.state = "READY"
    local major, minor = Primus:GetVersion()
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PrimusSuite]: Suite v%s (build %d) Initialized.", major, minor), "69ccf0"))
end

-- Staged login hooks with multiple fallback events
Events:Register("PLAYER_LOGIN", Primus, function()
    InitializeAll()
end)

Events:Register("PLAYER_ENTERING_WORLD", Primus, function()
    InitializeAll()
end)

Events:Register("VARIABLES_LOADED", Primus, function()
    if Primus.DB and Primus.DB.SyncNamespaces then
        Primus.DB:SyncNamespaces()
    end
end)
