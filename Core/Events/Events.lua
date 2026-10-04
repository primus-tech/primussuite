--[[
    PrimusLib: Safe Event, Hook & Signal Bus Engine
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides centralized event dispatching, safe function & script hooking,
    inter-module message broadcasting, and automatic resource cleanup.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local Events = Primus.Events
local Debug  = Primus.Debug
local Memory = Primus.Memory
local Utils  = Primus.Utils

-- Registries
local eventListeners   = {} -- [event] = { {owner, callback}, ... }
local signalListeners  = {} -- [signal] = { {owner, callback}, ... }
local hookedFunctions  = {} -- [targetTable_method] = originalFunc

-- Central Event Dispatcher Frame
local eventFrame = CreateFrame("Frame", "Primus_EventFrame")

local function Master_OnEvent()
    local event = event
    local listeners = eventListeners[event]
    if not listeners then return end

    local count = table.getn(listeners)
    for i = 1, count do
        local entry = listeners[i]
        if entry and entry.callback then
            if entry.owner then
                Debug:SafeCall(entry.callback, entry.owner, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
            else
                Debug:SafeCall(entry.callback, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
            end
        end
    end
end

eventFrame:SetScript("OnEvent", Master_OnEvent)

-- Register for a native WoW Event
function Events:Register(event, owner, callback)
    if not event or not callback then return end
    event = string.upper(event)

    if not eventListeners[event] then
        eventListeners[event] = {}
        eventFrame:RegisterEvent(event)
    end

    local list = eventListeners[event]
    -- Check if already registered
    for i = 1, table.getn(list) do
        if list[i].owner == owner and list[i].callback == callback then
            return
        end
    end

    table.insert(list, { owner = owner, callback = callback })
end

-- Unregister a native WoW Event for an owner
function Events:Unregister(event, owner)
    if not event or not eventListeners[event] then return end
    event = string.upper(event)

    local list = eventListeners[event]
    local i = 1
    while i <= table.getn(list) do
        if list[i].owner == owner then
            table.remove(list, i)
        else
            i = i + 1
        end
    end

    if table.getn(list) == 0 then
        eventListeners[event] = nil
        eventFrame:UnregisterEvent(event)
    end
end

-- Unregister all events and signals bound to an owner (Clean Lifecycle cleanup)
function Events:UnregisterAll(owner)
    if not owner then return end

    -- Cleanup native events
    for event, list in pairs(eventListeners) do
        local i = 1
        while i <= table.getn(list) do
            if list[i].owner == owner then
                table.remove(list, i)
            else
                i = i + 1
            end
        end
        if table.getn(list) == 0 then
            eventListeners[event] = nil
            eventFrame:UnregisterEvent(event)
        end
    end

    -- Cleanup custom signals
    for signal, list in pairs(signalListeners) do
        local i = 1
        while i <= table.getn(list) do
            if list[i].owner == owner then
                table.remove(list, i)
            else
                i = i + 1
            end
        end
        if table.getn(list) == 0 then
            signalListeners[signal] = nil
        end
    end
end

Events.UnregisterOwner = Events.UnregisterAll


-- =========================================================================
-- CUSTOM SIGNAL / MESSAGE BUS (Inter-Module Communication)
-- =========================================================================

function Events:Listen(signal, owner, callback)
    if not signal or not callback then return end
    signal = string.upper(signal)

    if not signalListeners[signal] then
        signalListeners[signal] = {}
    end

    table.insert(signalListeners[signal], { owner = owner, callback = callback })
end

function Events:Fire(signal, a1, a2, a3, a4, a5)
    if not signal or not signalListeners[signal] then return end
    signal = string.upper(signal)

    local list = signalListeners[signal]
    local count = table.getn(list)
    for i = 1, count do
        local entry = list[i]
        if entry and entry.callback then
            if entry.owner then
                Debug:SafeCall(entry.callback, entry.owner, a1, a2, a3, a4, a5)
            else
                Debug:SafeCall(entry.callback, a1, a2, a3, a4, a5)
            end
        end
    end
end

-- =========================================================================
-- FUNCTION & SCRIPT HOOKING
-- =========================================================================

-- Safely hook a global or table function without breaking existing returns
function Events:Hook(targetTable, methodName, hookFunc)
    if type(targetTable) == "string" then
        hookFunc = methodName
        methodName = targetTable
        targetTable = _G
    end

    if not targetTable or not methodName or type(targetTable[methodName]) ~= "function" or not hookFunc then
        Debug:Warn("Events", "Cannot hook nil or non-function: " .. tostring(methodName))
        return false
    end

    targetTable._primusHooks = targetTable._primusHooks or {}
    targetTable._primusHooks[methodName] = targetTable._primusHooks[methodName] or {}

    local hooks = targetTable._primusHooks[methodName]
    for i = 1, table.getn(hooks) do
        if hooks[i] == hookFunc then
            return true
        end
    end
    table.insert(hooks, hookFunc)

    if not targetTable._primusHookInstalled or not targetTable._primusHookInstalled[methodName] then
        targetTable._primusHookInstalled = targetTable._primusHookInstalled or {}
        targetTable._primusHookInstalled[methodName] = true

        local orig = targetTable[methodName]
        targetTable[methodName] = function(a1, a2, a3, a4, a5, a6, a7, a8)
            if methodName == "SetHyperlink" and type(a2) == "string" then
                local _, _, clean = string.find(a2, "|H(.-)|h")
                if clean then a2 = clean end
            end
            local r1, r2, r3, r4
            if orig then
                r1, r2, r3, r4 = orig(a1, a2, a3, a4, a5, a6, a7, a8)
            end
            local currentHooks = targetTable._primusHooks and targetTable._primusHooks[methodName]
            if currentHooks then
                local hCount = table.getn(currentHooks)
                for h = 1, hCount do
                    Debug:SafeCall(currentHooks[h], a1, a2, a3, a4, a5, a6, a7, a8)
                end
            end
            return r1, r2, r3, r4
        end
    end

    return true
end

-- Safely hook a Frame script handler (OnShow, OnClick, etc.)
function Events:HookScript(frame, scriptName, hookFunc)
    if not frame or not frame.GetScript or not frame.SetScript or not hookFunc then return false end

    frame._primusHooks = frame._primusHooks or {}
    frame._primusHooks[scriptName] = frame._primusHooks[scriptName] or {}

    local hooks = frame._primusHooks[scriptName]
    for i = 1, table.getn(hooks) do
        if hooks[i] == hookFunc then
            return true
        end
    end
    table.insert(hooks, hookFunc)

    if not frame._primusHookInstalled or not frame._primusHookInstalled[scriptName] then
        frame._primusHookInstalled = frame._primusHookInstalled or {}
        frame._primusHookInstalled[scriptName] = true

        local orig = frame:GetScript(scriptName)
        frame:SetScript(scriptName, function(a1, a2, a3, a4, a5)
            local currentHooks = frame._primusHooks and frame._primusHooks[scriptName]
            if currentHooks then
                local hCount = table.getn(currentHooks)
                for h = 1, hCount do
                    Debug:SafeCall(currentHooks[h], a1, a2, a3, a4, a5)
                end
            end
            if orig then
                orig(a1, a2, a3, a4, a5)
            end
        end)
    end
    return true
end
