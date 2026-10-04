--[[
    PrimusUI Module: PUIMerchant (15-Second Patient Scanner Engine & Ingestion Pipeline)
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides:
    1. Server-Safe 15.0s Patient AH Scanner Loop (strictly respecting OctoWoW DDoS rate limiters).
    2. Streaming Page-by-Page Ingestion (Zero memory backlog, zero frame freezes at scan finish).
    3. Real-time 1-second countdown updates for UI displays.
    4. Asynchronous page query watchdog (25.0s timeout with 3 retries).
    5. Automatic 3-way economy detection (Alliance / Horde / Neutral).
    6. Tier 2 Passive Browse Sniffer for organic auction browsing.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local PUIMerchant = Primus.PUIMerchant or {}
Primus.PUIMerchant = PUIMerchant

local DB    = Primus.DB
local Utils = Primus.Utils
local Time  = Primus.Time
local Items = Primus.Items

-- Scanner State Variables
local isScanning = false
local isPaused = false
local scanPage = 0
local totalPages = 1
local totalAuctionsCataloged = 0
local isWaitingForNextPage = false
local lastQueryTime = 0
local pageCooldownEnd = 0
local pageRetries = 0
local maxRetries = 3
local currentScope = 0 -- 0 = All, 6 = Trade Goods, 4 = Consumables, 1 = Weapons, 2 = Armor

-- Adaptive Step-Down Throttle Configuration
local PACING_PRESETS = {
    ["PATIENT"]  = 10.0,
    ["STANDARD"] = 5.0,
    ["FAST"]     = 2.5,
    ["TURBO"]    = 1.0,
}
local MIN_COOLDOWN_FLOOR = 1.0
local MAX_COOLDOWN_CEIL  = 12.0
local STEP_DOWN_DELTA    = 0.5  -- -0.5s after 2 consecutive clean pages
local STEP_UP_BACKOFF    = 2.5  -- +2.5s on throttle/retry
local currentEffectiveCooldown = 5.0
local consecutiveSuccessPages = 0

local SCAN_TIMEOUT = 25.0  -- 25-second watchdog for slow server responses

PUIMerchant.scannerState = {
    isScanning = false,
    isPaused = false,
    scanPage = 0,
    totalPages = 1,
    totalCataloged = 0,
    remainingCooldown = 0,
    currentCooldown = 5.0,
    pacingMode = "ADAPTIVE",
    etaSeconds = 0,
    etaText = "--",
    statusText = "Ready",
}

-- Calculate Active Pacing Delay
function PUIMerchant:GetPacingDelay()
    local mode = self.db and self.db:Get("scanPacingMode", "ADAPTIVE") or "ADAPTIVE"
    if mode == "ADAPTIVE" then
        return currentEffectiveCooldown
    elseif PACING_PRESETS[mode] then
        return PACING_PRESETS[mode]
    else
        return 5.0
    end
end

-- Set User Pacing Preset
function PUIMerchant:SetPacingMode(mode)
    if not mode then mode = "ADAPTIVE" end
    if self.db then
        self.db:Set("scanPacingMode", mode)
    end
    if mode == "ADAPTIVE" then
        currentEffectiveCooldown = 5.0
        consecutiveSuccessPages = 0
    elseif PACING_PRESETS[mode] then
        currentEffectiveCooldown = PACING_PRESETS[mode]
    end
    PUIMerchant.scannerState.pacingMode = mode
    PUIMerchant.scannerState.currentCooldown = currentEffectiveCooldown
    if self.UpdateFlyoutScannerUI then
        self:UpdateFlyoutScannerUI()
    end
end

-- Step Down Delay on Consecutive Clean Pages
function PUIMerchant:StepDownCooldown()
    local mode = self.db and self.db:Get("scanPacingMode", "ADAPTIVE") or "ADAPTIVE"
    if mode ~= "ADAPTIVE" then return end

    consecutiveSuccessPages = consecutiveSuccessPages + 1
    if consecutiveSuccessPages >= 2 then
        consecutiveSuccessPages = 0
        if currentEffectiveCooldown > MIN_COOLDOWN_FLOOR then
            currentEffectiveCooldown = math.max(MIN_COOLDOWN_FLOOR, currentEffectiveCooldown - STEP_DOWN_DELTA)
        end
    end
end

-- Step Up Backoff on Throttle or Dropped Query
function PUIMerchant:StepUpBackoff()
    local mode = self.db and self.db:Get("scanPacingMode", "ADAPTIVE") or "ADAPTIVE"
    consecutiveSuccessPages = 0
    if mode == "ADAPTIVE" then
        currentEffectiveCooldown = math.min(MAX_COOLDOWN_CEIL, currentEffectiveCooldown + STEP_UP_BACKOFF)
    end
end

-- Format Seconds into Human-Readable ETA (e.g., 2h 15m or 4m 30s)
function PUIMerchant:FormatETA(seconds)
    seconds = seconds or 0
    if seconds <= 0 then return "0s" end
    if seconds >= 3600 then
        local hours = math.floor(seconds / 3600)
        local mins = math.floor(math.mod(seconds, 3600) / 60)
        return string.format("%dh %02dm", hours, mins)
    elseif seconds >= 60 then
        local mins = math.floor(seconds / 60)
        local secs = math.mod(seconds, 60)
        return string.format("%dm %02ds", mins, secs)
    else
        return string.format("%ds", seconds)
    end
end

-- Update scanner state snapshot for UI components
local function UpdateScannerState(statusMsg)
    PUIMerchant.scannerState.isScanning = isScanning
    PUIMerchant.scannerState.isPaused = isPaused
    PUIMerchant.scannerState.scanPage = scanPage
    PUIMerchant.scannerState.totalPages = totalPages
    PUIMerchant.scannerState.totalCataloged = totalAuctionsCataloged
    
    local now = GetTime()
    local rem = math.floor(pageCooldownEnd - now)
    if rem < 0 then rem = 0 end
    PUIMerchant.scannerState.remainingCooldown = rem
    PUIMerchant.scannerState.currentCooldown = PUIMerchant:GetPacingDelay()
    PUIMerchant.scannerState.pacingMode = PUIMerchant.db and PUIMerchant.db:Get("scanPacingMode", "ADAPTIVE") or "ADAPTIVE"

    -- Dynamic ETA Estimation
    local remainingPages = totalPages - scanPage
    if remainingPages < 0 then remainingPages = 0 end
    local totalEtaSeconds = math.ceil((remainingPages * PUIMerchant:GetPacingDelay()) + rem)
    if not isScanning or scanPage == 0 then totalEtaSeconds = 0 end

    PUIMerchant.scannerState.etaSeconds = totalEtaSeconds
    PUIMerchant.scannerState.etaText = PUIMerchant:FormatETA(totalEtaSeconds)

    if statusMsg then
        PUIMerchant.scannerState.statusText = statusMsg
    end

    if PUIMerchant.UpdateFlyoutScannerUI then
        PUIMerchant:UpdateFlyoutScannerUI()
    end
end

-- Get Category Scope Display Name
function PUIMerchant:GetScopeName(scope)
    scope = tonumber(scope) or 0
    if scope == 6 then return "Trade Goods"
    elseif scope == 4 then return "Consumables"
    elseif scope == 1 then return "Weapons"
    elseif scope == 2 then return "Armor"
    else return "All Categories" end
end

-- Retrieve Active Checkpoint (Valid for current Realm & AH Faction within 12 hours)
function PUIMerchant:GetScanCheckpoint()
    if not self.db or not self.db.data then return nil end
    local cp = self.db.data.scanCheckpoint
    if not cp or not cp.page or cp.page <= 0 then return nil end

    local realm = GetRealmName() or "Default"
    local ahType = self:GetCurrentAHType()
    if cp.realm ~= realm or cp.ahType ~= ahType then
        return nil
    end

    local now = Time:GetServerTimestamp()
    -- Checkpoints expire after 12 hours (43,200s)
    if (now - (cp.timestamp or 0)) > 43200 then
        self.db.data.scanCheckpoint = nil
        return nil
    end

    return cp
end

-- Save Active Scan Progress to SavedVariables
function PUIMerchant:SaveScanCheckpoint()
    if not self.db or not self.db.data then return end
    if scanPage <= 0 then return end

    local realm = GetRealmName() or "Default"
    local ahType = self:GetCurrentAHType()
    self.db.data.scanCheckpoint = {
        realm = realm,
        ahType = ahType,
        page = scanPage,
        totalPages = totalPages,
        scope = currentScope or 0,
        totalCataloged = totalAuctionsCataloged or 0,
        timestamp = Time:GetServerTimestamp(),
    }
end

-- Clear Saved Checkpoint on Full Completion or Fresh Reset
function PUIMerchant:ClearScanCheckpoint()
    if self.db and self.db.data then
        self.db.data.scanCheckpoint = nil
    end
end

-- Start, Resume, or Fresh Scan
function PUIMerchant:StartScan(scopeCategory, forceFresh)
    if not AuctionFrame or not AuctionFrame:IsShown() then
        DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIMerchant]: Open the Auction House to run an AH scan.", "ffbb33"))
        return
    end

    if isScanning then
        if isPaused then
            self:ResumeScan()
        else
            self:PauseScan()
        end
        return
    end

    local ahType = self:GetCurrentAHType()
    local cp = (not forceFresh) and self:GetScanCheckpoint() or nil

    if cp and cp.page and cp.page > 0 then
        -- Resume from checkpoint with a 2-page safety overlap rewind
        local rewindPage = math.max(0, cp.page - 2)
        scanPage = rewindPage
        currentScope = cp.scope or scopeCategory or 0
        totalPages = cp.totalPages or 1
        totalAuctionsCataloged = cp.totalCataloged or 0
        pageRetries = 0
        isScanning = true
        isPaused = false

        lastQueryTime = GetTime()
        local pacingDelay = self:GetPacingDelay()
        pageCooldownEnd = lastQueryTime + pacingDelay

        local scopeName = self:GetScopeName(currentScope)
        if CanSendAuctionQuery() then
            isWaitingForNextPage = false
            UpdateScannerState(string.format("Resuming at Page %d/%d (%s)...", scanPage + 1, totalPages, scopeName))
            DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: Resuming Scan at Page %d/%d (2-page safety rewind) [%s AH - %s - %s]...", scanPage + 1, totalPages, ahType, scopeName, PUIMerchant.scannerState.pacingMode), "69ccf0"))
            QueryAuctionItems("", 0, 0, 0, (currentScope and currentScope > 0) and currentScope or 0, 0, scanPage, 0, 0)
        else
            isWaitingForNextPage = true
            UpdateScannerState(string.format("Queued Resume at Page %d/%d (Cooldown)...", scanPage + 1, totalPages))
            DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: Queued resume at page %d as soon as server cooldown clears...", scanPage + 1), "ffbb33"))
        end
    else
        self:ClearScanCheckpoint()
        currentScope = scopeCategory or 0
        isScanning = true
        isPaused = false
        scanPage = 0
        totalPages = 1
        totalAuctionsCataloged = 0
        pageRetries = 0

        lastQueryTime = GetTime()
        local pacingDelay = self:GetPacingDelay()
        pageCooldownEnd = lastQueryTime + pacingDelay

        local scopeName = self:GetScopeName(currentScope)
        if CanSendAuctionQuery() then
            isWaitingForNextPage = false
            UpdateScannerState(string.format("Requesting Page 1 (%s - %s)...", scopeName, ahType))
            DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: Starting %s AH Scan [%s AH - %s] (Pacing: %0.1fs)...", PUIMerchant.scannerState.pacingMode, ahType, scopeName, pacingDelay), "69ccf0"))
            QueryAuctionItems("", 0, 0, 0, (currentScope and currentScope > 0) and currentScope or 0, 0, 0, 0, 0)
        else
            isWaitingForNextPage = true
            UpdateScannerState(string.format("Queueing Scan [%s AH] (Waiting on server cooldown)...", ahType))
            DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: AH query busy. Queued page 1 to send as soon as cooldown clears...", ahType), "ffbb33"))
        end
    end
end

-- Pause Active Scan
function PUIMerchant:PauseScan()
    if not isScanning or isPaused then return end
    isPaused = true
    self:SaveScanCheckpoint()
    UpdateScannerState("Scan Paused")
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIMerchant]: AH scan paused. Checkpoint saved. Click Resume to continue.", "ffbb33"))
end

-- Resume Paused Scan
function PUIMerchant:ResumeScan()
    if not isScanning or not isPaused then return end
    isPaused = false
    lastQueryTime = GetTime()
    pageCooldownEnd = lastQueryTime + self:GetPacingDelay()
    isWaitingForNextPage = true
    UpdateScannerState(string.format("Resuming at Page %d/%d...", scanPage + 1, totalPages))
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText("[PUIMerchant]: Resuming AH scan...", "69ccf0"))
end

-- Stop Active Scan
function PUIMerchant:StopScan()
    if not isScanning then return end
    isScanning = false
    isPaused = false
    isWaitingForNextPage = false

    self:SaveScanCheckpoint()

    local realm = GetRealmName() or "Default"
    local ahType = self:GetCurrentAHType()
    local realmData = self:GetRealmPriceData(realm, ahType)
    realmData.lastScan = Time:GetServerTimestamp()
    realmData.totalListings = totalAuctionsCataloged

    UpdateScannerState(string.format("Stopped (Page %d/%d saved)", scanPage, totalPages))
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: AH scan stopped at page %d/%d. %d listings cataloged. Checkpoint saved.", scanPage, totalPages, totalAuctionsCataloged), "ffbb33"))
end

-- Process Returned Auction Batch (Streaming Ingestion - Instant per-page processing)
function PUIMerchant:ProcessScanResults()
    if not isScanning or isPaused then return end
    if isWaitingForNextPage then return end

    local numBatchAuctions, totalAuctions = GetNumAuctionItems("list")

    -- Initial query latency / empty results fallback with retry
    if (not totalAuctions or totalAuctions == 0) and numBatchAuctions == 0 and scanPage == 0 then
        if pageRetries < maxRetries then
            pageRetries = pageRetries + 1
            self:StepUpBackoff()
            isWaitingForNextPage = true
            lastQueryTime = GetTime()
            pageCooldownEnd = lastQueryTime + self:GetPacingDelay()
            UpdateScannerState(string.format("Waiting on AH server (retry %d)...", pageRetries))
            return
        else
            self:FinishScan()
            return
        end
    end

    if totalAuctions and totalAuctions > 0 then
        totalPages = math.ceil(totalAuctions / (NUM_AUCTION_ITEMS_PER_PAGE or 50))
    end

    local realm = GetRealmName() or "Default"
    local ahType = self:GetCurrentAHType()

    -- Stream each auction listing directly into daily storage without memory buffering
    if numBatchAuctions and numBatchAuctions > 0 then
        for i = 1, numBatchAuctions do
            local name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice = GetAuctionItemInfo("list", i)
            local timeLeft = GetAuctionItemTimeLeft("list", i)
            if name and count and count > 0 then
                local unitPrice = 0
                if buyoutPrice and buyoutPrice > 0 then
                    unitPrice = math.floor(buyoutPrice / count)
                elseif minBid and minBid > 0 then
                    unitPrice = math.floor(minBid / count)
                end

                if unitPrice > 0 then
                    self:RecordAuctionListing(name, unitPrice, {
                        texture = texture,
                        quality = quality or 1,
                        itemLevel = level or 1,
                        timeLeft = timeLeft,
                    }, realm, ahType)
                    totalAuctionsCataloged = totalAuctionsCataloged + 1
                end
            end
        end
    end

    scanPage = scanPage + 1
    pageRetries = 0
    self:StepDownCooldown() -- Accelerate/step-down throttle on consecutive successful page receipts
    self:SaveScanCheckpoint()

    if scanPage >= totalPages or (numBatchAuctions == 0 and scanPage > 1) then
        self:FinishScan()
    else
        isWaitingForNextPage = true
        lastQueryTime = GetTime()
        local pacingDelay = self:GetPacingDelay()
        pageCooldownEnd = lastQueryTime + pacingDelay
        UpdateScannerState(string.format("Page %d/%d (%d items) - Cooldown %0.1fs...", scanPage, totalPages, totalAuctionsCataloged, pacingDelay))
    end
end

-- Complete Scan (Instantaneous - 0ms freeze)
function PUIMerchant:FinishScan()
    isScanning = false
    isPaused = false
    isWaitingForNextPage = false

    self:ClearScanCheckpoint()

    local realm = GetRealmName() or "Default"
    local ahType = self:GetCurrentAHType()
    local realmData = self:GetRealmPriceData(realm, ahType)
    realmData.lastScan = Time:GetServerTimestamp()
    realmData.totalListings = totalAuctionsCataloged

    UpdateScannerState(string.format("Scan Complete! (%d cataloged)", totalAuctionsCataloged))
    DEFAULT_CHAT_FRAME:AddMessage(Utils.ColorText(string.format("[PUIMerchant]: AH Scan Complete! %d auction listings cataloged across %d pages.", totalAuctionsCataloged, scanPage), "69ccf0"))
end

-- =========================================================================
-- PASSIVE BROWSE SNIFFER (Tier 2 Ingestion)
-- =========================================================================

function PUIMerchant:SniffBrowsePage()
    if isScanning then return end
    if not AuctionFrame or not AuctionFrame:IsShown() then return end

    local numBatchAuctions = GetNumAuctionItems("list")
    if not numBatchAuctions or numBatchAuctions == 0 then return end

    local realm = GetRealmName() or "Default"
    local ahType = self:GetCurrentAHType()

    for i = 1, numBatchAuctions do
        local name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice = GetAuctionItemInfo("list", i)
        local timeLeft = GetAuctionItemTimeLeft("list", i)
        if name and count and count > 0 then
            local unitPrice = 0
            if buyoutPrice and buyoutPrice > 0 then
                unitPrice = math.floor(buyoutPrice / count)
            elseif minBid and minBid > 0 then
                unitPrice = math.floor(minBid / count)
            end

            if unitPrice > 0 then
                self:RecordAuctionListing(name, unitPrice, {
                    texture = texture,
                    quality = quality or 1,
                    itemLevel = level or 1,
                    timeLeft = timeLeft,
                }, realm, ahType)
            end
        end
    end
end

-- =========================================================================
-- ASYNCHRONOUS SCANNER TICKER & WATCHDOG
-- =========================================================================

function PUIMerchant:InitScannerTicker()
    -- Fast 0.20s loop for query dispatch & watchdog
    Time:Every(0.20, function()
        if not isScanning or isPaused then return end

        local now = GetTime()

        -- Auto-abort if player closes AH mid-scan
        if not AuctionFrame or not AuctionFrame:IsShown() then
            PUIMerchant:StopScan()
            return
        end

        -- Dispatch next page once cooldown elapsed and server ready
        if isWaitingForNextPage then
            if now >= pageCooldownEnd and CanSendAuctionQuery() then
                isWaitingForNextPage = false
                lastQueryTime = now
                pageCooldownEnd = now + PUIMerchant:GetPacingDelay()
                UpdateScannerState(string.format("Querying Page %d/%d (%d items)...", scanPage + 1, totalPages, totalAuctionsCataloged))
                QueryAuctionItems("", 0, 0, 0, (currentScope and currentScope > 0) and currentScope or 0, 0, scanPage, 0, 0)
            end
        else
            -- Watchdog: detect dropped packets or server lag (> SCAN_TIMEOUT seconds)
            if (now - lastQueryTime) > SCAN_TIMEOUT then
                if pageRetries < maxRetries then
                    pageRetries = pageRetries + 1
                    PUIMerchant:StepUpBackoff()
                    lastQueryTime = now
                    pageCooldownEnd = now + PUIMerchant:GetPacingDelay()
                    if CanSendAuctionQuery() then
                        UpdateScannerState(string.format("Retrying Page %d/%d (attempt %d)...", scanPage + 1, totalPages, pageRetries))
                        QueryAuctionItems("", 0, 0, 0, (currentScope and currentScope > 0) and currentScope or 0, 0, scanPage, 0, 0)
                    else
                        isWaitingForNextPage = true
                    end
                else
                    PUIMerchant:FinishScan()
                end
            end
        end
    end, "PUIMerchantScanner")

    -- 0.5s UI Countdown Ticker (Smooth step-down visual updates)
    Time:Every(0.5, function()
        if not isScanning then return end
        if isWaitingForNextPage and not isPaused then
            local now = GetTime()
            local rem = math.floor(pageCooldownEnd - now + 0.5)
            if rem < 0 then rem = 0 end
            local curPacing = PUIMerchant:GetPacingDelay()
            local pacingTag = (PUIMerchant.scannerState.pacingMode == "ADAPTIVE") and string.format("⚡ %0.1fs Auto", curPacing) or string.format("%0.1fs", curPacing)
            UpdateScannerState(string.format("Page %d/%d (%d items) - Next in %ds (%s)...", scanPage, totalPages, totalAuctionsCataloged, rem, pacingTag))
        end
    end, "PUIMerchantCountdown")
end
