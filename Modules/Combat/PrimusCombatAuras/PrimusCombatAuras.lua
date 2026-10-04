--[[
    PrimusLib Module: AuraEngine (Hidden Tooltip Buff/Debuff Scanner)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Extracts real spell names, stack counts, debuff types (Magic, Curse,
    Poison, Disease), and tooltip descriptions from Vanilla 1.12 units.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUICombatAuras = Primus.PUICombatAuras or {}
Primus.PUICombatAuras = PUICombatAuras
_G.PUICombatAuras = PUICombatAuras
Primus:RegisterModule("PUICombatAuras", PUICombatAuras, "Combat")

local Events = Primus.Events
local Memory = Primus.Memory
local Utils  = Primus.Utils

-- Dispel Classification Colors
PUICombatAuras.DispelColors = {
    ["Magic"]   = { r = 0.20, g = 0.60, b = 1.00, hex = "3399ff" }, -- Blue
    ["Curse"]   = { r = 0.60, g = 0.00, b = 1.00, hex = "9900ff" }, -- Purple
    ["Poison"]  = { r = 0.00, g = 0.60, b = 0.00, hex = "009900" }, -- Green
    ["Disease"] = { r = 0.60, g = 0.40, b = 0.00, hex = "996600" }, -- Brown/Yellow
    ["None"]    = { r = 0.80, g = 0.00, b = 0.00, hex = "cc0000" }, -- Red
}

-- Hidden Tooltip for reading aura metadata
local scannerTip = CreateFrame("GameTooltip", "Primus_AuraScannerTip", UIParent, "GameTooltipTemplate")
scannerTip:SetOwner(UIParent, "ANCHOR_NONE")

-- Read aura metadata from unit slot
function PUICombatAuras:ScanUnitAura(unit, index, isDebuff)
    scannerTip:ClearLines()
    if isDebuff then
        scannerTip:SetUnitDebuff(unit, index)
    else
        scannerTip:SetUnitBuff(unit, index)
    end

    local spellName = Primus_AuraScannerTipTextLeft1:GetText()
    if not spellName or spellName == "" then return nil end

    local debuffType = Primus_AuraScannerTipTextRight1:GetText() or "None"
    local desc = Primus_AuraScannerTipTextLeft2:GetText() or ""

    local auraData = Memory:AcquireTable()
    auraData.index = index
    auraData.unit = unit
    auraData.name = spellName
    auraData.isDebuff = isDebuff or false
    auraData.debuffType = debuffType
    auraData.texture = isDebuff and UnitDebuff(unit, index) or UnitBuff(unit, index)

    return auraData
end

-- Get all auras on a unit
function PUICombatAuras:GetUnitAuras(unit, isDebuff, destList)
    destList = destList or {}
    Utils.Wipe(destList)

    local maxAuras = isDebuff and 16 or 32
    for i = 1, maxAuras do
        local texture = isDebuff and UnitDebuff(unit, i) or UnitBuff(unit, i)
        if not texture then break end

        local data = self:ScanUnitAura(unit, i, isDebuff)
        if data then
            table.insert(destList, data)
        end
    end

    return destList
end

function PUICombatAuras:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUICombatAuras", {
        name = "PUICombatAuras",
        category = "Combat",
        label = "Combat Auras Engine",
        icon = "Interface\Icons\Spell_Holy_WordFortitude",
        desc = "Extracts spell names, stack counts, and debuff types (Magic, Curse, Poison, Disease).",
    })
end

function PUICombatAuras:OnInitialize()
    self:RegisterOptionsFlare()
    -- Clear scanner tooltip
    scannerTip:Hide()
end
