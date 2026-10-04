--[[
    PrimusUI Module: PUITalk (Blizzard Chat Suppression & Chat Event Subscriptions)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    - Permanent suppression of default Blizzard chat frames (ChatFrame1..7, tabs, editbox).
    - DEFAULT_CHAT_FRAME.AddMessage hook capturing 100% of addon prints and engine notices.
    - Native chat event subscriptions with granular channel filtering.
    - Authoritative direct message event routing (CHAT_MSG_WHISPER, CHAT_MSG_WHISPER_INFORM).
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus or not Primus.PUITalk then return end

local PUITalk = Primus.PUITalk
local Events  = Primus.Events

-- =========================================================================
-- 1. BLIZZARD CHAT FRAME SUPPRESSION & ADDOUN ROUTING
-- =========================================================================

function PUITalk:SuppressBlizzardChat()
    if DEFAULT_CHAT_FRAME and not DEFAULT_CHAT_FRAME.primusPUITalkHooked then
        local origAddMessage = DEFAULT_CHAT_FRAME.AddMessage
        DEFAULT_CHAT_FRAME.AddMessage = function(self, text, r, g, b, id)
            if text then
                PUITalk:AddChatMessage(tostring(text), r, g, b)
            end
        end
        DEFAULT_CHAT_FRAME.primusPUITalkHooked = true
    end

    for i = 1, 7 do
        local cf = _G["ChatFrame" .. i]
        if cf then
            cf:UnregisterAllEvents()
            cf:ClearAllPoints()
            cf:SetPoint("BOTTOMLEFT", UIParent, "TOPLEFT", -2000, 2000)
            cf:SetWidth(1)
            cf:SetHeight(1)
            cf:SetAlpha(0)
            cf:EnableMouse(false)
            cf:Hide()
        end

        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab then
            tab:UnregisterAllEvents()
            tab:ClearAllPoints()
            tab:SetPoint("BOTTOMLEFT", UIParent, "TOPLEFT", -2000, 2000)
            tab:SetAlpha(0)
            tab:EnableMouse(false)
            tab:Hide()
        end
    end

    if ChatFrameEditBox then
        ChatFrameEditBox:ClearAllPoints()
        ChatFrameEditBox:SetPoint("BOTTOMLEFT", UIParent, "TOPLEFT", -2000, 2000)
        ChatFrameEditBox:Hide()

        if not ChatFrameEditBox._primusPUITalkHooked then
            ChatFrameEditBox._primusPUITalkHooked = true
            local origInsert = ChatFrameEditBox.Insert
            ChatFrameEditBox.Insert = function(self, text)
                if PUITalk.FocusInput then
                    PUITalk:FocusInput("")
                end
                if PUITalk.masterFrame and PUITalk.masterFrame.editBox then
                    if PUITalk.masterFrame.editBox.Insert then
                        PUITalk.masterFrame.editBox:Insert(text)
                    else
                        local cur = PUITalk.masterFrame.editBox:GetText() or ""
                        PUITalk.masterFrame.editBox:SetText(cur .. text)
                    end
                    return
                end
                if origInsert then origInsert(self, text) end
            end

            local origIsVisible = ChatFrameEditBox.IsVisible
            ChatFrameEditBox.IsVisible = function(self)
                if PUITalk.IsInputFocused and PUITalk:IsInputFocused() then
                    return 1
                end
                if PUITalk.masterFrame and PUITalk.masterFrame.editBox and PUITalk.masterFrame.editBox.hasFocus then
                    return 1
                end
                if origIsVisible then return origIsVisible(self) end
                return nil
            end
        end
    end

    if not _G.Primus_Original_SetItemRef and SetItemRef then
        _G.Primus_Original_SetItemRef = SetItemRef
        SetItemRef = function(link, text, button)
            if link and string.sub(link, 1, 4) == "url:" then
                if PUITalk.ShowURLCopyPopup then
                    PUITalk:ShowURLCopyPopup(string.sub(link, 5))
                    return
                end
            end
            if _G.Primus_Original_SetItemRef then
                return _G.Primus_Original_SetItemRef(link, text, button)
            end
        end
    end

    -- Hook native FrameXML click handlers to auto-open and route Shift-clicked items to PUITalk
    if PaperDollItemSlotButton_OnClick and not _G.Primus_Hooked_PaperDoll_OnClick then
        local origPaperDoll_OnClick = PaperDollItemSlotButton_OnClick
        PaperDollItemSlotButton_OnClick = function(button, ignoreModifiers)
            if button == "LeftButton" and IsShiftKeyDown() and not ignoreModifiers then
                local link = GetInventoryItemLink("player", this:GetID())
                if link and ChatFrameEditBox then
                    ChatFrameEditBox:Insert(link)
                    return
                end
            end
            return origPaperDoll_OnClick(button, ignoreModifiers)
        end
        _G.Primus_Hooked_PaperDoll_OnClick = true
    end

    if QuestLogRewardItem_OnClick and not _G.Primus_Hooked_QuestLogReward_OnClick then
        local origQL_OnClick = QuestLogRewardItem_OnClick
        QuestLogRewardItem_OnClick = function()
            if IsShiftKeyDown() and this.rewardType ~= "spell" then
                local link = GetQuestLogItemLink(this.type, this:GetID())
                if link and ChatFrameEditBox then
                    ChatFrameEditBox:Insert(link)
                    return
                end
            end
            return origQL_OnClick()
        end
        _G.Primus_Hooked_QuestLogReward_OnClick = true
    end

    if QuestRewardItem_OnClick and not _G.Primus_Hooked_QuestReward_OnClick then
        local origQR_OnClick = QuestRewardItem_OnClick
        QuestRewardItem_OnClick = function()
            if IsShiftKeyDown() and this.rewardType ~= "spell" then
                local link = GetQuestItemLink(this.type, this:GetID())
                if link and ChatFrameEditBox then
                    ChatFrameEditBox:Insert(link)
                    return
                end
            end
            return origQR_OnClick()
        end
        _G.Primus_Hooked_QuestReward_OnClick = true
    end

    if LootFrameItem_OnClick and not _G.Primus_Hooked_LootFrameItem_OnClick then
        local origLoot_OnClick = LootFrameItem_OnClick
        LootFrameItem_OnClick = function(button)
            if IsShiftKeyDown() then
                local link = GetLootSlotLink(this.slot)
                if link and ChatFrameEditBox then
                    ChatFrameEditBox:Insert(link)
                    return
                end
            end
            return origLoot_OnClick(button)
        end
        _G.Primus_Hooked_LootFrameItem_OnClick = true
    end

    if ChatFrameMenuButton then
        ChatFrameMenuButton:Hide()
        ChatFrameMenuButton.Show = function() end
    end
end

-- =========================================================================
-- 2. GAME CHAT EVENT DISPATCHER (CENTRALIZED PRIMUS.CHAT CONSUMER)
-- =========================================================================

function PUITalk:RegisterChatEvents()
    local Chat = Primus.Chat

    -- 1. Register with Master Primus.Chat Pipeline
    if Chat and Chat.RegisterConsumer then
        Chat:RegisterConsumer("PUITalk", 10, function(msgObj)
            if not msgObj or not msgObj.event then return end
            local event = msgObj.event
            local msg = msgObj.text
            local sender = msgObj.sender
            local lang = msgObj.lang

            -- Say & Yell
            if event == "CHAT_MSG_SAY" then
                if not PUITalk:IsChannelEnabled("SAY") then return end
                local colored = PUITalk:GetColoredName(sender)
                local formatted = string.format("%s |cffffffff[Say]|r [%s]: %s", PUITalk:GetTimestamp(), colored, msg)
                local r, g, b = PUITalk:GetChannelColor("SAY")
                PUITalk:AddChatMessage(formatted, r, g, b)

            elseif event == "CHAT_MSG_YELL" then
                if not PUITalk:IsChannelEnabled("YELL") then return end
                local colored = PUITalk:GetColoredName(sender)
                local formatted = string.format("%s |cffff4040[Yell]|r [%s]: %s", PUITalk:GetTimestamp(), colored, msg)
                local r, g, b = PUITalk:GetChannelColor("YELL")
                PUITalk:AddChatMessage(formatted, r, g, b)

            -- Emotes
            elseif event == "CHAT_MSG_EMOTE" then
                if not PUITalk:IsChannelEnabled("EMOTE") then return end
                local colored = PUITalk:GetColoredName(sender)
                local formatted = string.format("%s |cffff8040[Emote]|r %s %s", PUITalk:GetTimestamp(), colored, msg)
                local r, g, b = PUITalk:GetChannelColor("EMOTE")
                PUITalk:AddChatMessage(formatted, r, g, b)

            elseif event == "CHAT_MSG_TEXT_EMOTE" then
                if not PUITalk:IsChannelEnabled("EMOTE") then return end
                local formatted = string.format("%s |cffff8040%s|r", PUITalk:GetTimestamp(), msg)
                local r, g, b = PUITalk:GetChannelColor("EMOTE")
                PUITalk:AddChatMessage(formatted, r, g, b)

            -- Party & Raid
            elseif event == "CHAT_MSG_PARTY" then
                if not PUITalk:IsChannelEnabled("PARTY") then return end
                local colored = PUITalk:GetColoredName(sender)
                local formatted = string.format("%s |cffaaaaee[Party]|r [%s]: %s", PUITalk:GetTimestamp(), colored, msg)
                local r, g, b = PUITalk:GetChannelColor("PARTY")
                PUITalk:AddChatMessage(formatted, r, g, b)

            elseif event == "CHAT_MSG_RAID" then
                if not PUITalk:IsChannelEnabled("RAID") then return end
                local colored = PUITalk:GetColoredName(sender)
                local formatted = string.format("%s |cffff7f00[Raid]|r [%s]: %s", PUITalk:GetTimestamp(), colored, msg)
                local r, g, b = PUITalk:GetChannelColor("RAID")
                PUITalk:AddChatMessage(formatted, r, g, b)

            elseif event == "CHAT_MSG_RAID_LEADER" then
                if not PUITalk:IsChannelEnabled("RAID") then return end
                local colored = PUITalk:GetColoredName(sender)
                local formatted = string.format("%s |cffff4800[Raid Leader]|r [%s]: %s", PUITalk:GetTimestamp(), colored, msg)
                local r, g, b = PUITalk:GetChannelColor("RAID_WARNING")
                PUITalk:AddChatMessage(formatted, r, g, b)

            elseif event == "CHAT_MSG_RAID_WARNING" then
                if not PUITalk:IsChannelEnabled("RAID") then return end
                local colored = PUITalk:GetColoredName(sender)
                local formatted = string.format("%s |cffff4800[Raid Warning]|r [%s]: %s", PUITalk:GetTimestamp(), colored, msg)
                local r, g, b = PUITalk:GetChannelColor("RAID_WARNING")
                PUITalk:AddChatMessage(formatted, r, g, b)

            -- Guild & Officer
            elseif event == "CHAT_MSG_GUILD" then
                if not PUITalk:IsChannelEnabled("GUILD") then return end
                local colored = PUITalk:GetColoredName(sender)
                local formatted = string.format("%s |cff40ff40[Guild]|r [%s]: %s", PUITalk:GetTimestamp(), colored, msg)
                local r, g, b = PUITalk:GetChannelColor("GUILD")
                PUITalk:AddChatMessage(formatted, r, g, b)

            elseif event == "CHAT_MSG_OFFICER" then
                if not PUITalk:IsChannelEnabled("OFFICER") then return end
                local colored = PUITalk:GetColoredName(sender)
                local formatted = string.format("%s |cff40c040[Officer]|r [%s]: %s", PUITalk:GetTimestamp(), colored, msg)
                local r, g, b = PUITalk:GetChannelColor("OFFICER")
                PUITalk:AddChatMessage(formatted, r, g, b)

            -- Standard & Custom Channels
            elseif event == "CHAT_MSG_CHANNEL" then
                local cNum = tonumber(msgObj.channelNumber) or 0
                local cName = msgObj.channelNameBase or msgObj.channelName or "Channel"
                local cleanBaseName = cName
                local dashPos = string.find(cleanBaseName, " %- ")
                if dashPos then cleanBaseName = string.sub(cleanBaseName, 1, dashPos - 1) end
                local lowerBase = string.lower(cleanBaseName)
                local lowerFull = string.lower(cName .. " " .. (msgObj.channelName or ""))

                local filterKey = nil
                if cNum == 1 or string.find(lowerFull, "general") then
                    filterKey = "GENERAL"
                elseif cNum == 2 or string.find(lowerFull, "trade") then
                    filterKey = "TRADE"
                elseif cNum == 3 or string.find(lowerFull, "defense") or string.find(lowerFull, "localdefense") then
                    filterKey = "LOCALDEFENSE"
                elseif cNum == 4 or string.find(lowerFull, "lookingforgroup") or string.find(lowerFull, "lfg") then
                    filterKey = "LFG"
                else
                    PUITalk:RegisterJoinedChannel(cleanBaseName)
                    if not PUITalk:IsChannelEnabled("WORLD") then return end
                    if not PUITalk:IsChannelEnabled("CUSTOM_" .. lowerBase) then return end
                end

                if filterKey and not PUITalk:IsChannelEnabled(filterKey) then return end

                local colored = PUITalk:GetColoredName(sender)
                local chanBadge = string.format("[%s. %s]", tostring(cNum > 0 and cNum or ""), cName)
                local formatted = string.format("%s |cffe6c099%s|r [%s]: %s", PUITalk:GetTimestamp(), chanBadge, colored, msg)
                local r, g, b = PUITalk:GetChannelColor("CHANNEL")
                PUITalk:AddChatMessage(formatted, r, g, b)

            -- System & Notices
            elseif event == "CHAT_MSG_SYSTEM" then
                if not PUITalk:IsChannelEnabled("SYSTEM") then return end
                local formatted = string.format("%s |cffffff00%s|r", PUITalk:GetTimestamp(), msg)
                PUITalk:AddChatMessage(formatted, 1.0, 1.0, 0.0)

            elseif event == "CHAT_MSG_CHANNEL_NOTICE" then
                local action = msg
                local channelName = msgObj.channelName
                if action == "YOU_JOINED" and channelName then
                    PUITalk:RegisterJoinedChannel(channelName)
                elseif action == "YOU_LEFT" and channelName then
                    PUITalk:UnregisterLeftChannel(channelName)
                end
                if not PUITalk:IsChannelEnabled("SYSTEM") then return end
                local formatted = string.format("%s |cff888888[%s]: %s|r", PUITalk:GetTimestamp(), channelName or "Channel", action or "")
                PUITalk:AddChatMessage(formatted, 0.6, 0.6, 0.6)

            -- Monster Messages
            elseif event == "CHAT_MSG_MONSTER_SAY" then
                if not PUITalk:IsChannelEnabled("MONSTER") then return end
                local formatted = string.format("%s |cffffd100[%s]:|r %s", PUITalk:GetTimestamp(), sender or "Monster", msg)
                PUITalk:AddChatMessage(formatted, 1.0, 0.85, 0.4)

            elseif event == "CHAT_MSG_MONSTER_YELL" then
                if not PUITalk:IsChannelEnabled("MONSTER") then return end
                local formatted = string.format("%s |cffff4040[%s yells]:|r %s", PUITalk:GetTimestamp(), sender or "Monster", msg)
                PUITalk:AddChatMessage(formatted, 1.0, 0.35, 0.35)

            elseif event == "CHAT_MSG_MONSTER_EMOTE" then
                if not PUITalk:IsChannelEnabled("MONSTER") then return end
                local formatted = string.format("%s |cffff8040%s %s|r", PUITalk:GetTimestamp(), sender or "", msg)
                PUITalk:AddChatMessage(formatted, 1.0, 0.5, 0.25)

            -- Skills & Tradeskills
            elseif event == "CHAT_MSG_SKILL" or event == "CHAT_MSG_SPELL_TRADESKILLS" then
                if not PUITalk:IsChannelEnabled("SKILL") then return end
                local formatted = string.format("%s |cff70b0ff%s|r", PUITalk:GetTimestamp(), msg)
                local r, g, b = PUITalk:GetChannelColor("SKILL")
                PUITalk:AddChatMessage(formatted, r, g, b)

            -- Combat Info
            elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
                if not PUITalk:IsChannelEnabled("COMBAT_INFO") then return end
                local formatted = string.format("%s |cff70b0ff%s|r", PUITalk:GetTimestamp(), msg)
                PUITalk:AddChatMessage(formatted, 0.45, 0.70, 1.0)

            elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
                if not PUITalk:IsChannelEnabled("COMBAT_INFO") then return end
                local formatted = string.format("%s |cffdfb8ff%s|r", PUITalk:GetTimestamp(), msg)
                PUITalk:AddChatMessage(formatted, 0.87, 0.72, 1.0)

            elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
                if not PUITalk:IsChannelEnabled("COMBAT_INFO") then return end
                local formatted = string.format("%s |cff80d0ff%s|r", PUITalk:GetTimestamp(), msg)
                PUITalk:AddChatMessage(formatted, 0.50, 0.80, 1.0)

            elseif event == "CHAT_MSG_COMBAT_MISC_INFO" then
                if not PUITalk:IsChannelEnabled("COMBAT_INFO") then return end
                local formatted = string.format("%s |cffaaaaaa%s|r", PUITalk:GetTimestamp(), msg)
                PUITalk:AddChatMessage(formatted, 0.65, 0.65, 0.65)

            -- Opening & Pet Notices
            elseif event == "CHAT_MSG_OPENING" or event == "CHAT_MSG_PET_INFO" then
                if not PUITalk:IsChannelEnabled("SYSTEM") then return end
                local formatted = string.format("%s |cffffff00%s|r", PUITalk:GetTimestamp(), msg)
                PUITalk:AddChatMessage(formatted, 1.0, 1.0, 0.0)

            -- Battlegrounds
            elseif event == "CHAT_MSG_BATTLEGROUND" then
                if not PUITalk:IsChannelEnabled("RAID") then return end
                local colored = PUITalk:GetColoredName(sender)
                local formatted = string.format("%s |cffff7f00[BG]|r [%s]: %s", PUITalk:GetTimestamp(), colored, msg)
                local r, g, b = PUITalk:GetChannelColor("RAID")
                PUITalk:AddChatMessage(formatted, r, g, b)

            elseif event == "CHAT_MSG_BATTLEGROUND_LEADER" then
                if not PUITalk:IsChannelEnabled("RAID") then return end
                local colored = PUITalk:GetColoredName(sender)
                local formatted = string.format("%s |cffff4800[BG Leader]|r [%s]: %s", PUITalk:GetTimestamp(), colored, msg)
                local r, g, b = PUITalk:GetChannelColor("RAID_WARNING")
                PUITalk:AddChatMessage(formatted, r, g, b)

            elseif event == "CHAT_MSG_BG_SYSTEM_NEUTRAL" then
                if not PUITalk:IsChannelEnabled("SYSTEM") then return end
                local formatted = string.format("%s |cffffd100[BG]:|r %s", PUITalk:GetTimestamp(), msg)
                PUITalk:AddChatMessage(formatted, 1.0, 0.85, 0.0)

            elseif event == "CHAT_MSG_BG_SYSTEM_ALLIANCE" then
                if not PUITalk:IsChannelEnabled("SYSTEM") then return end
                local formatted = string.format("%s |cff0070dd[Alliance]:|r %s", PUITalk:GetTimestamp(), msg)
                PUITalk:AddChatMessage(formatted, 0.0, 0.44, 0.87)

            elseif event == "CHAT_MSG_BG_SYSTEM_HORDE" then
                if not PUITalk:IsChannelEnabled("SYSTEM") then return end
                local formatted = string.format("%s |cffff2020[Horde]:|r %s", PUITalk:GetTimestamp(), msg)
                PUITalk:AddChatMessage(formatted, 1.0, 0.13, 0.13)

            -- Boss & Whispers
            elseif event == "CHAT_MSG_RAID_BOSS_EMOTE" then
                if not PUITalk:IsChannelEnabled("MONSTER") then return end
                local formatted = string.format("%s |cffff4800[%s]:|r %s", PUITalk:GetTimestamp(), sender or "Boss", msg)
                PUITalk:AddChatMessage(formatted, 1.0, 0.28, 0.0)

            elseif event == "CHAT_MSG_RAID_BOSS_WHISPER" then
                if not PUITalk:IsChannelEnabled("MONSTER") then return end
                local formatted = string.format("%s |cffff4800[%s whispers]:|r %s", PUITalk:GetTimestamp(), sender or "Boss", msg)
                PUITalk:AddChatMessage(formatted, 1.0, 0.28, 0.0)

            elseif event == "CHAT_MSG_MONSTER_WHISPER" then
                if not PUITalk:IsChannelEnabled("MONSTER") then return end
                local formatted = string.format("%s |cffffd100[%s whispers]:|r %s", PUITalk:GetTimestamp(), sender or "Monster", msg)
                PUITalk:AddChatMessage(formatted, 1.0, 0.85, 0.4)

            -- Ignored & Filtered
            elseif event == "CHAT_MSG_IGNORED" then
                local formatted = string.format("%s |cffff4444%s is ignoring you.|r", PUITalk:GetTimestamp(), sender or "Player")
                PUITalk:AddChatMessage(formatted, 1.0, 0.27, 0.27)

            elseif event == "CHAT_MSG_FILTERED" then
                local formatted = string.format("%s |cffff4444%s is not receiving whispers.|r", PUITalk:GetTimestamp(), sender or "Player")
                PUITalk:AddChatMessage(formatted, 1.0, 0.27, 0.27)

            -- Loot & Money
            elseif event == "CHAT_MSG_LOOT" then
                if not PUITalk:IsChannelEnabled("LOOT") then return end
                local formatted = string.format("%s |cff00cc00%s|r", PUITalk:GetTimestamp(), msg)
                PUITalk:AddChatMessage(formatted, 0.0, 0.8, 0.0)

            elseif event == "CHAT_MSG_MONEY" then
                if not PUITalk:IsChannelEnabled("LOOT") then return end
                local formatted = string.format("%s |cffffff00%s|r", PUITalk:GetTimestamp(), msg)
                PUITalk:AddChatMessage(formatted, 1.0, 1.0, 0.0)

            -- Direct Messages (Whispers)
            elseif event == "CHAT_MSG_WHISPER" then
                PUITalk.lastWhisperSender = sender
                local key = string.lower(sender)
                if PUITalk.AddDMMessage then
                    PUITalk:AddDMMessage(key, sender, msg, false)
                end
                if PUITalk.db:Get("autoPopDMs") then
                    if PUITalk.OpenDMConversation then PUITalk:OpenDMConversation(sender) end
                else
                    if PUITalk.RefreshDMTabs then PUITalk:RefreshDMTabs() end
                end

            elseif event == "CHAT_MSG_WHISPER_INFORM" then
                local key = string.lower(sender or msgObj.target or "")
                if PUITalk.AddDMMessage then
                    PUITalk:AddDMMessage(key, UnitName("player"), msg, true)
                end
            end
        end)
    end

    -- 2. Register Player Level Up & Points
    Events:Register("PLAYER_LEVEL_UP", "PUITalk_Chat", function(owner, event, level, hp, mp, talentPoints)
        local formatted = string.format("%s |cffffff00You have reached level %d!|r", PUITalk:GetTimestamp(), tonumber(level) or 1)
        PUITalk:AddChatMessage(formatted, 1.0, 1.0, 0.0)
        if talentPoints and tonumber(talentPoints) and tonumber(talentPoints) > 0 then
            PUITalk:AddChatMessage(string.format("%s |cffffff00You have gained %d talent points.|r", PUITalk:GetTimestamp(), tonumber(talentPoints)), 1.0, 1.0, 0.0)
        end
    end)

    Events:Register("CHARACTER_POINTS_CHANGED", "PUITalk_Chat", function(owner, event, change1, change2)
        if change2 and tonumber(change2) and tonumber(change2) > 0 then
            local _, cp2 = UnitCharacterPoints("player")
            if cp2 and cp2 > 0 then
                local formatted = string.format("%s |cffffff00You now have %d unspent talent points.|r", PUITalk:GetTimestamp(), cp2)
                PUITalk:AddChatMessage(formatted, 1.0, 1.0, 0.0)
            end
        end
    end)
end
