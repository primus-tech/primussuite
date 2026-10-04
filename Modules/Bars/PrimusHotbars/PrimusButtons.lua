--[[
    PrimusUI Module: PUIHotbars - Buttons Engine
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Manages button skinning, pure scaling (zero texture cropping),
    transparent 1-pixel overlays, hotkey formatting, and the 0.15s
    out-of-range & out-of-mana vertex tinting ticker.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIHotbars = Primus.PUIHotbars or {}
Primus.PUIHotbars = PUIHotbars

local Media   = Primus.Media
local Utils   = Primus.Utils
local Keybind = Primus.Keybind
local DB      = Primus.DB

PUIHotbars.trackedButtons = PUIHotbars.trackedButtons or {}

-- =========================================================================
-- HOTKEY TEXT FORMATTER
-- =========================================================================

function PUIHotbars:FormatHotkey(text)
    if not text or text == "" then return "" end
    text = string.gsub(text, "ALT%-", "a")
    text = string.gsub(text, "CTRL%-", "c")
    text = string.gsub(text, "SHIFT%-", "s")
    text = string.gsub(text, "Num Pad ", "N")
    text = string.gsub(text, "Middle Mouse", "M3")
    text = string.gsub(text, "Mouse Wheel Up", "WU")
    text = string.gsub(text, "Mouse Wheel Down", "WD")
    text = string.gsub(text, "Button 4", "M4")
    text = string.gsub(text, "Button 5", "M5")
    return text
end

-- =========================================================================
-- BUTTON STYLING & PURE SCALING ENGINE
-- =========================================================================

function PUIHotbars:StyleButton(btn, size)
    if not btn then return end
    local btnName = btn:GetName()
    if not btnName then return end

    size = size or 36
    btn:SetWidth(size)
    btn:SetHeight(size)

    local hotbarsDB = DB:GetNamespace("PUIHotbars")

    local border  = _G[btnName .. "Border"]
    local normal  = _G[btnName .. "NormalTexture"] or (btn.GetNormalTexture and btn:GetNormalTexture())
    local icon    = _G[btnName .. "Icon"] or _G[btnName .. "IconTexture"]
    local hotkey  = _G[btnName .. "HotKey"]
    local count   = _G[btnName .. "Count"]
    local name    = _G[btnName .. "Name"]
    local flash   = _G[btnName .. "Flash"]

    -- Hide legacy Blizzard border artwork
    if border and type(border.Hide) == "function" then border:Hide() end
    if normal then
        if type(normal.SetTexture) == "function" then normal:SetTexture("") end
        if type(normal.Hide) == "function" then normal:Hide() end
        if type(normal.SetAlpha) == "function" then normal:SetAlpha(0) end
    end
    if flash and type(flash.SetTexture) == "function" then
        flash:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    end

    -- Pure Scaling: Retain full native texture coordinates (0, 1, 0, 1) without cropping
    if icon then
        if type(icon.SetTexCoord) == "function" then
            icon:SetTexCoord(0.0, 1.0, 0.0, 1.0)
        end
        if type(icon.ClearAllPoints) == "function" then icon:ClearAllPoints() end
        if type(icon.SetPoint) == "function" then
            icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
            icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        end
    end

    -- Cooldown Frame Centering & Scaling
    local cooldown = _G[btnName .. "Cooldown"]
    if cooldown then
        if type(cooldown.ClearAllPoints) == "function" then cooldown:ClearAllPoints() end
        if type(cooldown.SetPoint) == "function" then cooldown:SetPoint("CENTER", btn, "CENTER", 0, 0) end
        if type(cooldown.SetWidth) == "function" then cooldown:SetWidth(36) end
        if type(cooldown.SetHeight) == "function" then cooldown:SetHeight(36) end
        if type(cooldown.SetScale) == "function" then cooldown:SetScale((size - 2) / 36) end
    end

    -- Empty Slot Background (Behind Icon on BACKGROUND layer)
    if not btn._primusBg then
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        if bg then
            bg:SetAllPoints(btn)
            bg:SetTexture(Media:Fetch("statusbar", "Default") or "Interface\\Buttons\\WHITE8X8")
            bg:SetVertexColor(0.08, 0.08, 0.10, 0.85)
            btn._primusBg = bg
        end
    end

    -- 1-Pixel Border Overlay (Transparent backdrop, only border stroke rendered)
    if not btn._primusBorder then
        local b = CreateFrame("Frame", nil, btn)
        if b then
            b:SetAllPoints(btn)
            b:SetBackdrop(Media:Fetch("border", "1Pixel"))
            b:SetBackdropColor(0, 0, 0, 0)
            b:SetBackdropBorderColor(0.22, 0.22, 0.28, 1.0)
            b:SetFrameLevel(btn:GetFrameLevel() + 2)
            btn._primusBorder = b
        end
    end

    -- Hotkey Text Formatting & Positioning
    if hotkey then
        if type(hotkey.ClearAllPoints) == "function" then hotkey:ClearAllPoints() end
        if type(hotkey.SetPoint) == "function" then hotkey:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -2) end
        if type(hotkey.SetFont) == "function" then hotkey:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE") end
        if type(hotkey.SetTextColor) == "function" then hotkey:SetTextColor(0.9, 0.9, 0.9) end
        if type(hotkey.GetText) == "function" and type(hotkey.SetText) == "function" then
            local raw = hotkey:GetText()
            if raw then hotkey:SetText(self:FormatHotkey(raw)) end
        end
        if hotbarsDB and not hotbarsDB:Get("hotkeys", true) and type(hotkey.Hide) == "function" then
            hotkey:Hide()
        end
    end

    -- Stack Count
    if count then
        if type(count.ClearAllPoints) == "function" then count:ClearAllPoints() end
        if type(count.SetPoint) == "function" then count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2) end
        if type(count.SetFont) == "function" then count:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE") end
    end

    -- Macro Name
    if name then
        if type(name.ClearAllPoints) == "function" then name:ClearAllPoints() end
        if type(name.SetPoint) == "function" then name:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2) end
        if type(name.SetFont) == "function" then name:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE") end
        if hotbarsDB and not hotbarsDB:Get("macroNames", false) and type(name.Hide) == "function" then
            name:Hide()
        end
    end

    if Keybind and Keybind.RegisterHoverTarget then
        Keybind:RegisterHoverTarget(btn)
    end

    -- Safely enable showgrid so empty action slots remain visible with sleek 1-pixel borders
    if string.find(btnName, "^ActionButton") or string.find(btnName, "^MultiBar") then
        btn.showgrid = 1
        if normal then
            if type(normal.SetVertexColor) == "function" then normal:SetVertexColor(1.0, 1.0, 1.0, 0.4) end
            if type(normal.Show) == "function" then normal:Show() end
        end
        btn:Show()
    end

    -- Register into tracking array for Range/Mana tickers
    local alreadyTracked = false
    local tCount = table.getn(self.trackedButtons)
    for i = 1, tCount do
        if self.trackedButtons[i] == btn then
            alreadyTracked = true
            break
        end
    end
    if not alreadyTracked then
        table.insert(self.trackedButtons, btn)
    end
end

-- =========================================================================
-- RANGE & MANA VERTEX COLOR TINTING TICKER
-- =========================================================================

function PUIHotbars:UpdateButtonStates()
    local hotbarsDB = DB:GetNamespace("PUIHotbars")
    local doRange = hotbarsDB and hotbarsDB:Get("rangeTint", true) or true
    local doMana  = hotbarsDB and hotbarsDB:Get("manaTint", true) or true

    local count = table.getn(self.trackedButtons)
    for i = 1, count do
        local btn = self.trackedButtons[i]
        if btn and btn:IsShown() then
            local action = nil
            if btn.GetPagedID then
                action = btn:GetPagedID()
            elseif ActionButton_GetPagedID then
                action = ActionButton_GetPagedID(btn)
            elseif btn.action then
                action = btn.action
            end

            local icon = _G[btn:GetName() .. "Icon"] or _G[btn:GetName() .. "IconTexture"]
            if icon and type(icon.SetVertexColor) == "function" and action and HasAction(action) then
                local inRange = IsActionInRange(action)
                local isUsable, notEnoughMana = IsUsableAction(action)

                if doRange and inRange == 0 and UnitExists("target") then
                    icon:SetVertexColor(0.85, 0.20, 0.20) -- Red (Out of Range)
                elseif doMana and notEnoughMana then
                    icon:SetVertexColor(0.30, 0.30, 0.85) -- Blue (Out of Mana)
                elseif not isUsable then
                    icon:SetVertexColor(0.40, 0.40, 0.40) -- Grey (Unusable)
                else
                    icon:SetVertexColor(1.0, 1.0, 1.0)    -- Normal (Ready)
                end
            elseif icon and type(icon.SetVertexColor) == "function" then
                icon:SetVertexColor(1.0, 1.0, 1.0)
            end
        end
    end
end
