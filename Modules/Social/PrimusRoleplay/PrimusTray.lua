--[[
    PrimusUI: PUIRoleplay Quick Action Tray / RP Bar (PUITray.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (100% Feature Parity with TurtleRP IconTray + Primus Dark Glass UI)
--]]

local Primus = _G.Primus
local PUIRoleplay = Primus.PUIRoleplay or {}
Primus.PUIRoleplay = PUIRoleplay

local Tray = {}
PUIRoleplay.Tray = Tray

local trayFrame = nil
local isRPModeActive = false

--------------------------------------------------------------------------------
-- Helper: Create Styled Tray Button
--------------------------------------------------------------------------------
local function CreateTrayButton(parent, width, height, iconTexture, buttonText)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(width or 24)
    btn:SetHeight(height or 22)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    btn:SetBackdropColor(0.10, 0.12, 0.12, 0.85)
    btn:SetBackdropBorderColor(0.25, 0.35, 0.30, 0.8)

    if iconTexture then
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetWidth(15)
        icon:SetHeight(15)
        icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
        icon:SetTexture(iconTexture)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon = icon
    end

    if buttonText then
        local text = btn:CreateFontString(nil, "OVERLAY")
        text:SetFont(Primus.Media:Fetch("font", "Default"), 10, "OUTLINE")
        text:SetPoint("CENTER", btn, "CENTER", 0, 0)
        text:SetText(buttonText)
        btn.text = text
    end

    btn:SetScript("OnEnter", function()
        this:SetBackdropColor(0.20, 0.35, 0.25, 1.0)
        this:SetBackdropBorderColor(0.40, 0.90, 0.50, 1.0)
        if this.tooltipText then
            GameTooltip:SetOwner(this, "ANCHOR_TOP")
            GameTooltip:AddLine(this.tooltipTitle or "RP Action", 0.4, 0.9, 0.4)
            GameTooltip:AddLine(this.tooltipText, 0.9, 0.9, 0.9, true)
            if this.tooltipSubText then
                GameTooltip:AddLine(this.tooltipSubText, 0.6, 0.8, 1.0, true)
            end
            GameTooltip:Show()
        end
    end)

    btn:SetScript("OnLeave", function()
        this:SetBackdropColor(0.10, 0.12, 0.12, 0.85)
        this:SetBackdropBorderColor(0.25, 0.35, 0.30, 0.8)
        GameTooltip:Hide()
    end)

    return btn
end

--------------------------------------------------------------------------------
-- Build the RP Quick Bar (Tray)
--------------------------------------------------------------------------------
function Tray:BuildFrame()
    if trayFrame then return trayFrame end

    local f = CreateFrame("Frame", "Primus_PUIRoleplay_Tray", UIParent)
    f:SetWidth(338)
    f:SetHeight(28)
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -180)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    f:SetBackdropColor(0.05, 0.07, 0.06, 0.94)
    f:SetBackdropBorderColor(0.25, 0.40, 0.30, 1.0)

    -- Alt-drag moving support
    f:SetScript("OnDragStart", function()
        this:StartMoving()
    end)
    f:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
    end)

    -- Register with PUIMover under SOCIAL
    if Primus.PUIMover then
        Primus.PUIMover:Register(f, "PUIRP_Tray", "RP Quick Action Tray", "SOCIAL")
    end

    local xOffset = 4
    local btnSpacing = 3

    -- 1. IC / OOC Toggle Button
    local icBtn = CreateTrayButton(f, 32, 22, nil, "IC")
    icBtn:SetPoint("LEFT", f, "LEFT", xOffset, 0)
    icBtn.tooltipTitle = "Roleplay State"
    icBtn.tooltipText = "Toggle In-Character (IC) vs Out-Of-Character (OOC)."
    icBtn.tooltipSubText = "|cff69ccf0Left-Click:|r Switch Status"
    icBtn:SetScript("OnClick", function()
        local cur = PUIRoleplay:GetICState()
        local nextState = (cur == "1") and "0" or "1"
        PUIRoleplay:SetICState(nextState)
        Tray:UpdateICButton()
        local statusLabel = (nextState == "1") and "|cff40af6f[IC]|r" or "|cffd3681e[OOC]|r"
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffPrimus RP:|r Status set to " .. statusLabel)
    end)
    f.icBtn = icBtn
    xOffset = xOffset + 32 + btnSpacing

    -- 2. RP Immersion Mode Button [RP]
    local rpBtn = CreateTrayButton(f, 26, 22, nil, "RP")
    rpBtn:SetPoint("LEFT", f, "LEFT", xOffset, 0)
    rpBtn.text:SetTextColor(0.4, 0.8, 1.0)
    rpBtn.tooltipTitle = "RP Immersion Mode"
    rpBtn.tooltipText = "Toggle cinematic RP view (hides action bars and unit frames while keeping chat and tooltips active)."
    rpBtn.tooltipSubText = "|cff69ccf0Left-Click:|r Toggle Immersion"
    rpBtn:SetScript("OnClick", function()
        Tray:ToggleRPMode()
    end)
    f.rpBtn = rpBtn
    xOffset = xOffset + 26 + btnSpacing

    -- 3. Character Sheet / Bio Button
    local bioBtn = CreateTrayButton(f, 22, 22, "Interface\\Icons\\INV_Misc_Book_09")
    bioBtn:SetPoint("LEFT", f, "LEFT", xOffset, 0)
    bioBtn.tooltipTitle = "RP Character Sheet"
    bioBtn.tooltipText = "Open your roleplay character profile and editor."
    bioBtn.tooltipSubText = "|cff69ccf0Left-Click:|r Open Sheet"
    bioBtn:SetScript("OnClick", function()
        PUIRoleplay:OpenProfile()
    end)
    f.bioBtn = bioBtn
    xOffset = xOffset + 22 + btnSpacing

    -- 4. DiceMaster D20 Tabletop & Combat Engine
    local diceBtn = CreateTrayButton(f, 22, 22, "Interface\\Icons\\INV_Misc_Dice_02")
    diceBtn:SetPoint("LEFT", f, "LEFT", xOffset, 0)
    diceBtn.tooltipTitle = "DiceMaster D20 Tabletop"
    diceBtn.tooltipText = "Open D20 roller, stat modifiers, advantage/disadvantage, and tabletop HP & status tracker."
    diceBtn.tooltipSubText = "|cff69ccf0Left-Click:|r Open DiceMaster"
    diceBtn:SetScript("OnClick", function()
        if PUIRoleplay.Dice and PUIRoleplay.Dice.Toggle then
            PUIRoleplay.Dice:Toggle()
        end
    end)
    f.diceBtn = diceBtn
    xOffset = xOffset + 22 + btnSpacing

    -- 5. RP Extended Inventory Pouch (Bag)
    local bagBtn = CreateTrayButton(f, 22, 22, "Interface\\Icons\\INV_Misc_Bag_08")
    bagBtn:SetPoint("LEFT", f, "LEFT", xOffset, 0)
    bagBtn.tooltipTitle = "RP Extended Inventory"
    bagBtn.tooltipText = "Open custom roleplay inventory pouch, craft RP items, and inspect artifacts."
    bagBtn.tooltipSubText = "|cff69ccf0Left-Click:|r Open RP Bag"
    bagBtn:SetScript("OnClick", function()
        if PUIRoleplay.Extended and PUIRoleplay.Extended.ToggleBag then
            PUIRoleplay.Extended:ToggleBag()
        end
    end)
    f.bagBtn = bagBtn
    xOffset = xOffset + 22 + btnSpacing

    -- 6. Parchment Documents & Written Letters
    local docBtn = CreateTrayButton(f, 22, 22, "Interface\\Icons\\INV_Misc_Note_01")
    docBtn:SetPoint("LEFT", f, "LEFT", xOffset, 0)
    docBtn.tooltipTitle = "Parchment Documents & Letters"
    docBtn.tooltipText = "Compose, seal, and read in-game written letters and books."
    docBtn.tooltipSubText = "|cff69ccf0Left-Click:|r Open Documents"
    docBtn:SetScript("OnClick", function()
        if PUIRoleplay.Extended and PUIRoleplay.Extended.OpenDocumentEngine then
            PUIRoleplay.Extended:OpenDocumentEngine()
        end
    end)
    f.docBtn = docBtn
    xOffset = xOffset + 22 + btnSpacing

    -- 7. Story Logger / Elephant Archive
    local eleBtn = CreateTrayButton(f, 22, 22, "Interface\\Icons\\INV_Misc_Book_06")
    eleBtn:SetPoint("LEFT", f, "LEFT", xOffset, 0)
    eleBtn.tooltipTitle = "Elephant Story Logger"
    eleBtn.tooltipText = "Open roleplay story logger, review past scene transcripts, and export to Discord/Markdown."
    eleBtn.tooltipSubText = "|cff69ccf0Left-Click:|r Open Story Archive"
    eleBtn:SetScript("OnClick", function()
        if PUIRoleplay.Elephant and PUIRoleplay.Elephant.Toggle then
            PUIRoleplay.Elephant:Toggle()
        end
    end)
    f.eleBtn = eleBtn
    xOffset = xOffset + 22 + btnSpacing

    -- 8. RP Directory & Map Button
    local dirBtn = CreateTrayButton(f, 22, 22, "Interface\\Icons\\INV_Misc_Map_01")
    dirBtn:SetPoint("LEFT", f, "LEFT", xOffset, 0)
    dirBtn.tooltipTitle = "RP Directory & Map"
    dirBtn.tooltipText = "Browse active roleplayers, character bios, and world map locations."
    dirBtn.tooltipSubText = "|cff69ccf0Left-Click:|r Open Directory"
    dirBtn:SetScript("OnClick", function()
        PUIRoleplay:OpenDirectory()
    end)
    f.dirBtn = dirBtn
    xOffset = xOffset + 22 + btnSpacing

    -- 9. Emotes & Extended Chat Composer Button
    local chatBtn = CreateTrayButton(f, 22, 22, "Interface\\GossipFrame\\GossipGossipIcon")
    chatBtn:SetPoint("LEFT", f, "LEFT", xOffset, 0)
    chatBtn.tooltipTitle = "RP Emote Composer"
    chatBtn.tooltipText = "Open the long-form roleplay chat and emote composer (>255 character chunking)."
    chatBtn.tooltipSubText = "|cff69ccf0Left-Click:|r Open Composer"
    chatBtn:SetScript("OnClick", function()
        if PUIRoleplay.Emotes and PUIRoleplay.Emotes.OpenComposer then
            PUIRoleplay.Emotes:OpenComposer()
        end
    end)
    f.chatBtn = chatBtn
    xOffset = xOffset + 22 + btnSpacing

    -- 10. Show / Hide Helm Toggle
    local helmBtn = CreateTrayButton(f, 22, 22, "Interface\\Icons\\INV_Helmet_08")
    helmBtn:SetPoint("LEFT", f, "LEFT", xOffset, 0)
    helmBtn.tooltipTitle = "Toggle Helm"
    helmBtn.tooltipText = "Show or hide your character's equipped helmet."
    helmBtn.tooltipSubText = "|cff69ccf0Left-Click:|r Toggle Helm"
    helmBtn:SetScript("OnClick", function()
        ShowHelm(not ShowingHelm())
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffPrimus RP:|r Helm display is now " .. (ShowingHelm() and "|cff33ff33Visible|r" or "|cffff4444Hidden|r"))
    end)
    f.helmBtn = helmBtn
    xOffset = xOffset + 22 + btnSpacing

    -- 11. Show / Hide Cloak Toggle
    local cloakBtn = CreateTrayButton(f, 22, 22, "Interface\\Icons\\INV_Misc_Cape_10")
    cloakBtn:SetPoint("LEFT", f, "LEFT", xOffset, 0)
    cloakBtn.tooltipTitle = "Toggle Cloak"
    cloakBtn.tooltipText = "Show or hide your character's equipped cloak."
    cloakBtn.tooltipSubText = "|cff69ccf0Left-Click:|r Toggle Cloak"
    cloakBtn:SetScript("OnClick", function()
        ShowCloak(not ShowingCloak())
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffPrimus RP:|r Cloak display is now " .. (ShowingCloak() and "|cff33ff33Visible|r" or "|cffff4444Hidden|r"))
    end)
    f.cloakBtn = cloakBtn
    xOffset = xOffset + 22 + btnSpacing

    -- 12. Overhead Names Toggle (NPC & Player)
    local namesBtn = CreateTrayButton(f, 22, 22, "Interface\\Icons\\Spell_Shadow_MindSteal")
    namesBtn:SetPoint("LEFT", f, "LEFT", xOffset, 0)
    namesBtn.tooltipTitle = "Toggle Overhead Names"
    namesBtn.tooltipText = "Toggle NPC and player text names above character heads for cinematic immersion."
    namesBtn.tooltipSubText = "|cff69ccf0Left-Click:|r Toggle Names"
    namesBtn:SetScript("OnClick", function()
        local cur = GetCVar("UnitNameNPC") == "1" or GetCVar("UnitNamePlayer") == "1"
        if cur then
            SetCVar("UnitNameNPC", 0)
            SetCVar("UnitNamePlayer", 0)
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffPrimus RP:|r Overhead names |cffff4444Disabled|r")
        else
            SetCVar("UnitNameNPC", 1)
            SetCVar("UnitNamePlayer", 1)
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffPrimus RP:|r Overhead names |cff33ff33Enabled|r")
        end
    end)
    f.namesBtn = namesBtn

    trayFrame = f
    self:UpdateICButton()
    return f
end

--------------------------------------------------------------------------------
-- Update IC/OOC Button State
--------------------------------------------------------------------------------
function Tray:UpdateICButton()
    if not trayFrame or not trayFrame.icBtn then return end
    local isIC = (PUIRoleplay:GetICState() == "1")
    if isIC then
        trayFrame.icBtn.text:SetText("IC")
        trayFrame.icBtn.text:SetTextColor(0.25, 0.95, 0.45) -- Green
        trayFrame.icBtn.tooltipText = "Currently: |cff40af6fIn-Character (IC)|r"
    else
        trayFrame.icBtn.text:SetText("OOC")
        trayFrame.icBtn.text:SetTextColor(0.95, 0.60, 0.20) -- Amber/Orange
        trayFrame.icBtn.tooltipText = "Currently: |cffd3681eOut-Of-Character (OOC)|r"
    end
end

--------------------------------------------------------------------------------
-- RP Immersion Mode Toggle
--------------------------------------------------------------------------------
function Tray:ToggleRPMode()
    isRPModeActive = not isRPModeActive

    if isRPModeActive then
        -- Enter RP Immersion Mode
        if MainMenuBar then MainMenuBar:Hide() end
        if MinimapCluster then MinimapCluster:Hide() end
        if PlayerFrame then PlayerFrame:Hide() end
        if TargetFrame then TargetFrame:Hide() end
        if PetActionBarFrame then PetActionBarFrame:Hide() end

        -- Keep chat, tooltip, and tray visible
        if trayFrame then
            trayFrame.rpBtn.text:SetTextColor(0.2, 1.0, 0.4)
            trayFrame.rpBtn:SetBackdropBorderColor(0.2, 1.0, 0.4, 1.0)
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffPrimus RP:|r RP Immersion Mode |cff33ff33ENABLED|r (Action bars hidden).")
    else
        -- Exit RP Immersion Mode
        if MainMenuBar then MainMenuBar:Show() end
        if MinimapCluster then MinimapCluster:Show() end
        if PlayerFrame then PlayerFrame:Show() end
        if TargetFrame and UnitExists("target") then TargetFrame:Show() end

        if trayFrame then
            trayFrame.rpBtn.text:SetTextColor(0.4, 0.8, 1.0)
            trayFrame.rpBtn:SetBackdropBorderColor(0.25, 0.35, 0.30, 0.8)
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffPrimus RP:|r RP Immersion Mode |cffff4444DISABLED|r (Standard UI restored).")
    end
end

--------------------------------------------------------------------------------
-- Show / Hide / Toggle
--------------------------------------------------------------------------------
function Tray:Show()
    local f = self:BuildFrame()
    f:Show()
    self:UpdateICButton()
end

function Tray:Hide()
    if trayFrame then
        trayFrame:Hide()
    end
end

function Tray:Toggle()
    local f = self:BuildFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        self:UpdateICButton()
    end
end
