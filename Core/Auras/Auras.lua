--[[
    PrimusUI Core Subsystem: Primus.Auras (Centralized Unit Aura & Enchant Scanner)
    Target: Vanilla WoW 1.12.1 (Client Build 5875 | Interface 11200 | Lua 5.0.2)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims, Single Domain Owner)
    
    Provides high-performance, single-point cached polling for player buffs, debuffs,
    weapon enchants, and party/raid cleansable afflictions. Eliminates redundant C-API
    queries across UnitFrames, HUD wings, Tactical peeling, and Auras.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local Auras = Primus.Auras or {}
Primus.Auras = Auras
_G.PrimusAuras = Auras

local Events = Primus.Events
local Time   = Primus.Time
local Utils  = Primus.Utils

-- =========================================================================
-- CONSTANTS & COLOR MATRIX
-- =========================================================================

Auras.DISPEL_COLORS = {
    ["Magic"]   = { r = 0.20, g = 0.60, b = 1.00, hex = "3399ff" },
    ["Curse"]   = { r = 0.60, g = 0.00, b = 1.00, hex = "9900ff" },
    ["Poison"]  = { r = 0.00, g = 0.80, b = 0.00, hex = "00cc00" },
    ["Disease"] = { r = 0.90, g = 0.40, b = 0.10, hex = "e66619" },
    ["none"]    = { r = 0.80, g = 0.20, b = 0.20, hex = "cc3333" },
    ["None"]    = { r = 0.80, g = 0.20, b = 0.20, hex = "cc3333" },
}

Auras.CLASS_DEBUFF_PRIORITY = {
    ["PRIEST"]  = { "Magic", "Disease", "Curse", "Poison" },
    ["PALADIN"] = { "Magic", "Poison", "Disease", "Curse" },
    ["DRUID"]   = { "Curse", "Poison", "Magic", "Disease" },
    ["MAGE"]    = { "Curse", "Magic", "Poison", "Disease" },
    ["SHAMAN"]  = { "Poison", "Disease", "Magic", "Curse" },
    ["WARRIOR"] = { "Magic", "Curse", "Poison", "Disease" },
    ["ROGUE"]   = { "Poison", "Magic", "Curse", "Disease" },
    ["HUNTER"]  = { "Poison", "Magic", "Curse", "Disease" },
    ["WARLOCK"] = { "Curse", "Magic", "Poison", "Disease" },
}

-- =========================================================================
-- CACHE STRUCTURE & INVALIDATION
-- =========================================================================

local auraCache = {}         -- [unit] = { lastUpdate = time, buffs = {}, debuffs = {}, totalBuffs = 0, totalDebuffs = 0 }
local weaponEnchantCache = { lastUpdate = 0 }
local CACHE_TTL = 0.10       -- 100ms cache validity window

local function WipeTable(t)
    if not t then return {} end
    for k in pairs(t) do
        t[k] = nil
    end
    t.n = 0
    return t
end

-- =========================================================================
-- PUBLIC AURA QUERY APIS
-- =========================================================================

function Auras:GetDispelColor(dispelType)
    local dt = dispelType or "None"
    return self.DISPEL_COLORS[dt] or self.DISPEL_COLORS["None"]
end

function Auras:InvalidateUnit(unit)
    if unit then
        auraCache[unit] = nil
    else
        auraCache = {}
        weaponEnchantCache.lastUpdate = 0
    end
end

-- Get cached or fresh weapon enchants
function Auras:GetWeaponEnchants()
    local now = GetTime()
    if weaponEnchantCache and (now - (weaponEnchantCache.lastUpdate or 0)) < CACHE_TTL then
        return weaponEnchantCache
    end

    local hasMH, mhExp, mhCharges, hasOH, ohExp, ohCharges = GetWeaponEnchantInfo()
    weaponEnchantCache.lastUpdate = now
    weaponEnchantCache.hasMainHand = hasMH and true or false
    weaponEnchantCache.mainHandExp = (hasMH and mhExp) and (mhExp / 1000) or 0
    weaponEnchantCache.mainHandCharges = mhCharges or 0
    weaponEnchantCache.hasOffHand = hasOH and true or false
    weaponEnchantCache.offHandExp = (hasOH and ohExp) and (ohExp / 1000) or 0
    weaponEnchantCache.offHandCharges = ohCharges or 0

    return weaponEnchantCache
end

-- Get cached or fresh unit aura record
function Auras:GetUnitAuras(unit)
    unit = unit or "player"
    if not UnitExists(unit) then
        return nil
    end

    local now = GetTime()
    local cached = auraCache[unit]
    if cached and (now - cached.lastUpdate) < CACHE_TTL then
        return cached
    end

    cached = cached or { buffs = {}, debuffs = {} }
    WipeTable(cached.buffs)
    WipeTable(cached.debuffs)
    cached.lastUpdate = now

    local bCount = 0
    local dCount = 0

    if unit == "player" then
        -- 1. Player Buffs (using GetPlayerBuff for precise time left & cancellation index)
        for i = 0, 31 do
            local buffIndex, untilCancelled = GetPlayerBuff(i, "HELPFUL")
            if buffIndex > -1 then
                local texture = GetPlayerBuffTexture(buffIndex)
                if texture then
                    bCount = bCount + 1
                    local timeLeft = GetPlayerBuffTimeLeft(buffIndex) or 0
                    local stacks = GetPlayerBuffApplications(buffIndex) or 0
                    cached.buffs[bCount] = {
                        slot = i,
                        buffIndex = buffIndex,
                        texture = texture,
                        stacks = stacks,
                        timeLeft = timeLeft,
                        untilCancelled = untilCancelled == 1,
                        isDebuff = false,
                    }
                end
            end
        end

        -- 2. Player Debuffs
        for i = 0, 15 do
            local debuffIndex = GetPlayerBuff(i, "HARMFUL")
            if debuffIndex > -1 then
                local texture = GetPlayerBuffTexture(debuffIndex)
                if texture then
                    dCount = dCount + 1
                    local timeLeft = GetPlayerBuffTimeLeft(debuffIndex) or 0
                    local stacks = GetPlayerBuffApplications(debuffIndex) or 0
                    local dispelType = GetPlayerBuffDispelType(debuffIndex) or "None"
                    cached.debuffs[dCount] = {
                        slot = i,
                        buffIndex = debuffIndex,
                        texture = texture,
                        stacks = stacks,
                        timeLeft = timeLeft,
                        dispelType = dispelType,
                        isDebuff = true,
                    }
                end
            end
        end
    else
        -- Non-player Units (Target, Party, Raid, Pet)
        for i = 1, 16 do
            local texture, stacks = UnitBuff(unit, i)
            if texture then
                bCount = bCount + 1
                cached.buffs[bCount] = {
                    slot = i,
                    texture = texture,
                    stacks = stacks or 0,
                    timeLeft = 0,
                    isDebuff = false,
                }
            end
        end

        for i = 1, 16 do
            local texture, stacks, dispelType = UnitDebuff(unit, i)
            if texture then
                dCount = dCount + 1
                cached.debuffs[dCount] = {
                    slot = i,
                    texture = texture,
                    stacks = stacks or 0,
                    timeLeft = 0,
                    dispelType = dispelType or "None",
                    isDebuff = true,
                }
            end
        end
    end

    cached.totalBuffs = bCount
    cached.totalDebuffs = dCount
    auraCache[unit] = cached
    return cached
end

-- High-speed query returning the highest priority cleansable debuff across group members
function Auras:GetGroupCleansableDebuffs(playerClass)
    if not playerClass then
        local _, pCls = UnitClass("player")
        playerClass = pCls or "WARRIOR"
    end

    local priorities = self.CLASS_DEBUFF_PRIORITY[playerClass] or { "Magic", "Curse", "Poison", "Disease" }
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    local count = numRaid > 0 and numRaid or numParty
    local prefix = numRaid > 0 and "raid" or "party"

    local units = { "player" }
    for i = 1, count do
        table.insert(units, prefix .. i)
    end

    local results = {}
    local uCount = table.getn(units)

    for i = 1, uCount do
        local u = units[i]
        if UnitExists(u) and not UnitIsDeadOrGhost(u) and UnitIsConnected(u) then
            local auras = self:GetUnitAuras(u)
            if auras and auras.totalDebuffs > 0 then
                for d = 1, auras.totalDebuffs do
                    local debuff = auras.debuffs[d]
                    local dType = debuff.dispelType
                    if dType and dType ~= "None" and dType ~= "none" then
                        -- Check priority score
                        local prioScore = 99
                        local pCount = table.getn(priorities)
                        for p = 1, pCount do
                            if priorities[p] == dType then
                                prioScore = p
                                break
                            end
                        end

                        table.insert(results, {
                            unit = u,
                            unitName = UnitName(u) or u,
                            dispelType = dType,
                            debuffSlot = debuff.slot,
                            texture = debuff.texture,
                            priority = prioScore,
                        })
                    end
                end
            end
        end
    end

    -- Sort by priority (1 = highest)
    table.sort(results, function(a, b)
        return a.priority < b.priority
    end)

    return results
end

-- =========================================================================
-- INITIALIZATION & EVENT DISPATCH
-- =========================================================================

function Auras:Initialize()
    if self.initialized then return end
    self.initialized = true

    if Events and Events.Register then
        Events:Register("UNIT_AURA", "PrimusAuras", function(owner, event, unit)
            if unit then
                Auras:InvalidateUnit(unit)
            end
        end)

        Events:Register("PLAYER_AURAS_CHANGED", "PrimusAuras", function()
            Auras:InvalidateUnit("player")
            weaponEnchantCache.lastUpdate = 0
        end)

        Events:Register("PLAYER_TARGET_CHANGED", "PrimusAuras", function()
            Auras:InvalidateUnit("target")
        end)

        Events:Register("PARTY_MEMBERS_CHANGED", "PrimusAuras", function()
            Auras:InvalidateUnit()
        end)

        Events:Register("RAID_ROSTER_UPDATE", "PrimusAuras", function()
            Auras:InvalidateUnit()
        end)

        Events:Register("PLAYER_ENTERING_WORLD", "PrimusAuras", function()
            Auras:InvalidateUnit()
        end)
    end
end

-- Initialize on file load
Auras:Initialize()
