--[[
    PrimusUI: PUIRoleplay Comms Engine (PUIComms.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (Multi-Channel OWPRP, TTRP, xtensionxtooltip2, MyRolePlay)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIRoleplay = Primus.PUIRoleplay or {}
Primus.PUIRoleplay = PUIRoleplay

local Comms = {}
PUIRoleplay.Comms = Comms

local minChatLevel = 1
local timeBetweenPings = 30

-- Active Channels Matrix
local primaryChannel = "OWPRP"
local fallbackChannels = { "TTRP", "xtensionxtooltip2", "MyRolePlay" }

-- Throttling & Deduplication State
local lastRequestTimes = {}
local lastDataSentTime = {}
local globalLastSendTime = 0
local lastPingSentTime = 0

--------------------------------------------------------------------------------
-- Multi-Channel Resolver & Verification
--------------------------------------------------------------------------------
function Comms:GetChannelID(name)
    if not name then return nil end
    local num = GetChannelName(name)
    if num and num > 0 then return num end
    num = GetChannelName(string.lower(name))
    if num and num > 0 then return num end

    local chanList = { GetChannelList() }
    local count = table.getn(chanList)
    for i = 1, count, 2 do
        if string.lower(tostring(chanList[i+1] or "")) == string.lower(name) then
            return tonumber(chanList[i])
        end
    end
    return nil
end

function Comms:CanChat(targetChannel)
    if (UnitLevel("player") or 0) < minChatLevel then
        return false
    end
    if targetChannel then
        local id = self:GetChannelID(targetChannel)
        return (id and id > 0)
    end
    if self:GetChannelID(primaryChannel) then return true end
    for _, ch in ipairs(fallbackChannels) do
        if self:GetChannelID(ch) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Channel Sending via ChatThrottleLib or Native Fallback
--------------------------------------------------------------------------------
function Comms:SendToChannel(channel, message, priority)
    local chanNumber = self:GetChannelID(channel)
    if not chanNumber or chanNumber == 0 then return end

    local encoded = PUIRoleplay.Protocols and PUIRoleplay.Protocols:DrunkEncode(message) or message
    local prio = priority or "BULK"
    if _G.ChatThrottleLib then
        _G.ChatThrottleLib:SendChatMessage(prio, channel, encoded, "CHANNEL", nil, chanNumber)
    else
        SendChatMessage(encoded, "CHANNEL", nil, chanNumber)
    end
end

function Comms:SendBroadcastMessage(message, priority)
    if not self:CanChat() then return end

    if self:GetChannelID(primaryChannel) then
        self:SendToChannel(primaryChannel, message, priority)
    end

    if self:GetChannelID("TTRP") then
        self:SendToChannel("TTRP", message, priority)
    end
end

--------------------------------------------------------------------------------
-- Channel Handshake & Join All Multi-Channels
--------------------------------------------------------------------------------
function Comms:JoinRPChannel()
    if (UnitLevel("player") or 0) < minChatLevel then
        return
    end

    local allChannels = { primaryChannel, "TTRP", "xtensionxtooltip2", "MyRolePlay" }
    for _, ch in ipairs(allChannels) do
        if not self:GetChannelID(ch) then
            JoinChannelByName(ch)
        end
    end

    Primus.Time:After(3.0, function()
        if Comms:CanChat() then
            Comms:SendPing("A")
        end
    end, PUIRoleplay)
end

--------------------------------------------------------------------------------
-- Presence Pings (P & A)
--------------------------------------------------------------------------------
function Comms:SendPing(pingType)
    if not self:CanChat() then return end

    local curTime = time()
    if (curTime - lastPingSentTime) < 15 and pingType == "P" then
        return
    end
    lastPingSentTime = curTime

    local pType = pingType or "P"
    local zoneText = GetZoneText() or ""
    local msg = pType .. zoneText

    local settings = PUIRoleplay:GetSettings() or {}
    if settings and (settings.share_location == "1" or settings.share_location == 1 or settings.share_location == true) then
        local x, y = GetPlayerMapPosition("player")
        if x and y and (x > 0 or y > 0) then
            local posX = math.floor(x * 10000) / 10000
            local posY = math.floor(y * 10000) / 10000
            msg = msg .. "~" .. posX .. "~" .. posY .. "~1.2.0"
        else
            msg = msg .. "~false~false~1.2.0"
        end
    else
        msg = msg .. "~false~false~1.2.0"
    end

    self:SendBroadcastMessage(msg, "NORMAL")
end

function Comms:StartPingTicker()
    Primus.Time:Every(timeBetweenPings, function()
        if Comms:CanChat() then
            Comms:SendPing("P")
        end
    end, PUIRoleplay)
end

--------------------------------------------------------------------------------
-- Request Dispatcher (M, T, D, L, X)
--------------------------------------------------------------------------------
function Comms:SendRequest(requestType, playerName)
    if not self:CanChat() or not playerName or playerName == "" or playerName == UnitName("player") then
        return
    end

    local curTime = time()
    if (curTime - globalLastSendTime) < 1.5 then
        return
    end

    local reqKey = playerName .. "_" .. requestType
    if lastRequestTimes[reqKey] and (curTime - lastRequestTimes[reqKey]) < 30 then
        return
    end

    lastRequestTimes[reqKey] = curTime
    globalLastSendTime = curTime

    local charInfo = PUIRoleplay:GetCharacterData(playerName)
    local key = charInfo and charInfo["key" .. requestType]
    local packet = requestType .. ":" .. playerName .. "~" .. (key and key ~= "" and key or "NO_KEY")
    self:SendBroadcastMessage(packet, "BULK")
end

--------------------------------------------------------------------------------
-- Chunking & Transmitting Outbound Data
--------------------------------------------------------------------------------
function Comms:SendData(dataPrefix)
    local curTime = time()
    if lastDataSentTime[dataPrefix] and (curTime - lastDataSentTime[dataPrefix]) < 3 then
        return
    end
    lastDataSentTime[dataPrefix] = curTime

    local payload = PUIRoleplay.Protocols:BuildPayload(dataPrefix)
    local myInfo = PUIRoleplay:GetMyProfile()
    local myKey = myInfo["key" .. dataPrefix] or "PUI10"

    local splitLength = 200
    local totalLen = string.len(payload)
    local numChunks = math.ceil(totalLen / splitLength)
    if numChunks == 0 then numChunks = 1 end

    local chunks = {}
    for i = 1, numChunks do
        local startIdx = (i - 1) * splitLength + 1
        local endIdx = i * splitLength
        if endIdx > totalLen then endIdx = totalLen end
        chunks[i] = string.sub(payload, startIdx, endIdx)
    end

    local totalChunks = table.getn(chunks)
    for i = 1, totalChunks do
        local packet = dataPrefix .. "R:p~" .. myKey .. "~" .. i .. "~" .. totalChunks .. "~" .. chunks[i]
        self:SendBroadcastMessage(packet, "BULK")
    end
end

--------------------------------------------------------------------------------
-- Inbound Packet Routing & Reassembly
--------------------------------------------------------------------------------
local msgSplitTable = {}
local pingSplitTable = {}

function Comms:OnChatMessage(msg, sender)
    if not msg or not sender or sender == "" then return end

    local decoded = PUIRoleplay.Protocols and PUIRoleplay.Protocols:DrunkDecode(msg) or msg
    local colonStart = string.find(decoded, ":")

    if colonStart then
        local dataPrefix = string.sub(decoded, 1, colonStart - 1)
        local tildeStart = string.find(decoded, "~", colonStart)

        if tildeStart then
            local targetName = string.sub(decoded, colonStart + 1, tildeStart - 1)

            if targetName == UnitName("player") then
                if self:CanChat() and (dataPrefix == "M" or dataPrefix == "T" or dataPrefix == "D" or dataPrefix == "L" or dataPrefix == "X" or dataPrefix == "P") then
                    local myInfo = PUIRoleplay:GetMyProfile()
                    local keyFromMsg = string.sub(decoded, tildeStart + 1)
                    local myKey = myInfo["key" .. dataPrefix]

                    if keyFromMsg == "NO_KEY" or keyFromMsg ~= myKey then
                        self:SendData(dataPrefix)
                    end
                end
            elseif (targetName == "p" or string.sub(dataPrefix, -1) == "R") and (dataPrefix == "MR" or dataPrefix == "TR" or dataPrefix == "DR" or dataPrefix == "LR" or dataPrefix == "XR" or dataPrefix == "PR") then
                self:ProcessResponse(dataPrefix, sender, decoded)
            end
        end
    else
        local firstChar = string.sub(decoded, 1, 1)
        if firstChar == "P" or firstChar == "A" then
            self:ProcessPing(sender, decoded)
        end
    end
end

function Comms:ProcessResponse(dataPrefix, sender, msg)
    local tildePos = string.find(msg, "~")
    if not tildePos then return end

    local dataSlice = string.sub(msg, tildePos)
    local parts = PUIRoleplay.Protocols:SplitString(dataSlice, "~", msgSplitTable)

    local key = parts[2]
    local chunkIdx = tonumber(parts[3])
    local totalChunks = tonumber(parts[4])

    if not key or key == "" or not chunkIdx or not totalChunks then
        return
    end

    local charData = PUIRoleplay:GetOrCreateCharacterData(sender)
    if not charData["temp" .. dataPrefix] or chunkIdx == 1 then
        charData["temp" .. dataPrefix] = key .. "~"
    end

    local totalParts = table.getn(parts)
    local chunkPayload = ""
    for i = 5, totalParts do
        chunkPayload = chunkPayload .. (parts[i] or "") .. (i == totalParts and "" or "~")
    end
    charData["temp" .. dataPrefix] = (charData["temp" .. dataPrefix] or "") .. chunkPayload

    if chunkIdx == totalChunks then
        local rawJoined = charData["temp" .. dataPrefix]
        local tokens = PUIRoleplay.Protocols:SplitString(rawJoined, "~", {})
        PUIRoleplay.Protocols:ParsePayload(dataPrefix, tokens, sender, charData)
        charData["temp" .. dataPrefix] = nil
        PUIRoleplay:OnDataReceived(dataPrefix, sender)
    end
end

function Comms:ProcessPing(sender, msg)
    if not sender or sender == "" or sender == UnitName("player") then return end

    local zoneText = string.sub(msg, 2)
    if PUIRoleplay.Protocols and PUIRoleplay.Protocols.DrunkDecode then
        zoneText = PUIRoleplay.Protocols:DrunkDecode(zoneText)
    end

    PUIRoleplay:RecordQueryablePlayer(sender)

    local charData = PUIRoleplay:GetOrCreateCharacterData(sender)
    local strs = PUIRoleplay.Protocols:SplitString(zoneText, "~", pingSplitTable)
    if table.getn(strs) >= 3 then
        charData["zone"] = strs[1] or ""
        charData["zoneX"] = strs[2] or ""
        charData["zoneY"] = strs[3] or ""
    else
        charData["zone"] = zoneText
    end

    PUIRoleplay:OnPingReceived(sender)
end
