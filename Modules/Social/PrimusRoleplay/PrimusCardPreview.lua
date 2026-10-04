--[[
    PrimusUI: PUIRoleplay Matchmaking Profile Card Preview (PUICardPreview.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (Tinder/Bumble-Style Discovery Card)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIRoleplay = Primus.PUIRoleplay or {}
Primus.PUIRoleplay = PUIRoleplay

local Sheet = PUIRoleplay.Sheet or {}
PUIRoleplay.Sheet = Sheet

local cardPreviewFrame = nil

local function Create1PxBackdrop(parent, r, g, b, a, borderR, borderG, borderB, borderA)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    frame:SetBackdropColor(r or 0.08, g or 0.08, b or 0.10, a or 0.95)
    frame:SetBackdropBorderColor(borderR or 0.25, borderG or 0.25, borderB or 0.28, borderA or 1.0)
    return frame
end

function Sheet:OpenCardPreviewModal(targetName)
    local target = targetName or UnitName("player")
    local isSelf = (target == UnitName("player"))
    local data = isSelf and PUIRoleplay:GetMyProfile() or PUIRoleplay:GetCharacterData(target)
    if not data then data = {} end

    local parentFrame = Sheet:BuildFrame()
    if not cardPreviewFrame then
        local p = CreateFrame("Frame", "Primus_PUIRPSheet_CardPreview", parentFrame)
        p:SetWidth(380)
        p:SetHeight(480)
        p:SetPoint("CENTER", parentFrame, "CENTER", 0, 0)
        p:SetFrameStrata("DIALOG")
        p:EnableMouse(true)
        p:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        p:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
        p:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
        table.insert(UISpecialFrames, "Primus_PUIRPSheet_CardPreview")

        local closeBtn = CreateFrame("Button", nil, p)
        closeBtn:SetWidth(16)
        closeBtn:SetHeight(16)
        closeBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, -8)
        closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
        closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
        closeBtn:SetScript("OnClick", function() p:Hide() end)

        local avBg = Create1PxBackdrop(p, 0, 0, 0, 1, 0.35, 0.35, 0.45, 1)
        avBg:SetWidth(80)
        avBg:SetHeight(80)
        avBg:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -16)

        local avTex = avBg:CreateTexture(nil, "ARTWORK")
        avTex:SetPoint("TOPLEFT", avBg, "TOPLEFT", 2, -2)
        avTex:SetPoint("BOTTOMRIGHT", avBg, "BOTTOMRIGHT", -2, 2)
        p.avTex = avTex

        local nameText = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("TOPLEFT", avBg, "TOPRIGHT", 12, 0)
        p.nameText = nameText

        local titleText = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        titleText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
        titleText:SetTextColor(0.0, 0.85, 1.0)
        p.titleText = titleText

        local demoPill = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        demoPill:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -3)
        p.demoPill = demoPill

        local relText = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        relText:SetPoint("TOPLEFT", demoPill, "BOTTOMLEFT", 0, -3)
        p.relText = relText

        local sep = Create1PxBackdrop(p, 0.2, 0.25, 0.35, 0.8, 0, 0, 0, 0)
        sep:SetPoint("TOPLEFT", avBg, "BOTTOMLEFT", 0, -10)
        sep:SetWidth(348)
        sep:SetHeight(1)

        local lfHeader = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lfHeader:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 0, -8)
        lfHeader:SetText("|cffffd100Looking For Activities:|r")

        local lfBadges = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lfBadges:SetPoint("TOPLEFT", lfHeader, "BOTTOMLEFT", 0, -3)
        lfBadges:SetWidth(348)
        lfBadges:SetJustifyH("LEFT")
        p.lfBadges = lfBadges

        local bioHeader = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bioHeader:SetPoint("TOPLEFT", lfBadges, "BOTTOMLEFT", 0, -10)
        bioHeader:SetText("|cff00e5ffAbout & Glance:|r")

        local bioSummary = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bioSummary:SetPoint("TOPLEFT", bioHeader, "BOTTOMLEFT", 0, -3)
        bioSummary:SetWidth(348)
        bioSummary:SetJustifyH("LEFT")
        p.bioSummary = bioSummary

        cardPreviewFrame = p
    end

    local p = cardPreviewFrame
    local iconIdx = tonumber(data.icon) or 1
    p.avTex:SetTexture("Interface\\Icons\\" .. (PUIRoleplay.Icons[iconIdx] or "INV_Misc_QuestionMark"))

    local fullRPName = PUIRoleplay:ComposeFullName(data)
    if fullRPName == "" then fullRPName = target end
    p.nameText:SetText("|cffffffff" .. fullRPName .. "|r")

    local titleStr = PUIRoleplay:ComposeTitle(data)
    p.titleText:SetText((titleStr ~= "") and ("<" .. titleStr .. ">") or "")

    local tags = {}
    if data.apparent_age and data.apparent_age ~= "" then
        table.insert(tags, "|cff00ccff[" .. data.apparent_age .. "]|r")
    end
    if data.biological_sex and data.biological_sex ~= "" then
        table.insert(tags, "|cffffd100[" .. data.biological_sex .. "]|r")
    end
    if data.gender_identity and data.gender_identity ~= "" and data.gender_identity ~= data.biological_sex then
        table.insert(tags, "|cff00ffaa[" .. data.gender_identity .. "]|r")
    end
    local pr = (data.currently_ic == "1") and data.ic_pronouns or data.ooc_pronouns
    if pr and pr ~= "" then
        table.insert(tags, "|cffffcc80(" .. pr .. ")|r")
    end
    if data.show_orientation ~= false and data.orientation and data.orientation ~= "" then
        table.insert(tags, "|cffff80cc[" .. data.orientation .. "]|r")
    end

    local lgbtq = (data.lgbtqia_friendly ~= false) and " |cffff0000[|cffff7f00LGBTQIA+|cff9400d3]|r" or ""
    local adult18 = (data.adult_18plus_flag == true) and " |cffff3355[18+]|r" or ""
    p.demoPill:SetText(table.concat(tags, " ") .. lgbtq .. adult18)

    p.relText:SetText("Status: |cffffffff" .. (data.relationship_status or "Single") .. "|r")

    local lfStr = ""
    local lf = data.looking_for or {}
    if lf.adventure then lfStr = lfStr .. " |cff00ff88[Adventure]|r" end
    if lf.romance then lfStr = lfStr .. " |cffff80cc[Romance]|r" end
    if lf.casual_tavern then lfStr = lfStr .. " |cffffcc00[Tavern]|r" end
    if lf.combat then lfStr = lfStr .. " |cffff4444[Combat]|r" end
    if lf.political_guild then lfStr = lfStr .. " |cff00ccff[Guild]|r" end
    if lf.mentorship then lfStr = lfStr .. " |cffb080ff[Mentorship]|r" end
    if lfStr == "" then lfStr = "|cff888888No preferences listed|r" end
    p.lfBadges:SetText(lfStr)

    local rawDesc = (data.appearance_desc and data.appearance_desc ~= "") and data.appearance_desc or (data.description or "")
    local cleanDesc = PUIRoleplay.UnescapeRPText and PUIRoleplay:UnescapeRPText(rawDesc) or rawDesc
    if cleanDesc ~= "" then
        snippet = snippet .. string.sub(cleanDesc, 1, 200) .. (string.len(cleanDesc) > 200 and "..." or "")
    else
        snippet = snippet .. "No description provided."
    end
    p.bioSummary:SetText(snippet)

    p:Show()
end
