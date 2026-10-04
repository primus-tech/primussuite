--[[
    PrimusLib Module: Class_Warrior (Rage, Stance, Session DPS & Threat/Intervene Suite)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Tracks:
    1. Active Stance (Battle, Defensive, Berserker) and real-time Rage.
    2. Sunder Armor stack counter on current target.
    3. Session vs All-Time damage dealt and live combat DPS.
    4. Party threat/aggro scanner with 1-click Intervene and Taunt alerts.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local _, playerClass = UnitClass("player")
if playerClass ~= "WARRIOR" then return end

local PUIWarrior = Primus.PUIWarrior or {}
Primus.PUIWarrior = PUIWarrior
_G.PUIWarrior = PUIWarrior
Primus:RegisterModule("PUIWarrior", PUIWarrior, "Classes")

local DB      = Primus.DB
local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local Events  = Primus.Events
local Time    = Primus.Time
local PUIMover = Primus.PUIMover

local warriorDB = DB:RegisterNamespace("PUIWarrior", {
    enabled = true,
    allTimeDamage = 0,
})

local hudFrame = nil
local rageBar = nil

-- Damage Statistics
local sessionDamage = 0
local combatStartTime = 0
local totalCombatTime = 0
local inCombat = false

-- Stance Names & Icons
local STANCES = {
    [1] = { name = "Battle",    icon = "Interface\\Icons\\Ability_Warrior_OffensiveStance", color = { 0.9, 0.4, 0.2 } },
    [2] = { name = "Defensive", icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance", color = { 0.2, 0.6, 1.0 } },
    [3] = { name = "Berserker", icon = "Interface\\Icons\\Ability_Racial_Avatar",           color = { 1.0, 0.2, 0.2 } },
}

local WARRIOR_BIG_SPELLS = {
    { name = "Shield Wall",        short = "SWall",   tex = "Ability_Warrior_ShieldWall" },
    { name = "Last Stand",         short = "LStand",  tex = "Spell_Holy_AshenghoulProtection" },
    { name = "Challenging Shout",  short = "CShout",  tex = "Ability_BullRush" },
    { name = "Taunt",              short = "Taunt",   tex = "Spell_Nature_Reincarnation" },
    { name = "Mocking Blow",       short = "Mock",    tex = "Ability_Warrior_PunishingBlow" },
    { name = "Recklessness",       short = "Reck",    tex = "Ability_CriticalStrike" },
    { name = "Retaliation",        short = "Retal",   tex = "Ability_Warrior_Challange" },
    { name = "Death Wish",         short = "DWish",   tex = "Spell_Shadow_DeathPact" },
    { name = "Berserker Rage",     short = "BRage",   tex = "Spell_Nature_AncestralGuardian" },
}

local knownSpells = {}

function PUIWarrior:ScanSpellbook()
    knownSpells = {}
    local i = 1
    local numBig = table.getn(WARRIOR_BIG_SPELLS)
    while true do
        local spellName = GetSpellName(i, BOOKTYPE_SPELL)
        if not spellName then break end
        local texture = GetSpellTexture(i, BOOKTYPE_SPELL)
        for idx = 1, numBig do
            local bigSpell = WARRIOR_BIG_SPELLS[idx]
            if string.find(spellName, bigSpell.name) or (texture and string.find(texture, bigSpell.tex)) then
                if not knownSpells[bigSpell.name] then
                    knownSpells[bigSpell.name] = {
                        spellID = i,
                        name    = bigSpell.name,
                        texture = texture,
                        short   = bigSpell.short,
                        tex     = bigSpell.tex,
                    }
                end
            end
        end
        i = i + 1
    end
end

function PUIWarrior:GetMajorCooldowns()
    local list = {}
    local numBig = table.getn(WARRIOR_BIG_SPELLS)
    for idx = 1, numBig do
        local def = WARRIOR_BIG_SPELLS[idx]
        local info = knownSpells[def.name]
        if info then
            local start, duration = GetSpellCooldown(info.spellID, BOOKTYPE_SPELL)
            local remaining = 0
            if start and start > 0 and duration and duration > 0 then
                remaining = (start + duration) - GetTime()
                if remaining < 0 then remaining = 0 end
            end
            table.insert(list, {
                name = def.name,
                short = def.short,
                tex = def.tex,
                icon = info.texture or ("Interface\\Icons\\" .. def.tex),
                duration = duration or 0,
                remaining = remaining,
                isReady = (remaining <= 0),
                spellId = info.spellID,
            })
        end
    end
    return list
end

-- Detect Current Warrior Stance
function PUIWarrior:GetActiveStance()
    local numForms = GetNumShapeshiftForms()
    for i = 1, numForms do
        local icon, name, active = GetShapeshiftFormInfo(i)
        if active then
            return i, STANCES[i] or { name = name, icon = icon, color = { 1, 1, 1 } }
        end
    end
    return 1, STANCES[1]
end

-- Count Sunder Armor Stacks on Unit
function PUIWarrior:GetSunderStacks(unit)
    unit = unit or "target"
    if not UnitExists(unit) then return 0 end

    for i = 1, 16 do
        local texture, applications = UnitDebuff(unit, i)
        if not texture then break end
        if string.find(texture, "Ability_Warrior_Sunder") then
            return applications or 1
        end
    end
    return 0
end

-- Scan Party for Hostile Threat & Aggro
function PUIWarrior:ScanPartyThreat()
    local numParty = GetNumPartyMembers()
    if numParty == 0 then return nil, nil end

    for i = 1, numParty do
        local partyUnit = "party" .. i
        local targetUnit = "party" .. i .. "target"

        if UnitExists(partyUnit) and not UnitIsDeadOrGhost(partyUnit) then
            -- Check if mob is targeting this party member
            if UnitExists(targetUnit) and UnitCanAttack("player", targetUnit) and not UnitIsDead(targetUnit) then
                local mobTarget = targetUnit .. "target"
                if UnitExists(mobTarget) and UnitIsUnit(mobTarget, partyUnit) and not UnitIsUnit(partyUnit, "player") then
                    local pName = UnitName(partyUnit)
                    local mName = UnitName(targetUnit)
                    return partyUnit, pName, targetUnit, mName
                end
            end
        end
    end
    return nil, nil, nil, nil
end

-- Update Warrior HUD Display
function PUIWarrior:UpdateHUD()
    if not hudFrame or not hudFrame:IsShown() then return end

    -- 1. Rage & Stance
    local curRage = UnitMana("player")
    local maxRage = UnitManaMax("player")
    if maxRage == 0 then maxRage = 100 end

    rageBar:SetMinMaxValues(0, maxRage)
    rageBar:SetValue(curRage)
    rageBar.text:SetText(string.format("Rage: %d / %d", curRage, maxRage))

    local stanceIndex, stanceInfo = self:GetActiveStance()
    hudFrame.stanceText:SetText(stanceInfo.name)
    hudFrame.stanceText:SetTextColor(stanceInfo.color[1], stanceInfo.color[2], stanceInfo.color[3])

    -- 2. Target Sunder Stacks
    if UnitExists("target") and UnitCanAttack("player", "target") then
        local sunders = self:GetSunderStacks("target")
        hudFrame.sunderText:SetText(string.format("Sunder: %d/5", sunders))
        if sunders >= 5 then
            hudFrame.sunderText:SetTextColor(0.2, 1.0, 0.4) -- Green 5 stacks
        elseif sunders > 0 then
            hudFrame.sunderText:SetTextColor(1.0, 0.8, 0.2) -- Yellow partial
        else
            hudFrame.sunderText:SetTextColor(0.6, 0.6, 0.6) -- Gray 0
        end
    else
        hudFrame.sunderText:SetText("Sunder: --")
        hudFrame.sunderText:SetTextColor(0.4, 0.4, 0.4)
    end

    -- 3. Damage & DPS Tracker
    local effectiveTime = totalCombatTime
    if inCombat and combatStartTime > 0 then
        effectiveTime = effectiveTime + (GetTime() - combatStartTime)
    end
    local dps = effectiveTime > 0 and (sessionDamage / effectiveTime) or 0
    local allTime = warriorDB.allTimeDamage or 0

    hudFrame.dpsText:SetText(string.format("DPS: %.1f | Session: %s | All: %s", dps, Utils.FormatNumber(sessionDamage), Utils.FormatNumber(allTime)))

    -- 4. Party Threat / Intervene Scanner
    local partyUnit, partyName, mobUnit, mobName = self:ScanPartyThreat()
    if partyUnit and partyName then
        hudFrame.alertBtn.partyUnit = partyUnit
        hudFrame.alertBtn.mobUnit = mobUnit
        hudFrame.alertBtn.text:SetText(string.format("ALERT: %s taking aggro from %s!", string.sub(partyName, 1, 8), string.sub(mobName or "Mob", 1, 8)))
        hudFrame.alertBtn:Show()
    else
        hudFrame.alertBtn:Hide()
    end
end

function PUIWarrior:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIWarrior", {
        name = "Class_Warrior",
        category = "Classes",
        label = "Warrior Nuances",
        options = {
            {
                key = "enabled",
                type = "checkbox",
                label = "Enable Warrior Suite",
                desc = "Show Rage bar, Stance tracker, Sunder armor counter, and Peel alerts.",
                default = true,
                get = function() return warriorDB:Get("enabled") end,
                set = function(v)
                    warriorDB:Set("enabled", v)
                    if v then hudFrame:Show() else hudFrame:Hide() end
                end,
            },
        },
    })
end

function PUIWarrior:OnInitialize()
    -- Create Warrior HUD Frame
    hudFrame = CreateFrame("Frame", "Primus_WarriorHUD", UIParent)
    hudFrame:SetWidth(280)
    hudFrame:SetHeight(76)
    hudFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 180)
    hudFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
    hudFrame:SetBackdropColor(0.08, 0.06, 0.06, 0.9)
    hudFrame:SetBackdropBorderColor(0.78, 0.61, 0.43, 1) -- Warrior Tan

    -- Header / Stance
    local title = hudFrame:CreateFontString(nil, "OVERLAY")
    title:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    title:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 6, -6)
    title:SetText(Utils.ColorText("Warrior Suite", "c79c6e"))
    hudFrame.title = title

    local stanceText = hudFrame:CreateFontString(nil, "OVERLAY")
    stanceText:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    stanceText:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -6, -6)
    stanceText:SetText("Battle")
    hudFrame.stanceText = stanceText

    -- Sunder Armor Text
    local sunderText = hudFrame:CreateFontString(nil, "OVERLAY")
    sunderText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    sunderText:SetPoint("TOP", hudFrame, "TOP", 0, -6)
    sunderText:SetText("Sunder: --")
    hudFrame.sunderText = sunderText

    -- Rage Status Bar
    rageBar = Widgets:CreateStatusBar(hudFrame, 268, 14, 0, 100)
    rageBar:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 6, -22)
    rageBar:SetStatusBarColor(0.9, 0.2, 0.2, 1.0)
    rageBar.text:SetText("Rage: 0 / 100")

    -- Session DPS / Damage Text
    local dpsText = hudFrame:CreateFontString(nil, "OVERLAY")
    dpsText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    dpsText:SetPoint("TOPLEFT", rageBar, "BOTTOMLEFT", 0, -4)
    dpsText:SetTextColor(0.85, 0.85, 0.85)
    dpsText:SetText("DPS: 0.0 | Session: 0 | All: 0")
    hudFrame.dpsText = dpsText

    -- Threat / Intervene Alert Button
    local alertBtn = CreateFrame("Button", "Primus_WarriorAlertBtn", hudFrame)
    alertBtn:SetPoint("TOPLEFT", dpsText, "BOTTOMLEFT", 0, -2)
    alertBtn:SetPoint("BOTTOMRIGHT", hudFrame, "BOTTOMRIGHT", -6, 4)
    alertBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    alertBtn:SetBackdropColor(0.4, 0.1, 0.1, 0.9)
    alertBtn:SetBackdropBorderColor(1.0, 0.2, 0.2, 1)

    local alertText = alertBtn:CreateFontString(nil, "OVERLAY")
    alertText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    alertText:SetPoint("CENTER", alertBtn, "CENTER", 0, 0)
    alertText:SetTextColor(1.0, 0.9, 0.2)
    alertText:SetText("PEEL ALERT")
    alertBtn.text = alertText

    alertBtn:SetScript("OnClick", function()
        if this.partyUnit and UnitExists(this.partyUnit) then
            TargetUnit(this.partyUnit)
            -- Try Intervene if available (or macro target)
            CastSpellByName("Intervene")
        elseif this.mobUnit and UnitExists(this.mobUnit) then
            TargetUnit(this.mobUnit)
            CastSpellByName("Taunt")
        end
    end)
    alertBtn:Hide()
    local mover = PUIMover or Primus.PUIMover
    if mover and mover.Register then
        mover:Register(hudFrame, "WarriorHUD", "Warrior Suite (Rage, DPS & Intervene)", "CLASS")
    end

    self:RegisterOptionsFlare()
end

function PUIWarrior:OnEnable()
    if hudFrame and warriorDB:Get("enabled") then
        hudFrame:Show()
    end

    -- Combat Log Damage Hook
    Events:Listen("PRIMUS_COMBAT_EVENT", self, function(owner, data)
        if data and data.source == UnitName("player") and data.amount and data.amount > 0 then
            if data.eventType == "SWING_DAMAGE" or data.eventType == "SPELL_DAMAGE" then
                sessionDamage = sessionDamage + data.amount
                warriorDB:Set("allTimeDamage", (warriorDB:Get("allTimeDamage") or 0) + data.amount)
            end
        end
    end)

    -- Combat State Tracking
    Events:Register("PLAYER_REGEN_DISABLED", self, function()
        inCombat = true
        combatStartTime = GetTime()
    end)

    Events:Register("PLAYER_REGEN_ENABLED", self, function()
        inCombat = false
        if combatStartTime > 0 then
            totalCombatTime = totalCombatTime + (GetTime() - combatStartTime)
            combatStartTime = 0
        end
        PUIWarrior:UpdateHUD()
    end)

    -- Spellbook & Cooldown Events
    self:ScanSpellbook()
    Events:Register("SPELLS_CHANGED", self, function() PUIWarrior:ScanSpellbook() PUIWarrior:UpdateHUD() end)
    Events:Register("LEARNED_SPELL_IN_TAB", self, function() PUIWarrior:ScanSpellbook() PUIWarrior:UpdateHUD() end)
    Events:Register("SPELL_UPDATE_COOLDOWN", self, function() PUIWarrior:UpdateHUD() end)
    Events:Register("PLAYER_ENTERING_WORLD", self, function() PUIWarrior:ScanSpellbook() PUIWarrior:UpdateHUD() end)

    -- Dynamic Events
    Events:Register("UNIT_RAGE", self, function() PUIWarrior:UpdateHUD() end)
    Events:Register("PLAYER_AURAS_CHANGED", self, function() PUIWarrior:UpdateHUD() end)
    Events:Register("PLAYER_TARGET_CHANGED", self, function() PUIWarrior:UpdateHUD() end)
    Events:Register("UNIT_AURA", self, function() PUIWarrior:UpdateHUD() end)

    -- Live HUD Ticker (0.2s)
    Time:Every(0.2, function()
        PUIWarrior:UpdateHUD()
    end, self)

    self:UpdateHUD()
end

function PUIWarrior:OnDisable()
    Time:CancelAll(self)
    Events:UnregisterOwner(self)
    if hudFrame then hudFrame:Hide() end
end

