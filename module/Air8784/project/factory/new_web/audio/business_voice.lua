-- Remote/configuration speech shares task_voice ownership with call preemption.
local M={}
function M.supported()
    return audio_v2 and type(audio_v2.tts_pcm_start)=="function"
        and type(audio_v2.tts_pcm_read)=="function" and type(audio_v2.tts_pcm_stop)=="function" or false
end
function M.valid_text(text)
    if type(text)~="string" or #text==0 or #text>300 then return false end
    local i,visible=1,false
    while i<=#text do
        local b=text:byte(i);local size,code
        if b<128 then size,code=1,b
        elseif b>=194 and b<=223 then size,code=2,b-192
        elseif b>=224 and b<=239 then size,code=3,b-224
        elseif b>=240 and b<=244 then size,code=4,b-240
        else return false end
        for j=1,size-1 do
            local c=text:byte(i+j)
            if not c or c<128 or c>191 then return false end
            code=code*64+c-128
        end
        if (size==3 and code<2048) or (size==4 and code<65536) or code>1114111
            or (code>=55296 and code<=57343) or code<32 or (code>=127 and code<=159) then return false end
        if code~=32 and code~=160 and code~=12288 and not (code>=8192 and code<=8202)
            and code~=8232 and code~=8233 and code~=8239 and code~=8287 then visible=true end
        i=i+size
    end
    return visible
end
function M.config_text(before,after,reboot)
    local same=require("aircloud_settings").same
    local parts={}
    if not same(before.sip,after.sip) then parts[#parts+1]="SIP参数修改成功" end
    if before.sos_mode~=after.sos_mode then
        parts[#parts+1]="SOS模式已修改为"..(after.sos_mode=="sip" and "SIP模式" or "SIP桥接4G模式")
    end
    local number_fields={"sos_sip_numbers","sos_sip_cc_numbers","sos_sip_cc_peers","sos_sip_cc_map","sos_cc_numbers"}
    for _,key in ipairs(number_fields) do
        if not same(before[key],after[key]) then
            local numbers=after.sos_mode=="sip" and after.sos_sip_numbers or after.sos_sip_cc_numbers
            parts[#parts+1]="SOS号码修改完成，共"..#(numbers or {}).."个号码";break
        end
    end
    for _,field in ipairs({{"volume","音量修改成功"},{"mic_gain","麦克风增益修改成功"}}) do
        if (before.audio or {})[field[1]]~=(after.audio or {})[field[1]] then parts[#parts+1]=field[2] end
    end
    if #parts==0 then return nil end
    if reboot then parts[#parts+1]="等待自动重启后生效" end
    return table.concat(parts,"，")
end
function M.new(adapter)
    local voice=require "task_voice"
    local settings=require "aircloud_settings"
    local copy=require("sos_config").copy
    local api={};local pending,playing
    local boot_pending=adapter.speech_status~=nil
    local registered,ready_pending=false,false
    local registration_epoch=0
    local observed_epoch
    local function observe_registration()
        if not adapter.speech_status then return end
        local current,epoch=adapter.speech_status()
        current=current==true
        if current and (not registered or (epoch~=nil and epoch~=observed_epoch)) then
            registration_epoch=registration_epoch+1
            ready_pending=true
        end
        observed_epoch=epoch
        registered=current
    end
    local function startup_step()
        if playing or voice.is_playing() or not adapter.voice_ready() then return end
        local kind=boot_pending and "boot" or (ready_pending and registered and not settings.pending and "ready")
        if not kind then return end
        local item={kind=kind,epoch=registration_epoch}
        local function consume()
            if kind=="boot" then boot_pending=false
            elseif item.epoch==registration_epoch then ready_pending=false end
        end
        if not M.supported() then
            consume();log.warn("business_voice","STARTUP_SPEECH_SKIPPED",kind,"unsupported");return
        end
        local function can_play()
            observe_registration()
            return adapter.voice_ready() and (kind=="boot" or (registered and not settings.pending))
        end
        playing=item
        local function done(status,reason)
            if playing~=item then return end
            playing=nil
            -- Only preemption retries. Native errors/timeouts are terminal for this notice.
            if status~="cancelled" then consume() end
            log.info("business_voice","STARTUP_SPEECH_END",kind,status,reason)
        end
        local text=kind=="boot" and "开机完成" or "SIP通话已就绪"
        local ok,reason=voice.start_text(text,can_play,adapter.restore_volume,done,15000)
        if not ok and playing==item then
            playing=nil;consume()
            log.warn("business_voice","STARTUP_SPEECH_FAILED",kind,reason)
        end
    end
    function api.changed(before,after)
        if settings.same(before,after) then return end
        pending={before=pending and pending.before or copy(before),after=copy(after),elapsed=0}
    end
    function api.remote(text,notify)
        if not M.supported() then return false,"unsupported_feature" end
        if pending or playing or voice.is_playing() or not adapter.voice_ready() then
            local reason=adapter.voice_busy_reason and adapter.voice_busy_reason()
                or (voice.is_playing() and "announcement_playing") or (pending and "config_announcement_pending") or "audio_not_ready"
            log.warn("business_voice","TTS_BUSY",reason)
            return false,"audio_busy",{busy_reason=reason}
        end
        local voice_config = require "task_voice_config"
        if not voice_config.enabled then return false,"tts_disabled" end
        return voice.start_text(text,adapter.voice_ready,adapter.restore_volume,notify,15000)
    end
    function api.idle() return not pending and not playing and not voice.is_playing() end
    function api.step(ms)
        observe_registration()
        if playing then return end
        if not pending then startup_step();return end
        -- Calls pause the deadline; audio recovery after a call consumes it.
        if not adapter.voice_call_idle() then return end
        pending.elapsed=pending.elapsed+ms
        if pending.elapsed>=15000 or not M.supported() then
            log.warn("business_voice","CONFIG_SPEECH_SKIPPED","timeout or unsupported");pending=nil;return
        end
        if voice.is_playing() or not adapter.voice_ready() then return end
        local item=pending
        local text=M.config_text(item.before,item.after,settings.pending)
        if not text then pending=nil;return end
        pending=nil;playing=item
        local function done(status,reason)
            if playing~=item then return end
            playing=nil
            if status=="cancelled" then
                if pending then pending.before=item.before else pending=item end
            end
            log.info("business_voice","CONFIG_SPEECH_END",status,reason)
        end
        if not voice.start_text(text,adapter.voice_ready,adapter.restore_volume,done,15000-item.elapsed) then
            playing=nil
            log.warn("business_voice","CONFIG_SPEECH_FAILED")
        end
    end
    return api
end
return M
