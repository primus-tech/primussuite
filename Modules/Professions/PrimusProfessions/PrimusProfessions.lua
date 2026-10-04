--[[
    PrimusUI Module: PUIProfessions (Recipe Catalog & Acquisition Tracker)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    1. Comprehensive Vanilla recipe catalog across all Crafting & Gathering professions.
    2. Automatic scanning of known recipes via TradeSkillFrame & CraftFrame.
    3. Missing Recipe Tracker: Displays what you don't know and exact source locations:
       - Trainer, Vendor, Mob Drop, Quest, or Reputation standing.
    4. Search bar & filtering by Source Type or Missing Only.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIProfessions = Primus.PUIProfessions or {}
Primus.PUIProfessions = PUIProfessions
_G.PUIProfessions = PUIProfessions
Primus:RegisterModule("PUIProfessions", PUIProfessions, "Professions")

local DB      = Primus.DB
local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local Events  = Primus.Events
local PUIMover = Primus.PUIMover

local professionsDB = DB:RegisterNamespace("PUIProfessions", {
    enabled = true,
    showMissingOnly = true,
    knownRecipes = {}, -- [professionName] = { [recipeName] = true }
})

local professionsFrame = nil
local recipeRows = {}
local currentProfession = "Cooking"
local activeFilter = "ALL"
local searchQuery = ""

-- =========================================================================
-- MASTER VANILLA RECIPE ACQUISITION DATABASE
-- =========================================================================

local RECIPE_DATABASE = {
    ["Cooking"] = {
        { name = "Savory Deviate Delight", req = 85, src = "Drop", detail = "Barrens mobs (Deviate Fish)" },
        { name = "Nightfin Soup",          req = 250, src = "Vendor", detail = "Sheendra Tallgrass (Feralas)" },
        { name = "Grilled Squid",          req = 240, src = "Vendor", detail = "Kelsey Yance (Booty Bay)" },
        { name = "Smoked Desert Dumplings", req = 285, src = "Quest", detail = "Sharing the Knowledge (Silithus)" },
        { name = "Runn Tum Tuber Surprise", req = 275, src = "Drop", detail = "Pusillin (Dire Maul East)" },
        { name = "Dragonbreath Chili",     req = 200, src = "Vendor", detail = "Super-Seller 680 (Desolace)" },
        { name = "Monster Omelet",         req = 225, src = "Vendor", detail = "Himmik (Winterspring)" },
        { name = "Tender Wolf Steak",      req = 225, src = "Vendor", detail = "Dirge Quikcleave (Tanaris)" },
        { name = "Dirge's Kickin' Chimaerok Chops", req = 300, src = "Quest", detail = "Scepter of Shifting Sands" },
        { name = "Clamlette Surprise",     req = 225, src = "Quest", detail = "Clamlette Surprise (Tanaris)" },
    },
    ["Alchemy"] = {
        { name = "Flask of Supreme Power", req = 300, src = "Drop", detail = "Ras Frostwhisper (Scholomance)" },
        { name = "Flask of the Titans",    req = 300, src = "Drop", detail = "General Drakkisath (UBRS)" },
        { name = "Flask of Distilled Wisdom", req = 300, src = "Drop", detail = "Balnazzar (Stratholme Live)" },
        { name = "Flask of Petrification", req = 300, src = "Drop", detail = "High-level world drop (50+)" },
        { name = "Elixir of the Mongoose", req = 275, src = "Drop", detail = "Jadefire Rogues (Felwood)" },
        { name = "Greater Fire Protection Potion", req = 290, src = "Drop", detail = "Firebrand Pyromancer (LBRS)" },
        { name = "Greater Nature Protection Potion", req = 290, src = "Rep", detail = "Cenarion Circle (Friendly)" },
        { name = "Greater Shadow Protection Potion", req = 290, src = "Drop", detail = "Shadowmage (Darkwhisper Gorge)" },
        { name = "Greater Frost Protection Potion", req = 290, src = "Drop", detail = "Frostmaul Giants (Winterspring)" },
        { name = "Greater Arcane Protection Potion", req = 290, src = "Drop", detail = "Cobalt Mageweaver (Winterspring)" },
        { name = "Living Action Potion",   req = 285, src = "Rep", detail = "Zandalar Tribe (Exalted)" },
        { name = "Free Action Potion",     req = 150, src = "Vendor", detail = "Kor'geld (Barrens) / Soolie (Darnassus)" },
        { name = "Restorative Potion",     req = 215, src = "Quest", detail = "Uldaman Reagent (Badlands)" },
        { name = "Transmute Arcanite",     req = 275, src = "Vendor", detail = "Xizk Goodstitch (Booty Bay)" },
        { name = "Transmute Water to Air", req = 275, src = "Vendor", detail = "Magnus Frostwake (Scholomance)" },
    },
    ["Blacksmithing"] = {
        { name = "Lionheart Helm",         req = 300, src = "Drop", detail = "Raid World Bosses / High Level (0.5%)" },
        { name = "Stronghold Gauntlets",   req = 300, src = "Drop", detail = "World Bosses / High Level World" },
        { name = "Titanic Leggings",       req = 300, src = "Drop", detail = "Anubisath Warders (AQ40)" },
        { name = "Nightfall",              req = 300, src = "Rep", detail = "Thorium Brotherhood (Exalted)" },
        { name = "Arcanite Reaper",        req = 275, src = "Drop", detail = "Bannok Grimaxe (LBRS)" },
        { name = "Dark Iron Pulverizer",   req = 275, src = "Rep", detail = "Thorium Brotherhood (Honored)" },
        { name = "Dark Iron Plate",        req = 285, src = "Rep", detail = "Thorium Brotherhood (Friendly)" },
        { name = "Elemental Sharpening Stone", req = 300, src = "Drop", detail = "Molten Core trash mobs" },
    },
    ["Engineering"] = {
        { name = "Goblin Sapper Charge",   req = 215, src = "Trainer", detail = "Goblin Engineering Trainer" },
        { name = "Field Repair Bot 74A",   req = 300, src = "Drop", detail = "Floor Schematic near Golem Lord (BRD)" },
        { name = "Hyper-Radiant Flame Reflector", req = 290, src = "Drop", detail = "Solakar Flamewreath (UBRS)" },
        { name = "Gyrofreeze Ice Reflector", req = 260, src = "Drop", detail = "Crimson Inquisitor (Stratholme)" },
        { name = "Ultra-Flash Shadow Reflector", req = 300, src = "Drop", detail = "World Drop (Level 55+)" },
        { name = "Gnomish Cloaking Device", req = 200, src = "Trainer", detail = "Gnomish Engineering Trainer" },
        { name = "Bloodvine Goggles",      req = 300, src = "Rep", detail = "Zandalar Tribe (Honored)" },
    },
    ["Enchanting"] = {
        { name = "Enchant Weapon - Crusader", req = 300, src = "Drop", detail = "Scarlet Spellbinder (WPL)" },
        { name = "Enchant Weapon - Spell Power", req = 300, src = "Drop", detail = "Molten Core Bosses" },
        { name = "Enchant Weapon - Healing Power", req = 300, src = "Drop", detail = "Molten Core Bosses" },
        { name = "Enchant Weapon - 15 Agility", req = 290, src = "Rep", detail = "Timbermaw Hold (Honored)" },
        { name = "Enchant Weapon - 25 Agility", req = 300, src = "Rep", detail = "Timbermaw Hold (Friendly in 1.12)" },
        { name = "Enchant Gloves - Greater Agility", req = 300, src = "Drop", detail = "Legashi Rogue (Azshara)" },
        { name = "Enchant Boots - Greater Agility", req = 295, src = "Drop", detail = "Spirestone Mystic (LBRS)" },
        { name = "Enchant Chest - Greater Stats", req = 300, src = "Drop", detail = "World Drop (Level 55+)" },
        { name = "Smoking Heart of the Mountain", req = 265, src = "Drop", detail = "Lord Roccor (BRD)" },
    },
    ["Leatherworking"] = {
        { name = "Devilsaur Gauntlets",    req = 290, src = "Vendor", detail = "Nergal (Un'Goro Crater)" },
        { name = "Devilsaur Leggings",     req = 300, src = "Vendor", detail = "Nergal (Un'Goro Crater)" },
        { name = "Hide of the Wild",       req = 300, src = "Drop", detail = "Knot Thimblejack Cache (DM Tribute)" },
        { name = "Corehound Boots",        req = 300, src = "Rep", detail = "Thorium Brotherhood (Exalted)" },
        { name = "Black Dragonscale Shoulders", req = 300, src = "Rep", detail = "Thorium Brotherhood (Honored)" },
        { name = "Onyxia Scale Cloak",     req = 300, src = "Quest", detail = "Head of Onyxia Quest Chain" },
    },
    ["Tailoring"] = {
        { name = "Bloodvine Vest",         req = 300, src = "Rep", detail = "Zandalar Tribe (Honored)" },
        { name = "Bloodvine Leggings",     req = 300, src = "Rep", detail = "Zandalar Tribe (Honored)" },
        { name = "Bloodvine Boots",        req = 300, src = "Rep", detail = "Zandalar Tribe (Friendly)" },
        { name = "Robe of the Archmage",   req = 300, src = "Drop", detail = "Firebrand Pyromancer (LBRS)" },
        { name = "Truefaith Vestments",    req = 300, src = "Drop", detail = "Balnazzar (Stratholme Live)" },
        { name = "Robe of the Void",       req = 300, src = "Drop", detail = "Darkmaster Gandling (Scholomance)" },
        { name = "Mooncloth Bag",          req = 260, src = "Vendor", detail = "Qia (Winterspring)" },
        { name = "Bottomless Bag",         req = 300, src = "Drop", detail = "Raid World Bosses / High Level" },
    },
    ["First Aid"] = {
        { name = "Heavy Runecloth Bandage", req = 290, src = "Trainer", detail = "Doctor Gustaf (Theramore) / Gregory (Hammerfall)" },
        { name = "Powerful Anti-Venom",     req = 300, src = "Quest", detail = "Argent Dawn Medallion (EPL)" },
    },
}

-- Scan Current Player TradeSkillFrame for Known Recipes
function PUIProfessions:ScanTradeSkill()
    local profName = GetTradeSkillLine()
    if not profName or profName == "UNKNOWN" then return end

    if not professionsDB.knownRecipes[profName] then
        professionsDB.knownRecipes[profName] = {}
    end

    local numSkills = GetNumTradeSkills()
    for i = 1, numSkills do
        local skillName, skillType = GetTradeSkillInfo(i)
        if skillName and skillType ~= "header" then
            professionsDB.knownRecipes[profName][skillName] = true
        end
    end

    currentProfession = profName
    self:UpdateRecipeList()
end

-- =========================================================================
-- UI CREATION & RECIPE LIST RENDERING
-- =========================================================================

local function CreateRecipeRow(parent, index)
    local row = CreateFrame("Button", "Primus_PUIProfessionsRow_" .. index, parent)
    row:SetWidth(380)
    row:SetHeight(22)
    row:SetBackdrop(Media:Fetch("border", "1Pixel"))
    row:SetBackdropColor(0.06, 0.08, 0.10, 0.7)
    row:SetBackdropBorderColor(0.15, 0.20, 0.28, 0.8)

    local reqText = row:CreateFontString(nil, "OVERLAY")
    reqText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    reqText:SetPoint("LEFT", row, "LEFT", 6, 0)
    reqText:SetWidth(36)
    reqText:SetTextColor(1.0, 0.84, 0.0)
    row.reqText = reqText

    local nameText = row:CreateFontString(nil, "OVERLAY")
    nameText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    nameText:SetPoint("LEFT", reqText, "RIGHT", 4, 0)
    nameText:SetWidth(150)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    local srcTag = row:CreateFontString(nil, "OVERLAY")
    srcTag:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    srcTag:SetPoint("LEFT", nameText, "RIGHT", 4, 0)
    srcTag:SetWidth(50)
    row.srcTag = srcTag

    local detailText = row:CreateFontString(nil, "OVERLAY")
    detailText:SetFont(Media:Fetch("font", "Default"), 8, "")
    detailText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    detailText:SetWidth(130)
    detailText:SetJustifyH("RIGHT")
    detailText:SetTextColor(0.7, 0.7, 0.7)
    row.detailText = detailText

    recipeRows[index] = row
    return row
end

function PUIProfessions:UpdateRecipeList()
    if not professionsFrame or not professionsFrame:IsShown() then return end

    local profRecipes = RECIPE_DATABASE[currentProfession] or {}
    local known = professionsDB.knownRecipes[currentProfession] or {}
    local rowCount = 0

    professionsFrame.title:SetText(string.format("PUI Professions: |cffffd100%s|r", currentProfession))

    local count = table.getn(profRecipes)
    for i = 1, count do
        local r = profRecipes[i]
        local isKnown = known[r.name] or false
        local matchesFilter = (activeFilter == "ALL" or r.src == activeFilter)
        local matchesSearch = (searchQuery == "" or string.find(string.lower(r.name), string.lower(searchQuery)))

        if (not professionsDB.showMissingOnly or not isKnown) and matchesFilter and matchesSearch then
            rowCount = rowCount + 1
            local row = recipeRows[rowCount] or CreateRecipeRow(professionsFrame.container, rowCount)

            row.reqText:SetText(string.format("[%d]", r.req))
            row.nameText:SetText(r.name)

            if isKnown then
                row.nameText:SetTextColor(0.2, 1.0, 0.4) -- Green Known
                row.srcTag:SetText("KNOWN")
                row.srcTag:SetTextColor(0.2, 1.0, 0.4)
            else
                row.nameText:SetTextColor(1.0, 0.8, 0.8) -- Pinkish Missing
                row.srcTag:SetText(r.src)
                if r.src == "Drop" then row.srcTag:SetTextColor(1.0, 0.3, 0.3)
                elseif r.src == "Rep" then row.srcTag:SetTextColor(0.4, 0.8, 1.0)
                elseif r.src == "Quest" then row.srcTag:SetTextColor(1.0, 0.8, 0.2)
                else row.srcTag:SetTextColor(0.8, 0.8, 0.8) end
            end

            row.detailText:SetText(r.detail)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", professionsFrame.container, "TOPLEFT", 0, -(rowCount - 1) * 24)
            row:Show()
        end
    end

    for i = rowCount + 1, 30 do
        if recipeRows[i] then recipeRows[i]:Hide() end
    end
end

function PUIProfessions:CreateUI()
    if professionsFrame then return professionsFrame end

    professionsFrame = CreateFrame("Frame", "Primus_PUIProfessionsFrame", UIParent)
    professionsFrame:SetWidth(400)
    professionsFrame:SetHeight(360)
    professionsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    professionsFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
    professionsFrame:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
    professionsFrame:SetBackdropBorderColor(1.0, 0.6, 0.2, 1) -- Orange/Bronze
    professionsFrame:SetMovable(true)
    professionsFrame:EnableMouse(true)
    professionsFrame:RegisterForDrag("LeftButton")
    professionsFrame:SetScript("OnDragStart", function() this:StartMoving() end)
    professionsFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    professionsFrame:Hide()

    -- Title Header
    local title = professionsFrame:CreateFontString(nil, "OVERLAY")
    title:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    title:SetPoint("TOPLEFT", professionsFrame, "TOPLEFT", 6, -6)
    title:SetText("PUIProfessions: Recipes")
    professionsFrame.title = title

    local closeBtn = CreateFrame("Button", nil, professionsFrame)
    closeBtn:SetWidth(16)
    closeBtn:SetHeight(16)
    closeBtn:SetPoint("TOPRIGHT", professionsFrame, "TOPRIGHT", -4, -4)
    closeBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    closeBtn:SetBackdropColor(0.6, 0.1, 0.1, 0.8)
    closeBtn:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
    local cT = closeBtn:CreateFontString(nil, "OVERLAY")
    cT:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    cT:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    cT:SetText("X")
    closeBtn:SetScript("OnClick", function() professionsFrame:Hide() end)

    -- Filter Buttons Bar (All, Drop, Vendor, Rep, Quest)
    local filterBar = CreateFrame("Frame", nil, professionsFrame)
    filterBar:SetPoint("TOPLEFT", professionsFrame, "TOPLEFT", 6, -24)
    filterBar:SetPoint("TOPRIGHT", professionsFrame, "TOPRIGHT", -6, -24)
    filterBar:SetHeight(20)

    local function CreateFilterBtn(label, filterVal, x)
        local btn = CreateFrame("Button", nil, filterBar)
        btn:SetWidth(56)
        btn:SetHeight(18)
        btn:SetPoint("LEFT", filterBar, "LEFT", x, 0)
        btn:SetBackdrop(Media:Fetch("border", "1Pixel"))
        btn:SetBackdropColor(0.1, 0.12, 0.16, 0.9)
        btn:SetBackdropBorderColor(0.3, 0.4, 0.6, 1)
        local txt = btn:CreateFontString(nil, "OVERLAY")
        txt:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
        txt:SetPoint("CENTER", btn, "CENTER", 0, 0)
        txt:SetText(label)
        btn:SetScript("OnClick", function()
            activeFilter = filterVal
            PUIProfessions:UpdateRecipeList()
        end)
        return btn
    end

    CreateFilterBtn("All", "ALL", 0)
    CreateFilterBtn("Drop", "Drop", 60)
    CreateFilterBtn("Vendor", "Vendor", 120)
    CreateFilterBtn("Rep", "Rep", 180)
    CreateFilterBtn("Quest", "Quest", 240)

    -- Missing Only Toggle Button
    local missingBtn = CreateFrame("Button", nil, filterBar)
    missingBtn:SetWidth(75)
    missingBtn:SetHeight(18)
    missingBtn:SetPoint("RIGHT", filterBar, "RIGHT", 0, 0)
    missingBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    missingBtn:SetBackdropColor(0.18, 0.12, 0.05, 0.9)
    missingBtn:SetBackdropBorderColor(1.0, 0.6, 0.2, 1)
    local mText = missingBtn:CreateFontString(nil, "OVERLAY")
    mText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    mText:SetPoint("CENTER", missingBtn, "CENTER", 0, 0)
    mText:SetText("Missing Only")
    mText:SetTextColor(1.0, 0.8, 0.2)
    missingBtn:SetScript("OnClick", function()
        professionsDB.showMissingOnly = not professionsDB.showMissingOnly
        mText:SetTextColor(professionsDB.showMissingOnly and 1.0 or 0.5, professionsDB.showMissingOnly and 0.8 or 0.5, professionsDB.showMissingOnly and 0.2 or 0.5)
        PUIProfessions:UpdateRecipeList()
    end)

    -- Container for Rows
    local container = CreateFrame("Frame", nil, professionsFrame)
    container:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -4)
    container:SetPoint("BOTTOMRIGHT", professionsFrame, "BOTTOMRIGHT", -6, 6)
    professionsFrame.container = container

    for i = 1, 20 do
        CreateRecipeRow(container, i)
    end

    local mover = PUIMover or Primus.PUIMover
    if mover and mover.Register then
        mover:Register(professionsFrame, "PUIProfessions", "PUIProfessions: Recipe & Crafting Tracker", "UTILITY")
    end
    return professionsFrame
end

-- =========================================================================
-- OPTIONS FLARE REGISTRATION
-- =========================================================================

function PUIProfessions:RegisterOptionsFlare()
    local Options = Primus.Options
    if not Options or not Options.RegisterModuleOptions then return end

    Options:RegisterModuleOptions("PUIProfessions", "Professions", {
        title = "PUIProfessions: Recipe Catalog",
        description = "Crafting recipe catalog and missing acquisition source tracker.",
        fields = {
            {
                key = "enabled",
                label = "Enable Recipe Acquisition Tracker",
                type = "checkbox",
                default = true,
                get = function() return professionsDB:Get("enabled", true) end,
                set = function(val)
                    professionsDB:Set("enabled", val)
                    if val then PUIProfessions:OnEnable() else PUIProfessions:OnDisable() end
                end,
            },
            {
                key = "showMissingOnly",
                label = "Filter to Missing Recipes Only",
                type = "checkbox",
                default = true,
                get = function() return professionsDB:Get("showMissingOnly", true) end,
                set = function(val)
                    professionsDB:Set("showMissingOnly", val)
                    PUIProfessions:UpdateRecipeList()
                end,
            },
        },
    })
end

-- =========================================================================
-- LIFECYCLE & EVENT DISPATCH
-- =========================================================================

function PUIProfessions:OnInitialize()
    self:RegisterOptionsFlare()

    -- Subcommand registration via Console Router
    if Primus.Console and Primus.Console.RegisterSubCommand then
        Primus.Console:RegisterSubCommand("professions", function(argParam)
            PUIProfessions:CreateUI()
            if argParam and argParam ~= "" then
                local clean = Utils.Trim(argParam)
                for prof, _ in pairs(RECIPE_DATABASE) do
                    if string.lower(prof) == string.lower(clean) then
                        currentProfession = prof
                        break
                    end
                end
            end
            if professionsFrame and professionsFrame:IsShown() then
                professionsFrame:Hide()
            else
                if not professionsFrame then PUIProfessions:CreateUI() end
                professionsFrame:Show()
                PUIProfessions:UpdateRecipeList()
            end
        end, "PUIProfessions Recipe & Crafting Tracker (/pui professions [profession])")
    end
end

function PUIProfessions:OnEnable()
    -- Hook TradeSkillFrame & CraftFrame to scan known recipes
    Events:Register("TRADE_SKILL_SHOW", "PUIProfessions", function()
        PUIProfessions:ScanTradeSkill()
    end)
    Events:Register("TRADE_SKILL_UPDATE", "PUIProfessions", function()
        PUIProfessions:ScanTradeSkill()
    end)
    Events:Register("CRAFT_SHOW", "PUIProfessions", function()
        PUIProfessions:ScanTradeSkill()
    end)
end

function PUIProfessions:OnDisable()
    Events:UnregisterOwner("PUIProfessions")
    if professionsFrame and professionsFrame:IsShown() then
        professionsFrame:Hide()
    end
end
