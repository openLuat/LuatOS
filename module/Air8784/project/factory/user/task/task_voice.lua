--[[
@module  task_voice
@summary 任务生效固定短语与接听就绪提示音
@version 1.2
@date    2026.09.29
@author  王世豪
@usage
主动任务只播放/luadb/tv_ok.pcm（任务已生效）；仅接听模式切换发两声短音。
保持原来的任务版本去重、空闲/注册/音频就绪检查与来电抢占。
逐帧发送PCM，不停止MIC、不复位Air1103，退出恢复原音量。
]]
local M={}
local cfg=require "task_voice_config"
local air=require "air1103"
local active,timer,file,check,restore
local started,next_frame,tone_index=0,0,0
local frame_count,byte_count=0,0
local safe_tick
local silence=string.rep(string.char(0),320)
local function now_ms()
    local s,us=mcu.ticks2(0)
    return s*1000+us/1000
end
function M.is_playing() return active==true end
function M.cancel(reason)
    if not active then return end
    active=false
    if timer then sys.timerStop(timer);timer=nil end
    if file then file:close();file=nil end
    local callback=restore;restore=nil
    if callback then pcall(callback) end
    log.info("task_voice",reason or "finished", "frames",frame_count,"pcm_bytes",byte_count,"elapsed_ms",math.floor(now_ms()-started))
end
local function tone_frame(index)
    local position,frequency
    if index<=12 then position=index-1;frequency=880
    elseif index>=23 and index<=34 then position=index-23;frequency=1100
    else return silence end
    local samples={}
    for i=0,159 do
        local n=position*160+i
        local fade=math.min(1,n/160,(1919-n)/160)
        samples[#samples+1]=string.pack("<i2",math.floor(5000*fade*math.sin(2*math.pi*frequency*n/16000)))
    end
    return table.concat(samples)
end
local function tick()
    if not active then return end
    if now_ms()-started>cfg.timeout_ms or not check() or air.is_running() then M.cancel("interrupted");return end
    local data
    if file then
        data=file:read(320)
        if not data then M.cancel("finished");return end
    else
        tone_index=tone_index+1
        if tone_index>44 then M.cancel("finished");return end
        data=tone_frame(tone_index)
    end
    if not air.play_direct(data) then M.cancel("audio failed");return end
    frame_count=frame_count+1;byte_count=byte_count+#data
    next_frame=math.max(next_frame+10,now_ms()-20)
    timer=sys.timerStart(safe_tick,math.max(1,math.ceil(next_frame-now_ms())))
end
function safe_tick()
    local ok,err=pcall(tick)
    if not ok then M.cancel("playback error");log.warn("task_voice",tostring(err)) end
end
function M.start(record,can_play,on_restore)
    if not cfg.enabled or active or not can_play() or air.is_running() or type(air.play_direct)~="function" then return false end
    if record.task then
        file=io.open(cfg.path.."tv_ok.pcm","rb")
        if not file then log.warn("task_voice","missing tv_ok.pcm");return false end
    end
    frame_count,byte_count=0,0
    check,restore=can_play,on_restore
    started=now_ms();next_frame=started+10;tone_index=0
    if not air.set_volume(math.max(0,math.min(31,cfg.volume))) then
        if file then file:close();file=nil end
        restore=nil;return false
    end
    log.info("task_voice", "start", record.task and "tv_ok.pcm" or "receiver beep", "volume",cfg.volume)
    active=true;timer=sys.timerStart(safe_tick,10);return true
end
return M
