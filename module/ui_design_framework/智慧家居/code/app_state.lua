--[[
@module app_state
@summary 全屋智能 Demo 的设备数据层（四房间设备矩阵 + 场景 + 安防，四方案页面共享）
@version 2.0
@usage
1、集中保存房间、设备矩阵（灯光/窗帘/新风等）、温湿度、空调、安防状态；
2、所有值均为本地模拟，接入真实设备时把 toggle_dev / ac_delta / 定时器里的赋值
   换成 MQTT 或 HTTP 下发即可，UI 层不需要改动；
3、提供 room / set_room / dev_on_count / dev_delta / ac_delta / start_sim 等接口。
]]

local M = {}

-- 空调温度可调范围
M.AC_TEMP_MIN = 16
M.AC_TEMP_MAX = 30

-- 场景 Dock（与底部 Dock 按钮一一对应）
M.scenes = { "回家", "离家", "睡眠", "观影", "起床", "会客" }

-- 安防状态
M.security = { armed = true, locked = true }

-- 当前房间下标
M.active = 1

-- 房间数据（DEMO：客厅 / 主卧 / 书房 / 厨房）
-- devs：设备矩阵（2 列磁贴）；ds 为数值前缀（亮度/开合/风量...）
M.rooms = {
    {
        id = "living", name = "客厅",
        temp = 24.0, humi = 48, ac_t = 26, ac_mode = "制冷",
        devs = {
            { nm = "客厅主灯", on = true,  val = 60,  ds = "亮度 " },
            { nm = "客厅筒灯", on = true,  val = 80,  ds = "亮度 " },
            { nm = "灯带",     on = false, val = 70,  ds = "亮度 " },
            { nm = "客厅窗帘", on = false, val = 30,  ds = "开合 " },
            { nm = "新风",     on = true,  val = 45,  ds = "风量 " },
            { nm = "加湿器",   on = false, val = 50,  ds = "雾量 " },
        },
    },
    {
        id = "master", name = "主卧",
        temp = 25.1, humi = 55, ac_t = 25, ac_mode = "制冷",
        devs = {
            { nm = "主卧吸顶灯", on = false, val = 70,  ds = "亮度 " },
            { nm = "床头灯",     on = true,  val = 30,  ds = "亮度 " },
            { nm = "主卧窗帘",   on = true,  val = 100, ds = "开合 " },
            { nm = "加湿器",     on = false, val = 50,  ds = "雾量 " },
            { nm = "新风",       on = true,  val = 40,  ds = "风量 " },
            { nm = "电热毯",     on = false, val = 60,  ds = "档位 " },
        },
    },
    {
        id = "study", name = "书房",
        temp = 23.4, humi = 44, ac_t = 24, ac_mode = "关闭",
        devs = {
            { nm = "书房台灯", on = true,  val = 80, ds = "亮度 " },
            { nm = "书房主灯", on = false, val = 60, ds = "亮度 " },
            { nm = "书房窗帘", on = false, val = 0,  ds = "开合 " },
            { nm = "新风",     on = false, val = 40, ds = "风量 " },
        },
    },
    {
        id = "kitchen", name = "厨房",
        temp = 26.2, humi = 62, ac_t = 26, ac_mode = "关闭",
        devs = {
            { nm = "厨房顶灯", on = true,  val = 90, ds = "亮度 " },
            { nm = "油烟机",   on = false, val = 70, ds = "档位 " },
            { nm = "净水器",   on = true,  val = 50, ds = "流量 " },
        },
    },
}

function M.room()
    return M.rooms[M.active]
end

function M.set_room(i)
    if i >= 1 and i <= #M.rooms then M.active = i end
    return M.room()
end

-- 房间内已开设备数 / 总数
function M.dev_on_count(room)
    local on = 0
    for _, d in ipairs(room.devs) do
        if d.on then on = on + 1 end
    end
    return on, #room.devs
end

-- 设备档位加减（0~100 边界限制），返回新值
function M.dev_delta(room, idx, delta)
    local d = room.devs[idx]
    if not d then return nil end
    local v = d.val + delta
    if v < 0 then v = 0 end
    if v > 100 then v = 100 end
    d.val = v
    return v
end

-- 空调温度加减（带边界限制），返回新值
function M.ac_delta(room, delta)
    local t = room.ac_t + delta
    if t < M.AC_TEMP_MIN then t = M.AC_TEMP_MIN end
    if t > M.AC_TEMP_MAX then t = M.AC_TEMP_MAX end
    room.ac_t = t
    return t
end

function M.fmt_temp(t)
    return string.format("%.1f", t)
end

-- 温湿度模拟：每 5 秒做一次 ±0.2℃ / ±1% 的小幅漂移，模拟真实传感器读数
function M.start_sim()
    math.randomseed(os.time() or 1)
    sys.timerLoopStart(function()
        for _, r in ipairs(M.rooms) do
            local dt = math.random() - math.random()   -- -1 ~ 1
            r.temp = r.temp + dt * 0.2
            if r.temp < 16 then r.temp = 16 end
            if r.temp > 32 then r.temp = 32 end

            local dh = math.random(-1, 1)
            r.humi = r.humi + dh
            if r.humi < 30 then r.humi = 30 end
            if r.humi > 90 then r.humi = 90 end
        end
    end, 5000)
end

return M
