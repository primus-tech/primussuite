--[[
    PrimusUI Module: PUITalk (Core State, Cache & String Utilities)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    - Shared module state and database namespace registration.
    - Player class caching and class color string formatting.
    - Chat cleaning, timestamp generation, channel coloring, and URL linkification.
    - Unread state tracking, conversation management, and roster lookup for tab-completion.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUITalk = Primus.PUITalk or {}
Primus.PUITalk = PUITalk
_G.PUITalk = PUITalk
Primus:RegisterModule("PUITalk", PUITalk, "Social")

local DB    = Primus.DB
local Utils = Primus.Utils

-- Database Namespace
PUITalk.db = DB:RegisterNamespace("PUITalk", {
    enabled          = true,
    divertWhispers   = true,   -- Suppresses whispers from main chat log and routes to Tab 2
    autoPopDMs       = false,  -- Automatically switch to Tab 2 on incoming whisper
    playSounds       = true,   -- Sound alerts on incoming direct messages
    classColors      = true,   -- Class colored player names
    stickyChannels   = true,   -- Sticky chat channels across /say, /guild, /party, /raid
    mousewheelScroll = true,   -- Mousewheel fast scrolling on chat frames
    chatCopy         = true,   -- In-place selection and clipboard copy tools
    activeMasterTab  = 1,      -- 1: Chat, 2: Messages, 3: Social
    activeSocialTab  = "friends", -- "friends" or "guild"
    width            = 450,
    height           = 230,
    channels         = {
        SAY          = true,
        YELL         = true,
        EMOTE        = true,
        PARTY        = true,
        RAID         = true,
        GUILD        = true,
        OFFICER      = true,
        GENERAL      = true,
        TRADE        = true,
        LOCALDEFENSE = true,
        LFG          = true,
        WORLD        = true,
        SYSTEM       = true,
        SKILL        = true,
        COMBAT_INFO  = true,
        MONSTER      = true,
        LOOT         = true,
    },
    customChannelList = { "World" },
})

function PUITalk:IsChannelEnabled(chanKey)
    local ch = self.db:Get("channels")
    if not ch then return true end
    if ch[chanKey] ~= nil then
        return ch[chanKey]
    end
    -- For custom channels, inherit master WORLD setting if not individually set
    if string.sub(chanKey, 1, 7) == "CUSTOM_" then
        if ch.WORLD ~= nil then return ch.WORLD end
        return true
    end
    return true
end

function PUITalk:SetChannelEnabled(chanKey, enabled)
    local ch = self.db:Get("channels") or {}
    ch[chanKey] = enabled
    self.db:Set("channels", ch)
end

function PUITalk:RegisterJoinedChannel(channelName)
    if not channelName or channelName == "" then return end
    local cleanName = channelName
    local dashPos = string.find(channelName, " %- ")
    if dashPos then
        cleanName = string.sub(channelName, 1, dashPos - 1)
    end
    local lower = string.lower(cleanName)
    if lower == "general" or lower == "trade" or lower == "localdefense" or lower == "lookingforgroup" or lower == "guildrecruitment" then
        return
    end

    local list = self.db:Get("customChannelList") or {}
    local found = false
    for _, name in ipairs(list) do
        if string.lower(name) == lower then
            found = true
            break
        end
    end
    if not found then
        table.insert(list, cleanName)
        self.db:Set("customChannelList", list)
    end

    if self.RefreshCustomChannelMenu then
        self:RefreshCustomChannelMenu()
    end
end

function PUITalk:UnregisterLeftChannel(channelName)
    if not channelName or channelName == "" then return end
    if self.RefreshCustomChannelMenu then
        self:RefreshCustomChannelMenu()
    end
end

function PUITalk:GetNonBasicChannels()
    local result = {}
    local seen = {}
    local chanList = { GetChannelList() }

    if chanList and table.getn(chanList) > 0 then
        for i = 1, table.getn(chanList), 2 do
            local num = tonumber(chanList[i]) or 0
            local rawName = tostring(chanList[i+1] or "")
            local cleanName = rawName
            local dashPos = string.find(rawName, " %- ")
            if dashPos then
                cleanName = string.sub(rawName, 1, dashPos - 1)
            end
            local lowerClean = string.lower(cleanName)

            local isBasic = false
            if num == 1 or num == 2 or num == 3 or num == 4 then
                isBasic = true
            elseif lowerClean == "general" or lowerClean == "trade" or lowerClean == "localdefense" or lowerClean == "lookingforgroup" or lowerClean == "guildrecruitment" then
                isBasic = true
            end

            if not isBasic and cleanName ~= "" and not seen[lowerClean] then
                seen[lowerClean] = true
                table.insert(result, {
                    num = num,
                    name = cleanName,
                    rawName = rawName,
                    key = "CUSTOM_" .. lowerClean,
                    isJoined = true,
                })
            end
        end
    end

    local savedChannels = self.db:Get("customChannelList") or {}
    for _, chName in ipairs(savedChannels) do
        local lower = string.lower(chName)
        if not seen[lower] then
            seen[lower] = true
            local num = GetChannelName(chName)
            local isJoined = (num and num > 0)
            table.insert(result, {
                num = isJoined and num or 0,
                name = chName,
                rawName = chName,
                key = "CUSTOM_" .. lower,
                isJoined = isJoined,
            })
        end
    end

    if not seen["world"] then
        local num = GetChannelName("world")
        local isJoined = (num and num > 0)
        table.insert(result, {
            num = isJoined and num or 0,
            name = "World",
            rawName = "World",
            key = "CUSTOM_world",
            isJoined = isJoined,
        })
    end

    return result
end

-- Shared State
PUITalk.playerClassCache    = {}
PUITalk.chatBuffers         = {}
PUITalk.dmTabs              = {}
PUITalk.activeDMKey         = nil
PUITalk.conversationHistory  = {}
PUITalk.unreadCounts        = {}
PUITalk.lastWhisperSender   = nil
PUITalk.friendRows          = {}
PUITalk.guildRows           = {}
PUITalk.copyButtons         = {}

for i = 1, 7 do
    PUITalk.chatBuffers[i] = {}
end

-- =========================================================================
-- UNREAD STATE MANAGEMENT & CONVERSATIONS
-- =========================================================================

function PUITalk:GetTotalUnreadCount()
    local total = 0
    for k, count in pairs(self.unreadCounts) do
        if count and count > 0 then
            total = total + count
        end
    end
    return total
end

function PUITalk:GetUnreadCount(key)
    if not key then return 0 end
    return self.unreadCounts[string.lower(key)] or 0
end

function PUITalk:IncrementUnread(key)
    if not key then return end
    key = string.lower(key)
    self.unreadCounts[key] = (self.unreadCounts[key] or 0) + 1
    if self.dmTabs[key] then
        self.dmTabs[key].unread = self.unreadCounts[key]
    end
end

function PUITalk:MarkAsRead(key)
    if not key then return end
    key = string.lower(key)
    self.unreadCounts[key] = 0
    if self.dmTabs[key] then
        self.dmTabs[key].unread = 0
    end
end

function PUITalk:ClearDMHistory(key)
    if not key then return end
    key = string.lower(key)
    self.conversationHistory[key] = {}
    if self.masterFrame and self.masterFrame.viewMessages and (self.activeDMKey == key) then
        self.masterFrame.viewMessages.msgFrame:Clear()
    end
end

function PUITalk:CloseDMConversation(key)
    if not key then return end
    key = string.lower(key)
    self:MarkAsRead(key)
    if self.dmTabs[key] then
        if self.dmTabs[key].button then
            self.dmTabs[key].button:Hide()
            self.dmTabs[key].button = nil
        end
        self.dmTabs[key] = nil
    end

    if self.activeDMKey == key then
        self.activeDMKey = nil
        for nextKey, _ in pairs(self.dmTabs) do
            self:SelectDMTab(nextKey)
            return
        end
        if self.masterFrame and self.masterFrame.viewMessages then
            self.masterFrame.viewMessages.msgFrame:Clear()
        end
    end
    if self.RefreshDMTabs then
        self:RefreshDMTabs()
    end
end

-- =========================================================================
-- ROSTER NAMES & CLASS CACHE
-- =========================================================================

function PUITalk:GetRosterNames()
    local names = {}
    local seen = {}

    local function add(n)
        if n and n ~= "" and not seen[n] then
            seen[n] = true
            table.insert(names, n)
        end
    end

    local numFriends = GetNumFriends()
    for i = 1, numFriends do
        local n, _, _, _, connected = GetFriendInfo(i)
        if connected and n then add(n) end
    end

    if IsInGuild() then
        local numGuild = GetNumGuildMembers()
        for i = 1, numGuild do
            local n, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
            if online and n then add(n) end
        end
    end

    for i = 1, 4 do
        if UnitExists("party" .. i) then add(UnitName("party" .. i)) end
    end
    local numRaid = GetNumRaidMembers()
    for i = 1, numRaid do
        if UnitExists("raid" .. i) then add(UnitName("raid" .. i)) end
    end

    return names
end

local function CacheUnitClass(unit)
    if not UnitExists(unit) then return end
    local name = UnitName(unit)
    local _, class = UnitClass(unit)
    if name and class then
        PUITalk.playerClassCache[name] = class
    end
end

function PUITalk:UpdateClassCache()
    CacheUnitClass("player")
    CacheUnitClass("target")

    for i = 1, 4 do
        CacheUnitClass("party" .. i)
    end

    local numRaid = GetNumRaidMembers()
    for i = 1, numRaid do
        CacheUnitClass("raid" .. i)
    end

    if IsInGuild() then
        local numGuild = GetNumGuildMembers()
        for i = 1, numGuild do
            local name, _, _, _, class = GetGuildRosterInfo(i)
            if name and class then
                PUITalk.playerClassCache[name] = class
            end
        end
    end

    local numFriends = GetNumFriends()
    for i = 1, numFriends do
        local name, _, class = GetFriendInfo(i)
        if name and class then
            PUITalk.playerClassCache[name] = class
        end
    end
end

-- =========================================================================
-- CLASS COLORING & STRING UTILITIES
-- =========================================================================

function PUITalk:GetColoredName(name)
    if not name or not self.db:Get("classColors") then return name end
    local class = self.playerClassCache[name]
    if class then
        local r, g, b = Utils.GetClassColor(class)
        local hex = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
        return string.format("|cff%s%s|r", hex, name)
    end
    return name
end

function PUITalk:CleanChatText(str)
    if not str then return "" end
    str = string.gsub(str, "|H.-|h(.-)|h", "%1")
    str = string.gsub(str, "|c%x%x%x%x%x%x%x%x", "")
    str = string.gsub(str, "|r", "")
    return str
end

function PUITalk:LinkifyURLs(text)
    if not text then return text end
    local patterns = {
        "(https?://%S+)",
        "(www%.%S+)",
        "(discord%.gg/%S+)",
        "(github%.com/%S+)",
    }
    for _, pat in ipairs(patterns) do
        text = string.gsub(text, pat, "|cff69ccf0|Hurl:%1|h[%1]|h|r")
    end
    return text
end

function PUITalk:GetTimestamp()
    local hour, minute = GetGameTime()
    return string.format("[%02d:%02d]", hour, minute)
end

PUITalk.CHANNEL_COLORS = {
    ["SAY"]          = { r = 1.00, g = 1.00, b = 1.00 },
    ["YELL"]         = { r = 1.00, g = 0.25, b = 0.25 },
    ["EMOTE"]        = { r = 1.00, g = 0.50, b = 0.25 },
    ["PARTY"]        = { r = 0.67, g = 0.67, b = 1.00 },
    ["RAID"]         = { r = 1.00, g = 0.50, b = 0.00 },
    ["RAID_WARNING"] = { r = 1.00, g = 0.28, b = 0.00 },
    ["GUILD"]        = { r = 0.25, g = 1.00, b = 0.25 },
    ["OFFICER"]      = { r = 0.25, g = 0.75, b = 0.25 },
    ["WHISPER"]      = { r = 1.00, g = 0.50, b = 1.00 },
    ["SYSTEM"]       = { r = 1.00, g = 1.00, b = 0.00 },
    ["SKILL"]        = { r = 0.44, g = 0.69, b = 1.00 },
    ["COMBAT_INFO"]  = { r = 0.50, g = 0.80, b = 1.00 },
    ["CHANNEL"]      = { r = 0.90, g = 0.75, b = 0.60 },
    ["MONSTER"]      = { r = 1.00, g = 0.85, b = 0.40 },
    ["LOOT"]         = { r = 0.00, g = 0.67, b = 0.00 },
}

function PUITalk:GetChannelColor(chanType)
    local col = self.CHANNEL_COLORS[chanType]
    if col then return col.r, col.g, col.b end
    return 1.0, 1.0, 1.0
end

function PUITalk:IsInputFocused()
    if self.masterFrame and self.masterFrame.editBox then
        return self.masterFrame.editBox.hasFocus == true
    end
    return false
end

-- =========================================================================
-- 6. HYPERLINK INTERACTION ROUTER
-- =========================================================================

function PUITalk:HandleHyperlinkClick(link, text, button)
    if not link then return end

    -- 1. Web URLs (Linkified by PUITalk)
    if string.sub(link, 1, 4) == "url:" then
        local url = string.sub(link, 5)
        if self.ShowURLCopyPopup then
            self:ShowURLCopyPopup(url)
        end
        return
    end

    -- 2. Player Links (e.g. "player:PlayerName")
    if string.sub(link, 1, 6) == "player" then
        local name = string.sub(link, 8)
        if name and string.len(name) > 0 then
            name = string.gsub(name, "([^%s]*)%s+([^%s]*)%s+([^%s]*)", "%3")
            name = string.gsub(name, "([^%s]*)%s+([^%s]*)", "%2")

            if IsShiftKeyDown() then
                local staticPopup = StaticPopup_Visible("ADD_IGNORE") or
                                    StaticPopup_Visible("ADD_FRIEND") or
                                    StaticPopup_Visible("ADD_GUILDMEMBER") or
                                    StaticPopup_Visible("ADD_RAIDMEMBER")
                if staticPopup then
                    local eb = _G[staticPopup .. "EditBox"]
                    if eb and eb.SetText then eb:SetText(name) return end
                end

                if not self:IsInputFocused() then
                    self:FocusInput("")
                end
                if self.masterFrame and self.masterFrame.editBox then
                    if self.masterFrame.editBox.Insert then
                        self.masterFrame.editBox:Insert(name)
                    else
                        local cur = self.masterFrame.editBox:GetText() or ""
                        self.masterFrame.editBox:SetText(cur .. name)
                    end
                else
                    SendWho("n-" .. name)
                end
            elseif button == "RightButton" then
                if self.OpenDMContextMenu then
                    self:OpenDMContextMenu(nil, string.lower(name), name)
                elseif FriendsFrame_ShowDropdown then
                    FriendsFrame_ShowDropdown(name, 1)
                end
            else
                if self.db:Get("divertWhispers", true) then
                    self:OpenDMConversation(name)
                    self:FocusInput("")
                else
                    ChatFrame_SendTell(name)
                end
            end
        end
        return
    end

    -- 3. Items, Spells, Quests, Enchants
    if IsControlKeyDown() then
        if DressUpItemLink then DressUpItemLink(text or link) end
    elseif IsShiftKeyDown() then
        if not self:IsInputFocused() then
            self:FocusInput("")
        end
        if self.masterFrame and self.masterFrame.editBox then
            local insText = text or link
            if self.masterFrame.editBox.Insert then
                self.masterFrame.editBox:Insert(insText)
            else
                local cur = self.masterFrame.editBox:GetText() or ""
                self.masterFrame.editBox:SetText(cur .. insText)
            end
        end
    else
        ShowUIPanel(ItemRefTooltip)
        if not ItemRefTooltip:IsVisible() then
            ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE")
        end
        ItemRefTooltip:SetHyperlink(link)
    end
end

