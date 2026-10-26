--[[
    PrimusUI Module: PUIBags (Automated Inventory Sorting & Stack Defragmentation Engine)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Features:
    1. Automated Stack Defragmentation: Consolidates partial stacks of identical items.
    2. Rule-Based Priority Sorting: Quest -> Consumables -> Trade Goods -> Equipment -> Utility -> Recipes -> Misc -> Junk -> Free.
    3. Throttled Non-Blocking Cursor Move Queue: Safe Vanilla 1.12.1 item swapping with lock-state validation and zero packet loss.
    4. Special Container Isolation: Quivers, Ammo Pouches, Soul Bags, Herb Bags, Mining Sacks preserved without corrupting slots.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIBags = Primus.PUIBags or {}
Primus.PUIBags = PUIBags
_G.PUIBags = PUIBags

local Sort = {}
PUIBags.Sort = Sort

local Utils      = Primus.Utils
local Categories = PUIBags.Categories
local Events     = Primus.Events

local isSorting = false
local moveQueue = {}
local currentMoveIndex = 1
local sortTickerFrame = nil
local sortStartTime = 0
local MAX_SORT_TIMEOUT = 8.0 -- Safety timeout in seconds

-- =========================================================================
-- STACK DEFRAGMENTATION (CONSOLIDATION)
-- =========================================================================

-- =========================================================================
-- VIRTUAL BAG STATE BUILDER
-- =========================================================================

function Sort:BuildVirtualBags()
    local vb = {}
    for bagID = 0, 4 do
        vb[bagID] = {}
        local numSlots = GetContainerNumSlots(bagID) or 0
        for slotID = 1, numSlots do
            local texture, itemCount, locked, quality = GetContainerItemInfo(bagID, slotID)
            local itemLink = GetContainerItemLink(bagID, slotID)

            if texture and itemLink then
                local _, _, itemIDStr = string.find(itemLink, "item:(%d+)")
                local itemID = tonumber(itemIDStr) or 0
                local name, _, qual, minLvl, iType, sType, maxStack = GetItemInfo(itemLink)
                local prio, pName, pQual, pMinLvl, pType, isBound = Categories:ClassifyItem(bagID, slotID)

                vb[bagID][slotID] = {
                    bag = bagID,
                    slot = slotID,
                    itemID = itemID,
                    name = name or pName or ("Item #" .. itemID),
                    quality = qual or pQual or quality or 0,
                    minLevel = minLvl or pMinLvl or 0,
                    itemType = iType or pType or "",
                    itemSubType = sType or "",
                    count = itemCount or 1,
                    maxStack = maxStack or 1,
                    priority = prio,
                    isBound = isBound,
                    link = itemLink,
                }
            else
                vb[bagID][slotID] = nil
            end
        end
    end
    return vb
end

-- =========================================================================
-- SPECIAL CONTAINER PACKING (Ammo -> Quivers, Mats -> Specialty Bags)
-- =========================================================================

function Sort:PackSpecialContainers(vb)
    local moves = {}

    -- 1. Identify equipped specialized containers (quivers, pouches, soul bags, herb, mining, enchanting)
    local specialBags = {}
    for bagID = 1, 4 do
        local specType = Categories:GetSpecialContainerType(bagID)
        if specType then
            table.insert(specialBags, {
                bagID = bagID,
                specType = specType,
                numSlots = GetContainerNumSlots(bagID) or 0,
            })
        end
    end

    if table.getn(specialBags) == 0 then
        return moves
    end

    -- Phase A: Consolidate partial stacks inside each special bag
    for _, spec in ipairs(specialBags) do
        local bID = spec.bagID
        local numSlots = spec.numSlots
        for s1 = 1, numSlots - 1 do
            local it1 = vb[bID][s1]
            if it1 and it1.maxStack > 1 and it1.count < it1.maxStack then
                for s2 = s1 + 1, numSlots do
                    local it2 = vb[bID][s2]
                    if it2 and it2.itemID == it1.itemID and it2.count > 0 then
                        local space = it1.maxStack - it1.count
                        local transfer = math.min(space, it2.count)
                        it1.count = it1.count + transfer
                        it2.count = it2.count - transfer

                        table.insert(moves, {
                            fromBag = bID,
                            fromSlot = s2,
                            toBag = bID,
                            toSlot = s1,
                            type = "MERGE",
                        })

                        if it2.count == 0 then
                            vb[bID][s2] = nil
                        end
                    end
                end
            end
        end
    end

    -- Phase B: Scan regular bags for items matching special bag types and pack them
    for _, spec in ipairs(specialBags) do
        local specBagID = spec.bagID
        local specType = spec.specType
        local specNumSlots = spec.numSlots

        for regBagID = 0, 4 do
            local isRegSpecial = Categories:GetSpecialContainerType(regBagID)
            if not isRegSpecial then
                local regSlots = GetContainerNumSlots(regBagID) or 0
                for regSlotID = 1, regSlots do
                    local regItem = vb[regBagID][regSlotID]
                    if regItem and regItem.count > 0 then
                        local matchingType = Categories:GetItemSpecialContainerType(
                            regItem.link, regItem.name, regItem.itemType, regItem.itemSubType, regItem.itemID
                        )

                        if matchingType == specType then
                            -- Step B1: Try merging into existing partial stacks in the special container
                            if regItem.maxStack > 1 then
                                for sSlot = 1, specNumSlots do
                                    local sItem = vb[specBagID][sSlot]
                                    if sItem and sItem.itemID == regItem.itemID and sItem.count < sItem.maxStack then
                                        local space = sItem.maxStack - sItem.count
                                        local transfer = math.min(space, regItem.count)
                                        sItem.count = sItem.count + transfer
                                        regItem.count = regItem.count - transfer

                                        table.insert(moves, {
                                            fromBag = regBagID,
                                            fromSlot = regSlotID,
                                            toBag = specBagID,
                                            toSlot = sSlot,
                                            type = "MERGE",
                                        })

                                        if regItem.count == 0 then
                                            vb[regBagID][regSlotID] = nil
                                            break
                                        end
                                    end
                                end
                            end

                            -- Step B2: If item still has remaining count, place in an empty slot in the special container
                            if regItem and regItem.count > 0 then
                                for sSlot = 1, specNumSlots do
                                    if not vb[specBagID][sSlot] then
                                        table.insert(moves, {
                                            fromBag = regBagID,
                                            fromSlot = regSlotID,
                                            toBag = specBagID,
                                            toSlot = sSlot,
                                            type = "PACK",
                                        })
                                        vb[specBagID][sSlot] = regItem
                                        regItem.bag = specBagID
                                        regItem.slot = sSlot
                                        vb[regBagID][regSlotID] = nil
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return moves
end

-- =========================================================================
-- STACK DEFRAGMENTATION (CONSOLIDATION)
-- =========================================================================

-- Scans regular bags and merges partial stacks of the same item
function Sort:ConsolidateStacks(vb)
    local partialStacks = {} -- [itemID] = { itemRecord1, itemRecord2, ... }

    for bagID = 0, 4 do
        local isSpecial = Categories:GetSpecialContainerType(bagID)
        if not isSpecial then
            local numSlots = GetContainerNumSlots(bagID) or 0
            for slotID = 1, numSlots do
                local item = vb[bagID][slotID]
                if item and item.maxStack > 1 and item.count < item.maxStack then
                    if not partialStacks[item.itemID] then
                        partialStacks[item.itemID] = {}
                    end
                    table.insert(partialStacks[item.itemID], item)
                end
            end
        end
    end

    local moves = {}
    for itemID, list in pairs(partialStacks) do
        local n = table.getn(list)
        if n > 1 then
            for i = 1, n - 1 do
                local target = list[i]
                for j = i + 1, n do
                    local source = list[j]
                    if target.count < target.maxStack and source.count > 0 then
                        local space = target.maxStack - target.count
                        local transfer = math.min(space, source.count)
                        target.count = target.count + transfer
                        source.count = source.count - transfer

                        table.insert(moves, {
                            fromBag = source.bag,
                            fromSlot = source.slot,
                            toBag = target.bag,
                            toSlot = target.slot,
                            type = "MERGE",
                        })

                        if source.count == 0 then
                            vb[source.bag][source.slot] = nil
                        end
                    end
                end
            end
        end
    end

    return moves
end

-- =========================================================================
-- CATEGORY PRIORITY SORTING MATRIX (Retail WoW Algorithm)
-- =========================================================================

-- Computes target ordering for all slots in regular bags:
-- Hearthstone -> Quest Objects -> Bound Gear -> BoE Gear -> Consumables -> Mats -> White Things -> Trash
function Sort:ComputeSortMoves(vb)
    local regularSlots = {}
    local items = {}

    for bagID = 0, 4 do
        local isSpecial = Categories:GetSpecialContainerType(bagID)
        if not isSpecial then
            local numSlots = GetContainerNumSlots(bagID) or 0
            for slotID = 1, numSlots do
                table.insert(regularSlots, { bag = bagID, slot = slotID })
                local item = vb[bagID][slotID]
                if item then
                    table.insert(items, item)
                end
            end
        end
    end

    -- Sort items according to Retail WoW priority hierarchy
    table.sort(items, function(a, b)
        -- 1. Category Priority (1 = Hearthstone, 2 = Quest, 3 = Bound Gear, 4 = BoE Gear, 5 = Consumables, 6 = Mats, 7 = Utility, 8 = Junk)
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        -- 2. Quality descending (Epic 4 > Rare 3 > Uncommon 2 > Common 1 > Poor 0)
        if a.quality ~= b.quality then
            return a.quality > b.quality
        end
        -- 3. Min Level / Item Level descending
        if a.minLevel ~= b.minLevel then
            return a.minLevel > b.minLevel
        end
        -- 4. Item Name ascending (alphabetical)
        if a.name ~= b.name then
            return a.name < b.name
        end
        -- 5. Count descending
        if a.count ~= b.count then
            return a.count > b.count
        end
        return a.itemID < b.itemID
    end)

    -- Minimum swap cycle solver using vb state
    local numItems = table.getn(items)
    local moves = {}

    for targetIdx = 1, numItems do
        local targetSlot = regularSlots[targetIdx]
        local desiredItem = items[targetIdx]

        local currentInTarget = vb[targetSlot.bag][targetSlot.slot]
        local isAlreadyCorrect = currentInTarget and (currentInTarget == desiredItem)

        if not isAlreadyCorrect then
            -- Find where desiredItem currently resides in vb
            local sBag, sSlot = nil, nil
            for bagID = 0, 4 do
                if not Categories:GetSpecialContainerType(bagID) then
                    local numSlots = GetContainerNumSlots(bagID) or 0
                    for slotID = 1, numSlots do
                        if vb[bagID][slotID] == desiredItem then
                            sBag = bagID
                            sSlot = slotID
                            break
                        end
                    end
                    if sBag then break end
                end
            end

            if sBag and (sBag ~= targetSlot.bag or sSlot ~= targetSlot.slot) then
                local tBag, tSlot = targetSlot.bag, targetSlot.slot

                table.insert(moves, {
                    fromBag = sBag,
                    fromSlot = sSlot,
                    toBag = tBag,
                    toSlot = tSlot,
                    type = "SWAP",
                })

                -- Update simulated state
                local temp = vb[tBag][tSlot]
                vb[tBag][tSlot] = vb[sBag][sSlot]
                vb[sBag][sSlot] = temp
                if vb[tBag][tSlot] then
                    vb[tBag][tSlot].bag = tBag
                    vb[tBag][tSlot].slot = tSlot
                end
                if vb[sBag][sSlot] then
                    vb[sBag][sSlot].bag = sBag
                    vb[sBag][sSlot].slot = sSlot
                end
            end
        end
    end

    return moves
end

-- =========================================================================
-- THROTTLED NON-BLOCKING EXECUTION ENGINE
-- =========================================================================

local function CleanupSort()
    isSorting = false
    moveQueue = {}
    currentMoveIndex = 1
    if sortTickerFrame then
        sortTickerFrame:Hide()
    end
    if PUIBags.OnSortFinished then
        PUIBags:OnSortFinished()
    end
    if PUIBags.UpdateBagSlots then
        PUIBags:UpdateBagSlots()
    end
end

local function StepSortQueue()
    if not isSorting then return end

    -- Safety Timeout
    if (GetTime() - sortStartTime) > MAX_SORT_TIMEOUT then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIBags]: Sort operation timed out.", "ffbb33"))
        CleanupSort()
        return
    end

    -- Cursor Safety: If cursor is holding an item unexpectedly, safely restore to bags
    if CursorHasItem() then
        ClearCursor()
        if CursorHasItem() then
            return
        end
    end

    local totalMoves = table.getn(moveQueue)
    if currentMoveIndex > totalMoves then
        -- All moves complete!
        CleanupSort()
        return
    end

    local move = moveQueue[currentMoveIndex]
    if not move then
        CleanupSort()
        return
    end

    -- Check if from or to slots are currently locked by server
    local _, _, fromLocked = GetContainerItemInfo(move.fromBag, move.fromSlot)
    local _, _, toLocked = GetContainerItemInfo(move.toBag, move.toSlot)

    if fromLocked or toLocked then
        -- Wait for ITEM_LOCK_CHANGED
        return
    end

    -- Execute swap/merge
    PickupContainerItem(move.fromBag, move.fromSlot)
    PickupContainerItem(move.toBag, move.toSlot)
    if CursorHasItem() then
        PickupContainerItem(move.fromBag, move.fromSlot)
    end

    currentMoveIndex = currentMoveIndex + 1

    if PUIBags.OnSortProgress then
        PUIBags:OnSortProgress(currentMoveIndex, totalMoves)
    end
end

function Sort:Start()
    if isSorting then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIBags]: Sorting already in progress...", "ffbb33"))
        return
    end

    -- Clear cursor if holding item
    if CursorHasItem() then
        ClearCursor()
    end

    -- Step 0: Build initial virtual bag state
    local vb = self:BuildVirtualBags()

    -- Step 1: Pack special containers (Ammo -> Quivers/Pouches, Mats -> Specialty Bags)
    local specialMoves = self:PackSpecialContainers(vb)

    -- Step 2: Defragment & consolidate partial stacks
    local mergeMoves = self:ConsolidateStacks(vb)

    -- Step 3: Compute category priority moves (Retail WoW algorithm)
    local sortMoves = self:ComputeSortMoves(vb)

    -- Merge move lists
    moveQueue = {}
    for _, m in ipairs(specialMoves) do table.insert(moveQueue, m) end
    for _, m in ipairs(mergeMoves) do table.insert(moveQueue, m) end
    for _, m in ipairs(sortMoves) do table.insert(moveQueue, m) end

    local totalMoves = table.getn(moveQueue)
    if totalMoves == 0 then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIBags]: Inventory is already organized.", "69ccf0"))
        if PUIBags.UpdateBagSlots then PUIBags:UpdateBagSlots() end
        return
    end

    isSorting = true
    currentMoveIndex = 1
    sortStartTime = GetTime()

    if PUIBags.OnSortStarted then
        PUIBags:OnSortStarted(totalMoves)
    end

    -- Create non-blocking ticker frame
    if not sortTickerFrame then
        sortTickerFrame = CreateFrame("Frame", "PUIBags_SortTickerFrame", UIParent)
        sortTickerFrame:Hide()
        sortTickerFrame.elapsed = 0
        sortTickerFrame:SetScript("OnUpdate", function()
            this.elapsed = (this.elapsed or 0) + arg1
            if this.elapsed >= 0.05 then
                this.elapsed = 0
                StepSortQueue()
            end
        end)
    end

    sortTickerFrame.elapsed = 0
    sortTickerFrame:Show()
end

function Sort:IsSorting()
    return isSorting
end

function Sort:Stop()
    if isSorting then
        CleanupSort()
    end
end
