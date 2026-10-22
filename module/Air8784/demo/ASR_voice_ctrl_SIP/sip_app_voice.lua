--[[
@module  sip_app_voice
@summary 用 Air1103 离线语音识别替代按键：说"接听电话"接听、"挂断电话"挂断
@version 1.0
@date    2026.10.21
@description
    基于本工程已初始化的 Air1103（config.audio 配置串口、2M 波特率、外挂语音芯片）。
    仅注册 air1103.on_identify，不碰 audio_drv 的 on_audio_data / MIC 上行，
    因此语音识别与 SIP 通话 PCM 桥接可同时工作。
@usage
    Air1103 语音芯片（固件 V1.1.8 及以上）支持免唤醒词指令，直接说：
        "接听电话"（或"接通电话"）-> 发布 SIP_APP_MAIN_ACCEPT_REQ，由 sip_app_main 接听
        "挂断电话"                -> 发布 SIP_APP_MAIN_HANGUP_REQ，由 sip_app_main 挂断
    若板子上 1103 的串口/电源脚与默认配置不同，改 config.audio.uart_id / power_gpio。
]]

local air1103 = require "air1103"

local function on_identify(text)
    text = (text or ""):match("^%s*(.-)%s*$")
    if text == "" then return end
    log.info("sip_app_voice", "Air1103识别到:", text)
    if text == "接听电话" or text == "接通电话" then
        log.info("sip_app_voice", ">>> 语音指令[接听电话]")
        sys.publish("SIP_APP_MAIN_ACCEPT_REQ")
    elseif text == "挂断电话" then
        log.info("sip_app_voice", ">>> 语音指令[挂断电话]")
        sys.publish("SIP_APP_MAIN_HANGUP_REQ")
    end
end

air1103.on_identify(on_identify)
log.info("sip_app_voice", "语音接听/挂断已启用：当前V1.1.8固件无需使用唤醒词，直接说[接听电话]或[挂断电话]即可触发语音指令")
