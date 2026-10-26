--[[
    PrimusUI Module: PUIBags (Vanilla 1.12.1 Inventory Sorter)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2 / Interface 11200)

    Sorting Architecture:
    1. Dedicated Inventory (Quivers, Ammo Pouches, Soul/Herb/Mining/Enchanting Bags):
       - Strictly quarantined from general inventory.
       - Dedicated items (ammo, shards, herbs, etc.) fill dedicated slots first with 0 gaps.
       - Overflow spills into general inventory.
    2. General Inventory:
       - Top slots (1..N): Non-trash items sorted by Retail WoW hierarchy (no gaps):
         Hearthstone > Tradeskill Tools > Quest > Bound Gear > BoE Gear > Consumables > Mats > White Things
       - Middle slots: All extra spaces (empty slots) separating non-trash from trash.
       - Bottom slots: Trash loot (grey / quality 0) placed in the last available slots.
    3. Two-Phase Execution Engine:
       - Phase 1: Dedicated bags are packed, satisfied, and sealed.
       - Phase 2: General bags sort exclusively within general slots (special bags completely invisible).
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
local MAX_SORT_TIMEOUT = 14.0
local TICK_DELAY = 0.15 -- Vanilla 1.12 server-safe throttle delay

-- Planned Target State: [bagID][slotID] = { key = "...", itemID = ..., count = ..., meta = ... } or nil (empty)
local slotTargets = {}
local initialMismatches = 0
local cachedBagSpecialTypes = {}

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

-- Partitions bag slots into General Slots and Dedicated Slots
local function GetInventorySlots()
    local generalSlots = {}
    local dedicatedSlots = {} -- [specType] = { {bag=..., slot=...}, ... }
    local bagSpecialTypes = {} -- [bagID] = specType or nil

    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        if numSlots > 0 then
            local specType = Categories:GetSpecialContainerType(bagID)
            bagSpecialTypes[bagID] = specType
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

    cachedBagSpecialTypes = bagSpecialTypes
    return generalSlots, dedicatedSlots, bagSpecialTypes
end

-- Checks if an item can be legally placed into a container bag
local function CanItemGoInBag(bagID, itemLink)
    if not bagID or bagID <= 0 or bagID > 4 then return true end
    local specType = cachedBagSpecialTypes[bagID]
    if not specType then return true end -- Standard bag accepts all items
    if not itemLink then return true end

    local _, _, itemID = string.find(itemLink, "item:(%d+)")
    itemID = tonumber(itemID) or 0
    local name, _, _, _, itemType, itemSubType = GetItemInfo(itemID)
    if not name then
        name, _, _, _, itemType, itemSubType = GetItemInfo(itemLink)
    end
    local itemSpec = Categories:GetItemSpecialContainerType(itemLink, name, itemType, itemSubType, itemID)
    return itemSpec == specType
end

-- Safely executes a two-way item swap between two container slots with quarantine validation
local function DoSwap(sB, sS, dB, dS)
    if sB == dB and sS == dS then return false end

    local _, _, sLocked = GetContainerItemInfo(sB, sS)
    local _, _, dLocked = GetContainerItemInfo(dB, dS)
    if sLocked or dLocked then
        return false -- Pair is locked by server, yield and retry next tick
    end

    -- Strict Quarantine Check: verify destination container accepts source item, and source accepts displaced item
    local sLink = GetContainerItemLink(sB, sS)
    local dLink = GetContainerItemLink(dB, dS)

    if sLink and not CanItemGoInBag(dB, sLink) then
        return false
    end
    if dLink and not CanItemGoInBag(sB, dLink) then
        return false
    end

    ClearCursor()
    PickupContainerItem(sB, sS)
    PickupContainerItem(dB, dS)
    return true
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

                local cCount = tonumber(itemCount) or 1
                if cCount <= 0 then cCount = 1 end
                itemTotals[key] = (itemTotals[key] or 0) + cCount

                local mStack = tonumber(maxStack) or 1
                if mStack <= 0 then mStack = 1 end

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
                        maxStack = mStack,
                    }
                end
            end
        end
    end

    -- 2. Decompose totals into discrete stacks (automatic defragmentation)
    local allStacks = {}
    for key, totalCount in pairs(itemTotals) do
        local meta = itemMeta[key]
        local maxStack = tonumber(meta.maxStack) or 1
        if maxStack <= 0 then maxStack = 1 end
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
-- LIVE EXECUTION ENGINE (TWO-PHASE QUARANTINE)
-- =========================================================================

local function CleanupSort()
    isSorting = false
    idleTicks = 0
    if sortTickerFrame then
        sortTickerFrame:Hide()
    end
    if PUIBags.OnSortFinished then
        pcall(PUIBags.OnSortFinished, PUIBags)
    end
    if PUIBags.UpdateBagSlots then
        pcall(PUIBags.UpdateBagSlots, PUIBags)
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

    local generalSlots, dedicatedSlots, bagSpecialTypes = GetInventorySlots()

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
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIBags]: Bags organized.", "69ccf0"))
        CleanupSort()
        return
    end

    if PUIBags.OnSortProgress then
        local done = math.max(0, initialMismatches - mismatches)
        pcall(PUIBags.OnSortProgress, PUIBags, done, initialMismatches)
    end

    -- =========================================================================
    -- PHASE 1: DEDICATED CONTAINERS (QUIVER / AMMO / SOUL / HERB / MINING / ENCHANT)
    -- =========================================================================
    local dedicatedAllDone = true

    for specType, slots in pairs(dedicatedSlots) do
        local numSlots = table.getn(slots)

        -- 1A. Consolidate partial stacks within dedicated slots of this specType
        for i = 1, numSlots do
            local ref1 = slots[i]
            local item1 = live[ref1.bag][ref1.slot]
            if item1 then
                local _, _, _, _, _, _, maxStack = GetItemInfo(item1.link)
                maxStack = maxStack or 1
                if maxStack > 1 and item1.count < maxStack then
                    for j = i + 1, numSlots do
                        local ref2 = slots[j]
                        local item2 = live[ref2.bag][ref2.slot]
                        if item2 and item2.key == item1.key and item2.count > 0 then
                            local t1 = slotTargets[ref1.bag] and slotTargets[ref1.bag][ref1.slot]
                            local t2 = slotTargets[ref2.bag] and slotTargets[ref2.bag][ref2.slot]
                            local bothDone = t1 and t1.key == item1.key and t1.count == item1.count and t2 and t2.key == item2.key and t2.count == item2.count
                            if not bothDone then
                                if DoSwap(ref2.bag, ref2.slot, ref1.bag, ref1.slot) then
                                    idleTicks = 0
                                    return -- Yield for server lock
                                end
                            end
                        end
                    end
                end
            end
        end

        -- 1B. Satisfy target dedicated slots
        for i = 1, numSlots do
            local slotRef = slots[i]
            local dB, dS = slotRef.bag, slotRef.slot
            local target = slotTargets[dB] and slotTargets[dB][dS]
            local current = live[dB][dS]

            if target then
                local isCorrect = current and (current.key == target.key) and (current.count == target.count)
                if not isCorrect then
                    dedicatedAllDone = false
                    local srcBag, srcSlot = nil, nil

                    -- Priority 1: Pull matching item from general slots (quarantine into dedicated)
                    for _, gRef in ipairs(generalSlots) do
                        local gItem = live[gRef.bag][gRef.slot]
                        if gItem and gItem.key == target.key and gItem.count == target.count then
                            srcBag, srcSlot = gRef.bag, gRef.slot
                            break
                        end
                    end

                    -- Priority 2: Shift matching item from another dedicated slot of the same type
                    if not srcBag then
                        for _, oRef in ipairs(slots) do
                            if not (oRef.bag == dB and oRef.slot == dS) then
                                local oItem = live[oRef.bag][oRef.slot]
                                if oItem and oItem.key == target.key and oItem.count == target.count then
                                    local oTarget = slotTargets[oRef.bag] and slotTargets[oRef.bag][oRef.slot]
                                    if not (oTarget and oTarget.key == oItem.key and oTarget.count == oItem.count) then
                                        srcBag, srcSlot = oRef.bag, oRef.slot
                                        break
                                    end
                                end
                            end
                        end
                    end

                    -- Priority 3: Pull matching item (any count) from general slots
                    if not srcBag then
                        for _, gRef in ipairs(generalSlots) do
                            local gItem = live[gRef.bag][gRef.slot]
                            if gItem and gItem.key == target.key then
                                srcBag, srcSlot = gRef.bag, gRef.slot
                                break
                            end
                        end
                    end

                    -- Priority 4: Shift matching item (any count) from another dedicated slot
                    if not srcBag then
                        for _, oRef in ipairs(slots) do
                            if not (oRef.bag == dB and oRef.slot == dS) then
                                local oItem = live[oRef.bag][oRef.slot]
                                if oItem and oItem.key == target.key then
                                    local oTarget = slotTargets[oRef.bag] and slotTargets[oRef.bag][oRef.slot]
                                    if not (oTarget and oTarget.key == oItem.key and oTarget.count == oItem.count) then
                                        srcBag, srcSlot = oRef.bag, oRef.slot
                                        break
                                    end
                                end
                            end
                        end
                    end

                    if srcBag and srcSlot then
                        if DoSwap(srcBag, srcSlot, dB, dS) then
                            idleTicks = 0
                            return -- Yield for server lock
                        end
                    end
                end
            elseif not target and current then
                -- Dedicated slot is planned to be empty, but currently has an item: evacuate it to general empty slot
                dedicatedAllDone = false
                for _, gRef in ipairs(generalSlots) do
                    local gTarget = slotTargets[gRef.bag] and slotTargets[gRef.bag][gRef.slot]
                    local gCurrent = live[gRef.bag][gRef.slot]
                    if not gTarget and not gCurrent then
                        if DoSwap(dB, dS, gRef.bag, gRef.slot) then
                            idleTicks = 0
                            return -- Yield for server lock
                        end
                    end
                end
            end
        end
    end

    -- If dedicated containers are not yet fully organized, yield and wait for them to finish before touching general
    if not dedicatedAllDone then
        idleTicks = idleTicks + 1
        if idleTicks >= 4 then
            Sort:PlanTargets()
            idleTicks = 0
        end
        return
    end

    -- =========================================================================
    -- PHASE 2: GENERAL INVENTORY ONLY (STRICTLY QUARANTINED FROM SPECIAL BAGS)
    -- =========================================================================
    local numGeneral = table.getn(generalSlots)

    -- 2A. Consolidate partial stacks within general inventory
    for i = 1, numGeneral do
        local ref1 = generalSlots[i]
        local item1 = live[ref1.bag][ref1.slot]
        if item1 then
            local _, _, _, _, _, _, maxStack = GetItemInfo(item1.link)
            maxStack = maxStack or 1
            if maxStack > 1 and item1.count < maxStack then
                for j = i + 1, numGeneral do
                    local ref2 = generalSlots[j]
                    local item2 = live[ref2.bag][ref2.slot]
                    if item2 and item2.key == item1.key and item2.count > 0 then
                        local t1 = slotTargets[ref1.bag] and slotTargets[ref1.bag][ref1.slot]
                        local t2 = slotTargets[ref2.bag] and slotTargets[ref2.bag][ref2.slot]
                        local bothDone = t1 and t1.key == item1.key and t1.count == item1.count and t2 and t2.key == item2.key and t2.count == item2.count
                        if not bothDone then
                            if DoSwap(ref2.bag, ref2.slot, ref1.bag, ref1.slot) then
                                idleTicks = 0
                                return -- Yield for server lock
                            end
                        end
                    end
                end
            end
        end
    end

    -- 2B. Satisfy Target Slots within general inventory
    for i = 1, numGeneral do
        local slotRef = generalSlots[i]
        local bagID, slotID = slotRef.bag, slotRef.slot
        local target = slotTargets[bagID] and slotTargets[bagID][slotID]
        local current = live[bagID][slotID]

        if target then
            local isCorrect = current and (current.key == target.key) and (current.count == target.count)
            if not isCorrect then
                local srcBag, srcSlot = nil, nil

                -- Priority 1: Exact count match within general slots
                for j = 1, numGeneral do
                    local sRef = generalSlots[j]
                    if not (sRef.bag == bagID and sRef.slot == slotID) then
                        local sItem = live[sRef.bag][sRef.slot]
                        if sItem and sItem.key == target.key and sItem.count == target.count then
                            local sTarget = slotTargets[sRef.bag] and slotTargets[sRef.bag][sRef.slot]
                            if not (sTarget and sTarget.key == sItem.key and sTarget.count == sItem.count) then
                                srcBag, srcSlot = sRef.bag, sRef.slot
                                break
                            end
                        end
                    end
                end

                -- Priority 2: Any count match within general slots
                if not srcBag then
                    for j = 1, numGeneral do
                        local sRef = generalSlots[j]
                        if not (sRef.bag == bagID and sRef.slot == slotID) then
                            local sItem = live[sRef.bag][sRef.slot]
                            if sItem and sItem.key == target.key then
                                local sTarget = slotTargets[sRef.bag] and slotTargets[sRef.bag][sRef.slot]
                                if not (sTarget and sTarget.key == sItem.key and sTarget.count == sItem.count) then
                                    srcBag, srcSlot = sRef.bag, sRef.slot
                                    break
                                end
                            end
                        end
                    end
                end

                -- Priority 3: Fallback by itemID within general slots
                if not srcBag then
                    for j = 1, numGeneral do
                        local sRef = generalSlots[j]
                        if not (sRef.bag == bagID and sRef.slot == slotID) then
                            local sItem = live[sRef.bag][sRef.slot]
                            if sItem and sItem.itemID == target.meta.itemID then
                                srcBag, srcSlot = sRef.bag, sRef.slot
                                break
                            end
                        end
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

    -- 2C. Evacuate Displaced Items from general slots planned as empty
    for i = 1, numGeneral do
        local slotRef = generalSlots[i]
        local bagID, slotID = slotRef.bag, slotRef.slot
        local target = slotTargets[bagID] and slotTargets[bagID][slotID]
        local current = live[bagID][slotID]

        if not target and current then
            for j = 1, numGeneral do
                local eRef = generalSlots[j]
                local eTarget = slotTargets[eRef.bag] and slotTargets[eRef.bag][eRef.slot]
                local eCurrent = live[eRef.bag][eRef.slot]
                if not eTarget and not eCurrent then
                    if DoSwap(bagID, slotID, eRef.bag, eRef.slot) then
                        idleTicks = 0
                        return -- Yield for server lock
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
        if (GetTime() - sortStartTime) > MAX_SORT_TIMEOUT then
            CleanupSort()
        else
            if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIBags]: Sorting already in progress...", "ffbb33"))
            end
            return
        end
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
            local cCount = (count and count > 0) and count or 1
            if target and (not key or key ~= target.key or cCount ~= target.count) then
                mismatches = mismatches + 1
            elseif not target and key then
                mismatches = mismatches + 1
            end
        end
    end

    if mismatches == 0 then
        if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIBags]: Inventory is already organized.", "69ccf0"))
        end
        if PUIBags.UpdateBagSlots then pcall(PUIBags.UpdateBagSlots, PUIBags) end
        return
    end

    isSorting = true
    idleTicks = 0
    initialMismatches = mismatches
    sortStartTime = GetTime()

    if PUIBags.OnSortStarted then
        pcall(PUIBags.OnSortStarted, PUIBags, initialMismatches)
    end

    if not sortTickerFrame then
        sortTickerFrame = CreateFrame("Frame", "PUIBags_SortTickerFrame", UIParent)
        sortTickerFrame:Hide()
        sortTickerFrame.elapsed = 0
        sortTickerFrame:SetScript("OnUpdate", function()
            this.elapsed = (this.elapsed or 0) + arg1
            if this.elapsed >= TICK_DELAY then
                this.elapsed = 0
                local status, err = pcall(StepSortEngine)
                if not status and err then
                    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
                        DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[PUIBags Sort Error]: " .. tostring(err) .. "|r")
                    end
                    CleanupSort()
                end
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
