--[[
    PrimusLib: Universal Window & Widget Skinning Engine (Primus.Skinner)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    1. Atomic Visual Mechanics:
       - Canvas Texture (Solid, Dialog, Tooltip)
       - Glass Opacity Slider (50% to 100% solid)
       - Border Style (1Pixel, Dialog Brass, Tooltip Bevel, Borderless)
       - Accent Glow (Class Color, Cyan, Gold, Purple, Custom RGB)
       - Tab & Button Styles (Flat Underline vs Classic Blizzard)
    2. Curated Preset Recipes (Blizz-Like Default, Dark Glass, Onyx Gold, Void Purple, Midnight Navy, Minimal Matte).
    3. Live In-Memory Repainting without requiring client /reload.
    4. Shareable Theme String Exporter / Importer.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local Skinner = Primus.Skinner or {}
Primus.Skinner = Skinner
Skinner.name = "Skinner"
Skinner.enabled = true
Primus:RegisterModule("Skinner", Skinner, "Core")
Skinner.enabled = true

local Media  = Primus.Media
local Utils  = Primus.Utils
local Events = Primus.Events

-- Registered Skinned Frame Registry for Live Theme Repainting
local registeredFrames = {}
local registeredButtons = {}
local registeredTabs = {}
local registeredEditBoxes = {}
local repaintCallbacks = {}

-- Register DB Namespace with default "BlizzLike" recipe
local skinnerDB = Primus.DB and Primus.DB:RegisterNamespace("Skinner", {
    preset               = "BlizzLike",
    canvasTexture        = "Dialog",     -- "Dialog", "Solid", "Tooltip"
    backdropOpacity      = 0.95,         -- 0.50 to 1.00
    backdropColor        = { 0.12, 0.10, 0.08 },
    borderStyle          = "Dialog",     -- "Dialog", "1Pixel", "Tooltip", "None"
    borderColor          = { 0.85, 0.75, 0.50 },
    borderOpacity        = 1.0,
    accentColor          = { 1.00, 0.82, 0.00 },
    useClassColorAccent  = false,
    buttonStyle          = "Blizz",      -- "Blizz", "Flat"
    tabStyle             = "Classic",    -- "Classic", "Underline"
    headerFont           = "Morpheus",   -- "Morpheus", "Default", "Arial", "Skurri"
    bodyFont             = "Default",
})
Skinner.db = skinnerDB

-- Register a custom repaint callback
function Skinner:RegisterCallback(name, fn)
    if name and fn then
        repaintCallbacks[name] = fn
    end
end

-- =========================================================================
-- CURATED PRESET RECIPES
-- =========================================================================

Skinner.presets = {
    BlizzLike = {
        name = "Blizz-Like (Classic 2004)",
        canvasTexture = "Dialog",
        backdropOpacity = 0.95,
        backdropColor = { 0.12, 0.10, 0.08 },
        borderStyle = "Dialog",
        borderColor = { 0.85, 0.75, 0.50 },
        borderOpacity = 1.0,
        accentColor = { 1.00, 0.82, 0.00 },
        useClassColorAccent = false,
        buttonStyle = "Blizz",
        tabStyle = "Classic",
        headerFont = "Morpheus",
    },
    DarkGlass = {
        name = "Dark Glass (Cyan)",
        canvasTexture = "Solid",
        backdropOpacity = 0.95,
        backdropColor = { 0.06, 0.06, 0.09 },
        borderStyle = "1Pixel",
        borderColor = { 0.20, 0.20, 0.25 },
        borderOpacity = 1.0,
        accentColor = { 0.20, 0.75, 1.00 },
        useClassColorAccent = false,
        buttonStyle = "Flat",
        tabStyle = "Underline",
        headerFont = "Default",
    },
    OnyxGold = {
        name = "Onyx Gold",
        canvasTexture = "Solid",
        backdropOpacity = 0.98,
        backdropColor = { 0.03, 0.03, 0.04 },
        borderStyle = "1Pixel",
        borderColor = { 0.50, 0.40, 0.15 },
        borderOpacity = 1.0,
        accentColor = { 1.00, 0.84, 0.00 },
        useClassColorAccent = false,
        buttonStyle = "Flat",
        tabStyle = "Underline",
        headerFont = "Default",
    },
    VoidPurple = {
        name = "Void Purple",
        canvasTexture = "Solid",
        backdropOpacity = 0.95,
        backdropColor = { 0.05, 0.03, 0.08 },
        borderStyle = "1Pixel",
        borderColor = { 0.35, 0.20, 0.55 },
        borderOpacity = 1.0,
        accentColor = { 0.75, 0.40, 1.00 },
        useClassColorAccent = false,
        buttonStyle = "Flat",
        tabStyle = "Underline",
        headerFont = "Default",
    },
    MidnightNavy = {
        name = "Midnight Navy",
        canvasTexture = "Solid",
        backdropOpacity = 0.95,
        backdropColor = { 0.02, 0.04, 0.08 },
        borderStyle = "1Pixel",
        borderColor = { 0.15, 0.28, 0.48 },
        borderOpacity = 1.0,
        accentColor = { 0.40, 0.80, 1.00 },
        useClassColorAccent = false,
        buttonStyle = "Flat",
        tabStyle = "Underline",
        headerFont = "Default",
    },
    MinimalMatte = {
        name = "Minimal Matte (White)",
        canvasTexture = "Solid",
        backdropOpacity = 1.00,
        backdropColor = { 0.08, 0.08, 0.08 },
        borderStyle = "1Pixel",
        borderColor = { 0.18, 0.18, 0.18 },
        borderOpacity = 1.0,
        accentColor = { 0.90, 0.90, 0.90 },
        useClassColorAccent = false,
        buttonStyle = "Flat",
        tabStyle = "Underline",
        headerFont = "Default",
    },
}

-- Apply a Preset Recipe to DB and Repaint
function Skinner:ApplyPreset(presetKey)
    local p = self.presets[presetKey]
    if not p then return end

    local db = self.db
    if db then
        db:Set("preset", presetKey)
        db:Set("canvasTexture", p.canvasTexture)
        db:Set("backdropOpacity", p.backdropOpacity)
        db:Set("backdropColor", p.backdropColor)
        db:Set("borderStyle", p.borderStyle)
        db:Set("borderColor", p.borderColor)
        db:Set("borderOpacity", p.borderOpacity)
        db:Set("accentColor", p.accentColor)
        db:Set("useClassColorAccent", p.useClassColorAccent)
        db:Set("buttonStyle", p.buttonStyle)
        db:Set("tabStyle", p.tabStyle)
        db:Set("headerFont", p.headerFont)
    end

    self:RepaintAll()
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PrimusSkinner]: Applied Theme Preset: %s", p.name), "69ccf0"))
end

-- =========================================================================
-- COLOR & BACKDROP GENERATOR
-- =========================================================================

function Skinner:GetBackdropColor()
    local db = self.db
    local col = db and db:Get("backdropColor", { 0.12, 0.10, 0.08 }) or { 0.12, 0.10, 0.08 }
    local a = db and db:Get("backdropOpacity", 0.95) or 0.95
    return col[1] or 0.1, col[2] or 0.1, col[3] or 0.1, a
end

function Skinner:GetBorderColor()
    local db = self.db
    local col = db and db:Get("borderColor", { 0.85, 0.75, 0.50 }) or { 0.85, 0.75, 0.50 }
    local a = db and db:Get("borderOpacity", 1.0) or 1.0
    return col[1] or 0.8, col[2] or 0.7, col[3] or 0.5, a
end

function Skinner:GetAccentColor()
    local db = self.db
    if db and db:Get("useClassColorAccent", false) then
        local _, class = UnitClass("player")
        local cColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if cColor then
            return cColor.r, cColor.g, cColor.b, 1.0
        end
    end
    local col = db and db:Get("accentColor", { 1.00, 0.82, 0.00 }) or { 1.00, 0.82, 0.00 }
    return col[1] or 1.0, col[2] or 0.82, col[3] or 0.0, 1.0
end

function Skinner:GetBackdropDescriptor()
    local db = self.db
    local bStyle = db and db:Get("borderStyle", "Dialog") or "Dialog"
    return Media:Fetch("border", bStyle) or Media:Fetch("border", "1Pixel")
end

-- =========================================================================
-- UNIVERSAL SKINNING PRIMITIVES
-- =========================================================================

-- Skin Container Frame
function Skinner:SkinFrame(frame, customBackdrop)
    if not frame then return end
    
    local bd = customBackdrop or self:GetBackdropDescriptor()
    frame:SetBackdrop(bd)
    local r, g, b, a = self:GetBackdropColor()
    local br, bg, bb, ba = self:GetBorderColor()
    frame:SetBackdropColor(r, g, b, a)
    frame:SetBackdropBorderColor(br, bg, bb, ba)
    frame.primusSkinned = true

    registeredFrames[frame] = true
end

-- Skin Push Button
function Skinner:SkinButton(btn, text, isAccent)
    if not btn then return end
    btn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    
    local r, g, b, a = self:GetBackdropColor()
    local br, bg, bb, ba = self:GetBorderColor()
    if isAccent then
        br, bg, bb, ba = self:GetAccentColor()
    end

    btn:SetBackdropColor(r * 1.3, g * 1.3, b * 1.3, a)
    btn:SetBackdropBorderColor(br, bg, bb, ba)
    if text and btn.SetText then btn:SetText(text) end

    local ar, ag, ab, aa = self:GetAccentColor()

    btn:SetScript("OnEnter", function()
        btn:SetBackdropColor(r * 1.8, g * 1.8, b * 1.8, 1.0)
        btn:SetBackdropBorderColor(ar, ag, ab, 1.0)
    end)
    btn:SetScript("OnLeave", function()
        btn:SetBackdropColor(r * 1.3, g * 1.3, b * 1.3, a)
        btn:SetBackdropBorderColor(br, bg, bb, ba)
    end)

    btn.primusSkinned = true
    registeredButtons[btn] = { isAccent = isAccent }
end

-- Skin Tab Button
function Skinner:SkinTab(tab)
    if not tab then return end
    local tabName = tab:GetName()
    if tabName then
        if _G[tabName .. "Left"] then _G[tabName .. "Left"]:Hide() end
        if _G[tabName .. "Middle"] then _G[tabName .. "Middle"]:Hide() end
        if _G[tabName .. "Right"] then _G[tabName .. "Right"]:Hide() end
        if _G[tabName .. "LeftDisabled"] then _G[tabName .. "LeftDisabled"]:Hide() end
        if _G[tabName .. "MiddleDisabled"] then _G[tabName .. "MiddleDisabled"]:Hide() end
        if _G[tabName .. "RightDisabled"] then _G[tabName .. "RightDisabled"]:Hide() end
    end

    tab:SetBackdrop(Media:Fetch("border", "1Pixel"))
    local r, g, b, a = self:GetBackdropColor()
    local br, bg, bb, ba = self:GetBorderColor()
    tab:SetBackdropColor(r, g, b, 0.90)
    tab:SetBackdropBorderColor(br, bg, bb, ba)

    -- Accent underline active indicator
    if not tab.primusIndicator then
        local indicator = tab:CreateTexture(nil, "OVERLAY")
        indicator:SetTexture(Media:Fetch("texture", "Solid") or "Interface\\Buttons\\WHITE8X8")
        local ar, ag, ab, aa = self:GetAccentColor()
        indicator:SetVertexColor(ar, ag, ab, aa)
        indicator:SetHeight(2)
        indicator:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 2, 1)
        indicator:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -2, 1)
        indicator:Hide()
        tab.primusIndicator = indicator
    end

    tab.primusSkinned = true
    registeredTabs[tab] = true
end

-- Skin EditBox
function Skinner:SkinEditBox(editBox)
    if not editBox then return end
    editBox:SetBackdrop(Media:Fetch("border", "1Pixel"))
    local r, g, b, a = self:GetBackdropColor()
    local br, bg, bb, ba = self:GetBorderColor()
    editBox:SetBackdropColor(r * 0.7, g * 0.7, b * 0.7, 0.95)
    editBox:SetBackdropBorderColor(br, bg, bb, ba)
    editBox:SetTextInsets(4, 4, 0, 0)
    editBox.primusSkinned = true
    registeredEditBoxes[editBox] = true
end

-- Skin ScrollBar
function Skinner:SkinScrollBar(scrollBar)
    if not scrollBar then return end
    local scrollName = scrollBar:GetName()
    if scrollName then
        if _G[scrollName .. "BG"] then _G[scrollName .. "BG"]:Hide() end
        if _G[scrollName .. "Top"] then _G[scrollName .. "Top"]:Hide() end
        if _G[scrollName .. "Bottom"] then _G[scrollName .. "Bottom"]:Hide() end
        if _G[scrollName .. "Middle"] then _G[scrollName .. "Middle"]:Hide() end
    end

    local thumb = scrollBar:GetThumbTexture() or (scrollName and _G[scrollName .. "ThumbTexture"])
    if thumb then
        thumb:SetTexture(Media:Fetch("texture", "Solid") or "Interface\\Buttons\\WHITE8X8")
        local ar, ag, ab, aa = self:GetAccentColor()
        thumb:SetVertexColor(ar, ag, ab, 0.7)
        thumb:SetWidth(6)
    end
    scrollBar.primusSkinned = true
end

-- Skin Flat Minimal Close Button
function Skinner:SkinCloseButton(closeBtn)
    if not closeBtn then return end
    closeBtn:SetWidth(16)
    closeBtn:SetHeight(16)
    
    local normalTex = closeBtn:GetNormalTexture()
    if normalTex then normalTex:SetAlpha(0) end
    local pushedTex = closeBtn:GetPushedTexture()
    if pushedTex then pushedTex:SetAlpha(0) end
    local highlightTex = closeBtn:GetHighlightTexture()
    if highlightTex then highlightTex:SetAlpha(0) end

    if not closeBtn.text then
        local txt = closeBtn:CreateFontString(nil, "OVERLAY")
        txt:SetFont(Media:Fetch("font", "Default"), 11, "OUTLINE")
        txt:SetPoint("CENTER", 0, 0)
        txt:SetText("x")
        txt:SetTextColor(0.7, 0.7, 0.7)
        closeBtn.text = txt

        closeBtn:SetScript("OnEnter", function()
            txt:SetTextColor(1.0, 0.3, 0.3)
        end)
        closeBtn:SetScript("OnLeave", function()
            txt:SetTextColor(0.7, 0.7, 0.7)
        end)
    end
    closeBtn.primusSkinned = true
end

-- Skin CheckBox
function Skinner:SkinCheckBox(checkBtn)
    if not checkBtn then return end
    checkBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    local r, g, b, a = self:GetBackdropColor()
    local br, bg, bb, ba = self:GetBorderColor()
    checkBtn:SetBackdropColor(r * 0.7, g * 0.7, b * 0.7, 0.95)
    checkBtn:SetBackdropBorderColor(br, bg, bb, ba)
    checkBtn.primusSkinned = true
end

-- =========================================================================
-- LIVE IN-MEMORY REPAINT ENGINE
-- =========================================================================

function Skinner:RepaintAll()
    local bd = self:GetBackdropDescriptor()
    local r, g, b, a = self:GetBackdropColor()
    local br, bg, bb, ba = self:GetBorderColor()
    local ar, ag, ab, aa = self:GetAccentColor()

    for frame in pairs(registeredFrames) do
        if frame and frame.SetBackdrop then
            frame:SetBackdrop(bd)
            frame:SetBackdropColor(r, g, b, a)
            frame:SetBackdropBorderColor(br, bg, bb, ba)
        end
    end

    for btn, info in pairs(registeredButtons) do
        if btn and btn.SetBackdropColor then
            local ob_r, ob_g, ob_b, ob_a = br, bg, bb, ba
            if info and info.isAccent then
                ob_r, ob_g, ob_b, ob_a = ar, ag, ab, aa
            end
            btn:SetBackdropColor(r * 1.3, g * 1.3, b * 1.3, a)
            btn:SetBackdropBorderColor(ob_r, ob_g, ob_b, ob_a)
        end
    end

    for tab in pairs(registeredTabs) do
        if tab and tab.SetBackdropColor then
            tab:SetBackdropColor(r, g, b, 0.90)
            tab:SetBackdropBorderColor(br, bg, bb, ba)
            if tab.primusIndicator then
                tab.primusIndicator:SetVertexColor(ar, ag, ab, aa)
            end
        end
    end

    for eb in pairs(registeredEditBoxes) do
        if eb and eb.SetBackdropColor then
            eb:SetBackdropColor(r * 0.7, g * 0.7, b * 0.7, 0.95)
            eb:SetBackdropBorderColor(br, bg, bb, ba)
        end
    end

    for name, cb in pairs(repaintCallbacks) do
        if type(cb) == "function" then
            pcall(cb, bd, r, g, b, a, br, bg, bb, ba, ar, ag, ab, aa)
        end
    end
end

-- =========================================================================
-- THEME STRING EXPORT / IMPORT
-- =========================================================================

function Skinner:ExportThemeString()
    local db = self.db
    if not db then return "" end
    local bStyle = db:Get("borderStyle", "Dialog")
    local op = math.floor((db:Get("backdropOpacity", 0.95)) * 100)
    local bgCol = db:Get("backdropColor", { 0.12, 0.10, 0.08 })
    local brCol = db:Get("borderColor", { 0.85, 0.75, 0.50 })
    local acCol = db:Get("accentColor", { 1.00, 0.82, 0.00 })

    local str = string.format("PUI:THEME:%s:%d:%.2f,%.2f,%.2f:%.2f,%.2f,%.2f:%.2f,%.2f,%.2f",
        bStyle, op,
        bgCol[1] or 0.1, bgCol[2] or 0.1, bgCol[3] or 0.1,
        brCol[1] or 0.8, brCol[2] or 0.7, brCol[3] or 0.5,
        acCol[1] or 1.0, acCol[2] or 0.8, acCol[3] or 0.0
    )
    return str
end

function Skinner:ImportThemeString(str)
    if not str or type(str) ~= "string" then return false end
    str = Utils.Trim(str)

    local _, _, bStyle, opStr, bgStr, brStr, acStr = string.find(str, "PUI:THEME:(%a+):(%d+):([%d%.,]+):([%d%.,]+):([%d%.,]+)")
    if not bStyle then return false end

    local op = (tonumber(opStr) or 95) / 100
    local db = self.db
    if db then
        db:Set("preset", "Custom")
        db:Set("borderStyle", bStyle)
        db:Set("backdropOpacity", op)
        
        -- Parse RGBs
        local _, _, r1, g1, b1 = string.find(bgStr, "([%d%.]+),([%d%.]+),([%d%.]+)")
        if r1 then db:Set("backdropColor", { tonumber(r1), tonumber(g1), tonumber(b1) }) end

        local _, _, r2, g2, b2 = string.find(brStr, "([%d%.]+),([%d%.]+),([%d%.]+)")
        if r2 then db:Set("borderColor", { tonumber(r2), tonumber(g2), tonumber(b2) }) end

        local _, _, r3, g3, b3 = string.find(acStr, "([%d%.]+),([%d%.]+),([%d%.]+)")
        if r3 then db:Set("accentColor", { tonumber(r3), tonumber(g3), tonumber(b3) }) end
    end

    self:RepaintAll()
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PrimusSkinner]: Custom Theme Imported Successfully!", "1eff00"))
    return true
end

-- =========================================================================
-- OPTIONS FLARE REGISTRATION
-- =========================================================================

function Skinner:RegisterOptions()
    local Options = Primus.Options
    if not Options or not Options.RegisterModuleOptions then return end

    Options:RegisterModuleOptions("Skinner", "Core", {
        title = "Skinner: Theming & Aesthetics",
        description = "Universal window & widget skinning engine with dynamic atomic mechanics and classic presets.",
        fields = {
            {
                key = "preset",
                label = "Theme Preset",
                type = "select",
                options = {
                    { text = "Blizz-Like (Classic 2004)", label = "Blizz-Like (Classic 2004)", value = "BlizzLike" },
                    { text = "Dark Glass (Cyan)",         label = "Dark Glass (Cyan)",         value = "DarkGlass" },
                    { text = "Onyx Gold",                 label = "Onyx Gold",                 value = "OnyxGold" },
                    { text = "Void Purple",               label = "Void Purple",               value = "VoidPurple" },
                    { text = "Midnight Navy",             label = "Midnight Navy",             value = "MidnightNavy" },
                    { text = "Minimal Matte (White)",     label = "Minimal Matte (White)",     value = "MinimalMatte" },
                },
                default = "BlizzLike",
                get = function() return Skinner.db:Get("preset", "BlizzLike") end,
                set = function(val) Skinner:ApplyPreset(val) end,
            },
            {
                key = "borderStyle",
                label = "Window Border Style",
                type = "select",
                options = {
                    { text = "Classic Dialog Brass", label = "Classic Dialog Brass", value = "Dialog" },
                    { text = "1-Pixel Razor Edge",   label = "1-Pixel Razor Edge",   value = "1Pixel" },
                    { text = "Tooltip Bevel (2px)",  label = "Tooltip Bevel (2px)",  value = "Tooltip" },
                    { text = "Borderless",           label = "Borderless",           value = "None" },
                },
                default = "Dialog",
                get = function() return Skinner.db:Get("borderStyle", "Dialog") end,
                set = function(val)
                    Skinner.db:Set("borderStyle", val)
                    Skinner:RepaintAll()
                end,
            },
            {
                key = "backdropOpacity",
                label = "Glass Transparency & Opacity",
                type = "slider",
                min = 0.50,
                max = 1.00,
                step = 0.05,
                default = 0.95,
                get = function() return Skinner.db:Get("backdropOpacity", 0.95) end,
                set = function(val)
                    Skinner.db:Set("backdropOpacity", val)
                    Skinner:RepaintAll()
                end,
            },
            {
                key = "useClassColorAccent",
                label = "Use Player Class Color for Accents",
                type = "checkbox",
                default = false,
                get = function() return Skinner.db:Get("useClassColorAccent", false) end,
                set = function(val)
                    Skinner.db:Set("useClassColorAccent", val)
                    Skinner:RepaintAll()
                end,
            },
        },
    })
end

-- Initialize Skinner Options on Login
if Events and Events.Register then
    Events:Register("PLAYER_LOGIN", "Skinner", function()
        Skinner:RegisterOptions()
    end)
end
