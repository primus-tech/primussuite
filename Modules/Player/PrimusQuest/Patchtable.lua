--[[
    PrimusUI Module: PUIQuest (Turtle WoW Dynamic Delta-Patching Engine)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Dynamically patches or unpatches Turtle WoW custom quests, NPCs, objects,
    and items on top of the canonical PUIQuest.DB without legacy globals.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIQuest = Primus.PUIQuest or {}
Primus.PUIQuest = PUIQuest
_G.PUIQuest = PUIQuest

local Patchtable = {}
PUIQuest.Patchtable = Patchtable

local isPatched = false
local backupTables = {}

local DB_CATEGORIES = { "items", "quests", "quests-itemreq", "objects", "units", "zones", "professions", "areatrigger", "refloot" }

-- Deep table patching
local function ApplyDiff(base, diff)
    if not base or not diff then return end
    for k, v in pairs(diff) do
        if type(v) == "string" and v == "_" then
            base[k] = nil
        else
            base[k] = v
        end
    end
end

-- Apply Turtle WoW delta patches to canonical PUIQuest.DB
function Patchtable:Apply()
    if isPatched then return end
    local DB = PUIQuest.DB
    if not DB then return end

    -- Custom race bitmasks
    if DB.bitraces then
        DB.bitraces[256] = "Goblin"
        DB.bitraces[512] = "BloodElf"
    else
        DB.bitraces = {
            [1] = "Human",
            [2] = "Orc",
            [4] = "Dwarf",
            [8] = "NightElf",
            [16] = "Undead",
            [32] = "Tauren",
            [64] = "Gnome",
            [128] = "Troll",
            [256] = "Goblin",
            [512] = "BloodElf",
        }
    end

    -- Patch categories
    for i = 1, table.getn(DB_CATEGORIES) do
        local cat = DB_CATEGORIES[i]
        if DB[cat] then
            -- Data diff
            if DB[cat]["data-turtle"] and DB[cat]["data"] then
                ApplyDiff(DB[cat]["data"], DB[cat]["data-turtle"])
            end
            -- Locale diff
            if DB[cat]["enUS-turtle"] and DB[cat]["enUS"] then
                ApplyDiff(DB[cat]["enUS"], DB[cat]["enUS-turtle"])
            end
        end
    end

    if DB["meta-turtle"] and DB["meta"] then
        ApplyDiff(DB["meta"], DB["meta-turtle"])
    end
    if DB["minimap-turtle"] and DB["minimap"] then
        ApplyDiff(DB["minimap"], DB["minimap-turtle"])
    end

    -- Northwind zone typo workaround for custom 1.12 clients
    if GetMapZones then
        for id, name in pairs({GetMapZones(2)}) do
            if name == "Northwind " and DB["zones"] and DB["zones"]["enUS-turtle"] then
                DB["zones"]["enUS-turtle"][5581] = "Northwind "
            end
        end
    end

    -- Apply Octo / Turtle curated manual overwrites
    if PUIQuest.Overwrites and PUIQuest.Overwrites.Apply then
        PUIQuest.Overwrites:Apply(DB)
    end

    -- Octo / Turtle WoW web database URL
    PUIQuest.dburl = "https://octowow.st/db/?quest="

    isPatched = true
    if PUIQuest.Database and PUIQuest.Database.Reload then
        PUIQuest.Database:Reload()
    end
end

function Patchtable:IsPatched()
    return isPatched
end
