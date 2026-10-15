--[[
@module  tts_app
@summary TTS 播报服务（云端下行/本地共用播放路径）
@version 1.0.0
@date    2026.09.23
@author  江访

=== 设计要点 ===

1. 播放统一走 exaudio.play_start({ type = 1, content = 文本 })，
   **不走旧框架 audio.tts()**：旧框架在 DAC 模式下不出声（PA/DAC 通路
   未正确配置，llm_chat 已踩过）。DAC / ES8311 / TM8211 等 model 全走
   exaudio 统一路径，机型差异全部收敛在 config.hw.audio 表。

2. 打断式播报：新播报打断旧播报（含 AI 助手的 TTS）。打断只发一次
   play_stop，并广播 TTS_INTERRUPTED 让持有方（llm_chat）清理自身状态；
   旧播讲协程靠「播放代次 gen」自行退出，**不做** llm_chat 那套 vol(0)
   全局静音等待（那是它页面切换竞争的特有路径，会误伤新播报）。

3. **严禁 pm(SHUTDOWN)**：TTS 只需 play_stop。SHUTDOWN 会让 DAC 下电，
   再 setup + play_start 会失败（Air8601 DAC 模式已验证）。

4. 音量每次起播时读 project_config.hw.audio.play_vol（settings_display_app
   的 set_volume 统一写回点，media_volume 持久化恢复），自动跟随
   「亮度和声音」页的音量设置，勿缓存、勿另起炉灶。

5. 无音频能力（hw.audio 未配置）时 available() 返回 false，say 静默跳过
   并发布 TTS_PLAY_END(false)。同一份固件在有/无喇叭的板子上都安全。

=== 对外接口 ===

  tts_app.available()   -> boolean  是否具备播报能力（hw.audio + exaudio）
  tts_app.say(text)             -- 异步播报（任意上下文可调，打断当前播报）
  tts_app.stop()                -- 停止当前播报

=== 对外事件 ===

  订阅  TTS_PLAY_REQUEST   string   请求播报文本（aircloud_app 等转发进来）
  订阅  TTS_STOP_REQUEST            请求停止播报
  发布  TTS_PLAY_BEGIN     string   开始播报（文本）
  发布  TTS_PLAY_END       boolean  播报结束（true=完整播完）
  发布  TTS_INTERRUPTED             播报被外部打断（持有方据此清理自身状态）
]]

local M = {}

-- exaudio 是固件扩展库，须 require 绑定（welcome_win / video_util / llm_chat 同款拿法），
-- 裸用全局 exaudio 在 LuatOS 里恒为 nil（会导致 available() 误判成"无音频能力"回 ERR no audio）；
-- 其顶层引用 i2s 常量，无音频固件上 require 会报错，故 pcall 兜底置 nil
local ok_exaudio, exaudio = pcall(require, "exaudio")
if not ok_exaudio then exaudio = nil end

local gen = 0   -- 播放代次：stop/新 say 时 +1，旧协程据此退出

--- 能力探测：C 库可能是 userdata，不能用 type(t)=="table" 前置判断
--- （见 aircloud_app 头部 has_api 的坑说明）
local function has_fn(t, key)
    if t == nil then return false end
    local ok, f = pcall(function() return t[key] end)
    return ok and type(f) == "function"
end

--- 读音频硬件配置（hw.audio 不存在 = 本板无播报能力）
local function get_audio_cfg()
    return _G.project_config and _G.project_config.hw and _G.project_config.hw.audio
end

function M.available()
    return exaudio ~= nil and get_audio_cfg() ~= nil
        and has_fn(exaudio, "setup") and has_fn(exaudio, "play_start")
end

--- 与 llm_chat.tts_init 相同的 setup 参数组装（字段一一对应，勿单方面增删）
local function tts_setup(ac)
    local sp = { model = ac.model or "es8311", pa_ctrl = ac.pa_ctrl,
                 pa_on_level = ac.pa_on_level or 1, dac_delay = ac.dac_delay }
    if ac.dac_ctrl then sp.dac_ctrl = ac.dac_ctrl end
    if ac.i2c_id then sp.i2c_id = ac.i2c_id end
    if ac.i2s_sample then sp.i2s_sample = ac.i2s_sample end
    if ac.bits_per_sample then sp.bits_per_sample = ac.bits_per_sample end
    if ac.i2s_framebit then sp.i2s_framebit = ac.i2s_framebit end
    if ac.channels then sp.channels = ac.channels end
    if ac.pa_delay then sp.pa_delay = ac.pa_delay end
    if ac.tx_bus_type and ac.rx_bus_type then
        sp.tx_bus_type = ac.tx_bus_type; sp.tx_bus_id = ac.tx_bus_id or 0
        sp.rx_bus_type = ac.rx_bus_type; sp.rx_bus_id = ac.rx_bus_id or 0
    end
    if ac.audio_mode then sp.audio_mode = ac.audio_mode end
    -- setup 幂等（audio_v2 下重复调用不出错），每次起播前调用保证通路完整
    local ok, result = pcall(exaudio.setup, sp)
    if not ok or not result then
        log.warn("tts_app", "exaudio.setup 异常/失败", ok, result)
    end
    -- 音量走统一写回点 ac.play_vol（「亮度和声音」页 set_volume 写回），
    -- 每次现读，自动跟随用户音量设置
    pcall(exaudio.vol, ac.play_vol or 70)
end

--- 播放一段文本（仅在协程内调用）
--- @param text string 播报文本
--- @param my_gen number 本次播放的代次
--- @return boolean 是否完整播完
local function play_blocking(text, my_gen)
    local ac = get_audio_cfg()
    if not ac then return false end
    tts_setup(ac)
    sys.wait(100)                       -- 等 DAC/PA 上电稳定（setup 后需要时间）
    if gen ~= my_gen then return false end

    local done = false
    local ok = exaudio.play_start({
        type = 1,
        content = text,
        cbfnc = function(event)
            if event == exaudio.PLAY_DONE then done = true end
        end
    })
    if not ok then
        log.warn("tts_app", "exaudio.play_start 失败")
        return false
    end
    sys.publish("TTS_PLAY_BEGIN", text)

    local t = 0
    while not done and gen == my_gen and t < 30000 do
        sys.wait(100); t = t + 100
    end

    if not done and gen == my_gen then
        -- 自身超时未播完：补一次干净停止（TTS 只需 play_stop，勿 pm(SHUTDOWN)）
        pcall(exaudio.play_stop, { type = 1 })
    end
    return done
end

--- 异步播报（打断当前播报），任意上下文可调
function M.say(text)
    if type(text) ~= "string" or text == "" then return end
    if not M.available() then
        log.warn("tts_app", "无音频能力（hw.audio 未配置），跳过播报:", text)
        sys.publish("TTS_PLAY_END", false)
        return
    end
    gen = gen + 1
    local my_gen = gen
    sys.publish("TTS_INTERRUPTED")          -- 让 llm_chat 等持有方清理状态
    pcall(exaudio.play_stop, { type = 1 })  -- 打断上一条（含 AI 助手 TTS）
    sys.taskInit(function()
        local ok = play_blocking(text, my_gen)
        if gen == my_gen then
            sys.publish("TTS_PLAY_END", ok and true or false)
        end
    end)
end

--- 停止当前播报
function M.stop()
    gen = gen + 1
    sys.publish("TTS_INTERRUPTED")
    pcall(exaudio.play_stop, { type = 1 })
    sys.publish("TTS_PLAY_END", false)
end

sys.subscribe("TTS_PLAY_REQUEST", function(text) M.say(tostring(text or "")) end)
sys.subscribe("TTS_STOP_REQUEST", function() M.stop() end)

log.info("tts_app", "模块已加载, available=", M.available())
return M
