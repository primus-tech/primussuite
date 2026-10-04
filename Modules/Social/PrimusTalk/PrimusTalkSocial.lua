--[[
    PrimusUI Module: PUITalk (Social View, Friends List, Guild Roster & Live Filter Engine)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    - Tab 3 Viewport construction (Primus_PUITalkViewSocial).
    - Friends and Guild sub-tabs with instant live search filter EditBox.
    - Right-click social player menu (DM, Invite, Target, Inspect, Who).
    - Virtualized row pool with class colors, status dots, and 1-click [💬 DM] button.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus or not Primus.PUITalk then return end

local PUITalk = Primus.PUITalk
local Media   = Primus.Media
local Utils   = Primus.Utils

local socialContextMenu = nil

-- =========================================================================
-- 1. RIGHT-CLICK SOCIAL CONTEXT MENU
-- =========================================================================

local function CreateSocialContextMenu()
    if socialContextMenu then return socialContextMenu end

    local menu = CreateFrame("Frame", "Primus_PUITalkSocialMenu", UIParent)
    menu:SetWidth(150)
    menu:SetHeight(130)
    menu:SetFrameStrata("DIALOG")
    menu:SetFrameLevel(110)
    menu:SetBackdrop(Media:Fetch("border", "1Pixel"))
    menu:SetBackdropColor(0.06, 0.08, 0.12, 0.98)
    menu:SetBackdropBorderColor(0.20, 0.50, 0.90, 1.0)
    menu:EnableMouse(true)
    menu:SetClampedToScreen(true)
    menu:Hide()

    tinsert(UISpecialFrames, "Primus_PUITalkSocialMenu")

    local title = menu:CreateFontString(nil, "OVERLAY")
    title:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    title:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -8)
    title:SetText(Utils.ColorText("Player Actions", "69ccf0"))
    menu.title = title

    local items = {
        {
            text = "💬 Send DM",
            action = function()
                if menu.targetName then PUITalk:OpenDMConversation(menu.targetName) end
            end
        },
        {
            text = "⚔️ Invite to Group",
            action = function()
                if menu.targetName then InviteByName(menu.targetName) end
            end
        },
        {
            text = "🎯 Target Player",
            action = function()
                if menu.targetName then TargetByName(menu.targetName) end
            end
        },
        {
            text = "🔍 Inspect",
            action = function()
                if menu.targetName then
                    TargetByName(menu.targetName)
                    if UnitExists("target") and (UnitName("target") == menu.targetName) then
                        InspectUnit("target")
                    end
                end
            end
        },
        {
            text = "📋 Who / Info",
            action = function()
                if menu.targetName then SendChatMessage("/who " .. menu.targetName, "SAY") end
            end
        },
    }

    local yOff = -26
    for i, it in ipairs(items) do
        local btn = CreateFrame("Button", nil, menu)
        btn:SetWidth(138)
        btn:SetHeight(18)
        btn:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, yOff)
        btn:SetBackdrop(Media:Fetch("border", "1Pixel"))
        btn:SetBackdropColor(0.08, 0.10, 0.14, 0.6)
        btn:SetBackdropBorderColor(0.15, 0.20, 0.30, 0.6)

        local bTxt = btn:CreateFontString(nil, "OVERLAY")
        bTxt:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
        bTxt:SetPoint("LEFT", btn, "LEFT", 6, 0)
        bTxt:SetText(it.text)

        btn.act = it.action
        btn:SetScript("OnEnter", function()
            this:SetBackdropColor(0.18, 0.26, 0.40, 1.0)
            this:SetBackdropBorderColor(0.40, 0.75, 1.0, 1.0)
        end)
        btn:SetScript("OnLeave", function()
            this:SetBackdropColor(0.08, 0.10, 0.14, 0.6)
            this:SetBackdropBorderColor(0.15, 0.20, 0.30, 0.6)
        end)
        btn:SetScript("OnClick", function()
            menu:Hide()
            if this.act then this.act() end
        end)

        yOff = yOff - 20
    end

    socialContextMenu = menu
    return menu
end

function PUITalk:OpenSocialContextMenu(anchor, targetName)
    local menu = CreateSocialContextMenu()
    menu.targetName = targetName
    menu.title:SetText(Utils.ColorText(targetName or "Player", "69ccf0"))

    menu:ClearAllPoints()
    if anchor then
        local top = anchor:GetTop() or 0
        local screenHeight = UIParent:GetHeight() or 768
        if top > (screenHeight * 0.6) then
            menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
        else
            menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
        end
    else
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        menu:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end

    menu:Show()
    menu:Raise()
end

-- =========================================================================
-- 2. TAB 3 SOCIAL VIEWPORT CONSTRUCTION & ROW BUILDER
-- =========================================================================

local function CreateSocialRow(parent, index)
    local row = CreateFrame("Button", "Primus_PUITalkSocialRow_" .. index, parent)
    row:SetWidth(420)
    row:SetHeight(20)
    row:SetBackdrop(Media:Fetch("border", "1Pixel"))
    row:SetBackdropColor(0.06, 0.08, 0.12, 0.6)
    row:SetBackdropBorderColor(0.15, 0.20, 0.30, 0.6)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local statusDot = row:CreateTexture(nil, "ARTWORK")
    statusDot:SetWidth(7)
    statusDot:SetHeight(7)
    statusDot:SetPoint("LEFT", row, "LEFT", 6, 0)
    statusDot:SetTexture("Interface\\Buttons\\WHITE8X8")
    statusDot:SetVertexColor(0.2, 1.0, 0.4)
    row.statusDot = statusDot

    local nameText = row:CreateFontString(nil, "OVERLAY")
    nameText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    nameText:SetPoint("LEFT", statusDot, "RIGHT", 6, 0)
    nameText:SetWidth(100)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    local infoText = row:CreateFontString(nil, "OVERLAY")
    infoText:SetFont(Media:Fetch("font", "Default"), 8, "")
    infoText:SetPoint("LEFT", nameText, "RIGHT", 4, 0)
    infoText:SetWidth(180)
    infoText:SetJustifyH("LEFT")
    infoText:SetTextColor(0.75, 0.75, 0.75)
    row.infoText = infoText

    local dmBtn = CreateFrame("Button", nil, row)
    dmBtn:SetWidth(45)
    dmBtn:SetHeight(16)
    dmBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    dmBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    dmBtn:SetBackdropColor(0.12, 0.22, 0.38, 0.9)
    dmBtn:SetBackdropBorderColor(0.3, 0.6, 1.0, 1)
    local dmTxt = dmBtn:CreateFontString(nil, "OVERLAY")
    dmTxt:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    dmTxt:SetPoint("CENTER", 0, 0)
    dmTxt:SetText("💬 DM")
    dmTxt:SetTextColor(0.4, 0.85, 1.0)
    dmBtn:SetScript("OnClick", function()
        local parentRow = this:GetParent()
        if parentRow and parentRow.targetName then
            PUITalk:OpenDMConversation(parentRow.targetName)
        end
    end)
    row.dmBtn = dmBtn

    row:SetScript("OnClick", function()
        if arg1 == "RightButton" then
            PUITalk:OpenSocialContextMenu(this, this.targetName)
        else
            if this.targetName then
                PUITalk:OpenDMConversation(this.targetName)
            end
        end
    end)
    row:SetScript("OnEnter", function()
        this:SetBackdropColor(0.15, 0.22, 0.35, 0.9)
        this:SetBackdropBorderColor(0.30, 0.60, 1.0, 1.0)
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:AddLine("👤 " .. (this.targetName or "Player"), 0.4, 0.85, 1.0)
        GameTooltip:AddLine("• Left-Click: Open Direct Message.", 1, 1, 1)
        GameTooltip:AddLine("• Right-Click: Player Action Menu.", 1, 0.85, 0.2)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        this:SetBackdropColor(0.06, 0.08, 0.12, 0.6)
        this:SetBackdropBorderColor(0.15, 0.20, 0.30, 0.6)
        GameTooltip:Hide()
    end)

    return row
end

function PUITalk:CreateSocialView(viewport, master)
    if not viewport then return end

    local viewSocial = CreateFrame("Frame", "Primus_PUITalkViewSocial", viewport)
    viewSocial:SetAllPoints(viewport)
    viewSocial:SetBackdrop(Media:Fetch("border", "1Pixel"))
    viewSocial:SetBackdropColor(0.04, 0.04, 0.06, 0.8)
    viewSocial:SetBackdropBorderColor(0.15, 0.20, 0.30, 0.8)

    local socialNav = CreateFrame("Frame", nil, viewSocial)
    socialNav:SetPoint("TOPLEFT", viewSocial, "TOPLEFT", 4, -4)
    socialNav:SetPoint("TOPRIGHT", viewSocial, "TOPRIGHT", -4, -4)
    socialNav:SetHeight(22)

    local btnFriends = CreateFrame("Button", nil, socialNav)
    btnFriends:SetWidth(65)
    btnFriends:SetHeight(20)
    btnFriends:SetPoint("LEFT", socialNav, "LEFT", 0, 0)
    btnFriends:SetBackdrop(Media:Fetch("border", "1Pixel"))
    local bfTxt = btnFriends:CreateFontString(nil, "OVERLAY")
    bfTxt:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    bfTxt:SetPoint("CENTER", 0, 0)
    bfTxt:SetText("Friends")
    btnFriends.text = bfTxt
    btnFriends:SetScript("OnClick", function()
        PUITalk.db:Set("activeSocialTab", "friends")
        PUITalk:RefreshSocialView()
    end)
    viewSocial.btnFriends = btnFriends

    local btnGuild = CreateFrame("Button", nil, socialNav)
    btnGuild:SetWidth(65)
    btnGuild:SetHeight(20)
    btnGuild:SetPoint("LEFT", btnFriends, "RIGHT", 4, 0)
    btnGuild:SetBackdrop(Media:Fetch("border", "1Pixel"))
    local bgTxt = btnGuild:CreateFontString(nil, "OVERLAY")
    bgTxt:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    bgTxt:SetPoint("CENTER", 0, 0)
    bgTxt:SetText("Guild")
    btnGuild.text = bgTxt
    btnGuild:SetScript("OnClick", function()
        PUITalk.db:Set("activeSocialTab", "guild")
        PUITalk:RefreshSocialView()
    end)
    viewSocial.btnGuild = btnGuild

    local btnRefresh = CreateFrame("Button", nil, socialNav)
    btnRefresh:SetWidth(65)
    btnRefresh:SetHeight(20)
    btnRefresh:SetPoint("RIGHT", socialNav, "RIGHT", 0, 0)
    btnRefresh:SetBackdrop(Media:Fetch("border", "1Pixel"))
    btnRefresh:SetBackdropColor(0.12, 0.16, 0.22, 1.0)
    btnRefresh:SetBackdropBorderColor(0.25, 0.45, 0.70, 1.0)
    local brTxt = btnRefresh:CreateFontString(nil, "OVERLAY")
    brTxt:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    brTxt:SetPoint("CENTER", 0, 0)
    brTxt:SetText("🔄 Refresh")
    btnRefresh:SetScript("OnClick", function()
        ShowFriends()
        if IsInGuild() then GuildRoster() end
        PUITalk:RefreshSocialView()
    end)

    local searchBox = CreateFrame("EditBox", "Primus_PUITalkSocialSearchBox", socialNav)
    searchBox:SetPoint("LEFT", btnGuild, "RIGHT", 6, 0)
    searchBox:SetPoint("RIGHT", btnRefresh, "LEFT", -6, 0)
    searchBox:SetHeight(18)
    searchBox:SetBackdrop(Media:Fetch("border", "1Pixel"))
    searchBox:SetBackdropColor(0.04, 0.05, 0.08, 0.9)
    searchBox:SetBackdropBorderColor(0.20, 0.35, 0.60, 0.9)
    searchBox:SetFont(Media:Fetch("font", "Default"), 8, "")
    searchBox:SetTextColor(0.9, 0.9, 0.9)
    searchBox:SetAutoFocus(false)

    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY")
    searchPlaceholder:SetFont(Media:Fetch("font", "Default"), 8, "")
    searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 6, 0)
    searchPlaceholder:SetText("🔍 Search...")
    searchPlaceholder:SetTextColor(0.45, 0.50, 0.60)
    searchBox.placeholder = searchPlaceholder

    searchBox:SetScript("OnTextChanged", function()
        local txt = this:GetText()
        if txt and txt ~= "" then
            searchPlaceholder:Hide()
        else
            searchPlaceholder:Show()
        end
        PUITalk:RefreshSocialView()
    end)
    searchBox:SetScript("OnEscapePressed", function()
        this:SetText("")
        this:ClearFocus()
    end)
    viewSocial.searchBox = searchBox

    local socialContainer = CreateFrame("Frame", "Primus_PUITalkSocialList", viewSocial)
    socialContainer:SetPoint("TOPLEFT", socialNav, "BOTTOMLEFT", 0, -4)
    socialContainer:SetPoint("BOTTOMRIGHT", viewSocial, "BOTTOMRIGHT", -4, 4)
    viewSocial.socialContainer = socialContainer
    master.viewSocial = viewSocial
    return viewSocial
end

-- =========================================================================
-- 3. REFRESH & POPULATE SOCIAL ROSTER (WITH LIVE SEARCH FILTER)
-- =========================================================================

function PUITalk:RefreshSocialView()
    local masterFrame = self.masterFrame
    if not masterFrame or not masterFrame.viewSocial or not masterFrame.viewSocial:IsShown() then return end

    local viewSocial = masterFrame.viewSocial
    local container  = viewSocial.socialContainer
    local socialMode = self.db:Get("activeSocialTab") or "friends"

    if socialMode == "friends" then
        viewSocial.btnFriends:SetBackdropColor(0.18, 0.26, 0.40, 1.0)
        viewSocial.btnFriends:SetBackdropBorderColor(0.40, 0.75, 1.0, 1.0)
        viewSocial.btnFriends.text:SetTextColor(1, 1, 1)
        viewSocial.btnGuild:SetBackdropColor(0.08, 0.10, 0.14, 0.8)
        viewSocial.btnGuild:SetBackdropBorderColor(0.20, 0.28, 0.40, 0.8)
        viewSocial.btnGuild.text:SetTextColor(0.7, 0.7, 0.7)
    else
        viewSocial.btnGuild:SetBackdropColor(0.18, 0.26, 0.40, 1.0)
        viewSocial.btnGuild:SetBackdropBorderColor(0.40, 0.75, 1.0, 1.0)
        viewSocial.btnGuild.text:SetTextColor(1, 1, 1)
        viewSocial.btnFriends:SetBackdropColor(0.08, 0.10, 0.14, 0.8)
        viewSocial.btnFriends:SetBackdropBorderColor(0.20, 0.28, 0.40, 0.8)
        viewSocial.btnFriends.text:SetTextColor(0.7, 0.7, 0.7)
    end

    local filterQuery = ""
    if viewSocial.searchBox then
        filterQuery = string.lower(Utils.Trim(viewSocial.searchBox:GetText() or ""))
    end

    local rowCount = 0
    local onlineFriendsCount = 0
    local totalFriendsCount = GetNumFriends()

    if socialMode == "friends" then
        for i = 1, totalFriendsCount do
            local name, level, class, area, connected, status = GetFriendInfo(i)
            if connected and name then
                onlineFriendsCount = onlineFriendsCount + 1
                local searchBlob = string.lower(string.format("%s %s %s %s %s", name, tostring(level or ""), class or "", area or "", status or ""))
                local match = (filterQuery == "") or (string.find(searchBlob, filterQuery, 1, true) ~= nil)

                if match then
                    rowCount = rowCount + 1
                    local row = self.friendRows[rowCount] or CreateSocialRow(container, rowCount)
                    self.friendRows[rowCount] = row

                    row.targetName = name
                    local r, g, b = Utils.GetClassColor(class or "")
                    row.nameText:SetText(name)
                    row.nameText:SetTextColor(r, g, b)

                    local statusStr = (status and status ~= "") and (" (" .. status .. ")") or ""
                    row.infoText:SetText(string.format("Lvl %s %s - %s%s", tostring(level or "?"), class or "", area or "Unknown", statusStr))
                    row.statusDot:SetVertexColor(0.2, 1.0, 0.4)

                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(rowCount - 1) * 22)
                    row:Show()
                end
            end
        end

        if masterFrame.tabSocial and masterFrame.tabSocial.text then
            if filterQuery ~= "" then
                masterFrame.tabSocial.text:SetText(string.format("👥 Social (%d/%d)", rowCount, onlineFriendsCount))
            else
                masterFrame.tabSocial.text:SetText(string.format("👥 Social (%d/%d)", onlineFriendsCount, totalFriendsCount))
            end
        end
    else
        if IsInGuild() then
            local numGuild = GetNumGuildMembers()
            local totalOnlineGuild = 0
            for i = 1, math.min(numGuild, 60) do
                local name, rank, rankIndex, level, class, zone, note, officernote, online = GetGuildRosterInfo(i)
                if online and name and name ~= UnitName("player") then
                    totalOnlineGuild = totalOnlineGuild + 1
                    local searchBlob = string.lower(string.format("%s %s %s %s %s %s", name, tostring(level or ""), class or "", rank or "", zone or "", note or ""))
                    local match = (filterQuery == "") or (string.find(searchBlob, filterQuery, 1, true) ~= nil)

                    if match then
                        rowCount = rowCount + 1
                        local row = self.guildRows[rowCount] or CreateSocialRow(container, rowCount)
                        self.guildRows[rowCount] = row

                        row.targetName = name
                        local r, g, b = Utils.GetClassColor(class or "")
                        row.nameText:SetText(name)
                        row.nameText:SetTextColor(r, g, b)
                        row.infoText:SetText(string.format("Lvl %s %s <%s> - %s", tostring(level or "?"), class or "", rank or "", zone or "Unknown"))
                        row.statusDot:SetVertexColor(0.2, 0.8, 1.0)

                        row:ClearAllPoints()
                        row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(rowCount - 1) * 22)
                        row:Show()
                    end
                end
            end
            if masterFrame.tabSocial and masterFrame.tabSocial.text then
                if filterQuery ~= "" then
                    masterFrame.tabSocial.text:SetText(string.format("👥 Social (%d/%d)", rowCount, totalOnlineGuild))
                else
                    masterFrame.tabSocial.text:SetText(string.format("👥 Social (%d)", totalOnlineGuild))
                end
            end
        end
    end

    for i = rowCount + 1, 60 do
        if self.friendRows[i] then self.friendRows[i]:Hide() end
        if self.guildRows[i] then self.guildRows[i]:Hide() end
    end
end
