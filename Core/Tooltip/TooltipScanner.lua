--[[
    PrimusUI: PUITooltip Recycled Background Scanner Pool (PUITooltipScanner.lua)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUITooltip = Primus.PUITooltip or {}
Primus.PUITooltip = PUITooltip

local Scanner = {}
PUITooltip.Scanner = Scanner

local scanTooltip = nil
local scanResultsBuffer = {}

--------------------------------------------------------------------------------
-- Build / Retrieve Background Scanner Tooltip
--------------------------------------------------------------------------------
function Scanner:GetScanTooltip()
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "Primus_PUITooltip_ScanTooltip", UIParent, "GameTooltipTemplate")
        scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    return scanTooltip
end

--------------------------------------------------------------------------------
-- Generic Line Extractor (Recycled Buffer)
--------------------------------------------------------------------------------
local function ExtractLines(tt)
    for k in pairs(scanResultsBuffer) do
        scanResultsBuffer[k] = nil
    end
    
    local numLines = tt:NumLines()
    for i = 1, numLines do
        local left = _G["Primus_PUITooltip_ScanTooltipTextLeft" .. i]
        local right = _G["Primus_PUITooltip_ScanTooltipTextRight" .. i]
        scanResultsBuffer[i] = {
            left = left and left:GetText() or "",
            right = right and right:GetText() or "",
        }
    end
    table.setn(scanResultsBuffer, numLines)
    return scanResultsBuffer
end

--------------------------------------------------------------------------------
-- Scanner API
--------------------------------------------------------------------------------
function PUITooltip:ScanBagItem(bag, slot)
    local tt = Scanner:GetScanTooltip()
    tt:ClearLines()
    tt:SetBagItem(bag, slot)
    return ExtractLines(tt)
end

function PUITooltip:ScanInventoryItem(unit, slot)
    local tt = Scanner:GetScanTooltip()
    tt:ClearLines()
    tt:SetInventoryItem(unit or "player", slot)
    return ExtractLines(tt)
end

function PUITooltip:ScanHyperlink(link)
    local tt = Scanner:GetScanTooltip()
    tt:ClearLines()
    tt:SetHyperlink(link)
    return ExtractLines(tt)
end

function PUITooltip:ScanAction(slot)
    local tt = Scanner:GetScanTooltip()
    tt:ClearLines()
    tt:SetAction(slot)
    return ExtractLines(tt)
end

--------------------------------------------------------------------------------
-- Durability Helper (Zero Garbage Allocation)
--------------------------------------------------------------------------------
local DURABILITY_REGEX = string.gsub(DURABILITY_TEMPLATE or "Durability %d / %d", "%%d", "(%%d+)")

function PUITooltip:GetItemDurability(bag, slot)
    local tt = Scanner:GetScanTooltip()
    tt:ClearLines()
    if bag then
        tt:SetBagItem(bag, slot)
    else
        tt:SetInventoryItem("player", slot)
    end
    
    for j = 1, tt:NumLines() do
        local line = _G["Primus_PUITooltip_ScanTooltipTextLeft" .. j]
        if line then
            local text = line:GetText()
            if text then
                local _, _, cur, max = string.find(text, DURABILITY_REGEX)
                if cur and max then
                    return tonumber(cur), tonumber(max), math.floor((tonumber(cur) / tonumber(max)) * 100)
                end
            end
        end
    end
    return nil, nil, nil
end

function Scanner:GetInventoryDurability(slot)
    return PUITooltip:GetItemDurability(nil, slot)
end

function Scanner:GetBagDurability(bag, slot)
    return PUITooltip:GetItemDurability(bag, slot)
end

function Scanner:ScanBagItem(bag, slot)
    return PUITooltip:ScanBagItem(bag, slot)
end

function Scanner:ScanInventoryItem(unit, slot)
    return PUITooltip:ScanInventoryItem(unit, slot)
end

function Scanner:ScanHyperlink(link)
    return PUITooltip:ScanHyperlink(link)
end
