--[[
@module  watchdog_app
@summary 外部看门狗管理（Air153D + exair153x_wdt，factory_new 出厂固件）
@version 1.0
@date    2026.10.27
@author  江访
@usage
喂狗脚取自 config.hw.wdt.pin（8603 / 8605 系列为 GPIO57），使用 exair153x_wdt 扩展库
控制 Air153D 外部看门狗芯片。exair153x_wdt 内部管理 GPIO 脉冲、自动喂狗任务和
防误触发机制，本模块仅负责读配置、初始化和消息桥接。
app_main 按 features.wdt 开关加载，不开该开关的型号不加载本模块。

消息协议：
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

local wdt_ok, exair153x_wdt = pcall(require, "exair153x_wdt")

local wdt_cfg = (_G.project_config and _G.project_config.hw and _G.project_config.hw.wdt) or {}
local WATCHDOG_PIN = wdt_cfg.pin
local WATCHDOG_TIMEOUT_SEC = wdt_cfg.timeout_sec or 240 -- Air153D 默认240秒，实际由 STRAP 引脚决定

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
        sys.publish("WATCHDOG_LAST_FEED", os.time())
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
    if not wdt_ok then
        log.error("watchdog_app", "exair153x_wdt not packed in firmware, watchdog NOT fed")
        return
    end
    if type(WATCHDOG_PIN) ~= "number" then
        log.error("watchdog_app", "config.hw.wdt.pin missing, watchdog NOT fed")
        return
    end
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
