--[[
@module exgb28181audio_raw
@summary GB28181 音频的"裸 C stream"后端（PC e2e / 板上探针用）

发布库 exgb28181client 不再自带音频媒体：音频会话一律 external，由调用方
选一个后端。本模块就是其中一个后端 —— 直接用 C 的 gb28181.stream_* 建链、
收 RTP/剥头/解 PS，把 PCMA 交给 on_pcm；上行用 stream_push_audio。

它不依赖 voip/audio_v2，因此 PC 模拟器也能跑；demo 的 AUDIO_PROBE 也用它。
普通应用应使用 exgb28181audio（native/bridge）或板级私有后端（如 air1103）。

    local raw = require "exgb28181audio_raw"
    raw.start(sess, { on_pcm = function(sess, pcma) ... end })
    while running do raw.pump(); sys.wait(20) end
    raw.stop()
]]

local M = {}

local ok, mod = pcall(require, "gb28181")
local gb = ok and mod or rawget(_G, "gb28181")

local st = {
    stream = nil, sess = nil, running = false,
    link_up = false,
    rx_frames = 0, rx_bytes = 0,   -- 下行：交给 on_pcm 的帧数/字节
    tx_bytes = 0,                  -- 上行：成功入队的字节
    last_error = nil,
}

local function now_ms()
    local s, us = mcu.ticks2(0)
    return s * 1000 + us // 1000
end

local function logi(...) log.info("gb28181audio", ...) end

local function fail(msg)
    st.last_error = msg
    return false, msg
end

--[[
裸流后端是否可用（只检查 C stream API，不需要 voip/audio_v2）。

@api exgb28181audio_raw.available()
@return boolean
@return string|nil 原因
]]
function M.available()
    if not gb or not gb.stream_new then
        return false, "固件没编 gb28181.stream_*"
    end
    return true
end

--[[
为一条音频会话建立裸流通道。

@api exgb28181audio_raw.start(session, opts)
@table session exgb28181client.talks() 里的音频会话
@table opts
    on_pcm   function(session, pcma) 收到下行 PCMA 时回调（pump 时触发）
    adapter  网络适配器索引，缺省 0（默认网卡）
@return boolean
@return string|nil 失败原因
]]
function M.start(session, opts)
    opts = opts or {}
    if st.running then return fail("已启动，请先 stop()") end
    if type(session) ~= "table" then return fail("session 参数无效") end
    local okapi, why = M.available()
    if not okapi then return fail(why) end

    local port = tonumber(session.local_port)
    if not port or port <= 0 then return fail("会话没有本地端口") end
    local transport = session.transport or "udp"
    local mode
    if transport == "udp" then mode = "udp"
    elseif transport == "tcp" then mode = "tcp"
    elseif transport == "tcp_passive" then mode = "tcp_passive"
    else return fail("未知承载: " .. tostring(transport)) end

    local stream = gb.stream_new(session.ssrc or 0, 8, 0, opts.adapter or 0)
    if not stream then return fail("stream_new 失败") end
    if not gb.stream_enable_rx(stream) then
        gb.stream_close(stream, 1)
        return fail("stream_enable_rx 失败")
    end
    gb.stream_set_sink(stream, function(pcma)
        st.rx_frames = st.rx_frames + 1
        st.rx_bytes  = st.rx_bytes + #pcma
        if type(opts.on_pcm) == "function" then
            local ok, err = pcall(opts.on_pcm, session, pcma)
            if not ok then log.error("gb28181audio", "on_pcm 异常", tostring(err)) end
        end
    end)

    local oke, err = gb.stream_open(stream, mode, port)
    if not oke then
        gb.stream_close(stream, 1)
        return fail(err or "stream_open 失败")
    end
    if mode ~= "tcp_passive" then
        if not session.remote_ip or not session.remote_port then
            gb.stream_close(stream, 1)
            return fail("会话没有对端媒体地址")
        end
        oke, err = gb.stream_connect(stream, session.remote_ip, session.remote_port)
        if not oke then
            gb.stream_close(stream, 1)
            return fail(err or "stream_connect 失败")
        end
    end

    st.stream, st.sess, st.running = stream, session, true
    st.link_up = (mode == "udp")
    st.rx_frames, st.rx_bytes, st.tx_bytes = 0, 0, 0
    st.last_error = nil
    -- 注意：**不要**把它挂到 session.stream 上。音频媒体归本模块独占，
    -- client 的会话回收会去 poll 同名 stream 的链路事件，两边抢同一份事件
    -- 会让这里丢 online/closed。需要读数时用 stats().stream。
    logi("裸流音频已启动", session.call_id or "", transport,
         tostring(session.remote_ip) .. ":" .. tostring(session.remote_port),
         "local=" .. tostring(port))
    return true
end

--[[
收一轮链路事件 + 下行包，再泵一次发送队列。调用方按 20ms 节拍调用。

@api exgb28181audio_raw.pump()
@return int 本轮投递的帧数（已交给 on_pcm）
@return int 本轮发出的字节数
]]
function M.pump()
    if not st.stream then return 0, 0 end
    local now = now_ms()
    local ev, param = gb.stream_poll_ev(st.stream, now)
    while ev do
        if ev == "online" then
            st.link_up = true
        elseif ev == "error" then
            st.link_up = false
            log.warn("gb28181audio", "媒体链路可疑事件", tostring(param))
        elseif ev == "closed" then
            st.link_up = false
        end
        ev, param = gb.stream_poll_ev(st.stream, now)
    end
    local rx = gb.stream_poll_rx(st.stream) or 0
    local tx = gb.stream_pump(st.stream, now) or 0
    return rx, tx
end

--[[
把一段 PCMA 交给上行队列（按 20ms 切片由 C 完成）。

@api exgb28181audio_raw.talk_push(session, pcma)
@table session
@string pcma
@return boolean
]]
function M.talk_push(session, pcma)
    if not st.running or not st.stream then return false end
    if type(pcma) ~= "string" or #pcma == 0 then return false end
    local took = gb.stream_push_audio(st.stream, pcma)
    if took and took > 0 then
        st.tx_bytes = st.tx_bytes + took
        return true
    end
    return false
end

--[[
关闭裸流通道。可重复调用。

@api exgb28181audio_raw.stop()
@return boolean
]]
function M.stop()
    if st.stream then
        gb.stream_close(st.stream, 1)
    end
    st.stream, st.sess, st.running, st.link_up = nil, nil, false, false
    return true
end

--[[
查询是否在运行。

@api exgb28181audio_raw.is_running()
@return boolean
]]
function M.is_running()
    return st.running
end

--[[
统计。顶层字段与另外两个音频后端保持同一形状。

@api exgb28181audio_raw.stats()
@return table
]]
function M.stats()
    local vs = {}
    if st.stream and gb.stream_stats then
        local ok, v = pcall(gb.stream_stats, st.stream)
        if ok and type(v) == "table" then vs = v end
    end
    -- link_up 以 C 的缓存为准（pump 里 poll_ev 更新），模块自己的标记是兜底
    local link_up = (type(vs.link_up) == "boolean") and vs.link_up or st.link_up
    return {
        running      = st.running,
        mode         = st.running and "raw" or nil,
        mic_active   = false,
        link_up      = link_up,
        up_bytes     = st.tx_bytes,
        down_bytes   = st.rx_bytes,
        down_frames  = st.rx_frames,
        last_error   = st.last_error,
        stream       = vs,
    }
end

--[[
最近一次 start 失败的原因。

@api exgb28181audio_raw.last_error()
@return string|nil
]]
function M.last_error()
    return st.last_error
end

return M
