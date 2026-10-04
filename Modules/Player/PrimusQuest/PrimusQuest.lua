--[[
    PrimusUI Module: PUIQuest (Master In-Game Database & Quest Navigation Controller)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Integrated Octo WoW / Turtle WoW engine:
    1. Multi-Indexed In-Game Database (25,000+ items, quests, NPCs, objects).
    2. Real-Time Server Quest Synchronization (.queststatus query via CHAT_MSG_ADDON).
    3. Recursive Pre-requisite & Closed Chain History Completion.
    4. Custom Bitmask Filtering (Goblin: 256, Blood Elf: 512, Classes).
    5. POI World Map Overlays, Clustering, and Dynamic GPS Route Trails.
    6. 3D HUD Navigation Arrow & Minimap Radar with Instance Texture Support.
    7. Backward-Compatible pfDB and pfQuest Global Bridges.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIQuest = Primus.PUIQuest or {}
Primus.PUIQuest = PUIQuest
_G.PUIQuest = PUIQuest
Primus:RegisterModule("PUIQuest", PUIQuest, "Player")

local DB      = Primus.DB
local Events  = Primus.Events
local Utils   = Primus.Utils
local Console = Primus.Console
local Time    = Primus.Time
local Debug   = Primus.Debug

-- Database Web URL (Octo WoW / Turtle WoW database)
PUIQuest.dburl = "https://octowow.st/db/?quest="

-- Completed Quests History
PUIQuest.history = {}

-- Global Compatibility Shims for third-party addons
_G.pfDB = PUIQuest.DB
_G.pfQuest = PUIQuest
_G.pfDatabase = PUIQuest.Database
_G.pfMap = PUIQuest.Map

PUIQuest.db = DB:RegisterNamespace("PUIQuest", {
    enabled             = true,
    turtleMode          = true,     -- Enable Turtle WoW / Octo WoW Custom Extensions
    showWorldMapPins    = true,
    showMinimapPins     = true,
    minimapShape        = "auto",   -- "auto", "round", "square"
    showRouteLines      = true,     -- Glowing route trails connecting player to target
    showAvailableQuests = true,
    showTurnIns         = true,
    showObjectives      = true,
})

-- Ensure global storage alias for external scripts
if _G.PrimusGlobalDB then
    _G.PrimusGlobalDB.PUIQuest = PUIQuest.db.data
end

-- =========================================================================
-- PUBLIC NAVIGATION HANDSHAKE API
-- =========================================================================

function PUIQuest:FocusQuest(questTitle)
    if PUIQuest.Tracker then
        PUIQuest.Tracker:SetFocus(questTitle)
    end
    if PUIQuest.Map then
        PUIQuest.Map:Update()
    end
    if questTitle then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIQuest]: Focused objective target: %s", questTitle), "69ccf0"))
    end
end

function PUIQuest:GetFocusedQuest()
    if PUIQuest.Tracker then
        return PUIQuest.Tracker:GetFocus()
    end
    return nil
end

-- =========================================================================
-- INSTANCE / MINIMAP COMPATIBILITY
-- =========================================================================

function PUIQuest:HasMinimap(map_id)
    -- Disable dungeon minimap by default in instances
    local has_minimap = not IsInInstance()

    -- Enable dungeon minimap if continent is less than 3 (e.g. AV, custom battlegrounds)
    if IsInInstance() and GetCurrentMapContinent() < 3 then
        has_minimap = true
    end

    return has_minimap
end

-- =========================================================================
-- QUEST COMPLETION & PREREQUISITE RESOLUTION
-- =========================================================================

function PUIQuest:IsQuestCompleted(qid)
    if not qid then return false end
    qid = tonumber(qid)
    if not qid then return false end
    if self.history and self.history[qid] then return true end
    if _G.PUIQuest_history and _G.PUIQuest_history[qid] then return true end
    if _G.pfQuest_history and _G.pfQuest_history[qid] then return true end
    return false
end

function PUIQuest:MarkQuestComplete(histTable, qid)
    if not qid or not tonumber(qid) then return end
    qid = tonumber(qid)
    local targetHist = histTable or self.history or {}

    local time = targetHist[qid] and targetHist[qid][1] or 0
    local level = targetHist[qid] and targetHist[qid][2] or 0
    targetHist[qid] = { time, level }

    local questData = self.DB and self.DB["quests"] and self.DB["quests"]["data"]
    if questData and questData[qid] then
        -- Close mutually exclusive quests
        local close = questData[qid]["close"]
        if close then
            for _, cQid in pairs(close) do
                if not targetHist[cQid] then
                    self:MarkQuestComplete(targetHist, cQid)
                end
            end
        end

        -- Close all prerequisite chains
        local pre = questData[qid]["pre"]
        if pre then
            for _, pQid in pairs(pre) do
                if not targetHist[pQid] then
                    self:MarkQuestComplete(targetHist, pQid)
                end
            end
        end
    end
end

function PUIQuest:ArePrereqsCompleted(qid)
    if not qid then return true end
    qid = tonumber(qid)
    if not qid then return true end

    local questData = self.DB and self.DB["quests"] and self.DB["quests"]["data"]
    if not questData or not questData[qid] then return true end
    local qInfo = questData[qid]

    -- 1. Check prerequisite quests
    local pre = qInfo["pre"]
    if pre then
        for _, preQid in pairs(pre) do
            if not self:IsQuestCompleted(preQid) then
                return false
            end
        end
    end

    -- 2. Check race bitmask (Goblin: 256, BloodElf: 512, etc.)
    local raceMask = qInfo["race"]
    if raceMask and type(raceMask) == "number" and raceMask > 0 then
        local _, playerRace = UnitRace("player")
        local bitraces = self.DB and self.DB.bitraces
        if bitraces and playerRace then
            local found = false
            for mask, rName in pairs(bitraces) do
                if string.lower(rName) == string.lower(playerRace) then
                    if math.mod(math.floor(raceMask / mask), 2) == 1 then
                        found = true
                        break
                    end
                end
            end
            if not found then return false end
        end
    end

    -- 3. Check class bitmask
    local classMask = qInfo["class"]
    if classMask and type(classMask) == "number" and classMask > 0 then
        local _, playerClass = UnitClass("player")
        local bitclasses = {
            [1] = "WARRIOR",
            [2] = "PALADIN",
            [4] = "HUNTER",
            [8] = "ROGUE",
            [16] = "PRIEST",
            [64] = "SHAMAN",
            [128] = "MAGE",
            [256] = "WARLOCK",
            [1024] = "DRUID",
        }
        if playerClass then
            local found = false
            for mask, cName in pairs(bitclasses) do
                if cName == playerClass then
                    if math.mod(math.floor(classMask / mask), 2) == 1 then
                        found = true
                        break
                    end
                end
            end
            if not found then return false end
        end
    end

    return true
end

-- =========================================================================
-- SERVER QUEST SYNCHRONIZATION (.queststatus PROTOCOL)
-- =========================================================================

local queryFrame = CreateFrame("Frame", "PUIQuest_ServerSyncFrame", UIParent)
queryFrame:Hide()

queryFrame:SetScript("OnEvent", function()
    if event == "CHAT_MSG_ADDON" and arg1 == "TWQUEST" and arg2 then
        local tokens = Utils.Split(arg2, " ")
        for _, qidStr in ipairs(tokens) do
            local qid = tonumber(qidStr)
            if qid then
                PUIQuest:MarkQuestComplete(this.history, qid)
            end
        end
    end
end)

queryFrame:SetScript("OnShow", function()
    this.history = {}
    this.startTime = GetTime()
    this:RegisterEvent("CHAT_MSG_ADDON")
    SendChatMessage(".queststatus", "GUILD")
end)

queryFrame:SetScript("OnHide", function()
    this:UnregisterEvent("CHAT_MSG_ADDON")

    local count = 0
    for _ in pairs(this.history or {}) do
        count = count + 1
    end

    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIQuest]: A total of %d completed quests synced from server.", count), "69ccf0"))

    PUIQuest.history = this.history
    _G.PUIQuest_history = this.history
    _G.pfQuest_history = this.history
    this.history = nil

    if PUIQuest.Map then PUIQuest.Map:Update() end
    if PUIQuest.Tracker then PUIQuest.Tracker:Update() end
end)

queryFrame:SetScript("OnUpdate", function()
    if GetTime() > (this.startTime or 0) + 3 then
        this:Hide()
    end
end)

function PUIQuest:QueryServer()
    if not IsInGuild() then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIQuest]: Server quest synchronization (.queststatus) requires being in a guild.", "ffbb33"))
        return
    end
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIQuest]: Requesting completed quest status from server (.queststatus)...", "69ccf0"))
    queryFrame:Show()
end

-- =========================================================================
-- OPTIONS FLARE REGISTRATION
-- =========================================================================

function PUIQuest:RegisterOptionsFlare()
    local Options = Primus.Options
    if not Options or not Options.RegisterModuleOptions then return end

    Options:RegisterModuleOptions("PUIQuest", "Player", {
        title = "PUIQuest: Database & Quest Engine",
        description = "Integrated quest navigation, 25,000+ item/NPC database, world map overlays, route connection lines, and Octo WoW / Turtle WoW extensions.",
        icon = "Interface\\Icons\\INV_Misc_Map02",
        fields = {
            {
                key = "enabled",
                label = "Enable PUIQuest Navigation & Database",
                type = "checkbox",
                default = true,
                get = function() return PUIQuest.db:Get("enabled", true) end,
                set = function(val)
                    PUIQuest.db:Set("enabled", val)
                    if val then PUIQuest:OnEnable() else PUIQuest:OnDisable() end
                end,
            },
            {
                key = "turtleMode",
                label = "Enable Turtle WoW / Octo WoW Database Extensions",
                type = "checkbox",
                default = true,
                get = function() return PUIQuest.db:Get("turtleMode", true) end,
                set = function(val)
                    PUIQuest.db:Set("turtleMode", val)
                    if val and PUIQuest.Patchtable then
                        PUIQuest.Patchtable:Apply()
                    end
                    if PUIQuest.Map then PUIQuest.Map:Update() end
                end,
            },
            {
                key = "showMinimapPins",
                label = "Show 3D HUD Navigation Arrow & Minimap Radar",
                type = "checkbox",
                default = true,
                get = function() return PUIQuest.db:Get("showMinimapPins", true) end,
                set = function(val)
                    PUIQuest.db:Set("showMinimapPins", val)
                    if PUIQuest.Tracker then PUIQuest.Tracker:Update() end
                end,
            },
            {
                key = "minimapShape",
                label = "Minimap Radar Shape Clamp",
                type = "dropdown",
                options = {
                    { value = "auto", label = "Auto (Detect Square/Round)" },
                    { value = "round", label = "Classic Round" },
                    { value = "square", label = "Modern Square" },
                },
                default = "auto",
                get = function() return PUIQuest.db:Get("minimapShape", "auto") end,
                set = function(val)
                    PUIQuest.db:Set("minimapShape", val)
                    if PUIQuest.Tracker then PUIQuest.Tracker:Update() end
                end,
            },
            {
                key = "showRouteLines",
                label = "Show Dynamic Route Connection Lines on Map",
                type = "checkbox",
                default = true,
                get = function() return PUIQuest.db:Get("showRouteLines", true) end,
                set = function(val)
                    PUIQuest.db:Set("showRouteLines", val)
                    if PUIQuest.Map then PUIQuest.Map:Update() end
                end,
            },
            {
                key = "showWorldMapPins",
                label = "Show Quest POI Overlays on World Map",
                type = "checkbox",
                default = true,
                get = function() return PUIQuest.db:Get("showWorldMapPins", true) end,
                set = function(val)
                    PUIQuest.db:Set("showWorldMapPins", val)
                    if PUIQuest.Map then PUIQuest.Map:Update() end
                end,
            },
            {
                key = "showAvailableQuests",
                label = "Show Available Quests (!) on World Map",
                type = "checkbox",
                default = true,
                get = function() return PUIQuest.db:Get("showAvailableQuests", true) end,
                set = function(val)
                    PUIQuest.db:Set("showAvailableQuests", val)
                    if PUIQuest.Map then PUIQuest.Map:Update() end
                end,
            },
            {
                key = "showTurnIns",
                label = "Show Active Turn-In Badges (?) on World Map",
                type = "checkbox",
                default = true,
                get = function() return PUIQuest.db:Get("showTurnIns", true) end,
                set = function(val)
                    PUIQuest.db:Set("showTurnIns", val)
                    if PUIQuest.Map then PUIQuest.Map:Update() end
                end,
            },
        },
    })
end

-- =========================================================================
-- LIFECYCLE & EVENT ROUTING
-- =========================================================================

function PUIQuest:OnInitialize()
    self:RegisterOptionsFlare()

    -- Initialize SavedVariable history
    if not _G.PUIQuest_history then
        _G.PUIQuest_history = _G.pfQuest_history or {}
    end
    _G.pfQuest_history = _G.PUIQuest_history
    self.history = _G.PUIQuest_history

    -- Apply Octo / Turtle WoW delta patches & overwrites if enabled
    if PUIQuest.db:Get("turtleMode", true) and PUIQuest.Patchtable then
        PUIQuest.Patchtable:Apply()
    end

    if PUIQuest.Database then
        PUIQuest.Database:BuildIndices()
    end

    if PUIQuest.Quest then
        PUIQuest.Quest:Initialize()
    end

    -- Expose global aliases for legacy / external script support
    _G.pfDB = PUIQuest.DB
    _G.pfQuest = PUIQuest
    _G.pfDatabase = PUIQuest.Database
    _G.pfMap = PUIQuest.Map

    -- CLI Router Integration
    if Console and Console.RegisterSubCommand then
        Console:RegisterSubCommand("quest", function(args)
            PUIQuest:HandleSlashCommand(args)
        end, "PUIQuest navigation & database status (/pui quest)")
        Console:RegisterSubCommand("db", function(args)
            if PUIQuest.Browser then
                PUIQuest.Browser:Toggle()
            end
        end, "Open in-game database browser (/pui db)")
    end
end

function PUIQuest:OnEnable()
    Events:Register("QUEST_LOG_UPDATE", "PUIQuest", function()
        if Primus.PUIMap then Primus.PUIMap:Refresh() elseif PUIQuest.Map then PUIQuest.Map:Update() end
        if PUIQuest.Tracker then PUIQuest.Tracker:Update() end
    end)

    Events:Register("ZONE_CHANGED", "PUIQuest", function()
        if PUIQuest.Map then PUIQuest.Map:Update() end
        if PUIQuest.Tracker then PUIQuest.Tracker:Update() end
    end)

    Events:Register("ZONE_CHANGED_NEW_AREA", "PUIQuest", function()
        if PUIQuest.Map then PUIQuest.Map:Update() end
        if PUIQuest.Tracker then PUIQuest.Tracker:Update() end
    end)

    Events:Register("PLAYER_ENTERING_WORLD", "PUIQuest", function()
        -- Auto cache validation check for custom quests
        if PUIQuest.DB and PUIQuest.DB["quests"] and PUIQuest.DB["quests"]["data-turtle"] then
            local count = 0
            for _ in pairs(PUIQuest.DB["quests"]["data-turtle"]) do
                count = count + 1
            end
            if not _G.PUIQuest_turtlecount or _G.PUIQuest_turtlecount ~= count then
                _G.PUIQuest_turtlecount = count
                _G.pfQuest_turtlecount = count
                if PUIQuest.Database and PUIQuest.Database.Reload then
                    PUIQuest.Database:Reload()
                end
            end
        end

        if PUIQuest.Quest then PUIQuest.Quest:Initialize() end
        if PUIQuest.Map then PUIQuest.Map:Update() end
        if PUIQuest.Tracker then PUIQuest.Tracker:Update() end
    end)

    -- Real-time WorldMap Route & Pin Ticker (0.3s when WorldMap is open)
    Time:Every(0.3, function()
        if WorldMapFrame and WorldMapFrame:IsVisible() and PUIQuest.Map then
            PUIQuest.Map:Update()
        end
    end, nil, "PUIQuest")
end

function PUIQuest:OnDisable()
    Events:UnregisterOwner("PUIQuest")
    Time:CancelAll("PUIQuest")
    if PUIQuest.Map then
        PUIQuest.Map:ClearPins()
        PUIQuest.Map:ClearRoute()
    end
    if PUIQuest.Tracker then
        PUIQuest.Tracker:SetFocus(nil)
    end
end

-- =========================================================================
-- CLI DIAGNOSTICS & SYNC HANDLER
-- =========================================================================

function PUIQuest:HandleSlashCommand(args)
    if not args or args == "" or args == "status" then
        local turtleActive = PUIQuest.db:Get("turtleMode", true)
        local histCount = 0
        for _ in pairs(PUIQuest.history or {}) do histCount = histCount + 1 end

        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("=== PrimusUI: PUIQuest Engine Status ===", "69ccf0"))
        DEFAULT_CHAT_FRAME:AddMessage(string.format("• Turtle/Octo WoW Extensions: |cffffd100%s|r", turtleActive and "ACTIVE" or "DISABLED"))
        DEFAULT_CHAT_FRAME:AddMessage(string.format("• Completed Quests Synced: |cffffd100%d|r", histCount))
        DEFAULT_CHAT_FRAME:AddMessage("• Subcommands: |cffffffff/pui quest sync|r (Server Sync), |cffffffff/pui db|r (Browser), |cffffffff/pui quest focus <title>|r, |cffffffff/pui quest reset|r, |cffffffff/pui quest debug|r")
        return
    end

    local tokens = Utils.Split(args, " ")
    local cmd = string.lower(tokens[1] or "")

    if cmd == "sync" or cmd == "query" then
        self:QueryServer()
    elseif cmd == "browser" or cmd == "db" or cmd == "show" then
        if PUIQuest.Browser then PUIQuest.Browser:Toggle() end
    elseif cmd == "reset" then
        PUIQuest.history = {}
        _G.PUIQuest_history = {}
        _G.pfQuest_history = {}
        if PUIQuest.Map then PUIQuest.Map:Update() end
        if PUIQuest.Tracker then PUIQuest.Tracker:Update() end
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIQuest]: Quest history cache cleared.", "ffbb33"))
    elseif cmd == "turtle" or cmd == "octo" then
        local state = string.lower(tokens[2] or "")
        if state == "on" or state == "1" or state == "enable" then
            PUIQuest.db:Set("turtleMode", true)
            if PUIQuest.Patchtable then PUIQuest.Patchtable:Apply() end
            DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIQuest]: Turtle WoW / Octo WoW extensions enabled.", "69ccf0"))
        elseif state == "off" or state == "0" or state == "disable" then
            PUIQuest.db:Set("turtleMode", false)
            DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIQuest]: Turtle WoW / Octo WoW extensions disabled.", "ffbb33"))
        end
        if PUIQuest.Map then PUIQuest.Map:Update() end
    elseif cmd == "focus" or cmd == "track" then
        table.remove(tokens, 1)
        local title = table.concat(tokens, " ")
        if title and title ~= "" then
            self:FocusQuest(title)
        else
            self:FocusQuest(nil)
            DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIQuest]: Reset to automatic closest-quest navigation.", "ffbb33"))
        end
    elseif cmd == "arrow" or cmd == "debug" then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("=== PUIQuest Navigation Diagnostics ===", "69ccf0"))
        local px, py = GetPlayerMapPosition("player")
        DEFAULT_CHAT_FRAME:AddMessage(string.format("• Player Pos: |cffffd100%.2f, %.2f|r (Zone: %s / %s)", (px or 0)*100, (py or 0)*100, tostring(GetZoneText()), tostring(GetRealZoneText())))
        
        if PUIQuest.Tracker then
            if PUIQuest.Tracker.ResetFacingModel then
                PUIQuest.Tracker:ResetFacingModel()
            end
            if PUIQuest.Tracker.GetFacingInfo then
                local pf, src = PUIQuest.Tracker:GetFacingInfo()
                local deg = math.floor(math.deg(pf or 0) + 0.5)
                DEFAULT_CHAT_FRAME:AddMessage(string.format("• Player Facing: |cffffd100%d°|r (%.2f rad) via |cff69ccf0%s|r", deg, pf or 0, src or "None"))
            end
        end

        local activeTarget = PUIQuest.Tracker and PUIQuest.Tracker:GetActiveTarget()
        if activeTarget then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("• Active Target: |cff00ff00%s|r (%s)", activeTarget.title or "None", activeTarget.text or ""))
            if activeTarget.isDifferentZone then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("• Target Zone: |cffffbb33%s|r (Different Zone)", activeTarget.zoneName or "Unknown"))
            else
                DEFAULT_CHAT_FRAME:AddMessage(string.format("• Distance: |cffffffff%d yd|r (Coords: %.1f, %.1f)", activeTarget.yards or 0, (activeTarget.x or 0)*100, (activeTarget.y or 0)*100))
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("• Active Target: |cffff4444None found (Check quest log)|r")
        end
        local numLog = GetNumQuestLogEntries() or 0
        DEFAULT_CHAT_FRAME:AddMessage(string.format("• Quest Log Entries: |cffffffff%d|r", numLog))
        if PUIQuest.Tracker then
            PUIQuest.Tracker:Update()
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIQuest]: Unknown subcommand. Use '/pui quest' for status.", "ff4444"))
    end
end
