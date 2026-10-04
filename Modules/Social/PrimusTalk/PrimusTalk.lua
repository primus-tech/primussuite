--[[
    PrimusUI Module: PUITalk (Master Lifecycle Orchestrator & Console Routing)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    - Main module lifecycle management (OnInitialize, OnEnable, OnDisable).
    - Periodic social roster polling and roster synchronization events.
    - Console subcommands registration (/pui talk [copy|msg|social]).
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus or not Primus.PUITalk then return end

local PUITalk = Primus.PUITalk
local Utils   = Primus.Utils
local Events  = Primus.Events
local Time    = Primus.Time

-- =========================================================================
-- LIFECYCLE: INITIALIZE, ENABLE, DISABLE
-- =========================================================================

function PUITalk:OnInitialize()
    self:SuppressBlizzardChat()
    self:RegisterChatEvents()
    self:UpdateClassCache()
    self:RegisterOptionsFlare()
    self:CreateMasterFrame()
    self:HookChatKeybind()

    -- Console Subcommand Registrations
    if Primus.Console and Primus.Console.RegisterSubCommand then
        Primus.Console:RegisterSubCommand("talk", function(argParam, parts)
            argParam = Utils.Trim(argParam or "")
            if parts and parts[2] == "copy" then
                local idx = tonumber(parts[3]) or 1
                PUITalk:OpenCopyFrame(idx)
            elseif parts and (parts[2] == "msg" or parts[2] == "messages" or parts[2] == "im") then
                PUITalk:CreateMasterFrame()
                if PUITalk.masterFrame then
                    PUITalk.masterFrame:Show()
                    PUITalk:SelectMasterTab(2)
                end
            elseif parts and (parts[2] == "social" or parts[2] == "friends" or parts[2] == "guild") then
                PUITalk:CreateMasterFrame()
                if PUITalk.masterFrame then
                    PUITalk.masterFrame:Show()
                    PUITalk:SelectMasterTab(3)
                end
            else
                PUITalk:CreateMasterFrame()
                if PUITalk.masterFrame then
                    PUITalk.masterFrame:Show()
                    PUITalk:SelectMasterTab(1)
                    if PUITalk.masterFrame.editBox and not UnitAffectingCombat("player") then
                        PUITalk.masterFrame.editBox:SetFocus()
                    end
                end
            end
        end, "PUITalk Autonomous Chat & Social Suite (/pui talk [copy 1-7|msg|social])")
    end
end

function PUITalk:OnEnable()
    self:SuppressBlizzardChat()

    -- Social & Class Cache Update Events
    Events:Register("PLAYER_ENTERING_WORLD", "PUITalk", function()
        PUITalk:SuppressBlizzardChat()
        PUITalk:UpdateClassCache()
    end)
    Events:Register("PARTY_MEMBERS_CHANGED", "PUITalk", function() PUITalk:UpdateClassCache() end)
    Events:Register("RAID_ROSTER_UPDATE", "PUITalk", function() PUITalk:UpdateClassCache() end)
    Events:Register("GUILD_ROSTER_UPDATE", "PUITalk", function()
        PUITalk:UpdateClassCache()
        PUITalk:RefreshSocialView()
    end)
    Events:Register("FRIENDLIST_UPDATE", "PUITalk", function()
        PUITalk:UpdateClassCache()
        PUITalk:RefreshSocialView()
    end)
    Events:Register("PLAYER_TARGET_CHANGED", "PUITalk", function()
        if UnitExists("target") then
            local name = UnitName("target")
            local _, class = UnitClass("target")
            if name and class then
                PUITalk.playerClassCache[name] = class
            end
        end
    end)

    -- Periodic Social Roster Polling (10s)
    Time:Every(10.0, function()
        if PUITalk.masterFrame and PUITalk.masterFrame:IsShown() and (PUITalk.db:Get("activeMasterTab") == 3) then
            ShowFriends()
            if IsInGuild() then GuildRoster() end
            PUITalk:RefreshSocialView()
        end
    end, "PUITalk")
end

function PUITalk:OnDisable()
    Time:CancelAll("PUITalk")
    Events:UnregisterOwner("PUITalk")
    Events:UnregisterOwner("PUITalk_Chat")

    if self.masterFrame and self.masterFrame:IsShown() then
        self.masterFrame:Hide()
    end
end
