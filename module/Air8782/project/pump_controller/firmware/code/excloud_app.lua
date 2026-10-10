--[[
@module  excloud_app
@summary AirCloud 服务核心（连接 / 鉴权 / 事件分发 / 运维日志上传 / 控制回应）
@version 1.0.0
@date    2026.09.11
@author  嵌入式软件设计开发代理
@usage
参考官方 demo module/Air780EPM/demo/aircloud/excloud_main.lua：
1. 网络就绪后 excloud.setup / excloud.on / excloud.open；
2. 统一处理 excloud 回调事件，并向上层发布内部主题：
   - 鉴权成功 → AIRCLOUD_READY
   - 收到 CONTROL_COMMAND(19) → AIRCLOUD_CMD
   - 运维日志上传请求(25) → excloud.upload_mtnlogs()
   - 收到 CTRL_RESULT → 回复 CONTROL_RESPONSE(20)
3. 提供 send_tlv() 供 aircloud_report 上报数据；
4. 网络收发正常时向 network_watchdog 喂狗；
5. 定时（5 分钟）检查并上传运维日志。
依据：requirement.md 5.5/5.7、network-communication-protocol.md、嵌入式软件总体设计.md 4.10。
本模块有对外接口，末尾 return M。
]]

local excloud    = require("excloud")
local config_app = require("config_app")
local msg_bus    = require("msg_bus")
local oam_logger = require("oam_logger")

local M = {}

-- 运行状态
local runtime = {
    connected     = false,
    authenticated = false,
}

-- =========================================================================
-- 对外：发送 TLV 数据（供 aircloud_report 使用）
-- =========================================================================
function M.send_tlv(tlvs, need_reply)
    return excloud.send(tlvs, need_reply or false, false)
end

-- =========================================================================
-- 内部：处理下行消息，按字段含义分发
-- =========================================================================
local function handle_incoming_message(data)
    for _, tlv in ipairs(data.tlvs or {}) do
        if tlv.field == config_app.FIELD_MEANINGS.CONTROL_COMMAND then
            -- 控制命令(19)：交由 aircloud_ctrl 解析执行
            sys.publish(msg_bus.AIRCLOUD_CMD, { cmd_type = "control", data = tlv.value })
        elseif tlv.field == config_app.FIELD_MEANINGS.MTN_LOG_UPLOAD_REQ_SIGNAL then
            -- 运维日志上传请求(25)
            log.info("excloud_app", "收到运维日志上传请求")
            excloud.upload_mtnlogs()
        else
            log.info("excloud_app", "收到未处理字段", "field", tlv.field, "value", tostring(tlv.value))
        end
    end
end

-- =========================================================================
-- 内部：excloud 全局事件回调
-- =========================================================================
local function on_excloud_event(event, data)
    if event == "connect_result" then
        if data.success then
            runtime.connected = true
            log.info("excloud_app", "连接成功")
            oam_logger.log("cloud", "connected")
        else
            runtime.connected = false
            log.error("excloud_app", "连接失败", data.error or "")
        end

    elseif event == "auth_result" then
        if data.success then
            runtime.authenticated = true
            log.info("excloud_app", "鉴权成功")
            oam_logger.log("cloud", "authed")
            sys.publish(msg_bus.AIRCLOUD_READY)
        else
            runtime.authenticated = false
            log.error("excloud_app", "鉴权失败", data.message or "")
        end

    elseif event == "message" then
        -- 收到下行数据即喂网络看门狗
        sys.publish(msg_bus.FEED_NET_WDT)
        handle_incoming_message(data)

    elseif event == "send_result" then
        if data.success then
            sys.publish(msg_bus.FEED_NET_WDT)
        else
            log.warn("excloud_app", "发送失败", data.error_msg or "")
        end

    elseif event == "disconnect" then
        runtime.connected = false
        runtime.authenticated = false
        log.warn("excloud_app", "与服务器断开连接")

    elseif event == "reconnect_failed" then
        log.warn("excloud_app", "重连失败", data.count or 0)

    elseif event == "auth_key_error" then
        log.error("excloud_app", "获取 auth_key 失败", data.error or "")

    elseif event == "mtn_log_upload_complete" then
        log.info("excloud_app", "运维日志上传完成", "成功", data.success_count or 0)

    else
        log.info("excloud_app", "回调事件", event)
    end
end

-- =========================================================================
-- 内部：回复控制回应（订阅 CTRL_RESULT）
-- =========================================================================
local function on_ctrl_result(payload)
    local results = payload and payload.results or {}
    local value = json.encode(results)
    local ok, err = excloud.send({
        {
            field_meaning = config_app.FIELD_MEANINGS.CONTROL_RESPONSE,
            data_type     = config_app.DATA_TYPES.UNICODE,
            value         = value,
        }
    }, false)
    if not ok then
        log.warn("excloud_app", "回复控制回应失败", err)
    end
end

-- =========================================================================
-- 内部：等待默认网卡就绪
-- =========================================================================
local function wait_network_ready()
    while not socket.adapter(socket.dft()) do
        log.warn("excloud_app", "等待默认网卡 IP_READY...")
        sys.wait(1000)
    end
end

-- =========================================================================
-- 内部：运维日志定时上传（每 mtn_log_upload_cycle 秒检查并上传）
-- =========================================================================
local function mtn_log_upload_task()
    sys.waitUntil(msg_bus.AIRCLOUD_READY)
    while true do
        sys.wait(config_app.mtn_log_upload_cycle * 1000)
        excloud.upload_mtnlogs()
    end
end

-- =========================================================================
-- 内部：excloud 服务主任务
-- =========================================================================
local function excloud_task()
    -- 等待网络就绪
    wait_network_ready()

    -- 组装 setup 参数（依据 network-communication-protocol.md 第 3/6/7 章）
    local setup_params = {
        transport                 = config_app.cloud_transport,       -- tcp
        use_getip                 = config_app.cloud_use_getip,       -- 真（合宙公有云）
        auto_reconnect            = config_app.cloud_auto_reconnect,
        reconnect_interval        = config_app.cloud_reconnect_interval,
        max_reconnect             = config_app.cloud_max_reconnect,
        timeout                   = 30,
        debug                     = config_app.cloud_debug,
        -- 运维日志（必须启用）
        mtn_log_enabled           = config_app.mtn_log_enabled,
        mtn_log_blocks            = config_app.mtn_log_blocks,
        mtn_log_write_way         = config_app.mtn_log_write_way,
        aircloud_mtn_log_enabled  = config_app.aircloud_mtn_log_enabled,
    }

    -- PC 模拟器：excloud 自动判定为“虚拟设备”（rtos.bsp()=="PC" → device_type=9），
    -- 必须提供 virtual_phone_number / virtual_serial_num，否则 excloud.setup 失败。
    -- 注：若 sim_identity 已生效（真机身份），全局 rtos.bsp() 已返回机型，此处条件为假、不注入（符合预期）。
    if rtos.bsp() == "PC" then
        setup_params.virtual_phone_number = config_app.cloud_virtual_phone_number
        setup_params.virtual_serial_num   = config_app.cloud_virtual_serial_num
    end

    local setup_ok, setup_err = excloud.setup(setup_params)
    if not setup_ok then
        log.error("excloud_app", "excloud.setup 失败", setup_err)
        return
    end
    log.info("excloud_app", "excloud.setup 成功")

    -- 注册回调
    excloud.on(on_excloud_event)

    -- 打开服务
    local open_ok, open_err = excloud.open()
    if not open_ok then
        log.error("excloud_app", "excloud.open 失败", open_err)
        return
    end
    log.info("excloud_app", "excloud.open 成功")
end

-- =========================================================================
-- 订阅与启动
-- =========================================================================
sys.subscribe(msg_bus.CTRL_RESULT, on_ctrl_result)
sys.taskInit(excloud_task)
sys.taskInit(mtn_log_upload_task)

return M
