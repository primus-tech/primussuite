--[[
    PrimusUI Module: PUIHud - Central Triage Array & Reassurance Flash
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides tactical situational awareness:
    - Top Pins: Real-time MT1, MT2, MA vitals and 1-click targeting
    - Heal Flash & Rebound Engine: Emerald green peripheral pulse and toast
      when MT health rebounds from critical levels or receives big direct heals.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIHud = Primus.PUIHud or {}
Primus.PUIHud = PUIHud

local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local DB      = Primus.DB
local Anim    = Primus.Anim
local Events  = Primus.Events

local triageContainer = nil
local triageTopPins   = {}
local healFlashFrame  = nil

-- Rolling MT Health State Table: [unit] = { prevHP, prevPct, isCritical, lastCritTime, name }
local tankHealthState = {}

-- =========================================================================
-- TRIAGE ARRAY BUILDER
-- =========================================================================

function PUIHud:BuildTriage(parent)
    local hudDB = DB:GetNamespace("PUIHud")
    local gap = hudDB and hudDB:Get("centerGap", 120) or 120

    -- 1. Triage Container
    triageContainer = CreateFrame("Frame", "Primus_PUIHud_TriageArray", parent)
    triageContainer:SetWidth(gap)
    triageContainer:SetHeight(70)
    triageContainer:SetPoint("TOP", parent, "TOP", 0, -10)
    triageContainer:EnableMouse(false)

    -- 2. Top Pins (MT1, MT2, MA)
    for i = 1, 3 do
        local pin = CreateFrame("Button", "Primus_PUIHud_TriagePin_" .. i, triageContainer)
        pin:SetWidth(gap / 3 - 2)
        pin:SetHeight(16)
        pin:SetPoint("TOPLEFT", triageContainer, "TOPLEFT", (i - 1) * (gap / 3 + 1), 0)
        pin:SetBackdrop(Media:Fetch("border", "1Pixel"))
        pin:SetBackdropColor(0.10, 0.15, 0.20, 0.80)
        pin:SetBackdropBorderColor(0.30, 0.60, 0.90, 0.90)

        local pinBar = Widgets:CreateStatusBar(pin, gap / 3 - 4, 12, 0, 100)
        pinBar:SetPoint("CENTER", pin, "CENTER", 0, 0)
        pinBar:SetStatusBarColor(0.20, 0.70, 0.30, 1.0)
        pin.bar = pinBar

        local pText = pinBar:CreateFontString(nil, "OVERLAY")
        pText:SetFont(Media:Fetch("font", "Default"), 7, "OUTLINE")
        pText:SetPoint("CENTER", pinBar, "CENTER", 0, 0)
        pText:SetTextColor(1, 1, 1)
        pin.text = pText

        pin:RegisterForClicks("LeftButtonUp")
        pin:SetScript("OnClick", function()
            if this.unit and UnitExists(this.unit) then
                TargetUnit(this.unit)
            end
        end)
        pin:Hide()
        triageTopPins[i] = pin
    end

    -- 3. Reassurance Emerald Green Flash Frame
    healFlashFrame = CreateFrame("Frame", "Primus_PUIHud_HealFlash", parent)
    healFlashFrame:SetWidth(gap + 120)
    healFlashFrame:SetHeight(28)
    healFlashFrame:SetPoint("CENTER", parent, "CENTER", 0, 24)
    healFlashFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
    healFlashFrame:SetBackdropColor(0.05, 0.20, 0.08, 0.85)
    healFlashFrame:SetBackdropBorderColor(0.20, 1.00, 0.40, 1.0)

    local hfText = healFlashFrame:CreateFontString(nil, "OVERLAY")
    hfText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    hfText:SetPoint("CENTER", healFlashFrame, "CENTER", 0, 0)
    hfText:SetTextColor(0.4, 1.0, 0.5)
    healFlashFrame.text = hfText
    healFlashFrame:Hide()

    self.triageContainer = triageContainer
    self.triageTopPins   = triageTopPins
    self.healFlashFrame  = healFlashFrame
end

-- =========================================================================
-- HEAL REASSURANCE FLASH & REBOUND PULSE
-- =========================================================================

function PUIHud:FlashRebound(tankName, deltaPct, curPct)
    if not healFlashFrame then return end
    local hudDB = DB:GetNamespace("PUIHud")
    if hudDB and not hudDB:Get("showTriageArray", true) then return end

    healFlashFrame.text:SetText(string.format("|cff33ff33✨ MT STABILIZED:|r %s (+%d%% |cff88ff88%d%%|r)", tankName or "Main Tank", deltaPct or 0, curPct or 100))
    healFlashFrame:SetBackdropBorderColor(0.20, 1.00, 0.40, 1.0)
    healFlashFrame:SetAlpha(1.0)
    healFlashFrame:Show()

    if hudDB and hudDB:Get("triageSoundAlert", true) then
        PlaySound("RaidWarning")
    end

    if Anim and Anim.Fade then
        Anim:Fade(healFlashFrame, 1.5, 1.0, 0.0)
    end
end

function PUIHud:FlashIncomingHeal(healerName, spellName, victimName, amount)
    if not healFlashFrame then return end
    local hudDB = DB:GetNamespace("PUIHud")
    if hudDB and not hudDB:Get("showTriageArray", true) then return end

    local amtStr = amount and (" (+" .. amount .. ")") or ""
    healFlashFrame.text:SetText(string.format("|cff33ff33✨ %s:|r %s on %s%s", healerName or "Healer", spellName or "Heal", victimName or "Tank", amtStr))
    healFlashFrame:SetBackdropBorderColor(0.30, 0.85, 1.00, 1.0)
    healFlashFrame:SetAlpha(1.0)
    healFlashFrame:Show()

    if Anim and Anim.Fade then
        Anim:Fade(healFlashFrame, 1.2, 1.0, 0.0)
    end
end

-- =========================================================================
-- TRIAGE ARRAY UPDATES & HEALTH REBOUND DETECTION
-- =========================================================================

function PUIHud:UpdateTriageArray()
    local hudDB = DB:GetNamespace("PUIHud")
    if not triageContainer or (hudDB and not hudDB:Get("showTriageArray", true)) then
        if triageContainer then triageContainer:Hide() end
        return
    else
        triageContainer:Show()
    end

    local critThreshold = hudDB and hudDB:Get("triageCriticalThreshold", 35) or 35
    local pinIndex = 0
    local raidMembers = GetNumRaidMembers()

    if raidMembers > 0 then
        for i = 1, raidMembers do
            local rName, rank, subgroup, level, class, fileName, zone, online, isDead, role = GetRaidRosterInfo(i)
            if role == "MAINTANK" or role == "MAINASSIST" then
                pinIndex = pinIndex + 1
                local pin = triageTopPins[pinIndex]
                if pin then
                    local unit = "raid" .. i
                    local curHP, maxHP, pctHP = Utils.GetUnitHealth(unit)
                    pin.unit = unit
                    pin.bar:SetMinMaxValues(0, maxHP)
                    pin.bar:SetValue(curHP)
                    pin.text:SetText(string.format("%s %d%%", string.sub(rName or "Tank", 1, 8), pctHP))
                    pin:Show()

                    -- Health Rebound State Machine
                    local state = tankHealthState[unit]
                    if not state then
                        state = { prevHP = curHP, prevPct = pctHP, isCritical = false, lastCritTime = 0, name = rName }
                        tankHealthState[unit] = state
                    end

                    if pctHP > 0 and pctHP <= critThreshold then
                        state.isCritical = true
                        state.lastCritTime = GetTime()
                    elseif state.isCritical and (pctHP >= 55 or (pctHP - state.prevPct) >= 20) then
                        state.isCritical = false
                        PUIHud:FlashRebound(rName, pctHP - state.prevPct, pctHP)
                    end

                    state.prevHP = curHP
                    state.prevPct = pctHP
                    state.name = rName
                end
            end
            if pinIndex >= 3 then break end
        end
    elseif GetNumPartyMembers() > 0 then
        for i = 1, GetNumPartyMembers() do
            pinIndex = pinIndex + 1
            local pin = triageTopPins[pinIndex]
            if pin then
                local unit = "party" .. i
                local curHP, maxHP, pctHP = Utils.GetUnitHealth(unit)
                local pName = UnitName(unit) or ("Party" .. i)
                pin.unit = unit
                pin.bar:SetMinMaxValues(0, maxHP)
                pin.bar:SetValue(curHP)
                pin.text:SetText(string.format("%s %d%%", string.sub(pName, 1, 8), pctHP))
                pin:Show()

                -- Health Rebound State Machine
                local state = tankHealthState[unit]
                if not state then
                    state = { prevHP = curHP, prevPct = pctHP, isCritical = false, lastCritTime = 0, name = pName }
                    tankHealthState[unit] = state
                end

                if pctHP > 0 and pctHP <= critThreshold then
                    state.isCritical = true
                    state.lastCritTime = GetTime()
                elseif state.isCritical and (pctHP >= 55 or (pctHP - state.prevPct) >= 20) then
                    state.isCritical = false
                    PUIHud:FlashRebound(pName, pctHP - state.prevPct, pctHP)
                end

                state.prevHP = curHP
                state.prevPct = pctHP
                state.name = pName
            end
            if pinIndex >= 3 then break end
        end
    end

    for j = pinIndex + 1, 3 do
        if triageTopPins[j] then triageTopPins[j]:Hide() end
    end
end

-- =========================================================================
-- COMBAT LOG HEAL SNIFFER HOOK
-- =========================================================================

function PUIHud:HookTriageCombatLog()
    local healEvents = {
        "CHAT_MSG_SPELL_PARTY_BUFF",
        "CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF",
        "CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF",
        "CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS",
        "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS",
    }
    local count = table.getn(healEvents)
    for k = 1, count do
        Events:Register(healEvents[k], "PUITriage", function(owner, event, msg)
            if not msg then return end
            local _, _, healer, spell, victim, amount = string.find(msg, "(.+)'s (.+) heals (.+) for (%d+)%.")
            if not healer then
                _, _, healer, spell, victim, amount = string.find(msg, "(.+)'s (.+) critically heals (.+) for (%d+)%.")
            end
            if not healer then
                _, _, victim, amount, healer, spell = string.find(msg, "(.+) gains (%d+) health from (.+)'s (.+)%.")
            end

            if victim and healer and spell then
                -- Check if victim is one of our monitored MT units
                for u, state in pairs(tankHealthState) do
                    if state.name == victim and state.isCritical then
                        state.isCritical = false
                        PUIHud:FlashRebound(victim, 25, 60)
                        break
                    end
                end
            end
        end)
    end
end
