--[[
@module  watchdog_app
@summary 外部看门狗管理
@version 2.0
@date    2026.08.04
@author  江访
@usage
GPIO27，使用 air153C_wtd 扩展库控制 Air153C 外部看门狗芯片。
- 初始化看门狗：240秒超时，180秒喂狗循环
- 发布 WATCHDOG_STATUS(enabled, timeout_sec)
- 发布 WATCHDOG_LAST_FEED(timestamp)
- 订阅 WATCHDOG_FEED_REQUEST（手动喂狗）
- 订阅 WATCHDOG_ENABLE_REQUEST(enabled)（启停）

修复说明 (2026.08.04):
air153C_wtd.feed_dog / close_watch_dog 都是"拉高 N ms 再拉低"的异步脉冲，
内部共用同一个 sys.timerStart 回调。若禁用时上一个喂狗脉冲尚未完成，
残留的 400ms 回调会提前把引脚拉低，使 700ms 关闭脉冲被截断成 400ms 喂狗脉冲，
导致看门狗并未真正关闭、仍会按时复位。
本版本引入 op_busy 互斥锁 + 脉冲完成等待，串行执行 feed/close 操作，
确保关闭脉冲(700ms)完整发出后再释放引脚。
]]

local air153C_wtd = require "air153C_wtd"

local WATCHDOG_PIN = 27
local FEED_INTERVAL_MS = 180000  -- 3分钟喂一次(180s)，Air153C 超时240秒(4分钟)
local WATCHDOG_TIMEOUT_SEC = 240 -- Air153C 固定240秒

-- 脉冲时序: feed 约400ms, close 约700ms, 各留余量等待完成
local FEED_PULSE_MS = 500
local CLOSE_PULSE_MS = 800

-- 等待互斥锁超时 (最长 2s), 避免永久阻塞
local MUTEX_WAIT_TIMEOUT_MS = 2000

local watchdog_enabled = true
local last_feed_time = 0
local op_busy = false  -- 看门狗操作互斥锁, 防止 feed/close 脉冲重叠

--[[
等待看门狗操作互斥锁释放（需在协程中调用）

@local
@function wait_mutex
@return boolean 是否成功拿到锁
]]
local function wait_mutex()
    local wait_cnt = 0
    while op_busy do
        sys.wait(20)
        wait_cnt = wait_cnt + 1
        if wait_cnt * 20 >= MUTEX_WAIT_TIMEOUT_MS then
            log.warn("watchdog_app", "wait mutex timeout")
            return false
        end
    end
    op_busy = true
    return true
end

--[[
执行一次喂狗操作（需在协程中调用，内含 sys.wait）

@local
@function do_feed_watchdog
]]
local function do_feed_watchdog()
    if not watchdog_enabled then
        return
    end
    if not wait_mutex() then
        return
    end
    -- 拿到锁后二次确认(等待期间可能已被禁用)
    if not watchdog_enabled then
        op_busy = false
        return
    end
    air153C_wtd.feed_dog(WATCHDOG_PIN)
    last_feed_time = mcu.ticks()
    sys.publish("WATCHDOG_LAST_FEED", last_feed_time)
    sys.wait(FEED_PULSE_MS)  -- 等待脉冲完成, 避免与后续操作冲突
    op_busy = false
    sys.publish("WATCHDOG_STATUS", watchdog_enabled, WATCHDOG_TIMEOUT_SEC)
end

--[[
定期喂狗任务

@local
@function feed_task
]]
local function feed_task()
    sys.wait(1000)
    -- 开机后第一次喂狗
    do_feed_watchdog()
    log.info("watchdog_app", "first feed done")

    while true do
        sys.wait(FEED_INTERVAL_MS)
        do_feed_watchdog()
    end
end

--[[
启用看门狗操作任务（协程，可等待脉冲完成）

@local
@function enable_watchdog_task
]]
local function enable_watchdog_task()
    if not wait_mutex() then
        return
    end
    -- 确保引脚已回到低电平(残留 feed 回调已执行完), 再重新初始化
    sys.wait(500)
    air153C_wtd.init(WATCHDOG_PIN)
    air153C_wtd.feed_dog(WATCHDOG_PIN)
    sys.wait(FEED_PULSE_MS)
    op_busy = false
    log.info("watchdog_app", "enabled")
    sys.publish("WATCHDOG_STATUS", watchdog_enabled, WATCHDOG_TIMEOUT_SEC)
end

--[[
禁用看门狗操作任务（协程，可等待脉冲完成）

@local
@function disable_watchdog_task
]]
local function disable_watchdog_task()
    if not wait_mutex() then
        return
    end
    -- 确保引脚已回到低电平(残留 feed 回调已执行完), 再发 700ms 关闭脉冲
    sys.wait(500)
    air153C_wtd.close_watch_dog(WATCHDOG_PIN)
    -- 等待 700ms 关闭脉冲完整发出, 期间不进行任何 GPIO 操作
    sys.wait(CLOSE_PULSE_MS)
    op_busy = false
    log.info("watchdog_app", "disabled")
    sys.publish("WATCHDOG_STATUS", watchdog_enabled, WATCHDOG_TIMEOUT_SEC)
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
    sys.taskInit(do_feed_watchdog)
    log.info("watchdog_app", "manual feed")
end

--[[
WATCHDOG_ENABLE_REQUEST 回调

@local
@function on_enable_request
@param enabled boolean 是否启用
]]
local function on_enable_request(enabled)
    if enabled and not watchdog_enabled then
        watchdog_enabled = true
        sys.taskInit(enable_watchdog_task)
    elseif not enabled and watchdog_enabled then
        watchdog_enabled = false
        sys.taskInit(disable_watchdog_task)
    else
        sys.publish("WATCHDOG_STATUS", watchdog_enabled, WATCHDOG_TIMEOUT_SEC)
    end
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
初始化看门狗

@local
@function init_watchdog
]]
local function init_watchdog()
    air153C_wtd.init(WATCHDOG_PIN)
    watchdog_enabled = true
    log.info("watchdog_app", "init done, pin:", WATCHDOG_PIN)
end

init_watchdog()

sys.subscribe("WATCHDOG_FEED_REQUEST", on_feed_request)
sys.subscribe("WATCHDOG_ENABLE_REQUEST", on_enable_request)
sys.subscribe("WATCHDOG_GET_STATUS_REQUEST", on_get_status_request)

sys.taskInit(feed_task)
