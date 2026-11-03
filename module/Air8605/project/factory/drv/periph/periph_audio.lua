--[[
@module  periph_audio
@summary 录音播放外设驱动（config.peripherals 中 type="audio"）
@version 1.0
@date    2026.10.26
@author  江访

=== 配置示例 ===

config/eng_xxx.lua 声明（板上只有一路音频，hw.audio 是硬件表，peripherals 只登记测试点）：
   hw = {
       audio = { model = "air1103", uart_id = 6, audio_mode = "new",
                 play_vol = 70, mic_vol = 70, record_format = "PCM_16000" },
   },
   peripherals = {
       { type = "audio", id = "audio1", name = "录音播放", record_seconds = 5 },
   }

=== 接口 ===

M.init(params)         → handle | false, err
M.list()               → { {id=, name=, handle=}, ... }
M.get(id)              → handle
M.reset_all()          → 关闭全部实例并清空注册表

handle.id / handle.name / handle.params
handle:start()         → ok, err      初始化音频（exaudio.setup，幂等）
handle:stop()          → ok           停止录音/播放并关掉音频
handle:record_start([秒]) → ok, err   录音（缺省 record_seconds 秒），可提前 record_stop
handle:record_stop()   → ok, err      提前结束录音并落盘
handle:play_start()    → ok, err      回放最近一次录音
handle:play_stop()     → ok, err      停止回放
handle:status()        → { enabled=bool, info=string }

=== 约定 ===

- 音频硬件一律读 config.hw.audio（model / uart_id / audio_mode / 音量 / 录音格式），
  没配 hw.audio 的板子 init 直接失败，"功能测试"里也不会出现「音频」组
- Air1103（model="air1103"）录音固定 PCM_16000（16kHz/16bit/单声道），回放走流式 PCM；
  其他 model 按 hw.audio.record_format 录成文件，amr/wav/mp3 走 exaudio 文件播放
- exaudio.setup 入参由 app/common/audio_hw 统一组装（必带 uart_id/audio_mode）。
  Air1103 实际接 UART6，漏传 uart_id 会被 exaudio 缺省绑到 UART1（隔离 485 那一路），
  现象是录音采不到数据、回放也没声音
- 录音起播后做 MIC 就绪探测（2.5s）：没采到数据直接报
  「未收到MIC数据，请检查供电、UART和固件」，不让用户对着静音录音等满时长
- Air1103 每次录音都复位芯片，恢复 MIC 上行前落盘的是静音，
  下发给 exaudio 的时长补 2 秒，用户要几秒就录到几秒有效音频
- 录音一律「函数 path 手动落盘」：字符串 path 在 exaudio 内部按 "ab" 追加写，不会创建文件
  （与 module/Air8784/project/factory/user/factory.lua 同款写法）
- 状态经 sys.publish("AUDIO_TEST_STATE", id, state, info) 广播，
  state 取 idle / recording / playing / error
- 所有 exaudio.* 调用 pcall 包裹，失败返回 false + 错误串；exaudio 是固件扩展库，
  须 require 绑定，裸用全局 exaudio 在 LuatOS 里恒为 nil
]]

local M = {}

-- exaudio 是固件扩展库，须 require 绑定（tts_app / video_util 同款拿法）
local ok_exaudio, exaudio = pcall(require, "exaudio")
if not ok_exaudio then exaudio = nil end

-- exaudio.setup 入参统一组装（必带 uart_id/audio_mode，Air1103 靠它绑到 UART6）
local audio_hw = require "audio_hw"

-- 录音文件固定落 /ram（内存盘，掉电即失，只作当场试听）
local REC_PATH = "/ram/audio_test"
-- 流式回放每批字节数（Air1103 下行 320B/10ms，取 10 帧一批）
local PLAY_CHUNK = 3200
-- 流式回放喂数据节奏：Air1103 按 32KB/s 消费，每批等 #d/32 毫秒防溢出
local PLAY_BYTE_PER_MS = 32
-- MIC 上行就绪探测超时：Air1103 复位后约 1.4s 才恢复 MIC 上行，超时给足余量
local MIC_READY_TIMEOUT_MS = 2500
-- Air1103 录音时长补偿：芯片复位到恢复 MIC 上行之间落盘的是静音，
-- 按参考工程 boot_ms=1500 补 2 秒，用户要几秒就录到几秒有效音频
local AIR1103_UPSTREAM_DELAY_S = 2

-- 已登记实例：id → handle
local instances = {}
-- 回调由 C 层反调，带不上 handle，用模块级变量反查当前录音/回放实例
local rec_owner = nil
local play_owner = nil

-- 后置定义的收尾/关闭函数，先占位让前面的回调能引用到
local finalize_record
local audio_teardown
-- MIC 就绪探测定时器句柄（收尾时取消，防止残留定时器误判下一次录音）
local mic_probe_t = nil

--[[
@function audio_cfg
@summary 取板级音频配置（hw.audio），没有即本板无音频能力
@return table|nil
]]
local function audio_cfg()
    local cfg = _G.project_config
    return cfg and cfg.hw and cfg.hw.audio
end

--[[
@function publish_state
@summary 广播实例状态，并写回 handle 供 status() 读取
@param h 实例 handle
@param state idle / recording / playing / error
@param info 状态描述
]]
local function publish_state(h, state, info)
    if not h then return end
    h.state = state
    h.info = tostring(info or "")
    sys.publish("AUDIO_TEST_STATE", h.id, state, h.info)
end

--[[
@function rec_format_of
@summary 录音格式 → exaudio 常量 + 文件扩展名 + 是否 PCM（决定回放走流式还是文件）
@param ac hw.audio 配置
@return number|nil, string, boolean
]]
local function rec_format_of(ac)
    if exaudio == nil then return nil, ".pcm", true end
    -- Air1103 只支持 PCM_16000，配置写了别的也按这个走
    if ac.model == "air1103" then return exaudio.PCM_16000, ".pcm", true end
    local f = tostring(ac.record_format or "AMR_NB"):upper()
    if f == "PCM_8000"  then return exaudio.PCM_8000,  ".pcm", true end
    if f == "PCM_16000" then return exaudio.PCM_16000, ".pcm", true end
    if f == "PCM_24000" then return exaudio.PCM_24000, ".pcm", true end
    if f == "PCM_32000" then return exaudio.PCM_32000, ".pcm", true end
    if f == "PCM_48000" then return exaudio.PCM_48000, ".pcm", true end
    if f == "AMR_WB"    then return exaudio.AMR_WB,    ".amr", false end
    return exaudio.AMR_NB, ".amr", false
end

--[[
@function audio_setup
@summary 初始化音频（首次 setup，之后只 pm(RESUME) 恢复）
@param h 实例 handle
@return boolean, string|nil
]]
local function audio_setup(h)
    local ac = audio_cfg()
    if not ac then return false, "未配置 hw.audio" end
    if exaudio == nil then return false, "缺少 exaudio 扩展库" end
    if h.inited then
        pcall(exaudio.pm, exaudio.RESUME)
        return true
    end

    -- 入参由 audio_hw 统一组装（DAC 模式 pa_ctrl/pa_on_level/dac_delay、
    -- ES8311 模式 i2c_id/dac_ctrl/i2s_sample 等与分总线 tx/rx_bus、
    -- Air1103 模式 uart_id + audio_mode="new" + 16bit/单声道）
    local sp = audio_hw.params()
    local ok, err = audio_hw.setup()
    if not ok then return false, err end
    pcall(exaudio.mic_vol, ac.mic_vol or 70)
    h.inited = true
    -- setup 是全局一次性的（boot_ui 已收口）：日志只记本次申请的入参，
    -- 真实通路是否通要看录音的 MIC 就绪探测结果
    log.info("periph_audio", "音频就绪", h.id, sp.model, "uart:", tostring(sp.uart_id))
    return true
end

-- 录音数据回调：C 层把编码后的音频帧写入 zbuff 后反调，随后 exaudio 会 del 该 zbuff
local function rec_data_cb(buff, len)
    local h = rec_owner
    if not h or not h.rec_fp then return end
    if buff and len and len > 0 then
        local ok, data = pcall(buff.toStr, buff, 0, len)
        if ok and type(data) == "string" and #data > 0 then
            h.mic_got = true
            pcall(h.rec_fp.write, h.rec_fp, data)
        end
    end
end

-- 录音完成回调：time 到期触发（提前 stop 的场景由 record_stop 自己收尾）
local function rec_done_cb(event)
    if exaudio == nil or event ~= exaudio.RECORD_DONE then return end
    local h = rec_owner
    if not h or h.state ~= "recording" then return end
    finalize_record(h)
end

--[[
@function finalize_record
@summary 录音收尾：关文件、算时长/大小、广播结果
@param h 实例 handle
]]
finalize_record = function(h)
    if mic_probe_t then
        sys.timerStop(mic_probe_t)
        mic_probe_t = nil
    end
    if h.rec_fp then
        pcall(h.rec_fp.close, h.rec_fp)
        h.rec_fp = nil
    end
    rec_owner = nil
    local sz = 0
    if h.rec_path and io.exists(h.rec_path) then
        sz = io.fileSize(h.rec_path) or 0
    end
    h.rec_bytes = sz
    h.rec_ready = sz > 0
    if h.mic_fail then
        publish_state(h, "error", "录音失败：未收到MIC数据，请检查供电、UART和固件")
    elseif sz > 0 then
        publish_state(h, "idle", string.format("录音完成 %d 秒 %d 字节，可播放", h.rec_seconds or 0, sz))
    else
        publish_state(h, "error", "录音失败：没有采到数据")
    end
end

--[[
@function mic_probe
@summary MIC 上行就绪探测：到点还没采到数据即判定供电/UART/固件有问题，直接收尾报错
]]
local function mic_probe()
    mic_probe_t = nil
    local h = rec_owner
    if not h or h.mic_got then return end
    if h.state ~= "recording" then return end
    local ac = audio_cfg() or {}
    h.mic_fail = true
    log.error("periph_audio", "未收到MIC数据", h.id,
              "model:", tostring(ac.model), "uart:", tostring(audio_hw.params().uart_id))
    pcall(exaudio.record_stop)
    finalize_record(h)
end

--[[
@function record_start
@summary 开始录音（函数 path 手动落盘），到时长自动结束
@param h 实例 handle
@param seconds 录音时长（秒），缺省用 params.record_seconds，超过 max_record_time 按后者钳制
@return boolean, string|nil
]]
local function record_start(h, seconds)
    if not h or not h.inited then return false, "音频未初始化" end
    if h.state == "recording" then return false, "正在录音" end
    if h.state == "playing" then return false, "正在播放，请先停止" end

    local ac = audio_cfg() or {}
    local fmt, ext = rec_format_of(ac)
    if fmt == nil then return false, "缺少 exaudio 扩展库" end

    -- 时长以入参优先，最后按硬件最长录音钳一刀，防止把 Air1103 喂过头
    local secs = tonumber(seconds) or h.params.record_seconds or 5
    local max_t = tonumber(ac.max_record_time) or 30
    if secs < 1 then secs = 1 end
    if secs > max_t then secs = max_t end

    local path = REC_PATH .. ext
    if io.exists(path) then pcall(os.remove, path) end
    local fp = io.open(path, "wb")
    if not fp then return false, "录音文件打开失败: " .. path end

    h.rec_path = path
    h.rec_fp = fp
    h.rec_seconds = secs
    h.mic_got = false
    h.mic_fail = false
    rec_owner = h

    -- Air1103 每次录音都复位芯片，恢复 MIC 上行前落盘的是静音，时长补 AIR1103_UPSTREAM_DELAY_S
    local cmd_secs = secs
    if audio_hw.is_air1103() then cmd_secs = secs + AIR1103_UPSTREAM_DELAY_S end

    local ok, ret = pcall(exaudio.record_start, {
        format = fmt,
        time = cmd_secs,
        path = rec_data_cb,
        cbfnc = rec_done_cb,
    })
    if not ok or not ret then
        pcall(fp.close, fp)
        h.rec_fp = nil
        rec_owner = nil
        return false, "录音启动失败: " .. tostring(ret)
    end
    if mic_probe_t then
        sys.timerStop(mic_probe_t)
        mic_probe_t = nil
    end
    mic_probe_t = sys.timerStart(mic_probe, MIC_READY_TIMEOUT_MS)
    publish_state(h, "recording", string.format("录音中 %d 秒...", h.rec_seconds))
    log.info("periph_audio", "开始录音", h.id, "时长", h.rec_seconds, "格式", tostring(ac.record_format))
    return true
end

--[[
@function record_stop
@summary 提前结束录音（audio_v2 的 record_stop 后可能不再触发 RECORD_DONE，须主动收尾）
@param h 实例 handle
@return boolean, string|nil
]]
local function record_stop(h)
    if not h or h.state ~= "recording" then return false, "当前没有在录音" end
    pcall(exaudio.record_stop)
    -- 收尾自身幂等（rec_fp 关一次即置 nil），新旧框架都走这里
    finalize_record(h)
    return true
end

-- 流式回放协程：边读文件边喂 Air1103，喂完 exaudio.finish() 排空触发 PLAY_DONE
-- play_gen 是每次回放的代号：停止后立刻重开时，上一个协程靠它认出自己已过期
local function play_stream_task(gen)
    local h = play_owner
    if not h then return end
    local file = io.open(h.rec_path, "rb")
    if not file then
        play_owner = nil
        publish_state(h, "error", "回放文件打开失败")
        return
    end
    while h.play_gen == gen and not h.stop_req do
        local d = file:read(PLAY_CHUNK)
        if not d or #d == 0 then break end
        -- 最后一批不足 PLAY_CHUNK 补静音，保证 320B 帧对齐
        if #d < PLAY_CHUNK then
            d = d .. string.rep("\0", PLAY_CHUNK - #d)
        end
        pcall(exaudio.play_stream_write, d)
        sys.wait(math.max(20, math.floor(#d / PLAY_BYTE_PER_MS)))
    end
    file:close()
    if h.play_gen == gen then
        pcall(exaudio.finish)
    end
end

-- 流式/文件回放完成回调
local function play_done_cb(event)
    if exaudio == nil or event ~= exaudio.PLAY_DONE then return end
    local h = play_owner
    if not h then return end
    play_owner = nil
    h.stop_req = false
    publish_state(h, "idle", "播放完成")
end
--[[
@function play_start
@summary 回放最近一次录音：PCM 走流式，amr/wav/mp3 走文件播放
@param h 实例 handle
@return boolean, string|nil
]]
local function play_start(h)
    if not h or not h.inited then return false, "音频未初始化" end
    if h.state == "recording" then return false, "正在录音，请先停止" end
    if h.state == "playing" then return false, "正在播放" end
    if not h.rec_path or not h.rec_ready then return false, "还没有可用的录音" end

    local ac = audio_cfg() or {}
    local _, _, is_pcm = rec_format_of(ac)

    h.stop_req = false
    h.play_gen = (h.play_gen or 0) + 1
    play_owner = h
    local ok, ret
    if is_pcm then
        ok, ret = pcall(exaudio.play_start, {
            type = 2,
            cbfnc = play_done_cb,
            priority = 1,
            sampling_rate = 16000,
            sampling_depth = 16,
            signed_or_unsigned = true,
        })
        if ok and ret then
            sys.taskInit(play_stream_task, h.play_gen)
        end
    else
        ok, ret = pcall(exaudio.play_start, {
            type = 0,
            content = h.rec_path,
            cbfnc = play_done_cb,
        })
    end
    if not ok or not ret then
        play_owner = nil
        return false, "播放启动失败: " .. tostring(ret)
    end
    publish_state(h, "playing", "播放中...")
    log.info("periph_audio", "开始回放", h.id, h.rec_path, is_pcm and "流式PCM" or "文件")
    return true
end

--[[
@function play_stop
@summary 停止回放
@param h 实例 handle
@return boolean, string|nil
]]
local function play_stop(h)
    if not h or h.state ~= "playing" then return false, "当前没有在播放" end
    -- stop_req 置起后不再归位：正在跑的喂数协程靠它退出，归位只在 play_start / 播完
    h.stop_req = true
    pcall(exaudio.play_stop, { type = 2 })
    pcall(exaudio.play_stop, { type = 0 })
    play_owner = nil
    publish_state(h, "idle", "已停止播放")
    return true
end

--[[
@function audio_teardown
@summary 关闭实例：停掉录音/回放，只清状态不下电（Air1103 供电脚常供电）
@param h 实例 handle
@return boolean
]]
audio_teardown = function(h)
    if not h then return false end
    if h.state == "recording" then
        pcall(exaudio.record_stop)
        finalize_record(h)
    elseif h.state == "playing" then
        h.stop_req = true
        pcall(exaudio.play_stop, { type = 2 })
        pcall(exaudio.play_stop, { type = 0 })
        play_owner = nil
    end
    h.inited = false
    publish_state(h, "idle", "已关闭")
    log.info("periph_audio", "音频已关闭", h.id)
    return true
end

--[[
@function audio_status
@summary 读取状态
@param h 实例 handle
@return table { enabled=bool, info=string }
]]
local function audio_status(h)
    if not h then return { enabled = false, info = "invalid" } end
    local ac = audio_cfg()
    if not ac then return { enabled = false, info = "未配置 hw.audio" } end
    if not h.inited then
        return { enabled = false, info = string.format("%s | %s 未初始化", h.name or "?", tostring(ac.model or "?")) }
    end
    local info = h.info
    if not info or info == "" then
        info = string.format("%s | %s | 录音格式 %s", h.name or "?",
                             tostring(ac.model or "?"), tostring(ac.record_format or "AMR_NB"))
        if h.rec_ready then
            info = info .. string.format(" | 已录 %d 字节", h.rec_bytes or 0)
        end
    end
    return { enabled = true, info = info }
end

-- 创建 handle 并挂载方法
local function make_handle(params)
    local h = {
        id = params.id,
        name = params.name or params.id,
        params = params,
        state = "idle",
        info = "",
        inited = false,
        rec_path = nil,
        rec_fp = nil,
        rec_bytes = 0,
        rec_ready = false,
        mic_got = false,
        mic_fail = false,
        rec_seconds = params.record_seconds or 5,
        stop_req = false,
        play_gen = 0,
    }
    h.start        = audio_setup
    h.stop         = audio_teardown
    h.record_start = record_start
    h.record_stop  = record_stop
    h.play_start   = play_start
    h.play_stop    = play_stop
    h.status       = audio_status
    return h
end

--[[
登记音频实例（不初始化音频）
@param table params  config.peripherals 条目
@return table|false  handle 或 false, 错误串
]]
function M.init(params)
    if type(params) ~= "table" then return false, "params must be table" end
    if not params.id then return false, "missing id" end
    if instances[params.id] then return false, "duplicated id: " .. tostring(params.id) end
    if not audio_cfg() then return false, "未配置 hw.audio" end
    local h = make_handle(params)
    instances[params.id] = h
    log.info("periph_audio", "音频已登记", params.id)
    return h
end

--[[
列出已登记实例
@return table  { {id=, name=, handle=}, ... }
]]
function M.list()
    local out = {}
    for id, h in pairs(instances) do
        out[#out + 1] = { id = id, name = h.name, handle = h }
    end
    return out
end

--[[
取单个实例 handle
@param string id  实例 id
@return table|nil  handle
]]
function M.get(id)
    return instances[id]
end

-- 关闭全部实例并清空注册表
function M.reset_all()
    for id, h in pairs(instances) do
        pcall(h.stop, h)
        instances[id] = nil
    end
    rec_owner = nil
    play_owner = nil
    return true
end

return M
