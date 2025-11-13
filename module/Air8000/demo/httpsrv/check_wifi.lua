--[[
@module  check_wifi
@summary 远程升级wifi固件模块
@version 1.1
@date    2025.10.28
@author  拓毅恒
@usage
检查WiFi版本并自动升级
功能：检查当前Air8000模组的WiFi固件是否为最新版本，若不是则自动启动升级（需确保模组已经正常联网）。
完毕后最好取消注意：升级调用，防止后期版本升级过高导致程序使用不稳定。

本文件没有对外接口，直接在main.lua中require "check_wifi"就可以加载运行。
]]

local exfotawifi = require("exfotawifi")

local function fota_wifi_task()
    local result = exfotawifi.request()
    if result then
        log.info("exfotawifi", "升级任务执行成功")
    else
        log.info("exfotawifi", "升级任务执行失败")
    end

    -- 注意：固件版本需≥V2017版本才有`AIRLINK_SFOTA_DONE`事件
    -- 如下操作，在下载完毕后会重启模组，将版本更新到最新
    sys.waitUntil("AIRLINK_SFOTA_DONE")
    log.info("fotawifi","WIFI下载完毕，开始重启")
    sys.wait(100)
    pm.reboot()
end

-- 在设备启动时检查SIM卡状态
sys.taskInit(fota_wifi_task)