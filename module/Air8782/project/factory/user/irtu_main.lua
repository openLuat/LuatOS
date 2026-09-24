--[[
@module  irtu_main
@summary 出厂固件功能初始化模块
@version 2.0.0
@date    2026.09.20
@author  李源龙
@usage
本文件为出厂固件的功能初始化模块，核心业务逻辑为：
    加载default,gnss,driver,create,watchdog_app模块，然后开启task，在task中初始化各个模块
    其中基础功能模块为default,driver,create
    传感器采集模块（sensor_task + factory_app）由 create → factory_app → sensor_task 链式加载，
    无需在此显式加载
    外置看门狗（watchdog_app）按版本启用（5个版本均带 Air153）
    GNSS定位功能目前仅支持Air780EGG,Air780EGP,Air780EGH等内置GNSS的模块（8780G/S），
    8780G 版本的 GPS 由 factory_app 自动启用，无需在此打开 gnss.init()
    音频功能目前仅支持Air780EHV内置音频解码芯片的模块（8780V），
    TTS 播报由 factory_app 懒加载 audio_config，无需在此显式加载
]]
local irtu_main = {}

local default = require "default"
-- 加载gnss模块，如果需要GNSS定位功能，请加载此模块
-- local gnss = require "gnss"
local driver = require "driver"
local create = require "create"
-- 加载音频config模块，如果需要音频功能，请加载此模块
-- local audio_config= require "audio_config"
-- 外置硬件看门狗（按版本启用，加载后自动初始化并喂狗）
local watchdog_app = require "watchdog_app"

local function irtu_init()
    -- 初始化配置
    default.init()
    -- 初始化驱动
    driver.init()
    -- 启动服务器
    create.start()
    -- 启动GNSS
    -- gnss.init()
    -- 启动音频配置
    -- audio_config.init()
end
sys.taskInit(irtu_init)

return irtu_main

