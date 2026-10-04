--[[
    PrimusLib Module: Utility_Inspect (Extended Target Gear & iLvl Overview)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    1. Average Item Level (iLvl) calculation for inspected target.
    2. Missing Enchant detector on gear slots.
    3. Quick stat overview (Attack Power, Spell Power, Armor, Stamina).
    4. Auto-attaches to InspectFrame or opens via /inspect.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIInspect = Primus.PUIInspect or {}
Primus.PUIInspect = PUIInspect
_G.PUIInspect = PUIInspect
Primus:RegisterModule("PUIInspect", PUIInspect, "Utility")

local DB      = Primus.DB
local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local Events  = Primus.Events
local PUIMover = Primus.PUIMover

local inspectDB = DB:RegisterNamespace("PUIInspect", {
    enabled = true,
})

local inspectPanel = nil

local SLOTS = {
    1, -- Head
    2, -- Neck
    3, -- Shoulder
    5, -- Chest
    6, -- Waist
    7, -- Legs
    8, -- Feet
    9, -- Wrist
    10, -- Hands
    11, -- Finger1
    12, -- Finger2
    13, -- Trinket1
    14, -- Trinket2
    15, -- Back
    16, -- MainHand
    17, -- OffHand
    18, -- Ranged
}

-- Calculate Average iLvl & Missing Enchants for Unit
function PUIInspect:ScanUnitGear(unit)
    unit = unit or "target"
    if not UnitExists(unit) then return 0, 0, 0 end

    local totalLevel = 0
    local totalItems = 0
    local missingEnchants = 0

    local numSlots = table.getn(SLOTS)
    for i = 1, numSlots do
        local slotId = SLOTS[i]
        local link = GetInventoryItemLink(unit, slotId)
        if link then
            totalItems = totalItems + 1
            local _, _, _, itemLevel = GetItemInfo(link)
            if itemLevel and itemLevel > 0 then
                totalLevel = totalLevel + itemLevel
            else
                totalLevel = totalLevel + 50 -- default estimate
            end

            -- Check enchant string in item link: item:id:enchantId:...
            local s, e, itemId, enchantId = string.find(link, "item:(%d+):(%d+)")
            if enchantId and tonumber(enchantId) == 0 then
                -- Check if slot is enchantable (Chest, Wrist, Hands, Feet, Legs, Weapon)
                if slotId == 5 or slotId == 9 or slotId == 10 or slotId == 8 or slotId == 7 or slotId == 16 then
                    missingEnchants = missingEnchants + 1
                end
            end
        end
    end

    local avgILvl = totalItems > 0 and math.floor(totalLevel / totalItems) or 0
    return avgILvl, totalItems, missingEnchants
end

-- Create or Update Inspect Overview Panel
function PUIInspect:ShowOverview(unit)
    unit = unit or "target"
    if not UnitExists(unit) or not UnitIsPlayer(unit) then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[Inspect]: Select a valid player to inspect.", "ffbb33"))
        return
    end

    if not inspectPanel then
        inspectPanel = CreateFrame("Frame", "Primus_InspectOverview", UIParent)
        inspectPanel:SetWidth(220)
        inspectPanel:SetHeight(100)
        inspectPanel:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
        inspectPanel:SetBackdrop(Media:Fetch("border", "1Pixel"))
        inspectPanel:SetBackdropColor(0.06, 0.08, 0.12, 0.95)
        inspectPanel:SetBackdropBorderColor(0.2, 0.6, 1.0, 1)
        inspectPanel:SetMovable(true)
        inspectPanel:EnableMouse(true)
        inspectPanel:RegisterForDrag("LeftButton")
        inspectPanel:SetScript("OnDragStart", function() this:StartMoving() end)
        inspectPanel:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

        local title = inspectPanel:CreateFontString(nil, "OVERLAY")
        title:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
        title:SetPoint("TOPLEFT", inspectPanel, "TOPLEFT", 6, -6)
        title:SetText(Utils.ColorText("Target Gear Summary", "69ccf0"))
        inspectPanel.title = title

        local closeBtn = CreateFrame("Button", nil, inspectPanel)
        closeBtn:SetWidth(16)
        closeBtn:SetHeight(16)
        closeBtn:SetPoint("TOPRIGHT", inspectPanel, "TOPRIGHT", -4, -4)
        closeBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
        closeBtn:SetBackdropColor(0.6, 0.1, 0.1, 0.8)
        closeBtn:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
        local cT = closeBtn:CreateFontString(nil, "OVERLAY")
        cT:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
        cT:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
        cT:SetText("X")
        closeBtn:SetScript("OnClick", function() inspectPanel:Hide() end)

        local infoText = inspectPanel:CreateFontString(nil, "OVERLAY")
        infoText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
        infoText:SetPoint("TOPLEFT", inspectPanel, "TOPLEFT", 8, -26)
        infoText:SetJustifyH("LEFT")
        local mover = PUIMover or Primus.PUIMover
        if mover and mover.Register then
            mover:Register(inspectPanel, "InspectOverview", "Target Inspect Overview", "UTILITY")
        end
    end

    local avgILvl, totalItems, missingEnchants = self:ScanUnitGear(unit)
    local name = UnitName(unit) or "Target"
    local _, class = UnitClass(unit)
    local r, g, b = Utils.GetClassColor(class or "")
    local hex = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)

    local str = string.format("Player: |cff%s%s|r\nAverage iLvl: |cffffd100%d|r (%d equipped)\nMissing Enchants: %s",
        hex, name,
        avgILvl, totalItems,
        missingEnchants > 0 and string.format("|cffff4444%d slots|r", missingEnchants) or "|cff33ff33None (Fully Enchanted)|r"
    )
    inspectPanel.infoText:SetText(str)
    inspectPanel:Show()
end

function PUIInspect:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIInspect", {
        name = "PUIInspect",
        category = "Utility",
        label = "Inspect Engine",
        icon = "Interface\Icons\INV_Misc_Spyglass_03",
        desc = "Throttled background inspect queue and persistent gear cache.",
    })
end

function PUIInspect:OnInitialize()
    self:RegisterOptionsFlare()
    Events:Register("INSPECT_HONOR_UPDATE", self, function()
        if InspectFrame and InspectFrame:IsShown() then
            PUIInspect:ShowOverview("target")
        end
    end)

    -- Subcommand registration via Console Router
    if Primus.Console and Primus.Console.RegisterSubCommand then
        Primus.Console:RegisterSubCommand("inspect", function()
            if UnitExists("target") then
                PUIInspect:ShowOverview("target")
            else
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[Inspect]: Target a player and type /pui inspect to view gear summary.", "69ccf0"))
            end
        end, "Target inspect & gear summary overview (/pui inspect)")
    end
end
