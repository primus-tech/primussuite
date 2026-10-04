--[[
    PrimusUI Module: PUITalk (Options Flare Preferences Schema)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    - Options Flare configuration schema registration for PUITalk.
    - Preferences for divert whispers, audio alerts, auto-pop DMs, and class colors.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus or not Primus.PUITalk then return end

local PUITalk = Primus.PUITalk

-- =========================================================================
-- OPTIONS FLARE REGISTRATION
-- =========================================================================

function PUITalk:RegisterOptionsFlare()
    local Options = Primus.Options
    if not Options or not Options.RegisterModuleOptions then return end

    Options:RegisterModuleOptions("PUITalk", {
        name     = "Social_Talk",
        category = "Social",
        label    = "PUITalk (Autonomous Chat & Social Hub)",
        options  = {
            {
                key     = "divertWhispers",
                type    = "checkbox",
                label   = "Divert Whispers to Messages Tab",
                desc    = "Filters whispers out of standard game chat, routing them cleanly to Tab 2.",
                default = true,
                get     = function() return PUITalk.db:Get("divertWhispers") end,
                set     = function(v) PUITalk.db:Set("divertWhispers", v) end,
            },
            {
                key     = "playSounds",
                type    = "checkbox",
                label   = "Play Sound Notification on Whisper",
                desc    = "Plays an audio chime when an incoming direct message is received.",
                default = true,
                get     = function() return PUITalk.db:Get("playSounds") end,
                set     = function(v) PUITalk.db:Set("playSounds", v) end,
            },
            {
                key     = "autoPopDMs",
                type    = "checkbox",
                label   = "Auto-Open Messages Tab on Whisper",
                desc    = "Automatically displays the PUITalk window and selects Tab 2 on incoming whisper.",
                default = false,
                get     = function() return PUITalk.db:Get("autoPopDMs") end,
                set     = function(v) PUITalk.db:Set("autoPopDMs", v) end,
            },
            {
                key     = "classColors",
                type    = "checkbox",
                label   = "Class Colored Names",
                desc    = "Colors player names by their character class across chat and social tabs.",
                default = true,
                get     = function() return PUITalk.db:Get("classColors") end,
                set     = function(v)
                    PUITalk.db:Set("classColors", v)
                    PUITalk:UpdateClassCache()
                end,
            },
        },
    })
end
