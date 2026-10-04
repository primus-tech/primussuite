--[[
    PrimusUI Module: PUIHud - Dual-Swing Timers & Timing Rails
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides precision combat timing rails:
    - Player Swing Bar (Left): MH/OH & Auto-Shot progression
    - Enemy Swing Bar (Right): Target melee attack cadence
    - GCD / ACD Rail (Center): Global Cooldown ticker
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIHud = Primus.PUIHud or {}
Primus.PUIHud = PUIHud

local Widgets = Primus.Widgets
local Media   = Primus.Media
local DB      = Primus.DB

local timingRailFrame = nil
local playerSwingBar  = nil
local enemySwingBar   = nil
local hudCastBar      = nil
local gcdTickerBar    = nil

local playerSwingStart = 0
local playerSwingDur   = 2.0
local playerIsRanged   = false
local enemySwingStart  = 0
local enemySwingDur    = 2.0
local gcdStart         = 0
local gcdDuration      = 1.5

-- CastBar State
local isCasting        = false
local isChanneling     = false
local castStartTime    = 0
local castDuration     = 0
local castSpellName    = ""

-- =========================================================================
-- TIMING RAILS & CENTER STACK BUILDER
-- =========================================================================

function PUIHud:BuildTimingRails(parent)
    local hudDB = DB:GetNamespace("PUIHud")
    local gap = hudDB and hudDB:Get("centerGap", 120) or 120
    local railWidth = gap + 40
    local bottomMiniBarWidth = 4 * 26 + 3 * 4 -- 116px

    timingRailFrame = CreateFrame("Frame", "Primus_PUIHud_TimingRails", parent)
    timingRailFrame:SetWidth(railWidth)
    timingRailFrame:SetHeight(72)
    timingRailFrame:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0)

    -- ROW 1: ANCHOR FOR BOTTOM MINI-BAR (Inside / Top of stack)
    local miniBarAnchor = CreateFrame("Frame", "Primus_PUIHud_BottomMiniBarAnchor", timingRailFrame)
    miniBarAnchor:SetWidth(bottomMiniBarWidth)
    miniBarAnchor:SetHeight(26)
    miniBarAnchor:SetPoint("TOP", timingRailFrame, "TOP", 0, 0)
    timingRailFrame.miniBarAnchor = miniBarAnchor

    -- ROW 2: DUAL SWING TIMERS (Player Left, Enemy Right - Underneath Bottom Mini-Bar)
    local halfWidth = (railWidth / 2) - 2
    playerSwingBar = Widgets:CreateStatusBar(timingRailFrame, halfWidth, 8, 0, 2.0)
    playerSwingBar:SetPoint("TOPLEFT", timingRailFrame, "TOPLEFT", 0, -30)
    playerSwingBar:SetStatusBarColor(0.40, 0.80, 1.00, 1.0)

    local pSwText = playerSwingBar:CreateFontString(nil, "OVERLAY")
    pSwText:SetFont(Media:Fetch("font", "Default"), 7, "OUTLINE")
    pSwText:SetPoint("LEFT", playerSwingBar, "LEFT", 2, 0)
    pSwText:SetText("Swing")
    pSwText:SetTextColor(1, 1, 1)
    playerSwingBar.label = pSwText

    enemySwingBar = Widgets:CreateStatusBar(timingRailFrame, halfWidth, 8, 0, 2.0)
    enemySwingBar:SetPoint("TOPRIGHT", timingRailFrame, "TOPRIGHT", 0, -30)
    enemySwingBar:SetStatusBarColor(1.00, 0.40, 0.30, 1.0)

    local eSwText = enemySwingBar:CreateFontString(nil, "OVERLAY")
    eSwText:SetFont(Media:Fetch("font", "Default"), 7, "OUTLINE")
    eSwText:SetPoint("RIGHT", enemySwingBar, "RIGHT", -2, 0)
    eSwText:SetText("Enemy")
    eSwText:SetTextColor(1, 1, 1)
    enemySwingBar.label = eSwText

    -- ROW 3: HUD CAST BAR (Underneath Swing Timers)
    hudCastBar = Widgets:CreateStatusBar(timingRailFrame, railWidth, 12, 0, 1.0)
    hudCastBar:SetPoint("TOP", timingRailFrame, "TOP", 0, -42)
    hudCastBar:SetStatusBarColor(1.0, 0.70, 0.10, 1.0)
    hudCastBar:Hide()

    local cIcon = hudCastBar:CreateTexture(nil, "OVERLAY")
    cIcon:SetWidth(12)
    cIcon:SetHeight(12)
    cIcon:SetPoint("RIGHT", hudCastBar, "LEFT", -3, 0)
    cIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    hudCastBar.icon = cIcon

    local cText = hudCastBar:CreateFontString(nil, "OVERLAY")
    cText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    cText:SetPoint("LEFT", hudCastBar, "LEFT", 3, 0)
    cText:SetTextColor(1, 1, 1)
    hudCastBar.spellText = cText

    local cTime = hudCastBar:CreateFontString(nil, "OVERLAY")
    cTime:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    cTime:SetPoint("RIGHT", hudCastBar, "RIGHT", -3, 0)
    cTime:SetTextColor(1, 1, 0.6)
    hudCastBar.timeText = cTime

    -- ROW 4: GCD TICKER RAIL (Underneath HUD Cast Bar)
    gcdTickerBar = Widgets:CreateStatusBar(timingRailFrame, railWidth, 5, 0, 1.5)
    gcdTickerBar:SetPoint("TOP", hudCastBar, "BOTTOM", 0, -3)
    gcdTickerBar:SetStatusBarColor(1.00, 0.85, 0.20, 1.0)

    self.timingRailFrame = timingRailFrame
    self.playerSwingBar  = playerSwingBar
    self.enemySwingBar   = enemySwingBar
    self.hudCastBar      = hudCastBar
    self.gcdTickerBar    = gcdTickerBar
end

-- =========================================================================
-- TIMING & CASTBAR TRIGGERS
-- =========================================================================

function PUIHud:TriggerPlayerSwing(speed, isRanged)
    playerIsRanged = isRanged or false
    if playerIsRanged then
        playerSwingDur = speed or UnitRangedDamage("player") or 2.5
        if playerSwingBar then
            playerSwingBar:SetStatusBarColor(0.70, 0.90, 0.40, 1.0)
        end
    else
        playerSwingDur = speed or UnitAttackSpeed("player") or 2.0
        if playerSwingBar then
            playerSwingBar:SetStatusBarColor(0.40, 0.80, 1.00, 1.0)
        end
    end

    if playerSwingDur <= 0 then playerSwingDur = 2.0 end
    playerSwingStart = GetTime()
    if playerSwingBar then
        playerSwingBar:SetMinMaxValues(0, playerSwingDur)
        playerSwingBar:SetValue(0)
    end
end

function PUIHud:ResetPlayerSwing()
    playerSwingStart = 0
    if playerSwingBar then
        playerSwingBar:SetValue(0)
        if playerSwingBar.label then
            playerSwingBar.label:SetText(playerIsRanged and "Auto Shot" or "Swing")
        end
    end
end

function PUIHud:TriggerEnemySwing(speed)
    enemySwingDur = speed or 2.0
    if enemySwingDur <= 0 then enemySwingDur = 2.0 end
    enemySwingStart = GetTime()
    if enemySwingBar then
        enemySwingBar:SetMinMaxValues(0, enemySwingDur)
        enemySwingBar:SetValue(0)
    end
end

function PUIHud:TriggerGCD(duration)
    gcdDuration = duration or 1.5
    if gcdDuration <= 0 then gcdDuration = 1.5 end
    gcdStart = GetTime()
    if gcdTickerBar then
        gcdTickerBar:SetMinMaxValues(0, gcdDuration)
        gcdTickerBar:SetValue(0)
    end
end

-- CastBar Triggers
function PUIHud:StartCast(spellName, duration, isChan, iconTex)
    if not hudCastBar then return end
    isCasting = not isChan
    isChanneling = isChan or false
    castSpellName = spellName or "Casting"
    castDuration = duration or 1.0
    castStartTime = GetTime()

    hudCastBar:SetMinMaxValues(0, castDuration)
    hudCastBar:SetValue(isChanneling and castDuration or 0)
    hudCastBar.spellText:SetText(castSpellName)
    if iconTex and iconTex ~= "" then
        hudCastBar.icon:SetTexture(iconTex)
        hudCastBar.icon:Show()
    else
        hudCastBar.icon:Hide()
    end
    hudCastBar:SetStatusBarColor(isChanneling and 0.3 or 1.0, isChanneling and 0.8 or 0.7, isChanneling and 1.0 or 0.1, 1.0)
    hudCastBar:Show()
end

function PUIHud:StopCast()
    isCasting = false
    isChanneling = false
    castStartTime = 0
    if hudCastBar then
        hudCastBar:Hide()
    end
end

function PUIHud:CastDelay(delaySec)
    if isCasting and castStartTime > 0 then
        castDuration = castDuration + (delaySec or 0)
        if hudCastBar then hudCastBar:SetMinMaxValues(0, castDuration) end
    elseif isChanneling and castStartTime > 0 then
        castStartTime = castStartTime - (delaySec or 0)
    end
end

-- =========================================================================
-- REAL-TIME TICKER (CALLED AT 0.04s)
-- =========================================================================

function PUIHud:UpdateTimers(now)
    local hudDB = DB:GetNamespace("PUIHud")
    if hudDB and not hudDB:Get("showSwingTimer", true) then
        if timingRailFrame then timingRailFrame:Hide() end
        return
    else
        if timingRailFrame then timingRailFrame:Show() end
    end

    -- 1. Player Swing Progression
    if playerSwingStart > 0 and playerSwingBar then
        local elapsed = now - playerSwingStart
        if elapsed <= playerSwingDur then
            playerSwingBar:SetValue(elapsed)
            if playerSwingBar.label then
                local rem = playerSwingDur - elapsed
                playerSwingBar.label:SetText(string.format("%s %.1fs", (playerIsRanged and "Auto" or "Swing"), rem))
            end
        else
            playerSwingStart = 0
            playerSwingBar:SetValue(playerSwingDur)
            if playerSwingBar.label then
                playerSwingBar.label:SetText(playerIsRanged and "Auto" or "Swing")
            end
        end
    end

    -- 2. Enemy Swing Progression
    if enemySwingStart > 0 and enemySwingBar then
        local elapsed = now - enemySwingStart
        if elapsed <= enemySwingDur then
            enemySwingBar:SetValue(elapsed)
            if enemySwingBar.label then
                local rem = enemySwingDur - elapsed
                enemySwingBar.label:SetText(string.format("Enemy %.1fs", rem))
            end
        else
            enemySwingStart = 0
            enemySwingBar:SetValue(enemySwingDur)
            if enemySwingBar.label then
                enemySwingBar.label:SetText("Enemy")
            end
        end
    end

    -- 3. HUD Cast Bar Progression
    if (isCasting or isChanneling) and hudCastBar and castStartTime > 0 then
        local elapsed = now - castStartTime
        if elapsed <= castDuration then
            if isChanneling then
                hudCastBar:SetValue(castDuration - elapsed)
                hudCastBar.timeText:SetText(string.format("%.1fs", castDuration - elapsed))
            else
                hudCastBar:SetValue(elapsed)
                hudCastBar.timeText:SetText(string.format("%.1fs", castDuration - elapsed))
            end
        else
            self:StopCast()
        end
    end

    -- 4. GCD Rail Progression
    if gcdStart > 0 and gcdTickerBar then
        local elapsed = now - gcdStart
        if elapsed <= gcdDuration then
            gcdTickerBar:SetValue(elapsed)
        else
            gcdStart = 0
            gcdTickerBar:SetValue(gcdDuration)
        end
    end
end
