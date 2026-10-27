--[[
@module  voice
@summary 汤姆猫 - 中文台词播报（四种后端自动降级，没有 TTS 固件也能说话）
@version 2.2
@date    2026.10.25
@author  江访

=== 为什么搞四个后端 ===
不同 Air8607 固件带的东西不一样：有的固件内置 exaudio 扩展库，有的只编了
audio_v2/audio C 库，有的两者都没有。所以启动时按顺序探测，谁可用用谁：

  1. ex_tts     exaudio 存在 + 固件有 audio_v2.tts/audio.tts
                 -> exaudio.play_start({type = 1, content = 文本}) —— 官方推荐路径
  2. ex_stream  exaudio 存在（不一定有 TTS）
                 -> 播 res/voice/<key>.wav 的 PCM（流式），不需要任何解码器
  3. av2_tts    没有 exaudio，但固件有 audio_v2.tts
                 -> 自己配 DAC + PA，直接 audio_v2.tts(文本)
  4. aud_tts    没有 exaudio / audio_v2，但固件有旧框架 audio.tts
                 -> audio.config + audio.setBus(BUS_DAC) + audio.tts(文本)
  5. 静音        四个都不行：交互/气泡/动画照常，状态行显示诊断码

=== DAC 模式最小配置（后端 3）的依据 ===
照抄 script/libs/exaudio.lua 的 audio_v2_setup + pm(RESUME)：
  audio_v2.on(cb) / config_pa_power_ctrl(...) / soft_volume(...)
  起播前 shutdown(false,false,false) 唤醒 + 拉高 PA，然后 audio_v2.tts(text, pri)
DAC 模式不需要配 I2S 和 codec，所以这套足够。

=== 响应速度 ===
setup/音量在 init() 做一次并保持唤醒；say() 里只有一段很短的通路准备（见下）。
路径 2 的 PCM 后台预读进内存，连点是直接换播放指针（即时打断）。

=== 为什么"只有第一句会播报"（v2.2 修的就是这个）===
TTS 路径原来有两个坑，任何一个都足以让第二句以后彻底没声：

1. busy 是单向闩锁。st.busy 只由音频库的"播完回调"清，
   而 REQUEST_END 在被打断/被高优先级顶掉/库内部请求残留/合成失败时都可能丢。
   丢一次以后 say() 永远走 st.pending 分支、连 play_start 都不再调用，
   表现为"第一句正常，之后怎么点都没反应"。
   -> 现在每句都挂一个按时长估算的看门狗（arm_watchdog），超时强制收尾；
      回调带播报代次 gen，过期回调直接丢弃，不会误清新请求的 busy。

2. 起播前没有重建音频通路。同款硬件的 factory tts_app.lua 里写得很明确：
   setup 幂等、要"每次起播前调用保证通路完整"，并且先 play_stop 清掉上一条，
   再等 DAC/PA 上电（他们用 100ms）。少了这段，第二句 play_start 可能返回 true
   但不出声、也不回调 REQUEST_END —— 和第 1 点叠在一起就是永久静音。
   -> 现在 ex_tts 起播前走 tts_prep(): play_stop -> setup+vol+pm(RESUME) -> wait(60)。
]]

local T = require "theme"

local M = {}

-- mode: nil(未探测) / "ex_tts" / "ex_stream" / "av2_tts" / "aud_tts" / "silent"
local st = {
    ready = false,
    mode = nil,
    enabled = true,
    busy = false,
    pending = nil,
    req_gen = 0,        -- 最近一次起播的代次（audio_v2/audio 的结束回调凭它认领）
    last = "",
    bytes = 0,
    diag = "",          -- 给界面/日志看的探测结果
}
M.st = st

-- ==================== 库探测 ====================
local function has_fn(t, k)
    if t == nil then return false end
    local ok, f = pcall(function() return t[k] end)
    return ok and type(f) == "function"
end

--[[取固件库：先看全局（部分内置库会挂在 _G），再 require
@return lib|nil, err
]]
local function get_lib(name)
    local g = rawget(_G, name)
    if g then return g, nil end
    local ok, lib = pcall(require, name)
    if not ok then return nil, tostring(lib) end
    if lib == nil then return nil, "require 返回 nil" end
    return lib, nil
end

local ex, av2, aud          -- exaudio / audio_v2 / audio(旧框架)
local ex_err, av2_err, aud_err

local AUDIO_ID = 0          -- 旧框架 audio 的多媒体通道号

local function pa_set(on)
    if gpio and gpio.setup then gpio.setup(T.audio.pa_ctrl, on and 1 or 0) end
end

-- ==================== 播报代次 / 收尾 / 看门狗 ====================
-- gen：每次起播 +1。旧请求的回调凭旧代次被丢弃，避免"上一条的结束事件"
-- 把新起播的 busy 清掉（会导致重复起播）或者反过来把 busy 永远焊死。
local gen = 0

local function bump_gen()
    gen = gen + 1
    return gen
end

--[[收尾：清 busy 并把挂起的那句接上
@param number my_gen 这次播报的代次（nil = 无条件收尾）
@param string why    非 nil 时打一条告警（看门狗超时 / 异常路径用）
]]
local function finish(my_gen, why)
    if my_gen and my_gen ~= gen then return end     -- 过期回调，忽略
    if not st.busy then return end
    st.busy = false
    if why then log.warn("voice", why, st.last) end
    local p = st.pending
    st.pending = nil
    if p and st.enabled and st.ready then
        sys.taskInit(function()
            if not st.busy and st.enabled then M.say(st.last_key, p) end
        end)
    end
end

--[[看门狗：播完回调丢了也要能把 busy 解开
没有它，一次 REQUEST_END 丢失就是永久静音（老的"只播第一句"故障）。
@param number my_gen 代次
@param number ms     超时时间（按台词字数估）
]]
local function arm_watchdog(my_gen, ms)
    sys.taskInit(function()
        sys.wait(ms)
        if my_gen == gen then finish(my_gen, "播报超时没收到结束回调，强制收尾") end
    end)
end

-- 按字符数估播报时长（汉字 3 字节、约 0.24s/字），给看门狗兜底用
local function say_ms(text)
    local chars = #text / 3
    local ms = 1500 + chars * 240
    if ms < 3000 then ms = 3000 elseif ms > 20000 then ms = 20000 end
    return math.floor(ms)
end

-- exaudio 的通路配置：字段与 factory/app/common/tts_app.lua 的 tts_setup 对齐
local EX_SETUP = {
    model = T.audio.model,
    pa_ctrl = T.audio.pa_ctrl,
    pa_on_level = T.audio.pa_on_level,
    dac_delay = T.audio.dac_delay,
}

--[[打开/重建 exaudio 通路（setup + 音量 + 唤醒）；setup 幂等，可反复调用
每次传一份新表：exaudio 会把参数表存成内部状态，复用同一张表有被改写的风险。
@return boolean
]]
local function ex_open()
    return (pcall(function()
        local cfg = {}
        for k, v in pairs(EX_SETUP) do cfg[k] = v end
        if ex.setup(cfg) == false then error("setup 返回失败") end
        if has_fn(ex, "vol") then ex.vol(T.audio.vol) end
        if has_fn(ex, "pm") and ex.RESUME then ex.pm(ex.RESUME) end
    end))
end

--[[TTS 起播前的通路准备（顺序照抄 tts_app.lua：先 stop 再 setup 再起播）
不做的两个后果：
  1. 上一条请求在框架里残留 -> 新 play_start 返回 true 但不出声、也不回调；
  2. 播完后通路已下电 -> 直接静音。
代价每句约 60ms（DAC/PA 上电），画面在起播前早就刷出去了，听感不变。
]]
local function tts_prep()
    local mode = st.mode
    if mode == "ex_tts" then
        if has_fn(ex, "play_stop") then pcall(ex.play_stop, { type = 1 }) end
        ex_open()
        sys.wait(60)
    elseif mode == "av2_tts" then
        if has_fn(av2, "stop") then pcall(av2.stop) end
        pa_set(true)
        if has_fn(av2, "shutdown") then pcall(av2.shutdown, false, false, false) end
    elseif mode == "aud_tts" then
        if has_fn(aud, "stop") then pcall(aud.stop, AUDIO_ID) end
        pa_set(true)
    end
end

-- ==================== 后端 2 用：WAV 资源 ====================
-- 上板时把 res/voice 整个目录一起拷过去；这里按常见挂载点依次找
local RES_DIRS = { "/res/voice/", "/luadb/res/voice/", "res/voice/", "/voice/" }
local KEYS = { "head", "ear", "eye", "face", "belly", "paw", "foot", "tail" }
local clip = {}          -- key -> PCM 字符串（16bit LE）
local cur = nil          -- 正在播的片段 { pcm, pos, n }
local BLOCK = T.audio.block
local silence = string.rep("\0", BLOCK * 2)

--[[读 WAV，跳过头部取 data 段（只认 PCM WAV）]]
local function read_wav(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local size = f:seek("end")
    f:seek("set", 0)
    local head = f:read(64)
    local off = head and head:find("data", 1, true)
    if not off or off + 7 > #head then
        f:close()
        return nil
    end
    local dlen = string.unpack("<I4", head, off + 4)
    local pcm_off = off + 8 - 1                 -- 0-based
    if pcm_off + dlen > size then dlen = size - pcm_off end
    if dlen < 320 then
        f:close()
        return nil
    end
    f:seek("set", pcm_off)
    local pcm = f:read(dlen)
    f:close()
    return pcm
end

local function load_clip(key)
    for _, dir in ipairs(RES_DIRS) do
        local pcm = read_wav(dir .. key .. ".wav")
        if pcm then return pcm, dir end
    end
    return nil
end

-- 开一次流式会话（可重开：请求被框架回收后必须重新 play_start）
local function stream_open()
    return (pcall(function()
        assert(ex.play_start({
            codec_id = 0,                   -- RAW / PCM
            type = 2,                       -- 流式
            sampling_rate = T.audio.rate,
            sampling_depth = 16,
            signed_or_unsigned = true,
            stream_buffer_size = 2048,      -- 约 64ms：小一点，点了就出声
        }), "exaudio.play_start(流式) 失败")
    end))
end

local function stream_task()
    if not stream_open() then
        log.warn("voice", "流式播放不可用，退到 TTS 或静音")
        st.ready = false
        return
    end

    local wr = ex.play_stream_write
    local produced = 0
    local t0 = (mcu and mcu.ticks and mcu.ticks()) or 0
    local hz = (mcu and mcu.hz and mcu.hz()) or 1000
    local tpm = (hz > 1) and (hz / 1000) or 1
    local block_ms = BLOCK * 1000 / T.audio.rate
    local fails = 0

    while true do
        local data
        local c = cur
        if c and st.enabled then
            local room = c.n - c.pos + 1
            local cnt = room < BLOCK and room or BLOCK
            data = c.pcm:sub((c.pos - 1) * 2 + 1, (c.pos + cnt - 1) * 2)
            c.pos = c.pos + cnt
            if c.pos > c.n then cur = nil end
        else
            data = silence
        end

        local wok, ret = pcall(wr, data)
        if not wok or ret == false then
            -- 写入连续失败＝C 层的流式请求已经没了（被回收/被打断），
            -- 光等下去救不回来，必须重开一次会话，否则第二句以后永远没声。
            fails = fails + 1
            if fails >= 10 then
                fails = 0
                log.warn("voice", "流式写入连续失败，重开流式会话")
                if not stream_open() then sys.wait(200) end
            else
                sys.wait(10)
            end
        else
            fails = 0
            produced = produced + block_ms
            local now = (mcu and mcu.ticks and mcu.ticks()) or 0
            local el = (now >= t0) and ((now - t0) / tpm) or 0
            local lead = produced - el
            if lead > block_ms then
                sys.wait(math.floor(lead - block_ms + 2))
            end
        end
    end
end

-- ==================== 后端 1/2：exaudio ====================
local function ex_tts_start(text)
    pcall(tts_prep)
    local my = bump_gen()
    st.req_gen = my
    st.busy = true
    local ok, ret = pcall(ex.play_start, {
        type = 1,
        content = text,
        priority = T.audio.priority,
        cbfnc = function() M.done(my) end,
    })
    if not ok or ret == false then
        st.busy = false
        return false, tostring(ret)
    end
    arm_watchdog(my, say_ms(text))
    return true
end

--[[播报结束回调：把连点时挂起的那句接上
@param number my_gen 起播时的代次（nil 兼容裸调用）
]]
function M.done(my_gen)
    finish(my_gen)
end

-- ==================== 后端 3：直连 audio_v2 ====================
local function av2_setup()
    if not has_fn(av2, "tts") then return false end
    local ok = pcall(function()
        if has_fn(av2, "on") then
            -- 回调签名是 (请求索引, 事件, 附加参数)。少写一个参数会拿 request_index
            -- 去和 REQUEST_END 比，永远不成立 -> busy 清不掉 -> 只有第一句能播。
            av2.on(function(_, event)
                if event == av2.REQUEST_END then M.done(st.req_gen) end
            end)
        end
        if has_fn(av2, "config_pa_power_ctrl") then
            av2.config_pa_power_ctrl(true, T.audio.pa_ctrl, T.audio.pa_on_level, 10)
        end
        if has_fn(av2, "soft_volume") then av2.soft_volume(T.audio.vol) end
        if has_fn(av2, "shutdown") then av2.shutdown(false, false, false) end  -- 唤醒
    end)
    if ok then pa_set(true) end
    return ok
end

local function av2_tts_start(text)
    pcall(tts_prep)
    local my = bump_gen()
    st.req_gen = my
    st.busy = true
    local ok, ret = pcall(av2.tts, text, T.audio.priority)
    if not ok or ret == false then
        st.busy = false
        return false, tostring(ret)
    end
    arm_watchdog(my, say_ms(text))
    return true
end

-- ==================== 后端 4：直连旧框架 audio ====================
local function aud_setup()
    if not has_fn(aud, "tts") then return false end
    local ok = pcall(function()
        if has_fn(aud, "config") then
            aud.config(AUDIO_ID, T.audio.pa_ctrl, T.audio.pa_on_level, 0, 10)
        end
        if has_fn(aud, "setBus") and aud.BUS_DAC then
            aud.setBus(AUDIO_ID, aud.BUS_DAC, { dacid = 0 })
        end
        if has_fn(aud, "on") then
            local d1, d2 = aud.PLAY_DONE, aud.SPEAK_DONE
            aud.on(function(_, event)
                if (d1 and event == d1) or (d2 and event == d2) then M.done(st.req_gen) end
            end)
        end
        if has_fn(aud, "vol") then aud.vol(AUDIO_ID, T.audio.vol) end
    end)
    if ok then pa_set(true) end
    return ok
end

local function aud_tts_start(text)
    pcall(tts_prep)
    local my = bump_gen()
    st.req_gen = my
    st.busy = true
    local ok, ret = pcall(aud.tts, AUDIO_ID, text)
    if not ok or ret == false then
        st.busy = false
        return false, tostring(ret)
    end
    arm_watchdog(my, say_ms(text))
    return true
end

-- ==================== 对外接口 ====================

local function pick_backend()
    ex, ex_err = get_lib("exaudio")
    av2, av2_err = get_lib("audio_v2")
    aud, aud_err = get_lib("audio")

    st.diag = string.format("ex:%d a2:%d au:%d",
        ex and 1 or 0, av2 and 1 or 0, aud and 1 or 0)

    -- 1. exaudio + TTS
    if ex and has_fn(ex, "setup") and has_fn(ex, "play_start") then
        local has_tts = has_fn(av2, "tts") or has_fn(aud, "tts")
        if has_tts then
            if ex_open() then return "ex_tts" end
            log.warn("voice", "exaudio 初始化失败，尝试直连 audio_v2")
        end
        -- 2. exaudio + 流式 PCM（不需要 TTS）
        if has_fn(ex, "play_stream_write") then
            if ex_open() then return "ex_stream" end
            log.warn("voice", "exaudio 流式初始化失败，尝试直连 audio_v2")
        end
    end

    -- 3. 直连 audio_v2（需要固件带 tts）
    if av2_setup() then return "av2_tts" end
    -- 4. 直连旧框架 audio
    if aud_setup() then return "aud_tts" end

    return nil
end

--[[初始化：探测后端、配置通路、（WAV 路径）后台加载资源
@return boolean 是否具备出声能力
]]
function M.init()
    if st.ready then return true end

    st.mode = pick_backend()
    if not st.mode then
        pa_set(false)
        st.ready = false
        log.warn("voice", "无可用音频后端，进静音模式（交互与气泡照常）",
            "诊断", st.diag,
            "exaudio:", tostring(ex_err),
            "audio_v2:", tostring(av2_err),
            "audio:", tostring(aud_err))
        return false
    end

    st.ready = true
    log.info("voice", "语音就绪 后端", st.mode, "音量", T.audio.vol, "诊断", st.diag)

    if st.mode == "ex_stream" then
        sys.taskInit(stream_task)
        -- 后台逐句读进内存，点的时候不碰文件系统
        sys.taskInit(function()
            for _, k in ipairs(KEYS) do
                if not clip[k] then
                    local pcm, dir = load_clip(k)
                    if pcm then
                        clip[k] = pcm
                        st.bytes = st.bytes + #pcm
                        if not st.res_dir then st.res_dir = dir end
                    else
                        log.warn("voice", "缺少语音资源", k .. ".wav（放进 res/voice/）")
                    end
                end
                sys.wait(10)
            end
            log.info("voice", "语音资源就绪", st.bytes, "字节 目录", tostring(st.res_dir or "-"))
        end)
    end
    return true
end

--[[说一句话（非阻塞，立即返回）
@param string key 部位标识（对应 res/voice/<key>.wav，路径 2 用）
@param string text 台词文本（TTS 路径用）
@return number 1 已起播 / 0 未播
]]
function M.say(key, text)
    if not st.enabled or not st.ready then return 0 end
    st.last_key = key

    local mode = st.mode
    if mode == "ex_tts" or mode == "av2_tts" or mode == "aud_tts" then
        if type(text) ~= "string" or text == "" then return 0 end
        st.last = text
        if st.busy then
            st.pending = text           -- 只留最后一句，不排队积压
            log.info("voice", "上一句还没播完，挂起", text)
            return 0
        end
        local ok
        if mode == "ex_tts" then
            ok = ex_tts_start(text)
        elseif mode == "av2_tts" then
            ok = av2_tts_start(text)
        else
            ok = aud_tts_start(text)
        end
        if not ok then
            log.warn("voice", "起播失败", mode, text)
            return 0
        end
        return 1
    end

    if mode == "ex_stream" then
        local pcm = clip[key]
        if not pcm then
            pcm = load_clip(key)        -- 后台还没读到：立刻补读一次
            if pcm then clip[key] = pcm end
        end
        if not pcm then return 0 end
        st.last = key
        cur = { pcm = pcm, pos = 1, n = #pcm // 2 }   -- 直接换指针 = 即时打断
        return 1
    end
    return 0
end

function M.stop()
    st.pending = nil
    st.busy = false
    bump_gen()          -- 上一条的回调别再动状态
    cur = nil
    local mode = st.mode
    if mode == "ex_tts" and has_fn(ex, "play_stop") then
        pcall(ex.play_stop, { type = 1 })
    elseif mode == "av2_tts" and has_fn(av2, "stop") then
        pcall(av2.stop)
    elseif mode == "aud_tts" and has_fn(aud, "stop") then
        pcall(aud.stop, AUDIO_ID)
    end
end

--[[开关声音（关了顺手把功放拉低，免得底噪）
@return boolean 当前是否开启
]]
function M.set_enabled(on)
    st.enabled = on and true or false
    if not st.enabled then
        st.pending = nil
        st.busy = false
        cur = nil
        M.stop()
        pa_set(false)
    elseif st.ready then
        if st.mode == "ex_tts" then
            -- 关闭时 stop 已经把音频通路下电，光 pm(RESUME) 恢复不了，得重跑 setup
            ex_open()
        elseif st.mode == "ex_stream" then
            if has_fn(ex, "pm") and ex.RESUME then pcall(ex.pm, ex.RESUME) end
        elseif st.mode == "av2_tts" and has_fn(av2, "shutdown") then
            pcall(av2.shutdown, false, false, false)
        end
        pa_set(true)
    end
    log.info("voice", st.enabled and "语音 开" or "语音 关")
    return st.enabled
end

function M.available()
    return st.ready
end

return M
