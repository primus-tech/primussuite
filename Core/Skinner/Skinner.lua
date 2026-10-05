--[[
    PrimusCore Foundation: Universal Window, Widget & Theme Skinning Engine (Primus.Skinner)
    Target: Vanilla WoW 1.12.1 (Client Build 5875 | Interface 11200 | Lua 5.0.2)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims, Single Domain Ownership)
    
    Provides:
    1. Atomic Visual Mechanics:
       - Composite Canvas & Border Descriptors (1Pixel Razor, Tooltip Bevel, Dialog Brass, Borderless)
       - Dynamic Glass Opacity (50% to 100% solid)
       - Accent Glow & Textures (Cyan, Gold, Purple, Navy, Class Color, Custom RGB)
       - Flat Tabs with Underline Active Indicators & Smooth Push Buttons
    2. Curated Theme Presets (Dark Glass, Onyx Gold, Void Purple, Midnight Navy, Minimal Matte, Blizz-Like).
    3. Live In-Memory Repainting (RepaintAll) without requiring client /reload.
    4. Weak-Key Memory Management (Zero GC leaks on ephemeral frames).
    5. Shareable Theme String Exporter / Importer.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local Skinner = Primus.Skinner or {}
Primus.Skinner = Skinner
Skinner.name = "Skinner"
Skinner.category = "Core"

-- Register Module with Primus Master Controller
Primus:RegisterModule("Skinner", Skinner, "Core")

local Media  = Primus.Media
local Utils  = Primus.Utils

-- =========================================================================
-- ZERO-LEAK WEAK KEY REGISTRIES
-- =========================================================================

local registeredFrames    = setmetatable({}, { __mode = "k" })
local registeredButtons   = setmetatable({}, { __mode = "k" })
local registeredTabs      = setmetatable({}, { __mode = "k" })
local registeredEditBoxes = setmetatable({}, { __mode = "k" })
local repaintCallbacks   = {}

-- Helper: Safe color clamping (0.0 to 1.0)
local function Clamp(v)
    if v > 1.0 then return 1.0 elseif v < 0.0 then return 0.0 else return v end
end

-- =========================================================================
-- CURATED THEME PRESET RECIPES (Dark Glass is Canonical Default)
-- =========================================================================

Skinner.presets = {
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
        bodyFont = "Default",
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
        bodyFont = "Default",
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
        bodyFont = "Default",
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
        bodyFont = "Default",
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
        bodyFont = "Default",
    },
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
        bodyFont = "Default",
    },
}

-- =========================================================================
-- STAGED LIFECYCLE HOOKS (Architecture Law #5)
-- =========================================================================

function Skinner:OnInitialize()
    if Primus.DB and not self.db then
        self.db = Primus.DB:RegisterNamespace("Skinner", {
            preset               = "DarkGlass",
            canvasTexture        = "Solid",
            backdropOpacity      = 0.95,
            backdropColor        = { 0.06, 0.06, 0.09 },
            borderStyle          = "1Pixel",
            borderColor          = { 0.20, 0.20, 0.25 },
            borderOpacity        = 1.0,
            accentColor          = { 0.20, 0.75, 1.00 },
            useClassColorAccent  = false,
            buttonStyle          = "Flat",
            tabStyle             = "Underline",
            headerFont           = "Default",
            bodyFont             = "Default",
        })
    end
    self:RegisterOptions()

    local Console = Primus.Console
    if Console and Console.RegisterSubCommand then
        Console:RegisterSubCommand("theme", function(argParam)
            argParam = Utils and Utils.Trim and Utils.Trim(argParam or "") or (argParam or "")
            local lower = string.lower(argParam)
            if lower == "dark" or lower == "darkglass" or lower == "cyan" then
                Skinner:ApplyPreset("DarkGlass")
            elseif lower == "gold" or lower == "onyx" or lower == "onyxgold" then
                Skinner:ApplyPreset("OnyxGold")
            elseif lower == "purple" or lower == "void" or lower == "voidpurple" then
                Skinner:ApplyPreset("VoidPurple")
            elseif lower == "navy" or lower == "midnight" or lower == "midnightnavy" or lower == "blue" then
                Skinner:ApplyPreset("MidnightNavy")
            elseif lower == "white" or lower == "matte" or lower == "minimal" or lower == "minimalmatte" then
                Skinner:ApplyPreset("MinimalMatte")
            elseif lower == "classic" or lower == "blizz" or lower == "blizzlike" or lower == "2004" then
                Skinner:ApplyPreset("BlizzLike")
            else
                local list = "[PrimusSkinner]: Usage: /pui theme [dark | gold | purple | navy | matte | classic]"
                if DEFAULT_CHAT_FRAME then
                    DEFAULT_CHAT_FRAME:AddMessage(Utils and Utils.ColorText and Utils.ColorText(list, "ffd100") or list)
                end
            end
        end, "Switch UI Theme Preset (/pui theme [dark|gold|purple|navy|matte|classic])")

        Console:RegisterSubCommand("preset", function(argParam)
            local h = Console.subCommands and Console.subCommands["theme"]
            if h and h.handler then
                h.handler(argParam)
            end
        end, "Alias for /pui theme")
    end
end

function Skinner:OnEnable()
    self.enabled = true
    self:RepaintAll()
end

function Skinner:OnDisable()
    self.enabled = false
end

-- =========================================================================
-- REGISTRATION & REPAINT CALLBACKS
-- =========================================================================

function Skinner:RegisterCallback(name, fn)
    if name and fn then
        repaintCallbacks[name] = fn
    end
end

function Skinner:Unregister(frame)
    if not frame then return end
    registeredFrames[frame] = nil
    registeredButtons[frame] = nil
    registeredTabs[frame] = nil
    registeredEditBoxes[frame] = nil
end

-- =========================================================================
-- COLOR & BACKDROP GENERATOR
-- =========================================================================

function Skinner:GetBackdropColor()
    local db = self.db
    local col = db and db:Get("backdropColor", { 0.06, 0.06, 0.09 }) or { 0.06, 0.06, 0.09 }
    local a = db and db:Get("backdropOpacity", 0.95) or 0.95
    return col[1] or 0.06, col[2] or 0.06, col[3] or 0.09, a
end

function Skinner:GetBorderColor()
    local db = self.db
    local col = db and db:Get("borderColor", { 0.20, 0.20, 0.25 }) or { 0.20, 0.20, 0.25 }
    local a = db and db:Get("borderOpacity", 1.0) or 1.0
    return col[1] or 0.20, col[2] or 0.20, col[3] or 0.25, a
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
    local col = db and db:Get("accentColor", { 0.20, 0.75, 1.00 }) or { 0.20, 0.75, 1.00 }
    return col[1] or 0.20, col[2] or 0.75, col[3] or 1.00, 1.0
end

function Skinner:GetBackdropDescriptor(customStyle)
    local db = self.db
    local bStyle = customStyle or (db and db:Get("borderStyle", "1Pixel")) or "1Pixel"
    local cTex = db and db:Get("canvasTexture", "Solid") or "Solid"

    local bgFile = "Interface\\Buttons\\WHITE8X8"
    if cTex == "Dialog" then
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background"
    elseif cTex == "Tooltip" then
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background"
    end

    if bStyle == "1Pixel" then
        return {
            bgFile = bgFile,
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        }
    elseif bStyle == "Dialog" then
        return {
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        }
    elseif bStyle == "Tooltip" then
        return {
            bgFile = bgFile,
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        }
    elseif bStyle == "None" then
        return {
            bgFile = bgFile,
            edgeFile = nil,
            tile = false, tileSize = 0, edgeSize = 0,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        }
    end

    return Media and Media:Fetch("border", bStyle) or {
        bgFile = bgFile,
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    }
end

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
        db:Set("bodyFont", p.bodyFont or "Default")
    end

    self:RepaintAll()
    if DEFAULT_CHAT_FRAME then
        local msg = string.format("[PrimusSkinner]: Applied Theme Preset: %s", p.name)
        DEFAULT_CHAT_FRAME:AddMessage(Utils and Utils.ColorText and Utils.ColorText(msg, "69ccf0") or msg)
    end
end

-- =========================================================================
-- UNIVERSAL SKINNING PRIMITIVES
-- =========================================================================

-- Skin Container Frame / Panel
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

-- Skin Push Button (with non-destructive script hook chaining and live color evaluation)
function Skinner:SkinButton(btn, text, isAccent)
    if not btn then return end
    btn:SetBackdrop(self:GetBackdropDescriptor("1Pixel"))
    
    btn._primusIsAccent = isAccent
    local r, g, b, a = self:GetBackdropColor()
    local br, bg, bb, ba = self:GetBorderColor()
    if isAccent then
        br, bg, bb, ba = self:GetAccentColor()
    end

    btn:SetBackdropColor(Clamp(r + 0.05), Clamp(g + 0.05), Clamp(b + 0.06), a)
    btn:SetBackdropBorderColor(br, bg, bb, ba)
    if text and btn.SetText then btn:SetText(text) end

    if not btn._primusHoverHooked then
        btn._origOnEnter = btn:GetScript("OnEnter")
        btn._origOnLeave = btn:GetScript("OnLeave")
        
        btn:SetScript("OnEnter", function()
            local cr, cg, cb = Skinner:GetBackdropColor()
            local ar, ag, ab = Skinner:GetAccentColor()
            this:SetBackdropColor(Clamp(cr + 0.12), Clamp(cg + 0.12), Clamp(cb + 0.14), 1.0)
            this:SetBackdropBorderColor(ar, ag, ab, 1.0)
            if this._origOnEnter then this._origOnEnter() end
        end)
        
        btn:SetScript("OnLeave", function()
            local cr, cg, cb, ca = Skinner:GetBackdropColor()
            local cbr, cbg, cbb, cba = Skinner:GetBorderColor()
            if this._primusIsAccent then
                cbr, cbg, cbb, cba = Skinner:GetAccentColor()
            end
            this:SetBackdropColor(Clamp(cr + 0.05), Clamp(cg + 0.05), Clamp(cb + 0.06), ca)
            this:SetBackdropBorderColor(cbr, cbg, cbb, cba)
            if this._origOnLeave then this._origOnLeave() end
        end)
        
        btn._primusHoverHooked = true
    end

    btn.primusSkinned = true
    registeredButtons[btn] = { isAccent = isAccent }
end

-- Skin Tab Button with Underline Active Indicator
function Skinner:SkinTab(tab)
    if not tab then return end
    local tabName = tab:GetName()
    if tabName then
        local suffixes = {
            "Left", "Middle", "Right",
            "LeftDisabled", "MiddleDisabled", "RightDisabled",
            "LeftHighlight", "MiddleHighlight", "RightHighlight",
            "HighlightTexture"
        }
        for i = 1, table.getn(suffixes) do
            local tex = _G[tabName .. suffixes[i]]
            if tex and tex.Hide then tex:Hide() end
        end
    end

    tab:SetBackdrop(self:GetBackdropDescriptor("1Pixel"))
    local r, g, b, a = self:GetBackdropColor()
    local br, bg, bb, ba = self:GetBorderColor()
    tab:SetBackdropColor(r, g, b, 0.90)
    tab:SetBackdropBorderColor(br, bg, bb, ba)

    -- Accent underline active indicator
    if not tab.primusIndicator then
        local indicator = tab:CreateTexture(nil, "OVERLAY")
        indicator:SetTexture("Interface\\Buttons\\WHITE8X8")
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

-- Manage Tab Active State
function Skinner:SetTabSelected(tab, isSelected)
    if not tab then return end
    if not tab.primusSkinned then
        self:SkinTab(tab)
    end

    local ar, ag, ab, aa = self:GetAccentColor()
    local br, bg, bb, ba = self:GetBorderColor()

    if isSelected then
        if tab.primusIndicator then tab.primusIndicator:Show() end
        tab:SetBackdropBorderColor(ar, ag, ab, 0.9)
        local txt = tab:GetFontString() or (tab.GetName and _G[tab:GetName() .. "Text"])
        if txt and txt.SetTextColor then
            txt:SetTextColor(ar, ag, ab)
        end
    else
        if tab.primusIndicator then tab.primusIndicator:Hide() end
        tab:SetBackdropBorderColor(br, bg, bb, ba)
        local txt = tab:GetFontString() or (tab.GetName and _G[tab:GetName() .. "Text"])
        if txt and txt.SetTextColor then
            txt:SetTextColor(0.70, 0.70, 0.70)
        end
    end
end

-- Skin EditBox
function Skinner:SkinEditBox(editBox)
    if not editBox then return end
    editBox:SetBackdrop(self:GetBackdropDescriptor("1Pixel"))
    local r, g, b, a = self:GetBackdropColor()
    local br, bg, bb, ba = self:GetBorderColor()
    editBox:SetBackdropColor(Clamp(r * 0.7), Clamp(g * 0.7), Clamp(b * 0.7), 0.95)
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
        thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
        local ar, ag, ab, aa = self:GetAccentColor()
        thumb:SetVertexColor(ar, ag, ab, 0.75)
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
        local fontPath = Media and Media:Fetch("font", "Default") or "Fonts\\FRIZQT__.TTF"
        txt:SetFont(fontPath, 11, "OUTLINE")
        txt:SetPoint("CENTER", 0, 0)
        txt:SetText("x")
        txt:SetTextColor(0.7, 0.7, 0.7)
        closeBtn.text = txt

        if not closeBtn._primusHoverHooked then
            closeBtn._origOnEnter = closeBtn:GetScript("OnEnter")
            closeBtn._origOnLeave = closeBtn:GetScript("OnLeave")
            closeBtn:SetScript("OnEnter", function()
                txt:SetTextColor(1.0, 0.3, 0.3)
                if this._origOnEnter then this._origOnEnter() end
            end)
            closeBtn:SetScript("OnLeave", function()
                txt:SetTextColor(0.7, 0.7, 0.7)
                if this._origOnLeave then this._origOnLeave() end
            end)
            closeBtn._primusHoverHooked = true
        end
    end
    closeBtn.primusSkinned = true
end

-- Skin CheckBox
function Skinner:SkinCheckBox(checkBtn)
    if not checkBtn then return end
    checkBtn:SetBackdrop(self:GetBackdropDescriptor("1Pixel"))
    local r, g, b, a = self:GetBackdropColor()
    local br, bg, bb, ba = self:GetBorderColor()
    checkBtn:SetBackdropColor(Clamp(r * 0.7), Clamp(g * 0.7), Clamp(b * 0.7), 0.95)
    checkBtn:SetBackdropBorderColor(br, bg, bb, ba)
    checkBtn.primusSkinned = true
end

-- Typography Primitives
function Skinner:SkinHeader(fontString, size)
    if not fontString then return end
    local fontName = self.db and self.db:Get("headerFont", "Default") or "Default"
    local fontPath = Media and Media:Fetch("font", fontName) or "Fonts\\FRIZQT__.TTF"
    fontString:SetFont(fontPath, size or 12, "OUTLINE")
end

function Skinner:SkinBody(fontString, size)
    if not fontString then return end
    local fontName = self.db and self.db:Get("bodyFont", "Default") or "Default"
    local fontPath = Media and Media:Fetch("font", fontName) or "Fonts\\FRIZQT__.TTF"
    fontString:SetFont(fontPath, size or 10, "OUTLINE")
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
            btn:SetBackdrop(self:GetBackdropDescriptor("1Pixel"))
            btn:SetBackdropColor(Clamp(r + 0.05), Clamp(g + 0.05), Clamp(b + 0.06), a)
            btn:SetBackdropBorderColor(ob_r, ob_g, ob_b, ob_a)
        end
    end

    for tab in pairs(registeredTabs) do
        if tab and tab.SetBackdropColor then
            tab:SetBackdrop(self:GetBackdropDescriptor("1Pixel"))
            tab:SetBackdropColor(r, g, b, 0.90)
            tab:SetBackdropBorderColor(br, bg, bb, ba)
            if tab.primusIndicator then
                tab.primusIndicator:SetVertexColor(ar, ag, ab, aa)
            end
        end
    end

    for eb in pairs(registeredEditBoxes) do
        if eb and eb.SetBackdropColor then
            eb:SetBackdrop(self:GetBackdropDescriptor("1Pixel"))
            eb:SetBackdropColor(Clamp(r * 0.7), Clamp(g * 0.7), Clamp(b * 0.7), 0.95)
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
    local bStyle = db:Get("borderStyle", "1Pixel")
    local op = math.floor((db:Get("backdropOpacity", 0.95)) * 100)
    local bgCol = db:Get("backdropColor", { 0.06, 0.06, 0.09 })
    local brCol = db:Get("borderColor", { 0.20, 0.20, 0.25 })
    local acCol = db:Get("accentColor", { 0.20, 0.75, 1.00 })

    local str = string.format("PUI:THEME:%s:%d:%.2f,%.2f,%.2f:%.2f,%.2f,%.2f:%.2f,%.2f,%.2f",
        bStyle, op,
        bgCol[1] or 0.06, bgCol[2] or 0.06, bgCol[3] or 0.09,
        brCol[1] or 0.20, brCol[2] or 0.20, brCol[3] or 0.25,
        acCol[1] or 0.20, acCol[2] or 0.75, acCol[3] or 1.00
    )
    return str
end

function Skinner:ImportThemeString(str)
    if not str or type(str) ~= "string" then return false end
    if Utils and Utils.Trim then str = Utils.Trim(str) end

    -- Pattern matches alphanumeric & underscores (e.g. 1Pixel, Dialog, Tooltip, None)
    local _, _, bStyle, opStr, bgStr, brStr, acStr = string.find(str, "PUI:THEME:([%w_]+):(%d+):([%d%.,]+):([%d%.,]+):([%d%.,]+)")
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
    if DEFAULT_CHAT_FRAME then
        local msg = "[PrimusSkinner]: Custom Theme Imported Successfully!"
        DEFAULT_CHAT_FRAME:AddMessage(Utils and Utils.ColorText and Utils.ColorText(msg, "1eff00") or msg)
    end
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
                    { text = "Dark Glass (Cyan)",         label = "Dark Glass (Cyan)",         value = "DarkGlass" },
                    { text = "Onyx Gold",                 label = "Onyx Gold",                 value = "OnyxGold" },
                    { text = "Void Purple",               label = "Void Purple",               value = "VoidPurple" },
                    { text = "Midnight Navy",             label = "Midnight Navy",             value = "MidnightNavy" },
                    { text = "Minimal Matte (White)",     label = "Minimal Matte (White)",     value = "MinimalMatte" },
                    { text = "Blizz-Like (Classic 2004)", label = "Blizz-Like (Classic 2004)", value = "BlizzLike" },
                },
                default = "DarkGlass",
                get = function() return Skinner.db and Skinner.db:Get("preset", "DarkGlass") or "DarkGlass" end,
                set = function(val) Skinner:ApplyPreset(val) end,
            },
            {
                key = "borderStyle",
                label = "Window Border Style",
                type = "select",
                options = {
                    { text = "1-Pixel Razor Edge",   label = "1-Pixel Razor Edge",   value = "1Pixel" },
                    { text = "Classic Dialog Brass", label = "Classic Dialog Brass", value = "Dialog" },
                    { text = "Tooltip Bevel (2px)",  label = "Tooltip Bevel (2px)",  value = "Tooltip" },
                    { text = "Borderless",           label = "Borderless",           value = "None" },
                },
                default = "1Pixel",
                get = function() return Skinner.db and Skinner.db:Get("borderStyle", "1Pixel") or "1Pixel" end,
                set = function(val)
                    if Skinner.db then Skinner.db:Set("borderStyle", val) end
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
                get = function() return Skinner.db and Skinner.db:Get("backdropOpacity", 0.95) or 0.95 end,
                set = function(val)
                    if Skinner.db then Skinner.db:Set("backdropOpacity", val) end
                    Skinner:RepaintAll()
                end,
            },
            {
                key = "useClassColorAccent",
                label = "Use Player Class Color for Accents",
                type = "checkbox",
                default = false,
                get = function() return Skinner.db and Skinner.db:Get("useClassColorAccent", false) or false end,
                set = function(val)
                    if Skinner.db then Skinner.db:Set("useClassColorAccent", val) end
                    Skinner:RepaintAll()
                end,
            },
        },
    })
end
