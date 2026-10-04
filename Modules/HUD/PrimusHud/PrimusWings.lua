--[[
    PrimusUI Module: PUIHud - Vertical Status Wings Engine
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides vertical, bottom-to-top status bars for Player & Target vitals
    (Health and Power) with class coloring, reaction colors, and level tags.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIHud = Primus.PUIHud or {}
Primus.PUIHud = PUIHud

local Widgets = Primus.Widgets
local Media   = Primus.Media
local Utils   = Primus.Utils
local DB      = Primus.DB

local leftWingFrame   = nil
local rightWingFrame  = nil
local playerHealthBar = nil
local playerPowerBar  = nil
local targetHealthBar = nil
local targetPowerBar  = nil

-- =========================================================================
-- WINGS BUILDER
-- =========================================================================

function PUIHud:BuildWings(parent)
    local hudDB = DB:GetNamespace("PUIHud")
    local wingW = hudDB and hudDB:Get("wingWidth", 28) or 28
    local wingH = hudDB and hudDB:Get("wingHeight", 180) or 180
    local pwrW  = hudDB and hudDB:Get("powerWidth", 10) or 10

    -- =====================================================================
    -- 1. LEFT WING: VERTICAL PLAYER STATUS (HP + POWER)
    -- =====================================================================
    leftWingFrame = CreateFrame("Frame", "Primus_PUIHud_LeftWing", parent)
    leftWingFrame:SetWidth(wingW + pwrW + 4)
    leftWingFrame:SetHeight(wingH)
    leftWingFrame:SetPoint("LEFT", parent, "LEFT", 30, 0)

    -- Vertical Health Bar (Fills Bottom to Top)
    playerHealthBar = Widgets:CreateStatusBar(leftWingFrame, wingW, wingH, 0, 100)
    playerHealthBar:SetPoint("TOPLEFT", leftWingFrame, "TOPLEFT", 0, 0)
    playerHealthBar:SetOrientation("VERTICAL")
    playerHealthBar:SetStatusBarColor(0.20, 0.80, 0.20, 1.0)

    local playerHPText = playerHealthBar:CreateFontString(nil, "OVERLAY")
    playerHPText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    playerHPText:SetPoint("CENTER", playerHealthBar, "CENTER", 0, 0)
    playerHPText:SetTextColor(1, 1, 1)
    parent.playerHPText = playerHPText

    -- Vertical Power Bar
    playerPowerBar = Widgets:CreateStatusBar(leftWingFrame, pwrW, wingH, 0, 100)
    playerPowerBar:SetPoint("LEFT", playerHealthBar, "RIGHT", 2, 0)
    playerPowerBar:SetOrientation("VERTICAL")
    playerPowerBar:SetStatusBarColor(0.20, 0.50, 1.00, 1.0)

    local playerPwrText = playerPowerBar:CreateFontString(nil, "OVERLAY")
    playerPwrText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    playerPwrText:SetPoint("BOTTOM", playerPowerBar, "BOTTOM", 0, 4)
    playerPwrText:SetTextColor(0.8, 0.9, 1.0)
    parent.playerPwrText = playerPwrText

    -- Clickable Player Target Area
    local pClick = CreateFrame("Button", nil, leftWingFrame)
    pClick:SetAllPoints(leftWingFrame)
    pClick:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pClick:SetScript("OnClick", function()
        if arg1 == "LeftButton" then
            TargetUnit("player")
        elseif arg1 == "RightButton" and PlayerFrameDropDown then
            ToggleDropDownMenu(1, nil, PlayerFrameDropDown, "cursor")
        end
    end)

    -- =====================================================================
    -- 2. RIGHT WING: VERTICAL TARGET STATUS (HP + POWER)
    -- =====================================================================
    rightWingFrame = CreateFrame("Frame", "Primus_PUIHud_RightWing", parent)
    rightWingFrame:SetWidth(wingW + pwrW + 4)
    rightWingFrame:SetHeight(wingH)
    rightWingFrame:SetPoint("RIGHT", parent, "RIGHT", -30, 0)

    -- Vertical Power Bar (Left of Target HP)
    targetPowerBar = Widgets:CreateStatusBar(rightWingFrame, pwrW, wingH, 0, 100)
    targetPowerBar:SetPoint("TOPLEFT", rightWingFrame, "TOPLEFT", 0, 0)
    targetPowerBar:SetOrientation("VERTICAL")
    targetPowerBar:SetStatusBarColor(0.20, 0.50, 1.00, 1.0)

    local targetPwrText = targetPowerBar:CreateFontString(nil, "OVERLAY")
    targetPwrText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    targetPwrText:SetPoint("BOTTOM", targetPowerBar, "BOTTOM", 0, 4)
    targetPwrText:SetTextColor(0.8, 0.9, 1.0)
    parent.targetPwrText = targetPwrText

    -- Vertical Health Bar
    targetHealthBar = Widgets:CreateStatusBar(rightWingFrame, wingW, wingH, 0, 100)
    targetHealthBar:SetPoint("LEFT", targetPowerBar, "RIGHT", 2, 0)
    targetHealthBar:SetOrientation("VERTICAL")
    targetHealthBar:SetStatusBarColor(0.80, 0.20, 0.20, 1.0)

    local targetHPText = targetHealthBar:CreateFontString(nil, "OVERLAY")
    targetHPText:SetFont(Media:Fetch("font", "Default"), 9, "OUTLINE")
    targetHPText:SetPoint("CENTER", targetHealthBar, "CENTER", 0, 0)
    targetHPText:SetTextColor(1, 1, 1)
    parent.targetHPText = targetHPText

    local targetNameText = rightWingFrame:CreateFontString(nil, "OVERLAY")
    targetNameText:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    targetNameText:SetPoint("BOTTOMRIGHT", targetHealthBar, "TOPRIGHT", 0, 4)
    targetNameText:SetTextColor(1.0, 0.9, 0.3)
    parent.targetNameText = targetNameText

    local tClick = CreateFrame("Button", nil, rightWingFrame)
    tClick:SetAllPoints(rightWingFrame)
    tClick:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tClick:SetScript("OnClick", function()
        if arg1 == "LeftButton" then
            TargetUnit("target")
        elseif arg1 == "RightButton" and TargetFrameDropDown then
            ToggleDropDownMenu(1, nil, TargetFrameDropDown, "cursor")
        end
    end)

    self.leftWingFrame   = leftWingFrame
    self.rightWingFrame  = rightWingFrame
    self.playerHealthBar = playerHealthBar
    self.playerPowerBar  = playerPowerBar
    self.targetHealthBar = targetHealthBar
    self.targetPowerBar  = targetPowerBar
end

-- =========================================================================
-- WINGS REAL-TIME UPDATES
-- =========================================================================

function PUIHud:UpdatePlayerWing()
    local hudFrame = self.hudFrame
    if not hudFrame or not playerHealthBar or not playerPowerBar then return end

    local curHP, maxHP, pctHP = Utils.GetUnitHealth("player")
    local curPwr = UnitMana("player") or 0
    local maxPwr = UnitManaMax("player") or 1
    local pwrType = UnitPowerType("player") or 0

    playerHealthBar:SetMinMaxValues(0, maxHP)
    playerHealthBar:SetValue(curHP)

    local _, pClass = UnitClass("player")
    local r, g, b = Utils.GetClassColor(pClass or "WARRIOR")
    playerHealthBar:SetStatusBarColor(r, g, b, 1.0)

    if hudFrame.playerHPText then
        hudFrame.playerHPText:SetText(string.format("%d%%\n|cffaaaaaa%d|r", pctHP, curHP))
    end

    playerPowerBar:SetMinMaxValues(0, maxPwr > 0 and maxPwr or 1)
    playerPowerBar:SetValue(curPwr)

    if pwrType == 1 then
        playerPowerBar:SetStatusBarColor(0.95, 0.20, 0.20, 1.0) -- Rage Red
        if hudFrame.playerPwrText then hudFrame.playerPwrText:SetText(tostring(curPwr)) end
    elseif pwrType == 3 then
        playerPowerBar:SetStatusBarColor(1.00, 0.85, 0.15, 1.0) -- Energy Yellow
        if hudFrame.playerPwrText then hudFrame.playerPwrText:SetText(tostring(curPwr)) end
    else
        playerPowerBar:SetStatusBarColor(0.20, 0.50, 1.00, 1.0) -- Mana Blue
        local pwrPct = maxPwr > 0 and math.floor((curPwr / maxPwr) * 100) or 0
        if hudFrame.playerPwrText then hudFrame.playerPwrText:SetText(string.format("%d%%", pwrPct)) end
    end
end

function PUIHud:UpdateTargetWing()
    local hudFrame = self.hudFrame
    if not hudFrame or not targetHealthBar or not targetPowerBar or not rightWingFrame then return end

    if not UnitExists("target") then
        rightWingFrame:Hide()
        if self.rightAssistBtn then self.rightAssistBtn:Hide() end
        return
    end

    rightWingFrame:Show()
    if self.rightAssistBtn then self.rightAssistBtn:Show() end

    local curHP, maxHP, pctHP = Utils.GetUnitHealth("target")
    local curPwr = UnitMana("target") or 0
    local maxPwr = UnitManaMax("target") or 1
    local pwrType = UnitPowerType("target") or 0

    targetHealthBar:SetMinMaxValues(0, maxHP)
    targetHealthBar:SetValue(curHP)

    if UnitIsPlayer("target") then
        local _, tClass = UnitClass("target")
        local r, g, b = Utils.GetClassColor(tClass or "")
        targetHealthBar:SetStatusBarColor(r, g, b, 1.0)
    else
        if UnitIsEnemy("player", "target") then
            targetHealthBar:SetStatusBarColor(0.90, 0.20, 0.20, 1.0)
        elseif UnitIsFriend("player", "target") then
            targetHealthBar:SetStatusBarColor(0.20, 0.85, 0.20, 1.0)
        else
            targetHealthBar:SetStatusBarColor(0.95, 0.85, 0.20, 1.0)
        end
    end

    if hudFrame.targetHPText then
        hudFrame.targetHPText:SetText(string.format("%d%%\n|cffaaaaaa%d|r", pctHP, curHP))
    end

    targetPowerBar:SetMinMaxValues(0, maxPwr > 0 and maxPwr or 1)
    targetPowerBar:SetValue(curPwr)

    if pwrType == 1 then
        targetPowerBar:SetStatusBarColor(0.95, 0.20, 0.20, 1.0)
        if hudFrame.targetPwrText then hudFrame.targetPwrText:SetText(tostring(curPwr)) end
    elseif pwrType == 3 then
        targetPowerBar:SetStatusBarColor(1.00, 0.85, 0.15, 1.0)
        if hudFrame.targetPwrText then hudFrame.targetPwrText:SetText(tostring(curPwr)) end
    else
        targetPowerBar:SetStatusBarColor(0.20, 0.50, 1.00, 1.0)
        local pwrPct = maxPwr > 0 and math.floor((curPwr / maxPwr) * 100) or 0
        if hudFrame.targetPwrText then hudFrame.targetPwrText:SetText(string.format("%d%%", pwrPct)) end
    end

    local name = UnitName("target") or "Target"
    local level = UnitLevel("target") or 0
    local levelStr = level <= 0 and "??" or tostring(level)
    local classification = UnitClassification("target")
    local tag = ""
    if classification == "worldboss" then tag = "B"
    elseif classification == "elite" then tag = "+"
    elseif classification == "rareelite" then tag = "R+"
    elseif classification == "rare" then tag = "R" end

    if hudFrame.targetNameText then
        hudFrame.targetNameText:SetText(string.format("[%s%s] %s", levelStr, tag, string.sub(name, 1, 14)))
    end
end

-- =========================================================================
-- VERTICAL AURA COLUMNS (Player Left & Target Right)
-- =========================================================================

local playerAuraButtons = {}
local targetAuraButtons = {}
local playerAuraFrame = nil
local targetAuraFrame = nil

local DISPEL_COLORS = {
    ["Magic"]   = { 0.2, 0.6, 1.0 },
    ["Curse"]   = { 0.6, 0.0, 1.0 },
    ["Poison"]  = { 0.0, 0.8, 0.0 },
    ["Disease"] = { 0.9, 0.4, 0.1 },
    ["none"]    = { 0.8, 0.1, 0.1 },
}

local function CreateAuraSlot(parent, isTarget, index)
    local size = 22
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(size)
    btn:SetHeight(size)
    btn:SetBackdrop(Media:Fetch("border", "1Pixel"))
    btn:SetBackdropColor(0.04, 0.04, 0.06, 0.85)
    btn:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:Hide()

    local icon = btn:CreateTexture(nil, "BORDER")
    icon:SetAllPoints(btn)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = icon

    local count = btn:CreateFontString(nil, "OVERLAY")
    count:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    count:SetTextColor(1, 1, 1)
    btn.count = count

    local duration = btn:CreateFontString(nil, "OVERLAY")
    duration:SetFont(Media:Fetch("font", "Default"), 8, "OUTLINE")
    duration:SetPoint("CENTER", btn, "CENTER", 0, 0)
    duration:SetTextColor(1, 1, 0.4)
    duration:Hide()
    btn.duration = duration

    btn:SetScript("OnEnter", function()
        if isTarget then
            if btn.isDebuff and btn.unitSlot then
                GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                GameTooltip:SetUnitDebuff("target", btn.unitSlot)
            elseif btn.unitSlot then
                GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                GameTooltip:SetUnitBuff("target", btn.unitSlot)
            end
        else
            if btn.isWeaponEnchant and btn.weaponSlot then
                GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
                GameTooltip:SetInventoryItem("player", btn.weaponSlot)
            elseif btn.buffIndex then
                GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
                GameTooltip:SetPlayerBuff(btn.buffIndex)
            end
        end
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    btn:SetScript("OnClick", function()
        if not isTarget and arg1 == "RightButton" and btn.buffIndex and not btn.isDebuff then
            CancelPlayerBuff(btn.buffIndex)
        end
    end)

    return btn
end

function PUIHud:BuildAuraColumns(parent, leftWing, rightWing)
    local size = 22
    local spacing = 3
    local lWing = leftWing or leftWingFrame
    local rWing = rightWing or rightWingFrame

    -- 1. Player Aura Column (OUTSIDE - Left of Left Wing)
    playerAuraFrame = CreateFrame("Frame", "Primus_PUIHud_PlayerAuras", parent)
    playerAuraFrame:SetWidth(size)
    playerAuraFrame:SetHeight(8 * size + 7 * spacing)
    if lWing then
        playerAuraFrame:SetPoint("RIGHT", lWing, "LEFT", -6, 0)
    else
        playerAuraFrame:SetPoint("LEFT", parent, "LEFT", 0, 0)
    end

    for i = 1, 8 do
        local btn = CreateAuraSlot(playerAuraFrame, false, i)
        btn:SetPoint("TOPLEFT", playerAuraFrame, "TOPLEFT", 0, -(i - 1) * (size + spacing))
        table.insert(playerAuraButtons, btn)
    end

    -- 2. Target Aura Column (OUTSIDE - Right of Right Wing)
    targetAuraFrame = CreateFrame("Frame", "Primus_PUIHud_TargetAuras", parent)
    targetAuraFrame:SetWidth(size)
    targetAuraFrame:SetHeight(8 * size + 7 * spacing)
    if rWing then
        targetAuraFrame:SetPoint("LEFT", rWing, "RIGHT", 6, 0)
    else
        targetAuraFrame:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    end

    for i = 1, 8 do
        local btn = CreateAuraSlot(targetAuraFrame, true, i)
        btn:SetPoint("TOPLEFT", targetAuraFrame, "TOPLEFT", 0, -(i - 1) * (size + spacing))
        table.insert(targetAuraButtons, btn)
    end

    self.playerAuraFrame = playerAuraFrame
    self.targetAuraFrame = targetAuraFrame
end

function PUIHud:UpdateAuras()
    local CoreAuras = Primus.Auras
    -- Update Player Auras (Up to 4 Buffs/Enchants + 4 Debuffs)
    local slotIdx = 1

    -- 1. Temporary Weapon Enchants (Main Hand & Off Hand) via Central Auras Service
    local enchants = CoreAuras and CoreAuras:GetWeaponEnchants()
    if enchants and enchants.hasMainHand and slotIdx <= 4 then
        local btn = playerAuraButtons[slotIdx]
        if btn then
            btn.buffIndex = nil
            btn.isDebuff = false
            btn.isWeaponEnchant = true
            btn.weaponSlot = 16
            btn.icon:SetTexture(GetInventoryItemTexture("player", 16) or "Interface\\Icons\\INV_Sword_04")
            btn.count:SetText("")
            local durSec = enchants.mainHandExp or 0
            if durSec > 0 then
                btn.duration:SetText(Utils.FormatAuraDuration(durSec))
                local dr, dg, db = Utils.GetAuraDurationColor(durSec)
                btn.duration:SetTextColor(dr, dg, db)
                btn.duration:Show()
            else
                btn.duration:SetText("")
                btn.duration:Hide()
            end
            btn:SetBackdropBorderColor(0.8, 0.4, 0.0, 0.9)
            btn:Show()
            slotIdx = slotIdx + 1
        end
    end

    if enchants and enchants.hasOffHand and slotIdx <= 4 then
        local btn = playerAuraButtons[slotIdx]
        if btn then
            btn.buffIndex = nil
            btn.isDebuff = false
            btn.isWeaponEnchant = true
            btn.weaponSlot = 17
            btn.icon:SetTexture(GetInventoryItemTexture("player", 17) or "Interface\\Icons\\INV_Sword_04")
            btn.count:SetText("")
            local durSec = enchants.offHandExp or 0
            if durSec > 0 then
                btn.duration:SetText(Utils.FormatAuraDuration(durSec))
                local dr, dg, db = Utils.GetAuraDurationColor(durSec)
                btn.duration:SetTextColor(dr, dg, db)
                btn.duration:Show()
            else
                btn.duration:SetText("")
                btn.duration:Hide()
            end
            btn:SetBackdropBorderColor(0.8, 0.4, 0.0, 0.9)
            btn:Show()
            slotIdx = slotIdx + 1
        end
    end

    -- 2. Player Buffs & Debuffs from Primus.Auras
    local pAuras = CoreAuras and CoreAuras:GetUnitAuras("player")
    if pAuras then
        if pAuras.totalBuffs and pAuras.totalBuffs > 0 then
            for i = 1, pAuras.totalBuffs do
                if slotIdx > 4 then break end
                local buff = pAuras.buffs[i]
                if buff and buff.texture then
                    local btn = playerAuraButtons[slotIdx]
                    if btn then
                        btn.buffIndex = buff.buffIndex
                        btn.isDebuff = false
                        btn.isWeaponEnchant = false
                        btn.icon:SetTexture(buff.texture)
                        local stack = buff.stacks or 0
                        btn.count:SetText(stack > 1 and tostring(stack) or "")

                        local timeLeft = buff.timeLeft
                        if timeLeft and timeLeft > 0 then
                            btn.duration:SetText(Utils.FormatAuraDuration(timeLeft))
                            local dr, dg, db = Utils.GetAuraDurationColor(timeLeft)
                            btn.duration:SetTextColor(dr, dg, db)
                            btn.duration:Show()
                        else
                            btn.duration:SetText("")
                            btn.duration:Hide()
                        end

                        btn:SetBackdropBorderColor(0.2, 0.7, 0.3, 0.8)
                        btn:Show()
                        slotIdx = slotIdx + 1
                    end
                end
            end
        end

        if pAuras.totalDebuffs and pAuras.totalDebuffs > 0 then
            for i = 1, pAuras.totalDebuffs do
                if slotIdx > 8 then break end
                local debuff = pAuras.debuffs[i]
                if debuff and debuff.texture then
                    local btn = playerAuraButtons[slotIdx]
                    if btn then
                        btn.buffIndex = debuff.buffIndex
                        btn.isDebuff = true
                        btn.isWeaponEnchant = false
                        btn.icon:SetTexture(debuff.texture)
                        local stack = debuff.stacks or 0
                        btn.count:SetText(stack > 1 and tostring(stack) or "")

                        local timeLeft = debuff.timeLeft
                        if timeLeft and timeLeft > 0 then
                            btn.duration:SetText(Utils.FormatAuraDuration(timeLeft))
                            local dr, dg, db = Utils.GetAuraDurationColor(timeLeft)
                            btn.duration:SetTextColor(dr, dg, db)
                            btn.duration:Show()
                        else
                            btn.duration:SetText("")
                            btn.duration:Hide()
                        end

                        local dc = CoreAuras and CoreAuras:GetDispelColor(debuff.dispelType) or { r = 0.8, g = 0.2, b = 0.2 }
                        btn:SetBackdropBorderColor(dc.r, dc.g, dc.b, 0.9)
                        btn:Show()
                        slotIdx = slotIdx + 1
                    end
                end
            end
        end
    end

    for j = slotIdx, 8 do
        if playerAuraButtons[j] then
            playerAuraButtons[j].duration:SetText("")
            playerAuraButtons[j].duration:Hide()
            playerAuraButtons[j]:Hide()
        end
    end

    -- Update Target Auras (Up to 4 Buffs + 4 Debuffs)
    if not UnitExists("target") then
        if targetAuraFrame then targetAuraFrame:Hide() end
        return
    end
    if targetAuraFrame then targetAuraFrame:Show() end

    local tSlot = 1
    local tAuras = CoreAuras and CoreAuras:GetUnitAuras("target")
    if tAuras then
        if tAuras.totalBuffs and tAuras.totalBuffs > 0 then
            for i = 1, tAuras.totalBuffs do
                if tSlot > 4 then break end
                local buff = tAuras.buffs[i]
                if buff and buff.texture then
                    local btn = targetAuraButtons[tSlot]
                    if btn then
                        btn.unitSlot = buff.slot
                        btn.isDebuff = false
                        btn.icon:SetTexture(buff.texture)
                        btn.count:SetText("")
                        if btn.duration then
                            btn.duration:SetText("")
                            btn.duration:Hide()
                        end
                        btn:SetBackdropBorderColor(0.2, 0.7, 0.3, 0.8)
                        btn:Show()
                        tSlot = tSlot + 1
                    end
                end
            end
        end

        if tAuras.totalDebuffs and tAuras.totalDebuffs > 0 then
            for i = 1, tAuras.totalDebuffs do
                if tSlot > 8 then break end
                local debuff = tAuras.debuffs[i]
                if debuff and debuff.texture then
                    local btn = targetAuraButtons[tSlot]
                    if btn then
                        btn.unitSlot = debuff.slot
                        btn.isDebuff = true
                        btn.icon:SetTexture(debuff.texture)
                        local stack = debuff.stacks or 0
                        btn.count:SetText(stack > 1 and tostring(stack) or "")
                        if btn.duration then
                            btn.duration:SetText("")
                            btn.duration:Hide()
                        end
                        local dc = CoreAuras and CoreAuras:GetDispelColor(debuff.dispelType) or { r = 0.8, g = 0.2, b = 0.2 }
                        btn:SetBackdropBorderColor(dc.r, dc.g, dc.b, 0.9)
                        btn:Show()
                        tSlot = tSlot + 1
                    end
                end
            end
        end
    end

    for j = tSlot, 8 do
        if targetAuraButtons[j] then
            if targetAuraButtons[j].duration then
                targetAuraButtons[j].duration:SetText("")
                targetAuraButtons[j].duration:Hide()
            end
            targetAuraButtons[j]:Hide()
        end
    end
end

