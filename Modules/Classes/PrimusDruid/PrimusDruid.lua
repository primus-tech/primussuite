--[[
    PrimusLib Module: Class_Druid (Buff Matrix, Reagents, Feral Mana & Rebirth Suite)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Tracks:
    1. Mark / Gift of the Wild and Thorns party & raid buff matrix.
    2. Reagent counts for Wild Thornroot, Wild Berries, and Ironwood Seed.
    3. Feral Form True Mana Bar (hidden mana & spirit regen in Cat/Bear form).
    4. Long cooldown monitors for Innervate and Rebirth.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local _, playerClass = UnitClass("player")
if playerClass ~= "DRUID" then return end

local PUIDruid = Primus.PUIDruid or {}
Primus.PUIDruid = PUIDruid
_G.PUIDruid = PUIDruid
Primus:RegisterModule("PUIDruid", PUIDruid, "Classes")

local DB      = Primus.DB
local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local Events  = Primus.Events
local Time    = Primus.Time
local PUIMover = Primus.PUIMover

local druidDB = DB:RegisterNamespace("PUIDruid", {
    enabled = true,
})

local hudFrame = nil
local feralManaBar = nil
local rowButtons = {}

-- Feral Mana Estimation State
local estimatedMana = 0
local maxMana = 0
local lastMana = 0
local lastManaTick = 0
local fsrStartTime = 0

-- Count Reagent in Bags
local function GetReagentCount(reagentName)
    local count = 0
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots > 0 then
            for slot = 1, numSlots do
                local link = GetContainerItemLink(bag, slot)
                if link and string.find(link, reagentName) then
                    local _, itemCount = GetContainerItemInfo(bag, slot)
                    count = count + (itemCount or 1)
                end
            end
        end
    end
    return count
end

local DRUID_BIG_SPELLS = {
    { name = "Barkskin",                short = "Bark",    tex = "Spell_Nature_StoneClawTotem" }, -- 1 min
    { name = "Nature's Swiftness",      short = "NS",      tex = "Spell_Nature_RavenForm" },      -- 3 min
    { name = "Frenzied Regeneration",   short = "Frenzied",tex = "Ability_BullRush" },            -- 3 min
    { name = "Tranquility",             short = "Tranq",   tex = "Spell_Nature_Tranquility" },    -- 5 min
    { name = "Innervate",               short = "Inner",   tex = "Spell_Nature_Lightning" },      -- 6 min
    { name = "Rebirth",                 short = "Rebirth", tex = "Spell_Nature_Reincarnation" },  -- 30 min
}

-- Find Spell Cooldown by Name
local function GetSpellCD(spellName)
    local i = 1
    while true do
        local name = GetSpellName(i, BOOKTYPE_SPELL)
        if not name then break end
        if name == spellName then
            local start, duration = GetSpellCooldown(i, BOOKTYPE_SPELL)
            if start and start > 0 and duration and duration > 0 then
                local cdLeft = (start + duration) - GetTime()
                return cdLeft > 0 and cdLeft or 0, duration, i
            end
            return 0, 0, i
        end
        i = i + 1
    end
    return 0, 0, nil
end

function PUIDruid:GetMajorCooldowns()
    local list = {}
    for i = 1, table.getn(DRUID_BIG_SPELLS) do
        local def = DRUID_BIG_SPELLS[i]
        local cdLeft, duration, spellId = GetSpellCD(def.name)
        if spellId then
            table.insert(list, {
                name = def.name,
                short = def.short,
                tex = def.tex,
                icon = "Interface\\Icons\\" .. def.tex,
                duration = duration or 0,
                remaining = cdLeft or 0,
                isReady = (cdLeft <= 0),
                spellId = spellId,
            })
        end
    end
    return list
end

-- Scan Unit for MotW and Thorns
function PUIDruid:GetUnitDruidBuffs(unit)
    if not UnitExists(unit) then return false, false end

    local hasMotW = false
    local hasThorns = false

    for i = 1, 32 do
        local tex = UnitBuff(unit, i)
        if not tex then break end
        if string.find(tex, "Spell_Nature_Regeneration") or string.find(tex, "Spell_Nature_HealingTouch") then
            hasMotW = true
        elseif string.find(tex, "Spell_Nature_Thorns") then
            hasThorns = true
        end
    end
    return hasMotW, hasThorns
end

-- Create Row for Druid Buff Matrix
local function CreateMatrixRow(parent, index)
    local row = CreateFrame("Button", "Primus_DruidRow_" .. index, parent)
    row:SetWidth(180)
    row:SetHeight(18)
    row:SetBackdrop(Media:Fetch("border", "1Pixel"))
    row:SetBackdropColor(0.08, 0.08, 0.10, 0.8)
    row:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    label:SetPoint("LEFT", row, "LEFT", 4, 0)
    label:SetWidth(70)
    label:SetJustifyH("LEFT")
    row.label = label

    local motwText = row:CreateFontString(nil, "OVERLAY")
    motwText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    motwText:SetPoint("LEFT", label, "RIGHT", 4, 0)
    motwText:SetText("MotW")
    row.motwText = motwText

    local thornsText = row:CreateFontString(nil, "OVERLAY")
    thornsText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    thornsText:SetPoint("LEFT", motwText, "RIGHT", 8, 0)
    thornsText:SetText("Thorns")
    row.thornsText = thornsText

    rowButtons[index] = row
    return row
end

-- Update Druid HUD & Buff Matrix
function PUIDruid:UpdateHUD()
    if not hudFrame or not hudFrame:IsShown() then return end

    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    local rowCount = 0

    if numRaid > 0 then
        for r = 1, math.min(numRaid, 8) do
            local unit = "raid" .. r
            if UnitExists(unit) and not UnitIsDeadOrGhost(unit) then
                rowCount = rowCount + 1
                local row = rowButtons[rowCount] or CreateMatrixRow(hudFrame.container, rowCount)
                local name = UnitName(unit) or unit
                local _, uClass = UnitClass(unit)
                local rC, gC, bC = Utils.GetClassColor(uClass or "DRUID")
                row.label:SetText(string.sub(name, 1, 8))
                row.label:SetTextColor(rC, gC, bC)

                local hasMotW, hasThorns = self:GetUnitDruidBuffs(unit)
                row.motwText:SetTextColor(hasMotW and 0.2 or 1.0, hasMotW and 1.0 or 0.2, hasMotW and 0.4 or 0.2)
                row.thornsText:SetTextColor(hasThorns and 0.2 or 0.4, hasThorns and 1.0 or 0.4, hasThorns and 0.4 or 0.4)

                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", hudFrame.container, "TOPLEFT", 0, -(rowCount - 1) * 20)
                row:Show()
            end
        end
    elseif numParty > 0 then
        local units = { "player", "party1", "party2", "party3", "party4" }
        for _, unit in ipairs(units) do
            if UnitExists(unit) then
                rowCount = rowCount + 1
                local row = rowButtons[rowCount] or CreateMatrixRow(hudFrame.container, rowCount)
                local name = UnitName(unit) or unit
                local _, uClass = UnitClass(unit)
                local rC, gC, bC = Utils.GetClassColor(uClass or "DRUID")
                row.label:SetText(string.sub(name, 1, 8))
                row.label:SetTextColor(rC, gC, bC)

                local hasMotW, hasThorns = self:GetUnitDruidBuffs(unit)
                row.motwText:SetTextColor(hasMotW and 0.2 or 1.0, hasMotW and 1.0 or 0.2, hasMotW and 0.4 or 0.2)
                row.thornsText:SetTextColor(hasThorns and 0.2 or 0.4, hasThorns and 1.0 or 0.4, hasThorns and 0.4 or 0.4)

                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", hudFrame.container, "TOPLEFT", 0, -(rowCount - 1) * 20)
                row:Show()
            end
        end
    else
        rowCount = 1
        local row = rowButtons[1] or CreateMatrixRow(hudFrame.container, 1)
        row.label:SetText("Player")
        row.label:SetTextColor(1.0, 0.49, 0.04)

        local hasMotW, hasThorns = self:GetUnitDruidBuffs("player")
        row.motwText:SetTextColor(hasMotW and 0.2 or 1.0, hasMotW and 1.0 or 0.2, hasMotW and 0.4 or 0.2)
        row.thornsText:SetTextColor(hasThorns and 0.2 or 0.4, hasThorns and 1.0 or 0.4, hasThorns and 0.4 or 0.4)

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", hudFrame.container, "TOPLEFT", 0, 0)
        row:Show()
    end

    for i = rowCount + 1, 10 do
        if rowButtons[i] then rowButtons[i]:Hide() end
    end

    -- Reagents: Wild Thornroot / Berries & Ironwood Seed
    local thornsRoots = GetReagentCount("Wild Thornroot")
    local berries = GetReagentCount("Wild Berries")
    local seeds = GetReagentCount("Ironwood Seed")
    hudFrame.reagentText:SetText(string.format("Roots: %d | Berries: %d | Seed: %d", thornsRoots, berries, seeds))

    -- Cooldowns: Innervate & Rebirth
    local innervateCD = GetSpellCD("Innervate")
    local rebirthCD = GetSpellCD("Rebirth")
    hudFrame.innervateText:SetText(innervateCD > 0 and ("Inner: " .. Time:FormatShort(innervateCD)) or "Inner: READY")
    hudFrame.innervateText:SetTextColor(innervateCD > 0 and 1.0 or 0.2, innervateCD > 0 and 0.3 or 1.0, innervateCD > 0 and 0.3 or 0.4)

    hudFrame.rebirthText:SetText(rebirthCD > 0 and ("Rebirth: " .. Time:FormatShort(rebirthCD)) or "Rebirth: READY")
    hudFrame.rebirthText:SetTextColor(rebirthCD > 0 and 1.0 or 0.2, rebirthCD > 0 and 0.3 or 1.0, rebirthCD > 0 and 0.3 or 0.4)

    hudFrame:SetHeight(rowCount * 20 + 72)
end

function PUIDruid:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIDruid", {
        name = "Class_Druid",
        category = "Classes",
        label = "Druid Nuances",
        options = {
            {
                key = "enabled",
                type = "checkbox",
                label = "Enable Druid Suite",
                desc = "Show MotW/Thorns buff matrix, Reagents, Innervate/Rebirth timers, and Feral Mana bar.",
                default = true,
                get = function() return druidDB:Get("enabled") end,
                set = function(v)
                    druidDB:Set("enabled", v)
                    if v then hudFrame:Show() else hudFrame:Hide() end
                end,
            },
        },
    })
end

function PUIDruid:OnInitialize()
    maxMana = UnitManaMax("player")
    estimatedMana = UnitMana("player")

    -- Feral Form True Mana Bar
    feralManaBar = Widgets:CreateStatusBar(UIParent, 160, 12, 0, maxMana)
    feralManaBar:SetPoint("CENTER", UIParent, "CENTER", 0, -130)
    feralManaBar:SetStatusBarColor(0.2, 0.6, 1.0, 1.0)
    feralManaBar.text:SetText("Feral Mana")
    feralManaBar:Hide()

    local mover = PUIMover or Primus.PUIMover
    if mover and mover.Register then
        mover:Register(feralManaBar, "DruidFeralMana", "Feral Form True Mana Bar", "CLASS")
    end

    -- Druid Suite HUD Frame
    hudFrame = CreateFrame("Frame", "Primus_DruidHUD", UIParent)
    hudFrame:SetWidth(190)
    hudFrame:SetHeight(130)
    hudFrame:SetPoint("LEFT", UIParent, "LEFT", 20, 0)
    hudFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
    hudFrame:SetBackdropColor(0.08, 0.06, 0.04, 0.9)
    hudFrame:SetBackdropBorderColor(1.0, 0.49, 0.04, 1) -- Druid Orange

    -- Header Title
    local title = hudFrame:CreateFontString(nil, "OVERLAY")
    title:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    title:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 6, -6)
    title:SetText(Utils.ColorText("Druid Suite", "ff7d0a"))
    hudFrame.title = title

    -- Cooldown Texts
    local innervateText = hudFrame:CreateFontString(nil, "OVERLAY")
    innervateText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    innervateText:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -6, -4)
    innervateText:SetText("Inner: READY")
    hudFrame.innervateText = innervateText

    local rebirthText = hudFrame:CreateFontString(nil, "OVERLAY")
    rebirthText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    rebirthText:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -6, -14)
    rebirthText:SetText("Rebirth: READY")
    hudFrame.rebirthText = rebirthText

    -- Container for matrix rows
    local container = CreateFrame("Frame", nil, hudFrame)
    container:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 5, -26)
    container:SetPoint("BOTTOMRIGHT", hudFrame, "BOTTOMRIGHT", -5, 20)
    hudFrame.container = container

    for i = 1, 10 do
        local row = CreateMatrixRow(container, i)
        row:Hide()
    end

    -- Reagents Footer Text
    local reagentText = hudFrame:CreateFontString(nil, "OVERLAY")
    reagentText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    reagentText:SetPoint("BOTTOMLEFT", hudFrame, "BOTTOMLEFT", 6, 4)
    reagentText:SetTextColor(0.85, 0.85, 0.7)
    reagentText:SetText("Roots: 0 | Berries: 0 | Seed: 0")
    hudFrame.reagentText = reagentText

    if mover and mover.Register then
        mover:Register(hudFrame, "DruidHUD", "Druid Suite (Buffs, Reagents & Cooldowns)", "CLASS")
    end

    self:RegisterOptionsFlare()
end

function PUIDruid:OnEnable()
    if hudFrame and druidDB:Get("enabled") then
        hudFrame:Show()
    end

    -- Track Feral Mana Regeneration
    Events:Register("UNIT_MANA", self, function(owner, event, unit)
        if unit ~= "player" then return end
        local powerType = UnitPowerType("player")
        if powerType == 0 then
            estimatedMana = UnitMana("player")
            maxMana = UnitManaMax("player")
            feralManaBar:Hide()
        else
            if druidDB:Get("enabled") then feralManaBar:Show() end
        end
    end)

    Events:Register("PLAYER_AURAS_CHANGED", self, function()
        local powerType = UnitPowerType("player")
        if powerType ~= 0 and druidDB:Get("enabled") then
            feralManaBar:Show()
        else
            feralManaBar:Hide()
        end
        PUIDruid:UpdateHUD()
    end)

    Events:Register("PARTY_MEMBERS_CHANGED", self, function() PUIDruid:UpdateHUD() end)
    Events:Register("RAID_ROSTER_UPDATE", self, function() PUIDruid:UpdateHUD() end)
    Events:Register("UNIT_AURA", self, function() PUIDruid:UpdateHUD() end)
    Events:Register("BAG_UPDATE", self, function() PUIDruid:UpdateHUD() end)

    -- 0.1s Feral Mana Bar Ticker & 1s HUD Matrix Refresh
    Time:Every(0.1, function()
        local powerType = UnitPowerType("player")
        if powerType ~= 0 and feralManaBar:IsShown() then
            -- Simulate base spirit mana regen (approx 2s ticks)
            local now = GetTime()
            if now - lastManaTick >= 2.0 then
                local spirit = UnitStat("player", 5) or 100
                local regen = (spirit / 5) + 15
                estimatedMana = math.min(maxMana, estimatedMana + regen)
                lastManaTick = now
            end
            feralManaBar:SetMinMaxValues(0, maxMana)
            feralManaBar:SetValue(estimatedMana)
            feralManaBar.text:SetText(string.format("Mana: %d / %d", estimatedMana, maxMana))
        end
    end, self)

    Time:Every(1.0, function()
        PUIDruid:UpdateHUD()
    end, self)

    self:UpdateHUD()
end

function PUIDruid:OnDisable()
    Time:CancelAll(self)
    Events:UnregisterOwner(self)
    if hudFrame then hudFrame:Hide() end
    if feralManaBar then feralManaBar:Hide() end
end

