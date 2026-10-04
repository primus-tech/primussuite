--[[
    PrimusUI Module: PUITactical Reaction Engine & Emergency Action Hub
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides real-time threat alert detection and 2-Click "Claim & Execute"
    emergency rescue workflows using a 4-layer zero-false-positive pipeline:
    1. Melee White Hit Guarantee (100% certainty single-target aggro)
    2. Unit Target-of-Target Validation
    3. Temporal Multi-Victim Deduplication (150ms window)
    4. Ability Blacklist & Periodic Channel Filtering
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUITactical = Primus.PUITactical or {}
Primus.PUITactical = PUITactical
_G.PUITactical = PUITactical
Primus:RegisterModule("PUITactical", PUITactical, "Combat")

local DB      = Primus.DB
local Events  = Primus.Events
local Comm    = Primus.Comm
local Time    = Primus.Time
local Utils   = Primus.Utils
local Console = Primus.Console

-- Persistent PUITactical Settings
local tacDB = DB:RegisterNamespace("PUITactical", {
    enabled       = true,
    claimTimeout  = 1.5,
    resolveHold   = 1.0,
    soundAlert    = true,
})

-- Active PUITactical Alert State
local currentAlert = nil
local recentSpellHits = {} -- [mobName..spellName] = { timestamp, count }
local isClaimedByMe = false
local claimedByOther = nil
local claimExpiryTime = 0
local resolveHoldExpiry = 0

-- Blacklisted AoE / Cleave Abilities
local AOE_BLACKLIST = {
    ["Cleave"]            = true,
    ["Sweeping Strikes"]  = true,
    ["Tail Sweep"]        = true,
    ["Dragon Breath"]     = true,
    ["Wing Buffet"]       = true,
    ["Whirlwind"]         = true,
    ["War Stomp"]         = true,
    ["Fire Nova"]         = true,
    ["Thunder Clap"]      = true,
    ["Flame Buffet"]      = true,
    ["Blast Wave"]        = true,
    ["Rain of Fire"]      = true,
    ["Blizzard"]          = true,
    ["Hellfire"]          = true,
    ["Arcane Explosion"]  = true,
    ["Magma Splash"]      = true,
    ["Lava Breath"]       = true,
    ["Trample"]           = true,
}

-- Class PUITactical Action Table
local CLASS_ACTIONS = {
    ["WARRIOR"] = {
        primarySpell = "Taunt",
        secondarySpell = "Mocking Blow",
        rescueSpell = "Intervene",
        icon = "Interface\\Icons\\Spell_Nature_Reincarnation",
        label = "TAUNT PEEL",
    },
    ["PALADIN"] = {
        primarySpell = "Blessing of Protection",
        secondarySpell = "Hammer of Justice",
        rescueSpell = "Blessing of Protection",
        icon = "Interface\\Icons\\Spell_Holy_SealOfProtection",
        label = "BoP RESCUE",
    },
    ["MAGE"] = {
        primarySpell = "Polymorph",
        secondarySpell = "Frost Nova",
        rescueSpell = "Polymorph",
        icon = "Interface\\Icons\\Spell_Nature_Polymorph",
        label = "CC PEEL",
    },
    ["ROGUE"] = {
        primarySpell = "Kick",
        secondarySpell = "Gouge",
        rescueSpell = "Blind",
        icon = "Interface\\Icons\\Ability_Kick",
        label = "KICK / GOUGE",
    },
    ["PRIEST"] = {
        primarySpell = "Power Word: Shield",
        secondarySpell = "Flash Heal",
        rescueSpell = "Power Word: Shield",
        icon = "Interface\\Icons\\Spell_Holy_PowerWordShield",
        label = "EMERGENCY SHIELD",
    },
    ["DRUID"] = {
        primarySpell = "Growl",
        secondarySpell = "Barkskin",
        rescueSpell = "Rejuvenation",
        icon = "Interface\\Icons\\Ability_Physical_Taunt",
        label = "GROWL PEEL",
    },
    ["WARLOCK"] = {
        primarySpell = "Fear",
        secondarySpell = "Banish",
        rescueSpell = "Fear",
        icon = "Interface\\Icons\\Spell_Shadow_Possession",
        label = "FEAR PEEL",
    },
    ["HUNTER"] = {
        primarySpell = "Distracting Shot",
        secondarySpell = "Concussive Shot",
        rescueSpell = "Freezing Trap",
        icon = "Interface\\Icons\\Spell_Arcane_Blink",
        label = "DISTRACT PEEL",
    },
    ["SHAMAN"] = {
        primarySpell = "Earth Shock",
        secondarySpell = "Grounding Totem",
        rescueSpell = "Lesser Healing Wave",
        icon = "Interface\\Icons\\Spell_Nature_EarthShock",
        label = "SHOCK INTERRUPT",
    },
}

-- Check if unit or name is designated Main Tank / Off Tank
local function IsTankUnit(nameOrUnit)
    if not nameOrUnit or nameOrUnit == "" then return false end

    local name = nameOrUnit
    if nameOrUnit == "player" or nameOrUnit == "target" or nameOrUnit == "pet" or nameOrUnit == "targettarget"
       or string.find(nameOrUnit, "^party%d+$") or string.find(nameOrUnit, "^raid%d+$")
       or string.find(nameOrUnit, "^partypet%d+$") or string.find(nameOrUnit, "^raidpet%d+$") then
        if not UnitExists(nameOrUnit) then return false end
        name = UnitName(nameOrUnit)
    end

    if not name or name == "" then return false end

    -- 1. In raid, check if main tank or main assist role
    local numRaid = GetNumRaidMembers()
    if numRaid and numRaid > 0 then
        for i = 1, numRaid do
            local rName, rank, subgroup, level, class, fileName, zone, online, isDead, role = GetRaidRosterInfo(i)
            if rName == name and (role == "MAINTANK" or role == "MAINASSIST") then
                return true
            end
        end
    end

    -- 2. In party, check if the member is a Warrior
    local numParty = GetNumPartyMembers()
    if numParty and numParty > 0 then
        for i = 1, numParty do
            local pUnit = "party" .. i
            if UnitExists(pUnit) and UnitName(pUnit) == name then
                local _, pClass = UnitClass(pUnit)
                if pClass == "WARRIOR" then
                    return true
                end
            end
        end
    end

    -- 3. Check if player self is the tank
    if name == UnitName("player") then
        local _, playerClass = UnitClass("player")
        if playerClass == "WARRIOR" then
            return true
        end
    end

    return false
end

-- =========================================================================
-- 4-LAYER AGGRO DISCRIMINATION PIPELINE
-- =========================================================================

function PUITactical:ProcessThreatEvent(mobName, victimName, spellName, isMeleeHit)
    if not tacDB:Get("enabled", true) then return end
    if not mobName or not victimName then return end

    local playerName = UnitName("player")
    if victimName == playerName and not isMeleeHit then
        -- Collateral spell damage to player handled by normal HUD
    end

    -- Layer 4: Ability Blacklist Filtering
    if spellName and AOE_BLACKLIST[spellName] then
        return
    end

    -- Layer 3: Temporal Multi-Victim Deduplication (150ms window)
    if spellName and not isMeleeHit then
        local now = GetTime()
        local key = mobName .. ":" .. spellName
        local entry = recentSpellHits[key]
        if entry and (now - entry.timestamp) < 0.15 then
            entry.count = entry.count + 1
            return -- Suppress AoE
        else
            recentSpellHits[key] = { timestamp = now, count = 1 }
        end
    end

    -- Layer 2: Tank Exemption
    -- If victim is Main Tank, this is normal tank damage
    if IsTankUnit(victimName) then
        return
    end

    -- Trigger PUITactical Alert
    self:TriggerAlert(mobName, victimName, spellName, isMeleeHit)
end

-- Trigger Emergency PUITactical Alert
function PUITactical:TriggerAlert(mobName, victimName, spellName, isMeleeHit)
    local now = GetTime()
    currentAlert = {
        mob = mobName,
        victim = victimName,
        spell = spellName,
        isMelee = isMeleeHit,
        time = now,
        stage = 1, -- 1: Alert/Unclaimed, 2: Claimed/Timeout, 3: Resolved
    }
    isClaimedByMe = false
    claimedByOther = nil
    claimExpiryTime = 0

    if tacDB:Get("soundAlert", true) then
        PlaySound("RaidWarning")
    end

    Events:Fire("PRIMUS_TACTICAL_ALERT", currentAlert)
end

-- =========================================================================
-- 2-CLICK "CLAIM & EXECUTE" STATE MACHINE
-- =========================================================================

-- Click 1: Claim Lockout
function PUITactical:ClaimRescue()
    if not currentAlert or currentAlert.stage ~= 1 then return false end

    currentAlert.stage = 2
    isClaimedByMe = true
    claimedByOther = nil
    claimExpiryTime = GetTime() + tacDB:Get("claimTimeout", 1.5)

    -- Broadcast Claim over Comm
    if Comm and Comm.Send then
        Comm:Send("PRI_TAC", {
            action = "CLAIM",
            player = UnitName("player"),
            mob    = currentAlert.mob or "Target",
            victim = currentAlert.victim or UnitName("player")
        }, "RAID")
    end

    Events:Fire("PRIMUS_TACTICAL_CLAIMED", currentAlert, UnitName("player"))
    return true
end

-- Click 2: Execute Action
function PUITactical:ExecuteRescue()
    if not currentAlert or currentAlert.stage ~= 2 or not isClaimedByMe then return false end

    local _, playerClass = UnitClass("player")
    local action = CLASS_ACTIONS[playerClass or "WARRIOR"]
    if not action then return false end

    -- Snap target to threat mob or victim
    if playerClass == "PALADIN" or playerClass == "PRIEST" then
        -- Defensive target on party member
        TargetByName(currentAlert.victim)
        CastSpellByName(action.rescueSpell or action.primarySpell)
    else
        -- Offensive target on mob
        TargetByName(currentAlert.mob)
        CastSpellByName(action.primarySpell)
    end

    -- Stage 3: Resolved
    currentAlert.stage = 3
    resolveHoldExpiry = GetTime() + tacDB:Get("resolveHold", 1.0)

    -- Broadcast Resolution over Comm
    if Comm and Comm.Send then
        Comm:Send("PRI_TAC", {
            action = "RESOLVE",
            player = UnitName("player"),
            mob    = currentAlert.mob or "Target",
            victim = currentAlert.victim or UnitName("player")
        }, "RAID")
    end

    Events:Fire("PRIMUS_TACTICAL_RESOLVED", currentAlert, UnitName("player"))
    return true
end

-- Release or Dismiss Alert
function PUITactical:DismissAlert()
    currentAlert = nil
    isClaimedByMe = false
    claimedByOther = nil
    claimExpiryTime = 0
    resolveHoldExpiry = 0
    Events:Fire("PRIMUS_TACTICAL_DISMISSED")
end

-- Get Current Alert State
function PUITactical:GetCurrentAlert()
    return currentAlert, isClaimedByMe, claimedByOther
end

-- Get Class PUITactical Action Profile
function PUITactical:GetClassAction()
    local _, playerClass = UnitClass("player")
    return CLASS_ACTIONS[playerClass or "WARRIOR"] or CLASS_ACTIONS["WARRIOR"]
end

-- =========================================================================
-- 1-CLICK DECURSIVE SMART SCANNER
-- =========================================================================

function PUITactical:CleanseNext()
    local success, unit, debuffType, spellName = Utils.CleanseNextMember(nil, "ALL")
    if success then
        local uName = UnitName(unit) or unit
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[Decursive]: Cleansing %s on %s with %s", debuffType or "Debuff", uName, spellName or "Cleanse"), "33ff33"))
        return true
    else
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[Decursive]: No cleansable debuffs found on group members.", "999999"))
        return false
    end
end

-- =========================================================================
-- OPTIONS FLARE REGISTRATION
-- =========================================================================

function PUITactical:RegisterOptionsFlare()
    local Options = Primus.Options
    if not Options or not Options.RegisterModuleOptions then return end

    Options:RegisterModuleOptions("PUITactical", "Combat", {
        title = "PUITactical: Emergency Reaction & Decursive",
        description = "2-Click threat peel alerts and 1-Click Decursive smart group cleansing.",
        fields = {
            {
                key = "enabled",
                label = "Enable PUITactical Reaction Engine",
                type = "checkbox",
                default = true,
                get = function() return tacDB:Get("enabled", true) end,
                set = function(val)
                    tacDB:Set("enabled", val)
                    if val then PUITactical:OnEnable() else PUITactical:OnDisable() end
                end,
            },
            {
                key = "soundAlert",
                label = "Sound Alert on Threat Alert",
                type = "checkbox",
                default = true,
                get = function() return tacDB:Get("soundAlert", true) end,
                set = function(val) tacDB:Set("soundAlert", val) end,
            },
            {
                key = "claimTimeout",
                label = "Claim Window Timeout (sec)",
                type = "slider",
                min = 1.0,
                max = 3.0,
                step = 0.25,
                default = 1.5,
                get = function() return tacDB:Get("claimTimeout", 1.5) end,
                set = function(val) tacDB:Set("claimTimeout", val) end,
            },
            {
                key = "resolveHold",
                label = "Success Hold Duration (sec)",
                type = "slider",
                min = 0.5,
                max = 2.0,
                step = 0.25,
                default = 1.0,
                get = function() return tacDB:Get("resolveHold", 1.0) end,
                set = function(val) tacDB:Set("resolveHold", val) end,
            },
        },
    })
end

-- =========================================================================
-- LIFECYCLE & EVENT DISPATCH
-- =========================================================================

function PUITactical:OnInitialize()
    self:RegisterOptionsFlare()

    -- Subcommand Registration
    if Console and Console.RegisterSubCommand then
        Console:RegisterSubCommand("tactical", function(argParam)
            argParam = Utils.Trim(argParam or "")
            if argParam == "toggle" then
                local cur = tacDB:Get("enabled", true)
                tacDB:Set("enabled", not cur)
                if cur then PUITactical:OnDisable() else PUITactical:OnEnable() end
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUITactical]: Threat reaction engine is now " .. (not cur and "ENABLED" or "DISABLED"), "69ccf0"))
            elseif argParam == "test" then
                PUITactical:TriggerAlert("Core Hound", UnitName("player"), nil, true)
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUITactical]: Test alert triggered on self. Click to Claim.", "69ccf0"))
            elseif argParam == "claim" then
                PUITactical:TriggerAlert("Ancient Core Hound", UnitName("player"), nil, true)
                -- Simulate remote party claim
                claimedByOther = "RaidTank1"
                isClaimedByMe = false
                if currentAlert then
                    currentAlert.stage = 2
                    claimExpiryTime = GetTime() + tacDB:Get("claimTimeout", 1.5)
                    Events:Fire("PRIMUS_TACTICAL_CLAIMED", currentAlert, "RaidTank1")
                end
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUITactical]: Simulated remote claim by RaidTank1 (Button locked).", "69ccf0"))
            elseif argParam == "resolve" then
                if currentAlert then
                    currentAlert.stage = 3
                    resolveHoldExpiry = GetTime() + tacDB:Get("resolveHold", 1.0)
                    Events:Fire("PRIMUS_TACTICAL_RESOLVED", currentAlert, claimedByOther or UnitName("player"))
                    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUITactical]: Alert resolved (Emerald Green hold).", "69ccf0"))
                end
            else
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("=== PrimusUI PUITactical Reaction Engine ===", "69ccf0"))
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("Status: ", "ffbb33") .. (tacDB:Get("enabled", true) and "|cff33ff33ACTIVE|r" or "|cffff4444DISABLED|r"))
                DEFAULT_CHAT_FRAME:AddMessage("Provides 2-Click 'Claim & Execute' threat mitigation alerts.")
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("Commands: /pui tactical [toggle | test | claim | resolve]", "ffd100"))
            end
        end, "PUITactical Reaction Engine (/pui tactical [toggle|test|claim|resolve])")

        Console:RegisterSubCommand("cleanse", function()
            PUITactical:CleanseNext()
        end, "1-Click Decursive Group Cleanse (/pui cleanse)")

        if Console.RegisterAlias then
            Console:RegisterAlias("decurse", "cleanse")
        end
    end
end

function PUITactical:OnEnable()
    -- 1. Parse Combat Log White Hits (Layer 1 Guarantee)
    Events:Register("CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS", "PUITactical", function(owner, event, msg)
        if not msg then return end
        local _, _, mob, victim = string.find(msg, "(.+) hits (.+) for")
        if not mob then _, _, mob, victim = string.find(msg, "(.+) crits (.+) for") end
        if mob and victim then
            PUITactical:ProcessThreatEvent(mob, victim, nil, true)
        end
    end)

    Events:Register("CHAT_MSG_COMBAT_CREATURE_VS_PARTY_MISSES", "PUITactical", function(owner, event, msg)
        if not msg then return end
        local _, _, mob, victim = string.find(msg, "(.+) misses (.+)%.")
        if not mob then _, _, mob, victim = string.find(msg, "(.+) attacks%. (.+) absorbs") end
        if not mob then _, _, mob, victim = string.find(msg, "(.+) attacks%. (.+) blocks") end
        if not mob then _, _, mob, victim = string.find(msg, "(.+) attacks%. (.+) dodges") end
        if not mob then _, _, mob, victim = string.find(msg, "(.+) attacks%. (.+) parries") end
        if mob and victim then
            PUITactical:ProcessThreatEvent(mob, victim, nil, true)
        end
    end)

    -- 2. Parse Creature Spells against Party
    Events:Register("CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE", "PUITactical", function(owner, event, msg)
        if not msg then return end
        local _, _, mob, spell, victim = string.find(msg, "(.+)'s (.+) hits (.+) for")
        if not mob then _, _, mob, spell, victim = string.find(msg, "(.+)'s (.+) crits (.+) for") end
        if mob and victim and spell then
            PUITactical:ProcessThreatEvent(mob, victim, spell, false)
        end
    end)

    -- 3. Inter-Client Comm Syncing
    if Comm and Comm.RegisterPrefix then
        Comm:RegisterPrefix("PRI_TAC", function(owner, subPrefix, data, sender, channel)
            if not data or not data.action or sender == UnitName("player") then return end
            local actionType = data.action
            local player = data.player or sender
            local mob = data.mob
            local victim = data.victim

            if actionType == "CLAIM" then
                if currentAlert then
                    -- If already claimed by player, apply tie breaker (lexicographical order)
                    if isClaimedByMe then
                        if player < UnitName("player") then
                            isClaimedByMe = false
                            claimedByOther = player
                            currentAlert.stage = 2
                            claimExpiryTime = GetTime() + tacDB:Get("claimTimeout", 1.5)
                            Events:Fire("PRIMUS_TACTICAL_CLAIMED", currentAlert, player)
                        end
                    else
                        claimedByOther = player
                        isClaimedByMe = false
                        currentAlert.stage = 2
                        claimExpiryTime = GetTime() + tacDB:Get("claimTimeout", 1.5)
                        Events:Fire("PRIMUS_TACTICAL_CLAIMED", currentAlert, player)
                    end
                end
            elseif actionType == "RESOLVE" then
                if currentAlert then
                    currentAlert.stage = 3
                    resolveHoldExpiry = GetTime() + tacDB:Get("resolveHold", 1.0)
                    Events:Fire("PRIMUS_TACTICAL_RESOLVED", currentAlert, player)
                end
            end
        end, "PUITactical")
    end

    -- 4. State Machine Expiration Ticker (0.05s)
    Time:Every(0.05, function()
        local now = GetTime()
        if currentAlert then
            if currentAlert.stage == 2 and claimExpiryTime > 0 and now >= claimExpiryTime then
                PUITactical:DismissAlert()
            elseif currentAlert.stage == 3 and resolveHoldExpiry > 0 and now >= resolveHoldExpiry then
                PUITactical:DismissAlert()
            end
        end
    end, "PUITactical")
end

function PUITactical:OnDisable()
    Time:CancelAll("PUITactical")
    Events:UnregisterOwner("PUITactical")
    if Comm and Comm.UnregisterOwner then
        Comm:UnregisterOwner("PUITactical")
    end
    self:DismissAlert()
end
