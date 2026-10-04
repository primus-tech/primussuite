--[[
    PrimusLib Module: AutoMechanics (Auto-Dismount & Auto-Stand)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Handles automatic dismounting on spellcast or taxi, and auto-standing
    when sitting on spellcast attempts.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIAutoMechanics = Primus.PUIAutoMechanics or {}
Primus.PUIAutoMechanics = PUIAutoMechanics
_G.PUIAutoMechanics = PUIAutoMechanics
Primus:RegisterModule("PUIAutoMechanics", PUIAutoMechanics, "Utility")

local DB     = Primus.DB
local Events = Primus.Events
local Debug  = Primus.Debug

local autoDB = DB:RegisterNamespace("PUIAutoMechanics", {
    autoDismount = true,
    autoStand = true,
})

-- Dismount function for Vanilla 1.12
function PUIAutoMechanics:Dismount()
    for i = 0, 15 do
        local buffIndex = GetPlayerBuff(i, "HELPFUL")
        if buffIndex > -1 then
            local texture = GetPlayerBuffTexture(buffIndex)
            -- Common mount icon paths in Vanilla
            if texture and (string.find(texture, "Spell_Nature_Swiftness") or 
                            string.find(texture, "Ability_Mount") or 
                            string.find(texture, "INV_Misc_Foot_") or 
                            string.find(texture, "Spell_Frost_FrostWolf")) then
                CancelPlayerBuff(buffIndex)
                return true
            end
        end
    end
    return false
end

function PUIAutoMechanics:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIAutoMechanics", {
        name = "PUIAutoMechanics",
        category = "Utility",
        label = "Auto Mechanics",
        icon = "Interface\\Icons\\Ability_Mount_Raptor",
        desc = "Auto-dismount on action, auto-stand on spellcast, and auto-skip taxi prompts.",
    })
end

function PUIAutoMechanics:OnInitialize()
    self:RegisterOptionsFlare()
    -- Intercept UI error messages (e.g. "Can't attack while mounted", "You must be standing")
    Events:Register("UI_ERROR_MESSAGE", self, function(owner, event, msg)
        if not msg then return end
        local lowerMsg = string.lower(msg)

        if autoDB:Get("autoDismount") and (
            msg == ERR_ATTACK_MOUNTED or
            msg == ERR_TAXIPLAYERALREADYMOUNTED or
            string.find(lowerMsg, "mounted") or
            string.find(lowerMsg, "dismount")
        ) then
            PUIAutoMechanics:Dismount()
        end

        if autoDB:Get("autoStand") and (
            msg == SPELL_FAILED_NOT_STANDING or
            msg == ERR_NOT_STANDING or
            string.find(lowerMsg, "standing") or
            string.find(lowerMsg, "kneeling") or
            string.find(lowerMsg, "sitting")
        ) then
            DoEmote("STAND")
        end
    end)

    -- Auto-dismount on flight master opening
    Events:Register("TAXIMAP_OPENED", self, function()
        if autoDB:Get("autoDismount") then
            PUIAutoMechanics:Dismount()
        end
    end)
end
