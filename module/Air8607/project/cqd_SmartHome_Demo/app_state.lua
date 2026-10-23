--[[
@module app_state
@summary 全屋智能 Demo 的设备数据层（两房一厅：客厅 / 主卧 / 次卧）
@version 1.0
@usage
1、集中保存房间、灯光、窗帘、温湿度、空调状态；
2、所有值均为本地模拟，接入真实设备时把 set_xxx / 定时器里的赋值
   换成 MQTT 或 HTTP 下发即可，UI 层不需要改动；
3、提供 get_room / avg_temp / start_sim 等接口。
]]

local M = {}

-- 风速档位：1=低 2=中 3=高
M.FAN_LABELS = { "低", "中", "高" }

function M.fan_label(v)
    return M.FAN_LABELS[v] or "中"
end

-- 空调温度可调范围
M.AC_TEMP_MIN = 16
M.AC_TEMP_MAX = 30

-- 房间数据（DEMO：两房一厅）
M.rooms = {
    {
        id      = "living",
        name    = "客厅",
        en      = "Living Room",
        temp    = 26.4,
        humi    = 58,
        light   = { label = "客厅灯", on = true },
        curtain = { label = "窗帘",   on = false },   -- on = 已拉开
        ac      = { on = true, temp = 26, fan = 2 },  -- fan: 1低 2中 3高
    },
    {
        id      = "master",
        name    = "主卧",
        en      = "Master Bedroom",
        temp    = 25.1,
        humi    = 62,
        light   = { label = "主卧灯", on = false },
        curtain = { label = "窗帘",   on = true },
        ac      = { on = true, temp = 25, fan = 1 },
    },
    {
        id      = "second",
        name    = "次卧",
        en      = "Second Bedroom",
        temp    = 27.3,
        humi    = 55,
        light   = { label = "次卧灯", on = false },
        curtain = { label = "窗帘",   on = false },
        ac      = { on = false, temp = 27, fan = 3 },
    },
}

function M.get_room(index)
    return M.rooms[index]
end

-- 全屋平均温度（保留 1 位小数）
function M.avg_temp()
    local sum = 0
    for _, r in ipairs(M.rooms) do
        sum = sum + r.temp
    end
    return math.floor(sum / #M.rooms * 10 + 0.5) / 10
end

function M.fmt_temp(t)
    return string.format("%.1f", t)
end

-- 空调温度加减（带边界限制）
function M.ac_temp_delta(room, delta)
    local t = room.ac.temp + delta
    if t < M.AC_TEMP_MIN then t = M.AC_TEMP_MIN end
    if t > M.AC_TEMP_MAX then t = M.AC_TEMP_MAX end
    room.ac.temp = t
    return t
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
