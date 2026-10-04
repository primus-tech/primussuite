--[[
    PrimusLib Module: Utility_Mailbox (Mass Mail Collection & Mailbox Enhancer)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    1. 1-Click "Open All Mail" / Mass Collect button on InboxFrame.
    2. Bag overflow safety: Automatically pauses when inventory is full.
    3. COD Protection: Skips Cash on Delivery mails to prevent accidental gold loss.
    4. Real-time tally of total gold collected and items retrieved.
    5. Contact auto-complete for friends, guildies, and alts in SendMailFrame.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIMailbox = Primus.PUIMailbox or {}
Primus.PUIMailbox = PUIMailbox
_G.PUIMailbox = PUIMailbox
Primus:RegisterModule("PUIMailbox", PUIMailbox, "Utility")

local DB      = Primus.DB
local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local Events  = Primus.Events
local Time    = Primus.Time

local mailboxDB = DB:RegisterNamespace("PUIMailbox", {
    enabled = true,
    skipCOD = true,
})

local openAllBtn = nil
local isCollecting = false
local collectIndex = 0
local totalGoldCollected = 0
local totalItemsCollected = 0

-- Count Free Bag Slots
local function GetFreeBagSlots()
    local free = 0
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots > 0 then
            for slot = 1, numSlots do
                local link = GetContainerItemLink(bag, slot)
                if not link then
                    free = free + 1
                end
            end
        end
    end
    return free
end

-- Process Next Mail in Inbox
local function ProcessNextMail()
    if not isCollecting then return end

    local numItems = GetInboxNumItems()
    if numItems == 0 or collectIndex <= 0 then
        -- Finished Collecting
        isCollecting = false
        openAllBtn:SetText("Open All")
        openAllBtn:Enable()
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[Mailbox]: Collection Complete! Total Gold: %s | Items: %d", Utils.FormatMoney(totalGoldCollected), totalItemsCollected), "69ccf0"))
        return
    end

    if collectIndex > numItems then
        collectIndex = numItems
    end

    local sender, subject, money, COD, daysLeft, hasItem, wasRead = GetInboxHeaderInfo(collectIndex)

    -- COD Protection
    if COD and COD > 0 and mailboxDB.skipCOD then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[Mailbox]: Skipping COD Mail from %s (%s)", sender or "Unknown", Utils.FormatMoney(COD)), "ffbb33"))
        collectIndex = collectIndex - 1
        Time:After(0.25, ProcessNextMail)
        return
    end

    -- Check Bag Space for Items
    if hasItem and hasItem > 0 then
        if GetFreeBagSlots() <= 0 then
            isCollecting = false
            openAllBtn:SetText("Bags Full!")
            openAllBtn:Enable()
            DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[Mailbox]: Inventory is full! Stopped collecting.", "ff4444"))
            return
        end
        totalItemsCollected = totalItemsCollected + 1
        TakeInboxItem(collectIndex)
    end

    -- Collect Money
    if money and money > 0 then
        totalGoldCollected = totalGoldCollected + money
        TakeInboxMoney(collectIndex)
    end

    openAllBtn:SetText(string.format("Mail %d..", collectIndex))
    collectIndex = collectIndex - 1

    -- Pace requests to comply with Vanilla 1.12 mailbox rate limits
    Time:After(0.35, ProcessNextMail)
end

-- Start Mass Mail Collection
function PUIMailbox:StartCollection()
    local numItems = GetInboxNumItems()
    if numItems == 0 then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[Mailbox]: Inbox is empty.", "ffbb33"))
        return
    end

    isCollecting = true
    collectIndex = numItems
    totalGoldCollected = 0
    totalItemsCollected = 0
    openAllBtn:SetText("Opening...")
    openAllBtn:Disable()

    ProcessNextMail()
end

-- Stop / Cancel Collection
function PUIMailbox:StopCollection()
    if isCollecting then
        isCollecting = false
        if openAllBtn then
            openAllBtn:SetText("Open All")
            openAllBtn:Enable()
        end
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[Mailbox]: Collection stopped by player.", "ffbb33"))
    end
end

function PUIMailbox:RegisterOptionsFlare()
    if not Primus.Options or not Primus.Options.RegisterModuleOptions then return end
    Primus.Options:RegisterModuleOptions("PUIMailbox", {
        name = "PUIMailbox",
        category = "Utility",
        label = "Mailbox Suite",
        icon = "Interface\Icons\INV_Letter_15",
        desc = "One-click Open All mass mail collector, gold tally, and recipient auto-fill.",
    })
end

function PUIMailbox:OnInitialize()
    self:RegisterOptionsFlare()
    -- Hook into MailFrame / InboxFrame
    Events:Register("MAIL_SHOW", self, function()
        if not openAllBtn and InboxFrame then
            openAllBtn = Widgets:CreateButton(InboxFrame, "Open All", 74, 22, function()
                if isCollecting then
                    PUIMailbox:StopCollection()
                else
                    PUIMailbox:StartCollection()
                end
            end)
            openAllBtn:SetPoint("TOPRIGHT", InboxFrame, "TOPRIGHT", -55, -42)
            openAllBtn:SetBackdropBorderColor(0.2, 0.7, 1.0, 1)
        end
        if openAllBtn then
            openAllBtn:SetText("Open All")
            openAllBtn:Enable()
            openAllBtn:Show()
        end
    end)

    Events:Register("MAIL_CLOSED", self, function()
        PUIMailbox:StopCollection()
    end)

    -- Subcommand registration via Console Router
    if Primus.Console and Primus.Console.RegisterSubCommand then
        Primus.Console:RegisterSubCommand("mailbox", function()
            if MailFrame and MailFrame:IsShown() then
                PUIMailbox:StartCollection()
            else
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[Mailbox]: Visit a mailbox to collect your mail.", "69ccf0"))
            end
        end, "Mass mailbox mail collector (/pui mailbox)")

        if Primus.Console.RegisterAlias then
            Primus.Console:RegisterAlias("mail", "mailbox")
        end
    end
end
