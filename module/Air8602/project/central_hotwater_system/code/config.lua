--[[
@module  config
@summary 太阳能热水工程控制系统 - 全局配置
@version 1.0.0
@date    2026.10.12
@usage
集中存放硬件、界面、数据模拟的配置项。
各模块通过 require "config" 读取，不在业务代码里散落魔法数字。
]]

local config = {}

config.project = "SOLAR_HOTWATER"
config.version = "001.000.001"

-- ============ 屏幕 / 触摸（Air8602 + HX8282 10.1寸 1024x600 + GT911）============
config.lcd = {
    interface = "rgb",
    pin_rst = 15,          -- HX8282 复位脚；Air8602 无 LCD_EN，不传 pin_pwr
    w = 1024,
    h = 600,
    hbp = 140, hspw = 20, hfp = 160,
    vbp = 20,  vspw = 3,  vfp = 12,
    bus_speed = 50 * 1000 * 1000,
}

config.touch = {
    port = 1,              -- I2C PORT1（CLK=GPIO33 / SDA=GPIO32）
    pin_rst = 72,          -- TP_RESET
    pin_int = 51,          -- TP_INT
    w = 1024,
    h = 600,
}

config.backlight_pin = 13

-- 上电时序（顺序 + 延时，参照 Air8602 EVB）
config.power_steps = {
    { pin = 42, level = 1, delay = 50 },
    { pin = 43, level = 1 },
    { pin = 52, level = 1 },
    { pin = 56, level = 1 },
    { pin = 57, level = 1 },
}

-- ============ 界面 ============
config.theme = "dark"          -- "dark" / "light"
config.font_size = 20          -- hzfont 基础注册字号
config.text_scale = 1.3        -- 全局字号放大系数（设计稿 10~12px 在 hzfont 下偏小）
config.product = "太阳能热水工程控制系统"
config.brand = "SOLAROS"       -- 侧栏品牌
config.link = "4G"             -- 侧栏联网标签

-- ============ 数据模拟（数据层节奏，UI 不关心具体数值）============
config.data = {
    tick_ms = 1000,        -- 数据刷新周期
    spark_points = 20,     -- 温度卡 spark 折线点数
    trend_points = 24,     -- 曲线页点数（24h）
    alarm_visible = 6,     -- 报警列表可见条数（无滚动条，固定条数）
}

-- 默认运行参数（设置页可直接修改）
config.params = {
    startup_dt   = 8.0,    -- 集热循环启动温差 ℃
    stop_dt      = 3.0,    -- 集热循环停止温差 ℃
    heat_on      = 50,     -- 电加热启动温度 ℃
    heat_off     = 60,     -- 电加热停止温度 ℃
    overtemp     = 85,     -- 高温保护温度 ℃
    antifreeze   = 5,      -- 防冻启动温度 ℃
    water_on     = 30,     -- 上水启动水位 %
    water_off    = 95,     -- 上水停止水位 %
    low_level    = 20,     -- 低水位报警 %
    dry_burn     = 15,     -- 防干烧保护值 %
    report_interval = 60,  -- 数据上报间隔 s
}

-- 各参数的步进范围（min/max/step/unit），供设置页步进器使用
config.param_spec = {
    startup_dt = { min = 2,   max = 20,  step = 0.5, unit = "℃" },
    stop_dt    = { min = 1,   max = 10,  step = 0.5, unit = "℃" },
    heat_on    = { min = 30,  max = 90,  step = 1,   unit = "℃" },
    heat_off   = { min = 35,  max = 95,  step = 1,   unit = "℃" },
    overtemp   = { min = 60,  max = 100, step = 1,   unit = "℃" },
    antifreeze = { min = 0,   max = 15,  step = 1,   unit = "℃" },
    water_on   = { min = 10,  max = 80,  step = 5,   unit = "%" },
    water_off  = { min = 50,  max = 100, step = 5,   unit = "%" },
    low_level  = { min = 5,   max = 50,  step = 5,   unit = "%" },
    dry_burn   = { min = 5,   max = 40,  step = 5,   unit = "%" },
    report_interval = { min = 10, max = 300, step = 10, unit = "s" },
}

-- 默认保护开关状态
config.switches = {
    auto_run   = true,     -- 自动运行模式
    antifreeze = true,     -- 防冻保护
    overtemp   = true,     -- 高温保护
    dry_burn   = true,     -- 防干烧保护
}

-- ============ 调试开关（出厂默认关闭）============
config.debug = {
    -- 视图切换性能
    perf_log = true,
    -- 视图实例缓存：true = 每个视图只建一次，切换改为「隐藏旧 + 显示新」（大幅提速）
    view_cache = true,
    view_cache_max = 6,
    view_cache_mem_high = 85,
    -- 开机预热：主窗口打开后按顺序把其余视图预先建好并隐藏
    view_preload = true,
    view_preload_delay = 2500,   -- 窗口打开后延迟多久开始预热（ms）
    view_preload_gap = 1200,     -- 相邻两个视图的预热间隔（ms）
    -- AirUI 内置调试统计（每秒 FPS/内存/组件数；组件级日志较多，仅排查用）
    airui_debug = false,
}

return config
