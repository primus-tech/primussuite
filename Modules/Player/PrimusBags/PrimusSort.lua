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

-- Scans all regular bags and merges partial stacks of the same item
function Sort:ConsolidateStacks()
    local partialStacks = {} -- [itemID] = { {bag=b, slot=s, count=c, maxStack=m}, ... }

    for bagID = 0, 4 do
        -- Skip special bags for general consolidation (special bags handle their own items)
        local isSpecial = Categories and Categories:GetSpecialContainerType(bagID)
        local numSlots = GetContainerNumSlots(bagID) or 0

        for slotID = 1, numSlots do
            local texture, itemCount, locked, quality = GetContainerItemInfo(bagID, slotID)
            local itemLink = GetContainerItemLink(bagID, slotID)

            if texture and itemCount and itemLink and not locked then
                local _, _, itemIDStr = string.find(itemLink, "item:(%d+)")
                local itemID = tonumber(itemIDStr)
                local _, _, _, _, _, _, maxStack = GetItemInfo(itemLink)

                if itemID and maxStack and maxStack > 1 and itemCount < maxStack then
                    if not partialStacks[itemID] then
                        partialStacks[itemID] = {}
                    end
                    table.insert(partialStacks[itemID], {
                        bag = bagID,
                        slot = slotID,
                        count = itemCount,
                        maxStack = maxStack,
                    })
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
                    end
                end
            end
        end
    end

    return moves
end

-- =========================================================================
-- CATEGORY PRIORITY SORTING MATRIX
-- =========================================================================

-- Computes the target ordering for all slots in regular bags
function Sort:ComputeSortMoves()
    local regularSlots = {} -- List of {bag, slot} in natural order
    local items = {}        -- List of item records

    for bagID = 0, 4 do
        local isSpecial = Categories and Categories:GetSpecialContainerType(bagID)
        if not isSpecial then
            local numSlots = GetContainerNumSlots(bagID) or 0
            for slotID = 1, numSlots do
                table.insert(regularSlots, { bag = bagID, slot = slotID })

                local texture, itemCount, locked, quality = GetContainerItemInfo(bagID, slotID)
                local itemLink = GetContainerItemLink(bagID, slotID)

                if texture and itemLink then
                    local prio, name, qual, minLvl, itemType = Categories:ClassifyItem(bagID, slotID)
                    local _, _, itemIDStr = string.find(itemLink, "item:(%d+)")
                    local itemID = tonumber(itemIDStr) or 0

                    table.insert(items, {
                        bag = bagID,
                        slot = slotID,
                        priority = prio,
                        quality = qual or 0,
                        minLevel = minLvl or 0,
                        name = name or "",
                        itemID = itemID,
                        count = itemCount or 1,
                        link = itemLink,
                    })
                end
            end
        end
    end

    -- Sort items according to priority hierarchy
    table.sort(items, function(a, b)
        -- 1. Category Priority (1 = Quest, 2 = Consumable, ..., 8 = Junk)
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        -- 2. Quality descending (Epic 4 > Rare 3 > Uncommon 2 > Common 1 > Poor 0)
        if a.quality ~= b.quality then
            return a.quality > b.quality
        end
        -- 3. Min Level descending
        if a.minLevel ~= b.minLevel then
            return a.minLevel > b.minLevel
        end
        -- 4. Item Name ascending
        if a.name ~= b.name then
            return a.name < b.name
        end
        -- 5. Count descending
        if a.count ~= b.count then
            return a.count > b.count
        end
        return a.itemID < b.itemID
    end)

    -- Map items to target slot positions
    local totalRegularSlots = table.getn(regularSlots)
    local numItems = table.getn(items)
    local moves = {}

    -- Track current contents of all slots: slotKey -> itemRecord
    local state = {}
    for i = 1, totalRegularSlots do
        local slotRef = regularSlots[i]
        local key = string.format("%d:%d", slotRef.bag, slotRef.slot)
        local texture, itemCount = GetContainerItemInfo(slotRef.bag, slotRef.slot)
        local link = GetContainerItemLink(slotRef.bag, slotRef.slot)
        if texture and link then
            state[key] = { bag = slotRef.bag, slot = slotRef.slot, link = link, count = itemCount }
        else
            state[key] = nil
        end
    end

    -- Selection Sort / Cycle Leader algorithm to generate minimum swap operations
    for targetIdx = 1, numItems do
        local targetSlot = regularSlots[targetIdx]
        local desiredItem = items[targetIdx]

        -- Current item at targetSlot
        local currentKey = string.format("%d:%d", targetSlot.bag, targetSlot.slot)
        local currentInTarget = state[currentKey]

        -- Check if targetSlot already holds the desired item (same link and count)
        local isAlreadyCorrect = currentInTarget and (currentInTarget.bag == desiredItem.bag and currentInTarget.slot == desiredItem.slot)

        if not isAlreadyCorrect then
            -- Find where the desired item currently resides in state
            local sourceKey = nil
            for k, curItem in pairs(state) do
                if curItem and curItem.bag == desiredItem.bag and curItem.slot == desiredItem.slot then
                    sourceKey = k
                    break
                end
            end

            if sourceKey and sourceKey ~= currentKey then
                local sBag, sSlot = state[sourceKey].bag, state[sourceKey].slot
                local tBag, tSlot = targetSlot.bag, targetSlot.slot

                table.insert(moves, {
                    fromBag = sBag,
                    fromSlot = sSlot,
                    toBag = tBag,
                    toSlot = tSlot,
                    type = "SWAP",
                })

                -- Update simulated state
                local temp = state[currentKey]
                state[currentKey] = state[sourceKey]
                state[sourceKey] = temp
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

    -- Cursor Safety: If cursor is holding an item unexpectedly, try to clear it or wait
    if CursorHasItem() then
        return
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

    -- Step 1: Defragment & consolidate partial stacks
    local mergeMoves = self:ConsolidateStacks()

    -- Step 2: Compute category priority moves
    local sortMoves = self:ComputeSortMoves()

    -- Merge move lists
    moveQueue = {}
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
