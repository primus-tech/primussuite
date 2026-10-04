--[[
    PrimusUI Module: PUIMerchant (Economy & Valuation Master Orchestrator)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    1. Lifecycle Orchestration (OnInitialize, OnEnable, OnDisable).
    2. 1-Click Seller Assistance & Undercut Calculator on Auction Creation Tab.
    3. Shift+Click Quick Buyout & Per-Unit Price Overlays on Browse Rows.
    4. PUITooltip Provider Integration with Shift-Hover Sparklines.
    5. Console Command Router (/pui market, /pui merchant).
    6. Module Options Flare Configuration.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIMerchant = Primus.PUIMerchant or {}
Primus.PUIMerchant = PUIMerchant
_G.PUIMerchant = PUIMerchant
Primus:RegisterModule("PUIMerchant", PUIMerchant, "Utility")

local DB      = Primus.DB
local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local Events  = Primus.Events
local Time    = Primus.Time
local Items   = Primus.Items

local unitPriceLabels = {}
local lastAuctionedItemName = nil

-- =========================================================================
-- SELLER ASSISTANCE & 1-CLICK UNDERCUT ENGINE
-- =========================================================================

function PUIMerchant:UpdateAuctionAutoPricing()
    if not AuctionFrameAuctions or not AuctionFrameAuctions:IsShown() then return end

    local name, texture, count, quality, canUse, price = GetAuctionSellItemInfo()
    if not name or name == "" then
        lastAuctionedItemName = nil
        return
    end

    if name == lastAuctionedItemName then return end
    lastAuctionedItemName = name

    count = (count and count > 0) and count or 1
    local pData = self:GetItemMetrics(name)
    if not pData then return end

    local targetBuyoutPerUnit = 0
    local targetBidPerUnit = 0

    -- Calculate Undercut Buyout Price
    if pData.runningMedian7d and pData.runningMedian7d > 0 then
        -- Suggest 98% of 7-day Median or 1c below latest minimum buyout
        if pData.latestMinBuyout and pData.latestMinBuyout > 100 then
            targetBuyoutPerUnit = pData.latestMinBuyout - 1
        else
            targetBuyoutPerUnit = math.floor(pData.runningMedian7d * 0.98)
        end
    elseif pData.latestMinBuyout and pData.latestMinBuyout > 0 then
        targetBuyoutPerUnit = pData.latestMinBuyout
    end

    -- Calculate Bid Price (Low Tier 35% average or 80% of buyout)
    local todayKey = self:GetDayKey()
    local todayStat = pData.history and pData.history[todayKey]
    if todayStat and todayStat.lowAvg and todayStat.lowAvg > 0 then
        targetBidPerUnit = todayStat.lowAvg
    elseif targetBuyoutPerUnit > 0 then
        targetBidPerUnit = math.floor(targetBuyoutPerUnit * 0.80)
    end

    -- Apply Stack Total
    local totalBuyout = targetBuyoutPerUnit * count
    local totalBid = targetBidPerUnit * count

    if totalBuyout > 0 and BuyoutPrice then
        MoneyInputFrame_SetCopper(BuyoutPrice, totalBuyout)
    end
    if totalBid > 0 and StartPrice then
        MoneyInputFrame_SetCopper(StartPrice, totalBid)
    end

    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: Auto-Priced %s (x%d) -> Buyout: %s | Bid: %s", name, count, Utils.FormatMoney(totalBuyout), Utils.FormatMoney(totalBid)), "69ccf0"))
end

local function HookAuctionsTab()
    if not AuctionsItemButton or AuctionsItemButton.primusHooked then return end

    -- Hook Sell Slot Script
    local origOnClick = AuctionsItemButton:GetScript("OnClick")
    AuctionsItemButton:SetScript("OnClick", function()
        if origOnClick then origOnClick() end
        PUIMerchant:UpdateAuctionAutoPricing()
    end)

    local origOnDrag = AuctionsItemButton:GetScript("OnReceiveDrag")
    AuctionsItemButton:SetScript("OnReceiveDrag", function()
        if origOnDrag then origOnDrag() end
        PUIMerchant:UpdateAuctionAutoPricing()
    end)

    AuctionsItemButton.primusHooked = true
end

-- =========================================================================
-- BROWSE ROW PRICE-PER-UNIT & QUICK BUYOUT
-- =========================================================================

local function GetUnitPriceLabel(index, rowButton)
    if unitPriceLabels[index] then return unitPriceLabels[index] end

    local label = rowButton:CreateFontString(nil, "OVERLAY")
    label:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    label:SetPoint("BOTTOMRIGHT", rowButton, "BOTTOMRIGHT", -12, 2)
    label:SetTextColor(0.85, 0.85, 0.5)
    unitPriceLabels[index] = label
    return label
end

function PUIMerchant:UpdateBrowsePrices()
    if not AuctionFrame or not AuctionFrame:IsShown() then return end
    if not BrowseButton1 then return end

    local offset = FauxScrollFrame_GetOffset(BrowseScrollFrame) or 0
    local numBatchAuctions = GetNumAuctionItems("list")

    for i = 1, NUM_BROWSE_TO_DISPLAY do
        local rowBtn = _G["BrowseButton" .. i]
        if rowBtn and rowBtn:IsShown() then
            local index = offset + i
            local name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice = GetAuctionItemInfo("list", index)
            local label = GetUnitPriceLabel(i, rowBtn)

            if count and count > 1 and buyoutPrice and buyoutPrice > 0 then
                local unitPrice = math.floor(buyoutPrice / count)
                label:SetText(string.format("(%s ea)", Utils.FormatMoney(unitPrice)))
                label:Show()
            else
                label:Hide()
            end
        else
            if unitPriceLabels[i] then unitPriceLabels[i]:Hide() end
        end
    end
end

local function HookBrowseRows()
    for i = 1, NUM_BROWSE_TO_DISPLAY do
        local rowBtn = _G["BrowseButton" .. i]
        if rowBtn and not rowBtn.primusHooked then
            rowBtn.browseIndex = i
            rowBtn.origOnClick = rowBtn:GetScript("OnClick")
            rowBtn:SetScript("OnClick", function()
                if IsShiftKeyDown() and PUIMerchant.db:Get("quickBuyout", true) then
                    local offset = FauxScrollFrame_GetOffset(BrowseScrollFrame) or 0
                    local index = offset + (this.browseIndex or this:GetID() or 1)
                    local name, _, count, _, _, _, _, _, buyoutPrice = GetAuctionItemInfo("list", index)
                    if buyoutPrice and buyoutPrice > 0 then
                        SetSelectedAuctionItem("list", index)
                        PlaceAuctionBid("list", index, buyoutPrice)
                        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: Quick Buyout: %s (x%d) for %s", name or "Item", count or 1, Utils.FormatMoney(buyoutPrice)), "69ccf0"))
                        return
                    end
                end
                if this.origOnClick then
                    this.origOnClick()
                end
            end)
            rowBtn.primusHooked = true
        end
    end
end

-- =========================================================================
-- TOOLTIP MARKET PRICE INJECTION (PUITooltip Provider)
-- =========================================================================

local function InjectTooltipPrice(tooltip, itemData)
    if not PUIMerchant.db:Get("showTooltipPrices", true) then return end

    local itemName = nil
    if itemData and itemData.name then
        itemName = itemData.name
    else
        local name = _G[tooltip:GetName() .. "TextLeft1"]
        if name and name:GetText() then
            itemName = name:GetText()
        end
    end
    if not itemName then return end

    local pData = PUIMerchant:GetItemMetrics(itemName)
    if not pData then return end

    local minBuyout = pData.latestMinBuyout or 0
    local runAvg = pData.runningAvg7d or minBuyout
    local runMed = pData.runningMedian7d or runAvg

    if minBuyout > 0 or runAvg > 0 then
        tooltip:AddLine(" ")
        tooltip:AddDoubleLine("|cffffd100PUIMerchant 7d Avg:|r", Utils.FormatMoney(runAvg))
        tooltip:AddDoubleLine("|cff69ccf0Core Median (±15%):|r", Utils.FormatMoney(runMed))
        tooltip:AddDoubleLine("|cffaaaaaaLatest Min Buyout:|r", Utils.FormatMoney(minBuyout))

        -- Total Volume
        local totalVol = 0
        if pData.history then
            for _, h in pairs(pData.history) do
                totalVol = totalVol + (h.totalVolume or 0)
            end
        end
        if totalVol == 0 then totalVol = pData.totalVolume or 1 end
        tooltip:AddDoubleLine("|cffaaaaaaSeen in AH:|r", string.format("|cff33ccff%d items|r", totalVol))

        -- Shift-Hover Hint
        if not IsShiftKeyDown() and PUIMerchant.db:Get("showTooltipSparkline", true) then
            tooltip:AddLine("|cff555555[Hold Shift for Price Trend]|r")
        end

        tooltip:Show()
    end
end

-- =========================================================================
-- OPTIONS FLARE REGISTRATION
-- =========================================================================

function PUIMerchant:RegisterOptionsFlare()
    local Options = Primus.Options
    if not Options or not Options.RegisterModuleOptions then return end

    Options:RegisterModuleOptions("PUIMerchant", "Utility", {
        title = "PUIMerchant: Economy & Valuation",
        description = "Auction House 15s scanner, market pricing database, offline catalog, and dark glass skin.",
        fields = {
            {
                key = "enabled",
                label = "Enable PUIMerchant Economy Engine",
                type = "checkbox",
                default = true,
                get = function() return PUIMerchant.db:Get("enabled", true) end,
                set = function(val)
                    PUIMerchant.db:Set("enabled", val)
                    if val then PUIMerchant:OnEnable() else PUIMerchant:OnDisable() end
                end,
            },
            {
                key = "flyoutSide",
                label = "AH Control Flyout Docking Side",
                type = "select",
                options = {
                    { label = "Right Side", value = "RIGHT" },
                    { label = "Left Side",  value = "LEFT" },
                },
                default = "RIGHT",
                get = function() return PUIMerchant.db:Get("flyoutSide", "RIGHT") end,
                set = function(val)
                    PUIMerchant.db:Set("flyoutSide", val)
                    PUIMerchant:UpdateFlyoutAnchor()
                end,
            },
            {
                key = "quickBuyout",
                label = "Shift+Click Quick Buyout on Browse Rows",
                type = "checkbox",
                default = true,
                get = function() return PUIMerchant.db:Get("quickBuyout", true) end,
                set = function(val) PUIMerchant.db:Set("quickBuyout", val) end,
            },
            {
                key = "showTooltipPrices",
                label = "Inject AH Market Prices into GameTooltips",
                type = "checkbox",
                default = true,
                get = function() return PUIMerchant.db:Get("showTooltipPrices", true) end,
                set = function(val) PUIMerchant.db:Set("showTooltipPrices", val) end,
            },
            {
                key = "showTooltipSparkline",
                label = "Show Trend Breakdown in Tooltips",
                type = "checkbox",
                default = true,
                get = function() return PUIMerchant.db:Get("showTooltipSparkline", true) end,
                set = function(val) PUIMerchant.db:Set("showTooltipSparkline", val) end,
            },
        },
    })
end

-- =========================================================================
-- LIFECYCLE & EVENT DISPATCH
-- =========================================================================

function PUIMerchant:OnInitialize()
    self:RegisterOptionsFlare()

    -- Subcommand registration via Console Router
    if Primus.Console and Primus.Console.RegisterSubCommand then
        Primus.Console:RegisterSubCommand("merchant", function(argParam)
            argParam = Utils.Trim(argParam or "")
            if argParam == "stop" then
                PUIMerchant:StopScan()
            elseif argParam == "scan" or argParam == "" then
                if AuctionFrame and AuctionFrame:IsShown() then
                    PUIMerchant:StartScan(0)
                else
                    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIMerchant]: Open the Auction House to run an AH scan.", "69ccf0"))
                end
            elseif argParam == "prune" then
                local purged = PUIMerchant:PruneOldHistory(nil, 14)
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: Pruned %d stale entries older than 14 days.", purged), "69ccf0"))
            elseif argParam == "market" or argParam == "deals" then
                PUIMerchant:ToggleMarketExplorer(argParam == "deals")
            else
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("=== PrimusUI Merchant & Economy Suite ===", "69ccf0"))
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("/pui merchant [scan | stop | prune | market | deals]", "ffbb33"))
            end
        end, "PUIMerchant AH price scanner & valuation (/pui merchant [scan|stop|prune|market])")

        Primus.Console:RegisterSubCommand("market", function(argParam)
            argParam = Utils.Trim(argParam or "")
            PUIMerchant:ToggleMarketExplorer(argParam == "deals" or argParam == "sniper")
            if argParam ~= "" and argParam ~= "deals" and argParam ~= "sniper" then
                if searchEditBox then
                    searchEditBox:SetText(argParam)
                end
            end
        end, "PUIMerchant Offline Market Explorer (/pui market [itemName|deals])")
    end
end

function PUIMerchant:OnEnable()
    -- Initialize asynchronous scanner ticker
    self:InitScannerTicker()

    -- Hook AH Frame Show to apply skin, dock flyout, and hook rows
    Events:Register("AUCTION_HOUSE_SHOW", "PUIMerchant", function()
        PUIMerchant:SkinAuctionHouse()
        PUIMerchant:CreateFlyoutDrawer()
        HookBrowseRows()
        HookAuctionsTab()
        PUIMerchant:UpdateBrowsePrices()
    end)

    Events:Register("AUCTION_ITEM_LIST_UPDATE", "PUIMerchant", function()
        if PUIMerchant.scannerState and PUIMerchant.scannerState.isScanning then
            PUIMerchant:ProcessScanResults()
        else
            PUIMerchant:SniffBrowsePage()
            PUIMerchant:UpdateBrowsePrices()
        end
    end)

    Events:Register("AUCTION_HOUSE_CLOSED", "PUIMerchant", function()
        if PUIMerchant.scannerState and PUIMerchant.scannerState.isScanning then
            PUIMerchant:StopScan()
        end
    end)

    -- Register as PUITooltip Item Provider (Priority 20: runs after vendor base values)
    local Tooltip = Primus.PUITooltip
    if Tooltip and Tooltip.RegisterItemProvider then
        Tooltip:RegisterItemProvider("PUIMerchant", 20, function(tt, data)
            InjectTooltipPrice(tt, data)
        end)
    end
end

function PUIMerchant:OnDisable()
    Time:CancelAll("PUIMerchantScanner")
    Time:CancelAll("PUIMerchantCountdown")
    Events:UnregisterOwner("PUIMerchant")
    self:StopScan()

    local Tooltip = Primus.PUITooltip
    if Tooltip and Tooltip.UnregisterItemProvider then
        Tooltip:UnregisterItemProvider("PUIMerchant")
    end
end
