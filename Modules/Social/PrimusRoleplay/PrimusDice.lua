--[[
    PrimusUI: PUIRoleplay DiceMaster D20 Tabletop & Combat Engine (PUIDice.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (D20 Rolls, Stat Modifiers, Tabletop HP & Status Buffs)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIRoleplay = Primus.PUIRoleplay or {}
Primus.PUIRoleplay = PUIRoleplay

local Dice = {}
PUIRoleplay.Dice = Dice

local diceFrame = nil
Dice.activeModifier = 0
Dice.activeStatName = "None"
Dice.advantageMode = 0 -- -1 = Disadvantage, 0 = Normal, 1 = Advantage

-- Predefined Tabletop Status Conditions (16 Archetypes)
Dice.StatusConditions = {
    { id = "bleeding",    name = "Bleeding",    icon = "Ability_Rogue_BloodSplatter",   color = "FF4444", desc = "Taking periodic damage over time." },
    { id = "poisoned",    name = "Poisoned",    icon = "Ability_Poison",               color = "44FF44", desc = "Toxified; reduced physical stamina." },
    { id = "burning",     name = "Burning",     icon = "Spell_Fire_Immolation",        color = "FF8800", desc = "Engulfed in flames; intense heat." },
    { id = "shielded",    name = "Shielded",    icon = "Spell_Holy_PowerWordShield",   color = "FFE066", desc = "Protected by magical/physical ward." },
    { id = "stunned",     name = "Stunned",     icon = "Spell_Frost_Stun",             color = "66CCFF", desc = "Incapacitated; unable to act this turn." },
    { id = "inspired",    name = "Inspired",    icon = "Spell_Holy_PrayerOfSpirit",    color = "FFCC00", desc = "+2 bonus to all D20 rolls." },
    { id = "exhausted",   name = "Exhausted",   icon = "Spell_Nature_Sleep",           color = "999999", desc = "Fatigued; -2 penalty to physical rolls." },
    { id = "blinded",     name = "Blinded",     icon = "Spell_Shadow_ConeOfSilence",   color = "777777", desc = "Disadvantage on sight-based actions." },
    { id = "frozen",      name = "Frozen",      icon = "Spell_Frost_FrostArmor",       color = "88EEFF", desc = "Entangled in ice; movement halted." },
    { id = "cursed",      name = "Cursed",      icon = "Spell_Shadow_CurseOfTounges",  color = "BB44FF", desc = "Afflicted by dark magical hex." },
    { id = "blessed",     name = "Blessed",     icon = "Spell_Holy_Renew",             color = "FFEE88", desc = "Empowered by divine grace." },
    { id = "charmed",     name = "Charmed",     icon = "Spell_Shadow_MindSteal",       color = "FF88CC", desc = "Enthralled; unwilling to harm source." },
    { id = "enraged",     name = "Enraged",     icon = "Ability_Racial_BloodRage",     color = "FF2222", desc = "Furious; increased offense, lowered defense." },
    { id = "fortified",   name = "Fortified",   icon = "Ability_Warrior_DefensiveStance", color = "AAAAAA", desc = "Armor and physical defense boosted." },
    { id = "silenced",    name = "Silenced",    icon = "Spell_Shadow_ImpPhaseShift",   color = "8888CC", desc = "Muffled; unable to cast verbal spells." },
    { id = "unconscious", name = "Unconscious", icon = "Ability_Rogue_FeignDeath",     color = "444444", desc = "Knocked out; defenseless." }
}

--------------------------------------------------------------------------------
-- D20 Roll Evaluation Engine
--------------------------------------------------------------------------------
function Dice:Roll(sides, count, modifier, statName, advMode)
    sides = tonumber(sides) or 20
    count = tonumber(count) or 1
    modifier = tonumber(modifier) or Dice.activeModifier or 0
    statName = statName or Dice.activeStatName or "None"
    advMode = advMode or Dice.advantageMode or 0

    local rolls = {}
    local total = 0

    if sides == 20 and advMode ~= 0 then
        -- Advantage or Disadvantage D20 Roll
        local r1 = math.random(1, 20)
        local r2 = math.random(1, 20)
        local chosen = (advMode == 1) and math.max(r1, r2) or math.min(r1, r2)
        local discarded = (advMode == 1) and math.min(r1, r2) or math.max(r1, r2)
        local finalScore = chosen + modifier

        local outcome = "Normal"
        if chosen == 20 then outcome = "|cff00ff88Critical Success!|r"
        elseif chosen == 1 then outcome = "|cffff3333Critical Fumble!|r"
        elseif finalScore >= 20 then outcome = "|cff00e5ffHeroic Success|r"
        elseif finalScore >= 15 then outcome = "|cff40ff66Success|r"
        elseif finalScore >= 10 then outcome = "|cffffcc00Moderate Success|r"
        else outcome = "|cffff6666Failure|r"
        end

        local advLabel = (advMode == 1) and "[ADVANTAGE]" or "[DISADVANTAGE]"
        local modStr = (modifier > 0) and ("+" .. modifier) or ((modifier < 0) and tostring(modifier) or "")
        local statTag = (statName ~= "None" and statName ~= "") and (" (" .. statName .. ")") or ""

        local msg = string.format("[D20 %s] Rolled: %d, %d -> Kept |cffffffff%d|r%s%s = |cff00e5ff%d|r (%s)",
            advLabel, r1, r2, chosen, modStr, statTag, finalScore, outcome)

        self:BroadcastRoll(msg)
        return finalScore, msg
    end

    -- Standard Multi-Die Roll
    for i = 1, count do
        local r = math.random(1, sides)
        table.insert(rolls, r)
        total = total + r
    end

    local finalTotal = total + modifier
    local outcome = ""
    if sides == 20 and count == 1 then
        local nat = rolls[1]
        if nat == 20 then outcome = " -> |cff00ff88Critical Success!|r"
        elseif nat == 1 then outcome = " -> |cffff3333Critical Fumble!|r"
        elseif finalTotal >= 20 then outcome = " -> |cff00e5ffHeroic Success|r"
        elseif finalTotal >= 15 then outcome = " -> |cff40ff66Success|r"
        elseif finalTotal >= 10 then outcome = " -> |cffffcc00Moderate Success|r"
        else outcome = " -> |cffff6666Failure|r"
        end
    end

    local rollListStr = table.concat(rolls, "+")
    local modStr = (modifier > 0) and ("+" .. modifier) or ((modifier < 0) and tostring(modifier) or "")
    local statTag = (statName ~= "None" and statName ~= "") and (" (" .. statName .. ")") or ""

    local msg = string.format("[%dD%d%s%s] Rolled: (%s)%s = |cff00e5ff%d|r%s",
        count, sides, modStr, statTag, rollListStr, modStr, finalTotal, outcome)

    self:BroadcastRoll(msg)
    return finalTotal, msg
end

function Dice:BroadcastRoll(message)
    local chatChannel = "EMOTE"
    if UnitInRaid("player") then chatChannel = "RAID"
    elseif GetNumPartyMembers() > 0 then chatChannel = "PARTY"
    end

    SendChatMessage(message, chatChannel)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DiceMaster]|r " .. message)

    if PUIRoleplay.Comms and PUIRoleplay.Comms.SendBroadcastMessage then
        PUIRoleplay.Comms:SendBroadcastMessage("D20:" .. message, "ALERT")
    end
end

--------------------------------------------------------------------------------
-- Tabletop Character State (HP, Resource, Status Effects)
--------------------------------------------------------------------------------
function Dice:GetTabletopStats()
    local p = PUIRoleplay:GetMyProfile()
    if not p.d20_stats then
        p.d20_stats = {
            cur_hp = 20,
            max_hp = 20,
            cur_resource = 10,
            max_resource = 10,
            resource_name = "Stamina",
            armor = 0,
            status_effects = {}
        }
        PUIRoleplay:SaveMyProfile(p)
    end
    return p.d20_stats
end

function Dice:ModifyHP(delta)
    local s = self:GetTabletopStats()
    s.cur_hp = math.max(0, math.min(s.max_hp, (s.cur_hp or 20) + delta))
    PUIRoleplay:SaveMyProfile(PUIRoleplay:GetMyProfile())
    self:RefreshUI()
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ccff[DiceMaster]|r RP Health: |cffffffff%d / %d|r (%s%d)",
        s.cur_hp, s.max_hp, (delta >= 0 and "+" or ""), delta))
end

function Dice:ModifyResource(delta)
    local s = self:GetTabletopStats()
    s.cur_resource = math.max(0, math.min(s.max_resource, (s.cur_resource or 10) + delta))
    PUIRoleplay:SaveMyProfile(PUIRoleplay:GetMyProfile())
    self:RefreshUI()
end

function Dice:ToggleStatus(condId)
    local s = self:GetTabletopStats()
    if not s.status_effects then s.status_effects = {} end
    if s.status_effects[condId] then
        s.status_effects[condId] = nil
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DiceMaster]|r Status condition removed: |cffffffff" .. condId .. "|r")
    else
        s.status_effects[condId] = true
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[DiceMaster]|r Status condition applied: |cff00ff88" .. condId .. "|r")
    end
    PUIRoleplay:SaveMyProfile(PUIRoleplay:GetMyProfile())
    self:RefreshUI()
end

--------------------------------------------------------------------------------
-- Build DiceMaster Master UI Window
--------------------------------------------------------------------------------
function Dice:BuildFrame()
    if diceFrame then return diceFrame end

    local f = CreateFrame("Frame", "Primus_PUIRoleplay_DiceFrame", UIParent)
    f:SetWidth(460)
    f:SetHeight(480)
    f:SetPoint("CENTER", UIParent, "CENTER", 180, 0)
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    f:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
    f:SetBackdropBorderColor(0.20, 0.22, 0.28, 1.0)
    table.insert(UISpecialFrames, "Primus_PUIRoleplay_DiceFrame")

    -- Title Bar
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    titleBar:SetHeight(28)
    titleBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    titleBar:SetBackdropColor(0.11, 0.12, 0.15, 1.0)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleText:SetText("|cff00ccffDICEMASTER|r |cffffffffD20 TABLETOP & COMBAT|r")

    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetWidth(18)
    closeBtn:SetHeight(18)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Section 1: Quick Dice Bar (D4, D6, D8, D10, D12, D20, D100)
    local diceBarHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    diceBarHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -36)
    diceBarHeader:SetText("|cffffd100QUICK DICE TRAY:|r")

    local diceTypes = { 4, 6, 8, 10, 12, 20, 100 }
    f.diceBtns = {}
    local dW = 56
    for i, d in ipairs(diceTypes) do
        local btn = CreateFrame("Button", nil, f)
        btn:SetWidth(dW)
        btn:SetHeight(24)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", 12 + (i - 1) * (dW + 6), -52)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        btn:SetBackdropColor(0.08, 0.12, 0.18, 0.95)
        btn:SetBackdropBorderColor(0.0, 0.65, 0.90, 0.8)

        local t = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetPoint("CENTER", btn, "CENTER", 0, 0)
        t:SetText("D" .. d)
        btn.sides = d

        btn:SetScript("OnEnter", function()
            this:SetBackdropColor(0.0, 0.45, 0.70, 1.0)
            this:SetBackdropBorderColor(0.0, 0.90, 1.0, 1.0)
        end)
        btn:SetScript("OnLeave", function()
            this:SetBackdropColor(0.08, 0.12, 0.18, 0.95)
            this:SetBackdropBorderColor(0.0, 0.65, 0.90, 0.8)
        end)
        btn:SetScript("OnClick", function()
            Dice:Roll(this.sides, 1, Dice.activeModifier, Dice.activeStatName, Dice.advantageMode)
        end)
    end

    -- Section 2: Modifiers & Advantage Toggles
    local modHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    modHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -84)
    modHeader:SetText("|cff00e5ffSTAT MODIFIERS & ADVANTAGE:|r")

    local statDefs = {
        { name = "None", mod = 0 },
        { name = "STR (+2)", mod = 2 },
        { name = "AGI (+3)", mod = 3 },
        { name = "STA (+2)", mod = 2 },
        { name = "INT (+4)", mod = 4 },
        { name = "SPI (+1)", mod = 1 },
        { name = "Custom", mod = 0 }
    }
    f.statBtns = {}
    local sW = 56
    for i, s in ipairs(statDefs) do
        local btn = CreateFrame("Button", nil, f)
        btn:SetWidth(sW)
        btn:SetHeight(20)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", 12 + (i - 1) * (sW + 6), -100)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        btn:SetBackdropColor(0.06, 0.06, 0.09, 0.95)
        btn:SetBackdropBorderColor(0.25, 0.25, 0.32, 1.0)

        local t = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetPoint("CENTER", btn, "CENTER", 0, 0)
        t:SetText(s.name)
        btn.text = t
        btn.statName = s.name
        btn.statMod = s.mod

        btn:SetScript("OnClick", function()
            Dice.activeStatName = this.statName
            Dice.activeModifier = this.statMod
            Dice:RefreshUI()
        end)
        f.statBtns[i] = btn
    end

    -- Advantage / Disadvantage Mode Buttons
    local advBtn = CreateFrame("Button", nil, f)
    advBtn:SetWidth(138)
    advBtn:SetHeight(22)
    advBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -126)
    advBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    local advTxt = advBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    advTxt:SetPoint("CENTER", advBtn, "CENTER", 0, 0)
    advTxt:SetText("Advantage (Best 2)")
    advBtn.text = advTxt
    advBtn:SetScript("OnClick", function()
        Dice.advantageMode = (Dice.advantageMode == 1) and 0 or 1
        Dice:RefreshUI()
    end)
    f.advBtn = advBtn

    local disadvBtn = CreateFrame("Button", nil, f)
    disadvBtn:SetWidth(138)
    disadvBtn:SetHeight(22)
    disadvBtn:SetPoint("TOPLEFT", advBtn, "TOPRIGHT", 8, 0)
    disadvBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    local disTxt = disadvBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    disTxt:SetPoint("CENTER", disadvBtn, "CENTER", 0, 0)
    disTxt:SetText("Disadvantage (Worst 2)")
    disadvBtn.text = disTxt
    disadvBtn:SetScript("OnClick", function()
        Dice.advantageMode = (Dice.advantageMode == -1) and 0 or -1
        Dice:RefreshUI()
    end)
    f.disadvBtn = disadvBtn

    local customRollBtn = CreateFrame("Button", nil, f)
    customRollBtn:SetWidth(140)
    customRollBtn:SetHeight(22)
    customRollBtn:SetPoint("TOPLEFT", disadvBtn, "TOPRIGHT", 8, 0)
    customRollBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    customRollBtn:SetBackdropColor(0.12, 0.45, 0.25, 0.95)
    customRollBtn:SetBackdropBorderColor(0.2, 0.85, 0.4, 1.0)
    local crTxt = customRollBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    crTxt:SetPoint("CENTER", customRollBtn, "CENTER", 0, 0)
    crTxt:SetText("|cffffffffROLL 1D20 + MOD|r")
    customRollBtn:SetScript("OnClick", function()
        Dice:Roll(20, 1, Dice.activeModifier, Dice.activeStatName, Dice.advantageMode)
    end)

    -- Section 3: RP Tabletop Health & Resource Trackers
    local hpHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hpHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -156)
    hpHeader:SetText("|cffffd100TABLETOP HEALTH & RESOURCES:|r")

    -- HP Bar Container
    local hpBox = CreateFrame("Frame", nil, f)
    hpBox:SetWidth(434)
    hpBox:SetHeight(38)
    hpBox:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -172)
    hpBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    hpBox:SetBackdropColor(0.04, 0.04, 0.07, 0.95)
    hpBox:SetBackdropBorderColor(0.25, 0.25, 0.32, 1.0)
    f.hpBox = hpBox

    local hpLabel = hpBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hpLabel:SetPoint("LEFT", hpBox, "LEFT", 10, 0)
    hpLabel:SetText("|cffff3333RP Health:|r 20 / 20")
    f.hpLabel = hpLabel

    local function CreateHPBtn(text, delta, xOff)
        local b = CreateFrame("Button", nil, hpBox)
        b:SetWidth(36)
        b:SetHeight(20)
        b:SetPoint("RIGHT", hpBox, "RIGHT", xOff, 0)
        b:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        b:SetBackdropColor(0.12, 0.12, 0.16, 0.95)
        b:SetBackdropBorderColor(0.35, 0.35, 0.45, 1.0)
        local bt = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bt:SetPoint("CENTER", b, "CENTER", 0, 0)
        bt:SetText(text)
        b:SetScript("OnClick", function() Dice:ModifyHP(delta) end)
        return b
    end

    CreateHPBtn("+5", 5, -8)
    CreateHPBtn("+1", 1, -48)
    CreateHPBtn("-1", -1, -88)
    CreateHPBtn("-5", -5, -128)

    -- Section 4: 16 Status Effect Condition Badges
    local statusHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -218)
    statusHeader:SetText("|cff00e5ffSTATUS CONDITIONS & EFFECTS (Click to Toggle):|r")

    f.condBtns = {}
    local condCols = 4
    local cW = 104
    local cH = 28
    for idx, cond in ipairs(Dice.StatusConditions) do
        local col = math.mod(idx - 1, condCols)
        local row = math.floor((idx - 1) / condCols)

        local cBtn = CreateFrame("Button", nil, f)
        cBtn:SetWidth(cW)
        cBtn:SetHeight(cH)
        cBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 12 + col * (cW + 6), -236 - row * (cH + 4))
        cBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        cBtn:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
        cBtn:SetBackdropBorderColor(0.20, 0.22, 0.28, 1.0)

        local icon = cBtn:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(20)
        icon:SetHeight(20)
        icon:SetPoint("LEFT", cBtn, "LEFT", 4, 0)
        icon:SetTexture("Interface\\Icons\\" .. cond.icon)
        cBtn.icon = icon

        local lbl = cBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        lbl:SetPoint("RIGHT", cBtn, "RIGHT", -2, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetText("|cff" .. cond.color .. cond.name .. "|r")
        cBtn.label = lbl
        cBtn.condId = cond.id
        cBtn.condMeta = cond

        cBtn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:AddLine(this.condMeta.name, 1, 1, 1)
            GameTooltip:AddLine(this.condMeta.desc, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        cBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cBtn:SetScript("OnClick", function()
            Dice:ToggleStatus(this.condId)
        end)

        f.condBtns[idx] = cBtn
    end

    diceFrame = f
    self:RefreshUI()
    return f
end

function Dice:RefreshUI()
    local f = diceFrame
    if not f then return end

    local s = self:GetTabletopStats()
    if f.hpLabel then
        f.hpLabel:SetText(string.format("|cffff3333RP Health:|r %d / %d", s.cur_hp or 20, s.max_hp or 20))
    end

    if f.advBtn then
        if Dice.advantageMode == 1 then
            f.advBtn:SetBackdropColor(0.0, 0.50, 0.80, 1.0)
            f.advBtn:SetBackdropBorderColor(0.0, 0.90, 1.0, 1.0)
        else
            f.advBtn:SetBackdropColor(0.06, 0.06, 0.09, 0.95)
            f.advBtn:SetBackdropBorderColor(0.25, 0.25, 0.32, 1.0)
        end
    end

    if f.disadvBtn then
        if Dice.advantageMode == -1 then
            f.disadvBtn:SetBackdropColor(0.70, 0.20, 0.20, 1.0)
            f.disadvBtn:SetBackdropBorderColor(1.0, 0.40, 0.40, 1.0)
        else
            f.disadvBtn:SetBackdropColor(0.06, 0.06, 0.09, 0.95)
            f.disadvBtn:SetBackdropBorderColor(0.25, 0.25, 0.32, 1.0)
        end
    end

    local activeStatus = s.status_effects or {}
    for _, btn in ipairs(f.condBtns or {}) do
        if activeStatus[btn.condId] then
            btn:SetBackdropColor(0.15, 0.35, 0.20, 1.0)
            btn:SetBackdropBorderColor(0.20, 0.90, 0.40, 1.0)
        else
            btn:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
            btn:SetBackdropBorderColor(0.20, 0.22, 0.28, 1.0)
        end
    end
end

function Dice:Open()
    local f = self:BuildFrame()
    f:Show()
    self:RefreshUI()
end

function Dice:Toggle()
    local f = self:BuildFrame()
    if f:IsShown() then f:Hide() else f:Show(); self:RefreshUI() end
end

-- Slash command hooks
SLASH_PUIDICE1 = "/puidice"
SLASH_PUIDICE2 = "/roll20"
SLASH_PUIDICE3 = "/d20"
SlashCmdList["PUIDICE"] = function(msg)
    if msg and msg ~= "" then
        local mod = tonumber(msg)
        if mod then
            Dice:Roll(20, 1, mod, "Custom", 0)
            return
        end
    end
    Dice:Toggle()
end
