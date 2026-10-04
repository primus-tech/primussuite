--[[
    PrimusUI: PUIRoleplay Constants & Data Model
    Target: Vanilla WoW 1.12.1 / Turtle WoW (100% Multi-Addon Wire Compatibility)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIRoleplay = Primus.PUIRoleplay or {}
Primus.PUIRoleplay = PUIRoleplay

--------------------------------------------------------------------------------
-- Multi-Channel Communication Definitions
--------------------------------------------------------------------------------
PUIRoleplay.Channels = {
    PRIMARY     = "OWPRP",               -- OctoWoW Roleplay Primary Channel (High Bandwidth)
    TURTLERP    = "TTRP",                -- TurtleRP Broadcast Channel
    FLAGRSP     = "xtensionxtooltip2",   -- FlagRSP / TotalRP Legacy Bridge
    MRP         = "MyRolePlay",          -- MyRolePlay Standard Channel
}

PUIRoleplay.ChannelList = {
    "OWPRP",
    "TTRP",
    "xtensionxtooltip2",
    "MyRolePlay",
}

--------------------------------------------------------------------------------
-- Helper: Compose Full Character Name & Full Character Title
--------------------------------------------------------------------------------
function PUIRoleplay:ComposeFullName(p)
    if not p then return "" end
    local nameComposite = ""
    if p.first_name and p.first_name ~= "" then
        nameComposite = p.first_name
        if p.middle_name and p.middle_name ~= "" then
            nameComposite = nameComposite .. " " .. p.middle_name
        end
        if p.last_name and p.last_name ~= "" then
            nameComposite = nameComposite .. " " .. p.last_name
        end
    elseif p.full_name and p.full_name ~= "" then
        nameComposite = p.full_name
    elseif p.name and p.name ~= "" then
        nameComposite = p.name
    else
        nameComposite = ""
    end
    return nameComposite
end

function PUIRoleplay:ComposeTitle(charData)
    if not charData then return "" end
    local pfx = charData.prefix or ""
    local ttl = charData.title or ""
    local ep = charData.epithet or charData.suffix or ""
    local house = charData.house_name or charData.house or charData.tribe or charData.clan or charData.bloodline or ""

    local parts = {}
    local rankTitle = ""
    if pfx ~= "" then
        rankTitle = pfx
    end
    if ttl ~= "" then
        if rankTitle ~= "" then
            rankTitle = rankTitle .. " " .. ttl
        else
            rankTitle = ttl
        end
    end

    if rankTitle ~= "" then
        table.insert(parts, rankTitle)
    end

    if ep ~= "" and ep ~= ttl then
        table.insert(parts, ep)
    end

    if house ~= "" then
        if table.getn(parts) > 0 then
            local lHouse = string.lower(house)
            if string.find(lHouse, "^house") or string.find(lHouse, "^clan") or string.find(lHouse, "^tribe") or string.find(lHouse, "^the ") then
                table.insert(parts, house)
            else
                table.insert(parts, "of " .. house)
            end
        else
            table.insert(parts, house)
        end
    end

    if table.getn(parts) == 0 then return "" end
    return table.concat(parts, ", ")
end

--------------------------------------------------------------------------------
-- Dropdown Options & Dictionaries
--------------------------------------------------------------------------------
PUIRoleplay.DropdownOptions = {
    experience = {
        ["a"] = "Beginner",
        ["b"] = "Casual",
        ["c"] = "Experienced",
        ["d"] = "Veteran",
        ["e"] = "Do Not Show"
    },
    walkups = {
        ["a"] = "Walkups Welcome",
        ["b"] = "Whisper First",
        ["c"] = "Guild Only",
        ["d"] = "Closed Session",
        ["e"] = "Do Not Show"
    },
    injury = {
        ["a"] = "Minor Only",
        ["b"] = "Realistic / Negotiated",
        ["c"] = "Permanent Allowed",
        ["d"] = "No Injury",
        ["e"] = "Do Not Show"
    },
    death = {
        ["a"] = "Negotiated Only",
        ["b"] = "Ask First",
        ["c"] = "Full Consent (Permadeath OK)",
        ["d"] = "No Permadeath",
        ["e"] = "Do Not Show"
    },
    combat = {
        ["a"] = "D20 Rolls (DiceMaster)",
        ["b"] = "Emote Combat (Freeform)",
        ["c"] = "PvP Duel Resolution",
        ["d"] = "Storyteller / DM Decides",
        ["e"] = "No Combat"
    },
    sex = {
        ["a"] = "Male",
        ["b"] = "Female",
        ["c"] = "Intersex",
        ["d"] = "Hermaphrodite / Gynandromorph",
        ["e"] = "Asexual / Neuter",
        ["f"] = "Other / Custom"
    },
    gender = {
        ["a"] = "Cisgender Male",
        ["b"] = "Cisgender Female",
        ["c"] = "Transgender Male",
        ["d"] = "Transgender Female",
        ["e"] = "Non-Binary",
        ["f"] = "Agender",
        ["g"] = "Genderfluid",
        ["h"] = "Two-Spirit",
        ["i"] = "Androgynous",
        ["j"] = "Demiboy / Demigirl",
        ["k"] = "Other / Custom"
    },
    orientation = {
        ["a"] = "Heterosexual / Straight",
        ["b"] = "Homosexual / Gay",
        ["c"] = "Homosexual / Lesbian",
        ["d"] = "Bisexual",
        ["e"] = "Pansexual",
        ["f"] = "Asexual",
        ["g"] = "Demisexual",
        ["h"] = "Queer",
        ["i"] = "Questioning / Open",
        ["j"] = "Other / Custom",
        ["k"] = "Prefer Not to Say"
    },
    relationship = {
        ["a"] = "Single & Looking",
        ["b"] = "Single & Not Looking",
        ["c"] = "In a Relationship",
        ["d"] = "Partnered / Courting",
        ["e"] = "Married",
        ["f"] = "It's Complicated",
        ["g"] = "Widowed",
        ["h"] = "Open / Poly"
    },
    erp = {
        ["a"] = "No Adult Content (Clean RP)",
        ["b"] = "Romance & Fade-to-Black Only",
        ["c"] = "Story-First ERP (Plot Required)",
        ["d"] = "Adult / ERP Friendly (18+)"
    }
}

--------------------------------------------------------------------------------
-- Default Full Character Profile Schema
--------------------------------------------------------------------------------
PUIRoleplay.DefaultProfile = {
    -- 1. Identity & Nomenclature
    first_name          = "",
    middle_name         = "",
    last_name           = "",
    prefix              = "",
    title               = "",
    epithet             = "",
    suffix              = "",
    nickname            = "",
    house_name          = "",
    bloodline           = "",
    tribe               = "",
    clan                = "",
    full_name           = "",

    -- 2. Demographics, Sex, Gender & Identity
    apparent_age        = "",
    biological_sex      = "Male",
    gender_identity     = "Cisgender Male",
    ic_pronouns         = "He/Him",
    ooc_pronouns        = "He/Him",
    lgbtqia_friendly    = true,
    orientation         = "Heterosexual / Straight",
    show_orientation    = true,

    -- 3. Appearance & Physicals
    eye_color           = "",
    height              = "",
    weight              = "",
    body_build          = "",
    current_emotion     = "Calm",
    appearance_desc     = "",

    -- 4. Visual At-A-Glance Traits (5 Slots)
    glances = {
        [1] = { active = false, icon = "INV_Jewelry_Ring_03", title = "", text = "" },
        [2] = { active = false, icon = "INV_Sword_27", title = "", text = "" },
        [3] = { active = false, icon = "Spell_Holy_HolyBolt", title = "", text = "" },
        [4] = { active = false, icon = "INV_Misc_Book_09", title = "", text = "" },
        [5] = { active = false, icon = "INV_Misc_Bag_08", title = "", text = "" },
    },

    -- 5. Lore & Origins
    birth_city          = "",
    home_city           = "",
    motto               = "",
    faction_clan        = "",
    history = {
        chapter1        = "",
        chapter2        = "",
        chapter3        = "",
        chapter4        = "",
        chapter5        = "",
        chapter6        = "",
    },

    -- 6. Roleplay Dynamics & Preferences
    experience_level    = "Experienced",
    currently_ic        = "1",
    walkup_policy       = "Walkups Welcome",
    combat_preference   = "D20 Rolls (DiceMaster)",
    permadeath_consent  = "Negotiated Only",
    injury_consent      = "Realistic / Negotiated",

    -- 7. Dating, Romance & 18+ Adult-Oriented Roleplay
    relationship_status = "Single & Looking",
    looking_for = {
        adventure       = true,
        romance         = true,
        combat          = false,
        casual_tavern   = true,
        political_guild = false,
        adult_18plus    = false,
        mentorship      = false,
    },
    adult_18plus_flag   = false,
    erp_preference      = "No Adult Content (Clean RP)",
    ooc_boundaries      = "",
    ooc_notes           = "",

    -- 8. Psychological & Personality Traits Spectrum (TotalRP3 Compatible)
    personality_traits  = nil,

    -- 9. Technical Metadata & Keys
    keyM                = "",
    keyT                = "",
    keyD                = "",
    keyL                = "",
    keyX                = "",
    keyP                = "",
    icon                = "1",
}

--------------------------------------------------------------------------------
-- Default Personality Trait Spectrum Axes (Standard TotalRP3 Archetypes)
--------------------------------------------------------------------------------
PUIRoleplay.DefaultPersonalityTraits = {
    { id = "chaotic_lawful",    leftName = "Chaotic",   rightName = "Lawful",     leftIcon = "INV_Misc_Dice_02",        rightIcon = "Spell_Holy_SealOfSacrifice", value = 10, isCustom = false },
    { id = "cruel_merciful",    leftName = "Cruel",     rightName = "Merciful",   leftIcon = "Ability_Rogue_Eviscerate", rightIcon = "Spell_Holy_HolyBolt",        value = 10, isCustom = false },
    { id = "impulsive_cautious", leftName = "Impulsive", rightName = "Cautious",   leftIcon = "Ability_Warrior_Charge",  rightIcon = "Ability_Defend",             value = 10, isCustom = false },
    { id = "selfish_altruistic", leftName = "Selfish",   rightName = "Altruistic", leftIcon = "INV_Misc_Coin_02",        rightIcon = "Spell_Holy_PrayerOfHealing", value = 10, isCustom = false },
    { id = "skeptical_pious",   leftName = "Skeptical", rightName = "Pious",      leftIcon = "INV_Misc_Book_06",        rightIcon = "Spell_Holy_HolySmite",       value = 10, isCustom = false },
    { id = "ascetic_hedonistic", leftName = "Ascetic",   rightName = "Hedonistic", leftIcon = "INV_Drink_04",            rightIcon = "INV_Misc_Food_14",           value = 10, isCustom = false },
    { id = "serious_playful",   leftName = "Serious",   rightName = "Playful",    leftIcon = "Spell_Shadow_AntiShadow", rightIcon = "Spell_Magic_PolymorphPig",   value = 10, isCustom = false },
    { id = "shy_bold",          leftName = "Timid",     rightName = "Bold",       leftIcon = "Ability_Druid_Cower",     rightIcon = "Ability_Racial_BloodRage",   value = 10, isCustom = false },
    { id = "humble_proud",      leftName = "Humble",    rightName = "Proud",      leftIcon = "INV_Cloth_01",            rightIcon = "INV_Crown_01",               value = 10, isCustom = false },
}

PUIRoleplay.ClassData = {
    ["Druid"]    = { 1.00, 0.49, 0.04, "FF7C0A" },
    ["Hunter"]   = { 0.67, 0.83, 0.45, "AAD372" },
    ["Mage"]     = { 0.25, 0.78, 0.92, "3FC7EB" },
    ["Paladin"]  = { 0.96, 0.55, 0.73, "F48CBA" },
    ["Priest"]   = { 1.00, 1.00, 1.00, "FFFFFF" },
    ["Rogue"]    = { 1.00, 0.96, 0.41, "FFF468" },
    ["Shaman"]   = { 0.00, 0.44, 0.87, "0070DD" },
    ["Warlock"]  = { 0.53, 0.53, 0.93, "8788EE" },
    ["Warrior"]  = { 0.78, 0.61, 0.43, "C69B6D" }
}

