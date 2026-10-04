--[[
    PrimusLib Module: Class_Mage (Major Cooldowns & Mana Gem Engine)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Tracks "THE BIG SPELLS" (Evocation, Ice Block, Cold Snap, Arcane Power,
    Presence of Mind, Combustion, Blink, Ice Barrier) and Mana Gem availability.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local _, playerClass = UnitClass("player")
if playerClass ~= "MAGE" then return end

local PUIMage = Primus.PUIMage or {}
Primus.PUIMage = PUIMage
_G.PUIMage = PUIMage
Primus:RegisterModule("PUIMage", PUIMage, "Classes")

local DB      = Primus.DB
local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local Events  = Primus.Events
local Time    = Primus.Time
local PUIMover = Primus.PUIMover

local mageDB = DB:RegisterNamespace("PUIMage", {
    enabled = true,
})

local hudFrame = nil
local spellButtons = {}
local knownSpells = {}

-- Major Mage Spells to track (Ordered by frequency of use / cooldown tier)
local BIG_SPELLS = {
    { name = "Blink",            tex = "Spell_Arcane_Blink",       short = "Blink" },   -- 15s CD
    { name = "Cone of Cold",     tex = "Spell_Frost_Glacier",      short = "CoC" },     -- 10s CD
    { name = "Frost Nova",       tex = "Spell_Frost_FrostNova",    short = "Nova" },    -- 25s / 21s CD
    { name = "Ice Barrier",      tex = "Spell_Ice_Lament",         short = "Barrier" }, -- 30s CD
    { name = "Blast Wave",       tex = "Spell_Holy_Excorcism_02",  short = "Wave" },    -- 45s CD
    { name = "Presence of Mind", tex = "Spell_Nature_EnchantArmor",short = "PoM" },     -- 3 min CD
    { name = "Arcane Power",     tex = "Spell_Nature_Lightning",   short = "AP" },      -- 3 min CD
    { name = "Combustion",       tex = "Spell_Fire_SealOfFire",    short = "Comb" },    -- 3 min CD
    { name = "Ice Block",        tex = "Spell_Frost_Frost",        short = "Block" },   -- 5 min CD
    { name = "Evocation",        tex = "Spell_Nature_Purge",       short = "Evo" },     -- 8 min CD
    { name = "Cold Snap",        tex = "Spell_Frost_WizardMark",   short = "Snap" },    -- 10 min CD
}



-- Format cooldown duration
local function FormatCD(seconds)
    if not seconds or seconds <= 0 then return "" end
    if seconds >= 60 then
        return string.format("%dm", math.ceil(seconds / 60))
    else
        return string.format("%ds", math.floor(seconds))
    end
end

-- Scan Spellbook for Known Big Spells
function PUIMage:ScanSpellbook()
    knownSpells = {}
    local i = 1
    local numBig = table.getn(BIG_SPELLS)
    while true do
        local spellName, spellRank = GetSpellName(i, BOOKTYPE_SPELL)
        if not spellName then break end
        local texture = GetSpellTexture(i, BOOKTYPE_SPELL)
        
        for idx = 1, numBig do
            local bigSpell = BIG_SPELLS[idx]
            if string.find(spellName, bigSpell.name) or (texture and string.find(texture, bigSpell.tex)) then
                if not knownSpells[bigSpell.name] then
                    knownSpells[bigSpell.name] = {
                        spellID   = i,
                        name      = bigSpell.name,
                        texture   = texture,
                        short     = bigSpell.short,
                    }
                end
            end
        end
        i = i + 1
    end
end

function PUIMage:GetMajorCooldowns()
    local list = {}
    local numBig = table.getn(BIG_SPELLS)
    for idx = 1, numBig do
        local def = BIG_SPELLS[idx]
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

-- Scan for Mana Gems in Bags
function PUIMage:GetManaGemInfo()
    local bestGem = nil
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots > 0 then
            for slot = 1, numSlots do
                local link = GetContainerItemLink(bag, slot)
                if link and (string.find(link, "Mana Ruby") or string.find(link, "Mana Citrine") or string.find(link, "Mana Jade") or string.find(link, "Mana Agate")) then
                    local texture = GetContainerItemInfo(bag, slot)
                    local start, duration = GetContainerItemCooldown(bag, slot)
                    local isReady = (start == 0 or not start)
                    local cdLeft = 0
                    if not isReady and duration and duration > 0 then
                        cdLeft = (start + duration) - GetTime()
                    end
                    return true, isReady, cdLeft, texture, link
                end
            end
        end
    end
    return false, false, 0, nil, nil
end

-- Create Button for Cooldown Widget
local function CreateCDButton(parent, index)
    local btn = CreateFrame("Button", "Primus_MageCDBtn_" .. index, parent)
    btn:SetWidth(32)
    btn:SetHeight(32)
    btn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    btn:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
    btn:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)

    local icon = btn:CreateTexture(nil, "BORDER")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = icon

    local cdText = btn:CreateFontString(nil, "OVERLAY")
    cdText:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    cdText:SetPoint("CENTER", btn, "CENTER", 0, 0)
    cdText:SetTextColor(1, 1, 0.4)
    btn.cdText = cdText

    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    label:SetPoint("BOTTOM", btn, "TOP", 0, 2)
    label:SetTextColor(0.8, 0.8, 0.8)
    btn.label = label

    spellButtons[index] = btn
    return btn
end

-- Update Mage Cooldown Display
function PUIMage:UpdateCooldowns()
    if not hudFrame or not hudFrame:IsShown() then return end

    local activeCount = 0

    -- 1. Display Big Spells
    for _, bigSpell in ipairs(BIG_SPELLS) do
        local info = knownSpells[bigSpell.name]
        if info then
            activeCount = activeCount + 1
            local btn = spellButtons[activeCount] or CreateCDButton(hudFrame, activeCount)
            btn.icon:SetTexture(info.texture or ("Interface\\Icons\\" .. bigSpell.tex))
            btn.label:SetText(info.short or bigSpell.name)

            local start, duration = GetSpellCooldown(info.spellID, BOOKTYPE_SPELL)
            local isReady = (start == 0 or not start)
            local cdLeft = 0
            if not isReady and duration and duration > 0 then
                cdLeft = (start + duration) - GetTime()
            end

            if isReady or cdLeft <= 0 then
                btn.icon:SetVertexColor(1, 1, 1)
                btn.cdText:SetText("")
                btn:SetBackdropBorderColor(0.2, 0.8, 0.4, 1) -- Green border when ready
            else
                btn.icon:SetVertexColor(0.4, 0.4, 0.4)
                btn.cdText:SetText(FormatCD(cdLeft))
                btn:SetBackdropBorderColor(0.8, 0.2, 0.2, 1) -- Red border on CD
            end

            btn:ClearAllPoints()
            btn:SetPoint("LEFT", hudFrame, "LEFT", (activeCount - 1) * 36 + 6, 0)
            btn:Show()
        end
    end

    -- 2. Display Mana Gem Slot
    local hasGem, gemReady, gemCD, gemTex = self:GetManaGemInfo()
    if hasGem then
        activeCount = activeCount + 1
        local btn = spellButtons[activeCount] or CreateCDButton(hudFrame, activeCount)
        btn.icon:SetTexture(gemTex or "Interface\\Icons\\INV_Misc_Gem_Ruby_01")
        btn.label:SetText("Gem")

        if gemReady or gemCD <= 0 then
            btn.icon:SetVertexColor(1, 1, 1)
            btn.cdText:SetText("")
            btn:SetBackdropBorderColor(0.2, 0.8, 1.0, 1)
        else
            btn.icon:SetVertexColor(0.4, 0.4, 0.4)
            btn.cdText:SetText(FormatCD(gemCD))
            btn:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
        end

        btn:ClearAllPoints()
        btn:SetPoint("LEFT", hudFrame, "LEFT", (activeCount - 1) * 36 + 6, 0)
        btn:Show()
    end

    -- Hide unused buttons
    for i = activeCount + 1, 12 do
        if spellButtons[i] then
            spellButtons[i]:Hide()
        end
    end

    -- Resize panel
    if activeCount > 0 then
        hudFrame:SetWidth(activeCount * 36 + 12)
    end
end

-- =========================================================================
-- POLYMORPH TRACKER (PolyTracker)
-- =========================================================================

local polyFrame = nil
local activePoly = {
    target = nil,
    duration = 50,
    startTime = 0,
    endTime = 0,
    texture = "Interface\\Icons\\Spell_Nature_Polymorph",
    isBroken = false,
}

local pendingPolyTarget = nil

-- Update PolyTracker UI
function PUIMage:UpdatePolyTracker()
    if not polyFrame then return end

    if activePoly.target then
        local now = GetTime()
        local remaining = activePoly.endTime - now

        if remaining <= 0 then
            activePoly.target = nil
            polyFrame:Hide()
            return
        end

        polyFrame.bar:SetMinMaxValues(0, activePoly.duration)
        polyFrame.bar:SetValue(remaining)
        polyFrame.timeText:SetText(string.format("%.1fs", remaining))
        polyFrame.nameText:SetText("Sheep: " .. activePoly.target)
        polyFrame.icon:SetTexture(activePoly.texture)

        if remaining <= 5 then
            polyFrame.bar:SetStatusBarColor(1.0, 0.2, 0.2) -- Red urgent
            polyFrame.bar.border:SetBackdropBorderColor(1.0, 0.2, 0.2, 1)
        elseif remaining <= 15 then
            polyFrame.bar:SetStatusBarColor(1.0, 0.8, 0.2) -- Yellow warning
            polyFrame.bar.border:SetBackdropBorderColor(1.0, 0.8, 0.2, 1)
        else
            polyFrame.bar:SetStatusBarColor(0.2, 0.8, 1.0) -- Blue normal
            polyFrame.bar.border:SetBackdropBorderColor(0.2, 0.6, 0.9, 1)
        end

        polyFrame:Show()
    else
        polyFrame:Hide()
    end
end

-- Start Polymorph Timer (Authentic Vanilla 1.12 Variants: Sheep, Pig, Turtle)
function PUIMage:StartPoly(targetName, spellName)
    local duration = 50 -- Default Rank 4
    local tex = "Interface\\Icons\\Spell_Nature_Polymorph"

    if spellName and string.find(spellName, "Pig") then
        tex = "Interface\\Icons\\Spell_Magic_PolymorphPig"
    elseif spellName and string.find(spellName, "Turtle") then
        tex = "Interface\\Icons\\Ability_Hunter_Pet_Turtle"
    end


    activePoly.target = targetName or "Target"
    activePoly.duration = duration
    activePoly.startTime = GetTime()
    activePoly.endTime = activePoly.startTime + duration
    activePoly.texture = tex
    activePoly.isBroken = false

    self:UpdatePolyTracker()
end

-- Stop/Break Polymorph
function PUIMage:BreakPoly(targetName)
    if activePoly.target and (not targetName or string.find(targetName, activePoly.target)) then
        activePoly.target = nil
        if polyFrame then
            polyFrame:Hide()
        end
    end
end

function PUIMage:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIMage", {
        name = "Class_Mage",
        category = "Classes",
        label = "Mage Nuances",
        options = {
            {
                key = "enabled",
                type = "checkbox",
                label = "Enable Mage Suite",
                desc = "Show major cooldown icons, Mana Gem status, and Polymorph tracker.",
                default = true,
                get = function() return mageDB:Get("enabled") end,
                set = function(v)
                    mageDB:Set("enabled", v)
                    if v then hudFrame:Show() else hudFrame:Hide() end
                end,
            },
        },
    })
end

function PUIMage:OnInitialize()
    -- 1. Create Mage Major Cooldowns HUD
    hudFrame = CreateFrame("Frame", "Primus_MageHUD", UIParent)
    hudFrame:SetWidth(200)
    hudFrame:SetHeight(42)
    hudFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 160)
    hudFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
    hudFrame:SetBackdropColor(0.06, 0.08, 0.12, 0.9)
    hudFrame:SetBackdropBorderColor(0.2, 0.6, 0.9, 1)

    self:ScanSpellbook()

    for i = 1, 14 do
        local btn = CreateCDButton(hudFrame, i)
        btn:Hide()
    end

    local mover = PUIMover or Primus.PUIMover
    if mover and mover.Register then
        mover:Register(hudFrame, "MageHUD", "Mage Major Cooldowns", "CLASS")
    end

    -- 2. Create PolyTracker Status Bar Frame
    polyFrame = CreateFrame("Frame", "Primus_PolyTracker", UIParent)
    polyFrame:SetWidth(180)
    polyFrame:SetHeight(24)
    polyFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    polyFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
    polyFrame:SetBackdropColor(0.06, 0.08, 0.12, 0.9)
    polyFrame:SetBackdropBorderColor(0.2, 0.6, 0.9, 1)
    polyFrame:Hide()

    local polyIcon = polyFrame:CreateTexture(nil, "BORDER")
    polyIcon:SetWidth(20)
    polyIcon:SetHeight(20)
    polyIcon:SetPoint("LEFT", polyFrame, "LEFT", 2, 0)
    polyIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    polyIcon:SetTexture("Interface\\Icons\\Spell_Nature_Polymorph")
    polyFrame.icon = polyIcon

    local bar = CreateFrame("StatusBar", nil, polyFrame)
    bar:SetPoint("TOPLEFT", polyIcon, "TOPRIGHT", 4, -2)
    bar:SetPoint("BOTTOMRIGHT", polyFrame, "BOTTOMRIGHT", -2, 2)
    bar:SetStatusBarTexture(Media:Fetch("statusbar", "Default"))
    bar:SetStatusBarColor(0.2, 0.8, 1.0)
    polyFrame.bar = bar

    local barBorder = CreateFrame("Frame", nil, bar)
    barBorder:SetAllPoints(bar)
    barBorder:SetBackdrop(Media:Fetch("border", "1Pixel"))
    barBorder:SetBackdropColor(0, 0, 0, 0)
    barBorder:SetBackdropBorderColor(0.2, 0.6, 0.9, 1)
    bar.border = barBorder

    local nameText = bar:CreateFontString(nil, "OVERLAY")
    nameText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    nameText:SetPoint("LEFT", bar, "LEFT", 4, 0)
    nameText:SetTextColor(1, 1, 1)
    polyFrame.nameText = nameText

    local timeText = bar:CreateFontString(nil, "OVERLAY")
    timeText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    timeText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    timeText:SetTextColor(1, 1, 0.4)
    if mover and mover.Register then
        mover:Register(polyFrame, "PolyTracker", "Mage PolyTracker", "CLASS")
    end

    self:RegisterOptionsFlare()
end

function PUIMage:OnEnable()
    if hudFrame and mageDB:Get("enabled") then
        hudFrame:Show()
    end

    -- 3. Events
    Events:Register("SPELLS_CHANGED", self, function()
        PUIMage:ScanSpellbook()
        PUIMage:UpdateCooldowns()
    end)
    Events:Register("LEARNED_SPELL_IN_TAB", self, function()
        PUIMage:ScanSpellbook()
        PUIMage:UpdateCooldowns()
    end)
    Events:Register("BAG_UPDATE", self, function()
        PUIMage:UpdateCooldowns()
    end)
    Events:Register("SPELL_UPDATE_COOLDOWN", self, function()
        PUIMage:UpdateCooldowns()
    end)

    -- Cast & Combat Log Tracking for Poly
    Events:Register("SPELLCAST_START", self, function(owner, event, spellName)
        if spellName and string.find(spellName, "Polymorph") then
            pendingPolyTarget = UnitName("target")
        end
    end)

    Events:Register("SPELLCAST_STOP", self, function()
        if pendingPolyTarget then
            PUIMage:StartPoly(pendingPolyTarget, "Polymorph")
            pendingPolyTarget = nil
        end
    end)

    Events:Register("CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS", self, function(owner, event, msg)
        if msg and string.find(msg, "is afflicted by Polymorph") then
            local _, _, target = string.find(msg, "(.+) is afflicted by Polymorph")
            PUIMage:StartPoly(target or UnitName("target"), "Polymorph")
        end
    end)

    Events:Register("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS", self, function(owner, event, msg)
        if msg and string.find(msg, "is afflicted by Polymorph") then
            local _, _, target = string.find(msg, "(.+) is afflicted by Polymorph")
            PUIMage:StartPoly(target or UnitName("target"), "Polymorph")
        end
    end)

    Events:Register("CHAT_MSG_SPELL_AURA_GONE_OTHER", self, function(owner, event, msg)
        if msg and string.find(msg, "Polymorph") then
            local _, _, target = string.find(msg, "Polymorph .* from (.+)%.")
            PUIMage:BreakPoly(target)
        end
    end)

    Events:Register("CHAT_MSG_SPELL_SELF_DAMAGE", self, function(owner, event, msg)
        if msg and (string.find(msg, "Your Polymorph was resisted") or string.find(msg, "Your Polymorph was immune")) then
            PUIMage:BreakPoly()
        end
    end)

    -- 0.2s Ticker for Cooldown Animations & PolyTracker
    Time:Every(0.2, function()
        PUIMage:UpdateCooldowns()
        PUIMage:UpdatePolyTracker()
    end, self)

    self:UpdateCooldowns()
end

function PUIMage:OnDisable()
    Time:CancelAll(self)
    Events:UnregisterOwner(self)
    if hudFrame then hudFrame:Hide() end
    if polyFrame then polyFrame:Hide() end
end



