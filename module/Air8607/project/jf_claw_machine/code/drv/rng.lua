--[[
@module rng
@summary 随机数：优先 crypto.trng 真随机，不可用时回退 LCG
@ver 1.0.0
@author cqd
@usage
local rng = require "rng"
local r = rng.float()  -- [0,1)
local n = rng.int(6)   -- [1,6]
]]

local M = {}

local state = 12345
local seeded = false

local function seed()
    local ok, tick = pcall(function() return mcu.ticks() end)
    state = (((ok and type(tick) == "number") and tick or 12345) * 2654435761 + 1013904223) % 2147483648
    seeded = true
end

-- [0,1) 区间浮点随机
function M.float()
    local ok, raw = pcall(crypto.trng, 4)
    if ok and type(raw) == "string" and #raw >= 4 then
        local b1, b2, b3, b4 = string.byte(raw, 1, 4)
        local u = ((b4 * 256 + b3) * 256 + b2) * 256 + b1
        return u / 4294967296
    end
    if not seeded then seed() end
    state = (state * 1103515245 + 12345) % 2147483648
    return state / 2147483648
end

-- [1,n] 区间整数随机
function M.int(n)
    n = math.floor(tonumber(n) or 1)
    if n < 1 then return 1 end
    return math.floor(M.float() * n) + 1
end

return M
