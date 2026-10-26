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
       - Key-based matching: Slots holding the desired item type are satisfied and NEVER swapped with identical items.
       - Source protection: A slot that is already satisfied is never used as a source for other moves.
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

-- Planned Target State: [bagID][slotID] = item record or nil (empty)
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
    if not itemLink then return true end -- Empty slot can always be displaced

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
-- TARGET PLANNING ENGINE (REAL ITEMS ONLY, NO SYNTHETIC CHOPPING)
-- =========================================================================

function Sort:PlanTargets()
    slotTargets = {}
    for bagID = 0, 4 do
        slotTargets[bagID] = {}
    end

    local generalSlots, dedicatedSlots = GetInventorySlots()

    -- 1. Scan and collect REAL items currently across all bags
    local realItems = {}
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        for slotID = 1, numSlots do
            local texture, count = GetContainerItemInfo(bagID, slotID)
            local link = GetContainerItemLink(bagID, slotID)

            if texture and link then
                local prio, name, qual, minLvl, iType, isBound = Categories:ClassifyItem(bagID, slotID)
                local key, isBnd, itemID = GetSlotItemKey(bagID, slotID)
                local _, _, _, _, _, sType, maxStack = GetItemInfo(link)
                if not sType then
                    _, _, _, _, _, sType, maxStack = GetItemInfo(itemID)
                end

                local cCount = tonumber(count) or 1
                if cCount <= 0 then cCount = 1 end

                table.insert(realItems, {
                    key = key,
                    itemID = itemID,
                    name = name or ("Item #" .. itemID),
                    quality = qual or 0,
                    minLevel = minLvl or 0,
                    itemType = iType or "",
                    itemSubType = sType or "",
                    priority = prio,
                    isBound = (isBound == true) or (isBnd == true),
                    link = link,
                    count = cCount,
                    maxStack = tonumber(maxStack) or 1,
                })
            end
        end
    end

    -- 2. Route items to Dedicated Containers vs General Inventory
    local dedicatedAssignments = {} -- [specType] = list of items
    local generalNonTrash = {}       -- list of items (Quality > 0)
    local generalTrash = {}          -- list of items (Quality == 0)

    for _, item in ipairs(realItems) do
        local specType = Categories:GetItemSpecialContainerType(
            item.link, item.name, item.itemType, item.itemSubType, item.itemID
        )

        local assignedToDedicated = false
        if specType and dedicatedSlots[specType] then
            if not dedicatedAssignments[specType] then
                dedicatedAssignments[specType] = {}
            end
            local currentCount = table.getn(dedicatedAssignments[specType])
            local maxCapacity = table.getn(dedicatedSlots[specType])

            if currentCount < maxCapacity then
                table.insert(dedicatedAssignments[specType], item)
                assignedToDedicated = true
            end
        end

        if not assignedToDedicated then
            if item.quality == 0 then
                table.insert(generalTrash, item)
            else
                table.insert(generalNonTrash, item)
            end
        end
    end

    -- 3. Sort Dedicated items (by MinLevel desc, Name asc, Count desc, ItemID asc)
    for specType, items in pairs(dedicatedAssignments) do
        table.sort(items, function(a, b)
            if a.minLevel ~= b.minLevel then
                return a.minLevel > b.minLevel
            end
            if a.name ~= b.name then
                return a.name < b.name
            end
            if a.count ~= b.count then
                return a.count > b.count
            end
            if a.itemID ~= b.itemID then
                return a.itemID < b.itemID
            end
            return false
        end)
    end

    -- 4. Sort General Non-Trash items (Retail WoW Hierarchy)
    table.sort(generalNonTrash, function(a, b)
        -- 1. Category Priority (1 = Hearthstone, 2 = Tools, 3 = Quest, 4 = Bound Gear, 5 = BoE Gear, 6 = Consumables, 7 = Mats, 8 = White Things)
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        -- 2. Quality descending (Epic > Rare > Uncommon > Common)
        if a.quality ~= b.quality then
            return a.quality > b.quality
        end
        -- 3. Item Level / Min Level descending
        if a.minLevel ~= b.minLevel then
            return a.minLevel > b.minLevel
        end
        -- 4. Item Name ascending (alphabetical)
        if a.name ~= b.name then
            return a.name < b.name
        end
        -- 5. Stack Count descending
        if a.count ~= b.count then
            return a.count > b.count
        end
        if a.itemID ~= b.itemID then
            return a.itemID < b.itemID
        end
        return false
    end)

    -- 5. Sort General Trash items
    table.sort(generalTrash, function(a, b)
        if a.minLevel ~= b.minLevel then
            return a.minLevel > b.minLevel
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
        if a.count ~= b.count then
            return a.count > b.count
        end
        if a.itemID ~= b.itemID then
            return a.itemID < b.itemID
        end
        return false
    end)

    -- 6. Assign Dedicated Slots (0 gaps)
    for specType, slots in pairs(dedicatedSlots) do
        local items = dedicatedAssignments[specType] or {}
        local numAssigned = table.getn(items)
        for i, slotRef in ipairs(slots) do
            if i <= numAssigned then
                slotTargets[slotRef.bag][slotRef.slot] = items[i]
            else
                slotTargets[slotRef.bag][slotRef.slot] = nil
            end
        end
    end

    -- 7. Assign General Slots (Non-Trash -> Middle Extra Spaces -> Trash at the end)
    local totalGeneral = table.getn(generalSlots)
    local numNonTrash = table.getn(generalNonTrash)
    local numTrash = table.getn(generalTrash)
    local extraSpaces = totalGeneral - (numNonTrash + numTrash)
    if extraSpaces < 0 then extraSpaces = 0 end

    -- A. Top Slots: Non-trash items (1..numNonTrash)
    for i = 1, numNonTrash do
        if i <= totalGeneral then
            local slotRef = generalSlots[i]
            slotTargets[slotRef.bag][slotRef.slot] = generalNonTrash[i]
        end
    end

    -- B. Middle Slots: Extra spaces (nil) separating non-trash from trash
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
-- LIVE EXECUTION ENGINE (TWO-PHASE QUARANTINE, KEY-BASED STABILITY)
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

-- Checks live inventory against planned targets and executes at most ONE move per tick
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

            -- Compare live against planned target (KEY-BASED: same item key is considered satisfied)
            local target = slotTargets[bagID] and slotTargets[bagID][slotID]
            local current = live[bagID][slotID]

            if target and (not current or current.key ~= target.key) then
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
        if done > initialMismatches then done = initialMismatches end
        pcall(PUIBags.OnSortProgress, PUIBags, done, initialMismatches)
    end

    -- =========================================================================
    -- PARTIAL STACK CONSOLIDATION (ONLY MERGES WHEN BOTH SLOTS ARE PARTIAL)
    -- =========================================================================
    local function TryConsolidate(slots)
        local n = table.getn(slots)
        for i = 1, n do
            local r1 = slots[i]
            local it1 = live[r1.bag][r1.slot]
            if it1 then
                local _, _, _, _, _, _, maxStack = GetItemInfo(it1.link)
                maxStack = maxStack or 1
                if maxStack > 1 and it1.count < maxStack then
                    for j = i + 1, n do
                        local r2 = slots[j]
                        local it2 = live[r2.bag][r2.slot]
                        -- Both must have identical item, both must be partial stacks (< maxStack)
                        if it2 and it2.key == it1.key and it2.count < maxStack and it2.count > 0 then
                            if DoSwap(r2.bag, r2.slot, r1.bag, r1.slot) then
                                idleTicks = 0
                                Sort:PlanTargets()
                                return true
                            end
                        end
                    end
                end
            end
        end
        return false
    end

    -- Try consolidate within dedicated bags
    for specType, slots in pairs(dedicatedSlots) do
        if TryConsolidate(slots) then return end
    end

    -- Try consolidate within general bags
    if TryConsolidate(generalSlots) then return end

    -- =========================================================================
    -- PHASE 1: DEDICATED CONTAINERS (QUIVER / AMMO / SOUL / HERB / MINING / ENCHANT)
    -- =========================================================================
    local dedicatedAllDone = true

    for specType, slots in pairs(dedicatedSlots) do
        local numSlots = table.getn(slots)

        for i = 1, numSlots do
            local slotRef = slots[i]
            local dB, dS = slotRef.bag, slotRef.slot
            local target = slotTargets[dB] and slotTargets[dB][dS]
            local current = live[dB][dS]

            if target then
                -- Key-based satisfaction: if slot already holds the desired item, it is satisfied!
                local isCorrect = current and (current.key == target.key)
                if not isCorrect then
                    dedicatedAllDone = false
                    local srcBag, srcSlot = nil, nil

                    -- Priority 1: Pull matching item from general slots (quarantine into dedicated)
                    for _, gRef in ipairs(generalSlots) do
                        local gItem = live[gRef.bag][gRef.slot]
                        if gItem and gItem.key == target.key then
                            srcBag, srcSlot = gRef.bag, gRef.slot
                            break
                        end
                    end

                    -- Priority 2: Shift matching item from another dedicated slot that is NOT already satisfied
                    if not srcBag then
                        for _, oRef in ipairs(slots) do
                            if not (oRef.bag == dB and oRef.slot == dS) then
                                local oItem = live[oRef.bag][oRef.slot]
                                if oItem and oItem.key == target.key then
                                    local oTarget = slotTargets[oRef.bag] and slotTargets[oRef.bag][oRef.slot]
                                    -- SOURCE PROTECTION: Only use oRef if it is NOT already satisfied!
                                    if not (oTarget and oTarget.key == oItem.key) then
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

    for i = 1, numGeneral do
        local slotRef = generalSlots[i]
        local bagID, slotID = slotRef.bag, slotRef.slot
        local target = slotTargets[bagID] and slotTargets[bagID][slotID]
        local current = live[bagID][slotID]

        if target then
            -- Key-based satisfaction: if slot already holds desired item, IT IS SATISFIED!
            local isCorrect = current and (current.key == target.key)
            if not isCorrect then
                local srcBag, srcSlot = nil, nil

                -- Find a source slot holding target.key that is NOT already satisfied
                for j = 1, numGeneral do
                    local sRef = generalSlots[j]
                    if not (sRef.bag == bagID and sRef.slot == slotID) then
                        local sItem = live[sRef.bag][sRef.slot]
                        if sItem and sItem.key == target.key then
                            local sTarget = slotTargets[sRef.bag] and slotTargets[sRef.bag][sRef.slot]
                            -- SOURCE PROTECTION: Never steal from a slot that is already matching its target!
                            if not (sTarget and sTarget.key == sItem.key) then
                                srcBag, srcSlot = sRef.bag, sRef.slot
                                break
                            end
                        end
                    end
                end

                -- Fallback: If no exact key found (e.g. suffix variance), match by itemID
                if not srcBag then
                    for j = 1, numGeneral do
                        local sRef = generalSlots[j]
                        if not (sRef.bag == bagID and sRef.slot == slotID) then
                            local sItem = live[sRef.bag][sRef.slot]
                            if sItem and sItem.itemID == target.itemID then
                                local sTarget = slotTargets[sRef.bag] and slotTargets[sRef.bag][sRef.slot]
                                if not (sTarget and sTarget.itemID == sItem.itemID) then
                                    srcBag, srcSlot = sRef.bag, sRef.slot
                                    break
                                end
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

    -- Anti-Stall Guard: If no valid move was made this tick, increment idle counter
    idleTicks = idleTicks + 1
    if idleTicks >= 4 then
        -- Re-plan targets against live state to resolve any server discrepancies
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

    -- Check if inventory already matches planned layout (Key-Based)
    local mismatches = 0
    for bagID = 0, 4 do
        local numSlots = GetContainerNumSlots(bagID) or 0
        for slotID = 1, numSlots do
            local texture = GetContainerItemInfo(bagID, slotID)
            local link = GetContainerItemLink(bagID, slotID)
            local key = nil
            if texture and link then
                key = GetSlotItemKey(bagID, slotID)
            end

            local target = slotTargets[bagID] and slotTargets[bagID][slotID]
            if target and (not key or key ~= target.key) then
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
