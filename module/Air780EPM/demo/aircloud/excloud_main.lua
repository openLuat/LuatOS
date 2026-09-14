--[[
@module  excloud_main
@summary excloud 云平台服务核心（连接、认证、心跳、状态、事件分发）
@version 1.0.0
@date    2026.08.29
@author  LuatOS 嵌入式软件设计开发
@usage
本模块封装 excloud 扩展库的服务生命周期，是整个示例工程的“枢纽”：
1. 完成 excloud.setup / excloud.on / excloud.open 等初始化与启动
2. 等待网络就绪（socket 默认网卡）
3. 统一注册并处理 excloud 全局回调（connect_result / auth_result / message 等）
4. 把 message 事件中的各类 TLV 字段分发给对应的业务模块
   （控制命令 → excloud_cmd；运维日志上传信令 → excloud_upload；其它 → 统一记录）
5. 提供 send_tlv 等辅助函数供其它模块发送 TLV 数据
6. 处理自动心跳与状态查询

本模块会 require 三个业务模块，为避免循环依赖，这三个业务模块不反向 require 本模块，
而是各自导出公开函数，由本模块在合适时机调用。
]]

-- 依赖库
local excloud = require("excloud")

-- 业务配置
local config = require("config")
-- 业务模块（只在本模块中 require，由本模块分发调用）
local excloud_cmd = require("excloud_cmd")
local excloud_report = require("excloud_report")
local excloud_upload = require("excloud_upload")

-- 本模块对外导出的表
local M = {}

-- 连接/服务运行状态缓存，供其它模块通过 status() 查询
local runtime = {
    opened = false,         -- open() 是否已成功调用
    connected = false,      -- 底层连接是否建立
    authenticated = false,  -- 是否完成鉴权
}

-- =========================================================================
-- 日志辅助
-- =========================================================================
local function log_info(...)
    log.info(config.log_tag, ...)
end

local function log_warn(...)
    log.warn(config.log_tag, ...)
end

local function log_error(...)
    log.error(config.log_tag, ...)
end

-- =========================================================================
-- 发送 TLV 数据的统一封装（供 report/upload/cmd 等模块调用）
-- @param tlvs 待发送的 TLV 列表，形如 { {field_meaning=, data_type=, value=}, ... }
-- @param need_reply 是否需要云平台回复（对应下行控制反馈场景可传 true）
-- @param is_auth_msg 是否为鉴权消息（一般业务上报传 false）
-- @return ok, err —— ok 为 true 表示发送成功，失败时返回 false + 错误信息
-- =========================================================================
function M.send_tlv(tlvs, need_reply, is_auth_msg)
    return excloud.send(tlvs, need_reply or false, is_auth_msg or false)
end

-- =========================================================================
-- 查询当前 excloud 服务状态（供外部展示/调试用）
-- =========================================================================
function M.status()
    return {
        opened = runtime.opened,
        connected = runtime.connected,
        authenticated = runtime.authenticated,
        -- excloud 库自身的状态对象
        lib_status = excloud.status(),
        server_info = excloud.get_server_info(),
        lib_version = excloud.version(),
    }
end

-- =========================================================================
-- 全局事件回调：excloud 的所有事件都会进到这里
-- @param event  事件名（字符串）
-- @param data   事件附带的数据（table）
-- 事件一览：
--   connect_result          连接结果（data.success / data.error）
--   auth_result             鉴权结果（data.success / data.message）
--   message                 收到云平台下行消息（data.header / data.tlvs）
--   disconnect              与服务器断开
--   reconnect_failed        重连失败（data.count / data.max_reconnect / data.getip_failed）
--   send_result             发送数据结果（data.success / data.sequence_num / data.error_msg）
--   mtn_log_upload_start    运维日志上传开始（data.file_count）
--   mtn_log_upload_progress 运维日志上传进度（data.current_file / data.total_files/...）
--   mtn_log_upload_complete 运维日志上传完成（data.success_count/...）
--   auth_key_error          获取 auth_key 失败（data.error，多为 getip 鉴权信息缺失）
--   file_upload             文件上传异常（data.success / data.error）
-- =========================================================================
local function on_excloud_event(event, data)
    log_info("[回调]", event, data and json.encode(data) or "")

    if event == "connect_result" then
        if data.success then
            log_info("连接成功")
            runtime.connected = true
            -- 等待鉴权成功后再启动业务任务（也可在此提前启动，仅作演示）
            sys.publish("excloud_connected")
        else
            log_error("连接失败", data.error or "")
            runtime.connected = false
        end

    elseif event == "auth_result" then
        if data.success then
            log_info("鉴权成功")
            runtime.authenticated = true
            -- 鉴权成功后，通知其它业务任务可以开始周期上报
            sys.publish("excloud_authed")
            -- 若配置了自动心跳但尚未启动，则在此启动
            if config.auto_start_heartbeat then
                -- 构造心跳数据：优先使用用户在 config 中配置的 heartbeat_data；
                -- 默认自动构造 TIMESTAMP 心跳（os.time() 为秒级 Unix 时间戳）。
                -- 注意：心跳必须携带至少一个 TLV 字段，否则 excloud 库会报
                -- "没有有效的TLV数据可发送"且心跳发送失败，服务器可能判定设备离线。
                local heartbeat_data = config.heartbeat_data
                if not heartbeat_data then
                    heartbeat_data = {
                        {
                            field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP,
                            data_type = excloud.DATA_TYPES.INTEGER,
                            value = os.time(),
                        },
                    }
                end
                local ok = excloud.start_heartbeat(config.heartbeat_interval, heartbeat_data)
                if not ok then
                    log_warn("启动自动心跳失败")
                end
            end
        else
            log_error("鉴权失败", data.message or "")
            runtime.authenticated = false
        end

    elseif event == "message" then
        -- 收到云平台下发的消息，解析其中的 TLV 列表并分发
        handle_incoming_message(data)

    elseif event == "disconnect" then
        log_warn("与服务器断开连接")
        runtime.connected = false
        runtime.authenticated = false

    elseif event == "reconnect_failed" then
        log_info("重连失败，已尝试", data.count, "次，最大重连次数:", data.max_reconnect)

    elseif event == "send_result" then
        if data.success then
            log_info("发送成功，流水号:", data.sequence_num)
        else
            log_warn("发送失败:", data.error_msg or "")
        end

    elseif event == "auth_key_error" then
        -- getip 未能获取到 auth_key，无法继续鉴权/连接
        log_error("获取 auth_key 失败:", data.error or "",
            "请检查 use_getip/getip_url 配置，或改为手动配置 auth_key")

    elseif event == "file_upload" then
        -- 文件上传异常（图片/音频/运维日志）
        if data.success then
            log_info("文件上传成功")
        else
            log_warn("文件上传异常:", data.error or "")
        end

    elseif event == "mtn_log_upload_start" then
        log_info("运维日志上传开始，文件数量:", data.file_count)

    elseif event == "mtn_log_upload_progress" then
        log_info("运维日志上传进度，当前:", data.current_file, "/", data.total_files,
            "文件名:", data.file_name, "状态:", data.status)

    elseif event == "mtn_log_upload_complete" then
        log_info("运维日志上传完成，成功:", data.success_count, "失败:", data.failed_count,
            "总计:", data.total_files)
    else
        log_warn("未识别的回调事件:", event)
    end
end

-- =========================================================================
-- 分发下行消息：遍历 data.tlvs，按字段含义分别处理
-- @param data 云平台下行消息，结构为 { header={...}, tlvs={ {field,type,value}, ... } }
-- =========================================================================
function handle_incoming_message(data)
    log_info("收到消息，流水号:", data.header and data.header.sequence_num)

    -- 遍历该消息中的所有 TLV 字段
    for _, tlv in ipairs(data.tlvs or {}) do
        log_info("下行TLV字段", "含义:", tlv.field, "类型:", tlv.type, "值:", tostring(tlv.value))

        -- 1. 控制命令（重点）：交给 excloud_cmd 模块解析并执行
        if tlv.field == config.FIELD_MEANINGS.CONTROL_COMMAND then
            excloud_cmd.handle_command(tlv.value)

        -- 2. 运维日志上传请求（下行信令 25）：通知 upload 模块触发上传
        elseif tlv.field == config.FIELD_MEANINGS.MTN_LOG_UPLOAD_REQ_SIGNAL then
            excloud_upload.handle_mtn_log_upload_signal(tlv.value)

        -- 3. 短信发送请求回复（下行 29）：演示性记录
        elseif tlv.field == config.FIELD_MEANINGS.SMS_SEND_RSP then
            log_info("云平台短信发送回复:", tostring(tlv.value))

        -- 4. 鉴权回复（下行 17）：通常由库内部自动处理，这里仅为演示透传
        elseif tlv.field == config.FIELD_MEANINGS.AUTH_RESPONSE then
            log_info("收到鉴权回复（库内部已自动处理，此处仅为演示）")

        -- 5. 其它未知字段：统一记录，便于扩展
        else
            log_info("收到未特别处理的字段，含义:", tlv.field, "值:", tostring(tlv.value))
        end
    end
end

-- =========================================================================
-- 等待默认网卡（4G）连接成功
-- 只有网络就绪后才能 connect 到云平台
-- =========================================================================
local function wait_network_ready()
    log_info("等待默认网卡就绪...")
    -- 反复检查默认网卡是否已获得 IP，未就绪则每 1 秒重试
    while not socket.adapter(socket.dft()) do
        log_warn("等待默认网卡 IP_READY...")
        sys.wait(1000)
    end
    log_info("默认网卡已就绪")
end

-- =========================================================================
-- 初始化并启动 excloud 服务
-- =========================================================================
local function excloud_task()
    -- 1. 等待网络（4G 网卡）就绪
    wait_network_ready()

    -- 2. 组装 excloud.setup 所需的配置参数
    --    这里把 config 中的接入参数原样透传。excloud 内部对 getip 遵循“手动配置优先”的
    --    通用规则：凡是用户在 config 中已手动填写的接入字段（host/port/username/password/
    --    client_id/udp_auth_key 等），都不会被 getip 自动发现的结果覆盖；仅当某字段为 nil
    --    时，getip 才会用服务器返回的值回填。因此这里无需额外指定“是否允许覆盖”，
    --    直接把 config 透传过去，交给 excloud 按“手动优先”逻辑处理即可。
    --    注意：device_type / protocol_version 无需（也不能）在 setup 中主动配置，
    --    excloud 库会自动识别设备类型、固定协议版本，手动传入会打印告警并忽略；
    --    auth_key 已支持配置（遵循「手动配置优先」），本示例 use_getip=true 保持 nil，
    --    交由 getip 自动回填即可；若手动接入（use_getip=false）可在 config 中填写。
    local setup_params = {
        -- 传输与接入
        transport = config.transport,
        use_getip = config.use_getip,
        -- host/port 保持 nil：本示例 use_getip=true，真实服务器地址/端口由 getip 自动获取。
        -- 此处透传 config.host/config.port（均为 nil），交给 getip 自动回填即可；
        -- 仅当 use_getip=false 改用手动接入时，才在 config 中填写具体值。
        host = config.host,
        port = config.port,
        udp_auth_key = config.udp_auth_key,
        -- getip 与网络
        getip_url = config.getip_url,
        ipv6 = config.ipv6,
        -- MQTT 参数
        qos = config.qos,
        retain = config.retain,
        keepalive = config.keepalive,
        clean_session = config.clean_session,
        ssl = config.ssl,
        client_id = config.client_id,
        username = config.username,
        password = config.password,
        -- 重连参数
        auto_reconnect = config.auto_reconnect,
        reconnect_interval = config.reconnect_interval,
        max_reconnect = config.max_reconnect,
        timeout = config.timeout,
        -- 调试
        debug = config.debug,
        -- 运维日志
        mtn_log_enabled = config.mtn_log_enabled,
        mtn_log_blocks = config.mtn_log_blocks,
        mtn_log_write_way = config.mtn_log_write_way,
        aircloud_mtn_log_enabled = config.aircloud_mtn_log_enabled,
    }

    -- 文件上传来源（图片/音频/运维日志是否直接使用合宙平台参数），透传默认值 false
    setup_params.imginfo_from_luat = config.imginfo_from_luat
    setup_params.audinfo_from_luat = config.audinfo_from_luat
    setup_params.mtninfo_from_luat = config.mtninfo_from_luat

    -- Socket 底层与 SSL 证书参数（一般无需修改，透传默认值）
    setup_params.local_port = config.local_port
    setup_params.keep_idle = config.keep_idle
    setup_params.keep_interval = config.keep_interval
    setup_params.keep_cnt = config.keep_cnt
    setup_params.server_cert = config.server_cert
    setup_params.client_cert = config.client_cert
    setup_params.client_key = config.client_key
    setup_params.client_password = config.client_password

    -- 虚拟设备参数（仅在强制虚拟设备时才有意义）
    if config.force_virtual_device then
        setup_params.virtual_phone_number = config.virtual_phone_number
        setup_params.virtual_serial_num = config.virtual_serial_num
    end

    -- 3. 执行 setup（内部会自动识别设备类型与设备 ID）
    local setup_ok, setup_err = excloud.setup(setup_params)
    -- 通知 log_demo_task：setup 已完成（成功/失败都发布，避免等待方永久挂起；
    -- 只有 setup 成功返回，config.mtn_log_enabled 才会写入库内部配置，运维日志才可用）
    sys.publish("excloud_setup_done", setup_ok, setup_err)
    if not setup_ok then
        log_error("excloud.setup 失败:", setup_err)
        return
    end
    log_info("excloud.setup 成功")

    -- 4. 注册全局回调
    excloud.on(on_excloud_event)
    log_info("已注册 excloud 全局回调")

    -- 5. 打开服务（建立 socket / 鉴权，并在成功后自动重连）
    local open_ok, open_err = excloud.open()
    if not open_ok then
        log_error("excloud.open 失败:", open_err)
        return
    end
    log_info("excloud.open 成功")
    runtime.opened = true
end

-- =========================================================================
-- 启动服务协程
-- =========================================================================
sys.taskInit(excloud_task)

-- 导出本模块
return M
