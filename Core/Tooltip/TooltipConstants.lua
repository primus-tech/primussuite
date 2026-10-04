--[[
    PrimusUI: PUITooltip Master Constants & Defaults (PUITooltipConstants.lua)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUITooltip = Primus.PUITooltip or {}
Primus.PUITooltip = PUITooltip

PUITooltip.Constants = {}
local C = PUITooltip.Constants

--------------------------------------------------------------------------------
-- Database Defaults (Account-Wide / Character Namespace)
--------------------------------------------------------------------------------
PUITooltip.Defaults = {
    anchorMode = "SMART_CORNER", -- "SMART_CORNER", "CURSOR", "MOVER"
    itemQualityBorders = true,
    showHealthBar = true,
    showHealthText = true,
    showTargetOfTarget = true,
    showGuildRank = true,
    showFactionIcon = false,
    hideInCombat = false,
    hideInBattlegrounds = false,
    fontSizeDelta = 0,
    backdropAlpha = 0.95,
}

--------------------------------------------------------------------------------
-- Item Quality Color Definitions
--------------------------------------------------------------------------------
C.QualityColors = {
    [0] = { r = 0.62, g = 0.62, b = 0.62, hex = "9d9d9d", name = "Poor" },
    [1] = { r = 1.00, g = 1.00, b = 1.00, hex = "ffffff", name = "Common" },
    [2] = { r = 0.12, g = 1.00, b = 0.00, hex = "1eff00", name = "Uncommon" },
    [3] = { r = 0.00, g = 0.44, b = 0.87, hex = "0070dd", name = "Rare" },
    [4] = { r = 0.64, g = 0.21, b = 0.93, hex = "a335ee", name = "Epic" },
    [5] = { r = 1.00, g = 0.50, b = 0.00, hex = "ff8000", name = "Legendary" },
    [6] = { r = 0.90, g = 0.80, b = 0.50, hex = "e6cc80", name = "Artifact" },
}

--------------------------------------------------------------------------------
-- Unit Reaction Colors
--------------------------------------------------------------------------------
C.ReactionColors = {
    [1] = { r = 0.90, g = 0.15, b = 0.15, hex = "e62626" }, -- Hated / Hostile
    [2] = { r = 0.90, g = 0.15, b = 0.15, hex = "e62626" }, -- Hostile
    [3] = { r = 0.85, g = 0.45, b = 0.15, hex = "d97326" }, -- Unfriendly
    [4] = { r = 0.95, g = 0.85, b = 0.15, hex = "f2d926" }, -- Neutral
    [5] = { r = 0.15, g = 0.85, b = 0.15, hex = "26d926" }, -- Friendly
    [6] = { r = 0.15, g = 0.85, b = 0.15, hex = "26d926" }, -- Honored
    [7] = { r = 0.15, g = 0.85, b = 0.15, hex = "26d926" }, -- Revered
    [8] = { r = 0.15, g = 0.85, b = 0.15, hex = "26d926" }, -- Exalted
    ["Tapped"] = { r = 0.55, g = 0.55, b = 0.55, hex = "8c8c8c" },
}

--------------------------------------------------------------------------------
-- Class Colors (Standard 1.12.1 Fallback)
--------------------------------------------------------------------------------
C.ClassColors = {
    ["WARRIOR"] = { r = 0.78, g = 0.61, b = 0.43, hex = "c79c6e" },
    ["PALADIN"] = { r = 0.96, g = 0.55, b = 0.73, hex = "f58cba" },
    ["HUNTER"]  = { r = 0.67, g = 0.83, b = 0.45, hex = "abd473" },
    ["ROGUE"]   = { r = 1.00, g = 0.96, b = 0.41, hex = "fff569" },
    ["PRIEST"]  = { r = 1.00, g = 1.00, b = 1.00, hex = "ffffff" },
    ["SHAMAN"]  = { r = 0.00, g = 0.44, b = 0.87, hex = "0070de" },
    ["MAGE"]    = { r = 0.41, g = 0.80, b = 0.94, hex = "69ccf0" },
    ["WARLOCK"] = { r = 0.58, g = 0.51, b = 0.79, hex = "9482c9" },
    ["DRUID"]   = { r = 1.00, g = 0.49, b = 0.04, hex = "ff7d0a" },
}

--------------------------------------------------------------------------------
-- Palette Tokens (PrimusUI Dark Design System)
--------------------------------------------------------------------------------
C.DefaultBackdrop = {
    r = 0.05, g = 0.05, b = 0.07, a = 0.95,
    borderR = 0.25, borderG = 0.25, borderB = 0.30, borderA = 1.0
}
