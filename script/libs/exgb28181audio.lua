--[[
@module exgb28181audio
@summary GB28181 对讲/广播的音频：把会话直接交给 voip

分工：信令与 SDP 归 exgb28181client（须设 external_audio=true + audio_port），
编解码、AEC/降噪/AGC、抖动缓冲、RTP 收发、麦克风与喇叭**全归 voip**。本模块只
做三件事：把协商结果转给 voip、按需打开功放与音量、把 voip 的统计换个名字报出来。

    local gba = require "exgb28181audio"
    gba.start(sess, { pa_gpio = 27 })     -- talk/accepted 之后
    gba.stop()

承载按会话的 `transport` 原样透传："udp"/"tcp"/"tcp_passive"（TCP 下 RTP 按
RFC 4571 定界，由 voip 内部处理）。

**不搬 PCM、不碰音频设备**：BK 的驱动在 `voip_is_running()` 时把通用播放泵整个掐掉
（`luat_audio_bk72xx_v2.c`），audio_v2 的播放通道不再取数 —— 桥接模式喂进去的下行
PCM 到不了喇叭（真机现象：**连底噪都没有**）。voip 自己的通路正是照这条分流设计的。
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

--[[
开启音频会话。

@api exgb28181audio.start(session[, opts])
@table session exgb28181client 的音频会话（talk/accepted 事件里的那个）
@table opts 可选：
    pa_gpio   功放使能脚（如 27），给了就拉高；**喇叭完全没声时先查这里**
    pa_level  功放有效的电平，缺省 1（高有效）
    volume    软件音量 0~1000，缺省不动
@return boolean
@return string|nil 失败原因
]]
function M.start(session, opts)
    local function fail(msg)
        last_err = msg
        st.last_error = msg
        return false, msg
    end

    -- voip 可能自己收摊了（媒体连接被对端关掉，见 voip 侧）—— 以它为准，
    -- 否则这个陈旧的标志会让下一次 start 被"已启动"挡在门外
    if running and voip and voip.isRunning and not voip.isRunning() then
        logi("voip 已自行结束(媒体连接断开)，清掉旧状态")
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
    if running and voip and voip.isRunning and not voip.isRunning() then
        running = false
        logi("voip 已自行结束(媒体连接断开)")
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
