--[[
    PrimusLib Module: Class_Warlock (Soul Shards, Stones & Curse Engine)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Tracks Soul Shard inventory counts, Healthstone/Soulstone readiness,
    active demon pet status, and real-time target curse/DoT durations.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local _, playerClass = UnitClass("player")
if playerClass ~= "WARLOCK" then return end

local PUIWarlock = Primus.PUIWarlock or {}
Primus.PUIWarlock = PUIWarlock
_G.PUIWarlock = PUIWarlock
Primus:RegisterModule("PUIWarlock", PUIWarlock, "Classes")

local DB      = Primus.DB
local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local Events  = Primus.Events
local Time    = Primus.Time
local PUIMover = Primus.PUIMover

local warlockDB = DB:RegisterNamespace("PUIWarlock", {
    enabled = true,
    maxShards = 28,
})

local hudFrame = nil

-- Known Warlock Curse & DoT Textures
local WARLOCK_DEBUFFS = {
    ["Spell_Shadow_ChillTouch"]              = "CoE",       -- Curse of Elements
    ["Spell_Shadow_CurseOfAchimonde"]        = "CoS",       -- Curse of Shadow
    ["Spell_Shadow_UnholyStrength"]          = "CoR",       -- Curse of Recklessness
    ["Spell_Shadow_CurseOfSargeras"]         = "Agony",     -- Curse of Agony
    ["Spell_Shadow_AuraOfDarkness"]          = "Doom",      -- Curse of Doom
    ["Spell_Shadow_CurseOfTounges"]          = "Tongues",   -- Curse of Tongues
    ["Spell_Shadow_CurseOfMannoroth"]        = "Weakness",  -- Curse of Weakness
    ["Spell_Shadow_AbominationExplosion"]    = "Corruption",-- Corruption
    ["Spell_Fire_Immolation"]                = "Immolate",  -- Immolate
    ["Spell_Shadow_Requiem"]                 = "Siphon",    -- Siphon Life
}

local WARLOCK_BIG_SPELLS = {
    { name = "Soulstone Resurrection", short = "SS",       tex = "Spell_Shadow_SoulGem" },
    { name = "Death Coil",             short = "DCoil",    tex = "Spell_Shadow_DeathCoil" },
    { name = "Howl of Terror",         short = "Howl",     tex = "Spell_Shadow_DeathScream" },
    { name = "Shadowburn",             short = "Sburn",    tex = "Spell_Shadow_ScourgeBuild" },
    { name = "Soul Link",              short = "SLink",    tex = "Spell_Shadow_GatherShadows" },
    { name = "Amplify Curse",          short = "AmpCurse", tex = "Spell_Shadow_Contagion" },
    { name = "Fel Domination",         short = "FelDom",   tex = "Spell_Nature_RemoveCurse" },
}

local knownSpells = {}

function PUIWarlock:ScanSpellbook()
    knownSpells = {}
    local i = 1
    local numBig = table.getn(WARLOCK_BIG_SPELLS)
    while true do
        local spellName = GetSpellName(i, BOOKTYPE_SPELL)
        if not spellName then break end
        local texture = GetSpellTexture(i, BOOKTYPE_SPELL)
        for idx = 1, numBig do
            local bigSpell = WARLOCK_BIG_SPELLS[idx]
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

function PUIWarlock:GetMajorCooldowns()
    local list = {}
    local numBig = table.getn(WARLOCK_BIG_SPELLS)
    for idx = 1, numBig do
        local def = WARLOCK_BIG_SPELLS[idx]
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

-- Count Soul Shards in Bags
function PUIWarlock:GetSoulShardCount()
    local count = 0
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots > 0 then
            for slot = 1, numSlots do
                local link = GetContainerItemLink(bag, slot)
                if link and string.find(link, "Soul Shard") then
                    local _, itemCount = GetContainerItemInfo(bag, slot)
                    count = count + (itemCount or 1)
                end
            end
        end
    end
    return count
end

-- Check Healthstone Availability & Cooldown
function PUIWarlock:GetHealthstoneInfo()
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots > 0 then
            for slot = 1, numSlots do
                local link = GetContainerItemLink(bag, slot)
                if link and string.find(link, "Healthstone") then
                    local start, duration = GetContainerItemCooldown(bag, slot)
                    local isReady = (start == 0 or not start)
                    local cdLeft = 0
                    if not isReady and duration and duration > 0 then
                        cdLeft = (start + duration) - GetTime()
                    end
                    return true, isReady, cdLeft, link
                end
            end
        end
    end
    return false, false, 0, nil
end

-- Check Soulstone in Bag
function PUIWarlock:GetSoulstoneInfo()
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots > 0 then
            for slot = 1, numSlots do
                local link = GetContainerItemLink(bag, slot)
                if link and string.find(link, "Soulstone") then
                    local start, duration = GetContainerItemCooldown(bag, slot)
                    local isReady = (start == 0 or not start)
                    local cdLeft = 0
                    if not isReady and duration and duration > 0 then
                        cdLeft = (start + duration) - GetTime()
                    end
                    return true, isReady, cdLeft, link
                end
            end
        end
    end
    return false, false, 0, nil
end

-- Scan Target Curser / DoT
function PUIWarlock:GetTargetCurseInfo()
    if not UnitExists("target") or UnitIsDead("target") then
        return nil, nil
    end

    for i = 1, 16 do
        local texture = UnitDebuff("target", i)
        if not texture then break end
        for texKey, name in pairs(WARLOCK_DEBUFFS) do
            if string.find(texture, texKey) then
                return name, texture
            end
        end
    end
    return nil, nil
end

-- Update HUD Display
function PUIWarlock:UpdateHUD()
    if not hudFrame or not hudFrame:IsShown() then return end

    -- 1. Shards
    local shards = self:GetSoulShardCount()
    hudFrame.shardText:SetText(string.format("Shards: %d", shards))
    if shards <= 3 then
        hudFrame.shardText:SetTextColor(1.0, 0.2, 0.2)
    elseif shards <= 8 then
        hudFrame.shardText:SetTextColor(1.0, 0.8, 0.2)
    else
        hudFrame.shardText:SetTextColor(0.6, 0.4, 0.9)
    end

    -- 2. Healthstone
    local hasHS, hsReady, hsCD = self:GetHealthstoneInfo()
    if hasHS then
        if hsReady then
            hudFrame.hsText:SetText("HS: Ready")
            hudFrame.hsText:SetTextColor(0.2, 1.0, 0.2)
        else
            hudFrame.hsText:SetText(string.format("HS: %ds", math.floor(hsCD)))
            hudFrame.hsText:SetTextColor(0.7, 0.7, 0.7)
        end
    else
        hudFrame.hsText:SetText("HS: None")
        hudFrame.hsText:SetTextColor(0.5, 0.5, 0.5)
    end

    -- 3. Soulstone
    local hasSS, ssReady, ssCD = self:GetSoulstoneInfo()
    if hasSS then
        if ssReady then
            hudFrame.ssText:SetText("SS: Ready")
            hudFrame.ssText:SetTextColor(0.2, 1.0, 0.8)
        else
            hudFrame.ssText:SetText(string.format("SS: %dm", math.ceil(ssCD / 60)))
            hudFrame.ssText:SetTextColor(0.7, 0.7, 0.7)
        end
    else
        hudFrame.ssText:SetText("SS: None")
        hudFrame.ssText:SetTextColor(0.5, 0.5, 0.5)
    end

    -- 4. Target Curse
    local curseName, curseTex = self:GetTargetCurseInfo()
    if curseName then
        hudFrame.curseText:SetText("Curse: " .. curseName)
        hudFrame.curseText:SetTextColor(1.0, 0.6, 0.2)
    else
        hudFrame.curseText:SetText("Curse: None")
        hudFrame.curseText:SetTextColor(0.5, 0.5, 0.5)
    end
end

function PUIWarlock:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIWarlock", {
        name = "Class_Warlock",
        category = "Classes",
        label = "Warlock Nuances",
        options = {
            {
                key = "enabled",
                type = "checkbox",
                label = "Enable Warlock Suite",
                desc = "Show Soul Shard counter, Healthstone/Soulstone ready status, and target curse.",
                default = true,
                get = function() return warlockDB:Get("enabled") end,
                set = function(v)
                    warlockDB:Set("enabled", v)
                    if v then hudFrame:Show() else hudFrame:Hide() end
                end,
            },
            {
                key = "maxShards",
                type = "slider",
                label = "Max Desired Shards",
                desc = "Threshold for bag shard capacity warning.",
                min = 10,
                max = 32,
                step = 2,
                default = 28,
                get = function() return warlockDB.maxShards or 28 end,
                set = function(v) warlockDB.maxShards = v end,
            },
        },
    })
end

function PUIWarlock:OnInitialize()
    -- Create Warlock HUD Panel
    hudFrame = CreateFrame("Frame", "Primus_WarlockHUD", UIParent)
    hudFrame:SetWidth(280)
    hudFrame:SetHeight(32)
    hudFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 170)
    hudFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
    hudFrame:SetBackdropColor(0.06, 0.04, 0.08, 0.9)
    hudFrame:SetBackdropBorderColor(0.4, 0.2, 0.6, 1)

    -- Shard Icon & Text
    local shardIcon = hudFrame:CreateTexture(nil, "ARTWORK")
    shardIcon:SetWidth(20)
    shardIcon:SetHeight(20)
    shardIcon:SetPoint("LEFT", hudFrame, "LEFT", 6, 0)
    shardIcon:SetTexture("Interface\\Icons\\INV_Misc_Gem_Amethyst_02")
    shardIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local shardText = hudFrame:CreateFontString(nil, "OVERLAY")
    shardText:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    shardText:SetPoint("LEFT", shardIcon, "RIGHT", 4, 0)
    shardText:SetText("Shards: 0")
    hudFrame.shardText = shardText

    -- Healthstone Text
    local hsText = hudFrame:CreateFontString(nil, "OVERLAY")
    hsText:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    hsText:SetPoint("LEFT", shardText, "RIGHT", 8, 0)
    hsText:SetText("HS: None")
    hudFrame.hsText = hsText

    -- Soulstone Text
    local ssText = hudFrame:CreateFontString(nil, "OVERLAY")
    ssText:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    ssText:SetPoint("LEFT", hsText, "RIGHT", 8, 0)
    ssText:SetText("SS: None")
    hudFrame.ssText = ssText

    -- Target Curse Text
    local curseText = hudFrame:CreateFontString(nil, "OVERLAY")
    curseText:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    curseText:SetPoint("LEFT", ssText, "RIGHT", 8, 0)
    curseText:SetText("Curse: None")
    hudFrame.curseText = curseText

    local mover = PUIMover or Primus.PUIMover
    if mover and mover.Register then
        mover:Register(hudFrame, "WarlockHUD", "Warlock Shards & Curses", "CLASS")
    end

    self:RegisterOptionsFlare()
end

function PUIWarlock:OnEnable()
    if hudFrame and warlockDB:Get("enabled") then
        hudFrame:Show()
    end

    -- Spellbook & Cooldown Events
    self:ScanSpellbook()
    Events:Register("SPELLS_CHANGED", self, function() PUIWarlock:ScanSpellbook() PUIWarlock:UpdateHUD() end)
    Events:Register("LEARNED_SPELL_IN_TAB", self, function() PUIWarlock:ScanSpellbook() PUIWarlock:UpdateHUD() end)
    Events:Register("SPELL_UPDATE_COOLDOWN", self, function() PUIWarlock:UpdateHUD() end)
    Events:Register("PLAYER_ENTERING_WORLD", self, function() PUIWarlock:ScanSpellbook() PUIWarlock:UpdateHUD() end)

    -- Event updates
    Events:Register("BAG_UPDATE", self, function()
        PUIWarlock:UpdateHUD()
    end)
    Events:Register("PLAYER_TARGET_CHANGED", self, function()
        PUIWarlock:UpdateHUD()
    end)
    Events:Register("UNIT_AURA", self, function()
        if arg1 == "target" or arg1 == "player" then
            PUIWarlock:UpdateHUD()
        end
    end)

    -- 1s Ticker for Cooldowns
    Time:Every(1.0, function()
        PUIWarlock:UpdateHUD()
    end, self)

    self:UpdateHUD()
end

function PUIWarlock:OnDisable()
    Time:CancelAll(self)
    Events:UnregisterOwner(self)
    if hudFrame then hudFrame:Hide() end
end


