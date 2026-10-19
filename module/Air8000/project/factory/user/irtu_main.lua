--[[
@module  irtu_main
@summary Air8000 出厂固件正常模式功能初始化模块
@version 2.0.0
@date    2026.10.16
@usage
本文件为出厂固件正常模式的功能初始化模块：
    按版本加载网卡(netdrv_device)，加载 default/driver/create/watchdog_app，
    在 task 中依次初始化。
    - 传感器采集（sensor_task + factory_app）由 create → factory_app → sensor_task 链式加载
    - 外置硬件看门狗 watchdog_app 按 factory_config 版本配置启用
    - 8000G 内置 GNSS 由 factory_app 自动启用，无需在此 gnss.init()
    - 8000T TTS 由 factory_app 懒加载 audio_config，无需在此显式加载
]]
local irtu_main = {}

-- 网卡驱动（按 factory_config.get_netdev() 分发：4g/wifi/eth/multiple，兼容 PC/Air8101）
require "netdrv_device"
local default = require "default"
-- 加载gnss模块，如果需要独立GNSS透传功能，请加载此模块
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

