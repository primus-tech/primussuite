--[[
    PrimusUI Module: PUIHotbars - Micro Menu & Bag Bar Engine
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Virtualizes Blizzard's Micro Menu buttons and Bag & Keyring slots into
    dockable, movable containers with pure scaling, 1-pixel borders,
    Zen combat state integration, and Single Bag (One-Bag) suppression.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIHotbars = Primus.PUIHotbars or {}
Primus.PUIHotbars = PUIHotbars

local Media    = Primus.Media
local DB       = Primus.DB
local Hider    = Primus.Hider
local PUIMover = Primus.PUIMover

local microAnchor = nil
local bagAnchor   = nil

-- =========================================================================
-- MICRO MENU BAR VIRTUALIZATION
-- =========================================================================

function PUIHotbars:BuildMicroBar()
    local hotbarsDB = DB:GetNamespace("PUIHotbars")

    local microList = {
        "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton",
        "QuestLogMicroButton", "SocialsMicroButton", "WorldMapMicroButton",
        "MainMenuMicroButton", "HelpMicroButton"
    }

    local btnW = 28
    local btnH = 58
    local spacing = 0
    local totalW = 8 * btnW + 7 * spacing

    if not microAnchor then
        microAnchor = CreateFrame("Frame", "Primus_PUIHotbars_MicroBar", UIParent)
        microAnchor:SetWidth(totalW)
        microAnchor:SetHeight(btnH)
        microAnchor:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -6, 6)
        local mover = PUIMover or Primus.PUIMover
        if mover and mover.Register then
            mover:Register(microAnchor, "PUIHotbars_Micro", "PUIHotbars: Micro Menu Bar", "BARS")
        end
    else
        microAnchor:SetWidth(totalW)
        microAnchor:SetHeight(btnH)
    end

    for i = 1, 8 do
        local btn = _G[microList[i]]
        if btn then
            btn:SetParent(microAnchor)
            btn:ClearAllPoints()
            btn:SetWidth(btnW)
            btn:SetHeight(btnH)
            btn:SetPoint("LEFT", microAnchor, "LEFT", (i - 1) * (btnW + spacing), 0)
            btn:Show()
        end
    end

    if hotbarsDB and hotbarsDB:Get("showMicro", true) then
        microAnchor:Show()
    else
        microAnchor:Hide()
    end

    -- Register with Core Hider for dynamic Zen combat fading
    Hider = Primus.Hider or Hider
    if Hider and Hider.RegisterDynamic then
        Hider:RegisterDynamic(microAnchor, "MicroMenu", {
            mode = "fade",
            fadeOnCombat = true,
            enableHoverPeek = true,
        })
    end

    self.microAnchor = microAnchor
    return microAnchor
end

-- =========================================================================
-- BAG BAR VIRTUALIZATION & SINGLE BAG (ONE-BAG) MODE
-- =========================================================================

function PUIHotbars:BuildBagBar()
    Hider = Primus.Hider or Hider
    local hotbarsDB = DB:GetNamespace("PUIHotbars")
    local isSingleBag = hotbarsDB and hotbarsDB:Get("singleBag", false)
    local showKeyring = hotbarsDB and hotbarsDB:Get("showKeyring", true)

    local bagList = {
        { name = "MainMenuBarBackpackButton", w = 37, h = 37, isBag = true,  showInSingle = true },
        { name = "CharacterBag0Slot",         w = 37, h = 37, isBag = true,  showInSingle = false },
        { name = "CharacterBag1Slot",         w = 37, h = 37, isBag = true,  showInSingle = false },
        { name = "CharacterBag2Slot",         w = 37, h = 37, isBag = true,  showInSingle = false },
        { name = "CharacterBag3Slot",         w = 37, h = 37, isBag = true,  showInSingle = false },
        { name = "KeyRingButton",             w = 18, h = 39, isBag = false, showInSingle = showKeyring },
    }

    local spacing = 4
    local activeButtons = {}
    local totalW = 0

    for i = 1, 6 do
        local info = bagList[i]
        local shouldShow = true
        if isSingleBag then
            shouldShow = info.showInSingle
        elseif info.name == "KeyRingButton" then
            shouldShow = showKeyring
        end

        local btn = _G[info.name]
        if shouldShow then
            -- Unsuppress if previously in Graveyard
            if Hider and Hider.Unsuppress and Hider:IsSuppressed(btn) then
                Hider:Unsuppress(btn, UIParent)
            end
            table.insert(activeButtons, info)
            if totalW > 0 then
                totalW = totalW + spacing
            end
            totalW = totalW + info.w
        else
            -- Suppress permanently into the Graveyard to block Blizzard BAG_UPDATE loops
            if Hider and Hider.Suppress and btn then
                Hider:Suppress(btn)
            elseif btn then
                btn:Hide()
            end
        end
    end

    local totalH = 39

    if not bagAnchor then
        bagAnchor = CreateFrame("Frame", "Primus_PUIHotbars_BagBar", UIParent)
        bagAnchor:SetWidth(totalW > 0 and totalW or 37)
        bagAnchor:SetHeight(totalH)
        bagAnchor:SetFrameStrata("MEDIUM")
        bagAnchor:SetFrameLevel(2)
        bagAnchor:SetAlpha(1.0)
        bagAnchor:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -6, 68)
        local mover = PUIMover or Primus.PUIMover
        if mover and mover.Register then
            mover:Register(bagAnchor, "PUIHotbars_Bags", "PUIHotbars: Bag Bar", "BARS")
        end
    else
        bagAnchor:SetWidth(totalW > 0 and totalW or 37)
        bagAnchor:SetHeight(totalH)
        bagAnchor:SetFrameStrata("MEDIUM")
        bagAnchor:SetFrameLevel(2)
        bagAnchor:SetAlpha(1.0)
        local mover = PUIMover or Primus.PUIMover
        if mover and mover.ClampFrameToScreen then
            mover:ClampFrameToScreen(bagAnchor)
        end
    end

    local curX = 0
    local numActive = table.getn(activeButtons)
    for idx = 1, numActive do
        local info = activeButtons[idx]
        local btn = _G[info.name]
        if btn then
            btn:SetParent(bagAnchor)
            btn:ClearAllPoints()
            btn:SetWidth(info.w)
            btn:SetHeight(info.h)
            btn:SetPoint("LEFT", bagAnchor, "LEFT", curX, 0)
            curX = curX + info.w + spacing

            if info.isBag then
                -- 1-Pixel Border Overlay for Bag Slots
                if not btn._primusBorder then
                    local b = CreateFrame("Frame", nil, btn)
                    b:SetAllPoints(btn)
                    b:SetBackdrop(Media:Fetch("border", "1Pixel"))
                    b:SetBackdropColor(0, 0, 0, 0)
                    b:SetBackdropBorderColor(0.22, 0.22, 0.28, 1.0)
                    b:SetFrameLevel(btn:GetFrameLevel() + 2)
                    btn._primusBorder = b
                end

                -- Pure Scaling: Native uncropped texture coordinates (0, 1, 0, 1)
                local icon = _G[btn:GetName() .. "IconTexture"] or _G[btn:GetName() .. "Icon"]
                if icon then
                    if type(icon.SetTexCoord) == "function" then
                        icon:SetTexCoord(0.0, 1.0, 0.0, 1.0)
                    end
                    if type(icon.ClearAllPoints) == "function" then icon:ClearAllPoints() end
                    if type(icon.SetPoint) == "function" then
                        icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
                        icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
                    end
                end

                -- Refresh bag slot display & backdrop texture
                if btn:GetName() ~= "MainMenuBarBackpackButton" and PaperDollItemSlotButton_Update then
                    local origThis = this
                    this = btn
                    PaperDollItemSlotButton_Update()
                    this = origThis
                end
            else
                -- KeyRing Button Aspect-Ratio & Texture Atlas Normalization
                if btn:GetName() == "KeyRingButton" then
                    local normal = btn:GetNormalTexture()
                    if normal and type(normal.SetTexCoord) == "function" then
                        normal:SetTexCoord(0.0, 0.5625, 0.0, 0.609375)
                    end
                    local pushed = btn:GetPushedTexture()
                    if pushed and type(pushed.SetTexCoord) == "function" then
                        pushed:SetTexCoord(0.0, 0.5625, 0.0, 0.609375)
                    end
                    local highlight = btn:GetHighlightTexture()
                    if highlight and type(highlight.SetTexCoord) == "function" then
                        highlight:SetTexCoord(0.0, 0.5625, 0.0, 0.609375)
                    end
                    if KeyRingButtonItemAnim then
                        KeyRingButtonItemAnim:ClearAllPoints()
                        KeyRingButtonItemAnim:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
                    end
                end
            end

            btn:SetAlpha(1.0)
            btn:Show()
        end
    end

    -- Hook Backpack Click in Single Bag Mode to toggle all inventory bags
    if not PUIHotbars._backpackHooked and MainMenuBarBackpackButton then
        PUIHotbars._backpackHooked = true
        local orig_OnClick = MainMenuBarBackpackButton:GetScript("OnClick")
        MainMenuBarBackpackButton:SetScript("OnClick", function()
            local cfg = DB:GetNamespace("PUIHotbars")
            if cfg and cfg:Get("singleBag", false) then
                if IsBagOpen(0) and IsBagOpen(1) and IsBagOpen(2) and IsBagOpen(3) and IsBagOpen(4) then
                    CloseAllBags()
                else
                    OpenAllBags()
                end
            else
                if orig_OnClick then
                    orig_OnClick()
                else
                    ToggleBackpack()
                end
            end
        end)
    end

    if hotbarsDB and hotbarsDB:Get("showBags", true) then
        bagAnchor:Show()
    else
        bagAnchor:Hide()
    end

    -- Register with Core Hider for dynamic Zen combat fading
    if Hider and Hider.RegisterDynamic then
        Hider:RegisterDynamic(bagAnchor, "BagBar", {
            mode = "fade",
            fadeOnCombat = true,
            enableHoverPeek = true,
        })
    end

    self.bagAnchor = bagAnchor
    return bagAnchor
end
