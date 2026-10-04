--[[
@module  task_adapter
@summary 单SIP与SIP_CC统一任务适配及重启切换
@version 2.0
@date    2026.09.29
@author  王世豪
@usage
协同配置版本：运行模式独立于主动任务保存，删除任务不改变模式。
同一套任务协议支持pair/round/phone。跨音频分支保存后回执reboot_pending，
至少3秒后等通话与媒体空闲再重启；不在通话中热切换音频。
同一单SIP分支的pair/round互换无需重启。重启后只加载目标分支，不自动拨号。
]]
local runtime = require "task_runtime"
local exsip = require "exsip"
local voice = require "task_voice"
local air1103 = require "air1103"
local cc_sip, cc_app
local state, failed, pending = "INIT", false, false
local adapter = {
    modes = runtime.switchable and {"pair", "round", "phone"} or {"phone"},
    mode_switch = runtime.switchable,
    active_mode = runtime.active
}
-- 单 SIP：离开"通话中"状态即视为本次呼叫结束（含未接通就失败/被拒 486），
-- 及时置 failed 通知任务引擎释放，避免引擎等满 wait(30s) 超时才放开按键。
local CALL_STATES = {DIALING=true, INCOMING=true, ANSWERING=true, CONNECTED=true, HANGING_UP=true}
local function on_single_state(value)
    if CALL_STATES[state] and not CALL_STATES[value] then failed = true end
    state = value
end
local function on_call_failed() failed = true end
if runtime.active == "single" then
    sys.subscribe("SIP_APP_STATE", on_single_state)
else
    cc_sip = require "cc_sip"
    cc_app = require "cc_main"
    sys.subscribe("SIP_FAILED", on_call_failed)
    sys.subscribe("CC_FAILED", on_call_failed)
    sys.subscribe("SIP_DISCONNECTED", on_call_failed)
    sys.subscribe("CC_DISCONNECTED", on_call_failed)
end
local function calls_idle()
    if runtime.active == "single" then
        return state == "READY" or state == "INIT" or state == "OFFLINE"
            or state == "AUDIO_RECOVERING" or state == "AUDIO_ERROR" or state == "CONFIG_REQUIRED"
    end
    return cc_sip.get_state() == "sip_idle" and cc_app.get_state() == "cc_idle"
end
function adapter.idle()
    return not pending and not voice.is_playing() and calls_idle() and not exsip.is_voip_running()
end
function adapter.ready()
    if not adapter.idle() then return false end
    if runtime.active == "single" then return state == "READY" end
    return cc_sip.is_registered() and cc_app.is_ready()
end
function adapter.connected()
    if runtime.active == "single" then return state == "CONNECTED" end
    return cc_sip.get_state() == "sip_connected" and cc_app.get_state() == "cc_connected"
end
function adapter.failed()
    if runtime.active == "single" then
        return state == "OFFLINE" or state == "AUDIO_ERROR" or failed
    end
    return failed
end
function adapter.incoming() return runtime.active == "single" and state == "INCOMING" end
function adapter.accept()
    if not pending then sys.publish("SIP_APP_MAIN_ACCEPT_REQ") end
end
function adapter.dial(number)
    if not adapter.ready() then return false end
    failed = false
    if runtime.active == "single" then
        sys.publish("SIP_APP_MAIN_DIAL_REQ", "cloud-task", (#number == 16 and number or number .. "0"))
    else
        sys.publish("SIP_MESSAGE", json.encode({cmd="dial", number=number}))
    end
    return true
end
function adapter.hangup()
    if runtime.active == "single" then sys.publish("SIP_APP_MAIN_HANGUP_REQ")
    else sys.publish("SIP_MESSAGE", json.encode({cmd="hangup"})) end
end
function adapter.reboot_pending() return pending end
local function restart_when_idle()
    if calls_idle() and not exsip.is_voip_running() then
        log.info("task_runtime", "reboot to apply saved mode")
        rtos.reboot()
    else
        log.info("task_runtime", "waiting for idle before reboot")
        sys.timerStart(restart_when_idle, 1000)
    end
end
function adapter.mode_changed(next_mode)
    if next_mode ~= runtime.active and runtime.switchable and not pending then
        pending = true
        log.info("task_runtime", "saved mode; reboot pending", next_mode)
        sys.timerStart(restart_when_idle, 3000)
    end
end
function adapter.health()
    local registered, audio_ready
    if runtime.active == "single" then
        local single_app = require "single_app"
        registered, audio_ready = single_app.status()
    else
        registered = cc_sip.is_registered()
        local cc_audio = require "cc_audio"
        audio_ready = cc_audio.is_ready() and cc_app.is_ready()
    end
    return {sip_registered=registered, audio_ready=audio_ready, call_idle=calls_idle() and not exsip.is_voip_running()}
end
local function announcement_ready()
    if pending or not calls_idle() or exsip.is_voip_running() then return false end
    local h=adapter.health()
    return h.sip_registered and h.audio_ready and h.call_idle
end
local function restore_volume()
    local level
    if runtime.active=="single" then
        local single_config = require "single_config"
        level=single_config.audio.volume
    else
        local cfg=require "sip_config"
        local cc_bridge = require "cc_bridge"
        level=cc_bridge.get_state().local_audio and cfg.air1103_volume or 0
    end
    air1103.set_volume(math.max(0,math.min(31,level or 0)))
end
function adapter.cancel_announcement() voice.cancel("call or new command") end
function adapter.announcement_available() return not air1103.is_running() end
function adapter.announce(record)
    if not voice.start(record,announcement_ready,restore_volume) then log.warn("task_voice","skipped: disabled, busy or missing resources") end
end
-- ==================== 主灯(GPIO24)：通话/来电/拨号中常亮，空闲熄灭 ====================
local MAIN_LED_PIN = 24
gpio.setup(MAIN_LED_PIN, 0)
local function update_main_led()
    local on
    if runtime.active == "single" then
        on = state == "CONNECTED" or state == "DIALING" or state == "ANSWERING" or state == "INCOMING"
    else
        -- cc：任一侧进入通话（拨号/响铃/接通/挂断中）即点亮，两侧都空闲才熄灭
        on = cc_sip.get_state() ~= "sip_idle" or cc_app.get_state() ~= "cc_idle"
    end
    gpio.setup(MAIN_LED_PIN, on and 1 or 0)
end
sys.timerLoopStart(update_main_led, 500)

local task_cloud = require "task_cloud"
task_cloud.start(adapter)
return adapter
