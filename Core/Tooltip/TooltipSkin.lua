--[[
    PrimusUI: PUITooltip Skin & Theme Engine (PUITooltipSkin.lua)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUITooltip = Primus.PUITooltip or {}
Primus.PUITooltip = PUITooltip

local Skin = {}
PUITooltip.Skin = Skin

local C = PUITooltip.Constants
local Media = Primus.Media

-- Tooltips to automatically skin
local tooltipsToSkin = {
    "GameTooltip",
    "ItemRefTooltip",
    "ItemRefShoppingTooltip1",
    "ItemRefShoppingTooltip2",
    "ItemRefShoppingTooltip3",
    "ShoppingTooltip1",
    "ShoppingTooltip2",
    "ShoppingTooltip3",
    "WorldMapTooltip",
    "WorldMapCompareTooltip1",
    "WorldMapCompareTooltip2",
    "WorldMapCompareTooltip3",
    "QuestFader_GameTooltip",
}

--------------------------------------------------------------------------------
-- Apply Primus 1-Pixel Dark Backdrop
--------------------------------------------------------------------------------
function Skin:ApplyBackdrop(tooltip)
    if not tooltip then return end
    
    local bd = Media and Media:Fetch("border", "1Pixel") or {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    }
    
    tooltip:SetBackdrop(bd)
    local def = C.DefaultBackdrop
    local settings = PUITooltip:GetSettings()
    local alpha = settings.backdropAlpha or def.a
    
    tooltip:SetBackdropColor(def.r, def.g, def.b, alpha)
    tooltip:SetBackdropBorderColor(def.borderR, def.borderG, def.borderB, def.borderA)
end

--------------------------------------------------------------------------------
-- Reset Border Color to Default
--------------------------------------------------------------------------------
function Skin:ResetBorderColor(tooltip)
    if not tooltip then return end
    local def = C.DefaultBackdrop
    tooltip:SetBackdropBorderColor(def.borderR, def.borderG, def.borderB, def.borderA)
end

--------------------------------------------------------------------------------
-- Set Border by Item Quality
--------------------------------------------------------------------------------
function Skin:SetQualityBorder(tooltip, quality)
    if not tooltip then return end
    local settings = PUITooltip:GetSettings()
    if settings.itemQualityBorders == false or not quality then
        self:ResetBorderColor(tooltip)
        return
    end
    
    local qColor = C.QualityColors[tonumber(quality)]
    if qColor then
        tooltip:SetBackdropBorderColor(qColor.r, qColor.g, qColor.b, 1.0)
    else
        self:ResetBorderColor(tooltip)
    end
end

--------------------------------------------------------------------------------
-- Style GameTooltipStatusBar (Health Bar)
--------------------------------------------------------------------------------
function Skin:StyleStatusBar()
    local sb = _G["GameTooltipStatusBar"]
    if not sb then return end
    
    sb:SetHeight(5)
    sb:ClearAllPoints()
    sb:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 1, -2)
    sb:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -1, -2)
    
    local barTex = Media and Media:Fetch("statusbar", "Flat") or "Interface\\TargetingFrame\\UI-StatusBar"
    sb:SetStatusBarTexture(barTex)
    
    if not sb.primusBackdrop then
        local bg = CreateFrame("Frame", nil, sb)
        bg:SetPoint("TOPLEFT", sb, "TOPLEFT", -1, 1)
        bg:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 1, -1)
        bg:SetFrameLevel(sb:GetFrameLevel() > 0 and (sb:GetFrameLevel() - 1) or 0)
        bg:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        bg:SetBackdropColor(0.04, 0.04, 0.06, 0.95)
        bg:SetBackdropBorderColor(0.20, 0.20, 0.25, 1.0)
        sb.primusBackdrop = bg
    end
    
    if not sb.healthText then
        local txt = sb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("CENTER", sb, "CENTER", 0, 0)
        txt:SetFont(Media and Media:Fetch("font", "Pixel") or "Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        txt:Hide()
        sb.healthText = txt
    end
end

--------------------------------------------------------------------------------
-- Initialize All Tooltip Skins & Hooks
--------------------------------------------------------------------------------
function Skin:Initialize()
    for _, name in ipairs(tooltipsToSkin) do
        local tt = _G[name]
        if tt then
            self:ApplyBackdrop(tt)
            
            -- Hook OnShow and OnHide to ensure persistent styling and clean border resets
            if not tt.primusSkinHooked then
                local origOnShow = tt:GetScript("OnShow")
                tt:SetScript("OnShow", function()
                    if origOnShow then origOnShow() end
                    Skin:ApplyBackdrop(this)
                end)
                
                local origOnHide = tt:GetScript("OnHide")
                tt:SetScript("OnHide", function()
                    if origOnHide then origOnHide() end
                    Skin:ResetBorderColor(this)
                end)
                tt.primusSkinHooked = true
            end
        end
    end
    
    self:StyleStatusBar()
end
