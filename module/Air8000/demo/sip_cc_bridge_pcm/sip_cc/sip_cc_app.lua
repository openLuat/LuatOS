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
