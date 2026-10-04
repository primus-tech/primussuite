--[[
    PrimusUI: PUIRoleplay Target At-A-Glance HUD Pill (PUIGlance.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (PrimusUI Dark Glassmorphism)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIRoleplay = Primus.PUIRoleplay or {}
Primus.PUIRoleplay = PUIRoleplay

local Glance = {}
PUIRoleplay.Glance = Glance

local glanceFrame = nil

--------------------------------------------------------------------------------
-- Build Target Glance HUD Pill Frame (5 Glance Slots)
--------------------------------------------------------------------------------
function Glance:BuildFrame()
    if glanceFrame then return glanceFrame end

    local f = CreateFrame("Frame", "Primus_PUIRoleplay_GlanceBar", UIParent)
    f:SetWidth(320)
    f:SetHeight(34)
    f:SetPoint("BOTTOM", TargetFrame or UIParent, "TOP", 0, 10)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:Hide()

    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    f:SetBackdropColor(0.06, 0.06, 0.08, 0.92)
    f:SetBackdropBorderColor(0.25, 0.25, 0.30, 1.0)

    if Primus.PUIMover then
        Primus.PUIMover:Register(f, "PUIRPGlance", "Target RP Glance Bar", "SOCIAL")
    end

    -- Target RP Name
    local nameText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", f, "LEFT", 8, 0)
    nameText:SetText("Target Name")
    f.nameText = nameText

    -- IC / OOC Status Badge
    local icBadge = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    icBadge:SetPoint("LEFT", nameText, "RIGHT", 6, 0)
    icBadge:SetText("[IC]")
    f.icBadge = icBadge

    -- 5 At-A-Glance Action/Icon Buttons
    f.glanceBtns = {}
    for i = 1, 5 do
        local btn = CreateFrame("Button", nil, f)
        btn:SetWidth(22)
        btn:SetHeight(22)
        btn:SetPoint("RIGHT", f, "RIGHT", -48 - (5 - i) * 25, 0)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        btn:SetBackdropColor(0, 0, 0, 1)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        btn.tex = tex
        btn.index = i

        btn:SetScript("OnEnter", function()
            this:SetBackdropBorderColor(0.0, 0.8, 1.0, 1.0)
            if this.title and this.title ~= "" then
                GameTooltip:SetOwner(this, "ANCHOR_TOP")
                GameTooltip:AddLine(this.title, 1.0, 0.85, 0.2)
                if this.desc and this.desc ~= "" then
                    GameTooltip:AddLine(this.desc, 0.9, 0.9, 0.9, true)
                end
                GameTooltip:Show()
            end
        end)

        btn:SetScript("OnLeave", function()
            this:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
            GameTooltip:Hide()
        end)

        f.glanceBtns[i] = btn
    end

    -- Quick [Bio] Button
    local bioBtn = CreateFrame("Button", nil, f)
    bioBtn:SetWidth(38)
    bioBtn:SetHeight(20)
    bioBtn:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    bioBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    bioBtn:SetBackdropColor(0.12, 0.12, 0.15, 0.9)
    bioBtn:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)

    local bioText = bioBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bioText:SetPoint("CENTER", bioBtn, "CENTER", 0, 0)
    bioText:SetText("Bio")
    bioBtn.text = bioText

    bioBtn:SetScript("OnClick", function()
        if UnitIsPlayer("target") then
            PUIRoleplay:OpenProfile(UnitName("target"))
        end
    end)
    bioBtn:SetScript("OnEnter", function()
        this:SetBackdropBorderColor(0.0, 0.8, 1.0, 1.0)
    end)
    bioBtn:SetScript("OnLeave", function()
        this:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
    end)
    f.bioBtn = bioBtn

    glanceFrame = f
    return f
end

--------------------------------------------------------------------------------
-- Target Update Handler
--------------------------------------------------------------------------------
function Glance:UpdateTarget()
    local f = self:BuildFrame()
    if not UnitIsPlayer("target") then
        f:Hide()
        return
    end

    local targetName = UnitName("target")
    local settings = PUIRoleplay:GetSettings() or {}
    if settings.bgs == "off" and IsInInstance() == "pvp" then
        f:Hide()
        return
    end

    if targetName ~= UnitName("player") and PUIRoleplay.Comms and PUIRoleplay.Comms.SendRequest then
        PUIRoleplay.Comms:SendRequest("T", targetName)
        PUIRoleplay.Comms:SendRequest("M", targetName)
    end

    self:RenderTargetData(targetName)
end

function Glance:RenderTargetData(targetName)
    local f = self:BuildFrame()
    local charData = (targetName == UnitName("player")) and PUIRoleplay:GetMyProfile() or PUIRoleplay:GetCharacterData(targetName)

    if not charData then
        f:Hide()
        return
    end

    local fullName = charData.full_name or targetName
    if charData.first_name and charData.first_name ~= "" then
        fullName = charData.first_name .. (charData.last_name and (" " .. charData.last_name) or "")
    end
    local classColor = charData.class_color or "FFFFFF"
    f.nameText:SetText("|cff" .. classColor .. fullName .. "|r")

    if charData.currently_ic == "1" then
        f.icBadge:SetText("|cff40ff66[IC]|r")
    elseif charData.currently_ic == "0" then
        f.icBadge:SetText("|cffffaa00[OOC]|r")
    else
        f.icBadge:SetText("")
    end

    -- Setup 5 Glance Buttons
    local visibleGlances = 0
    for i = 1, 5 do
        local btn = f.glanceBtns[i]
        local glance = (charData.glances and charData.glances[i]) or {}
        local rawTitle = glance.title or charData["atAGlance" .. i .. "Title"] or ""
        local rawDesc = glance.text or charData["atAGlance" .. i] or ""
        local title = PUIRoleplay.UnescapeRPText and PUIRoleplay:UnescapeRPText(rawTitle) or rawTitle
        local desc = PUIRoleplay.UnescapeRPText and PUIRoleplay:UnescapeRPText(rawDesc) or rawDesc
        local iconName = glance.icon or ""
        local iconIdx = tonumber(charData["atAGlance" .. i .. "Icon"]) or 0

        if iconName ~= "" then
            btn.tex:SetTexture("Interface\\Icons\\" .. iconName)
            btn.title = title
            btn.desc = desc
            btn:Show()
            visibleGlances = visibleGlances + 1
        elseif iconIdx > 0 and PUIRoleplay.Icons[iconIdx] then
            btn.tex:SetTexture("Interface\\Icons\\" .. PUIRoleplay.Icons[iconIdx])
            btn.title = title
            btn.desc = desc
            btn:Show()
            visibleGlances = visibleGlances + 1
        elseif title ~= "" then
            btn.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            btn.title = title
            btn.desc = desc
            btn:Show()
            visibleGlances = visibleGlances + 1
        else
            btn:Hide()
        end
    end

    local nameWidth = f.nameText:GetStringWidth() or 80
    local dynamicWidth = math.max(240, nameWidth + (visibleGlances * 26) + 70)
    f:SetWidth(dynamicWidth)
    f:Show()
end
