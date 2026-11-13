--[[
@module  data_sim
@summary 工艺数据模拟器（3# 配料灌装线）
@version 1.0
@date    2026.11.10
@usage
本文件为 FactoryHMI 演示项目的数据层，核心业务逻辑为：
1、维护整线运行状态：运行/停止/急停、自动/手动模式、各设备启停、阀开度；
2、维护工艺量：罐内温度、系统压力、进料流量、T-101/T-102 液位、产量、运行时长；
3、维护参数设定值：目标温度、目标压力、阀开度、灌装量、灌装速度、搅拌转速、PID；
4、维护报警列表（最多 8 条，供报警页表格直接显示）与三系列趋势历史（各 60 点）；
5、data_sim.tick 每 900ms 推进一次，做一阶惯性趋近 + 噪声，并触发超温报警。

对外接口：
1、data_sim.init    初始化趋势历史
2、data_sim.start   启动 900ms 推进定时器
3、data_sim.tick    推进一步（定时器回调）
4、data_sim.add_alarm 追加一条报警
5、data_sim.fmt     定点格式化数字
]]

local M = {}

-- ---------------- 运行状态 ----------------
M.running = true          -- 整线运行中
M.estop = false           -- 急停已触发
M.mode = "auto"           -- auto | manual

-- 设备状态
M.p1 = true               -- 进料泵 P-101
M.p2 = true               -- 循环泵 P-102
M.e101 = true             -- 换热器 E-101
M.v2 = true               -- 灌装阀 FV-102
M.v1 = 64                 -- 调节阀 FV-101 开度 %

-- 工艺量
M.tankA = 62              -- T-101 液位 %
M.tankB = 44              -- T-102 液位 %
M.temp = 78.4
M.press = 0.62
M.flow = 126.5
M.count = 1284
M.sec = 7654              -- 累计运行秒数

-- 设定值
M.tempSet = 80.0
M.pressSet = 0.65
M.fillMl = 250
M.speed = 70
M.rpm = 320
M.kp = 2.4
M.ki = 0.8
M.recipe = 1              -- 当前选中配方 1~3

-- 趋势量程（chart 统一 0~100 归一化）
M.TEMP_MIN, M.TEMP_MAX = 40, 110
M.PRESS_MIN, M.PRESS_MAX = 0.3, 0.9
M.FLOW_MIN, M.FLOW_MAX = 0, 240

-- 报警列表：t 时间 / code 代码 / msg 描述 / lv 等级 crit|warn|info / ack 已确认
M.alarms = {
    {t = "08:12:04", code = "A-021", msg = "混合罐 T-102 液位低于 30%", lv = "warn", ack = false},
    {t = "07:56:31", code = "A-014", msg = "循环泵 P-102 电流偏高", lv = "warn", ack = true},
    {t = "07:40:12", code = "A-002", msg = "压缩空气压力低", lv = "info", ack = true},
}
M.ALARM_MAX = 8

-- 趋势历史（0~100 归一化后的值）
M.hist = {temp = {}, press = {}, flow = {}}
M.HIST_POINTS = 60

-- 选中的报警行下标，-1 表示未选
M.sel_alarm = -1

-- 超温报警去抖
local temp_latch = false

--[[
定点格式化数字；

@api data_sim.fmt(value, digits)
@number value 数值
@int digits 小数位
@return string 文本
]]
function M.fmt(value, digits)
    local fmtstr = "%." .. tostring(digits) .. "f"
    return string.format(fmtstr, value)
end

--[[
数值限幅；
]]
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

--[[
归一化到 0~100，供 chart 使用；
]]
local function norm(v, vmin, vmax)
    return clamp((v - vmin) / (vmax - vmin) * 100, 0, 100)
end

M.norm = norm

--[[
追加一条报警到表头；
]]
function M.add_alarm(code, msg, lv)
    local item = {t = os.date("%H:%M:%S"), code = code, msg = msg, lv = lv, ack = false}
    table.insert(M.alarms, 1, item)
    while #M.alarms > M.ALARM_MAX do
        table.remove(M.alarms)
    end
    M.sel_alarm = -1
end

--[[
统计未确认报警数；
]]
function M.unack_count()
    local n = 0
    for i = 1, #M.alarms do
        if not M.alarms[i].ack then n = n + 1 end
    end
    return n
end

--[[
设备是否处于“通电且整线运行”状态；
]]
function M.dev_on(key)
    if M.estop or not M.running then return false end
    if key == "v1" then return M.v1 > 0 end
    return M[key] == true
end

--[[
初始化 60 点趋势历史；
]]
function M.init()
    local i
    for i = 1, M.HIST_POINTS do
        M.hist.temp[i] = norm(76 + (i % 7) * 0.6, M.TEMP_MIN, M.TEMP_MAX)
        M.hist.press[i] = norm(0.58 + (i % 5) * 0.012, M.PRESS_MIN, M.PRESS_MAX)
        M.hist.flow[i] = norm(112 + (i % 9) * 2.4, M.FLOW_MIN, M.FLOW_MAX)
    end

    -- 极值统计初值（趋势页三张统计卡）
    M.t_min, M.t_max = M.temp, M.temp
    M.p_min, M.p_max = M.press, M.press
    M.f_min, M.f_max = M.flow, M.flow
    M.last = {temp = norm(M.temp, M.TEMP_MIN, M.TEMP_MAX),
              press = norm(M.press, M.PRESS_MIN, M.PRESS_MAX),
              flow = norm(M.flow, M.FLOW_MIN, M.FLOW_MAX)}
end

--[[
推进一步工艺仿真；
]]
function M.tick()
    if M.running and not M.estop then
        M.sec = M.sec + 1

        local load = (M.v1 / 100) * (M.speed / 100)
        local feed = 0
        if M.dev_on("p1") then feed = 1 end
        local circ = 0
        if M.dev_on("p2") then circ = 1 end

        -- 一阶惯性趋近设定值 + 小幅噪声
        M.temp = M.temp + (M.tempSet - M.temp) * 0.10 + (math.random() - 0.5) * 0.45
        M.press = M.press + (M.pressSet - M.press) * 0.12 + (math.random() - 0.5) * 0.012
        M.flow = feed * (58 + load * 150) + (math.random() - 0.5) * 2.4
        if M.flow < 0 then M.flow = 0 end

        if feed == 1 and M.v1 > 0 then
            M.tankA = clamp(M.tankA - 0.09 - load * 0.10, 2, 100)
            M.tankB = clamp(M.tankB + 0.07 + load * 0.09, 0, 97)
        end
        if feed == 0 and circ == 1 then
            M.tankB = clamp(M.tankB - 0.05, 0, 97)
        end

        if M.dev_on("v2") and feed == 1 and M.v1 > 0 and math.random() < 0.55 then
            M.count = M.count + 1
        end
    end

    -- 超温报警，带去抖
    if M.temp > 88 and not temp_latch then
        temp_latch = true
        M.add_alarm("A-031", "混合罐温度超高 " .. M.fmt(M.temp, 1) .. "℃", "crit")
    end
    if M.temp < 86 then temp_latch = false end

    -- 最新采样点（trend_win 用 chart:add_point 推进曲线）
    M.last = {
        temp = norm(M.temp, M.TEMP_MIN, M.TEMP_MAX),
        press = norm(M.press, M.PRESS_MIN, M.PRESS_MAX),
        flow = norm(M.flow, M.FLOW_MIN, M.FLOW_MAX),
    }
    -- 极值统计
    if M.temp > M.t_max then M.t_max = M.temp end
    if M.temp < M.t_min then M.t_min = M.temp end
    if M.press > M.p_max then M.p_max = M.press end
    if M.press < M.p_min then M.p_min = M.press end
    if M.flow > M.f_max then M.f_max = M.flow end
    if M.flow < M.f_min and M.flow > 0 then M.f_min = M.flow end
end

--[[
启动推进定时器；
]]
function M.start()
    M.init()
    sys.timerLoopStart(M.tick, 900)
end

return M
