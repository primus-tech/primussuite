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
    local btn = CreateFrame("Button", (isTarget and "Primus_PUIHud_TargetAura_" or "Primus_PUIHud_PlayerAura_") .. index, parent)
    btn:SetWidth(size)
    btn:SetHeight(size)
    btn:SetBackdrop(Media and Media:Fetch("border", "1Pixel") or {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    btn:SetBackdropColor(0.04, 0.04, 0.06, 0.85)
    btn:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:Hide()

    local icon = btn:CreateTexture(nil, "BORDER")
    icon:SetAllPoints(btn)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = icon

    local count = btn:CreateFontString(nil, "OVERLAY")
    count:SetFont(Media and Media:Fetch("font", "Default") or "Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    count:SetTextColor(1, 1, 1)
    btn.count = count

    local duration = btn:CreateFontString(nil, "OVERLAY")
    duration:SetFont(Media and Media:Fetch("font", "Default") or "Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
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

    -- 1. Player Aura Array (OUTSIDE - 2 Columns of 8 to Left of Left Wing, Expanding Outwards)
    playerAuraFrame = CreateFrame("Frame", "Primus_PUIHud_PlayerAuras", parent)
    playerAuraFrame:SetWidth(2 * size + spacing)
    playerAuraFrame:SetHeight(8 * size + 7 * spacing)
    if lWing then
        playerAuraFrame:SetPoint("RIGHT", lWing, "LEFT", -6, 0)
    else
        playerAuraFrame:SetPoint("LEFT", parent, "LEFT", 0, 0)
    end

    for i = 1, 16 do
        local btn = CreateAuraSlot(playerAuraFrame, false, i)
        local col = (i <= 8) and 1 or 2
        local row = (i <= 8) and i or (i - 8)
        local xOfs = (col == 1) and 0 or -(size + spacing)
        local yOfs = -(row - 1) * (size + spacing)

        btn:SetPoint("TOPRIGHT", playerAuraFrame, "TOPRIGHT", xOfs, yOfs)
        table.insert(playerAuraButtons, btn)
    end

    -- 2. Target Aura Array (OUTSIDE - 2 Columns of 8 to Right of Right Wing, Expanding Outwards)
    targetAuraFrame = CreateFrame("Frame", "Primus_PUIHud_TargetAuras", parent)
    targetAuraFrame:SetWidth(2 * size + spacing)
    targetAuraFrame:SetHeight(8 * size + 7 * spacing)
    if rWing then
        targetAuraFrame:SetPoint("LEFT", rWing, "RIGHT", 6, 0)
    else
        targetAuraFrame:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    end

    for i = 1, 16 do
        local btn = CreateAuraSlot(targetAuraFrame, true, i)
        local col = (i <= 8) and 1 or 2
        local row = (i <= 8) and i or (i - 8)
        local xOfs = (col == 1) and 0 or (size + spacing)
        local yOfs = -(row - 1) * (size + spacing)

        btn:SetPoint("TOPLEFT", targetAuraFrame, "TOPLEFT", xOfs, yOfs)
        table.insert(targetAuraButtons, btn)
    end

    self.playerAuraFrame = playerAuraFrame
    self.targetAuraFrame = targetAuraFrame
end

-- Resilient Player Aura Collector with Direct C-API Self-Healing Fallback
local function GetPlayerAuraList()
    local CoreAuras = Primus.Auras
    local enchants = CoreAuras and CoreAuras.GetWeaponEnchants and CoreAuras:GetWeaponEnchants()
    if not enchants then
        local hasMH, mhExp, mhCharges, hasOH, ohExp, ohCharges = GetWeaponEnchantInfo()
        enchants = {
            hasMainHand = hasMH and true or false,
            mainHandExp = (hasMH and mhExp) and (mhExp / 1000) or 0,
            mainHandCharges = mhCharges or 0,
            hasOffHand = hasOH and true or false,
            offHandExp = (hasOH and ohExp) and (ohExp / 1000) or 0,
            offHandCharges = ohCharges or 0,
        }
    end

    local pAuras = CoreAuras and CoreAuras.GetUnitAuras and CoreAuras:GetUnitAuras("player")
    local buffs = {}
    local debuffs = {}

    if pAuras and pAuras.totalBuffs and pAuras.totalBuffs > 0 then
        for i = 1, pAuras.totalBuffs do
            local b = pAuras.buffs[i]
            if b and b.texture then
                table.insert(buffs, b)
            end
        end
    else
        -- Direct C-API Scan
        for i = 0, 31 do
            local buffIndex, untilCancelled = GetPlayerBuff(i, "HELPFUL")
            if buffIndex and buffIndex > -1 then
                local tex = GetPlayerBuffTexture(buffIndex)
                if tex then
                    table.insert(buffs, {
                        slot = i,
                        buffIndex = buffIndex,
                        texture = tex,
                        stacks = GetPlayerBuffApplications(buffIndex) or 0,
                        timeLeft = GetPlayerBuffTimeLeft(buffIndex) or 0,
                        untilCancelled = untilCancelled == 1,
                        isDebuff = false,
                    })
                end
            else
                break
            end
        end
    end

    if pAuras and pAuras.totalDebuffs and pAuras.totalDebuffs > 0 then
        for i = 1, pAuras.totalDebuffs do
            local d = pAuras.debuffs[i]
            if d and d.texture then
                table.insert(debuffs, d)
            end
        end
    else
        -- Direct C-API Scan
        for i = 0, 15 do
            local debuffIndex = GetPlayerBuff(i, "HARMFUL")
            if debuffIndex and debuffIndex > -1 then
                local tex = GetPlayerBuffTexture(debuffIndex)
                if tex then
                    table.insert(debuffs, {
                        slot = i,
                        buffIndex = debuffIndex,
                        texture = tex,
                        stacks = GetPlayerBuffApplications(debuffIndex) or 0,
                        timeLeft = GetPlayerBuffTimeLeft(debuffIndex) or 0,
                        dispelType = GetPlayerBuffDispelType(debuffIndex) or "None",
                        isDebuff = true,
                    })
                end
            else
                break
            end
        end
    end

    return enchants, buffs, debuffs
end

-- Resilient Target Aura Collector
local function GetTargetAuraList()
    local CoreAuras = Primus.Auras
    local tAuras = CoreAuras and CoreAuras.GetUnitAuras and CoreAuras:GetUnitAuras("target")
    local buffs = {}
    local debuffs = {}

    if tAuras and tAuras.totalBuffs and tAuras.totalBuffs > 0 then
        for i = 1, tAuras.totalBuffs do
            local b = tAuras.buffs[i]
            if b and b.texture then
                table.insert(buffs, b)
            end
        end
    else
        for i = 1, 16 do
            local tex, stacks = UnitBuff("target", i)
            if tex then
                table.insert(buffs, {
                    slot = i,
                    texture = tex,
                    stacks = stacks or 0,
                    timeLeft = 0,
                    isDebuff = false,
                })
            else
                break
            end
        end
    end

    if tAuras and tAuras.totalDebuffs and tAuras.totalDebuffs > 0 then
        for i = 1, tAuras.totalDebuffs do
            local d = tAuras.debuffs[i]
            if d and d.texture then
                table.insert(debuffs, d)
            end
        end
    else
        for i = 1, 16 do
            local tex, stacks, dType = UnitDebuff("target", i)
            if tex then
                table.insert(debuffs, {
                    slot = i,
                    texture = tex,
                    stacks = stacks or 0,
                    timeLeft = 0,
                    dispelType = dType or "None",
                    isDebuff = true,
                })
            else
                break
            end
        end
    end

    return buffs, debuffs
end

function PUIHud:UpdateAuras()
    local hudDB = DB and DB:GetNamespace("PUIHud")
    local showPlayerAuras = hudDB and hudDB:Get("showPlayerAuras", true)
    if showPlayerAuras == nil then showPlayerAuras = true end

    local showTargetAuras = hudDB and hudDB:Get("showTargetAuras", true)
    if showTargetAuras == nil then showTargetAuras = true end

    local CoreAuras = Primus.Auras
    local maxCapacity = 16

    -- =========================================================================
    -- 1. UPDATE PLAYER AURAS (Weapon Enchants, Buffs, Debuffs)
    -- =========================================================================
    if not showPlayerAuras then
        if playerAuraFrame then playerAuraFrame:Hide() end
    else
        if playerAuraFrame then playerAuraFrame:Show() end
        local enchants, buffs, debuffs = GetPlayerAuraList()
        local slotIdx = 1

        -- 1A. Main-Hand Weapon Enchant
        if enchants and enchants.hasMainHand and slotIdx <= maxCapacity then
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
                btn:SetBackdropBorderColor(0.90, 0.50, 0.10, 0.95)
                btn:Show()
                slotIdx = slotIdx + 1
            end
        end

        -- 1B. Off-Hand Weapon Enchant
        if enchants and enchants.hasOffHand and slotIdx <= maxCapacity then
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
                btn:SetBackdropBorderColor(0.90, 0.50, 0.10, 0.95)
                btn:Show()
                slotIdx = slotIdx + 1
            end
        end

        -- 1C. Helpful Buffs
        local numDebuffs = table.getn(debuffs)
        local numBuffs = table.getn(buffs)
        local maxBuffSlots = maxCapacity - numDebuffs
        if maxBuffSlots < 8 then maxBuffSlots = 8 end

        for i = 1, numBuffs do
            if slotIdx > maxCapacity or (slotIdx > maxBuffSlots and numDebuffs > 0) then break end
            local buff = buffs[i]
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

                    btn:SetBackdropBorderColor(0.15, 0.65, 0.25, 0.85)
                    btn:Show()
                    slotIdx = slotIdx + 1
                end
            end
        end

        -- 1D. Harmful Debuffs (Dispel-Colored Borders)
        for i = 1, numDebuffs do
            if slotIdx > maxCapacity then break end
            local debuff = debuffs[i]
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

                    local dc = CoreAuras and CoreAuras.GetDispelColor and CoreAuras:GetDispelColor(debuff.dispelType) or { r = 0.9, g = 0.2, b = 0.2 }
                    btn:SetBackdropBorderColor(dc.r, dc.g, dc.b, 1.0)
                    btn:Show()
                    slotIdx = slotIdx + 1
                end
            end
        end

        -- Hide unused buttons
        for j = slotIdx, maxCapacity do
            if playerAuraButtons[j] then
                playerAuraButtons[j].duration:SetText("")
                playerAuraButtons[j].duration:Hide()
                playerAuraButtons[j]:Hide()
            end
        end
    end

    -- =========================================================================
    -- 2. UPDATE TARGET AURAS
    -- =========================================================================
    if not UnitExists("target") or not showTargetAuras then
        if targetAuraFrame then targetAuraFrame:Hide() end
        return
    end
    if targetAuraFrame then targetAuraFrame:Show() end

    local tSlot = 1
    local tBuffs, tDebuffs = GetTargetAuraList()
    local numTD = table.getn(tDebuffs)
    local numTB = table.getn(tBuffs)

    -- 2A. Target Debuffs First (Tactical Dispel / DoT Focus)
    for i = 1, numTD do
        if tSlot > maxCapacity then break end
        local debuff = tDebuffs[i]
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
                local dc = CoreAuras and CoreAuras.GetDispelColor and CoreAuras:GetDispelColor(debuff.dispelType) or { r = 0.9, g = 0.2, b = 0.2 }
                btn:SetBackdropBorderColor(dc.r, dc.g, dc.b, 1.0)
                btn:Show()
                tSlot = tSlot + 1
            end
        end
    end

    -- 2B. Target Buffs
    for i = 1, numTB do
        if tSlot > maxCapacity then break end
        local buff = tBuffs[i]
        if buff and buff.texture then
            local btn = targetAuraButtons[tSlot]
            if btn then
                btn.unitSlot = buff.slot
                btn.isDebuff = false
                btn.icon:SetTexture(buff.texture)
                local stack = buff.stacks or 0
                btn.count:SetText(stack > 1 and tostring(stack) or "")
                if btn.duration then
                    btn.duration:SetText("")
                    btn.duration:Hide()
                end
                btn:SetBackdropBorderColor(0.20, 0.70, 0.30, 0.85)
                btn:Show()
                tSlot = tSlot + 1
            end
        end
    end

    -- Hide unused target buttons
    for j = tSlot, maxCapacity do
        if targetAuraButtons[j] then
            if targetAuraButtons[j].duration then
                targetAuraButtons[j].duration:SetText("")
                targetAuraButtons[j].duration:Hide()
            end
            targetAuraButtons[j]:Hide()
        end
    end
end

