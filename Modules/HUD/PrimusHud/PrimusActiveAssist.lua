--[[
    PrimusUI Module: PUIHud - ActiveAssist Smart Action Buttons
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides context-driven smart action buttons:
    - Left ActiveAssist:  2-Click "Claim & Execute" Threat Peel (Red -> Amber -> Green)
    - Right ActiveAssist: 1-Click Main Tank Focus Fire Assist
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIHud = Primus.PUIHud or {}
Primus.PUIHud = PUIHud

local Media    = Primus.Media
local Tactical = Primus.PUITactical

local leftAssistBtn  = nil
local rightAssistBtn = nil

-- =========================================================================
-- ACTIVE-ASSIST BUTTONS BUILDER
-- =========================================================================

function PUIHud:BuildActiveAssist(parent, leftWing, rightWing)
    local wingW = leftWing:GetWidth()

    -- 1. Left ActiveAssist (Threat Peel & Rescue)
    leftAssistBtn = CreateFrame("Button", "Primus_PUIHud_LeftActiveAssist", parent)
    leftAssistBtn:SetWidth(wingW + 16)
    leftAssistBtn:SetHeight(32)
    leftAssistBtn:SetPoint("BOTTOMLEFT", leftWing, "TOPLEFT", -8, 8)
    leftAssistBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    leftAssistBtn:SetBackdropColor(0.90, 0.15, 0.15, 0.55)
    leftAssistBtn:SetBackdropBorderColor(1.0, 0.2, 0.2, 1.0)
    leftAssistBtn:RegisterForClicks("LeftButtonUp")

    local laText = leftAssistBtn:CreateFontString(nil, "OVERLAY")
    laText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    laText:SetPoint("TOP", leftAssistBtn, "TOP", 0, -4)
    laText:SetTextColor(1, 1, 1)
    leftAssistBtn.text = laText

    local laSub = leftAssistBtn:CreateFontString(nil, "OVERLAY")
    laSub:SetFont(Media:Fetch("font", "Default"), 7, "")
    laSub:SetPoint("BOTTOM", leftAssistBtn, "BOTTOM", 0, 3)
    laSub:SetTextColor(0.9, 0.9, 0.9)
    leftAssistBtn.subText = laSub

    leftAssistBtn:SetScript("OnClick", function()
        if Tactical then
            local alert, isClaimedByMe = Tactical:GetCurrentAlert()
            if alert then
                if alert.stage == 1 then
                    Tactical:ClaimRescue()
                elseif alert.stage == 2 and isClaimedByMe then
                    Tactical:ExecuteRescue()
                end
            end
        end
    end)

    leftAssistBtn:SetScript("OnEnter", function()
        if not Tactical or not Tactical.GetCurrentAlert then return end
        local alert, isClaimedByMe, claimedByOther = Tactical:GetCurrentAlert()
        if not alert then return end

        GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("PrimusUI ActiveAssist: Threat Peel", 1, 0.8, 0)
        GameTooltip:AddLine(string.format("Mob: |cffffffff%s|r", alert.mob or "Unknown"), 1, 0.3, 0.3)
        GameTooltip:AddLine(string.format("Victim: |cffffffff%s|r", alert.victim or "Unknown"), 0.3, 0.8, 1)
        if alert.stage == 1 then
            GameTooltip:AddLine("Status: |cffff4444Unclaimed|r (Click 1 to claim)", 1, 1, 1)
        elseif alert.stage == 2 then
            if isClaimedByMe then
                GameTooltip:AddLine("Status: |cffffff00Claimed by You|r (Click 2 to cast rescue)", 1, 1, 1)
            else
                GameTooltip:AddLine(string.format("Status: |cff888888Locked (Claimed by %s)|r", claimedByOther or "Raid"), 1, 1, 1)
            end
        elseif alert.stage == 3 then
            GameTooltip:AddLine("Status: |cff33ff33Resolved / Rescued|r", 0.2, 1.0, 0.2)
        end
        GameTooltip:Show()
    end)
    leftAssistBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    leftAssistBtn:Hide()

    -- 2. Right ActiveAssist (Main Tank Focus Fire)
    rightAssistBtn = CreateFrame("Button", "Primus_PUIHud_RightActiveAssist", parent)
    rightAssistBtn:SetWidth(wingW + 16)
    rightAssistBtn:SetHeight(32)
    rightAssistBtn:SetPoint("BOTTOMRIGHT", rightWing, "TOPRIGHT", 8, 8)
    rightAssistBtn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    rightAssistBtn:SetBackdropColor(0.15, 0.35, 0.65, 0.65)
    rightAssistBtn:SetBackdropBorderColor(0.3, 0.7, 1.0, 1.0)
    rightAssistBtn:RegisterForClicks("LeftButtonUp")

    local raText = rightAssistBtn:CreateFontString(nil, "OVERLAY")
    raText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    raText:SetPoint("TOP", rightAssistBtn, "TOP", 0, -4)
    raText:SetTextColor(1, 1, 1)
    rightAssistBtn.text = raText

    local raSub = rightAssistBtn:CreateFontString(nil, "OVERLAY")
    raSub:SetFont(Media:Fetch("font", "Default"), 7, "")
    raSub:SetPoint("BOTTOM", rightAssistBtn, "BOTTOM", 0, 3)
    raSub:SetTextColor(0.8, 0.9, 1.0)
    rightAssistBtn.subText = raSub

    rightAssistBtn:SetScript("OnClick", function()
        if rightAssistBtn.targetUnit and UnitExists(rightAssistBtn.targetUnit) then
            TargetUnit(rightAssistBtn.targetUnit)
        end
    end)

    rightAssistBtn:SetScript("OnEnter", function()
        if not rightAssistBtn.targetUnit or not UnitExists(rightAssistBtn.targetUnit) then return end
        GameTooltip:SetOwner(this, "ANCHOR_TOPRIGHT")
        GameTooltip:AddLine("PrimusUI ActiveAssist: Focus Fire", 0.3, 0.7, 1.0)
        GameTooltip:AddLine(string.format("Target: |cffffffff%s|r", UnitName(rightAssistBtn.targetUnit) or "Unknown"), 1, 1, 1)
        if rightAssistBtn.mtName then
            GameTooltip:AddLine(string.format("Main Tank: |cffffffff%s|r", rightAssistBtn.mtName), 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine("Click to snap target to Main Tank's target.", 0.2, 1.0, 0.4)
        GameTooltip:Show()
    end)
    rightAssistBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    rightAssistBtn:Hide()

    self.leftAssistBtn  = leftAssistBtn
    self.rightAssistBtn = rightAssistBtn
end

-- =========================================================================
-- ACTIVE-ASSIST REAL-TIME UPDATES
-- =========================================================================

function PUIHud:UpdateLeftActiveAssist()
    if not leftAssistBtn then return end

    if not Tactical or not Tactical.GetCurrentAlert then
        leftAssistBtn:Hide()
        return
    end

    local alert, isClaimedByMe, claimedByOther = Tactical:GetCurrentAlert()
    if not alert then
        leftAssistBtn:Hide()
        return
    end

    leftAssistBtn:Show()
    local classAction = Tactical.GetClassAction and Tactical:GetClassAction() or { primarySpell = "Taunt" }

    if alert.stage == 1 then
        -- 🔴 Stage 1: Alert / Unclaimed (Transparent Red)
        leftAssistBtn:SetBackdropColor(0.90, 0.15, 0.15, 0.55)
        leftAssistBtn:SetBackdropBorderColor(1.0, 0.2, 0.2, 1.0)
        leftAssistBtn.text:SetText(string.format("|cffff4444[PEEL]:|r %s", string.sub(alert.mob or "Target", 1, 12)))
        leftAssistBtn.subText:SetText("Click 1 to Claim")
    elseif alert.stage == 2 then
        if isClaimedByMe then
            -- 🟡 Stage 2: Claimed by Player (Glowing Amber)
            leftAssistBtn:SetBackdropColor(1.00, 0.75, 0.10, 0.75)
            leftAssistBtn:SetBackdropBorderColor(1.0, 0.9, 0.2, 1.0)
            leftAssistBtn.text:SetText(string.format("|cffffff00[EXECUTE]:|r %s", classAction.primarySpell))
            leftAssistBtn.subText:SetText("Click 2 to Cast")
        else
            -- Dimmed: Claimed by another group member
            leftAssistBtn:SetBackdropColor(0.20, 0.25, 0.35, 0.6)
            leftAssistBtn:SetBackdropBorderColor(0.4, 0.6, 0.8, 0.8)
            leftAssistBtn.text:SetText(string.format("[Claimed: %s]", claimedByOther or "Raid"))
            leftAssistBtn.subText:SetText("Locked")
        end
    elseif alert.stage == 3 then
        -- 🟢 Stage 3: Resolved / Success (Emerald Green)
        leftAssistBtn:SetBackdropColor(0.20, 0.85, 0.20, 0.85)
        leftAssistBtn:SetBackdropBorderColor(0.3, 1.0, 0.3, 1.0)
        leftAssistBtn.text:SetText("|cff33ff33[RESCUED!]|r")
        leftAssistBtn.subText:SetText("Aggro Peeled")
    end
end

function PUIHud:UpdateRightActiveAssist()
    if not rightAssistBtn then return end

    local mtUnit = nil
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local rName, rank, subgroup, level, class, fileName, zone, online, isDead, role = GetRaidRosterInfo(i)
            if role == "MAINTANK" or role == "MAINASSIST" then
                mtUnit = "raid" .. i
                break
            end
        end
    elseif GetNumPartyMembers() > 0 then
        mtUnit = "party1"
    end

    if mtUnit and UnitExists(mtUnit .. "target") then
        local tName = UnitName(mtUnit .. "target") or "MT Target"
        local tankName = UnitName(mtUnit) or "Tank"
        rightAssistBtn.targetUnit = mtUnit .. "target"
        rightAssistBtn.mtName = tankName
        rightAssistBtn.text:SetText(string.format("|cff33ccff[ASSIST]:|r %s", string.sub(tName, 1, 12)))
        rightAssistBtn.subText:SetText(string.format("MT: %s", tankName))
        rightAssistBtn:Show()
    else
        rightAssistBtn.targetUnit = nil
        rightAssistBtn.mtName = nil
        rightAssistBtn:Hide()
    end
end
