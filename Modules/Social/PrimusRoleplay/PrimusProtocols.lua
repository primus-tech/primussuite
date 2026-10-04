--[[
    PrimusUI: PUIRoleplay Protocols & Data Codecs (PUIProtocols.lua)
    Target: Vanilla WoW 1.12.1 / Turtle WoW (Wire Serialization, Drunk Codec & Tokens)
    Architecture: Strict TRUTH.md compliance (Zero Aliases, Zero Shims)
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIRoleplay = Primus.PUIRoleplay or {}
Primus.PUIRoleplay = PUIRoleplay

local Protocols = {}
PUIRoleplay.Protocols = Protocols

--------------------------------------------------------------------------------
-- Multi-Protocol Wire Data Schemas
--------------------------------------------------------------------------------
local dataKeys = {
    ["M"] = { "keyM", "icon", "full_name", "race", "class", "class_color", "ooc_info", "ic_info", "currently_ic", "ooc_pronouns", "ic_pronouns", "nsfw", "title", "prefix", "nickname", "house_name", "apparent_age", "biological_sex", "gender_identity", "lgbtqia_friendly", "orientation", "show_orientation", "epithet" },
    ["T"] = { "keyT", "atAGlance1", "atAGlance1Title", "atAGlance1Icon", "atAGlance2", "atAGlance2Title", "atAGlance2Icon", "atAGlance3", "atAGlance3Title", "atAGlance3Icon", "atAGlance4", "atAGlance4Title", "atAGlance4Icon", "atAGlance5", "atAGlance5Title", "atAGlance5Icon", "experience", "walkups", "injury", "romance", "death", "combat_preference" },
    ["D"] = { "keyD", "description", "eye_color", "height", "weight", "body_build", "current_emotion" },
    ["L"] = { "keyL", "birth_city", "home_city", "motto", "faction_clan", "history1", "history2", "history3", "history4", "history5", "history6" },
    ["X"] = { "keyX", "relationship_status", "looking_adventure", "looking_romance", "looking_combat", "looking_tavern", "looking_guild", "looking_adult", "looking_mentorship", "adult_18plus_flag", "erp_preference", "ooc_boundaries" }
}
dataKeys["MR"] = dataKeys["M"]
dataKeys["TR"] = dataKeys["T"]
dataKeys["DR"] = dataKeys["D"]
dataKeys["LR"] = dataKeys["L"]
dataKeys["XR"] = dataKeys["X"]

Protocols.DataKeys = dataKeys

--------------------------------------------------------------------------------
-- Drunk Codec (Protects Wire Packets from Slurred Speech)
--------------------------------------------------------------------------------
local DrunkSuffix = string.gsub(SLURRED_SPEECH or "...hic!", "%%s(.+)", "%1$")

function Protocols:DrunkEncode(text)
    if not text then return "" end
    text = string.gsub(text, "s", "\176")
    text = string.gsub(text, "S", "\167")
    return text
end

function Protocols:DrunkDecode(text)
    if not text then return "" end
    text = string.gsub(text, "\194\176", "s")
    text = string.gsub(text, "\194\167", "S")
    text = string.gsub(text, "\195\167", "S")
    text = string.gsub(text, "\176", "s")
    text = string.gsub(text, "\167", "S")
    text = string.gsub(text, "°", "s")
    text = string.gsub(text, "§", "S")
    if DrunkSuffix and DrunkSuffix ~= "" then
        text = string.gsub(text, DrunkSuffix, "")
    end
    return text
end

--------------------------------------------------------------------------------
-- RP Text Codec (@N Newline & Escape Sequence Translation)
--------------------------------------------------------------------------------
function Protocols:UnescapeText(text)
    if not text then return "" end
    text = tostring(text)
    if text == "" or text == "nil" or text == "NO_KEY" then return "" end

    -- Normalize CRLF and CR if any slipped in
    text = string.gsub(text, "\r\n", "\n")
    text = string.gsub(text, "\r", "\n")

    -- Replace wire tokens with natural characters
    -- @N / @n -> newline
    text = string.gsub(text, "@[Nn]", "\n")
    -- @J / @j -> newline (soft return / paragraph)
    text = string.gsub(text, "@[Jj]", "\n")
    -- @T / @t -> tab indentation (4 spaces)
    text = string.gsub(text, "@[Tt]", "    ")
    -- @@ -> literal @
    text = string.gsub(text, "@@", "@")

    return text
end

function Protocols:EscapeText(text)
    if not text then return "" end
    text = tostring(text)
    if text == "" or text == "nil" then return "" end

    -- Replace line breaks with @N
    text = string.gsub(text, "\r\n", "@N")
    text = string.gsub(text, "\r", "@N")
    text = string.gsub(text, "\n", "@N")
    text = string.gsub(text, "\t", "@T")

    -- Remove any ~ delimiters so they don't break wire chunk boundaries
    text = string.gsub(text, "~", "-")

    return text
end

--------------------------------------------------------------------------------
-- String Splitting Utility (Safe for Lua 5.0.2 / Vanilla WoW 1.12.1)
--------------------------------------------------------------------------------
function Protocols:SplitString(str, delimiter, targetTable)
    local result = targetTable or {}
    for k in pairs(result) do result[k] = nil end
    if not str or str == "" then
        table.setn(result, 0)
        return result
    end
    if not delimiter or delimiter == "" then
        result[1] = str
        table.setn(result, 1)
        return result
    end

    local strLen = string.len(str)
    local from = 1
    local delim_from, delim_to = string.find(str, delimiter, from, true)
    local i = 1
    local maxLoops = 2000
    local loopCount = 0

    while delim_from and loopCount < maxLoops do
        loopCount = loopCount + 1
        result[i] = string.sub(str, from, delim_from - 1)
        i = i + 1
        if delim_to < from then
            from = from + 1
        else
            from = delim_to + 1
        end
        if from > strLen then
            break
        end
        delim_from, delim_to = string.find(str, delimiter, from, true)
    end

    if from <= strLen then
        result[i] = string.sub(str, from)
    else
        result[i] = ""
    end
    table.setn(result, i)
    return result
end

--------------------------------------------------------------------------------
-- Build Outbound Wire Payload
--------------------------------------------------------------------------------
function Protocols:BuildPayload(dataPrefix, profile)
    local prof = profile or PUIRoleplay:GetMyProfile()

    -- Special handling for Personality Packet "P"
    if dataPrefix == "P" or dataPrefix == "PR" then
        local payload = dataPrefix .. ":" .. (prof.keyP or PUIRoleplay:GenerateKey())
        local traits = PUIRoleplay:GetPersonalityTraits(prof)
        for _, t in ipairs(traits) do
            local str = string.format("%s^%s^%s^%s^%s^%s^%s",
                t.id or "custom",
                t.leftName or "Left",
                t.rightName or "Right",
                t.leftIcon or "INV_Misc_QuestionMark",
                t.rightIcon or "INV_Misc_QuestionMark",
                tostring(t.value or 10),
                t.isCustom and "1" or "0"
            )
            payload = payload .. "~" .. str
        end
        return payload
    end

    local keys = dataKeys[dataPrefix]
    if not keys then return "" end

    local payload = dataPrefix .. ":"
    local count = table.getn(keys)

    for i = 1, count do
        local key = keys[i]
        local val = prof[key]

        -- Special handling for glances & looking_for nested structures
        if not val then
            if key == "looking_adventure" then val = (prof.looking_for and prof.looking_for.adventure) and "1" or "0"
            elseif key == "looking_romance" then val = (prof.looking_for and prof.looking_for.romance) and "1" or "0"
            elseif key == "looking_combat" then val = (prof.looking_for and prof.looking_for.combat) and "1" or "0"
            elseif key == "looking_tavern" then val = (prof.looking_for and prof.looking_for.casual_tavern) and "1" or "0"
            elseif key == "looking_guild" then val = (prof.looking_for and prof.looking_for.political_guild) and "1" or "0"
            elseif key == "looking_adult" then val = (prof.looking_for and prof.looking_for.adult_18plus) and "1" or "0"
            elseif key == "looking_mentorship" then val = (prof.looking_for and prof.looking_for.mentorship) and "1" or "0"
            elseif key == "adult_18plus_flag" then val = (prof.adult_18plus_flag == true) and "1" or "0"
            elseif key == "lgbtqia_friendly" then val = (prof.lgbtqia_friendly ~= false) and "1" or "0"
            elseif key == "show_orientation" then val = (prof.show_orientation ~= false) and "1" or "0"
            elseif string.find(key, "^history%d$") then
                local chNum = string.sub(key, 8)
                val = (prof.history and prof.history["chapter" .. chNum]) or ""
            end
        end

        local strVal = tostring(val or "")
        if strVal == "true" then strVal = "1"
        elseif strVal == "false" then strVal = "0"
        end

        -- Escape multi-line / special text fields for wire transmission
        if key == "description" or key == "appearance_desc" or key == "motto" or
           key == "ooc_info" or key == "ic_info" or key == "ooc_boundaries" or
           string.find(key, "^history%d$") or string.find(key, "^atAGlance%d$") or
           string.find(key, "^atAGlance%dTitle$") then
            strVal = self:EscapeText(strVal)
        else
            strVal = string.gsub(strVal, "~", "-")
        end

        payload = payload .. strVal
        if i < count then
            payload = payload .. "~"
        end
    end

    return payload
end

--------------------------------------------------------------------------------
-- Parse Inbound Wire Payload
--------------------------------------------------------------------------------
function Protocols:ParsePayload(dataPrefix, chunks, playerName, targetChar)
    if not targetChar then return end

    -- Special handling for Personality Packet "P"
    if dataPrefix == "P" or dataPrefix == "PR" then
        targetChar.keyP = chunks[1] or ""
        local traits = {}
        local totalChunks = table.getn(chunks)
        for i = 2, totalChunks do
            local raw = chunks[i]
            if raw and raw ~= "" then
                local parts = self:SplitString(raw, "^", {})
                if table.getn(parts) >= 6 then
                    table.insert(traits, {
                        id = parts[1],
                        leftName = parts[2],
                        rightName = parts[3],
                        leftIcon = parts[4],
                        rightIcon = parts[5],
                        value = tonumber(parts[6]) or 10,
                        isCustom = (parts[7] == "1")
                    })
                end
            end
        end
        if table.getn(traits) > 0 then
            targetChar.personality_traits = traits
        end
        return
    end

    local keys = dataKeys[dataPrefix]
    if not keys then return end

    local totalChunks = table.getn(chunks)
    for i = 1, totalChunks do
        local key = keys[i]
        if key then
            local val = chunks[i]
            if val == "nil" or val == "NO_KEY" then val = "" end

            -- Unescape multi-line fields on wire receipt
            if key == "description" or key == "appearance_desc" or key == "motto" or
               key == "birth_city" or key == "home_city" or
               key == "ooc_info" or key == "ic_info" or key == "ooc_boundaries" or
               string.find(key, "^history%d$") or string.find(key, "^atAGlance%d$") or
               string.find(key, "^atAGlance%dTitle$") then
                val = self:UnescapeText(val)
            end

            targetChar[key] = val

            -- Map wire fields to internal rich schema
            if key == "looking_adventure" then
                if not targetChar.looking_for then targetChar.looking_for = {} end
                targetChar.looking_for.adventure = (val == "1" or val == "true")
            elseif key == "looking_romance" then
                if not targetChar.looking_for then targetChar.looking_for = {} end
                targetChar.looking_for.romance = (val == "1" or val == "true")
            elseif key == "looking_combat" then
                if not targetChar.looking_for then targetChar.looking_for = {} end
                targetChar.looking_for.combat = (val == "1" or val == "true")
            elseif key == "looking_tavern" then
                if not targetChar.looking_for then targetChar.looking_for = {} end
                targetChar.looking_for.casual_tavern = (val == "1" or val == "true")
            elseif key == "looking_guild" then
                if not targetChar.looking_for then targetChar.looking_for = {} end
                targetChar.looking_for.political_guild = (val == "1" or val == "true")
            elseif key == "looking_adult" then
                if not targetChar.looking_for then targetChar.looking_for = {} end
                targetChar.looking_for.adult_18plus = (val == "1" or val == "true")
            elseif key == "looking_mentorship" then
                if not targetChar.looking_for then targetChar.looking_for = {} end
                targetChar.looking_for.mentorship = (val == "1" or val == "true")
            elseif key == "adult_18plus_flag" then
                targetChar.adult_18plus_flag = (val == "1" or val == "true")
            elseif key == "lgbtqia_friendly" then
                targetChar.lgbtqia_friendly = (val == "1" or val == "true")
            elseif key == "show_orientation" then
                targetChar.show_orientation = (val ~= "0" and val ~= "false")
            elseif string.find(key, "^history%d$") then
                local chNum = string.sub(key, 8)
                if not targetChar.history then targetChar.history = {} end
                targetChar.history["chapter" .. chNum] = val
            elseif string.find(key, "^atAGlance%dTitle$") then
                local _, _, gIdxStr = string.find(key, "^atAGlance(%d)Title$")
                local gIdx = tonumber(gIdxStr)
                if gIdx then
                    if not targetChar.glances then targetChar.glances = {} end
                    if not targetChar.glances[gIdx] then targetChar.glances[gIdx] = {} end
                    targetChar.glances[gIdx].title = val
                end
            elseif string.find(key, "^atAGlance%dIcon$") then
                local _, _, gIdxStr = string.find(key, "^atAGlance(%d)Icon$")
                local gIdx = tonumber(gIdxStr)
                if gIdx then
                    if not targetChar.glances then targetChar.glances = {} end
                    if not targetChar.glances[gIdx] then targetChar.glances[gIdx] = {} end
                    targetChar.glances[gIdx].icon = val
                end
            elseif string.find(key, "^atAGlance%d$") then
                local _, _, gIdxStr = string.find(key, "^atAGlance(%d)$")
                local gIdx = tonumber(gIdxStr)
                if gIdx then
                    if not targetChar.glances then targetChar.glances = {} end
                    if not targetChar.glances[gIdx] then targetChar.glances[gIdx] = {} end
                    targetChar.glances[gIdx].text = val
                end
            end
        end
    end
end
