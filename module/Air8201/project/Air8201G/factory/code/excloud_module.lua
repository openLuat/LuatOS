--[[
@module  excloud_module
@summary excloud云端通信模块
@version 1.1
@date    2026.05.27
@description
    实现与合宙IoT云平台的通信，包括设备连接、认证、数据上报和远程控制
    本版本已移除 config 依赖与远程配置合并入口（check_update），所有参数硬编码在顶部常量。
]]

local excloud_module = {}

-- 导入模块
local excloud = require "excloud"
local global_config = require "global_config"

-- ========== 硬编码常量（原 config.excloud 默认值） ==========
local AUTH_KEY            = "tJMyP71DEubItiXa62w2ddkG3wum8wPm" -- 用户项目密钥
local DEVICE_TYPE         = 1            -- 设备类型: 1-4G, 2-WiFi, 9-虚拟设备
local TRANSPORT           = "tcp"        -- 传输协议
local AUTO_RECONNECT      = true         -- 自动重连
local RECONNECT_INTERVAL  = 10           -- 重连间隔(秒)
local MAX_RECONNECT       = 5            -- 最大重连次数
local MTN_LOG_ENABLED     = true         -- 启用运维日志
local MTN_LOG_BLOCKS      = 1            -- 日志文件块数
local USE_GETIP           = true         -- 使用getip服务
-- ============================================================

-- 回调函数列表
local callbacks = {}

-- 连接状态
local is_connected = false

-- ========== 心跳配置（模块级，对外暴露 + 内部状态分离） ==========
-- 【对外开关】是否在收到"连接成功"事件后自动启动心跳
--   true  → 收到 connect_result 成功时自动启动心跳（默认行为）
--   false → 收到 connect_result 成功时不启动心跳（用户自管或不需要心跳）
-- 用户可在 require 之后、init 之前修改此开关：
--   excloud_module.HEARTBEAT_AUTO_START = false
excloud_module.HEARTBEAT_AUTO_START = true

-- 心跳间隔（秒）：5 分钟。同样对外暴露允许业务覆盖
excloud_module.HEARTBEAT_INTERVAL_SEC = 300

-- 心跳数据 payload（仅 1 个 TIMESTAMP 字段，最小负载）
-- ⚠️ 必须传入非空表，否则官方 excloud 库默认 heartbeat_data={}，会触发
--    "没有有效的TLV数据可发送" 错误，心跳实际发不出去
-- ⚠️ value 是构建时刻的快照（库回调发包时复用同一份 data 引用）
local function build_heartbeat_payload()
    return {
        {
            field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP,
            data_type     = excloud.DATA_TYPES.INTEGER,
            value         = os.time()
        }
    }
end

-- 心跳是否已启动的"软标记"（与库内部 is_heartbeat_running 保持镜像）
-- 注：库内部 close() 会自动 stop_heartbeat()，因此 disconnect 事件需要把此标志归 false
local heartbeat_started = false

-- 启动心跳（轻量、幂等、可控）
-- 1. 检查对外开关 HEARTBEAT_AUTO_START → false 则跳过
-- 2. 检查 heartbeat_started 软标记 → 已启动则跳过（避免 stop+start 抖动）
-- 3. 真正需要启动时才构建 payload + 调用 excloud.start_heartbeat
local function start_heartbeat_if_needed()
    if not excloud_module.HEARTBEAT_AUTO_START then
        log.info("EXCLOUD", "心跳自动启动开关已关闭 (HEARTBEAT_AUTO_START=false)，跳过")
        return
    end
    if heartbeat_started then
        -- 已启动状态，定时器仍在跑，不重复启动（轻量）
        return
    end
    local payload = build_heartbeat_payload()
    excloud.start_heartbeat(excloud_module.HEARTBEAT_INTERVAL_SEC, payload)
    heartbeat_started = true
    log.info("EXCLOUD", "Heartbeat started, 间隔=" .. excloud_module.HEARTBEAT_INTERVAL_SEC
                        .. "s, payload=TIMESTAMP only")
end

-- 注册回调函数
function excloud_module.register_callback(callback)
    table.insert(callbacks, callback)
    log.info("EXCLOUD", "Callback registered")
end

-- 触发回调
local function trigger_callbacks(event, data)
    for _, cb in ipairs(callbacks) do
        pcall(cb, event, data)
    end
end

-- excloud事件处理回调
local function on_excloud_event(event, data)
    log.info("EXCLOUD", "Event received:", event, json.encode(data))

    if event == "connect_result" then
        if data.success then
            log.info("EXCLOUD", "Connected to cloud")
            is_connected = true
            sys.publish("EXCLOUD_CONNECTED")

            -- 根据对外开关决定是否启动心跳（首次/重连一视同仁，逻辑统一）
            -- 已启动状态下会直接跳过，避免重复 stop+start 抖动（轻量）
            start_heartbeat_if_needed()

            -- 上报设备上线状态（库内置 device_status 包，占用 1 个底层 sequence_num，不影响业务 SN）
            excloud_module.send_device_status("online")
        else
            log.error("EXCLOUD", "Connection failed:", data.error or "unknown")
            is_connected = false
            global_config.inc_tcp_fail_count()
        end

    elseif event == "auth_result" then
        if data.success then
            log.info("EXCLOUD", "Authentication successful")
        else
            log.error("EXCLOUD", "Authentication failed:", data.message)
        end

    elseif event == "message" then
        log.info("EXCLOUD", "Received message, sequence:", data.header.sequence_num)
        trigger_callbacks("message", data)

    elseif event == "disconnect" then
        log.warn("EXCLOUD", "Disconnected from cloud")
        is_connected = false
        global_config.inc_disconnect_count()
        global_config.inc_tcp_drop_count()
        -- 库内部 close()/重连流程会调用 stop_heartbeat()，软标记归位
        -- 这样下次 connect_result 时 start_heartbeat_if_needed 才会真正重启心跳
        heartbeat_started = false
        sys.publish("EXCLOUD_DISCONNECTED")

    elseif event == "reconnect_failed" then
        log.warn("EXCLOUD", "Reconnect failed, attempts:", data.count)

    elseif event == "send_result" then
        if data.success then
            log.info("EXCLOUD", "Send successful, sequence:", data.sequence_num)
        else
            log.error("EXCLOUD", "Send failed:", data.error_msg)
        end

    elseif event == "mtn_log_upload_start" then
        log.info("EXCLOUD", "Mtn log upload start, files:", data.file_count)

    elseif event == "mtn_log_upload_progress" then
        log.info("EXCLOUD", "Mtn log progress:", data.current_file, "/", data.total_files)

    elseif event == "mtn_log_upload_complete" then
        log.info("EXCLOUD", "Mtn log upload complete, success:", data.success_count)
    end
end

-- 初始化excloud
function excloud_module.init()
    log.info("EXCLOUD", "Initializing excloud...")

    excloud.on(on_excloud_event)

    local ok, err_msg = excloud.setup({
        use_getip          = USE_GETIP,
        device_type        = DEVICE_TYPE,
        transport          = TRANSPORT,
        auto_reconnect     = AUTO_RECONNECT,
        reconnect_interval = RECONNECT_INTERVAL,
        max_reconnect      = MAX_RECONNECT,
        mtn_log_enabled    = MTN_LOG_ENABLED,
        mtn_log_blocks     = MTN_LOG_BLOCKS,
        mtn_log_write_way  = excloud.MTN_LOG_ADD_WRITE,
        auth_key           = AUTH_KEY
    })

    if not ok then
        log.error("EXCLOUD", "Setup failed:", err_msg)
        return false
    end

    local ok2, err_msg2 = excloud.open()
    if not ok2 then
        log.error("EXCLOUD", "Open failed:", err_msg2)
        return false
    end

    -- ⚠️ 心跳启动逻辑已移至 on_excloud_event 的 connect_result 成功分支
    --    （首次连接成功 + 每次断网重连成功 都会自动启动心跳，统一管理）
    -- 旧的 excloud.start_heartbeat() 调用已删除，避免双重启动

    local qrinfo = excloud.get_qrinfo()
    if qrinfo and qrinfo.url then
        log.info("EXCLOUD", "QR Code URL:", qrinfo.url)
    end

    log.info("EXCLOUD", "Initialization complete")
    return true
end

-- 发送数据到云端
function excloud_module.send(data, is_urgent)
    if not is_connected then
        log.warn("EXCLOUD", "Not connected, skip sending")
        return false, "not connected"
    end

    log.info("EXCLOUD", "Sending data:", json.encode(data), "Urgent:", is_urgent or false)

    local ok, err_msg = excloud.send(data, is_urgent or false)

    if ok then
        log.info("EXCLOUD", "Data queued successfully")
    else
        log.error("EXCLOUD", "Failed to queue data:", err_msg)
    end

    return ok, err_msg
end

-- 发送设备状态
function excloud_module.send_device_status(status)
    log.info("EXCLOUD", "Sending device status:", status)

    local data = {
        {
            field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = os.time()
        }
    }

    return excloud_module.send(data, true)
end

-- 发送定位数据
function excloud_module.send_location(lat, lng, accuracy, source)
    log.info("EXCLOUD", "Sending location:", lat, lng, accuracy, source)

    local data = {
        {
            field_meaning = excloud.FIELD_MEANINGS.GNSS_LATITUDE,
            data_type = excloud.DATA_TYPES.FLOAT,
            value = lat
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.GNSS_LONGITUDE,
            data_type = excloud.DATA_TYPES.FLOAT,
            value = lng
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.LOCATION_METHOD,
            data_type = excloud.DATA_TYPES.ASCII,
            value = source
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = os.time()
        }
    }

    return excloud_module.send(data, false)
end

-- 发送电池状态
function excloud_module.send_battery(level, is_charging)
    log.info("EXCLOUD", "Sending battery status:", level, is_charging)

    local data = {
        {
            field_meaning = excloud.FIELD_MEANINGS.BATTERY_LEVEL,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = level
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.CHARGING_STATUS,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = is_charging and 1 or 0
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = os.time()
        }
    }

    return excloud_module.send(data, false)
end

-- 发送系统状态
function excloud_module.send_system_status(info)
    log.info("EXCLOUD", "Sending system status")

    local data = {
        {
            field_meaning = excloud.FIELD_MEANINGS.SIGNAL_STRENGTH_4G,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = info.signal or 0
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.SIM_ICCID,
            data_type = excloud.DATA_TYPES.ASCII,
            value = info.iccid or ""
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.CPU_TEMPERATURE,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = info.temperature or 0
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = os.time()
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.REBOOT_REASON,
            data_type = excloud.DATA_TYPES.UNICODE,
            value = info.reboot_reason or ""
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.REBOOT_COUNT,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = info.reboot_count or 0
        }
    }

    return excloud_module.send(data, false)
end

-- 上传运维日志
function excloud_module.upload_mtn_log()
    log.info("EXCLOUD", "Uploading mtn log")
    excloud.mtn_log_upload()
end

-- 记录运维日志
function excloud_module.log(tag, message, ...)
    excloud.mtn_log(tag, message, ...)
end

-- 获取连接状态
function excloud_module.is_connected()
    return is_connected
end

-- 获取状态信息
function excloud_module.status()
    return excloud.status()
end

return excloud_module
