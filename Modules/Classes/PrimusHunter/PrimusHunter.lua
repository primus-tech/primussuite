--[[
    PrimusLib Module: Class_Hunter (Ammo, Pet Happiness, Diet Scanner & Swing Bar)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Tracks ranged ammo count with low-ammo alerts, pet happiness/loyalty,
    pet food diet matching with 1-click Feed Pet, and Auto-Shot swing timers.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local _, playerClass = UnitClass("player")
if playerClass ~= "HUNTER" then return end

local PUIHunter = Primus.PUIHunter or {}
Primus.PUIHunter = PUIHunter
_G.PUIHunter = PUIHunter
Primus:RegisterModule("PUIHunter", PUIHunter, "Classes")

local DB      = Primus.DB
local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local Events  = Primus.Events
local Time    = Primus.Time
local PUIMover = Primus.PUIMover

local hunterDB = DB:RegisterNamespace("PUIHunter", {
    enabled = true,
})

local hudFrame = nil
local swingBar = nil
local swingStartTime = 0
local swingDuration = 2.5

-- Pet Happiness Data
local HAPPINESS_LABELS = {
    [1] = { name = "Unhappy (75% Dmg)", color = { 1.0, 0.2, 0.2 } },
    [2] = { name = "Content (100% Dmg)", color = { 1.0, 0.8, 0.2 } },
    [3] = { name = "Happy (125% Dmg)", color = { 0.2, 1.0, 0.4 } },
}

local HUNTER_BIG_SPELLS = {
    { name = "Tranquilizing Shot", short = "Tranq",   tex = "Spell_Nature_Drowsy" },
    { name = "Feign Death",        short = "FD",      tex = "Ability_Rogue_FeignDeath" },
    { name = "Rapid Fire",         short = "Rapid",   tex = "Ability_Hunter_RunningShot" },
    { name = "Bestial Wrath",      short = "BW",      tex = "Ability_Druid_FerociousBite" },
    { name = "Scatter Shot",       short = "Scatter", tex = "Ability_GolemStorm" },
    { name = "Deterrence",         short = "Det",     tex = "Ability_Whirlwind" },
    { name = "Intimidation",       short = "Intim",   tex = "Ability_Devour" },
}

local knownSpells = {}

function PUIHunter:ScanSpellbook()
    knownSpells = {}
    local i = 1
    local numBig = table.getn(HUNTER_BIG_SPELLS)
    while true do
        local spellName = GetSpellName(i, BOOKTYPE_SPELL)
        if not spellName then break end
        local texture = GetSpellTexture(i, BOOKTYPE_SPELL)
        for idx = 1, numBig do
            local bigSpell = HUNTER_BIG_SPELLS[idx]
            if string.find(spellName, bigSpell.name) or (texture and string.find(texture, bigSpell.tex)) then
                if not knownSpells[bigSpell.name] then
                    knownSpells[bigSpell.name] = {
                        spellID = i,
                        name    = bigSpell.name,
                        texture = texture,
                        short   = bigSpell.short,
                        tex     = bigSpell.tex,
                    }
                end
            end
        end
        i = i + 1
    end
end

function PUIHunter:GetMajorCooldowns()
    local list = {}
    local numBig = table.getn(HUNTER_BIG_SPELLS)
    for idx = 1, numBig do
        local def = HUNTER_BIG_SPELLS[idx]
        local info = knownSpells[def.name]
        if info then
            local start, duration = GetSpellCooldown(info.spellID, BOOKTYPE_SPELL)
            local remaining = 0
            if start and start > 0 and duration and duration > 0 then
                remaining = (start + duration) - GetTime()
                if remaining < 0 then remaining = 0 end
            end
            table.insert(list, {
                name = def.name,
                short = def.short,
                tex = def.tex,
                icon = info.texture or ("Interface\\Icons\\" .. def.tex),
                duration = duration or 0,
                remaining = remaining,
                isReady = (remaining <= 0),
                spellId = info.spellID,
            })
        end
    end
    return list
end

-- Count Equipped Ammo
function PUIHunter:GetAmmoCount()
    local count = GetInventoryItemCount("player", 0) -- Slot 0 is equipped Ammo in 1.12
    local link = GetInventoryItemLink("player", 0)
    local texture = GetInventoryItemTexture("player", 0)
    return count or 0, link, texture
end

local hunterScanTooltip = nil
local function GetHunterScanTooltip()
    if not hunterScanTooltip then
        hunterScanTooltip = CreateFrame("GameTooltip", "Primus_Hunter_ScanTooltip", UIParent, "GameTooltipTemplate")
        hunterScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    return hunterScanTooltip
end

-- Comprehensive Vanilla WoW Pet Diet Keyword Matchers
local MEAT_KEYWORDS = {
    "jerky", "meat", "rib", "ribs", "steak", "chop", "chops", "flesh", "haunch", "wing", "wings", "pork", "venison", "beef", 
    "chicken", "mutton", "sausage", "liver", "clam", "clams", "crawler", "gizzard", "flank", "carcass", 
    "quail", "turkey", "kebab", "roast", "bacon", "tripe", "tenderloin", "cutlet", "strips", 
    "shank", "filet", "fillet", "lamb", "veal", "sirloin", "brisket", "ham", "goulash", "stew", 
    "broth", "crab", "scorpid", "raptor", "stag", "wolf", "boar", "lion", "bear", "tiger", 
    "crocolisk", "turtle", "buzzard", "strider", "vulture", "basilisk", "chimera", "spider", 
    "lynx", "owl", "strigid", "rat", "goretusk", "coyote", "snout", "claw", "dragon", "chunk", 
    "morsel", "tendon", "heart", "kidney", "tongue", "entrails", "tail", "egg", "eggs", "omelet"
}

local FISH_KEYWORDS = {
    "fish", "salmon", "trout", "catfish", "sunscale", "snapper", "cod", "squid", "lobster", 
    "albacore", "mackerel", "smallfish", "mud snapper", "brilliant", "longjaw", "blackmouth", 
    "firefin", "deviate", "rockscale", "grouper", "nightfin", "plagued", "smooth", "frenzy", 
    "bass", "redgill", "sagefish", "scale", "fin", "gill", "eel", "carp", "perch", "herring",
    "yellowtail", "clamshell"
}

local BREAD_KEYWORDS = {
    "bread", "loaf", "roll", "rolls", "biscuit", "biscuits", "muffin", "muffins", "ration", "rations", "bun", "cake", "cookie", 
    "cookies", "flatbread", "sweetroll", "crust", "toast", "pastry", "dough", "pie", "tart", 
    "cornbread", "sourdough", "rye", "wheat", "brioche", "baguette", "pumpernickel", "grain", "corn"
}

local CHEESE_KEYWORDS = {
    "cheese", "cheddar", "brie", "curd", "curds", "gouda", "swiss", "bleu", "darnassian", 
    "alterac", "dalaran", "stormwind brie", "wedge", "wheel"
}

local FRUIT_KEYWORDS = {
    "apple", "apples", "banana", "bananas", "fruit", "fruits", "melon", "melons", "snapvine", "watermelon", "watermelons", 
    "orange", "oranges", "berry", "berries", "grape", "grapes", "peach", "peaches", "pear", "pears", "plum", "plums", 
    "cactus", "pineapple", "fig", "figs", "cherry", "cherries", "lemon", "lemons", "lime", "limes", "citrus", 
    "papaya", "mango", "mangoes", "pomegranate", "tangerine", "date", "dates", "raisin", "raisins", "tel'abim", 
    "plantain", "honeydew", "prune", "prunes"
}

local FUNGUS_KEYWORDS = {
    "mushroom", "mushrooms", "fungus", "spore", "spores", "shroom", "truffle", "truffles", "cap", "morel", "toadstool", 
    "puffball", "lichen", "cave mold", "mold", "fungi", "underspore"
}

-- Fallback family diets if GetPetFoodTypes() returns empty
local FAMILY_DIETS = {
    ["cat"] = { "meat", "fish" },
    ["panther"] = { "meat", "fish" },
    ["tiger"] = { "meat", "fish" },
    ["lion"] = { "meat", "fish" },
    ["cougar"] = { "meat", "fish" },
    ["lynx"] = { "meat", "fish" },
    ["wolf"] = { "meat" },
    ["worg"] = { "meat" },
    ["bear"] = { "meat", "fish", "cheese", "bread", "fungus", "fruit" },
    ["boar"] = { "meat", "fish", "cheese", "bread", "fungus", "fruit" },
    ["raptor"] = { "meat" },
    ["spider"] = { "meat" },
    ["crocolisk"] = { "meat", "fish" },
    ["croc"] = { "meat", "fish" },
    ["wind serpent"] = { "fish", "bread", "cheese" },
    ["bat"] = { "fruit", "fungus" },
    ["owl"] = { "meat" },
    ["bird of prey"] = { "meat" },
    ["carrion bird"] = { "meat", "fish" },
    ["hyena"] = { "meat", "fruit" },
    ["tallstrider"] = { "cheese", "fruit", "fungus" },
    ["strider"] = { "cheese", "fruit", "fungus" },
    ["crab"] = { "fish", "bread", "fungus" },
    ["scorpid"] = { "meat" },
    ["gorilla"] = { "fruit", "fungus" },
    ["turtle"] = { "fruit", "fungus" },
}

local NON_FOOD_JUNK_WORDS = {
    "bone", "bones", "skull", "tusk", "tusks", "tooth", "teeth", "fang", "fangs", 
    "feather", "feathers", "pelt", "pelts", "hide", "hides", "fur", "furs", 
    "eye", "eyes", "venom", "blood", "horn", "horns", "hoof", "hooves", 
    "talon", "talons", "beak", "beaks", "carapace", "chitin"
}

local function IsNonFoodExcluded(lower, itemType, isConsumableFood)
    -- Exclude equipment / armor / weapons / containers
    if itemType == "Armor" or itemType == "Weapon" or itemType == "Container" or itemType == "Quiver" then
        return true
    end
    if string.find(lower, "durability %d+ / %d+") or string.find(lower, "binds when") or string.find(lower, "soulbound") then
        return true
    end

    -- Strict non-food consumables
    if string.find(lower, "potion") or string.find(lower, "elixir") or string.find(lower, "flask") 
       or string.find(lower, "bandage") or string.find(lower, "first aid") or string.find(lower, "poison")
       or string.find(lower, "scroll of") or string.find(lower, "hearthstone") or string.find(lower, "soulstone")
       or string.find(lower, "healthstone") or string.find(lower, "spellstone") then
        return true
    end

    -- Pure mana drinks (exclude only if it doesn't also restore health)
    if (string.find(lower, "drinking") or string.find(lower, "restores %d+ mana")) and not string.find(lower, "eating") and not string.find(lower, "restores %d+ health") then
        return true
    end

    -- Common pure drinks
    if string.find(lower, "spring water") or string.find(lower, "morning glory dew") or string.find(lower, "sweet nectar") 
       or string.find(lower, "moonberry juice") or string.find(lower, "melon juice") or string.find(lower, "ice cold milk") 
       or string.find(lower, "plain milk") then
        return true
    end

    -- If it is NOT a player consumable food (i.e. mob drop / trade good), check for non-food junk words
    if not isConsumableFood then
        for _, junk in ipairs(NON_FOOD_JUNK_WORDS) do
            if string.find(lower, junk) then
                return true
            end
        end
    end

    return false
end

local function ClassifyItemFoodType(itemName, itemType, itemSubType, tooltipText)
    if not itemName or itemName == "" then return nil end
    local lower = string.lower(itemName .. " " .. (itemSubType or "") .. " " .. (tooltipText or ""))

    local isConsumableFood = false
    if tooltipText and (string.find(lower, "eating") or string.find(lower, "restores %d+ health") or string.find(lower, "must remain seated while eating")) then
        isConsumableFood = true
    end

    if IsNonFoodExcluded(lower, itemType, isConsumableFood) then
        return nil
    end

    -- Match against categories
    for _, kw in ipairs(MEAT_KEYWORDS) do
        if string.find(lower, kw) then return "meat" end
    end
    for _, kw in ipairs(FISH_KEYWORDS) do
        if string.find(lower, kw) then return "fish" end
    end
    for _, kw in ipairs(BREAD_KEYWORDS) do
        if string.find(lower, kw) then return "bread" end
    end
    for _, kw in ipairs(CHEESE_KEYWORDS) do
        if string.find(lower, kw) then return "cheese" end
    end
    for _, kw in ipairs(FRUIT_KEYWORDS) do
        if string.find(lower, kw) then return "fruit" end
    end
    for _, kw in ipairs(FUNGUS_KEYWORDS) do
        if string.find(lower, kw) then return "fungus" end
    end

    -- Generic cooked food fallback (if tooltip indicates edible health restoration)
    if isConsumableFood then
        return "bread"
    end

    return nil
end

-- Scan Bags for All Pet Foods matching Pet Diet
function PUIHunter:GetAllPetFoods()
    if not UnitExists("pet") then return {} end

    local diets = {}
    local dietList = { GetPetFoodTypes() }
    if dietList and table.getn(dietList) > 0 then
        for _, diet in ipairs(dietList) do
            if diet and diet ~= "" then
                diets[string.lower(diet)] = true
            end
        end
    end

    -- Boars and Bears are omnivores (they eat all 6 Vanilla food types)
    local family = UnitCreatureFamily("pet")
    local famLower = family and string.lower(family) or ""
    if famLower == "boar" or famLower == "bear" or string.find(famLower, "boar") or string.find(famLower, "bear") then
        diets["meat"] = true
        diets["fish"] = true
        diets["bread"] = true
        diets["cheese"] = true
        diets["fruit"] = true
        diets["fungus"] = true
    elseif famLower and FAMILY_DIETS[famLower] then
        for _, d in ipairs(FAMILY_DIETS[famLower]) do
            diets[d] = true
        end
    end

    -- Safe fallback: if diet list could not be determined, allow all food types
    if not next(diets) then
        diets["meat"] = true
        diets["fish"] = true
        diets["bread"] = true
        diets["cheese"] = true
        diets["fruit"] = true
        diets["fungus"] = true
    end

    local tt = GetHunterScanTooltip()
    local foodList = {}

    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local texture, count = GetContainerItemInfo(bag, slot)
                if texture then
                    -- Extract item name from link pattern [Item Name]
                    local link = GetContainerItemLink(bag, slot)
                    local itemName, itemType, itemSubType
                    if link then
                        local _, _, nameInLink = string.find(link, "%[(.+)%]")
                        if nameInLink and nameInLink ~= "" then
                            itemName = nameInLink
                        end
                        local infoName, _, _, _, iType, iSubType = GetItemInfo(link)
                        itemName = itemName or infoName
                        itemType = iType
                        itemSubType = iSubType
                    end

                    -- Tooltip scan directly from local bag slot
                    tt:SetOwner(UIParent, "ANCHOR_NONE")
                    tt:ClearLines()
                    tt:SetBagItem(bag, slot)

                    local line1 = _G["Primus_Hunter_ScanTooltipTextLeft1"]
                    local ttName = line1 and line1:GetText()
                    itemName = itemName or ttName

                    if itemName and itemName ~= "" then
                        local ttText = ""
                        local numLines = tt:NumLines() or 0
                        for j = 1, numLines do
                            local lineObj = _G["Primus_Hunter_ScanTooltipTextLeft" .. j]
                            if lineObj then
                                local lineText = lineObj:GetText()
                                if lineText then
                                    ttText = ttText .. " " .. lineText
                                end
                            end
                        end

                        local foodType = ClassifyItemFoodType(itemName, itemType, itemSubType, ttText)
                        if foodType and (diets[foodType] or diets["raw " .. foodType] or diets["meat"]) then
                            table.insert(foodList, {
                                name = itemName,
                                bag = bag,
                                slot = slot,
                                texture = texture or "Interface\\Icons\\INV_Misc_Food_14",
                                count = count or 1,
                                foodType = foodType,
                            })
                        end
                    end
                end
            end
        end
    end
    return foodList
end

-- Find the currently active or preferred pet food
function PUIHunter:FindPetFood()
    local foods = self:GetAllPetFoods()
    if not foods or table.getn(foods) == 0 then
        return nil, nil, nil, nil, nil
    end

    -- If player selected a preferred food name, check if it still exists
    if self.preferredFoodName then
        for _, food in ipairs(foods) do
            if food.name == self.preferredFoodName then
                return food.name, food.bag, food.slot, food.texture, food.count
            end
        end
    end

    -- Default to first available food
    local first = foods[1]
    return first.name, first.bag, first.slot, first.texture, first.count
end

-- Safely Cast Feed Pet without ever leaving an item or spell targeting stuck on the cursor
function PUIHunter:FeedPet(bag, slot)
    if not bag or not slot or not UnitExists("pet") then return end

    if CursorHasItem() then
        ClearCursor()
    end
    if SpellIsTargeting() then
        SpellStopTargeting()
    end

    CastSpellByName("Feed Pet")
    if SpellIsTargeting() then
        PickupContainerItem(bag, slot)
    end

    -- Safety check: If food was picked up to cursor instead of consumed, put it back immediately
    if CursorHasItem() then
        PickupContainerItem(bag, slot)
        ClearCursor()
    end
    if SpellIsTargeting() then
        SpellStopTargeting()
    end
end

-- =========================================================================
-- INTERACTIVE PET FOOD POPUP MENU
-- =========================================================================

local foodMenuFrame = nil
local foodMenuButtons = {}

function PUIHunter:ToggleFoodMenu()
    if foodMenuFrame and foodMenuFrame:IsShown() then
        foodMenuFrame:Hide()
        return
    end
    self:ShowFoodMenu()
end

function PUIHunter:ShowFoodMenu()
    if not UnitExists("pet") then return end

    if not foodMenuFrame then
        foodMenuFrame = CreateFrame("Frame", "Primus_HunterFoodMenu", UIParent)
        foodMenuFrame:SetFrameStrata("DIALOG")
        foodMenuFrame:SetClampedToScreen(true)
        foodMenuFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
        foodMenuFrame:SetBackdropColor(0.06, 0.08, 0.06, 0.96)
        foodMenuFrame:SetBackdropBorderColor(0.3, 0.7, 0.3, 1.0)
        foodMenuFrame:EnableMouse(true)
        tinsert(UISpecialFrames, "Primus_HunterFoodMenu")

        local title = foodMenuFrame:CreateFontString(nil, "OVERLAY")
        title:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
        title:SetPoint("TOPLEFT", foodMenuFrame, "TOPLEFT", 8, -6)
        title:SetText("Feed Pet - Select Food")
        title:SetTextColor(0.4, 0.9, 0.4)
        foodMenuFrame.title = title

        local hint = foodMenuFrame:CreateFontString(nil, "OVERLAY")
        hint:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
        hint:SetPoint("TOPRIGHT", foodMenuFrame, "TOPRIGHT", -8, -7)
        hint:SetText("[ESC to Close]")
        hint:SetTextColor(0.5, 0.5, 0.5)

        foodMenuFrame:SetScript("OnHide", function()
            GameTooltip:Hide()
        end)
    end

    local foods = self:GetAllPetFoods()
    local numFoods = table.getn(foods)
    local width = 230
    local rowHeight = 22
    local headerHeight = 26
    local totalHeight = headerHeight + (math.max(numFoods, 1) * rowHeight) + 8

    foodMenuFrame:SetWidth(width)
    foodMenuFrame:SetHeight(totalHeight)
    foodMenuFrame:ClearAllPoints()

    if hudFrame and hudFrame.petContainer then
        foodMenuFrame:SetPoint("BOTTOMLEFT", hudFrame.petContainer, "TOPLEFT", -20, 6)
    else
        foodMenuFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    -- Hide all existing buttons first
    for _, btn in ipairs(foodMenuButtons) do
        btn:Hide()
    end

    if numFoods == 0 then
        if not foodMenuFrame.noFoodText then
            local nf = foodMenuFrame:CreateFontString(nil, "OVERLAY")
            nf:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
            nf:SetPoint("CENTER", foodMenuFrame, "CENTER", 0, -8)
            nf:SetText("No pet food found in bags")
            nf:SetTextColor(0.6, 0.6, 0.6)
            foodMenuFrame.noFoodText = nf
        end
        foodMenuFrame.noFoodText:Show()
    else
        if foodMenuFrame.noFoodText then
            foodMenuFrame.noFoodText:Hide()
        end

        for idx, food in ipairs(foods) do
            local btn = foodMenuButtons[idx]
            if not btn then
                btn = CreateFrame("Button", "Primus_HunterFoodBtn_" .. idx, foodMenuFrame)
                btn:SetHeight(rowHeight - 2)
                btn:SetBackdrop(Media:Fetch("border", "1Pixel"))
                btn:SetBackdropColor(0.10, 0.12, 0.10, 0.8)
                btn:SetBackdropBorderColor(0.25, 0.35, 0.25, 0.8)

                local icon = btn:CreateTexture(nil, "ARTWORK")
                icon:SetWidth(16)
                icon:SetHeight(16)
                icon:SetPoint("LEFT", btn, "LEFT", 3, 0)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                btn.icon = icon

                local text = btn:CreateFontString(nil, "OVERLAY")
                text:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
                text:SetPoint("LEFT", icon, "RIGHT", 5, 0)
                text:SetPoint("RIGHT", btn, "RIGHT", -42, 0)
                text:SetJustifyH("LEFT")
                btn.text = text

                local tag = btn:CreateFontString(nil, "OVERLAY")
                tag:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
                tag:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
                btn.tag = tag

                btn:SetScript("OnEnter", function()
                    this:SetBackdropColor(0.20, 0.35, 0.20, 1.0)
                    this:SetBackdropBorderColor(0.40, 0.90, 0.40, 1.0)
                    if this.bag and this.slot then
                        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                        GameTooltip:SetBagItem(this.bag, this.slot)
                        GameTooltip:Show()
                    end
                end)

                btn:SetScript("OnLeave", function()
                    this:SetBackdropColor(0.10, 0.12, 0.10, 0.8)
                    this:SetBackdropBorderColor(0.25, 0.35, 0.25, 0.8)
                    GameTooltip:Hide()
                end)

                btn:SetScript("OnClick", function()
                    if this.bag and this.slot then
                        PUIHunter.preferredFoodName = this.foodName
                        PUIHunter:FeedPet(this.bag, this.slot)
                        PUIHunter:UpdateHUD()
                        foodMenuFrame:Hide()
                    end
                end)

                foodMenuButtons[idx] = btn
            end

            btn:SetWidth(width - 12)
            btn:SetPoint("TOPLEFT", foodMenuFrame, "TOPLEFT", 6, -headerHeight - ((idx - 1) * rowHeight))
            btn.bag = food.bag
            btn.slot = food.slot
            btn.foodName = food.name
            btn.icon:SetTexture(food.texture)
            btn.text:SetText(string.format("%s (%d)", food.name, food.count))
            btn.tag:SetText(string.upper(string.sub(food.foodType or "FOOD", 1, 4)))

            if food.foodType == "meat" then
                btn.tag:SetTextColor(1.0, 0.5, 0.5)
            elseif food.foodType == "fish" then
                btn.tag:SetTextColor(0.4, 0.8, 1.0)
            elseif food.foodType == "bread" then
                btn.tag:SetTextColor(0.9, 0.8, 0.4)
            elseif food.foodType == "cheese" then
                btn.tag:SetTextColor(1.0, 0.9, 0.2)
            elseif food.foodType == "fruit" then
                btn.tag:SetTextColor(0.5, 1.0, 0.5)
            elseif food.foodType == "fungus" then
                btn.tag:SetTextColor(0.8, 0.5, 1.0)
            else
                btn.tag:SetTextColor(0.7, 0.7, 0.7)
            end

            btn:Show()
        end
    end

    foodMenuFrame:Show()
end

-- Update Hunter HUD
function PUIHunter:UpdateHUD()
    if not hudFrame or not hudFrame:IsShown() then return end

    -- 1. Ammo Tracker
    local ammoCount, ammoLink, ammoTex = self:GetAmmoCount()
    hudFrame.ammoText:SetText(string.format("Ammo: %d", ammoCount))
    if ammoCount <= 50 then
        hudFrame.ammoText:SetTextColor(1.0, 0.2, 0.2) -- Red critical
    elseif ammoCount <= 200 then
        hudFrame.ammoText:SetTextColor(1.0, 0.8, 0.2) -- Yellow warning
    else
        hudFrame.ammoText:SetTextColor(0.8, 0.9, 0.5) -- Normal
    end

    -- 2. Pet Happiness & Food
    if UnitExists("pet") then
        local happiness, damagePercent, loyaltyRate = GetPetHappiness()
        local hInfo = HAPPINESS_LABELS[happiness or 3] or HAPPINESS_LABELS[3]
        hudFrame.petText:SetText(string.format("Pet: %s", hInfo.name))
        hudFrame.petText:SetTextColor(hInfo.color[1], hInfo.color[2], hInfo.color[3])

        if hudFrame.petHap then
            if happiness == 1 then
                hudFrame.petHap.tex:SetTexCoord(0.375, 0.5625, 0, 0.359375)
                hudFrame.petHap:Show()
            elseif happiness == 2 then
                hudFrame.petHap.tex:SetTexCoord(0.1875, 0.375, 0, 0.359375)
                hudFrame.petHap:Show()
            elseif happiness == 3 then
                hudFrame.petHap.tex:SetTexCoord(0, 0.1875, 0, 0.359375)
                hudFrame.petHap:Show()
            else
                hudFrame.petHap:Hide()
            end
        end

        local foodName, bag, slot, foodTex, foodCount = self:FindPetFood()
        if foodName then
            local dispName = (string.len(foodName) > 14) and (string.sub(foodName, 1, 12) .. "..") or foodName
            hudFrame.foodText:SetText(string.format("Food: %s (%d)", dispName, foodCount or 1))
            hudFrame.foodText:SetTextColor(0.2, 0.8, 1.0)
            if hudFrame.feedBtn then
                hudFrame.feedBtn.bag = bag
                hudFrame.feedBtn.slot = slot
                hudFrame.feedBtn:Enable()
                if hudFrame.feedBtn.text then
                    hudFrame.feedBtn.text:SetTextColor(0.9, 0.9, 0.9)
                end
            end
        else
            hudFrame.foodText:SetText("Food: None")
            hudFrame.foodText:SetTextColor(0.6, 0.6, 0.6)
            if hudFrame.feedBtn then
                hudFrame.feedBtn.bag = nil
                hudFrame.feedBtn.slot = nil
                hudFrame.feedBtn:Disable()
                if hudFrame.feedBtn.text then
                    hudFrame.feedBtn.text:SetTextColor(0.4, 0.4, 0.4)
                end
            end
        end
        hudFrame.petContainer:Show()
    else
        if hudFrame.petHap then hudFrame.petHap:Hide() end
        hudFrame.petText:SetText("Pet: None")
        hudFrame.petText:SetTextColor(0.5, 0.5, 0.5)
        hudFrame.foodText:SetText("")
        hudFrame.petContainer:Hide()
    end
end

function PUIHunter:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIHunter", {
        name = "PUIHunter",
        category = "Classes",
        label = "Hunter Nuances",
        options = {
            {
                key = "enabled",
                type = "checkbox",
                label = "Enable Hunter Suite",
                desc = "Show ammo counter, Pet happiness/feed helper, and Auto-Shot swing bar.",
                default = true,
                get = function() return hunterDB:Get("enabled") end,
                set = function(v)
                    hunterDB:Set("enabled", v)
                    if v then hudFrame:Show() else hudFrame:Hide() end
                end,
            },
        },
    })
end

function PUIHunter:OnInitialize()
    -- Create Hunter HUD Bar
    hudFrame = CreateFrame("Frame", "Primus_HunterHUD", UIParent)
    hudFrame:SetWidth(320)
    hudFrame:SetHeight(32)
    hudFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 160)
    hudFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
    hudFrame:SetBackdropColor(0.06, 0.08, 0.06, 0.9)
    hudFrame:SetBackdropBorderColor(0.4, 0.8, 0.3, 1)

    -- Ammo Text
    local ammoText = hudFrame:CreateFontString(nil, "OVERLAY")
    ammoText:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    ammoText:SetPoint("LEFT", hudFrame, "LEFT", 8, 0)
    ammoText:SetText("Ammo: 0")
    hudFrame.ammoText = ammoText

    -- Pet Sub-Container (Clickable for Food Menu)
    local petContainer = CreateFrame("Button", nil, hudFrame)
    petContainer:SetPoint("LEFT", ammoText, "RIGHT", 12, 0)
    petContainer:SetPoint("RIGHT", hudFrame, "RIGHT", -4, 0)
    petContainer:SetHeight(28)
    petContainer:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    petContainer:SetScript("OnClick", function()
        if arg1 == "RightButton" then
            PUIHunter:ToggleFoodMenu()
        end
    end)
    petContainer:SetScript("OnEnter", function()
        GameTooltip:SetOwner(petContainer, "ANCHOR_TOPRIGHT")
        GameTooltip:AddLine("Pet Quick Panel", 0.4, 0.9, 0.4)
        local foodName = PUIHunter:FindPetFood()
        if foodName then
            GameTooltip:AddLine("Active Food: " .. foodName, 0.2, 0.8, 1.0)
        end
        GameTooltip:AddLine("|cff69ccf0Right-Click:|r Open Food Menu", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    petContainer:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    hudFrame.petContainer = petContainer

    -- Pet Happiness Icon
    local petHap = CreateFrame("Frame", nil, petContainer)
    petHap:SetWidth(16)
    petHap:SetHeight(16)
    petHap:SetPoint("TOPLEFT", petContainer, "TOPLEFT", 0, -2)
    local petHapTex = petHap:CreateTexture(nil, "ARTWORK")
    petHapTex:SetAllPoints(petHap)
    petHapTex:SetTexture("Interface\\PetPaperDollFrame\\UI-PetHappiness")
    petHap.tex = petHapTex
    hudFrame.petHap = petHap

    local petText = petContainer:CreateFontString(nil, "OVERLAY")
    petText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    petText:SetPoint("LEFT", petHap, "RIGHT", 4, 0)
    petText:SetText("Pet: Content")
    hudFrame.petText = petText

    local foodText = petContainer:CreateFontString(nil, "OVERLAY")
    foodText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    foodText:SetPoint("BOTTOMLEFT", petContainer, "BOTTOMLEFT", 0, 2)
    foodText:SetText("Food: Meat")
    hudFrame.foodText = foodText

    -- Quick 1-Click Feed Pet Button (Left-Click to Feed, Right-Click for Food Menu)
    local feedBtn = Widgets:CreateButton(petContainer, "Feed", 45, 18, function()
        if arg1 == "RightButton" then
            PUIHunter:ToggleFoodMenu()
        else
            if this.bag and this.slot then
                PUIHunter:FeedPet(this.bag, this.slot)
            else
                PUIHunter:ToggleFoodMenu()
            end
        end
    end)
    feedBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    feedBtn:SetPoint("RIGHT", petContainer, "RIGHT", -4, 0)
    feedBtn:SetScript("OnEnter", function()
        this:SetBackdropColor(0.25, 0.25, 0.30, 1.0)
        this:SetBackdropBorderColor(0.40, 0.70, 1.00, 1.0)
        GameTooltip:SetOwner(this, "ANCHOR_TOPRIGHT")
        if this.bag and this.slot then
            GameTooltip:SetBagItem(this.bag, this.slot)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff69ccf0Left-Click:|r Feed Pet with this item", 0.4, 0.9, 0.4)
        else
            GameTooltip:AddLine("Feed Pet", 0.4, 0.9, 0.4)
            GameTooltip:AddLine("No quick food detected in bags.", 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine("|cff69ccf0Right-Click:|r Choose food from bag menu", 0.9, 0.8, 0.3)
        GameTooltip:Show()
    end)
    feedBtn:SetScript("OnLeave", function()
        this:SetBackdropColor(0.15, 0.15, 0.18, 1.0)
        this:SetBackdropBorderColor(0.30, 0.30, 0.35, 1.0)
        GameTooltip:Hide()
    end)
    hudFrame.feedBtn = feedBtn
    local mover = PUIMover or Primus.PUIMover
    if mover and mover.Register then
        mover:Register(hudFrame, "HunterHUD", "Hunter Suite (Ammo & Pet)", "CLASS")
    end

    -- Auto-Shot Swing Bar
    swingBar = Widgets:CreateStatusBar(UIParent, 180, 14, 0, 2.5)
    swingBar:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    swingBar:SetStatusBarColor(0.7, 0.9, 0.4, 1.0)
    swingBar.text:SetText("Auto Shot")
    swingBar:Hide()

    if mover and mover.Register then
        mover:Register(swingBar, "HunterAutoShot", "Hunter Auto-Shot Swing Bar", "CLASS")
    end

    self:RegisterOptionsFlare()
end

function PUIHunter:OnEnable()
    if hudFrame and hunterDB:Get("enabled") then
        hudFrame:Show()
    end

    -- Events
    Events:Register("START_AUTOREPEAT_SPELL", self, function()
        local speed = UnitRangedDamage("player") or 2.5
        swingDuration = speed
        swingStartTime = GetTime()
        swingBar:SetMinMaxValues(0, swingDuration)
        swingBar:SetValue(0)
        swingBar:Show()
    end)

    Events:Register("STOP_AUTOREPEAT_SPELL", self, function()
        swingStartTime = 0
        swingBar:Hide()
    end)

    -- Cast completion hook for Aimed Shot / Multi-Shot swing resets
    local lastHunterCast = nil
    Events:Register("SPELLCAST_START", self, function(owner, event, spellName, duration)
        lastHunterCast = spellName
    end)

    Events:Register("SPELLCAST_STOP", self, function()
        if lastHunterCast == "Aimed Shot" or lastHunterCast == "Multi-Shot" then
            local speed = UnitRangedDamage("player") or 2.5
            swingDuration = speed
            swingStartTime = GetTime()
            swingBar:SetMinMaxValues(0, swingDuration)
            swingBar:SetValue(0)
            swingBar:Show()
        end
        lastHunterCast = nil
    end)

    Events:Register("SPELLCAST_FAILED", self, function()
        lastHunterCast = nil
    end)

    Events:Register("SPELLCAST_INTERRUPTED", self, function()
        lastHunterCast = nil
    end)

    Events:Listen("PRIMUS_COMBAT_EVENT", self, function(owner, data)
        if not data then return end
        if (data.isSwing or data.isRanged) and data.source == UnitName("player") then
            local speed = UnitRangedDamage("player") or 2.5
            swingDuration = speed
            swingStartTime = GetTime()
            swingBar:SetMinMaxValues(0, swingDuration)
            swingBar:SetValue(0)
            swingBar:Show()
        end
    end)

    -- Spellbook & Cooldown Events
    self:ScanSpellbook()
    Events:Register("SPELLS_CHANGED", self, function() PUIHunter:ScanSpellbook() PUIHunter:UpdateHUD() end)
    Events:Register("LEARNED_SPELL_IN_TAB", self, function() PUIHunter:ScanSpellbook() PUIHunter:UpdateHUD() end)
    Events:Register("SPELL_UPDATE_COOLDOWN", self, function() PUIHunter:UpdateHUD() end)
    Events:Register("PLAYER_ENTERING_WORLD", self, function() PUIHunter:ScanSpellbook() PUIHunter:UpdateHUD() end)

    Events:Register("UNIT_INVENTORY_CHANGED", self, function()
        PUIHunter:UpdateHUD()
    end)
    Events:Register("UNIT_PET", self, function()
        PUIHunter:UpdateHUD()
    end)
    Events:Register("UNIT_HAPPINESS", self, function()
        PUIHunter:UpdateHUD()
    end)
    Events:Register("BAG_UPDATE", self, function()
        PUIHunter:UpdateHUD()
    end)

    -- Auto-Shot Swing Bar Driver
    local swingThrottle = 0
    swingBar:SetScript("OnUpdate", function()
        local elapsed = arg1 or 0.04
        swingThrottle = swingThrottle + elapsed
        if swingThrottle < 0.033 then return end
        swingThrottle = 0

        if swingStartTime > 0 and swingBar:IsShown() then
            local passed = GetTime() - swingStartTime
            if passed <= swingDuration then
                swingBar:SetValue(passed)
                local rem = swingDuration - passed
                swingBar.text:SetText(string.format("Auto Shot: %.1fs", rem))
            else
                swingBar:SetValue(swingDuration)
                swingBar.text:SetText("Auto Shot: Ready")
            end
        end
    end)

    Time:Every(2.0, function()
        PUIHunter:UpdateHUD()
    end, self)

    self:UpdateHUD()
end

function PUIHunter:OnDisable()
    Time:CancelAll(self)
    Events:UnregisterOwner(self)
    swingStartTime = 0
    if swingBar then
        swingBar:SetScript("OnUpdate", nil)
        swingBar:Hide()
    end
    if hudFrame then hudFrame:Hide() end
end


