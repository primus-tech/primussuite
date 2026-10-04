--[[
    PrimusUI Module: Vendor (Auto-Repair & Non-Wearable Grey Item Junk Seller)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Features:
    1. Sells non-wearable grey junk items upon merchant interaction or manual trigger.
       - Strictly preserves wearable equipment (weapons, armor, cloth/leather/mail/plate, trinkets, rings).
    2. Interactive "Sell Greys" button and "Auto-Sell Greys" checkbox embedded directly into MerchantFrame.
    3. Automatic equipment repairs when interacting with repair-capable merchants.
    4. Auto-sell defaults to DEACTIVATED out-of-the-box.
    5. 100% programmatic dynamic item resolution (zero hardcoded name lookups).
    6. Built-in diagnostic inspection via '/pui vendor debug'.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIVendor = Primus.PUIVendor or {}
Primus.PUIVendor = PUIVendor
_G.PUIVendor = PUIVendor
Primus:RegisterModule("PUIVendor", PUIVendor, "Player")

local DB      = Primus.DB
local Events  = Primus.Events
local Utils   = Primus.Utils
local Media   = Primus.Media
local Console = Primus.Console

local vendorDB = DB:RegisterNamespace("PUIVendor", {
    autoSellGrey = false,
    autoRepair = true,
})

local merchantSellBtn = nil
local merchantAutoCheck = nil

-- Dedicated Hidden Tooltip for definitive 1.12 item scanning
local scanTooltip = CreateFrame("GameTooltip", "Primus_VendorScanTip", UIParent, "GameTooltipTemplate")
scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")

-- Extract all programmatic info about an item in a container slot
local function GetSlotItemData(bag, slot)
    local link = GetContainerItemLink(bag, slot)
    if not link then return nil end

    local texture, itemCount, locked, containerQuality = GetContainerItemInfo(bag, slot)
    if not texture then return nil end

    -- Extract raw clean item string and numeric ID
    local cleanItem = nil
    local itemID = nil
    local _, _, fullItem = string.find(link, "(item:%d+:%d+:%d+:%d+)")
    if fullItem then
        cleanItem = fullItem
    end
    local _, _, idStr = string.find(link, "item:(%d+)")
    if idStr then
        itemID = tonumber(idStr)
        if not cleanItem then
            cleanItem = "item:" .. idStr .. ":0:0:0"
        end
    end

    -- Extract item name from brackets if available
    local linkItemName = nil
    local _, _, nameMatch = string.find(link, "%[(.+)%]")
    if nameMatch then
        linkItemName = nameMatch
    end

    -- Query GetItemInfo with multiple fallbacks
    -- Vanilla 1.12.1 signature: itemName, itemLink, itemRarity, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture (9 returns!)
    local name, itemLink, quality, minLevel, itemType, itemSubType, maxStack, equipLoc, itemTex = nil
    if cleanItem then
        name, itemLink, quality, minLevel, itemType, itemSubType, maxStack, equipLoc, itemTex = GetItemInfo(cleanItem)
    end
    if not name and itemID then
        name, itemLink, quality, minLevel, itemType, itemSubType, maxStack, equipLoc, itemTex = GetItemInfo(itemID)
    end
    if not name and linkItemName then
        name, itemLink, quality, minLevel, itemType, itemSubType, maxStack, equipLoc, itemTex = GetItemInfo(linkItemName)
    end
    if not name and link then
        name, itemLink, quality, minLevel, itemType, itemSubType, maxStack, equipLoc, itemTex = GetItemInfo(link)
    end

    -- Quality Detection
    local isGrey = false
    local lowerLink = string.lower(link)
    if string.find(lowerLink, "9d9d9d") or string.find(lowerLink, "cff9d9d9d") then
        isGrey = true
    end
    if quality == 0 then
        isGrey = true
    elseif quality and quality > 0 then
        isGrey = false
    end
    if containerQuality == 0 then
        isGrey = true
    elseif containerQuality and containerQuality > 0 then
        isGrey = false
    end

    -- Check tooltip line 1 color if quality still ambiguous
    if not isGrey and not (quality and quality > 0) then
        scanTooltip:ClearLines()
        scanTooltip:SetBagItem(bag, slot)
        local line1 = _G["Primus_VendorScanTipTextLeft1"]
        if line1 and line1:IsShown() then
            local r, g, b = line1:GetTextColor()
            if r and g and b and r < 0.72 and g < 0.72 and b < 0.72 and math.abs(r - g) < 0.08 and math.abs(g - b) < 0.08 then
                isGrey = true
            end
        end
    end

    -- Wearability Check
    local isWearable = false
    if equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP" then
        isWearable = true
    end

    -- Also check tooltip lines for armor/weapon slots
    if not isWearable then
        scanTooltip:ClearLines()
        scanTooltip:SetBagItem(bag, slot)
        local numLines = scanTooltip:NumLines() or 0
        for l = 2, numLines do
            local leftObj = _G["Primus_VendorScanTipTextLeft" .. l]
            local rightObj = _G["Primus_VendorScanTipTextRight" .. l]
            local leftText = leftObj and leftObj:GetText() or ""
            local rightText = rightObj and rightObj:GetText() or ""

            if leftText == "Head" or leftText == "Neck" or leftText == "Shoulder" or leftText == "Back" 
               or leftText == "Chest" or leftText == "Shirt" or leftText == "Tabard" or leftText == "Wrist" 
               or leftText == "Hands" or leftText == "Waist" or leftText == "Legs" or leftText == "Feet" 
               or leftText == "Finger" or leftText == "Trinket" or leftText == "Held In Off-hand"
               or string.find(leftText, "Two%-Hand") or string.find(leftText, "One%-Hand") 
               or string.find(leftText, "Main Hand") or string.find(leftText, "Off Hand")
               or string.find(leftText, "Ranged") or string.find(leftText, "Gun") or string.find(leftText, "Bow")
               or string.find(leftText, "Crossbow") or string.find(leftText, "Wand") or string.find(leftText, "Thrown")
               or rightText == "Shield" or rightText == "Cloth" or rightText == "Leather" or rightText == "Mail" or rightText == "Plate" then
                isWearable = true
                break
            end
        end
    end

    return {
        bag = bag,
        slot = slot,
        name = name or linkItemName or "Unknown",
        link = link,
        locked = locked,
        quality = quality,
        containerQuality = containerQuality,
        isGrey = isGrey,
        isWearable = isWearable,
        equipLoc = equipLoc or "",
        itemType = itemType or "",
        shouldSell = (isGrey and not isWearable and not locked),
    }
end

-- Sell all non-wearable grey quality items in bags
function PUIVendor:SellGreyJunk(isManual)
    local itemsSold = 0

    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag) or 0
        if numSlots > 0 then
            for slot = 1, numSlots do
                local data = GetSlotItemData(bag, slot)
                if data and data.shouldSell then
                    UseContainerItem(bag, slot)
                    itemsSold = itemsSold + 1
                end
            end
        end
    end

    if itemsSold > 0 then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[Vendor]: Sold %d non-wearable grey junk item(s).", itemsSold), "69ccf0"))
    elseif isManual then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[Vendor]: No non-wearable grey junk found in bags.", "ffbb33"))
    end
end

-- Diagnostic scan of bags
function PUIVendor:DebugScan()
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("=== PrimusUI Vendor Inventory Diagnostic ===", "69ccf0"))
    local totalFound = 0
    local totalGrey = 0

    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag) or 0
        if numSlots > 0 then
            for slot = 1, numSlots do
                local data = GetSlotItemData(bag, slot)
                if data then
                    totalFound = totalFound + 1
                    if data.isGrey then
                        totalGrey = totalGrey + 1
                        DEFAULT_CHAT_FRAME:AddMessage(string.format(
                            "Bag %d Slot %d: %s | Grey: %s | Wearable: %s | EquipLoc: '%s' | Action: %s",
                            bag, slot, data.link,
                            tostring(data.isGrey),
                            tostring(data.isWearable),
                            tostring(data.equipLoc),
                            data.shouldSell and Utils.ColorText("SELL", "00ff00") or Utils.ColorText("KEEP", "ff4444")
                        ))
                    end
                end
            end
        end
    end

    DEFAULT_CHAT_FRAME:AddMessage(string.format("[Vendor Diagnostic]: Scanned %d items total (%d detected as grey).", totalFound, totalGrey))
end

-- Repair all gear if merchant can repair
function PUIVendor:AutoRepair()
    if CanMerchantRepair() then
        local cost, possible = GetRepairAllCost()
        if possible and cost > 0 and GetMoney() >= cost then
            RepairAllItems()
            local gold = math.floor(cost / 10000)
            local silver = math.floor(Utils.Mod(cost, 10000) / 100)
            local copper = Utils.Mod(cost, 100)
            DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[Vendor]: Auto-repaired all items for %dg %ds %dc", gold, silver, copper), "ffbb33"))
        end
    end
end

-- Build and attach merchant UI elements
local function BuildMerchantControls()
    if not MerchantFrame or merchantSellBtn then return end

    -- 1. Manual "Sell Greys" Button
    local btn = CreateFrame("Button", "Primus_MerchantSellGreysBtn", MerchantFrame)
    btn:SetWidth(80)
    btn:SetHeight(20)
    btn:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", 18, 92)
    btn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    btn:SetBackdropColor(0.12, 0.14, 0.18, 0.95)
    btn:SetBackdropBorderColor(0.3, 0.6, 0.9, 1.0)

    local btnText = btn:CreateFontString(nil, "OVERLAY")
    btnText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    btnText:SetPoint("CENTER", 0, 0)
    btnText:SetText(Utils.ColorText("Sell Greys", "69ccf0"))
    btn.text = btnText

    btn:SetScript("OnEnter", function()
        btn:SetBackdropColor(0.2, 0.3, 0.45, 1.0)
        btn:SetBackdropBorderColor(0.5, 0.85, 1.0, 1.0)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText("Sell Non-Wearable Greys")
        GameTooltip:AddLine("Click to sell all poor quality (grey) junk items in your bags.", 0.8, 0.8, 0.8, 1)
        GameTooltip:AddLine("Wearable weapons and armor are safely preserved.", 0.2, 1.0, 0.2, 1)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        btn:SetBackdropColor(0.12, 0.14, 0.18, 0.95)
        btn:SetBackdropBorderColor(0.3, 0.6, 0.9, 1.0)
        GameTooltip:Hide()
    end)

    btn:SetScript("OnClick", function()
        PUIVendor:SellGreyJunk(true)
    end)

    merchantSellBtn = btn

    -- 2. "Auto-Sell Greys" CheckBox
    local cb = CreateFrame("CheckButton", "Primus_MerchantAutoSellCheck", MerchantFrame, "UICheckButtonTemplate")
    cb:SetWidth(18)
    cb:SetHeight(18)
    cb:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", 18, 70)

    local cbText = cb:CreateFontString(nil, "OVERLAY")
    cbText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    cbText:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cbText:SetText("Auto-Sell")
    cbText:SetTextColor(0.85, 0.85, 0.9)
    cb.text = cbText

    local function SyncCheckState()
        local isEnabled = vendorDB:Get("autoSellGrey", false)
        cb:SetChecked(isEnabled and 1 or 0)
    end

    cb:SetScript("OnClick", function()
        local isChecked = (cb:GetChecked() == 1 or cb:GetChecked() == true) and true or false
        vendorDB:Set("autoSellGrey", isChecked)
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[Vendor]: Auto-Sell Greys %s.", isChecked and "ENABLED" or "DISABLED"), "69ccf0"))
    end)

    cb:SetScript("OnEnter", function()
        cbText:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(cb, "ANCHOR_RIGHT")
        GameTooltip:SetText("Auto-Sell Greys")
        GameTooltip:AddLine("Automatically sell non-wearable grey junk whenever you visit a merchant.", 0.8, 0.8, 0.8, 1)
        GameTooltip:Show()
    end)

    cb:SetScript("OnLeave", function()
        cbText:SetTextColor(0.85, 0.85, 0.9)
        GameTooltip:Hide()
    end)

    merchantAutoCheck = cb
    SyncCheckState()
end

-- =========================================================================
-- OPTIONS FLARE REGISTRATION
-- =========================================================================

function PUIVendor:RegisterOptionsFlare()
    local Options = Primus.Options
    if not Options or not Options.RegisterModuleOptions then return end

    Options:RegisterModuleOptions("PUIVendor", "Player", {
        title = "PUIVendor: Merchant Automation",
        description = "Automated equipment repairs and safe non-wearable grey junk selling.",
        fields = {
            {
                key = "autoSellGrey",
                label = "Auto-Sell Grey Junk (Preserves Wearables)",
                type = "checkbox",
                default = false,
                get = function() return vendorDB:Get("autoSellGrey", false) end,
                set = function(val)
                    vendorDB:Set("autoSellGrey", val)
                    if merchantAutoCheck then merchantAutoCheck:SetChecked(val and 1 or 0) end
                end,
            },
            {
                key = "autoRepair",
                label = "Auto-Repair Equipment at Merchants",
                type = "checkbox",
                default = true,
                get = function() return vendorDB:Get("autoRepair", true) end,
                set = function(val) vendorDB:Set("autoRepair", val) end,
            },
        },
    })
end

-- =========================================================================
-- LIFECYCLE & EVENT DISPATCH
-- =========================================================================

function PUIVendor:OnInitialize()
    self:RegisterOptionsFlare()
    BuildMerchantControls()

    -- Register console subcommand
    if Console and Console.RegisterSubCommand then
        Console:RegisterSubCommand("vendor", function(arg)
            if arg == "sell" then
                PUIVendor:SellGreyJunk(true)
            elseif arg == "repair" then
                PUIVendor:AutoRepair()
            elseif arg == "debug" or arg == "scan" or arg == "test" then
                PUIVendor:DebugScan()
            else
                local cur = vendorDB:Get("autoSellGrey", false)
                vendorDB:Set("autoSellGrey", not cur)
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[Vendor]: Auto-Sell Greys %s.", not cur and "ENABLED" or "DISABLED"), "69ccf0"))
            end
        end, "Vendor settings, sell, repair, & diagnostics (/pui vendor [sell|repair|debug])")
    end
end

function PUIVendor:OnEnable()
    Events:Register("MERCHANT_SHOW", "Vendor", function()
        BuildMerchantControls()
        if merchantAutoCheck then
            local isEnabled = vendorDB:Get("autoSellGrey", false)
            merchantAutoCheck:SetChecked(isEnabled and 1 or 0)
        end

        if vendorDB:Get("autoSellGrey", false) then
            PUIVendor:SellGreyJunk(false)
        end
        if vendorDB:Get("autoRepair", true) then
            PUIVendor:AutoRepair()
        end
    end)
end

function PUIVendor:OnDisable()
    Events:UnregisterOwner("PUIVendor")
    if merchantSellBtn then merchantSellBtn:Hide() end
    if merchantAutoCheck then merchantAutoCheck:Hide() end
end
