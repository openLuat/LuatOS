-- Local call announcements on Air1103, using the same native PCM TTS as 8786.
-- Cancellation retains ownership until the native worker actually releases it.
local M={}
local exaudio
local task_voice=require "task_voice"
local current
function M.log_support()
    local missing={}
    for _,name in ipairs({"tts_pcm_start","tts_pcm_read","tts_pcm_stop"}) do
        if not audio_v2 or type(audio_v2[name])~="function" then missing[#missing+1]="audio_v2."..name end
    end
    if #missing>0 then
        log.error("call_voice","TTS_CAPABILITY_MISSING",table.concat(missing,","))
        return false
    end
    log.info("call_voice","TTS_CAPABILITY_OK")
    return true
end
local reasons={peer_hangup="对方挂断",local_hangup="我方主动挂断",
    peer_cancel="对方取消来电",call_failed="呼叫失败",socket_closed="网络断开",timeout="呼叫超时"}
function M.hangup_text(reason) return reasons[reason] or "已挂断" end
function M.is_busy() return current~=nil end
function M.cancel()
    if current and not current.stopping then
        current.stopping=true
        exaudio.play_stop({type=1})
    end
end
-- Must run in a sys task. Never start media over a still-running TTS worker.
function M.prepare()
    M.cancel()
    task_voice.cancel("call preemption")
    for _=1,250 do
        if not current and not task_voice.is_playing() then return true end
        sys.wait(20)
    end
    log.error("call_voice","TTS stop timeout; audio remains reserved")
    return false
end
function M.speak(text,valid)
    if not M.prepare() then log.warn("call_voice","TTS_SKIPPED","audio not released",text);return false end
    if valid and not valid() then log.info("call_voice","TTS_SKIPPED","call changed",text);return false end
    exaudio=exaudio or require "exaudio"
    task_voice.cancel("call announcement")
    local item={};current=item
    log.info("call_voice","TTS_START",text)
    local ok,accepted,reason=pcall(exaudio.play_start,{type=1,content=text,
        cbfnc=function(event,result)
            if event==exaudio.PLAY_DONE and current==item then
                item.result=result
                current=nil
                if result==nil or result=="done" then log.info("call_voice","TTS_DONE",text)
                else log.warn("call_voice","TTS_PLAY_FAILED",result,text) end
            end
        end})
    if not ok or not accepted then
        if current==item then current=nil end
        log.warn("call_voice","TTS_START_FAILED",reason or accepted,text)
        return false
    end
    for _=1,750 do
        if current~=item then return not item.stopping and (item.result==nil or item.result=="done") end
        if valid and not valid() then M.cancel() end
        sys.wait(20)
    end
    M.cancel()
    log.warn("call_voice","announcement timeout")
    return false
end
-- SIP_CC media bypasses Air1103. Announce the whole bridged call only once,
-- even when both legs dial/connect/disconnect independently.
local legs={sip="sip_idle",cc="cc_idle"}
local bridge_generation=0
local bridge_worker=false
local bridge_text
local function bridge_idle() return legs.sip=="sip_idle" and legs.cc=="cc_idle" end
function M.bridge_state(leg,state)
    if legs[leg]==state then return end
    local was_idle=bridge_idle()
    legs[leg]=state
    local text
    if was_idle and not bridge_idle() then
        text=(state=="sip_incoming" or state=="cc_ringing") and "收到来电" or "正在拨号"
    elseif not was_idle and bridge_idle() then text="已挂断" end
    if not text then return end
    bridge_generation=bridge_generation+1
    bridge_text=text
    M.cancel()
    if bridge_worker then return end
    bridge_worker=true
    sys.taskInit(function()
        local audio=require "exaudio"
        local cfg=require "sip_config"
        while bridge_text do
            local generation=bridge_generation
            local pending=bridge_text;bridge_text=nil
            if not M.prepare() then break end
            audio.vol(math.ceil((cfg.air1103_volume or 20)*100/31))
            M.speak(pending,function()return generation==bridge_generation end)
        end
        if M.prepare() then
            local enabled=require("cc_bridge").get_state().local_audio
            audio.vol(enabled and 35 or 0)
        end
        bridge_worker=false
    end)
end
return M
