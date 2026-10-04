--[[
    PrimusLib: Encapsulated Widget Factory
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides fluent, programmatic builders for modern-styled Vanilla UI elements:
    Panels, Buttons, StatusBars, CheckButtons, Sliders, ScrollFrames, and ItemSlots.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local Anim    = Primus.Anim
local Skinner = Primus.Skinner

local widgetIDCounter = 0
local function NextWidgetName(prefix)
    widgetIDCounter = widgetIDCounter + 1
    return string.format("PrimusWidget_%s_%d", prefix or "Element", widgetIDCounter)
end

-- =========================================================================
-- BASE PANEL BUILDER
-- =========================================================================

function Widgets:CreatePanel(parent, title, width, height)
    parent = parent or UIParent
    width  = width or 300
    height = height or 200

    local frame = CreateFrame("Frame", NextWidgetName("Panel"), parent)
    frame:SetWidth(width)
    frame:SetHeight(height)
    frame:SetPoint("CENTER", 0, 0)

    if Skinner and Skinner.SkinFrame then
        Skinner:SkinFrame(frame)
    else
        frame:SetBackdrop(Media:Fetch("border", "1Pixel"))
        frame:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
        frame:SetBackdropBorderColor(0.20, 0.20, 0.25, 1.0)
    end
    frame:EnableMouse(true)
    frame:SetMovable(true)

    -- Header / Title
    if title then
        local header = frame:CreateFontString(nil, "OVERLAY")
        header:SetFont(Media:Fetch("font", "Default"), 12, "OUTLINE")
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)
        header:SetText(Utils.ColorText(title, "69ccf0"))
        frame.titleText = header
    end

    -- Close Button
    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetWidth(18)
    closeBtn:SetHeight(18)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    
    if Skinner and Skinner.SkinCloseButton then
        Skinner:SkinCloseButton(closeBtn)
    else
        local closeText = closeBtn:CreateFontString(nil, "OVERLAY")
        closeText:SetFont(Media:Fetch("font", "Default"), 12, "OUTLINE")
        closeText:SetPoint("CENTER", 0, 0)
        closeText:SetText("x")
        closeText:SetTextColor(0.8, 0.8, 0.8)

        closeBtn:SetScript("OnEnter", function() closeText:SetTextColor(1, 0.2, 0.2) end)
        closeBtn:SetScript("OnLeave", function() closeText:SetTextColor(0.8, 0.8, 0.8) end)
    end
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    frame.closeButton = closeBtn

    return frame
end

-- =========================================================================
-- BUTTON BUILDER
-- =========================================================================

function Widgets:CreateButton(parent, text, width, height, onClick)
    parent = parent or UIParent
    width  = width or 100
    height = height or 24

    local btn = CreateFrame("Button", NextWidgetName("Button"), parent)
    btn:SetWidth(width)
    btn:SetHeight(height)

    if Skinner and Skinner.SkinButton then
        Skinner:SkinButton(btn, text)
    else
        btn:SetBackdrop(Media:Fetch("border", "1Pixel"))
        btn:SetBackdropColor(0.15, 0.15, 0.18, 1.0)
        btn:SetBackdropBorderColor(0.30, 0.30, 0.35, 1.0)

        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetFont(Media:Fetch("font", "Default"), 11, "OUTLINE")
        label:SetPoint("CENTER", 0, 0)
        label:SetText(text or "Button")
        label:SetTextColor(0.9, 0.9, 0.9)
        btn.text = label

        btn:SetScript("OnEnter", function()
            btn:SetBackdropColor(0.25, 0.25, 0.30, 1.0)
            btn:SetBackdropBorderColor(0.40, 0.70, 1.00, 1.0)
        end)
        btn:SetScript("OnLeave", function()
            btn:SetBackdropColor(0.15, 0.15, 0.18, 1.0)
            btn:SetBackdropBorderColor(0.30, 0.30, 0.35, 1.0)
        end)
    end

    if not btn.text then
        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetFont(Media:Fetch("font", "Default"), 11, "OUTLINE")
        label:SetPoint("CENTER", 0, 0)
        label:SetText(text or "Button")
        label:SetTextColor(0.9, 0.9, 0.9)
        btn.text = label
    end

    if onClick then
        btn:SetScript("OnClick", onClick)
    end

    function btn:SetButtonText(t)
        if self.text then self.text:SetText(t) end
        if self.SetText then self:SetText(t) end
    end

    return btn
end

-- =========================================================================
-- STATUS BAR BUILDER (Health / Mana / Cast Bars)
-- =========================================================================

function Widgets:CreateStatusBar(parent, width, height, minVal, maxVal)
    parent = parent or UIParent
    width  = width or 150
    height = height or 16

    local bar = CreateFrame("StatusBar", NextWidgetName("StatusBar"), parent)
    bar:SetWidth(width)
    bar:SetHeight(height)
    bar:SetStatusBarTexture(Media:Fetch("statusbar", "Default"))
    bar:SetMinMaxValues(minVal or 0, maxVal or 100)
    bar:SetValue(maxVal or 100)

    -- Background
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetTexture(Media:Fetch("statusbar", "Default"))
    bg:SetVertexColor(0.1, 0.1, 0.1, 0.6)
    bar.bg = bg

    -- Border
    local border = CreateFrame("Frame", nil, bar)
    border:SetAllPoints(bar)
    border:SetBackdrop(Media:Fetch("border", "1Pixel"))
    border:SetBackdropColor(0, 0, 0, 0)
    border:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    bar.border = border

    -- Text overlay
    local text = bar:CreateFontString(nil, "OVERLAY")
    text:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.text = text

    function bar:SetSmoothValue(val, duration)
        Anim:SmoothBar(self, val, duration)
    end

    return bar
end

-- =========================================================================
-- CHECK BUTTON BUILDER
-- =========================================================================

function Widgets:CreateCheckButton(parent, labelText, defaultChecked, onToggle)
    local cb = CreateFrame("CheckButton", NextWidgetName("CheckBtn"), parent, "UICheckButtonTemplate")
    cb:SetWidth(20)
    cb:SetHeight(20)

    local origSetChecked = cb.SetChecked
    local origGetChecked = cb.GetChecked

    if defaultChecked then
        origSetChecked(cb, 1)
    else
        origSetChecked(cb, 0)
    end

    local text = cb:CreateFontString(nil, "OVERLAY")
    text:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetText(labelText or "")
    text:SetTextColor(0.9, 0.9, 0.9)
    cb.text = text
    cb.onToggle = onToggle

    -- Expand clickable hit area over label text
    cb:SetHitRectInsets(0, -220, 0, 0)

    cb:SetScript("OnClick", function()
        local raw = origGetChecked(this)
        local isChecked = (raw == 1 or raw == true) and true or false
        if onToggle then
            onToggle(isChecked)
        end
    end)

    cb:SetScript("OnEnter", function()
        text:SetTextColor(1, 1, 1)
    end)
    cb:SetScript("OnLeave", function()
        text:SetTextColor(0.9, 0.9, 0.9)
    end)

    function cb:SetChecked(val)
        if val and val ~= 0 then
            origSetChecked(self, 1)
        else
            origSetChecked(self, 0)
        end
    end

    function cb:GetChecked()
        local raw = origGetChecked(self)
        return (raw == 1 or raw == true) and true or false
    end

    return cb
end

-- =========================================================================
-- SLIDER BUILDER
-- =========================================================================

function Widgets:CreateSlider(parent, labelText, minVal, maxVal, step, defaultVal, onValueChanged)
    local frame = CreateFrame("Frame", NextWidgetName("SliderGroup"), parent)
    frame:SetWidth(180)
    frame:SetHeight(36)

    local slider = CreateFrame("Slider", NextWidgetName("Slider"), frame, "OptionsSliderTemplate")
    slider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    slider:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    slider:SetHeight(14)
    slider:SetMinMaxValues(minVal or 0, maxVal or 100)
    slider:SetValueStep(step or 1)
    slider:SetValue(defaultVal or minVal or 0)

    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    title:SetText(labelText or "")
    frame.title = title

    local valText = frame:CreateFontString(nil, "OVERLAY")
    valText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    valText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    valText:SetTextColor(0.4, 0.8, 1.0)
    valText:SetText(string.format("%.1f", defaultVal or minVal or 0))
    frame.valText = valText

    slider:SetScript("OnValueChanged", function()
        local val = this:GetValue()
        valText:SetText(string.format("%.1f", val))
        if onValueChanged then
            onValueChanged(val)
        end
    end)

    frame.slider = slider
    return frame
end

-- =========================================================================
-- ITEM SLOT BUTTON BUILDER (Bags, Bank, Paperdoll, ActionBars)
-- =========================================================================

function Widgets:CreateItemSlot(parent, size)
    size = size or 36
    local slot = CreateFrame("Button", NextWidgetName("ItemSlot"), parent)
    slot:SetWidth(size)
    slot:SetHeight(size)
    slot:SetBackdrop(Media:Fetch("border", "1Pixel"))
    slot:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
    slot:SetBackdropBorderColor(0.25, 0.25, 0.30, 1)

    -- Icon Texture
    local icon = slot:CreateTexture(nil, "BORDER")
    icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    slot.icon = icon

    -- Stack Count
    local count = slot:CreateFontString(nil, "OVERLAY")
    count:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -2, 2)
    slot.count = count

    -- Cooldown Frame
    local cd = CreateFrame("Model", NextWidgetName("Cooldown"), slot, "CooldownFrameTemplate")
    cd:ClearAllPoints()
    cd:SetPoint("CENTER", slot, "CENTER", 0, 0)
    cd:SetWidth(36)
    cd:SetHeight(36)
    cd:SetScale((size - 2) / 36)
    slot.cooldown = cd

    return slot
end

-- =========================================================================
-- LAYOUT HELPERS (Automatic Alignment)
-- =========================================================================

function Widgets:LayoutHorizontal(frameList, spacing, parent, anchorPoint)
    spacing = spacing or 5
    anchorPoint = anchorPoint or "TOPLEFT"
    local count = table.getn(frameList)
    for i = 1, count do
        local f = frameList[i]
        f:ClearAllPoints()
        if i == 1 then
            f:SetPoint(anchorPoint, parent, anchorPoint, 0, 0)
        else
            f:SetPoint("LEFT", frameList[i - 1], "RIGHT", spacing, 0)
        end
    end
end

function Widgets:LayoutVertical(frameList, spacing, parent, anchorPoint)
    spacing = spacing or 5
    anchorPoint = anchorPoint or "TOPLEFT"
    local count = table.getn(frameList)
    for i = 1, count do
        local f = frameList[i]
        f:ClearAllPoints()
        if i == 1 then
            f:SetPoint(anchorPoint, parent, anchorPoint, 0, 0)
        else
            f:SetPoint("TOP", frameList[i - 1], "BOTTOM", 0, -spacing)
        end
    end
end
