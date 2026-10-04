--[[
    PrimusUI Module: PUISpellbook 2.0 (Traditional 2-Page Spread Spellbook & Rank Manager)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Features:
    1. Classic Two-Page Spread (6 spell cards Left Page + 6 spell cards Right Page = 12 per view).
    2. Interactive multi-rank dropdown flyout for 1-click downranking and drag-and-drop.
    3. Live search and filter header with real-time query recalculation.
    4. Right-side discipline skill-line tabs (General, Class Specs, Pet Spells).
    5. Authentic page-turn audio triggers (igSpellBookOpen, igSpellBookClose, igSpellBookPage).
    6. Customizable RGBA Color Theming (Obsidian, Parchment, Arcane, Emerald, Crimson).
    7. Full MoverEngine ("PLAYER" category) and 'P' keybind virtualization.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUISpellbook = Primus.PUISpellbook or {}
Primus.PUISpellbook = PUISpellbook
_G.PUISpellbook = PUISpellbook
Primus:RegisterModule("PUISpellbook", PUISpellbook, "Player")

local DB      = Primus.DB
local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local Events  = Primus.Events
local PUIMover = Primus.PUIMover
local Console = Primus.Console

-- Theme Presets
local THEMES = {
    ["OBSIDIAN"] = {
        name = "Sleek Obsidian",
        bg = { r = 0.06, g = 0.06, b = 0.08, a = 0.96 },
        border = { r = 0.25, g = 0.25, b = 0.30, a = 1.0 },
        accent = { r = 1.00, g = 0.85, b = 0.25, a = 1.0 },
        cardBg = { r = 0.10, g = 0.10, b = 0.13, a = 0.90 },
        cardBorder = { r = 0.20, g = 0.22, b = 0.28, a = 1.0 },
    },
    ["PARCHMENT"] = {
        name = "Antique Parchment",
        bg = { r = 0.16, g = 0.13, b = 0.09, a = 0.96 },
        border = { r = 0.45, g = 0.35, b = 0.20, a = 1.0 },
        accent = { r = 0.95, g = 0.80, b = 0.40, a = 1.0 },
        cardBg = { r = 0.22, g = 0.18, b = 0.13, a = 0.90 },
        cardBorder = { r = 0.38, g = 0.30, b = 0.18, a = 1.0 },
    },
    ["ARCANE"] = {
        name = "Midnight Arcane",
        bg = { r = 0.06, g = 0.08, b = 0.16, a = 0.96 },
        border = { r = 0.20, g = 0.45, b = 0.75, a = 1.0 },
        accent = { r = 0.40, g = 0.85, b = 1.00, a = 1.0 },
        cardBg = { r = 0.09, g = 0.12, b = 0.22, a = 0.90 },
        cardBorder = { r = 0.22, g = 0.35, b = 0.55, a = 1.0 },
    },
    ["EMERALD"] = {
        name = "Fel Emerald",
        bg = { r = 0.05, g = 0.12, b = 0.08, a = 0.96 },
        border = { r = 0.18, g = 0.52, b = 0.28, a = 1.0 },
        accent = { r = 0.35, g = 1.00, b = 0.55, a = 1.0 },
        cardBg = { r = 0.08, g = 0.18, b = 0.12, a = 0.90 },
        cardBorder = { r = 0.18, g = 0.38, b = 0.24, a = 1.0 },
    },
    ["CRIMSON"] = {
        name = "Crimson Horde",
        bg = { r = 0.14, g = 0.06, b = 0.06, a = 0.96 },
        border = { r = 0.55, g = 0.20, b = 0.20, a = 1.0 },
        accent = { r = 1.00, g = 0.40, b = 0.40, a = 1.0 },
        cardBg = { r = 0.20, g = 0.09, b = 0.09, a = 0.90 },
        cardBorder = { r = 0.40, g = 0.18, b = 0.18, a = 1.0 },
    },
}

local spellbookDB = DB:RegisterNamespace("PUISpellbook", {
    enabled = true,
    theme = "OBSIDIAN",
    showAllRanks = false,
})

-- UI State Handles
local mainFrame       = nil
local searchBox       = nil
local pageText        = nil
local prevBtn         = nil
local nextBtn         = nil
local tabButtons      = {}
local spellCards      = {}
local rankFlyout      = nil

local currentTab      = 1
local currentPage     = 1
local totalPages      = 1
local searchQuery     = ""
local CARDS_PER_PAGE  = 12 -- 6 Left Page + 6 Right Page

-- Cached Spell Catalog
local spellCatalog    = {}

-- =========================================================================
-- SPELLBOOK SCANNER & MULTI-RANK GROUPER
-- =========================================================================

function PUISpellbook:ScanSpellbook()
    spellCatalog = {}
    local numTabs = GetNumSpellTabs()

    for tab = 1, numTabs do
        local name, texture, offset, numSpells = GetSpellTabInfo(tab)
        spellCatalog[tab] = {
            name = name or ("Tab " .. tab),
            texture = texture,
            spells = {},
        }

        local groupedByName = {}

        for s = 1, numSpells do
            local spellId = offset + s
            local spellName, subName = GetSpellName(spellId, BOOKTYPE_SPELL)
            local tex = GetSpellTexture(spellId, BOOKTYPE_SPELL)

            if spellName then
                local rankNum = 1
                if subName then
                    local _, _, r = string.find(subName, "Rank (%d+)")
                    if r then rankNum = tonumber(r) or 1 end
                end

                if not groupedByName[spellName] then
                    groupedByName[spellName] = {
                        name = spellName,
                        texture = tex,
                        isPassive = (subName == "Passive"),
                        highestSpellId = spellId,
                        highestRank = rankNum,
                        highestSubName = subName or "",
                        ranks = {},
                    }
                    table.insert(spellCatalog[tab].spells, groupedByName[spellName])
                end

                local group = groupedByName[spellName]
                table.insert(group.ranks, {
                    spellId = spellId,
                    rankNum = rankNum,
                    subName = subName or "",
                    texture = tex,
                })

                if rankNum >= group.highestRank then
                    group.highestRank = rankNum
                    group.highestSpellId = spellId
                    group.highestSubName = subName or ""
                    group.texture = tex
                end
            end
        end
    end
end

-- =========================================================================
-- MULTI-RANK SELECTION FLYOUT
-- =========================================================================

local function ShowRankFlyout(anchorBtn, spellGroup)
    if not spellGroup or not spellGroup.ranks then return end
    if Widgets and Widgets.IsContextMenuShown and Widgets:IsContextMenuShown() then
        Widgets:HideContextMenu()
        return
    end

    local items = {}
    table.insert(items, { text = spellGroup.name or "Spell Ranks", isTitle = true })
    table.insert(items, { isSeparator = true })

    local count = table.getn(spellGroup.ranks)
    for i = 1, count do
        local rData = spellGroup.ranks[i]
        local sId = rData.spellId
        local rankLabel = (rData.subName and rData.subName ~= "") and rData.subName or ("Rank " .. rData.rankNum)
        table.insert(items, {
            text = rankLabel,
            icon = spellGroup.icon,
            color = "69ccf0",
            func = function()
                if sId then
                    CastSpell(sId, BOOKTYPE_SPELL)
                end
            end,
        })
    end

    if Widgets and Widgets.ShowContextMenu then
        Widgets:ShowContextMenu(anchorBtn, items, {
            point = "BOTTOMLEFT",
            relPoint = "TOPLEFT",
            yOffset = 4,
            minWidth = 140,
        })
    end
end

-- =========================================================================
-- SPELL ROW CARD BUILDER (6 Left Page + 6 Right Page)
-- =========================================================================

local function CreateSpellCard(parent, index)
    local card = CreateFrame("Button", "Primus_PUISpellbook_Card_" .. index, parent)
    card:SetWidth(340)
    card:SetHeight(62)
    card:SetBackdrop(Media:Fetch("border", "1Pixel"))
    card:SetBackdropColor(0.10, 0.10, 0.13, 0.90)
    card:SetBackdropBorderColor(0.20, 0.22, 0.28, 1.0)
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    card:RegisterForDrag("LeftButton")

    -- Spell Icon Frame
    local iconFrame = CreateFrame("Frame", nil, card)
    iconFrame:SetWidth(46)
    iconFrame:SetHeight(46)
    iconFrame:SetPoint("LEFT", card, "LEFT", 8, 0)
    iconFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
    iconFrame:SetBackdropBorderColor(0.35, 0.35, 0.40, 1.0)

    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    card.icon = icon
    card.iconFrame = iconFrame

    -- Spell Title
    local nameText = card:CreateFontString(nil, "OVERLAY")
    nameText:SetFont(Media:Fetch("font", "Default"), 11, "OUTLINE")
    nameText:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 10, -3)
    nameText:SetTextColor(1.0, 0.85, 0.25)
    card.nameText = nameText

    -- Subtext / Rank Text
    local subText = card:CreateFontString(nil, "OVERLAY")
    subText:SetFont(Media:Fetch("font", "Default"), 9, "")
    subText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
    subText:SetTextColor(0.75, 0.75, 0.80)
    card.subText = subText

    -- Cost & Cast Info
    local costText = card:CreateFontString(nil, "OVERLAY")
    costText:SetFont(Media:Fetch("font", "Default"), 8, "")
    costText:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMRIGHT", 10, 3)
    costText:SetTextColor(0.45, 0.80, 1.00)
    card.costText = costText

    -- Multi-Rank Dropdown Button
    local rankBtn = CreateFrame("Button", nil, card)
    rankBtn:SetWidth(68)
    rankBtn:SetHeight(20)
    rankBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
    rankBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    rankBtn:SetBackdropColor(0.14, 0.16, 0.22, 0.95)
    rankBtn:SetBackdropBorderColor(0.35, 0.55, 0.80, 1.0)
    rankBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    rankBtn:EnableMouse(true)
    rankBtn:SetFrameLevel(card:GetFrameLevel() + 2)

    local rankBtnText = rankBtn:CreateFontString(nil, "OVERLAY")
    rankBtnText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    rankBtnText:SetPoint("CENTER", rankBtn, "CENTER", 0, 0)
    rankBtnText:SetTextColor(0.40, 0.85, 1.00)
    rankBtnText:SetText("Ranks ▼")
    rankBtn.text = rankBtnText

    rankBtn:SetScript("OnEnter", function()
        rankBtn:SetBackdropColor(0.22, 0.28, 0.40, 1.0)
        rankBtn:SetBackdropBorderColor(0.50, 0.85, 1.00, 1.0)
    end)
    rankBtn:SetScript("OnLeave", function()
        rankBtn:SetBackdropColor(0.14, 0.16, 0.22, 0.95)
        rankBtn:SetBackdropBorderColor(0.35, 0.55, 0.80, 1.0)
    end)

    rankBtn:SetScript("OnClick", function()
        if card.spellGroup and table.getn(card.spellGroup.ranks) > 1 then
            ShowRankFlyout(rankBtn, card.spellGroup)
        end
    end)
    card.rankBtn = rankBtn

    -- Interactivity
    card:SetScript("OnClick", function()
        if this.spellId then
            CastSpell(this.spellId, BOOKTYPE_SPELL)
        end
    end)

    card:SetScript("OnDragStart", function()
        if this.spellId then
            PickupSpell(this.spellId, BOOKTYPE_SPELL)
        end
    end)

    card:SetScript("OnEnter", function()
        card:SetBackdropBorderColor(0.45, 0.80, 1.00, 1.0)
        if this.spellId then
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetSpell(this.spellId, BOOKTYPE_SPELL)
            GameTooltip:Show()
        end
    end)

    card:SetScript("OnLeave", function()
        local t = THEMES[spellbookDB:Get("theme", "OBSIDIAN")] or THEMES["OBSIDIAN"]
        card:SetBackdropBorderColor(t.cardBorder.r, t.cardBorder.g, t.cardBorder.b, t.cardBorder.a)
        GameTooltip:Hide()
    end)

    return card
end

-- =========================================================================
-- SPELLBOOK TWO-PAGE SPREAD BUILDER
-- =========================================================================

function PUISpellbook:CreateSpellbookUI()
    if mainFrame then return mainFrame end

    mainFrame = CreateFrame("Frame", "Primus_PUISpellbookFrame", UIParent)
    mainFrame:SetWidth(740)
    mainFrame:SetHeight(530)
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    mainFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
    mainFrame:EnableMouse(true)
    mainFrame:SetMovable(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function() this:StartMoving() end)
    mainFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    mainFrame:Hide()

    -- Central Spine Divider
    spineDivider = mainFrame:CreateTexture(nil, "BORDER")
    spineDivider:SetWidth(1)
    spineDivider:SetHeight(440)
    spineDivider:SetPoint("TOP", mainFrame, "TOP", 0, -42)
    spineDivider:SetTexture(Media:Fetch("statusbar", "Flat"))
    spineDivider:SetVertexColor(1, 1, 1, 0.08)

    -- Header Title
    local title = mainFrame:CreateFontString(nil, "OVERLAY")
    title:SetFont(Media:Fetch("font", "Default"), 12, "OUTLINE")
    title:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 16, -12)
    title:SetText(Utils.ColorText("PUI SPELLBOOK", "ffd100"))
    mainFrame.title = title

    -- Close Button [X]
    local closeBtn = CreateFrame("Button", "Primus_PUISpellbookCloseBtn", mainFrame)
    closeBtn:SetWidth(20)
    closeBtn:SetHeight(20)
    closeBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -10, -10)
    closeBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    closeBtn:SetBackdropColor(0.35, 0.10, 0.10, 0.95)
    closeBtn:SetBackdropBorderColor(0.80, 0.25, 0.25, 1.0)
    closeBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    closeBtn:EnableMouse(true)
    closeBtn:SetFrameLevel(mainFrame:GetFrameLevel() + 3)

    local closeText = closeBtn:CreateFontString(nil, "OVERLAY")
    closeText:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    closeText:SetPoint("CENTER", 0, 0)
    closeText:SetText("X")
    closeText:SetTextColor(1, 1, 1)
    closeBtn:SetScript("OnClick", function() PUISpellbook:Toggle() end)

    -- Live Search EditBox Header
    local sb = CreateFrame("EditBox", "Primus_PUISpellbookSearchBox", mainFrame)
    sb:SetWidth(200)
    sb:SetHeight(22)
    sb:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -14, 0)
    sb:SetBackdrop(Media:Fetch("border", "1Pixel"))
    sb:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
    sb:SetBackdropBorderColor(0.30, 0.35, 0.45, 1.0)
    sb:SetFont(Media:Fetch("font", "Default"), 10, "")
    sb:SetTextColor(1, 1, 1)
    sb:SetAutoFocus(false)
    sb:SetTextInsets(6, 6, 0, 0)

    local sbHint = sb:CreateFontString(nil, "OVERLAY")
    sbHint:SetFont(Media:Fetch("font", "Default"), 9, "")
    sbHint:SetPoint("LEFT", sb, "LEFT", 8, 0)
    sbHint:SetText(Utils.ColorText("Search Spells...", "777777"))
    sb.hint = sbHint

    sb:SetScript("OnTextChanged", function()
        local text = Utils.Trim(sb:GetText() or "")
        searchQuery = text
        if text == "" then
            sbHint:Show()
        else
            sbHint:Hide()
        end
        currentPage = 1
        PUISpellbook:RefreshUI()
    end)

    sb:SetScript("OnEscapePressed", function()
        sb:SetText("")
        sb:ClearFocus()
    end)
    searchBox = sb

    -- Page Navigation Footer: [◄ Prev Page] | Page X of Y | [Next Page ►]
    prevBtn = CreateFrame("Button", "Primus_PUISpellbookPrevBtn", mainFrame)
    prevBtn:SetWidth(100)
    prevBtn:SetHeight(24)
    prevBtn:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 18, 12)
    prevBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    prevBtn:SetBackdropColor(0.12, 0.15, 0.20, 0.95)
    prevBtn:SetBackdropBorderColor(0.30, 0.45, 0.65, 1.0)
    prevBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    prevBtn:EnableMouse(true)
    prevBtn:SetFrameLevel(mainFrame:GetFrameLevel() + 2)

    local prevText = prevBtn:CreateFontString(nil, "OVERLAY")
    prevText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    prevText:SetPoint("CENTER", 0, 0)
    prevText:SetText("◄ Prev Page")
    prevText:SetTextColor(0.8, 0.9, 1.0)
    prevBtn.text = prevText

    prevBtn:SetScript("OnClick", function()
        if currentPage > 1 then
            currentPage = currentPage - 1
            PlaySound("igSpellBookPage")
            PUISpellbook:RefreshUI()
        end
    end)

    nextBtn = CreateFrame("Button", "Primus_PUISpellbookNextBtn", mainFrame)
    nextBtn:SetWidth(100)
    nextBtn:SetHeight(24)
    nextBtn:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -18, 12)
    nextBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    nextBtn:SetBackdropColor(0.12, 0.15, 0.20, 0.95)
    nextBtn:SetBackdropBorderColor(0.30, 0.45, 0.65, 1.0)
    nextBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    nextBtn:EnableMouse(true)
    nextBtn:SetFrameLevel(mainFrame:GetFrameLevel() + 2)

    local nextText = nextBtn:CreateFontString(nil, "OVERLAY")
    nextText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    nextText:SetPoint("CENTER", 0, 0)
    nextText:SetText("Next Page ►")
    nextText:SetTextColor(0.8, 0.9, 1.0)
    nextBtn.text = nextText

    nextBtn:SetScript("OnClick", function()
        if currentPage < totalPages then
            currentPage = currentPage + 1
            PlaySound("igSpellBookPage")
            PUISpellbook:RefreshUI()
        end
    end)

    pageText = mainFrame:CreateFontString(nil, "OVERLAY")
    pageText:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    pageText:SetPoint("BOTTOM", mainFrame, "BOTTOM", 0, 18)
    pageText:SetTextColor(0.85, 0.85, 0.90)
    pageText:SetText("Page 1 of 1")

    -- Right-Side Skill-Line Tab Container
    local tabBar = CreateFrame("Frame", "Primus_PUISpellbookTabBar", mainFrame)
    tabBar:SetWidth(38)
    tabBar:SetHeight(400)
    tabBar:SetPoint("TOPLEFT", mainFrame, "TOPRIGHT", 2, -40)
    mainFrame.tabBar = tabBar

    -- Build 12 Spell Cards (6 Left Page + 6 Right Page)
    local cardSpacingY = 70
    local startY = -48

    -- Left Page: Cards 1 to 6
    for i = 1, 6 do
        local card = CreateSpellCard(mainFrame, i)
        card:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 18, startY - (i - 1) * cardSpacingY)
        spellCards[i] = card
    end

    -- Right Page: Cards 7 to 12
    for j = 7, 12 do
        local card = CreateSpellCard(mainFrame, j)
        card:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 382, startY - (j - 7) * cardSpacingY)
        spellCards[j] = card
    end

    -- Mousewheel support for page turn
    mainFrame:EnableMouseWheel(true)
    mainFrame:SetScript("OnMouseWheel", function()
        if arg1 > 0 and currentPage > 1 then
            currentPage = currentPage - 1
            PlaySound("igSpellBookPage")
            PUISpellbook:RefreshUI()
        elseif arg1 < 0 and currentPage < totalPages then
            currentPage = currentPage + 1
            PlaySound("igSpellBookPage")
            PUISpellbook:RefreshUI()
        end
    end)

    -- Register with PUIMover under PLAYER category
    local mover = PUIMover or Primus.PUIMover
    if mover and mover.Register then
        mover:Register(mainFrame, "PUISpellbook", "PUISpellbook: 2-Page Spellbook", "PLAYER")
    end

    -- Allow ESC key to close PUISpellbook natively
    table.insert(UISpecialFrames, "Primus_PUISpellbookFrame")

    PUISpellbook:ApplyTheme()
    return mainFrame
end

-- Apply Visual Theme
function PUISpellbook:ApplyTheme()
    if not mainFrame then return end
    local themeKey = spellbookDB:Get("theme", "OBSIDIAN")
    local t = THEMES[themeKey] or THEMES["OBSIDIAN"]

    mainFrame:SetBackdropColor(t.bg.r, t.bg.g, t.bg.b, t.bg.a)
    mainFrame:SetBackdropBorderColor(t.border.r, t.border.g, t.border.b, t.border.a)
    mainFrame.title:SetText(Utils.ColorText("PUI SPELLBOOK", string.format("%02x%02x%02x", t.accent.r * 255, t.accent.g * 255, t.accent.b * 255)))

    for i = 1, 12 do
        local card = spellCards[i]
        if card then
            card:SetBackdropColor(t.cardBg.r, t.cardBg.g, t.cardBg.b, t.cardBg.a)
            card:SetBackdropBorderColor(t.cardBorder.r, t.cardBorder.g, t.cardBorder.b, t.cardBorder.a)
            card.nameText:SetTextColor(t.accent.r, t.accent.g, t.accent.b)
        end
    end
end

-- =========================================================================
-- DISCIPLINE TABS (Right Edge)
-- =========================================================================

function PUISpellbook:BuildTabs()
    local numTabs = table.getn(spellCatalog)
    local tabH = 36

    for i = 1, math.max(numTabs, table.getn(tabButtons)) do
        local tBtn = tabButtons[i]
        if i <= numTabs then
            local tabData = spellCatalog[i]
            if not tBtn then
                tBtn = CreateFrame("Button", "Primus_PUISpellbookTab_" .. i, mainFrame.tabBar)
                tBtn:SetWidth(34)
                tBtn:SetHeight(tabH)
                tBtn:SetPoint("TOPLEFT", mainFrame.tabBar, "TOPLEFT", 0, -(i - 1) * (tabH + 6))
                tBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
                tBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                tBtn:EnableMouse(true)
                tBtn:SetFrameLevel(mainFrame:GetFrameLevel() + 3)

                local icon = tBtn:CreateTexture(nil, "ARTWORK")
                icon:SetPoint("TOPLEFT", tBtn, "TOPLEFT", 2, -2)
                icon:SetPoint("BOTTOMRIGHT", tBtn, "BOTTOMRIGHT", -2, 2)
                icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                tBtn.icon = icon

                tBtn:SetScript("OnClick", function()
                    local idx = this.tabIndex or 1
                    currentTab = idx
                    currentPage = 1
                    PlaySound("igSpellBookPage")
                    PUISpellbook:RefreshUI()
                end)

                tBtn:SetScript("OnEnter", function()
                    this:SetBackdropBorderColor(0.60, 0.85, 1.00, 1.0)
                    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                    GameTooltip:SetText(this.tabName or ("Tab " .. (this.tabIndex or 1)))
                    GameTooltip:Show()
                end)

                tBtn:SetScript("OnLeave", function()
                    local isCur = (this.tabIndex == currentTab)
                    if isCur then
                        this:SetBackdropColor(0.20, 0.45, 0.75, 1.0)
                        this:SetBackdropBorderColor(0.40, 0.90, 1.00, 1.0)
                    else
                        this:SetBackdropColor(0.08, 0.08, 0.12, 0.8)
                        this:SetBackdropBorderColor(0.25, 0.25, 0.30, 0.8)
                    end
                    GameTooltip:Hide()
                end)

                tabButtons[i] = tBtn
            end

            tBtn.tabIndex = i
            tBtn.tabName = tabData.name
            tBtn.icon:SetTexture(tabData.texture or "Interface\\Icons\\INV_Misc_QuestionMark")

            if i == currentTab then
                tBtn:SetBackdropColor(0.20, 0.45, 0.75, 1.0)
                tBtn:SetBackdropBorderColor(0.40, 0.90, 1.00, 1.0)
            else
                tBtn:SetBackdropColor(0.08, 0.08, 0.12, 0.8)
                tBtn:SetBackdropBorderColor(0.25, 0.25, 0.30, 0.8)
            end
            tBtn:Show()
        elseif tBtn then
            tBtn:Hide()
        end
    end
end

-- =========================================================================
-- UI REFRESH & SPREAD RENDERING
-- =========================================================================

function PUISpellbook:RefreshUI()
    if not mainFrame or not mainFrame:IsShown() then return end

    local numTabs = table.getn(spellCatalog)
    if currentTab > numTabs or currentTab < 1 then
        currentTab = 1
    end

    PUISpellbook:BuildTabs()

    -- Filter Spells
    local tabData = spellCatalog[currentTab]
    local filteredSpells = {}

    if tabData and tabData.spells then
        for _, group in ipairs(tabData.spells) do
            local matches = true
            if searchQuery ~= "" then
                local lowerName = string.lower(group.name)
                local lowerQuery = string.lower(searchQuery)
                if not string.find(lowerName, lowerQuery) then
                    matches = false
                end
            end
            if matches then
                table.insert(filteredSpells, group)
            end
        end
    end

    local totalSpells = table.getn(filteredSpells)
    totalPages = math.max(1, math.ceil(totalSpells / CARDS_PER_PAGE))
    if currentPage > totalPages then currentPage = totalPages end
    if currentPage < 1 then currentPage = 1 end

    -- Update Navigation Footer
    pageText:SetText(string.format("Page %d of %d  (%d Spells)", currentPage, totalPages, totalSpells))

    if currentPage <= 1 then
        prevBtn:Disable()
        prevBtn.text:SetTextColor(0.4, 0.4, 0.4)
        prevBtn:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.6)
    else
        prevBtn:Enable()
        prevBtn.text:SetTextColor(0.8, 0.9, 1.0)
        prevBtn:SetBackdropBorderColor(0.30, 0.45, 0.65, 1.0)
    end

    if currentPage >= totalPages then
        nextBtn:Disable()
        nextBtn.text:SetTextColor(0.4, 0.4, 0.4)
        nextBtn:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.6)
    else
        nextBtn:Enable()
        nextBtn.text:SetTextColor(0.8, 0.9, 1.0)
        nextBtn:SetBackdropBorderColor(0.30, 0.45, 0.65, 1.0)
    end

    local startIndex = (currentPage - 1) * CARDS_PER_PAGE

    -- Populate 12 Spell Cards
    for i = 1, CARDS_PER_PAGE do
        local card = spellCards[i]
        local spellIndex = startIndex + i
        local spellGroup = filteredSpells[spellIndex]

        if spellGroup then
            card.spellGroup = spellGroup
            card.spellId = spellGroup.highestSpellId

            card.icon:SetTexture(spellGroup.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            card.nameText:SetText(spellGroup.name)
            card.subText:SetText(spellGroup.highestSubName ~= "" and spellGroup.highestSubName or "Active")

            -- Status / Rank text
            if spellGroup.isPassive then
                card.costText:SetText(Utils.ColorText("Passive Ability", "888888"))
            elseif spellGroup.highestSubName ~= "" then
                card.costText:SetText(Utils.ColorText(spellGroup.highestSubName, "69ccf0"))
            else
                card.costText:SetText(Utils.ColorText("Active Ability", "44ff44"))
            end

            -- Multi-Rank Button
            local rankCount = table.getn(spellGroup.ranks)
            if rankCount > 1 then
                card.rankBtn.text:SetText(string.format("Ranks (%d) ▼", rankCount))
                card.rankBtn:Show()
            else
                card.rankBtn:Hide()
            end

            card:Show()
        else
            card.spellGroup = nil
            card.spellId = nil
            card:Hide()
        end
    end
end

-- =========================================================================
-- OPTIONS FLARE REGISTRATION
-- =========================================================================

function PUISpellbook:RegisterOptionsFlare()
    local Options = Primus.Options
    if not Options or not Options.RegisterModuleOptions then return end

    Options:RegisterModuleOptions("PUISpellbook", "Player", {
        title = "PUISpellbook: 2-Page Spread",
        description = "Classic two-page spread spellbook with multi-rank flyouts and color themes.",
        fields = {
            {
                key = "enabled",
                label = "Enable PUISpellbook 2.0 Spread",
                type = "checkbox",
                default = true,
                get = function() return spellbookDB:Get("enabled", true) end,
                set = function(val)
                    spellbookDB:Set("enabled", val)
                    if val then PUISpellbook:OnEnable() else PUISpellbook:OnDisable() end
                end,
            },
            {
                key = "theme",
                label = "Visual Color Theme",
                type = "dropdown",
                options = {
                    { label = "Sleek Obsidian", value = "OBSIDIAN" },
                    { label = "Antique Parchment", value = "PARCHMENT" },
                    { label = "Midnight Arcane", value = "ARCANE" },
                    { label = "Fel Emerald", value = "EMERALD" },
                    { label = "Crimson Horde", value = "CRIMSON" },
                },
                default = "OBSIDIAN",
                get = function() return spellbookDB:Get("theme", "OBSIDIAN") end,
                set = function(val)
                    spellbookDB:Set("theme", val)
                    PUISpellbook:ApplyTheme()
                end,
            },
        },
    })
end

-- =========================================================================
-- TOGGLE & LIFECYCLE
-- =========================================================================

function PUISpellbook:Toggle()
    local frame = self:CreateSpellbookUI()
    if frame:IsShown() then
        frame:Hide()
        if rankFlyout then rankFlyout:Hide() end
        if Primus.Audio then Primus.Audio:PlaySound("igSpellBookClose") else PlaySound("igSpellBookClose") end
    else
        self:ScanSpellbook()
        frame:Show()
        if Primus.Audio then Primus.Audio:PlaySound("igSpellBookOpen") else PlaySound("igSpellBookOpen") end
        self:RefreshUI()
    end
end

function PUISpellbook:OnInitialize()
    self:RegisterOptionsFlare()

    -- Register Console Subcommand
    if Console and Console.RegisterSubCommand then
        Console:RegisterSubCommand("spellbook", function(arg)
            if arg and THEMES[string.upper(arg)] then
                spellbookDB:Set("theme", string.upper(arg))
                PUISpellbook:ApplyTheme()
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUISpellbook]: Theme set to " .. THEMES[string.upper(arg)].name, "69ccf0"))
            else
                PUISpellbook:Toggle()
            end
        end, "Toggle PUISpellbook 2-page spread or set theme (/pui spellbook [obsidian|parchment|arcane|emerald|crimson])")
    end
end

function PUISpellbook:OnEnable()
    -- Hook Spellbook Events for instant talent/spell sync
    Events:Register("LEARNED_SPELL_IN_TAB", "PUISpellbook", function()
        PUISpellbook:ScanSpellbook()
        PUISpellbook:RefreshUI()
    end)
    Events:Register("SPELLS_CHANGED", "PUISpellbook", function()
        PUISpellbook:ScanSpellbook()
        PUISpellbook:RefreshUI()
    end)

    -- Hook Blizzard ToggleSpellBook function cleanly without mutating C++ frame internals
    if not self._hookedToggle then
        local origToggle = _G["ToggleSpellBook"]
        _G["ToggleSpellBook"] = function(bookType)
            if spellbookDB:Get("enabled", true) and (bookType == BOOKTYPE_SPELL or not bookType) then
                PUISpellbook:Toggle()
            elseif origToggle then
                origToggle(bookType)
            end
        end
        self._hookedToggle = true
    end
end

function PUISpellbook:OnDisable()
    Events:UnregisterOwner("PUISpellbook")
    if mainFrame and mainFrame:IsShown() then
        mainFrame:Hide()
    end
    if rankFlyout and rankFlyout:IsShown() then
        rankFlyout:Hide()
    end
end
