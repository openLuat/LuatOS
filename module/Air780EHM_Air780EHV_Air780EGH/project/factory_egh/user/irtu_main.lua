--[[
@module  irtu_main
@summary 出厂固件功能初始化模块
@version 2.0.0
@date    2026.09.20
@author  李源龙
@usage
本文件为出厂固件的功能初始化模块，核心业务逻辑为：
    加载 default,driver,create 模块，然后开启 task，在 task 中初始化各个模块
    其中基础功能模块为 default,driver,create
    传感器采集模块（sensor_task + factory_app）由 create → factory_app → sensor_task 链式加载，
    无需在此显式加载
    本工程为 Air780EGH/EGP/EGG 核心板：无外置看门狗（仅 main.lua 内核软狗）、无音频 codec、
    开机即开内置 GNSS（UART2，由 factory_app 经 exgnss 管理；main.lua 已置 IRTU_DISABLE_UART2）
]]
local irtu_main = {}

local default = require "default"
local driver = require "driver"
local create = require "create"

local function irtu_init()
    -- 初始化配置
    default.init()
    -- 初始化驱动
    driver.init()
    -- 启动服务器
    create.start()
end
sys.taskInit(irtu_init)

return irtu_main

