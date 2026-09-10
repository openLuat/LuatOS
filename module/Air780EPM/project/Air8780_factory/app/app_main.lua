--[[
@module  app_main
@summary 应用主入口模块（精简版，无UI）
@version 1.0
@date    2026.09.09
@author  江访
@usage
精简自 turnkey_devboard app_main，去除 status_provider_app 和 UI 相关模块。
加载顺序：
1. netdrv_device：网络驱动设备
2. aircloud_app：云平台应用（含传感器数据上报、CPU温度、LBS经纬度）
3. sensor_app：传感器应用
4. fota_app：FOTA升级应用
]]

-- 加载网络驱动设备功能模块
require "netdrv_device"

-- 加载 aircloud 主模块（含数据上报逻辑）
require "aircloud_app"

-- 加载 sensor_app 传感器主模块
require "sensor_app"

-- 加载 看门狗应用模块
require "watchdog_app"

