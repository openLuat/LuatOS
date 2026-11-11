--[[
@module  conf
@summary 注塑车间工艺监控终端 - 全局配置（机台/工艺/模具/工单/报警/布局）
@version 1.0
@date    2026.11.10
]]
local conf = {}

-- ==================== 屏幕与运行参数 ====================
conf.W, conf.H = 1024, 600
conf.tick_ms = 1000           -- 主循环节拍（工艺仿真 1Hz）
conf.name = "注塑车间工艺监控"
conf.shop = "一车间 · 8 台伺服注塑机"

conf.font = { size = 16, cache_size = 12, antialias = 1 }
-- 背光必须走 PWM3（PIN55 = GPIO13），与 factory/config/eng_8607_10i_v0.lua 一致。
-- 写成 0 会去操作 PWM0，背光通道无人管，屏幕表现就是"黑屏/不动"。
conf.backlight = { pwm_ch = 3, freq = 1000, default = 85 }
conf.kv = "ims"               -- fskv 键前缀

-- ==================== 布局 ====================
conf.top_h = 72
conf.body_y = 72
conf.body_h = 528
conf.pad = 20
conf.gap = 12

conf.tabs = { "总览", "工艺", "模具工单", "报警", "设置" }

-- ==================== 机台状态 ====================
conf.state = {
    run   = { name = "运行", color = 0x2ED47A },
    idle  = { name = "待机", color = 0x35A8E0 },
    alarm = { name = "报警", color = 0xFF4D5E },
    stop  = { name = "停机", color = 0x8899A6 },
    setup = { name = "调机", color = 0xFFB020 },
}

-- ==================== 成型周期阶段 ====================
-- ratio 之和为 1.0，仿真按占比推进当前阶段
conf.phases = {
    { key = "close",  name = "合模", ratio = 0.08 },
    { key = "inject", name = "射胶", ratio = 0.12 },
    { key = "hold",   name = "保压", ratio = 0.20 },
    { key = "cool",   name = "冷却", ratio = 0.45 },
    { key = "open",   name = "开模", ratio = 0.08 },
    { key = "eject",  name = "顶出", ratio = 0.07 },
}

-- ==================== 工艺参数（可调，写回 KV）====================
conf.params = {
    { key = "inj_press",  name = "射胶压力", unit = "MPa", min = 40,  max = 140, step = 1,   def = 88 },
    { key = "inj_speed",  name = "射胶速度", unit = "%",   min = 20,  max = 99,  step = 1,   def = 62 },
    { key = "hold_press", name = "保压压力", unit = "MPa", min = 20,  max = 100, step = 1,   def = 55 },
    { key = "hold_time",  name = "保压时间", unit = "s",   min = 0.5, max = 8,   step = 0.1, def = 3.2 },
    { key = "cool_time",  name = "冷却时间", unit = "s",   min = 5,   max = 40,  step = 0.5, def = 16.5 },
    { key = "barrel_t",   name = "料筒温度", unit = "℃",   min = 180, max = 280, step = 1,   def = 235 },
    { key = "mold_t",     name = "模具温度", unit = "℃",   min = 30,  max = 110, step = 1,   def = 62 },
    { key = "back_press", name = "熔胶背压", unit = "MPa", min = 1,   max = 20,  step = 0.5, def = 6 },
}

-- ==================== 报警阈值（可调）====================
conf.limits = {
    { key = "mold_hi",   name = "模温上限",     unit = "℃", min = 60,  max = 130, step = 1,   def = 95 },
    { key = "oil_hi",    name = "油温上限",     unit = "℃", min = 35,  max = 75,  step = 1,   def = 58 },
    { key = "cyc_dev",   name = "周期偏差上限", unit = "%",  min = 5,   max = 40,  step = 1,   def = 15 },
    { key = "lowp_time", name = "低压保护时间", unit = "s",  min = 0.5, max = 5,   step = 0.1, def = 1.8 },
}

-- ==================== 模具台账（life/used 单位：万模次）====================
conf.molds = {
    { id = "M-101", product = "面板前壳", cavity = 2, life = 100, used = 42.6, state = "在用" },
    { id = "M-102", product = "面板后壳", cavity = 2, life = 100, used = 88.4, state = "在用" },
    { id = "M-103", product = "导光板",   cavity = 4, life = 80,  used = 23.1, state = "在用" },
    { id = "M-104", product = "支架",     cavity = 8, life = 120, used = 61.7, state = "在用" },
    { id = "M-105", product = "电池盖",   cavity = 4, life = 90,  used = 79.5, state = "在用" },
    { id = "M-106", product = "卡扣",     cavity = 16, life = 150, used = 33.2, state = "在用" },
    { id = "M-107", product = "装饰圈",   cavity = 2, life = 80,  used = 12.8, state = "在库" },
    { id = "M-108", product = "端盖",     cavity = 6, life = 100, used = 55.0, state = "在库" },
}

-- ==================== 生产工单 ====================
conf.orders = {
    { id = "WO-2603-011", product = "面板前壳", mold = "M-101", plan = 12000, done = 8640, machine = 1, state = "生产中" },
    { id = "WO-2603-012", product = "面板后壳", mold = "M-102", plan = 10000, done = 9120, machine = 2, state = "生产中" },
    { id = "WO-2603-013", product = "导光板",   mold = "M-103", plan = 8000,  done = 3260, machine = 3, state = "生产中" },
    { id = "WO-2603-014", product = "支架",     mold = "M-104", plan = 20000, done = 15400, machine = 4, state = "生产中" },
    { id = "WO-2603-015", product = "电池盖",   mold = "M-105", plan = 15000, done = 11250, machine = 5, state = "生产中" },
    { id = "WO-2603-016", product = "卡扣",     mold = "M-106", plan = 40000, done = 18600, machine = 6, state = "生产中" },
    { id = "WO-2603-017", product = "装饰圈",   mold = "M-107", plan = 6000,  done = 0,     machine = 0, state = "待排产" },
    { id = "WO-2603-018", product = "端盖",     mold = "M-108", plan = 9000,  done = 0,     machine = 0, state = "待排产" },
}

-- ==================== 机台 ====================
conf.machine = {
    count = 8,
    cols = 4,
    tonnage = 180,            -- 锁模力 t
    cycle = { min = 24.0, max = 36.0 },
}
conf.machine_ids = {
    "IMM-01", "IMM-02", "IMM-03", "IMM-04",
    "IMM-05", "IMM-06", "IMM-07", "IMM-08",
}

-- ==================== 报警代码表（level: 1 提示 2 警告 3 严重）====================
conf.alarm_codes = {
    { code = "A-101", name = "料斗缺料",       level = 2 },
    { code = "A-102", name = "模温超上限",     level = 2 },
    { code = "A-103", name = "液压油温高",     level = 1 },
    { code = "A-104", name = "开模未到位",     level = 2 },
    { code = "A-105", name = "低压保护超时",   level = 1 },
    { code = "A-106", name = "射胶压力异常",   level = 2 },
    { code = "A-107", name = "机械手取件失败", level = 3 },
    { code = "A-108", name = "周期偏差超限",   level = 1 },
}

conf.level_color = { [1] = 0xFFC53D, [2] = 0xFF9A3C, [3] = 0xFF4D5E }
conf.level_name = { [1] = "提示", [2] = "警告", [3] = "严重" }

-- ==================== 班次 ====================
conf.shifts = { "早班 08:00-16:00", "中班 16:00-24:00", "夜班 00:00-08:00" }

return conf
