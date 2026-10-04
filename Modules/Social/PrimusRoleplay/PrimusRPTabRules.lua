--[[
    PrimusUI: PUIRoleplay Profile Tab 5 - Rules of Engagement (PUIRPTabRules.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (Combat, Injury, Death & Walkup Consent)
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
-- Build Tab Panel 5: Rules of Engagement & Preferences
--------------------------------------------------------------------------------
function SheetTabs:BuildPanel5(parent, f)
    local p5 = CreateFrame("Frame", nil, parent)
    p5:SetAllPoints(parent)
    p5:Hide()
    f.panel5 = p5

    local styleSections = {
        { key = "experience_level", label = "Roleplay Experience Level:", opts = PUIRoleplay.DropdownOptions.experience },
        { key = "walkup_policy", label = "Walk-Up Preferences & Policy:", opts = PUIRoleplay.DropdownOptions.walkups },
        { key = "combat_preference", label = "Combat & Conflict Resolution:", opts = PUIRoleplay.DropdownOptions.combat },
        { key = "injury_consent", label = "Character Injury Tolerance:", opts = PUIRoleplay.DropdownOptions.injury },
        { key = "permadeath_consent", label = "Character Death Willingness (Permadeath):", opts = PUIRoleplay.DropdownOptions.death }
    }

    p5.dropdowns = {}
    local curStyleY = -10
    for _, sec in ipairs(styleSections) do
        local card = self:Create1PxBackdrop(p5, 0.05, 0.05, 0.07, 0.8, 0.20, 0.22, 0.26, 1.0)
        card:SetWidth(478)
        card:SetHeight(52)
        card:SetPoint("TOPLEFT", p5, "TOPLEFT", 10, curStyleY)

        local sLbl = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sLbl:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -6)
        sLbl:SetText("|cff00e5ff" .. sec.label .. "|r")

        local dd = self:CreateStyledDropdown(card, 460, 22, sec.opts or {}, function(optKey, optVal)
            local p = PUIRoleplay:GetMyProfile()
            p[sec.key] = optVal
            p.keyT = PUIRoleplay:GenerateKey()
            PUIRoleplay:SaveMyProfile(p)
        end)
        dd:SetPoint("TOPLEFT", sLbl, "BOTTOMLEFT", 0, -2)
        p5.dropdowns[sec.key] = dd

        curStyleY = curStyleY - 58
    end
end
