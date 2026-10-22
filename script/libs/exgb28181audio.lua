--[[
@module exgb28181audio
@summary GB28181 对讲/广播的音频通路：audio_v2 PCM 桥接、外置芯片

分工：信令与 SDP 归 exgb28181client（须设 external_audio=true；audio_port 是媒体
端口的**基址**，实际每次通话在 `[它, +max_sessions)` 里轮换，见那边 alloc_audio_port）。
本模块只管音频会话与 PCM/编码搬运；codec 上电、I2C、I2S 引脚等板级初始化由应用做。

    local gba = require "exgb28181audio"
    -- 板级初始化由应用负责：codec 上电/I2C/ES8311/I2S/功放脚
    gba.start(sess, { hw_prepare = board_audio_prepare }) -- 板载 codec（voip 直驱）
    gba.start(sess, { mode = "bridge" })               -- audio_v2 speech + voip PCM 桥接
    gba.start(sess, { chip = "air1103", uart_id = 2 }) -- 外置语音芯片
    gba.mic_start({ on_frame = fn })                   -- 麦克风采集（视频内嵌音频）
    gba.stop()

承载按会话的 `transport` 原样透传："udp"/"tcp"/"tcp_passive"（TCP 下 RTP 按
RFC 4571 定界，由 voip 内部处理）。

**板载 codec（缺省 / `mode="native"`）**：编解码/AEC/抖动缓冲/RTP/麦克风与喇叭
全归 voip，本模块只把协商结果转过去、设软件音量、把统计换个名字报出来。

**`mode="bridge"`**：voip 只做 RTP/编码/抖动缓冲，PCM 由 audio_v2 采/放 ——
麦克风 → `voip.pcmIn`，`voip.pcmOut` → `audio_v2.input`。用于需要应用侧同时
处理 PCM 的板子（例如视频流内嵌音频）。麦克风与对讲**互斥**：同一时刻只有一个去处。

**外置芯片（`chip="air1103"`）**：芯片在模组外，没有 codec 给 voip 驱动，只能走
voip 的 PCM 桥接 —— 本模块这时的活儿多一层：双向重采样、控芯片播放节拍、收尾复位
芯片把 MIC 上行拉回来。骨架与 Air8784 的 `single/single_audio.lua`（同款芯片的
SIP 场景）一致，便于两边一起维护。详见 ARCHITECTURE.md §4.7。

**麦克风采集（`mic_start`）**：audio_v2.record 出 RAW PCM，音频回调只把数据
切成 20ms 帧入队；库内 10ms 采集泵判字节序、编码成 PCMA 后再交给 `on_frame`。
只负责采集与编码，推到哪个会话由调用方决定。
]]

local M = {}

local FRAME_MS      = 20
local SAMPLE_RATE   = 8000

local sess      = nil
local running   = false
local last_err  = nil
-- 当前对讲会话的模式：nil | "native" | "bridge" | "air1103"。
-- mic 采集不在这里，它有独立的 mic.active（两者互斥，但不是同一个状态）。
local active_mode = nil

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

-- ==================== G.711A 编解码 ====================

-- PCM16LE → G.711A（带饱和；G.711 编码器本身没有增益参数）
local function alaw_encode(s)
    local sign = 0
    if s >= 0 then
        sign = 0x80
    else
        s = -s
    end
    if s > 32635 then s = 32635 end
    if s >= 256 then
        local exp, mask = 7, 0x4000
        while exp > 0 and (s & mask) == 0 do
            exp = exp - 1
            mask = mask >> 1
        end
        local mant = (s >> (exp + 3)) & 0x0F
        return (sign | (exp << 4) | mant) ~ 0x55
    end
    return (sign | (s >> 4)) ~ 0x55
end

local function pcm_to_alaw(pcm, gain, swap)
    local out = {}
    for i = 1, #pcm - 1, 2 do
        local b0, b1 = pcm:byte(i), pcm:byte(i + 1)
        if swap then b0, b1 = b1, b0 end
        local s = b0 | (b1 << 8)
        if s >= 0x8000 then s = s - 0x10000 end
        if gain and gain ~= 1 then
            s = math.floor(s * gain + 0.5)
            if s > 32767 then s = 32767
            elseif s < -32768 then s = -32768 end
        end
        out[#out + 1] = string.char(alaw_encode(s))
    end
    return table.concat(out)
end

local function alaw_decode(a)
    a = a ~ 0x55
    local sign = a & 0x80
    local exp = (a & 0x70) >> 4
    local data = (a & 0x0F) << 4
    if exp == 0 then
        data = data + 8
    elseif exp == 1 then
        data = data + 0x108
    else
        data = (data + 0x108) << (exp - 1)
    end
    if sign ~= 0 then return data else return -data end
end

local function alaw_to_pcm(pcma)
    local out = {}
    for i = 1, #pcma do
        local v = alaw_decode(pcma:byte(i)) & 0xFFFF
        out[#out + 1] = string.char(v & 0xFF, (v >> 8) & 0xFF)
    end
    return table.concat(out)
end

local function pcm_gain(pcm, gain)
    if not gain or gain == 1 then return pcm end
    local out = {}
    for i = 1, #pcm - 1, 2 do
        local s = pcm:byte(i) | (pcm:byte(i + 1) << 8)
        if s >= 0x8000 then s = s - 0x10000 end
        s = math.floor(s * gain + 0.5)
        if s > 32767 then s = 32767
        elseif s < -32768 then s = -32768 end
        local v = s & 0xFFFF
        out[#out + 1] = string.char(v & 0xFF, (v >> 8) & 0xFF)
    end
    return table.concat(out)
end

--[[
板级音频初始化由应用负责（codec 上电/I2C/ES8311/I2S/功放脚都是板子相关的）。

本库在每次 start/mic_start 前调用 opts.hw_prepare()，应用在这里把自己的
硬件初始化/参数写进驱动。没有传就不做任何硬件操作。
]]
local function hw_prepare(opts)
    if type(opts.hw_prepare) ~= "function" then return true end
    local ok, err = pcall(opts.hw_prepare, opts)
    if not ok then
        log.error("gb28181audio", "hw_prepare 异常", tostring(err))
        return false, "hw_prepare 失败"
    end
    return true
end

--[[ 音频能力自检：对讲必须有 voip；audio_v2 是可选的（只影响软件音量/增益） ]]
function M.available()
    if voip == nil then return false, "固件没编 voip(LUAT_USE_VOIP)" end
    return true
end

function M.warn_optional()
    if audio_v2 == nil then
        log.warn("gb28181audio", "固件没有 audio_v2：软件音量/增益不可用")
    end
end

--[[
等音频请求/voip 收尾。**会 yield**，只能在协程里调用。
opts.voip = true 时连 voip 一起等到 idle（voip.stop 是异步的）。
]]
function M.wait_idle(timeout_ms, opts)
    opts = opts or {}
    local timeout = timeout_ms or 200
    local has_audio_api = audio_v2 and audio_v2.is_all_done
    -- 老固件没有 is_all_done：保底睡一段，行为与旧 demo 一致
    if not has_audio_api and not opts.voip then
        sys.wait(timeout_ms or 100)
        return true
    end
    local waited = 0
    local function audio_done()
        if not has_audio_api then return true end
        return audio_v2.is_all_done()
    end
    local function voip_done()
        if not opts.voip then return true end
        if not (voip and voip.getState) then return true end
        return voip.getState() == "idle"
    end
    while (not audio_done() or not voip_done()) and waited < timeout do
        sys.wait(10)
        waited = waited + 10
    end
    return audio_done() and voip_done()
end

-- 暴露纯函数，供 demo 的 tone/自测复用
M.alaw_encode  = alaw_encode
M.pcm_to_alaw  = pcm_to_alaw
M.alaw_to_pcm  = alaw_to_pcm
M.pcm_gain     = pcm_gain

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

    if not opts.uart_id then
        return fail("air1103 需要 uart_id（板级配置）")
    end
    exa   = exa   or require "exaudio"
    a1103 = a1103 or require "air1103"
    if not chip_ready then
        local ok, res = pcall(exa.setup, {
            model = "air1103", uart_id = opts.uart_id,
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
    active_mode = "air1103"
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

-- ==================== 麦克风采集（视频内嵌音频） ====================
--[[
audio_v2.record 把麦克风编成 RAW PCM，每 20ms 一帧(320 字节)。回调里只入队/
切帧，由 on_frame 交给应用（通常是 client.push_ps_audio 编码进视频 PS）。

**与对讲互斥**：mic_start 拒绝在 voip 忙/对讲运行时启动；M.start 也会先
mic_stop()。麦克风同一时刻只能服务一个去处。
]]
local MIC_BACKLOG_FRAMES = 8    -- 音频回调一次最多保留的积压
local MIC_QUEUE_FRAMES   = 10   -- 任务侧待发队列上限(200ms)

local mic = {
    buf = nil, req = nil, active = false,
    pcm_tail = "", frames = 0,
    on_frame = nil, gain = 4, debug = false,
    err_logged = 0,
    rxq = {}, dropped = 0, gen = 0, pushed = 0,
    -- 字节序判定：nil = 还没判；判定后固定用 true/false
    pcm_swap = nil, diag_frames = 0, diag_le = 0, diag_be = 0,
}

-- 前向声明：audio_v2 只有一个全局回调，mic 和 bridge 共用（定义在后文）
local audio_dispatch

-- 音频回调只取出+入队：这里在 audio msgbus 路径里，编码/网络操作会拖死
-- 消息泵并触发看门狗 NMI（2026-10-21 实测）。编码和 on_frame 交给采集泵。
local function mic_on_audio(_req, event)
    if event ~= audio_v2.REQUEST_GET_NEW_DATA or not mic.active then return end
    local n = mic.buf:used()
    if n == 0 then return end

    -- 丢掉过老积压；按 16bit 样本对齐，否则后续字节序会整体错开
    local keep = 320 * MIC_BACKLOG_FRAMES
    if n > keep then
        local drop = n - keep
        drop = drop - drop % 2
        if drop > 0 then
            mic.buf:del(0, drop)
            mic.dropped = mic.dropped + drop // 320
            n = n - drop
        end
    end

    local data = mic.buf:toStr(0, n)
    mic.buf:del()
    mic.frames = mic.frames + 1
    if mic.frames == 1 or (mic.debug and mic.frames % 50 == 0) then
        logi(("MIC 采集 第%d帧 %d字节"):format(mic.frames, #data))
    end

    mic.pcm_tail = mic.pcm_tail .. data
    local q = mic.rxq
    while #mic.pcm_tail >= 320 do
        q[#q + 1] = mic.pcm_tail:sub(1, 320)
        mic.pcm_tail = mic.pcm_tail:sub(321)
    end
    while #q > MIC_QUEUE_FRAMES do
        table.remove(q, 1)
        mic.dropped = mic.dropped + 1
    end
end

-- 一帧 PCM 在小端/大端两种解释下的平均幅度之和。
-- 正常语音集中在 0 附近；字节序反了会把低字节读成高字节，幅度恒在 1 万上下。
local function mic_abs_sums(pcm)
    local le, be = 0, 0
    for i = 1, #pcm - 1, 2 do
        local b0, b1 = pcm:byte(i), pcm:byte(i + 1)
        local v = b0 | (b1 << 8)
        if v >= 0x8000 then v = v - 0x10000 end
        le = le + math.abs(v)
        v = b1 | (b0 << 8)
        if v >= 0x8000 then v = v - 0x10000 end
        be = be + math.abs(v)
    end
    return le, be
end

local function mic_frame_stats(pcm, swap)
    local mn, mx, sum, zc, prev = 32767, -32768, 0, 0, 0
    for i = 1, #pcm - 1, 2 do
        local b0, b1 = pcm:byte(i), pcm:byte(i + 1)
        if swap then b0, b1 = b1, b0 end
        local s = b0 | (b1 << 8)
        if s >= 0x8000 then s = s - 0x10000 end
        if s < mn then mn = s end
        if s > mx then mx = s end
        sum = sum + math.abs(s)
        if i > 1 and ((s >= 0) ~= (prev >= 0)) then zc = zc + 1 end
        prev = s
    end
    return mn, mx, sum // 160, zc
end

-- 采集泵：取一帧、判字节序（前 50 帧）、编码、交给 on_frame。
-- 运行在普通 Lua 任务里，可以安全调用网络/PS 封装。
local function mic_pump_task(gen)
    while mic.active and mic.gen == gen do
        local q = mic.rxq
        if #q > 0 then
            local pcm = table.remove(q, 1)
            local swap = mic.pcm_swap
            if swap == nil then
                local le, be = mic_abs_sums(pcm)
                mic.diag_frames = mic.diag_frames + 1
                mic.diag_le = mic.diag_le + le
                mic.diag_be = mic.diag_be + be
                if mic.diag_frames >= 50 then
                    local nl = mic.diag_frames * 160
                    mic.pcm_swap = (mic.diag_be * 2 < mic.diag_le)
                    logi(("PCM 字节序判定 swap=%s LE均值=%d BE均值=%d")
                         :format(tostring(mic.pcm_swap),
                                 mic.diag_le // nl, mic.diag_be // nl))
                end
                swap = false      -- 判定前先按 LE 发，避免静音
            end

            local pcma = pcm_to_alaw(pcm, mic.gain, swap)
            local ok, err = pcall(mic.on_frame, pcma)
            if not ok then
                mic.err_logged = mic.err_logged + 1
                if mic.err_logged == 1 or mic.err_logged % 100 == 0 then
                    log.warn("gb28181audio", "on_frame 回调异常", tostring(err))
                end
            end
            mic.pushed = mic.pushed + 1
            if mic.debug and mic.pushed % 50 == 0 then
                local mn, mx, avg, zc = mic_frame_stats(pcm, swap)
                logi(("内嵌音频 已推 %d 次 PCM min=%d max=%d 均幅=%d 过零=%d/160 swap=%s")
                     :format(mic.pushed, mn, mx, avg, zc, tostring(swap)))
            end
        end
        sys.wait(10)
    end
end

--[[
启动麦克风采集。
opts.on_frame  必填，function(pcma) —— 每 20ms 一帧 160B PCMA
opts.mic_gain  软件增益，缺省 4（G.711A 编码器本身无增益）
opts.debug     打开 audio_v2 内部日志，缺省 false
@return boolean, string|nil
]]
function M.mic_start(opts)
    opts = opts or {}
    if type(opts.on_frame) ~= "function" then
        return false, "mic_start 需要 on_frame 回调"
    end
    -- 已启动：只更新回调/增益，不重开请求（多路视频/换会话时要用新闭包）
    if mic.active then
        mic.on_frame = opts.on_frame
        mic.gain = opts.mic_gain or mic.gain
        return true
    end
    if running or (voip and voip.getState and voip.getState() ~= "idle") then
        return false, "对讲/voip 正在使用音频设备"
    end
    if not (audio_v2 and audio_v2.record) then
        return false, "固件没有 audio_v2.record"
    end
    if audio_v2.DATA_CODEC_TYPE_RAW == nil then
        return false, "固件没有 RAW 录音模式"
    end
    if audio_v2.debug then audio_v2.debug(opts.debug and true or false) end
    if audio_v2.get_driver_info then
        local n, def = audio_v2.get_driver_info()
        logi("audio_v2 驱动数=" .. tostring(n) .. " 默认=" .. tostring(def))
    end
    -- 板级初始化（codec/I2S/功放）由应用在 hw_prepare 里做
    local okhw, wh = hw_prepare(opts)
    if not okhw then return false, wh end
    if not mic.buf then
        mic.buf = zbuff.create(2048)
        if not mic.buf then return false, "zbuff 创建失败" end
    end
    audio_v2.on(audio_dispatch)
    mic.buf:del()
    mic.pcm_tail = ""
    mic.rxq = {}
    mic.frames = 0
    mic.dropped = 0
    mic.pushed = 0
    mic.err_logged = 0
    mic.pcm_swap = nil
    mic.diag_frames = 0
    mic.diag_le = 0
    mic.diag_be = 0
    mic.on_frame = opts.on_frame
    mic.gain = opts.mic_gain or 4
    mic.debug = opts.debug and true or false
    local ok, idx = audio_v2.record(mic.buf, 1,
        audio_v2.DATA_CODEC_TYPE_RAW, 0, SAMPLE_RATE, 16, 1)
    if not ok then return false, "audio_v2.record 启动失败" end
    mic.req, mic.active = idx, true
    -- 采集泵：回调只入队，编码/推流在这里做（见 mic_on_audio 的说明）
    mic.gen = mic.gen + 1
    local gen = mic.gen
    sys.taskInit(function() mic_pump_task(gen) end)
    logi("麦克风采集已启动 request=" .. tostring(idx) ..
         " (RAW PCM, gain=" .. tostring(mic.gain) .. ")")
    return true
end

function M.mic_stop()
    if not mic.active then return end
    mic.active = false
    mic.gen = mic.gen + 1          -- 让采集泵退出（可能还卡在 sys.wait 里）
    if mic.req and audio_v2.stop then pcall(audio_v2.stop, mic.req) end
    mic.req = nil
    mic.pcm_tail = ""
    mic.rxq = {}
end

function M.mic_active()
    return mic.active
end

-- ==================== 对讲 PCM 桥接（audio_v2.speech + voip.pcmIn/out） ====================
--[[
bridge 模式下 voip 只做 RTP/编码/JB，PCM 由应用通过 audio_v2 采/放：

    麦克风 PCM ── voip.pcmIn() → 对讲上行 RTP
    voip.pcmOut() → audio_v2.input() → 喇叭

**麦克风同一时刻只有一个去处**：非对讲时走 mic_start 编进视频 PS；进入对讲时
mic_stop()，这里只喂 voip 上行。bridge 不再往视频 PS 推音频 —— 一份 PCM
双推会把两边节拍绑死，一边卡住两边都断。
]]
local bridge = {
    active = false, gen = 0, buf = nil, req = nil,
    rxq = {}, rx_tail = "", pcm = "", need = false,
    gain = 4, debug = false,
    dbg = { rec = 0, rec_bytes = 0, rec_empty = 0, play = 0,
            pcm_in = 0, pcm_cons = 0, pcm_err = 0, drop = 0, retry = 0,
            loop_tx = 0, loop_rx = 0, input_calls = 0,
            pcm_max_ms = 0, input_max_ms = 0 },
}

-- 上行只保留最近 5 帧（100ms）。再多就丢最旧的，绝不把延迟越积越大。
local BRIDGE_RXQ_MAX = 5

local function bridge_on_rec()
    bridge.dbg.rec = bridge.dbg.rec + 1
    local n = bridge.buf:used()
    if n == 0 then
        -- 事件到了但 save_buffer 是空的：编码器没产出（不是 RX 没数据）
        bridge.dbg.rec_empty = bridge.dbg.rec_empty + 1
        return
    end
    bridge.dbg.rec_bytes = bridge.dbg.rec_bytes + n
    if bridge.dbg.rec == 1 then
        logi("bridge 首次录音回调", n .. "字节PCMA")
    end
    local pcma = bridge.buf:toStr(0, n)
    bridge.buf:del()
    pcma = bridge.rx_tail .. pcma
    bridge.rx_tail = ""
    -- 切整帧：回调可能一次给好几帧（Lua 侧被 GC 拖慢时尤其明显），
    -- 但 voip.pcmIn 的接口语义就是 20ms 一帧，这里统一切成 160 字节。
    local pos, len = 1, #pcma
    while len - pos + 1 >= 160 do
        bridge.rxq[#bridge.rxq + 1] = pcma:sub(pos, pos + 159)
        pos = pos + 160
    end
    if pos <= len then bridge.rx_tail = pcma:sub(pos) end
    while #bridge.rxq > BRIDGE_RXQ_MAX do
        table.remove(bridge.rxq, 1)
        bridge.dbg.drop = bridge.dbg.drop + 1
    end
end

local function bridge_on_play(_req)
    bridge.dbg.play = bridge.dbg.play + 1
    bridge.need = true
end

--[[
上行、下行分两个任务。

上行任务只做 voip.pcmIn；下行任务只在播放事件到来时补 speech 播放 FIFO。
拆开是为了定位/规避一类故障：audio_v2.input 内部会 suspend_all，一旦它变慢，
同任务里的上行喂帧就会被一起拖住，表现为 rxq 溢出大量丢帧（2026-10-22 实测：
录音 47 帧/秒，实际只喂进去 17 帧/秒，丢 131 帧）。
]]
local function bridge_tx_task()
    bridge.gen = bridge.gen + 1
    local gen = bridge.gen
    sys.taskInit(function()
        while bridge.active and bridge.gen == gen do
            bridge.dbg.loop_tx = bridge.dbg.loop_tx + 1
            if bridge.pcm == "" and #bridge.rxq > 0 then
                local pcma = table.remove(bridge.rxq, 1)
                bridge.pcm = pcm_gain(alaw_to_pcm(pcma), bridge.gain)
            end

            if bridge.pcm ~= "" then
                bridge.dbg.pcm_in = bridge.dbg.pcm_in + 1
                local t0 = now_ms()
                local used = tonumber(voip.pcmIn(bridge.pcm)) or 0
                local dt = now_ms() - t0
                if dt > bridge.dbg.pcm_max_ms then bridge.dbg.pcm_max_ms = dt end
                if used > 0 then
                    bridge.dbg.pcm_cons = bridge.dbg.pcm_cons + used
                    bridge.pcm = bridge.pcm:sub(used * 2 + 1)
                    bridge.dbg.retry = 0
                else
                    -- -1 = voip 还没到 RUNNING / 不在 bridge 模式；0 = 环形缓冲满
                    bridge.dbg.pcm_err = bridge.dbg.pcm_err + 1
                    bridge.dbg.retry = bridge.dbg.retry + 1
                    if bridge.dbg.pcm_err == 1 then
                        log.warn("gb28181audio", "voip.pcmIn 未消费",
                                 "返回=" .. tostring(used),
                                 "状态=" .. tostring(voip.getState and voip.getState()))
                    end
                    if bridge.dbg.retry >= 40 then   -- 40 × 5ms = 200ms
                        bridge.dbg.retry = 0
                        bridge.dbg.drop = bridge.dbg.drop + 1
                        bridge.pcm = ""
                    end
                end
            end
            sys.wait(5)
        end
    end)
end

local function bridge_rx_task()
    local gen = bridge.gen
    sys.taskInit(function()
        while bridge.active and bridge.gen == gen do
            bridge.dbg.loop_rx = bridge.dbg.loop_rx + 1
            -- 下行：voip.pcmOut → PCM → PCMA → speech 播放输入。
            -- 每次最多补 80ms；5ms 一拍，减少 suspend_all 次数。
            if bridge.need then
                bridge.need = false
                local t0 = now_ms()
                local _, _, free = audio_v2.input(bridge.req, "", false)
                free = tonumber(free) or 0
                if free >= 1 then
                    local n = math.min(free, 640)
                    local pcm = voip.pcmOut(n)
                    local want = n * 2
                    if not pcm then pcm = "" end
                    if #pcm < want then
                        pcm = pcm .. string.rep("\0", want - #pcm)
                    elseif #pcm > want then
                        pcm = pcm:sub(1, want)
                    end
                    audio_v2.input(bridge.req, pcm_to_alaw(pcm, 1), false)
                end
                bridge.dbg.input_calls = bridge.dbg.input_calls + 1
                local dt = now_ms() - t0
                if dt > bridge.dbg.input_max_ms then bridge.dbg.input_max_ms = dt end
            end
            sys.wait(5)
        end
    end)
end

-- 单一 audio_v2 回调：按 request 分发到"麦克风采集"或"对讲 bridge"
audio_dispatch = function(req, event)
    if event == audio_v2.REQUEST_GET_NEW_DATA then
        if bridge.active and req == bridge.req then
            bridge_on_rec()
        elseif mic.active and req == mic.req then
            mic_on_audio(req, event)
        end
    elseif event == audio_v2.REQUEST_NEED_NEW_DATA then
        if bridge.active and req == bridge.req then
            bridge_on_play(req)
        end
    end
end

local function bridge_start(session, opts)
    local function fail(msg)
        last_err = msg
        st.last_error = msg
        return false, msg
    end
    if not (audio_v2 and audio_v2.speech and audio_v2.input) then
        return fail("audio_v2 不支持 speech/input")
    end
    if not (voip and voip.setAudioMode and voip.pcmIn and voip.pcmOut) then
        return fail("voip 不支持 bridge")
    end
    if voip.AUDIO_MODE_BRIDGE == nil then
        return fail("voip 没有 AUDIO_MODE_BRIDGE")
    end
    if voip.getState and voip.getState() ~= "idle" then
        return fail("voip 正忙(" .. tostring(voip.getState()) .. ")")
    end

    -- 麦克风与对讲互斥
    M.mic_stop()

    if not bridge.buf then
        bridge.buf = zbuff.create(2048)
        if not bridge.buf then return fail("zbuff 创建失败") end
    end
    bridge.buf:del()
    bridge.rxq, bridge.rx_tail, bridge.pcm, bridge.need = {}, "", "", false
    bridge.dbg = { rec = 0, rec_bytes = 0, rec_empty = 0, play = 0,
                   pcm_in = 0, pcm_cons = 0, pcm_err = 0, drop = 0, retry = 0,
                   loop_tx = 0, loop_rx = 0, input_calls = 0,
                   pcm_max_ms = 0, input_max_ms = 0 }
    bridge.gain = opts.bridge_gain or 4
    bridge.debug = opts.debug and true or false

    if voip.setAudioMode(voip.AUDIO_MODE_BRIDGE) == false then
        return fail("voip.setAudioMode(BRIDGE) 失败")
    end
    local okv = voip.start({
        codec       = voip.PCMA,
        sample_rate = SAMPLE_RATE,
        ptime       = FRAME_MS,
        transport   = session.transport,
        remote_ip   = session.remote_ip,
        remote_port = session.remote_port,
        local_port  = session.local_port,
        ssrc        = session.ssrc,
        -- bridge 下 AEC 的参考链路不完整，先关掉，避免削掉上行
        aec_enable  = 0,
        aec_denoise = 0,
        aec_agc     = 0,
    })
    if not okv then
        return fail("voip.start 失败")
    end

    audio_v2.on(audio_dispatch)
    -- bridge 诊断期强制打开 audio_v2 内部日志；停止/失败时恢复到配置值
    if audio_v2.debug then pcall(audio_v2.debug, true) end
    --[[
    **全双工用 speech 单请求**：录音/播放共用同一个 I2S 时钟和请求块，
    避免 record + stream 两个独立请求各自跑块节奏（正是撕裂/倍速的来源）。
    RAW 编解码器在 speech 里被绑定拒绝，所以用 G.711A：录音回调给 PCMA，
    播放侧 input 也收 PCMA。dsp_type=0xFF：不绑 BSP 的 SpeexDSP。
    ]]
    local ok, req = audio_v2.speech(
        audio_v2.DATA_CODEC_TYPE_G711_ALAW, bridge.buf, 1,
        audio_v2.DATA_CODEC_TYPE_G711_ALAW, SAMPLE_RATE, 16, 1, nil, 0xFF)
    if not ok then
        pcall(voip.stop)
        if audio_v2.debug then pcall(audio_v2.debug, opts.debug and true or false) end
        return fail("audio_v2.speech 失败")
    end

    bridge.req, bridge.active = req, true
    bridge_tx_task()
    bridge_rx_task()
    logi("对讲 bridge 已启动(speech G711A)",
         "req=" .. tostring(req), "麦克风只走对讲上行")
    return true
end

local function bridge_stop()
    if not bridge.active and not bridge.req then return end
    bridge.active = false
    bridge.gen = bridge.gen + 1          -- 让还在 sys.wait 的旧任务退出
    if bridge.req and audio_v2 and audio_v2.stop then
        pcall(audio_v2.stop, bridge.req)
    end
    bridge.req = nil
    if voip then pcall(voip.stop) end
    if audio_v2 and audio_v2.debug then
        pcall(audio_v2.debug, bridge.debug and true or false)
    end
    local d = bridge.dbg
    logi("对讲 bridge 已关闭",
         ("录音事件=%d 字节=%d 空=%d 播放事件=%d pcmIn=%d 已消费样本=%d 未消费=%d 丢帧=%d")
         :format(d.rec, d.rec_bytes, d.rec_empty, d.play,
                 d.pcm_in, d.pcm_cons, d.pcm_err, d.drop),
         ("上行循环=%d 下行循环=%d 补包=%d pcm耗时=%dms 补包耗时=%dms")
         :format(d.loop_tx, d.loop_rx, d.input_calls,
                 d.pcm_max_ms, d.input_max_ms))
end

--[[
开启音频会话。

@api exgb28181audio.start(session[, opts])
@table session exgb28181client 的音频会话（talk/accepted 事件里的那个）
@table opts 可选：
    hw_prepare function  每次 start 前调用，应用在这里做板级初始化
                         （codec 上电/I2C/ES8311/I2S/功放脚）
    audio_mode 板级音频模式，缺省 voip.AUDIO_MODE_I2S，可覆盖
    chip      "air1103" 时走外置语音芯片：PCM 经 voip 桥接 + UART 与芯片交换
    uart_id   芯片所在串口，**air1103 必填**
    mic_gain  上行重采样增益 1~8，缺省 1（芯片够响就别动）
    play_buffer_ms 下行水位(ms)，缺省 60、最小 40。**只在芯片模式下有意义**
    volume    软件音量 0~1000，缺省不动
@return boolean
@return string|nil 失败原因
]]
function M.start(session, opts)
    opts = opts or {}

    -- 模式归一化：chip 优先（保持 air1103 老用法），其次 opts.mode。
    local mode = opts.mode or "native"
    if opts.chip == "air1103" then mode = "air1103" end
    if mode ~= "native" and mode ~= "bridge" and mode ~= "air1103" then
        local msg = "未知音频模式: " .. tostring(mode)
        last_err = msg
        st.last_error = msg
        return false, msg
    end

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

    -- voip 可能自己收摊了（媒体连接被对端关掉，见 voip 侧）—— 以它为准，
    -- 否则这个陈旧的标志会让下一次 start 被"已启动"挡在门外
    if running and not voip_alive() then
        logi("voip 已自行结束(" .. tostring(voip.getState()) .. ")，清掉旧状态")
        running = false
        if active_mode == "bridge" then
            bridge.gen = bridge.gen + 1
            bridge.active = false
        end
    end
    if running then
        local msg = "已启动，请先 stop()"
        last_err = msg
        st.last_error = msg
        return false, msg
    end

    if mode == "air1103" then
        return start_air1103(session, opts)
    end

    -- 板级初始化（codec/I2S/功放）由应用的 hw_prepare 完成
    local okhw, wh = hw_prepare(opts)
    if not okhw then
        last_err = wh
        st.last_error = wh
        return false, wh
    end

    local function fail(msg)
        last_err = msg
        st.last_error = msg
        return false, msg
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

    if mode == "bridge" then
        local ok, err = bridge_start(session, opts)
        if ok then
            sess      = session
            running   = true
            active_mode = "bridge"
            last_err  = nil
            st.last_error = nil
        end
        return ok, err
    end
    if opts.volume and audio_v2 and audio_v2.soft_volume then
        pcall(audio_v2.soft_volume, opts.volume)
    end

    -- 显式恢复板级音频模式：上一次可能是 bridge，voip 会停在 BRIDGE。
    -- 默认 I2S，板子不同可通过 opts.audio_mode 覆盖。
    local audio_mode = opts.audio_mode or voip.AUDIO_MODE_I2S
    if voip.setAudioMode and audio_mode ~= nil then
        if voip.setAudioMode(audio_mode) == false then
            return fail("voip.setAudioMode 失败")
        end
    end
    -- AEC 默认开；opts.aec=false 可关掉做对照（AEC 参考异常时会压掉麦克风）
    local aec = 1
    if opts.aec ~= nil then
        aec = opts.aec and 1 or 0
    end
    --[[
    jitter_depth 按承载分开：

    UDP（广播）：平台 20ms 一个包，JB 预存 6 帧(120ms)足够吸收 Wi-Fi 抖动。
    TCP（对讲）：ZLM 的 RTP-over-TCP 是**按 MSS 成批写的**——实测每个 TCP 段
    1340 字节 ≈ 7.7 个 RTP 帧 ≈ 150ms 音频，一撮一撮到达。JB 预存必须覆盖
    一个批次再加余量，否则每批之间必然欠载：实测 depth=3 时对讲 jbsil 涨到
    15 帧/秒、满屏 `jb resync`。12 帧=240ms，覆盖 150ms 批次 + 90ms 余量。
    ]]
    local jb_depth = opts.jitter_depth
                     or ((transport == "udp") and 6 or 12)
    local okv = voip.start({
        codec        = voip.PCMA,
        sample_rate  = SAMPLE_RATE,
        ptime        = FRAME_MS,
        transport    = transport,
        remote_ip    = session.remote_ip,
        remote_port  = session.remote_port,
        local_port   = session.local_port,
        ssrc         = session.ssrc,
        jitter_depth = jb_depth,
        aec_enable   = aec,
        aec_denoise  = aec,
        aec_agc      = aec,
    })
    if not okv then
        return fail("voip.start 失败")
    end

    sess    = session
    running = true
    active_mode = "native"
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
    -- **按 active_mode 清理，不能只看 running**：voip 自行结束时 running 已经被
    -- 清掉，但 speech 请求和 bridge 任务还在，必须一起收掉。
    local mode = active_mode
    running = false

    if mode == "bridge" then
        bridge_stop()
        active_mode = nil
        sess = nil
        return true
    end

    if mode == "air1103" or chip == "air1103" then
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
        active_mode = nil
        logi("外置芯片音频会话已关闭")
        return true
    end

    if mode == "native" then
        if voip then pcall(voip.stop) end
        sess = nil
        active_mode = nil
        logi("音频会话已关闭")
        return true
    end

    -- 没有记录的活动会话，但 voip 可能还活着（上层只做了部分清理）：兜底停掉。
    if voip and voip_alive() then pcall(voip.stop) end
    sess = nil
    active_mode = nil
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
        if active_mode == "bridge" then
            -- 让还在 sys.wait 的 bridge 任务也退出；资源由 M.stop 清理
            bridge.gen = bridge.gen + 1
            bridge.active = false
        end
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
        mode      = active_mode,
        mic_active = mic.active,
        up_frames      = vs.tx_packets or 0,
        up_bytes       = (vs.tx_packets or 0) * 320,
        up_drop        = vs.tx_errors or 0,
        down_frames    = vs.rx_frames or 0,
        down_bytes     = (vs.rx_frames or 0) * 320,
        down_silence   = vs.jb_silence or 0,
        down_drop_bytes = (vs.rx_queue_dropped or 0) * 320,
        last_error     = st.last_error,
        voip      = vs,
        -- 视频内嵌音频的采集侧读数（mic_start 时才有意义）
        mic = {
            frames = mic.frames, queued = #mic.rxq,
            dropped = mic.dropped, pushed = mic.pushed,
            swap = mic.pcm_swap,
        },
    }
    if active_mode == "bridge" then
        local d = bridge.dbg
        t.bridge = {
            rec = d.rec, rec_bytes = d.rec_bytes, rec_empty = d.rec_empty,
            play = d.play, pcm_in = d.pcm_in, pcm_cons = d.pcm_cons,
            pcm_err = d.pcm_err, drop = d.drop, retry = d.retry,
            queued = #bridge.rxq,
            cur_frame_samples = #bridge.pcm // 2,
        }
    end
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
