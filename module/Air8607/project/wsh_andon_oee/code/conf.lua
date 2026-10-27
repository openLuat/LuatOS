--[[
@module  conf
@summary 产线 Andon 安灯 + OEE 生产看板 - 板级与业务参数
@author  王世豪
@version 1.0
@date    2026.10.26
@board   Air8607（Air1603）+ 10寸 RGB 1024x600 + GT911 触摸 + SPI1 TF 卡
@usage
改产线名、班次目标、工位数、异常类型、响应阈值、模拟节奏，都只改本文件。
]]
local M = {}

-- ==================== 屏幕 ====================
M.W, M.H = 1024, 600

M.display = {
    pin_rst = 15,
    rotation = 0,
}

M.touch = {
    port = 1,
    pin_rst = 14,
    pin_int = 51,
}

M.backlight = {
    pwm_ch = 3,
    freq = 1000,
    duty = 85,          -- 0..100
}

M.font = {
    size = 16,
    cache_size = 2048,
    antialias = 1,
}

-- ==================== RTC ====================
M.rtc = {
    base_year = 1900,   -- 必须先设基准年
    timezone = 32,      -- 东八区（单位 15 分钟，8h = 32）
}

-- ==================== 产线 ====================
M.line = {
    name = "SMT 产线 A",
    shift = "白班",
    shift_hours = 8,     -- 班次时长（小时），用于可用率分母
    target = 3000,       -- 班次目标产量
    cycle_time = 42,     -- 整线节拍（秒/件）
    work_order = "WO-1026",  -- 当前工单号
    product = "X200",       -- 当前产品型号
    safety_days = 128,      -- 安全生产天数（真机可接传感器动态更新）
}

-- ==================== 工位（4 列 x 2 行 = 8 个）====================
M.stations = {
    { id = 1, name = "工位01" },
    { id = 2, name = "工位02" },
    { id = 3, name = "工位03" },
    { id = 4, name = "工位04" },
    { id = 5, name = "工位05" },
    { id = 6, name = "工位06" },
    { id = 7, name = "工位07" },
    { id = 8, name = "工位08" },
}

-- ==================== 异常类型 ====================
M.alarm_types = {
    { key = "mat", name = "缺料" },
    { key = "dev", name = "设备故障" },
    { key = "qty", name = "质量问题" },
    { key = "chg", name = "换型" },
}

-- 响应阈值（秒）：超过 warn 变黄，超过 timeout 变红并升级
M.threshold = {
    ack_warn = 60,
    ack_timeout = 120,
}

-- ==================== 刷新周期（毫秒）====================
M.tick = {
    ui = 1000,   -- 看板刷新
    sim = 1000,  -- 虚拟产线推进
}

-- ==================== 虚拟产线（无外设也能完整演示）====================
M.sim = {
    enabled = true,
    alarm_min = 25,   -- 每 25~55 秒随机产生一次异常
    alarm_max = 55,
    auto_recover = false,  -- true 时异常到点自动恢复（纯展示模式）
}

return M
