--[[
@module  config
@summary VOCs 在线环境监测系统 - 全局配置
@version 1.0.0
@date    2026.10.10
@usage
集中存放硬件、界面、数据模拟的配置项。
各模块通过 require "config" 读取，不在业务代码里散落魔法数字。
]]

local config = {}

config.project = "VOCS_MONITOR"
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
    port = 1,              -- I2C PORT1
    pin_rst = 72,
    pin_int = 51,
    w = 1024,
    h = 600,
}

config.backlight_pin = 13

-- 上电时序（顺序 + 延时，参照 Air1602 EVB）
config.power_steps = {
    { pin = 42, level = 1, delay = 50 },
    { pin = 43, level = 1 },
    { pin = 52, level = 1 },
    { pin = 56, level = 1 },
    { pin = 57, level = 1 },
}

-- ============ 界面 ============
config.theme = "light"         -- "dark" / "light"
config.font_size = 20          -- hzfont 基础注册字号（各控件可各自指定 font_size）
config.text_scale = 1.3        -- 全局字号放大系数（设计稿 10~12px 在 hzfont 下偏小，统一放大）
config.method = "VOC-58"       -- 顶栏“方法”标签
config.firmware = "v2.4.1"     -- 底栏固件版本

-- ============ 数据模拟（数据层节奏，UI 不关心具体数值）============
config.data = {
    tick_ms = 1000,        -- 数据刷新周期
    trend_period = 3,      -- 每 N 个 tick 追加一个趋势点（≈3s）
    chrom_points = 180,    -- 色谱曲线采样点数
    trend_points = 60,     -- 趋势曲线点数
}

-- 默认色谱方法参数（设置页可直接修改）
config.params = {
    column_temp = 45,      -- 柱温起始 °C
    heat_rate = 8,         -- 升温速率 °C/min
    inlet_temp = 220,      -- 进样口温度 °C
    split_ratio = 10,      -- 分流比 :1
    scan_range = 130,      -- 扫描范围 m/z
    carrier = "氦气 He",   -- 载气类型
    brightness = 80,       -- 屏幕亮度 %
}

-- 各参数的步进范围（min/max/step/单位），供设置页步进器使用
config.param_spec = {
    column_temp = { min = 30,  max = 120, step = 5,  unit = "°C" },
    heat_rate   = { min = 2,   max = 30,  step = 1,  unit = "°C/min" },
    inlet_temp  = { min = 150, max = 300, step = 10, unit = "°C" },
    split_ratio = { min = 1,   max = 50,  step = 1,  unit = ":1" },
    scan_range  = { min = 10,  max = 200, step = 5,  unit = "m/z" },
    brightness  = { min = 20,  max = 100, step = 10, unit = "%" },
}

-- 默认开关状态
config.switches = {
    auto_calib = true,     -- 自动校准
    cloud_upload = true,   -- 数据云端上传
    alarm = false,         -- 超标声光报警
    smooth = true,         -- 谱图实时平滑
}

-- ============ 调试开关（出厂默认关闭）============
-- 说明：AirUI 的 chart 里，「Y 轴刻度文字/网格」由轴配置(y_axis/hdiv)独立绘制，
--       而「曲线的像素高度」只取决于数据值 + 建图时的 y_min/y_max（lv_chart_set_axis_range）。
--       运行期没有 Lua 接口能改这个范围（airui_chart_set_range 未暴露，set_y_axis 只改标签），
--       所以一旦某端把 y_min/y_max 丢了，就会出现“刻度对、曲线贴底”的现象。
config.debug = {
    -- 趋势图数据诊断：打印三条趋势数据下发前的 点数/min/max（节流，仅前 3 次与每 20 次一次）
    trend_data_log = true,
    -- 趋势图范围自检：开启后三条曲线固定为 24 / 12 / 0 三条水平线。
    -- 判读：24 那条线画在绘图区顶边 → y_min/y_max 生效；
    --       三条线全部挤在绘图区下部约 1/4 → 固件未应用 y_min/y_max（内部范围仍是默认 0~100）。
    chart_range_probe = false,

    -- ============ 视图切换性能 ============
    -- 切换耗时日志：打印每次切换的「新建/缓存、耗时 ms、组件数、Lua 内存」
    perf_log = true,
    -- 视图实例缓存：true = 每个视图只建一次，切换改为「隐藏旧 + 显示新」（大幅提速）；
    --              false = 回到「每次切换销毁重建」的旧行为，便于对比验证
    view_cache = true,
    -- 缓存保留的视图数上限（1 = 只留当前，等效旧行为；5 = 五个视图全部常驻）
    view_cache_max = 5,
    -- LVGL 内存占用百分比超过该值就淘汰最久未用的缓存视图。
    -- 仅在 airui_debug 打开（能取到该统计值）时生效，0 = 不限制
    view_cache_mem_high = 85,
    -- 开机预热：主窗口打开后按顺序把其余视图预先建好并隐藏，使首次进入也秒开。
    -- 实测 5 个视图全常驻 lua_mem 仅 +258KB（5511/12392KB）、组件 446，内存充裕，故默认打开
    view_preload = true,
    view_preload_delay = 2500,   -- 窗口打开后延迟多久开始预热（ms），避免和开机首屏抢 CPU
    view_preload_gap = 1200,     -- 相邻两个视图的预热间隔（ms）：留足时间让渲染队列消化完
    -- 打开 AirUI 内置调试统计（每秒打印 FPS/内存/组件数）。
    -- 注意：开启后每个组件的创建/销毁都会打一行日志，仅在深度排查时临时打开
    airui_debug = false,
}

return config
