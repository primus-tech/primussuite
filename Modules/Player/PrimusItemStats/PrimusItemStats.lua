--[[
    PrimusLib Module: ItemStats (BonusScanner for Vanilla 1.12.1)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Scans equipped gear tooltips to compute true combat stats:
    +Spell Damage (All Schools), +Healing, +Hit, +Crit, MP5, and Defense.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIItemStats = Primus.PUIItemStats or {}
Primus.PUIItemStats = PUIItemStats
_G.PUIItemStats = PUIItemStats
Primus:RegisterModule("PUIItemStats", PUIItemStats, "Player")

local Events = Primus.Events
local Memory = Primus.Memory
local Utils  = Primus.Utils

-- Total Computed Stats
PUIItemStats.stats = {
    spellDamage = 0,
    healing = 0,
    spellHit = 0,
    spellCrit = 0,
    meleeHit = 0,
    meleeCrit = 0,
    mp5 = 0,
    defense = 0,
    schools = {
        ["Arcane"] = 0,
        ["Fire"]   = 0,
        ["Frost"]  = 0,
        ["Holy"]   = 0,
        ["Nature"] = 0,
        ["Shadow"] = 0,
    }
}

-- Hidden Tooltip Scanner
local statTip = CreateFrame("GameTooltip", "Primus_StatScanTip", UIParent, "GameTooltipTemplate")
statTip:SetOwner(UIParent, "ANCHOR_NONE")

-- Parse a single line of tooltip text
local function ParseStatLine(text)
    if not text or text == "" then return end

    -- "Increases damage and healing done by magical spells and effects by up to %d."
    local _, _, dmg = string.find(text, "Increases damage and healing done by magical spells and effects by up to (%d+)%.")
    if dmg then
        local val = tonumber(dmg) or 0
        PUIItemStats.stats.spellDamage = PUIItemStats.stats.spellDamage + val
        PUIItemStats.stats.healing = PUIItemStats.stats.healing + val
    end

    -- "Increases healing done by spells and effects by up to %d."
    local _, _, heal = string.find(text, "Increases healing done by spells and effects by up to (%d+)%.")
    if heal then
        PUIItemStats.stats.healing = PUIItemStats.stats.healing + (tonumber(heal) or 0)
    end

    -- Specific Schools (e.g. Shadow, Frost, Fire, Nature, Holy, Arcane)
    for school in pairs(PUIItemStats.stats.schools) do
        local _, _, schDmg = string.find(text, "Increases damage done by " .. school .. " spells and effects by up to (%d+)%.")
        if schDmg then
            PUIItemStats.stats.schools[school] = PUIItemStats.stats.schools[school] + (tonumber(schDmg) or 0)
        end
    end

    -- "Restores %d mana per 5 sec."
    local _, _, mp5 = string.find(text, "Restores (%d+) mana per 5 sec%.")
    if mp5 then
        PUIItemStats.stats.mp5 = PUIItemStats.stats.mp5 + (tonumber(mp5) or 0)
    end

    -- "Improves your chance to hit with spells by %d%%."
    local _, _, sHit = string.find(text, "Improves your chance to hit with spells by (%d+)%%%.")
    if sHit then
        PUIItemStats.stats.spellHit = PUIItemStats.stats.spellHit + (tonumber(sHit) or 0)
    end

    -- "Improves your chance to get a critical strike with spells by %d%%."
    local _, _, sCrit = string.find(text, "Improves your chance to get a critical strike with spells by (%d+)%%%.")
    if sCrit then
        PUIItemStats.stats.spellCrit = PUIItemStats.stats.spellCrit + (tonumber(sCrit) or 0)
    end

    -- "Increases defense by %d."
    local _, _, def = string.find(text, "Increases defense by (%d+)%.")
    if def then
        PUIItemStats.stats.defense = PUIItemStats.stats.defense + (tonumber(def) or 0)
    end
end

-- Scan all 19 equipment slots
function PUIItemStats:ScanEquippedGear()
    -- Reset stats
    self.stats.spellDamage = 0
    self.stats.healing = 0
    self.stats.spellHit = 0
    self.stats.spellCrit = 0
    self.stats.meleeHit = 0
    self.stats.meleeCrit = 0
    self.stats.mp5 = 0
    self.stats.defense = 0
    for school in pairs(self.stats.schools) do
        self.stats.schools[school] = 0
    end

    for slotID = 1, 19 do
        local link = GetInventoryItemLink("player", slotID)
        if link then
            statTip:ClearLines()
            statTip:SetInventoryItem("player", slotID)

            for lineIdx = 1, statTip:NumLines() do
                local leftText = _G["Primus_StatScanTipTextLeft" .. lineIdx]
                if leftText then
                    ParseStatLine(leftText:GetText())
                end
            end
        end
    end

    Events:Fire("ITEM_STATS_UPDATED", self.stats)
end

function PUIItemStats:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIItemStats", {
        name = "PUIItemStats",
        category = "Player",
        label = "Item Stats & Budget",
        icon = "Interface\Icons\INV_Misc_QuestionMark",
        desc = "Calculates stat budget, effective health, and bonus spell power ratings.",
    })
end

function PUIItemStats:OnInitialize()
    self:RegisterOptionsFlare()
    Events:Register("PLAYER_EQUIPMENT_CHANGED", self, function()
        PUIItemStats:ScanEquippedGear()
    end)
    Events:Register("PLAYER_ENTERING_WORLD", self, function()
        PUIItemStats:ScanEquippedGear()
    end)

    -- Initial scan
    self:ScanEquippedGear()
end
