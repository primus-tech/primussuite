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
       - Throttled per-tick execution with ITEM_LOCK validation to prevent 1.12 packet drops.
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
local MAX_SORT_TIMEOUT = 12.0
local TICK_DELAY = 0.15 -- Vanilla 1.12 server-safe throttle delay

-- Planned Target State: [bagID][slotID] = { key = "...", itemID = ..., count = ... } or nil (empty)
local slotTargets = {}
local totalMismatches = 0
local initialMismatches = 0

-- =========================================================================
-- HELPER FUNCTIONS
-- =========================================================================

local function GetItemKey(link, isBound)
    if not link then return nil end
    local _, _, itemID, enchantID, suffixID, uniqueID = string.find(link, "item:(%d+):(%d*):(%d*):(%d*)")
    return string.format("%s:%s:%s:%s:%s", itemID or 0, enchantID or 0, suffixID or 0, uniqueID or 0, isBound and 1 or 0)
end

local function IsAnySlotLocked()
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        for slotID = 1, numSlots do
            local _, _, locked = GetContainerItemInfo(bagID, slotID)
            if locked then
                return true
            end
        end
    end
    return false
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
                local _, _, itemIDStr = string.find(itemLink, "item:(%d+)")
                local itemID = tonumber(itemIDStr) or 0
                local _, _, _, _, _, sType, maxStack = GetItemInfo(itemLink)

                local key = GetItemKey(itemLink, isBound)
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

    -- 4. Sort Dedicated items
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

    -- 5. Sort General Non-Trash items (Retail WoW Hierarchy)
    table.sort(generalNonTrash, function(a, b)
        -- 1. Category Priority (1 = Hearthstone, 2 = Quest, 3 = Bound Gear, 4 = BoE Gear, 5 = Consumables, 6 = Mats, 7 = White Things)
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

    -- Lock State Check: Wait for server to acknowledge in-flight moves
    if IsAnySlotLocked() then
        return
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
                local _, _, _, _, _, _, isBound = Categories:ClassifyItem(bagID, slotID)
                local key = GetItemKey(link, isBound)
                live[bagID][slotID] = {
                    bag = bagID,
                    slot = slotID,
                    key = key,
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

    -- 2. Phase A: Consolidate Partial Stacks Live
    -- If two slots contain the same key and one has space, merge them
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
                                -- Check if destination target needs this merge
                                local target1 = slotTargets[b1] and slotTargets[b1][s1]
                                local target2 = slotTargets[b2] and slotTargets[b2][s2]

                                if not (target1 and target1.key == item1.key and item1.count == target1.count and target2 and target2.key == item2.key and item2.count == target2.count) then
                                    PickupContainerItem(b2, s2)
                                    PickupContainerItem(b1, s1)
                                    if CursorHasItem() then
                                        PickupContainerItem(b2, s2)
                                    end
                                    return -- Yield for lock
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 3. Phase B: Satisfy Target Slots
    -- Find the first slot that does not hold its desired target item
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        for slotID = 1, numSlots do
            local target = slotTargets[bagID] and slotTargets[bagID][slotID]
            local current = live[bagID][slotID]

            if target then
                -- This slot wants a specific item
                local isCorrect = current and (current.key == target.key) and (current.count == target.count)
                if not isCorrect then
                    -- Find an item in bags matching target.key
                    local srcBag, srcSlot = nil, nil

                    -- Priority: Find exact count match first
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

                    -- Secondary: Find any matching key
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

                    if srcBag and srcSlot then
                        PickupContainerItem(srcBag, srcSlot)
                        PickupContainerItem(bagID, slotID)
                        if CursorHasItem() then
                            PickupContainerItem(srcBag, srcSlot)
                        end
                        return -- Yield for lock
                    end
                end
            end
        end
    end

    -- 4. Phase C: Evacuate Items from Slots Planned as Empty
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        for slotID = 1, numSlots do
            local target = slotTargets[bagID] and slotTargets[bagID][slotID]
            local current = live[bagID][slotID]

            if not target and current then
                -- This slot should be empty, but has an item
                -- Find another slot that should be empty and is currently empty
                for eB = 0, 4 do
                    local eN = GetContainerNumSlots(eB) or 0
                    for eS = 1, eN do
                        local eTarget = slotTargets[eB] and slotTargets[eB][eS]
                        local eCurrent = live[eB][eS]
                        if not eTarget and not eCurrent then
                            PickupContainerItem(bagID, slotID)
                            PickupContainerItem(eB, eS)
                            if CursorHasItem() then
                                PickupContainerItem(bagID, slotID)
                            end
                            return -- Yield for lock
                        end
                    end
                end
            end
        end
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

    if IsAnySlotLocked() then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIBags]: Cannot sort while items are locked.", "ffbb33"))
        return
    end

    -- Plan desired target layout
    self:PlanTargets()

    -- Check if inventory already matches planned layout
    local generalSlots, dedicatedSlots = GetInventorySlots()
    local mismatches = 0

    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        for slotID = 1, numSlots do
            local texture, count = GetContainerItemInfo(bagID, slotID)
            local link = GetContainerItemLink(bagID, slotID)
            local key = nil
            if texture and link then
                local _, _, _, _, _, _, isBound = Categories:ClassifyItem(bagID, slotID)
                key = GetItemKey(link, isBound)
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
