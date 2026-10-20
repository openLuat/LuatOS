--[[
@module exgb28181audio
@summary GB28181 对讲/广播的音频：会话交给 voip（板载 codec）或 voip 的 PCM 桥接（外置芯片）

分工：信令与 SDP 归 exgb28181client（须设 external_audio=true；audio_port 是媒体
端口的**基址**，实际每次通话在 `[它, +max_sessions)` 里轮换，见那边 alloc_audio_port）。

    local gba = require "exgb28181audio"
    gba.start(sess, { pa_gpio = 27 })                 -- 板载 codec
    gba.start(sess, { chip = "air1103", uart_id = 2 }) -- 外置语音芯片
    gba.stop()

承载按会话的 `transport` 原样透传："udp"/"tcp"/"tcp_passive"（TCP 下 RTP 按
RFC 4571 定界，由 voip 内部处理）。

**板载 codec（缺省）**：编解码/AEC/抖动缓冲/RTP/麦克风与喇叭全归 voip，本模块只把
协商结果转过去、开功放与音量、把统计换个名字报出来。**不搬 PCM、不碰音频设备** ——
BK 驱动在 `voip_is_running()` 时把 audio_v2 的通用播放泵整个掐掉
（`luat_audio_bk72xx_v2.c`），桥接喂进去的下行到不了喇叭（真机现象：连底噪都没有）。

**外置芯片（`chip="air1103"`）**：芯片在模组外，没有 codec 给 voip 驱动，只能走
voip 的 PCM 桥接 —— 本模块这时的活儿多一层：双向重采样、控芯片播放节拍、收尾复位
芯片把 MIC 上行拉回来。骨架与 Air8784 的 `single/single_audio.lua`（同款芯片的
SIP 场景）一致，便于两边一起维护。详见 ARCHITECTURE.md §4.7。
]]

local M = {}

local FRAME_MS      = 20
local SAMPLE_RATE   = 8000

local sess      = nil
local running   = false
local last_err  = nil
local pa_gpio   = nil

local st = {
    up_frames = 0, up_bytes = 0,
    down_frames = 0, down_bytes = 0,
    down_silence = 0,         -- 播放侧补静音的帧数（抖动缓冲没数据）
    down_drop_bytes = 0,      -- 到了播放通路却被丢掉的
    up_drop = 0,              -- 发送侧失败（voip.tx_errors）
    last_error = nil,         -- 最近一次 start 失败在哪一步（见 M.last_error）
}

local function logi(...) log.info("gb28181audio", ...) end

-- voip 是否还活着。**不能用 voip.isRunning()**：它只在 RUNNING 时为真，而会话起来
-- 后的前几毫秒是 STARTING，此时它报 false。谁在这段窗口里查一次，就会被误判成
-- "会话已结束"而把桥拆掉(现象：刚接通就没声)。只有 idle/error 才是真的结束了。
local function voip_alive()
    if not voip or not voip.getState then return true end
    local s = voip.getState()
    return s ~= "idle" and s ~= "error"
end

-- ==================== 外置语音芯片：Air1103 ====================
-- 芯片自己管 MIC/喇叭/AEC，模组这侧只搬 PCM：
--   上行 512B@16k → pcmResampler(16k→8k) → voip.pcmIn   → RTP
--   下行 RTP → voip.pcmOut(160)@8k → pcmResampler(8k→16k) → 芯片播放流
-- 两边的帧长不是巧合：重采样器单次输入上限正好是 512B(16k) / 320B(8k)，
-- 也就是芯片的上行帧与 20ms 的下行块，一次一片，不用再切。

local chip        = nil      -- "air1103" 时才走这条通路
local exa, a1103             -- require 得到的 exaudio / air1103
local mic_rs, spk_rs         -- 上行(16k→8k) / 下行(8k→16k) 重采样器
local up_q  = {}             -- 芯片上行帧队列（512B/帧）
local up_tail = ""           -- pcmIn 没吃完的尾巴，下次接着送
local up_timer, dn_timer
local chip_ready = false     -- exaudio.setup 只做一次(换串口要 uninit 后再 setup)
local up_last_ms, up_reset_once = 0, false   -- 上行看门狗：最后一帧时刻 / 是否已重试过
local chip_uplink_restore                    -- 前向声明：看门狗要回调它

local CHIP_FRAME_UP  = 512   -- 芯片 MIC 上行帧：16ms @16k/16bit 单声道
local CHIP_QUEUE_MAX = 8     -- 上行积压上限（约 128ms），多了丢最旧，防延迟累积
-- 下行水位：低于"目标+余量"就向 voip 要数据，一次要 20ms。太小 → 芯片 DAC 断流
-- (补静音/爆音)；太大 → 对讲延迟高。缺省取 Air8784 同款芯片的 60ms，可用
-- opts.play_buffer_ms 调。判据看 M.stats().down_silence：芯片补静音的次数，应为 0。
local DN_TARGET_MS   = 60
local DN_HIGH_MS     = 20    -- 超过 目标+20ms 就暂停取数，防止积压

-- 毫秒单调时基：mcu.ticks() 是 tick 不是毫秒(要除 mcu.hz())，ticks2 直接给秒+微秒
local function now_ms()
    local s, us = mcu.ticks2(0)
    return s * 1000 + us // 1000
end

-- 上行：芯片每 16ms 给一帧，只入队，重采样放到定时器里做
local function chip_up_cb(data)
    if not running then return end
    if type(data) ~= "string" or #data ~= CHIP_FRAME_UP then return end
    up_last_ms = now_ms()
    if #up_q >= CHIP_QUEUE_MAX then table.remove(up_q, 1) end
    up_q[#up_q + 1] = data
end

local function chip_up_tick()
    if not running then return end
    if #up_tail == 0 and #up_q > 0 then
        up_tail = mic_rs:process(table.remove(up_q, 1))
    end
    if #up_tail > 0 then
        -- pcmIn 只吃整数帧，返回已消费样本数，剩下的尾巴留到下一拍
        local used = tonumber(voip.pcmIn(up_tail)) or 0
        if used > 0 then up_tail = up_tail:sub(used * 2 + 1) end
    end
    up_timer = sys.timerStart(chip_up_tick, 10)
end

local function chip_dn_tick()
    if not running then return end
    -- 上行看门狗：芯片的 MIC 可能被别处复位掉，一旦断流整路对讲就只剩下行。
    -- 只在通话期间、且没重试过时复位一次，避免反复复位把上行按死。
    if not up_reset_once and now_ms() - up_last_ms > 1500 then
        up_reset_once = true
        logi("芯片上行断流，复位一次尝试恢复")
        pcall(chip_uplink_restore)
    end
    if voip_alive() and a1103.get_pending() < (DN_TARGET_MS // 10) * 320 + (DN_HIGH_MS // 10) * 320 then
        local pcm = voip.pcmOut(160)
        -- pcmOut 可能给半帧，长度必须是 2 的倍数才喂得进重采样器
        if pcm and #pcm > 0 and #pcm <= 320 and #pcm % 2 == 0 then
            -- 只取第一个返回值：process 还返回"限幅样本数"，直接内联传参会当成
            -- play_stream_write 的 is_end(而 Lua 里 0 为真) → 立刻按"播完"收尾停流
            local out = spk_rs:process(pcm)
            exa.play_stream_write(out)
        end
    end
    dn_timer = sys.timerStart(chip_dn_tick, 5)
end

-- 收芯片上行帧不调 exaudio.record_start：那条路会起写任务搬缓冲、清队列、覆盖
-- on_audio_data 回调（见 single_audio.lua 的取舍），桥接要的是原始帧。
-- 挂上回调并放行上行。**不复位芯片**：复位要 1.4s，放在通话开头等于每次都白等；
-- 芯片上电即自动上行，停播放时我们也已经复位过了（见 M.stop）。
local function chip_uplink_arm()
    a1103.on_audio_data(chip_up_cb)
    a1103.set_rx_enable(true)
    up_last_ms, up_reset_once = now_ms(), false
end

-- 复位芯片把 MIC 上行拉回来（停播放时芯片被 02 01 停了上行，只能靠复位恢复）。
-- 不动 up_reset_once：看门狗已经置位，一次通话只重试一次，否则每次复位要 1.4s，
-- 反复复位反而把上行按死（新会话由 chip_uplink_arm 清标志）。
function chip_uplink_restore()
    a1103.set_rx_enable(false)        -- 复位期间先掐掉，免得半帧混进来
    a1103.on_audio_data(chip_up_cb)
    a1103.reset()
    a1103.set_rx_enable(true)
    up_last_ms = now_ms()
end

local function start_air1103(session, opts)
    local function fail(msg)
        last_err = msg
        st.last_error = msg
        return false, msg
    end

    if running then return fail("已启动，请先 stop()") end
    if type(session) ~= "table" then return fail("session 参数无效") end
    local transport = session.transport or "udp"
    if transport ~= "tcp_passive" and
            (session.remote_ip == nil or session.remote_port == nil) then
        return fail("会话没有对端媒体地址(SDP 未协商?)")
    end
    -- voip 是 userdata 模块(不是 table)，只能按可空 + 函数面来判
    if voip == nil then
        return fail("voip 不可用(固件未编 LUAT_USE_VOIP?)")
    end
    if type(voip.pcmIn) ~= "function" or voip.AUDIO_MODE_BRIDGE == nil then
        return fail("固件未编 voip 桥接(LUAT_USE_VOIP_BRIDGE)")
    end

    exa   = exa   or require "exaudio"
    a1103 = a1103 or require "air1103"
    if not chip_ready then
        local ok, res = pcall(exa.setup, {
            model = "air1103", uart_id = opts.uart_id or 2,
            bits_per_sample = 16, channels = 1,
        })
        if not ok or not res then return fail("exaudio.setup 失败(model=air1103)") end
        chip_ready = true
    end

    -- 音量按芯片的 0~31 档，走到 exaudio.vol 的 0~100
    if opts.volume then pcall(exa.vol, math.floor(opts.volume * 100 / 31 + 0.5)) end
    -- 水位可调：欠载(爆音)就调大，嫌延迟高就调小。按 10ms 对齐，最小 40ms
    if opts.play_buffer_ms then
        DN_TARGET_MS = math.max(40, math.floor(opts.play_buffer_ms / 10) * 10)
    end

    mic_rs = mic_rs or voip.pcmResampler(16000, 8000, opts.mic_gain or 1)
    spk_rs = spk_rs or voip.pcmResampler(8000, 16000)
    if not mic_rs or not spk_rs then return fail("pcmResampler 创建失败") end
    mic_rs:reset(); spk_rs:reset()

    -- 必须在 start 之前设：voip 只在 IDLE 状态接受改模式
    voip.setAudioMode(voip.AUDIO_MODE_BRIDGE)
    local okv = voip.start({
        codec        = voip.PCMA,
        sample_rate  = SAMPLE_RATE,
        ptime        = FRAME_MS,
        transport    = transport,
        remote_ip    = session.remote_ip,
        remote_port  = session.remote_port,
        -- local_port 只是"希望用的端口"：上一个会话的 socket 还没放掉时 voip 会
        -- **静默**换一个，而 SDP 里报给平台的仍是这个值 → 平台下行全丢。收尾后
        -- 约 100ms 内不能起新会话(见 tests/tools/air1103_sim/README.md)。
        local_port   = session.local_port,
        ssrc         = session.ssrc,
        -- 回声消除在芯片里做；模组侧再开一遍只会把上行削坏
        aec_enable   = 0,
        aec_denoise  = 0,
        aec_agc      = 0,
    })
    if not okv then return fail("voip.start 失败") end

    sess    = session
    chip    = "air1103"
    running = true
    last_err = nil
    up_q, up_tail = {}, ""
    st.last_error = nil

    chip_uplink_arm()
    if not exa.play_start({ type = 2, sampling_rate = 16000,
                            sampling_depth = 16, signed_or_unsigned = true }) then
        running = false
        pcall(voip.stop)
        return fail("exaudio.play_start 失败")
    end
    -- 先要一拍数据垫底，再起节拍（否则第一拍必然是空的）
    if voip_alive() then
        local pcm = voip.pcmOut(160)
        if pcm and #pcm > 0 and #pcm % 2 == 0 then
            local out = spk_rs:process(pcm)
            exa.play_stream_write(out)
        end
    end
    up_timer = sys.timerStart(chip_up_tick, 10)
    dn_timer = sys.timerStart(chip_dn_tick, 5)

    logi("外置芯片会话已就绪(air1103)", session.call_id or "", transport,
         tostring(session.remote_ip) .. ":" .. tostring(session.remote_port),
         "ssrc=" .. tostring(session.ssrc))
    return true
end

--[[
开启音频会话。

@api exgb28181audio.start(session[, opts])
@table session exgb28181client 的音频会话（talk/accepted 事件里的那个）
@table opts 可选：
    chip      "air1103" 时走外置语音芯片：PCM 经 voip 桥接 + UART 与芯片交换。
              此时 pa_gpio/pa_level 不适用（功放在芯片侧），volume 按芯片的 0~31 档给
    uart_id   芯片所在串口，缺省 2
    mic_gain  上行重采样增益 1~8，缺省 1（芯片够响就别动）
    play_buffer_ms 下行水位(ms)，缺省 60、最小 40。**只在芯片模式下有意义**：
              欠载(爆音)就调大、嫌延迟高就调小，判据看 stats().down_silence 恒为 0
    pa_gpio   功放使能脚（如 27），给了就拉高；**喇叭完全没声时先查这里**
    pa_level  功放有效的电平，缺省 1（高有效）
    volume    软件音量 0~1000，缺省不动
@return boolean
@return string|nil 失败原因
]]
function M.start(session, opts)
    opts = opts or {}
    -- voip.stop() 是异步的：Lua 侧投完事件就返回，媒体端口的释放和收尾在 voip 任务里
    -- 稍后才做。这段时间里 isRunning() 已经报 false，但 getState() 还是 "stopping"；
    -- 此时再 start 会被随后到达的停止事件拆掉 —— 现象是"新会话起来了却没声"。
    -- 宁可显式失败让上层稍后重试，也不要静默起一个死会话。
    if voip and voip.getState and voip.getState() ~= "idle" then
        local msg = "voip 正忙(" .. tostring(voip.getState()) .. ")，上一会话还在收尾"
        last_err = msg
        st.last_error = msg
        return false, msg
    end
    if opts.chip == "air1103" then
        return start_air1103(session, opts)
    end
    local function fail(msg)
        last_err = msg
        st.last_error = msg
        return false, msg
    end

    -- voip 可能自己收摊了（媒体连接被对端关掉，见 voip 侧）—— 以它为准，
    -- 否则这个陈旧的标志会让下一次 start 被"已启动"挡在门外
    if running and not voip_alive() then
        logi("voip 已自行结束(" .. tostring(voip.getState()) .. ")，清掉旧状态")
        running = false
    end
    if running then
        return fail("已启动，请先 stop()")
    end
    if type(session) ~= "table" then
        return fail("session 参数无效")
    end
    -- 被动 TCP 的对端是连进来的那个，协商时没有它的地址可填 —— 只有
    -- 主动方向（UDP / TCP active）才必须有对端地址
    local transport = session.transport or "udp"
    if transport ~= "tcp_passive" and
            (session.remote_ip == nil or session.remote_port == nil) then
        return fail("会话没有对端媒体地址(SDP 未协商?)")
    end

    -- voip / audio_v2 都是 C 库，全局注册（require 不到）。固件没编就叫出来
    if voip == nil then
        return fail("voip 不可用(固件未编 LUAT_USE_VOIP?)")
    end

    opts = opts or {}
    -- 功放与音量是**板级**的事，库不替应用猜；喇叭没声（连底噪都没有）时第一个查这里。
    -- 正确做法是把 PA 脚交给音频驱动（Air8101 的 demo 也是这么配的），它会在音频
    -- 启动/停止时自己拉放；自己 gpio.setup 只在没有这个 API 的老固件上兜底 ——
    -- 那样驱动起来时可能把脚复用掉，而且停了也不会放开。
    if opts.pa_gpio and audio_v2 and audio_v2.config_pa_power_ctrl then
        local okp = audio_v2.config_pa_power_ctrl(true, opts.pa_gpio,
                                            opts.pa_level or 1, opts.pa_delay or 200)
        logi("功放脚已交给音频驱动 GPIO" .. tostring(opts.pa_gpio),
             "电平", opts.pa_level or 1, tostring(okp))
    elseif opts.pa_gpio and gpio then
        gpio.setup(opts.pa_gpio, opts.pa_level or 1)
        pa_gpio = opts.pa_gpio        -- 自己拉的才由自己放开（见 M.stop）
        logi("功放脚已直拉 GPIO" .. tostring(opts.pa_gpio))
    end
    if opts.volume and audio_v2 and audio_v2.soft_volume then
        pcall(audio_v2.soft_volume, opts.volume)
    end

    -- 这些值都来自那次 SDP 协商；ssrc 平台按 SDP 的 y= 校验。
    -- 不调 setAudioMode：默认就是 voip 自己驱动音频设备，正是我们要的
    local okv = voip.start({
        codec        = voip.PCMA,
        sample_rate  = SAMPLE_RATE,
        ptime        = FRAME_MS,
        transport    = transport,
        remote_ip    = session.remote_ip,
        remote_port  = session.remote_port,
        local_port   = session.local_port,
        ssrc         = session.ssrc,
        aec_enable   = 1,
        aec_denoise  = 1,
        aec_agc      = 1,
    })
    if not okv then
        return fail("voip.start 失败")
    end

    sess    = session
    running = true
    last_err = nil
    for k, v in pairs(st) do
        if type(v) == "number" then st[k] = 0 end
    end
    st.last_error = nil

    logi("音频会话已交给 voip", session.call_id or "", transport,
         tostring(session.remote_ip) .. ":" .. tostring(session.remote_port),
         "ssrc=" .. tostring(session.ssrc))
    return true
end

-- 关闭音频会话。必须调，否则 voip 不停、媒体端口不放开。
-- 同步即可：只需 voip.stop()（发个停止事件就返回），没有会互锁的音频任务收尾。
function M.stop()
    if not running then
        return true
    end
    running = false

    if chip == "air1103" then
        sys.timerStop(up_timer); up_timer = nil
        sys.timerStop(dn_timer); dn_timer = nil
        up_q, up_tail = {}, ""
        if exa then pcall(exa.play_stop, { type = 2 }) end
        if voip then pcall(voip.stop) end
        -- 停播放会连带发 02 01 把芯片 MIC 上行也停掉。这里立刻复位把它拉回来
        -- （芯片重启约 1.4s），下一次对讲就不必先等这 1.4s。
        if a1103 then pcall(chip_uplink_restore) end
        chip = nil
        sess = nil
        logi("外置芯片音频会话已关闭")
        return true
    end

    if voip then
        pcall(voip.stop)
    end
    if pa_gpio and gpio then
        gpio.setup(pa_gpio, 0)      -- 自己拉的自己放开；交给驱动的那种由驱动管
        pa_gpio = nil
    end
    sess = nil
    logi("音频会话已关闭")
    return true
end

--[[ 查询是否已开启
@api exgb28181audio.is_running()
@return boolean
]]
function M.is_running()
    -- **以 voip 的实际状态为准**：媒体连接被对端关掉时 voip 会自己收摊，
    -- 此时本模块也要跟着变成"未运行"（调用方看到的是同一件事）
    if running and not voip_alive() then
        running = false
        logi("voip 已自行结束(" .. tostring(voip.getState()) .. ")")
    end
    return running
end

--[[
统计，数值来自 voip（字段名与旧版一致，调用方判据不用改）：
`up_bytes`/`down_bytes` 是**进出口的字节**（down 只算真正进了播放通路的），
`up_drop` 是发送失败次数，`down_silence` 是播放侧补静音次数，`t.voip` 是原始计数。

下行没声时按这个顺序看：`t.voip.rx_packets=0` 一个包没到 → `rx_frames=0` 到了没解出来
→ `down_bytes>0` 而喇叭不响则是功放脚/音量。
@api exgb28181audio.stats()
@return table
]]
function M.stats()
    local vs = {}
    if voip and voip.stats then
        local ok, v = pcall(voip.stats)
        if ok and type(v) == "table" then vs = v end
    end

    local t = {
        running   = running,
        up_frames      = vs.tx_packets or 0,
        up_bytes       = (vs.tx_packets or 0) * 320,
        up_drop        = vs.tx_errors or 0,
        down_frames    = vs.rx_frames or 0,
        down_bytes     = (vs.rx_frames or 0) * 320,
        down_silence   = vs.jb_silence or 0,
        down_drop_bytes = (vs.rx_queue_dropped or 0) * 320,
        last_error     = st.last_error,
        voip      = vs,
    }
    if chip == "air1103" then
        -- 芯片通路全是"另一侧"的读数，必须一起看才有意义
        t.chip          = "air1103"
        t.chip_queued   = #up_q          -- 上行积压帧数（>0 说明搬得比芯片产出慢）
        t.chip_pending  = a1103 and a1103.get_pending() or 0   -- 芯片侧未播出的字节
        t.chip_mic_stale_ms = now_ms() - up_last_ms             -- 上行静默时长
    end
    return t
end

--[[ 最近一次 start 失败在哪一步（nil = 没失败过）
@api exgb28181audio.last_error()
@return string|nil
]]
function M.last_error()
    return st.last_error
end

return M
