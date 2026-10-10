--[[
@module  watchdog_app
@summary 外部看门狗管理（Air153D + exair153x_wdt）
@version 3.0
@date    2026.09.01
@author  江访
@usage
GPIO27，使用 exair153x_wdt 扩展库控制 Air153D 外部看门狗芯片。
exair153x_wdt 内部管理 GPIO 脉冲、自动喂狗任务和防误触发机制，
本模块仅负责消息桥接和应用级启停状态。

消息协议（与旧版完全兼容）：
- 发布 WATCHDOG_STATUS(enabled, timeout_sec)
- 发布 WATCHDOG_LAST_FEED(timestamp)
- 订阅 WATCHDOG_FEED_REQUEST（手动喂狗）
- 订阅 WATCHDOG_ENABLE_REQUEST(enabled)（启停）
- 订阅 WATCHDOG_GET_STATUS_REQUEST（状态查询）

启停说明：
exair153x_wdt 内部自动喂狗任务持续运行，无法外部停止。
"禁用"操作仅在应用层拦截手动喂狗请求，不影响底层自动喂狗。
Air153D 超时档位由硬件 STRAP 引脚配置，软件层不参与。
]]

local exair153x_wdt = require "exair153x_wdt"

local WATCHDOG_PIN = 27
local WATCHDOG_TIMEOUT_SEC = 240 -- Air153D 默认240秒，实际由 STRAP 引脚决定

local watchdog_enabled = true

--[[
手动喂狗回调（由 exair153x_wdt.feed() 触发后发布状态）

@local
@function do_feed
]]
local function do_feed()
    if not watchdog_enabled then
        return
    end
    if exair153x_wdt.feed() then
        sys.publish("WATCHDOG_STATUS", watchdog_enabled, WATCHDOG_TIMEOUT_SEC)
    end
end

--[[
WATCHDOG_FEED_REQUEST 回调（手动喂狗）

@local
@function on_feed_request
]]
local function on_feed_request()
    if not watchdog_enabled then
        log.warn("watchdog_app", "watchdog disabled, ignore feed request")
        return
    end
    sys.taskInit(do_feed)
    log.info("watchdog_app", "manual feed")
end

--[[
WATCHDOG_ENABLE_REQUEST 回调

@local
@function on_enable_request
@param enabled boolean 是否启用
]]
local function on_enable_request(enabled)
    if enabled ~= watchdog_enabled then
        watchdog_enabled = enabled
        log.info("watchdog_app", enabled and "enabled" or "disabled")
    end
    sys.publish("WATCHDOG_STATUS", watchdog_enabled, WATCHDOG_TIMEOUT_SEC)
end

--[[
WATCHDOG_GET_STATUS_REQUEST 回调

@local
@function on_get_status_request
]]
local function on_get_status_request()
    sys.publish("WATCHDOG_STATUS", watchdog_enabled, WATCHDOG_TIMEOUT_SEC)
end

--[[
初始化看门狗，启动 exair153x_wdt 自动喂狗任务

@local
@function init_watchdog
]]
local function init_watchdog()
    exair153x_wdt.init({ wdt_pin = WATCHDOG_PIN })
    watchdog_enabled = true
    log.info("watchdog_app", "init done, pin:", WATCHDOG_PIN)
end

init_watchdog()

-- 首次手动喂狗，触发 WATCHDOG_STATUS 消息供 UI 初始显示
sys.taskInit(do_feed)

sys.subscribe("WATCHDOG_FEED_REQUEST", on_feed_request)
sys.subscribe("WATCHDOG_ENABLE_REQUEST", on_enable_request)
sys.subscribe("WATCHDOG_GET_STATUS_REQUEST", on_get_status_request)
