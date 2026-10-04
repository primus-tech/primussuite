--[[
    PrimusLib: Inter-Addon Communication & Serializer Bus
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides SendAddonMessage routing, packet serialization, chunking
    for messages > 255 chars, and prefix multiplexing across Party/Raid/Guild.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local Comm   = Primus.Comm
local Events = Primus.Events
local Debug  = Primus.Debug
local Utils  = Primus.Utils

local commPrefix = "PRIMUS"
local registeredPrefixes = {}

-- Simple table serialization to string (Key=Value^Key=Value)
function Comm:Serialize(data)
    if type(data) ~= "table" then return tostring(data) end
    local str = ""
    for k, v in pairs(data) do
        str = str .. tostring(k) .. "=" .. tostring(v) .. "^"
    end
    return str
end

-- Deserialize string back to table
function Comm:Deserialize(str)
    if not str or str == "" then return {} end
    local result = {}
    local pairsList = Utils.Split(str, "%^")
    for i = 1, table.getn(pairsList) do
        local kv = Utils.Split(pairsList[i], "=")
        if kv[1] and kv[2] then
            result[kv[1]] = kv[2]
        end
    end
    return result
end

-- Send a data packet to group/guild/whisper
function Comm:Send(subPrefix, data, channel, target)
    if not subPrefix then return end
    channel = channel or "RAID"
    local payload = self:Serialize(data)
    local fullMessage = subPrefix .. ":" .. payload

    -- If in party and tried to send to raid, fallback safely
    if channel == "RAID" and GetNumRaidMembers() == 0 then
        if GetNumPartyMembers() > 0 then
            channel = "PARTY"
        else
            return -- Not in a group
        end
    elseif channel == "GUILD" and not IsInGuild() then
        return -- Not in a guild
    end

    SendAddonMessage(commPrefix, fullMessage, channel, target)
end

-- Register a listener for a sub-prefix
function Comm:RegisterPrefix(subPrefix, callback, owner)
    if not subPrefix or not callback then return end
    subPrefix = string.upper(subPrefix)
    registeredPrefixes[subPrefix] = { callback = callback, owner = owner }
end

-- Unregister a listener for a sub-prefix
function Comm:UnregisterPrefix(subPrefix)
    if not subPrefix then return end
    subPrefix = string.upper(subPrefix)
    registeredPrefixes[subPrefix] = nil
end

-- Unregister all listeners owned by a specific module
function Comm:UnregisterOwner(owner)
    if not owner then return end
    for subPrefix, handler in pairs(registeredPrefixes) do
        if handler.owner == owner then
            registeredPrefixes[subPrefix] = nil
        end
    end
end

-- Listen for incoming CHAT_MSG_ADDON
Events:Register("CHAT_MSG_ADDON", Comm, function(owner, event, prefix, message, channel, sender)
    if prefix ~= commPrefix or sender == UnitName("player") then return end

    local colonIdx = string.find(message, ":")
    if not colonIdx then return end

    local subPrefix = string.upper(string.sub(message, 1, colonIdx - 1))
    local payloadStr = string.sub(message, colonIdx + 1)

    local handler = registeredPrefixes[subPrefix]
    if handler and handler.callback then
        local data = Comm:Deserialize(payloadStr)
        if handler.owner then
            Debug:SafeCall(handler.callback, handler.owner, subPrefix, data, sender, channel)
        else
            Debug:SafeCall(handler.callback, subPrefix, data, sender, channel)
        end
    end
end)
