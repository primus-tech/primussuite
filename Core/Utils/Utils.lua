--[[
    PrimusLib: Lua 5.0.2 Utility Engine & Polyfills
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local Utils = Primus.Utils

-- =========================================================================
-- TABLE UTILITIES & HELPERS (Lua 5.0 Compliant)
-- =========================================================================

-- Reusable wipe function that doesn't trigger table deallocation
function Utils.Wipe(t)
    if type(t) ~= "table" then return t end
    for k in pairs(t) do
        t[k] = nil
    end
    t.n = 0
    return t
end

-- Shallow Copy
function Utils.Copy(src, dest)
    dest = dest or {}
    if type(src) ~= "table" then return src end
    for k, v in pairs(src) do
        dest[k] = v
    end
    return dest
end

-- Deep Copy (Protected against cyclic references & deep recursion)
function Utils.DeepCopy(src, seen, depth)
    if type(src) ~= "table" then return src end
    depth = depth or 0
    if depth > 30 then return src end

    seen = seen or {}
    if seen[src] then return seen[src] end

    local copy = {}
    seen[src] = copy

    for k, v in pairs(src) do
        if type(v) == "table" then
            copy[k] = Utils.DeepCopy(v, seen, depth + 1)
        else
            copy[k] = v
        end
    end
    return copy
end

-- Deep Merge (Protected against cyclic references & deep recursion)
function Utils.DeepMerge(dest, src, seen, depth)
    if type(dest) ~= "table" or type(src) ~= "table" then return dest end
    depth = depth or 0
    if depth > 30 then return dest end

    seen = seen or {}
    if seen[src] then return dest end
    seen[src] = true

    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dest[k]) ~= "table" then
                dest[k] = {}
            end
            Utils.DeepMerge(dest[k], v, seen, depth + 1)
        elseif dest[k] == nil then
            dest[k] = v
        end
    end
    return dest
end

-- Count number of keys in a dictionary table (since table.getn only works on arrays)
function Utils.Count(t)
    if type(t) ~= "table" then return 0 end
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

-- Find value index in an array
function Utils.IndexOf(t, target)
    if type(t) ~= "table" then return nil end
    local n = table.getn(t)
    for i = 1, n do
        if t[i] == target then
            return i
        end
    end
    return nil
end

-- =========================================================================
-- STRING UTILITIES (Vanilla Pattern & String Ops)
-- =========================================================================

function Utils.Trim(s)
    if not s or type(s) ~= "string" then return "" end
    return string.gsub(s, "^%s*(.-)%s*$", "%1")
end

function Utils.StartsWith(s, prefix)
    if not s or not prefix then return false end
    return string.sub(s, 1, string.len(prefix)) == prefix
end

function Utils.EndsWith(s, suffix)
    if not s or not suffix then return false end
    return suffix == "" or string.sub(s, -string.len(suffix)) == suffix
end

-- Fast string splitting into a table (using delimiter)
function Utils.Split(s, delimiter, dest)
    dest = dest or {}
    Utils.Wipe(dest)
    if not s or s == "" then return dest end
    delimiter = delimiter or "%s+"

    local pattern = string.format("([^%s]+)", delimiter)
    local count = 0
    string.gsub(s, pattern, function(match)
        count = count + 1
        dest[count] = match
    end)
    dest.n = count
    return dest
end

-- =========================================================================
-- MATH UTILITIES
-- =========================================================================

function Utils.Clamp(val, minVal, maxVal)
    if val < minVal then return minVal end
    if val > maxVal then return maxVal end
    return val
end

function Utils.Round(val, decimals)
    decimals = decimals or 0
    local mult = math.pow(10, decimals)
    return math.floor(val * mult + 0.5) / mult
end

-- Safe Modulo (Lua 5.0 math.mod wrapper)
function Utils.Mod(a, b)
    if not b or b == 0 then return 0 end
    if math.mod then
        return math.mod(a, b)
    else
        return a - math.floor(a / b) * b
    end
end

-- Get accurate Unit Health & Max Health with MobHealth support and stable percentage detection
function Utils.GetUnitHealth(unit)
    unit = unit or "player"
    if not UnitExists(unit) then return 0, 1, 0, false end

    local curHP = UnitHealth(unit) or 0
    local maxHP = UnitHealthMax(unit) or 1
    local isEstimated = false

    if unit == "target" and not UnitIsPlayer("target") then
        local _G_ref = getglobals and getglobals() or _G or getfenv(0)
        if _G_ref.MobHealth_GetTargetCurMaxHP then
            local mhCur, mhMax = _G_ref.MobHealth_GetTargetCurMaxHP()
            if mhCur and mhMax and mhMax > 0 then
                curHP = mhCur
                maxHP = mhMax
                isEstimated = true
            end
        elseif _G_ref.MobHealth3 and _G_ref.MobHealth3.GetUnitHealth then
            local mhCur, mhMax = _G_ref.MobHealth3:GetUnitHealth("target")
            if mhCur and mhMax and mhMax > 0 then
                curHP = mhCur
                maxHP = mhMax
                isEstimated = true
            end
        end
    end

    local pct = maxHP > 0 and math.floor((curHP / maxHP) * 100) or 0
    return curHP, maxHP, pct, isEstimated
end

-- =========================================================================
-- COLOR & FORMATTING UTILITIES
-- =========================================================================

-- Convert Hex string ("#RRGGBB" or "RRGGBB") to RGB (0-1 floats)
function Utils.HexToRGB(hex)
    if not hex then return 1, 1, 1, 1 end
    hex = string.gsub(hex, "^#", "")
    if string.len(hex) == 6 then
        local r = tonumber(string.sub(hex, 1, 2), 16) / 255
        local g = tonumber(string.sub(hex, 3, 4), 16) / 255
        local b = tonumber(string.sub(hex, 5, 6), 16) / 255
        return r, g, b, 1
    elseif string.len(hex) == 8 then
        local r = tonumber(string.sub(hex, 1, 2), 16) / 255
        local g = tonumber(string.sub(hex, 3, 4), 16) / 255
        local b = tonumber(string.sub(hex, 5, 6), 16) / 255
        local a = tonumber(string.sub(hex, 7, 8), 16) / 255
        return r, g, b, a
    end
    return 1, 1, 1, 1
end

-- Convert RGB (0-1 floats) to Hex string ("|cffRRGGBB")
function Utils.RGBToHex(r, g, b)
    r = Utils.Clamp(math.floor((r or 1) * 255), 0, 255)
    g = Utils.Clamp(math.floor((g or 1) * 255), 0, 255)
    b = Utils.Clamp(math.floor((b or 1) * 255), 0, 255)
    return string.format("|cff%02x%02x%02x", r, g, b)
end

-- Colorize text with Hex
function Utils.ColorText(text, hex)
    if not hex then return text end
    if not Utils.StartsWith(hex, "|c") then
        hex = "|cff" .. string.gsub(hex, "^#", "")
    end
    return hex .. tostring(text) .. "|r"
end

-- 1.12 Class Colors
Utils.ClassColors = {
    ["WARRIOR"] = { r = 0.78, g = 0.61, b = 0.43, hex = "c79c6e" },
    ["MAGE"]    = { r = 0.41, g = 0.80, b = 0.94, hex = "69ccf0" },
    ["ROGUE"]   = { r = 1.00, g = 0.96, b = 0.41, hex = "fff569" },
    ["DRUID"]   = { r = 1.00, g = 0.49, b = 0.04, hex = "ff7d0a" },
    ["HUNTER"]  = { r = 0.67, g = 0.83, b = 0.45, hex = "abd473" },
    ["SHAMAN"]  = { r = 0.00, g = 0.44, b = 0.87, hex = "0070de" }, -- Classic Vanilla Shaman Blue
    ["PRIEST"]  = { r = 1.00, g = 1.00, b = 1.00, hex = "ffffff" },
    ["WARLOCK"] = { r = 0.58, g = 0.51, b = 0.79, hex = "9482c9" },
    ["PALADIN"] = { r = 0.96, g = 0.55, b = 0.73, hex = "f58cba" },
}

function Utils.GetClassColor(className)
    if not className then return 0.8, 0.8, 0.8, "cccccc" end
    local upper = string.upper(className)
    local c = Utils.ClassColors[upper]
    if c then
        return c.r, c.g, c.b, c.hex
    end
    return 0.8, 0.8, 0.8, "cccccc"
end

-- =========================================================================
-- HYPERLINK UTILITIES
-- =========================================================================

-- Extract raw payload ("item:1234:...") from formatted chat link ("|c...|Hitem:1234:...|h...")
function Utils.ExtractLink(link)
    if not link or type(link) ~= "string" then return nil end
    local _, _, clean = string.find(link, "|H(.-)|h")
    return clean or link
end

-- Extract item name from formatted item hyperlink ("|c...|Hitem:...|h[Item Name]|h|r")
function Utils.ExtractItemName(link)
    if not link or type(link) ~= "string" then return "" end
    local _, _, name = string.find(link, "%[(.+)%]")
    return name or link
end

-- Format integer with thousands separators (e.g. 1,234,567)
function Utils.FormatNumber(val)
    if not val then return "0" end
    local num = math.floor(tonumber(val) or 0)
    local formatted = tostring(num)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end

-- Format copper currency into Gold/Silver/Copper string with color codes
function Utils.FormatMoney(copper, formatType)
    copper = tonumber(copper) or 0
    local isNegative = copper < 0
    copper = math.abs(copper)
    local gold = math.floor(copper / 10000)
    local silver = math.floor(Utils.Mod(copper, 10000) / 100)
    local cop = Utils.Mod(copper, 100)

    local str = ""
    if gold > 0 then
        str = str .. string.format("%d|cffffd100g|r ", gold)
    end
    if silver > 0 or gold > 0 then
        str = str .. string.format("%d|cffe6e6e6s|r ", silver)
    end
    str = str .. string.format("%d|cffc87d3ec|r", cop)
    if isNegative then
        str = "-" .. str
    end
    return str
end

-- Safely get CVar value without throwing if CVar does not exist in 1.12.1
function Utils.GetCVar(cvarName, defaultVal)
    if not cvarName or type(GetCVar) ~= "function" then return defaultVal end
    local ok, val = pcall(GetCVar, cvarName)
    if ok and val ~= nil then
        return val
    end
    return defaultVal
end

-- =========================================================================
-- SPELLBOOK & KNOWN SPELL HELPERS
-- =========================================================================

local knownSpellsCache = nil

-- Scan all spellbook tabs and cache learned spells & ranks
function Utils.ScanKnownSpells()
    knownSpellsCache = {}
    local numTabs = GetNumSpellTabs()
    for t = 1, numTabs do
        local _, _, offset, numSpells = GetSpellTabInfo(t)
        for s = 1, numSpells do
            local spellName, spellRank = GetSpellName(offset + s, BOOKTYPE_SPELL)
            if spellName then
                knownSpellsCache[string.lower(spellName)] = {
                    name = spellName,
                    rank = spellRank,
                    index = offset + s,
                }
            end
        end
    end
    return knownSpellsCache
end

-- Check if a spell is known in the player's spellbook
function Utils.IsSpellKnown(spellName)
    if not spellName then return false end
    if not knownSpellsCache then
        Utils.ScanKnownSpells()
    end
    return knownSpellsCache[string.lower(spellName)] ~= nil
end

-- Get cached spell information
function Utils.GetKnownSpellInfo(spellName)
    if not spellName then return nil end
    if not knownSpellsCache then
        Utils.ScanKnownSpells()
    end
    return knownSpellsCache[string.lower(spellName)]
end

-- Resolve the best learned cleanse spell for a given player class and debuff type
function Utils.GetKnownCleanseSpell(playerClass, debuffType)
    if not playerClass then
        local _, pCls = UnitClass("player")
        playerClass = pCls or "WARRIOR"
    end
    if not knownSpellsCache then
        Utils.ScanKnownSpells()
    end

    if playerClass == "PRIEST" then
        if debuffType == "Magic" or debuffType == "ALL" then
            if Utils.IsSpellKnown("Dispel Magic") then return "Dispel Magic" end
        end
        if debuffType == "Disease" or debuffType == "ALL" then
            if Utils.IsSpellKnown("Abolish Disease") then return "Abolish Disease" end
            if Utils.IsSpellKnown("Cure Disease") then return "Cure Disease" end
        end
    elseif playerClass == "PALADIN" then
        if Utils.IsSpellKnown("Cleanse") then
            return "Cleanse"
        end
        if debuffType == "Poison" or debuffType == "Disease" or debuffType == "ALL" then
            if Utils.IsSpellKnown("Purify") then return "Purify" end
        end
    elseif playerClass == "DRUID" then
        if debuffType == "Curse" or debuffType == "ALL" then
            if Utils.IsSpellKnown("Remove Curse") then return "Remove Curse" end
        end
        if debuffType == "Poison" or debuffType == "ALL" then
            if Utils.IsSpellKnown("Abolish Poison") then return "Abolish Poison" end
            if Utils.IsSpellKnown("Cure Poison") then return "Cure Poison" end
        end
    elseif playerClass == "MAGE" then
        if debuffType == "Curse" or debuffType == "ALL" then
            if Utils.IsSpellKnown("Remove Lesser Curse") then return "Remove Lesser Curse" end
        end
    elseif playerClass == "SHAMAN" then
        if debuffType == "Poison" or debuffType == "ALL" then
            if Utils.IsSpellKnown("Cure Poison") then return "Cure Poison" end
        end
        if debuffType == "Disease" or debuffType == "ALL" then
            if Utils.IsSpellKnown("Cure Disease") then return "Cure Disease" end
        end
        if debuffType == "Magic" then
            if Utils.IsSpellKnown("Purge") then return "Purge" end
        end
    end

    return nil
end

-- =========================================================================
-- CLICK-CASTING & UNCONSTRAINED 1.12.1 ACTION PRIMITIVES
-- =========================================================================

-- Programmatically target and cast a spell on a unit with previous target preservation
function Utils.CastOnUnit(unit, spellName)
    if not unit or not UnitExists(unit) or not spellName then return false end
    local hadTarget = UnitExists("target")
    local isTargetingSelf = UnitIsUnit("target", "player")

    TargetUnit(unit)
    CastSpellByName(spellName)

    if hadTarget and not isTargetingSelf then
        TargetLastTarget()
    elseif not hadTarget then
        ClearTarget()
    end
    return true
end

-- Scan player and party/raid members for cleansable debuffs and cast dispel with 1-click
function Utils.CleanseNextMember(cleanseSpell, targetDebuffType)
    local _, playerClass = UnitClass("player")
    targetDebuffType = targetDebuffType or "ALL"

    local CoreAuras = Primus.Auras
    if CoreAuras and CoreAuras.GetGroupCleansableDebuffs then
        local cleansables = CoreAuras:GetGroupCleansableDebuffs(playerClass)
        local cCount = table.getn(cleansables)
        for i = 1, cCount do
            local item = cleansables[i]
            if item and (targetDebuffType == "ALL" or item.dispelType == targetDebuffType) then
                local spellToCast = cleanseSpell or Utils.GetKnownCleanseSpell(playerClass, item.dispelType)
                if spellToCast and Utils.IsSpellKnown(spellToCast) then
                    Utils.CastOnUnit(item.unit, spellToCast)
                    return true, item.unit, item.dispelType, spellToCast
                end
            end
        end
        return false
    end

    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    local count = numRaid > 0 and numRaid or numParty
    local prefix = numRaid > 0 and "raid" or "party"

    -- Priority: Self -> Group Members
    local units = { "player" }
    for i = 1, count do
        table.insert(units, prefix .. i)
    end

    local uCount = table.getn(units)
    for i = 1, uCount do
        local unit = units[i]
        if UnitExists(unit) and not UnitIsDeadOrGhost(unit) and UnitIsConnected(unit) then
            for d = 1, 16 do
                local _, _, debuffType = UnitDebuff(unit, d)
                if debuffType and (targetDebuffType == "ALL" or debuffType == targetDebuffType) then
                    local spellToCast = cleanseSpell or Utils.GetKnownCleanseSpell(playerClass, debuffType)
                    if spellToCast and Utils.IsSpellKnown(spellToCast) then
                        Utils.CastOnUnit(unit, spellToCast)
                        return true, unit, debuffType, spellToCast
                    end
                end
            end
        end
    end
    return false
end

-- =========================================================================
-- TOOLTIP DURABILITY SCANNER (Vanilla 1.12.1)
-- =========================================================================

local scanTooltip = nil

local function GetScanTooltip()
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "Primus_Utils_ScanTooltip", UIParent, "GameTooltipTemplate")
        scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    return scanTooltip
end

function Utils.GetInventoryItemDurability(slotID)
    if not slotID then return nil, nil end
    local Tooltip = Primus.PUITooltip
    if Tooltip and Tooltip.Scanner and Tooltip.Scanner.GetInventoryDurability then
        return Tooltip.Scanner:GetInventoryDurability(slotID)
    end

    local tt = GetScanTooltip()
    tt:ClearLines()
    local hasItem = tt:SetInventoryItem("player", slotID)
    if not hasItem then return nil, nil end

    local durPattern = DURABILITY_TEMPLATE and string.gsub(DURABILITY_TEMPLATE, "%%d", "(%%d+)") or "Durability (%d+) / (%d+)"
    local numLines = tt:NumLines() or 0
    for j = 1, numLines do
        local line = _G["Primus_Utils_ScanTooltipTextLeft" .. j]
        if line then
            local text = line:GetText()
            if text then
                local _, _, cur, max = string.find(text, durPattern)
                if cur and max then
                    return tonumber(cur), tonumber(max)
                end
            end
        end
    end
    return nil, nil
end

function Utils.GetContainerItemDurability(bagID, slotID)
    if not bagID or not slotID then return nil, nil end
    local Tooltip = Primus.PUITooltip
    if Tooltip and Tooltip.Scanner and Tooltip.Scanner.GetBagDurability then
        return Tooltip.Scanner:GetBagDurability(bagID, slotID)
    end

    local tt = GetScanTooltip()
    tt:ClearLines()
    local hasItem = tt:SetBagItem(bagID, slotID)
    if not hasItem then return nil, nil end

    local durPattern = DURABILITY_TEMPLATE and string.gsub(DURABILITY_TEMPLATE, "%%d", "(%%d+)") or "Durability (%d+) / (%d+)"
    local numLines = tt:NumLines() or 0
    for j = 1, numLines do
        local line = _G["Primus_Utils_ScanTooltipTextLeft" .. j]
        if line then
            local text = line:GetText()
            if text then
                local _, _, cur, max = string.find(text, durPattern)
                if cur and max then
                    return tonumber(cur), tonumber(max)
                end
            end
        end
    end
    return nil, nil
end

-- =========================================================================
-- AURA DURATION & TIME FORMATTERS
-- =========================================================================

-- Format aura time remaining: hours ("1h"), minutes ("15m", "2m"), then seconds ("59s", "8s")
function Utils.FormatAuraDuration(seconds)
    if not seconds or seconds <= 0 then return "" end
    if seconds >= 3600 then
        return string.format("%dh", math.floor(seconds / 3600))
    elseif seconds >= 60 then
        return string.format("%dm", math.ceil(seconds / 60))
    else
        return string.format("%ds", math.floor(seconds))
    end
end

-- Dynamic color tier for aura duration (Yellow >= 1m, Orange < 1m, Red < 10s)
function Utils.GetAuraDurationColor(seconds)
    if not seconds or seconds <= 0 then
        return 1, 1, 1
    elseif seconds < 10 then
        return 1.0, 0.25, 0.25 -- Red (critical urgency)
    elseif seconds < 60 then
        return 1.0, 0.70, 0.10 -- Orange (under 1 minute)
    else
        return 1.0, 1.0, 0.40  -- Yellow (minutes remaining)
    end
end

-- =========================================================================
-- CENTRALIZED WEB URL PATTERNS & DIALOG MODAL
-- =========================================================================

Utils.URL_PATTERNS = {
    "https?://%S+",
    "www%.%S+",
    "discord%.gg/%S+",
    "discord%.com/%S+",
    "twitch%.tv/%S+",
    "youtube%.com/%S+",
    "youtu%.be/%S+",
    "imgur%.com/%S+",
    "carrd%.co/%S+",
    "toyhou%.se/%S+",
    "github%.com/%S+",
    "spotify%.com/%S+",
    "soundcloud%.com/%S+",
    "deviantart%.com/%S+",
    "artstation%.com/%S+"
}

function Utils.ExtractURLs(text)
    if not text or text == "" then return {} end
    local urls = {}
    local clean = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    clean = string.gsub(clean, "|r", "")
    clean = string.gsub(clean, "|H.-|h(.-)|h", "%1")

    for _, pat in ipairs(Utils.URL_PATTERNS) do
        for url in string.gfind(clean, pat) do
            url = string.gsub(url, "[%.,!%?)%]\"]+$", "")
            table.insert(urls, url)
        end
    end
    return urls
end

local urlCopyModal = nil

function Utils.ShowURLDialog(url, titleText)
    if not urlCopyModal then
        local f = CreateFrame("Frame", "Primus_URLCopyModal", UIParent)
        f:SetWidth(440)
        f:SetHeight(105)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(160)
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        f:SetBackdropColor(0.06, 0.08, 0.12, 0.98)
        f:SetBackdropBorderColor(0.20, 0.50, 0.90, 1.0)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function() this:StartMoving() end)
        f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
        table.insert(UISpecialFrames, "Primus_URLCopyModal")

        local title = f:CreateFontString(nil, "OVERLAY")
        local font = (Primus.Media and Primus.Media.Fetch and Primus.Media:Fetch("font", "Default")) or "Fonts\\FRIZQT__.TTF"
        title:SetFont(font, 10, "OUTLINE")
        title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
        title:SetText(Utils.ColorText("Web Link Copy", "69ccf0") .. " |cffaaaaaa(Press Ctrl+C to copy)|r")
        f.title = title

        local eb = CreateFrame("EditBox", "Primus_URLCopyModal_EditBox", f)
        eb:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -32)
        eb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 36)
        eb:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        eb:SetBackdropColor(0.03, 0.04, 0.06, 1.0)
        eb:SetBackdropBorderColor(0.25, 0.35, 0.50, 1.0)
        eb:SetFont(font, 11, "")
        eb:SetTextColor(1, 1, 0.4)
        eb:SetAutoFocus(true)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        f.editBox = eb

        local copyBtn = CreateFrame("Button", nil, f)
        copyBtn:SetWidth(95)
        copyBtn:SetHeight(20)
        copyBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8)
        copyBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        copyBtn:SetBackdropColor(0.12, 0.25, 0.15, 1.0)
        copyBtn:SetBackdropBorderColor(0.30, 0.80, 0.30, 1.0)
        local cTxt = copyBtn:CreateFontString(nil, "OVERLAY")
        cTxt:SetFont(font, 9, "OUTLINE")
        cTxt:SetPoint("CENTER", 0, 0)
        cTxt:SetText("Select All")
        copyBtn:SetScript("OnClick", function()
            eb:SetFocus()
            eb:HighlightText(0)
        end)

        local closeBtn = CreateFrame("Button", nil, f)
        closeBtn:SetWidth(70)
        closeBtn:SetHeight(20)
        closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 8)
        closeBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        closeBtn:SetBackdropColor(0.15, 0.15, 0.18, 1.0)
        closeBtn:SetBackdropBorderColor(0.35, 0.35, 0.40, 1.0)
        local clTxt = closeBtn:CreateFontString(nil, "OVERLAY")
        clTxt:SetFont(font, 9, "OUTLINE")
        clTxt:SetPoint("CENTER", 0, 0)
        clTxt:SetText("Done")
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        urlCopyModal = f
    end

    if titleText and titleText ~= "" then
        urlCopyModal.title:SetText(Utils.ColorText(titleText, "69ccf0") .. " |cffaaaaaa(Press Ctrl+C to copy)|r")
    else
        urlCopyModal.title:SetText(Utils.ColorText("Web Link Copy", "69ccf0") .. " |cffaaaaaa(Press Ctrl+C to copy)|r")
    end

    urlCopyModal.editBox:SetText(url or "")
    urlCopyModal:Show()
    urlCopyModal:Raise()
    urlCopyModal.editBox:SetFocus()
    urlCopyModal.editBox:HighlightText(0)
end
