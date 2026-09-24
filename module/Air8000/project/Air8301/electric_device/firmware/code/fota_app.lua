--[[
@module  fota_app
@summary FOTA 远程升级模块（基于 libfota3 v2.0）
@version 1.2
@date    2026.09.18
@author  嵌入式软件设计开发代理
@usage
根据 requirement.md F-008 与用户确认的 FOTA 方案实现：
- 库：libfota3（合宙内部库 v2.0，官方标注"仅限合宙内部技术人员使用"，用户有特殊获取渠道）
- 触发逻辑（用户确认 1+2）：
  1. 每次开机，等待网络就绪之后，立即触发一次检测（无条件触发，不看上次检测时间戳）
  2. 每 12 小时触发一次检测（保留定时机制）

设计说明（v1.2 修订，解决 v1.1 开机检测未触发问题）：
- v1.1 使用 request({auto=false}) + sys.waitUntil("IP_READY") 等待网络，
  实测 sys.waitUntil("IP_READY") 在当前平台返回的是消息数据（IP 地址字符串）而非 "IP_READY" 消息名，
  导致判断条件 ret ~= "IP_READY" 恒真，开机检测被误判为超时跳过（check_update 从未被调用）。
- v1.2 改为：
  * 不再调用 request()：其内部 wait_time_sync() 会等待网络 + NTP 时间同步，
    期间 running 标志被占用（最长 60s+30s），会导致 check_update() 被互斥跳过；
  * 改用 libfota3.config() 设置配置（project_key/on_status/on_confirm 等，
    config 内部将参数合并到 opts，不占用 running）；
  * 开机检测：直接调用 libfota3.check_update()——其内部 do_check_flow() 自带
    wait_network()（60s 超时，网络未就绪时每秒回调 on_status("network_fail")，
    就绪后自动继续 http_check），天然满足"每次开机等待网络就绪后触发一次"；
  * 12 小时定时：sys.timerLoopStart 周期调用 libfota3.check_update()。
- on_status 中 network_fail 为 wait_network 等待网络期间的周期性回调（每 1 秒一次），
  仅记录日志，不发布 FOTA_STATUS，避免 home_win 界面频繁刷新。

⚠️ 依赖：libfota3.lua 库文件（v2.0）由 LuatOS 扩展库提供（script/libs/libfota3.lua）。

发布消息：
- "FOTA_STATUS"            -- FOTA 状态变化 {state, msg, percent}（供 home_win 可选显示）
]]

local libfota3 = require "libfota3"
local aircloud_app = require "aircloud_app"

-- 自动检测间隔：12 小时（秒）（requirement.md 5.4：每 12 小时触发）
local AUTO_INTERVAL = 12 * 3600

--[[
libfota3 状态回调：统一 INFO 级别日志并发布状态

@local
@function on_status
@param status string 状态（checking/check_fail/no_new_version/new_version/downloading/...）
@param msg string 消息
@param percent number 下载进度（可选）
@return nil
]]
local function on_status(status, msg, percent)
    -- network_fail 是 libfota3 wait_network() 等待网络期间的周期性回调（每 1 秒一次），
    -- 仅记录日志，不发布 FOTA_STATUS，避免 home_win 频繁刷新
    if status == "network_fail" then
        log.info("fota_app", "[network_fail] 网络未就绪，等待网络连接中...")
        return
    end
    if percent then
        log.info("fota_app", "[" .. status .. "] " .. tostring(msg) .. " " .. percent .. "%")
    else
        log.info("fota_app", "[" .. status .. "] " .. tostring(msg))
    end
    -- 发布 FOTA 状态（供 home_win 可选显示）
    sys.publish("FOTA_STATUS", status, msg, percent)
    -- 运维日志（协议 9：FOTA 升级为关键业务，仅状态变化时记录一次，network_fail 周期回调不记录）
    aircloud_app.mtn_log("fota", "FOTA 状态: " .. tostring(status) .. ", " .. tostring(msg)
        .. (percent and (" " .. percent .. "%") or ""))
end

--[[
libfota3 确认回调：自动确认下载和重启（无人工干预场景）

@local
@function on_confirm
@param action string 动作（"download" 确认下载 / "reboot" 确认重启升级）
@param info any 附加信息
@param callback function 确认回调（传 true 表示确认）
@return nil
]]
local function on_confirm(action, info, callback)
    log.info("fota_app", "自动确认: action=" .. tostring(action))
    callback(true)
end

--[[
12 小时定时检测：周期调用 check_update()，保留定时触发机制

@local
@function start_auto_timer
@return nil
]]
local function start_auto_timer()
    sys.timerLoopStart(function()
        log.info("fota_app", "定时触发 FOTA 检测（间隔 " .. (AUTO_INTERVAL / 3600) .. " 小时）")
        libfota3.check_update()
    end, AUTO_INTERVAL * 1000)
    log.info("fota_app", "12 小时定时检测已启动")
end

--[[
FOTA 模块初始化

@local
@function fota_init
@return boolean 初始化结果
]]
local function fota_init()
    -- 1. 检查 PROJECT_KEY（main.lua 中配置，仅用于 FOTA，与 AirCloud 无关）
    local project_key = _G.PROJECT_KEY
    if not project_key or project_key == "" then
        log.info("fota_app", "PROJECT_KEY 未配置，FOTA 功能不可用")
        return true
    end

    -- 2. 配置 libfota3（config() 合并到 opts，替代 request() 以避免时间同步流程占用 running 互斥标志）
    libfota3.config({
        project_key = project_key,
        interval = AUTO_INTERVAL,
        on_status = on_status,
        on_confirm = on_confirm
    })

    -- 3. 开机立即检测
    --    check_update() 内部 do_check_flow() 自带 wait_network()（60s 超时），
    --    会先等待网络就绪再执行 http_check，天然满足"每次开机等待网络就绪后触发一次"
    sys.taskInit(function()
        log.info("fota_app", "触发开机 FOTA 检测（等待网络就绪后执行）")
        libfota3.check_update()
    end)

    -- 4. 12 小时定时检测（保留定时触发机制）
    start_auto_timer()

    log.info("fota_app", "FOTA 模块已启动（libfota3 v2.0, 触发: 开机立即 + 每12小时）")
    return true
end

-- 启动 FOTA 初始化
fota_init()
