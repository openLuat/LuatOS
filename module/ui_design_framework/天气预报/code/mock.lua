--[[
@module mock
@summary 天气虚拟数据（按 城市×日期 固定种子缓存，切换前后数值不变，
        与 preview.html 行为一致），后续替换为真实天气 API 数据
]]

local mock = {}

mock.CITIES = {
    { name = "浦东新区", prov = "上海市" },
    { name = "黄浦区",   prov = "上海市" },
    { name = "成都市",   prov = "四川省" },
    { name = "朝阳区",   prov = "北京市" },
}
mock.DAYS = {
    { d = 12, w = "昨天" },
    { d = 13, w = "今天" },
    { d = 14, w = "周六" },
    { d = 15, w = "周日" },
    { d = 16, w = "周一" },
    { d = 17, w = "周二" },
    { d = 18, w = "周三" },
}
mock.HOURS = { "17:00", "当前", "21:00", "23:00", "01:00",
               "03:00", "05:00", "07:00", "09:00", "11:00", "13:00", "15:00" }

-- 全局选中状态（城市/日期/图表tab/视图/附加线开关，页面间共享）
mock.S = { city = 1, day = 2, tab = 1, view = "图表",
    feel_on = false, gust_on = false, dew_on = false, ftemp_on = false }

local state = {}

pcall(function()
    math.randomseed(os.time())
end)

--------------------------------------------------------------------
-- 随机游走（"live"数值：每 1.5s 微动，模拟实时读数）
--------------------------------------------------------------------
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

function mock.rint(key, min, max, drift)
    return math.floor(mock.next(key, min, max, drift) + 0.5)
end

function mock.fmt(v, dec)
    return string.format("%." .. (dec or 1) .. "f", v)
end

--------------------------------------------------------------------
-- 稳定值缓存：同一 key 只生成一次（"同一天天气不变"）
--------------------------------------------------------------------
local function stable(key, fn)
    if state[key] == nil then state[key] = fn() end
    return state[key]
end

-- 天气现象（固定于 城市+日期）
function mock.cond(ci, di)
    return stable("cond_" .. ci .. "_" .. di, function()
        local pool = { "晴", "多云", "阴", "小雨", "阵雨", "雷阵雨" }
        return pool[math.random(#pool)]
    end)
end

-- 当日最高/最低温（固定于 城市+日期）
function mock.hilo(ci, di)
    return stable("hl_" .. ci .. "_" .. di, function()
        local hi = 14 + math.random(11)
        return { hi = hi, lo = hi - 3 - math.random(5) }
    end)
end

-- 逐小时序列（整数，直接喂 chart:set_values）
-- tab: 1=温度℃ 2=降水0.1mm 3=风速km/h 4=湿度% 5=云量%
--      6=气压hPa 7=紫外线 8=可见度km 9=体感℃（固定于 城市+日期+tab）
function mock.hourly(ci, di, tab)
    return stable("h_" .. ci .. "_" .. di .. "_" .. tab, function()
        local t = {}
        if tab == 1 or tab == 9 then
            local hl = mock.hilo(ci, di)
            local off = (tab == 9) and 1 or 0   -- 体感比实际高 ~1°
            for i = 1, 12 do
                local base = hl.lo + (hl.hi - hl.lo)
                    * math.sin(math.pi * (i - 1) / 11)
                t[i] = math.floor(base + off + (math.random() * 4 - 2) + 0.5)
            end
        elseif tab == 2 then
            for i = 1, 12 do t[i] = math.random(0, 120) end
        elseif tab == 3 then
            for i = 1, 12 do t[i] = math.random(2, 30) end
        elseif tab == 4 then
            for i = 1, 12 do t[i] = 45 + math.random(50) end
        elseif tab == 5 then
            for i = 1, 12 do t[i] = 20 + math.random(70) end
        elseif tab == 6 then
            for i = 1, 12 do t[i] = 1000 + math.random(28) end
        elseif tab == 7 then
            -- 真实昼夜规律：6~18 点有紫外线，正午最强
            for i = 1, 12 do
                local h = (17 + i * 2) % 24
                local mask = (h >= 6 and h <= 18)
                    and math.sin(math.pi * (h - 6) / 12) or 0
                t[i] = math.floor(9 * mask * (0.6 + math.random() * 0.4))
            end
        else
            for i = 1, 12 do t[i] = 2 + math.random(12) end
        end
        return t
    end)
end

-- 逐小时天气图标种类（固定于 城市+日期+小时）
-- 返回 sun / moon / cloud / partly / rain / thunder（配合 theme.wicon）
function mock.hicon(ci, di, i)
    return stable("ic_" .. ci .. "_" .. di .. "_" .. i, function()
        local h = (17 + i * 2) % 24          -- 17:00 起每 2 小时
        local night = (h >= 20 or h <= 5)
        local cond = mock.cond(ci, di)
        if cond == "雷阵雨" then return "thunder" end
        if cond == "小雨" or cond == "阵雨" then
            if math.random(3) == 1 then return "cloud" end
            return "rain"
        end
        if night then
            if math.random(4) == 1 then return "cloud" end
            return "moon"
        end
        if cond == "晴" then
            return (math.random(4) == 1) and "partly" or "sun"
        end
        if cond == "多云" then
            return (math.random(2) == 1) and "partly" or "cloud"
        end
        return "cloud"  -- 阴
    end)
end

-- 天气现象 → 图标种类（hero 卡用）
function mock.icon_of(cond)
    if cond == "晴" then return "sun" end
    if cond == "多云" then return "partly" end
    if cond == "小雨" or cond == "阵雨" then return "rain" end
    if cond == "雷阵雨" then return "thunder" end
    return "cloud"
end

-- 当前温度（取"当前"时点）
function mock.cur_temp(ci, di)
    return mock.hourly(ci, di, 1)[2] or 20
end

return mock
