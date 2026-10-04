--[[
    PrimusUI: Bootstrap & Master Controller Election
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Manages the global anchor, master election, flare discovery,
    and runtime state handover across all bundled/standalone instances.
--]]

local MAJOR = "Primus-1.0"
local MINOR = 10000 -- Semantic build number (e.g. 1.0.0 = 10000)

local _G = getglobals and getglobals() or _G or getfenv(0)

-- Global Anchor Table Initialization
if not _G.PrimusGlobal then
    _G.PrimusGlobal = {
        activeMajor = MAJOR,
        activeMinor = MINOR,
        addons = {},          -- Registered Addon Flares
        modules = {},         -- Registered Sub-Modules
        pendingFlares = {},   -- Queue of pre-login registrations
        state = "BOOT",       -- BOOT -> DISCOVERY -> INITIALIZING -> READY
    }
end

local globalRegistry = _G.PrimusGlobal

-- Controller Election: Check if incoming file is newer than active controller
if _G.Primus and globalRegistry.activeMinor and globalRegistry.activeMinor >= MINOR then
    -- Existing active controller is already up-to-date or newer. Skip initialization.
    return
end

-- Initialize or Hot-Upgrade the Master Controller table
local Primus = _G.Primus or {}
_G.Primus = Primus

Primus.MAJOR = MAJOR
Primus.MINOR = MINOR
globalRegistry.activeMajor = MAJOR
globalRegistry.activeMinor = MINOR

-- Internal Subsystem Tables (Core Only)
Primus.Utils     = Primus.Utils or {}
Primus.Memory    = Primus.Memory or {}
Primus.Debug     = Primus.Debug or {}
Primus.Time      = Primus.Time or {}
Primus.Events    = Primus.Events or {}
Primus.DB        = Primus.DB or {}
Primus.Media     = Primus.Media or {}
Primus.Anim      = Primus.Anim or {}
Primus.Widgets   = Primus.Widgets or {}
Primus.Keybind   = Primus.Keybind or {}
Primus.Console   = Primus.Console or {}
Primus.Comm      = Primus.Comm or {}
Primus.State     = Primus.State or {}
Primus.Hider     = Primus.Hider or {}
Primus.Options   = Primus.Options or {}

-- Public Registration API (The Flare Protocol)
function Primus:RegisterAddon(addonName, addonTable)
    if not addonName or type(addonName) ~= "string" then
        if self.Debug and self.Debug.Error then
            self.Debug:Error("Bootstrap", "Invalid addon name passed to RegisterAddon")
        end
        return nil
    end

    addonTable = addonTable or {}
    addonTable.name = addonName
    addonTable.isPrimusAddon = true
    addonTable.modules = addonTable.modules or {}

    globalRegistry.addons[addonName] = addonTable
    Primus[addonName] = addonTable

    -- If the engine is already booted, run immediate initialization
    if globalRegistry.state == "READY" and addonTable.OnInitialize and not addonTable.__initialized then
        addonTable.__initialized = true
        if self.Debug and self.Debug.SafeCall then
            self.Debug:SafeCall(addonTable.OnInitialize, addonTable)
        else
            addonTable:OnInitialize()
        end
    end

    return addonTable
end

function Primus:GetAddon(addonName)
    return globalRegistry.addons[addonName]
end

function Primus:RegisterModule(moduleName, moduleTable, category)
    if not moduleName or type(moduleName) ~= "string" then
        if self.Debug and self.Debug.Error then
            self.Debug:Error("Bootstrap", "Invalid module name passed to RegisterModule")
        end
        return nil
    end

    moduleTable = moduleTable or {}
    moduleTable.name = moduleName
    moduleTable.category = category or "General"
    moduleTable.enabled = false

    globalRegistry.modules[moduleName] = moduleTable
    Primus[moduleName] = moduleTable

    -- Auto-register short and alternative prefix aliases
    if string.find(moduleName, "^Primus") then
        local shortName = string.sub(moduleName, 7)
        if shortName ~= "" then
            Primus[shortName] = moduleTable
            Primus["PUI" .. shortName] = moduleTable
            globalRegistry.modules[shortName] = moduleTable
            globalRegistry.modules["PUI" .. shortName] = moduleTable
        end
    elseif string.find(moduleName, "^PUI") then
        local shortName = string.sub(moduleName, 4)
        if shortName ~= "" then
            Primus[shortName] = moduleTable
            Primus["Primus" .. shortName] = moduleTable
            globalRegistry.modules[shortName] = moduleTable
            globalRegistry.modules["Primus" .. shortName] = moduleTable
        end
    end

    if globalRegistry.state == "READY" and moduleTable.OnInitialize and not moduleTable.__initialized then
        moduleTable.__initialized = true
        if self.Debug and self.Debug.SafeCall then
            self.Debug:SafeCall(moduleTable.OnInitialize, moduleTable)
        else
            moduleTable:OnInitialize()
        end
    end

    return moduleTable
end

function Primus:GetModule(moduleName)
    if not moduleName then return nil end
    return globalRegistry.modules[moduleName]
        or (string.find(moduleName, "^Primus") and globalRegistry.modules[string.sub(moduleName, 7)])
        or (string.find(moduleName, "^PUI") and globalRegistry.modules[string.sub(moduleName, 4)])
        or globalRegistry.modules["Primus" .. moduleName]
        or globalRegistry.modules["PUI" .. moduleName]
end

function Primus:EnableModule(moduleName)
    local moduleObj = self:GetModule(moduleName)
    if not moduleObj then return false end
    if moduleObj.enabled then return true end

    moduleObj.enabled = true

    local db = self.DB and self.DB:GetNamespace("Modules")
    if db then
        db:Set(moduleName, true)
    end

    if moduleObj.OnEnable and type(moduleObj.OnEnable) == "function" then
        if self.Debug and self.Debug.SafeCall then
            self.Debug:SafeCall(moduleObj.OnEnable, moduleObj)
        else
            moduleObj:OnEnable()
        end
    end

    if self.Events and self.Events.Fire then
        self.Events:Fire("MODULE_ENABLED", moduleName)
    end
    return true
end

function Primus:DisableModule(moduleName)
    local moduleObj = self:GetModule(moduleName)
    if not moduleObj then return false end
    if not moduleObj.enabled then return true end

    if moduleObj.OnDisable and type(moduleObj.OnDisable) == "function" then
        if self.Debug and self.Debug.SafeCall then
            self.Debug:SafeCall(moduleObj.OnDisable, moduleObj)
        else
            moduleObj:OnDisable()
        end
    end

    moduleObj.enabled = false

    if self.Events and self.Events.UnregisterAll then
        self.Events:UnregisterAll(moduleObj)
    end

    if self.Time and self.Time.CancelAll then
        self.Time:CancelAll(moduleObj)
    end

    local db = self.DB and self.DB:GetNamespace("Modules")
    if db then
        db:Set(moduleName, false)
    end

    if self.Events and self.Events.Fire then
        self.Events:Fire("MODULE_DISABLED", moduleName)
    end
    return true
end

function Primus:IsModuleEnabled(moduleName)
    local moduleObj = self:GetModule(moduleName)
    return (moduleObj and moduleObj.enabled == true) or false
end

function Primus:ToggleModule(moduleName)
    if self:IsModuleEnabled(moduleName) then
        return self:DisableModule(moduleName)
    else
        return self:EnableModule(moduleName)
    end
end

function Primus:GetRegistry()
    return globalRegistry
end

function Primus:GetVersion()
    return MAJOR, MINOR
end
