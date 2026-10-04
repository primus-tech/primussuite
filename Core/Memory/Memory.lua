--[[
    PrimusLib: Memory & Object Recycling Pool
    Target: Vanilla WoW 1.12.1 (Lua 5.0.2)
    
    Provides high-performance zero-allocation table pooling to eliminate
    the "stop-the-world" garbage collector lag spikes in Vanilla WoW.
--]]

local _G = getglobals and getglobals() or _G or getfenv(0)
local Primus = _G.Primus
if not Primus then return end

local Memory = Primus.Memory
local Utils  = Primus.Utils

-- Table Pool storage
local pool = {}
local poolSize = 0
local maxPoolSize = 500

-- Statistics
Memory.stats = {
    allocated = 0,
    acquired = 0,
    released = 0,
    activeInUse = 0,
}

-- Acquire a clean, empty table from the pool (or allocate one if pool is empty)
function Memory:AcquireTable()
    self.stats.acquired = self.stats.acquired + 1
    if poolSize > 0 then
        local t = pool[poolSize]
        pool[poolSize] = nil
        poolSize = poolSize - 1
        self.stats.activeInUse = self.stats.activeInUse + 1
        return t
    end

    self.stats.allocated = self.stats.allocated + 1
    self.stats.activeInUse = self.stats.activeInUse + 1
    return {}
end

-- Release a table back into the pool after wiping its contents
function Memory:ReleaseTable(t)
    if type(t) ~= "table" then return end
    self.stats.released = self.stats.released + 1
    self.stats.activeInUse = math.max(0, self.stats.activeInUse - 1)

    if poolSize < maxPoolSize then
        Utils.Wipe(t)
        poolSize = poolSize + 1
        pool[poolSize] = t
    end
end

-- Acquire a table pre-populated with shallow copied values
function Memory:AcquireCopy(src)
    local t = self:AcquireTable()
    if type(src) == "table" then
        for k, v in pairs(src) do
            t[k] = v
        end
    end
    return t
end

-- Get memory diagnostic summary
function Memory:GetStats()
    return {
        pooled = poolSize,
        totalAllocated = self.stats.allocated,
        timesAcquired = self.stats.acquired,
        timesReleased = self.stats.released,
        activeInUse = self.stats.activeInUse,
    }
end

-- Trigger manual garbage collection and return freed memory in KB
function Memory:CollectGarbage()
    local before = gcinfo and gcinfo() or 0
    collectgarbage()
    local after = gcinfo and gcinfo() or 0
    return math.max(0, before - after)
end
