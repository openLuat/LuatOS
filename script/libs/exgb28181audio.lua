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

start() 会**接管两个槽位**，stop() 会把它们还回去：

  exgb28181client.on_audio  下行收包入口（收到先入队）
  audio_v2.on               框架开口要数据时的写入点（拉模型，见 M.feed）

所以应用侧不要另外注册这两个，否则后注册的会覆盖前者。
]]

local M = {}

-- 20ms @ 8kHz：G.711A 一帧 = 160 字节。上行按这个粒度切包，
-- 与 talk_push 的建议值、以及 G.711 编解码器的 one_frame_sample_cnt 一致。
local FRAME_MS      = 20
local FRAME_BYTES   = 160
local SAMPLE_RATE   = 8000

local a2        = nil    -- audio_v2 模块句柄
local client    = nil    -- exgb28181client
local req_idx   = nil    -- audio_v2.speech 返回的请求索引（上行录音、下行播放都挂在它上）
local rec_zb    = nil    -- 录音缓冲（框架往里写 G.711A）
local sess      = nil    -- 绑定的 gb28181 会话
local timer     = nil    -- 上行泵
local running   = false

local st = {
    up_frames = 0, up_bytes = 0,          -- 上行：已推给平台的帧/字节
    down_frames = 0, down_bytes = 0,      -- 下行：已交给 audio_v2 的帧/字节
    down_drop_bytes = 0,                  -- 下行：进了桥但没进喇叭的字节（队列溢出丢弃）
    up_drop = 0,                          -- talk_push 失败（会话没了/队列满）

    -- 下行延迟的定位用：框架开口的频率、那一刻剩余空间多少、队列积压多少。
    -- 三个数一摆就能分清"框架不开口"和"开口了但没空间"这两种完全不同的病因。
    on_need_calls = 0,                    -- 框架开口要数据的次数
    on_need_fails = 0,                    -- 其中 input 查询失败/返回 false 的次数
    on_need_free  = -1,                   -- 最近一次上报的剩余空间
    down_q_max    = 0,                    -- 排空瞬间队列积压的条目数
}

-- 下行待播队列。**只是"到货与框架开口之间的中转"，不是抖动缓冲** —— 留太大等于
-- 给自己加延迟。实测框架开口约 100 次/秒、每次把输入口取空，所以这个队列常态是空的
-- （队列峰值 2 条）；真正需要容的是**起播瞬间平台推来的突发**（实测一次被丢掉
-- 13600 字节 ≈ 1.7 秒），所以留 500ms 余量。超了丢最老的：丢旧的比丢新的好，
-- 至少听到的是近期的声音。
local DOWN_Q_MAX   = 4 * 1024
local down_q       = {}
local down_q_bytes = 0

--[[
抖动缓冲的目标深度：开局先攒够这么多字节再开始喂。

为什么需要：平台推来的 RTP 是**成块**的（实测 800 字节一块 = 100ms），而框架是
"开口要多少才给多少"，实测每秒开口约 55 次、每次只能拿到约 145 字节 —— 不到一帧
(160 字节)。也就是播放侧一直卡在"刚好够、随时会饿"的临界点，网络一抖就断。

攒够这一段后一次性放出去，播放 fifo 里就**长期保有**这段头寸（之后进出等速，
它不会被消耗掉），抖动由它吸收。代价是固定增加这一段延迟 —— 拿延迟换连续。
]]
local DOWN_PREBUF  = 2400      -- 300ms @ G.711A 8KB/s
local down_fed     = false     -- 本次会话是否已过预缓冲

--[[
框架开口要数据时**唯一**的写入点（拉模型，见 M.feed 的说明）。

    audio_v2.input(idx)             查剩余空间 → (ok, ?, free_len)
    audio_v2.input(idx, data, 结束)  写入

写不完的留在队头，下一轮继续；一旦返回失败或写入 0 字节就停手 ——
硬塞的结果是"写成功但进不了解码器"，正是这个 bug 的原形。
]]
local function on_need(idx, ev)
    if not running or ev ~= a2.REQUEST_NEED_NEW_DATA then
        return
    end
    if idx ~= req_idx then
        return
    end

    st.on_need_calls = st.on_need_calls + 1
    if #down_q > st.down_q_max then
        st.down_q_max = #down_q
    end

    -- 抖动缓冲：攒够 DOWN_PREBUF 再放行。这段期间播放侧会灌空白
    -- （实测空白累计到 4 次才算播放结束，约 2 秒，300ms 远在安全线内）。
    if not down_fed then
        if down_q_bytes < DOWN_PREBUF then
            return
        end
        down_fed = true
    end

    local ok, _, free = a2.input(req_idx)
    st.on_need_free = free or -1
    if not ok then
        st.on_need_fails = st.on_need_fails + 1
        return
    end

    while free and free >= FRAME_BYTES and #down_q > 0 do
        local body = down_q[1]
        local r, wrote = a2.input(req_idx, body, false)
        if not r or (wrote or 0) == 0 then
            break
        end
        if (wrote or 0) < #body then
            down_q[1] = body:sub((wrote or 0) + 1)     -- 部分写入，余下留队头
            down_q_bytes = down_q_bytes - (wrote or 0)
            break
        end
        table.remove(down_q, 1)
        down_q_bytes = down_q_bytes - #body
        free = free - (wrote or 0)
    end
end

local function logi(...) log.info("gb28181audio", ...) end

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
    return true
end

--[[
下行数据入口：把平台发来的音频送进喇叭。

由 start() 注册为 exgb28181client.on_audio 的回调，一般不需要自己调。

@param s    音频会话
@param body 已经剥掉 RTP 头、必要时解过 PS 的 G.711A（收包侧的处理都在 C 里）
]]
function M.feed(s, body)
    if not running or type(body) ~= "string" or #body == 0 then
        return
    end

    if req_idx == nil then
        return
    end

    --[[
    **只入队，不直接写。**

    audio_v2 的输入是**拉模型**：框架在 REQUEST_NEED_NEW_DATA 里问你要数据，
    并在那一刻才把这个口子接到解码器上。收包就写等于写进一个还没接上的口子 ——
    input() 会返回"写成功"，数据却永远到不了解码器，播放侧只能灌空白音：
    实机表现就是"下行字节数一路涨、喇叭只有底噪"。真机上验过：同一段 PCM，
    盲喂时解码器报 `decode once, no data output`，改成按需喂立刻读到
    `decode raw mode read N bytes`，喇叭出声。

    所以这里排队，写入由 on_need() 在框架开口时做。
    ]]
    st.down_frames = st.down_frames + 1
    st.down_bytes  = st.down_bytes + #body

    down_q[#down_q + 1] = body
    down_q_bytes = down_q_bytes + #body

    -- 平台突发/网络抖动时队列可能涨得比喇叭消耗快；超上限丢最老的，
    -- 并计入 down_drop_bytes（这个量就是"进了桥但没进喇叭"的字节）。
    while down_q_bytes > DOWN_Q_MAX and #down_q > 0 do
        local old = table.remove(down_q, 1)
        down_q_bytes = down_q_bytes - #old
        st.down_drop_bytes = st.down_drop_bytes + #old
    end
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
    挂那儿的话平台推来的声音会按秒成坨地进播放器。C 只是把解好的 G.711A
    放进 sink 回调，收取的时机由调用方给 —— 而这里就是那个"该收的时机"。
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

    --[[
    **整块交过去，不在这里切包。**

    切包与时间戳推进是协议侧的固定知识，在 C 里做（一次调用切好），
    省掉每包一次跨语言往返。上面那个 `used % FRAME_BYTES` 仍然必要：
    半帧不能推给平台（会打乱对端抖动缓冲的节拍），余数留在缓冲里等下拍。
    ]]
    if client.talk_push(sess, pcma) then
        st.up_frames = st.up_frames + #pcma / FRAME_BYTES
        st.up_bytes  = st.up_bytes + #pcma
    else
        st.up_drop = st.up_drop + 1
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

    --[[
    下行的目标就是 speech 请求自己，不另开 extern_source。

    解码泵读的是 `request_block->org_input_data_fifo`（见 luat_audio_core.c 的
    _audio_decode_stream_to_fifo），而 audio_v2.input(request_index, ...) 才是
    往那个口子写的 API。extern_source 建的是**另一个** fifo：往里写数据没人读，
    真机日志表现为 `decode input fifo empty, decode end` + 播放侧一路灌空白音。
    ]]
    sess     = session
    running  = true
    st.up_frames, st.up_bytes, st.down_frames, st.down_bytes, st.up_drop = 0, 0, 0, 0, 0
    st.down_drop_bytes = 0

    down_q, down_q_bytes = {}, 0        -- 上一次会话的残留不能带进来
    down_fed = false                    -- 新会话重新做一次预缓冲

    -- 接管下行：start()/stop() 成对管这两个槽位，见文件头说明
    client.on_audio(M.feed)             -- 收包入口（只入队）
    a2.on(on_need)                      -- 框架开口要数据时的写入点

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
    if a2 then
        pcall(a2.on, nil)           -- 把 audio_v2 的回调槽位还回去（应用可能自己要用）
    end
    if a2 and req_idx then
        a2.stop(req_idx)            -- 会连带停掉 extern_source
    end

    req_idx, rec_zb, sess = nil, nil, nil
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
    down_bytes 一直为 0 → 下行没收到（对照 C 层 stream_stats 的 rx_* 计数）
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
