--[[
    PrimusUI: PUIRoleplay Master Module Coordinator (PUIRoleplay.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (Multi-Channel OWPRP, TTRP, xtensionxtooltip2, MyRolePlay)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIRoleplay = Primus.PUIRoleplay or {}
Primus.PUIRoleplay = PUIRoleplay
_G.PUIRoleplay = PUIRoleplay
Primus:RegisterModule("PUIRoleplay", PUIRoleplay, "Social")

local charDB = nil
local globalDB = nil

local defaultCharTemplate = PUIRoleplay.DefaultProfile or {
    keyM = "PUI10",
    keyT = "PUI20",
    keyD = "PUI30",
    icon = "1",
    first_name = "",
    middle_name = "",
    last_name = "",
    prefix = "",
    title = "",
    epithet = "",
    suffix = "",
    nickname = "",
    house_name = "",
    bloodline = "",
    tribe = "",
    clan = "",
    full_name = "",
    apparent_age = "",
    gender_identity = "Cisgender Male",
    ic_pronouns = "He/Him",
    ooc_pronouns = "He/Him",
    lgbtqia_friendly = true,
    orientation = "Heterosexual / Straight",
    show_orientation = true,
    eye_color = "",
    height = "",
    weight = "",
    body_build = "",
    current_emotion = "Calm",
    appearance_desc = "",
    glances = {
        [1] = { active = false, icon = "INV_Jewelry_Ring_03", title = "", text = "" },
        [2] = { active = false, icon = "INV_Sword_27", title = "", text = "" },
        [3] = { active = false, icon = "Spell_Holy_HolyBolt", title = "", text = "" },
        [4] = { active = false, icon = "INV_Misc_Book_09", title = "", text = "" },
        [5] = { active = false, icon = "INV_Misc_Bag_08", title = "", text = "" },
    },
    birth_city = "",
    home_city = "",
    motto = "",
    faction_clan = "",
    history = {
        chapter1 = "",
        chapter2 = "",
        chapter3 = "",
        chapter4 = "",
        chapter5 = "",
        chapter6 = "",
    },
    experience_level = "Experienced",
    currently_ic = "1",
    walkup_policy = "Walkups Welcome",
    combat_preference = "D20 Rolls (DiceMaster)",
    permadeath_consent = "Negotiated Only",
    injury_consent = "Realistic / Negotiated",
    relationship_status = "Single & Looking",
    looking_for = {
        adventure = true,
        romance = true,
        combat = false,
        casual_tavern = true,
        political_guild = false,
        adult_18plus = false,
        mentorship = false,
    },
    adult_18plus_flag = false,
    erp_preference = "No Adult Content (Clean RP)",
    ooc_boundaries = "",
    ooc_notes = "",
}

local charDefaults = {
    selected_profile = "0",
    profiles = {
        ["0"] = defaultCharTemplate,
        ["1"] = defaultCharTemplate,
        ["2"] = defaultCharTemplate,
        ["3"] = defaultCharTemplate
    },
    character_notes = {}
}

local globalDefaults = {
    known_characters = {},
    queryable_players = {},
    settings = {
        share_location = "1",
        show_nsfw = "0",
        bgs = "off",
        show_glance_bar = true,
        show_icon_tray = true,
        active_channels = { "OWPRP", "TTRP", "xtensionxtooltip2", "MyRolePlay" },
    }
}

--------------------------------------------------------------------------------
-- Key Generation
--------------------------------------------------------------------------------
local alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
function PUIRoleplay:GenerateKey()
    local key = ""
    local len = string.len(alphabet)
    for i = 1, 5 do
        local r = math.random(1, len)
        key = key .. string.sub(alphabet, r, r)
    end
    return key
end

--------------------------------------------------------------------------------
-- Database & Profile Helpers
--------------------------------------------------------------------------------
function PUIRoleplay:GetCharData()
    if charDB and charDB.data then
        return charDB.data
    end
    return charDefaults
end

function PUIRoleplay:GetGlobalData()
    if globalDB and globalDB.data then
        return globalDB.data
    end
    return globalDefaults
end

function PUIRoleplay:GetData()
    return self:GetCharData()
end

function PUIRoleplay:GetActiveProfileSlot()
    local data = self:GetCharData()
    return data.selected_profile or "0"
end

function PUIRoleplay:SetActiveProfileSlot(slot)
    local data = self:GetCharData()
    data.selected_profile = tostring(slot)
    if not data.profiles then data.profiles = {} end
    if not data.profiles[data.selected_profile] then
        data.profiles[data.selected_profile] = Primus.Utils.DeepCopy(defaultCharTemplate)
    end
    self:SyncGlobalBridges()
end

function PUIRoleplay:GetMyProfile()
    local data = self:GetCharData()
    local slot = self:GetActiveProfileSlot()
    if not data.profiles then data.profiles = {} end
    if not data.profiles[slot] then
        data.profiles[slot] = Primus.Utils.DeepCopy(defaultCharTemplate)
    end
    local prof = data.profiles[slot]
    local pName = UnitName("player")
    local pRace = UnitRace("player")
    local pClass = UnitClass("player")

    if pName and pName ~= "" and pName ~= "Unknown Being" then
        if not prof.full_name or prof.full_name == "" then
            prof.full_name = pName
        end
    end
    if pRace and pRace ~= "" then
        if not prof.race or prof.race == "" then
            prof.race = pRace
        end
    end
    if pClass and pClass ~= "" then
        if not prof.class or prof.class == "" or prof.class ~= pClass then
            prof.class = pClass
            local cData = PUIRoleplay.ClassData and PUIRoleplay.ClassData[prof.class]
            if cData then prof.class_color = cData[4] end
        end
    end
    return prof
end

function PUIRoleplay:SaveMyProfile(prof)
    local data = self:GetCharData()
    local slot = self:GetActiveProfileSlot()
    if not data.profiles then data.profiles = {} end
    data.profiles[slot] = prof
    self:SyncGlobalBridges()
end

function PUIRoleplay:ComposeFullName(p)
    if not p then return "" end
    local nameComposite = ""
    if p.first_name and p.first_name ~= "" then
        nameComposite = p.first_name
        if p.middle_name and p.middle_name ~= "" then
            nameComposite = nameComposite .. " " .. p.middle_name
        end
        if p.last_name and p.last_name ~= "" then
            nameComposite = nameComposite .. " " .. p.last_name
        end
    elseif p.full_name and p.full_name ~= "" then
        nameComposite = p.full_name
    elseif p.name and p.name ~= "" then
        nameComposite = p.name
    else
        nameComposite = ""
    end
    return nameComposite
end

function PUIRoleplay:UnescapeRPText(text)
    if self.Protocols and self.Protocols.UnescapeText then
        return self.Protocols:UnescapeText(text)
    end
    if not text then return "" end
    text = tostring(text)
    text = string.gsub(text, "\r\n", "\n")
    text = string.gsub(text, "\r", "\n")
    text = string.gsub(text, "@[Nn]", "\n")
    text = string.gsub(text, "@[Jj]", "\n")
    text = string.gsub(text, "@[Tt]", "    ")
    text = string.gsub(text, "@@", "@")
    return text
end

function PUIRoleplay:EscapeRPText(text)
    if self.Protocols and self.Protocols.EscapeText then
        return self.Protocols:EscapeText(text)
    end
    if not text then return "" end
    text = tostring(text)
    text = string.gsub(text, "\r\n", "@N")
    text = string.gsub(text, "\r", "@N")
    text = string.gsub(text, "\n", "@N")
    text = string.gsub(text, "\t", "@T")
    text = string.gsub(text, "~", "-")
    return text
end

function PUIRoleplay:ComposeTitle(charData)
    if not charData then return "" end
    local pfx = charData.prefix or ""
    local ttl = charData.title or ""
    local ep = charData.epithet or charData.suffix or ""
    local house = charData.house_name or charData.house or charData.tribe or charData.clan or charData.bloodline or ""

    local parts = {}
    local rankTitle = ""
    if pfx ~= "" then
        rankTitle = pfx
    end
    if ttl ~= "" then
        if rankTitle ~= "" then
            rankTitle = rankTitle .. " " .. ttl
        else
            rankTitle = ttl
        end
    end

    if rankTitle ~= "" then
        table.insert(parts, rankTitle)
    end

    if ep ~= "" and ep ~= ttl then
        table.insert(parts, ep)
    end

    if house ~= "" then
        if table.getn(parts) > 0 then
            local lHouse = string.lower(house)
            if string.find(lHouse, "^house") or string.find(lHouse, "^clan") or string.find(lHouse, "^tribe") or string.find(lHouse, "^the ") then
                table.insert(parts, house)
            else
                table.insert(parts, "of " .. house)
            end
        else
            table.insert(parts, house)
        end
    end

    if table.getn(parts) == 0 then return "" end
    return table.concat(parts, ", ")
end

function PUIRoleplay:GetPersonalityTraits(profile)
    local prof = profile or self:GetMyProfile()
    if not prof.personality_traits or table.getn(prof.personality_traits) == 0 then
        prof.personality_traits = {}
        for _, t in ipairs(PUIRoleplay.DefaultPersonalityTraits or {}) do
            table.insert(prof.personality_traits, {
                id = t.id,
                leftName = t.leftName,
                rightName = t.rightName,
                leftIcon = t.leftIcon,
                rightIcon = t.rightIcon,
                value = t.value or 10,
                isCustom = false
            })
        end
    end
    return prof.personality_traits
end

function PUIRoleplay:GetCharacterData(name)
    if not name or name == "" then return nil end
    if name == UnitName("player") then return self:GetMyProfile() end
    local gData = self:GetGlobalData()
    if not gData.known_characters then gData.known_characters = {} end
    return gData.known_characters[name]
end

function PUIRoleplay:GetOrCreateCharacterData(name)
    if not name or name == "" then return {} end
    if name == UnitName("player") then return self:GetMyProfile() end
    local gData = self:GetGlobalData()
    if not gData.known_characters then gData.known_characters = {} end
    if not gData.known_characters[name] then
        gData.known_characters[name] = {}
    end
    return gData.known_characters[name]
end

function PUIRoleplay:GetAllKnownCharacters()
    local gData = self:GetGlobalData()
    if not gData.known_characters then gData.known_characters = {} end
    return gData.known_characters
end

function PUIRoleplay:SetCharacterNote(name, note)
    if not name or name == "" then return end
    local cData = self:GetCharData()
    if not cData.character_notes then cData.character_notes = {} end
    cData.character_notes[name] = note
    self:SyncGlobalBridges()
end

function PUIRoleplay:GetCharacterNote(name)
    if not name or name == "" then return "" end
    local cData = self:GetCharData()
    if not cData.character_notes then cData.character_notes = {} end
    return cData.character_notes[name] or ""
end

function PUIRoleplay:GetSettings()
    local gData = self:GetGlobalData()
    if not gData.settings then gData.settings = globalDefaults.settings end
    return gData.settings
end

function PUIRoleplay:GetICState()
    local prof = self:GetMyProfile()
    return prof.currently_ic or "1"
end

function PUIRoleplay:SetICState(state)
    local prof = self:GetMyProfile()
    prof.currently_ic = tostring(state)
    prof.keyM = self:GenerateKey()
    self:SaveMyProfile(prof)
    if self.Glance then
        self.Glance:UpdateTarget()
    end
    if self.Tray and self.Tray.UpdateICButton then
        self.Tray:UpdateICButton()
    end
end

function PUIRoleplay:RecordQueryablePlayer(name)
    if not name or name == "" then return end
    local gData = self:GetGlobalData()
    if not gData.queryable_players then gData.queryable_players = {} end
    gData.queryable_players[name] = time()
    self:SyncGlobalBridges()
end

function PUIRoleplay:IsPlayerOnline(name)
    if not name or name == "" then return false end
    if name == UnitName("player") then return true end
    local gData = self:GetGlobalData()
    if gData and gData.queryable_players and gData.queryable_players[name] then
        local lastSeen = gData.queryable_players[name]
        if type(lastSeen) == "number" and lastSeen > (time() - 180) then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Global Bridges (100% Seamless TurtleRP & MRP Cross-Compatibility)
--------------------------------------------------------------------------------
function PUIRoleplay:SyncGlobalBridges()
    local gData = self:GetGlobalData()
    local cData = self:GetCharData()
    if not gData.known_characters then gData.known_characters = {} end
    if not gData.queryable_players then gData.queryable_players = {} end
    if not gData.settings then gData.settings = globalDefaults.settings end
    if not cData.profiles then cData.profiles = {} end

    _G.TurtleRPCharacters = gData.known_characters
    _G.TurtleRPCharacterInfo = self:GetMyProfile()
    _G.TurtleRPPlayerProfiles = cData.profiles
    _G.TurtleRPQueryablePlayers = gData.queryable_players
    _G.TurtleRPSettings = gData.settings

    if UnitName("player") then
        _G.TurtleRPCharacters[UnitName("player")] = _G.TurtleRPCharacterInfo
    end
end

--------------------------------------------------------------------------------
-- Network Events / Updates Callback
--------------------------------------------------------------------------------
function PUIRoleplay:OnDataReceived(dataPrefix, playerName)
    self:SyncGlobalBridges()

    if self.Sheet and Primus_PUIRoleplay_Sheet and Primus_PUIRoleplay_Sheet:IsVisible() then
        self.Sheet:Refresh()
    end

    if UnitName("target") == playerName and self.Glance then
        self.Glance:RenderTargetData(playerName)
    end

    if self.Directory and Primus_PUIRoleplay_Directory and Primus_PUIRoleplay_Directory:IsVisible() then
        self.Directory:RefreshList()
    end
end

function PUIRoleplay:OnPingReceived(sender)
    self:SyncGlobalBridges()
    if self.Directory then
        self.Directory:UpdateWorldMapPins()
        if Primus_PUIRoleplay_Directory and Primus_PUIRoleplay_Directory:IsVisible() then
            self.Directory:RefreshList()
        end
    end
end

--------------------------------------------------------------------------------
-- Module Lifecycle (OnInitialize, OnEnable, OnDisable)
--------------------------------------------------------------------------------
function PUIRoleplay:OnInitialize()
    charDB = Primus.DB:RegisterNamespace("PUIRoleplay", charDefaults, true)
    globalDB = Primus.DB:RegisterNamespace("PUIRoleplay_Global", globalDefaults, false)

    -- Migrate legacy data
    local gData = self:GetGlobalData()
    if _G.TurtleRPCharacters and type(_G.TurtleRPCharacters) == "table" then
        for k, v in pairs(_G.TurtleRPCharacters) do
            if not gData.known_characters[k] and type(v) == "table" then
                gData.known_characters[k] = Primus.Utils.DeepCopy(v)
            end
        end
    end

    local myProf = self:GetMyProfile()
    if not myProf.keyM or myProf.keyM == "" then myProf.keyM = self:GenerateKey() end
    if not myProf.keyT or myProf.keyT == "" then myProf.keyT = self:GenerateKey() end
    if not myProf.keyD or myProf.keyD == "" then myProf.keyD = self:GenerateKey() end

    self:SyncGlobalBridges()
    self:RegisterFlare()

    -- Console Subcommands
    Primus.Console:RegisterSubCommand("rp", function(args)
        if args == "dir" or args == "directory" then
            PUIRoleplay:OpenDirectory()
        elseif args == "chat" or args == "compose" or args == "split" or args == "emote" then
            PUIRoleplay.Emotes:OpenComposer()
        elseif args == "listen" or args == "listener" then
            if PUIRoleplay.Listener then PUIRoleplay.Listener:Toggle() end
        elseif args == "logs" or args == "elephant" then
            if PUIRoleplay.Elephant then PUIRoleplay.Elephant:OpenLogs() end
        elseif args == "bar" or args == "tray" then
            if PUIRoleplay.Tray then PUIRoleplay.Tray:Toggle() end
        else
            PUIRoleplay:OpenProfile()
        end
    end, "Roleplaying suite (/pui rp [dir|compose|listen|logs|tray])")

    SLASH_PUIRP1 = "/rp"
    SlashCmdList["PUIRP"] = function(msg)
        if msg == "dir" or msg == "directory" then
            PUIRoleplay:OpenDirectory()
        elseif msg == "chat" or msg == "compose" or msg == "split" or msg == "emote" then
            PUIRoleplay.Emotes:OpenComposer()
        elseif msg == "listen" or msg == "listener" then
            if PUIRoleplay.Listener then PUIRoleplay.Listener:Toggle() end
        elseif msg == "logs" or msg == "elephant" then
            if PUIRoleplay.Elephant then PUIRoleplay.Elephant:OpenLogs() end
        elseif msg == "bar" or msg == "tray" then
            if PUIRoleplay.Tray then PUIRoleplay.Tray:Toggle() end
        elseif msg == "ic" then
            PUIRoleplay:SetICState("1")
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffPrimus RP:|r Status set to |cff40ff66[IC]|r")
        elseif msg == "ooc" then
            PUIRoleplay:SetICState("0")
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffPrimus RP:|r Status set to |cffffaa00[OOC]|r")
        else
            PUIRoleplay:OpenProfile()
        end
    end

    SLASH_PUITTRP1 = "/ttrp"
    SlashCmdList["PUITTRP"] = SlashCmdList["PUIRP"]

    SLASH_PUIMRP1 = "/mrp"
    SlashCmdList["PUIMRP"] = SlashCmdList["PUIRP"]
end

function PUIRoleplay:OnEnable()
    self:GetMyProfile()
    self:SyncGlobalBridges()

    -- Channel Comms & Dialogue Pipeline
    if Primus.Chat then
        Primus.Chat:RegisterConsumer("PUIRoleplayComms", 5, function(msgObj)
            if msgObj.event == "CHAT_MSG_CHANNEL" then
                local ch = string.lower(msgObj.channelName or "")
                local chBase = string.lower(msgObj.channelNameBase or "")
                local msgText = msgObj.message or msgObj.text
                if ch == "owprp" or string.find(ch, "owprp") or chBase == "owprp" or string.find(chBase, "owprp") or
                   ch == "ttrp" or string.find(ch, "ttrp") or chBase == "ttrp" or string.find(chBase, "ttrp") or
                   ch == "xtensionxtooltip2" or string.find(ch, "xtensionxtooltip2") or chBase == "xtensionxtooltip2" or string.find(chBase, "xtensionxtooltip2") or
                   ch == "myroleplay" or string.find(ch, "myroleplay") or chBase == "myroleplay" or string.find(chBase, "myroleplay") then
                    PUIRoleplay.Comms:OnChatMessage(msgText, msgObj.sender)
                end
            end
        end)

        Primus.Chat:RegisterConsumer("PUIRoleplayDialogue", 20, function(msgObj)
            local event = msgObj.event
            local msgText = msgObj.message or msgObj.text
            if event == "CHAT_MSG_SAY" or event == "CHAT_MSG_EMOTE" or event == "CHAT_MSG_TEXT_EMOTE" or
               event == "CHAT_MSG_YELL" or event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_PARTY" or
               event == "CHAT_MSG_RAID" then
                if PUIRoleplay.Listener then
                    PUIRoleplay.Listener:ProcessMessage(event, msgText, msgObj.sender)
                end
                if PUIRoleplay.Elephant then
                    PUIRoleplay.Elephant:LogMessage(event, msgText, msgObj.sender)
                end
            end
        end)
    end

    Primus.Events:Register("CHAT_MSG_CHANNEL_NOTICE", self, function(owner, event, noticeType, sender, _, chanStr, _, _, _, chanNum, chanName)
        local ch = string.lower(chanName or "")
        local cs = string.lower(chanStr or "")
        if ch == "owprp" or cs == "owprp" or string.find(cs, "owprp") or
           ch == "ttrp" or cs == "ttrp" or string.find(cs, "ttrp") then
            if noticeType == "YOU_JOINED" or noticeType == "YOU_CHANGED" then
                if PUIRoleplay.Comms and PUIRoleplay.Comms:CanChat() then
                    PUIRoleplay.Comms:SendPing("A")
                end
            end
        end
    end)

    -- Player entering world
    Primus.Events:Register("PLAYER_ENTERING_WORLD", self, function()
        PUIRoleplay:GetMyProfile()
        PUIRoleplay:SyncGlobalBridges()
        PUIRoleplay.Comms:JoinRPChannel()
    end)

    Primus.Events:Register("PLAYER_LEVEL_UP", self, function(owner, event, newLevel)
        local lvl = tonumber(newLevel) or UnitLevel("player") or 0
        if lvl >= 1 then
            PUIRoleplay.Comms:JoinRPChannel()
        end
    end)

    -- Target Updates
    Primus.Events:Register("PLAYER_TARGET_CHANGED", self, function()
        if PUIRoleplay.Glance then
            PUIRoleplay.Glance:UpdateTarget()
        end
        if UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
            local name = UnitName("target")
            if name and PUIRoleplay.Comms and PUIRoleplay.Comms:CanChat() then
                local charData = PUIRoleplay:GetCharacterData(name)
                if not charData or not charData.keyT then
                    PUIRoleplay.Comms:SendRequest("T", name)
                end
            end
        end
    end)


    self.Comms:JoinRPChannel()
    self.Comms:StartPingTicker()
    self.Tooltip:Initialize()

    local s = self:GetSettings()
    if s.show_icon_tray ~= false and self.Tray then
        self.Tray:Show()
    end
end

function PUIRoleplay:OnDisable()
    Primus.Events:UnregisterOwner(self)
    Primus.Time:CancelAll(self)

    if self.Tooltip and self.Tooltip.Disable then self.Tooltip:Disable() end
    if Primus_PUIRoleplay_Sheet then Primus_PUIRoleplay_Sheet:Hide() end
    if Primus_PUIRoleplay_GlanceBar then Primus_PUIRoleplay_GlanceBar:Hide() end
    if Primus_PUIRoleplay_Directory then Primus_PUIRoleplay_Directory:Hide() end
    if Primus_PUIRoleplay_Listener then Primus_PUIRoleplay_Listener:Hide() end
    if Primus_PUIRoleplay_Elephant then Primus_PUIRoleplay_Elephant:Hide() end
    if Primus_PUIRoleplay_DiceFrame then Primus_PUIRoleplay_DiceFrame:Hide() end
    if Primus_PUIRoleplay_BagFrame then Primus_PUIRoleplay_BagFrame:Hide() end
    if Primus_PUIRoleplay_ItemForge then Primus_PUIRoleplay_ItemForge:Hide() end
    if Primus_PUIRoleplay_DocFrame then Primus_PUIRoleplay_DocFrame:Hide() end
    if self.Tray then self.Tray:Hide() end
end

--------------------------------------------------------------------------------
-- Options Flare Hub Integration
--------------------------------------------------------------------------------
function PUIRoleplay:RegisterFlare()
    if not Primus.Options then return end

    Primus.Options:RegisterModuleOptions("PUIRoleplay", {
        title = "Roleplaying (PUIRP)",
        category = "Social",
        order = 4,
        desc = "Full-featured Roleplaying suite with Multi-Channel Telemetry (OWPRP, TTRP, MRP), At-A-Glance HUD pill, and Matchmaking Directory."
    }, function(parent)
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetWidth(parent:GetWidth())
        frame:SetHeight(420)

        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
        title:SetText("|cff00ccffRoleplaying Suite Settings|r")

        local trayCB = Primus.Widgets:CreateCheckButton(frame, "Show RP Quick Action Bar (Tray)", PUIRoleplay:GetSettings().show_icon_tray ~= false, function(checked)
            local s = PUIRoleplay:GetSettings()
            s.show_icon_tray = checked
            if checked and PUIRoleplay.Tray then
                PUIRoleplay.Tray:Show()
            elseif PUIRoleplay.Tray then
                PUIRoleplay.Tray:Hide()
            end
        end)
        trayCB:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)

        local shareLocCB = Primus.Widgets:CreateCheckButton(frame, "Share Location on RP World Map", PUIRoleplay:GetSettings().share_location == "1", function(checked)
            local s = PUIRoleplay:GetSettings()
            s.share_location = checked and "1" or "0"
        end)
        shareLocCB:SetPoint("TOPLEFT", trayCB, "BOTTOMLEFT", 0, -8)

        local bgsCB = Primus.Widgets:CreateCheckButton(frame, "Disable RP overlays in Battlegrounds", PUIRoleplay:GetSettings().bgs == "off", function(checked)
            local s = PUIRoleplay:GetSettings()
            s.bgs = checked and "off" or "on"
        end)
        bgsCB:SetPoint("TOPLEFT", shareLocCB, "BOTTOMLEFT", 0, -8)

        local nsfwCB = Primus.Widgets:CreateCheckButton(frame, "Show 18+ Adult-Oriented Roleplay Profiles", PUIRoleplay:GetSettings().show_nsfw == "1", function(checked)
            local s = PUIRoleplay:GetSettings()
            s.show_nsfw = checked and "1" or "0"
        end)
        nsfwCB:SetPoint("TOPLEFT", bgsCB, "BOTTOMLEFT", 0, -8)

        local openSheetBtn = Primus.Widgets:CreateButton(frame, "Open Profile Editor", 160, 24, function()
            PUIRoleplay:OpenProfile()
        end)
        openSheetBtn:SetPoint("TOPLEFT", nsfwCB, "BOTTOMLEFT", 0, -16)

        local openDirBtn = Primus.Widgets:CreateButton(frame, "Open RP Directory", 160, 24, function()
            PUIRoleplay:OpenDirectory()
        end)
        openDirBtn:SetPoint("LEFT", openSheetBtn, "RIGHT", 12, 0)

        local openCompBtn = Primus.Widgets:CreateButton(frame, "Emote Composer", 160, 24, function()
            PUIRoleplay.Emotes:OpenComposer()
        end)
        openCompBtn:SetPoint("TOPLEFT", openSheetBtn, "BOTTOMLEFT", 0, -8)

        local toggleListenBtn = Primus.Widgets:CreateButton(frame, "Toggle Listener", 160, 24, function()
            if PUIRoleplay.Listener then PUIRoleplay.Listener:Toggle() end
        end)
        toggleListenBtn:SetPoint("LEFT", openCompBtn, "RIGHT", 12, 0)

        local toggleLogsBtn = Primus.Widgets:CreateButton(frame, "View Chat Logs", 160, 24, function()
            if PUIRoleplay.Elephant then PUIRoleplay.Elephant:OpenLogs() end
        end)
        toggleLogsBtn:SetPoint("TOPLEFT", openCompBtn, "BOTTOMLEFT", 0, -8)

        local toggleTrayBtn = Primus.Widgets:CreateButton(frame, "Toggle RP Bar", 160, 24, function()
            if PUIRoleplay.Tray then PUIRoleplay.Tray:Toggle() end
        end)
        toggleTrayBtn:SetPoint("LEFT", toggleLogsBtn, "RIGHT", 12, 0)

        local toggleDiceBtn = Primus.Widgets:CreateButton(frame, "DiceMaster (D20)", 160, 24, function()
            if PUIRoleplay.Dice then PUIRoleplay.Dice:Toggle() end
        end)
        toggleDiceBtn:SetPoint("TOPLEFT", toggleLogsBtn, "BOTTOMLEFT", 0, -8)

        local toggleBagBtn = Primus.Widgets:CreateButton(frame, "RP Bag / Extended", 160, 24, function()
            if PUIRoleplay.Extended then PUIRoleplay.Extended:ToggleBag() end
        end)
        toggleBagBtn:SetPoint("LEFT", toggleDiceBtn, "RIGHT", 12, 0)

        return frame
    end)
end
