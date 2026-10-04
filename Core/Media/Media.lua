--[[
    PrimusLib: Shared Media & Skinning Registry
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides a centralized repository for UI styling assets:
    Fonts, Statusbar Textures, Borders, Backdrops, and Sounds.
    All paths verified for native Vanilla WoW 1.12.1 client MPQs.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local Media = Primus.Media
if not Media then
    Media = {}
    Primus.Media = Media
end

-- Storage tables for media types
Media.fonts      = {}
Media.statusbars = {}
Media.borders    = {}
Media.sounds     = {}

-- =========================================================================
-- DEFAULT ASSETS REGISTRATION (1.12.1 Native Assets)
-- =========================================================================

-- Fonts
Media.fonts["Default"]  = "Fonts\\FRIZQT__.TTF"
Media.fonts["Arial"]    = "Fonts\\ARIALN.TTF"
Media.fonts["Morpheus"] = "Fonts\\MORPHEUS.TTF"
Media.fonts["Skurri"]   = "Fonts\\SKURRI.TTF"

-- Statusbars
Media.statusbars["Default"]    = "Interface\\TargetingFrame\\UI-StatusBar"
Media.statusbars["Smooth"]     = "Interface\\TargetingFrame\\UI-StatusBar"
Media.statusbars["Flat"]       = "Interface\\TargetingFrame\\UI-StatusBar"
Media.statusbars["RaidBar"]    = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"

-- Borders / Backdrops
Media.borders["None"] = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = nil,
    tile = false, tileSize = 0, edgeSize = 0,
    insets = { left = 0, right = 0, top = 0, bottom = 0 }
}

Media.borders["1Pixel"] = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
}

Media.borders["Tooltip"] = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
}

Media.borders["Dialog"] = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
}

-- Sounds
Media.sounds["LevelUp"]   = "Sound\\Interface\\LevelUp.wav"
Media.sounds["RaidAlert"] = "Sound\\Interface\\RaidWarning.wav"
Media.sounds["Tell"]      = "Sound\\Interface\\iTellMessage.wav"

-- =========================================================================
-- REGISTRATION & FETCH API
-- =========================================================================

function Media:Register(mediaType, name, pathOrTable)
    if not mediaType or not name or not pathOrTable then return end
    mediaType = string.lower(mediaType)

    if mediaType == "font" then
        self.fonts[name] = pathOrTable
    elseif mediaType == "statusbar" or mediaType == "texture" then
        self.statusbars[name] = pathOrTable
    elseif mediaType == "border" or mediaType == "backdrop" then
        self.borders[name] = pathOrTable
    elseif mediaType == "sound" then
        self.sounds[name] = pathOrTable
    end
end

function Media:Fetch(mediaType, name)
    mediaType = string.lower(mediaType or "")
    if mediaType == "font" then
        return self.fonts[name] or self.fonts["Default"]
    elseif mediaType == "statusbar" or mediaType == "texture" then
        return self.statusbars[name] or self.statusbars["Default"]
    elseif mediaType == "border" or mediaType == "backdrop" then
        return self.borders[name] or self.borders["1Pixel"]
    elseif mediaType == "sound" then
        return self.sounds[name] or self.sounds["RaidAlert"]
    end
    return nil
end
