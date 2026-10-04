--[[
    PrimusUI: PUIRoleplay Directory Profile Flyout Sidecar (PUIDirFlyout.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (Multi-Tab Character Detail Drawer)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIRoleplay = Primus.PUIRoleplay or {}
Primus.PUIRoleplay = PUIRoleplay

local Directory = PUIRoleplay.Directory or {}
PUIRoleplay.Directory = Directory

local flyoutTraitRows = {}

--------------------------------------------------------------------------------
-- Build Right-Hand Profile Discovery Flyout Sidecar
--------------------------------------------------------------------------------
function Directory:BuildFlyout(parent)
    local flyout = CreateFrame("Frame", "Primus_PUIRoleplay_DirFlyout", parent)
    flyout:SetWidth(440)
    flyout:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, 0)
    flyout:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", 2, 0)
    flyout:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    flyout:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
    flyout:SetBackdropBorderColor(0.20, 0.22, 0.28, 1.0)
    flyout:EnableMouse(true)
    flyout:Hide()
    parent.flyout = flyout

    -- Title Bar
    local titleBar = CreateFrame("Frame", nil, flyout)
    titleBar:SetPoint("TOPLEFT", flyout, "TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", flyout, "TOPRIGHT", -1, -1)
    titleBar:SetHeight(28)
    titleBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    titleBar:SetBackdropColor(0.11, 0.12, 0.15, 1.0)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleText:SetText("|cffffd100DISCOVERY PROFILE DETAIL|r")

    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetWidth(18)
    closeBtn:SetHeight(18)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
    closeBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    closeBtn:SetBackdropColor(0.4, 0.1, 0.1, 0.9)
    closeBtn:SetBackdropBorderColor(0.8, 0.2, 0.2, 1.0)
    local cbText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cbText:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    cbText:SetText("x")
    closeBtn:SetScript("OnClick", function()
        flyout:Hide()
        Directory.selectedPlayer = nil
        Directory:RefreshList()
    end)

    -- Quick Action Buttons in Title Bar
    local whisperBtn = CreateFrame("Button", nil, titleBar)
    whisperBtn:SetWidth(60)
    whisperBtn:SetHeight(18)
    whisperBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    whisperBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    whisperBtn:SetBackdropColor(0.08, 0.18, 0.28, 0.95)
    whisperBtn:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
    local wbText = whisperBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    wbText:SetPoint("CENTER", whisperBtn, "CENTER", 0, 0)
    wbText:SetText("Whisper")
    whisperBtn:SetScript("OnClick", function()
        if Directory.selectedPlayer then
            ChatFrame_OpenChat("/w " .. Directory.selectedPlayer .. " ")
        end
    end)

    local targetBtn = CreateFrame("Button", nil, titleBar)
    targetBtn:SetWidth(50)
    targetBtn:SetHeight(18)
    targetBtn:SetPoint("RIGHT", whisperBtn, "LEFT", -4, 0)
    targetBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    targetBtn:SetBackdropColor(0.08, 0.18, 0.28, 0.95)
    targetBtn:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
    local tbText = targetBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tbText:SetPoint("CENTER", targetBtn, "CENTER", 0, 0)
    tbText:SetText("Target")
    targetBtn:SetScript("OnClick", function()
        if Directory.selectedPlayer then
            TargetByName(Directory.selectedPlayer, true)
        end
    end)

    -- Header Info Box (Avatar, Full Name, Title, Demographics)
    local headerBox = CreateFrame("Frame", nil, flyout)
    headerBox:SetPoint("TOPLEFT", flyout, "TOPLEFT", 8, -32)
    headerBox:SetPoint("TOPRIGHT", flyout, "TOPRIGHT", -8, -32)
    headerBox:SetHeight(82)
    headerBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    headerBox:SetBackdropColor(0.08, 0.08, 0.11, 0.95)
    headerBox:SetBackdropBorderColor(0.25, 0.25, 0.30, 1.0)

    local avatarIcon = CreateFrame("Frame", nil, headerBox)
    avatarIcon:SetWidth(56)
    avatarIcon:SetHeight(56)
    avatarIcon:SetPoint("TOPLEFT", headerBox, "TOPLEFT", 8, -8)
    avatarIcon:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    avatarIcon:SetBackdropColor(0, 0, 0, 1)
    avatarIcon:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)

    local avatarTex = avatarIcon:CreateTexture(nil, "ARTWORK")
    avatarTex:SetPoint("TOPLEFT", avatarIcon, "TOPLEFT", 1, -1)
    avatarTex:SetPoint("BOTTOMRIGHT", avatarIcon, "BOTTOMRIGHT", -1, 1)
    avatarTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    flyout.avatarTex = avatarTex

    local nameStr = headerBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameStr:SetPoint("TOPLEFT", avatarIcon, "TOPRIGHT", 10, -2)
    nameStr:SetText("Character Name")
    flyout.nameStr = nameStr

    local titleStr = headerBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    titleStr:SetPoint("TOPLEFT", nameStr, "BOTTOMLEFT", 0, -2)
    titleStr:SetText("<No Title>")
    flyout.titleStr = titleStr

    local demoTags = headerBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    demoTags:SetPoint("TOPLEFT", titleStr, "BOTTOMLEFT", 0, -4)
    demoTags:SetText("|cff00ccff[Age 25]|r |cffff80cc[Bisexual]|r |cffff0000[LGBTQIA+]|r")
    flyout.demoTags = demoTags

    local statusPill = CreateFrame("Frame", nil, headerBox)
    statusPill:SetWidth(100)
    statusPill:SetHeight(18)
    statusPill:SetPoint("TOPRIGHT", headerBox, "TOPRIGHT", -8, -8)
    statusPill:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    local statusPillText = statusPill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusPillText:SetPoint("CENTER", statusPill, "CENTER", 0, 0)
    statusPill.text = statusPillText
    flyout.statusPill = statusPill

    -- Flyout 5 Tabs: Appearance (1), Traits (2), Style & ERP (3), Lore (4), Notes (5)
    local tabNames = { "Appearance", "Traits", "Style/ERP", "Lore", "Notes" }
    local tabs = {}
    local tabW = 82
    for i = 1, 5 do
        local tBtn = CreateFrame("Button", nil, flyout)
        tBtn:SetWidth(tabW)
        tBtn:SetHeight(22)
        tBtn:SetPoint("TOPLEFT", flyout, "TOPLEFT", 8 + (i - 1) * (tabW + 3), -120)
        tBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 0 }
        })
        tBtn:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
        tBtn:SetBackdropBorderColor(0.22, 0.24, 0.28, 1.0)

        local tTxt = tBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tTxt:SetPoint("CENTER", tBtn, "CENTER", 0, 0)
        tTxt:SetText(tabNames[i])
        tBtn.text = tTxt
        tBtn.tabIdx = i

        tBtn:SetScript("OnClick", function()
            Directory:SelectFlyoutTab(this.tabIdx)
        end)
        tabs[i] = tBtn
    end
    flyout.tabs = tabs

    -- Content Container Box
    local contentBox = CreateFrame("Frame", nil, flyout)
    contentBox:SetPoint("TOPLEFT", flyout, "TOPLEFT", 8, -142)
    contentBox:SetPoint("BOTTOMRIGHT", flyout, "BOTTOMRIGHT", -8, 8)
    contentBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    contentBox:SetBackdropColor(0.04, 0.04, 0.06, 0.95)
    contentBox:SetBackdropBorderColor(0.18, 0.20, 0.24, 1.0)
    flyout.contentBox = contentBox

    -- Panel 1: Glances & Appearance
    local p1 = CreateFrame("Frame", nil, contentBox)
    p1:SetAllPoints(contentBox)
    flyout.p1 = p1

    local lfBadgeDisplay = p1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lfBadgeDisplay:SetPoint("TOPLEFT", p1, "TOPLEFT", 8, -8)
    lfBadgeDisplay:SetWidth(408)
    lfBadgeDisplay:SetJustifyH("LEFT")
    p1.lfBadgeDisplay = lfBadgeDisplay

    p1.glanceCards = {}
    for i = 1, 5 do
        local gCard = CreateFrame("Frame", nil, p1)
        gCard:SetWidth(408)
        gCard:SetHeight(48)
        gCard:SetPoint("TOPLEFT", p1, "TOPLEFT", 8, -32 - (i - 1) * 52)
        gCard:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        gCard:SetBackdropColor(0.06, 0.06, 0.08, 0.9)
        gCard:SetBackdropBorderColor(0.20, 0.22, 0.26, 1.0)

        local gIcon = gCard:CreateTexture(nil, "ARTWORK")
        gIcon:SetWidth(32)
        gIcon:SetHeight(32)
        gIcon:SetPoint("TOPLEFT", gCard, "TOPLEFT", 6, -8)
        gIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        gCard.icon = gIcon

        local gTitle = gCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        gTitle:SetPoint("TOPLEFT", gIcon, "TOPRIGHT", 6, 0)
        gTitle:SetPoint("TOPRIGHT", gCard, "TOPRIGHT", -6, 0)
        gTitle:SetJustifyH("LEFT")
        gCard.title = gTitle

        local gDesc = gCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        gDesc:SetPoint("TOPLEFT", gTitle, "BOTTOMLEFT", 0, -2)
        gDesc:SetPoint("BOTTOMRIGHT", gCard, "BOTTOMRIGHT", -6, 4)
        gDesc:SetJustifyH("LEFT")
        gCard.desc = gDesc

        p1.glanceCards[i] = gCard
    end

    -- Panel 2: Personality Spectrum Traits
    local p2 = CreateFrame("Frame", nil, contentBox)
    p2:SetAllPoints(contentBox)
    p2:Hide()
    flyout.p2 = p2

    local p2Scroll = CreateFrame("ScrollFrame", "Primus_PUIRoleplay_FlyoutTraitScroll", p2, "UIPanelScrollFrameTemplate")
    p2Scroll:SetPoint("TOPLEFT", p2, "TOPLEFT", 4, -4)
    p2Scroll:SetPoint("BOTTOMRIGHT", p2, "BOTTOMRIGHT", -22, 4)

    local p2Child = CreateFrame("Frame", nil, p2Scroll)
    p2Child:SetWidth(390)
    p2Child:SetHeight(500)
    p2Scroll:SetScrollChild(p2Child)
    p2.scrollChild = p2Child

    -- Panel 3: Style & ERP
    local p3 = CreateFrame("Frame", nil, contentBox)
    p3:SetAllPoints(contentBox)
    p3:Hide()
    flyout.p3 = p3

    p3.styleRows = {}
    local styleMeta = {
        { key = "relationship_status", label = "Relationship Status" },
        { key = "walkup_policy", label = "Walk-Up Preferences" },
        { key = "combat_preference", label = "Combat & Conflict Resolution" },
        { key = "injury_consent", label = "Injury Tolerance" },
        { key = "permadeath_consent", label = "Permadeath Willingness" },
        { key = "experience_level", label = "RP Experience Level" },
        { key = "erp_preference", label = "Adult / ERP Preference" },
        { key = "ooc_boundaries", label = "OOC Safety & Boundaries" }
    }

    for idx, item in ipairs(styleMeta) do
        local sCard = CreateFrame("Frame", nil, p3)
        sCard:SetWidth(408)
        sCard:SetHeight(32)
        sCard:SetPoint("TOPLEFT", p3, "TOPLEFT", 8, -6 - (idx - 1) * 36)
        sCard:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        sCard:SetBackdropColor(0.06, 0.06, 0.08, 0.85)
        sCard:SetBackdropBorderColor(0.20, 0.22, 0.26, 1.0)

        local lbl = sCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", sCard, "LEFT", 8, 0)
        lbl:SetText("|cff00e5ff" .. item.label .. ":|r")

        local val = sCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        val:SetPoint("RIGHT", sCard, "RIGHT", -8, 0)
        val:SetText("Unknown")
        sCard.valTxt = val
        sCard.key = item.key

        table.insert(p3.styleRows, sCard)
    end

    -- Panel 4: Lore & History
    local p4 = CreateFrame("Frame", nil, contentBox)
    p4:SetAllPoints(contentBox)
    p4:Hide()
    flyout.p4 = p4

    local bioScroll = CreateFrame("ScrollFrame", "Primus_PUIRoleplay_FlyoutBioScroll", p4, "UIPanelScrollFrameTemplate")
    bioScroll:SetPoint("TOPLEFT", p4, "TOPLEFT", 8, -8)
    bioScroll:SetPoint("BOTTOMRIGHT", p4, "BOTTOMRIGHT", -24, 8)

    local bioChild = CreateFrame("Frame", nil, bioScroll)
    bioChild:SetWidth(380)
    bioChild:SetHeight(800)
    bioScroll:SetScrollChild(bioChild)

    local bioText = bioChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bioText:SetPoint("TOPLEFT", bioChild, "TOPLEFT", 0, 0)
    bioText:SetWidth(380)
    bioText:SetJustifyH("LEFT")
    bioText:SetText("Biography and history chronicles.")
    p4.bioText = bioText

    -- Panel 5: Private GM / Player Notes
    local p5 = CreateFrame("Frame", nil, contentBox)
    p5:SetAllPoints(contentBox)
    p5:Hide()
    flyout.p5 = p5

    local nHeader = p5:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nHeader:SetPoint("TOPLEFT", p5, "TOPLEFT", 8, -8)
    nHeader:SetText("|cffffd100YOUR PRIVATE NOTES ON THIS CHARACTER (Saved Locally):|r")

    local notesScroll = CreateFrame("ScrollFrame", "Primus_PUIRoleplay_FlyoutNotesScroll", p5, "UIPanelScrollFrameTemplate")
    notesScroll:SetPoint("TOPLEFT", nHeader, "BOTTOMLEFT", 0, -6)
    notesScroll:SetPoint("BOTTOMRIGHT", p5, "BOTTOMRIGHT", -24, 8)

    local notesEB = CreateFrame("EditBox", nil, notesScroll)
    notesEB:SetWidth(380)
    notesEB:SetHeight(800)
    notesEB:SetMultiLine(true)
    notesEB:SetAutoFocus(false)
    notesEB:SetFontObject(GameFontHighlightSmall)
    notesEB:SetTextColor(1.0, 1.0, 1.0, 1.0)
    notesEB:SetTextInsets(4, 4, 4, 4)
    notesScroll:SetScrollChild(notesEB)
    p5.notesEB = notesEB

    notesEB:SetScript("OnTextChanged", function()
        if ScrollingEdit_OnTextChanged then ScrollingEdit_OnTextChanged(notesScroll) end
        if Directory.selectedPlayer and flyout.isRefreshing ~= true then
            PUIRoleplay:SetCharacterNote(Directory.selectedPlayer, this:GetText())
        end
    end)
end

function Directory:SelectFlyoutTab(index)
    Directory.activeFlyoutTab = index
    local f = Directory:BuildFrame()
    local flyout = f.flyout
    if not flyout then return end

    for i = 1, 5 do
        local tab = flyout.tabs[i]
        if tab then
            if i == index then
                tab:SetBackdropColor(0.16, 0.18, 0.24, 1.0)
                tab:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
                tab.text:SetTextColor(0.0, 0.90, 1.0)
            else
                tab:SetBackdropColor(0.06, 0.06, 0.08, 0.9)
                tab:SetBackdropBorderColor(0.20, 0.22, 0.26, 1.0)
                tab.text:SetTextColor(0.70, 0.70, 0.75)
            end
        end
    end

    if flyout.p1 then flyout.p1:Hide() end
    if flyout.p2 then flyout.p2:Hide() end
    if flyout.p3 then flyout.p3:Hide() end
    if flyout.p4 then flyout.p4:Hide() end
    if flyout.p5 then flyout.p5:Hide() end

    if index == 1 and flyout.p1 then flyout.p1:Show()
    elseif index == 2 and flyout.p2 then flyout.p2:Show()
    elseif index == 3 and flyout.p3 then flyout.p3:Show()
    elseif index == 4 and flyout.p4 then flyout.p4:Show()
    elseif index == 5 and flyout.p5 then flyout.p5:Show()
    end
end

function Directory:ShowPlayerFlyout(charName)
    if not charName then return end
    local f = Directory:BuildFrame()
    Directory.selectedPlayer = charName

    if PUIRoleplay.Comms and PUIRoleplay.Comms.SendRequest then
        PUIRoleplay.Comms:SendRequest("M", charName)
        PUIRoleplay.Comms:SendRequest("T", charName)
        PUIRoleplay.Comms:SendRequest("D", charName)
        PUIRoleplay.Comms:SendRequest("L", charName)
        PUIRoleplay.Comms:SendRequest("X", charName)
        PUIRoleplay.Comms:SendRequest("P", charName)
    end

    Directory:RefreshFlyout()
    f.flyout:Show()
    Directory:RefreshList()
end

function Directory:RefreshFlyout()
    local f = Directory:BuildFrame()
    local flyout = f.flyout
    if not flyout or not Directory.selectedPlayer then return end

    local name = Directory.selectedPlayer
    local isSelf = (name == UnitName("player"))
    local data = isSelf and PUIRoleplay:GetMyProfile() or PUIRoleplay:GetCharacterData(name)
    if not data then return end

    flyout.isRefreshing = true

    local iconIdx = tonumber(data.icon) or 1
    flyout.avatarTex:SetTexture("Interface\\Icons\\" .. (PUIRoleplay.Icons[iconIdx] or "INV_Misc_QuestionMark"))

    local colorHex = data.class_color or (PUIRoleplay.ClassData and data.class and PUIRoleplay.ClassData[data.class] and PUIRoleplay.ClassData[data.class][4]) or "00ccff"
    local fullName = PUIRoleplay:ComposeFullName(data)
    if fullName == "" then fullName = name end
    flyout.nameStr:SetText("|cff" .. colorHex .. fullName .. "|r")

    local titleStr = PUIRoleplay:ComposeTitle(data)
    if titleStr ~= "" then
        flyout.titleStr:SetText("<" .. titleStr .. ">")
    else
        flyout.titleStr:SetText("|cff888888" .. name .. "|r")
    end

    local age = (data.apparent_age and data.apparent_age ~= "") and data.apparent_age or "Age ?"
    local sex = (data.biological_sex and data.biological_sex ~= "") and data.biological_sex or nil
    local gender = (data.gender_identity and data.gender_identity ~= "") and data.gender_identity or nil
    local icPr = (data.ic_pronouns and data.ic_pronouns ~= "") and ("(" .. data.ic_pronouns .. ")") or ""
    local ori = (data.show_orientation ~= false and data.orientation and data.orientation ~= "") and data.orientation or nil
    local lgbtq = (data.lgbtqia_friendly ~= false) and " |cffff0000[|cffff7f00LGBTQIA+|cff9400d3]|r" or ""
    local adult18 = (data.adult_18plus_flag == true) and " |cffff3355[18+]|r" or ""

    local tagList = {}
    table.insert(tagList, "|cff00ccff" .. age .. "|r")
    if sex then table.insert(tagList, "|cffffd100" .. sex .. "|r") end
    if gender then table.insert(tagList, "|cff00ffaa" .. gender .. "|r") end
    if icPr ~= "" then table.insert(tagList, "|cffffffff" .. icPr .. "|r") end
    if ori then table.insert(tagList, "|cffff80cc" .. ori .. "|r") end

    local tagStr = table.concat(tagList, " | ") .. lgbtq .. adult18
    flyout.demoTags:SetText(tagStr)

    local isOnline = isSelf or PUIRoleplay:IsPlayerOnline(name)
    local isIC = (data.currently_ic == "1")
    if not isOnline then
        flyout.statusPill:SetBackdropColor(0.25, 0.25, 0.28, 0.9)
        flyout.statusPill:SetBackdropBorderColor(0.4, 0.4, 0.45, 1.0)
        flyout.statusPill.text:SetText("|cff888888OFFLINE|r")
    elseif isIC then
        flyout.statusPill:SetBackdropColor(0.08, 0.45, 0.15, 0.9)
        flyout.statusPill:SetBackdropBorderColor(0.2, 0.85, 0.3, 1.0)
        flyout.statusPill.text:SetText("|cff40ff66IN CHARACTER|r")
    else
        flyout.statusPill:SetBackdropColor(0.45, 0.25, 0.05, 0.9)
        flyout.statusPill:SetBackdropBorderColor(0.85, 0.5, 0.15, 1.0)
        flyout.statusPill.text:SetText("|cffffaa00OUT OF CHAR|r")
    end

    -- Tab 1: Glances
    local lfStr = "Looking For:"
    local lf = data.looking_for or {}
    if lf.adventure then lfStr = lfStr .. " |cff00ff88[Adventure]|r" end
    if lf.romance then lfStr = lfStr .. " |cffff80cc[Romance]|r" end
    if lf.casual_tavern then lfStr = lfStr .. " |cffffcc00[Tavern]|r" end
    if lf.combat then lfStr = lfStr .. " |cffff4444[Combat]|r" end
    if lf.political_guild then lfStr = lfStr .. " |cff00ccff[Guild]|r" end
    if lf.mentorship then lfStr = lfStr .. " |cffb080ff[Mentorship]|r" end
    flyout.p1.lfBadgeDisplay:SetText(lfStr)

    for i = 1, 5 do
        local gCard = flyout.p1.glanceCards[i]
        local glance = (data.glances and data.glances[i]) or {}
        local rawTitle = glance.title or data["atAGlance" .. i .. "Title"] or ""
        local rawText = glance.text or data["atAGlance" .. i] or ""
        local gTitle = PUIRoleplay:UnescapeRPText(rawTitle)
        local gText = PUIRoleplay:UnescapeRPText(rawText)
        local gIcon = glance.icon or ""
        local gIconIdx = tonumber(data["atAGlance" .. i .. "Icon"]) or 0

        if gIcon ~= "" then
            gCard.icon:SetTexture("Interface\\Icons\\" .. gIcon)
        elseif gIconIdx > 0 and PUIRoleplay.Icons[gIconIdx] then
            gCard.icon:SetTexture("Interface\\Icons\\" .. PUIRoleplay.Icons[gIconIdx])
        else
            gCard.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end

        if gTitle ~= "" or gText ~= "" then
            gCard.title:SetText("|cffffd100" .. gTitle .. "|r")
            gCard.desc:SetText(gText)
            gCard:Show()
        else
            gCard.title:SetText("|cff666666(Empty Glance Slot " .. i .. ")|r")
            gCard.desc:SetText("")
            gCard:Show()
        end
    end

    -- Tab 2: Personality Spectrum Traits
    local traits = PUIRoleplay:GetPersonalityTraits(data)
    local p2Child = flyout.p2.scrollChild
    for _, r in ipairs(flyoutTraitRows) do r:Hide() end

    local trackW = 140
    local rH = 38
    p2Child:SetHeight(math.max(300, table.getn(traits) * rH + 10))

    for idx, t in ipairs(traits) do
        local r = flyoutTraitRows[idx]
        if not r then
            r = CreateFrame("Frame", nil, p2Child)
            r:SetWidth(380)
            r:SetHeight(rH - 4)
            r:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false, tileSize = 0, edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 }
            })
            r:SetBackdropColor(0.06, 0.06, 0.08, 0.85)
            r:SetBackdropBorderColor(0.18, 0.20, 0.24, 1.0)

            local lIcon = r:CreateTexture(nil, "ARTWORK")
            lIcon:SetWidth(22)
            lIcon:SetHeight(22)
            lIcon:SetPoint("LEFT", r, "LEFT", 4, 0)
            r.lIcon = lIcon

            local lTxt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            lTxt:SetPoint("LEFT", lIcon, "RIGHT", 4, 0)
            lTxt:SetWidth(75)
            lTxt:SetJustifyH("LEFT")
            r.lTxt = lTxt

            local trk = CreateFrame("Frame", nil, r)
            trk:SetWidth(trackW)
            trk:SetHeight(12)
            trk:SetPoint("LEFT", lTxt, "RIGHT", 4, 0)
            trk:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false, tileSize = 0, edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 }
            })
            trk:SetBackdropColor(0.03, 0.03, 0.05, 1.0)
            trk:SetBackdropBorderColor(0.28, 0.28, 0.35, 1.0)
            r.trk = trk

            local lFill = trk:CreateTexture(nil, "BORDER")
            lFill:SetTexture(0.0, 0.75, 1.0, 0.65)
            trk.lFill = lFill

            local rFill = trk:CreateTexture(nil, "BORDER")
            rFill:SetTexture(1.0, 0.65, 0.1, 0.65)
            trk.rFill = rFill

            local thumb = CreateFrame("Frame", nil, trk)
            thumb:SetWidth(6)
            thumb:SetHeight(16)
            thumb:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false, tileSize = 0, edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 }
            })
            thumb:SetBackdropColor(1, 1, 1, 0.95)
            thumb:SetBackdropBorderColor(0, 0.85, 1, 1)
            trk.thumb = thumb

            local rTxt = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rTxt:SetPoint("LEFT", trk, "RIGHT", 4, 0)
            rTxt:SetWidth(75)
            rTxt:SetJustifyH("RIGHT")
            r.rTxt = rTxt

            local rIcon = r:CreateTexture(nil, "ARTWORK")
            rIcon:SetWidth(22)
            rIcon:SetHeight(22)
            rIcon:SetPoint("LEFT", rTxt, "RIGHT", 4, 0)
            r.rIcon = rIcon

            flyoutTraitRows[idx] = r
        end

        r:SetPoint("TOPLEFT", p2Child, "TOPLEFT", 0, -((idx - 1) * rH))
        r:Show()

        r.lIcon:SetTexture("Interface\\Icons\\" .. (t.leftIcon or "INV_Misc_QuestionMark"))
        r.rIcon:SetTexture("Interface\\Icons\\" .. (t.rightIcon or "INV_Misc_QuestionMark"))
        r.lTxt:SetText(t.leftName or "Left")
        r.rTxt:SetText(t.rightName or "Right")

        local val = math.max(0, math.min(20, tonumber(t.value) or 10))
        local frac = val / 20.0
        local thumbX = math.floor(frac * trackW)
        local midX = math.floor(trackW / 2)

        r.trk.thumb:SetPoint("CENTER", r.trk, "LEFT", thumbX, 0)
        if val < 10 then
            r.trk.rFill:Hide()
            r.trk.lFill:ClearAllPoints()
            r.trk.lFill:SetPoint("TOPLEFT", r.trk, "LEFT", thumbX, 5)
            r.trk.lFill:SetPoint("BOTTOMRIGHT", r.trk, "LEFT", midX, -5)
            r.trk.lFill:Show()
        elseif val > 10 then
            r.trk.lFill:Hide()
            r.trk.rFill:ClearAllPoints()
            r.trk.rFill:SetPoint("TOPLEFT", r.trk, "LEFT", midX, 5)
            r.trk.rFill:SetPoint("BOTTOMRIGHT", r.trk, "LEFT", thumbX, -5)
            r.trk.rFill:Show()
        else
            r.trk.lFill:Hide()
            r.trk.rFill:Hide()
        end
    end

    -- Tab 3: Style
    for _, sCard in ipairs(flyout.p3.styleRows) do
        local val = data[sCard.key] or "Not Specified"
        sCard.valTxt:SetText("|cffffffff" .. PUIRoleplay:UnescapeRPText(tostring(val)) .. "|r")
    end

    -- Tab 4: Lore
    local bioStr = ""
    if data.motto and data.motto ~= "" then
        bioStr = bioStr .. "|cffffd100Motto:|r \"" .. PUIRoleplay:UnescapeRPText(data.motto) .. "\"\n\n"
    end
    if data.birth_city and data.birth_city ~= "" then
        bioStr = bioStr .. "|cff00e5ffBirthplace:|r " .. PUIRoleplay:UnescapeRPText(data.birth_city) .. "    |cff00e5ffHome:|r " .. PUIRoleplay:UnescapeRPText(data.home_city or "") .. "\n\n"
    end
    if data.history then
        for chIdx = 1, 6 do
            local chText = data.history["chapter" .. chIdx]
            if chText and chText ~= "" then
                bioStr = bioStr .. "|cff00e5ff--- Chapter " .. chIdx .. " ---|r\n" .. PUIRoleplay:UnescapeRPText(chText) .. "\n\n"
            end
        end
    end
    if bioStr == "" then
        bioStr = PUIRoleplay:UnescapeRPText(data.description or "No detailed biography recorded.")
    end
    flyout.p4.bioText:SetText(bioStr)
    if flyout.p4.bioText.GetStringHeight then
        local neededH = math.max(400, flyout.p4.bioText:GetStringHeight() + 40)
        local bioChild = flyout.p4.bioText:GetParent()
        if bioChild then bioChild:SetHeight(neededH) end
    end

    -- Tab 5: Notes
    flyout.p5.notesEB:SetText(PUIRoleplay:GetCharacterNote(name) or "")

    Directory:SelectFlyoutTab(Directory.activeFlyoutTab or 1)
    flyout.isRefreshing = false
end
