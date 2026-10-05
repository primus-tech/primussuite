--[[
    PrimusUI Module: PUIMerchant (Offline Market Explorer & TSM-Style Deal Finder)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    1. Standalone Offline Market Catalog Window (/pui market).
    2. TSM-Style Data Grid:
       - Item Icon & Name (Quality colored)
       - Scanned Volume
       - Latest Min Buyout & Core Median
       - 7-Day Running Average
       - Market Value Percentage (MV %) with Deal Highlighting (<= 70%)
       - 7-Day Mini Sparkline Strip
    3. Sniping & Vendor Arbitrage Tab (Items < 70% MV or < Vendor Sell Price).
    4. Live 14-Day Box-Plot Bar Graph Detail View for Selected Item.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIMerchant = Primus.PUIMerchant or {}
Primus.PUIMerchant = PUIMerchant

local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local Items   = Primus.Items

local explorerFrame = nil
local searchEditBox = nil
local qualityFilter = 0 -- 0 = All
local categoryFilter = "All"
local activeTab = "CATALOG" -- "CATALOG" or "SNIPER"
local selectedItemName = nil
local filteredItemList = {}
local rowFrames = {}
local NUM_ROWS = 9
local detailGraphFrame = nil
local detailTextLeft = nil
local detailTextRight = nil

-- Sorting State
local currentSortCol = "NAME"
local currentSortDir = "ASC" -- "ASC" or "DESC"
local headerButtons = {}

local HEADER_DEFINITIONS = {
    { key = "NAME",   title = "Item Name",   width = 190, align = "LEFT",   offX = 28  },
    { key = "VOL",    title = "Vol",         width = 40,  align = "RIGHT",  offX = 220 },
    { key = "MIN",    title = "Min Buyout",  width = 85,  align = "RIGHT",  offX = 265 },
    { key = "MEDIAN", title = "Core Median", width = 85,  align = "RIGHT",  offX = 355 },
    { key = "AVG",    title = "7d Run Avg",  width = 85,  align = "RIGHT",  offX = 445 },
    { key = "MVPCT",  title = "MV %",        width = 50,  align = "RIGHT",  offX = 535 },
    { key = "TREND",  title = "7-Day Trend", width = 110, align = "CENTER", offX = 595 },
}

-- Quality Mapping
local QUALITY_OPTIONS = {
    { text = "All Qualities", value = 0 },
    { text = "Common+ (1)",  value = 1 },
    { text = "Uncommon+ (2)", value = 2 },
    { text = "Rare+ (3)",    value = 3 },
    { text = "Epic+ (4)",    value = 4 },
}

-- Category Mapping
local CATEGORY_OPTIONS = {
    { text = "All Categories", value = "All" },
    { text = "Trade Goods",    value = "Trade Goods" },
    { text = "Consumables",    value = "Consumables" },
    { text = "Weapons & Armor", value = "Equipment" },
}

local ahScopeFilter = "CURRENT" -- "CURRENT", "Faction", "Neutral"

-- =========================================================================
-- SORTING ENGINE & HELPERS
-- =========================================================================

local function GetTotalVolume(pData)
    if not pData then return 0 end
    local totalVol = 0
    if pData.history then
        for _, h in pairs(pData.history) do
            totalVol = totalVol + (h.totalVolume or 0)
        end
    end
    if totalVol == 0 then totalVol = pData.totalVolume or 1 end
    return totalVol
end

local function GetItemMVPct(pData)
    if not pData then return 100 end
    local minB = pData.latestMinBuyout or 0
    local runMed = pData.runningMedian7d or pData.runningAvg7d or 0
    if runMed > 0 and minB > 0 then
        return math.floor((minB / runMed) * 100)
    end
    return 100
end

function PUIMerchant:SortExplorerList()
    local col = currentSortCol or "NAME"
    local dir = currentSortDir or "ASC"

    table.sort(filteredItemList, function(a, b)
        local valA, valB
        if col == "NAME" then
            valA = string.lower(a.name or "")
            valB = string.lower(b.name or "")
        elseif col == "VOL" then
            valA = GetTotalVolume(a)
            valB = GetTotalVolume(b)
        elseif col == "MIN" then
            valA = a.latestMinBuyout or 0
            valB = b.latestMinBuyout or 0
        elseif col == "MEDIAN" then
            valA = a.runningMedian7d or a.latestMinBuyout or 0
            valB = b.runningMedian7d or b.latestMinBuyout or 0
        elseif col == "AVG" then
            valA = a.runningAvg7d or a.latestMinBuyout or 0
            valB = b.runningAvg7d or b.latestMinBuyout or 0
        elseif col == "MVPCT" then
            valA = GetItemMVPct(a)
            valB = GetItemMVPct(b)
        else
            valA = string.lower(a.name or "")
            valB = string.lower(b.name or "")
        end

        if valA == valB then
            return string.lower(a.name or "") < string.lower(b.name or "")
        end

        if dir == "ASC" then
            return valA < valB
        else
            return valA > valB
        end
    end)
end

function PUIMerchant:UpdateHeaderLabels()
    for _, def in ipairs(HEADER_DEFINITIONS) do
        local btn = headerButtons[def.key]
        if btn and btn.label then
            if def.key == currentSortCol then
                local arrow = (currentSortDir == "ASC") and "▲" or "▼"
                btn.label:SetText(string.format("|cff20c0ff%s %s|r", def.title, arrow))
                if btn.SetBackdropBorderColor then
                    btn:SetBackdropBorderColor(0.20, 0.75, 1.0, 0.8)
                end
            else
                btn.label:SetText(string.format("|cff88aacc%s|r", def.title))
                if btn.SetBackdropBorderColor then
                    btn:SetBackdropBorderColor(0.20, 0.20, 0.25, 0.0)
                end
            end
        end
    end
end

function PUIMerchant:SetExplorerSort(colKey)
    if colKey == "TREND" then return end

    if currentSortCol == colKey then
        currentSortDir = (currentSortDir == "ASC") and "DESC" or "ASC"
    else
        currentSortCol = colKey
        if colKey == "VOL" or colKey == "MIN" or colKey == "MEDIAN" or colKey == "AVG" then
            currentSortDir = "DESC" -- numeric defaults to highest first
        else
            currentSortDir = "ASC"  -- name / mv % defaults to lowest/A-Z first
        end
    end

    self:SortExplorerList()
    self:UpdateHeaderLabels()
    self:UpdateExplorerTable()
end

-- =========================================================================
-- FILTERING & DATA REFRESH
-- =========================================================================

function PUIMerchant:RefreshExplorerData()
    if not explorerFrame or not explorerFrame:IsShown() then return end

    filteredItemList = {}
    local realm = GetRealmName() or "Default"
    local targetAHTypes = {}

    if ahScopeFilter == "CURRENT" then
        table.insert(targetAHTypes, self:GetCurrentAHType())
    elseif ahScopeFilter == "Neutral" then
        table.insert(targetAHTypes, "Neutral")
    elseif ahScopeFilter == "Faction" then
        table.insert(targetAHTypes, UnitFactionGroup("player") or "Alliance")
    else
        table.insert(targetAHTypes, "Alliance")
        table.insert(targetAHTypes, "Horde")
        table.insert(targetAHTypes, "Neutral")
    end

    local queryText = searchEditBox and string.lower(Utils.Trim(searchEditBox:GetText() or "")) or ""
    local seenItems = {}

    for _, ahType in ipairs(targetAHTypes) do
        local realmData = self:GetRealmPriceData(realm, ahType)
        if realmData and realmData.priceData then
            for itemName, pData in pairs(realmData.priceData) do
                if not seenItems[itemName] then
                    local matches = true

                    -- Search Query Filter
                    if queryText ~= "" then
                        local lowerName = string.lower(itemName)
                        if not string.find(lowerName, queryText, 1, true) then
                            matches = false
                        end
                    end

                    -- Quality Filter
                    if matches and qualityFilter > 0 then
                        local q = pData.quality or 1
                        if q < qualityFilter then matches = false end
                    end

                    -- Category Filter
                    if matches and categoryFilter ~= "All" then
                        local cls = pData.itemClass or "Trade Goods"
                        if categoryFilter == "Equipment" then
                            if cls ~= "Weapon" and cls ~= "Armor" then matches = false end
                        elseif cls ~= categoryFilter then
                            matches = false
                        end
                    end

                    -- Mode Filter: Sniping / Deal Finder Tab
                    if matches and activeTab == "SNIPER" then
                        local isDeal = false
                        local minB = pData.latestMinBuyout or 0
                        local runMed = pData.runningMedian7d or pData.runningAvg7d or 0

                        -- Deal criteria 1: Listed at <= 70% of 7-day Running Median
                        if runMed > 0 and minB > 0 and (minB <= (runMed * 0.70)) then
                            isDeal = true
                        end

                        -- Deal criteria 2: Listed below vendor sell price (instant arbitrage)
                        local itemID = Items:GetID(itemName)
                        if itemID and VanillaItemPrices and VanillaItemPrices[itemID] then
                            local vSell = VanillaItemPrices[itemID].s or 0
                            if vSell > 0 and minB > 0 and minB < vSell then
                                isDeal = true
                            end
                        end

                        if not isDeal then matches = false end
                    end

                    if matches then
                        seenItems[itemName] = true
                        table.insert(filteredItemList, pData)
                    end
                end
            end
        end
    end

    self:SortExplorerList()
    self:UpdateHeaderLabels()
    self:UpdateExplorerTable()
end

-- =========================================================================
-- TABLE RENDERING & SELECTION
-- =========================================================================

function PUIMerchant:UpdateExplorerTable()
    if not explorerFrame or not explorerFrame.scrollFrame then return end

    local totalItems = table.getn(filteredItemList)
    FauxScrollFrame_Update(explorerFrame.scrollFrame, totalItems, NUM_ROWS, 24)
    local offset = FauxScrollFrame_GetOffset(explorerFrame.scrollFrame) or 0

    for i = 1, NUM_ROWS do
        local row = rowFrames[i]
        local dataIndex = offset + i

        if row and dataIndex <= totalItems then
            local pData = filteredItemList[dataIndex]
            row.pData = pData
            row.itemName = pData.name

            -- Item Icon
            if pData.texture then
                row.icon:SetTexture(pData.texture)
                row.icon:Show()
            else
                row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                row.icon:Show()
            end

            -- Quality Color & Name
            local qColor = Items:GetQualityColor(pData.quality or 1)
            row.nameText:SetText(pData.name or "Unknown")
            row.nameText:SetTextColor(qColor.r, qColor.g, qColor.b)

            -- Volume
            local totalVol = 0
            if pData.history then
                for _, h in pairs(pData.history) do
                    totalVol = totalVol + (h.totalVolume or 0)
                end
            end
            if totalVol == 0 then totalVol = pData.totalVolume or 1 end
            row.volText:SetText(tostring(totalVol))

            -- Latest Min Buyout
            row.minBuyoutText:SetText(Utils.FormatMoney(pData.latestMinBuyout or 0))

            -- Core Median
            row.medianText:SetText(Utils.FormatMoney(pData.runningMedian7d or pData.latestMinBuyout or 0))

            -- 7-Day Running Average
            local runAvg = pData.runningAvg7d or pData.latestMinBuyout or 0
            row.runAvgText:SetText(Utils.FormatMoney(runAvg))

            -- Market Value % (MV %)
            local runMed = pData.runningMedian7d or runAvg
            if runMed > 0 and pData.latestMinBuyout and pData.latestMinBuyout > 0 then
                local mvPct = math.floor((pData.latestMinBuyout / runMed) * 100)
                if mvPct <= 70 then
                    row.mvText:SetText(string.format("|cff1eff00%d%% !|r", mvPct))
                elseif mvPct > 120 then
                    row.mvText:SetText(string.format("|cffff4444%d%%|r", mvPct))
                else
                    row.mvText:SetText(string.format("|cffffd100%d%%|r", mvPct))
                end
            else
                row.mvText:SetText("|cff888888100%|r")
            end

            -- Sparkline Strip
            PUIMerchant:UpdateMiniSparkline(row.sparkline, pData)

            -- Highlight selected row
            if selectedItemName and selectedItemName == pData.name then
                row:SetBackdropColor(0.18, 0.22, 0.32, 0.95)
                row:SetBackdropBorderColor(0.40, 0.70, 1.00, 1.0)
            else
                row:SetBackdropColor(0.08, 0.08, 0.11, 0.70)
                row:SetBackdropBorderColor(0.18, 0.18, 0.22, 0.8)
            end

            row:Show()
        else
            if row then row:Hide() end
        end
    end

    -- Update detail pane for selected item
    self:UpdateDetailPane()
end

function PUIMerchant:SelectItem(itemName)
    selectedItemName = itemName
    self:UpdateExplorerTable()
end

function PUIMerchant:UpdateDetailPane()
    if not detailGraphFrame then return end

    if not selectedItemName then
        if table.getn(filteredItemList) > 0 then
            selectedItemName = filteredItemList[1].name
        else
            detailTextLeft:SetText("Select an item above to view 14-day market history.")
            detailTextRight:SetText("")
            PUIMerchant:UpdateMarketBarGraph(detailGraphFrame, nil)
            return
        end
    end

    local pData = self:GetItemMetrics(selectedItemName)
    if not pData then
        detailTextLeft:SetText("No data available for selected item.")
        detailTextRight:SetText("")
        PUIMerchant:UpdateMarketBarGraph(detailGraphFrame, nil)
        return
    end

    -- Format Left Stats
    local qColor = Items:GetQualityColor(pData.quality or 1)
    local leftStr = string.format("|cff%s[%s]|r\n", qColor.hex or "ffffff", pData.name or "Item")
    leftStr = leftStr .. string.format("|cffaaaaaaLatest Min Buyout:|r %s\n", Utils.FormatMoney(pData.latestMinBuyout or 0))
    leftStr = leftStr .. string.format("|cffaaaaaa7-Day Running Avg:|r %s\n", Utils.FormatMoney(pData.runningAvg7d or 0))
    leftStr = leftStr .. string.format("|cffaaaaaa7-Day Core Median:|r %s", Utils.FormatMoney(pData.runningMedian7d or 0))

    -- Check for Vendor Arbitrage
    local itemID = Items:GetID(pData.name)
    if itemID and VanillaItemPrices and VanillaItemPrices[itemID] then
        local vSell = VanillaItemPrices[itemID].s or 0
        if vSell > 0 and pData.latestMinBuyout and pData.latestMinBuyout < vSell then
            leftStr = leftStr .. string.format("\n|cff1eff00[ARBITRAGE]: Sells to Vendor for %s (Profit: +%s)|r", Utils.FormatMoney(vSell), Utils.FormatMoney(vSell - pData.latestMinBuyout))
        end
    end
    detailTextLeft:SetText(leftStr)

    -- Format Right Stats (Latest Day Breakdown)
    local todayKey = self:GetDayKey()
    local todayStat = pData.history and (pData.history[todayKey] or nil)
    if not todayStat and pData.history then
        -- Grab newest recorded day
        local dKeys = {}
        for k, _ in pairs(pData.history) do table.insert(dKeys, k) end
        table.sort(dKeys)
        if table.getn(dKeys) > 0 then
            todayStat = pData.history[dKeys[table.getn(dKeys)]]
        end
    end

    if todayStat then
        local rightStr = string.format("|cff69ccf0Distribution Snapshot:|r\n")
        rightStr = rightStr .. string.format("|cff1eff00Low Tier (35%%):|r %s (%d items)\n", Utils.FormatMoney(todayStat.lowAvg or 0), todayStat.lowVolume or 0)
        rightStr = rightStr .. string.format("|cffffd100Core Range (±15%%):|r %s - %s (%d items)\n", Utils.FormatMoney(todayStat.coreMin or 0), Utils.FormatMoney(todayStat.coreMax or 0), todayStat.coreVolume or 0)
        rightStr = rightStr .. string.format("|cffff4444High Tier (35%%):|r %s (%d items)", Utils.FormatMoney(todayStat.highAvg or 0), todayStat.highVolume or 0)
        detailTextRight:SetText(rightStr)
    else
        detailTextRight:SetText("|cff888888Single-point scan data.\nFull box-plot clusters populate\nafter multi-page AH scans.|r")
    end

    -- Update Bar Graph
    PUIMerchant:UpdateMarketBarGraph(detailGraphFrame, pData)
end

-- =========================================================================
-- CREATE MAIN EXPLORER WINDOW
-- =========================================================================

function PUIMerchant:CreateMarketExplorerWindow()
    if explorerFrame then return end

    explorerFrame = Widgets:CreatePanel(UIParent, "PUIMerchant: Market Explorer & Analytics", 740, 470)
    explorerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    explorerFrame:Hide()

    -- Search EditBox
    searchEditBox = CreateFrame("EditBox", "PUIMerchantExplorerSearch", explorerFrame)
    searchEditBox:SetWidth(180)
    searchEditBox:SetHeight(22)
    searchEditBox:SetPoint("TOPLEFT", explorerFrame, "TOPLEFT", 12, -32)
    searchEditBox:SetBackdrop(Media:Fetch("border", "1Pixel"))
    searchEditBox:SetBackdropColor(0.04, 0.04, 0.06, 0.90)
    searchEditBox:SetBackdropBorderColor(0.25, 0.25, 0.30, 1.0)
    searchEditBox:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    searchEditBox:SetAutoFocus(false)
    searchEditBox:SetTextInsets(6, 6, 0, 0)
    searchEditBox:SetScript("OnTextChanged", function()
        PUIMerchant:RefreshExplorerData()
    end)

    local searchPlaceholder = searchEditBox:CreateFontString(nil, "OVERLAY")
    searchPlaceholder:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    searchPlaceholder:SetPoint("LEFT", searchEditBox, "LEFT", 8, 0)
    searchPlaceholder:SetTextColor(0.5, 0.5, 0.5)
    searchPlaceholder:SetText("Search item name...")
    searchEditBox:SetScript("OnEditFocusGained", function() searchPlaceholder:Hide() end)
    searchEditBox:SetScript("OnEditFocusLost", function()
        if searchEditBox:GetText() == "" then searchPlaceholder:Show() end
    end)

    -- Quality Filter Button
    local qBtn = Widgets:CreateButton(explorerFrame, "All Qualities", 100, 22, function()
        qualityFilter = math.mod(qualityFilter + 1, 5)
        local opt = QUALITY_OPTIONS[qualityFilter + 1]
        this:SetText(opt.text)
        PUIMerchant:RefreshExplorerData()
    end)
    qBtn:SetPoint("LEFT", searchEditBox, "RIGHT", 6, 0)

    -- Mode Tab: Catalog
    local catalogTabBtn = Widgets:CreateButton(explorerFrame, "Market Catalog", 110, 22, function()
        activeTab = "CATALOG"
        this:SetBackdropBorderColor(0.20, 0.75, 1.0, 1.0)
        _G["PUIMerchantSniperTabBtn"]:SetBackdropBorderColor(0.25, 0.25, 0.30, 1.0)
        if currentSortCol == "MVPCT" then
            currentSortCol = "NAME"
            currentSortDir = "ASC"
        end
        PUIMerchant:RefreshExplorerData()
    end)
    catalogTabBtn:SetPoint("LEFT", qBtn, "RIGHT", 14, 0)
    catalogTabBtn:SetBackdropBorderColor(0.20, 0.75, 1.0, 1.0)

    -- Mode Tab: Deal Finder / Sniper
    local sniperTabBtn = Widgets:CreateButton(explorerFrame, "Deal Finder & Sniper", 140, 22, function()
        activeTab = "SNIPER"
        this:SetBackdropBorderColor(0.20, 0.85, 0.35, 1.0)
        catalogTabBtn:SetBackdropBorderColor(0.25, 0.25, 0.30, 1.0)
        if currentSortCol == "NAME" then
            currentSortCol = "MVPCT"
            currentSortDir = "ASC"
        end
        PUIMerchant:RefreshExplorerData()
    end)
    sniperTabBtn:SetPoint("LEFT", catalogTabBtn, "RIGHT", 4, 0)
    _G["PUIMerchantSniperTabBtn"] = sniperTabBtn

    -- Refresh Button
    local refreshBtn = Widgets:CreateButton(explorerFrame, "Refresh", 60, 22, function()
        PUIMerchant:RefreshExplorerData()
    end)
    refreshBtn:SetPoint("TOPRIGHT", explorerFrame, "TOPRIGHT", -28, -32)

    -- Table Column Headers (Interactive & Sortable)
    local headerFrame = CreateFrame("Frame", nil, explorerFrame)
    headerFrame:SetWidth(716)
    headerFrame:SetHeight(20)
    headerFrame:SetPoint("TOPLEFT", explorerFrame, "TOPLEFT", 12, -60)

    headerButtons = {}
    for _, def in ipairs(HEADER_DEFINITIONS) do
        local defKey = def.key
        if defKey == "TREND" then
            local lbl = headerFrame:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
            lbl:SetWidth(def.width)
            lbl:SetJustifyH(def.align)
            lbl:SetPoint("LEFT", headerFrame, "LEFT", def.offX, 0)
            lbl:SetTextColor(0.4, 0.8, 1.0)
            lbl:SetText(def.title)
        else
            local btn = CreateFrame("Button", nil, headerFrame)
            btn:SetWidth(def.width)
            btn:SetHeight(18)
            btn:SetPoint("LEFT", headerFrame, "LEFT", def.offX, 0)
            btn:SetBackdrop(Media:Fetch("border", "1Pixel"))
            btn:SetBackdropColor(0.08, 0.08, 0.12, 0.50)
            btn:SetBackdropBorderColor(0.20, 0.20, 0.25, 0.0)

            local lbl = btn:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
            lbl:SetPoint("LEFT", btn, "LEFT", 2, 0)
            lbl:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
            lbl:SetJustifyH(def.align)
            lbl:SetText(def.title)
            btn.label = lbl

            btn:SetScript("OnClick", function()
                PUIMerchant:SetExplorerSort(defKey)
            end)
            btn:SetScript("OnEnter", function()
                btn:SetBackdropColor(0.15, 0.18, 0.25, 0.90)
                btn.label:SetTextColor(1.0, 1.0, 1.0)
            end)
            btn:SetScript("OnLeave", function()
                btn:SetBackdropColor(0.08, 0.08, 0.12, 0.50)
                PUIMerchant:UpdateHeaderLabels()
            end)

            headerButtons[defKey] = btn
        end
    end
    PUIMerchant:UpdateHeaderLabels()

    -- Table Scroll Frame
    local scrollFrame = CreateFrame("ScrollFrame", "PUIMerchantExplorerScroll", explorerFrame, "FauxScrollFrameTemplate")
    scrollFrame:SetWidth(692)
    scrollFrame:SetHeight(220)
    scrollFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -2)
    explorerFrame.scrollFrame = scrollFrame

    scrollFrame:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(24, function()
            PUIMerchant:UpdateExplorerTable()
        end)
    end)

    -- Build Row Frames
    for i = 1, NUM_ROWS do
        local row = CreateFrame("Button", nil, explorerFrame)
        row:SetWidth(716)
        row:SetHeight(23)
        row:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -((i - 1) * 24))
        row:SetBackdrop(Media:Fetch("border", "1Pixel"))
        row:SetBackdropColor(0.08, 0.08, 0.11, 0.70)
        row:SetBackdropBorderColor(0.18, 0.18, 0.22, 0.8)

        -- Icon
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(18)
        icon:SetHeight(18)
        icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon = icon

        -- Name
        local nameText = row:CreateFontString(nil, "OVERLAY")
        nameText:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
        nameText:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        nameText:SetWidth(185)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        -- Volume
        local volText = row:CreateFontString(nil, "OVERLAY")
        volText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
        volText:SetPoint("LEFT", row, "LEFT", 220, 0)
        volText:SetWidth(40)
        volText:SetJustifyH("RIGHT")
        volText:SetTextColor(0.8, 0.8, 0.8)
        row.volText = volText

        -- Min Buyout
        local minBuyoutText = row:CreateFontString(nil, "OVERLAY")
        minBuyoutText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
        minBuyoutText:SetPoint("LEFT", row, "LEFT", 265, 0)
        minBuyoutText:SetWidth(85)
        minBuyoutText:SetJustifyH("RIGHT")
        row.minBuyoutText = minBuyoutText

        -- Median
        local medianText = row:CreateFontString(nil, "OVERLAY")
        medianText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
        medianText:SetPoint("LEFT", row, "LEFT", 355, 0)
        medianText:SetWidth(85)
        medianText:SetJustifyH("RIGHT")
        row.medianText = medianText

        -- Run Avg
        local runAvgText = row:CreateFontString(nil, "OVERLAY")
        runAvgText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
        runAvgText:SetPoint("LEFT", row, "LEFT", 445, 0)
        runAvgText:SetWidth(85)
        runAvgText:SetJustifyH("RIGHT")
        row.runAvgText = runAvgText

        -- MV %
        local mvText = row:CreateFontString(nil, "OVERLAY")
        mvText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
        mvText:SetPoint("LEFT", row, "LEFT", 535, 0)
        mvText:SetWidth(50)
        mvText:SetJustifyH("RIGHT")
        row.mvText = mvText

        -- Sparkline
        local sparkline = PUIMerchant:CreateMiniSparkline(row, 105, 16)
        sparkline:SetPoint("LEFT", row, "LEFT", 595, 0)
        row.sparkline = sparkline

        -- Click handler
        row:SetScript("OnClick", function()
            if this.itemName then
                if IsShiftKeyDown() and ChatFrameEditBox and ChatFrameEditBox:IsVisible() then
                    ChatFrameEditBox:Insert(string.format("[%s]", this.itemName))
                    return
                end
                PUIMerchant:SelectItem(this.itemName)
            end
        end)

        row:SetScript("OnEnter", function()
            if this.pData and this.pData.name then
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                local qColor = Items:GetQualityColor(this.pData.quality or 1)
                GameTooltip:AddLine(this.pData.name, qColor.r, qColor.g, qColor.b)
                GameTooltip:AddDoubleLine("Latest Min Buyout:", Utils.FormatMoney(this.pData.latestMinBuyout or 0))
                GameTooltip:AddDoubleLine("7-Day Running Avg:", Utils.FormatMoney(this.pData.runningAvg7d or 0))
                GameTooltip:AddDoubleLine("7-Day Core Median:", Utils.FormatMoney(this.pData.runningMedian7d or 0))
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cff69ccf0Click to view 14-day box-plot chart|r")
                GameTooltip:AddLine("|cffaaaaaaShift+Click to link item in chat|r")
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        rowFrames[i] = row
    end

    -- Bottom Detail Pane Container
    local detailPane = CreateFrame("Frame", nil, explorerFrame)
    detailPane:SetWidth(716)
    detailPane:SetHeight(135)
    detailPane:SetPoint("BOTTOMLEFT", explorerFrame, "BOTTOMLEFT", 12, 10)
    detailPane:SetBackdrop(Media:Fetch("border", "1Pixel"))
    detailPane:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    detailPane:SetBackdropBorderColor(0.20, 0.20, 0.25, 1.0)

    -- Left Detail Text
    detailTextLeft = detailPane:CreateFontString(nil, "OVERLAY")
    detailTextLeft:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    detailTextLeft:SetPoint("TOPLEFT", detailPane, "TOPLEFT", 10, -8)
    detailTextLeft:SetJustifyH("LEFT")
    detailTextLeft:SetText("Select an item above...")

    -- Right Detail Text
    detailTextRight = detailPane:CreateFontString(nil, "OVERLAY")
    detailTextRight:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    detailTextRight:SetPoint("TOPLEFT", detailPane, "TOPLEFT", 225, -8)
    detailTextRight:SetJustifyH("LEFT")
    detailTextRight:SetText("")

    -- Live 14-Day Box-Plot Bar Graph
    detailGraphFrame = PUIMerchant:CreateMarketBarGraph(detailPane, 250, 118, 14)
    detailGraphFrame:SetPoint("TOPRIGHT", detailPane, "TOPRIGHT", -8, -8)

    PUIMerchant.explorerFrame = explorerFrame
end

-- Toggle Explorer Modal
function PUIMerchant:ToggleMarketExplorer(openSnipingTab)
    self:CreateMarketExplorerWindow()
    if not explorerFrame then return end

    if explorerFrame:IsShown() then
        explorerFrame:Hide()
    else
        if openSnipingTab then
            activeTab = "SNIPER"
            if _G["PUIMerchantSniperTabBtn"] then
                _G["PUIMerchantSniperTabBtn"]:SetBackdropBorderColor(0.20, 0.85, 0.35, 1.0)
            end
        else
            activeTab = "CATALOG"
        end
        explorerFrame:Show()
        self:RefreshExplorerData()
    end
end
