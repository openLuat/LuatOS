--[[
@module  check_wifi
@summary 用于检查当前模组中WiFi是否是最新版本，使用蓝牙配网功能需要WIFI版本≥14。
            如果模组中WiFi版本<14，则需要打开此功能启动升级。
@version 1.1
@date    2025.08.11
@author  拓毅恒
@usage
本文件为WIFI固件升级功能模块，核心业务逻辑为：
1、判断网络是否正常；
2、执行WiFi升级操作；
3、反馈升级结果；

本文件没有对外接口，直接在main.lua中require "check_wifi"就可以加载运行；
]]
local exfotawifi = require("exfotawifi")

local function wifi_fota_task_func()
    local result = exfotawifi.request()
    if result then
        log.info("exfotawifi", "升级任务执行成功")
    else
        log.info("exfotawifi", "升级任务执行失败")
    end
end

-- 判断网络是否正常
local function wait_ip_ready()
    local result, ip, adapter = sys.waitUntil("IP_READY", 30000)
    if result then
        log.info("exfotawifi", "开始执行升级任务")
        sys.taskInit(wifi_fota_task_func)
    else
        log.error("当前正在升级WIFI&蓝牙固件，请插入可以上网的SIM卡")
    end
end

-- 在设备启动时检查网络状态
sys.taskInit(wait_ip_ready)
