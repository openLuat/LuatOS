--[[
@module  excloud_app
@summary AirCloud（云平台）连接管理功能模块
@version 1.0
@date    2026.08.06
@author  王城钧
@usage
本文件为AirCloud连接管理功能模块，核心业务逻辑为：
1、setup配置excloud库（传输方式、自动重连、运维日志等参数）；
2、等待短信服务就绪和网络就绪后，调用open启动excloud服务；
3、启动心跳定时上报，维持与服务器的连接活性；
4、启动运维日志定时上传任务；
5、注册平台消息回调函数，处理鉴权结果、连接结果、平台下发的消息以及连接断开事件：
   - 收到服务器下发的消息后，分发给sms_bridge桥接功能模块做短信指令处理；

本文件没有对外接口，直接在main.lua中require "excloud_app"就可以加载运行；
]]


-- 变量
local excloud = require("excloud")
local sms_bridge = require("sms_bridge")

_G.EXCLOUD = excloud

local TRANSPORT          = "tcp"
local AUTO_RECONNECT     = true
local RECONNECT_INTERVAL = 10
local MAX_RECONNECT      = 5
local HEARTBEAT_INTERVAL = 300

local MTN_LOG_ENABLED    = true
local MTN_LOG_BLOCKS     = 2
local MTN_LOG_WRITE_WAY  = 1
local MTN_LOG_AIRCLOUD   = true
local MTN_LOG_FIRST_UPLOAD   = 60
local MTN_LOG_UPLOAD_INTERVAL = 1800


-- 平台消息回调
local function on_excloud_event(event, data)
    if event == "auth_result" then
        if data.success then
            log.info("excloud_app", "鉴权成功")
            excloud.mtn_log("main", "AirCloud鉴权成功")
        else
            log.error("excloud_app", "鉴权失败", data.message)
            excloud.mtn_log("main", "AirCloud鉴权失败", data.message or "")
        end
    elseif event == "connect_result" then
        log.info("excloud_app", "连接结果", data.success and "成功" or "失败")
    elseif event == "message" then
        log.info("excloud_app", "收到平台消息", "seq=", data.header and data.header.sequence_num)
        for i, tlv in ipairs(data.tlvs or {}) do
            local val = tlv.value
            if type(val) == "string" and #val > 50 then
                val = string.sub(val, 1, 50) .. "..."
            end
            log.info("excloud_app", string.format("  [%d] field=%d type=%d value=%s", i, tlv.field, tlv.type, tostring(val)))
        end
        sms_bridge.handle_message(data.tlvs)
    elseif event == "disconnect" then
        log.warn("excloud_app", "连接断开")
        excloud.mtn_log("main", "AirCloud连接断开")
    end
end


-- 主连接任务
sys.taskInit(function()
    log.info("excloud_app", "等待网络就绪...")

    sys.waitUntil("SMS_READY", 30000)
    log.info("excloud_app", "短信服务就绪")

    while not socket.adapter(socket.dft()) do
        sys.waitUntil("IP_READY", 1000)
    end
    log.info("excloud_app", "网络就绪")

    excloud.setup({
        transport          = TRANSPORT,
        auto_reconnect     = AUTO_RECONNECT,
        reconnect_interval = RECONNECT_INTERVAL,
        max_reconnect      = MAX_RECONNECT,
        mtn_log_enabled    = MTN_LOG_ENABLED,
        mtn_log_blocks     = MTN_LOG_BLOCKS,
        mtn_log_write_way  = MTN_LOG_WRITE_WAY,
        aircloud_mtn_log_enabled = MTN_LOG_AIRCLOUD,
    })
    excloud.on(on_excloud_event)

    local ok, err = excloud.open()
    if not ok then
        log.error("excloud_app", "启动失败", err)
        return
    end
    log.info("excloud_app", "AirCloud连接已启动")
    excloud.mtn_log("main", "启动完成", "网络就绪", "短信就绪", "AirCloud已启动")

    excloud.start_heartbeat(HEARTBEAT_INTERVAL)
    log.info("excloud_app", "心跳已启动", HEARTBEAT_INTERVAL, "s")
    excloud.mtn_log("main", "心跳已启动", "间隔", HEARTBEAT_INTERVAL)

    sys.taskInit(function()
        sys.wait(MTN_LOG_FIRST_UPLOAD * 1000)
        log.info("excloud_app", "首次上传运维日志")
        excloud.upload_mtnlogs()
        while true do
            sys.wait(MTN_LOG_UPLOAD_INTERVAL * 1000)
            log.info("excloud_app", "定时上传运维日志")
            excloud.upload_mtnlogs()
        end
    end)
    log.info("excloud_app", "运维日志定时上传已启动", "首次", MTN_LOG_FIRST_UPLOAD, "s", "间隔", MTN_LOG_UPLOAD_INTERVAL, "s")
    excloud.mtn_log("main", "运维日志定时上传已启动", "间隔", MTN_LOG_UPLOAD_INTERVAL)
end)

log.info("excloud_app", "已加载")
