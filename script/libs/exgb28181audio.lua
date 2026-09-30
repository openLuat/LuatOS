--[[
@module exgb28181audio
@summary GB28181 语音对讲/广播的音频桥（audio_v2 ↔ exgb28181client）
@version 0.1.0
@date 2026.09.16

把 exgb28181client 的音频会话与 LuatOS 的 audio_v2 框架接起来：上行走麦克风，
下行走喇叭。本模块只搬字节，不做编解码 —— 两端都用 audio_v2 自带的
DATA_CODEC_TYPE_G711_ALAW，PCM↔G.711A 的转换在框架内部完成。

分层：
    gb28181(C)       协议编解码(PS 解封装等)，不碰编解码器
    exgb28181client  信令 + 会话 + talk_push(上行出口) / on_audio(下行入口)
    exgb28181audio   本文件：麦克风/喇叭 ↔ 会话
    audio_v2(LuatOS) 音频框架：编解码、DMA、混音、驱动

不加 AEC：
    对讲是双向同开的，理论上麦克风会拾到喇叭的声音。回声消除要在 PCM 域做，
    而本桥两端都直接用 G.711A 直通(压缩域)，所以**不做 AEC**。
    命令的取舍是：实现简单、Lua 层不碰编解码；代价是回声要靠结构隔离
    (喇叭与麦克风的物理间距/腔体)处理，而不是靠算法。

基本用法：
    local exgb28181audio = require "exgb28181audio"

    -- 在平台的音频 INVITE 受理成功后(或 start_talk 发出后)打开
    exgb28181audio.start(sess)
    -- 会话结束时关闭
    exgb28181audio.stop()

start() 会**接管** exgb28181client 的 on_audio 回调槽位（下行数据由它送入喇叭），
stop() 会把它清掉。所以同一个客户端上不要另外注册 on_audio，否则后注册的会覆盖前者。
]]

local M = {}

-- 20ms @ 8kHz：G.711A 一帧 = 160 字节。上行按这个粒度切包，
-- 与 talk_push 的建议值、以及 G.711 编解码器的 one_frame_sample_cnt 一致。
local FRAME_MS      = 20
local FRAME_BYTES   = 160
local SAMPLE_RATE   = 8000

local a2        = nil    -- audio_v2 模块句柄
local gb        = nil    -- C 层 gb28181（只为 ps_demux_audio）
local client    = nil    -- exgb28181client
local req_idx   = nil    -- audio_v2.speech 返回的请求索引
local src_idx   = nil    -- audio_v2.extern_source 返回的播放源索引
local rec_zb    = nil    -- 录音缓冲（框架往里写 G.711A）
local sess      = nil    -- 绑定的 gb28181 会话
local timer     = nil    -- 上行泵
local ps_pend   = ""     -- 下行 PS 重组缓冲（仅 is_ps 时用）
local running   = false

local st = {
    up_frames = 0, up_bytes = 0,          -- 上行：已推给平台的帧/字节
    down_frames = 0, down_bytes = 0,      -- 下行：已交给 audio_v2 的帧/字节
    down_ps = 0,                          -- 下行里 PS 封装的包数（用于判定平台用哪种）
    up_drop = 0,                          -- talk_push 失败（会话没了/队列满）
}

local function logi(...) log.info("gb28181audio", ...) end
local function logw(...) log.warn("gb28181audio", ...) end

--[[
加载依赖。失败返回 false + 原因，不抛错 —— 与 exgb28181.lua 同样的理由：
固件可能没开 LUAT_USE_AUDIO_V2，这时 require 本模块本身不该炸。
]]
local function load_deps()
    if a2 == nil then
        a2 = rawget(_G, "audio_v2")
        if a2 == nil then
            local ok, mod = pcall(require, "audio_v2")
            a2 = ok and mod or nil
        end
        if a2 == nil then
            return false, "audio_v2 不可用(固件未开 LUAT_USE_AUDIO_V2?)"
        end
    end
    if client == nil then
        local ok, mod = pcall(require, "exgb28181client")
        if not ok then
            return false, "无法加载 exgb28181client"
        end
        client = mod
    end
    if gb == nil then
        local ok, mod = pcall(require, "gb28181")
        gb = ok and mod or rawget(_G, "gb28181")
        -- gb 不可用时只有 PS 封装的下行解析不了，不是致命错误
    end
    return true
end

--[[
下行数据入口：把平台发来的音频送进喇叭。

由 start() 注册为 exgb28181client.on_audio 的回调，一般不需要自己调。

@param s    音频会话
@param body 已剥掉 RTP 头的载荷
@param is_ps 载荷是否 PS 封装
]]
function M.feed(s, body, is_ps)
    if not running or type(body) ~= "string" or #body == 0 then
        return
    end

    --[[
    **原生后端下这条分支不会走到**：C 侧已经把 PS 解封装完了，交过来的
    is_ps 恒为 false。留着它是为仍按老契约传 PS 的调用方 —— 联调工具
    tools/audio_bridge 就是直接喂 PS 给这里验重组逻辑的。

    跨包缓冲 ps_pend 仍是这里保管：`gb.ps_demux_audio` 是无状态的，
    尾部不完整的部分得由调用方留着再拼。
    ]]
    if is_ps then
        st.down_ps = st.down_ps + 1
        if gb == nil or type(gb.ps_demux_audio) ~= "function" then
            -- 只在第一次告警，避免每包刷屏
            if st.down_ps == 1 then
                logw("下行是 PS 封装，但 C 层没有 ps_demux_audio，无法解析")
            end
            return
        end
        -- 无状态解封装：C 层不持有跨调用缓冲，尾部不完整的部分由这里保管
        ps_pend = ps_pend .. body
        local pcma, consumed = gb.ps_demux_audio(ps_pend)
        if type(consumed) == "number" then
            ps_pend = ps_pend:sub(consumed + 1)
        end
        if type(pcma) ~= "string" or #pcma == 0 then
            return
        end
        body = pcma
    end

    if src_idx == nil then
        return
    end
    a2.input(src_idx, body, false)
    st.down_frames = st.down_frames + 1
    st.down_bytes  = st.down_bytes + #body
end

--[[
上行泵：把麦克风缓冲里的 G.711A 按 160 字节(20ms)切包推给平台。

为什么是轮询而不是录音回调：录音数据由框架写进 rec_zb，框架没有给 Lua 侧
"每帧回调"的钩子(只有 C 层的 record_callback_frame_cnt 机制)。
轮询的代价可以接受 —— 20ms 一次，每次只做一次 toStr/del。
]]
local function pump()
    if not running or rec_zb == nil or sess == nil then
        return
    end

    --[[
    顺手把**下行**收一轮。

    为什么挂在这里：这一拍是 20ms，正好是音频的节拍。客户端的 tick 是 1 秒，
    挂那儿的话平台推来的声音会按秒成坨地进播放器。原生后端下 C 只是把解好的
    G.711A 放进 sink 回调，收取的时机由调用方给 —— 而这里就是那个"该收的时机"。
    ]]
    client.poll_rx(sess)

    local used = rec_zb:used()
    if used < FRAME_BYTES then
        return                      -- 不足一帧，等下一拍
    end

    -- 只取整数帧：余数留在缓冲里，避免把半帧推给平台
    local n = used - (used % FRAME_BYTES)
    local pcma = rec_zb:toStr(0, n)
    rec_zb:del(0, n)
    if type(pcma) ~= "string" or #pcma == 0 then
        return
    end

    if sess.stream then
        --[[
        原生后端：**整块交过去，不在这里切包**。

        切包与时间戳推进是协议侧的固定知识，已经下沉到 C（一次调用切好），
        省掉原先每包一次跨语言往返。上面那个 `used % FRAME_BYTES` 仍然必要：
        半帧不能推给平台（会打乱对端抖动缓冲的节拍），余数留在缓冲里等下拍。
        ]]
        if client.talk_push(sess, pcma) then
            st.up_frames = st.up_frames + #pcma / FRAME_BYTES
            st.up_bytes  = st.up_bytes + #pcma
        else
            st.up_drop = st.up_drop + 1
        end
        return
    end

    -- 老后端：仍在这里按 20ms 切 —— 它那条路是 media_push，不切包。
    -- 平台侧的抖动缓冲按包长工作，整块推会破坏它的节拍
    for i = 1, #pcma, FRAME_BYTES do
        local one = pcma:sub(i, i + FRAME_BYTES - 1)
        if client.talk_push(sess, one) then
            st.up_frames = st.up_frames + 1
            st.up_bytes  = st.up_bytes + #one
        else
            st.up_drop = st.up_drop + 1
        end
    end
end

--[[
开启音频桥：打开 audio_v2 的全双工通道，并把上行泵跑起来。

@api exgb28181audio.start(session)
@table session exgb28181client 的音频会话（start_talk 的返回值或 talk/accepted 事件里的会话）
@return boolean 成功返回 true
@return string|nil 失败原因
]]
function M.start(session)
    if running then
        return false, "已启动，请先 stop()"
    end
    if type(session) ~= "table" then
        return false, "session 参数无效"
    end

    local ok, err = load_deps()
    if not ok then
        return false, err
    end

    -- 录音回调粒度为 1 帧：让 rec_zb 尽快拿到数据，泵的延迟才小
    rec_zb = zbuff.create(16 * 1024)
    if rec_zb == nil then
        return false, "录音缓冲创建失败"
    end

    -- 记录与播放都用 G.711A：两端一致，Lua 层不必碰编解码
    local r, idx = a2.speech(a2.DATA_CODEC_TYPE_G711_ALAW, rec_zb, 1,
                             a2.DATA_CODEC_TYPE_G711_ALAW,
                             SAMPLE_RATE, 16, 1)
    if not r then
        rec_zb = nil
        return false, "audio_v2.speech 失败(音频设备被占用?)"
    end
    req_idx = idx

    -- extern_source 的流模式：后续用 M.feed → audio_v2.input 往里灌下行数据
    local r2, sid = a2.extern_source(req_idx, true, false,
                                     a2.DATA_CODEC_TYPE_G711_ALAW, true,
                                     SAMPLE_RATE, 16, 1, true)
    if not r2 then
        a2.stop(req_idx)
        req_idx, rec_zb = nil, nil
        return false, "audio_v2.extern_source 失败"
    end
    src_idx = sid

    sess     = session
    ps_pend  = ""
    running  = true
    st.up_frames, st.up_bytes, st.down_frames, st.down_bytes, st.down_ps, st.up_drop = 0, 0, 0, 0, 0, 0

    -- 接管下行：start()/stop() 成对管这个槽位，见文件头说明
    client.on_audio(M.feed)

    timer = sys.timerLoopStart(pump, FRAME_MS)

    logi("音频桥已开启", session.call_id or "")
    return true
end

--[[
关闭音频桥并释放音频通道。

必须调用：audio_v2 的请求索引是全局有限的资源，不释放会一直占着音频设备，
后续的 TTS/播放器/再次对讲都拿不到。
]]
function M.stop()
    if not running then
        return true
    end
    running = false

    if timer then
        sys.timerStop(timer)
        timer = nil
    end
    if client then
        client.on_audio(nil)        -- 摘掉下行回调，避免会话销毁后还被调用
    end
    if a2 and req_idx then
        a2.stop(req_idx)            -- 会连带停掉 extern_source
    end

    req_idx, src_idx, rec_zb, sess, ps_pend = nil, nil, nil, nil, ""
    logi("音频桥已关闭")
    return true
end

--[[
查询是否已开启。
@api exgb28181audio.is_running()
@return boolean
]]
function M.is_running()
    return running
end

--[[
统计。用于现场判断问题出在哪一段：
    up_bytes   为 0 且 up_drop 增长 → talk_push 失败（会话没了/队列满）
    up_frames  为 0 且 up_bytes 为 0 → 麦克风没数据（录音通道没开起来?）
    down_ps 占满 down_frames → 平台用 PS 封装下行（对照 C 层能否解出）
@api exgb28181audio.stats()
@return table
]]
function M.stats()
    local t = {}
    for k, v in pairs(st) do t[k] = v end
    t.running = running
    return t
end

return M
