--[[
@module main
@summary 全屋智能中控 Demo 入口（合宙 Air8601 + LuatOS + AirUI 核心库）
@version 1.0
@date 2026.10.14
@usage
1、硬件：合宙 Air8601（主控 Air1601，标配 7 寸 1024x600 电容触摸屏，HX8282 + GT911）
2、界面：LuatOS 核心库 airui（基于 LVGL 9.4 的图形化开发库）+ display 显示库 + hzfont 矢量中文
3、内容：两房一厅（客厅 / 主卧 / 次卧），每个房间一张半透明毛玻璃卡片，
        支持灯光开关、窗帘开关、温湿度显示、空调开关 + 温度加减 + 风速档位
4、本工程未使用任何扩展库（lib），全部基于核心库与本地脚本，烧录时无需附加 lib
]]

PROJECT = "AIR8601_SMART_HOME"
VERSION = "001.999.001"

log.info("main", PROJECT, VERSION)

-- Air8601 4G_RST 拉低（与合宙官方 Air8601 工程保持一致）
gpio.setup(64, 0, gpio.PULLDOWN)

-- 硬件初始化模块（GPIO 上电、LCD、触摸、背光、密度缩放）
local hardware = require "hardware"

-- 官方顺序：在界面模块加载之前先确定密度缩放系数（以 1024x600 为基准）
hardware.init_density_scale()

-- 看门狗：60 秒超时，每 3 秒喂狗
if wdt then
    wdt.init(60000)
    sys.timerLoopStart(wdt.feed, 3000)
    log.info("main", "看门狗已初始化，超时 60 秒")
end

-- 系统初始化任务：硬件上电 → 屏幕/触摸就绪 → 创建界面
local function system_init()
    -- 上电时序 + LCD + AirUI + 背光 + GT911 触摸
    hardware.init()

    -- 屏幕已就绪，重新计算一次密度缩放系数，确保与实际分辨率一致
    hardware.init_density_scale()

    -- 等待 AirUI 首帧渲染
    sys.wait(150)

    -- 创建全屋智能中控界面
    local ui_home = require "ui_home"
    ui_home.create()

    log.info("main", "系统初始化完成")
end

sys.taskInit(system_init)

-- 结尾总是这一句
sys.run()
-- sys.run() 之后不要加任何语句（加了也不会被执行）
