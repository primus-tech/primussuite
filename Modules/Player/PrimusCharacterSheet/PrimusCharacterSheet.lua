--[[
    PrimusLib Module: CharacterSheet (Paperdoll Durability & True Stat Panel)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Overlays item durability percentages directly onto the character paperdoll
    and adds an extended combat stat panel displaying ItemStats outputs.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUICharacterSheet = Primus.PUICharacterSheet or {}
Primus.PUICharacterSheet = PUICharacterSheet
_G.PUICharacterSheet = PUICharacterSheet
Primus:RegisterModule("PUICharacterSheet", PUICharacterSheet, "Player")

local ItemStats = Primus.PUIItemStats
local Events    = Primus.Events
local Media     = Primus.Media
local Utils     = Primus.Utils

local durabilityTexts = {}
local statDisplayFrame = nil

-- Standard 1.12 Paperdoll slot names
local SLOTS = {
    "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
    "ShirtSlot", "TabardSlot", "WristSlot", "HandsSlot", "WaistSlot",
    "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot",
    "Trinket1Slot", "MainHandSlot", "SecondaryHandSlot", "RangedSlot"
}

-- Update paperdoll durability overlays
function PUICharacterSheet:UpdateDurability()
    local count = table.getn(SLOTS)
    for i = 1, count do
        local slotName = "Character" .. SLOTS[i]
        local slotBtn = _G[slotName]
        if slotBtn then
            local slotID, _ = GetInventorySlotInfo(SLOTS[i])
            local curDur, maxDur = Utils.GetInventoryItemDurability(slotID)

            local txt = durabilityTexts[slotName]
            if not txt then
                txt = slotBtn:CreateFontString(nil, "OVERLAY")
                txt:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
                txt:SetPoint("BOTTOM", slotBtn, "BOTTOM", 0, 2)
                durabilityTexts[slotName] = txt
            end

            if curDur and maxDur and maxDur > 0 then
                local pct = math.floor((curDur / maxDur) * 100)
                if pct < 100 then
                    local hex = "69ccf0"
                    if pct < 30 then hex = "ff4444"
                    elseif pct < 60 then hex = "ffbb33" end
                    txt:SetText(Utils.ColorText(pct .. "%", hex))
                else
                    txt:SetText("")
                end
            else
                txt:SetText("")
            end
        end
    end
end

-- Update Extended Stats Panel on Character Frame
function PUICharacterSheet:UpdateStatsPanel()
    if not statDisplayFrame or not CharacterFrame:IsShown() then return end

    local itemStats = Primus.PUIItemStats
    local stats = itemStats and itemStats.stats
    if not stats then return end

    statDisplayFrame.text:SetText(string.format(
        "%s: |cffffffff+%d|r\n%s: |cffffffff+%d|r\n%s: |cffffffff+%d%%|r\n%s: |cffffffff+%d%%|r\n%s: |cffffffff%d|r\n%s: |cffffffff+%d|r",
        Utils.ColorText("Spell Dmg", "69ccf0"), stats.spellDamage,
        Utils.ColorText("Healing", "abd473"), stats.healing,
        Utils.ColorText("Spell Hit", "ffbb33"), stats.spellHit,
        Utils.ColorText("Spell Crit", "ffbb33"), stats.spellCrit,
        Utils.ColorText("MP5", "33b5e5"), stats.mp5,
        Utils.ColorText("Defense", "f58cba"), stats.defense
    ))
end

function PUICharacterSheet:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUICharacterSheet", {
        name = "PUICharacterSheet",
        category = "Player",
        label = "Character Sheet",
        icon = "Interface\Icons\INV_Chest_Cloth_17",
        desc = "Enhanced character panel with item level calculation and stats breakdown.",
    })
end

function PUICharacterSheet:OnInitialize()
    self:RegisterOptionsFlare()
    -- Create side panel on CharacterFrame
    statDisplayFrame = CreateFrame("Frame", "Primus_CharStatFrame", CharacterFrame)
    statDisplayFrame:SetWidth(120)
    statDisplayFrame:SetHeight(140)
    statDisplayFrame:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", -32, -80)
    statDisplayFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
    statDisplayFrame:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    statDisplayFrame:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)

    local txt = statDisplayFrame:CreateFontString(nil, "OVERLAY")
    txt:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    txt:SetPoint("TOPLEFT", statDisplayFrame, "TOPLEFT", 6, -6)
    txt:SetJustifyH("LEFT")
    statDisplayFrame.text = txt

    -- Hook CharacterFrame show & equipment update
    Events:HookScript(CharacterFrame, "OnShow", function()
        PUICharacterSheet:UpdateDurability()
        PUICharacterSheet:UpdateStatsPanel()
    end)

    Events:Listen("ITEM_STATS_UPDATED", self, function()
        PUICharacterSheet:UpdateStatsPanel()
    end)

    Events:Register("UPDATE_INVENTORY_DURABILITY", self, function()
        PUICharacterSheet:UpdateDurability()
    end)
end
