--[[
@module  app_init
@summary 启动编排：硬件初始化 -> 密度缩放 -> 数据层启动 -> 打开主窗口
@version 1.0.0
@date    2026.10.12
@usage
main.lua 只 require 本模块；本模块在加载时注册启动任务。
把「启动编排」独立成模块，保证 main.lua 仅含 require 与 sys.run()。
]]

local hardware = require "hardware"

-- 界面外壳与各视图模块（require 即注册订阅，不会立即建界面）
require "ui_shell"
require "ui_dash"
require "ui_ctrl"
require "ui_chart"
require "ui_alarm"
require "ui_param"
require "ui_sys"

-- 数据层（模拟数据源，周期性广播 SOLAR_DATA）
local mock_data = require "mock_data"

local function system_init()
    log.info("app_init", "系统初始化开始")

    -- 硬件初始化（上电 -> LCD -> AirUI -> 背光 -> 触摸）
    hardware.init()

    -- 屏幕密度缩放（需在界面构建前计算）
    hardware.init_density_scale()

    -- 启动数据层：先发一帧，界面打开后即可直接渲染
    mock_data.init()

    -- 等 AirUI 首帧渲染完成，避免开机白屏
    sys.wait(100)

    -- 打开主窗口
    sys.publish("OPEN_SOLAR_MAIN_WIN")

    log.info("app_init", "系统初始化完成")
end

sys.taskInit(system_init)
