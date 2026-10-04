--[[
    PrimusUI Core: Centralized Audio & Sound Governor (Audio.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (Lua 5.0.2)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)

    Subsystem: Throttled Sound Playback Engine
    - Enforces a 100ms throttle per sound token to prevent audio clipping/stacking.
    - Transparently resolves both Blizzard sound names and local MPQ sound files.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local Audio = Primus.Audio or {}
Primus.Audio = Audio
_G.Primus.Audio = Audio

local Media = Primus.Media

local lastPlayed = {}
local DEFAULT_THROTTLE = 0.10 -- 100 milliseconds

--------------------------------------------------------------------------------
-- Public Audio API
--------------------------------------------------------------------------------
function Audio:PlaySound(soundName, throttle)
    if not soundName or soundName == "" then return end
    throttle = throttle or DEFAULT_THROTTLE

    local now = GetTime()
    local last = lastPlayed[soundName] or 0
    if (now - last) < throttle then
        return
    end
    lastPlayed[soundName] = now

    -- Check if it's registered in Primus.Media
    if Media and Media.Fetch then
        local mediaPath = Media:Fetch("sound", soundName)
        if mediaPath and type(mediaPath) == "string" and string.find(mediaPath, "%.[wW][aA][vV]$") or string.find(mediaPath, "%.[mM][pP]3$") then
            PlaySoundFile(mediaPath)
            return
        end
    end

    -- If string looks like a file path
    if string.find(soundName, "\\") or string.find(soundName, "%.[wW][aA][vV]") or string.find(soundName, "%.[mM][pP]3") then
        PlaySoundFile(soundName)
        return
    end

    -- Native Blizzard sound token
    PlaySound(soundName)
end

function Audio:PlaySoundFile(filePath, throttle)
    if not filePath or filePath == "" then return end
    throttle = throttle or DEFAULT_THROTTLE

    local now = GetTime()
    local last = lastPlayed[filePath] or 0
    if (now - last) < throttle then
        return
    end
    lastPlayed[filePath] = now

    PlaySoundFile(filePath)
end
