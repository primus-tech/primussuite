--[[
    PrimusUI: PUIRoleplay Profile Tab 3 - Personality Traits Spectrum (PUIRPTabPersonality.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (TotalRP3-Compatible Spectrum Sliders & Custom Axes)
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

local personalityRows = {}

--------------------------------------------------------------------------------
-- Helper: Format Trait Bias Percentage
--------------------------------------------------------------------------------
local function FormatTraitStatus(val, leftName, rightName)
    local v = tonumber(val) or 10
    if v == 10 then
        return "|cffaaaaaaNeutral|r"
    elseif v < 10 then
        local pct = math.floor(((10 - v) / 10) * 100)
        return string.format("|cff00e5ff%d%% %s|r", pct, leftName or "Left")
    else
        local pct = math.floor(((v - 10) / 10) * 100)
        return string.format("|cffffaa00%d%% %s|r", pct, rightName or "Right")
    end
end

--------------------------------------------------------------------------------
-- Build Tab Panel 3: Personality Trait Sliders & Custom Axis Creator
--------------------------------------------------------------------------------
function SheetTabs:BuildPanel3(parent, f)
    local p3 = CreateFrame("Frame", nil, parent)
    p3:SetAllPoints(parent)
    p3:Hide()
    f.panel3 = p3

    -- Header Title
    local title = p3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", p3, "TOPLEFT", 10, -8)
    title:SetText("|cffffd100PSYCHOLOGICAL PROFILE & PERSONALITY SPECTRUM (TotalRP3):|r")

    -- Add Custom Trait Button
    local addBtn = CreateFrame("Button", nil, p3)
    addBtn:SetWidth(150)
    addBtn:SetHeight(20)
    addBtn:SetPoint("TOPRIGHT", p3, "TOPRIGHT", -10, -6)
    addBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    addBtn:SetBackdropColor(0.06, 0.35, 0.20, 0.95)
    addBtn:SetBackdropBorderColor(0.20, 0.85, 0.40, 1.0)

    local addTxt = addBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    addTxt:SetPoint("CENTER", addBtn, "CENTER", 0, 0)
    addTxt:SetText("+ Add Custom Axis")
    addBtn.text = addTxt

    addBtn:SetScript("OnEnter", function()
        this:SetBackdropColor(0.10, 0.50, 0.30, 1.0)
        this:SetBackdropBorderColor(0.40, 1.0, 0.60, 1.0)
    end)
    addBtn:SetScript("OnLeave", function()
        this:SetBackdropColor(0.06, 0.35, 0.20, 0.95)
        this:SetBackdropBorderColor(0.20, 0.85, 0.40, 1.0)
    end)
    addBtn:SetScript("OnClick", function()
        if not Sheet:IsViewingSelf() then return end
        local prof = PUIRoleplay:GetMyProfile()
        local traits = PUIRoleplay:GetPersonalityTraits(prof)
        local customId = "custom_" .. (table.getn(traits) + 1) .. "_" .. math.random(100, 999)

        table.insert(traits, {
            id = customId,
            leftName = "Custom Left",
            rightName = "Custom Right",
            leftIcon = "INV_Misc_QuestionMark",
            rightIcon = "INV_Misc_QuestionMark",
            value = 10,
            isCustom = true
        })

        prof.personality_traits = traits
        prof.keyP = PUIRoleplay:GenerateKey()
        PUIRoleplay:SaveMyProfile(prof)
        SheetTabs:RefreshPersonalityTab(f)
    end)
    p3.addBtn = addBtn

    local subTitle = p3:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subTitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    subTitle:SetText("|cff888888Drag sliders to adjust character skew. Center represents a neutral balance.|r")

    -- Scroll Frame for Personality Traits
    local scrollBg = self:Create1PxBackdrop(p3, 0.04, 0.04, 0.07, 0.95, 0.22, 0.24, 0.28, 1.0)
    scrollBg:SetPoint("TOPLEFT", subTitle, "BOTTOMLEFT", 0, -6)
    scrollBg:SetPoint("BOTTOMRIGHT", p3, "BOTTOMRIGHT", -6, 8)

    local scrollFrame = CreateFrame("ScrollFrame", "Primus_PUIRPSheet_PersonalityScroll", p3, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", scrollBg, "TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", scrollBg, "BOTTOMRIGHT", -22, 4)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(454)
    scrollChild:SetHeight(700)
    scrollFrame:SetScrollChild(scrollChild)
    p3.scrollChild = scrollChild
    p3.scrollFrame = scrollFrame

    SheetTabs:RefreshPersonalityTab(f)
end

--------------------------------------------------------------------------------
-- Refresh Personality Tab List
--------------------------------------------------------------------------------
function SheetTabs:RefreshPersonalityTab(f)
    local p3 = f.panel3
    if not p3 or not p3.scrollChild then return end

    local isSelf = Sheet:IsViewingSelf()
    local target = Sheet:GetTargetPlayer() or UnitName("player")
    local data = isSelf and PUIRoleplay:GetMyProfile() or PUIRoleplay:GetCharacterData(target)
    local traits = PUIRoleplay:GetPersonalityTraits(data)

    if p3.addBtn then
        if isSelf then p3.addBtn:Show() else p3.addBtn:Hide() end
    end

    -- Hide existing rows
    for _, r in ipairs(personalityRows) do
        r:Hide()
    end

    local trackWidth = 170
    local rowHeight = 46
    local startY = -4

    local count = table.getn(traits)
    p3.scrollChild:SetHeight(math.max(400, count * rowHeight + 20))

    for idx, trait in ipairs(traits) do
        local row = personalityRows[idx]
        if not row then
            row = CreateFrame("Frame", nil, p3.scrollChild)
            row:SetWidth(450)
            row:SetHeight(rowHeight - 4)
            row:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false, tileSize = 0, edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 }
            })
            row:SetBackdropColor(0.06, 0.06, 0.08, 0.85)
            row:SetBackdropBorderColor(0.18, 0.20, 0.24, 1.0)

            -- Left Icon Button
            local lIconBtn = CreateFrame("Button", nil, row)
            lIconBtn:SetWidth(26)
            lIconBtn:SetHeight(26)
            lIconBtn:SetPoint("LEFT", row, "LEFT", 6, 0)
            lIconBtn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false, tileSize = 0, edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 }
            })
            lIconBtn:SetBackdropColor(0, 0, 0, 1)
            lIconBtn:SetBackdropBorderColor(0.3, 0.3, 0.4, 1)

            local lTex = lIconBtn:CreateTexture(nil, "ARTWORK")
            lTex:SetPoint("TOPLEFT", lIconBtn, "TOPLEFT", 1, -1)
            lTex:SetPoint("BOTTOMRIGHT", lIconBtn, "BOTTOMRIGHT", -1, 1)
            lIconBtn.tex = lTex
            row.lIconBtn = lIconBtn

            -- Left Name
            local lNameEB = CreateFrame("EditBox", nil, row)
            lNameEB:SetWidth(90)
            lNameEB:SetHeight(18)
            lNameEB:SetPoint("LEFT", lIconBtn, "RIGHT", 4, 0)
            lNameEB:SetFontObject(GameFontHighlightSmall)
            lNameEB:SetAutoFocus(false)
            lNameEB:SetTextColor(0.0, 0.9, 1.0, 1.0)
            row.lNameEB = lNameEB

            -- Slider Track Container
            local track = CreateFrame("Frame", nil, row)
            track:SetWidth(trackWidth)
            track:SetHeight(14)
            track:SetPoint("LEFT", lNameEB, "RIGHT", 6, 0)
            track:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false, tileSize = 0, edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 }
            })
            track:SetBackdropColor(0.03, 0.03, 0.05, 1.0)
            track:SetBackdropBorderColor(0.28, 0.28, 0.35, 1.0)
            track:EnableMouse(true)
            row.track = track

            -- Center Neutral Line
            local centerLine = track:CreateTexture(nil, "ARTWORK")
            centerLine:SetWidth(2)
            centerLine:SetHeight(12)
            centerLine:SetPoint("CENTER", track, "CENTER", 0, 0)
            centerLine:SetTexture(0.5, 0.5, 0.6, 0.8)
            track.centerLine = centerLine

            -- Left Fill Texture (Cyan/Blue when < 10)
            local lFill = track:CreateTexture(nil, "BORDER")
            lFill:SetTexture(0.0, 0.75, 1.0, 0.65)
            track.lFill = lFill

            -- Right Fill Texture (Amber/Gold when > 10)
            local rFill = track:CreateTexture(nil, "BORDER")
            rFill:SetTexture(1.0, 0.65, 0.1, 0.65)
            track.rFill = rFill

            -- Slider Thumb Indicator
            local thumb = CreateFrame("Frame", nil, track)
            thumb:SetWidth(8)
            thumb:SetHeight(18)
            thumb:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false, tileSize = 0, edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 }
            })
            thumb:SetBackdropColor(1.0, 1.0, 1.0, 0.95)
            thumb:SetBackdropBorderColor(0.0, 0.85, 1.0, 1.0)
            track.thumb = thumb

            -- Status Readout Label (Centered above/below track)
            local statusLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            statusLbl:SetPoint("BOTTOM", track, "TOP", 0, 2)
            statusLbl:SetText("Neutral")
            row.statusLbl = statusLbl

            -- Right Name
            local rNameEB = CreateFrame("EditBox", nil, row)
            rNameEB:SetWidth(90)
            rNameEB:SetHeight(18)
            rNameEB:SetPoint("LEFT", track, "RIGHT", 6, 0)
            rNameEB:SetFontObject(GameFontHighlightSmall)
            rNameEB:SetAutoFocus(false)
            rNameEB:SetTextColor(1.0, 0.75, 0.2, 1.0)
            row.rNameEB = rNameEB

            -- Right Icon Button
            local rIconBtn = CreateFrame("Button", nil, row)
            rIconBtn:SetWidth(26)
            rIconBtn:SetHeight(26)
            rIconBtn:SetPoint("LEFT", rNameEB, "RIGHT", 4, 0)
            rIconBtn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false, tileSize = 0, edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 }
            })
            rIconBtn:SetBackdropColor(0, 0, 0, 1)
            rIconBtn:SetBackdropBorderColor(0.3, 0.3, 0.4, 1)

            local rTex = rIconBtn:CreateTexture(nil, "ARTWORK")
            rTex:SetPoint("TOPLEFT", rIconBtn, "TOPLEFT", 1, -1)
            rTex:SetPoint("BOTTOMRIGHT", rIconBtn, "BOTTOMRIGHT", -1, 1)
            rIconBtn.tex = rTex
            row.rIconBtn = rIconBtn

            -- Delete Custom Trait Button [X]
            local delBtn = CreateFrame("Button", nil, row)
            delBtn:SetWidth(16)
            delBtn:SetHeight(16)
            delBtn:SetPoint("LEFT", rIconBtn, "RIGHT", 4, 0)
            delBtn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false, tileSize = 0, edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 }
            })
            delBtn:SetBackdropColor(0.4, 0.05, 0.05, 0.9)
            delBtn:SetBackdropBorderColor(0.8, 0.2, 0.2, 1.0)

            local dTxt = delBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            dTxt:SetPoint("CENTER", delBtn, "CENTER", 0, 0)
            dTxt:SetText("x")
            delBtn.text = dTxt
            row.delBtn = delBtn

            personalityRows[idx] = row
        end

        row:SetPoint("TOPLEFT", p3.scrollChild, "TOPLEFT", 0, startY - (idx - 1) * rowHeight)
        row:Show()

        -- Assign Data & Values
        row.traitIndex = idx
        row.traitData = trait

        -- Left / Right Icons
        local lIconName = trait.leftIcon or "INV_Misc_QuestionMark"
        local rIconName = trait.rightIcon or "INV_Misc_QuestionMark"
        row.lIconBtn.tex:SetTexture("Interface\\Icons\\" .. lIconName)
        row.rIconBtn.tex:SetTexture("Interface\\Icons\\" .. rIconName)

        row.lIconBtn:SetScript("OnClick", function()
            if Sheet:IsViewingSelf() then
                local currentIdx = row.traitIndex
                Sheet:OpenIconPicker(function(selectedIconIndex)
                    local iconName = PUIRoleplay.Icons[selectedIconIndex] or "INV_Misc_QuestionMark"
                    local prof = PUIRoleplay:GetMyProfile()
                    local tList = PUIRoleplay:GetPersonalityTraits(prof)
                    if tList[currentIdx] then
                        tList[currentIdx].leftIcon = iconName
                        prof.personality_traits = tList
                        prof.keyP = PUIRoleplay:GenerateKey()
                        PUIRoleplay:SaveMyProfile(prof)
                        SheetTabs:RefreshPersonalityTab(f)
                    end
                end)
            end
        end)

        row.rIconBtn:SetScript("OnClick", function()
            if Sheet:IsViewingSelf() then
                local currentIdx = row.traitIndex
                Sheet:OpenIconPicker(function(selectedIconIndex)
                    local iconName = PUIRoleplay.Icons[selectedIconIndex] or "INV_Misc_QuestionMark"
                    local prof = PUIRoleplay:GetMyProfile()
                    local tList = PUIRoleplay:GetPersonalityTraits(prof)
                    if tList[currentIdx] then
                        tList[currentIdx].rightIcon = iconName
                        prof.personality_traits = tList
                        prof.keyP = PUIRoleplay:GenerateKey()
                        PUIRoleplay:SaveMyProfile(prof)
                        SheetTabs:RefreshPersonalityTab(f)
                    end
                end)
            end
        end)

        -- Names (Editable if custom trait)
        row.lNameEB:SetText(trait.leftName or "Left")
        row.rNameEB:SetText(trait.rightName or "Right")

        if trait.isCustom and isSelf then
            row.lNameEB:EnableMouse(true)
            row.rNameEB:EnableMouse(true)
            row.lNameEB:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            row.lNameEB:SetBackdropColor(0, 0, 0, 0.6)
            row.lNameEB:SetBackdropBorderColor(0.3, 0.3, 0.4, 1.0)
            row.rNameEB:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            row.rNameEB:SetBackdropColor(0, 0, 0, 0.6)
            row.rNameEB:SetBackdropBorderColor(0.3, 0.3, 0.4, 1.0)
            row.delBtn:Show()
        else
            row.lNameEB:EnableMouse(false)
            row.rNameEB:EnableMouse(false)
            row.lNameEB:SetBackdrop(nil)
            row.rNameEB:SetBackdrop(nil)
            row.delBtn:Hide()
        end

        row.lNameEB:SetScript("OnTextChanged", function()
            if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
                local prof = PUIRoleplay:GetMyProfile()
                local tList = PUIRoleplay:GetPersonalityTraits(prof)
                if tList[row.traitIndex] then
                    tList[row.traitIndex].leftName = this:GetText()
                    prof.personality_traits = tList
                    prof.keyP = PUIRoleplay:GenerateKey()
                    PUIRoleplay:SaveMyProfile(prof)
                end
            end
        end)

        row.rNameEB:SetScript("OnTextChanged", function()
            if Sheet:IsViewingSelf() and f.isRefreshing ~= true then
                local prof = PUIRoleplay:GetMyProfile()
                local tList = PUIRoleplay:GetPersonalityTraits(prof)
                if tList[row.traitIndex] then
                    tList[row.traitIndex].rightName = this:GetText()
                    prof.personality_traits = tList
                    prof.keyP = PUIRoleplay:GenerateKey()
                    PUIRoleplay:SaveMyProfile(prof)
                end
            end
        end)

        row.delBtn:SetScript("OnClick", function()
            if Sheet:IsViewingSelf() then
                local prof = PUIRoleplay:GetMyProfile()
                local tList = PUIRoleplay:GetPersonalityTraits(prof)
                table.remove(tList, row.traitIndex)
                prof.personality_traits = tList
                prof.keyP = PUIRoleplay:GenerateKey()
                PUIRoleplay:SaveMyProfile(prof)
                SheetTabs:RefreshPersonalityTab(f)
            end
        end)

        -- Slider Visualization Function
        local val = tonumber(trait.value) or 10
        local function UpdateVisualSlider(currVal)
            local v = math.max(0, math.min(20, currVal))
            local frac = v / 20.0
            local thumbX = math.floor(frac * trackWidth)
            local midX = math.floor(trackWidth / 2)

            row.track.thumb:SetPoint("CENTER", row.track, "LEFT", thumbX, 0)
            row.statusLbl:SetText(FormatTraitStatus(v, trait.leftName, trait.rightName))

            if v < 10 then
                row.track.rFill:Hide()
                row.track.lFill:ClearAllPoints()
                row.track.lFill:SetPoint("TOPLEFT", row.track, "LEFT", thumbX, 6)
                row.track.lFill:SetPoint("BOTTOMRIGHT", row.track, "LEFT", midX, -6)
                row.track.lFill:Show()
            elseif v > 10 then
                row.track.lFill:Hide()
                row.track.rFill:ClearAllPoints()
                row.track.rFill:SetPoint("TOPLEFT", row.track, "LEFT", midX, 6)
                row.track.rFill:SetPoint("BOTTOMRIGHT", row.track, "LEFT", thumbX, -6)
                row.track.rFill:Show()
            else
                row.track.lFill:Hide()
                row.track.rFill:Hide()
            end
        end

        UpdateVisualSlider(val)

        -- Slider Interaction
        if isSelf then
            row.track:SetScript("OnMouseDown", function()
                local cursorX = GetCursorPosition()
                local scale = this:GetEffectiveScale()
                local left = this:GetLeft() * scale
                local width = this:GetWidth() * scale
                local frac = math.max(0, math.min(1, (cursorX - left) / width))
                local newVal = math.floor(frac * 20 + 0.5)

                UpdateVisualSlider(newVal)

                local prof = PUIRoleplay:GetMyProfile()
                local tList = PUIRoleplay:GetPersonalityTraits(prof)
                if tList[row.traitIndex] then
                    tList[row.traitIndex].value = newVal
                    prof.personality_traits = tList
                    prof.keyP = PUIRoleplay:GenerateKey()
                    PUIRoleplay:SaveMyProfile(prof)
                end
            end)
        else
            row.track:SetScript("OnMouseDown", nil)
        end
    end
end
