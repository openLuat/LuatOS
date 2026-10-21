--[[
@module  mock_data
@summary 农业大棚模拟数据源（传感器/设备/告警状态）
@usage
真机联调时把本模块各字段替换为 MQTT/Modbus/串口采集结果即可，
UI 层只依赖 data.* 字段与 data.simulate() 刷新接口。
]]
local M = {}

-- 分区环境（6 个棚区）
M.zones = {
    { id = "A1", name = "育苗区", t = 25.2, h = 75, tOpt = { 22, 28 }, hOpt = { 65, 82 }, note = "雾培 | 24C恒温" },
    { id = "A2", name = "番茄区", t = 26.8, h = 68, tOpt = { 22, 30 }, hOpt = { 60, 80 }, note = "开花期 | 滴灌运行" },
    { id = "A3", name = "黄瓜区", t = 28.6, h = 72, tOpt = { 22, 30 }, hOpt = { 65, 85 }, note = "温度偏高 | 风机联动" },
    { id = "B1", name = "叶菜区", t = 24.6, h = 84, tOpt = { 18, 26 }, hOpt = { 60, 80 }, note = "湿度偏高 | 顶窗通风" },
    { id = "B2", name = "草莓区", t = 23.9, h = 66, tOpt = { 18, 26 }, hOpt = { 55, 75 }, note = "结果期 | 水肥一体" },
    { id = "B3", name = "花卉区", t = 25.8, h = 70, tOpt = { 20, 28 }, hOpt = { 60, 80 }, note = "催花期 | 补光80%" },
}

-- 土壤墒情
M.soil = {
    { z = "育苗区A1", t = 22.4, w = 58, ph = 6.6, ec = 1.3 },
    { z = "番茄区A2", t = 23.1, w = 41, ph = 6.4, ec = 1.6 },
    { z = "黄瓜区A3", t = 23.8, w = 46, ph = 6.8, ec = 1.5 },
    { z = "叶菜区B1", t = 21.9, w = 63, ph = 6.2, ec = 1.2 },
    { z = "草莓区B2", t = 21.2, w = 22, ph = 6.1, ec = 1.8 },
    { z = "花卉区B3", t = 22.8, w = 52, ph = 7.1, ec = 1.1 },
}

-- 环境总指标
M.env = {
    temp = 26.4, hum = 68, co2 = 620, lux = 32.4,   -- lux 单位 klux
    outTemp = 22.6, outHum = 54, wind = 3.4, gust = 5.1, windDir = "东南",
    rain = 0.0, pressure = 1013, uv = 5, dew = 12.8,
}

-- 水质
M.water = { score = 92, wt = 18.6, ph = 7.2, dox = 6.8, ec = 1.24, ntu = 3.4, level = 82 }

-- 设备（on=运行中, val=状态描述）
M.devices = {
    { id = "shutter", name = "卷帘",      sub = "顶窗卷膜机",  on = true,  val = "开度60%",   power = "0.75kW" },
    { id = "wet",     name = "湿帘",      sub = "蒸发降温",    on = false, val = "水泵待机",  power = "1.1kW" },
    { id = "fan",     name = "风机",      sub = "环流x4",     on = true,  val = "转速1200",  power = "0.55kW" },
    { id = "shade",   name = "遮阳网",    sub = "外遮阳",      on = true,  val = "展开70%",   power = "0.37kW" },
    { id = "co2gen",  name = "CO2气肥",  sub = "CO2发生器",   on = false, val = "目标800ppm", power = "0.2kW" },
    { id = "spray",   name = "喷淋",      sub = "微雾降温",    on = false, val = "待机",      power = "0.4kW" },
    { id = "irrig",   name = "浇灌",      sub = "滴灌管路",    on = true,  val = "流量2.4m3/h", power = "1.5kW" },
    { id = "fert",    name = "水肥",      sub = "施肥一体机",  on = false, val = "EC目标1.6", power = "0.6kW" },
    { id = "heat",    name = "加热",      sub = "热风炉",      on = false, val = "设定18C",   power = "3.0kW" },
    { id = "led",     name = "LED补光",   sub = "补光灯组",    on = true,  val = "亮度80%",   power = "0.9kW" },
}

-- 告警（lv: 1紧急 2警告 3提示）
-- msg 为大屏短文案（完整描述放 detail，供详情页/日志使用）
M.alarms = {
    { lv = 1, time = "14:32", src = "叶菜B1", msg = "湿度92%超限", detail = "空气湿度92%RH超上限，已开顶窗除湿", done = false },
    { lv = 2, time = "14:05", src = "草莓B2", msg = "墒情22%偏低", detail = "土壤含水率22%低于阈值，已联动滴灌", done = false },
    { lv = 2, time = "13:47", src = "气象站", msg = "风速8.2m/s", detail = "瞬时风速8.2m/s，遮阳网已收拢保护", done = false },
    { lv = 3, time = "12:20", src = "水肥站", msg = "浊度3.4偏高", detail = "浊度3.4NTU接近上限，建议反冲洗", done = true },
    { lv = 3, time = "11:58", src = "CO2设备", msg = "气瓶余量18%", detail = "气瓶剩余压力18%，请安排充装", done = true },
}

-- 随机扰动模拟采集刷新（真机替换为真实采集回调）
local function jitter(v, a) return v + (math.random() * 2 - 1) * a end
local function clamp(v, lo, hi) return math.min(hi, math.max(lo, v)) end

function M.simulate()
    local zt, zh = 0, 0
    for _, z in ipairs(M.zones) do
        z.t = math.floor(clamp(jitter(z.t, 0.3), 16, 34) * 10 + 0.5) / 10
        z.h = math.floor(clamp(jitter(z.h, 1.2), 35, 96) + 0.5)
        zt = zt + z.t
        zh = zh + z.h
    end
    M.env.temp = math.floor(zt / #M.zones * 10 + 0.5) / 10
    M.env.hum = math.floor(zh / #M.zones + 0.5)
    M.env.co2 = math.floor(clamp(jitter(M.env.co2, 18), 380, 1200))
    M.env.lux = math.floor(clamp(jitter(M.env.lux, 1.4), 2, 58) * 10) / 10
    M.env.wind = math.floor(clamp(jitter(M.env.wind, 0.8), 0.2, 12) * 10) / 10
    for _, s in ipairs(M.soil) do
        s.w = math.floor(clamp(jitter(s.w, 0.8), 12, 80))
        s.t = math.floor(clamp(jitter(s.t, 0.15), 5, 40) * 10) / 10
    end
end

-- 告警统计
function M.alarm_counts()
    local c = { 0, 0, 0, 0 }  -- 紧急/警告/提示/已处理
    for _, a in ipairs(M.alarms) do
        if a.done then c[4] = c[4] + 1 else c[a.lv] = c[a.lv] + 1 end
    end
    return c
end

function M.running_count()
    local n = 0
    for _, d in ipairs(M.devices) do
        if d.on then n = n + 1 end
    end
    return n
end

return M
