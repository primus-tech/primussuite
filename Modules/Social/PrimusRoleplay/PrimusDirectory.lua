--[[
    PrimusUI: PUIRoleplay Directory Master Browser (PUIDirectory.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (Matchmaking Directory & Filters)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIRoleplay = Primus.PUIRoleplay or {}
Primus.PUIRoleplay = PUIRoleplay

local Directory = PUIRoleplay.Directory or {}
PUIRoleplay.Directory = Directory

local dirFrame = nil
local VISIBLE_ROWS = 14
local ROW_HEIGHT = 26

Directory.sortField = "status"
Directory.sortAsc = true
Directory.activeFlyoutTab = 1
Directory.selectedPlayer = nil
Directory.activeFilter = "ALL"

--------------------------------------------------------------------------------
-- Build Directory UI Window
--------------------------------------------------------------------------------
function Directory:BuildFrame()
    if dirFrame then return dirFrame end

    local f = CreateFrame("Frame", "Primus_PUIRoleplay_Directory", UIParent)
    f:SetWidth(560)
    f:SetHeight(520)
    f:SetPoint("CENTER", UIParent, "CENTER", -120, 0)
    f:SetFrameStrata("HIGH")
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
    f:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
    f:SetBackdropBorderColor(0.20, 0.22, 0.26, 1.0)
    table.insert(UISpecialFrames, "Primus_PUIRoleplay_Directory")

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
    titleBar:SetBackdropColor(0.11, 0.12, 0.15, 1.0)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleText:SetText("|cff00ccffPRIMUS|r |cffffffffRP DIRECTORY & DISCOVERY|r")

    local totalText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    totalText:SetPoint("LEFT", titleText, "RIGHT", 10, 0)
    totalText:SetText("|cff888888(Scanning #OWPRP / #TTRP...)|r")
    f.totalText = totalText

    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetWidth(18)
    closeBtn:SetHeight(18)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local scanBtn = CreateFrame("Button", nil, titleBar)
    scanBtn:SetWidth(90)
    scanBtn:SetHeight(18)
    scanBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    scanBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    scanBtn:SetBackdropColor(0.10, 0.15, 0.22, 0.9)
    scanBtn:SetBackdropBorderColor(0.0, 0.6, 0.9, 0.8)

    local scanLabel = scanBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scanLabel:SetPoint("CENTER", scanBtn, "CENTER", 0, 0)
    scanLabel:SetText("|cff00ccff[ Ping / Scan ]|r")

    scanBtn:SetScript("OnEnter", function()
        this:SetBackdropColor(0.0, 0.35, 0.55, 0.9)
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Broadcast Presence Ping", 0.0, 0.8, 1.0)
        GameTooltip:AddLine("Broadcasts discovery pings across #OWPRP and #TTRP channels.", 0.8, 0.8, 0.8, 1)
        GameTooltip:Show()
    end)
    scanBtn:SetScript("OnLeave", function()
        this:SetBackdropColor(0.10, 0.15, 0.22, 0.9)
        GameTooltip:Hide()
    end)
    scanBtn:SetScript("OnClick", function()
        PUIRoleplay.Comms:SendPing("P")
        PUIRoleplay.Comms:SendPing("A")
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffPrimus RP:|r Broadcasted presence ping on |cffffcc00#OWPRP / #TTRP|r.")
        Directory:RefreshList(f.searchEB:GetText() or "")
    end)

    -- Search EditBox
    local searchEB = CreateFrame("EditBox", nil, f)
    searchEB:SetWidth(536)
    searchEB:SetHeight(22)
    searchEB:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -34)
    searchEB:SetAutoFocus(false)
    searchEB:SetFontObject(GameFontHighlightSmall)
    searchEB:SetTextColor(1.0, 1.0, 1.0, 1.0)
    searchEB:SetTextInsets(8, 8, 2, 2)
    searchEB:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    searchEB:SetBackdropColor(0.04, 0.04, 0.07, 0.95)
    searchEB:SetBackdropBorderColor(0.30, 0.30, 0.38, 1.0)

    searchEB:SetScript("OnEditFocusGained", function()
        this:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
        this:SetBackdropColor(0.08, 0.10, 0.14, 1.0)
    end)
    searchEB:SetScript("OnEditFocusLost", function()
        this:SetBackdropBorderColor(0.30, 0.30, 0.38, 1.0)
        this:SetBackdropColor(0.04, 0.04, 0.07, 0.95)
    end)
    searchEB:SetScript("OnEscapePressed", function()
        this:SetText("")
        this:ClearFocus()
        Directory:RefreshList("")
    end)
    searchEB:SetScript("OnTextChanged", function()
        Directory:RefreshList(this:GetText() or "")
    end)
    f.searchEB = searchEB

    -- Filter Chips
    local filterBar = CreateFrame("Frame", nil, f)
    filterBar:SetPoint("TOPLEFT", searchEB, "BOTTOMLEFT", 0, -4)
    filterBar:SetWidth(536)
    filterBar:SetHeight(22)

    local filterDefs = {
        { id = "ALL", label = "All Roleplayers" },
        { id = "IC", label = "IC Only" },
        { id = "LGBTQ", label = "|cffff0000L|cffff7f00G|cffffff00B|cff00ff00T|cff0000ffQ|cff9400d3+|r" },
        { id = "ROMANCE", label = "|cffff80ccRomance|r" },
        { id = "ADVENTURE", label = "|cff00ff88Adventure|r" },
        { id = "TAVERN", label = "|cffffcc00Tavern|r" },
        { id = "ADULT18", label = "|cffff335518+ Adult|r" }
    }

    f.filterButtons = {}
    local chipWidth = 73
    for cIdx, item in ipairs(filterDefs) do
        local cBtn = CreateFrame("Button", nil, filterBar)
        cBtn:SetWidth(chipWidth)
        cBtn:SetHeight(20)
        cBtn:SetPoint("TOPLEFT", filterBar, "TOPLEFT", (cIdx - 1) * (chipWidth + 4), 0)
        cBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        cBtn:SetBackdropColor(0.06, 0.06, 0.09, 0.95)
        cBtn:SetBackdropBorderColor(0.22, 0.22, 0.28, 1.0)

        local cbTxt = cBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cbTxt:SetPoint("CENTER", cBtn, "CENTER", 0, 0)
        cbTxt:SetText(item.label)
        cBtn.text = cbTxt
        cBtn.filterId = item.id

        cBtn:SetScript("OnClick", function()
            Directory.activeFilter = this.filterId
            for _, b in ipairs(f.filterButtons) do
                if b.filterId == Directory.activeFilter then
                    b:SetBackdropColor(0.0, 0.45, 0.70, 0.95)
                    b:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
                else
                    b:SetBackdropColor(0.06, 0.06, 0.09, 0.95)
                    b:SetBackdropBorderColor(0.22, 0.22, 0.28, 1.0)
                end
            end
            Directory:RefreshList(f.searchEB:GetText() or "")
        end)

        table.insert(f.filterButtons, cBtn)
    end

    -- Header Row
    local headerRow = CreateFrame("Frame", nil, f)
    headerRow:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -6)
    headerRow:SetWidth(518)
    headerRow:SetHeight(22)
    headerRow:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    headerRow:SetBackdropColor(0.08, 0.09, 0.12, 1.0)
    headerRow:SetBackdropBorderColor(0.18, 0.20, 0.24, 1.0)

    local function CreateSortHeaderButton(name, width, text, fieldKey)
        local btn = CreateFrame("Button", name, headerRow)
        btn:SetHeight(18)
        btn:SetWidth(width)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        btn:SetBackdropColor(0.05, 0.06, 0.08, 0.8)
        btn:SetBackdropBorderColor(0.16, 0.18, 0.22, 1.0)

        local fontStr = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fontStr:SetPoint("LEFT", btn, "LEFT", 6, 0)
        fontStr:SetText(text)
        btn.text = fontStr
        btn.fieldKey = fieldKey

        btn:SetScript("OnEnter", function()
            this:SetBackdropColor(0.12, 0.16, 0.24, 1.0)
            this:SetBackdropBorderColor(0.0, 0.70, 0.95, 0.9)
        end)
        btn:SetScript("OnLeave", function()
            this:SetBackdropColor(0.05, 0.06, 0.08, 0.8)
            this:SetBackdropBorderColor(0.16, 0.18, 0.22, 1.0)
        end)
        btn:SetScript("OnClick", function()
            if Directory.sortField == this.fieldKey then
                Directory.sortAsc = not Directory.sortAsc
            else
                Directory.sortField = this.fieldKey
                Directory.sortAsc = true
            end
            Directory:RefreshList()
        end)
        return btn
    end

    local btnStatus = CreateSortHeaderButton(nil, 84, "Status", "status")
    btnStatus:SetPoint("LEFT", headerRow, "LEFT", 2, 0)
    f.btnStatus = btnStatus

    local btnName = CreateSortHeaderButton(nil, 240, "Roleplayer / Full Name", "name")
    btnName:SetPoint("LEFT", btnStatus, "RIGHT", 4, 0)
    f.btnName = btnName

    local btnZone = CreateSortHeaderButton(nil, 184, "Current Zone / Vicinity", "zone")
    btnZone:SetPoint("LEFT", btnName, "RIGHT", 4, 0)
    f.btnZone = btnZone

    -- Rows
    f.currentOffset = 0
    f.matchedItems = {}
    f.rows = {}

    for i = 1, VISIBLE_ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetWidth(518)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -(i - 1) * (ROW_HEIGHT + 1) - 2)
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        row:SetBackdropColor(0.04, 0.04, 0.05, (math.mod(i, 2) == 0) and 0.85 or 0.45)
        row:SetBackdropBorderColor(0.14, 0.14, 0.17, 1.0)

        local statusTxt = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        statusTxt:SetPoint("LEFT", row, "LEFT", 6, 0)
        statusTxt:SetWidth(80)
        statusTxt:SetJustifyH("LEFT")
        row.statusTxt = statusTxt

        local nameTxt = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameTxt:SetPoint("LEFT", row, "LEFT", 90, 0)
        nameTxt:SetWidth(236)
        nameTxt:SetJustifyH("LEFT")
        row.nameTxt = nameTxt

        local zoneTxt = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        zoneTxt:SetPoint("LEFT", row, "LEFT", 330, 0)
        zoneTxt:SetWidth(180)
        zoneTxt:SetJustifyH("LEFT")
        row.zoneTxt = zoneTxt

        row:SetScript("OnEnter", function()
            if Directory.selectedPlayer ~= this.targetPlayerName then
                this:SetBackdropColor(0.0, 0.35, 0.55, 0.6)
                this:SetBackdropBorderColor(0.0, 0.7, 1.0, 1.0)
            end

            if this.targetPlayerName then
                local isSelf = (this.targetPlayerName == UnitName("player"))
                local data = isSelf and PUIRoleplay:GetMyProfile() or PUIRoleplay:GetCharacterData(this.targetPlayerName)
                if data then
                    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                    local fullName = (data.full_name and data.full_name ~= "") and data.full_name or this.targetPlayerName
                    local colorHex = data.class_color or "FFFFFF"
                    GameTooltip:AddLine("|cff" .. colorHex .. fullName .. "|r (|cff888888" .. this.targetPlayerName .. "|r)")

                    local isOnline = isSelf or PUIRoleplay:IsPlayerOnline(this.targetPlayerName)
                    local isIC = (data.currently_ic == "1")
                    local statusStr = not isOnline and "|cff777788Offline|r" or (isIC and "|cff00ff88In Character (IC)|r" or "|cffffaa00Out of Character (OOC)|r")
                    GameTooltip:AddLine("Status: " .. statusStr, 1, 1, 1)

                    if data.title and data.title ~= "" then
                        GameTooltip:AddLine("<" .. data.title .. ">", 0.0, 0.85, 1.0)
                    end
                    if data.apparent_age and data.apparent_age ~= "" then
                        GameTooltip:AddLine("Age: |cffffffff" .. data.apparent_age .. "|r", 0.8, 0.8, 0.8)
                    end
                    if data.biological_sex and data.biological_sex ~= "" then
                        GameTooltip:AddLine("Sex: |cffffffff" .. data.biological_sex .. "|r", 0.8, 0.8, 0.8)
                    end
                    if data.gender_identity and data.gender_identity ~= "" then
                        GameTooltip:AddLine("Gender: |cffffffff" .. data.gender_identity .. "|r", 0.8, 0.8, 0.8)
                    end
                    local pr = (data.currently_ic == "1") and data.ic_pronouns or data.ooc_pronouns
                    if pr and pr ~= "" then
                        GameTooltip:AddLine("Pronouns: |cffffffff" .. pr .. "|r", 0.8, 0.8, 0.8)
                    end
                    if data.lgbtqia_friendly ~= false then
                        GameTooltip:AddLine("|cffff0000[|cffff7f00LGBTQIA+|cff9400d3 Friendly Safe Space]|r", 1, 1, 1)
                    end
                    if data.adult_18plus_flag == true then
                        GameTooltip:AddLine("|cffff3355[18+ Adult-Oriented Profile]|r", 1, 0.3, 0.3)
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cff00ccffClick|r to open Discovery Card flyout.", 0.2, 0.8, 0.2)
                    GameTooltip:Show()
                end
            end
        end)

        row:SetScript("OnLeave", function()
            if Directory.selectedPlayer == this.targetPlayerName then
                this:SetBackdropColor(0.08, 0.18, 0.28, 0.95)
                this:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
            else
                this:SetBackdropColor(0.04, 0.04, 0.05, (math.mod(i, 2) == 0) and 0.85 or 0.45)
                this:SetBackdropBorderColor(0.14, 0.14, 0.17, 1.0)
            end
            GameTooltip:Hide()
        end)

        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function()
            if not this.targetPlayerName then return end
            if arg1 == "RightButton" and Widgets and Widgets.ShowContextMenu then
                local pName = this.targetPlayerName
                local charData = PUIRoleplay:GetCharacterData(pName) or {}
                local displayName = (charData.full_name and charData.full_name ~= "") and charData.full_name or pName
                local items = {
                    { text = displayName, isTitle = true },
                    { isSeparator = true },
                    { text = "Whisper", icon = "Interface\\Icons\\INV_Misc_Note_01", func = function()
                        ChatFrame_SendTell(pName)
                    end },
                    { text = "Invite to Group", icon = "Interface\\Icons\\INV_Misc_GroupNeedMore", func = function()
                        InviteByName(pName)
                    end },
                    { text = "Target Player", icon = "Interface\\Icons\\Ability_Hunter_MasterMarksman", func = function()
                        TargetByName(pName, true)
                    end },
                    { isSeparator = true },
                    { text = "Open Discovery Card", func = function()
                        Directory:ShowPlayerFlyout(pName)
                    end },
                    { text = "Open Character Sheet", func = function()
                        if PUIRoleplay.Sheet then PUIRoleplay.Sheet:Open(pName) end
                    end },
                    { text = "View At-a-Glance", func = function()
                        if PUIRoleplay.Glance then PUIRoleplay.Glance:Open(pName) end
                    end },
                }
                Widgets:ShowContextMenu(this, items, { point = "TOPLEFT", relPoint = "BOTTOMLEFT", yOffset = -2 })
            else
                Directory:ShowPlayerFlyout(this.targetPlayerName)
            end
        end)

        f.rows[i] = row
    end

    -- Scrollbar Slider
    local scrollbar = CreateFrame("Slider", "Primus_PUIRoleplay_DirectoryScrollBar", f)
    scrollbar:SetWidth(14)
    scrollbar:SetPoint("TOPLEFT", headerRow, "TOPRIGHT", 4, 0)
    scrollbar:SetPoint("BOTTOMLEFT", headerRow, "BOTTOMRIGHT", 4, -(VISIBLE_ROWS * (ROW_HEIGHT + 1) + 2))
    scrollbar:SetOrientation("VERTICAL")
    scrollbar:SetMinMaxValues(0, 0)
    scrollbar:SetValue(0)
    scrollbar:SetValueStep(1)
    scrollbar:SetFrameLevel(f:GetFrameLevel() + 25)
    scrollbar:EnableMouse(true)
    scrollbar:EnableMouseWheel(true)
    scrollbar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    scrollbar:SetBackdropColor(0.02, 0.03, 0.05, 0.9)
    scrollbar:SetBackdropBorderColor(0.18, 0.20, 0.26, 1.0)

    local thumb = scrollbar:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
    thumb:SetVertexColor(0.0, 0.7, 1.0, 0.9)
    thumb:SetWidth(12)
    thumb:SetHeight(32)
    scrollbar:SetThumbTexture(thumb)

    scrollbar:SetScript("OnValueChanged", function()
        Directory:UpdateScroll(math.floor(this:GetValue()))
    end)
    scrollbar:SetScript("OnMouseWheel", function()
        local current = this:GetValue()
        if arg1 > 0 then
            this:SetValue(math.max(0, current - 1))
        elseif arg1 < 0 then
            local _, maxVal = this:GetMinMaxValues()
            this:SetValue(math.min(maxVal, current + 1))
        end
    end)
    f.scrollbar = scrollbar

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function()
        local current = scrollbar:GetValue()
        if arg1 > 0 then
            scrollbar:SetValue(math.max(0, current - 1))
        elseif arg1 < 0 then
            local _, maxVal = scrollbar:GetMinMaxValues()
            scrollbar:SetValue(math.min(maxVal, current + 1))
        end
    end)

    if Directory.BuildFlyout then
        Directory:BuildFlyout(f)
    end

    dirFrame = f
    return f
end

--------------------------------------------------------------------------------
-- Directory Refresh & Render Logic
--------------------------------------------------------------------------------
function Directory:RefreshList(filterText)
    local f = self:BuildFrame()
    local query = string.lower(filterText or (f.searchEB and f.searchEB:GetText()) or "")
    local allChars = PUIRoleplay:GetAllKnownCharacters()
    local playerName = UnitName("player")
    local myZone = GetZoneText() or ""
    if myZone == "" then myZone = GetMinimapZoneText() or GetRealZoneText() or "" end

    local matched = {}
    local totalFound = 0
    local onlineCount = 0
    local hasPlayer = false
    local filterMode = Directory.activeFilter or "ALL"

    for name, data in pairs(allChars) do
        if data then
            totalFound = totalFound + 1
            local isSelf = (name == playerName)
            if isSelf then hasPlayer = true end

            local isOnline = isSelf or PUIRoleplay:IsPlayerOnline(name)
            if isOnline then onlineCount = onlineCount + 1 end

            local fullName = PUIRoleplay:ComposeFullName(data)
            if fullName == "" then fullName = name end
            local rawZone = isSelf and ((myZone ~= "") and myZone or (data.zone or "")) or (data.zone or "")
            local zone = PUIRoleplay.Protocols and PUIRoleplay.Protocols.DrunkDecode and PUIRoleplay.Protocols:DrunkDecode(rawZone) or rawZone
            local class = (data.class and data.class ~= "") and data.class or (isSelf and UnitClass("player") or "")
            local classColor = data.class_color or (isSelf and PUIRoleplay.ClassData and PUIRoleplay.ClassData[UnitClass("player")] and PUIRoleplay.ClassData[UnitClass("player")][4]) or "FFFFFF"
            local isIC = (data.currently_ic == "1")

            local passesFilter = true
            if filterMode == "IC" and not isIC then passesFilter = false end
            if filterMode == "LGBTQ" and (data.lgbtqia_friendly == false) then passesFilter = false end
            if filterMode == "ADULT18" and (data.adult_18plus_flag ~= true and (not data.looking_for or not data.looking_for.adult_18plus)) then passesFilter = false end
            if filterMode == "ROMANCE" and (not data.looking_for or not data.looking_for.romance) then passesFilter = false end
            if filterMode == "ADVENTURE" and (not data.looking_for or not data.looking_for.adventure) then passesFilter = false end
            if filterMode == "TAVERN" and (not data.looking_for or not data.looking_for.casual_tavern) then passesFilter = false end

            local statusRank = isOnline and (isIC and 1 or 2) or 3

            if passesFilter then
                if query == "" or string.find(string.lower(name), query) or string.find(string.lower(fullName), query) or string.find(string.lower(zone), query) or string.find(string.lower(class), query) then
                    table.insert(matched, {
                        rawName = name,
                        fullName = fullName,
                        class = class,
                        classColor = classColor,
                        isIC = isIC,
                        isOnline = isOnline,
                        statusRank = statusRank,
                        zone = zone
                    })
                end
            end
        end
    end

    if not hasPlayer and playerName then
        local myProf = PUIRoleplay:GetMyProfile() or {}
        local _, pClass = UnitClass("player")
        local colorHex = (PUIRoleplay.ClassData and PUIRoleplay.ClassData[pClass] and PUIRoleplay.ClassData[pClass][4]) or "FFFFFF"
        local myFullName = PUIRoleplay:ComposeFullName(myProf)
        if myFullName == "" then myFullName = playerName end
        local isIC = (myProf.currently_ic == "1")
        local currentZone = (myZone ~= "") and myZone or "Unknown"

        local passesFilter = true
        if filterMode == "IC" and not isIC then passesFilter = false end
        if filterMode == "LGBTQ" and (myProf.lgbtqia_friendly == false) then passesFilter = false end
        if filterMode == "ADULT18" and (myProf.adult_18plus_flag ~= true) then passesFilter = false end
        if filterMode == "ROMANCE" and (not myProf.looking_for or not myProf.looking_for.romance) then passesFilter = false end
        if filterMode == "ADVENTURE" and (not myProf.looking_for or not myProf.looking_for.adventure) then passesFilter = false end
        if filterMode == "TAVERN" and (not myProf.looking_for or not myProf.looking_for.casual_tavern) then passesFilter = false end

        if passesFilter then
            if query == "" or string.find(string.lower(playerName), query) or string.find(string.lower(myFullName), query) or string.find(string.lower(currentZone), query) then
                table.insert(matched, {
                    rawName = playerName,
                    fullName = myFullName,
                    class = pClass or "",
                    classColor = colorHex,
                    isIC = isIC,
                    isOnline = true,
                    statusRank = isIC and 1 or 2,
                    zone = currentZone
                })
                totalFound = totalFound + 1
                onlineCount = onlineCount + 1
            end
        end
    end

    table.sort(matched, function(a, b)
        local rawA = a.rawName or ""
        local rawB = b.rawName or ""
        local nameA = string.lower((a.fullName and a.fullName ~= "") and a.fullName or rawA)
        local nameB = string.lower((b.fullName and b.fullName ~= "") and b.fullName or rawB)
        local rankA = a.statusRank or 99
        local rankB = b.statusRank or 99
        local zoneA = string.lower(a.zone or "")
        local zoneB = string.lower(b.zone or "")

        if Directory.sortField == "status" then
            if rankA ~= rankB then
                if Directory.sortAsc then
                    return rankA < rankB
                else
                    return rankA > rankB
                end
            end
            if nameA ~= nameB then
                return nameA < nameB
            end
            return rawA < rawB
        elseif Directory.sortField == "name" then
            if nameA ~= nameB then
                if Directory.sortAsc then
                    return nameA < nameB
                else
                    return nameA > nameB
                end
            end
            if rankA ~= rankB then
                return rankA < rankB
            end
            return rawA < rawB
        elseif Directory.sortField == "zone" then
            if zoneA ~= zoneB then
                if Directory.sortAsc then
                    return zoneA < zoneB
                else
                    return zoneA > zoneB
                end
            end
            if nameA ~= nameB then
                return nameA < nameB
            end
            return rawA < rawB
        end

        if rankA ~= rankB then
            return rankA < rankB
        end
        return rawA < rawB
    end)

    f.matchedItems = matched

    local function GetSortArrow(field)
        if Directory.sortField == field then
            return Directory.sortAsc and " |cff00e5ff▲|r" or " |cff00e5ff▼|r"
        end
        return ""
    end

    if f.btnStatus then f.btnStatus.text:SetText("Status" .. GetSortArrow("status")) end
    if f.btnName then f.btnName.text:SetText("Roleplayer / Full Name" .. GetSortArrow("name")) end
    if f.btnZone then f.btnZone.text:SetText("Current Zone / Vicinity" .. GetSortArrow("zone")) end

    if f.totalText then
        f.totalText:SetText("|cff00ccff" .. table.getn(matched) .. "|r shown (|cff00ff66" .. onlineCount .. " online|r)")
    end

    local totalMatched = table.getn(matched)
    local maxOffset = math.max(0, totalMatched - VISIBLE_ROWS)
    f.scrollbar:SetMinMaxValues(0, maxOffset)
    if f.currentOffset > maxOffset then
        f.currentOffset = maxOffset
    end
    f.scrollbar:SetValue(f.currentOffset)

    self:UpdateScroll(f.currentOffset)
end

function Directory:UpdateScroll(offset)
    local f = self:BuildFrame()
    f.currentOffset = offset or 0
    local matched = f.matchedItems or {}
    local playerName = UnitName("player")
    local myZone = GetZoneText() or ""
    if myZone == "" then myZone = GetMinimapZoneText() or GetRealZoneText() or "" end

    for i = 1, VISIBLE_ROWS do
        local row = f.rows[i]
        local itemIdx = f.currentOffset + i
        local item = matched[itemIdx]

        if item then
            row.targetPlayerName = item.rawName

            if Directory.selectedPlayer == item.rawName then
                row:SetBackdropColor(0.08, 0.18, 0.28, 0.95)
                row:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
            else
                row:SetBackdropColor(0.04, 0.04, 0.05, (math.mod(i, 2) == 0) and 0.85 or 0.45)
                row:SetBackdropBorderColor(0.14, 0.14, 0.17, 1.0)
            end

            local statusText = not item.isOnline and "|cff777788○ Off|r" or (item.isIC and "|cff00ff88● IC|r" or "|cffffaa00● OOC|r")
            row.statusTxt:SetText(statusText)

            local colorHex = item.classColor or "FFFFFF"
            local displayName = "|cff" .. colorHex .. item.fullName .. "|r"
            if item.fullName ~= item.rawName then
                displayName = displayName .. " |cff666677(" .. item.rawName .. ")|r"
            end
            row.nameTxt:SetText(displayName)

            local displayZone = PUIRoleplay.Protocols and PUIRoleplay.Protocols.DrunkDecode and PUIRoleplay.Protocols:DrunkDecode(item.zone or "") or (item.zone or "")
            if item.rawName == playerName and (not displayZone or displayZone == "" or displayZone == "Unknown") then
                displayZone = myZone
            end
            row.zoneTxt:SetText((displayZone and displayZone ~= "") and displayZone or "|cff555555Unknown|r")
            row:Show()
        else
            row.targetPlayerName = nil
            row:Hide()
        end
    end
end

function PUIRoleplay:OpenDirectory()
    local f = Directory:BuildFrame()
    f:Show()
    PUIRoleplay.Comms:SendPing("P")
    Directory:RefreshList(f.searchEB and f.searchEB:GetText() or "")
end
