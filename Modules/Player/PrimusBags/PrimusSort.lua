--[[
    PrimusUI Module: PUIBags (Vanilla 1.12.1 Inventory Sorter)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2 / Interface 11200)

    Sorting Architecture:
    1. Dedicated Inventory (Quivers, Ammo Pouches, Soul/Herb/Mining/Enchanting Bags):
       - Dedicated items (ammo, shards, herbs, etc.) fill dedicated slots first with 0 gaps.
       - Overflow spills into general inventory.
    2. General Inventory:
       - Top slots (1..N): Non-trash items sorted by Retail WoW hierarchy (no gaps):
         Hearthstone > Quest > Bound Gear > BoE Gear > Consumables > Mats > White Things
       - Middle slots: All extra spaces (empty slots) separating non-trash from trash.
       - Bottom slots: Trash loot (grey / quality 0) placed in the last available slots.
    3. Engine:
       - Target-driven live state machine.
       - Pairwise slot lock validation (no global lock freezes).
       - Anti-stall fallback re-planner so it can NEVER hang or freeze.
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

local isSorting = false
local sortTickerFrame = nil
local sortStartTime = 0
local idleTicks = 0
local MAX_SORT_TIMEOUT = 12.0
local TICK_DELAY = 0.15 -- Vanilla 1.12 server-safe throttle delay

-- Planned Target State: [bagID][slotID] = { key = "...", itemID = ..., count = ... } or nil (empty)
local slotTargets = {}
local initialMismatches = 0

-- =========================================================================
-- HELPER FUNCTIONS
-- =========================================================================

-- Unified item fingerprint for consistent matching everywhere
local function GetSlotItemKey(bagID, slotID)
    local link = GetContainerItemLink(bagID, slotID)
    if not link then return nil, false, 0 end
    local prio, name, qual, minLvl, iType, isBound = Categories:ClassifyItem(bagID, slotID)
    local _, _, itemID, _, suffixID = string.find(link, "item:(%d+):(%d*):(%d*)")
    local boundFlag = (isBound == true) and 1 or 0
    local key = string.format("%s:%s:%d", itemID or 0, suffixID or 0, boundFlag)
    return key, (isBound == true), tonumber(itemID) or 0
end

-- Safely executes a two-way item swap between two container slots
local function DoSwap(sB, sS, dB, dS)
    local _, _, sLocked = GetContainerItemInfo(sB, sS)
    local _, _, dLocked = GetContainerItemInfo(dB, dS)
    if sLocked or dLocked then
        return false -- Pair is locked by server, yield and retry next tick
    end

    ClearCursor()
    PickupContainerItem(sB, sS)
    PickupContainerItem(dB, dS)
    if CursorHasItem() then
        PickupContainerItem(sB, sS)
    end
    if CursorHasItem() then
        ClearCursor()
    end
    return true
end

-- Partitions bag slots into General Slots and Dedicated Slots
local function GetInventorySlots()
    local generalSlots = {}
    local dedicatedSlots = {} -- [specType] = { {bag=..., slot=...}, ... }

    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        if numSlots > 0 then
            local specType = Categories:GetSpecialContainerType(bagID)
            if specType then
                if not dedicatedSlots[specType] then
                    dedicatedSlots[specType] = {}
                end
                for slotID = 1, numSlots do
                    table.insert(dedicatedSlots[specType], { bag = bagID, slot = slotID })
                end
            else
                for slotID = 1, numSlots do
                    table.insert(generalSlots, { bag = bagID, slot = slotID })
                end
            end
        end
    end

    return generalSlots, dedicatedSlots
end

-- =========================================================================
-- TARGET PLANNING ENGINE
-- =========================================================================

function Sort:PlanTargets()
    slotTargets = {}
    for bagID = 0, 4 do
        slotTargets[bagID] = {}
    end

    local generalSlots, dedicatedSlots = GetInventorySlots()

    -- 1. Identify all items currently across all bags
    local itemTotals = {} -- [key] = totalCount
    local itemMeta = {}   -- [key] = metadata record

    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        for slotID = 1, numSlots do
            local texture, itemCount = GetContainerItemInfo(bagID, slotID)
            local itemLink = GetContainerItemLink(bagID, slotID)

            if texture and itemLink then
                local prio, name, qual, minLvl, iType, isBound = Categories:ClassifyItem(bagID, slotID)
                local _, _, _, _, _, sType, maxStack = GetItemInfo(itemLink)
                local key, _, itemID = GetSlotItemKey(bagID, slotID)

                itemTotals[key] = (itemTotals[key] or 0) + (itemCount or 1)

                if not itemMeta[key] then
                    itemMeta[key] = {
                        key = key,
                        itemID = itemID,
                        name = name or ("Item #" .. itemID),
                        quality = qual or 0,
                        minLevel = minLvl or 0,
                        itemType = iType or "",
                        itemSubType = sType or "",
                        priority = prio,
                        isBound = isBound,
                        link = itemLink,
                        maxStack = maxStack or 1,
                    }
                end
            end
        end
    end

    -- 2. Decompose totals into discrete stacks (automatic defragmentation)
    local allStacks = {}
    for key, totalCount in pairs(itemTotals) do
        local meta = itemMeta[key]
        local maxStack = meta.maxStack or 1
        local remaining = totalCount

        while remaining > 0 do
            local stackCount = math.min(remaining, maxStack)
            table.insert(allStacks, {
                key = key,
                meta = meta,
                count = stackCount,
            })
            remaining = remaining - stackCount
        end
    end

    -- 3. Route stacks to Dedicated Containers vs General Inventory
    local dedicatedAssignments = {} -- [specType] = list of stacks
    local generalNonTrash = {}       -- list of stacks (Quality > 0)
    local generalTrash = {}          -- list of stacks (Quality == 0)

    for _, stack in ipairs(allStacks) do
        local meta = stack.meta
        local specType = Categories:GetItemSpecialContainerType(
            meta.link, meta.name, meta.itemType, meta.itemSubType, meta.itemID
        )

        local assignedToDedicated = false
        if specType and dedicatedSlots[specType] then
            if not dedicatedAssignments[specType] then
                dedicatedAssignments[specType] = {}
            end
            local currentCount = table.getn(dedicatedAssignments[specType])
            local maxCapacity = table.getn(dedicatedSlots[specType])

            if currentCount < maxCapacity then
                table.insert(dedicatedAssignments[specType], stack)
                assignedToDedicated = true
            end
        end

        if not assignedToDedicated then
            if meta.quality == 0 then
                table.insert(generalTrash, stack)
            else
                table.insert(generalNonTrash, stack)
            end
        end
    end

    -- 4. Sort Dedicated items (by MinLevel desc, Name asc, Count desc)
    for specType, stacks in pairs(dedicatedAssignments) do
        table.sort(stacks, function(a, b)
            if a.meta.minLevel ~= b.meta.minLevel then
                return a.meta.minLevel > b.meta.minLevel
            end
            if a.meta.name ~= b.meta.name then
                return a.meta.name < b.meta.name
            end
            return a.count > b.count
        end)
    end

    -- 5. Sort General Non-Trash items (Retail WoW Hierarchy with Tradeskill Tools)
    table.sort(generalNonTrash, function(a, b)
        -- 1. Category Priority (1 = Hearthstone, 2 = Tools, 3 = Quest, 4 = Bound Gear, 5 = BoE Gear, 6 = Consumables, 7 = Mats, 8 = White Things)
        if a.meta.priority ~= b.meta.priority then
            return a.meta.priority < b.meta.priority
        end
        -- 2. Quality descending (Epic > Rare > Uncommon > Common)
        if a.meta.quality ~= b.meta.quality then
            return a.meta.quality > b.meta.quality
        end
        -- 3. Item Level / Min Level descending
        if a.meta.minLevel ~= b.meta.minLevel then
            return a.meta.minLevel > b.meta.minLevel
        end
        -- 4. Item Name ascending (alphabetical)
        if a.meta.name ~= b.meta.name then
            return a.meta.name < b.meta.name
        end
        -- 5. Stack Count descending
        if a.count ~= b.count then
            return a.count > b.count
        end
        return a.meta.itemID < b.meta.itemID
    end)

    -- 6. Sort General Trash items
    table.sort(generalTrash, function(a, b)
        if a.meta.minLevel ~= b.meta.minLevel then
            return a.meta.minLevel > b.meta.minLevel
        end
        if a.meta.name ~= b.meta.name then
            return a.meta.name < b.meta.name
        end
        if a.count ~= b.count then
            return a.count > b.count
        end
        return a.meta.itemID < b.meta.itemID
    end)

    -- 7. Assign Dedicated Slots (0 gaps)
    for specType, slots in pairs(dedicatedSlots) do
        local stacks = dedicatedAssignments[specType] or {}
        local numAssigned = table.getn(stacks)
        for i, slotRef in ipairs(slots) do
            if i <= numAssigned then
                slotTargets[slotRef.bag][slotRef.slot] = stacks[i]
            else
                slotTargets[slotRef.bag][slotRef.slot] = nil
            end
        end
    end

    -- 8. Assign General Slots (Non-Trash -> Extra Spaces -> Trash at the end)
    local totalGeneral = table.getn(generalSlots)
    local numNonTrash = table.getn(generalNonTrash)
    local numTrash = table.getn(generalTrash)
    local extraSpaces = totalGeneral - (numNonTrash + numTrash)
    if extraSpaces < 0 then extraSpaces = 0 end

    -- A. Top Slots: Non-trash items with no gaps
    for i = 1, numNonTrash do
        if i <= totalGeneral then
            local slotRef = generalSlots[i]
            slotTargets[slotRef.bag][slotRef.slot] = generalNonTrash[i]
        end
    end

    -- B. Middle Slots: Extra spaces separating non-trash from trash
    for i = 1, extraSpaces do
        local slotIdx = numNonTrash + i
        if slotIdx <= totalGeneral then
            local slotRef = generalSlots[slotIdx]
            slotTargets[slotRef.bag][slotRef.slot] = nil
        end
    end

    -- C. Bottom Slots: Trash loot in the last available slots
    for t = 1, numTrash do
        local slotIdx = (totalGeneral - numTrash) + t
        if slotIdx > numNonTrash and slotIdx <= totalGeneral then
            local slotRef = generalSlots[slotIdx]
            slotTargets[slotRef.bag][slotRef.slot] = generalTrash[t]
        end
    end
end

-- =========================================================================
-- LIVE EXECUTION ENGINE
-- =========================================================================

local function CleanupSort()
    isSorting = false
    idleTicks = 0
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

-- Checks live inventory against planned targets and executes at most ONE move
local function StepSortEngine()
    if not isSorting then return end

    -- Safety Timeout
    if (GetTime() - sortStartTime) > MAX_SORT_TIMEOUT then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIBags]: Sort operation timed out.", "ffbb33"))
        CleanupSort()
        return
    end

    -- Cursor Safety: Clear cursor if unexpectedly holding an item
    if CursorHasItem() then
        ClearCursor()
        if CursorHasItem() then
            return
        end
    end

    -- 1. Scan Live Inventory State
    local live = {}
    local mismatches = 0

    for bagID = 0, 4 do
        live[bagID] = {}
        local numSlots = GetContainerNumSlots(bagID) or 0
        for slotID = 1, numSlots do
            local texture, count = GetContainerItemInfo(bagID, slotID)
            local link = GetContainerItemLink(bagID, slotID)

            if texture and link then
                local key, isBound, itemID = GetSlotItemKey(bagID, slotID)
                live[bagID][slotID] = {
                    bag = bagID,
                    slot = slotID,
                    key = key,
                    itemID = itemID,
                    count = count or 1,
                    link = link,
                }
            else
                live[bagID][slotID] = nil
            end

            -- Compare live against planned target
            local target = slotTargets[bagID] and slotTargets[bagID][slotID]
            local current = live[bagID][slotID]

            if target and (not current or current.key ~= target.key or current.count ~= target.count) then
                mismatches = mismatches + 1
            elseif not target and current then
                mismatches = mismatches + 1
            end
        end
    end

    if initialMismatches == 0 then
        initialMismatches = math.max(mismatches, 1)
    end

    if mismatches == 0 then
        -- All slots fully match their target!
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIBags]: Bags organized.", "69ccf0"))
        CleanupSort()
        return
    end

    if PUIBags.OnSortProgress then
        local done = math.max(0, initialMismatches - mismatches)
        PUIBags:OnSortProgress(done, initialMismatches)
    end

    local movedThisTick = false

    -- 2. Phase A: Consolidate Partial Stacks Live
    for b1 = 0, 4 do
        local n1 = GetContainerNumSlots(b1) or 0
        for s1 = 1, n1 do
            local item1 = live[b1][s1]
            if item1 then
                local _, _, _, _, _, _, maxStack = GetItemInfo(item1.link)
                maxStack = maxStack or 1

                if maxStack > 1 and item1.count < maxStack then
                    for b2 = b1, 4 do
                        local n2 = GetContainerNumSlots(b2) or 0
                        local startS2 = (b1 == b2) and (s1 + 1) or 1
                        for s2 = startS2, n2 do
                            local item2 = live[b2][s2]
                            if item2 and item2.key == item1.key and item2.count > 0 then
                                local target1 = slotTargets[b1] and slotTargets[b1][s1]
                                local target2 = slotTargets[b2] and slotTargets[b2][s2]

                                local bothTargetCorrect = target1 and target1.key == item1.key and item1.count == target1.count and target2 and target2.key == item2.key and item2.count == target2.count
                                if not bothTargetCorrect then
                                    if DoSwap(b2, s2, b1, s1) then
                                        idleTicks = 0
                                        return -- Yield for server lock
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 3. Phase B: Satisfy Target Slots
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        for slotID = 1, numSlots do
            local target = slotTargets[bagID] and slotTargets[bagID][slotID]
            local current = live[bagID][slotID]

            if target then
                local isCorrect = current and (current.key == target.key) and (current.count == target.count)
                if not isCorrect then
                    local srcBag, srcSlot = nil, nil

                    -- Priority 1: Find matching key with exact count
                    for sB = 0, 4 do
                        local sN = GetContainerNumSlots(sB) or 0
                        for sS = 1, sN do
                            if not (sB == bagID and sS == slotID) then
                                local sItem = live[sB][sS]
                                if sItem and sItem.key == target.key and sItem.count == target.count then
                                    local sTarget = slotTargets[sB] and slotTargets[sB][sS]
                                    if not (sTarget and sTarget.key == sItem.key and sTarget.count == sItem.count) then
                                        srcBag, srcSlot = sB, sS
                                        break
                                    end
                                end
                            end
                        end
                        if srcBag then break end
                    end

                    -- Priority 2: Find matching key with any count
                    if not srcBag then
                        for sB = 0, 4 do
                            local sN = GetContainerNumSlots(sB) or 0
                            for sS = 1, sN do
                                if not (sB == bagID and sS == slotID) then
                                    local sItem = live[sB][sS]
                                    if sItem and sItem.key == target.key then
                                        local sTarget = slotTargets[sB] and slotTargets[sB][sS]
                                        if not (sTarget and sTarget.key == sItem.key and sTarget.count == sItem.count) then
                                            srcBag, srcSlot = sB, sS
                                            break
                                        end
                                    end
                                end
                            end
                            if srcBag then break end
                        end
                    end

                    -- Priority 3: Fallback by itemID if key had random suffix variation
                    if not srcBag then
                        for sB = 0, 4 do
                            local sN = GetContainerNumSlots(sB) or 0
                            for sS = 1, sN do
                                if not (sB == bagID and sS == slotID) then
                                    local sItem = live[sB][sS]
                                    if sItem and sItem.itemID == target.meta.itemID then
                                        srcBag, srcSlot = sB, sS
                                        break
                                    end
                                end
                            end
                            if srcBag then break end
                        end
                    end

                    if srcBag and srcSlot then
                        if DoSwap(srcBag, srcSlot, bagID, slotID) then
                            idleTicks = 0
                            return -- Yield for server lock
                        end
                    end
                end
            end
        end
    end

    -- 4. Phase C: Evacuate Displaced Items from Slots Planned as Empty
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        for slotID = 1, numSlots do
            local target = slotTargets[bagID] and slotTargets[bagID][slotID]
            local current = live[bagID][slotID]

            if not target and current then
                for eB = 0, 4 do
                    local eN = GetContainerNumSlots(eB) or 0
                    for eS = 1, eN do
                        local eTarget = slotTargets[eB] and slotTargets[eB][eS]
                        local eCurrent = live[eB][eS]
                        if not eTarget and not eCurrent then
                            if DoSwap(bagID, slotID, eB, eS) then
                                idleTicks = 0
                                return -- Yield for server lock
                            end
                        end
                    end
                end
            end
        end
    end

    -- Anti-Stall Guard: If no valid move was made this tick, increment idle counter
    idleTicks = idleTicks + 1
    if idleTicks >= 4 then
        -- Re-plan targets against live state to resolve any unexpected item count shifts
        Sort:PlanTargets()
        idleTicks = 0
    end
end

-- =========================================================================
-- PUBLIC INTERFACE
-- =========================================================================

function Sort:Start()
    if isSorting then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIBags]: Sorting already in progress...", "ffbb33"))
        return
    end

    if CursorHasItem() then
        ClearCursor()
    end

    -- Plan desired target layout
    self:PlanTargets()

    -- Check if inventory already matches planned layout
    local mismatches = 0
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        for slotID = 1, numSlots do
            local texture, count = GetContainerItemInfo(bagID, slotID)
            local link = GetContainerItemLink(bagID, slotID)
            local key = nil
            if texture and link then
                key = GetSlotItemKey(bagID, slotID)
            end

            local target = slotTargets[bagID] and slotTargets[bagID][slotID]
            if target and (not key or key ~= target.key or count ~= target.count) then
                mismatches = mismatches + 1
            elseif not target and key then
                mismatches = mismatches + 1
            end
        end
    end

    if mismatches == 0 then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIBags]: Inventory is already organized.", "69ccf0"))
        if PUIBags.UpdateBagSlots then PUIBags:UpdateBagSlots() end
        return
    end

    isSorting = true
    idleTicks = 0
    initialMismatches = mismatches
    sortStartTime = GetTime()

    if PUIBags.OnSortStarted then
        PUIBags:OnSortStarted(initialMismatches)
    end

    if not sortTickerFrame then
        sortTickerFrame = CreateFrame("Frame", "PUIBags_SortTickerFrame", UIParent)
        sortTickerFrame:Hide()
        sortTickerFrame.elapsed = 0
        sortTickerFrame:SetScript("OnUpdate", function()
            this.elapsed = (this.elapsed or 0) + arg1
            if this.elapsed >= TICK_DELAY then
                this.elapsed = 0
                StepSortEngine()
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
