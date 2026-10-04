--[[
    PrimusUI Core: Centralized Context Menu Framework (ContextMenu.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (Lua 5.0.2)
    Architecture: Strict TRUTH.md compliance (Dark Glass 1px Aesthetic, Zero GC Churn)

    Provides:
    - Replaces ad-hoc Blizzard UIDropDownMenu and custom flyouts with a unified,
      high-performance, dark glass 1-pixel border context menu popup.
    - Full support for headers, titles, icons, checkmarks, separators, disabled states,
      and custom text colors.
    - Automatic screen-clamping, cursor-docking, and click-outside dismissal.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local Widgets = Primus.Widgets or {}
Primus.Widgets = Widgets

local Media = Primus.Media
local Utils = Primus.Utils

-- Menu state handles
local menuFrame = nil
local catcherFrame = nil
local menuButtons = {}
local ITEM_HEIGHT = 20
local MIN_WIDTH = 150

--------------------------------------------------------------------------------
-- Build / Acquire Master Context Menu Frame
--------------------------------------------------------------------------------
local function CreateContextMenuFrame()
    if menuFrame then return menuFrame end

    -- Click Catcher (Full Screen transparent overlay to close on outside click)
    local catcher = CreateFrame("Button", "Primus_ContextMenu_Catcher", UIParent)
    catcher:SetFrameStrata("DIALOG")
    catcher:SetFrameLevel(140)
    catcher:SetAllPoints(UIParent)
    catcher:EnableMouse(true)
    catcher:Hide()
    catcher:SetScript("OnClick", function()
        Widgets:HideContextMenu()
    end)
    catcherFrame = catcher

    -- Master Floating Menu Container
    local f = CreateFrame("Frame", "Primus_ContextMenu", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(150)
    f:SetWidth(MIN_WIDTH)
    f:SetHeight(100)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    f:SetBackdropColor(0.06, 0.08, 0.12, 0.98)
    f:SetBackdropBorderColor(0.20, 0.45, 0.75, 0.9)
    f:Hide()

    table.insert(UISpecialFrames, "Primus_ContextMenu")
    menuFrame = f
    return menuFrame
end

--------------------------------------------------------------------------------
-- Button Item Allocator
--------------------------------------------------------------------------------
local function AcquireMenuButton(index)
    if menuButtons[index] then
        return menuButtons[index]
    end

    local btn = CreateFrame("Button", "Primus_ContextMenu_Item_" .. index, menuFrame)
    btn:SetHeight(ITEM_HEIGHT)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    btn:SetBackdropColor(0, 0, 0, 0)

    -- Icon texture
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(14)
    icon:SetHeight(14)
    icon:SetPoint("LEFT", btn, "LEFT", 6, 0)
    icon:Hide()
    btn.icon = icon

    -- Checkmark indicator
    local check = btn:CreateFontString(nil, "OVERLAY")
    local font = (Media and Media.Fetch and Media:Fetch("font", "Default")) or "Fonts\\FRIZQT__.TTF"
    check:SetFont(font, 10, "OUTLINE")
    check:SetPoint("LEFT", btn, "LEFT", 6, 0)
    check:SetText("|cff00ff00✓|r")
    check:Hide()
    btn.check = check

    -- Main Text Label
    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetFont(font, 10, "")
    label:SetPoint("LEFT", btn, "LEFT", 22, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    label:SetJustifyH("LEFT")
    btn.label = label

    -- Subtitle / Extra Right-Aligned Text
    local rightLabel = btn:CreateFontString(nil, "OVERLAY")
    rightLabel:SetFont(font, 9, "")
    rightLabel:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    rightLabel:SetJustifyH("RIGHT")
    rightLabel:SetTextColor(0.6, 0.6, 0.6, 1.0)
    btn.rightLabel = rightLabel

    -- Separator line (for separator items)
    local sep = btn:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("LEFT", btn, "LEFT", 4, 0)
    sep:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    sep:SetTexture("Interface\\Buttons\\WHITE8X8")
    sep:SetVertexColor(0.25, 0.30, 0.40, 0.8)
    sep:Hide()
    btn.separator = sep

    -- Mouse Hover scripts
    btn:SetScript("OnEnter", function()
        if not this.isTitle and not this.disabled and not this.isSeparator then
            this:SetBackdropColor(0.15, 0.35, 0.65, 0.8)
            this.label:SetTextColor(1, 1, 1, 1)
        end
    end)

    btn:SetScript("OnLeave", function()
        if not this.isTitle and not this.disabled and not this.isSeparator then
            this:SetBackdropColor(0, 0, 0, 0)
            if this.itemColor then
                this.label:SetTextColor(this.itemColor.r or 0.9, this.itemColor.g or 0.9, this.itemColor.b or 0.9, 1.0)
            else
                this.label:SetTextColor(0.9, 0.9, 0.9, 1.0)
            end
        end
    end)

    btn:SetScript("OnClick", function()
        if this.disabled or this.isTitle or this.isSeparator then return end
        local item = this.itemData
        if item and item.func then
            local success, err = pcall(item.func, item)
            if not success and Primus.Log then
                Primus:Log("ContextMenu action error: " .. tostring(err), "ERROR")
            end
        end
        if not item or not item.keepShown then
            Widgets:HideContextMenu()
        end
    end)

    menuButtons[index] = btn
    return btn
end

--------------------------------------------------------------------------------
-- Public Context Menu API
--------------------------------------------------------------------------------
function Widgets:HideContextMenu()
    if menuFrame then
        menuFrame:Hide()
    end
    if catcherFrame then
        catcherFrame:Hide()
    end
end

function Widgets:IsContextMenuShown()
    return menuFrame and menuFrame:IsShown()
end

function Widgets:ShowContextMenu(anchorOrPoint, items, options)
    if not items or table.getn(items) == 0 then return end
    options = options or {}

    local f = CreateContextMenuFrame()
    f:Hide()

    -- Calculate Width & Populate Buttons
    local maxTextWidth = 100
    local visibleCount = 0
    local totalHeight = 8

    -- Hide all existing buttons
    for i = 1, table.getn(menuButtons) do
        menuButtons[i]:Hide()
    end

    local numItems = table.getn(items)
    for i = 1, numItems do
        local item = items[i]
        if item then
            visibleCount = visibleCount + 1
            local btn = AcquireMenuButton(visibleCount)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4 - (visibleCount - 1) * ITEM_HEIGHT)
            btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4 - (visibleCount - 1) * ITEM_HEIGHT)
            btn:SetBackdropColor(0, 0, 0, 0)

            btn.itemData = item
            btn.isTitle = item.isTitle or false
            btn.disabled = item.disabled or false
            btn.isSeparator = item.isSeparator or false
            btn.itemColor = nil

            if item.isSeparator then
                btn.label:Hide()
                btn.icon:Hide()
                btn.check:Hide()
                btn.rightLabel:Hide()
                btn.separator:Show()
                btn:EnableMouse(false)
            else
                btn.separator:Hide()
                btn:EnableMouse(not item.isTitle and not item.disabled)

                -- Icon or Checkmark
                if item.icon then
                    btn.icon:SetTexture(item.icon)
                    btn.icon:Show()
                    btn.check:Hide()
                    btn.label:SetPoint("LEFT", btn, "LEFT", 24, 0)
                elseif item.checked ~= nil then
                    btn.icon:Hide()
                    if item.checked then
                        btn.check:SetText("|cff00ff00✓|r")
                        btn.check:Show()
                    else
                        btn.check:Hide()
                    end
                    btn.label:SetPoint("LEFT", btn, "LEFT", 22, 0)
                else
                    btn.icon:Hide()
                    btn.check:Hide()
                    btn.label:SetPoint("LEFT", btn, "LEFT", 8, 0)
                end

                -- Label text & color
                btn.label:Show()
                btn.label:SetText(item.text or "")

                if item.isTitle then
                    btn.label:SetTextColor(0.95, 0.78, 0.20, 1.0) -- Gold Title
                elseif item.disabled then
                    btn.label:SetTextColor(0.45, 0.45, 0.45, 1.0) -- Disabled Gray
                elseif item.color then
                    if type(item.color) == "table" then
                        btn.itemColor = item.color
                        btn.label:SetTextColor(item.color.r or 1, item.color.g or 1, item.color.b or 1, item.color.a or 1)
                    else
                        btn.label:SetText(Utils.ColorText(item.text or "", item.color))
                    end
                else
                    btn.label:SetTextColor(0.9, 0.9, 0.9, 1.0)
                end

                -- Right Label
                if item.rightText then
                    btn.rightLabel:SetText(item.rightText)
                    btn.rightLabel:Show()
                else
                    btn.rightLabel:Hide()
                end

                -- Measure string width
                local strW = btn.label:GetStringWidth() or 80
                if item.rightText then
                    strW = strW + (btn.rightLabel:GetStringWidth() or 0) + 16
                end
                if strW > maxTextWidth then
                    maxTextWidth = strW
                end
            end

            btn:Show()
        end
    end

    local finalWidth = math.max(maxTextWidth + 36, options.minWidth or MIN_WIDTH)
    local finalHeight = visibleCount * ITEM_HEIGHT + 8
    f:SetWidth(finalWidth)
    f:SetHeight(finalHeight)

    -- Anchor Positioning
    f:ClearAllPoints()
    if anchorOrPoint == "CURSOR" then
        local cx, cy = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale() or 1
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale + 2, cy / scale - 2)
    elseif type(anchorOrPoint) == "table" and anchorOrPoint.GetCenter then
        local anchorPoint = options.point or "TOPLEFT"
        local relPoint = options.relPoint or "BOTTOMLEFT"
        local xOff = options.xOffset or 0
        local yOff = options.yOffset or -2
        f:SetPoint(anchorPoint, anchorOrPoint, relPoint, xOff, yOff)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    if catcherFrame then catcherFrame:Show() end
    f:Show()
end
