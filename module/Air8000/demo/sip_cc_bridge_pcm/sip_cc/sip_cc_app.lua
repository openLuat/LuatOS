--[[
@module  sip_cc_app
@summary SIP/CC 音频桥接应用调度
@version 1.0
@date    2026.07.27
@usage
负责等待网络并按顺序初始化纯 PCM CC、SIP和桥接状态。
]]

local cc_main = require "cc_main"
local sip_main = require "sip_main"
local config = require "config"
require "bridge"

local TAG = "sip_cc_app"

local function app_task()
    local ready, ip, adapter = sys.waitUntil("IP_READY", 10000)
    if ready then
        log.info(TAG, "网络已就绪",
            "adapter=" .. tostring(adapter),
            "ip=" .. tostring(ip))
    else
        log.warn(TAG, "等待网络超时，继续初始化 SIP")
    end

    -- TLS 校验证书有效期；在启动任何通话业务前完成网络校时。
    if type(config.sip_transport) == "string" and config.sip_transport:lower() == "tls" then
        log.info(TAG, "TLS 启动前网络校时")
        socket.sntp()
        if not sys.waitUntil("NTP_UPDATE", 10000) then
            log.error(TAG, "TLS 校时失败，停止启动")
            return
        end
    end

    -- 所有协调器已在模块加载时订阅事件，CC 必须先于 SIP 初始化。
    local cc_ok, reason = cc_main.init()
    if not cc_ok then
        log.error(TAG, "CC 初始化失败，停止启动", reason)
        return
    end
    if not sip_main.init() then
        log.error(TAG, "SIP 初始化失败，停止启动")
        return
    end
    log.info(TAG, "SIP/CC 桥接应用启动成功", "bridge_pcm")
end

sys.taskInit(app_task)

return true
