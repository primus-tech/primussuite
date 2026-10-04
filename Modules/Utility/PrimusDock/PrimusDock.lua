--[[
    PrimusUI Module: PUIDock (Curated UI Mover & Blizzard Element Hider)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides clean, non-cluttered frame moving for primary HUD elements,
    with safe, crash-proof Blizzard FrameXML anchor stabilization and
    comprehensive Blizzard art & element stripping (Griffons, Bars, Menus).
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIDock = Primus.PUIDock or {}
Primus.PUIDock = PUIDock
_G.PUIDock = PUIDock
Primus:RegisterModule("PUIDock", PUIDock, "Utility")

local PUIMover = Primus.PUIMover
local DB      = Primus.DB
local Utils   = Primus.Utils
local Events  = Primus.Events
local Console = Primus.Console
local Debug   = Primus.Debug

-- Database for custom frame scales, hidden states, and Blizzard element toggles
local dockDB = DB:RegisterNamespace("PUIDock", {
    scales = {},
    hidden = {},
    customRegistered = {},
    hideGriffons = true,
    hidePageArrows = true,
    hideMicroMenu = false,
    hideBagBar = false,
    hideBarArt = true,
    hideXpBar = true,
    hideCastBar = true,
})

-- Clean, Curated Primary HUD Containers Catalog (Excludes bars & combat HUD managed by PUIHotbars & PUIHud)
PUIDock.BlizzardCatalog = {
    -- Secondary Unit Frames
    { frame = "PartyMemberFrame1", name = "Party Member 1" },
    { frame = "PartyMemberFrame2", name = "Party Member 2" },
    { frame = "PartyMemberFrame3", name = "Party Member 3" },
    { frame = "PartyMemberFrame4", name = "Party Member 4" },
    { frame = "ComboFrame", name = "Combo Points" },

    -- HUD & System (Minimap is exclusively managed by PUIMinimapper)
    { frame = "DurabilityFrame", name = "Durability Doll" },
    { frame = "QuestWatchFrame", name = "Quest Tracker" },
    { frame = "UIErrorsFrame", name = "UI Warnings / Errors" },
    { frame = "WorldStateAlwaysUpFrame", name = "Score / World State" },
    { frame = "MirrorTimer1", name = "Breath / Fatigue Bar" },
    { frame = "ChatFrame1", name = "Chat Window" },
}

-- =========================================================================
-- SPECIALIZED BLIZZARD ANCHOR STABILIZERS
-- =========================================================================

local function SetupBlizzardHooks()
    -- Stabilize QuestWatch
    if QuestWatchFrame then
        QuestWatchFrame:SetWidth(200)
        QuestWatchFrame:SetHeight(150)
    end

    -- Stabilize Durability
    if DurabilityFrame then
        DurabilityFrame:SetWidth(60)
        DurabilityFrame:SetHeight(60)
    end
end

-- =========================================================================
-- PUIDOCK CORE API
-- =========================================================================

-- Hook a specific frame cleanly
function PUIDock:HookFrame(frameObj, frameKey, friendlyName)
    if not frameObj then return false end
    friendlyName = friendlyName or frameKey

    -- Register with PUIMover
    local mover = PUIMover or Primus.PUIMover
    if mover and mover.Register then
        mover:Register(frameObj, frameKey, friendlyName, "UTILITY")
    end

    -- Apply saved scale
    local scales = dockDB:Get("scales")
    if scales and scales[frameKey] then
        frameObj:SetScale(scales[frameKey])
    end

    -- Apply saved hidden state
    local hidden = dockDB:Get("hidden")
    if hidden and hidden[frameKey] then
        frameObj:Hide()
    end

    return true
end

-- Hook all curated Blizzard containers
function PUIDock:HookCuratedFrames()
    for _, item in ipairs(self.BlizzardCatalog) do
        local f = _G[item.frame]
        if f then
            self:HookFrame(f, item.frame, item.name)
        end
    end
end

-- Hook whatever specific frame the mouse is hovering over (On-Demand)
function PUIDock:HookMouseover()
    local focus = GetMouseFocus()
    if not focus or focus == UIParent or focus == WorldFrame then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIDock]: No valid frame under cursor to hook.", "ff4444"))
        return
    end

    local name = focus:GetName()
    if not name then
        name = "AnonymousFrame_" .. tostring(focus)
    end

    self:HookFrame(focus, name, name)
    local mover = PUIMover or Primus.PUIMover
    if mover and mover.Unlock then mover:Unlock("UTILITY") end
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIDock]: Hooked frame: " .. name, "69ccf0"))
end

-- Scale a specific frame
function PUIDock:SetFrameScale(frameKey, scale)
    local entry = _G[frameKey]
    if not entry then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIDock]: Frame not found: " .. tostring(frameKey), "ff4444"))
        return
    end

    scale = Utils.Clamp(tonumber(scale) or 1.0, 0.2, 3.0)
    entry:SetScale(scale)

    local scales = dockDB:Get("scales")
    scales[frameKey] = scale
    dockDB:Set("scales", scales)
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIDock]: Set scale of %s to %.2f", frameKey, scale), "69ccf0"))
end

-- Toggle arbitrary frame visibility
function PUIDock:ToggleFrameVisibility(frameKey)
    local entry = _G[frameKey]
    if not entry then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIDock]: Frame not found: " .. tostring(frameKey), "ff4444"))
        return
    end

    local hidden = dockDB:Get("hidden")
    if entry:IsShown() then
        entry:Hide()
        hidden[frameKey] = true
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIDock]: Hidden " .. frameKey, "ffbb33"))
    else
        entry:Show()
        hidden[frameKey] = nil
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIDock]: Shown " .. frameKey, "69ccf0"))
    end
    dockDB:Set("hidden", hidden)
end

-- =========================================================================
-- FOOLPROOF BLIZZARD ART & ELEMENT STRIPPER (Vanilla 1.12.1 Engine)
-- =========================================================================

-- Intercept .Show and .SetAlpha calls on Region/Frame/Texture objects
local function LockRegionHide(obj, isHiddenFunc)
    if not obj or obj._primusRegionHooked then return end
    obj._primusRegionHooked = true

    if obj.Show then
        local origShow = obj.Show
        obj.Show = function(self)
            if isHiddenFunc and isHiddenFunc() then
                if self.Hide then self:Hide() end
                return
            end
            if origShow then origShow(self) end
        end
    end

    if obj.SetAlpha then
        local origSetAlpha = obj.SetAlpha
        obj.SetAlpha = function(self, a)
            if isHiddenFunc and isHiddenFunc() then
                if origSetAlpha then origSetAlpha(self, 0) end
                return
            end
            if origSetAlpha then origSetAlpha(self, a) end
        end
    end
end

local function ApplyTextureVisibility(tex, isHidden, defWidth, defHeight)
    if not tex then return end
    if isHidden then
        if tex.SetAlpha then tex:SetAlpha(0) end
        if tex.SetVertexColor then tex:SetVertexColor(1, 1, 1, 0) end
        if tex.Hide then tex:Hide() end
    else
        if defWidth and tex.SetWidth then tex:SetWidth(defWidth) end
        if defHeight and tex.SetHeight then tex:SetHeight(defHeight) end
        if tex.SetVertexColor then tex:SetVertexColor(1, 1, 1, 1) end
        if tex.SetAlpha then tex:SetAlpha(1) end
        if tex.Show then tex:Show() end
    end
end

local function ApplyFrameVisibility(frame, isHidden, defWidth, defHeight, isInteractive)
    if not frame then return end
    if isHidden then
        if frame.EnableMouse then frame:EnableMouse(false) end
        if frame.SetAlpha then frame:SetAlpha(0) end
        if frame.Hide then frame:Hide() end
    else
        if defWidth and frame.SetWidth then frame:SetWidth(defWidth) end
        if defHeight and frame.SetHeight then frame:SetHeight(defHeight) end
        if isInteractive and frame.EnableMouse then
            frame:EnableMouse(true)
        elseif not isInteractive and frame.EnableMouse then
            frame:EnableMouse(false)
        end
        if frame.SetAlpha then frame:SetAlpha(1) end
        if frame.Show then frame:Show() end
    end
end

-- 1. Action Bar End-Cap Griffons
function PUIDock:SetGriffonsHidden(hide)
    dockDB:Set("hideGriffons", hide and true or false)
    local isHidden = function() return dockDB:Get("hideGriffons") end

    local leftCap = MainMenuBarLeftEndCap or (MainMenuBarArtFrame and MainMenuBarArtFrame.LeftEndCap)
    if leftCap then
        LockRegionHide(leftCap, isHidden)
        ApplyTextureVisibility(leftCap, hide, 128, 128)
    end

    local rightCap = MainMenuBarRightEndCap or (MainMenuBarArtFrame and MainMenuBarArtFrame.RightEndCap)
    if rightCap then
        LockRegionHide(rightCap, isHidden)
        ApplyTextureVisibility(rightCap, hide, 128, 128)
    end
end

-- 2. Action Bar Page Scrolling Buttons & Page Number
function PUIDock:SetPageArrowsHidden(hide)
    dockDB:Set("hidePageArrows", hide and true or false)
    local isHidden = function() return dockDB:Get("hidePageArrows") end

    if ActionBarUpButton then
        LockRegionHide(ActionBarUpButton, isHidden)
        ApplyFrameVisibility(ActionBarUpButton, hide, nil, nil, true)
    end

    if ActionBarDownButton then
        LockRegionHide(ActionBarDownButton, isHidden)
        ApplyFrameVisibility(ActionBarDownButton, hide, nil, nil, true)
    end

    if MainMenuBarPageNumber then
        if not MainMenuBarPageNumber._primusHooked then
            MainMenuBarPageNumber._primusHooked = true
            local origSetText = MainMenuBarPageNumber.SetText
            MainMenuBarPageNumber._origSetText = origSetText
            MainMenuBarPageNumber.SetText = function(self, text)
                if isHidden() then
                    if origSetText then origSetText(self, "") end
                    return
                end
                if origSetText then origSetText(self, text) end
            end
        end
        if hide then
            if MainMenuBarPageNumber._origSetText then
                MainMenuBarPageNumber._origSetText(MainMenuBarPageNumber, "")
            end
            if MainMenuBarPageNumber.SetAlpha then MainMenuBarPageNumber:SetAlpha(0) end
        else
            if MainMenuBarPageNumber.SetAlpha then MainMenuBarPageNumber:SetAlpha(1) end
            if MainMenuBar_UpdatePageNum then MainMenuBar_UpdatePageNum() end
        end
    end
end

-- 3. Micro Menu Buttons
local microButtons = {
    "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton",
    "QuestLogMicroButton", "SocialsMicroButton", "WorldMapMicroButton",
    "MainMenuMicroButton", "HelpMicroButton", "MainMenuBarPerformanceBarFrame"
}

function PUIDock:SetMicroMenuHidden(hide)
    dockDB:Set("hideMicroMenu", hide and true or false)
    local isHidden = function() return dockDB:Get("hideMicroMenu") end

    for _, name in ipairs(microButtons) do
        local el = _G[name]
        if el then
            LockRegionHide(el, isHidden)
            ApplyFrameVisibility(el, hide, 28, 58, true)
        end
    end
end

-- 4. Bag Bar Slots & Keyring
local bagSlots = {
    "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
    "CharacterBag2Slot", "CharacterBag3Slot", "KeyRingButton"
}

function PUIDock:SetBagBarHidden(hide)
    dockDB:Set("hideBagBar", hide and true or false)
    local isHidden = function() return dockDB:Get("hideBagBar") end

    for _, name in ipairs(bagSlots) do
        local el = _G[name]
        if el then
            LockRegionHide(el, isHidden)
            ApplyFrameVisibility(el, hide, 37, 37, true)
        end
    end
end

-- 5. Action Bar Background Textures & Borders
local barArtElements = {
    "MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3",
    "MainMenuMaxLevelBar0", "MainMenuMaxLevelBar1", "MainMenuMaxLevelBar2", "MainMenuMaxLevelBar3",
    "BonusActionBarTexture0", "BonusActionBarTexture1",
    "ShapeshiftBarLeft", "ShapeshiftBarMiddle", "ShapeshiftBarRight",
    "PetActionBarFrameSlidingActionBarTexture0", "PetActionBarFrameSlidingActionBarTexture1",
    "SlidingActionBarTexture0", "SlidingActionBarTexture1"
}

function PUIDock:SetActionBarArtHidden(hide)
    dockDB:Set("hideBarArt", hide and true or false)
    local isHidden = function() return dockDB:Get("hideBarArt") end

    for _, name in ipairs(barArtElements) do
        local tex = _G[name]
        if tex then
            LockRegionHide(tex, isHidden)
            ApplyTextureVisibility(tex, hide, 256, 43)
        end
    end

    if MainMenuBarOverlayFrame then
        LockRegionHide(MainMenuBarOverlayFrame, isHidden)
        ApplyFrameVisibility(MainMenuBarOverlayFrame, hide, nil, nil, false)
        if MainMenuBarOverlayFrame.EnableMouse then
            MainMenuBarOverlayFrame:EnableMouse(false)
        end
    end
end

-- 6. Experience & Reputation Watch Bars
function PUIDock:SetXpBarHidden(hide)
    dockDB:Set("hideXpBar", hide and true or false)
    local isHidden = function() return dockDB:Get("hideXpBar") end

    if MainMenuExpBar then
        LockRegionHide(MainMenuExpBar, isHidden)
        ApplyFrameVisibility(MainMenuExpBar, hide, nil, nil, true)
    end

    if ReputationWatchBar then
        LockRegionHide(ReputationWatchBar, isHidden)
        ApplyFrameVisibility(ReputationWatchBar, hide, nil, nil, true)
    end

    if ExhaustionTick then
        if hide then
            ExhaustionTick:Hide()
            if ExhaustionTick.SetAlpha then ExhaustionTick:SetAlpha(0) end
        else
            if ExhaustionTick.SetAlpha then ExhaustionTick:SetAlpha(1) end
            ExhaustionTick:Show()
        end
    end
end

-- 7. Default Blizzard Cast Bar
function PUIDock:SetCastBarHidden(hide)
    dockDB:Set("hideCastBar", hide and true or false)
    local isHidden = function() return dockDB:Get("hideCastBar", true) end

    if CastingBarFrame then
        LockRegionHide(CastingBarFrame, isHidden)
        if hide then
            CastingBarFrame:UnregisterAllEvents()
            CastingBarFrame:Hide()
            if CastingBarFrame.SetAlpha then CastingBarFrame:SetAlpha(0) end
            if not PUIDock._origCastingBarUpdate then
                PUIDock._origCastingBarUpdate = CastingBarFrame:GetScript("OnUpdate")
            end
            CastingBarFrame:SetScript("OnUpdate", nil)
            CastingBarFrame:ClearAllPoints()
            CastingBarFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, -5000)
            CastingBarFrame:SetScript("OnShow", function() this:Hide() end)
        else
            CastingBarFrame:SetScript("OnShow", nil)
            if PUIDock._origCastingBarUpdate then
                CastingBarFrame:SetScript("OnUpdate", PUIDock._origCastingBarUpdate)
            end
            CastingBarFrame:ClearAllPoints()
            CastingBarFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 140)
            if CastingBarFrame.SetAlpha then CastingBarFrame:SetAlpha(1) end
            CastingBarFrame:RegisterEvent("SPELLCAST_START")
            CastingBarFrame:RegisterEvent("SPELLCAST_STOP")
            CastingBarFrame:RegisterEvent("SPELLCAST_FAILED")
            CastingBarFrame:RegisterEvent("SPELLCAST_INTERRUPTED")
            CastingBarFrame:RegisterEvent("SPELLCAST_DELAYED")
            CastingBarFrame:RegisterEvent("SPELLCAST_CHANNEL_START")
            CastingBarFrame:RegisterEvent("SPELLCAST_CHANNEL_UPDATE")
            CastingBarFrame:RegisterEvent("SPELLCAST_CHANNEL_STOP")
        end
    end
end

-- Master application function
function PUIDock:ApplyElementHiding()
    self:SetGriffonsHidden(dockDB:Get("hideGriffons", true))
    self:SetPageArrowsHidden(dockDB:Get("hidePageArrows", true))
    self:SetMicroMenuHidden(dockDB:Get("hideMicroMenu", false))
    self:SetBagBarHidden(dockDB:Get("hideBagBar", false))
    self:SetActionBarArtHidden(dockDB:Get("hideBarArt", true))
    self:SetXpBarHidden(dockDB:Get("hideXpBar", true))
    self:SetCastBarHidden(dockDB:Get("hideCastBar", true))
end

-- Hook Blizzard FrameXML redraw events to ensure hidden state is persistently enforced
local function HookBlizzardRedraws()
    if PUIDock._hookedRedraws then return end
    PUIDock._hookedRedraws = true

    -- Hook MainMenuBar OnShow
    if MainMenuBar then
        local origOnShow = MainMenuBar:GetScript("OnShow")
        MainMenuBar:SetScript("OnShow", function()
            if origOnShow then origOnShow() end
            PUIDock:ApplyElementHiding()
        end)
    end

    if MainMenuBarArtFrame then
        local origArtShow = MainMenuBarArtFrame:GetScript("OnShow")
        MainMenuBarArtFrame:SetScript("OnShow", function()
            if origArtShow then origArtShow() end
            PUIDock:ApplyElementHiding()
        end)
    end

    if UIParent_ManageFramePositions then
        local origManage = UIParent_ManageFramePositions
        UIParent_ManageFramePositions = function()
            if origManage then origManage() end
            PUIDock:ApplyElementHiding()
            local mover = Primus.PUIMover or PUIMover
            if mover and mover.RestorePosition then
                mover:RestorePosition("QuestWatchFrame")
                mover:RestorePosition("DurabilityFrame")
                mover:RestorePosition("WorldStateAlwaysUpFrame")
            end
        end
    end

    if ChangeActionBarPage then
        local origChange = ChangeActionBarPage
        ChangeActionBarPage = function(page)
            if origChange then origChange(page) end
            PUIDock:ApplyElementHiding()
        end
    end

    if MainMenuBar_UpdateKeyRing then
        local origKey = MainMenuBar_UpdateKeyRing
        MainMenuBar_UpdateKeyRing = function()
            if origKey then origKey() end
            if dockDB:Get("hideBagBar") then
                PUIDock:SetBagBarHidden(true)
            end
        end
    end

    if ShowBonusActionBar then
        local origShowBonus = ShowBonusActionBar
        ShowBonusActionBar = function()
            if origShowBonus then origShowBonus() end
            if dockDB:Get("hideBarArt") then
                PUIDock:SetActionBarArtHidden(true)
            end
        end
    end

    if HideBonusActionBar then
        local origHideBonus = HideBonusActionBar
        HideBonusActionBar = function()
            if origHideBonus then origHideBonus() end
            if dockDB:Get("hideBarArt") then
                PUIDock:SetActionBarArtHidden(true)
            end
        end
    end

    if ShapeshiftBar_Update then
        local origSS = ShapeshiftBar_Update
        ShapeshiftBar_Update = function()
            if origSS then origSS() end
            if dockDB:Get("hideBarArt") then
                PUIDock:SetActionBarArtHidden(true)
            end
        end
    end

    if PetActionBar_Update then
        local origPet = PetActionBar_Update
        PetActionBar_Update = function()
            if origPet then origPet() end
            if dockDB:Get("hideBarArt") then
                PUIDock:SetActionBarArtHidden(true)
            end
        end
    end

    if MainMenuBar_UpdateArt then
        local origUpdateArt = MainMenuBar_UpdateArt
        MainMenuBar_UpdateArt = function()
            if origUpdateArt then origUpdateArt() end
            PUIDock:ApplyElementHiding()
        end
    end
end

-- =========================================================================
-- OPTIONS FLARE REGISTRATION
-- =========================================================================

function PUIDock:RegisterOptionsFlare()
    local Options = Primus.Options
    if not Options or not Options.RegisterModuleOptions then return end

    Options:RegisterModuleOptions("PUIDock", "Utility", {
        title = "PUIDock: Frame Mover & Art Stripper",
        description = "Blizzard element suppression and secondary UI container positioning.",
        fields = {
            {
                key = "hideGriffons",
                label = "Hide Action Bar End-Cap Griffons",
                type = "checkbox",
                default = true,
                get = function() return dockDB:Get("hideGriffons", true) end,
                set = function(val) PUIDock:SetGriffonsHidden(val) end,
            },
            {
                key = "hidePageArrows",
                label = "Hide Action Bar Page Arrows",
                type = "checkbox",
                default = true,
                get = function() return dockDB:Get("hidePageArrows", true) end,
                set = function(val) PUIDock:SetPageArrowsHidden(val) end,
            },
            {
                key = "hideBarArt",
                label = "Hide Blizzard Action Bar Background Art",
                type = "checkbox",
                default = true,
                get = function() return dockDB:Get("hideBarArt", true) end,
                set = function(val) PUIDock:SetActionBarArtHidden(val) end,
            },
            {
                key = "hideXpBar",
                label = "Hide Default Blizzard XP & Rep Bars",
                type = "checkbox",
                default = true,
                get = function() return dockDB:Get("hideXpBar", true) end,
                set = function(val) PUIDock:SetXpBarHidden(val) end,
            },
            {
                key = "hideCastBar",
                label = "Hide Default Blizzard Cast Bar",
                type = "checkbox",
                default = true,
                get = function() return dockDB:Get("hideCastBar", true) end,
                set = function(val) PUIDock:SetCastBarHidden(val) end,
            },
        },
    })
end

-- =========================================================================
-- LIFECYCLE & EVENT DISPATCH
-- =========================================================================

function PUIDock:OnInitialize()
    self:RegisterOptionsFlare()
    SetupBlizzardHooks()
    self:HookCuratedFrames()
    HookBlizzardRedraws()
    self:ApplyElementHiding()

    -- Register Slash Commands
    Console:RegisterSubCommand("dock", function(argParam, parts)
        local mover = PUIMover or Primus.PUIMover
        if not argParam or argParam == "" then
            if mover and mover.ToggleLock then mover:ToggleLock() end
        elseif argParam == "mouse" or argParam == "hover" then
            PUIDock:HookMouseover()
        elseif parts[2] == "scale" and parts[3] and parts[4] then
            PUIDock:SetFrameScale(parts[3], parts[4])
        elseif parts[2] == "hide" and parts[3] then
            local target = string.lower(parts[3])
            if target == "griffons" or target == "griffon" or target == "endcaps" then
                local cur = dockDB:Get("hideGriffons")
                PUIDock:SetGriffonsHidden(not cur)
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIDock]: Griffons are now " .. (not cur and "HIDDEN" or "SHOWN"), "69ccf0"))
            elseif target == "arrows" or target == "page" or target == "pagenum" then
                local cur = dockDB:Get("hidePageArrows")
                PUIDock:SetPageArrowsHidden(not cur)
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIDock]: Page arrows are now " .. (not cur and "HIDDEN" or "SHOWN"), "69ccf0"))
            elseif target == "art" or target == "textures" or target == "border" then
                local cur = dockDB:Get("hideBarArt")
                PUIDock:SetActionBarArtHidden(not cur)
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIDock]: Action bar art is now " .. (not cur and "HIDDEN" or "SHOWN"), "69ccf0"))
            elseif target == "menu" or target == "micromenu" then
                local cur = dockDB:Get("hideMicroMenu")
                PUIDock:SetMicroMenuHidden(not cur)
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIDock]: Micro menu is now " .. (not cur and "HIDDEN" or "SHOWN"), "69ccf0"))
            elseif target == "bags" or target == "bagbar" then
                local cur = dockDB:Get("hideBagBar")
                PUIDock:SetBagBarHidden(not cur)
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIDock]: Bag bar is now " .. (not cur and "HIDDEN" or "SHOWN"), "69ccf0"))
            elseif target == "xp" or target == "rep" or target == "xpbar" then
                local cur = dockDB:Get("hideXpBar")
                PUIDock:SetXpBarHidden(not cur)
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIDock]: XP bar is now " .. (not cur and "HIDDEN" or "SHOWN"), "69ccf0"))
            elseif target == "castbar" or target == "cast" then
                local cur = dockDB:Get("hideCastBar")
                PUIDock:SetCastBarHidden(not cur)
                DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIDock]: Blizzard CastBar is now " .. (not cur and "HIDDEN" or "SHOWN"), "69ccf0"))
            else
                PUIDock:ToggleFrameVisibility(parts[3])
            end
        elseif _G[argParam] then
            PUIDock:HookFrame(_G[argParam], argParam, argParam)
            if mover and mover.Unlock then mover:Unlock("UTILITY") end
        else
            DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIDock]: Unknown command or frame: " .. tostring(argParam), "ff4444"))
        end
    end, "PUIDock utility management (/pui dock [mouse | hide griffons/arrows/art/menu/bags/xp | scale Frame 1.2 | FrameName])")
end

function PUIDock:OnEnable()
    Events:Register("PLAYER_ENTERING_WORLD", "PUIDock", function()
        HookBlizzardRedraws()
        PUIDock:ApplyElementHiding()
    end)
    self:ApplyElementHiding()
end

function PUIDock:OnDisable()
    Events:UnregisterOwner("PUIDock")
end

