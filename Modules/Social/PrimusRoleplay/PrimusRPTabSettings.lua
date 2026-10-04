--[[
    PrimusUI: PUIRoleplay Profile Tab 7 - Profiles & Settings (PUIRPTabSettings.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (Profile Slots, OOC Notes & Private GM Notes)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIRoleplay = Primus.PUIRoleplay or {}
Primus.PUIRoleplay = PUIRoleplay

local Sheet = PUIRoleplay.Sheet or {}
PUIRoleplay.Sheet = Sheet

local SheetTabs = Sheet.Tabs or {}
Sheet.Tabs = SheetTabs

--------------------------------------------------------------------------------
-- Build Tab Panel 7: Character Profiles & Notes
--------------------------------------------------------------------------------
function SheetTabs:BuildPanel7(parent, f)
    local p7 = CreateFrame("Frame", nil, parent)
    p7:SetAllPoints(parent)
    p7:Hide()
    f.panel7 = p7

    local profHeader = p7:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profHeader:SetPoint("TOPLEFT", p7, "TOPLEFT", 10, -8)
    profHeader:SetText("|cff00e5ffCharacter Profile Slots (Saved per Character):|r")

    p7.profBtns = {}
    for i = 0, 3 do
        local pBtn = CreateFrame("Button", nil, p7)
        pBtn:SetWidth(110)
        pBtn:SetHeight(22)
        pBtn:SetPoint("TOPLEFT", profHeader, "BOTTOMLEFT", i * 118, -4)
        pBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })

        local pbText = pBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pbText:SetPoint("CENTER", pBtn, "CENTER", 0, 0)
        pbText:SetText("Profile " .. i)
        pBtn.text = pbText
        pBtn.slot = tostring(i)

        pBtn:SetScript("OnClick", function()
            if Sheet:IsViewingSelf() then
                PUIRoleplay:SetActiveProfileSlot(this.slot)
                Sheet:Refresh()
            end
        end)
        p7.profBtns[i] = pBtn
    end

    -- Addon Importer & Code Converter Action Buttons
    local importAddonBtn = CreateFrame("Button", nil, p7)
    importAddonBtn:SetWidth(232)
    importAddonBtn:SetHeight(22)
    importAddonBtn:SetPoint("TOPLEFT", profHeader, "BOTTOMLEFT", 0, -32)
    importAddonBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    importAddonBtn:SetBackdropColor(0.08, 0.22, 0.32, 0.95)
    importAddonBtn:SetBackdropBorderColor(0.0, 0.75, 1.0, 1.0)
    local iaTxt = importAddonBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    iaTxt:SetPoint("CENTER", importAddonBtn, "CENTER", 0, 0)
    iaTxt:SetText("|cff00ccff[Import from TurtleRP / MRP / TRP]|r")
    importAddonBtn:SetScript("OnClick", function()
        if PUIRoleplay.Importer and PUIRoleplay.Importer.Open then
            PUIRoleplay.Importer:Open()
        end
    end)
    p7.importAddonBtn = importAddonBtn

    local importCodeBtn = CreateFrame("Button", nil, p7)
    importCodeBtn:SetWidth(232)
    importCodeBtn:SetHeight(22)
    importCodeBtn:SetPoint("LEFT", importAddonBtn, "RIGHT", 14, 0)
    importCodeBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    importCodeBtn:SetBackdropColor(0.18, 0.14, 0.08, 0.95)
    importCodeBtn:SetBackdropBorderColor(1.0, 0.75, 0.20, 1.0)
    local icTxt = importCodeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    icTxt:SetPoint("CENTER", importCodeBtn, "CENTER", 0, 0)
    icTxt:SetText("|cffffd100[Export / Import Code String]|r")
    importCodeBtn:SetScript("OnClick", function()
        if PUIRoleplay.Importer and PUIRoleplay.Importer.OpenStringModal then
            PUIRoleplay.Importer:OpenStringModal()
        end
    end)
    p7.importCodeBtn = importCodeBtn

    local oocHeader = p7:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    oocHeader:SetPoint("TOPLEFT", importAddonBtn, "BOTTOMLEFT", 0, -8)
    oocHeader:SetText("|cff55ff88Public OOC Notes (Broadcasted over Wire):|r")

    local oocEB = self:CreateStyledEditBox(p7, 478, 20)
    oocEB:SetPoint("TOPLEFT", oocHeader, "BOTTOMLEFT", 0, -2)
    oocEB:SetScript("OnTextChanged", function()
        if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
            local p = PUIRoleplay:GetMyProfile()
            p.ooc_notes = this:GetText()
            p.keyM = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end
    end)
    p7.oocEB = oocEB

    local notesHeader = p7:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    notesHeader:SetPoint("TOPLEFT", oocEB, "BOTTOMLEFT", 0, -8)
    notesHeader:SetText("|cffffd100Private Character / GM Notes (Saved Locally):|r")

    local notesScrollBg = self:Create1PxBackdrop(p7, 0.04, 0.04, 0.07, 0.95, 0.28, 0.28, 0.35, 1.0)
    notesScrollBg:SetPoint("TOPLEFT", notesHeader, "BOTTOMLEFT", 0, -4)
    notesScrollBg:SetPoint("BOTTOMRIGHT", p7, "BOTTOMRIGHT", -10, 10)

    local notesScroll = CreateFrame("ScrollFrame", "Primus_PUIRPSheet_NotesScroll", p7, "UIPanelScrollFrameTemplate")
    notesScroll:SetPoint("TOPLEFT", notesScrollBg, "TOPLEFT", 4, -4)
    notesScroll:SetPoint("BOTTOMRIGHT", notesScrollBg, "BOTTOMRIGHT", -22, 4)

    local notesEB = CreateFrame("EditBox", nil, notesScroll)
    notesEB:SetWidth(446)
    notesEB:SetHeight(800)
    notesEB:SetMultiLine(true)
    notesEB:SetAutoFocus(false)
    notesEB:SetFontObject(GameFontHighlightSmall)
    notesEB:SetTextColor(1.0, 1.0, 1.0, 1.0)
    notesEB:SetTextInsets(4, 4, 4, 4)
    notesScroll:SetScrollChild(notesEB)
    p7.notesEB = notesEB

    notesScrollBg:SetScript("OnMouseDown", function() notesEB:SetFocus() end)
    notesEB:SetScript("OnTextChanged", function()
        if ScrollingEdit_OnTextChanged then ScrollingEdit_OnTextChanged(notesScroll) end
        if f.isRefreshing ~= true then
            local target = Sheet:GetTargetPlayer() or UnitName("player")
            PUIRoleplay:SetCharacterNote(target, this:GetText())
        end
    end)
    notesEB:SetScript("OnEscapePressed", function() this:ClearFocus() end)
end
