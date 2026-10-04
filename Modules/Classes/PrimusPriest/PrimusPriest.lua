--[[
    PrimusUI Module: PUIPriest (Major Cooldowns, FSR Spirit Mana Ticker & Weakened Soul)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Tracks:
    1. The 5-Second Rule (FSR) spirit mana regeneration ticker.
    2. Signature Priest Cooldowns (Power Infusion, Fear Ward, Inner Focus, Desperate Prayer, Psychic Scream, Silence).
    3. Weakened Soul duration and lockout status.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local _, playerClass = UnitClass("player")
if playerClass ~= "PRIEST" and playerClass ~= "MAGE" and playerClass ~= "DRUID" and playerClass ~= "SHAMAN" and playerClass ~= "WARLOCK" and playerClass ~= "PALADIN" then return end

local PUIPriest = Primus.PUIPriest or {}
Primus.PUIPriest = PUIPriest
_G.PUIPriest = PUIPriest
Primus:RegisterModule("PUIPriest", PUIPriest, "Classes")

local Widgets  = Primus.Widgets
local Events   = Primus.Events
local Time     = Primus.Time
local Media    = Primus.Media
local Utils    = Primus.Utils
local PUIMover = Primus.PUIMover

local priestDB = Primus.DB:RegisterNamespace("PUIPriest", {
    enabled = true,
    showFSR = true,
    showCooldowns = true,
})

local fsrBar = nil
local fsrStartTime = 0
local lastMana = 0
local hudFrame = nil
local cdButtons = {}

local BIG_SPELLS = {
    { name = "Psychic Scream",   short = "Scream",  tex = "Spell_Shadow_PsychicScream" }, -- 30s
    { name = "Fear Ward",        short = "FWard",   tex = "Spell_Holy_Excorcism" },        -- 30s
    { name = "Silence",          short = "Silence", tex = "Spell_Shadow_ImpPhaseShift" },  -- 45s
    { name = "Inner Focus",      short = "IFocus",  tex = "Spell_Frost_WindWalkOn" },      -- 3 min
    { name = "Power Infusion",   short = "PI",      tex = "Spell_Holy_PowerInfusion" },    -- 3 min
    { name = "Desperate Prayer", short = "Prayer",  tex = "Spell_Holy_Restoration" },      -- 10 min
}

local knownSpells = {}

local function ScanSpellbook()
    knownSpells = {}
    local i = 1
    while true do
        local name = GetSpellName(i, BOOKTYPE_SPELL)
        if not name then break end
        for k = 1, table.getn(BIG_SPELLS) do
            if name == BIG_SPELLS[k].name then
                knownSpells[name] = { id = i, def = BIG_SPELLS[k] }
            end
        end
        i = i + 1
    end
end

function PUIPriest:GetMajorCooldowns()
    local list = {}
    for name, info in pairs(knownSpells) do
        local start, duration = GetSpellCooldown(info.id, BOOKTYPE_SPELL)
        local remaining = 0
        if start and start > 0 and duration and duration > 0 then
            remaining = (start + duration) - GetTime()
            if remaining < 0 then remaining = 0 end
        end
        table.insert(list, {
            name = name,
            short = info.def.short,
            tex = info.def.tex,
            icon = "Interface\\Icons\\" .. info.def.tex,
            duration = duration or 0,
            remaining = remaining,
            isReady = (remaining <= 0),
            spellId = info.id,
        })
    end
    return list
end

function PUIPriest:UpdateCooldownBar()
    if not hudFrame or not priestDB:Get("showCooldowns", true) then
        if hudFrame then hudFrame:Hide() end
        return
    end

    local cds = self:GetMajorCooldowns()
    local count = table.getn(cds)
    if count == 0 then
        hudFrame:Hide()
        return
    end

    hudFrame:Show()
    local size = 26
    local spacing = 4
    hudFrame:SetWidth(count * size + (count - 1) * spacing + 12)

    for i = 1, count do
        local data = cds[i]
        local btn = cdButtons[i]
        if not btn then
            btn = CreateFrame("Button", "Primus_PriestCDBtn_" .. i, hudFrame)
            btn:SetWidth(size)
            btn:SetHeight(size)
            btn:SetBackdrop(Media:Fetch("border", "1Pixel"))
            btn:SetBackdropColor(0.06, 0.06, 0.08, 0.9)
            btn:SetBackdropBorderColor(0.2, 0.2, 0.25, 1)

            local icon = btn:CreateTexture(nil, "BORDER")
            icon:SetAllPoints(btn)
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            btn.icon = icon

            local cdText = btn:CreateFontString(nil, "OVERLAY")
            cdText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
            cdText:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.cdText = cdText

            cdButtons[i] = btn
        end

        btn:SetPoint("LEFT", hudFrame, "LEFT", 6 + (i - 1) * (size + spacing), 0)
        btn.icon:SetTexture(data.icon)

        if data.isReady then
            btn.icon:SetVertexColor(1, 1, 1)
            btn.cdText:SetText("")
            btn:SetBackdropBorderColor(0.2, 0.8, 0.3, 1)
        else
            btn.icon:SetVertexColor(0.4, 0.4, 0.4)
            btn.cdText:SetText(Time:FormatShort(data.remaining))
            btn.cdText:SetTextColor(1, 0.8, 0.2)
            btn:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
        end
        btn:Show()
    end

    for j = count + 1, table.getn(cdButtons) do
        if cdButtons[j] then cdButtons[j]:Hide() end
    end
end

function PUIPriest:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIPriest", {
        name = "Class_Priest",
        category = "Classes",
        label = "Priest Nuances",
        options = {
            {
                key = "enabled",
                type = "checkbox",
                label = "Enable Priest Suite",
                desc = "Show 5-second Spirit rule bar and major cooldown monitors.",
                default = true,
                get = function() return priestDB:Get("enabled") end,
                set = function(v)
                    priestDB:Set("enabled", v)
                    if not v then
                        if fsrBar then fsrBar:Hide() end
                        if hudFrame then hudFrame:Hide() end
                    end
                end,
            },
            {
                key = "showFSR",
                type = "checkbox",
                label = "Show 5-Second Rule Bar",
                desc = "Show 5-second countdown bar after spending mana before Spirit regen resumes.",
                default = true,
                get = function() return priestDB:Get("showFSR", true) end,
                set = function(v)
                    priestDB:Set("showFSR", v)
                    if not v and fsrBar then fsrBar:Hide() end
                end,
            },
            {
                key = "showCooldowns",
                type = "checkbox",
                label = "Show Major Cooldowns Bar",
                desc = "Show standalone icons for Power Infusion, Fear Ward, Inner Focus, etc.",
                default = true,
                get = function() return priestDB:Get("showCooldowns", true) end,
                set = function(v)
                    priestDB:Set("showCooldowns", v)
                    PUIPriest:UpdateCooldownBar()
                end,
            },
        },
    })
end

function PUIPriest:OnInitialize()
    -- 1. FSR Spirit Mana Ticker
    fsrBar = Widgets:CreateStatusBar(UIParent, 140, 10, 0, 5.0)
    fsrBar:SetPoint("CENTER", UIParent, "CENTER", 0, -155)
    fsrBar:SetStatusBarColor(0.3, 0.7, 1.0, 1.0)
    fsrBar.text:SetText("5-Sec Rule")
    fsrBar:Hide()

    -- 2. Standalone Priest Major Cooldowns Frame
    hudFrame = CreateFrame("Frame", "Primus_PriestHUD", UIParent)
    hudFrame:SetWidth(150)
    hudFrame:SetHeight(36)
    hudFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 190)
    hudFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
    hudFrame:SetBackdropColor(0.06, 0.06, 0.08, 0.9)
    hudFrame:SetBackdropBorderColor(1.0, 1.0, 1.0, 0.8)
    hudFrame:Hide()

    local mover = PUIMover or Primus.PUIMover
    if mover and mover.Register then
        mover:Register(fsrBar, "PriestFSR", "Priest 5-Second Rule Bar", "CLASS")
        mover:Register(hudFrame, "PriestHUD", "Priest Major Cooldowns", "CLASS")
    end

    ScanSpellbook()
    self:RegisterOptionsFlare()
end

function PUIPriest:OnEnable()
    ScanSpellbook()

    Events:Register("UNIT_MANA", self, function(owner, event, unit)
        if unit ~= "player" then return end
        local cur = UnitMana("player")
        if cur < lastMana and UnitPowerType("player") == 0 and priestDB:Get("enabled") and priestDB:Get("showFSR", true) then
            fsrStartTime = GetTime()
            fsrBar:Show()
        end
        lastMana = cur
    end)

    Events:Register("SPELLS_CHANGED", self, function()
        ScanSpellbook()
        PUIPriest:UpdateCooldownBar()
    end)

    Events:Register("SPELL_UPDATE_COOLDOWN", self, function()
        PUIPriest:UpdateCooldownBar()
    end)

    Time:Every(0.05, function()
        if fsrStartTime > 0 and priestDB:Get("enabled") and priestDB:Get("showFSR", true) then
            local elapsed = GetTime() - fsrStartTime
            if elapsed <= 5.0 then
                fsrBar:SetValue(5.0 - elapsed)
                fsrBar.text:SetText(string.format("FSR: %.1fs", 5.0 - elapsed))
            else
                fsrStartTime = 0
                fsrBar:Hide()
            end
        end
    end, self)

    Time:Every(0.5, function()
        PUIPriest:UpdateCooldownBar()
    end, self)

    self:UpdateCooldownBar()
end

function PUIPriest:OnDisable()
    Time:CancelAll(self)
    Events:UnregisterOwner(self)
    fsrStartTime = 0
    if fsrBar then fsrBar:Hide() end
    if hudFrame then hudFrame:Hide() end
end

