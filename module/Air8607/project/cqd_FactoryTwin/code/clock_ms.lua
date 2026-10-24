-- Platform-independent monotonic milliseconds from official LuatOS MCU APIs.
-- Air1601 mcu.ticks() is a raw OS tick (often 20 ms), not a millisecond.
-- Official API/source: docs/official_sources.md, "Air1601 毫秒时钟修正".
local Clock = {}
local Instance = {}
Instance.__index = Instance
local WRAP = 4294967296.0
local MILLION = 1000000.0

local function finite(value)
    return type(value) == "number" and value == value and
        value ~= math.huge and value ~= -math.huge
end

local function nonnegative(value)
    return finite(value) and value >= 0
end

local function reset(instance, provider)
    instance.source = provider
    instance.last_ms = nil
    instance.raw_last = nil
    instance.raw_ms = nil
end

local function index(provider, name) return provider[name] end
local function method(provider, name)
    -- LuatOS native modules are read-only userdata (ROTable), while desktop
    -- adapters use tables. Probe the capability instead of requiring a table.
    local ok, value = pcall(index, provider, name)
    if ok and type(value) == "function" then return value end
end

local function keep_monotonic(instance, value)
    if instance.last_ms ~= nil and value < instance.last_ms then
        value = instance.last_ms
    end
    instance.last_ms = value
    return value
end

-- Inject an indexable provider object for deterministic tests. Functions have
-- the same signatures as mcu.ticks2(mode), mcu.ticks(), and mcu.hz().
function Clock.new(provider)
    return setmetatable({provider = provider}, Instance)
end

function Instance:now(fallback_ms)
    local provider = self.dynamic and _G.mcu or self.provider
    if provider ~= self.source then reset(self, provider) end
    if provider ~= nil then
        local ticks2 = method(provider, "ticks2")
        if ticks2 then
            local ok, high, low = pcall(ticks2, 1)
            if ok and nonnegative(high) and high % 1 == 0 and
                nonnegative(low) and low < MILLION and low % 1 == 0 then
                local value = high * MILLION + low
                if finite(value) then
                    -- Rebase raw-tick fallback if this source later disappears.
                    self.raw_last, self.raw_ms = nil, nil
                    return keep_monotonic(self, value)
                end
            end
        end
        local ticks, hz_fn = method(provider, "ticks"), method(provider, "hz")
        if ticks and hz_fn then
            local tick_ok, raw = pcall(ticks)
            local hz_ok, hz = pcall(hz_fn)
            if tick_ok and hz_ok and finite(raw) and raw % 1 == 0 and finite(hz) and hz > 0 then
                -- % also normalizes a signed 32-bit tick returned by some BSPs.
                raw = raw % WRAP
                if self.raw_last == nil then
                    self.raw_ms = self.last_ms or (raw * 1000.0 / hz)
                else
                    local delta_ticks = (raw - self.raw_last) % WRAP
                    self.raw_ms = self.raw_ms + delta_ticks * 1000.0 / hz
                end
                self.raw_last = raw
                return keep_monotonic(self, self.raw_ms)
            end
        end
    end
    -- A missing frequency must never silently turn raw ticks into milliseconds.
    if nonnegative(fallback_ms) then return keep_monotonic(self, fallback_ms + 0.0) end
    return self.last_ms or 0
end

-- Absolute high/low milliseconds and the extended raw fallback do not wrap at
-- 2^32 milliseconds. A provider reset/backward input contributes no elapsed time.
function Clock.elapsed(now_ms, before_ms)
    if not nonnegative(now_ms) or not nonnegative(before_ms) or now_ms < before_ms then return 0 end
    return now_ms - before_ms
end

local default = setmetatable({dynamic = true}, Instance)

-- Resolve _G.mcu on every call so desktop adapters can attach after require().
function Clock.now(fallback_ms)
    return default:now(fallback_ms)
end

return Clock
