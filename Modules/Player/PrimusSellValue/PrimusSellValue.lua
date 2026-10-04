--[[
    PrimusUI Module: PUISellValue (Hybrid Item Pricing & Vendor Sell Value Engine)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Features:
    1. Hybrid Resolution Hierarchy:
       - Tier 1: Built-in Static DB (PUISellValue.StaticDB) seeded from pfUI/pfQuest item data.
       - Tier 2: Autonomous Live Realm-Learning Cache (PrimusGlobalDB.PUISellValue.realms[GetRealmName()].prices[itemID]).
    2. Universal Tooltip Injection:
       - Hooks SetBagItem, SetInventoryItem, SetHyperlink, SetAction, SetCraftItem,
         SetTradeSkillItem, SetLootItem, SetLootRollItem, SetQuestItem, SetQuestLogItem,
         SetInboxItem, SetSendMailItem, SetAuctionItem, SetAuctionSellItem, SetTradePlayerItem,
         SetTradeTargetItem, and ItemRefTooltip.
       - Formats single prices: "Sell: 1g 25s 40c"
       - Formats stack prices (>1): "Sell (x5): 7g 27s 00c (1g 25s 40c ea)"
       - Strictly suppresses injection when MerchantFrame is open to prevent duplicate rows.
    3. Autonomous Live Auto-Learning:
       - Silently captures native vendor prices during MERCHANT_SHOW, MERCHANT_UPDATE,
         and interactive container scans via a dedicated hidden tooltip engine.
    4. Options Flare & Console Router:
       - Master toggles in GUI and '/pui sell' diagnostic CLI.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUISellValue = Primus.PUISellValue or {}
Primus.PUISellValue = PUISellValue
_G.PUISellValue = PUISellValue
Primus:RegisterModule("PUISellValue", PUISellValue, "Player")

local DB      = Primus.DB
local Events  = Primus.Events
local Utils   = Primus.Utils
local Media   = Primus.Media
local Debug   = Primus.Debug
local Console = Primus.Console

local sellDB = DB:RegisterNamespace("PUISellValue", {
    enabled          = true,
    showSellPrice    = true,
    showBuyPrice     = true,
    showAuctionPrice = true,
    showSinglePrice  = true,
    showStackPrice   = true,
    showNoSellValue  = false,
    realms           = {},
})

-- Ensure global storage alias for external scripts / macros
if _G.PrimusGlobalDB then
    _G.PrimusGlobalDB.PUISellValue = sellDB.data
end

-- Dedicated Hidden Tooltip for Definitive 1.12 Vendor Money Capture
local scanTip = CreateFrame("GameTooltip", "Primus_SellValueScanTip", UIParent, "GameTooltipTemplate")
scanTip:SetOwner(UIParent, "ANCHOR_NONE")

local lastScannedMoney = 0
scanTip:SetScript("OnTooltipAddMoney", function()
    lastScannedMoney = arg1 or 0
end)
scanTip:SetScript("OnTooltipCleared", function()
    lastScannedMoney = 0
end)

-- Clean Item Name Extractor
local function CleanItemName(linkOrName)
    if not linkOrName then return nil end
    local _, _, name = string.find(linkOrName, "%[(.+)%]")
    return name or linkOrName
end

-- =========================================================================
-- REALM CACHE MANAGEMENT
-- =========================================================================

function PUISellValue:GetRealmData(realm)
    realm = realm or GetRealmName() or "Default"
    if not sellDB.data.realms then
        sellDB.data.realms = {}
    end
    if not sellDB.data.realms[realm] then
        sellDB.data.realms[realm] = {
            prices = {},
            buyPrices = {},
            learnedCount = 0,
            learnedBuyCount = 0,
        }
    end
    if not sellDB.data.realms[realm].buyPrices then
        sellDB.data.realms[realm].buyPrices = {}
    end
    -- Keep global alias synchronized
    if _G.PrimusGlobalDB and not _G.PrimusGlobalDB.PUISellValue then
        _G.PrimusGlobalDB.PUISellValue = sellDB.data
    end
    return sellDB.data.realms[realm]
end

function PUISellValue:LearnPrice(itemID, price, realm)
    if not itemID or not price or price < 0 then return false end
    itemID = tonumber(itemID)
    price = tonumber(price)
    if not itemID or not price then return false end

    local rData = self:GetRealmData(realm)
    if not rData.prices then rData.prices = {} end

    if rData.prices[itemID] ~= price then
        local isNew = (rData.prices[itemID] == nil)
        rData.prices[itemID] = price
        if isNew then
            rData.learnedCount = (rData.learnedCount or 0) + 1
        end
        return true
    end
    return false
end

function PUISellValue:LearnBuyPrice(itemID, price, realm)
    if not itemID or not price or price <= 0 then return false end
    itemID = tonumber(itemID)
    price = tonumber(price)
    if not itemID or not price then return false end

    local rData = self:GetRealmData(realm)
    if not rData.buyPrices then rData.buyPrices = {} end

    if rData.buyPrices[itemID] ~= price then
        local isNew = (rData.buyPrices[itemID] == nil)
        rData.buyPrices[itemID] = price
        if isNew then
            rData.learnedBuyCount = (rData.learnedBuyCount or 0) + 1
        end
        return true
    end
    return false
end

-- =========================================================================
-- HYBRID PRICE RESOLUTION ENGINE (SELL, BUY, AUCTION & VANILLAITEMPRICES)
-- =========================================================================

function PUISellValue:ExtractItemID(itemLinkOrString)
    if not itemLinkOrString then return nil end
    if type(itemLinkOrString) == "number" then
        return itemLinkOrString
    end
    local _, _, idStr = string.find(itemLinkOrString, "item:(%d+)")
    if idStr then
        return tonumber(idStr)
    end
    local num = tonumber(itemLinkOrString)
    if num then return num end

    -- Fallback: If item name passed, resolve via GetItemInfo
    if type(itemLinkOrString) == "string" and itemLinkOrString ~= "" then
        local cleanName = CleanItemName(itemLinkOrString)
        if cleanName and cleanName ~= "" then
            local _, link = GetItemInfo(cleanName)
            if link then
                local _, _, idFromLink = string.find(link, "item:(%d+)")
                if idFromLink then return tonumber(idFromLink) end
            end
        end
    end
    return nil
end

-- Get Vendor Sell Price (How much vendor gives you)
function PUISellValue:GetSellPrice(item)
    if not item then return nil end
    local baseDB = Primus.PUIBasePriceDB or _G.PUIBasePriceDB
    local itemID = self:ExtractItemID(item)
    if not itemID and baseDB and baseDB.GetItemID then
        itemID = baseDB:GetItemID(item)
    end
    local itemName = CleanItemName(item)

    -- 1. Tier 2: Live Realm Auto-Learning Cache
    local rData = self:GetRealmData()
    if itemID and rData and rData.prices and rData.prices[itemID] ~= nil then
        return rData.prices[itemID], "REALM_CACHE"
    end

    -- 2. Tier 1: PUIBasePriceDB Core Database & Built-in Static DB
    if baseDB and baseDB.GetSellPrice then
        local bp = baseDB:GetSellPrice(itemID or item)
        if bp ~= nil then return bp, "PUI_BASE_PRICE_DB" end
    end
    if itemID and PUISellValue.StaticDB and PUISellValue.StaticDB[itemID] ~= nil then
        return PUISellValue.StaticDB[itemID], "STATIC_DB"
    end

    -- 3. VanillaItemPrices Integration (_G.VanillaItemPrices / VanillaItemPrices bridge)
    local vip = _G.VanillaItemPrices or VanillaItemPrices
    if vip and itemID and vip[itemID] ~= nil then
        local val = vip[itemID]
        if type(val) == "number" then
            return val, "VANILLA_ITEM_PRICES"
        elseif type(val) == "table" then
            local sPrice = val.s or val.sell or val.sellPrice or val.price or val[1]
            if sPrice then return sPrice, "VANILLA_ITEM_PRICES" end
        end
    end

    -- 4. External Addon Fallbacks (SellValue, ItemPrices, Informant)
    if itemID then
        local sv = _G.SellValueDB or _G.ItemPrices or _G.InformantDB
        if sv and sv[itemID] ~= nil then
            local val = sv[itemID]
            if type(val) == "number" then
                return val, "EXTERNAL_DB"
            elseif type(val) == "table" then
                local sPrice = val.s or val.sell or val.price or val[1]
                if sPrice then return sPrice, "EXTERNAL_DB" end
            end
        end
    end

    -- 5. Query PUIQuest Canonical Database
    if itemID and Primus.PUIQuest and Primus.PUIQuest.Database then
        local puiPrice = Primus.PUIQuest.Database:GetItemVendorPrice(itemID)
        if puiPrice and puiPrice > 0 then
            return puiPrice, "PUIQUEST_DB"
        end
    end

    return nil, nil
end

-- Get Vendor Buy Price (How much vendor charges you)
function PUISellValue:GetBuyPrice(item)
    if not item then return nil end
    local baseDB = Primus.PUIBasePriceDB or _G.PUIBasePriceDB
    local itemID = self:ExtractItemID(item)
    if not itemID and baseDB and baseDB.GetItemID then
        itemID = baseDB:GetItemID(item)
    end
    local itemName = CleanItemName(item)

    -- 1. Tier 2: Live Realm Auto-Learned Buy Cache (from merchant visits)
    local rData = self:GetRealmData()
    if itemID and rData and rData.buyPrices and rData.buyPrices[itemID] ~= nil then
        return rData.buyPrices[itemID], "REALM_BUY_CACHE"
    end

    -- 2. Tier 1: PUIBasePriceDB Core Database & Built-in BuyStaticDB
    if baseDB and baseDB.GetBuyPrice then
        local bp = baseDB:GetBuyPrice(itemID or item)
        if bp ~= nil then return bp, "PUI_BASE_PRICE_DB" end
    end
    if itemID and PUISellValue.BuyStaticDB and PUISellValue.BuyStaticDB[itemID] ~= nil then
        return PUISellValue.BuyStaticDB[itemID], "STATIC_BUY_DB"
    end

    -- 3. VanillaItemPrices Integration
    local vip = _G.VanillaItemPrices or VanillaItemPrices
    if vip and itemID and type(vip[itemID]) == "table" then
        local bPrice = vip[itemID].b or vip[itemID].buy or vip[itemID].buyPrice or vip[itemID][2]
        if bPrice and bPrice > 0 then
            return bPrice, "VANILLA_ITEM_PRICES"
        end
    end

    return nil, nil
end

-- Get Auction Market Price (Partitioned by Realm)
function PUISellValue:GetAuctionPrice(item, realm)
    if not item then return nil end
    local itemName = CleanItemName(item)
    if not itemName or itemName == "" then return nil end

    local merchant = Primus.PUIMerchant or _G.PUIMerchant
    if merchant and merchant.GetItemPriceInfo then
        return merchant:GetItemPriceInfo(itemName, realm)
    end
    return nil
end

-- =========================================================================
-- AUTONOMOUS LIVE MERCHANT SCANNER (SELL & BUY PRICES)
-- =========================================================================

function PUISellValue:ScanMerchantGoods()
    if not MerchantFrame or not MerchantFrame:IsShown() then return 0, 0 end

    local newSell = 0
    local newBuy = 0

    -- 1. Scan Merchant Offerings (Buy Prices & Inherent Sell Prices)
    local numMerchantItems = GetMerchantNumItems() or 0
    for i = 1, numMerchantItems do
        local link = GetMerchantItemLink(i)
        local name, texture, price, quantity, numAvailable, isUsable = GetMerchantItemInfo(i)
        if link and price and price > 0 then
            local itemID = self:ExtractItemID(link)
            if itemID then
                local unitBuyPrice = math.floor(price / math.max(1, quantity or 1))
                if unitBuyPrice > 0 and self:LearnBuyPrice(itemID, unitBuyPrice) then
                    newBuy = newBuy + 1
                end

                -- Also scan item tooltip to capture sell price
                lastScannedMoney = 0
                scanTip:ClearLines()
                scanTip:SetMerchantItem(i)
                if lastScannedMoney > 0 then
                    local unitSellPrice = math.floor(lastScannedMoney / math.max(1, quantity or 1))
                    if unitSellPrice > 0 and self:LearnPrice(itemID, unitSellPrice) then
                        newSell = newSell + 1
                    end
                end
            end
        end
    end

    -- 2. Scan Player Inventory at Merchant
    local bagSell = self:ScanBagsAtMerchant()
    newSell = newSell + bagSell

    return newSell, newBuy
end

function PUISellValue:ScanBagsAtMerchant()
    if not MerchantFrame or not MerchantFrame:IsShown() then return 0 end

    local newLearned = 0
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag) or 0
        if numSlots > 0 then
            for slot = 1, numSlots do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local itemID = self:ExtractItemID(link)
                    if itemID then
                        local _, count = GetContainerItemInfo(bag, slot)
                        count = (count and count > 0) and count or 1

                        lastScannedMoney = 0
                        scanTip:ClearLines()
                        scanTip:SetBagItem(bag, slot)

                        if lastScannedMoney > 0 then
                            local unitPrice = math.floor(lastScannedMoney / count)
                            if unitPrice > 0 then
                                if self:LearnPrice(itemID, unitPrice) then
                                    newLearned = newLearned + 1
                                end
                            end
                        elseif lastScannedMoney == 0 then
                            -- Item has zero vendor sell price (unsellable quest item / soulbound currency)
                            if self:LearnPrice(itemID, 0) then
                                newLearned = newLearned + 1
                            end
                        end
                    end
                end
            end
        end
    end

    return newLearned
end

-- =========================================================================
-- UNIVERSAL TOOLTIP INJECTION ENGINE (SELL, BUY & REALM AUCTION)
-- =========================================================================

function PUISellValue:InjectTooltipPrice(tooltip, itemID, count)
    if not tooltip or not sellDB:Get("enabled", true) then return end
    if tooltip._primusSellValueInjected then return end

    count = (count and count > 0) and count or 1
    local realm = GetRealmName() or "Default"

    local itemName = nil
    local titleObj = _G[tooltip:GetName() .. "TextLeft1"]
    if titleObj and titleObj:GetText() then
        itemName = CleanItemName(titleObj:GetText())
    end

    -- If itemID is not numeric, resolve via PUIBasePriceDB and GetItemInfo
    local baseDB = Primus.PUIBasePriceDB or _G.PUIBasePriceDB
    if not itemID or type(itemID) ~= "number" then
        if baseDB and baseDB.GetItemID then
            itemID = baseDB:GetItemID(itemID or itemName)
        end
        if not itemID and itemName then
            local _, link = GetItemInfo(itemName)
            if link then itemID = self:ExtractItemID(link) end
        end
    end

    local sellPrice, sellSrc = self:GetSellPrice(itemID or itemName)
    local buyPrice, buySrc = self:GetBuyPrice(itemID or itemName)
    local minBuyout, avgBuyout, seenCount = self:GetAuctionPrice(itemName or itemID, realm)

    local showSell = sellDB:Get("showSellPrice", true) and (sellPrice ~= nil)
    local showBuy  = sellDB:Get("showBuyPrice", true) and (buyPrice ~= nil and buyPrice > 0)
    local showAH   = sellDB:Get("showAuctionPrice", true) and (avgBuyout ~= nil and avgBuyout > 0)

    -- If no prices are known or enabled, exit cleanly
    if not showSell and not showBuy and not showAH then return end

    -- Only suppress our custom Vendor Sell row if Blizzard's native money frame is actively shown (bag items at merchant)
    local hasBlizzNativeSell = (tooltip == GameTooltip and GameTooltipMoneyFrame1 and GameTooltipMoneyFrame1:IsShown())

    tooltip._primusSellValueInjected = true

    -- 1. Vendor Sell Price Row
    if showSell and not hasBlizzNativeSell then
        if sellPrice > 0 then
            if count > 1 and sellDB:Get("showStackPrice", true) then
                local totalStr = Utils.FormatMoney(sellPrice * count)
                local eachStr  = Utils.FormatMoney(sellPrice)
                tooltip:AddDoubleLine(string.format("|cffffd100Vendor Sell (x%d):|r", count), string.format("%s (%s ea)", totalStr, eachStr))
            else
                tooltip:AddDoubleLine("|cffffd100Vendor Sell:|r", Utils.FormatMoney(sellPrice))
            end
        elseif sellPrice == 0 and sellDB:Get("showNoSellValue", false) then
            tooltip:AddDoubleLine("|cffffd100Vendor Sell:|r", "|cff888888No sell value|r")
        end
    end

    -- 2. Vendor Buy Price Row (When known from merchant stock)
    if showBuy then
        if count > 1 and sellDB:Get("showStackPrice", true) then
            local totalStr = Utils.FormatMoney(buyPrice * count)
            local eachStr  = Utils.FormatMoney(buyPrice)
            tooltip:AddDoubleLine(string.format("|cff69ccf0Vendor Buy (x%d):|r", count), string.format("%s (%s ea)", totalStr, eachStr))
        else
            tooltip:AddDoubleLine("|cff69ccf0Vendor Buy:|r", Utils.FormatMoney(buyPrice))
        end
    end

    -- 3. Auction House Market Valuation Row (Partitioned by Realm)
    if showAH then
        if count > 1 and sellDB:Get("showStackPrice", true) then
            local totalStr = Utils.FormatMoney(avgBuyout * count)
            local eachStr  = Utils.FormatMoney(avgBuyout)
            tooltip:AddDoubleLine(string.format("|cff33ccffAH Market (x%d):|r", count), string.format("%s (%s ea)", totalStr, eachStr))
        else
            tooltip:AddDoubleLine(string.format("|cff33ccffAH Market (%s):|r", realm), Utils.FormatMoney(avgBuyout))
        end

        if minBuyout and minBuyout > 0 then
            local seenStr = (seenCount and seenCount > 0) and string.format(" |cff888888(Seen: %dx)|r", seenCount) or ""
            tooltip:AddDoubleLine("|cffaaaaaaAH Min Buyout:|r", Utils.FormatMoney(minBuyout) .. seenStr)
        end
    end

    tooltip:Show()
end

function PUISellValue:OnTooltipProcess(tooltip, itemData)
    if not tooltip or not itemData or not sellDB:Get("enabled", true) then return end
    local itemID = itemData.itemID or self:ExtractItemID(itemData.link)
    local count = itemData.count or 1
    self:InjectTooltipPrice(tooltip, itemID or itemData.link, count)
end

-- =========================================================================
-- OPTIONS FLARE REGISTRATION
-- =========================================================================

function PUISellValue:RegisterOptionsFlare()
    local Options = Primus.Options
    if not Options or not Options.RegisterModuleOptions then return end

    Options:RegisterModuleOptions("PUISellValue", "Player", {
        title = "PUISellValue: Item Pricing & Valuation",
        description = "Hybrid vendor sell/buy price engine with VanillaItemPrices bridge, realm-partitioned auction market pricing, and universal tooltip injection.",
        icon = "Interface\\Icons\\INV_Misc_Coin_02",
        fields = {
            {
                key = "enabled",
                label = "Enable Tooltip Price Injections",
                type = "checkbox",
                default = true,
                get = function() return sellDB:Get("enabled", true) end,
                set = function(val)
                    sellDB:Set("enabled", val)
                    if val then PUISellValue:OnEnable() else PUISellValue:OnDisable() end
                end,
            },
            {
                key = "showSellPrice",
                label = "Display Vendor Sell Price",
                type = "checkbox",
                default = true,
                get = function() return sellDB:Get("showSellPrice", true) end,
                set = function(val) sellDB:Set("showSellPrice", val) end,
            },
            {
                key = "showBuyPrice",
                label = "Display Vendor Buy Price (When Known)",
                type = "checkbox",
                default = true,
                get = function() return sellDB:Get("showBuyPrice", true) end,
                set = function(val) sellDB:Set("showBuyPrice", val) end,
            },
            {
                key = "showAuctionPrice",
                label = "Display AH Market Valuation (By Realm)",
                type = "checkbox",
                default = true,
                get = function() return sellDB:Get("showAuctionPrice", true) end,
                set = function(val) sellDB:Set("showAuctionPrice", val) end,
            },
            {
                key = "showSinglePrice",
                label = "Display Single Item Unit Value",
                type = "checkbox",
                default = true,
                get = function() return sellDB:Get("showSinglePrice", true) end,
                set = function(val) sellDB:Set("showSinglePrice", val) end,
            },
            {
                key = "showStackPrice",
                label = "Display Total Stack Value For Multiples",
                type = "checkbox",
                default = true,
                get = function() return sellDB:Get("showStackPrice", true) end,
                set = function(val) sellDB:Set("showStackPrice", val) end,
            },
            {
                key = "showNoSellValue",
                label = "Show 'No Sell Value' Notice on Unsellable Items",
                type = "checkbox",
                default = false,
                get = function() return sellDB:Get("showNoSellValue", false) end,
                set = function(val) sellDB:Set("showNoSellValue", val) end,
            },
        },
    })
end

-- =========================================================================
-- LIFECYCLE & EVENT DISPATCH
-- =========================================================================

function PUISellValue:OnInitialize()
    self:RegisterOptionsFlare()

    -- Synchronize global alias
    if _G.PrimusGlobalDB then
        _G.PrimusGlobalDB.PUISellValue = sellDB.data
    end

    -- CLI Router Integration
    if Console and Console.RegisterSubCommand then
        Console:RegisterSubCommand("sell", function(args)
            PUISellValue:HandleSlashCommand(args)
        end, "Vendor pricing & realm auction diagnostics (/pui sell)")
    end
end

local function HookTradeSkillButtons()
    if TradeSkillFrame then
        for i = 1, 8 do
            local btn = _G["TradeSkillSkill" .. i]
            if btn and not btn._primusTooltipHooked then
                btn._primusTooltipHooked = true
                local origOnEnter = btn:GetScript("OnEnter")
                btn:SetScript("OnEnter", function()
                    if origOnEnter then origOnEnter() end
                    local skillIndex = this:GetID() + (FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(TradeSkillListScrollFrame) or 0)
                    local skillName, skillType = GetTradeSkillInfo(skillIndex)
                    if skillName and skillType ~= "header" then
                        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                        GameTooltip:SetTradeSkillItem(skillIndex)
                    end
                end)
                local origOnLeave = btn:GetScript("OnLeave")
                btn:SetScript("OnLeave", function()
                    if origOnLeave then origOnLeave() end
                    GameTooltip:Hide()
                end)
            end
        end
    end

    if CraftFrame then
        for i = 1, 8 do
            local btn = _G["Craft" .. i]
            if btn and not btn._primusTooltipHooked then
                btn._primusTooltipHooked = true
                local origOnEnter = btn:GetScript("OnEnter")
                btn:SetScript("OnEnter", function()
                    if origOnEnter then origOnEnter() end
                    local craftIndex = this:GetID() + (FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(CraftListScrollFrame) or 0)
                    local craftName, craftSubSpellName, craftType = GetCraftInfo(craftIndex)
                    if craftName and craftType ~= "header" then
                        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                        GameTooltip:SetCraftItem(craftIndex)
                    end
                end)
                local origOnLeave = btn:GetScript("OnLeave")
                btn:SetScript("OnLeave", function()
                    if origOnLeave then origOnLeave() end
                    GameTooltip:Hide()
                end)
            end
        end
    end
end

function PUISellValue:OnEnable()
    -- Register as PUITooltip Item Provider
    local PUITooltip = Primus.PUITooltip
    if PUITooltip and PUITooltip.RegisterItemProvider then
        PUITooltip:RegisterItemProvider("PUISellValue", 10, function(tt, data)
            PUISellValue:OnTooltipProcess(tt, data)
        end)
    end

    -- Merchant Interaction Auto-Learning (Sell & Buy Prices)
    Events:Register("MERCHANT_SHOW", "PUISellValue", function()
        local newSell, newBuy = PUISellValue:ScanMerchantGoods()
        if (newSell + newBuy) > 0 then
            Debug:Info("PUISellValue", string.format("Learned %d sell prices and %d buy prices from merchant.", newSell, newBuy))
        end
    end)

    Events:Register("MERCHANT_UPDATE", "PUISellValue", function()
        PUISellValue:ScanMerchantGoods()
    end)

    -- TradeSkill and Craft UI Tooltip enhancements
    Events:Register("TRADE_SKILL_SHOW", "PUISellValue", function()
        HookTradeSkillButtons()
    end)
    Events:Register("TRADE_SKILL_UPDATE", "PUISellValue", function()
        HookTradeSkillButtons()
    end)
    Events:Register("CRAFT_SHOW", "PUISellValue", function()
        HookTradeSkillButtons()
    end)
    Events:Register("CRAFT_UPDATE", "PUISellValue", function()
        HookTradeSkillButtons()
    end)
    Events:Register("ADDON_LOADED", "PUISellValue", function()
        HookTradeSkillButtons()
    end)
end

function PUISellValue:OnDisable()
    local PUITooltip = Primus.PUITooltip
    if PUITooltip and PUITooltip.UnregisterItemProvider then
        PUITooltip:UnregisterItemProvider("PUISellValue")
    end
    Events:UnregisterOwner("PUISellValue")
end

-- =========================================================================
-- CLI DIAGNOSTICS HANDLER
-- =========================================================================

function PUISellValue:HandleSlashCommand(args)
    local realm = GetRealmName() or "Default"
    local rData = self:GetRealmData(realm)
    local learnedSell = rData.learnedCount or Utils.Count(rData.prices or {})
    local learnedBuy = rData.learnedBuyCount or Utils.Count(rData.buyPrices or {})
    local staticCount = Utils.Count(PUISellValue.StaticDB or {})
    local buyStaticCount = Utils.Count(PUISellValue.BuyStaticDB or {})
    local vipCount = Utils.Count(_G.VanillaItemPrices or VanillaItemPrices or {})

    local merchant = Primus.PUIMerchant or _G.PUIMerchant
    local realmAHData = merchant and merchant.GetRealmPriceData and merchant:GetRealmPriceData(realm)
    local ahCount = realmAHData and Utils.Count(realmAHData.priceData or {}) or 0

    if not args or args == "" or args == "status" then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("=== PrimusUI: Pricing & Valuation Database Status ===", "69ccf0"))
        DEFAULT_CHAT_FRAME:AddMessage(string.format("• Active Realm: |cffffd100%s|r", realm))
        DEFAULT_CHAT_FRAME:AddMessage(string.format("• Learned Realm Sell Prices: |cff00ff00%d items|r", learnedSell))
        DEFAULT_CHAT_FRAME:AddMessage(string.format("• Learned Realm Buy Prices:  |cff00ff00%d items|r", learnedBuy))
        DEFAULT_CHAT_FRAME:AddMessage(string.format("• Built-In Static Database:  |cff00e5ff%d items (Sell)|r / |cff00e5ff%d items (Buy)|r", staticCount, buyStaticCount))
        DEFAULT_CHAT_FRAME:AddMessage(string.format("• VanillaItemPrices Bridge:   |cffffcc00%d entries loaded|r", vipCount))
        DEFAULT_CHAT_FRAME:AddMessage(string.format("• AH Realm Market Listings:  |cff33ccff%d cataloged items|r", ahCount))
        DEFAULT_CHAT_FRAME:AddMessage("• Subcommands: |cffffffff/pui sell scan|r (scan merchant), |cffffffff/pui sell price <itemID/link>|r, |cffffffff/pui sell clear|r")
        return
    end

    local tokens = Utils.Split(args, " ")
    local cmd = string.lower(tokens[1] or "")

    if cmd == "scan" then
        if not MerchantFrame or not MerchantFrame:IsShown() then
            DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUISellValue]: You must be at a vendor window to scan and learn item prices.", "ffbb33"))
            return
        end
        local newSell, newBuy = self:ScanMerchantGoods()
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUISellValue]: Scanned merchant window. Learned %d new sell prices and %d new buy prices.", newSell, newBuy), "69ccf0"))
    elseif cmd == "price" then
        local target = tokens[2]
        if not target then
            DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUISellValue]: Usage: /pui sell price <itemID or itemLink>", "ffbb33"))
            return
        end
        local itemID = self:ExtractItemID(target)
        local itemName = CleanItemName(target)

        local sellPrice, sellSrc = self:GetSellPrice(itemID or itemName)
        local buyPrice, buySrc = self:GetBuyPrice(itemID or itemName)
        local minBuyout, avgBuyout, seenCount = self:GetAuctionPrice(itemName or itemID, realm)

        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("=== Pricing for: %s (ID: %s) [Realm: %s] ===", itemName or tostring(itemID), tostring(itemID or "N/A"), realm), "69ccf0"))
        if sellPrice then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("• Vendor Sell: |cffffffff%s|r (|cffaaaaaaSource: %s|r)", Utils.FormatMoney(sellPrice), tostring(sellSrc or "Unknown")))
        else
            DEFAULT_CHAT_FRAME:AddMessage("• Vendor Sell: |cff888888Unknown|r")
        end

        if buyPrice then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("• Vendor Buy:  |cffffffff%s|r (|cffaaaaaaSource: %s|r)", Utils.FormatMoney(buyPrice), tostring(buySrc or "Unknown")))
        else
            DEFAULT_CHAT_FRAME:AddMessage("• Vendor Buy:  |cff888888Unknown|r")
        end

        if avgBuyout then
            local seenStr = (seenCount and seenCount > 0) and string.format(" (Seen: %dx)", seenCount) or ""
            DEFAULT_CHAT_FRAME:AddMessage(string.format("• AH Market:   |cffffffff%s|r%s | Min Buyout: |cffffffff%s|r", Utils.FormatMoney(avgBuyout), seenStr, Utils.FormatMoney(minBuyout or avgBuyout)))
        else
            DEFAULT_CHAT_FRAME:AddMessage("• AH Market:   |cff888888No scan data recorded on this realm|r")
        end
    elseif cmd == "clear" then
        rData.prices = {}
        rData.buyPrices = {}
        rData.learnedCount = 0
        rData.learnedBuyCount = 0
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUISellValue]: Cleared learned price cache for realm '%s'.", realm), "ffbb33"))
    else
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUISellValue]: Unknown command. Use '/pui sell' for status.", "ff4444"))
    end
end
