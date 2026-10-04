--[[
    PrimusUI: PUITooltip Unit Formatting & Pipeline (PUITooltipUnit.lua)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUITooltip = Primus.PUITooltip or {}
Primus.PUITooltip = PUITooltip

local UnitHandler = {}
PUITooltip.Unit = UnitHandler

local C = PUITooltip.Constants

--------------------------------------------------------------------------------
-- Format Unit Lines
--------------------------------------------------------------------------------
function UnitHandler:FormatUnit(tooltip, unit)
    if not tooltip or not unit or not UnitExists(unit) then return end
    
    local settings = PUITooltip:GetSettings()
    
    -- Check combat / battleground suppressions
    if settings.hideInCombat and UnitAffectingCombat("player") then
        tooltip:Hide()
        return
    end
    
    local isPlayer = UnitIsPlayer(unit)
    local name = UnitName(unit) or "Unknown"
    local level = UnitLevel(unit)
    local race = UnitRace(unit)
    local class, classFileName = UnitClass(unit)
    local reaction = UnitReaction(unit, "player")
    local classification = UnitClassification(unit)
    
    -- 1. Name & Classification Colors
    local nameColor = { r = 1, g = 1, b = 1 }
    if isPlayer and classFileName and C.ClassColors[classFileName] then
        nameColor = C.ClassColors[classFileName]
    elseif UnitIsTapped(unit) and not UnitIsTappedByPlayer(unit) then
        nameColor = C.ReactionColors["Tapped"]
    elseif reaction and C.ReactionColors[reaction] then
        nameColor = C.ReactionColors[reaction]
    end
    
    -- First line (Name)
    local nameLine = _G[tooltip:GetName() .. "TextLeft1"]
    if nameLine then
        local pvpPrefix = ""
        if UnitIsPVP(unit) then
            pvpPrefix = (UnitFactionGroup(unit) == "Alliance") and "|cff00ccff[PvP]|r " or "|cffff3333[PvP]|r "
        end
        nameLine:SetText(pvpPrefix .. name)
        nameLine:SetTextColor(nameColor.r, nameColor.g, nameColor.b)
    end
    
    -- 2. Guild Line Formatting
    if isPlayer and settings.showGuildRank ~= false then
        local guildName, guildRankName = GetGuildInfo(unit)
        if guildName and guildName ~= "" then
            local rankStr = (guildRankName and guildRankName ~= "") and (" |cff888899(" .. guildRankName .. ")|r") or ""
            local line2 = _G[tooltip:GetName() .. "TextLeft2"]
            if line2 and string.find(line2:GetText() or "", guildName) then
                line2:SetText("<" .. guildName .. ">" .. rankStr)
                line2:SetTextColor(0.2, 0.8, 1.0)
            end
        end
    end
    
    -- 3. Level & Classification Line Formatting
    local levelDiff = (level and level > 0) and GetDifficultyColor(level) or { r = 1, g = 0.2, b = 0.2 }
    local levelStr = (level and level > 0) and tostring(level) or "??"
    
    local classSuffix = ""
    if classification == "worldboss" then
        classSuffix = " (Boss)"
    elseif classification == "rareelite" then
        classSuffix = " (Rare Elite)"
    elseif classification == "elite" then
        classSuffix = " (Elite)"
    elseif classification == "rare" then
        classSuffix = " (Rare)"
    end
    
    -- Find level line and reformat
    for i = 2, tooltip:NumLines() do
        local line = _G[tooltip:GetName() .. "TextLeft" .. i]
        if line then
            local txt = line:GetText() or ""
            if string.find(txt, "Level") or string.find(txt, "level") then
                local creatureType = UnitCreatureType(unit) or ""
                local creatureFamily = UnitCreatureFamily(unit) or ""
                local typeStr = isPlayer and (race .. " " .. class) or (creatureFamily ~= "" and creatureFamily or creatureType)
                line:SetText(string.format("Level %s%s %s", levelStr, classSuffix, typeStr))
                line:SetTextColor(levelDiff.r, levelDiff.g, levelDiff.b)
                break
            end
        end
    end
    
    -- 4. Target-of-Target Line
    if settings.showTargetOfTarget ~= false then
        local totUnit = unit .. "target"
        if UnitExists(totUnit) then
            local totName = UnitName(totUnit)
            local totColor = "ffffff"
            if UnitIsPlayer(totUnit) then
                local _, totClass = UnitClass(totUnit)
                if totClass and C.ClassColors[totClass] then
                    totColor = C.ClassColors[totClass].hex
                end
            elseif UnitReaction(totUnit, "player") and C.ReactionColors[UnitReaction(totUnit, "player")] then
                totColor = C.ReactionColors[UnitReaction(totUnit, "player")].hex
            end
            
            if totName and totName ~= "" then
                tooltip:AddLine(string.format("|cffaaaaaaTargeting:|r |cff%s%s|r", totColor, totName), 0.7, 0.7, 0.7)
            end
        end
    end
    
    -- 5. GameTooltipStatusBar (Health Bar)
    if settings.showHealthBar ~= false and GameTooltipStatusBar:IsShown() then
        local hp = UnitHealth(unit)
        local maxHp = UnitHealthMax(unit)
        if maxHp and maxHp > 0 then
            GameTooltipStatusBar:SetMinMaxValues(0, maxHp)
            GameTooltipStatusBar:SetValue(hp)
            GameTooltipStatusBar:SetStatusBarColor(nameColor.r, nameColor.g, nameColor.b)
            
            if GameTooltipStatusBar.healthText and settings.showHealthText ~= false then
                local pct = math.floor((hp / maxHp) * 100)
                GameTooltipStatusBar.healthText:SetText(string.format("%d / %d (%d%%)", hp, maxHp, pct))
                GameTooltipStatusBar.healthText:Show()
            end
        end
    end
    
    -- 6. Dispatch to registered Unit Providers
    local providers = PUITooltip:GetUnitProviders()
    for _, prov in ipairs(providers) do
        if prov.callback then
            prov.callback(tooltip, unit, name, isPlayer)
        end
    end
    
    tooltip:Show()
end

--------------------------------------------------------------------------------
-- Initialize Unit Hook
--------------------------------------------------------------------------------
function UnitHandler:Initialize()
    if not UnitHandler.hooked then
        local origSetUnit = GameTooltip.SetUnit
        GameTooltip.SetUnit = function(self, unit)
            local ret = origSetUnit and origSetUnit(self, unit)
            if PUITooltip:IsEnabled() then
                UnitHandler:FormatUnit(self, unit)
            end
            return ret
        end
        
        -- In Vanilla WoW 1.12.1, 3D world unit mouseover triggers UPDATE_MOUSEOVER_UNIT
        if Primus.Events and Primus.Events.Register then
            Primus.Events:Register("UPDATE_MOUSEOVER_UNIT", "PUITooltip_Unit", function()
                if PUITooltip:IsEnabled() and UnitExists("mouseover") and GameTooltip:IsShown() then
                    UnitHandler:FormatUnit(GameTooltip, "mouseover")
                end
            end)
        end
        
        UnitHandler.hooked = true
    end
end
