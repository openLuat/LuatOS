local memdiag = require "sip_mem_diag"
--[[
@module audio_app
@summary Air8606 UART6 Air1103 PCM bridge and audio diagnostics for SIP models.
All playback uses one owner and generation; stopping playback preserves MIC RX.
]]
local M = {}
local perf = require "audio_perf"
local ex_ok, exaudio = pcall(require, "exaudio")
local chip_ok, chip = pcall(require, "air1103")
local cfg = ((_G.project_config or {}).hw or {}).audio or {}
-- Air8606 的 Air1103 电源与功放共用 GPIO73，音频帧经 UART6 传输。
local PIN  = tonumber(cfg.power_gpio) or 73      -- Air1103 供电脚（AUDIOPA_EN）
local UART = tonumber(cfg.uart_id)    or 6
local BAUD = tonumber(cfg.baud)       or 2000000 -- air1103 固定 2M
local volume = math.max(0, math.min(100, tonumber(cfg.play_vol) or 70))
local initialized, initializing = false, false
local suspended, starting = false, false
local owner, generation = nil, 0
local final_call_report = nil
local frames, rx_bytes, bad_frames, last_mic, peak = 0, 0, 0, 0, 0
local mic_rate, fps = nil, 0
local fault = nil
local capture, capture_bytes = nil, 0
-- 自检录音缓冲：仅录音自检分配，结束/取消后释放。
local rec_buff
local function release_record_buffer()
    capture=nil;capture_bytes=0
    local buff=rec_buff;rec_buff=nil
    if buff then buff:free() end
end
local cap_last, cap_gap_max = 0, 0   -- 采集连续性体检（相邻帧最大间隔）
local queue, pending = {}, ""
local input_resampler, output_resampler
local stats = {uplink=0, downlink=0, drops=0}
local diag_busy = false
local diagnostic_session
local audio_hw = require "audio_hw"
local recovery_observation
-- 上行定时器仅作回压重试，下行保持按水位搬运。
local capture_timer, play_timer
local submit_mic
local muted = false
local mic_gap_max = 0
local last_submit,submit_gap_max,input_blocked,input_partial=nil,0,0,0
local uplink_error
local prestart_frames,near_clip_frames=0,0

local function now()
    if mcu and mcu.ticks2 then
        local s, us = mcu.ticks2(0)
        return s * 1000 + (us or 0) / 1000
    end
    return os.time() * 1000
end
local function restore_touch()
    if _G.tp_drv and type(_G.tp_drv.i2c_restore) == "function" then
        pcall(_G.tp_drv.i2c_restore)
    end
end
-- 800Hz/16kHz 测试音的 100ms 波形（3200 字节），每次自检都是同一串
local tone_cache
local function tone_pcm()
    if tone_cache then return tone_cache end
    local chunks={}
    for i=0,1599 do
        chunks[#chunks+1]=string.pack("<h",math.floor(6000*math.sin(2*math.pi*800*i/16000)))
    end
    tone_cache=table.concat(chunks)
    return tone_cache
end
local function signal_error(reason)
    fault = tostring(reason)
    log.error("audio_app", fault)
    sys.publish("AUDIO_ERROR", fault)
    return false, fault
end
local function pcm_peak(data)
    local out = 0
    for i=1,#data-1,16 do out=math.max(out,math.abs(string.unpack("<h",data,i))) end
    return out
end
-- 完整 MIC 帧到达后有界提交；回压时保留尾部，由后续帧或备用定时器重试。
local function on_pcm(data)
    if type(data) ~= "string" or #data ~= 512 then bad_frames=bad_frames+1;return end
    local tick=now()
    if owner=="call" and last_mic>0 then mic_gap_max=math.max(mic_gap_max,tick-last_mic) end
    if recovery_observation then
        local o=recovery_observation
        o.gap=math.max(o.gap,tick-o.last)
        o.last=tick;o.count=o.count+1
    end
    frames, last_mic = frames+1, tick
    -- 削顶诊断不必逐帧精确：MIC 64 帧/秒、每帧 32 次 unpack，全算每秒 2000+ 次 C 调用。
    -- 每 4 帧采一次足够反映电平，减少录音/通话期间的 CPU 抢占。
    if frames % 4 == 0 then peak = pcm_peak(data) end
    if capture then
        -- 采集连续性体检：相邻两帧间隔≈16ms 说明没丢帧；≈32/48ms 说明中间被整帧丢掉。
        if cap_last>0 then cap_gap_max=math.max(cap_gap_max,tick-cap_last) end
        cap_last=tick
        if capture_bytes+#data <= 112640 then
            -- zbuff 走 memcpy，录音期间不产出任何垃圾（字符串累积会让堆一路上涨，
            -- 中途触发完整 GC 停顿 100ms 级，UART6 的 MIC 上行 FIFO 随之溢出丢帧）
            capture:write(data)
            capture_bytes=capture_bytes+#data
        end
    end
    if owner == "call" then
        if peak>=32700 then near_clip_frames=near_clip_frames+1 end
        -- Startup PCM belongs to the waiting period, not the established call.
        if not voip.isRunning() then prestart_frames=prestart_frames+1;return end
        if #queue >= 8 then table.remove(queue,1);stats.drops=stats.drops+1;perf.count("queue_drop") end
        queue[#queue+1]=data
        if submit_mic then submit_mic() end
    end
end
local pcm_rx = require "sipapp_pcm_rx"
local mic_parser=pcm_rx.new(on_pcm)

-- MIC 归属管理（照搬工厂 periph_audio）：工厂里录音页/AI会话/外设页都会抢 chip.feed。
-- 蓝本在模块加载时就常驻覆盖 chip.feed 且从不还原，退出 SIP 后工厂录音的 MIC 解析器
-- 被 SIP 占用 → 「退出 SIP 后录音也异常」。改成「用的时候接管、用完还原」。
local original_feed, sip_feed
local function mic_install()
    if not chip_ok or not mic_parser then return false end
    if chip.feed == sip_feed then return true end
    original_feed = chip.feed
    chip.feed = sip_feed
    return true
end
local function mic_restore()
    if chip_ok and original_feed then chip.feed = original_feed end
end
sip_feed = function(data)
    if type(data)=="string" then
        rx_bytes=rx_bytes+#data
        return mic_parser.feed(data)
    end
end
local function firmware()
    if _G.is_pc then return false,"PC preview has no Air1103 hardware" end
    if not ex_ok then return false,"missing exaudio" end
    if not chip_ok then return false,"missing air1103" end
    for _,n in ipairs({"init","uninit","rebind_rx","on_audio_data","set_rx_enable","reset","set_volume","play_stream_start","play_stream_write","play_stream_stop","get_pending","is_running","get_tx_error"}) do
        if type(chip[n])~="function" then return false,"air1103 missing "..n end
    end
    for _,n in ipairs({"pcmIn","pcmOut","pcmResampler","isRunning"}) do
        if not voip or type(voip[n])~="function" then return false,"voip missing "..n end
    end
    return true
end
function M.check_firmware() return firmware() end
local function set_chip_volume()
    local ok,result=pcall(chip.set_volume,math.floor(volume*31/100))
    return ok and result~=false
end
local function stop_stream()
    if chip_ok then pcall(chip.play_stream_stop,true) end
    restore_touch()
end
local function cancel_playback()
    local report = final_call_report
    final_call_report = nil
    if owner=="call" and not report then perf.stop() end
    generation=generation+1
    owner=nil;submit_mic=nil;queue={};pending=""
    if capture_timer then sys.timerStop(capture_timer); capture_timer=nil end
    if play_timer then sys.timerStop(play_timer); play_timer=nil end
    stop_stream()
    if report then
        local ok, err = pcall(report)
        perf.stop()
        if not ok then log.warn("sip_diag", "final summary failed", tostring(err)) end
    end
end
local function start_stream(kind)
    if not initialized then return false,"audio_not_initialized" end
    if owner then return false,"audio_busy" end
    -- 与工厂录音页 periph_audio、官方 audio_drv 一致：不传 report_tx_error。
    -- 带这个开关时 air1103 会把"任何一次 UART 短写"判定为致命错误并停掉整条下行；
    -- 而 UART6 同时跑 MIC 上行(64 帧/s)与下行(100 帧/s)，工厂固件里 UI 重绘、airlink
    -- 同步 RPC 都会让 TX 缓冲瞬时变满，一次短写就中止 → 听感就是"声音卡住然后没了"。
    local ok,result,why=pcall(chip.play_stream_start,math.floor(volume*31/100))
    restore_touch()
    if not ok or not result then return false,why or "speaker_start_failed" end
    generation=generation+1;owner=kind
    return true,generation
end
local function stream_ok(token)
    return token==generation and owner~=nil and chip.is_running() and not chip.get_tx_error()
end
local function finish_stream(token)
    if token==generation then cancel_playback() end
end
local feed_write_count = 0
local function feed_pcm(token,data)
    local deadline=now()+5000
    -- 录音回放的常态是每帧 512B(16kHz 恒等转换)，这种情况直接整段写进驱动。
    -- 老写法用 data:sub(1,640) 把整帧 clone 一遍，3 秒就是 187 个临时字符串(≈95KB)，
    -- 而且全部压在 10ms 一拍的喂数节拍上 —— 堆一涨就在回放中途触发 GC，
    -- 定时器停摆 → 下行队列被抽干 → 听感就是"卡"。
    if #data<=640 then
        while stream_ok(token) and chip.get_pending()>1920 and now()<deadline do sys.wait(10) end
        if now()>=deadline then return false,"speaker_write_timeout" end
        if not stream_ok(token) then return false,chip.get_tx_error() or "playback_cancelled" end
        chip.play_stream_write(data)
        feed_write_count=feed_write_count+1
        if feed_write_count % 8 == 0 then sys.wait(1) end
        return true
    end
    -- Keep each write small. The driver queue is bounded; do not submit entire recordings.
    for pos=1,#data,640 do
        while stream_ok(token) and chip.get_pending()>1920 and now()<deadline do sys.wait(10) end
        if now()>=deadline then return false,"speaker_write_timeout" end
        if not stream_ok(token) then return false,chip.get_tx_error() or "playback_cancelled" end
        chip.play_stream_write(data:sub(pos,pos+639))
        -- 强制让出：队列水位判断偏松时这里会连写很多帧，一旦 UART TX 变慢就变成
        -- 一整段不让出的循环 —— UART6 的 MIC 上行 ISR 会被饿到 FIFO 溢出(日志里的
        -- uart6 err cr 10)，录音随之丢帧、下行节拍也跟着垮。
        -- 计数必须是模块级的：每次调用只写 512 字节(1 次)，局部计数永远到不了 8。
        feed_write_count=feed_write_count+1
        if feed_write_count % 8 == 0 then sys.wait(1) end
    end
    return true
end
local function drain(token)
    local deadline=now()+3000
    while stream_ok(token) and chip.get_pending()>0 and now()<deadline do sys.wait(10) end
    if not stream_ok(token) then return false,chip.get_tx_error() or "playback_cancelled" end
    if chip.get_pending()>0 then return false,"speaker_drain_timeout" end
    sys.wait(40)
    return true
end

local function pcm_converter(source_rate, target_rate, channels)
    -- V1028 rejects equal-rate conversion; preserve the PCM bytes unchanged.
    if source_rate == target_rate then
        return {reset=function() end, process=function(_, data) return data end}
    end
    return voip.pcmResampler(source_rate, target_rate, channels)
end

local function wait_mic(stage)
    mic_install()
    chip.on_audio_data(on_pcm);chip.set_rx_enable(true)
    mic_parser.reset()
    frames,last_mic=0,0
    local before=rx_bytes
    -- 照搬工厂 periph_audio 的 mic_warmup：先探测 300ms，MIC 已在出帧就不复位；
    -- 无条件复位会每次进 SIP 都打断已在跑的 MIC 上行（Air1103 复位后约 1.4s 才恢复）。
    local waited=0
    while frames==0 and waited<300 do sys.wait(50);waited=waited+50 end
    if frames>0 then
        log.info("audio_app","MIC already running",stage,"no reset")
        return true
    end
    assert(chip.reset(),"Air1103 reset command failed")
    local deadline=now()+6000
    while frames==0 and now()<deadline do sys.wait(50) end
    local p=mic_parser.stats()
    log.info("audio_app","MIC recovery",stage,"rx_bytes",rx_bytes-before,
        "frames",frames,"pending",p.pending,"checksum_errors",p.checksum_errors)
    return frames>0
end

-- ==================== MIC 上行归属：用的时候才接管 ====================
-- 老实现一进 SIP 页就 mic_install() + on_audio_data + set_rx_enable(true)，
-- 然后一直到关窗口才还 chip.feed。也就是说"只是打开 SIP 页看看联系人"，
-- UART6 上就已经常驻 64 帧/秒的 MIC 上行解析，和 10ms 一拍的播放下行
-- 挤同一个 Lua 任务 / 同一个 UART 驱动 —— 录音页(AI 聊天)回放跟着一起卡。
-- 现在改成：预热验证完就 set_rx_enable(false) 恢复轻载；自检录音/通话前再接管。
local preparation
local mic_stopped = false
local rx_on = false      -- 当前是否由本模块接管并解析 MIC 上行
local mic_ok = false     -- 硬件预热是否验证通过（空闲不按 last_mic 判活）

local function mic_idle()
    if chip_ok then
        -- set_rx_enable(false) 只关闭 Lua 解析，芯片仍会持续发送 MIC。
        -- 自检回放/空闲时从源头停上行；下一次 ensure_mic 会复位恢复。
        if type(chip.stop_audio)=="function" then
            local ok, stopped = pcall(chip.stop_audio)
            mic_stopped = ok and stopped == true
        end
        pcall(chip.set_rx_enable,false)
    end
    rx_on=false
end

-- 接管 MIC 上行并等到真的出帧（任务上下文调用）
local function ensure_mic(wait, active)
    wait=wait or sys.wait
    local token = generation
    active = active or function() return token == generation end
    if not active() then return false end
    if rx_on and last_mic>0 and now()-last_mic<3000 then return true end
    if not mic_install() then return false end
    chip.on_audio_data(on_pcm);chip.set_rx_enable(true);rx_on=true
    mic_parser.reset()
    local before=frames
    local waited=0
    while active() and not mic_stopped and frames==before and waited<300 do wait(30);waited=waited+30 end
    if not active() then return false end
    if frames>before then mic_stopped=false;mic_ok=true;return true end
    -- 上行可能已被上一次回放停掉(exaudio.finish → play_stream_stop → 02 01)，复位恢复
    assert(chip.reset(),"Air1103 reset command failed")
    mic_stopped=false
    local deadline=now()+6000
    while active() and frames==before and now()<deadline do wait(50) end
    if not active() then return false end
    mic_ok=frames>before
    return mic_ok
end

-- Call preparation has its own lifetime: tone generations must not cancel it.
function M.prepare_call()
    if preparation then return true end
    if suspended or not initialized or fault or diag_busy or initializing
        or (owner and owner~="tone") then return false,"audio_not_ready" end
    local job={started=now()}
    -- 从振铃到挂断独占语音通路，避免后台播报或录音在通话中重配 Air1103。
    local acquired, reason = audio_hw.acquire(job)
    if not acquired then return false, reason end
    preparation=job
    log.info("audio_app","call MIC prepare")
    sys.taskInit(function()
        local ok,result=pcall(ensure_mic,sys.wait,function() return preparation==job end)
        if preparation~=job then return end
        job.done=true;job.ok=ok and result==true
        job.error=ok and "audio_not_ready" or tostring(result)
        log.info("audio_app",job.ok and "call MIC ready" or "call MIC failed",
            "elapsed_ms",math.floor(now()-job.started))
        if not job.ok then signal_error(job.error) end
    end)
    return true
end
local function cancel_preparation()
    if preparation then
        audio_hw.release(preparation)
        preparation=nil
        log.info("audio_app","call MIC preparation released")
    end
end

-- The lease stays held until the worker has unwound, including cancellation.
local function check_session(session)
    assert(session and diagnostic_session==session and not session.cancelled,"audio_diagnostic_cancelled")
    if session.deadline then assert(now()<session.deadline,"audio_recovery_timeout") end
end
local function diagnostic_wait(ms,session)
    local until_at=now()+ms
    repeat
        check_session(session)
        local remaining=math.min(until_at-now(),session.deadline and session.deadline-now() or 20)
        -- ticks2 has sub-ms precision; the RTOS timer requires integer milliseconds.
        -- Round up only at the wait boundary, preserving the high-resolution clock.
        sys.wait(math.ceil(math.min(20,math.max(1,remaining))))
        check_session(session)
    until now()>=until_at
end

function M.diagnostic_begin()
    if preparation or diag_busy or initializing or (owner and owner~="tone") then return nil,"audio_busy" end
    local supported,reason=firmware()
    if not supported then return nil,reason end
    local session={}
    local accepted,why=audio_hw.acquire(session)
    if not accepted then return nil,why end
    diagnostic_session=session;diag_busy=true
    local cleaned,err=pcall(function()
        cancel_playback();capture=nil;capture_bytes=0
        mic_parser.reset();mic_ok=false
    end)
    if not cleaned then M.diagnostic_end(session,false,err);return nil,tostring(err) end
    return session
end
function M.diagnostic_cancel()
    if diagnostic_session then
        diagnostic_session.cancelled=true
        pcall(cancel_playback);capture=nil;capture_bytes=0
        if diagnostic_session.stop_probe then pcall(diagnostic_session.stop_probe) end
    end
end
function M.diagnostic_end(session,success,reason)
    if diagnostic_session~=session then return false,"audio_session_expired" end
    local cleanup_error
    local function clean(fn,...)
        local ok,err=pcall(fn,...)
        if not ok and not cleanup_error then cleanup_error=tostring(err) end
    end
    if session.stop_probe then clean(session.stop_probe);session.stop_probe=nil end
    if session.power_off then clean(gpio.setup,cfg.recovery_power_pin,cfg.recovery_power_active) end
    recovery_observation=nil;capture=nil;capture_bytes=0
    clean(release_record_buffer)
    clean(cancel_playback);clean(mic_idle);clean(mic_restore)
    clean(chip.on_audio_data,nil)
    clean(restore_touch)
    success=success and not session.cancelled and not cleanup_error
    reason=cleanup_error and ("audio_cleanup: "..cleanup_error) or reason
    mic_ok=success==true
    if success then fault=nil else fault=tostring(reason or "audio_diagnostic_cancelled") end
    diagnostic_session=nil;diag_busy=false
    audio_hw.release(session)
    if fault then pcall(signal_error,fault) end
    return success==true,fault
end

local function reopen_mic(session,power_cycle)
    stop_stream()
    assert(chip.uninit(),"Air1103 UART teardown failed")
    if power_cycle then
        assert(cfg.model=="air1103" and cfg.uart_id==6 and
            type(cfg.recovery_power_pin)=="number" and
            (cfg.recovery_power_active==0 or cfg.recovery_power_active==1),
            "Air1103 power configuration unconfirmed; GPIO untouched")
        session.power_off=true
        gpio.setup(cfg.recovery_power_pin,1-cfg.recovery_power_active)
        diagnostic_wait(300,session)
    end
    local ok,result=pcall(chip.init,6,2000000)
    if power_cycle then
        gpio.setup(cfg.recovery_power_pin,cfg.recovery_power_active)
        session.power_off=false
        diagnostic_wait(800,session)
    end
    assert(ok and result,"Air1103 UART reopen failed")
end

-- Task-only recovery, no success based on init flags or historical counters.
function M.recover(session,progress)
    log.info("audio_recovery", "AUDIO-RECOVERY-FIX1", "integer-ms diagnostic waits")
    local started=now()
    session.deadline=started+30000
    local stage="recover_mic"
    local safe,result=pcall(function()
        check_session(session)
        assert(cfg.model=="air1103" and cfg.uart_id==6,"unsupported audio recovery configuration")
        local setup,why=audio_hw.setup(nil,session);assert(setup,why)
        local levels={
            {"recover_mic","恢复麦克风"}, {"reset_mic","软件复位音频芯片"},
            {"reopen_uart","重开串口"}, {"power_cycle","重启音频芯片"},
        }
        for level,entry in ipairs(levels) do
            stage=entry[1];check_session(session)
            if progress then progress(stage,entry[2]) end
            local t,bytes,count=now(),rx_bytes,frames
            local ok,err=pcall(function()
                if level>=3 then reopen_mic(session,level==4) end
                assert(chip.rebind_rx(),"UART receive callback rebind failed")
                mic_install();mic_parser.reset()
                chip.on_audio_data(on_pcm);chip.set_rx_enable(true);rx_on=true
                if level>=2 then assert(chip.reset(),"Air1103 reset command failed") end
                local baseline=frames
                local startup=math.min(now()+6000,session.deadline)
                while frames==baseline and now()<startup do diagnostic_wait(20,session) end
                assert(frames>baseline,"MIC startup: no new valid frames")
                recovery_observation={count=0,last=now(),gap=0}
                diagnostic_wait(1000,session)
                local o=recovery_observation
                o.gap=math.max(o.gap,now()-o.last)
                assert(o.count>=40 and o.gap<=200,"MIC validation: insufficient frames or gap over 200ms")
            end)
            recovery_observation=nil
            log.info("audio_recovery",stage,"elapsed_ms",math.floor(now()-t),
                "total_ms",math.floor(now()-started),"rx_bytes",rx_bytes-bytes,
                "valid_frames",frames-count,"ok",ok,"reason",ok and "none" or tostring(err))
            check_session(session)
            if ok then
                mic_ok=true;mic_rate=16000
                input_resampler=assert(pcm_converter(16000,8000,1),"MIC resampler unavailable")
                output_resampler=assert(pcm_converter(8000,16000,1),"speaker resampler unavailable")
                initialized=true
                exaudio.sip_voip_start=M.start;exaudio.sip_voip_stop=M.stop_bridge
                return true
            end
            session.failure=stage..": "..tostring(err)
        end
        error(session.failure)
    end)
    session.deadline=nil;recovery_observation=nil
    if not safe then return false,stage..": "..tostring(result) end
    return true
end

-- Must run in a sys task. 初始化音频完全照搬工厂录音 periph_audio 的 audio_setup：
-- audio_hw.setup（幂等收口）+ mic_vol + MIC 预热，不做额外复位/重试/帧率标定。
function M.init()
    if diag_busy then return false,"audio_busy" end
    if initialized then return true end
    if initializing or owner then return false,"audio_busy" end
    local supported,reason=firmware()
    if not supported then return signal_error(reason) end
    initializing=true;initialized=false;fault=nil
    local ok,err=pcall(function()
        local audio_hw = require "audio_hw"
        local ok,err = audio_hw.setup()
        restore_touch()
        assert(ok, err or "audio_hw.setup failed")
        pcall(exaudio.mic_vol, (cfg.mic_vol or 70))
        -- MIC 预热：wait_mic 已照搬工厂 mic_warmup（先探测 300ms，没帧才复位一次）
        local received=wait_mic("warmup")
        if not received then error("MIC warmup failed") end
        mic_ok=true
        -- 预热只是验证硬件；验证完立刻停掉上行解析，别让"SIP 页开着"这件事本身
        -- 给 UART6 加上 64 帧/秒的常驻负载（那会拖慢录音页/回放的 10ms 下行）。
        mic_idle()
        -- 预热下行缓冲：air1103.play_stream_start 会 zbuff.create(94KB)，大块分配在
        -- 1.4MB 堆上会触发强制 GC（实测停顿 100ms 量级，正压在回放起点上，导致
        -- 队列被抽干 + UART6 溢出丢帧）。初始化阶段先建成，正式回放直接复用，
        -- 就不再出现 93KB 分配和那次强制 GC。
        pcall(function()
            if chip.play_stream_start(math.floor(volume*31/100)) then
                chip.play_stream_stop(true)   -- keep_rx: 不动 MIC 上行
            end
        end)
        -- Air1103 固定 16kHz，不做帧率标定
        mic_rate=16000
        input_resampler=assert(pcm_converter(mic_rate,8000,1),"MIC resampler unavailable")
        output_resampler=assert(voip.pcmResampler(8000,16000),"speaker resampler unavailable")
        initialized=true; suspended=false
        exaudio.sip_voip_start=M.start
        exaudio.sip_voip_stop=M.stop_bridge
        log.info("audio_app","audio ready via audio_hw.setup; MIC rate",mic_rate,"mic idle")
    end)
    restore_touch();initializing=false
    if not ok then return signal_error(err) end
    sys.publish("AUDIO_READY",M.diagnostics())
    return true
end
function M.request_init()
    if suspended then return false end
    if fault then return false end -- a fault requires an explicit complete recovery test
    if M.is_ready() then return true end
    if not initializing and not owner and not diag_busy then sys.taskInit(M.init) end
    return false
end
function M.is_ready()
    if not initialized or fault then return false end
    -- 空闲(未接管上行)时按"硬件已验证"判断，接管期间才按帧判活
    if preparation and not preparation.done then return mic_ok end
    if not rx_on then return mic_ok end
    return last_mic>0 and now()-last_mic<3000
end
function M.is_running() return owner=="call" end
function M.is_busy() return preparation~=nil or owner~=nil or initializing or diag_busy end
function M.is_bridge_ok() return owner=="call" and M.is_ready() and chip.is_running() end
function M.get_volume() return volume end
function M.set_mute(on)
    if type(on)~="boolean" then return false,"invalid_mute" end
    muted=on
    return true
end
function M.set_volume(value)
    if value==nil then return volume end
    if type(value)~="number" then return false,"invalid_volume" end
    volume=math.max(0,math.min(100,math.floor(value)))
    if initialized then return set_chip_volume() end
    return true
end
function M.diagnostics()
    local uart_rx = chip_ok and chip.rx_stats and chip.rx_stats() or {}
    return {ready=M.is_ready(),busy=M.is_busy(),initializing=initializing,owner=owner,
        frames=frames,rx_bytes=rx_bytes,rx_read_bytes=uart_rx.read_bytes,rx_discard_bytes=uart_rx.discard_bytes,
        bad_frames=bad_frames,fps=fps,mic_rate=mic_rate,
        peak=peak,volume=volume,error=fault,uart=6,baud=2000000,power_pin=73,
        uplink=stats.uplink,downlink=stats.downlink,drops=stats.drops}
end

local function start_impl(session)
    if diag_busy or initializing then return false,"audio_busy" end
    if owner=="call" then return true end
    -- 恢复 MIC 可能复位芯片，先停掉旧铃音，避免复位时仍在喂下行。
    if owner=="tone" then cancel_playback() end
    -- 通话才接管 MIC 上行（打开 SIP 页不接管）
    local job=preparation
    if job then
        while preparation==job and not job.done do sys.wait(20) end
        if preparation~=job then return false,"audio_cancelled" end
        if not job.ok then return false,job.error end
    end
    if not ensure_mic(nil,job and function() return preparation==job end or nil) then
        if job and preparation~=job then return false,"audio_cancelled" end
        return signal_error("audio_not_ready")
    end
    local rate=session and tonumber(session.sample_rate or 8000) or 8000
    if rate~=8000 then return false,"unsupported_sample_rate" end
    -- 自检可跳过；ensure_mic 与忙状态检查仍保护硬件和音频资源。
    local ok,token=start_stream("call")
    if not ok then return signal_error(token) end
    queue={};pending="";stats={uplink=0,downlink=0,drops=0}
    mic_gap_max=0;last_submit=nil;submit_gap_max=0;input_blocked=0;input_partial=0
    uplink_error=nil;prestart_frames=0;near_clip_frames=0
    input_resampler:reset();output_resampler:reset()
    local uplink=""
    local report_start=now()
    local report_at,previous_up,previous_down=report_start+10000,0,0
    local previous_drops,previous_frames=0,frames
    local pcm_reads,read_empty,read_blocked=0,0,0
    -- Fixed-size per-call counters; no polling, timers, forced GC or frame logs.
    local sched={n=0,gap=0,late=0,gt20=0,gt50=0,gt100=0,body=0,
        pcm_n=0,pcm_max=0,pcm_total=0,empty_run=0,empty_max=0,
        qmin=nil,qmax=nil,last=nil,due=nil}
    local rtp_previous=nil
    local function sched_enter()
        local t=now()
        sched.n=sched.n+1
        if sched.last then sched.gap=math.max(sched.gap,t-sched.last) end
        if sched.due then
            local late=math.max(0,t-sched.due)
            sched.late=math.max(sched.late,late)
            if late>20 then sched.gt20=sched.gt20+1 end
            if late>50 then sched.gt50=sched.gt50+1 end
            if late>100 then sched.gt100=sched.gt100+1 end
        end
        sched.last=t
        return t
    end
    local function sched_report(t)
        log.info("sip_sched","CALL-SCHED-DIAG1","session",token,
            "window_ms",math.floor(t-report_start),"callbacks",sched.n,
            "gap_max_ms",math.floor(sched.gap),"late_max_ms",math.floor(sched.late),
            "late_gt20",sched.gt20,"late_gt50",sched.gt50,"late_gt100",sched.gt100,
            "body_max_us",math.floor(sched.body*1000))
        log.info("sip_sched","pcm","session",token,"reads",sched.pcm_n,
            "read_max_us",math.floor(sched.pcm_max*1000),
            "read_mean_us",sched.pcm_n>0 and math.floor(sched.pcm_total*1000/sched.pcm_n) or "NA",
            "empty_run_max",sched.empty_max,"speaker_q_min",sched.qmin or "NA",
            "speaker_q_max",sched.qmax or "NA")
        sched.n=0;sched.gap=0;sched.late=0;sched.gt20=0;sched.gt50=0;sched.gt100=0
        sched.body=0;sched.pcm_n=0;sched.pcm_max=0;sched.pcm_total=0
        sched.empty_max=sched.empty_run;sched.qmin=nil;sched.qmax=nil
    end
    local function rtp_delta(v,t)
        local function delta(key)
            local prev=rtp_previous and rtp_previous[key]
            local value=v[key]
            if type(prev)~="number" or type(value)~="number" or value<prev then return "NA" end
            return value-prev
        end
        log.info("sip_sched","rtp_delta","session",token,
            "window_ms",rtp_previous and math.floor(t-rtp_previous.time) or "NA",
            "tx",delta("tx_packets"),"rx",delta("rx_packets"),"decoded",delta("decode_frames"))
        rtp_previous={time=t,tx_packets=v.tx_packets,rx_packets=v.rx_packets,decode_frames=v.decode_frames}
    end
    log.info("sip_sched","CALL-SCHED-DIAG1","START","session",token,
        "late_thresholds","overlapping; due measured at timer arm",
        "body","excludes summary logging; includes PCM processing",
        "rtp_arrival_jitter","NA","pcm_internal_queue","NA","uart_hw_error_counter","NA")
    local PLAY_TARGET=1920   -- 下行水位 60ms(320B/10ms)，与官方 audio_drv.play_buffer_ms=60 一致
    if job then log.info("audio_app","call bridge ready","prepare_elapsed_ms",math.floor(now()-job.started)) end
    log.info("audio_app","bridge v7: bounded MIC callback uplink",
        "up_max_frames",4,"up_budget_ms",3,"retry_ms",10,
        "play_first_ms",20,"play_ms",5,"perf",cfg.sip_perf_enabled==true)

    local function bridge_fail(why)
        if generation~=token then return end
        if capture_timer then sys.timerStop(capture_timer); capture_timer=nil end
        if play_timer then sys.timerStop(play_timer); play_timer=nil end
        finish_stream(token)
        signal_error(why)
        sys.publish("AUDIO_BRIDGE_FAILED",tostring(why))
    end

    -- 在 Lua 接收回调里提交 PCM，不等待下一条定时器消息。
    -- 每次最多四帧，帧间检查 3ms 预算；单次原生调用不能被此预算抢占。
    local capture_dispatch, play_dispatch
    local pumping=false
    local function pump_uplink()
        if owner~="call" or generation~=token or not voip.isRunning() then return end
        local measured=perf.tick("capture")
        local pcm_started=perf.begin("pcm_up")
        local started=now()
        for _=1,4 do
            if #uplink==0 and #queue>0 then
                uplink=input_resampler:process(table.remove(queue,1)) or ""
            end
            if #uplink==0 then break end
            local samples=tonumber(voip.pcmIn(muted and string.rep("\0",#uplink) or uplink)) or 0
            local used=math.max(0,math.min(#uplink//2,math.floor(samples)))*2
            if used==0 then
                input_blocked=input_blocked+1
                break
            end
            local tick=now()
            if last_submit then submit_gap_max=math.max(submit_gap_max,tick-last_submit) end
            last_submit=tick
            local partial=used<#uplink
            if partial then input_partial=input_partial+1 end
            uplink=uplink:sub(used+1);stats.uplink=stats.uplink+used
            if partial or now()-started>=3 then break end
        end
        perf.finish("pcm_up",pcm_started)
        perf.finish("capture",measured)
    end
    local function submit()
        if pumping or owner~="call" or generation~=token then return end
        pumping=true
        local good,why=pcall(pump_uplink)
        pumping=false
        if not good then uplink_error=tostring(why);bridge_fail(uplink_error) end
    end
    local function capture_tick()
        submit()
        if owner~="call" or generation~=token then return end
        capture_timer=assert(sys.timerStart(capture_dispatch,10),"capture timer unavailable")
    end

    -- 下行：按水位取 voip.pcmOut -> 8k->16k -> 交给驱动(驱动自己保持 10ms/帧、空队列补静音)
    -- 水位上限 PLAY_TARGET+640 是官方做法：既保证不欠载，又不会把通话延迟越堆越大。
    local quiet = _G.SIP_DIAG_QUIET_CALL == true
    local function report_call(final)
        local report_now=now()
        sched_report(report_now)
        perf.report(token, final)
        local uart_rx=chip.rx_stats and chip.rx_stats() or {}
        log.info("sip_health","perf-v1","session",token,"lua_kb",math.floor(collectgarbage("count")),
            "rx_read",uart_rx.read_bytes or 0,"rx_discard",uart_rx.discard_bytes or 0,"mic_frames",frames)
        log.info("audio_app","bridge", "window_ms",math.floor(report_now-report_start),
            "drops_delta",stats.drops-previous_drops,"mic_frames_delta",frames-previous_frames, "mic_peak",peak,"mic_age_ms",math.floor(now()-last_mic),
            "muted",muted,"up_bytes",stats.uplink-previous_up,
            "down_bytes",stats.downlink-previous_down,"mic_queue",#queue,"drops",stats.drops)
        log.info("audio_app","downlink", "session",token,"pcm_reads",pcm_reads,
            "empty",read_empty,"blocked",read_blocked,"speaker_pending",chip.get_pending(),
            "speaker_running",chip.is_running(),"tx_error",chip.get_tx_error() or "none")
        log.info("audio_app","uplink timing","mic_gap_max_ms",math.floor(mic_gap_max),
            "submit_gap_max_ms",math.floor(submit_gap_max),"input_blocked",input_blocked,
            "input_partial",input_partial,"uplink_pending_bytes",#uplink,
            "prestart_frames",prestart_frames,"near_clip_frames",near_clip_frames)
        mic_gap_max,submit_gap_max,input_blocked,input_partial=0,0,0,0
        local p=mic_parser.stats()
        log.info("audio_app","MIC RX","raw_bytes",rx_bytes,"valid_frames",frames,
            "discarded",p.discarded,"checksum_errors",p.checksum_errors,"pending",p.pending)
        if type(voip.stats)=="function" then
            local ok,v=pcall(voip.stats)
            if ok and type(v)=="table" then
                rtp_delta(v,report_now)
                log.info("audio_app","rtp", "session",token,"tx",v.tx_packets,"rx",v.rx_packets,
                    "rx_bytes",v.rx_bytes,"tx_errors",v.tx_errors)
                log.info("audio_app","rtp_decode", "parse_fail",v.rx_parse_fail,
                    "bad_payload",v.rx_bad_payload,"decode_drop",v.rx_decode_dropped,
                    "decode_frames",v.decode_frames,"rx_frames",v.rx_frames,
                    "jb_played",v.jb_played,"jb_silence",v.jb_silence)
            else log.warn("audio_app","voip.stats unavailable",tostring(v)) end
        end
        pcm_reads,read_empty,read_blocked=0,0,0
        previous_up,previous_down=stats.uplink,stats.downlink
        previous_drops,previous_frames=stats.drops,frames
        report_start=report_now;report_at=report_now+10000
    end
    if quiet then
        log.info("sip_diag", "CALL-LUA-QUIET1", "session", token,
            "periodic summaries deferred; final counters cover whole bridge session")
        final_call_report = function()
            log.info("sip_diag", "CALL-LUA-QUIET1", "FINAL", "session", token,
                "bridge stopped; queue watermark counters retained; current queue already released")
            report_call(true)
        end
    end

    -- CALL-WINDOW-DIAG1: bounded last 60 windows, no timer and no in-call output.
    local windows, window_count = {}, 0
    local window_start, window_due = now(), now()+10000
    local wg,wlate,wmin,wmax=0,0,nil,nil
    local previous={}
    local function save_window(final)
        local t=now()
        if t-window_start<1 then return end
        local v={}
        if type(voip.stats)=="function" then
            local ok,value=pcall(voip.stats)
            if ok and type(value)=="table" then v=value end
        end
        local dp,ds=perf.down_counts()
        local values={stats.uplink,stats.downlink,pcm_reads,read_empty,
            sched.gt50,dp,ds,v.rx_packets,v.decode_frames,v.tx_packets}
        window_count=window_count+1
        local slot=(window_count-1)%60+1
        local row=windows[slot] or {}
        windows[slot]=row
        row[1]=window_count;row[2]=math.floor(t-window_start)
        row[3]=math.floor(t-report_start);row[4]=math.floor(wg)
        row[5]=math.floor(wlate);row[6]=wmin or "NA";row[7]=wmax or "NA"
        for i=1,10 do
            local a,z=values[i],previous[i]
            row[7+i]=type(a)=="number" and type(z)=="number" and a>=z and a-z or "NA"
            previous[i]=a
        end
        row[18]=final and "tail" or "full"
        window_start=t;window_due=t+10000;wg=0;wlate=0;wmin=nil;wmax=nil
    end
    -- Local counters start at zero; native RTP has no reliable pre-start baseline.
    for i=1,7 do previous[i]=0 end
    local whole_report=final_call_report
    if quiet then final_call_report=function()
        save_window(true)
        log.info("sip_window","CALL-WINDOW-DIAG1","session",token,
            "windows",window_count,"overwritten",math.max(0,window_count-60),
            "columns=seq,ms,end_ms,gap_ms,late_ms,qmin,qmax,up,down,reads,empty,late50,pcm,silence,rtp_rx,decoded,rtp_tx,kind; first RTP delta NA; tail sampled after stop")
        for n=math.max(1,window_count-59),window_count do
            log.info("sip_window","session",token,table.concat(windows[(n-1)%60+1],","))
        end
        if whole_report then whole_report() end
    end end
    local function play_tick()
        if owner~="call" or generation~=token then return end
        local before=sched.last
        local due=sched.due
        local sched_started=sched_enter()
        if before then wg=math.max(wg,sched_started-before) end
        if due then wlate=math.max(wlate,math.max(0,sched_started-due)) end
        local measured=perf.tick("play")
        if not stream_ok(token) then bridge_fail(chip.get_tx_error() or "speaker_stopped"); return end
        if not M.is_ready() then
            local p=mic_parser.stats()
            log.error("audio_app","MIC lost detail","raw_rx_total",rx_bytes,"frames",frames,
                "parser_pending",p.pending,"discarded",p.discarded,"checksum_errors",p.checksum_errors)
            bridge_fail("MIC stream lost"); return
        end
        local pcm_started=perf.begin("pcm_down")
        if voip.isRunning() then
            local speaker_q=chip.get_pending()
            wmin=wmin and math.min(wmin,speaker_q) or speaker_q
            wmax=wmax and math.max(wmax,speaker_q) or speaker_q
            sched.qmin=sched.qmin and math.min(sched.qmin,speaker_q) or speaker_q
            sched.qmax=sched.qmax and math.max(sched.qmax,speaker_q) or speaker_q
            if speaker_q<PLAY_TARGET+640 then
                pcm_reads=pcm_reads+1
                local read_started=now()
                local pcm=voip.pcmOut(160)
                local read_ms=now()-read_started
                sched.pcm_n=sched.pcm_n+1
                sched.pcm_max=math.max(sched.pcm_max,read_ms)
                sched.pcm_total=sched.pcm_total+read_ms
                if pcm and #pcm>0 and #pcm%2==0 then
                    sched.empty_run=0
                    local output=output_resampler:process(pcm)
                    if output and #output>0 then chip.play_stream_write(output) end
                    stats.downlink=stats.downlink+#pcm
                else
                    read_empty=read_empty+1
                    sched.empty_run=sched.empty_run+1
                    sched.empty_max=math.max(sched.empty_max,sched.empty_run)
                end
            else
                read_blocked=read_blocked+1
            end
        end
        perf.finish("pcm_down",pcm_started)
        sched.body=math.max(sched.body,now()-sched_started)
        if quiet and now()>=window_due then save_window(false) end
        if not quiet and now()>=report_at then report_call(false) end
        perf.finish("play",measured)
        sched.due=now()+5
        play_timer=assert(sys.timerStart(play_dispatch,5),"play timer unavailable")
    end


    report_start=perf.start(cfg.sip_perf_enabled==true);report_at=report_start+10000
    -- One-shot callbacks are removed before running. Clear only this session's
    -- handle; failed work/rearming must stop the other half of the bridge too.
    capture_dispatch = function()
        if owner~="call" or generation~=token then return end
        capture_timer=nil
        local good,why=pcall(capture_tick)
        if not good then bridge_fail(tostring(why)) end
    end
    play_dispatch = function()
        if owner~="call" or generation~=token then return end
        play_timer=nil
        local good,why=pcall(play_tick)
        if not good then bridge_fail(tostring(why)) end
    end
    submit_mic=submit
    local scheduled,why=pcall(function()
        capture_timer=assert(sys.timerStart(capture_dispatch,10),"capture timer unavailable")
        sched.due=now()+20
        play_timer=assert(sys.timerStart(play_dispatch,20),"play timer unavailable")
    end)
    if not scheduled then bridge_fail(tostring(why));return false,tostring(why) end
    return true
end
function M.start(session)
    if suspended or starting or not initialized then return false, "audio_not_ready" end
    starting = true
    local ok, result, err = pcall(start_impl, session)
    starting = false
    if not ok then error(result, 0) end
    return result, err
end

function M.stop()
    cancel_preparation()
    if diag_busy then return true end -- diagnostic worker owns cleanup until it exits
    if owner=="call" or owner=="tone" then cancel_playback() end
    muted=false
    mic_idle()     -- 停掉上行解析，空闲时不占 UART6
    mic_restore()  -- 归还 chip.feed，让工厂录音等其它消费方恢复（否则退出 SIP 后录音异常）
    return true
end
M.stop_bridge=M.stop

function M.shutdown()
    suspended = true
    cancel_preparation()
    cancel_playback()
    M.diagnostic_cancel()
    local waited = 0
    while initializing or diag_busy or starting do
        if waited >= 15000 then error("SIP audio worker did not stop") end
        sys.wait(20); waited = waited + 20
    end
    cancel_playback()
    M.stop()
    release_record_buffer()
    initialized=false; suspended=true; mic_ok=false; fault=nil; last_mic=0
    mic_parser.reset()
    if chip_ok then chip.on_audio_data(nil) end
    return true
end

-- The application owns tones too: stop never issues STOP-MIC or resets the chip.
local function play_tone(names,loop)
    if suspended or diag_busy or initializing or owner=="call" then return false,"audio_busy" end
    if not initialized then return false,"audio_not_ready" end
    if owner=="tone" then cancel_playback() end
    local ok,token=start_stream("tone")
    if not ok then return false,token end
    -- 铃音与来电共用此入口。避免定时器回调一次读入约 60KB PCM，
    -- 将文件读取放进播放任务，按 640 字节喂入并保留取消检查。
    sys.taskInit(function()
        -- taskInit 会立即运行到首次让出，先离开触发铃音的事件回调。
        sys.wait(1)
        if token~=generation then return end
        local active_file
        local good,why=memdiag.call("tone.task",function()
            repeat
                for _,name in ipairs(names) do
                    if token~=generation then return end
                    active_file=assert(io.open("/luadb/air1103_"..name..".pcm","rb"),"missing tone: "..name)
                    local total=0
                    while token==generation do
                        local data=active_file:read(640)
                        if not data or #data==0 then break end
                        total=total+#data
                        assert(total<=64000,"invalid tone: "..name)
                        local accepted,reason=feed_pcm(token,data)
                        if not accepted then
                            if token==generation then error(reason) end
                            break
                        end
                    end
                    active_file:close();active_file=nil
                    if token~=generation then return end
                    assert(total>0,"empty tone: "..name)
                end
            until not loop or token~=generation
            if token==generation then local drained,reason=drain(token);assert(drained,reason) end
        end)
        if active_file then active_file:close() end
        if token==generation then
            finish_stream(token)
            if not good then signal_error(why) end
        end
    end)
    return true
end
function M.play_ringback_loop() return play_tone({"busy","gap"},true) end
function M.play_ringback() return play_tone({"busy","gap"},false) end
function M.play_hangup() return play_tone({"hangup"},false) end
function M.stop_ringback()
    if owner=="tone" then cancel_playback() end
    return true
end

-- Called only by audio_diag's background task. The lock covers initialization,
-- recording and playback; there is no window in which a call may steal the stream.
function M.diagnostic_run(kind,progress,session)
    if not session or session~=diagnostic_session or owner or initializing then return false,"audio_busy" end
    if kind~="tone" and kind~="record" then return false,"invalid_test" end
    diag_busy=true
    local function wait(ms) diagnostic_wait(ms,session) end
    local token
    local submitted, started = 0, now()
    local function report(stage,detail)
        log.info("audio_diag", kind, stage, detail)
        if progress then progress(stage,detail,M.diagnostics()) end
    end
    local function submit(data)
        local ok,why=feed_pcm(token,data)
        assert(ok,why)
        submitted=submitted+#data
    end
    -- ===== 回放体检（只在自检期间跑，开销可忽略）=====
    -- 目的：把"卡"归到三类之一，不再靠猜：
    --   pending_min==0 且 probe_gap_max 很大 → Lua 被别的任务占住，下行被抽干
    --   pending_min==0 且 probe_gap 正常(≈10ms) → 喂数节奏跟不上，属播放侧逻辑
    --   pending_min 始终>0                    → 播放侧没问题，卡在录音内容(采集丢帧)或芯片
    --   capture_gap_max≈16ms 说明录音连续；≈32ms/48ms 说明采集中间丢了整帧
    local probe_timer, probe_on
    local probe = {pending_min=nil, pending_max=0, samples=0, gap_max=0, draining=false}
    local probe_last = 0
    local function probe_stop()
        probe_on=false
        if probe_timer then sys.timerStop(probe_timer); probe_timer=nil end
    end
    local function probe_tick()
        if not probe_on then return end
        local t=now()
        if probe_last>0 then
            local gap=t-probe_last
            if gap>probe.gap_max then
                probe.gap_max=gap
                -- 记录这次长间隔期间本模块又提交了多少字节：
                -- 增量很大 → 是 feed_pcm 自己连写不让出；增量≈0 → 是别的任务占住的 Lua。
                probe.slow_delta=submitted-(probe.last_sub or submitted)
            end
        end
        probe_last=t; probe.last_sub=submitted
        -- 只在"喂数阶段"统计队列水位：起播前和 drain 收尾时队列必然是 0，
        -- 把它们算进 pending_min 会得出假的"欠载"结论。
        if not probe.draining and submitted>0 then
            local p=chip.get_pending() or 0
            if probe.pending_min==nil or p<probe.pending_min then probe.pending_min=p end
            if p>probe.pending_max then probe.pending_max=p end
        end
        probe.samples=probe.samples+1
    end
    local function probe_start()
        probe_on=true
        -- 用 timerLoopStart 复用一个定时器：每 10ms 重建单次定时器会把定时器池耗到
        -- "luat_timer_start: no free timer, create new"（日志里已经出现了）。
        probe_timer=sys.timerLoopStart(probe_tick,10)
    end
    session.stop_probe=probe_stop
    local success,reason=pcall(function()
        check_session(session)
        report("validating","验证录放音")
        assert(ensure_mic(wait),"MIC stream unavailable")
        if kind=="tone" then
            -- 放音期间不需要 MIC：停掉上行解析，UART6 只剩 10ms 一帧的下行。
            mic_idle()
            report("playing","播放 3 秒测试音，请确认喇叭声音清晰")
            log.info("audio_diag","PCM format",16000,16,1,"volume",volume,"chip_volume",math.floor(volume*31/100))
            probe_start()
            local ok,id=start_stream("diagnostic");assert(ok,id);token=id
            -- 波形只算一次：1600 次 math.sin + string.pack 每次自检重跑，
            -- 造出 1600 个临时短串，堆一涨就在喂数中途触发完整 GC。
            local pcm=tone_pcm()
            for i=1,30 do
                submit(pcm)
                -- 每次 submit 是 5 段 640B 的 UART6 下行写，30 次连写就是几百毫秒不让出，
                -- 而这段时间 lv_timer_handler 跑不了、触摸帧环会被挤爆。逐次让一拍。
                -- 芯片队列一次攒满 3 秒，且 feed_pcm 自带 1920B 水位闸，不会欠载。
                if i<30 then sys.wait(1) end
            end
        else
            report("recording","请说话：录制 3 秒，随后自动回放")
            -- 先让 UI 把状态刷完：report 会触发 LVGL 重排长文本 + fskv 读，
            -- 压在录音起点上就是开头几帧被顶掉。
            wait(60)
            -- 录音前把垃圾收干净，这 3 秒内堆不再增长，也就不会中途触发完整 GC。
            collectgarbage("collect")
            wait(20)
            if not rec_buff then
                local created_ok,created=pcall(zbuff.create,112640,0,zbuff.HEAP_AUTO)
                rec_buff=created_ok and created or nil
            end
            assert(rec_buff,"record buffer alloc failed")
            rec_buff:clear(0);rec_buff:used(0)
            local t,n=now(),frames
            capture=rec_buff;capture_bytes=0;cap_last=0;cap_gap_max=0
            wait(3000)
            capture=nil
            local bytes=capture_bytes
            local measured=(frames-n)*1000/math.max(1,now()-t)
            local rate
            if measured>=48 and measured<=76 then rate=16000
            elseif measured>=24 and measured<=39 then rate=8000
            else error("MIC frame rate unstable during recording") end
            assert(bytes>0,"no_recorded_pcm")
            assert(cap_gap_max<=200 and now()-last_mic<=200,"MIC recording gap over 200ms")
            report("replaying","正在回放录音，请确认声音内容、速度和清晰度")
            log.info("audio_diag","record captured", "bytes",bytes,"rate",rate,"frames",math.ceil(bytes/512))
            local resampler=assert(pcm_converter(rate,16000),"record resampler unavailable")
            -- 回放期间不需要 MIC：停掉上行解析，UART6 只剩 10ms 一帧的下行。
            mic_idle()
            -- 再把"正在回放"这一刷让出去，否则起播瞬间的喂数被 LVGL 挤掉，
            -- 芯片 DAC 缓冲被掏空，开头就是一段卡顿。
            wait(80)
            probe_start()
            local ok,id=start_stream("diagnostic");assert(ok,id);token=id
            local total=math.ceil(bytes/512)
            for i=0,total-1 do
                local off=i*512
                local output=resampler:process(rec_buff:toStr(off,math.min(512,bytes-off)))
                if output and #output>0 then submit(output) end
            end
        end
        -- Air1103 only consumes complete 320-byte frames. Pad the final fragment.
        local remainder=submitted%320
        if remainder~=0 then submit(string.rep("\0",320-remainder)) end
        -- 喂数结束，进入排空阶段：此后队列降到 0 是正常的，不再计入 pending_min。
        probe.draining=true
        local drained,why=drain(token);assert(drained,why)
        log.info("audio_diag","host playback drained", "pcm_bytes",submitted,
            "pending",chip.get_pending(),"tx_error",chip.get_tx_error() or "none",
            "elapsed_ms",math.floor(now()-started))
        probe_stop()
        log.info("audio_diag","REPLAY PROBE",
            "pending_min",probe.pending_min or -1,"pending_max",probe.pending_max,
            "samples",probe.samples,"lua_gap_max_ms",math.floor(probe.gap_max),
            "gap_delta_bytes",probe.slow_delta or -1,
            "capture_gap_max_ms",math.floor(cap_gap_max),
            "lua_mem_kb",math.floor(collectgarbage("count")))
        log.info("audio_diag","UART submission is not a chip acknowledgement or proof of audible sound")
    end)
    probe_stop()  -- 失败路径也要收，否则体检定时器会一直自转
    release_record_buffer()
    if token then finish_stream(token) end
    mic_idle()   -- 自检结束回到轻载，别让 SIP 页开着就一直占着 MIC 上行
    session.stop_probe=nil;restore_touch()
    if not success then return signal_error(reason) end
    return true,M.diagnostics()
end
function M.selftest()
    -- Keep require separate for Luatools' static dependency scanner.
    local diag = require "sph_audio_diag"
    return diag.start("tone")
end
return M
