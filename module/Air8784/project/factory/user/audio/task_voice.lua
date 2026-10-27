--[[
@module  task_voice
@summary 任务/配置提示 TTS 播报（运行时合成，不依赖预录 PCM 文件）
@version 1.0
@date    2026.10.27
@author  王世豪
@usage
提供 start()/start_text()/cancel()/is_playing() 等接口：
- 任务保存成功（"任务已生效"）或仅接听模式（"仅接听模式已生效"）时播报
- 文案与音量见 task_voice_config.lua
- 需固件具备 tts_pcm 能力；播放前检查 Air1103 与音频占用
]]
-- Task/configuration announcements: runtime TTS, no prerecorded PCM files.
local M={}
local cfg=require "task_voice_config"
local air=require "air1103"
local active,exaudio
function M.is_playing() return active~=nil end
local function finish(item,reason)
    if active~=item then return end
    active=nil
    if item.timer then sys.timerStop(item.timer) end
    if item.restore then pcall(item.restore) end
    log.info("task_voice","finished",reason)
    if item.notify then item.notify(item.cancel_status or ((reason==nil or reason=="done") and "done" or "failed"),item.cancel_reason or reason) end
end
function M.cancel(reason,status)
    if not active or active.stopping then return end
    active.stopping=true
    active.cancel_status=status or "cancelled"
    active.cancel_reason=reason or "cancelled"
    -- Keep ownership until the native TTS completion callback releases it.
    pcall(exaudio.play_stop,{type=1})
    log.info("task_voice","cancel",reason)
end
function M.start(record,can_play,on_restore)
    return M.start_text(record.task and cfg.task_text or cfg.receiver_text,can_play,on_restore)
end
function M.start_text(text,can_play,on_restore,notify,timeout)
    if not cfg.enabled then return false,"tts_disabled" end
    if active or not can_play() or air.is_running() then return false,"audio_busy" end
    exaudio=exaudio or require "exaudio"
    if not exaudio.is_end() then return false,"audio_busy" end
    local item={restore=on_restore,notify=notify,elapsed=0};active=item
    if not exaudio.vol(math.ceil(math.max(0,math.min(31,cfg.volume))*100/31)) then
        finish(item,"volume_failed");return false,"volume_failed"
    end
    local ok,accepted,reason=pcall(exaudio.play_start,{type=1,content=text,
        cbfnc=function(event,result)
            if event==exaudio.PLAY_DONE then finish(item,result) end
        end})
    if not ok or not accepted then
        local failure=reason or (not ok and tostring(accepted)) or "start_failed"
        finish(item,failure)
        log.warn("task_voice","TTS unavailable; requires tts_pcm firmware")
        return false,failure
    end
    local function check()
        if active~=item then return end
        item.elapsed=item.elapsed+100
        if not item.stopping then
            if not can_play() then M.cancel("call_preemption")
            elseif item.elapsed>=(timeout or cfg.timeout_ms) then M.cancel("playback_timeout","timeout") end
        end
    end
    if active==item then item.timer=sys.timerLoopStart(check,100) end
    log.info("task_voice","TTS_START",text)
    return true
end
return M
