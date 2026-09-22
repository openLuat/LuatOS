--[[
@module  ntp_app
@summary NTP 时间同步模块（系统服务层）
@version 1.0
@date    2026.09.18
@author  嵌入式软件设计开发代理
@usage
根据用户新增需求实现 NTP 时间同步功能（系统级时间校准，确保模组本地时间准确）：
- 参考 Air8000/demo/ntp/ntp_test.lua 官方 demo 实现
- 等待网络就绪 → socket.sntp(服务器列表) 发起时间同步 → 等待 NTP_UPDATE 事件（5 秒超时）
- 同步成功：设置东八区时区 rtc.timezone(32)、发布 NTP_SYNCED 消息、记录运维日志、12 小时周期同步
- 同步失败：发布 NTP_SYNC_FAILED 消息、记录运维日志、10 秒后重试

发布消息：
- "NTP_SYNCED"       -- NTP 时间同步成功（供其他模块感知时间状态，当前无订阅者，预留扩展）
- "NTP_SYNC_FAILED"  -- NTP 时间同步失败（供其他模块感知时间状态，当前无订阅者，预留扩展）

订阅消息：
- "NTP_ERROR"        -- 内核消息（socket.sntp 失败时自动发布，仅记录日志）
]]

local aircloud_app = require "aircloud_app"

-- NTP 服务器列表（最多 3 个，按顺序请求：连接时从第一个服务器试起，失败或超时就换下一个）
local NTP_SERVERS = {
    "ntp.aliyun.com",          -- 阿里云公共 NTP 服务器
    "ntp.ntsc.ac.cn",          -- 中国科学院国家授时中心
    "time1.cloud.tencent.com"  -- 腾讯云公共 NTP 服务器
}

-- 同步周期：12 小时（毫秒）（与 FOTA 检测周期对齐，工业设备时间漂移小，避免过频网络访问）
local SYNC_INTERVAL = 12 * 3600 * 1000
-- 失败重试间隔：10 秒（毫秒）（参考官方 demo：失败 10 秒重试）
local RETRY_INTERVAL = 10 * 1000
-- 等待同步结果超时：5 秒（毫秒）（参考官方 demo：等待 NTP_UPDATE 5 秒超时）
local WAIT_TIMEOUT = 5000

--[[
等待网络就绪（循环等待，直到默认网卡获取 IP）

与 aircloud_app.wait_network 同一机制：
- socket.adapter(socket.dft()) 检查默认网卡是否已获取 IP（IP_READY）
- sys.waitUntil("IP_READY", 1000) 等待内核产生的 IP_READY 消息，1 秒超时让出 CPU
说明：不设超时退出。网络可能延迟就绪（如无 SIM 卡时用户手动连接 WiFi），
任务必须持续等待，避免因超时退出导致时间同步永久失败。

@local
@function wait_network
@return nil
]]
local function wait_network()
    while not socket.adapter(socket.dft()) do
        log.info("ntp_app", "等待网络就绪（默认网卡未获取 IP），继续等待...")
        sys.waitUntil("IP_READY", 1000)
    end
end

--[[
NTP 同步失败事件处理（订阅内核 NTP_ERROR 消息）

socket.sntp 全部服务器失败时内核自动发布 NTP_ERROR，此处仅记录日志；
失败后的运维日志与 NTP_SYNC_FAILED 发布统一由 ntp_task 失败分支处理，避免重复记录。

@local
@function on_ntp_error
@return nil
]]
local function on_ntp_error()
    log.warn("ntp_app", "NTP 时间同步失败（收到 NTP_ERROR 事件）")
end

--[[
执行一次时间同步

socket.sntp 成功后系统时间已自动设置为本地时间（东八区），无需手动 rtc.set()；
本函数仅等待同步结果事件并返回是否成功。

@local
@function do_sync
@return boolean 同步是否成功（收到 NTP_UPDATE 为 true，超时/失败为 false）
]]
local function do_sync()
    -- 发起时间同步（自定义服务器列表，按顺序请求）
    socket.sntp(NTP_SERVERS)
    -- 等待同步结果（成功：NTP_UPDATE；失败：超时或 NTP_ERROR）
    local sync_success = sys.waitUntil("NTP_UPDATE", WAIT_TIMEOUT)
    return sync_success ~= nil
end

--[[
NTP 时间同步主任务

流程：
1. 等待网络就绪（与 aircloud_app 同一机制，循环等待不退出）
2. 执行时间同步：
   - 成功：设置东八区时区 rtc.timezone(32)（注意：须先同步时间再设置时区）、
           发布 NTP_SYNCED、记录运维日志、等待 SYNC_INTERVAL（12 小时）后再次同步
   - 失败：发布 NTP_SYNC_FAILED、记录运维日志、等待 RETRY_INTERVAL（10 秒）后重试

@local
@function ntp_task
@return nil
]]
local function ntp_task()
    -- 等待网络就绪（循环等待，不退出）
    wait_network()
    log.info("ntp_app", "网络已就绪，开始 NTP 时间同步")

    while true do
        if do_sync() then
            -- 同步成功：设置东八区时区（32 = 8 小时 × 4 个 1/4 时区；默认即东八区，显式设置确保一致）
            rtc.timezone(32)
            log.info("ntp_app", "NTP 同步成功，本地时间:", os.date("%Y-%m-%d %H:%M:%S"))
            -- 发布同步成功消息（供其他模块感知时间状态，预留扩展）
            sys.publish("NTP_SYNCED")
            -- 记录运维日志（F-009：时间同步为系统关键状态，同步成功记录一次）
            aircloud_app.mtn_log("ntp", "NTP 时间同步成功: " .. os.date("%Y-%m-%d %H:%M:%S"))
            -- 12 小时周期同步（与 FOTA 12 小时检测周期对齐）
            sys.wait(SYNC_INTERVAL)
        else
            -- 同步失败/超时：发布失败消息 + 记录运维日志 + 10 秒后重试
            log.warn("ntp_app", "NTP 同步失败/超时，10 秒后重试")
            sys.publish("NTP_SYNC_FAILED")
            aircloud_app.mtn_log("ntp", "NTP 时间同步失败，10 秒后重试")
            sys.wait(RETRY_INTERVAL)
        end
    end
end

-- 订阅 NTP 同步失败事件（内核消息，socket.sntp 失败时自动发布）
sys.subscribe("NTP_ERROR", on_ntp_error)

-- 启动 NTP 时间同步任务
sys.taskInit(ntp_task)
