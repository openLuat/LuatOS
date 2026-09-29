--[[
@module  msg_player
@summary 语音留言播放（UP 短按触发）
@version 1.0
@date    2026.09.28
@author  王世豪
@usage
本模块为留言播放业务模块，核心业务逻辑为：
1、监听 key_app 发布的 MSG_PLAY_REQ（UP 短按），仅在 SIP 空闲（READY / OFFLINE）时播放；
2、通话中 / 呼出中 / 来电振铃中一律忽略（产品定义：通话中按 UP 直接忽略）；
3、播放过程中 SIP 一旦进入非空闲状态（来电或开始呼出），立即打断留言，
   把播放通道让给振铃与通话下行语音；
4、留言文件与开关在 config.message 配置。Air1103 只支持 PCM 流式播放(type=2)，
   留言必须是 16kHz / 16bit / 单声道裸 PCM；

留言与通话共用同一条 Air1103 播放 FIFO，这是上面所有限制的根源。

本文件没有对外接口，在 app_main.lua 中 require "msg_player" 即可加载运行；
]]

local config = require "config"
local audio_drv = require "audio_drv"

local TAG = "msg_player"
local msg_cfg = config.message or {}
local sip_state = "INIT"        -- 由 sip_app_main 广播的 SIP_APP_STATE 更新

-- 只有这两种状态属于"空闲"，可以播留言
local function sip_idle()
    return sip_state == "READY" or sip_state == "OFFLINE"
end

sys.subscribe("SIP_APP_STATE", function(state)
    sip_state = state
    -- 播放中来了电话或开始呼出：让出播放通道（振铃、下行语音都要用这条 FIFO）
    if audio_drv.is_message_playing() and not sip_idle() then
        log.info(TAG, "SIP 状态", state, "打断留言播放")
        audio_drv.stop_message()
    end
end)

sys.subscribe("MSG_PLAY_REQ", function()
    if not msg_cfg.enabled then
        log.info(TAG, "留言功能已关闭")
        return
    end
    if not sip_idle() then
        log.warn(TAG, "SIP 非空闲，忽略留言播放", sip_state)
        return
    end
    if not audio_drv.play_message(msg_cfg.file) then
        log.warn(TAG, "留言播放未启动，检查文件与音频就绪状态")
    end
end)

log.info(TAG, "留言播放已就绪", "文件=", tostring(msg_cfg.file), "开关=", tostring(msg_cfg.enabled))
