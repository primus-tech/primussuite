--[[
    PrimusLib Module: FastLoot (Smooth Timer-Paced Auto-Loot Engine)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Accelerates looting from mobs, containers, and quest nodes by processing
    loot slots with a micro-timer pacing mechanism (50ms), preventing
    Vanilla 1.12.1 C++ client engine socket collisions and crashes on multi-item drops.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIFastLoot = Primus.PUIFastLoot or {}
Primus.PUIFastLoot = PUIFastLoot
_G.PUIFastLoot = PUIFastLoot
Primus:RegisterModule("PUIFastLoot", PUIFastLoot, "Utility")

local DB     = Primus.DB
local Events = Primus.Events
local Utils  = Primus.Utils
local Time   = Primus.Time

local fastLootDB = DB:RegisterNamespace("PUIFastLoot", {
    enabled        = true,
    alwaysFastLoot = false,
    lootDelay      = 0.05,
})

local isLooting = false
local lootTicker = nil
local currentSlot = 0

local function StopLooting()
    if lootTicker then
        Time:Cancel(lootTicker)
        lootTicker = nil
    end
    isLooting = false
    currentSlot = 0
end

local function IsAutoLootActive()
    if fastLootDB:Get("alwaysFastLoot", false) then
        return true
    end

    local autoLootCVar = Utils.GetCVar and Utils.GetCVar("autoLootDefault", nil)
    if not autoLootCVar then
        local ok, val = pcall(GetCVar, "autoLootDefault")
        if ok and val then autoLootCVar = val end
    end

    if autoLootCVar == "1" then
        return not IsShiftKeyDown()
    else
        -- If FastLoot is enabled in PrimusUI, auto-loot on standard click, hold Shift to inspect
        return not IsShiftKeyDown()
    end
end

local function ProcessNextLootSlot()
    if not isLooting then
        StopLooting()
        return
    end

    local numItems = GetNumLootItems()
    if not numItems or numItems <= 0 or currentSlot <= 0 then
        StopLooting()
        return
    end

    LootSlot(currentSlot)
    currentSlot = currentSlot - 1

    if currentSlot <= 0 then
        StopLooting()
    end
end

function PUIFastLoot:StartLootPump()
    if isLooting then return end
    
    local numItems = GetNumLootItems()
    if not numItems or numItems <= 0 then return end

    isLooting = true
    currentSlot = numItems

    -- Loot highest slot immediately
    LootSlot(currentSlot)
    currentSlot = currentSlot - 1

    -- If more items remain, start a timer ticker for subsequent slots
    if currentSlot > 0 then
        local delay = math.max(0.02, fastLootDB:Get("lootDelay", 0.05))
        lootTicker = Time:Every(delay, function()
            ProcessNextLootSlot()
        end, nil, "PUIFastLoot")
    else
        StopLooting()
    end
end

function PUIFastLoot:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIFastLoot", {
        name = "PUIFastLoot",
        category = "Utility",
        label = "Fast Loot",
        icon = "Interface\\Icons\\INV_Misc_Bag_10_Blue",
        desc = "Smooth timer-paced auto-looting from mobs, containers, and quest nodes.",
        fields = {
            {
                key = "enabled",
                label = "Enable Fast Loot",
                type = "checkbox",
                default = true,
                get = function() return fastLootDB:Get("enabled", true) end,
                set = function(val) fastLootDB:Set("enabled", val) end,
            },
            {
                key = "alwaysFastLoot",
                label = "Always Auto-Loot (Ignore Shift Key)",
                type = "checkbox",
                default = false,
                get = function() return fastLootDB:Get("alwaysFastLoot", false) end,
                set = function(val) fastLootDB:Set("alwaysFastLoot", val) end,
            },
            {
                key = "lootDelay",
                label = "Slot Pacing Delay (Seconds)",
                type = "slider",
                min = 0.02,
                max = 0.20,
                step = 0.01,
                default = 0.05,
                get = function() return fastLootDB:Get("lootDelay", 0.05) end,
                set = function(val) fastLootDB:Set("lootDelay", val) end,
            },
        },
    })
end

function PUIFastLoot:OnInitialize()
    self:RegisterOptionsFlare()

    Events:Register("LOOT_OPENED", "PUIFastLoot", function()
        if not fastLootDB:Get("enabled", true) then return end
        if isLooting then return end

        if IsAutoLootActive() then
            PUIFastLoot:StartLootPump()
        end
    end)

    Events:Register("LOOT_CLOSED", "PUIFastLoot", function()
        StopLooting()
    end)
end

function PUIFastLoot:OnDisable()
    StopLooting()
    Time:CancelAll("PUIFastLoot")
    Events:UnregisterOwner("PUIFastLoot")
end

