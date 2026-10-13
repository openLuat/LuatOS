--[[
@module exgb28181audio
@summary GB28181 对讲/广播的音频桥：麦克风/喇叭 ↔ voip

分工：信令与 SDP 归 exgb28181client（须设 external_audio=true + audio_port），
编解码、AEC/降噪/AGC、抖动缓冲、RTP 收发全归 voip。本模块只搬 PCM：
取录音喂 voip.pcmIn，从 voip.pcmOut 取出来写喇叭。

音频一律 PCM 16bit 单声道（DATA_CODEC_TYPE_VOIP_PCM 是 voip 注册的直通 codec）：

    local gba = require "exgb28181audio"
    gba.start(sess)     -- talk/accepted 之后
    gba.stop()

注：voip 只做 UDP 承载；平台要求 TCP 时这条路不通。
]]

local M = {}

local FRAME_MS         = 20
local FRAME_SAMPLES    = 160           -- 20ms @ 8kHz
local FRAME_PCM_BYTES  = FRAME_SAMPLES * 2
local SAMPLE_RATE      = 8000

-- 下行取不到 PCM 时补静音：不给数据播放节奏就断
local SILENCE          = string.rep("\0", FRAME_PCM_BYTES)

local a2        = nil
local voip      = nil
local client    = nil
local req_idx   = nil    -- speech 索引（录音）
local src_idx   = nil    -- extern_source 索引（播放）
local rec_zb    = nil
local sess      = nil
local timer     = nil
local running   = false

local st = {
    up_frames = 0, up_bytes = 0,
    down_frames = 0, down_bytes = 0,
    down_silence = 0,         -- voip 没数据、补了静音的帧数
    down_drop_bytes = 0,      -- 取到了却写不进喇叭
    up_drop = 0,              -- voip.pcmIn 拒收（桥接模式没开时恒涨）
    on_need_free  = -1,
}

local function logi(...) log.info("gb28181audio", ...) end

-- 固件可能没开 LUAT_USE_AUDIO_V2 / 没编 voip，缺了一样就明确报出来
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
    if voip == nil then
        voip = rawget(_G, "voip")
        if voip == nil then
            local ok, mod = pcall(require, "voip")
            voip = ok and mod or nil
        end
        if voip == nil then
            return false, "voip 不可用(固件未编 LUAT_USE_VOIP?)"
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

-- 20ms 一拍，上下行都在这拍上做完。播放是拉模型，没有数据时必须补静音
local function pump()
    if not running then
        return
    end

    local pcm = voip.pcmOut(FRAME_SAMPLES)
    if type(pcm) ~= "string" or #pcm == 0 then
        pcm = SILENCE
        st.down_silence = st.down_silence + 1
    else
        st.down_frames = st.down_frames + 1
        st.down_bytes  = st.down_bytes + #pcm
    end
    if src_idx then
        local ok, _, free = a2.input(src_idx)
        st.on_need_free = free or -1
        if ok then
            local r, wrote = a2.input(src_idx, pcm, false)
            if not r or (wrote or 0) == 0 then
                st.down_drop_bytes = st.down_drop_bytes + #pcm
            end
        end
    end

    if rec_zb then
        local used = rec_zb:used()
        if used >= FRAME_PCM_BYTES then
            -- 只取整数帧；半帧喂进去会让编码粒度错位
            local n = used - (used % FRAME_PCM_BYTES)
            local up = rec_zb:query(0, n)
            rec_zb:del(0, n)
            if type(up) == "string" and #up > 0 then
                local c = voip.pcmIn(up)
                if type(c) == "number" and c > 0 then
                    st.up_frames = st.up_frames + c / FRAME_SAMPLES
                    st.up_bytes  = st.up_bytes + c * 2
                else
                    st.up_drop = st.up_drop + 1
                end
            end
        end
    end
end

--[[
开启音频桥。

@api exgb28181audio.start(session)
@table session exgb28181client 的音频会话（talk/accepted 事件里的那个）
@return boolean
@return string|nil 失败原因
]]
function M.start(session)
    if running then
        return false, "已启动，请先 stop()"
    end
    if type(session) ~= "table" then
        return false, "session 参数无效"
    end
    if session.remote_ip == nil or session.remote_port == nil then
        return false, "会话没有对端媒体地址(SDP 未协商?)"
    end

    local ok, err = load_deps()
    if not ok then
        return false, err
    end

    -- 桥接模式：voip 只做编解码/RTP，PCM 由本模块喂入/取走。
    -- **漏了这句 pcmIn/pcmOut 全是空操作**（返回 0），而 voip.start 照样成功 ——
    -- 表现为"对讲上行一个包都没有，录音侧却一直在编码"。
    if voip.setAudioMode then
        pcall(voip.setAudioMode, voip.AUDIO_MODE_BRIDGE)
    end

    -- 四个值都来自那次 SDP 协商；ssrc 平台按 SDP 的 y= 校验
    local okv = voip.start({
        codec       = voip.PCMA,
        sample_rate = SAMPLE_RATE,
        ptime       = FRAME_MS,
        remote_ip   = session.remote_ip,
        remote_port = session.remote_port,
        local_port  = session.local_port,
        ssrc        = session.ssrc,
        aec_enable  = 1,
        aec_denoise = 1,
        aec_agc     = 1,
    })
    if not okv then
        return false, "voip.start 失败"
    end

    rec_zb = zbuff.create(4096)
    if rec_zb == nil then
        voip.stop()
        return false, "录音缓冲创建失败"
    end

    -- 录音：VOIP_PCM 是直通 codec，rec_zb 里就是原始 PCM
    local okr, rid = a2.speech(a2.DATA_CODEC_TYPE_VOIP_PCM, rec_zb, 1,
                               a2.DATA_CODEC_TYPE_VOIP_PCM,
                               SAMPLE_RATE, 16, 1)
    if not okr then
        rec_zb = nil
        voip.stop()
        return false, "audio_v2.speech 失败(音频设备被占用? 或未 setup)"
    end
    req_idx = rid

    -- 播放另开 extern_source 挂在同一请求上：下行 PCM 写到它给的索引
    local oks, sid = a2.extern_source(rid, true, false,
                                      a2.DATA_CODEC_TYPE_VOIP_PCM,
                                      true, SAMPLE_RATE, 16, 1, true)
    if not oks then
        a2.stop(rid)
        rec_zb, req_idx = nil, nil
        voip.stop()
        return false, "audio_v2.extern_source 失败"
    end
    src_idx = sid

    sess    = session
    running = true
    for k, v in pairs(st) do
        if type(v) == "number" then st[k] = 0 end
    end
    st.on_need_free = -1

    timer = sys.timerLoopStart(pump, FRAME_MS)

    logi("音频桥已开启(voip)", session.call_id or "",
         session.remote_ip .. ":" .. tostring(session.remote_port),
         "ssrc=" .. tostring(session.ssrc))
    return true
end

--[[
关闭音频桥。必须调用：audio_v2 的请求索引是全局有限资源，不释放会一直占着
音频设备；voip 不停则媒体端口不放开。
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
    if a2 and src_idx then
        a2.stop(src_idx)
    end
    if a2 and req_idx then
        a2.stop(req_idx)
    end
    if voip then
        pcall(voip.stop)
    end

    req_idx, src_idx, rec_zb, sess = nil, nil, nil, nil
    logi("音频桥已关闭")
    return true
end

--[[ 查询是否已开启
@api exgb28181audio.is_running()
@return boolean
]]
function M.is_running()
    return running
end

--[[
统计，用于现场判断问题出在哪一段：
    up_drop 持续增长        → voip 桥接模式没开（pcmIn 全拒）
    up_bytes 恒 0           → 麦克风没数据
    down_silence 持续增长   → voip 没收到可放的
    down_drop_bytes 增长    → 写不进喇叭
@api exgb28181audio.stats()
@return table 另含 t.voip（voip 自己的统计与 aec_* 指标）
]]
function M.stats()
    local t = {}
    for k, v in pairs(st) do t[k] = v end
    t.running = running
    if voip and type(voip.stats) == "function" then
        local ok, vs = pcall(voip.stats)
        if ok then t.voip = vs end
    end
    return t
end

return M
