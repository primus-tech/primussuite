--[[
    PrimusUI: PUIRoleplay Legacy Addon Importer & Converter (PUIImporter.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (Lua 5.0.2)
    
    Provides:
    - Auto-detection & extraction from TurtleRP, MyRolePlay (MRP), TotalRP (TRP/TRP2/TRP3), FlagRSP, and xtensionxtooltip.
    - Intelligent data normalization to Primus 7-tab canonical RP schema.
    - Interactive Importer UI modal with source picker, destination slot selector, and live diff preview.
    - Universal text/code export and import for Discord sharing, forum profiles, and cross-account backup.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIRoleplay = Primus.PUIRoleplay or {}
Primus.PUIRoleplay = PUIRoleplay

local Importer = {}
PUIRoleplay.Importer = Importer

local importFrame = nil
local codeModal = nil
local detectedSources = {}
local selectedSourceIdx = 1
local selectedDestSlot = "0"

--------------------------------------------------------------------------------
-- Helper: Safe String Sanitization
--------------------------------------------------------------------------------
local function CleanStr(val)
    if not val then return "" end
    local s = tostring(val)
    if s == "nil" or s == "NO_KEY" then return "" end
    return PUIRoleplay.UnescapeRPText and PUIRoleplay:UnescapeRPText(s) or s
end

local function MapScale(val, oldMin, oldMax, newMin, newMax)
    local n = tonumber(val) or oldMin
    if n < oldMin then n = oldMin end
    if n > oldMax then n = oldMax end
    local ratio = (n - oldMin) / ((oldMax - oldMin) > 0 and (oldMax - oldMin) or 1)
    return math.floor(newMin + ratio * (newMax - newMin) + 0.5)
end

--------------------------------------------------------------------------------
-- 1. Scan for Legacy Addons & Global SavedVariables
--------------------------------------------------------------------------------
function Importer:ScanAvailableSources()
    detectedSources = {}

    -- Source 1: TurtleRP (TTRP)
    if _G.TurtleRPCharacterInfo and type(_G.TurtleRPCharacterInfo) == "table" then
        local count = 0
        if _G.TurtleRPPlayerProfiles and type(_G.TurtleRPPlayerProfiles) == "table" then
            for k in pairs(_G.TurtleRPPlayerProfiles) do count = count + 1 end
        end
        table.insert(detectedSources, {
            id = "ttrp_active",
            name = "TurtleRP (Active Session)",
            desc = "Active character profile from TurtleRP memory",
            count = count > 0 and count or 1,
            fetch = function() return _G.TurtleRPCharacterInfo end
        })
    end

    if _G.TurtleRP_Profiles and type(_G.TurtleRP_Profiles) == "table" then
        local count = 0
        for k in pairs(_G.TurtleRP_Profiles) do count = count + 1 end
        table.insert(detectedSources, {
            id = "ttrp_saved",
            name = "TurtleRP (Saved Database)",
            desc = "Saved profiles from TurtleRP_Profiles database",
            count = count,
            fetch = function()
                local pName = UnitName("player")
                return _G.TurtleRP_Profiles[pName] or _G.TurtleRP_Profiles
            end
        })
    end

    -- Source 2: MyRolePlay (MRP)
    if _G.mrpSaved or _G.mrpProfiles or _G.mrpCharacterInfo or _G.mrp_DisplayNames or _G.msp then
        table.insert(detectedSources, {
            id = "mrp",
            name = "MyRolePlay (MRP / MSP)",
            desc = "MyRolePlay character profile and Mary Sue Protocol data",
            count = 1,
            fetch = function()
                local pName = UnitName("player")
                local data = {}
                if _G.mrpCharacterInfo then data = _G.mrpCharacterInfo end
                if _G.mrpSaved and _G.mrpSaved[pName] then data = _G.mrpSaved[pName] end
                if _G.mrp_DisplayNames and _G.mrp_DisplayNames[pName] then data.full_name = _G.mrp_DisplayNames[pName] end
                if _G.mrp_Biographies and _G.mrp_Biographies[pName] then data.description = _G.mrp_Biographies[pName] end
                return data
            end
        })
    end

    -- Source 3: TotalRP / TotalRP2 / TotalRP3 (TRP)
    if _G.TRP_Module_Player_Characteristics or _G.TRP2_Module_Player or _G.TRP3_Profiles or _G.TRP3_Configuration then
        table.insert(detectedSources, {
            id = "trp",
            name = "TotalRP / TRP2 / TRP3",
            desc = "TotalRP character characteristics, about, and glance traits",
            count = 1,
            fetch = function()
                local data = {}
                if _G.TRP_Module_Player_Characteristics then
                    for k, v in pairs(_G.TRP_Module_Player_Characteristics) do data[k] = v end
                end
                if _G.TRP_Module_Player_About then
                    for k, v in pairs(_G.TRP_Module_Player_About) do data[k] = v end
                end
                if _G.TRP_Module_Player_Misc then
                    for k, v in pairs(_G.TRP_Module_Player_Misc) do data[k] = v end
                end
                if _G.TRP2_Module_Player then
                    for k, v in pairs(_G.TRP2_Module_Player) do data[k] = v end
                end
                return data
            end
        })
    end

    -- Source 4: FlagRSP / FlagRSP2
    if _G.flagRSP_Profiles or _G.flagRSP_Character then
        table.insert(detectedSources, {
            id = "flagrsp",
            name = "FlagRSP / FlagRSP2",
            desc = "Legacy FlagRSP character name, title, and description",
            count = 1,
            fetch = function()
                local pName = UnitName("player")
                return (_G.flagRSP_Profiles and _G.flagRSP_Profiles[pName]) or _G.flagRSP_Character or {}
            end
        })
    end

    -- Source 5: xtensionxtooltip (xtt)
    if _G.xtensionxtooltip_Profiles or _G.xtt_saved then
        table.insert(detectedSources, {
            id = "xtt",
            name = "xtensionxtooltip",
            desc = "xtensionxtooltip target tooltip roleplay data",
            count = 1,
            fetch = function()
                local pName = UnitName("player")
                return (_G.xtensionxtooltip_Profiles and _G.xtensionxtooltip_Profiles[pName]) or _G.xtt_saved or {}
            end
        })
    end

    return detectedSources
end

--------------------------------------------------------------------------------
-- 2. Convert & Normalize Inbound Data to Primus Schema
--------------------------------------------------------------------------------
function Importer:ConvertToPrimusProfile(raw)
    if not raw or type(raw) ~= "table" then return nil end

    local prof = {}
    local def = PUIRoleplay.DefaultProfile or {}
    for k, v in pairs(def) do
        if type(v) == "table" then
            prof[k] = {}
            for subK, subV in pairs(v) do prof[k][subK] = subV end
        else
            prof[k] = v
        end
    end

    -- 1. Nomenclature & Titles
    prof.first_name   = CleanStr(raw.first_name or raw.FirstName or raw.FN or raw.prenom or "")
    prof.middle_name  = CleanStr(raw.middle_name or raw.MiddleName or raw.MN or "")
    prof.last_name    = CleanStr(raw.last_name or raw.LastName or raw.LN or raw.nom or raw.Surname or "")
    prof.prefix       = CleanStr(raw.prefix or raw.Prefix or raw.PF or raw.titre_prefix or raw.VA or "")
    prof.title        = CleanStr(raw.title or raw.Title or raw.TIT or raw.TT or raw.titre or "")
    prof.epithet      = CleanStr(raw.epithet or raw.suffix or raw.Suffix or raw.SF or "")
    prof.suffix       = prof.epithet
    prof.nickname     = CleanStr(raw.nickname or raw.Nickname or raw.NN or raw.NI or raw.alias or "")
    prof.house_name   = CleanStr(raw.house_name or raw.house or raw.House or raw.HN or raw.maison or raw.clan or raw.tribe or raw.bloodline or "")
    prof.bloodline    = prof.house_name
    prof.tribe        = prof.house_name
    prof.clan         = prof.house_name

    -- Fallback name breakdown if only full_name / DisplayName is present
    if prof.first_name == "" and prof.last_name == "" then
        local full = CleanStr(raw.full_name or raw.DisplayName or raw.NA or raw.nomComplet or "")
        if full ~= "" then
            local _, _, fn, ln = string.find(full, "^(%S+)%s*(.*)$")
            prof.first_name = fn or full
            prof.last_name  = ln or ""
        end
    end
    prof.full_name = PUIRoleplay:ComposeFullName(prof)

    -- 2. Demographics & Pronouns
    prof.apparent_age     = CleanStr(raw.apparent_age or raw.age or raw.Age or raw.AG or "")
    prof.biological_sex   = CleanStr(raw.biological_sex or raw.sex or raw.Sex or raw.sexe or "Male")
    prof.gender_identity  = CleanStr(raw.gender_identity or raw.gender or raw.Gender or prof.biological_sex)
    prof.ic_pronouns      = CleanStr(raw.ic_pronouns or raw.icPronouns or raw.pronouns or (prof.biological_sex == "Female" and "She/Her" or "He/Him"))
    prof.ooc_pronouns     = CleanStr(raw.ooc_pronouns or raw.oocPronouns or prof.ic_pronouns)
    prof.orientation      = CleanStr(raw.orientation or raw.Orientation or "Heterosexual / Straight")
    if raw.lgbtqia_friendly ~= nil then
        prof.lgbtqia_friendly = (raw.lgbtqia_friendly == true or raw.lgbtqia_friendly == "1" or raw.lgbtqia_friendly == 1)
    end
    if raw.show_orientation ~= nil then
        prof.show_orientation = (raw.show_orientation ~= false and raw.show_orientation ~= "0" and raw.show_orientation ~= 0)
    end

    -- 3. Physical Appearance
    prof.eye_color        = CleanStr(raw.eye_color or raw.EyeColor or raw.eyes or raw.yeux or raw.AE or "")
    prof.height           = CleanStr(raw.height or raw.Height or raw.taille or raw.AH or "")
    prof.weight           = CleanStr(raw.weight or raw.Weight or raw.poids or raw.AW or "")
    prof.body_build       = CleanStr(raw.body_build or raw.build or raw.silhouette or raw.BO or "")
    prof.current_emotion  = CleanStr(raw.current_emotion or raw.emotion or raw.humeur or raw.CO or "Calm")
    prof.appearance_desc  = CleanStr(raw.appearance_desc or raw.description or raw.Description or raw.DE or raw.physique or "")

    -- 4. At-A-Glance Traits (5 Slots)
    for i = 1, 5 do
        local g = (raw.glances and raw.glances[i]) or {}
        local gTitle = CleanStr(g.title or raw["atAGlance" .. i .. "Title"] or raw["glance" .. i .. "Title"] or raw["AC" .. i .. "_titre"] or "")
        local gText  = CleanStr(g.text or g.desc or raw["atAGlance" .. i] or raw["glance" .. i] or raw["AC" .. i .. "_texte"] or "")
        local gIcon  = CleanStr(g.icon or raw["atAGlance" .. i .. "Icon"] or raw["glance" .. i .. "Icon"] or raw["AC" .. i .. "_icone"] or "")
        local gActive = (g.active == true or gTitle ~= "" or gText ~= "")

        if not prof.glances then prof.glances = {} end
        prof.glances[i] = {
            active = gActive,
            title = gTitle,
            text = gText,
            icon = (gIcon ~= "") and gIcon or ((def.glances and def.glances[i] and def.glances[i].icon) or "INV_Misc_QuestionMark")
        }
    end

    -- 5. Lore & Origins
    prof.birth_city   = CleanStr(raw.birth_city or raw.BirthCity or raw.ville_naissance or raw.HB or "")
    prof.home_city    = CleanStr(raw.home_city or raw.HomeCity or raw.ville_residence or raw.HO or "")
    prof.motto        = CleanStr(raw.motto or raw.Motto or raw.devise or raw.MO or "")
    prof.faction_clan = CleanStr(raw.faction_clan or raw.Faction or raw.faction or raw["all\195\169geance"] or raw["allegeance"] or "")

    if not prof.history then prof.history = {} end
    for ch = 1, 6 do
        local h = (raw.history and raw.history["chapter" .. ch]) or raw["history" .. ch] or raw["chapter" .. ch] or raw["CH" .. ch] or ""
        prof.history["chapter" .. ch] = CleanStr(h)
    end
    if prof.history.chapter1 == "" and raw.History and raw.History ~= "" then
        prof.history.chapter1 = CleanStr(raw.History)
    end

    -- 6. Roleplay Preferences & Boundaries
    prof.experience_level   = CleanStr(raw.experience_level or raw.experience or "Experienced")
    prof.walkup_policy      = CleanStr(raw.walkup_policy or raw.walkups or "Walkups Welcome")
    prof.combat_preference  = CleanStr(raw.combat_preference or raw.combat or "D20 Rolls (DiceMaster)")
    prof.injury_consent     = CleanStr(raw.injury_consent or raw.injury or "Realistic / Negotiated")
    prof.permadeath_consent = CleanStr(raw.permadeath_consent or raw.death or "Negotiated Only")
    prof.relationship_status= CleanStr(raw.relationship_status or raw.relationship or "Single & Looking")
    prof.erp_preference     = CleanStr(raw.erp_preference or "No Adult Content (Clean RP)")
    prof.ooc_boundaries     = CleanStr(raw.ooc_boundaries or raw.boundaries or "")
    prof.ooc_notes          = CleanStr(raw.ooc_notes or raw.ooc_info or raw.OOC or "")

    if raw.adult_18plus_flag ~= nil then
        prof.adult_18plus_flag = (raw.adult_18plus_flag == true or raw.adult_18plus_flag == "1" or raw.adult_18plus_flag == 1)
    end

    -- 7. Personality Traits (TRP 0-20 scale mapping)
    if raw.personality_traits and type(raw.personality_traits) == "table" then
        prof.personality_traits = raw.personality_traits
    elseif raw.traits and type(raw.traits) == "table" then
        local tList = {}
        for _, t in ipairs(raw.traits) do
            table.insert(tList, {
                id = t.id or "custom",
                leftName = t.leftName or t.left or "Left",
                rightName = t.rightName or t.right or "Right",
                leftIcon = t.leftIcon or "INV_Misc_QuestionMark",
                rightIcon = t.rightIcon or "INV_Misc_QuestionMark",
                value = MapScale(t.value or 10, 0, 20, 0, 20),
                isCustom = t.isCustom or false
            })
        end
        prof.personality_traits = tList
    else
        prof.personality_traits = PUIRoleplay:GetPersonalityTraits(prof)
    end

    -- Generate Fresh Synchronization Keys
    prof.keyM = PUIRoleplay:GenerateKey()
    prof.keyT = PUIRoleplay:GenerateKey()
    prof.keyD = PUIRoleplay:GenerateKey()
    prof.keyL = PUIRoleplay:GenerateKey()
    prof.keyX = PUIRoleplay:GenerateKey()
    prof.keyP = PUIRoleplay:GenerateKey()

    return prof
end

--------------------------------------------------------------------------------
-- 3. String Serialization Engine (Profile Export / Import)
--------------------------------------------------------------------------------
function Importer:ExportToString(profile)
    local p = profile or PUIRoleplay:GetMyProfile()
    local tokens = {
        "PUIv1",
        p.first_name or "",
        p.middle_name or "",
        p.last_name or "",
        p.prefix or "",
        p.title or "",
        p.epithet or "",
        p.nickname or "",
        p.house_name or "",
        p.apparent_age or "",
        p.biological_sex or "Male",
        p.gender_identity or "Cisgender Male",
        p.ic_pronouns or "He/Him",
        p.ooc_pronouns or "He/Him",
        (p.lgbtqia_friendly ~= false) and "1" or "0",
        p.orientation or "",
        (p.show_orientation ~= false) and "1" or "0",
        p.eye_color or "",
        p.height or "",
        p.weight or "",
        p.body_build or "",
        p.current_emotion or "Calm",
        p.birth_city or "",
        p.home_city or "",
        p.motto or "",
        p.faction_clan or "",
        p.experience_level or "",
        p.walkup_policy or "",
        p.combat_preference or "",
        p.injury_consent or "",
        p.permadeath_consent or "",
        p.relationship_status or "",
        (p.adult_18plus_flag == true) and "1" or "0",
        p.erp_preference or "",
        p.ooc_notes or "",
        p.appearance_desc or ""
    }

    local serialized = table.concat(tokens, "^")
    return serialized
end

function Importer:ImportFromString(codeStr)
    if not codeStr or codeStr == "" then return nil, "Empty string" end
    local delim = "^"
    if string.find(codeStr, "§") then delim = "§" end
    local parts = PUIRoleplay.Protocols and PUIRoleplay.Protocols:SplitString(codeStr, delim, {}) or {}
    if table.getn(parts) < 10 or parts[1] ~= "PUIv1" then
        return nil, "Invalid or unrecognized Primus RP profile code format"
    end

    local p = PUIRoleplay.DefaultProfile or {}
    local prof = {}
    for k, v in pairs(p) do prof[k] = v end

    prof.first_name         = parts[2] or ""
    prof.middle_name        = parts[3] or ""
    prof.last_name          = parts[4] or ""
    prof.prefix             = parts[5] or ""
    prof.title              = parts[6] or ""
    prof.epithet            = parts[7] or ""
    prof.suffix             = prof.epithet
    prof.nickname           = parts[8] or ""
    prof.house_name         = parts[9] or ""
    prof.bloodline          = prof.house_name
    prof.tribe              = prof.house_name
    prof.clan               = prof.house_name
    prof.apparent_age       = parts[10] or ""
    prof.biological_sex     = parts[11] or "Male"
    prof.gender_identity    = parts[12] or "Cisgender Male"
    prof.ic_pronouns        = parts[13] or "He/Him"
    prof.ooc_pronouns       = parts[14] or "He/Him"
    prof.lgbtqia_friendly   = (parts[15] == "1")
    prof.orientation        = parts[16] or ""
    prof.show_orientation   = (parts[17] == "1")
    prof.eye_color          = parts[18] or ""
    prof.height             = parts[19] or ""
    prof.weight             = parts[20] or ""
    prof.body_build         = parts[21] or ""
    prof.current_emotion    = parts[22] or "Calm"
    prof.birth_city         = parts[23] or ""
    prof.home_city          = parts[24] or ""
    prof.motto              = parts[25] or ""
    prof.faction_clan       = parts[26] or ""
    prof.experience_level   = parts[27] or ""
    prof.walkup_policy      = parts[28] or ""
    prof.combat_preference  = parts[29] or ""
    prof.injury_consent     = parts[30] or ""
    prof.permadeath_consent = parts[31] or ""
    prof.relationship_status= parts[32] or ""
    prof.adult_18plus_flag  = (parts[33] == "1")
    prof.erp_preference     = parts[34] or ""
    prof.ooc_notes          = parts[35] or ""
    prof.appearance_desc    = parts[36] or ""
    prof.full_name          = PUIRoleplay:ComposeFullName(prof)

    prof.keyM = PUIRoleplay:GenerateKey()
    prof.keyT = PUIRoleplay:GenerateKey()
    prof.keyD = PUIRoleplay:GenerateKey()
    prof.keyL = PUIRoleplay:GenerateKey()
    prof.keyX = PUIRoleplay:GenerateKey()
    prof.keyP = PUIRoleplay:GenerateKey()

    return prof
end

--------------------------------------------------------------------------------
-- 4. Interactive Importer UI Window
--------------------------------------------------------------------------------
function Importer:BuildFrame()
    if importFrame then return importFrame end

    local f = CreateFrame("Frame", "Primus_PUIRP_ImporterModal", UIParent)
    f:SetWidth(480)
    f:SetHeight(420)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    f:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
    f:SetBackdropBorderColor(0.0, 0.70, 0.95, 1.0)
    table.insert(UISpecialFrames, "Primus_PUIRP_ImporterModal")

    -- Title Bar
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    titleBar:SetHeight(28)
    titleBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    titleBar:SetBackdropColor(0.10, 0.12, 0.16, 1.0)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleText:SetText("|cff00ccffPRIMUS|r |cffffffffRP PROFILE IMPORTER & CONVERTER|r")

    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetWidth(18)
    closeBtn:SetHeight(18)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Source Header
    local srcHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    srcHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -36)
    srcHeader:SetText("|cff00e5ff1. Select Detected Legacy Addon / Database Source:|r")

    -- Source Buttons Container
    f.srcBtns = {}
    for i = 1, 4 do
        local b = CreateFrame("Button", nil, f)
        b:SetWidth(452)
        b:SetHeight(26)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -54 - (i - 1) * 30)
        b:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        b:SetBackdropColor(0.08, 0.09, 0.12, 0.95)
        b:SetBackdropBorderColor(0.22, 0.25, 0.32, 1.0)

        local bTxt = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bTxt:SetPoint("LEFT", b, "LEFT", 8, 0)
        b.text = bTxt
        b.srcIdx = i

        b:SetScript("OnClick", function()
            selectedSourceIdx = this.srcIdx
            Importer:RefreshModal()
        end)
        f.srcBtns[i] = b
    end

    -- Destination Slot Selector
    local destHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    destHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -180)
    destHeader:SetText("|cff00e5ff2. Target Destination Primus Profile Slot:|r")

    f.destBtns = {}
    for s = 0, 3 do
        local slotStr = tostring(s)
        local sb = CreateFrame("Button", nil, f)
        sb:SetWidth(108)
        sb:SetHeight(22)
        sb:SetPoint("TOPLEFT", destHeader, "BOTTOMLEFT", s * 115, -4)
        sb:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        local sTxt = sb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sTxt:SetPoint("CENTER", sb, "CENTER", 0, 0)
        sTxt:SetText("Profile " .. s)
        sb.text = sTxt
        sb.slot = slotStr
        sb:SetScript("OnClick", function()
            selectedDestSlot = this.slot
            Importer:RefreshModal()
        end)
        f.destBtns[s] = sb
    end

    -- Preview Summary Box
    local prevHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    prevHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -234)
    prevHeader:SetText("|cffffd1003. Converted Profile Data Preview:|r")

    local prevBox = CreateFrame("Frame", nil, f)
    prevBox:SetPoint("TOPLEFT", prevHeader, "BOTTOMLEFT", 0, -4)
    prevBox:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 46)
    prevBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    prevBox:SetBackdropColor(0.04, 0.04, 0.06, 0.95)
    prevBox:SetBackdropBorderColor(0.20, 0.22, 0.26, 1.0)

    local prevText = prevBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    prevText:SetPoint("TOPLEFT", prevBox, "TOPLEFT", 8, -8)
    prevText:SetPoint("BOTTOMRIGHT", prevBox, "BOTTOMRIGHT", -8, 8)
    prevText:SetJustifyH("LEFT")
    prevText:SetJustifyV("TOP")
    f.prevText = prevText

    -- Bottom Actions: [Import & Save to Slot], [Text Code Modal], [Cancel]
    local importBtn = CreateFrame("Button", nil, f)
    importBtn:SetWidth(150)
    importBtn:SetHeight(24)
    importBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
    importBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    importBtn:SetBackdropColor(0.08, 0.40, 0.15, 0.95)
    importBtn:SetBackdropBorderColor(0.20, 0.85, 0.35, 1.0)
    local iTxt = importBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    iTxt:SetPoint("CENTER", importBtn, "CENTER", 0, 0)
    iTxt:SetText("|cff55ff88Import Profile|r")
    importBtn:SetScript("OnClick", function()
        Importer:ExecuteImport()
    end)
    f.importBtn = importBtn

    local stringBtn = CreateFrame("Button", nil, f)
    stringBtn:SetWidth(150)
    stringBtn:SetHeight(24)
    stringBtn:SetPoint("LEFT", importBtn, "RIGHT", 10, 0)
    stringBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    stringBtn:SetBackdropColor(0.12, 0.16, 0.24, 0.95)
    stringBtn:SetBackdropBorderColor(0.0, 0.75, 1.0, 1.0)
    local sTxt = stringBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sTxt:SetPoint("CENTER", stringBtn, "CENTER", 0, 0)
    sTxt:SetText("|cff00ccffCopy / Paste Code|r")
    stringBtn:SetScript("OnClick", function()
        f:Hide()
        Importer:OpenStringModal()
    end)

    local cancelBtn = CreateFrame("Button", nil, f)
    cancelBtn:SetWidth(80)
    cancelBtn:SetHeight(24)
    cancelBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
    cancelBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    cancelBtn:SetBackdropColor(0.20, 0.10, 0.10, 0.95)
    cancelBtn:SetBackdropBorderColor(0.60, 0.20, 0.20, 1.0)
    local cTxt = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cTxt:SetPoint("CENTER", cancelBtn, "CENTER", 0, 0)
    cTxt:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    importFrame = f
    return f
end

function Importer:RefreshModal()
    local f = self:BuildFrame()
    local sources = self:ScanAvailableSources()

    for i = 1, 4 do
        local b = f.srcBtns[i]
        local src = sources[i]
        if src then
            b:Show()
            b.text:SetText(string.format("|cffffffff%s|r - |cffaaaaaa%s|r", src.name, src.desc))
            if i == selectedSourceIdx then
                b:SetBackdropColor(0.10, 0.35, 0.55, 0.95)
                b:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
            else
                b:SetBackdropColor(0.08, 0.09, 0.12, 0.95)
                b:SetBackdropBorderColor(0.22, 0.25, 0.32, 1.0)
            end
        else
            b:Hide()
        end
    end

    for s = 0, 3 do
        local sb = f.destBtns[s]
        if tostring(s) == selectedDestSlot then
            sb:SetBackdropColor(0.0, 0.45, 0.75, 1.0)
            sb:SetBackdropBorderColor(0.0, 0.90, 1.0, 1.0)
            sb.text:SetTextColor(1, 1, 1)
        else
            sb:SetBackdropColor(0.06, 0.07, 0.09, 0.95)
            sb:SetBackdropBorderColor(0.20, 0.22, 0.28, 1.0)
            sb.text:SetTextColor(0.7, 0.7, 0.75)
        end
    end

    local src = sources[selectedSourceIdx]
    if src then
        local raw = src.fetch and src.fetch() or {}
        local converted = self:ConvertToPrimusProfile(raw)
        if converted then
            local summary = string.format(
                "|cff55ff88Character Name:|r %s\n|cff00ccffTitle / Prefix:|r %s\n|cff00ccffHouse / Bloodline:|r %s\n|cffffd100Demographics:|r Age: %s | Sex: %s | Pronouns: %s\n|cffff80ccGlances Detected:|r %d active glance slots\n|cffaaaaaaDescription Length:|r %d characters",
                converted.full_name or "Unknown",
                PUIRoleplay:ComposeTitle(converted) or "None",
                converted.house_name ~= "" and converted.house_name or "None",
                converted.apparent_age ~= "" and converted.apparent_age or "Not Specified",
                converted.biological_sex or "Male",
                converted.ic_pronouns or "He/Him",
                (converted.glances and table.getn(converted.glances)) or 0,
                string.len(converted.appearance_desc or "")
            )
            f.prevText:SetText(summary)
            f.importBtn:Enable()
        else
            f.prevText:SetText("|cffff4444No valid profile records found in selected database source.|r")
            f.importBtn:Disable()
        end
    else
        f.prevText:SetText("|cffaaaaaaNo legacy RP addon databases detected in current WoW session.\n\nTip: You can use |cff00ccff[Copy / Paste Code]|r to import from text.|r")
        f.importBtn:Disable()
    end
end

function Importer:ExecuteImport()
    local sources = self:ScanAvailableSources()
    local src = sources[selectedSourceIdx]
    if not src then return end

    local raw = src.fetch and src.fetch() or {}
    local converted = self:ConvertToPrimusProfile(raw)
    if not converted then return end

    local cData = PUIRoleplay:GetCharData()
    if not cData.profiles then cData.profiles = {} end
    cData.profiles[selectedDestSlot] = converted
    cData.selected_profile = selectedDestSlot

    PUIRoleplay:SyncGlobalBridges()
    if PUIRoleplay.Sheet and Primus_PUIRoleplay_Sheet and Primus_PUIRoleplay_Sheet:IsVisible() then
        PUIRoleplay.Sheet:Refresh()
    end

    if importFrame then importFrame:Hide() end
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ccffPrimus RP:|r Successfully imported profile from |cffffd100%s|r into |cff55ff88Profile Slot %s|r!", src.name, selectedDestSlot))
end

--------------------------------------------------------------------------------
-- 5. Text / Code String Importer Modal
--------------------------------------------------------------------------------
function Importer:OpenStringModal()
    if not codeModal then
        local f = CreateFrame("Frame", "Primus_PUIRP_StringModal", UIParent)
        f:SetWidth(460)
        f:SetHeight(280)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function() this:StartMoving() end)
        f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        f:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
        f:SetBackdropBorderColor(0.0, 0.70, 0.95, 1.0)
        table.insert(UISpecialFrames, "Primus_PUIRP_StringModal")

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
        title:SetText("|cff00ccffPrimus RP|r |cffffffffProfile String Code|r")

        local scrollBg = CreateFrame("Frame", nil, f)
        scrollBg:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -34)
        scrollBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 44)
        scrollBg:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        scrollBg:SetBackdropColor(0.03, 0.03, 0.05, 1.0)
        scrollBg:SetBackdropBorderColor(0.20, 0.22, 0.28, 1.0)

        local scroll = CreateFrame("ScrollFrame", "Primus_PUIRP_StringScroll", scrollBg, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", scrollBg, "TOPLEFT", 4, -4)
        scroll:SetPoint("BOTTOMRIGHT", scrollBg, "BOTTOMRIGHT", -22, 4)

        local eb = CreateFrame("EditBox", nil, scroll)
        eb:SetWidth(400)
        eb:SetHeight(400)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject(GameFontHighlightSmall)
        eb:SetTextColor(1, 1, 0.6)
        scroll:SetScrollChild(eb)
        f.eb = eb

        local applyBtn = CreateFrame("Button", nil, f)
        applyBtn:SetWidth(120)
        applyBtn:SetHeight(22)
        applyBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
        applyBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        applyBtn:SetBackdropColor(0.08, 0.40, 0.15, 0.95)
        applyBtn:SetBackdropBorderColor(0.20, 0.85, 0.35, 1.0)
        local aTxt = applyBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        aTxt:SetPoint("CENTER", applyBtn, "CENTER", 0, 0)
        aTxt:SetText("Apply Code")
        applyBtn:SetScript("OnClick", function()
            local code = eb:GetText()
            local prof, err = Importer:ImportFromString(code)
            if prof then
                local slot = PUIRoleplay:GetActiveProfileSlot()
                local cData = PUIRoleplay:GetCharData()
                if not cData.profiles then cData.profiles = {} end
                cData.profiles[slot] = prof
                PUIRoleplay:SyncGlobalBridges()
                if PUIRoleplay.Sheet and Primus_PUIRoleplay_Sheet and Primus_PUIRoleplay_Sheet:IsVisible() then
                    PUIRoleplay.Sheet:Refresh()
                end
                f:Hide()
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffPrimus RP:|r Successfully imported profile string into active profile slot!")
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cffff4444Primus RP Import Error:|r " .. tostring(err or "Failed to parse code"))
            end
        end)

        local exportBtn = CreateFrame("Button", nil, f)
        exportBtn:SetWidth(120)
        exportBtn:SetHeight(22)
        exportBtn:SetPoint("LEFT", applyBtn, "RIGHT", 10, 0)
        exportBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        exportBtn:SetBackdropColor(0.10, 0.20, 0.35, 0.95)
        exportBtn:SetBackdropBorderColor(0.0, 0.70, 1.0, 1.0)
        local eTxt = exportBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        eTxt:SetPoint("CENTER", exportBtn, "CENTER", 0, 0)
        eTxt:SetText("Generate Code")
        exportBtn:SetScript("OnClick", function()
            local code = Importer:ExportToString()
            eb:SetText(code)
            eb:HighlightText(0, string.len(code))
            eb:SetFocus()
        end)

        local closeBtn = CreateFrame("Button", nil, f)
        closeBtn:SetWidth(70)
        closeBtn:SetHeight(22)
        closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
        closeBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        closeBtn:SetBackdropColor(0.20, 0.10, 0.10, 0.95)
        closeBtn:SetBackdropBorderColor(0.60, 0.20, 0.20, 1.0)
        local clTxt = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        clTxt:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
        clTxt:SetText("Close")
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        codeModal = f
    end

    codeModal:Show()
    codeModal.eb:SetText(Importer:ExportToString())
    codeModal.eb:HighlightText(0)
    codeModal.eb:SetFocus()
end

function Importer:Open()
    local f = self:BuildFrame()
    f:Show()
    self:RefreshModal()
end

-- Slash Commands
SLASH_PUIIMPORT1 = "/puiimport"
SLASH_PUIIMPORT2 = "/rpimport"
SLASH_PUIIMPORT3 = "/puiconvert"
SLASH_PUIIMPORT4 = "/rpconvert"
SlashCmdList["PUIIMPORT"] = function(msg)
    Importer:Open()
end
