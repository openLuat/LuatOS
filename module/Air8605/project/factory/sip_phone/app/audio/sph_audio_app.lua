--[[
@module audio_app
@summary Air8605 UART6 Air1103 PCM bridge and isolated audio diagnostics.
UART3 belongs to Airlink. This module never probes or reconfigures other UARTs.
All playback uses one owner and generation; stopping playback preserves MIC RX.
]]
local M = {}
local ex_ok, exaudio = pcall(require, "exaudio")
local chip_ok, chip = pcall(require, "air1103")
local cfg = ((_G.project_config or {}).hw or {}).audio or {}
local volume = math.max(0, math.min(100, tonumber(cfg.play_vol) or 70))
local initialized, initializing = false, false
local owner, generation = nil, 0
local frames, rx_bytes, bad_frames, last_mic, peak = 0, 0, 0, 0, 0
local mic_rate, fps = nil, 0
local fault = nil
local capture, capture_bytes = nil, 0
-- 录音缓冲（zbuff，跨次复用）
local rec_buff
local cap_last, cap_gap_max = 0, 0   -- 采集连续性体检（相邻帧最大间隔）
local queue, pending = {}, ""
local input_resampler, output_resampler
local stats = {uplink=0, downlink=0, drops=0}
local diag_busy = false
-- 通话桥的两个搬运定时器（对齐官方 module/Air8784/demo/ASR_voice_ctrl_SIP/audio_drv.lua）
local capture_timer, play_timer
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
-- 【通话卡顿根因】串口接收回调里绝不做媒体搬运。
-- 官方 audio_drv.lua 的注释写得很明确：「串口回调只入队，重采样仍在独立定时器执行」。
-- 原实现在这里直接 pump_uplink -> 16k->8k 重采样 + voip.pcmIn(RTP 打包 + UDP 发送)：
-- 一次回调就可能占住 Lua 任务几十毫秒，导致（1）下一个 16ms 的 MIC 帧被 UART 缓冲顶掉，
-- （2）air1103 驱动 10ms 一帧的下行喂数节拍被推迟，芯片 DAC 缓冲掏空 → 通话"卡"。
-- 现在回调里只入队（上限 8 帧 = 128ms），搬运全部移到 capture_tick 定时器。
local function on_pcm(data)
    if type(data) ~= "string" or #data ~= 512 then bad_frames=bad_frames+1;return end
    local tick=now()
    if owner=="call" and last_mic>0 then mic_gap_max=math.max(mic_gap_max,tick-last_mic) end
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
        if #queue >= 8 then table.remove(queue,1);stats.drops=stats.drops+1 end
        queue[#queue+1]=data
    end
end
local pcm_rx = require "sph_sipapp_pcm_rx"
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
    for _,n in ipairs({"init","uninit","on_audio_data","set_rx_enable","reset","set_volume","play_stream_start","play_stream_write","play_stream_stop","get_pending","is_running","get_tx_error"}) do
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
    generation=generation+1
    owner=nil;queue={};pending=""
    if capture_timer then sys.timerStop(capture_timer); capture_timer=nil end
    if play_timer then sys.timerStop(play_timer); play_timer=nil end
    stop_stream()
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
    -- 录音回放的常态是每帧 512B(16kHz 恒等转换)，这种情况直接整段写进驱动。
    -- 老写法用 data:sub(1,640) 把整帧 clone 一遍，3 秒就是 187 个临时字符串(≈95KB)，
    -- 而且全部压在 10ms 一拍的喂数节拍上 —— 堆一涨就在回放中途触发 GC，
    -- 定时器停摆 → 下行队列被抽干 → 听感就是"卡"。
    if #data<=640 then
        while stream_ok(token) and chip.get_pending()>1920 do sys.wait(10) end
        if not stream_ok(token) then return false,chip.get_tx_error() or "playback_cancelled" end
        chip.play_stream_write(data)
        feed_write_count=feed_write_count+1
        if feed_write_count % 8 == 0 then sys.wait(1) end
        return true
    end
    -- Keep each write small. The driver queue is bounded; do not submit entire recordings.
    for pos=1,#data,640 do
        while stream_ok(token) and chip.get_pending()>1920 do sys.wait(10) end
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
local rx_on = false      -- 当前是否由本模块接管并解析 MIC 上行
local mic_ok = false     -- 硬件预热是否验证通过（空闲不按 last_mic 判活）

local function mic_idle()
    if chip_ok then pcall(chip.set_rx_enable,false) end
    rx_on=false
end

-- 接管 MIC 上行并等到真的出帧（任务上下文调用）
local function ensure_mic()
    if rx_on and last_mic>0 and now()-last_mic<3000 then return true end
    if not mic_install() then return false end
    chip.on_audio_data(on_pcm);chip.set_rx_enable(true);rx_on=true
    mic_parser.reset()
    local before=frames
    local waited=0
    while frames==before and waited<300 do sys.wait(30);waited=waited+30 end
    if frames>before then mic_ok=true;return true end
    -- 上行可能已被上一次回放停掉(exaudio.finish → play_stream_stop → 02 01)，复位恢复
    assert(chip.reset(),"Air1103 reset command failed")
    local deadline=now()+6000
    while frames==before and now()<deadline do sys.wait(50) end
    mic_ok=frames>before
    return mic_ok
end

local function reopen_mic(power_cycle)
    -- Stop the speaker before uninit so it cannot issue STOP-MIC during teardown.
    stop_stream()
    assert(chip.uninit(),"Air1103 UART teardown failed")
    if power_cycle then
        gpio.setup(73,0)
        sys.wait(300)
    end
    -- Bind UART6 before powering the chip back on; UART3 belongs to Airlink.
    local ok,result=pcall(chip.init,6,2000000)
    if power_cycle then
        gpio.setup(73,1)
        sys.wait(800)
    end
    assert(ok and result,"Air1103 UART reopen failed")
    chip.on_audio_data(on_pcm);chip.set_rx_enable(true)
end

-- Must run in a sys task. 初始化音频完全照搬工厂录音 periph_audio 的 audio_setup：
-- audio_hw.setup（幂等收口）+ mic_vol + MIC 预热，不做额外复位/重试/帧率标定。
function M.init()
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
        -- 录音缓冲在初始化时建好并跨次复用：zbuff.create 对 >=64KB 的申请会主动
        -- 连做两次完整 GC（源码里的 "create large size ... trigger force GC"），
        -- 放在录音起点上就是一次 100ms 级停顿。这里建一次，以后只 clear。
        if not rec_buff and type(zbuff)=="table" and type(zbuff.create)=="function" then
            local created_ok,created=pcall(zbuff.create,112640,0,zbuff.HEAP_AUTO)
            rec_buff=created_ok and created or nil
        end
        -- Air1103 固定 16kHz，不做帧率标定
        mic_rate=16000
        input_resampler=assert(pcm_converter(mic_rate,8000,1),"MIC resampler unavailable")
        output_resampler=assert(voip.pcmResampler(8000,16000),"speaker resampler unavailable")
        initialized=true
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
    if M.is_ready() then return true end
    if not initializing and not owner and not diag_busy then sys.taskInit(M.init) end
    return false
end
function M.is_ready()
    if not initialized then return false end
    -- 空闲(未接管上行)时按"硬件已验证"判断，接管期间才按帧判活
    if not rx_on then return mic_ok end
    return last_mic>0 and now()-last_mic<3000
end
function M.is_running() return owner=="call" end
function M.is_busy() return owner~=nil or initializing or diag_busy end
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
    return {ready=M.is_ready(),busy=M.is_busy(),initializing=initializing,owner=owner,
        frames=frames,rx_bytes=rx_bytes,bad_frames=bad_frames,fps=fps,mic_rate=mic_rate,
        peak=peak,volume=volume,error=fault,uart=6,baud=2000000,power_pin=73,
        uplink=stats.uplink,downlink=stats.downlink,drops=stats.drops}
end

function M.start(session)
    if diag_busy or initializing then return false,"audio_busy" end
    if owner=="call" then return true end
    -- 通话才接管 MIC 上行（打开 SIP 页不接管）
    if not ensure_mic() then return signal_error("audio_not_ready") end
    local rate=session and tonumber(session.sample_rate or 8000) or 8000
    if rate~=8000 then return false,"unsupported_sample_rate" end
    local store=require "sph_store"
    if not store.is_audio_verified() then return false,"audio_not_verified" end
    if owner=="tone" then cancel_playback() end
    local ok,token=start_stream("call")
    if not ok then return signal_error(token) end
    queue={};pending="";stats={uplink=0,downlink=0,drops=0}
    mic_gap_max=0;last_submit=nil;submit_gap_max=0;input_blocked=0;input_partial=0
    uplink_error=nil;prestart_frames=0;near_clip_frames=0
    input_resampler:reset();output_resampler:reset()
    local uplink=""
    local report_at,previous_up,previous_down=now()+5000,0,0
    local pcm_reads,read_empty,read_blocked=0,0,0
    local PLAY_TARGET=1920   -- 下行水位 60ms(320B/10ms)，与官方 audio_drv.play_buffer_ms=60 一致
    log.info("audio_app","bridge v4: 串口回调只入队; 上行/下行各自独立定时器(对齐官方 audio_drv)")

    local function bridge_fail(why)
        if generation~=token then return end
        if capture_timer then sys.timerStop(capture_timer); capture_timer=nil end
        if play_timer then sys.timerStop(play_timer); play_timer=nil end
        finish_stream(token)
        signal_error(why)
        sys.publish("AUDIO_BRIDGE_FAILED",tostring(why))
    end

    -- 上行：16k->8k 重采样 + voip.pcmIn。pcmIn 内含 RTP 打包与 UDP 发送，
    -- 是这条链路里最重的一步，只能放在独立定时器里，绝不能压回串口接收回调。
    local function capture_tick()
        if owner~="call" or generation~=token then capture_timer=nil; return end
        if voip.isRunning() then
            if #uplink==0 and #queue>0 then
                uplink=input_resampler:process(table.remove(queue,1)) or ""
            end
            if #uplink>0 then
                local okc,samples=pcall(voip.pcmIn, muted and string.rep("\0",#uplink) or uplink)
                if not okc then uplink_error=tostring(samples); bridge_fail(uplink_error); return end
                samples=tonumber(samples) or 0
                -- pcmIn 返回"已消费样本数"，未送走的尾部留到下一拍，绝不丢字节
                local used=math.max(0,math.min(#uplink//2,math.floor(samples)))*2
                if used==0 then
                    input_blocked=input_blocked+1
                else
                    local tick=now()
                    if last_submit then submit_gap_max=math.max(submit_gap_max,tick-last_submit) end
                    last_submit=tick
                    if used<#uplink then input_partial=input_partial+1 end
                    uplink=uplink:sub(used+1);stats.uplink=stats.uplink+used
                end
            end
        end
        -- 还有没送完的就 10ms 一拍赶紧送；刚出帧 2ms 内接上；空闲 5ms 收手
        capture_timer=sys.timerStart(capture_tick, #uplink>0 and 10 or (#queue>0 and 2 or 5))
    end

    -- 下行：按水位取 voip.pcmOut -> 8k->16k -> 交给驱动(驱动自己保持 10ms/帧、空队列补静音)
    -- 水位上限 PLAY_TARGET+640 是官方做法：既保证不欠载，又不会把通话延迟越堆越大。
    local function play_tick()
        if owner~="call" or generation~=token then play_timer=nil; return end
        if not stream_ok(token) then bridge_fail(chip.get_tx_error() or "speaker_stopped"); return end
        if not M.is_ready() then
            local p=mic_parser.stats()
            log.error("audio_app","MIC lost detail","raw_rx_total",rx_bytes,"frames",frames,
                "parser_pending",p.pending,"discarded",p.discarded,"checksum_errors",p.checksum_errors)
            bridge_fail("MIC stream lost"); return
        end
        if voip.isRunning() then
            if chip.get_pending()<PLAY_TARGET+640 then
                pcm_reads=pcm_reads+1
                local pcm=voip.pcmOut(160)
                if pcm and #pcm>0 and #pcm%2==0 then
                    local output=output_resampler:process(pcm)
                    if output and #output>0 then chip.play_stream_write(output) end
                    stats.downlink=stats.downlink+#pcm
                else
                    read_empty=read_empty+1
                end
            else
                read_blocked=read_blocked+1
            end
        end
        if now()>=report_at then
            log.info("audio_app","bridge", "mic_peak",peak,"mic_age_ms",math.floor(now()-last_mic),
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
            report_at=now()+5000
        end
        play_timer=sys.timerStart(play_tick,5)
    end

    capture_timer=sys.timerStart(capture_tick,10)
    play_timer=sys.timerStart(play_tick,20)
    return true
end
function M.stop()
    if owner=="call" then cancel_playback() end
    muted=false
    mic_idle()     -- 停掉上行解析，空闲时不占 UART6
    mic_restore()  -- 归还 chip.feed，让工厂录音等其它消费方恢复（否则退出 SIP 后录音异常）
    return true
end
M.stop_bridge=M.stop

-- The application owns tones too: stop never issues STOP-MIC or resets the chip.
local function play_tone(names,loop)
    if diag_busy or initializing or owner=="call" then return false,"audio_busy" end
    if not initialized then return false,"audio_not_ready" end
    if owner=="tone" then cancel_playback() end
    local buffers={}
    for _,name in ipairs(names) do
        local f=io.open("/luadb/air1103_"..name..".pcm","rb")
        if not f then return signal_error("missing tone: "..name) end
        local data=f:read("*a");f:close()
        if not data or #data==0 or #data>64000 then return signal_error("invalid tone: "..name) end
        buffers[#buffers+1]=data
    end
    local ok,token=start_stream("tone")
    if not ok then return false,token end
    sys.taskInit(function()
        local good,why=pcall(function()
            repeat
                for _,data in ipairs(buffers) do
                    local accepted,reason=feed_pcm(token,data)
                    if not accepted then
                        if token==generation then error(reason) end
                        return
                    end
                end
            until not loop or token~=generation
            if token==generation then local drained,reason=drain(token);assert(drained,reason) end
        end)
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
function M.diagnostic_run(kind,progress)
    if diag_busy or owner or initializing then return false,"audio_busy" end
    if kind~="tone" and kind~="record" then return false,"invalid_test" end
    diag_busy=true
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
    local success,reason=pcall(function()
        if not M.is_ready() then
            report("initializing","等待 Air1103 和麦克风数据")
            local ok,why=M.init();assert(ok,why)
        end
        -- 自检需要 MIC 数据，这里才接管上行（M.init 预热完已恢复轻载）
        assert(ensure_mic(),"MIC stream unavailable")
        if kind=="tone" then
            report("probing","Checking reset response before the 3-second tone")
            local baseline=frames
            sys.wait(200)
            assert(frames>baseline,"MIC stopped before command probe")
            -- 注意不要用 probe_start 做局部变量名：会遮蔽上面的 probe_start() 函数，
            -- 后面 probe_start() 就成了"调用一个数字"(attempt to call a number value)。
            local before,probe_t0,max_gap=frames,now(),0
            assert(chip.reset(),"Air1103 reset command submission failed")
            while now()-probe_t0<3000 do
                sys.wait(20)
                max_gap=math.max(max_gap,now()-last_mic)
            end
            local recovered=frames>before and now()-last_mic<200
            log.info("audio_diag","reset observation", "mic_gap_ms",math.floor(max_gap),
                "frames",frames-before,"recovered",recovered)
            if max_gap<200 then
                log.warn("audio_diag","No clear MIC pause: reset execution unconfirmed; check UART6 TX to Air1103 RX")
            end
            assert(recovered,"MIC did not recover after reset probe")
            -- 放音期间不需要 MIC：停掉上行解析，UART6 只剩 10ms 一帧的下行。
            mic_idle()
            report("playing","Playing 3-second 800Hz tone; check SPK and amplifier input")
            log.info("audio_diag","PCM format",16000,16,1,"volume",volume,"chip_volume",math.floor(volume*31/100))
            probe_start()
            local ok,id=start_stream("diagnostic");assert(ok,id);token=id
            local chunks={}
            for i=0,1599 do
                chunks[#chunks+1]=string.pack("<h",math.floor(6000*math.sin(2*math.pi*800*i/16000)))
            end
            local pcm=table.concat(chunks)
            for i=1,30 do submit(pcm) end
        else
            report("recording","请说话：录制 3 秒，随后自动回放")
            -- 先让 UI 把状态刷完：report 会触发 LVGL 重排长文本 + fskv 读，
            -- 压在录音起点上就是开头几帧被顶掉。
            sys.wait(60)
            -- 录音前把垃圾收干净，这 3 秒内堆不再增长，也就不会中途触发完整 GC。
            collectgarbage("collect")
            sys.wait(20)
            if not rec_buff then
                local created_ok,created=pcall(zbuff.create,112640,0,zbuff.HEAP_AUTO)
                rec_buff=created_ok and created or nil
            end
            assert(rec_buff,"record buffer alloc failed")
            rec_buff:clear(0);rec_buff:used(0)
            local t,n=now(),frames
            capture=rec_buff;capture_bytes=0;cap_last=0;cap_gap_max=0
            sys.wait(3000)
            capture=nil
            local bytes=capture_bytes
            local measured=(frames-n)*1000/math.max(1,now()-t)
            local rate
            if measured>=48 and measured<=76 then rate=16000
            elseif measured>=24 and measured<=39 then rate=8000
            else error("MIC frame rate unstable during recording") end
            assert(bytes>0,"no_recorded_pcm")
            report("replaying","正在回放录音，请确认声音内容、速度和清晰度")
            log.info("audio_diag","record captured", "bytes",bytes,"rate",rate,"frames",math.ceil(bytes/512))
            local resampler=assert(pcm_converter(rate,16000),"record resampler unavailable")
            -- 回放期间不需要 MIC：停掉上行解析，UART6 只剩 10ms 一帧的下行。
            mic_idle()
            -- 再把"正在回放"这一刷让出去，否则起播瞬间的喂数被 LVGL 挤掉，
            -- 芯片 DAC 缓冲被掏空，开头就是一段卡顿。
            sys.wait(80)
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
    capture=nil;capture_bytes=0
    if token then finish_stream(token) end
    mic_idle()   -- 自检结束回到轻载，别让 SIP 页开着就一直占着 MIC 上行
    diag_busy=false;restore_touch()
    if not success then return signal_error(reason) end
    fault=nil
    return true,M.diagnostics()
end
function M.selftest()
    -- Keep require separate for Luatools' static dependency scanner.
    local diag = require "sph_audio_diag"
    return diag.start("tone")
end
return M
