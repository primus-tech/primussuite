--[[
    PrimusUI Module: PUIHud - Bar 10 Cockpit Mini-Bars Engine
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Dedicated Bar 10 Backend Action Allocation (Slots 109..120):
    - Left Wing Mini-Bar (4 Buttons):  Slots 109, 110, 111, 112 (Defensives / Consumables)
    - Right Wing Mini-Bar (4 Buttons): Slots 113, 114, 115, 116 (Offensive Trinkets / Cooldowns)
    - ActiveAssist / Emergency:        Slots 117, 118, 119, 120
    
    Features:
    - 100% native drag-and-drop from Spellbook and Bags (PickupAction / PlaceAction).
    - Unconstrained click-casting (UseAction).
    - Pure scaling (0, 1, 0, 1) without texture clipping.
    - Zero stance collisions (completely isolated from Pages 7..9 / Slots 73..108).
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIHud = Primus.PUIHud or {}
Primus.PUIHud = PUIHud

local Media   = Primus.Media
local DB      = Primus.DB
local Keybind = Primus.Keybind

local cockpitBar1 = nil
local cockpitBar2 = nil
local cockpitBar3 = nil
local cockpitButtons = {}

-- =========================================================================
-- NATIVE BAR 10 ACTION BUTTON BUILDER
-- =========================================================================

local function CreateBar10ActionButton(parent, slotID, size)
    local btnName = "Primus_PUIHud_Bar10_Button" .. slotID
    local btn = CreateFrame("CheckButton", btnName, parent, "ActionButtonTemplate")
    btn:SetWidth(size)
    btn:SetHeight(size)
    btn:SetID(slotID)
    btn.slotID = slotID
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:EnableMouse(true)

    -- Hide & neutralize legacy Blizzard 66x66 / 64x64 textures
    local normal = _G[btnName .. "NormalTexture"] or (btn.GetNormalTexture and btn:GetNormalTexture())
    if normal then
        normal:SetTexture("")
        normal:Hide()
        normal:SetAlpha(0)
        normal:ClearAllPoints()
        normal:SetAllPoints(btn)
        local origSetTexture = normal.SetTexture
        normal.SetTexture = function(self, tex)
            if tex == "Interface\\Buttons\\UI-Quickslot2" or tex == "Interface\\Buttons\\UI-Quickslot" then
                return origSetTexture(self, "")
            end
            return origSetTexture(self, tex)
        end
    end

    local border = _G[btnName .. "Border"]
    if border then
        border:Hide()
        border:SetAlpha(0)
    end

    local nameText = _G[btnName .. "Name"]
    if nameText then
        nameText:Hide()
    end

    -- Flash Texture
    local flash = _G[btnName .. "Flash"]
    if flash then
        flash:ClearAllPoints()
        flash:SetAllPoints(btn)
        flash:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    end

    -- Cooldown Frame Centering & Scaling
    local cooldown = _G[btnName .. "Cooldown"]
    if cooldown then
        cooldown:ClearAllPoints()
        cooldown:SetPoint("CENTER", btn, "CENTER", 0, 0)
        cooldown:SetWidth(36)
        cooldown:SetHeight(36)
        cooldown:SetScale((size - 2) / 36)
    end

    -- Pushed, Highlight, and Checked Textures
    local pushed = btn:GetPushedTexture()
    if pushed then
        pushed:ClearAllPoints()
        pushed:SetAllPoints(btn)
    end

    local highlight = btn:GetHighlightTexture()
    if highlight then
        highlight:ClearAllPoints()
        highlight:SetAllPoints(btn)
    end

    local checked = btn:GetCheckedTexture()
    if checked then
        checked:ClearAllPoints()
        checked:SetAllPoints(btn)
    end

    -- Background Tile
    if not btn._primusBg then
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(btn)
        bg:SetTexture(Media:Fetch("statusbar", "Default") or "Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0.06, 0.08, 0.10, 0.85)
        btn._primusBg = bg
    end

    -- Pure Scaling: Full native texture coordinates (0, 1, 0, 1)
    local icon = _G[btnName .. "Icon"]
    if icon then
        icon:SetTexCoord(0.0, 1.0, 0.0, 1.0)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    end

    local count = _G[btnName .. "Count"]
    if count then
        count:ClearAllPoints()
        count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        count:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    end

    local hotkey = _G[btnName .. "HotKey"]
    if hotkey then
        hotkey:ClearAllPoints()
        hotkey:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
        hotkey:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    end

    -- 1-Pixel Border Overlay
    if not btn._primusBorder then
        local b = CreateFrame("Frame", nil, btn)
        b:SetAllPoints(btn)
        b:SetBackdrop(Media:Fetch("border", "1Pixel"))
        b:SetBackdropColor(0, 0, 0, 0)
        b:SetBackdropBorderColor(0.20, 0.30, 0.45, 0.8)
        b:SetFrameLevel(btn:GetFrameLevel() + 2)
        btn._primusBorder = b
    end

    -- Native Action Handlers
    btn:SetScript("OnClick", function()
        if IsShiftKeyDown() then
            PickupAction(slotID)
        else
            if MacroFrame_SaveMacro then
                MacroFrame_SaveMacro()
            end
            UseAction(slotID, 1)
        end
        local isCurrent = IsCurrentAction(slotID) or IsAutoRepeatAction(slotID)
        btn:SetChecked(isCurrent and 1 or 0)
        PUIHud:UpdateCockpitButtons()
    end)

    btn:SetScript("OnDragStart", function()
        PickupAction(slotID)
    end)

    btn:SetScript("OnReceiveDrag", function()
        PlaceAction(slotID)
        PUIHud:UpdateCockpitButtons()
    end)

    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetAction(slotID)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    if Keybind and Keybind.RegisterHoverTarget then
        Keybind:RegisterHoverTarget(btn)
    end

    btn:SetChecked(0)
    table.insert(cockpitButtons, btn)
    return btn
end

-- =========================================================================
-- COCKPIT MINI-BARS BUILDER
-- =========================================================================

function PUIHud:BuildCockpitMiniBars(parent, leftWing, rightWing, bottomAnchor)
    local size = 26
    local spacing = 4

    -- 1. Left Wing Mini-Bar (Slots 109, 110, 111, 112) - Vertical on INSIDE of Left Wing
    cockpitBar1 = CreateFrame("Frame", "Primus_PUIHud_CockpitLeft", parent)
    cockpitBar1:SetWidth(size)
    cockpitBar1:SetHeight(4 * size + 3 * spacing)
    cockpitBar1:SetPoint("LEFT", leftWing, "RIGHT", 6, 0)

    for i = 1, 4 do
        local slotID = 108 + i -- 109, 110, 111, 112
        local b = CreateBar10ActionButton(cockpitBar1, slotID, size)
        b:SetPoint("TOPLEFT", cockpitBar1, "TOPLEFT", 0, -(i - 1) * (size + spacing))
    end

    -- 2. Right Wing Mini-Bar (Slots 113, 114, 115, 116) - Vertical on INSIDE of Right Wing
    cockpitBar2 = CreateFrame("Frame", "Primus_PUIHud_CockpitRight", parent)
    cockpitBar2:SetWidth(size)
    cockpitBar2:SetHeight(4 * size + 3 * spacing)
    cockpitBar2:SetPoint("RIGHT", rightWing, "LEFT", -6, 0)

    for i = 1, 4 do
        local slotID = 112 + i -- 113, 114, 115, 116
        local b = CreateBar10ActionButton(cockpitBar2, slotID, size)
        b:SetPoint("TOPLEFT", cockpitBar2, "TOPLEFT", 0, -(i - 1) * (size + spacing))
    end

    -- 3. Bottom Mini-Bar (Slots 117, 118, 119, 120) - Horizontal on INSIDE (Top of Timing Stack)
    cockpitBar3 = CreateFrame("Frame", "Primus_PUIHud_CockpitBottom", parent)
    cockpitBar3:SetWidth(4 * size + 3 * spacing)
    cockpitBar3:SetHeight(size)

    if bottomAnchor then
        cockpitBar3:SetPoint("TOP", bottomAnchor, "TOP", 0, 0)
    else
        cockpitBar3:SetPoint("BOTTOM", parent, "BOTTOM", 0, 30)
    end

    for i = 1, 4 do
        local slotID = 116 + i -- 117, 118, 119, 120
        local b = CreateBar10ActionButton(cockpitBar3, slotID, size)
        b:SetPoint("TOPLEFT", cockpitBar3, "TOPLEFT", (i - 1) * (size + spacing), 0)
    end

    self.cockpitBar1 = cockpitBar1
    self.cockpitBar2 = cockpitBar2
    self.cockpitBar3 = cockpitBar3
    self.cockpitButtons = cockpitButtons

    self:UpdateCockpitButtons()
end

-- =========================================================================
-- REAL-TIME COCKPIT BUTTONS STATE & COOLDOWN UPDATES
-- =========================================================================

function PUIHud:UpdateCockpitButtons()
    local hudDB = DB:GetNamespace("PUIHud")
    if hudDB and not hudDB:Get("showCockpitBars", true) then
        if cockpitBar1 then cockpitBar1:Hide() end
        if cockpitBar2 then cockpitBar2:Hide() end
        if cockpitBar3 then cockpitBar3:Hide() end
        return
    else
        if cockpitBar1 then cockpitBar1:Show() end
        if cockpitBar2 then cockpitBar2:Show() end
        if cockpitBar3 then cockpitBar3:Show() end
    end

    local count = table.getn(cockpitButtons)
    for i = 1, count do
        local btn = cockpitButtons[i]
        if btn then
            local slotID = btn.slotID
            local btnName = btn:GetName()
            local icon = _G[btnName .. "Icon"]
            local countText = _G[btnName .. "Count"]
            local cdFrame = _G[btnName .. "Cooldown"]
            local normal = _G[btnName .. "NormalTexture"] or (btn.GetNormalTexture and btn:GetNormalTexture())

            if normal then
                normal:SetTexture("")
                normal:Hide()
                normal:SetAlpha(0)
            end

            local texture = GetActionTexture(slotID)
            if texture and icon then
                icon:SetTexture(texture)
                icon:Show()

                -- Checked / Active Action State (Auto-attack, queued Heroic Strike, Auto Shot, etc.)
                local isChecked = IsCurrentAction(slotID) or IsAutoRepeatAction(slotID)
                if isChecked then
                    btn:SetChecked(1)
                    if btn._primusBorder then
                        btn._primusBorder:SetBackdropBorderColor(1.0, 0.85, 0.20, 1.0) -- Gold active highlight
                    end
                else
                    btn:SetChecked(0)
                    if btn._primusBorder then
                        btn._primusBorder:SetBackdropBorderColor(0.20, 0.30, 0.45, 0.8) -- Default sleek border
                    end
                end

                -- Stack / Reagent Count Update
                local numItems = GetActionCount(slotID)
                if countText then
                    if numItems and numItems > 1 then
                        countText:SetText(tostring(numItems))
                        countText:Show()
                    else
                        countText:Hide()
                    end
                end

                -- Cooldown Update
                if cdFrame and GetActionCooldown then
                    local start, duration, enable = GetActionCooldown(slotID)
                    CooldownFrame_SetTimer(cdFrame, start, duration, enable)
                end

                -- Range & Mana Tinting
                local inRange = IsActionInRange(slotID)
                local isUsable, notEnoughMana = IsUsableAction(slotID)

                if inRange == 0 and UnitExists("target") then
                    icon:SetVertexColor(0.85, 0.20, 0.20) -- Red (Out of Range of Target)
                elseif notEnoughMana then
                    icon:SetVertexColor(0.30, 0.30, 0.85) -- Blue (Out of Mana/Energy/Rage)
                elseif not isUsable then
                    icon:SetVertexColor(0.40, 0.40, 0.40) -- Grey (Unusable)
                else
                    icon:SetVertexColor(1.0, 1.0, 1.0)    -- Normal (Ready)
                end
            else
                if icon then icon:Hide() end
                if countText then countText:Hide() end
                if cdFrame and cdFrame.Hide then cdFrame:Hide() end
                btn:SetChecked(0)
                if btn._primusBorder then
                    btn._primusBorder:SetBackdropBorderColor(0.15, 0.18, 0.25, 0.6)
                end
            end
        end
    end
end
