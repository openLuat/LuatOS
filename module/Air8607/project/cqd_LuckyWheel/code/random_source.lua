-- Uniform fan selection using the official LuatOS crypto.trng byte source.
-- No clock seed or pseudo-random fallback: a failed TRNG aborts the draw.
-- Official API: https://docs.openluat.com/osapi/core/crypto/#cryptotrnglen
local Random = {}
local Instance = {}
Instance.__index = Instance

local UINT32_RANGE = 4294967296.0
local MAX_ATTEMPTS = 32

local function valid_count(n)
    return type(n) == "number" and n == n and n >= 1 and n <= 65536
        and n == math.floor(n)
end

local function select_index(provider, n)
    if not valid_count(n) then
        return nil, "invalid_count"
    end

    -- Native LuatOS core libraries are indexable ROTable userdata, not tables.
    -- Also protect __index: unavailable or malformed providers must not crash UI.
    local lookup_ok, trng = pcall(function() return provider.trng end)
    if not lookup_ok then
        return nil, "trng_lookup_failed"
    end
    if type(trng) ~= "function" then
        return nil, "trng_unavailable"
    end

    -- Accept only the largest prefix whose length is exactly divisible by n.
    -- Every accepted residue then has the same number of uint32 inputs.
    local limit = UINT32_RANGE - (UINT32_RANGE % n)
    for _ = 1, MAX_ATTEMPTS do
        local ok, bytes = pcall(trng, 4)
        if not ok then
            return nil, "trng_failed"
        end
        if type(bytes) ~= "string" then
            return nil, "trng_invalid_result"
        end
        if #bytes ~= 4 then
            return nil, "trng_invalid_length"
        end
        local b1, b2, b3, b4 = string.byte(bytes, 1, 4)
        -- Float constants prevent signed 32-bit integer overflow in Lua hosts.
        -- All uint32 values remain exact in the double-precision number type.
        local value = b1 * 16777216.0 + b2 * 65536.0 + b3 * 256.0 + b4
        if value < limit then
            return math.floor(value % n) + 1
        end
    end
    return nil, "trng_rejection_limit"
end

function Random.new(provider)
    return setmetatable({provider = provider}, Instance)
end

function Instance:index(n)
    return select_index(self.provider, n)
end

-- Deliberately a normal function: Random.index(n), not Random:index(n).
-- Resolve the global on each draw to support native startup and test injection.
function Random.index(n)
    return select_index(_G.crypto, n)
end

return Random
