--[[
@module  sip_cc_app
@summary SIP/CC 音频桥接应用调度
@version 1.0
@date    2026.07.27
@usage
负责等待网络并按顺序初始化音频、CC、SIP和桥接状态。
]]

local config = require "config"
local audio_drv = require "audio_drv"
local cc_main = require "cc_main"
local sip_main = require "sip_main"
local bridge = require "bridge"

local TAG = "sip_cc_app"

local function log_state()
    local state = bridge.get_state()
    log.info(TAG, "状态",
        "SIP=" .. state.sip_state,
        "CC=" .. state.cc_state,
        "注册=" .. (sip_main.is_registered() and "Y" or "N"),
        "方向=" .. (state.call_direction or "-"),
        "时长=" .. state.call_duration .. "s")
end

local function app_task()
    local ready, ip, adapter = sys.waitUntil("IP_READY", 10000)
    if ready then
        log.info(TAG, "网络已就绪",
            "adapter=" .. tostring(adapter),
            "ip=" .. tostring(ip))
    else
        log.warn(TAG, "等待网络超时，继续初始化 SIP")
    end

    local audio_ok = audio_drv.init()
    local cc_ok = cc_main.init()
    local sip_ok = sip_main.init()

    bridge.set_local_audio(config.local_audio_default == true)

    if audio_ok and cc_ok and sip_ok then
        log.info(TAG, "SIP/CC 桥接应用启动成功")
    else
        log.error(TAG, "应用初始化失败",
            "audio=" .. tostring(audio_ok),
            "CC=" .. tostring(cc_ok),
            "SIP=" .. tostring(sip_ok))
    end

    sys.timerLoopStart(log_state, 10000)
end

sys.taskInit(app_task)

return true
