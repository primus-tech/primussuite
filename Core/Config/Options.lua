--[[
    PrimusUI: Master In-Game Configuration GUI & Distributed Flare Hub
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Implements the Distributed Options Flare Handshake with dynamic LoD canvas rendering,
    zero upfront memory allocation, Top Category Navigation bar matching Modules/ taxonomy,
    clean addon-name-only left tabs with rich hover GameTooltips, instant module enable/disable
    checkboxes, auto-hiding on Mover engagement, and full Profile IO management.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local Options = Primus.Options or {}
Primus.Options = Options
Primus:RegisterModule("Options", Options, "Core")

local DB       = Primus.DB
local Widgets  = Primus.Widgets
local Media    = Primus.Media
local Utils    = Primus.Utils
local Events   = Primus.Events
local Memory   = Primus.Memory
local Debug    = Primus.Debug

-- =========================================================================
-- REGISTRIES & STATE
-- =========================================================================

local registeredFlares = {}       -- [id] = { id=id, meta=meta, builderFunc=builderFunc }
local flareOrder       = {}       -- Array of registered IDs in registration order
local cachedPanels     = {}       -- [id] = constructed panel frame
local activeModuleId   = "System"
local selectedCategory = "ALL"

local optionsFrame     = nil
local moduleRows       = {}
local profileDropdown  = nil

-- Top Horizontal Category Taxonomy matching Modules/ directory structure
local TOP_CATEGORIES = {
    { id = "ALL",         label = "All",         desc = "Displays all modules across all categories." },
    { id = "UTILITY",     label = "Utility",     desc = "General utilities, automation, maps, and workflow helpers." },
    { id = "PLAYER",      label = "Player",      desc = "Player inventory, bags, bank, spellbook, and character sheet." },
    { id = "COMBAT",      label = "Combat",      desc = "Combat engine, threat meters, cooldowns, and tactical alerts." },
    { id = "HUD",         label = "HUD",         desc = "Heads-up displays, castbars, auras, and timers." },
    { id = "UNITS",       label = "Units",       desc = "Unit frames, party, raid, nameplates, and bosses." },
    { id = "BARS",        label = "Bars",        desc = "Action bars, stance bars, pet bars, microbar, and XP bar." },
    { id = "SOCIAL",      label = "Social",      desc = "Chat systems, roleplay suite, and master looter." },
    { id = "PROFESSIONS", label = "Professions", desc = "Trade skills, crafting queues, and recipe databases." },
    { id = "GATHERING",   label = "Gathering",   desc = "Resource nodes, tracking radars, and harvesting helpers." },
    { id = "CLASSES",     label = "Classes",     desc = "Class-specific power tracking and stance modules." },
    { id = "SYSTEM",      label = "System",      desc = "Core engine diagnostics, skinner, mover, and keybinder." },
}

-- Dictionary of clean friendly names for compound identifiers
local FRIENDLY_NAMES = {
    ["UnitFrames"]     = "Unit Frames",
    ["UnitBase"]       = "Unit Base",
    ["ItemCompare"]    = "Item Compare",
    ["AutoMechanics"]  = "Auto Mechanics",
    ["FastLoot"]       = "Fast Loot",
    ["MinimapOrbit"]   = "Minimap Orbit",
    ["Minimapper"]     = "Minimap",
    ["MasterLoot"]     = "Master Loot",
    ["SellValue"]      = "Sell Value",
    ["CharacterSheet"] = "Character Sheet",
    ["QuestWatch"]     = "Quest Watch",
    ["CombatAuras"]    = "Combat Auras",
    ["CombatLog"]      = "Combat Log",
    ["CastBar"]        = "Cast Bar",
    ["HealComm"]       = "Heal Comm",
    ["LogViewer"]      = "Log Viewer",
    ["Zen"]            = "Zen Mode",
}

-- =========================================================================
-- CLEAN NAME & CATEGORY RESOLUTION HELPERS
-- =========================================================================

local function GetCleanModuleName(flare)
    if not flare then return "Unknown" end
    if flare.meta and flare.meta.shortName and flare.meta.shortName ~= "" then
        return flare.meta.shortName
    end

    local raw = (flare.meta and (flare.meta.name or flare.meta.label or flare.meta.title)) or flare.id or "Module"

    -- Strip "Primus" or "PUI" prefixes
    if string.sub(raw, 1, 6) == "Primus" then
        raw = string.sub(raw, 7)
    elseif string.sub(raw, 1, 3) == "PUI" then
        raw = string.sub(raw, 4)
    end
    if string.sub(raw, 1, 1) == "_" or string.sub(raw, 1, 1) == " " then
        raw = string.sub(raw, 2)
    end

    -- If there is a trailing description or hyphen/parenthesis/colon, extract base
    local dashPos = string.find(raw, " %- ") or string.find(raw, " %:") or string.find(raw, " %(")
    if dashPos and dashPos > 1 then
        raw = string.sub(raw, 1, dashPos - 1)
    end
    raw = Utils.Trim(raw)
    if raw == "" then
        raw = flare.id
    end

    if FRIENDLY_NAMES[raw] then
        return FRIENDLY_NAMES[raw]
    end
    return raw
end

local function MatchesCategory(flareCat, filterCat)
    if not filterCat or filterCat == "ALL" then return true end
    local fUpper = string.upper(flareCat or "")
    local filterUpper = string.upper(filterCat or "")

    if filterUpper == "BARS" and (fUpper == "BARS" or fUpper == "ACTION BARS" or fUpper == "ACTIONBARS") then return true end
    if filterUpper == "COMBAT" and (fUpper == "COMBAT" or fUpper == "THREAT" or fUpper == "DAMAGE" or fUpper == "COMBAT & HUD") then return true end
    if filterUpper == "HUD" and (fUpper == "HUD" or fUpper == "AURAS" or fUpper == "HUD & AURAS") then return true end
    if filterUpper == "UNITS" and (fUpper == "UNITS" or fUpper == "UNIT FRAMES" or fUpper == "UNITFRAMES" or fUpper == "RAID" or fUpper == "PARTY") then return true end
    if filterUpper == "PLAYER" and (fUpper == "PLAYER" or fUpper == "BAGS" or fUpper == "CONTAINERS" or fUpper == "INVENTORY" or fUpper == "PLAYER & BAGS") then return true end
    if filterUpper == "SOCIAL" and (fUpper == "SOCIAL" or fUpper == "CHAT" or fUpper == "ROLEPLAY" or fUpper == "SOCIAL & CHAT") then return true end
    if filterUpper == "PROFESSIONS" and (fUpper == "PROFESSIONS" or fUpper == "TRADE" or fUpper == "TRADESKILL" or fUpper == "CRAFTING" or fUpper == "ECONOMY" or fUpper == "ECONOMY & TRADE") then return true end
    if filterUpper == "GATHERING" and (fUpper == "GATHERING" or fUpper == "TRACKING" or fUpper == "HARVESTING") then return true end
    if filterUpper == "CLASSES" and (fUpper == "CLASSES" or fUpper == "CLASS" or fUpper == "CLASS SUITE" or fUpper == "CLASS NUANCE") then return true end
    if filterUpper == "UTILITY" and (fUpper == "UTILITY" or fUpper == "LAYOUT" or fUpper == "UTILITY & LAYOUT" or fUpper == "GENERAL UTILITY") then return true end
    if filterUpper == "SYSTEM" and (fUpper == "SYSTEM" or fUpper == "CORE" or fUpper == "GENERAL" or fUpper == "SYSTEM & ENGINE" or fUpper == "ENGINE") then return true end

    return fUpper == filterUpper
end

-- =========================================================================
-- FLARE PROTOCOL REGISTRATION API
-- =========================================================================

function Options:RegisterModuleOptions(id, metaOrCategory, builderOrMeta)
    if not id or type(id) ~= "string" then return end

    local meta = {}
    local builderFunc = nil

    if type(metaOrCategory) == "string" then
        -- Signature: RegisterModuleOptions(id, category, metaTable)
        if type(builderOrMeta) == "table" then
            meta = builderOrMeta
            meta.category = meta.category or metaOrCategory
        elseif type(builderOrMeta) == "function" then
            meta.category = metaOrCategory
            builderFunc = builderOrMeta
        else
            meta.category = metaOrCategory
        end
    elseif type(metaOrCategory) == "table" then
        meta = metaOrCategory
        if type(builderOrMeta) == "function" then
            builderFunc = builderOrMeta
        end
    end

    meta.title    = meta.title or meta.name or meta.label or id
    meta.category = meta.category or "General"
    meta.icon     = meta.icon or "Interface\\Icons\\INV_Misc_Gear_01"
    meta.desc     = meta.desc or meta.description or ("Configures settings for " .. id .. ".")
    meta.order    = meta.order or 100

    if not registeredFlares[id] then
        table.insert(flareOrder, id)
    end

    registeredFlares[id] = {
        id = id,
        meta = meta,
        builderFunc = builderFunc,
    }

    -- If the GUI is currently open, refresh the module list
    if optionsFrame and optionsFrame:IsShown() then
        self:RefreshModuleList()
    end
end

-- Attach flare registration helper directly to Primus controller
Primus.RegisterModuleOptions = function(self, id, metaOrCategory, builderOrMeta)
    Options:RegisterModuleOptions(id, metaOrCategory, builderOrMeta)
end

function Options:GetRegisteredFlares()
    return registeredFlares
end

-- =========================================================================
-- DECLARATIVE OPTIONS PANEL BUILDER
-- =========================================================================

function Options:BuildDeclarativePanel(parent, flare)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetWidth(500)

    local opts = flare.meta.options or flare.meta.fields or {}
    local totalOpts = table.getn(opts)
    local curY = -10

    for i = 1, totalOpts do
        local opt = opts[i]
        local oType = opt.type or "checkbox"

        if oType == "checkbox" then
            local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
            cb:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, curY)
            cb:SetWidth(20)
            cb:SetHeight(20)
            cb.opt = opt

            local label = cb:CreateFontString(nil, "OVERLAY")
            label:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
            label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
            label:SetText(opt.label or opt.key or "Option")

            if opt.desc then
                local desc = panel:CreateFontString(nil, "OVERLAY")
                desc:SetFont(Media:Fetch("font", "Default"), 8, "")
                desc:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 26, -2)
                desc:SetTextColor(0.65, 0.65, 0.65)
                desc:SetText(opt.desc)
                curY = curY - 36
            else
                curY = curY - 26
            end

            if opt.get then
                cb:SetChecked(opt.get() and 1 or 0)
            elseif opt.default ~= nil then
                cb:SetChecked(opt.default and 1 or 0)
            end

            cb:SetScript("OnClick", function()
                local checked = (this:GetChecked() == 1 or this:GetChecked() == true)
                if this.opt and this.opt.set then
                    this.opt.set(checked)
                end
            end)

        elseif oType == "slider" then
            local slider = CreateFrame("Slider", "Primus_OptSlider_" .. flare.id .. "_" .. (opt.key or i), panel, "OptionsSliderTemplate")
            slider:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, curY - 14)
            slider:SetWidth(200)
            slider:SetHeight(16)
            slider:SetMinMaxValues(opt.min or 0, opt.max or 100)
            slider:SetValueStep(opt.step or 1)

            local title = slider:CreateFontString(nil, "OVERLAY")
            title:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
            title:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 2)
            title:SetText(opt.label or opt.key or "Setting")

            local valText = slider:CreateFontString(nil, "OVERLAY")
            valText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
            valText:SetPoint("LEFT", slider, "RIGHT", 10, 0)
            valText:SetTextColor(1, 1, 0.4)

            slider.opt = opt
            slider.valText = valText

            local curVal = opt.get and opt.get() or opt.default or (opt.min or 0)
            slider:SetValue(curVal)
            valText:SetText(tostring(curVal))

            slider:SetScript("OnValueChanged", function()
                local v = this:GetValue()
                if this.opt and this.opt.step and this.opt.step >= 1 then
                    v = math.floor(v + 0.5)
                end
                if this.valText then
                    this.valText:SetText(tostring(v))
                end
                if this.opt and this.opt.set then
                    this.opt.set(v)
                end
            end)

            if opt.desc then
                local desc = panel:CreateFontString(nil, "OVERLAY")
                desc:SetFont(Media:Fetch("font", "Default"), 8, "")
                desc:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -4)
                desc:SetTextColor(0.65, 0.65, 0.65)
                desc:SetText(opt.desc)
                curY = curY - 48
            else
                curY = curY - 38
            end

        elseif oType == "select" or oType == "dropdown" then
            local label = panel:CreateFontString(nil, "OVERLAY")
            label:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
            label:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, curY)
            label:SetText(opt.label or opt.key or "Setting")

            local curVal = opt.get and opt.get() or opt.default or ""
            local curText = tostring(curVal)
            if opt.options then
                local optCount = table.getn(opt.options)
                for o = 1, optCount do
                    if opt.options[o].value == curVal then
                        curText = opt.options[o].text or opt.options[o].value
                        break
                    end
                end
            end

            local selectBtn = Widgets:CreateButton(panel, curText .. " ▼", 220, 22)
            selectBtn:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
            selectBtn.opt = opt
            selectBtn:SetScript("OnClick", function()
                if not this.opt or not this.opt.options then return end
                local menuItems = {}
                local currentV = this.opt.get and this.opt.get() or this.opt.default or ""
                local optCount = table.getn(this.opt.options)
                for idx = 1, optCount do
                    local entry = this.opt.options[idx]
                    local eVal = entry.value
                    local eText = entry.text or entry.value
                    local btnSelf = this
                    local optSelf = this.opt
                    table.insert(menuItems, {
                        text = eText,
                        checked = (eVal == currentV),
                        func = function()
                            btnSelf.text:SetText(eText .. " ▼")
                            if optSelf.set then
                                optSelf.set(eVal)
                            end
                        end,
                        onClick = function()
                            btnSelf.text:SetText(eText .. " ▼")
                            if optSelf.set then
                                optSelf.set(eVal)
                            end
                        end,
                    })
                end
                if Widgets and Widgets.ShowContextMenu then
                    Widgets:ShowContextMenu(this, menuItems, { minWidth = 220 })
                end
            end)

            if opt.desc then
                local desc = panel:CreateFontString(nil, "OVERLAY")
                desc:SetFont(Media:Fetch("font", "Default"), 8, "")
                desc:SetPoint("TOPLEFT", selectBtn, "BOTTOMLEFT", 0, -4)
                desc:SetTextColor(0.65, 0.65, 0.65)
                desc:SetText(opt.desc)
                curY = curY - 56
            else
                curY = curY - 46
            end

        elseif oType == "button" then
            local btn = Widgets:CreateButton(panel, opt.buttonText or opt.label or "Action", 140, 22)
            btn.opt = opt
            btn:SetScript("OnClick", function()
                if this.opt and this.opt.onClick then
                    this.opt.onClick()
                end
            end)
            btn:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, curY)

            if opt.desc then
                local desc = panel:CreateFontString(nil, "OVERLAY")
                desc:SetFont(Media:Fetch("font", "Default"), 8, "")
                desc:SetPoint("LEFT", btn, "RIGHT", 10, 0)
                desc:SetTextColor(0.7, 0.7, 0.7)
                desc:SetText(opt.desc)
            end

            curY = curY - 30
        end
    end

    if totalOpts == 0 then
        local empty = panel:CreateFontString(nil, "OVERLAY")
        empty:SetFont(Media:Fetch("font", "Default"), 10, "")
        empty:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -20)
        empty:SetTextColor(0.7, 0.7, 0.7)
        empty:SetText("No additional settings available for this module.")
        curY = curY - 40
    end

    panel:SetHeight(math.abs(curY) + 20)
    return panel
end

-- =========================================================================
-- DYNAMIC LoD CANVAS LOADER & MODULE SELECTOR
-- =========================================================================

function Options:SelectModule(id)
    if not id or not registeredFlares[id] then
        id = "System"
    end
    activeModuleId = id
    local flare = registeredFlares[id]
    if not flare then return end

    -- Update Right Header Banner
    if optionsFrame and optionsFrame.banner then
        local b = optionsFrame.banner
        b.title:SetText(Utils.ColorText(flare.meta.title, "ffd100"))
        b.cat:SetText(Utils.ColorText(string.format("Category: %s", flare.meta.category or "General"), "69ccf0"))
        b.desc:SetText(flare.meta.desc or "")
        b.icon:SetTexture(flare.meta.icon or "Interface\\Icons\\INV_Misc_Gear_01")

        local isEnabled = Primus:IsModuleEnabled(id)
        if id == "System" or id == "Options" then isEnabled = true end
        if isEnabled then
            b.status:SetText(Utils.ColorText("[ ACTIVE ]", "33ff33"))
        else
            b.status:SetText(Utils.ColorText("[ DISABLED ]", "ff4444"))
        end
    end

    -- Hide all cached panels
    for panelId, panel in pairs(cachedPanels) do
        if panelId ~= id then
            panel:Hide()
        end
    end

    -- LoD Construction on demand
    if not cachedPanels[id] then
        local canvas = optionsFrame.canvasScrollChild
        local panel = nil

        if flare.builderFunc and type(flare.builderFunc) == "function" then
            panel = flare.builderFunc(canvas)
        elseif flare.meta and (flare.meta.options or flare.meta.fields) then
            panel = self:BuildDeclarativePanel(canvas, flare)
        else
            panel = self:BuildDeclarativePanel(canvas, flare)
        end

        if panel then
            panel:SetParent(canvas)
            panel:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, 0)
            panel:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", 0, 0)
            cachedPanels[id] = panel
        end
    end

    if cachedPanels[id] then
        cachedPanels[id]:Show()
    end

    self:RefreshModuleList()
end

function Options:ClearCanvas()
    for panelId, panel in pairs(cachedPanels) do
        panel:Hide()
    end
    if optionsFrame and optionsFrame.banner then
        local b = optionsFrame.banner
        b.title:SetText(Utils.ColorText(selectedCategory .. " Modules", "ffd100"))
        b.cat:SetText(Utils.ColorText("Category: " .. selectedCategory, "69ccf0"))
        b.desc:SetText("No modules are currently registered or active in this category.")
        b.icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
        b.status:SetText("")
    end
end

-- =========================================================================
-- TOP CATEGORY SELECTION HANDLER
-- =========================================================================

function Options:SetSelectedCategory(catId)
    selectedCategory = catId or "ALL"
    self:RefreshCategoryTabs()
    self:RefreshModuleList()

    -- Check if currently active module is visible in new category
    local isActiveVisible = false
    local firstVisibleId = nil

    local totalOrder = table.getn(flareOrder)
    for i = 1, totalOrder do
        local id = flareOrder[i]
        local flare = registeredFlares[id]
        if flare and MatchesCategory(flare.meta.category, selectedCategory) then
            if not firstVisibleId then firstVisibleId = id end
            if id == activeModuleId then
                isActiveVisible = true
                break
            end
        end
    end

    if not isActiveVisible and firstVisibleId then
        self:SelectModule(firstVisibleId)
    elseif not firstVisibleId then
        self:ClearCanvas()
    end
end

function Options:RefreshCategoryTabs()
    if not optionsFrame or not optionsFrame.categoryTabs then return end
    for _, tab in ipairs(optionsFrame.categoryTabs) do
        if tab.catId == selectedCategory then
            tab:SetBackdropColor(0.18, 0.32, 0.55, 1.0)
            tab:SetBackdropBorderColor(0.35, 0.75, 1.0, 1.0)
            tab.label:SetTextColor(1.0, 1.0, 1.0)
        else
            tab:SetBackdropColor(0.08, 0.10, 0.14, 0.85)
            tab:SetBackdropBorderColor(0.20, 0.25, 0.35, 0.8)
            tab.label:SetTextColor(0.70, 0.75, 0.85)
        end
    end
end

-- =========================================================================
-- LEFT 25% MODULE LIST & CHECKBOX RENDERER (CLEAN ADDON NAMES + RICH TOOLTIP)
-- =========================================================================

function Options:RefreshModuleList()
    if not optionsFrame or not optionsFrame.moduleScrollChild then return end
    local parent = optionsFrame.moduleScrollChild

    -- Filter matching flares
    local visibleFlares = {}
    local totalOrder = table.getn(flareOrder)
    for i = 1, totalOrder do
        local id = flareOrder[i]
        local flare = registeredFlares[id]
        if flare and MatchesCategory(flare.meta.category, selectedCategory) then
            table.insert(visibleFlares, flare)
        end
    end

    local count = table.getn(visibleFlares)
    local rowHeight = 24
    local spacing = 2

    for i = 1, count do
        local flare = visibleFlares[i]
        local cleanName = GetCleanModuleName(flare)
        local row = moduleRows[i]
        if not row then
            row = CreateFrame("Frame", nil, parent)
            row:SetWidth(186)
            row:SetHeight(rowHeight)
            row:SetBackdrop(Media:Fetch("border", "1Pixel"))
            row:SetBackdropColor(0.08, 0.10, 0.14, 0.85)
            row:SetBackdropBorderColor(0.20, 0.25, 0.35, 0.8)

            -- Enable Checkbox
            local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            cb:SetWidth(18)
            cb:SetHeight(18)
            cb:SetPoint("LEFT", row, "LEFT", 3, 0)
            cb:SetHitRectInsets(0, 0, 0, 0)
            row.cb = cb

            -- Clickable Title Button (Clean Addon Name Alone)
            local btn = CreateFrame("Button", nil, row)
            btn:SetPoint("LEFT", cb, "RIGHT", 4, 0)
            btn:SetPoint("RIGHT", row, "RIGHT", -3, 0)
            btn:SetHeight(rowHeight)

            local title = btn:CreateFontString(nil, "OVERLAY")
            title:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
            title:SetPoint("LEFT", btn, "LEFT", 2, 0)
            title:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
            title:SetJustifyH("LEFT")
            btn.title = title
            btn.parentRow = row
            row.btn = btn

            moduleRows[i] = row
        end

        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -(i - 1) * (rowHeight + spacing) - 2)
        row.moduleId = flare.id
        row.flare = flare
        row.cleanName = cleanName
        row.cb.moduleId = flare.id
        row.btn.moduleId = flare.id
        row.btn.flare = flare
        row.btn.cleanName = cleanName

        -- Set clean addon name alone on the left tab button
        row.btn.title:SetText(cleanName)

        -- Checkbox state & handler
        local isEnabled = Primus:IsModuleEnabled(flare.id)
        if flare.id == "System" or flare.id == "Options" or flare.id == "Skinner" then
            isEnabled = true
            row.cb:Disable()
        else
            row.cb:Enable()
        end
        row.cb:SetChecked(isEnabled and 1 or 0)

        row.cb:SetScript("OnClick", function()
            local checked = (this:GetChecked() == 1 or this:GetChecked() == true)
            if checked then
                Primus:EnableModule(this.moduleId)
            else
                Primus:DisableModule(this.moduleId)
            end
            Options:SelectModule(activeModuleId)
        end)

        row.cb:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT", 4, 0)
            GameTooltip:ClearLines()
            local en = Primus:IsModuleEnabled(this.moduleId)
            if this.moduleId == "System" or this.moduleId == "Options" or this.moduleId == "Skinner" then en = true end
            GameTooltip:AddLine("Module State", 1.0, 0.82, 0.0)
            GameTooltip:AddLine(en and "Click to disable this module." or "Click to enable this module.", 0.85, 0.85, 0.85)
            GameTooltip:Show()
        end)

        row.cb:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        -- Selection Highlight
        if flare.id == activeModuleId then
            row:SetBackdropColor(0.18, 0.30, 0.50, 1.0)
            row:SetBackdropBorderColor(0.35, 0.75, 1.00, 1.0)
            row.btn.title:SetTextColor(1.0, 1.0, 1.0)
        else
            row:SetBackdropColor(0.08, 0.10, 0.14, 0.85)
            row:SetBackdropBorderColor(0.20, 0.25, 0.35, 0.8)
            row.btn.title:SetTextColor(0.82, 0.85, 0.90)
        end

        row.btn:SetScript("OnClick", function()
            Options:SelectModule(this.moduleId)
        end)

        -- Rich GameTooltip Description on Hover
        row.btn:SetScript("OnEnter", function()
            local f = this.flare
            if not f then return end
            if f.id ~= activeModuleId then
                this.parentRow:SetBackdropColor(0.14, 0.18, 0.26, 0.95)
                this.parentRow:SetBackdropBorderColor(0.35, 0.50, 0.75, 0.95)
            end

            GameTooltip:SetOwner(this, "ANCHOR_RIGHT", 4, 0)
            GameTooltip:ClearLines()

            local headerTitle = f.meta.title or ("Primus " .. (this.cleanName or f.id))
            local en = Primus:IsModuleEnabled(f.id)
            if f.id == "System" or f.id == "Options" or f.id == "Skinner" then en = true end

            GameTooltip:AddLine(headerTitle, 1.0, 0.82, 0.0)
            local statStr = en and "|cff33ff33[ Active ]|r" or "|cffff4444[ Disabled ]|r"
            GameTooltip:AddDoubleLine("Category: " .. (f.meta.category or "General"), statStr, 0.41, 0.80, 0.94, 1, 1, 1)

            local d = f.meta.desc or f.meta.description or ("Configures and manages options for " .. (this.cleanName or f.id) .. ".")
            GameTooltip:AddLine(" ", 1, 1, 1)
            GameTooltip:AddLine(d, 0.9, 0.9, 0.9, true)

            local cmd = f.meta.command or f.meta.slash or ("/primus " .. string.lower(string.gsub(this.cleanName or f.id, "%s+", "")))
            GameTooltip:AddLine(" ", 1, 1, 1)
            GameTooltip:AddDoubleLine("Slash Command:", cmd, 0.6, 0.6, 0.6, 1.0, 0.82, 0.2)
            GameTooltip:AddLine("|cff666666<Click tab to configure> <Toggle box to enable/disable>|r", 0.4, 0.4, 0.4)

            GameTooltip:Show()
        end)

        row.btn:SetScript("OnLeave", function()
            local f = this.flare
            if f and f.id ~= activeModuleId then
                this.parentRow:SetBackdropColor(0.08, 0.10, 0.14, 0.85)
                this.parentRow:SetBackdropBorderColor(0.20, 0.25, 0.35, 0.8)
            end
            GameTooltip:Hide()
        end)

        row:Show()
    end

    -- Hide remaining unneeded rows
    local totalCreated = table.getn(moduleRows)
    for i = count + 1, totalCreated do
        if moduleRows[i] then moduleRows[i]:Hide() end
    end

    parent:SetHeight(math.max(count * (rowHeight + spacing) + 10, 100))
end

-- =========================================================================
-- PROFILE IO CONTROLS
-- =========================================================================

local function RefreshProfileSelector(pSelector, pEditBox)
    if not pSelector then return end
    local curProfile = DB:GetCurrentProfile()
    pSelector.text:SetText(Utils.ColorText("Profile: " .. curProfile, "69ccf0"))
    if pEditBox then
        pEditBox:SetText("")
    end
end

-- =========================================================================
-- BUILT-IN SYSTEM FLARE
-- =========================================================================

local function BuildSystemPanel(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetWidth(500)
    p:SetHeight(400)

    -- Section 1: Diagnostics & Memory
    local titleDiag = p:CreateFontString(nil, "OVERLAY")
    titleDiag:SetFont(Media:Fetch("font", "Default"), 11, "OUTLINE")
    titleDiag:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -10)
    titleDiag:SetText(Utils.ColorText("System Diagnostics & Memory Recycling Pool", "69ccf0"))

    local memText = p:CreateFontString(nil, "OVERLAY")
    memText:SetFont(Media:Fetch("font", "Default"), 10, "")
    memText:SetPoint("TOPLEFT", titleDiag, "BOTTOMLEFT", 0, -8)
    memText:SetJustifyH("LEFT")
    p.memText = memText

    local function RefreshMemStats()
        local stats = Memory:GetStats()
        local DebugEngine = Primus.Debug
        local errCount = (DebugEngine and DebugEngine.capturedErrors) and table.getn(DebugEngine.capturedErrors) or 0
        memText:SetText(string.format("• Reusable Tables in Pool: |cff33ff33%d|r\n• Active In-Use Tables: |cffffcc00%d|r\n• Zero Memory Leak Guarantee: |cff33ff33ACTIVE|r\n• Runtime Error Inspector: |c%s%d errors|r", stats.pooled, stats.activeInUse, errCount > 0 and "ffff4444" or "ff33ff33", errCount))
    end
    RefreshMemStats()

    local gcBtn = Widgets:CreateButton(p, "Run Garbage Collection", 160, 22, function()
        local freed = Memory:CollectGarbage()
        RefreshMemStats()
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[Primus]: Garbage Collection complete! Freed %d KB.", freed), "69ccf0"))
    end)
    gcBtn:SetPoint("TOPLEFT", memText, "BOTTOMLEFT", 0, -10)

    local errBtn = Widgets:CreateButton(p, "Open Error Inspector (/errors)", 190, 22, function()
        if Primus.Debug and Primus.Debug.ToggleErrorFrame then
            Primus.Debug:ToggleErrorFrame()
        end
    end)
    errBtn:SetPoint("LEFT", gcBtn, "RIGHT", 10, 0)
    errBtn:SetBackdropBorderColor(0.85, 0.25, 0.25, 1)

    -- Section 2: Global UI Scale & Zen Mode
    local titleScale = p:CreateFontString(nil, "OVERLAY")
    titleScale:SetFont(Media:Fetch("font", "Default"), 11, "OUTLINE")
    titleScale:SetPoint("TOPLEFT", gcBtn, "BOTTOMLEFT", 0, -16)
    titleScale:SetText(Utils.ColorText("Global Scale & Combat Focus Zen Engine", "ffd100"))

    local sScale = Widgets:CreateSlider(p, "Global UI Scale", 0.7, 1.4, 0.05, 1.0, function(val)
        UIParent:SetScale(val)
    end)
    sScale:SetPoint("TOPLEFT", titleScale, "BOTTOMLEFT", 0, -10)

    local zDB = DB:GetNamespace("Zen")
    local cbZen = Widgets:CreateCheckButton(p, "Enable Combat Zen Focus Engine (/primus zen)", zDB and zDB:Get("enabled", true) or true, function(checked)
        local db = DB:GetNamespace("Zen")
        if db then db:Set("enabled", checked) end
        if Primus.State and Primus.State.ApplyState then Primus.State:ApplyState(true) end
    end)
    cbZen:SetPoint("TOPLEFT", sScale, "BOTTOMLEFT", 0, -10)

    -- Section 3: Core QoL Automations
    local titleQoL = p:CreateFontString(nil, "OVERLAY")
    titleQoL:SetFont(Media:Fetch("font", "Default"), 11, "OUTLINE")
    titleQoL:SetPoint("TOPLEFT", cbZen, "BOTTOMLEFT", 0, -14)
    titleQoL:SetText(Utils.ColorText("Core Quality-of-Life Automations", "69ccf0"))

    local cbFastLoot = Widgets:CreateCheckButton(p, "FastLoot (Zero-Delay Instant Auto-Looting)", true, function(checked)
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[Options]: FastLoot " .. (checked and "Enabled" or "Disabled"), "69ccf0"))
    end)
    cbFastLoot:SetPoint("TOPLEFT", titleQoL, "BOTTOMLEFT", 0, -8)

    local cbMechanics = Widgets:CreateCheckButton(p, "AutoMechanics (Auto-Dismount & Auto-Stand on Cast)", true, function(checked)
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[Options]: AutoMechanics " .. (checked and "Enabled" or "Disabled"), "69ccf0"))
    end)
    cbMechanics:SetPoint("TOPLEFT", cbFastLoot, "BOTTOMLEFT", 0, -4)

    local cbCompare = Widgets:CreateCheckButton(p, "ItemCompare (Side-by-Side Equipment Tooltip Comparison)", true, function(checked)
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[Options]: ItemCompare " .. (checked and "Enabled" or "Disabled"), "69ccf0"))
    end)
    cbCompare:SetPoint("TOPLEFT", cbMechanics, "BOTTOMLEFT", 0, -4)

    p:SetScript("OnShow", function()
        RefreshMemStats()
    end)

    return p
end

-- =========================================================================
-- MASTER GUI WINDOW BUILDER
-- =========================================================================

function Options:CreateGUI()
    if optionsFrame then return optionsFrame end

    local w, h = 780, 540
    optionsFrame = CreateFrame("Frame", "Primus_OptionsFrame", UIParent)
    optionsFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    optionsFrame:SetFrameLevel(100)
    optionsFrame:SetWidth(w)
    optionsFrame:SetHeight(h)
    optionsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    optionsFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
    optionsFrame:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
    optionsFrame:SetBackdropBorderColor(0.20, 0.45, 0.85, 1.0)
    optionsFrame:SetMovable(true)
    optionsFrame:EnableMouse(true)
    optionsFrame:RegisterForDrag("LeftButton")
    optionsFrame:SetScript("OnDragStart", function() this:StartMoving() end)
    optionsFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    optionsFrame:Hide()

    -- Title Bar / Header
    local header = CreateFrame("Frame", nil, optionsFrame)
    header:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", optionsFrame, "TOPRIGHT", -4, -4)
    header:SetHeight(26)
    header:SetBackdrop(Media:Fetch("border", "1Pixel"))
    header:SetBackdropColor(0.10, 0.14, 0.22, 1.0)
    header:SetBackdropBorderColor(0.20, 0.40, 0.70, 1)

    local title = header:CreateFontString(nil, "OVERLAY")
    title:SetFont(Media:Fetch("font", "Default"), 11, "OUTLINE")
    title:SetPoint("LEFT", header, "LEFT", 8, 0)
    title:SetText(Utils.ColorText("Primus Suite", "3399ff") .. " |cffaaaaaa// Master Command Center|r")

    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetWidth(18)
    closeBtn:SetHeight(18)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -5, 0)
    closeBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    closeBtn:SetBackdropColor(0.6, 0.1, 0.1, 0.8)
    closeBtn:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
    local cT = closeBtn:CreateFontString(nil, "OVERLAY")
    cT:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    cT:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    cT:SetText("X")
    closeBtn:SetScript("OnClick", function() optionsFrame:Hide() end)

    -- =====================================================================
    -- TOP HORIZONTAL CATEGORY TABS BAR (MIRRORS MODULES/ TAXONOMY)
    -- =====================================================================
    local topCategoryBar = CreateFrame("Frame", nil, optionsFrame)
    topCategoryBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
    topCategoryBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -3)
    topCategoryBar:SetHeight(24)
    topCategoryBar:SetBackdrop(Media:Fetch("border", "1Pixel"))
    topCategoryBar:SetBackdropColor(0.05, 0.06, 0.08, 0.95)
    topCategoryBar:SetBackdropBorderColor(0.18, 0.22, 0.30, 0.8)
    optionsFrame.topCategoryBar = topCategoryBar

    local categoryTabs = {}
    optionsFrame.categoryTabs = categoryTabs

    local numTabs = table.getn(TOP_CATEGORIES)
    local totalBarWidth = w - 8 -- 772
    local tabSpacing = 2
    local tabWidth = math.floor((totalBarWidth - (numTabs - 1) * tabSpacing) / numTabs)

    for idx, catData in ipairs(TOP_CATEGORIES) do
        local tab = CreateFrame("Button", "Primus_OptionsCatTab_" .. catData.id, topCategoryBar)
        tab:SetWidth(tabWidth)
        tab:SetHeight(22)
        tab:SetPoint("LEFT", topCategoryBar, "LEFT", (idx - 1) * (tabWidth + tabSpacing) + 1, 0)
        tab:SetBackdrop(Media:Fetch("border", "1Pixel"))
        tab:SetBackdropColor(0.08, 0.10, 0.14, 0.85)
        tab:SetBackdropBorderColor(0.20, 0.25, 0.35, 0.8)
        tab.catId = catData.id
        tab.catData = catData

        local label = tab:CreateFontString(nil, "OVERLAY")
        label:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
        label:SetPoint("CENTER", tab, "CENTER", 0, 0)
        label:SetText(catData.label)
        tab.label = label

        tab:SetScript("OnClick", function()
            Options:SetSelectedCategory(this.catId)
        end)

        tab:SetScript("OnEnter", function()
            if this.catId ~= selectedCategory then
                this:SetBackdropColor(0.14, 0.20, 0.30, 0.95)
                this:SetBackdropBorderColor(0.35, 0.55, 0.80, 1.0)
            end
            GameTooltip:SetOwner(this, "ANCHOR_TOP", 0, 4)
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Category: " .. this.catData.label, 1.0, 0.82, 0.0)
            GameTooltip:AddLine(this.catData.desc, 0.85, 0.85, 0.85, true)

            local matchCount = 0
            for _, id in ipairs(flareOrder) do
                local flare = registeredFlares[id]
                if flare and MatchesCategory(flare.meta.category, this.catId) then
                    matchCount = matchCount + 1
                end
            end
            GameTooltip:AddLine(string.format("|cff69ccf0Modules in category:|r %d", matchCount), 0.6, 0.8, 1.0)
            GameTooltip:Show()
        end)

        tab:SetScript("OnLeave", function()
            Options:RefreshCategoryTabs()
            GameTooltip:Hide()
        end)

        categoryTabs[idx] = tab
    end

    -- =====================================================================
    -- LEFT 25% STATIC COMMAND CENTER (WIDTH = 196)
    -- =====================================================================
    local sidebar = CreateFrame("Frame", nil, optionsFrame)
    sidebar:SetPoint("TOPLEFT", topCategoryBar, "BOTTOMLEFT", 0, -3)
    sidebar:SetPoint("BOTTOMLEFT", optionsFrame, "BOTTOMLEFT", 4, 4)
    sidebar:SetWidth(196)
    sidebar:SetBackdrop(Media:Fetch("border", "1Pixel"))
    sidebar:SetBackdropColor(0.04, 0.05, 0.07, 0.95)
    sidebar:SetBackdropBorderColor(0.15, 0.18, 0.25, 0.8)

    -- Module Scroll Box
    local modScroll = CreateFrame("ScrollFrame", "Primus_ModListScroll", sidebar, "UIPanelScrollFrameTemplate")
    modScroll:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 4, -4)
    modScroll:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -22, 134)

    local modScrollChild = CreateFrame("Frame", nil, modScroll)
    modScrollChild:SetWidth(168)
    modScrollChild:SetHeight(200)
    modScroll:SetScrollChild(modScrollChild)
    optionsFrame.moduleScrollChild = modScrollChild

    -- Profile & Quick Actions Section (Bottom of Left Column)
    local profileSec = CreateFrame("Frame", nil, sidebar)
    profileSec:SetPoint("TOPLEFT", sidebar, "BOTTOMLEFT", 4, 130)
    profileSec:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -4, 4)
    profileSec:SetBackdrop(Media:Fetch("border", "1Pixel"))
    profileSec:SetBackdropColor(0.06, 0.08, 0.12, 0.9)
    profileSec:SetBackdropBorderColor(0.20, 0.25, 0.35, 0.8)

    local profTitle = profileSec:CreateFontString(nil, "OVERLAY")
    profTitle:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    profTitle:SetPoint("TOPLEFT", profileSec, "TOPLEFT", 6, -4)
    profTitle:SetText(Utils.ColorText("Profile Management", "ffd100"))

    local profSelector = CreateFrame("Button", nil, profileSec)
    profSelector:SetPoint("TOPLEFT", profTitle, "BOTTOMLEFT", 0, -3)
    profSelector:SetPoint("TOPRIGHT", profileSec, "TOPRIGHT", -6, -3)
    profSelector:SetHeight(18)
    profSelector:SetBackdrop(Media:Fetch("border", "1Pixel"))
    profSelector:SetBackdropColor(0.12, 0.16, 0.24, 1.0)
    profSelector:SetBackdropBorderColor(0.30, 0.45, 0.70, 1.0)
    local profText = profSelector:CreateFontString(nil, "OVERLAY")
    profText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    profText:SetPoint("LEFT", profSelector, "LEFT", 4, 0)
    profSelector.text = profText

    -- Profile EditBox
    local profEdit = CreateFrame("EditBox", "Primus_ProfileEditBox", profileSec)
    profEdit:SetPoint("TOPLEFT", profSelector, "BOTTOMLEFT", 0, -4)
    profEdit:SetPoint("TOPRIGHT", profileSec, "TOPRIGHT", -6, -4)
    profEdit:SetHeight(18)
    profEdit:SetFont(Media:Fetch("font", "Default"), 9, "")
    profEdit:SetAutoFocus(false)
    profEdit:SetBackdrop(Media:Fetch("border", "1Pixel"))
    profEdit:SetBackdropColor(0.08, 0.08, 0.10, 1)
    profEdit:SetBackdropBorderColor(0.3, 0.3, 0.4, 1)
    profEdit:SetTextInsets(4, 4, 2, 2)

    -- Save / Load / Delete Buttons
    local btnSave = Widgets:CreateButton(profileSec, "Save", 56, 18, function()
        local name = profEdit:GetText()
        if not name or name == "" then name = DB:GetCurrentProfile() end
        DB:SaveProfile(name)
        RefreshProfileSelector(profSelector, profEdit)
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[Primus]: Profile '%s' saved.", name), "69ccf0"))
    end)
    btnSave:SetPoint("TOPLEFT", profEdit, "BOTTOMLEFT", 0, -4)
    btnSave:SetBackdropBorderColor(0.2, 0.8, 0.4, 1)

    local btnLoad = Widgets:CreateButton(profileSec, "Load", 56, 18, function()
        local name = profEdit:GetText()
        if not name or name == "" then name = DB:GetCurrentProfile() end
        if DB:LoadProfile(name) then
            RefreshProfileSelector(profSelector, profEdit)
            DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[Primus]: Profile '%s' loaded.", name), "69ccf0"))
        end
    end)
    btnLoad:SetPoint("LEFT", btnSave, "RIGHT", 4, 0)
    btnLoad:SetBackdropBorderColor(0.2, 0.6, 1.0, 1)

    local btnDel = Widgets:CreateButton(profileSec, "Del", 56, 18, function()
        local name = profEdit:GetText()
        if not name or name == "" then name = DB:GetCurrentProfile() end
        if DB:DeleteProfile(name) then
            RefreshProfileSelector(profSelector, profEdit)
            DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[Primus]: Profile '%s' deleted.", name), "ff5555"))
        end
    end)
    btnDel:SetPoint("LEFT", btnLoad, "RIGHT", 4, 0)
    btnDel:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)

    -- Quick Utilities: Unlock UI (Auto-hides Options!), HoverBind, Reload UI
    local btnUnlock = Widgets:CreateButton(profileSec, "Unlock UI", 56, 18, function()
        Options:Hide()
        local mover = Primus.PUIMover or PUIMover or _G.PUIMover
        if mover and mover.ToggleLock then
            mover:ToggleLock()
        end
    end)
    btnUnlock:SetPoint("TOPLEFT", btnSave, "BOTTOMLEFT", 0, -4)
    btnUnlock:SetBackdropBorderColor(0.3, 0.6, 1.0, 1)

    local btnBind = Widgets:CreateButton(profileSec, "HoverBind", 56, 18, function()
        Options:Hide()
        if Primus.Keybind and Primus.Keybind.ToggleHoverBind then
            Primus.Keybind:ToggleHoverBind()
        end
    end)
    btnBind:SetPoint("LEFT", btnUnlock, "RIGHT", 4, 0)
    btnBind:SetBackdropBorderColor(1.0, 0.8, 0.2, 1)

    local btnReload = Widgets:CreateButton(profileSec, "Reload", 56, 18, function()
        ReloadUI()
    end)
    btnReload:SetPoint("LEFT", btnBind, "RIGHT", 4, 0)
    btnReload:SetBackdropBorderColor(0.2, 0.8, 0.4, 1)

    -- =====================================================================
    -- RIGHT 75% DYNAMIC LoD CANVAS (WIDTH = 568)
    -- =====================================================================
    local rightContainer = CreateFrame("Frame", nil, optionsFrame)
    rightContainer:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 4, 0)
    rightContainer:SetPoint("BOTTOMRIGHT", optionsFrame, "BOTTOMRIGHT", -4, 4)
    rightContainer:SetBackdrop(Media:Fetch("border", "1Pixel"))
    rightContainer:SetBackdropColor(0.04, 0.05, 0.07, 0.95)
    rightContainer:SetBackdropBorderColor(0.15, 0.18, 0.25, 0.8)

    -- Right Header Banner
    local banner = CreateFrame("Frame", nil, rightContainer)
    banner:SetPoint("TOPLEFT", rightContainer, "TOPLEFT", 4, -4)
    banner:SetPoint("TOPRIGHT", rightContainer, "TOPRIGHT", -4, -4)
    banner:SetHeight(46)
    banner:SetBackdrop(Media:Fetch("border", "1Pixel"))
    banner:SetBackdropColor(0.08, 0.12, 0.18, 1.0)
    banner:SetBackdropBorderColor(0.20, 0.35, 0.60, 1.0)

    local bIcon = banner:CreateTexture(nil, "BORDER")
    bIcon:SetWidth(32)
    bIcon:SetHeight(32)
    bIcon:SetPoint("LEFT", banner, "LEFT", 8, 0)
    bIcon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    banner.icon = bIcon

    local bTitle = banner:CreateFontString(nil, "OVERLAY")
    bTitle:SetFont(Media:Fetch("font", "Default"), 11, "OUTLINE")
    bTitle:SetPoint("TOPLEFT", bIcon, "TOPRIGHT", 8, -2)
    banner.title = bTitle

    local bCat = banner:CreateFontString(nil, "OVERLAY")
    bCat:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    bCat:SetPoint("LEFT", bTitle, "RIGHT", 10, 0)
    banner.cat = bCat

    local bDesc = banner:CreateFontString(nil, "OVERLAY")
    bDesc:SetFont(Media:Fetch("font", "Default"), 9, "")
    bDesc:SetPoint("TOPLEFT", bTitle, "BOTTOMLEFT", 0, -4)
    bDesc:SetTextColor(0.75, 0.75, 0.75)
    banner.desc = bDesc

    local bStatus = banner:CreateFontString(nil, "OVERLAY")
    bStatus:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    bStatus:SetPoint("RIGHT", banner, "RIGHT", -12, 0)
    banner.status = bStatus

    optionsFrame.banner = banner

    -- Right Content Scroll Viewport
    local canvasScroll = CreateFrame("ScrollFrame", "Primus_CanvasScroll", rightContainer, "UIPanelScrollFrameTemplate")
    canvasScroll:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", 0, -4)
    canvasScroll:SetPoint("BOTTOMRIGHT", rightContainer, "BOTTOMRIGHT", -22, 4)

    local canvasScrollChild = CreateFrame("Frame", nil, canvasScroll)
    canvasScrollChild:SetWidth(530)
    canvasScrollChild:SetHeight(390)
    canvasScroll:SetScrollChild(canvasScrollChild)
    optionsFrame.canvasScrollChild = canvasScrollChild

    -- Initial synchronization
    RefreshProfileSelector(profSelector, profEdit)
    Options:RefreshCategoryTabs()
    Options:RefreshModuleList()
    Options:SelectModule("System")

    optionsFrame:SetScript("OnShow", function()
        RefreshProfileSelector(profSelector, profEdit)
        Options:RefreshCategoryTabs()
        Options:RefreshModuleList()
        Options:SelectModule(activeModuleId or "System")
    end)

    local mover = Primus.PUIMover or PUIMover or _G.PUIMover
    if mover and mover.Register then
        mover:Register(optionsFrame, "OptionsGUI", "Master Settings GUI", "UTILITY")
    end

    return optionsFrame
end

function Options:Show()
    self:CreateGUI()
    if optionsFrame then
        optionsFrame:Show()
        optionsFrame:Raise()
    end
end

function Options:Hide()
    if optionsFrame and optionsFrame:IsShown() then
        optionsFrame:Hide()
    end
end

function Options:Toggle()
    self:CreateGUI()
    if optionsFrame:IsShown() then
        optionsFrame:Hide()
    else
        optionsFrame:Show()
        optionsFrame:Raise()
    end
end

function Options:IsOpen()
    return optionsFrame and optionsFrame:IsShown()
end

-- =========================================================================
-- BLIZZARD ESCAPE GAME MENU BUTTON INJECTION
-- =========================================================================

local function SetupGameMenuButton()
    if not GameMenuFrame then return end
    if _G["GameMenuButtonPrimus"] then return end

    local btn = CreateFrame("Button", "GameMenuButtonPrimus", GameMenuFrame, "GameMenuButtonTemplate")
    btn:SetText("PrimusUI")
    btn:SetWidth(144)
    btn:SetHeight(21)

    local btnText = btn:GetFontString()
    if btnText then
        btnText:SetTextColor(0.40, 0.80, 1.00)
    end

    btn:SetScript("OnClick", function()
        PlaySound("igMainMenuOption")
        HideUIPanel(GameMenuFrame)
        Options:Toggle()
    end)

    if GameMenuButtonUIOptions and GameMenuButtonKeybindings then
        btn:SetPoint("TOP", GameMenuButtonUIOptions, "BOTTOM", 0, -1)
        GameMenuButtonKeybindings:SetPoint("TOP", btn, "BOTTOM", 0, -1)

        local origHeight = GameMenuFrame:GetHeight() or 270
        GameMenuFrame:SetHeight(origHeight + 24)

        local origOnShow = GameMenuFrame:GetScript("OnShow")
        GameMenuFrame:SetScript("OnShow", function()
            if origOnShow then origOnShow() end
            GameMenuFrame:SetHeight(origHeight + 24)
            btn:SetPoint("TOP", GameMenuButtonUIOptions, "BOTTOM", 0, -1)
            GameMenuButtonKeybindings:SetPoint("TOP", btn, "BOTTOM", 0, -1)
        end)
    end
end

-- =========================================================================
-- INITIALIZE & REGISTER BUILT-IN FLARES
-- =========================================================================

function Options:OnInitialize()
    -- Register the Core System Flare
    self:RegisterModuleOptions("System", {
        title = "System & Diagnostics",
        category = "System",
        icon = "Interface\\Icons\\Spell_Holy_MindVision",
        desc = "Memory pool statistics, garbage collection, error inspector, and global UI scale.",
        order = 1,
    }, BuildSystemPanel)

    SetupGameMenuButton()
    Events:Register("PLAYER_ENTERING_WORLD", self, function()
        SetupGameMenuButton()
    end)

    -- Register console commands /primus config, /pui config, /primus gui, /pui gui
    local Console = Primus.Console
    if Console then
        Console:RegisterSubCommand("config", function()
            Options:Toggle()
        end, "Open visual Master Command Center GUI")
        Console:RegisterSubCommand("gui", function()
            Options:Toggle()
        end, "Open visual Master Command Center GUI")
    end
end
