--[[
@module  main
@summary VOCs 在线环境监测系统 - 主入口
@version 001.000.001
@date    2026.10.10
@usage
硬件初始化 -> 数据层启动 -> 打开主窗口（exwin）。
main.lua 只做模块加载与初始化编排，不含任何界面 / 业务逻辑代码。
]]

PROJECT = "VOCS_MONITOR"
VERSION = "001.000.001"

log.info("main", PROJECT, VERSION)

-- 硬件模块（上电时序 / LCD / AirUI / 背光 / 触摸）
local hardware = require "hardware"

-- 界面外壳与各视图模块（require 即注册订阅，不会立即建界面）
require "ui_shell"
require "ui_overview"
require "ui_chrom"
require "ui_ms"
require "ui_data"
require "ui_settings"

-- 数据层（模拟数据源，周期性广播 VOCS_DATA）
local mock_data = require "mock_data"

local function system_init()
    log.info("main", "系统初始化开始")

    -- 硬件初始化（上电 -> LCD -> AirUI -> 背光 -> 触摸）
    hardware.init()

    -- 屏幕密度缩放（需在界面构建前计算）
    hardware.init_density_scale()

    -- 启动数据层：先发一帧，界面打开后即可直接渲染
    mock_data.init()

    -- 等 AirUI 首帧渲染完成，避免开机白屏
    sys.wait(100)

    -- 打开主窗口
    sys.publish("OPEN_VOCS_MAIN_WIN")

    log.info("main", "系统初始化完成")
end

sys.taskInit(system_init)

sys.run()
