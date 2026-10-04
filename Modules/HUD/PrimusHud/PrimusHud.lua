--[[
    PrimusUI Module: PUIHud - Master Coordinator & Event Dispatcher
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Coordinates the 6 PUIHud subsystems:
    1. Wings.lua        - Vertical Player & Target Vitals (HP/Power)
    2. MiniBars.lua     - Dedicated Bar 10 Cockpit Mini-Bars (Slots 109..116)
    3. ActiveAssist.lua - Smart Action Buttons (Threat Peel & MT Assist)
    4. Timers.lua       - Dual-Swing Timers & Timing Rails
    5. Triage.lua       - Central Triage Array & Heal Flash
    6. PUIHud.lua       - Master Coordinator, Alpha Easing & Options Flare
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIHud = Primus.PUIHud or {}
Primus.PUIHud = PUIHud
_G.PUIHud = PUIHud
Primus:RegisterModule("PUIHud", PUIHud, "HUD")

local DB       = Primus.DB
local Utils    = Primus.Utils
local Events   = Primus.Events
local Time     = Primus.Time
local PUIMover = Primus.PUIMover
local Console  = Primus.Console
local Options  = Primus.Options

-- Persistent PUIHud Database Namespace
local hudDB = DB:RegisterNamespace("PUIHud", {
    enabled         = true,
    wingWidth       = 28,
    wingHeight      = 180,
    powerWidth      = 10,
    centerGap       = 120,
    idleAlpha       = 0.20,
    targetAlpha     = 0.80,
    combatAlpha     = 1.00,
    showSwingTimer  = true,
    showCockpitBars = true,
    showTriageArray = true,
})

local hudFrame        = nil
local currentAlpha    = 0.20
local targetAlphaGoal = 0.20

-- =========================================================================
-- ALPHA EASING CALCULATOR
-- =========================================================================

local function ComputeAlphaGoal()
    if not hudDB:Get("enabled", true) then return 0 end

    local mover = PUIMover or Primus.PUIMover
    if mover and mover.IsUnlocked and mover:IsUnlocked() then
        return 1.0
    end

    if UnitAffectingCombat("player") then
        return hudDB:Get("combatAlpha", 1.00)
    end

    if UnitExists("target") then
        return hudDB:Get("targetAlpha", 0.80)
    end

    local curHP = UnitHealth("player") or 0
    local maxHP = UnitHealthMax("player") or 1
    local curPwr = UnitMana("player") or 0
    local maxPwr = UnitManaMax("player") or 1
    local pwrType = UnitPowerType("player") or 0

    if curHP < maxHP then
        return 0.80
    end

    if (pwrType == 0 and maxPwr > 0 and curPwr < maxPwr) or (pwrType == 1 and curPwr > 0) or (pwrType == 3 and curPwr < 100) then
        return 0.70
    end

    return hudDB:Get("idleAlpha", 0.20)
end

-- =========================================================================
-- MASTER HUD FRAME CREATION & SUB-SYSTEM ASSEMBLY
-- =========================================================================

function PUIHud:CreateHUD()
    if hudFrame then return hudFrame end

    local wingW = hudDB:Get("wingWidth", 28)
    local wingH = hudDB:Get("wingHeight", 180)
    local pwrW  = hudDB:Get("powerWidth", 10)
    local gap   = hudDB:Get("centerGap", 120)

    hudFrame = CreateFrame("Frame", "Primus_PUIHudFrame", UIParent)
    hudFrame:SetWidth(gap + (wingW + pwrW + 4) * 2 + 120)
    hudFrame:SetHeight(wingH + 110)
    hudFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -80)
    hudFrame:SetAlpha(currentAlpha)
    hudFrame:EnableMouse(false)

    self.hudFrame = hudFrame

    -- 1. Assemble Vertical Wings (Player Left, Target Right)
    self:BuildWings(hudFrame)

    -- 2. Assemble Timing Rails & Center Bottom Stack (Dual-Swing, Cast Bar, Bottom Anchor, GCD)
    self:BuildTimingRails(hudFrame)

    -- 3. Assemble Dedicated Bar 10 Cockpit Mini-Bars (Left 109..112, Right 113..116, Bottom 117..120)
    local bottomAnchor = self.timingRailFrame and self.timingRailFrame.miniBarAnchor
    self:BuildCockpitMiniBars(hudFrame, self.leftWingFrame, self.rightWingFrame, bottomAnchor)

    -- 4. Assemble Vertical Aura Columns (Player Outside Left Wing, Target Outside Right Wing)
    self:BuildAuraColumns(hudFrame, self.leftWingFrame, self.rightWingFrame)

    -- 5. Assemble ActiveAssist Smart Buttons
    self:BuildActiveAssist(hudFrame, self.leftWingFrame, self.rightWingFrame)

    -- 6. Assemble Central Triage Array
    self:BuildTriage(hudFrame)

    -- Register with PUIMover
    local mover = PUIMover or Primus.PUIMover
    if mover and mover.Register then
        mover:Register(hudFrame, "PUIHud", "PUIHud: Precision Combat HUD", "HUD")
    end

    return hudFrame
end

function PUIHud:IsHudActive()
    if not hudDB:Get("enabled", true) then return false end
    if hudFrame and not hudFrame:IsShown() then return false end
    return true
end

-- =========================================================================
-- OPTIONS FLARE REGISTRATION
-- =========================================================================

function PUIHud:RegisterOptionsFlare()
    local optionsHub = Options or Primus.Options
    if not optionsHub or not optionsHub.RegisterModuleOptions then return end

    optionsHub:RegisterModuleOptions("PUIHud", "HUD", {
        title = "PUIHud: Precision Combat HUD",
        description = "Precision vertical vitals HUD, dual-swing combat rails, and Bar 10 cockpit mini-bars.",
        fields = {
            {
                key = "enabled",
                label = "Enable PUIHud",
                type = "checkbox",
                default = true,
                get = function() return hudDB:Get("enabled", true) end,
                set = function(val)
                    hudDB:Set("enabled", val)
                    if val then PUIHud:OnEnable() else PUIHud:OnDisable() end
                    if Primus.PUIAuras and Primus.PUIAuras.UpdateAuras then
                        Primus.PUIAuras:UpdateAuras()
                    end
                end,
            },
            {
                key = "showCockpitBars",
                label = "Show Bar 10 Cockpit Mini-Bars (Slots 109..116)",
                type = "checkbox",
                default = true,
                get = function() return hudDB:Get("showCockpitBars", true) end,
                set = function(val)
                    hudDB:Set("showCockpitBars", val)
                    PUIHud:UpdateCockpitButtons()
                end,
            },
            {
                key = "showSwingTimer",
                label = "Show Dual Swing & GCD Timing Rails",
                type = "checkbox",
                default = true,
                get = function() return hudDB:Get("showSwingTimer", true) end,
                set = function(val)
                    hudDB:Set("showSwingTimer", val)
                end,
            },
            {
                key = "showTriageArray",
                label = "Show Central Triage Array (MT Pins & Flash)",
                type = "checkbox",
                default = true,
                get = function() return hudDB:Get("showTriageArray", true) end,
                set = function(val)
                    hudDB:Set("showTriageArray", val)
                    PUIHud:UpdateTriageArray()
                end,
            },
            {
                key = "triageSoundAlert",
                label = "Triage Reassurance Sound Warning",
                type = "checkbox",
                default = true,
                get = function() return hudDB:Get("triageSoundAlert", true) end,
                set = function(val) hudDB:Set("triageSoundAlert", val) end,
            },
            {
                key = "triageCriticalThreshold",
                label = "Triage Critical Health Threshold (%)",
                type = "slider",
                min = 20,
                max = 50,
                step = 5,
                default = 35,
                get = function() return hudDB:Get("triageCriticalThreshold", 35) end,
                set = function(val) hudDB:Set("triageCriticalThreshold", val) end,
            },
            {
                key = "centerGap",
                label = "Center HUD Gap (px)",
                type = "slider",
                min = 80,
                max = 240,
                step = 10,
                default = 120,
                get = function() return hudDB:Get("centerGap", 120) end,
                set = function(val)
                    hudDB:Set("centerGap", val)
                end,
            },
            {
                key = "idleAlpha",
                label = "Idle Alpha",
                type = "slider",
                min = 0,
                max = 1,
                step = 0.05,
                default = 0.20,
                get = function() return hudDB:Get("idleAlpha", 0.20) end,
                set = function(val) hudDB:Set("idleAlpha", val) end,
            },
            {
                key = "targetAlpha",
                label = "Target Selected Alpha",
                type = "slider",
                min = 0,
                max = 1,
                step = 0.05,
                default = 0.80,
                get = function() return hudDB:Get("targetAlpha", 0.80) end,
                set = function(val) hudDB:Set("targetAlpha", val) end,
            },
            {
                key = "combatAlpha",
                label = "In-Combat Alpha",
                type = "slider",
                min = 0,
                max = 1,
                step = 0.05,
                default = 1.00,
                get = function() return hudDB:Get("combatAlpha", 1.00) end,
                set = function(val) hudDB:Set("combatAlpha", val) end,
            },
        },
    })
end

-- =========================================================================
-- LIFECYCLE & EVENT DISPATCH
-- =========================================================================

function PUIHud:OnInitialize()
    self:RegisterOptionsFlare()

    -- Subcommand Registration
    if Console and Console.RegisterSubCommand then
        Console:RegisterSubCommand("hud", function(argParam, parts)
            argParam = Utils.Trim(argParam or "")
            local mover = PUIMover or Primus.PUIMover
            if argParam == "" or argParam == "mover" or argParam == "unlock" then
                if mover and mover.Unlock then mover:Unlock("HUD") end
            elseif argParam == "toggle" then
                local cur = hudDB:Get("enabled", true)
                hudDB:Set("enabled", not cur)
                if not cur then PUIHud:OnEnable() else PUIHud:OnDisable() end
                if Primus.PUIAuras and Primus.PUIAuras.UpdateAuras then
                    Primus.PUIAuras:UpdateAuras()
                end
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIHud]: Precision Combat HUD is now " .. (not cur and "ENABLED" or "DISABLED"), "69ccf0"))
            elseif argParam == "testflash" then
                PUIHud:FlashRebound(UnitName("player") or "Main Tank", 42, 68)
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIHud]: Simulated MT Reassurance Flash triggered.", "69ccf0"))
            elseif parts and parts[2] == "gap" and parts[3] then
                local g = tonumber(parts[3]) or 120
                hudDB:Set("centerGap", g)
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIHud]: Center gap set to %d", g), "69ccf0"))
            else
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("=== PrimusUI PUIHud: Precision Combat HUD ===", "69ccf0"))
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("/pui hud [toggle | mover | gap <num> | testflash]", "ffbb33"))
            end
        end, "PUIHud Precision Combat HUD (/pui hud [toggle|mover|gap|testflash])")
    end
end

function PUIHud:OnEnable()
    self:CreateHUD()
    if hudFrame then hudFrame:Show() end

    -- 1. Reactive Vitals Events
    local vitalsEvents = {
        "UNIT_HEALTH", "UNIT_MAXHEALTH",
        "UNIT_MANA", "UNIT_MAXMANA",
        "UNIT_RAGE", "UNIT_ENERGY",
        "PLAYER_TARGET_CHANGED",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
        "PLAYER_ENTERING_WORLD",
        "RAID_ROSTER_UPDATE",
        "PARTY_MEMBERS_CHANGED",
    }

    local count = table.getn(vitalsEvents)
    for i = 1, count do
        Events:Register(vitalsEvents[i], "PUIHud", function()
            PUIHud:UpdatePlayerWing()
            PUIHud:UpdateTargetWing()
            PUIHud:UpdateRightActiveAssist()
            PUIHud:UpdateTriageArray()
            PUIHud:UpdateAuras()
            PUIHud:UpdateCockpitButtons()
        end)
    end

    -- 2. Bar 10 Action Bar Events & Auras
    local actionEvents = {
        "ACTIONBAR_UPDATE_STATE",
        "ACTIONBAR_UPDATE_COOLDOWN",
        "ACTIONBAR_UPDATE_USABLE",
        "ACTIONBAR_SLOT_CHANGED",
        "PLAYER_AURAS_CHANGED",
        "PLAYER_ENTER_COMBAT",
        "PLAYER_LEAVE_COMBAT",
        "START_AUTOREPEAT_SPELL",
        "STOP_AUTOREPEAT_SPELL",
        "UNIT_INVENTORY_CHANGED",
        "BAG_UPDATE",
    }
    local aCount = table.getn(actionEvents)
    for j = 1, aCount do
        Events:Register(actionEvents[j], "PUIHud", function()
            PUIHud:UpdateCockpitButtons()
            PUIHud:UpdateAuras()
        end)
    end

    Events:Register("UNIT_AURA", "PUIHud", function(owner, event, unit)
        if unit == "target" or unit == "player" then
            PUIHud:UpdateAuras()
            PUIHud:UpdateCockpitButtons()
        end
    end)

    -- 3. Tactical Alert Signals
    Events:Listen("PRIMUS_TACTICAL_ALERT", "PUIHud", function() PUIHud:UpdateLeftActiveAssist() end)
    Events:Listen("PRIMUS_TACTICAL_CLAIMED", "PUIHud", function() PUIHud:UpdateLeftActiveAssist() end)
    Events:Listen("PRIMUS_TACTICAL_RESOLVED", "PUIHud", function() PUIHud:UpdateLeftActiveAssist() end)
    Events:Listen("PRIMUS_TACTICAL_DISMISSED", "PUIHud", function() PUIHud:UpdateLeftActiveAssist() end)

    -- 4. Swing Detection Hooks
    Events:Register("START_AUTOREPEAT_SPELL", "PUIHud", function()
        local speed = UnitRangedDamage("player") or 2.5
        PUIHud:TriggerPlayerSwing(speed, true)
    end)

    Events:Register("STOP_AUTOREPEAT_SPELL", "PUIHud", function()
        PUIHud:ResetPlayerSwing()
    end)

    Events:Register("PLAYER_ENTER_COMBAT", "PUIHud", function()
        local speed = UnitAttackSpeed("player") or 2.0
        PUIHud:TriggerPlayerSwing(speed, false)
    end)

    Events:Register("PLAYER_LEAVE_COMBAT", "PUIHud", function()
        PUIHud:ResetPlayerSwing()
    end)

    Events:Listen("PRIMUS_COMBAT_EVENT", "PUIHud", function(owner, data)
        if not data then return end
        if (data.isSwing or data.isRanged) and data.source == UnitName("player") then
            local speed
            if data.isRanged then
                speed = UnitRangedDamage("player") or 2.5
            else
                speed = UnitAttackSpeed("player") or 2.0
            end
            PUIHud:TriggerPlayerSwing(speed, data.isRanged)
        elseif data.isEnemyOnPlayer or (UnitExists("target") and data.source == UnitName("target") and data.isSwing) then
            PUIHud:TriggerEnemySwing(2.0)
        end
    end)

    -- 5. Spellcast & GCD Hook
    local lastCastSpell = nil

    Events:Register("SPELLCAST_START", "PUIHud", function(owner, event, spellName, duration)
        lastCastSpell = spellName
        PUIHud:StartCast(spellName, (duration or 1000) / 1000, false)
        PUIHud:TriggerGCD(1.5)
    end)

    Events:Register("SPELLCAST_STOP", "PUIHud", function()
        if lastCastSpell == "Aimed Shot" or lastCastSpell == "Multi-Shot" or lastCastSpell == "Slam" then
            local isRanged = (lastCastSpell ~= "Slam")
            local speed = isRanged and (UnitRangedDamage("player") or 2.5) or (UnitAttackSpeed("player") or 2.0)
            PUIHud:TriggerPlayerSwing(speed, isRanged)
        end
        lastCastSpell = nil
        PUIHud:StopCast()
    end)

    Events:Register("SPELLCAST_FAILED", "PUIHud", function()
        lastCastSpell = nil
        PUIHud:StopCast()
    end)

    Events:Register("SPELLCAST_INTERRUPTED", "PUIHud", function()
        lastCastSpell = nil
        PUIHud:StopCast()
    end)

    Events:Register("SPELLCAST_DELAYED", "PUIHud", function(owner, event, delayMs)
        PUIHud:CastDelay((delayMs or 0) / 1000)
    end)

    Events:Register("SPELLCAST_CHANNEL_START", "PUIHud", function(owner, event, duration, spellName)
        lastCastSpell = spellName
        PUIHud:StartCast(spellName, (duration or 1000) / 1000, true)
        PUIHud:TriggerGCD(1.5)
    end)

    Events:Register("SPELLCAST_CHANNEL_UPDATE", "PUIHud", function(owner, event, delayMs)
        PUIHud:CastDelay((delayMs or 0) / 1000)
    end)

    Events:Register("SPELLCAST_CHANNEL_STOP", "PUIHud", function()
        lastCastSpell = nil
        PUIHud:StopCast()
    end)

    -- 6. Direct Frame OnUpdate Driver (Swing Bars, GCD, CastBar, Live Range & Alpha Easing)
    local lastCockpitUpdate = 0
    local lastAuraUpdate = 0
    local hudUpdateThrottle = 0
    hudFrame:SetScript("OnUpdate", function()
        local elapsed = arg1 or 0.04
        hudUpdateThrottle = hudUpdateThrottle + elapsed
        if hudUpdateThrottle < 0.033 then return end
        hudUpdateThrottle = 0

        local now = GetTime()

        -- Alpha Easing
        targetAlphaGoal = ComputeAlphaGoal()
        if math.abs(currentAlpha - targetAlphaGoal) > 0.02 then
            if currentAlpha < targetAlphaGoal then
                currentAlpha = currentAlpha + 0.04
            else
                currentAlpha = currentAlpha - 0.04
            end
            currentAlpha = Utils.Clamp(currentAlpha, 0, 1)
            if hudFrame then hudFrame:SetAlpha(currentAlpha) end
        end

        -- Timers & CastBar update
        PUIHud:UpdateTimers(now)

        -- Real-time 10Hz Range, Mana & State Ticker for Cockpit Mini-Bars
        if (now - lastCockpitUpdate) >= 0.10 then
            lastCockpitUpdate = now
            PUIHud:UpdateCockpitButtons()
        end

        -- 1Hz Live Aura Duration Countdown Ticker
        if (now - lastAuraUpdate) >= 1.0 then
            lastAuraUpdate = now
            PUIHud:UpdateAuras()
        end
    end)

    -- Initial refreshes
    self:UpdatePlayerWing()
    self:UpdateTargetWing()
    self:UpdateCockpitButtons()
    self:UpdateLeftActiveAssist()
    self:UpdateRightActiveAssist()
    self:UpdateTriageArray()
    self:HookTriageCombatLog()
    self:UpdateAuras()

    if Primus.PUIAuras and Primus.PUIAuras.UpdateAuras then
        Primus.PUIAuras:UpdateAuras()
    end
end

function PUIHud:OnDisable()
    Time:CancelAll("PUIHud")
    Events:UnregisterOwner("PUIHud")
    Events:UnregisterOwner("PUITriage")

    if hudFrame then
        hudFrame:SetScript("OnUpdate", nil)
        hudFrame:Hide()
    end

    if Primus.PUIAuras and Primus.PUIAuras.UpdateAuras then
        Primus.PUIAuras:UpdateAuras()
    end
end
