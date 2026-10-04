--[[
    PrimusLib: Lightweight Animation & Tween Engine
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides smooth easing transitions, frame fades, sliding animations,
    and interpolated status bar updates for Vanilla WoW without AnimationGroups.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local Anim   = Primus.Anim
local Utils  = Primus.Utils

local activeTweens = {}
local tweenIDCounter = 0

-- Easing Formulas
Anim.Ease = {
    Linear = function(t) return t end,
    InQuad = function(t) return t * t end,
    OutQuad = function(t) return t * (2 - t) end,
    InOutQuad = function(t)
        if t < 0.5 then return 2 * t * t else return -1 + (4 - 2 * t) * t end
    end,
}

-- Central Animation Driver Frame
local animFrame = CreateFrame("Frame", "Primus_AnimDriver")
animFrame:Hide()

local function Anim_OnUpdate()
    local elapsed = arg1
    if not elapsed or elapsed <= 0 then return end

    local hasActive = false
    for target, tw in pairs(activeTweens) do
        if tw and type(tw.progress) == "number" and type(tw.duration) == "number" and tw.duration > 0 then
            hasActive = true
            tw.progress = tw.progress + elapsed
            local ratio = tw.progress / tw.duration
            if ratio > 1 then ratio = 1 end
            if ratio < 0 then ratio = 0 end

            local easingFunc = tw.easing or Anim.Ease.OutQuad
            local eased = easingFunc(ratio)
            local currentVal = tw.from + (tw.to - tw.from) * eased

            if tw.onUpdate then
                tw.onUpdate(tw.target, currentVal, ratio)
            end

            if ratio >= 1 then
                local onComplete = tw.onComplete
                -- Clear tween from active table only if it was not replaced during onUpdate
                if activeTweens[target] == tw then
                    activeTweens[target] = nil
                end
                if onComplete then
                    onComplete(tw.target)
                end
            end
        else
            activeTweens[target] = nil
        end
    end

    if not hasActive then
        animFrame:Hide()
    end
end

animFrame:SetScript("OnUpdate", Anim_OnUpdate)

-- Cancel any active tween for a target or ID
function Anim:Cancel(targetOrId)
    if not targetOrId then return end
    if activeTweens[targetOrId] then
        activeTweens[targetOrId] = nil
        return
    end
    for target, tw in pairs(activeTweens) do
        if tw and (tw.id == targetOrId or tw.target == targetOrId) then
            activeTweens[target] = nil
        end
    end
end

-- Create a generic tween
function Anim:Tween(target, duration, fromVal, toVal, easingFunc, onUpdate, onComplete)
    if not target or not duration or duration <= 0 then
        if onUpdate and target and toVal then onUpdate(target, toVal, 1) end
        if onComplete and target then onComplete(target) end
        return nil
    end

    fromVal = fromVal or 0
    toVal = toVal or fromVal

    tweenIDCounter = tweenIDCounter + 1
    local tw = {
        id = tweenIDCounter,
        target = target,
        duration = duration,
        progress = 0,
        from = fromVal,
        to = toVal,
        easing = easingFunc or self.Ease.OutQuad,
        onUpdate = onUpdate,
        onComplete = onComplete,
    }

    activeTweens[target] = tw

    if not animFrame:IsShown() then
        animFrame:Show()
    end

    return tw.id
end

-- Fade Frame Alpha smoothly
function Anim:Fade(frame, duration, fromAlpha, toAlpha, onComplete)
    if not frame or not frame.SetAlpha then return end
    fromAlpha = fromAlpha or (frame:GetAlpha() or 1.0)
    toAlpha = toAlpha or 1.0
    duration = duration or 0.25

    frame:SetAlpha(fromAlpha)
    frame:Show()

    return self:Tween(frame, duration, fromAlpha, toAlpha, self.Ease.OutQuad,
        function(f, val)
            if f and f.SetAlpha then
                f:SetAlpha(val)
            end
        end,
        function(f)
            if toAlpha <= 0 and f and f.Hide then
                f:Hide()
            end
            if onComplete then onComplete(f) end
        end
    )
end

-- Smooth Statusbar Value Transition
function Anim:SmoothBar(statusBar, targetValue, duration)
    if not statusBar or not statusBar.GetValue or not statusBar.SetValue then return end
    local currentValue = statusBar:GetValue() or 0
    targetValue = targetValue or currentValue
    if currentValue == targetValue then return end

    duration = duration or 0.25
    return self:Tween(statusBar, duration, currentValue, targetValue, self.Ease.OutQuad,
        function(bar, val)
            if bar and bar.SetValue then
                bar:SetValue(val)
            end
        end
    )
end
