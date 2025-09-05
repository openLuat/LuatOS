--[[
@module  check_wifi
@summary 远程升级wifi固件模块
@version 1.0
@date    2025.08.29
@author  王世豪
@usage
检查WiFi版本并自动升级
功能：检查当前Air8000模组的WiFi固件是否为最新版本，若不是则自动启动升级（需插入可联网的SIM卡）。
说明：Air8000的蓝牙功能依赖WiFi协处理器，需确保WiFi固件为最新版本。

本文件没有对外接口，直接在main.lua中require ""check_wifi"就可以加载运行。
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
