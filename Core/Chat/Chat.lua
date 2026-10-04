--[[
    PrimusUI Core Subsystem: Primus.Chat (Universal Chat Ingestion & Message Pipeline)
    Target: Vanilla WoW 1.12.1 (Client Build 5875 | Interface 11200 | Lua 5.0.2)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims, Single Domain Owner)
    
    Centralizes all CHAT_MSG_* event ingestion into a single master dispatcher.
    Parses and sanitizes incoming chat messages once into a recycled message object,
    then dispatches structured data to subscribed consumers (PUITalk, PUILogViewer,
    PUIListener, PUIElephant, PUIEmotes) with zero multi-hook string churn.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local Chat = Primus.Chat or {}
Primus.Chat = Chat
_G.PrimusChat = Chat

local Events = Primus.Events
local Utils  = Primus.Utils

-- =========================================================================
-- CONSUMER REGISTRY
-- =========================================================================

local consumers = {} -- array of { id = id, priority = priority, callback = fn }
local isSorted = false

function Chat:RegisterConsumer(id, priority, callback)
    if not id or not callback then return end
    priority = priority or 50

    -- Remove existing consumer if registered
    self:UnregisterConsumer(id)

    table.insert(consumers, {
        id = id,
        priority = priority,
        callback = callback,
    })
    isSorted = false
end

function Chat:UnregisterConsumer(id)
    if not id then return end
    local count = table.getn(consumers)
    for i = 1, count do
        if consumers[i] and consumers[i].id == id then
            table.remove(consumers, i)
            break
        end
    end
end

-- =========================================================================
-- URL EXTRACTION PATTERNS (Lua 5.0.2 Regex)
-- =========================================================================

local URL_PATTERNS = {
    "https?://%S+",
    "www%.%S+",
    "discord%.gg/%S+",
    "discord%.com/%S+",
    "twitch%.tv/%S+",
    "youtube%.com/%S+",
    "youtu%.be/%S+",
    "imgur%.com/%S+",
    "carrd%.co/%S+",
    "toyhou%.se/%S+",
    "github%.com/%S+",
    "spotify%.com/%S+",
    "soundcloud%.com/%S+",
}

local function ExtractURLsFromText(text)
    if not text or text == "" then return nil end
    local clean = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    clean = string.gsub(clean, "|r", "")
    clean = string.gsub(clean, "|H.-|h(.-)|h", "%1")

    local found = nil
    for _, pat in ipairs(URL_PATTERNS) do
        for url in string.gfind(clean, pat) do
            url = string.gsub(url, "[%.,!%?)%]\"]+$", "")
            if not found then found = {} end
            table.insert(found, url)
        end
    end
    return found
end

-- =========================================================================
-- MESSAGE RECYCLING & DISPATCH
-- =========================================================================

local recycledMsgObj = {}

local function BuildMessageObject(event, text, sender, lang, channelName, target, flags, zoneID, channelNumber, channelNameBase)
    recycledMsgObj.event = event
    recycledMsgObj.text = text or ""
    recycledMsgObj.message = text or ""
    recycledMsgObj.sender = sender or ""
    recycledMsgObj.lang = lang or ""
    recycledMsgObj.channel = channelName or ""
    recycledMsgObj.channelName = channelName or ""
    recycledMsgObj.channelNameBase = channelNameBase or channelName or ""
    recycledMsgObj.channelNumber = tonumber(channelNumber) or 0
    recycledMsgObj.target = target or ""
    recycledMsgObj.flags = flags or ""
    recycledMsgObj.zoneID = zoneID or 0
    recycledMsgObj.time = time()
    recycledMsgObj.timeShort = date("%H:%M")
    recycledMsgObj.timeFull = date("%H:%M:%S")
    recycledMsgObj.type = string.gsub(event or "", "^CHAT_MSG_", "")

    -- Detect Category
    if event == "CHAT_MSG_SAY" or event == "CHAT_MSG_YELL" or event == "CHAT_MSG_EMOTE" or event == "CHAT_MSG_TEXT_EMOTE" then
        recycledMsgObj.category = "RP"
        recycledMsgObj.isIC = true
    elseif event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_WHISPER_INFORM" then
        recycledMsgObj.category = "WHISPER"
        recycledMsgObj.isIC = false
    elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" or event == "CHAT_MSG_RAID_WARNING" or event == "CHAT_MSG_BATTLEGROUND" or event == "CHAT_MSG_BATTLEGROUND_LEADER" then
        recycledMsgObj.category = "GROUP"
        recycledMsgObj.isIC = false
    elseif event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER" then
        recycledMsgObj.category = "GUILD"
        recycledMsgObj.isIC = false
    elseif event == "CHAT_MSG_CHANNEL" then
        recycledMsgObj.category = "CHANNEL"
        recycledMsgObj.isIC = false
    elseif event == "CHAT_MSG_LOOT" or event == "CHAT_MSG_MONEY" then
        recycledMsgObj.category = "LOOT"
        recycledMsgObj.isIC = false
    else
        recycledMsgObj.category = "SYSTEM"
        recycledMsgObj.isIC = false
    end

    -- Pre-extract URLs
    recycledMsgObj.urls = ExtractURLsFromText(recycledMsgObj.text)

    return recycledMsgObj
end

function Chat:Dispatch(event, text, sender, lang, channelName, target, flags, zoneID, channelNumber, channelNameBase)
    if not isSorted then
        table.sort(consumers, function(a, b)
            return a.priority < b.priority
        end)
        isSorted = true
    end

    local msgObj = BuildMessageObject(event, text, sender, lang, channelName, target, flags, zoneID, channelNumber, channelNameBase)

    local count = table.getn(consumers)
    for i = 1, count do
        local c = consumers[i]
        if c and c.callback then
            local ok, err = pcall(c.callback, msgObj)
            if not ok and _G.DEFAULT_CHAT_FRAME then
                -- Silent protection against broken consumers
            end
        end
    end
end

-- =========================================================================
-- MASTER EVENT REGISTRATION
-- =========================================================================

local CHAT_EVENTS = {
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_EMOTE",
    "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_CHANNEL_NOTICE",
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_SYSTEM",
    "CHAT_MSG_LOOT",
    "CHAT_MSG_MONEY",
    "CHAT_MSG_SKILL",
    "CHAT_MSG_SPELL_TRADESKILLS",
    "CHAT_MSG_COMBAT_XP_GAIN",
    "CHAT_MSG_COMBAT_HONOR_GAIN",
    "CHAT_MSG_COMBAT_FACTION_CHANGE",
    "CHAT_MSG_COMBAT_MISC_INFO",
    "CHAT_MSG_OPENING",
    "CHAT_MSG_PET_INFO",
    "CHAT_MSG_BATTLEGROUND",
    "CHAT_MSG_BATTLEGROUND_LEADER",
    "CHAT_MSG_BG_SYSTEM_NEUTRAL",
    "CHAT_MSG_BG_SYSTEM_ALLIANCE",
    "CHAT_MSG_BG_SYSTEM_HORDE",
    "CHAT_MSG_MONSTER_SAY",
    "CHAT_MSG_MONSTER_YELL",
    "CHAT_MSG_MONSTER_EMOTE",
    "CHAT_MSG_MONSTER_WHISPER",
    "CHAT_MSG_RAID_BOSS_EMOTE",
    "CHAT_MSG_RAID_BOSS_WHISPER",
    "CHAT_MSG_IGNORED",
    "CHAT_MSG_FILTERED",
}

function Chat:Initialize()
    if self.initialized then return end
    self.initialized = true

    if Events and Events.Register then
        local count = table.getn(CHAT_EVENTS)
        for i = 1, count do
            local evt = CHAT_EVENTS[i]
            Events:Register(evt, "PrimusChat", function(owner, event, msg, sender, lang, channelName, target, flags, zoneID, channelNumber, channelNameBase)
                Chat:Dispatch(event, msg, sender, lang, channelName, target, flags, zoneID, channelNumber, channelNameBase)
            end)
        end
    end
end

-- Initialize on file load
Chat:Initialize()
