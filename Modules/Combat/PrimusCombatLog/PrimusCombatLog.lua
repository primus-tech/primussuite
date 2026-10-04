--[[
    PrimusLib Module: CombatLogParser (Raw 1.12 Combat String Parser)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    High-performance zero-garbage string parser that converts raw 1.12 combat log
    text into structured event callbacks for damage, heals, casts, and auras.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUICombatLog = Primus.PUICombatLog or {}
Primus.PUICombatLog = PUICombatLog
_G.PUICombatLog = PUICombatLog
Primus:RegisterModule("PUICombatLog", PUICombatLog, "Combat")

local Events = Primus.Events
local Memory = Primus.Memory
local Utils  = Primus.Utils
local Debug  = Primus.Debug

local SWING_SPELLS = {
    ["Auto Shot"] = true,
    ["Shoot"] = true,
    ["Heroic Strike"] = true,
    ["Cleave"] = true,
    ["Raptor Strike"] = true,
    ["Maul"] = true,
    ["Slam"] = true,
    ["Sinister Strike"] = true,
    ["Backstab"] = true,
    ["Ambush"] = true,
    ["Ghostly Strike"] = true,
    ["Hemorrhage"] = true,
    ["Eviscerate"] = true,
    ["Mongoose Bite"] = true,
    ["Wing Clip"] = true,
    ["Counterattack"] = true,
    ["Overpower"] = true,
    ["Revenge"] = true,
    ["Mortal Strike"] = true,
    ["Bloodthirst"] = true,
    ["Whirlwind"] = true,
    ["Shield Slam"] = true,
    ["Ravage"] = true,
    ["Shred"] = true,
    ["Claw"] = true,
    ["Rip"] = true,
    ["Ferocious Bite"] = true,
    ["Swipe"] = true,
    ["Arcane Shot"] = true,
    ["Serpent Sting"] = true,
    ["Concussive Shot"] = true,
    ["Multi-Shot"] = true,
    ["Aimed Shot"] = true,
    ["Distracting Shot"] = true,
    ["Scorpid Sting"] = true,
    ["Viper Sting"] = true,
    ["Scatter Shot"] = true,
    ["Tranquilizing Shot"] = true,
}

local RANGED_SPELLS = {
    ["Auto Shot"] = true,
    ["Shoot"] = true,
    ["Arcane Shot"] = true,
    ["Serpent Sting"] = true,
    ["Concussive Shot"] = true,
    ["Multi-Shot"] = true,
    ["Aimed Shot"] = true,
    ["Distracting Shot"] = true,
    ["Scorpid Sting"] = true,
    ["Viper Sting"] = true,
    ["Scatter Shot"] = true,
    ["Tranquilizing Shot"] = true,
}

local function CleanString(s)
    if not s then return "" end
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "[%.%s]+$", "")
    return s
end

-- Combat event patterns for Vanilla 1.12 English client (robust against trailers and damage schools)
local PATTERNS = {
    -- 1. Player Melee Swings (Hits, Crits, Glancings, Blocks, Absorbs)
    { pattern = "^You hit (.+) for (%d+)", event = "SWING_DAMAGE", isPlayer = true, isCrit = false, isSwing = true, isRanged = false },
    { pattern = "^You crit (.+) for (%d+)", event = "SWING_DAMAGE", isPlayer = true, isCrit = true, isSwing = true, isRanged = false },

    -- 2. Player Ranged Swings (Auto Shot & Wand Shoot)
    { pattern = "^Your Auto Shot hits (.+) for (%d+)", event = "SWING_DAMAGE", isPlayer = true, isCrit = false, isRanged = true, isSwing = true },
    { pattern = "^Your Auto Shot crits (.+) for (%d+)", event = "SWING_DAMAGE", isPlayer = true, isCrit = true, isRanged = true, isSwing = true },
    { pattern = "^Your Shoot hits (.+) for (%d+)", event = "SWING_DAMAGE", isPlayer = true, isCrit = false, isRanged = true, isSwing = true },
    { pattern = "^Your Shoot crits (.+) for (%d+)", event = "SWING_DAMAGE", isPlayer = true, isCrit = true, isRanged = true, isSwing = true },

    -- 3. Player Melee Misses & Defenses
    { pattern = "^You miss (.+)", event = "SWING_MISSED", isPlayer = true, isSwing = true, isRanged = false },
    { pattern = "^You attack%. (.+) dodges", event = "SWING_MISSED", isPlayer = true, isSwing = true, isRanged = false },
    { pattern = "^You attack%. (.+) parries", event = "SWING_MISSED", isPlayer = true, isSwing = true, isRanged = false },
    { pattern = "^You attack%. (.+) blocks", event = "SWING_MISSED", isPlayer = true, isSwing = true, isRanged = false },
    { pattern = "^You attack%. (.+) absorbs", event = "SWING_MISSED", isPlayer = true, isSwing = true, isRanged = false },
    { pattern = "^You hit (.+), who is immune", event = "SWING_MISSED", isPlayer = true, isSwing = true, isRanged = false },

    -- 4. Player Ranged Misses & Defenses (Auto Shot & Shoot)
    { pattern = "^Your Auto Shot missed (.+)", event = "SWING_MISSED", isPlayer = true, isRanged = true, isSwing = true },
    { pattern = "^Your Auto Shot misses (.+)", event = "SWING_MISSED", isPlayer = true, isRanged = true, isSwing = true },
    { pattern = "^Your Auto Shot was dodged by (.+)", event = "SWING_MISSED", isPlayer = true, isRanged = true, isSwing = true },
    { pattern = "^Your Auto Shot was parried by (.+)", event = "SWING_MISSED", isPlayer = true, isRanged = true, isSwing = true },
    { pattern = "^Your Auto Shot was blocked by (.+)", event = "SWING_MISSED", isPlayer = true, isRanged = true, isSwing = true },
    { pattern = "^Your Auto Shot is absorbed by (.+)", event = "SWING_MISSED", isPlayer = true, isRanged = true, isSwing = true },
    { pattern = "^(.+) is immune to your Auto Shot", event = "SWING_MISSED", isPlayer = true, isRanged = true, isSwing = true, isTargetFirst = true },
    { pattern = "^Your Shoot missed (.+)", event = "SWING_MISSED", isPlayer = true, isRanged = true, isSwing = true },
    { pattern = "^Your Shoot misses (.+)", event = "SWING_MISSED", isPlayer = true, isRanged = true, isSwing = true },
    { pattern = "^Your Shoot was dodged by (.+)", event = "SWING_MISSED", isPlayer = true, isRanged = true, isSwing = true },
    { pattern = "^Your Shoot was blocked by (.+)", event = "SWING_MISSED", isPlayer = true, isRanged = true, isSwing = true },
    { pattern = "^Your Shoot is absorbed by (.+)", event = "SWING_MISSED", isPlayer = true, isRanged = true, isSwing = true },
    { pattern = "^(.+) is immune to your Shoot", event = "SWING_MISSED", isPlayer = true, isRanged = true, isSwing = true, isTargetFirst = true },

    -- 5. Enemy Swings on Player (Hits, Crits, Misses, Dodges, Parries, Blocks)
    { pattern = "^(.+) hits you for (%d+)", event = "SWING_DAMAGE", isPlayer = false, isCrit = false, isEnemyOnPlayer = true, isSwing = true },
    { pattern = "^(.+) crits you for (%d+)", event = "SWING_DAMAGE", isPlayer = false, isCrit = true, isEnemyOnPlayer = true, isSwing = true },
    { pattern = "^(.+) misses you", event = "SWING_MISSED", isPlayer = false, isEnemyOnPlayer = true, isSwing = true },
    { pattern = "^(.+) attacks%. You dodge", event = "SWING_MISSED", isPlayer = false, isEnemyOnPlayer = true, isSwing = true },
    { pattern = "^(.+) attacks%. You parry", event = "SWING_MISSED", isPlayer = false, isEnemyOnPlayer = true, isSwing = true },
    { pattern = "^(.+) attacks%. You block", event = "SWING_MISSED", isPlayer = false, isEnemyOnPlayer = true, isSwing = true },
    { pattern = "^(.+) attacks%. You absorb", event = "SWING_MISSED", isPlayer = false, isEnemyOnPlayer = true, isSwing = true },

    -- 6. Player Spell Damage & Abilities (including On-Next-Swing abilities like Heroic Strike, Raptor Strike)
    { pattern = "^Your (.+) hits (.+) for (%d+)", event = "SPELL_DAMAGE", isPlayer = true, isCrit = false },
    { pattern = "^Your (.+) crits (.+) for (%d+)", event = "SPELL_DAMAGE", isPlayer = true, isCrit = true },
    { pattern = "^Your (.+) missed (.+)", event = "SPELL_MISSED", isPlayer = true },
    { pattern = "^Your (.+) was dodged by (.+)", event = "SPELL_MISSED", isPlayer = true },
    { pattern = "^Your (.+) was parried by (.+)", event = "SPELL_MISSED", isPlayer = true },
    { pattern = "^Your (.+) was blocked by (.+)", event = "SPELL_MISSED", isPlayer = true },
    { pattern = "^Your (.+) is absorbed by (.+)", event = "SPELL_MISSED", isPlayer = true },
    { pattern = "^(.+) is immune to your (.+)", event = "SPELL_MISSED", isPlayer = true, isTargetFirst = true },

    -- 7. Player Heals
    { pattern = "^Your (.+) heals (.+) for (%d+)", event = "SPELL_HEAL", isPlayer = true, isCrit = false },
    { pattern = "^Your (.+) critically heals (.+) for (%d+)", event = "SPELL_HEAL", isPlayer = true, isCrit = true },

    -- 8. Enemy / Other Player Spells & Swings
    { pattern = "^(.+)'s (.+) hits you for (%d+)", event = "SPELL_DAMAGE", isPlayer = false, isCrit = false, isEnemyOnPlayer = true },
    { pattern = "^(.+)'s (.+) crits you for (%d+)", event = "SPELL_DAMAGE", isPlayer = false, isCrit = true, isEnemyOnPlayer = true },
    { pattern = "^(.+)'s (.+) hits (.+) for (%d+)", event = "SPELL_DAMAGE", isPlayer = false, isCrit = false },
    { pattern = "^(.+)'s (.+) crits (.+) for (%d+)", event = "SPELL_DAMAGE", isPlayer = false, isCrit = true },
    { pattern = "^(.+) hits (.+) for (%d+)", event = "SWING_DAMAGE", isPlayer = false, isCrit = false, isSwing = true },
    { pattern = "^(.+) crits (.+) for (%d+)", event = "SWING_DAMAGE", isPlayer = false, isCrit = true, isSwing = true },
    { pattern = "^(.+) misses (.+)", event = "SWING_MISSED", isPlayer = false, isSwing = true },
    { pattern = "^(.+) attacks%. (.+) dodges", event = "SWING_MISSED", isPlayer = false, isSwing = true },
    { pattern = "^(.+) attacks%. (.+) parries", event = "SWING_MISSED", isPlayer = false, isSwing = true },
    { pattern = "^(.+) attacks%. (.+) blocks", event = "SWING_MISSED", isPlayer = false, isSwing = true },
    { pattern = "^(.+) attacks%. (.+) absorbs", event = "SWING_MISSED", isPlayer = false, isSwing = true },

    -- 9. Other Heals
    { pattern = "^(.+)'s (.+) heals (.+) for (%d+)", event = "SPELL_HEAL", isPlayer = false, isCrit = false },
    { pattern = "^(.+)'s (.+) critically heals (.+) for (%d+)", event = "SPELL_HEAL", isPlayer = false, isCrit = true },

    -- 10. Aura gains
    { pattern = "^You gain (.+)", event = "SPELL_AURA_APPLIED", isPlayer = true },
    { pattern = "^(.+) gains (.+)", event = "SPELL_AURA_APPLIED", isPlayer = false },
}

local function ParseCombatString(msg)
    if not msg or msg == "" then return end

    local count = table.getn(PATTERNS)
    for i = 1, count do
        local p = PATTERNS[i]
        local s, e, a1, a2, a3, a4 = string.find(msg, p.pattern)
        if s then
            local data = Memory:AcquireTable()
            data.eventType = p.event
            data.isCrit = p.isCrit or false
            data.isRanged = p.isRanged or false
            data.isSwing = p.isSwing or false
            data.isEnemyOnPlayer = p.isEnemyOnPlayer or false
            data.timestamp = GetTime()

            if p.event == "SWING_DAMAGE" then
                if p.isPlayer then
                    data.source = UnitName("player")
                    data.target = CleanString(a1)
                    data.amount = tonumber(a2) or 0
                elseif p.isEnemyOnPlayer then
                    data.source = CleanString(a1)
                    data.target = UnitName("player")
                    data.amount = tonumber(a2) or 0
                else
                    data.source = CleanString(a1)
                    data.target = CleanString(a2)
                    data.amount = tonumber(a3) or 0
                end
            elseif p.event == "SWING_MISSED" then
                if p.isPlayer then
                    data.source = UnitName("player")
                    data.target = CleanString(a1)
                    data.amount = 0
                elseif p.isEnemyOnPlayer then
                    data.source = CleanString(a1 or "Enemy")
                    data.target = UnitName("player")
                    data.amount = 0
                else
                    data.source = CleanString(a1)
                    data.target = CleanString(a2)
                    data.amount = 0
                end
            elseif p.event == "SPELL_DAMAGE" then
                if p.isPlayer then
                    data.source = UnitName("player")
                    data.spellName = CleanString(a1)
                    data.target = CleanString(a2)
                    data.amount = tonumber(a3) or 0
                    data.school = a4 or "Physical"
                elseif p.isEnemyOnPlayer then
                    data.source = CleanString(a1)
                    data.spellName = CleanString(a2)
                    data.target = UnitName("player")
                    data.amount = tonumber(a3) or 0
                else
                    data.source = CleanString(a1)
                    data.spellName = CleanString(a2)
                    data.target = CleanString(a3)
                    data.amount = tonumber(a4) or 0
                end

                -- Dynamic swing classification for on-next-swing abilities
                if data.spellName and SWING_SPELLS[data.spellName] then
                    data.isSwing = true
                    data.isRanged = RANGED_SPELLS[data.spellName] or false
                end
            elseif p.event == "SPELL_MISSED" then
                if p.isPlayer then
                    data.source = UnitName("player")
                    if p.isTargetFirst then
                        data.target = CleanString(a1)
                        data.spellName = CleanString(a2)
                    else
                        data.spellName = CleanString(a1)
                        data.target = CleanString(a2)
                    end
                    data.amount = 0

                    if data.spellName and SWING_SPELLS[data.spellName] then
                        data.isSwing = true
                        data.isRanged = RANGED_SPELLS[data.spellName] or false
                    end
                else
                    data.source = CleanString(a1)
                    data.spellName = CleanString(a2)
                    data.target = CleanString(a3)
                    data.amount = 0
                end
            elseif p.event == "SPELL_HEAL" then
                data.source = p.isPlayer and UnitName("player") or CleanString(a1)
                data.spellName = CleanString(a1)
                data.target = CleanString(a2)
                data.amount = tonumber(a3) or 0
            elseif p.event == "SPELL_AURA_APPLIED" then
                if p.isPlayer then
                    data.target = UnitName("player")
                    data.spellName = CleanString(a1)
                else
                    data.target = CleanString(a1)
                    data.spellName = CleanString(a2)
                end
            end

            -- Fire structured event across Primus signal bus
            Events:Fire("PRIMUS_COMBAT_EVENT", data)
            Memory:ReleaseTable(data)
            return
        end
    end
end

function PUICombatLog:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUICombatLog", {
        name = "PUICombatLog",
        category = "Combat",
        label = "Combat Log Engine",
        icon = "Interface\\Icons\\INV_Misc_Book_09",
        desc = "Processes raw combat log events, threat parsing, and combat telemetry.",
    })
end

function PUICombatLog:OnInitialize()
    self:RegisterOptionsFlare()
    local combatEvents = {
        "CHAT_MSG_SPELL_SELF_DAMAGE",
        "CHAT_MSG_SPELL_SELF_BUFF",
        "CHAT_MSG_SPELL_PARTY_DAMAGE",
        "CHAT_MSG_SPELL_PARTY_BUFF",
        "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE",
        "CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF",
        "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
        "CHAT_MSG_SPELL_CREATURE_VS_SELF_BUFF",
        "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
        "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
        "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE",
        "CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE",
        "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE",
        "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
        "CHAT_MSG_COMBAT_SELF_HITS",
        "CHAT_MSG_COMBAT_SELF_MISSES",
        "CHAT_MSG_COMBAT_PARTY_HITS",
        "CHAT_MSG_COMBAT_PARTY_MISSES",
        "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS",
        "CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES",
        "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS",
        "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES",
        "CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS",
        "CHAT_MSG_COMBAT_CREATURE_VS_PARTY_MISSES",
        "CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS",
        "CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_MISSES",
        "CHAT_MSG_COMBAT_PET_HITS",
        "CHAT_MSG_COMBAT_PET_MISSES",
        "CHAT_MSG_SPELL_PET_DAMAGE",
        "CHAT_MSG_SPELL_PET_BUFF",
    }

    local count = table.getn(combatEvents)
    for i = 1, count do
        Events:Register(combatEvents[i], self, function(owner, event, msg)
            ParseCombatString(msg)
        end)
    end
end
