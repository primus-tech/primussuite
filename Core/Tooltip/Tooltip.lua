--[[
    PrimusUI: PUITooltip Master Coordinator & Public Provider Desk (PUITooltip.lua)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUITooltip = Primus.PUITooltip or {}
Primus.PUITooltip = PUITooltip

Primus:RegisterModule("PUITooltip", PUITooltip, "Utility")

local dbNamespace = nil
local unitProviders = {}
local itemProviders = {}
local spellProviders = {}

--------------------------------------------------------------------------------
-- Provider Sorting Helper
--------------------------------------------------------------------------------
local function SortProviders(providerList)
    table.sort(providerList, function(a, b)
        return (a.priority or 100) < (b.priority or 100)
    end)
end

--------------------------------------------------------------------------------
-- Public Provider Registration API
--------------------------------------------------------------------------------
function PUITooltip:RegisterUnitProvider(id, priority, callback)
    if not id or not callback then return end
    self:UnregisterUnitProvider(id)
    table.insert(unitProviders, { id = id, priority = priority or 50, callback = callback })
    SortProviders(unitProviders)
end

function PUITooltip:UnregisterUnitProvider(id)
    for i, prov in ipairs(unitProviders) do
        if prov.id == id then
            table.remove(unitProviders, i)
            break
        end
    end
end

function PUITooltip:GetUnitProviders()
    return unitProviders
end

function PUITooltip:RegisterItemProvider(id, priority, callback)
    if not id or not callback then return end
    self:UnregisterItemProvider(id)
    table.insert(itemProviders, { id = id, priority = priority or 50, callback = callback })
    SortProviders(itemProviders)
end

function PUITooltip:UnregisterItemProvider(id)
    for i, prov in ipairs(itemProviders) do
        if prov.id == id then
            table.remove(itemProviders, i)
            break
        end
    end
end

function PUITooltip:GetItemProviders()
    return itemProviders
end

function PUITooltip:RegisterSpellProvider(id, priority, callback)
    if not id or not callback then return end
    self:UnregisterSpellProvider(id)
    table.insert(spellProviders, { id = id, priority = priority or 50, callback = callback })
    SortProviders(spellProviders)
end

function PUITooltip:UnregisterSpellProvider(id)
    for i, prov in ipairs(spellProviders) do
        if prov.id == id then
            table.remove(spellProviders, i)
            break
        end
    end
end

function PUITooltip:GetSpellProviders()
    return spellProviders
end

--------------------------------------------------------------------------------
-- Public Tooltip Drawing Helpers
--------------------------------------------------------------------------------
function PUITooltip:AddLine(tooltip, text, r, g, b, wrap)
    if not tooltip or not text then return end
    tooltip:AddLine(text, r or 1.0, g or 1.0, b or 1.0, wrap)
end

function PUITooltip:AddDoubleLine(tooltip, leftText, rightText, lr, lg, lb, rr, rg, rb)
    if not tooltip or not leftText then return end
    tooltip:AddDoubleLine(
        leftText, rightText or "",
        lr or 1.0, lg or 1.0, lb or 1.0,
        rr or 1.0, rg or 1.0, rb or 1.0
    )
end

function PUITooltip:SetQualityBorder(tooltip, quality)
    if self.Skin then
        self.Skin:SetQualityBorder(tooltip, quality)
    end
end

--------------------------------------------------------------------------------
-- Settings & Database
--------------------------------------------------------------------------------
function PUITooltip:GetSettings()
    if dbNamespace and dbNamespace.data then
        return dbNamespace.data
    end
    return self.Defaults
end

function PUITooltip:IsEnabled()
    return self.enabled ~= false
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------
function PUITooltip:OnInitialize()
    dbNamespace = Primus.DB:RegisterNamespace("PUITooltip", self.Defaults, true)
    
    if self.Skin then self.Skin:Initialize() end
    if self.Anchor then self.Anchor:Initialize() end
    if self.Unit then self.Unit:Initialize() end
    if self.Item then self.Item:Initialize() end
    
    self:RegisterFlare()
end

function PUITooltip:OnEnable()
    self.enabled = true
    if self.Skin then self.Skin:Initialize() end
end

function PUITooltip:OnDisable()
    self.enabled = false
end

--------------------------------------------------------------------------------
-- Options Flare Hub Registration
--------------------------------------------------------------------------------
function PUITooltip:RegisterFlare()
    if not Primus.Options then return end
    
    Primus.Options:RegisterModuleOptions("PUITooltip", {
        title = "Universal Tooltips (PUITooltip)",
        category = "Utility",
        order = 3,
        desc = "Master Tooltip engine providing dark 1-pixel skinning, item quality borders, smart anchoring, unit metadata, and provider pipelines."
    }, function(parent)
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetWidth(parent:GetWidth())
        frame:SetHeight(480)
        
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
        title:SetText("|cff00ccffUniversal Tooltip Engine Settings|r")
        
        -- Anchor Mode Dropdown
        local anchorModes = {
            { "SMART_CORNER", "Smart Screen Corner (Bottom-Right)" },
            { "CURSOR", "Mouse Pointer (Follows Cursor)" },
            { "MOVER", "Custom Draggable Anchor (/pui move)" }
        }
        
        local curAnchor = PUITooltip:GetSettings().anchorMode or "SMART_CORNER"
        local anchorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        anchorLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
        anchorLabel:SetText("|cff00e5ffTooltip Anchor Placement:|r")
        
        local anchorDrop = Primus.Widgets:CreateDropdown(frame, 220, 24, anchorModes, curAnchor, function(val)
            local s = PUITooltip:GetSettings()
            s.anchorMode = val
        end)
        anchorDrop:SetPoint("TOPLEFT", anchorLabel, "BOTTOMLEFT", 0, -4)
        
        -- Checkboxes
        local cbQuality = Primus.Widgets:CreateCheckButton(frame, "Color Tooltip Border by Item Quality", PUITooltip:GetSettings().itemQualityBorders ~= false, function(checked)
            local s = PUITooltip:GetSettings()
            s.itemQualityBorders = checked
        end)
        cbQuality:SetPoint("TOPLEFT", anchorDrop, "BOTTOMLEFT", 0, -12)
        
        local cbHealth = Primus.Widgets:CreateCheckButton(frame, "Show Unit Health Bar below Tooltip", PUITooltip:GetSettings().showHealthBar ~= false, function(checked)
            local s = PUITooltip:GetSettings()
            s.showHealthBar = checked
        end)
        cbHealth:SetPoint("TOPLEFT", cbQuality, "BOTTOMLEFT", 0, -6)
        
        local cbHealthText = Primus.Widgets:CreateCheckButton(frame, "Show Numeric Health Values on Health Bar", PUITooltip:GetSettings().showHealthText ~= false, function(checked)
            local s = PUITooltip:GetSettings()
            s.showHealthText = checked
        end)
        cbHealthText:SetPoint("TOPLEFT", cbHealth, "BOTTOMLEFT", 0, -6)
        
        local cbToT = Primus.Widgets:CreateCheckButton(frame, "Show Target of Target Line on Unit Mouseover", PUITooltip:GetSettings().showTargetOfTarget ~= false, function(checked)
            local s = PUITooltip:GetSettings()
            s.showTargetOfTarget = checked
        end)
        cbToT:SetPoint("TOPLEFT", cbHealthText, "BOTTOMLEFT", 0, -6)
        
        local cbGuild = Primus.Widgets:CreateCheckButton(frame, "Show Player Guild Rank Name in Tooltip", PUITooltip:GetSettings().showGuildRank ~= false, function(checked)
            local s = PUITooltip:GetSettings()
            s.showGuildRank = checked
        end)
        cbGuild:SetPoint("TOPLEFT", cbToT, "BOTTOMLEFT", 0, -6)
        
        local cbCombat = Primus.Widgets:CreateCheckButton(frame, "Hide Unit Tooltips while in Combat", PUITooltip:GetSettings().hideInCombat == true, function(checked)
            local s = PUITooltip:GetSettings()
            s.hideInCombat = checked
        end)
        cbCombat:SetPoint("TOPLEFT", cbGuild, "BOTTOMLEFT", 0, -6)
        
        -- Open Mover Action Button
        local moveBtn = Primus.Widgets:CreateButton(frame, "Move Tooltip Anchor (/pui move)", 220, 24, function()
            if Primus.PUIMover and Primus.PUIMover.Toggle then
                Primus.PUIMover:Toggle()
            end
        end)
        moveBtn:SetPoint("TOPLEFT", cbCombat, "BOTTOMLEFT", 0, -16)
        
        return frame
    end)
end
