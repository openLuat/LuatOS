--[[

@module mock
@summary 虚拟模拟数据（随机游走），后续替换为真实传感器/云平台数据
]]

local mock = {}

local state = {}

pcall(function()
    math.randomseed(os.time())
end)

-- 随机游走取值：key相同则在上次值附近波动
function mock.next(key, min, max, drift)
    local v = state[key]
    if not v then v = (min + max) / 2 end
    drift = drift or (max - min) / 20
    v = v + (math.random() * 2 - 1) * drift
    if v < min then v = min end
    if v > max then v = max end
    state[key] = v
    return v
end

-- 格式化小数
function mock.fmt(v, dec)
    return string.format("%." .. (dec or 1) .. "f", v)
end

-- 生成一条曲线数据（整数，用于 chart:set_values）
function mock.series(key, min, max, n, base)
    local t = {}
    local v = base or mock.next(key, min, max)
    for i = 1, n do
        v = v + (math.random() * 2 - 1) * (max - min) / 10
        if v < min then v = min end
        if v > max then v = max end
        t[i] = math.floor(v + 0.5)
    end
    return t
end

-- 整数随机游走
function mock.rint(key, min, max, drift)
    return math.floor(mock.next(key, min, max, drift) + 0.5)
end

return mock
