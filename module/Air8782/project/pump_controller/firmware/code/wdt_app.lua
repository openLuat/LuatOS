--[[
@module  wdt_app
@summary 硬件看门狗（Air153C，喂狗 GPIO24）
@version 1.0.0
@date    2026.09.11
@author  嵌入式软件设计开发代理
@usage
依据 requirement.md 5.8 与嵌入式软件总体设计.md 4.14：
使用 exair153x_wdt 扩展库驱动板载 Air153C 硬件看门狗（喂狗信号 GPIO24），
init() 内部会启动自动喂狗任务，按 wdt_feed_period 周期喂狗。
参考 demo module/Air780EPM/demo/wdt/air153x_wdt.lua。
本模块无对外接口，直接 require "wdt_app" 即加载运行。
]]

local exair153x_wdt = require("exair153x_wdt")
local config_app    = require("config_app")

-- 初始化并保持硬件看门狗喂狗任务存活
local function wdt_task()
    local ok = exair153x_wdt.init({
        wdt_pin            = config_app.pin_wdt,
        auto_feed_period_s = config_app.wdt_feed_period,
    })
    if not ok then
        log.error("wdt_app", "硬件看门狗初始化失败")
        return
    end
    log.info("wdt_app", "Air153C 硬件看门狗已启动", "pin", config_app.pin_wdt,
        "period", config_app.wdt_feed_period)

    -- init 内部已启动自动喂狗任务，本任务仅保持常驻
    while true do
        sys.wait(3600000)
    end
end

sys.taskInit(wdt_task)
