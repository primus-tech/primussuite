--[[
    PrimusUI: PUIQuest Database Root Initializer
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Initializes canonical database structures for PUIQuest with zero legacy globals.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIQuest = Primus.PUIQuest or {}
Primus.PUIQuest = PUIQuest
_G.PUIQuest = PUIQuest

PUIQuest.DB = {
    ["areatrigger"] = {},
    ["items"] = {},
    ["meta"] = {},
    ["minimap"] = {},
    ["objects"] = {},
    ["professions"] = {},
    ["quests"] = {},
    ["quests-itemreq"] = {},
    ["refloot"] = {},
    ["units"] = {},
    ["zones"] = {},
    ["locales"] = { ["enUS"] = true },
}
