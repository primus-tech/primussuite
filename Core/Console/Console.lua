--[[
    PrimusUI: Slash Command & Console Router
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides structured slash command parsing, aliases, formatted output,
    and unified sub-command routing for all PrimusUI modules.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local Console = Primus.Console
local Utils   = Primus.Utils
local Keybind = Primus.Keybind
local Memory  = Primus.Memory
local Debug   = Primus.Debug

local subCommands = {}
local aliases     = {}

-- Register a sub-command
function Console:RegisterSubCommand(command, handler, helpText)
    if not command or not handler then return end
    command = string.lower(command)
    subCommands[command] = {
        handler = handler,
        helpText = helpText or "",
    }
end

-- Register an alias for a sub-command
function Console:RegisterAlias(alias, targetCommand)
    if not alias or not targetCommand then return end
    alias = string.lower(alias)
    targetCommand = string.lower(targetCommand)
    aliases[alias] = targetCommand
end

-- Retrieve Subcommands Table
function Console:GetSubCommands()
    return subCommands
end

-- Print Help Menu
function Console:PrintHelp()
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("=== PrimusUI Master Console ===", "69ccf0"))
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("/pui", "ffbb33") .. " or " .. Utils.ColorText("/primus", "ffbb33") .. " - Open Master Options GUI")
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("/pui move [bars|units|hud|player|class|social|util|lock|reset]", "ffbb33") .. " - Categorized frame mover")
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("/pui bind", "ffbb33") .. " - Toggle Hover-to-Bind mode")
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("/pui memory", "ffbb33") .. " - Table pool GC & diagnostics")
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("/pui errors", "ffbb33") .. " - Diagnostic error log")

    for cmd, info in pairs(subCommands) do
        if cmd ~= "move" and cmd ~= "bind" and cmd ~= "memory" and cmd ~= "errors" then
            DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("/pui " .. cmd, "ffbb33") .. " - " .. info.helpText)
        end
    end
end

-- Master Slash Command Handler
local function HandleSlashCommand(msg)
    msg = Utils.Trim(msg or "")
    if msg == "" or msg == "gui" or msg == "config" or msg == "options" then
        if Primus.Options then
            Primus.Options:Toggle()
        else
            Console:PrintHelp()
        end
        return
    end

    if msg == "help" then
        Console:PrintHelp()
        return
    end

    local parts = Utils.Split(msg, "%s+")
    local rawCmd = string.lower(parts[1] or "")
    local mainCmd = aliases[rawCmd] or rawCmd
    local argParam = parts[2]

    local MoverInstance = Primus.PUIMover or PUIMover or _G.PUIMover

    if mainCmd == "move" or mainCmd == "unlock" then
        if MoverInstance then
            if argParam then
                local sub = string.lower(argParam)
                if sub == "lock" then
                    MoverInstance:LockAll()
                elseif sub == "reset" then
                    MoverInstance:ResetAll()
                else
                    MoverInstance:Unlock(sub)
                end
            else
                MoverInstance:ToggleLock("BARS")
            end
        end
    elseif mainCmd == "lock" then
        if MoverInstance then
            MoverInstance:LockAll()
        end
    elseif mainCmd == "bind" or mainCmd == "hoverbind" then
        Keybind:ToggleHoverBind()
    elseif mainCmd == "memory" or mainCmd == "gc" then
        local freed = Memory:CollectGarbage()
        local stats = Memory:GetStats()
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PrimusUI Memory]: Pooled: %d | Active: %d | Freed: %d KB", stats.pooled, stats.activeInUse, freed), "69ccf0"))
    elseif mainCmd == "errors" or mainCmd == "error" or mainCmd == "bugs" then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("=== PrimusUI Error Log ===", "ff4444"))
        local count = table.getn(Debug.errorLog)
        if count == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("No errors recorded. System healthy!")
        else
            for i = 1, count do
                local err = Debug.errorLog[i]
                DEFAULT_CHAT_FRAME:AddMessage(string.format("[%s][%s]: %s", err.time, err.tag, err.message))
            end
        end
    elseif subCommands[mainCmd] then
        Debug:SafeCall(subCommands[mainCmd].handler, argParam, parts)
    else
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PrimusUI]: Unknown command '" .. rawCmd .. "'. Type /pui help", "ff4444"))
    end
end

-- Master Slash Command Bindings
SLASH_PRIMUS1 = "/primus"
SLASH_PRIMUS2 = "/pui"
SlashCmdList["PRIMUS"] = HandleSlashCommand

SLASH_HOVERBIND1 = "/hoverbind"
SlashCmdList["HOVERBIND"] = function()
    Keybind:ToggleHoverBind()
end
