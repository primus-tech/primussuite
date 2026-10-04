--[[
    PrimusUI: PUITooltip Item & Spell Pipeline (PUITooltipItem.lua)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUITooltip = Primus.PUITooltip or {}
Primus.PUITooltip = PUITooltip

local ItemHandler = {}
PUITooltip.Item = ItemHandler

local Skin = PUITooltip.Skin

--------------------------------------------------------------------------------
-- Helper: Extract Item ID & Quality from Link
--------------------------------------------------------------------------------
local function ParseItemLink(link)
    if not link then return nil, nil end
    local _, _, itemID = string.find(link, "item:(%d+)")
    local _, _, _, _, _, _, _, _, _, _, quality = GetItemInfo(link)
    if not quality and itemID then
        local _, _, qStr = string.find(link, "|cff(%x+)|H")
        -- Quality fallback resolution
        if qStr then
            for qNum, qData in pairs(PUITooltip.Constants.QualityColors) do
                if string.lower(qData.hex) == string.lower(qStr) then
                    quality = qNum
                    break
                end
            end
        end
    end
    return tonumber(itemID), tonumber(quality)
end

--------------------------------------------------------------------------------
-- Process Item Pipeline
--------------------------------------------------------------------------------
function ItemHandler:ProcessItem(tooltip, itemData)
    if not tooltip or not itemData then return end
    
    local settings = PUITooltip:GetSettings()
    
    -- 1. Apply Item Quality Border
    if itemData.quality and Skin then
        Skin:SetQualityBorder(tooltip, itemData.quality)
    end
    
    -- 2. Dispatch to registered Item Providers
    local providers = PUITooltip:GetItemProviders()
    for _, prov in ipairs(providers) do
        if prov.callback then
            prov.callback(tooltip, itemData)
        end
    end
    
    tooltip:Show()
end

--------------------------------------------------------------------------------
-- Process Spell Pipeline
--------------------------------------------------------------------------------
function ItemHandler:ProcessSpell(tooltip, spellData)
    if not tooltip or not spellData then return end
    
    local providers = PUITooltip:GetSpellProviders()
    for _, prov in ipairs(providers) do
        if prov.callback then
            prov.callback(tooltip, spellData)
        end
    end
    
    tooltip:Show()
end

--------------------------------------------------------------------------------
-- Master Blizzard Hook Suite
--------------------------------------------------------------------------------
function ItemHandler:Initialize()
    if ItemHandler.hooked then return end
    
    local tooltips = { GameTooltip, ItemRefTooltip }
    
    for _, tt in ipairs(tooltips) do
        if tt then
            -- 1. SetBagItem
            local origSetBagItem = tt.SetBagItem
            tt.SetBagItem = function(self, bag, slot)
                local hasItem = origSetBagItem and origSetBagItem(self, bag, slot)
                if PUITooltip:IsEnabled() then
                    local link = GetContainerItemLink(bag, slot)
                    local _, count = GetContainerItemInfo(bag, slot)
                    local itemID, quality = ParseItemLink(link)
                    ItemHandler:ProcessItem(self, {
                        bag = bag, slot = slot, count = count or 1,
                        link = link, itemID = itemID, quality = quality,
                        source = "BAG"
                    })
                end
                return hasItem
            end
            
            -- 2. SetInventoryItem
            local origSetInventoryItem = tt.SetInventoryItem
            tt.SetInventoryItem = function(self, unit, slot)
                local hasItem = origSetInventoryItem and origSetInventoryItem(self, unit, slot)
                if PUITooltip:IsEnabled() then
                    local link = GetInventoryItemLink(unit, slot)
                    local count = GetInventoryItemCount(unit, slot)
                    local itemID, quality = ParseItemLink(link)
                    ItemHandler:ProcessItem(self, {
                        unit = unit, slot = slot, count = count or 1,
                        link = link, itemID = itemID, quality = quality,
                        source = "INVENTORY"
                    })
                end
                return hasItem
            end
            
            -- 3. SetHyperlink
            local origSetHyperlink = tt.SetHyperlink
            tt.SetHyperlink = function(self, link)
                local ret = origSetHyperlink and origSetHyperlink(self, link)
                if PUITooltip:IsEnabled() and link then
                    if string.find(link, "item:") then
                        local itemID, quality = ParseItemLink(link)
                        ItemHandler:ProcessItem(self, {
                            link = link, itemID = itemID, quality = quality,
                            count = 1, source = "HYPERLINK"
                        })
                    elseif string.find(link, "spell:") then
                        local _, _, spellID = string.find(link, "spell:(%d+)")
                        ItemHandler:ProcessSpell(self, {
                            link = link, spellID = tonumber(spellID), source = "SPELL_LINK"
                        })
                    end
                end
                return ret
            end
            
            -- 4. SetAction
            local origSetAction = tt.SetAction
            tt.SetAction = function(self, slot)
                local ret = origSetAction and origSetAction(self, slot)
                if PUITooltip:IsEnabled() and HasAction(slot) then
                    local actionText = GetActionText(slot)
                    if not actionText then -- Not a macro
                        -- Test if item or spell
                        local count = GetActionCount(slot)
                        -- Try bag scan or tooltip scanning
                        local line1 = _G[self:GetName() .. "TextLeft1"]
                        local name = line1 and line1:GetText()
                        ItemHandler:ProcessItem(self, {
                            actionSlot = slot, count = count or 1, name = name, source = "ACTION"
                        })
                    end
                end
                return ret
            end
            
            -- 5. SetCraftItem & SetTradeSkillItem
            local origSetCraftItem = tt.SetCraftItem
            tt.SetCraftItem = function(self, skill, slot)
                local ret = origSetCraftItem and origSetCraftItem(self, skill, slot)
                if PUITooltip:IsEnabled() then
                    local link = GetCraftReagentItemLink(skill, slot)
                    local itemID, quality = ParseItemLink(link)
                    ItemHandler:ProcessItem(self, {
                        link = link, itemID = itemID, quality = quality,
                        craftSkill = skill, craftSlot = slot, source = "CRAFT_REAGENT"
                    })
                end
                return ret
            end
            
            local origSetTradeSkillItem = tt.SetTradeSkillItem
            tt.SetTradeSkillItem = function(self, skill, slot)
                local ret = origSetTradeSkillItem and origSetTradeSkillItem(self, skill, slot)
                if PUITooltip:IsEnabled() then
                    local link = slot and GetTradeSkillReagentItemLink(skill, slot) or GetTradeSkillItemLink(skill)
                    local itemID, quality = ParseItemLink(link)
                    ItemHandler:ProcessItem(self, {
                        link = link, itemID = itemID, quality = quality,
                        tradeSkill = skill, tradeSlot = slot, source = "TRADESKILL"
                    })
                end
                return ret
            end
            
            -- 6. SetLootItem & SetQuestItem
            local origSetLootItem = tt.SetLootItem
            tt.SetLootItem = function(self, slot)
                local ret = origSetLootItem and origSetLootItem(self, slot)
                if PUITooltip:IsEnabled() then
                    local link = GetLootSlotLink(slot)
                    local itemID, quality = ParseItemLink(link)
                    ItemHandler:ProcessItem(self, {
                        lootSlot = slot, link = link, itemID = itemID, quality = quality, source = "LOOT"
                    })
                end
                return ret
            end
            
            local origSetQuestItem = tt.SetQuestItem
            tt.SetQuestItem = function(self, qType, slot)
                local ret = origSetQuestItem and origSetQuestItem(self, qType, slot)
                if PUITooltip:IsEnabled() then
                    local link = GetQuestItemLink(qType, slot)
                    local itemID, quality = ParseItemLink(link)
                    ItemHandler:ProcessItem(self, {
                        questType = qType, questSlot = slot, link = link, itemID = itemID, quality = quality, source = "QUEST"
                    })
                end
                return ret
            end
            
            local origSetQuestLogItem = tt.SetQuestLogItem
            tt.SetQuestLogItem = function(self, qType, slot)
                local ret = origSetQuestLogItem and origSetQuestLogItem(self, qType, slot)
                if PUITooltip:IsEnabled() then
                    local link = GetQuestLogItemLink(qType, slot)
                    local itemID, quality = ParseItemLink(link)
                    ItemHandler:ProcessItem(self, {
                        questType = qType, questSlot = slot, link = link, itemID = itemID, quality = quality, source = "QUEST_LOG"
                    })
                end
                return ret
            end
            
            -- 7. SetMerchantItem & SetBuybackItem
            local origSetMerchantItem = tt.SetMerchantItem
            tt.SetMerchantItem = function(self, slot)
                local ret = origSetMerchantItem and origSetMerchantItem(self, slot)
                if PUITooltip:IsEnabled() then
                    local link = GetMerchantItemLink(slot)
                    local itemID, quality = ParseItemLink(link)
                    ItemHandler:ProcessItem(self, {
                        merchantSlot = slot, link = link, itemID = itemID, quality = quality, source = "MERCHANT"
                    })
                end
                return ret
            end
            
            local origSetBuybackItem = tt.SetBuybackItem
            tt.SetBuybackItem = function(self, slot)
                local ret = origSetBuybackItem and origSetBuybackItem(self, slot)
                if PUITooltip:IsEnabled() then
                    local link = GetBuybackItemLink(slot)
                    local itemID, quality = ParseItemLink(link)
                    ItemHandler:ProcessItem(self, {
                        buybackSlot = slot, link = link, itemID = itemID, quality = quality, source = "BUYBACK"
                    })
                end
                return ret
            end
            
            -- 8. SetInboxItem & SetSendMailItem
            local origSetInboxItem = tt.SetInboxItem
            tt.SetInboxItem = function(self, index, attachIndex)
                local ret = origSetInboxItem and origSetInboxItem(self, index, attachIndex)
                if PUITooltip:IsEnabled() then
                    local name, itemTexture, count, quality = GetInboxItem(index, attachIndex)
                    ItemHandler:ProcessItem(self, {
                        mailIndex = index, attachIndex = attachIndex, count = count or 1, quality = quality, source = "INBOX"
                    })
                end
                return ret
            end
            
            local origSetSendMailItem = tt.SetSendMailItem
            tt.SetSendMailItem = function(self, index)
                local ret = origSetSendMailItem and origSetSendMailItem(self, index)
                if PUITooltip:IsEnabled() then
                    local name, itemTexture, count, quality = GetSendMailItem(index)
                    ItemHandler:ProcessItem(self, {
                        sendMailIndex = index, count = count or 1, quality = quality, source = "SEND_MAIL"
                    })
                end
                return ret
            end
            
            -- 9. SetAuctionItem
            local origSetAuctionItem = tt.SetAuctionItem
            tt.SetAuctionItem = function(self, aType, index)
                local ret = origSetAuctionItem and origSetAuctionItem(self, aType, index)
                if PUITooltip:IsEnabled() then
                    local link = GetAuctionItemLink(aType, index)
                    local itemID, quality = ParseItemLink(link)
                    local name, texture, count = GetAuctionItemInfo(aType, index)
                    ItemHandler:ProcessItem(self, {
                        auctionType = aType, auctionIndex = index, link = link, itemID = itemID,
                        quality = quality, count = count or 1, source = "AUCTION"
                    })
                end
                return ret
            end
            
            -- 10. SetSpell
            local origSetSpell = tt.SetSpell
            tt.SetSpell = function(self, spellID, spellBookTab)
                local ret = origSetSpell and origSetSpell(self, spellID, spellBookTab)
                if PUITooltip:IsEnabled() then
                    ItemHandler:ProcessSpell(self, {
                        spellID = spellID, spellBookTab = spellBookTab, source = "SPELLBOOK"
                    })
                end
                return ret
            end
        end
    end
    
    ItemHandler.hooked = true
end
