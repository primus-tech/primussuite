--[[
    PrimusLib Module: Social_MasterLoot (Raid Roll Tracker & Master Loot Assistant)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    1. Automated /roll 1-100 parser linked to active loot items.
    2. Real-time sorted roll list with duplicate roll rejection.
    3. Countdown timer for roll windows.
    4. 1-Click "Announce Winner" broadcast to Raid / Party chat.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIMasterLoot = Primus.PUIMasterLoot or {}
Primus.PUIMasterLoot = PUIMasterLoot
_G.PUIMasterLoot = PUIMasterLoot
Primus:RegisterModule("PUIMasterLoot", PUIMasterLoot, "Social")

local DB      = Primus.DB
local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local Events  = Primus.Events
local Time    = Primus.Time
local PUIMover = Primus.PUIMover

local mlDB = DB:RegisterNamespace("PUIMasterLoot", {
    enabled = true,
    rollDuration = 15,
})

local mlFrame = nil
local activeItemLink = nil
local activeRolls = {}
local rollHistory = {}
local rollEndTime = 0
local isRolling = false

-- Reset Roll State
function PUIMasterLoot:ResetRolls()
    activeRolls = {}
    rollHistory = {}
    isRolling = false
    rollEndTime = 0
end

-- Start a New Roll Session
function PUIMasterLoot:StartRollSession(itemLink)
    self:ResetRolls()
    activeItemLink = itemLink or "Item"
    isRolling = true
    rollEndTime = GetTime() + (mlDB.rollDuration or 15)

    if not mlFrame then
        self:CreateUI()
    end

    mlFrame.itemText:SetText(itemLink or "Loot Roll")
    mlFrame:Show()

    local chan = GetNumRaidMembers() > 0 and "RAID" or (GetNumPartyMembers() > 0 and "PARTY" or "SAY")
    SendChatMessage(string.format("[MasterLoot]: Rolls open for %s! (1-100, %ds)", itemLink or "Item", mlDB.rollDuration or 15), chan)
end

-- Process Incoming System Message for Rolls
function PUIMasterLoot:ParseRoll(msg)
    if not isRolling then return end

    local s, e, player, roll, minRoll, maxRoll = string.find(msg, "(.+) rolls (%d+) %((%d+)%-(%d+)%)")
    if s and player and roll then
        roll = tonumber(roll)
        minRoll = tonumber(minRoll)
        maxRoll = tonumber(maxRoll)

        -- Accept only standard 1-100 rolls
        if minRoll == 1 and maxRoll == 100 then
            -- Reject duplicate rolls
            if not rollHistory[player] then
                rollHistory[player] = roll
                table.insert(activeRolls, { name = player, roll = roll })

                -- Sort rolls descending
                table.sort(activeRolls, function(a, b)
                    return a.roll > b.roll
                end)

                self:UpdateRollList()
            end
        end
    end
end

-- Update Roll Display
function PUIMasterLoot:UpdateRollList()
    if not mlFrame or not mlFrame:IsShown() then return end

    local str = ""
    local count = table.getn(activeRolls)
    for i = 1, math.min(count, 8) do
        local r = activeRolls[i]
        if i == 1 then
            str = str .. string.format("|cff33ff331. %s - %d (Leading)|r\n", r.name, r.roll)
        else
            str = str .. string.format("%d. %s - %d\n", i, r.name, r.roll)
        end
    end

    if count == 0 then
        str = "|cff888888Waiting for rolls...|r"
    end
    mlFrame.rollListText:SetText(str)
end

-- Announce Winning Roll
function PUIMasterLoot:AnnounceWinner()
    local count = table.getn(activeRolls)
    local chan = GetNumRaidMembers() > 0 and "RAID" or (GetNumPartyMembers() > 0 and "PARTY" or "SAY")

    if count > 0 then
        local winner = activeRolls[1]
        SendChatMessage(string.format("[MasterLoot]: Winner of %s is %s with a roll of %d!", activeItemLink or "Item", winner.name, winner.roll), chan)
    else
        SendChatMessage(string.format("[MasterLoot]: No rolls recorded for %s.", activeItemLink or "Item"), chan)
    end
    isRolling = false
end

-- Create MasterLoot UI Window
function PUIMasterLoot:CreateUI()
    mlFrame = CreateFrame("Frame", "Primus_MasterLootFrame", UIParent)
    mlFrame:SetWidth(240)
    mlFrame:SetHeight(200)
    mlFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    mlFrame:SetBackdrop(Media:Fetch("border", "1Pixel"))
    mlFrame:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    mlFrame:SetBackdropBorderColor(1.0, 0.8, 0.2, 1) -- Gold
    mlFrame:SetMovable(true)
    mlFrame:EnableMouse(true)
    mlFrame:RegisterForDrag("LeftButton")
    mlFrame:SetScript("OnDragStart", function() this:StartMoving() end)
    mlFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    mlFrame:Hide()

    local title = mlFrame:CreateFontString(nil, "OVERLAY")
    title:SetFont(Media:Fetch("font", "Default"), 10, "OUTLINE")
    title:SetPoint("TOPLEFT", mlFrame, "TOPLEFT", 6, -6)
    title:SetText(Utils.ColorText("Master Loot Tracker", "ffd100"))
    mlFrame.title = title

    local closeBtn = CreateFrame("Button", nil, mlFrame)
    closeBtn:SetWidth(16)
    closeBtn:SetHeight(16)
    closeBtn:SetPoint("TOPRIGHT", mlFrame, "TOPRIGHT", -4, -4)
    closeBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    closeBtn:SetBackdropColor(0.6, 0.1, 0.1, 0.8)
    closeBtn:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
    local cT = closeBtn:CreateFontString(nil, "OVERLAY")
    cT:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    cT:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    cT:SetText("X")
    closeBtn:SetScript("OnClick", function() mlFrame:Hide() end)

    local itemText = mlFrame:CreateFontString(nil, "OVERLAY")
    itemText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    itemText:SetPoint("TOPLEFT", mlFrame, "TOPLEFT", 8, -24)
    itemText:SetText("Item: None")
    mlFrame.itemText = itemText

    local timerText = mlFrame:CreateFontString(nil, "OVERLAY")
    timerText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    timerText:SetPoint("TOPRIGHT", mlFrame, "TOPRIGHT", -8, -24)
    timerText:SetText("15s")
    mlFrame.timerText = timerText

    local rollListText = mlFrame:CreateFontString(nil, "OVERLAY")
    rollListText:SetFont(Media:Fetch("font", "Default"), 9, "")
    rollListText:SetPoint("TOPLEFT", itemText, "BOTTOMLEFT", 0, -6)
    rollListText:SetJustifyH("LEFT")
    rollListText:SetText("Waiting for rolls...")
    mlFrame.rollListText = rollListText

    local announceBtn = Widgets:CreateButton(mlFrame, "Announce Winner", 130, 20, function()
        PUIMasterLoot:AnnounceWinner()
    end)
    announceBtn:SetPoint("BOTTOMLEFT", mlFrame, "BOTTOMLEFT", 6, 6)
    announceBtn:SetBackdropBorderColor(0.2, 0.8, 0.3, 1)

    local clearBtn = Widgets:CreateButton(mlFrame, "Clear", 60, 20, function()
        PUIMasterLoot:ResetRolls()
        PUIMasterLoot:UpdateRollList()
    end)
    local mover = PUIMover or Primus.PUIMover
    if mover and mover.Register then
        mover:Register(mlFrame, "MasterLootTracker", "Master Loot Roll Tracker", "SOCIAL")
    end
end

function PUIMasterLoot:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIMasterLoot", {
        name = "Social_MasterLoot",
        category = "Social",
        label = "Master Loot",
        options = {
            {
                key = "rollDuration",
                type = "slider",
                label = "Roll Window Duration",
                desc = "Duration in seconds for roll countdown window before closing.",
                min = 5,
                max = 60,
                step = 5,
                default = 15,
                get = function() return mlDB.rollDuration or 15 end,
                set = function(v) mlDB.rollDuration = v end,
            },
        },
    })
end

function PUIMasterLoot:OnInitialize()
    self:RegisterOptionsFlare()

    -- Subcommand registration via Console Router
    if Primus.Console and Primus.Console.RegisterSubCommand then
        Primus.Console:RegisterSubCommand("masterloot", function(argParam)
            if argParam and argParam ~= "" then
                PUIMasterLoot:StartRollSession(argParam)
            else
                if not mlFrame then PUIMasterLoot:CreateUI() end
                if mlFrame:IsShown() then
                    mlFrame:Hide()
                else
                    mlFrame:Show()
                end
            end
        end, "Master Loot Roll Tracker (/pui masterloot [item])")

        if Primus.Console.RegisterAlias then
            Primus.Console:RegisterAlias("ml", "masterloot")
        end
    end
end

function PUIMasterLoot:OnEnable()
    Events:Register("CHAT_MSG_SYSTEM", self, function(owner, event, msg)
        PUIMasterLoot:ParseRoll(msg)
    end)

    -- 0.5s Countdown Ticker
    Time:Every(0.5, function()
        if isRolling and mlFrame and mlFrame:IsShown() then
            local left = rollEndTime - GetTime()
            if left > 0 then
                mlFrame.timerText:SetText(string.format("%.0fs", left))
            else
                mlFrame.timerText:SetText("CLOSED")
                mlFrame.timerText:SetTextColor(1.0, 0.2, 0.2)
                PUIMasterLoot:AnnounceWinner()
            end
        end
    end, self)
end

function PUIMasterLoot:OnDisable()
    Time:CancelAll(self)
    Events:UnregisterOwner(self)
    self:ResetRolls()
    if mlFrame then mlFrame:Hide() end
end

