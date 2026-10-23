--[[
@module  main
@summary Air8783H SIP/CC PCM 桥接主入口
@usage
定义 PROJECT、VERSION 和远程升级 PRODUCT_KEY。
加载持久化配置、外部看门狗、网络、SIP/CC 桥接及云端业务，最后运行系统调度。
]]

-- Air8000w 纯 PCM CC <-> SIP 桥接应用入口。
PROJECT = "Air8783H_Factory"
VERSION = "001.000.001"
-- Set the IoT libfota3 project key before flashing.
PRODUCT_KEY = "uHcUqI4qv0S9W9flMZFNdjgArJoqYgIk"

sys = require "sys"
sysplus = require "sysplus"
local aircloud_settings = require "aircloud_settings"
local config = require "config"
aircloud_settings.init("8783H", config)
log.info("main", PROJECT, VERSION)
    -- 初始化硬件看门狗（Air153C，config.WDT_CONFIG 控制是否启用）
local air153c_wdt = require("air153c_wdt")
if air153c_wdt and air153c_wdt.init then air153c_wdt.init() end

require "netdrv_device"
require "sip_cc_app"
require "aircloud_app"

sys.run()
