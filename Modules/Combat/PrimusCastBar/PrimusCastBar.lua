--[[
    PrimusLib Module: CastBarEngine (Spellcast & Channel Monitor)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Monitors player, pet, and target spellcasting, channeling, and delays
    to drive castbar animations across UI frames.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUICastBar = Primus.PUICastBar or {}
Primus.PUICastBar = PUICastBar
_G.PUICastBar = PUICastBar
Primus:RegisterModule("PUICastBar", PUICastBar, "Combat")

local Events = Primus.Events
local Time   = Primus.Time

-- Active Casting States
PUICastBar.castingState = {
    ["player"] = { isCasting = false, isChanneling = false, spell = "", duration = 0, startTime = 0, endTime = 0 },
    ["target"] = { isCasting = false, isChanneling = false, spell = "", duration = 0, startTime = 0, endTime = 0 },
}

function PUICastBar:StartCast(unit, spellName, duration)
    local state = self.castingState[unit]
    if not state then return end

    state.isCasting = true
    state.isChanneling = false
    state.spell = spellName
    state.duration = (duration or 0) / 1000
    state.startTime = GetTime()
    state.endTime = state.startTime + state.duration

    Events:Fire("CASTBAR_START", unit, spellName, state.duration, false)
end

function PUICastBar:StopCast(unit)
    local state = self.castingState[unit]
    if not state then return end

    state.isCasting = false
    state.isChanneling = false
    Events:Fire("CASTBAR_STOP", unit)
end

function PUICastBar:StartChannel(unit, duration, spellName)
    local state = self.castingState[unit]
    if not state then return end

    state.isCasting = false
    state.isChanneling = true
    state.spell = spellName or "Channeling"
    state.duration = (duration or 0) / 1000
    state.startTime = GetTime()
    state.endTime = state.startTime + state.duration

    Events:Fire("CASTBAR_START", unit, state.spell, state.duration, true)
end

function PUICastBar:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUICastBar", {
        name = "PUICastBar",
        category = "Combat",
        label = "Cast Bar Engine",
        icon = "Interface\\Icons\\Spell_Holy_FlashHeal",
        desc = "Monitors spellcast and channel timers across player, pet, and target.",
    })
end

function PUICastBar:OnInitialize()
    self:RegisterOptionsFlare()

    -- Player Spellcast events
    Events:Register("SPELLCAST_START", self, function(owner, event, spellName, duration)
        PUICastBar:StartCast("player", spellName, duration)
    end)

    Events:Register("SPELLCAST_STOP", self, function()
        PUICastBar:StopCast("player")
    end)

    Events:Register("SPELLCAST_FAILED", self, function()
        PUICastBar:StopCast("player")
    end)

    Events:Register("SPELLCAST_INTERRUPTED", self, function()
        PUICastBar:StopCast("player")
    end)

    Events:Register("SPELLCAST_CHANNEL_START", self, function(owner, event, duration, spellName)
        PUICastBar:StartChannel("player", duration, spellName)
    end)

    Events:Register("SPELLCAST_CHANNEL_STOP", self, function()
        PUICastBar:StopCast("player")
    end)
end
