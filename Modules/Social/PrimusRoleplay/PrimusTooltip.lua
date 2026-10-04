--[[
    PrimusUI: PUIRoleplay GameTooltip RP Enhancer (PUITooltip.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (PUITooltip Unit Provider Integration)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIRoleplay = Primus.PUIRoleplay or {}
Primus.PUIRoleplay = PUIRoleplay

local Tooltip = {}
PUIRoleplay.Tooltip = Tooltip

--------------------------------------------------------------------------------
-- Provider Registration with Universal PUITooltip Engine
--------------------------------------------------------------------------------
function Tooltip:Initialize()
    local PUITooltip = Primus.PUITooltip
    if PUITooltip and PUITooltip.RegisterUnitProvider then
        PUITooltip:RegisterUnitProvider("PUIRoleplay", 1, function(tt, unit, unitName, isPlayer)
            if isPlayer then
                Tooltip:EnhancePlayerTooltip(tt, unit, unitName)
            end
        end)
    end
end

function Tooltip:Disable()
    local PUITooltip = Primus.PUITooltip
    if PUITooltip and PUITooltip.UnregisterUnitProvider then
        PUITooltip:UnregisterUnitProvider("PUIRoleplay")
    end
end

--------------------------------------------------------------------------------
-- Format & Inject Granular RP Metadata into Tooltip
--------------------------------------------------------------------------------
function Tooltip:EnhancePlayerTooltip(tooltip, unit, playerName)
    unit = unit or "mouseover"
    if not UnitIsPlayer(unit) then return end

    playerName = playerName or UnitName(unit)
    if not playerName then return end

    local isSelf = (playerName == UnitName("player"))
    local charData = isSelf and PUIRoleplay:GetMyProfile() or PUIRoleplay:GetCharacterData(playerName)

    -- Request fresh M & T packets if missing
    if not isSelf and (not charData or not charData.keyM or not charData.full_name or charData.full_name == "") then
        if PUIRoleplay.Comms and PUIRoleplay.Comms.SendRequest then
            PUIRoleplay.Comms:SendRequest("M", playerName)
            PUIRoleplay.Comms:SendRequest("T", playerName)
            PUIRoleplay.Comms:SendRequest("D", playerName)
        end
    end

    if not charData or not charData.keyM then return end

    -- 1. Full RP Name Composite
    local fullName = charData.full_name or playerName
    if charData.first_name and charData.first_name ~= "" then
        fullName = charData.first_name .. (charData.last_name and (" " .. charData.last_name) or "")
    end

    local class = charData.class or UnitClass(unit) or ""
    local classColor = charData.class_color or (PUIRoleplay.ClassData and PUIRoleplay.ClassData[class] and PUIRoleplay.ClassData[class][4]) or "FFFFFF"
    local isIC = (charData.currently_ic == "1")
    local icBadge = isIC and "|cff40ff66(IC)|r" or "|cffffaa00(OOC)|r"

    -- Pronouns
    local pronouns = isIC and charData.ic_pronouns or charData.ooc_pronouns
    local pronounText = (pronouns and pronouns ~= "") and (" |cffffcc80(" .. pronouns .. ")|r") or ""

    -- Format Line 1
    local line1 = _G[tooltip:GetName() .. "TextLeft1"]
    if line1 then
        local displayName = "|cff" .. classColor .. fullName .. "|r " .. icBadge .. pronounText
        line1:SetText(displayName)
    end

    -- 2. Prefix, Title, Epithet, and House Name
    local titleStr = PUIRoleplay:ComposeTitle(charData)
    if titleStr ~= "" then
        tooltip:AddLine("<" .. titleStr .. ">", 0.0, 0.85, 1.0)
    end

    -- 3. Demographic Badges Pill (Age, Sex, Gender, Orientation, LGBTQIA+, 18+)
    local demoPills = {}
    if charData.apparent_age and charData.apparent_age ~= "" then
        table.insert(demoPills, "|cff00ccff[" .. charData.apparent_age .. "]|r")
    end
    if charData.biological_sex and charData.biological_sex ~= "" then
        table.insert(demoPills, "|cffffd100[" .. charData.biological_sex .. "]|r")
    end
    if charData.gender_identity and charData.gender_identity ~= "" and charData.gender_identity ~= charData.biological_sex then
        table.insert(demoPills, "|cff00ffaa[" .. charData.gender_identity .. "]|r")
    end
    if charData.show_orientation ~= false and charData.orientation and charData.orientation ~= "" then
        table.insert(demoPills, "|cffff80cc[" .. charData.orientation .. "]|r")
    end
    if charData.lgbtqia_friendly ~= false then
        table.insert(demoPills, "|cffff0000[|cffff7f00LGBTQIA+|cff9400d3]|r")
    end
    if charData.adult_18plus_flag == true then
        table.insert(demoPills, "|cffff3355[18+]|r")
    end

    if table.getn(demoPills) > 0 then
        tooltip:AddLine(table.concat(demoPills, " "), 1, 1, 1)
    end

    -- 4. Current Emotion / Expression
    if charData.current_emotion and charData.current_emotion ~= "" and charData.current_emotion ~= "Calm" then
        tooltip:AddLine("Expression: |cffffffff\"" .. charData.current_emotion .. "\"|r", 0.85, 0.85, 0.5)
    end

    -- 5. Active At-A-Glance Traits
    if charData.glances then
        local glanceSnippets = {}
        for i = 1, 5 do
            local g = charData.glances[i]
            if g and g.active and g.title and g.title ~= "" then
                local gT = PUIRoleplay.UnescapeRPText and PUIRoleplay:UnescapeRPText(g.title) or g.title
                table.insert(glanceSnippets, "|cffffd100[" .. gT .. "]|r")
            end
        end
        if table.getn(glanceSnippets) > 0 then
            tooltip:AddLine("Glances: " .. table.concat(glanceSnippets, " "), 1, 0.85, 0.3)
        end
    end

    -- 6. IC / OOC Summary
    local icInfo = charData.ic_info
    if icInfo and icInfo ~= "" then
        local cleanIC = PUIRoleplay.UnescapeRPText and PUIRoleplay:UnescapeRPText(icInfo) or icInfo
        tooltip:AddLine(" ")
        tooltip:AddLine("IC Status:", 0.25, 0.85, 0.45)
        tooltip:AddLine(cleanIC, 0.85, 0.85, 0.85, true)
    end

    local oocInfo = charData.ooc_notes or charData.ooc_info
    if oocInfo and oocInfo ~= "" then
        local cleanOOC = PUIRoleplay.UnescapeRPText and PUIRoleplay:UnescapeRPText(oocInfo) or oocInfo
        tooltip:AddLine(" ")
        tooltip:AddLine("OOC Notes:", 0.85, 0.55, 0.2)
        tooltip:AddLine(cleanOOC, 0.85, 0.85, 0.85, true)
    end

    tooltip:Show()
end
