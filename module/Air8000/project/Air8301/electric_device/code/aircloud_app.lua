--[[
@module  aircloud_app
@summary AirCloud 云平台连接模块（基于 excloud 扩展库）
@version 1.0
@date    2026.09.18
@author  嵌入式软件设计开发代理
@usage
根据《网络通信协议文档》实现 AirCloud（合宙云）连接管理（Air8301）：
- 4G 为主通道、WiFi 为备用通道，TCP 长连接
- excloud.setup/open/on 管理连接、鉴权、心跳、重连

订阅消息：
- "EXLIB_NETDRV_NETWORK_STATUS"  -- 网络状态（exnetif 库发布，adapter 切换时触发）：检测网络切换（4G↔WiFi、WiFi 热点间、WiFi 未重新 DHCP）触发强制重连
- "IP_READY"                     -- 网络就绪（内核消息，4G/WiFi 网卡获取 IP 后发布）：未连接时触发连接流程

发布消息：
- "AIRCLOUD_CONNECTED"     -- 云连接成功
- "AIRCLOUD_AUTHED"        -- 云鉴权成功
- "AIRCLOUD_DISCONNECTED"  -- 云连接断开/重连失败 {count}
- "AIRCLOUD_RECONNECT"     -- 触发主动重连（内部信号，close+open 重建连接）
- "AIRCLOUD_CONNECT_TRIGGER" -- 触发连接流程（内部信号，IP_READY 网络就绪且未连接时发布）
- "AIRCLOUD_MSG"           -- 收到云端下行消息 {tlvs, header}
- "AIRCLOUD_SEND_RESULT"   -- 数据发送结果 {success, sequence_num}
- "FEED_NETWORK_WATCHDOG"  -- 网络收发成功（喂网络看门狗）

对外接口：
- aircloud_app.send(tlv_list, need_reply)   -- 发送 TLV 数据到云端
- aircloud_app.is_connected()               -- 获取当前连接状态
- aircloud_app.mtn_log(tag, ...)            -- 记录运维日志（协议 9）
- aircloud_app.upload_mtn_logs()            -- 主动上报运维日志（协议 9，自定义 TCP 服务器场景对接合宙）

运维日志主动上报（协议 9 / F-009，仅自定义 TCP 服务器模式启用）：
- 默认 AirCloud 模式（server_mode=1）：云端下发 Type=25 运维日志上传请求，excloud 自动上报，不启用主动上报任务
- 自定义 TCP 服务器场景（server_mode=2，use_getip=false）：云端不会下发 Type=25 运维日志上传请求，
  由本模块新增的 mtn_logs_upload_task 任务主动检测上报（任务内判断 server_mode，非 2 直接退出）：
  - 3.1 每次开机后：网络就绪 + excloud.setup 完成（getip 获取运维日志上报 url）后，如有未上报日志则上报一次
  - 3.2 每隔 10 分钟：如有未上报日志则上报一次
- setup_cfg.mtninfo_from_luat=true（仅 server_mode=2 分支设置）：运维日志上传使用合宙平台参数（上传时自动 getip 获取 url，
  不影响业务连接的 host/port/auth_key），业务仍对接自定义 TCP 服务器
]]

local excloud = require "excloud"

local aircloud_app = {}

--[[
安全转字符串：excloud 事件中的 error/error_msg/message/count 等字段可能是
布尔或 nil（例：socket.tx 失败时 err_msg 可能为 true），直接做字符串拼接会报错。

@param any v 任意值
@return string 字符串表示
]]
local function safe_str(v)
    if type(v) == "string" then
        return v
    end
    return tostring(v)
end

-- 连接状态标志
local connected = false   -- 云连接状态
local authed = false      -- 云鉴权状态
-- 重连互斥标志：普通重连（reconnect_task）、强制重连（force_reconnect_task）与连接流程（do_connect）共用，
-- 避免并发执行 close/open 导致连接状态混乱
local reconnecting = false
-- excloud.setup 完成标志（运维日志主动上传任务依赖：确保 excloud 已初始化、device_id 已生成）
local setup_done = false
-- 发送失败触发重连的防抖（毫秒）+ 上次触发时间戳（避免短时间多次发送失败重复触发重连）
local SEND_FAIL_DEBOUNCE = 3000
local last_send_fail_ticks = 0

--[[
excloud 事件回调：处理所有云平台事件

@local
@function on_excloud_event
@param event string 事件类型，如 "connect_result"/"auth_result"/"message"/"disconnect"/"reconnect_failed"/"send_result"/"mtn_log_upload_*"
@param data table 事件数据
@return nil
]]
local function on_excloud_event(event, data)
    log.info("aircloud_app", "事件回调:", event, json.encode(data))

    if event == "connect_result" then
        -- 连接成功/失败（协议 3.1：TCP 长连接）
        if data.success then
            connected = true
            log.info("aircloud_app", "连接成功")
            sys.publish("FEED_NETWORK_WATCHDOG")
            sys.publish("AIRCLOUD_CONNECTED")
        else
            -- 连接失败（如网络切换期挂起连接超时 / getip 失败）
            connected = false
            authed = false
            log.info("aircloud_app", "连接失败: " .. safe_str(data.error))
            -- 网络可用时触发主动重连；网络不可用时等待网络恢复（IP_READY 触发）
            -- （修复：connect_result 失败后无重连机制，导致连接超时后永久卡死）
            if socket.adapter(socket.dft()) then
                sys.publish("AIRCLOUD_RECONNECT", 0)
            else
                log.info("aircloud_app", "连接失败且网络不可用，等待网络恢复后由 IP_READY 触发重连")
            end
        end
    elseif event == "auth_result" then
        -- 鉴权结果（协议 5：Type=16 鉴权请求，Type=17 鉴权回复）
        if data.success then
            authed = true
            log.info("aircloud_app", "认证成功")
            sys.publish("FEED_NETWORK_WATCHDOG")
            sys.publish("AIRCLOUD_AUTHED")
        else
            authed = false
            log.info("aircloud_app", "认证失败: " .. safe_str(data.message))
        end
    elseif event == "message" then
        -- 收到云端下行消息（协议 8：控制命令 Type=19 等）
        log.info("aircloud_app", "收到消息, 流水号: " .. safe_str(data.header and data.header.sequence_num))
        -- 转发给协议处理模块解析
        sys.publish("AIRCLOUD_MSG", data.tlvs, data.header)
        sys.publish("FEED_NETWORK_WATCHDOG")
    elseif event == "disconnect" then
        -- 与服务器断开连接（协议 3.1：本地重试 3 次，失败重新连接）
        connected = false
        authed = false
        log.warn("aircloud_app", "与服务器断开连接")
        sys.publish("AIRCLOUD_DISCONNECTED", 0)
        -- 网络可用时触发主动重连；网络不可用（WiFi 关闭等）时不重连，
        -- 等待网络恢复后由 IP_READY 订阅触发连接流程
        -- （修复：网络不可用时 excloud.open() 不立即失败而是挂起等待 TCP 连接，
        --   最长约 37 秒后才超时，期间阻塞后续连接，导致 WiFi 恢复后连接不及时）
        if socket.adapter(socket.dft()) then
            sys.publish("AIRCLOUD_RECONNECT", 0)
        else
            log.info("aircloud_app", "网络不可用，等待网络恢复后由 IP_READY 触发重连")
        end
    elseif event == "reconnect_failed" then
        -- 重连失败超限（协议 3.1：3 次失败后触发主动重连）
        connected = false
        authed = false
        log.info("aircloud_app", "重连失败，已尝试 " .. safe_str(data.count) .. " 次")
        sys.publish("AIRCLOUD_DISCONNECTED", data.count)
        -- 网络可用时触发主动重连；网络不可用（WiFi 关闭等）时等待网络恢复
        if socket.adapter(socket.dft()) then
            sys.publish("AIRCLOUD_RECONNECT", 0)
        else
            log.info("aircloud_app", "网络不可用，等待网络恢复后由 IP_READY 触发重连")
        end
    elseif event == "send_result" then
        -- 数据发送结果
        if data.success then
            log.info("aircloud_app", "发送成功，流水号: " .. data.sequence_num)
            -- 发送成功才喂狗（失败不喂狗，让网络看门狗兜底）
            sys.publish("FEED_NETWORK_WATCHDOG")
        else
            local err = data.error_msg
            log.info("aircloud_app", "发送失败: " .. safe_str(err))
            -- 发送失败说明长连接当前不可用：同步离线状态并触发主动重连。
            -- 说明：excloud 的 error_msg 可能为布尔值（socket.tx 返回失败，如 TCP 异常 -13）
            --       或字符串（未连接 / 服务未开启）；实测 socket 异常时 excloud 可能不派发
            --       disconnect 事件，导致连接"假在线"卡死。故此处统一兜底触发重连，
            --       并加防抖，避免短时间多次失败重复触发。
            local now = mcu.ticks()
            if now - last_send_fail_ticks >= SEND_FAIL_DEBOUNCE then
                last_send_fail_ticks = now
                connected = false
                authed = false
                sys.publish("AIRCLOUD_DISCONNECTED", 0)
                -- 网络可用时触发主动重连；网络不可用（WiFi 关闭等）时等待网络恢复
                if socket.adapter(socket.dft()) then
                    sys.publish("AIRCLOUD_RECONNECT", 0)
                else
                    log.info("aircloud_app", "网络不可用，等待网络恢复后由 IP_READY 触发重连")
                end
            else
                log.info("aircloud_app", "发送失败防抖中，跳过本次重连触发")
            end
        end
        sys.publish("AIRCLOUD_SEND_RESULT", data.success, data.sequence_num)
    elseif event == "mtn_log_upload_start" then
        -- 运维日志上传开始（协议 9）
        log.info("aircloud_app", "运维日志上传开始", "文件数量:", data.file_count)
    elseif event == "mtn_log_upload_progress" then
        -- 运维日志上传进度
        log.info("aircloud_app", "运维日志上传进度",
            "当前文件:", data.current_file,
            "总数:", data.total_files,
            "文件名:", data.file_name,
            "状态:", data.status)
    elseif event == "mtn_log_upload_complete" then
        -- 运维日志上传完成
        log.info("aircloud_app", "运维日志上传完成",
            "成功:", data.success_count,
            "失败:", data.failed_count,
            "总计:", data.total_files)
    end
end

--[[
等待网络就绪（循环等待，直到默认网卡获取 IP）

参考官方 demo（photo_to_aircloud.lua excloud_task_func）：
- socket.adapter(socket.dft()) 检查默认网卡是否已获取 IP（IP_READY）
- sys.waitUntil("IP_READY", 1000) 等待内核产生的 IP_READY 消息，1 秒超时让出 CPU

说明：不设超时退出。网络可能延迟就绪（如无 SIM 卡时用户手动连接 WiFi），
任务必须持续等待，避免因超时退出导致云连接永久失败。

@local
@function wait_network
@return nil
]]
local function wait_network()
    while not socket.adapter(socket.dft()) do
        log.info("aircloud_app", "等待网络就绪（默认网卡未获取 IP），继续等待...")
        sys.waitUntil("IP_READY", 1000)
    end
end

--[[
执行 AirCloud 连接流程：读取配置 → setup → 注册回调 → open
可重复调用（首次连接 / open 失败后网络就绪时重新执行）

@local
@function do_connect
@return nil
]]
local function do_connect()
    -- 互斥保护：连接流程与重连（普通/强制）共用 reconnecting 标志，避免并发 close/open
    if reconnecting then
        log.info("aircloud_app", "重连/连接进行中，跳过本次连接流程")
        return
    end
    reconnecting = true

    -- 读取服务器配置（server_win 设置，fskv 持久化，掉电生效）
    local server_mode = fskv.get("server_mode") or 1
    local server_addr = fskv.get("server_addr") or ""
    local server_port = fskv.get("server_port") or ""
    -- 构造 excloud setup 配置（协议 3.1/4/5：TCP 长连接）
    local setup_cfg = {
        transport = "tcp",                   -- 使用 TCP 传输
        -- 关闭 excloud 内部自动重连：由本模块统一管理重连（网络可用性检查 + IP_READY 触发）
        -- 修复：excloud 内部重连不检查网络可用性，WiFi 关闭时仍会发起 TCP 连接并挂起
        --       （timeout=30 连接超时，最长约 40 秒），阻塞 WiFi 恢复后的快速连接
        auto_reconnect = false,              -- 关闭内部自动重连（由 aircloud_app 管理）
        reconnect_interval = 10,             -- 重连间隔（秒）
        max_reconnect = 3,                   -- 最大重连次数（协议 3.1：本地重试 3 次，失败重新连接）
        mtn_log_enabled = true,              -- 启用 AirCloud 运维日志（协议 9：关键业务日志本地循环存储，云端可远程拉取）
        mtn_log_blocks = 4,                  -- 运维日志每个文件块数（1 block ≈ 4KB，4 个文件共 16 block ≈ 64KB）
        mtn_log_write_way = excloud.MTN_LOG_ADD_WRITE,  -- 运维日志写入方式：追加写入（立即持久化，重要日志场景）
        debug = true,                          -- 开启 excloud HEX 收发日志（官方版默认关闭，便于协议抓包比对）
    }
    if server_mode == 2 and server_addr ~= "" and server_port ~= "" then
        -- 自定义 TCP 服务器（服务器设置页面配置）：use_getip=false，直连自定义地址/端口
        setup_cfg.use_getip = false
        setup_cfg.host = server_addr
        setup_cfg.port = tonumber(server_port)
        setup_cfg.auth_key = "qk0R0vWWv0u9DCemATePdwBe96DvPUef"
        -- 运维日志上传使用合宙平台参数（仅自定义 TCP 服务器场景需要）：
        -- 上传时自动调用 getip 获取运维日志上报 url，不修改业务连接的 host/port/auth_key 等字段，
        -- 实现"业务走自定义 TCP、运维日志走合宙 AirCloud"；默认 AirCloud 模式不设置（云端下发 Type=25 信令触发上报）
        setup_cfg.mtninfo_from_luat = true
        log.info("aircloud_app", "使用自定义 TCP 服务器:", server_addr .. ":" .. server_port)
    else
        -- 默认 AirCloud 服务器：use_getip=true（getip 动态获取），无需配置 host/port/auth_key
        setup_cfg.use_getip = true
        log.info("aircloud_app", "使用默认 AirCloud 服务器（getip 动态获取）")
    end
    local ok, err_msg = excloud.setup(setup_cfg)
    if not ok then
        if err_msg and string.find(err_msg, "already open") then
            -- excloud 已被内部"网络已恢复"机制打开（可能走未就绪网卡挂起，如 4G 抢占期）
            -- 主动关闭清理后重新连接（确保走当前就绪的默认网卡）
            -- （修复：原逻辑仅等待 excloud 连接结果，但若其连接走错误网卡挂起，
            --   需等约 30 秒超时才恢复，导致 WiFi 恢复后连接不及时甚至永久卡死）
            log.warn("aircloud_app", "excloud 已处于打开状态（可能是残留连接），主动关闭后重新连接")
            pcall(excloud.close)
            sys.wait(2000)
            ok, err_msg = excloud.setup(setup_cfg)
            if not ok then
                log.error("aircloud_app", "excloud.setup 重试失败:", err_msg)
                reconnecting = false
                return
            end
        else
            log.error("aircloud_app", "excloud.setup 失败:", err_msg)
            reconnecting = false
            return
        end
    end

    -- 标记 excloud.setup 完成（供运维日志主动上传任务判断 excloud 已初始化、device_id 已生成）
    setup_done = true

    -- 注册事件回调（重复注册覆盖旧回调，幂等）
    excloud.on(on_excloud_event)

    -- 开启服务（连接 + 鉴权）
    ok, err_msg = excloud.open()
    if not ok then
        log.error("aircloud_app", "excloud.open 失败:", err_msg)
        -- open 失败（典型：网络未就绪导致 getip 请求失败）：
        -- 不结束任务，由 IP_READY / 网络切换事件在网络就绪后触发 do_connect 重新连接
        reconnecting = false
        return
    end
    reconnecting = false
    log.info("aircloud_app", "AirCloud 连接已开启")

    -- 心跳机制（协议 6.1：每 5 分钟至少一个数据包）
    -- 本项目 1 分钟周期上报天然满足心跳要求，无需额外心跳包；
    -- 若需兜底可取消以下注释
    -- excloud.start_heartbeat()
end

--[[
AirCloud 连接主任务：等待网络就绪 → 连接流程 → 保持存活等待触发信号
网络未就绪时循环等待（不退出任务）；open 失败后任务保持存活，
由 IP_READY 订阅 / 网络切换事件在网络就绪后触发 do_connect 重新连接

@local
@function aircloud_task
@return nil
]]
local function aircloud_task()
    -- 等待网络就绪（循环等待，不退出：4G/WiFi 任一网卡获取 IP 后继续）
    wait_network()
    log.info("aircloud_app", "网络已就绪，开始连接 AirCloud")
    -- 执行连接流程（setup + on + open）
    do_connect()

    -- 连接后任务保持存活：等待连接触发信号（AIRCLOUD_CONNECT_TRIGGER）
    -- 触发源：IP_READY 订阅（网络就绪且未连接时发布）、网络切换事件（EXLIB_NETDRV_NETWORK_STATUS）
    while true do
        sys.waitUntil("AIRCLOUD_CONNECT_TRIGGER")
        if not connected then
            -- 确保默认网卡就绪（IP_READY 只是任一网卡就绪；默认网卡可能尚在切换，如 4G→WiFi）
            -- 否则 open 会走未就绪的默认网卡导致 TCP 连接挂起超时（timeout=30s）
            if not socket.adapter(socket.dft()) then
                log.info("aircloud_app", "触发连接但默认网卡未就绪，等待默认网卡就绪")
                wait_network()
            end
            log.info("aircloud_app", "收到连接触发信号，重新连接 AirCloud")
            do_connect()
            -- 连接未建立（do_connect 失败或 excloud 连接中）：延迟自动重试
            -- （修复：connect_result 失败后 AIRCLOUD_CONNECT_TRIGGER 不再发布，
            --   若无重试机制将永久卡死；30 秒退避避免网络未完全就绪时高频无效重试）
            if not connected then
                log.warn("aircloud_app", "连接未建立，30 秒后自动重试")
                sys.wait(30000)
            end
        else
            log.info("aircloud_app", "已连接，跳过触发连接")
        end
    end
end

--[[
运维日志主动上传任务（自定义 TCP 服务器场景对接合宙 AirCloud 运维日志）

需求背景（F-009 / 协议 9）：AirCloud 基本业务对接客户自定义 TCP 服务器时
（use_getip=false），云端不会下发 Type=25 运维日志上传请求，需设备主动检测上报。
本任务通过 excloud.upload_mtnlogs() 主动上传本地运维日志循环文件（/hzmtn1~4.trc），
上传目标为合宙 AirCloud 平台：setup_cfg.mtninfo_from_luat=true 时，上传过程自动调用
getip 获取运维日志上报 url，不影响业务连接的 host/port/auth_key。

上报时机（两种场景）：
- 3.1 每次开机后：等待网络就绪 + excloud.setup 完成（getip 获取到运维日志上报 url）后，
      若存在未上报的运维日志则上报一次
- 3.2 每隔 10 分钟：若存在未上报的运维日志则上报一次

说明：返回 false,"no mtn log files" 视为正常跳过（无未上报日志）；
      返回 false,"mtn log uploading" 视为上传中（excloud 内部互斥，自动跳过）；
      其余错误记日志后等待下一周期。

@local
@function mtn_logs_upload_task
@return nil
]]
local MTN_LOG_UPLOAD_INTERVAL = 600000 -- 运维日志主动上报周期（毫秒）：10 分钟

local function mtn_logs_upload_task()
    -- 仅自定义 TCP 服务器模式（server_mode=2）需要主动上报运维日志：
    -- 默认 AirCloud 模式（server_mode=1）下云端会下发 Type=25 运维日志上传请求，由 excloud 自动上报，
    -- 无需本任务主动上报；非自定义 TCP 模式直接退出任务
    local server_mode = fskv.get("server_mode") or 1
    if server_mode ~= 2 then
        log.info("aircloud_app", "默认 AirCloud 模式，运维日志由云端 Type=25 信令触发上报，跳过主动上报任务")
        return
    end
    -- 等待网络就绪（与 aircloud_task 同一机制：循环等待默认网卡获取 IP）
    wait_network()
    -- 等待 excloud.setup 完成（确保 excloud 已初始化、device_id 已生成、上传 url 可经 getip 获取）
    while not setup_done do
        sys.wait(1000)
    end
    log.info("aircloud_app", "运维日志主动上报任务启动（场景3.1：开机首次上报）")
    while true do
        -- 主动上报运维日志：无未上报日志（false,"no mtn log files"）视为正常跳过
        local ok, err_msg = excloud.upload_mtnlogs()
        if ok then
            log.info("aircloud_app", "运维日志主动上报完成")
        elseif err_msg == "no mtn log files" then
            log.info("aircloud_app", "无未上报运维日志，跳过本次上报")
        elseif err_msg == "mtn log uploading" then
            log.info("aircloud_app", "运维日志上传进行中，跳过本次上报")
        else
            log.warn("aircloud_app", "运维日志主动上报失败:", err_msg)
        end
        -- 场景 3.2：每 10 分钟检测上报一次
        sys.wait(MTN_LOG_UPLOAD_INTERVAL)
    end
end

-- 断线重连配置
local RECONNECT_DELAY = 5000      -- 重连延迟（毫秒）
local RECONNECT_CLOSE_WAIT = 2000 -- close 后等待（毫秒）

--[[
执行重连：关闭旧连接并重新开启（close + open 重建连接）

@local
@function do_reconnect
@return nil
]]
local function do_reconnect()
    log.warn("aircloud_app", "执行重连（close + open 重建连接）")
    connected = false
    authed = false
    -- 关闭旧连接（可能已断开，忽略错误）
    pcall(excloud.close)
    sys.wait(RECONNECT_CLOSE_WAIT)
    -- 重新开启服务（内部会重新连接 + 鉴权）
    local ok, err_msg = excloud.open()
    if not ok then
        log.error("aircloud_app", "重连失败:", err_msg)
    end
end

--[[
安全重连：互斥保护，避免普通重连与强制重连并发执行

@local
@function safe_do_reconnect
@return nil
]]
local function safe_do_reconnect()
    if reconnecting then
        log.info("aircloud_app", "重连进行中，跳过本次重连")
        return
    end
    -- 网络可用时才重连；网络不可用（WiFi 关闭等）时跳过，
    -- 等待网络恢复后由 IP_READY 订阅触发连接流程
    -- （兜底保护：所有重连路径均经此检查，避免网络不可用时 open 挂起创建幽灵连接）
    if not socket.adapter(socket.dft()) then
        log.info("aircloud_app", "网络不可用，跳过重连（等待网络恢复后由 IP_READY 触发连接）")
        return
    end
    reconnecting = true
    do_reconnect()
    reconnecting = false
end

local function reconnect_task()
    while true do
        sys.waitUntil("AIRCLOUD_RECONNECT")
        log.warn("aircloud_app", "收到重连信号，延迟 " .. (RECONNECT_DELAY / 1000) .. " 秒后重连")
        sys.wait(RECONNECT_DELAY)
        -- 仅未连接时执行重连（避免重复重连）
        if not connected then
            safe_do_reconnect()
        else
            log.info("aircloud_app", "已恢复连接，跳过重连")
        end
    end
end

--[[
网络切换强制重连任务：绕过 connected 检查，无条件重建连接
（网络切换后旧 TCP 连接必然失效，即使 connected 仍为 true 也必须重建）

@local
@function force_reconnect_task
@return nil
]]
local function force_reconnect_task()
    log.warn("aircloud_app", "网络切换强制重连，延迟 " .. (RECONNECT_DELAY / 1000) .. " 秒后重连")
    sys.wait(RECONNECT_DELAY)
    safe_do_reconnect()
end

sys.taskInit(reconnect_task)

-- 网络切换检测（协议 3.1：网络切换后 TCP 长连接失效，需主动重连）
-- 检测源：exnetif 库发布的消息 EXLIB_NETDRV_NETWORK_STATUS（adapter 切换时发布）
-- 覆盖场景：4G↔WiFi 切换、WiFi 热点间切换、WiFi CONNECTED 但未重新 DHCP（不发布 IP_READY）等全部网络切换
local last_net_key = nil              -- 上次网络标识（nil=尚未收到过网络状态事件；首次事件不触发重连）
local last_net_switch_ticks = 0       -- 上次触发网络重连的时间（防抖）
local NET_SWITCH_DEBOUNCE = 5000      -- 网络切换重连防抖（毫秒）：避免一次切换多次事件重复触发

-- 参数：net_type（"WiFi"/"4G"/"Ethernet"，所有网卡断开时为 nil），adapter（网卡 id，无网络时为 -1）
sys.subscribe("EXLIB_NETDRV_NETWORK_STATUS", function(net_type, adapter)
    -- 计算当前网络标识：网卡类型小写（wifi / 4g / ethernet），无网络为 none
    local key
    if type(net_type) == "string" then
        key = net_type:lower()
    else
        key = "none"
    end
    -- 仅"真正的网卡切换"才触发强制重连（last_net_key 非 nil 且与 key 不同，且新网络有效）
    -- 覆盖：4G↔WiFi、WiFi→4G 等网卡切换（旧 TCP 基于旧网卡，需重建）
    -- 首次事件（last_net_key=nil）不触发强制重连：不存在"切换"，连接由 IP_READY / wait_network 流程建立；
    --   若连接已建立（如 exnetif 的 WiFi CONNECTED 确认事件晚于 IP_READY 约 10 秒到达），
    --   说明连接已建立在该网络上，无需重建（修复"连接刚建立又被强制断开重建"问题）
    if last_net_key ~= nil and last_net_key ~= key and key ~= "none" then
        local now = mcu.ticks()
        if now - last_net_switch_ticks >= NET_SWITCH_DEBOUNCE then
            last_net_switch_ticks = now
            -- 仅已连接时强制重连：网络切换后旧 TCP 连接基于旧网卡，需重建
            -- 未连接时跳过：连接由 IP_READY / wait_network 流程负责建立
            if connected then
                log.warn("aircloud_app", "检测到网络切换:", last_net_key, "→", key, "(adapter=" .. tostring(adapter) .. ")，触发 AirCloud 强制重连")
                -- 触发强制重连（独立任务延迟 5 秒后 close+open 重建连接，给新网络就绪时间）
                -- 强制重连绕过 connected 检查：网络切换后旧 TCP 连接必然失效（即使 connected 仍为 true）也必须重建
                sys.taskInit(force_reconnect_task)
            else
                log.info("aircloud_app", "检测到网络切换:", last_net_key, "→", key, "(adapter=" .. tostring(adapter) .. ")，未连接，跳过强制重连")
            end
        else
            log.info("aircloud_app", "网络切换防抖，忽略:", last_net_key, "→", key)
        end
    elseif last_net_key == nil and key ~= "none" then
        -- 首次收到网络状态事件（如 WiFi CONNECTED 确认）：记录网络标识，不触发强制重连
        log.info("aircloud_app", "首次网络状态:", key, "(adapter=" .. tostring(adapter) .. ")，记录网络标识，不触发强制重连")
    end
    last_net_key = key
end)

-- 网络就绪触发连接（订阅内核 IP_READY 消息：4G/WiFi 网卡获取 IP 后内核自动发布）
-- 场景：开机无网络时 aircloud_task 已在 wait_network 中循环等待 IP_READY，此订阅为冗余保险；
--       主要作用：open 失败后（如 getip 请求失败），网络重新就绪时触发重新连接
--       （aircloud_task 在 while true 中等待 AIRCLOUD_CONNECT_TRIGGER）
local function on_ip_ready(ip, adapter)
    log.info("aircloud_app", "网络就绪(IP_READY):", tostring(ip), "adapter=" .. tostring(adapter))
    -- 仅未连接时触发连接（已连接时由网络切换/断线事件处理，避免重复连接）
    if not connected then
        log.info("aircloud_app", "网络就绪且未连接，触发 AirCloud 连接")
        sys.publish("AIRCLOUD_CONNECT_TRIGGER", 0)
    end
end
sys.subscribe("IP_READY", on_ip_ready)

-- 发送 TLV 数据到云端（协议 7：设备数据上报）
function aircloud_app.send(tlv_list, need_reply)
    return excloud.send(tlv_list, need_reply)
end

-- 获取当前连接状态
function aircloud_app.is_connected()
    return connected
end

-- 记录运维日志（协议 9：AirCloud 运维日志，关键业务逻辑处调用）
function aircloud_app.mtn_log(tag, ...)
    excloud.mtn_log(tag, ...)
end

-- 主动上报运维日志（协议 9：封装 excloud.upload_mtnlogs，供外部触发）
-- 返回：true=至少一个文件上传成功；false+err_msg=无未上报日志/上传中/失败
function aircloud_app.upload_mtn_logs()
    return excloud.upload_mtnlogs()
end

-- 启动云连接任务
sys.taskInit(aircloud_task)
-- 启动运维日志主动上传任务（场景3.1 开机上报一次 + 场景3.2 每10分钟上报一次）
sys.taskInit(mtn_logs_upload_task)

return aircloud_app
