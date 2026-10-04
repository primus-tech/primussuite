--[[
    PrimusLib: SavedVariables & Profile IO Engine
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Manages persistent account & character data storage, deep default
    merging, profile isolation, and schema migrations.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local DB     = Primus.DB
local Utils  = Primus.Utils
local Events = Primus.Events
local Debug  = Primus.Debug

-- Registered Namespaces
local registeredNamespaces = {}

-- Ensure root SavedVariable tables exist in global scope
local function InitializeRootStorage()
    if not _G.PrimusGlobalDB or type(_G.PrimusGlobalDB) ~= "table" then
        _G.PrimusGlobalDB = {
            version = 1,
            namespaces = {},
            profiles = {
                ["Default"] = {},
            },
            currentProfile = "Default",
        }
    end
    if not _G.PrimusGlobalDB.namespaces or type(_G.PrimusGlobalDB.namespaces) ~= "table" then
        _G.PrimusGlobalDB.namespaces = {}
    end
    if not _G.PrimusGlobalDB.profiles or type(_G.PrimusGlobalDB.profiles) ~= "table" then
        _G.PrimusGlobalDB.profiles = { ["Default"] = {} }
    end
    if not _G.PrimusGlobalDB.currentProfile then
        _G.PrimusGlobalDB.currentProfile = "Default"
    end

    if not _G.PrimusCharDB or type(_G.PrimusCharDB) ~= "table" then
        _G.PrimusCharDB = {
            version = 1,
            namespaces = {},
        }
    end
    if not _G.PrimusCharDB.namespaces or type(_G.PrimusCharDB.namespaces) ~= "table" then
        _G.PrimusCharDB.namespaces = {}
    end
end

local function SyncNamespaces()
    InitializeRootStorage()
    for name, handle in pairs(registeredNamespaces) do
        local root = handle.isCharSpecific and _G.PrimusCharDB.namespaces or _G.PrimusGlobalDB.namespaces
        if not root[name] then
            root[name] = {}
        end
        if handle.defaults and type(handle.defaults) == "table" then
            Utils.DeepMerge(root[name], handle.defaults)
        end
        handle.data = root[name]
    end
end

-- Register a persistent namespace for an addon or module
function DB:RegisterNamespace(name, defaults, isCharSpecific)
    if not name or type(name) ~= "string" then return nil end
    InitializeRootStorage()

    local root = isCharSpecific and _G.PrimusCharDB.namespaces or _G.PrimusGlobalDB.namespaces
    if not root[name] then
        if string.sub(name, 1, 3) == "PUI" then
            local legacyName = string.sub(name, 4)
            if root[legacyName] and type(root[legacyName]) == "table" then
                root[name] = Utils.DeepCopy(root[legacyName])
            else
                root[name] = {}
            end
        else
            root[name] = {}
        end
    end

    -- Deep merge default values into the stored data without overwriting user changes
    if defaults and type(defaults) == "table" then
        Utils.DeepMerge(root[name], defaults)
    end

    local handle = {
        name = name,
        data = root[name],
        defaults = defaults or {},
        isCharSpecific = isCharSpecific,
    }

    -- Helper methods on the namespace handle
    function handle:Get(key, fallback)
        if self.data and self.data[key] ~= nil then
            return self.data[key]
        end
        if self.defaults and self.defaults[key] ~= nil then
            return self.defaults[key]
        end
        return fallback
    end

    function handle:Set(key, value)
        if not self.data then
            local r = self.isCharSpecific and _G.PrimusCharDB.namespaces or _G.PrimusGlobalDB.namespaces
            if not r[self.name] then r[self.name] = {} end
            self.data = r[self.name]
        end
        self.data[key] = value
        Events:Fire("DB_VALUE_CHANGED", self.name, key, value)
    end

    function handle:Reset()
        if self.data then
            Utils.Wipe(self.data)
        end
        if self.defaults then
            Utils.DeepMerge(self.data, self.defaults)
        end
        Events:Fire("DB_RESET", self.name)
    end

    -- Transparent metatable proxy for direct field access (e.g. myDB.nodes, myDB.priceData)
    local handleMeta = {
        __index = function(t, k)
            local rawVal = rawget(t, k)
            if rawVal ~= nil then return rawVal end
            if t.data and t.data[k] ~= nil then
                return t.data[k]
            end
            if t.defaults and t.defaults[k] ~= nil then
                return t.defaults[k]
            end
            return nil
        end,
        __newindex = function(t, k, v)
            if k == "data" or k == "defaults" or k == "name" or k == "isCharSpecific" or k == "Get" or k == "Set" or k == "Reset" then
                rawset(t, k, v)
            else
                if not t.data then
                    local r = t.isCharSpecific and _G.PrimusCharDB.namespaces or _G.PrimusGlobalDB.namespaces
                    if not r[t.name] then r[t.name] = {} end
                    t.data = r[t.name]
                end
                t.data[k] = v
                Events:Fire("DB_VALUE_CHANGED", t.name, k, v)
            end
        end
    }
    setmetatable(handle, handleMeta)

    registeredNamespaces[name] = handle
    return handle
end

function DB:GetNamespace(name)
    return registeredNamespaces[name]
end

function DB:ResetProfile()
    for _, handle in pairs(registeredNamespaces) do
        handle:Reset()
    end
end

-- =========================================================================
-- PROFILE MANAGEMENT
-- =========================================================================

function DB:GetProfiles()
    InitializeRootStorage()
    local list = {}
    for profileName in pairs(_G.PrimusGlobalDB.profiles) do
        table.insert(list, profileName)
    end
    return list
end

function DB:GetCurrentProfile()
    InitializeRootStorage()
    return _G.PrimusGlobalDB.currentProfile or "Default"
end

function DB:SaveProfile(profileName)
    if not profileName or profileName == "" then return false end
    InitializeRootStorage()

    _G.PrimusGlobalDB.profiles[profileName] = Utils.DeepCopy(_G.PrimusGlobalDB.namespaces)
    _G.PrimusGlobalDB.currentProfile = profileName

    Events:Fire("PROFILE_SAVED", profileName)
    return true
end

function DB:LoadProfile(profileName)
    if not profileName or not _G.PrimusGlobalDB.profiles[profileName] then return false end
    InitializeRootStorage()

    _G.PrimusGlobalDB.namespaces = Utils.DeepCopy(_G.PrimusGlobalDB.profiles[profileName])
    _G.PrimusGlobalDB.currentProfile = profileName

    SyncNamespaces()
    Events:Fire("PROFILE_CHANGED", profileName)
    return true
end

function DB:DeleteProfile(profileName)
    if not profileName or profileName == "Default" then return false end
    InitializeRootStorage()
    if _G.PrimusGlobalDB.currentProfile == profileName then return false end

    _G.PrimusGlobalDB.profiles[profileName] = nil
    Events:Fire("PROFILE_DELETED", profileName)
    return true
end

function DB:CopyProfile(sourceName, targetName)
    if not sourceName or not targetName or not _G.PrimusGlobalDB.profiles[sourceName] then return false end
    InitializeRootStorage()

    _G.PrimusGlobalDB.profiles[targetName] = Utils.DeepCopy(_G.PrimusGlobalDB.profiles[sourceName])
    Events:Fire("PROFILE_COPIED", sourceName, targetName)
    return true
end

-- Auto-initialize when SavedVariables are loaded
Events:Register("VARIABLES_LOADED", DB, function()
    SyncNamespaces()
end)

Events:Register("PLAYER_LOGIN", DB, function()
    SyncNamespaces()
end)
