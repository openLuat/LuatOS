--[[
@module  network_watchdog
@summary 网络业务看门狗（监控网络业务运行状态，超时自动恢复）
@version 1.0.0
@date    2026.09.11
@author  嵌入式软件设计开发代理
@usage
依据 requirement.md 5.7（必须实现网络业务看门狗）：
参考官方 demo module/Air780EPM/demo/socket/client/long_connection/network_watchdog.lua，
但将喂狗方式统一为消息总线主题 FEED_NETWORK_WATCHDOG（msg_bus.FEED_NET_WDT）。
网络收发正常（excloud_app 在收到下行数据、发送成功时喂狗）即喂狗；
超过 config_app.net_wdt_timeout(240s) 未喂狗 → 判定网络业务异常 → 软件重启恢复。
本模块无对外接口，直接 require "network_watchdog" 即加载运行。
]]

local msg_bus    = require("msg_bus")
local config_app = require("config_app")

-- 网络业务看门狗任务
local function network_watchdog_task_func()
    while true do
        -- 等待喂狗消息；超时未等到则判定网络业务异常
        if not sys.waitUntil(msg_bus.FEED_NET_WDT, config_app.net_wdt_timeout * 1000) then
            log.error("network_watchdog", "网络业务看门狗超时", config_app.net_wdt_timeout, "秒无收发，软件重启恢复")
            sys.wait(3000)
            rtos.reboot()
        end
    end
end

sys.taskInit(network_watchdog_task_func)
