--[[
    PrimusUI: Centralized Frame Hider & Dynamic Zen State Engine
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides two core UI management functions:
    1. Static Structural Suppression ("The Graveyard"):
       - Permanently reparents unwanted Blizzard frames into an unrendered dummy frame.
       - Intercepts and blocks Blizzard FrameXML event loops (BAG_UPDATE, etc.) from forcing frames back on screen.
       - Maintains a registry for clean restoration when options change.
    2. Dynamic Contextual State Management ("Zen Registry"):
       - Standardized registration API for modules to declare contextual visibility rules (combat, target, resting).
       - Supports smooth alpha fading or full Show/Hide modes with Hover-to-Peek temporary reveals.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local Hider = Primus.Hider or {}
Primus.Hider = Hider

local Events = Primus.Events
local Anim   = Primus.Anim
local Time   = Primus.Time
local DB     = Primus.DB

-- =========================================================================
-- 1. UNRENDERED DUMMY FRAME ("THE GRAVEYARD")
-- =========================================================================

local dummyHider = _G["PrimusUI_Hider"]
if not dummyHider then
    dummyHider = CreateFrame("Frame", "PrimusUI_Hider", UIParent)
    dummyHider:Hide()
    dummyHider:SetWidth(1)
    dummyHider:SetHeight(1)
    dummyHider:SetPoint("BOTTOMLEFT", UIParent, "TOPLEFT", -1000, 1000)
    dummyHider:SetFrameStrata("BACKGROUND")
    dummyHider:SetFrameLevel(0)
    dummyHider:EnableMouse(false)
end

Hider.dummyFrame = dummyHider

-- Registry for static suppression
local suppressedRegistry = {}

-- Registry for dynamic state rules
local dynamicRegistry = {}
local peekTimers = {}
local hookedPeekFrames = {}

-- =========================================================================
-- 2. STATIC STRUCTURAL SUPPRESSION API
-- =========================================================================

--- Permanently suppress a frame by reparenting it to the hidden dummy frame
-- @param frame (Frame or string) The UI frame object or global frame name
-- @param opts (table, optional) Custom suppression options
function Hider:Suppress(frame, opts)
    if type(frame) == "string" then
        frame = _G[frame]
    end
    if not frame then return false end

    -- If already suppressed, update or skip
    if suppressedRegistry[frame] then
        frame:SetParent(dummyHider)
        frame:ClearAllPoints()
        frame:Hide()
        return true
    end

    -- Record original parent and anchor points for restoration
    local origParent = frame:GetParent()
    local origPoints = {}
    local numPoints = frame.GetNumPoints and frame:GetNumPoints() or 0
    for i = 1, numPoints do
        local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(i)
        table.insert(origPoints, {
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            xOfs = xOfs,
            yOfs = yOfs
        })
    end

    local origOnShow = frame.GetScript and frame:GetScript("OnShow")

    suppressedRegistry[frame] = {
        frame = frame,
        originalParent = origParent,
        originalPoints = origPoints,
        originalOnShow = origOnShow,
        options = opts or {}
    }

    -- Reparent to hidden dummy and clear anchors
    frame:SetParent(dummyHider)
    frame:ClearAllPoints()
    frame:Hide()

    -- Hook OnShow to force hide if Blizzard events call :Show()
    if frame.SetScript then
        frame:SetScript("OnShow", function()
            if Hider:IsSuppressed(frame) then
                frame:Hide()
            elseif origOnShow then
                origOnShow()
            end
        end)
    end

    return true
end

--- Restore a previously suppressed frame back to an active parent
-- @param frame (Frame or string) The UI frame object or global name
-- @param targetParent (Frame, optional) New parent to assign, defaults to original parent
function Hider:Unsuppress(frame, targetParent)
    if type(frame) == "string" then
        frame = _G[frame]
    end
    if not frame then return false end

    local record = suppressedRegistry[frame]
    if not record then return false end

    local parentToUse = targetParent or record.originalParent or UIParent
    frame:SetParent(parentToUse)
    frame:ClearAllPoints()

    -- Restore original points if targetParent was not explicitly supplied
    if not targetParent and record.originalPoints then
        local count = table.getn(record.originalPoints)
        for i = 1, count do
            local pt = record.originalPoints[i]
            frame:SetPoint(pt.point, pt.relativeTo or parentToUse, pt.relativePoint, pt.xOfs or 0, pt.yOfs or 0)
        end
    end

    -- Restore OnShow script
    if frame.SetScript then
        frame:SetScript("OnShow", record.originalOnShow)
    end

    suppressedRegistry[frame] = nil
    frame:Show()
    return true
end

--- Check if a frame is currently suppressed in the Graveyard
-- @param frame (Frame or string)
function Hider:IsSuppressed(frame)
    if type(frame) == "string" then
        frame = _G[frame]
    end
    return suppressedRegistry[frame] ~= nil
end

--- Return the hidden dummy frame
function Hider:GetHiderFrame()
    return dummyHider
end

-- =========================================================================
-- 3. DYNAMIC CONTEXTUAL / ZEN REGISTRATION API
-- =========================================================================

--- Register a frame for dynamic contextual visibility (combat, target, resting)
-- @param frame (Frame or string) The UI frame to manage
-- @param key (string) Unique key identifier
-- @param opts (table) Configuration options:
--   - mode: "fade" (default) or "hide"
--   - fadeOnCombat: boolean (default true)
--   - fadeOutOfCombat: boolean (default false)
--   - fadeOnNoTarget: boolean (default false)
--   - fadeOnResting: boolean (default false)
--   - enableHoverPeek: boolean (default true)
--   - combatAlpha: number (default 0.0)
--   - idleAlpha: number (default 1.0)
--   - fadeDuration: number (default 0.25)
--   - peekDuration: number (default 3.0)
function Hider:RegisterDynamic(frame, key, opts)
    if type(frame) == "string" then
        frame = _G[frame]
    end
    if not frame then return false end

    key = key or (frame.GetName and frame:GetName()) or tostring(frame)
    opts = opts or {}

    local entry = {
        frame = frame,
        key = key,
        mode = opts.mode or "fade",
        fadeOnCombat = (opts.fadeOnCombat ~= false),
        fadeOutOfCombat = (opts.fadeOutOfCombat == true),
        fadeOnNoTarget = (opts.fadeOnNoTarget == true),
        fadeOnResting = (opts.fadeOnResting == true),
        enableHoverPeek = (opts.enableHoverPeek ~= false),
        combatAlpha = opts.combatAlpha or 0.0,
        idleAlpha = opts.idleAlpha or 1.0,
        fadeDuration = opts.fadeDuration or 0.25,
        peekDuration = opts.peekDuration or 3.0,
        isPeeking = false
    }

    dynamicRegistry[key] = entry

    -- Set up hover-to-peek if enabled
    if entry.enableHoverPeek and not hookedPeekFrames[key] then
        hookedPeekFrames[key] = true
        if frame.EnableMouse then
            frame:EnableMouse(true)
        end
        local origEnter = frame.GetScript and frame:GetScript("OnEnter")
        frame:SetScript("OnEnter", function()
            if origEnter then origEnter() end
            Hider:PeekFrame(frame, key)
        end)
    end

    return true
end

--- Unregister a frame from dynamic management
-- @param keyOrFrame (string or Frame)
function Hider:UnregisterDynamic(keyOrFrame)
    local key = keyOrFrame
    if type(keyOrFrame) ~= "string" and keyOrFrame.GetName then
        key = keyOrFrame:GetName() or tostring(keyOrFrame)
    end
    if dynamicRegistry[key] then
        dynamicRegistry[key] = nil
        peekTimers[key] = nil
        return true
    end
    return false
end

--- Get all registered dynamic entries
function Hider:GetDynamicFrames()
    return dynamicRegistry
end

--- Temporarily reveal (peek) a faded/hidden frame
-- @param frame (Frame or string)
-- @param key (string, optional)
function Hider:PeekFrame(frame, key)
    if type(frame) == "string" then
        frame = _G[frame]
    end
    if not frame then return end

    key = key or (frame.GetName and frame:GetName()) or tostring(frame)
    local entry = dynamicRegistry[key]
    if not entry then return end

    -- Cancel active peek timer
    peekTimers[key] = nil
    entry.isPeeking = true

    if entry.mode == "hide" then
        frame:Show()
    else
        local curAlpha = frame:GetAlpha() or 0.0
        if Anim and Anim.Fade then
            Anim:Fade(frame, 0.15, curAlpha, entry.idleAlpha or 1.0)
        else
            frame:SetAlpha(entry.idleAlpha or 1.0)
        end
    end

    peekTimers[key] = GetTime() + (entry.peekDuration or 3.0)
end

--- Evaluate whether an entry should be suppressed/faded based on current state
local function ShouldFadeEntry(entry, stateConditions)
    local inCombat  = stateConditions.inCombat
    local hasTarget = stateConditions.hasTarget
    local isResting = stateConditions.isResting

    if entry.fadeOnCombat and inCombat then
        return true
    end
    if entry.fadeOutOfCombat and not inCombat then
        return true
    end
    if entry.fadeOnNoTarget and not hasTarget then
        return true
    end
    if entry.fadeOnResting and isResting then
        return true
    end

    return false
end

--- Apply dynamic state across all registered frames
-- @param stateConditions table containing { inCombat = bool, hasTarget = bool, isResting = bool, enabled = bool }
function Hider:ApplyDynamicState(stateConditions)
    if not stateConditions then
        stateConditions = {
            inCombat = UnitAffectingCombat and (UnitAffectingCombat("player") and true or false) or false,
            hasTarget = UnitExists and (UnitExists("target") and true or false) or false,
            isResting = IsResting and (IsResting() and true or false) or false,
            enabled = true
        }
    end

    if stateConditions.enabled == false then
        -- Reset all dynamic frames to idle state
        for key, entry in pairs(dynamicRegistry) do
            local f = entry.frame
            if f then
                if entry.mode == "hide" then
                    f:Show()
                else
                    f:SetAlpha(entry.idleAlpha or 1.0)
                end
            end
        end
        return
    end

    for key, entry in pairs(dynamicRegistry) do
        local f = entry.frame
        if f and not entry.isPeeking then
            local shouldFade = ShouldFadeEntry(entry, stateConditions)
            local targetAlpha = shouldFade and entry.combatAlpha or entry.idleAlpha
            local duration = entry.fadeDuration or 0.25

            if entry.mode == "hide" then
                if shouldFade then
                    f:Hide()
                else
                    f:Show()
                end
            else
                local curAlpha = f:GetAlpha() or 1.0
                if math.abs(curAlpha - targetAlpha) > 0.05 then
                    if Anim and Anim.Fade then
                        Anim:Fade(f, duration, curAlpha, targetAlpha)
                    else
                        f:SetAlpha(targetAlpha)
                    end
                end
            end
        end
    end
end

-- =========================================================================
-- 4. TICKER FOR PEEK TIMER EXPIRATION
-- =========================================================================

local function DynamicPeekTicker()
    local now = GetTime()
    local inCombat  = UnitAffectingCombat and (UnitAffectingCombat("player") and true or false) or false
    local hasTarget = UnitExists and (UnitExists("target") and true or false) or false
    local isResting = IsResting and (IsResting() and true or false) or false

    local stateConditions = {
        inCombat = inCombat,
        hasTarget = hasTarget,
        isResting = isResting,
        enabled = true
    }

    for key, expireTime in pairs(peekTimers) do
        if now >= expireTime then
            peekTimers[key] = nil
            local entry = dynamicRegistry[key]
            if entry and entry.frame then
                entry.isPeeking = false
                local shouldFade = ShouldFadeEntry(entry, stateConditions)
                local targetAlpha = shouldFade and entry.combatAlpha or entry.idleAlpha
                local duration = entry.fadeDuration or 0.25

                if entry.mode == "hide" then
                    if shouldFade then entry.frame:Hide() else entry.frame:Show() end
                else
                    if Anim and Anim.Fade then
                        Anim:Fade(entry.frame, duration, entry.frame:GetAlpha() or 1.0, targetAlpha)
                    else
                        entry.frame:SetAlpha(targetAlpha)
                    end
                end
            end
        end
    end
end

-- =========================================================================
-- 5. INITIALIZATION & LIFECYCLE
-- =========================================================================

function Hider:OnInitialize()
    if Time and Time.Every then
        Time:Every(0.1, DynamicPeekTicker)
    end
end

Primus:RegisterModule("Hider", Hider, "Core")
