--[[
@module  audio_route
@summary 录音/播放分路：Air1103 机型录音走语音芯片、播放走内置 DAC
@version 1.0
@date    2026.11.04
@author  江访

=== 设计要点 ===

1. 【为什么要分路】exaudio 的 model 是全局单例，而录音和播放对它的要求互相排斥：
   - record_start 只有 model=="air1103" 才走 Air1103 的 UART MIC 上行；
   - play_start 开头硬判 model=="air1103"，直接把下行灌给 Air1103，
     且只认 type=1(TTS) / type=2(流式PCM)，type=0(文件) 报 "unsupported"。
   Air8605M/W、Air8603M1/W1 这类板子「既接了 Air1103 也支持 DAC」，
   要的是录音走 1103、播放走内置 DAC，只能按需切换 model。

2. 【只对 Air1103 机型生效】enabled() 为假时，record_start / play_start 就是
   pcall(exaudio.xxx, cfg) 的原样转发，返回值形态与调用方原来的 pcall 完全一致。
   dac / es8311 / tm8211 / 无音频四类固件的行为与没有本模块时一致。

3. 【怎么切】重跑 exaudio.setup 换 model：
   - exaudio.setup 幂等；air1103.init 只认首次，同一串口重复调直接 return true；
   - dac 与 air1103 两个分支都不碰 audio_v2.config，而 Air1601/Air1602 上调
     audio_v2.config 会触发底层 UsageFault(pc=0) 死机，所以切换本身是安全的；
   - 切到播放态带上 hw.audio 的 pa_ctrl / pa_on_level / pa_delay，让 audio_v2 框架
     在起播时自动开 PA、播完自动关；
   - 切到录音态把 pa_ctrl 脚拉到 pa_on_level：分路板上若该脚兼作 Air1103 供电，
     停在低电平会让语音芯片没电；只当功放使能时拉高等于放开静音，同样无害。
     两种含义下录音都不会被弄坏，所以无条件拉一次。

4. 【DAC 音量】exaudio.vol 在 air1103 分支只写语音芯片的音量寄存器，够不着
   audio_v2.soft_volume，内置 DAC 那一路（mplayer 的 MP4 音轨、本模块的 DAC 播放）
   的音量因此不受控。audio_hw.vol 补一次 audio_v2.soft_volume，
   本模块再把「音频设置（音量）+ 开关（静音）」经全局消息 AUDIO_CFG_SYNC 广播出去，
   任何一处改动都收敛到 apply() 这一个生效点。

5. 【打断 TTS 不在本次范围】tts_app 的 TTS_INTERRUPTED、llm_chat 的 vol(0) 静音保持
   原样，只把它们的播放与静音收口到本模块，不动打断时序。

=== 对外接口 ===

  audio_route.enabled()          -> boolean     是否启用分路（Air1103 且播放走 DAC）
  audio_route.route()            -> string|nil  当前通路 "record" / "play"
  audio_route.enter_record()     -> ok, err     切到 Air1103 录音通路
  audio_route.enter_play()       -> ok, err     切到内置 DAC 播放通路
  audio_route.record_start(cfg)  -> ok, ret     等价 pcall(exaudio.record_start, cfg)
  audio_route.play_start(cfg)    -> ok, ret     等价 pcall(exaudio.play_start, cfg)
  audio_route.sync(vol, mute)    -> ok          下发音量/静音并广播 AUDIO_CFG_SYNC
  audio_route.apply(vol, mute)   -> ok          AUDIO_CFG_SYNC 的生效点
]]

local M = {}

-- exaudio.setup 入参统一组装（hw.audio → exaudio.setup / 音量），全固件唯一组装点
local audio_hw = require "audio_hw"

-- 全局消息：音频设置（音量 0-100）与开关（true = 静音）同步
M.SYNC_MSG = "AUDIO_CFG_SYNC"

-- 当前 exaudio 跑在哪条通路上（只对 enabled() 为真的板子有意义）
local route = nil

--[[
@function enabled
@summary 是否启用「录音走 Air1103 / 播放走 DAC」分路
@return boolean
]]
function M.enabled()
    if not audio_hw.is_air1103() then return false end
    local ac = audio_hw.cfg()
    -- play_model 不写按 "dac" 处理（Air1103 板的默认诉求就是播放走 DAC）；
    -- 显式写 "air1103" 可退回今天的单通路行为
    return (ac.play_model or "dac") ~= "air1103"
end

--[[
@function route
@summary 当前音频通路
@return string|nil "record" / "play"，未分路的板子恒为 nil
]]
function M.route()
    return route
end

-- 目标通路对应的 exaudio model
local function model_of(want)
    local ac = audio_hw.cfg() or {}
    if want == "play" then return ac.play_model or "dac" end
    return ac.model
end

-- 切通路：重跑 exaudio.setup 换 model（见文件头第 3 条）
local function switch(want)
    if not M.enabled() then return true end
    if route == want then return true end
    local ex = audio_hw.exaudio()
    if not ex or not ex.setup then return false, "缺少 exaudio 扩展库" end

    local model = model_of(want)
    local sp = audio_hw.params({ model = model })
    local ok, ret = pcall(ex.setup, sp)
    if not ok then return false, "exaudio.setup 异常: " .. tostring(ret) end
    if not ret then return false, "音频通路切换失败: " .. tostring(model) end

    if want == "record" then
        -- 见文件头第 3 条：pa_ctrl 兼作 Air1103 供电时，必须先补一脚高电平
        local ac = audio_hw.cfg()
        if ac and ac.pa_ctrl and gpio then
            pcall(gpio.setup, ac.pa_ctrl, ac.pa_on_level or 1)
        end
    end

    route = want
    audio_hw.vol()
    log.info("audio_route", "音频通路切到", want, model)
    return true
end

--[[
@function enter_record
@summary 切到 Air1103 录音通路（未分路的板子直接返回 true）
@return boolean, string|nil
]]
function M.enter_record()
    return switch("record")
end

--[[
@function enter_play
@summary 切到内置 DAC 播放通路（未分路的板子直接返回 true）
@return boolean, string|nil
]]
function M.enter_play()
    return switch("play")
end

--[[
@function record_start
@summary 录音起播：分路板先切到 Air1103 通路，再转交 exaudio.record_start
@param table cfg exaudio.record_start 入参
@return boolean, any  形态与 pcall(exaudio.record_start, cfg) 一致
]]
function M.record_start(cfg)
    local ok, err = M.enter_record()
    if not ok then return false, err end
    local ex = audio_hw.exaudio()
    if not ex or not ex.record_start then return false, "缺少 exaudio 扩展库" end
    return pcall(ex.record_start, cfg)
end

--[[
@function play_start
@summary 播放起播：分路板先切到内置 DAC 通路，再转交 exaudio.play_start
@param table cfg exaudio.play_start 入参
@return boolean, any  形态与 pcall(exaudio.play_start, cfg) 一致
]]
function M.play_start(cfg)
    local ok, err = M.enter_play()
    if not ok then return false, err end
    local ex = audio_hw.exaudio()
    if not ex or not ex.play_start then return false, "缺少 exaudio 扩展库" end
    return pcall(ex.play_start, cfg)
end

--[[
@function apply
@summary AUDIO_CFG_SYNC 生效点：音量与静音开关同时下发 exaudio.vol 与 DAC 数字增益
@param number|nil vol  音量 0-100，nil 取 hw.audio.play_vol
@param boolean|nil mute  true = 静音
@return boolean
]]
function M.apply(vol, mute)
    if not audio_hw.cfg() then return false end
    local level = (mute == true) and 0 or (vol or (audio_hw.cfg().play_vol) or 70)
    audio_hw.vol(level)
    return true
end

--[[
@function sync
@summary 同步音频设置与开关：立即生效并广播 AUDIO_CFG_SYNC
@param number|nil vol  音量 0-100
@param boolean|nil mute  true = 静音
@return boolean
]]
function M.sync(vol, mute)
    M.apply(vol, mute)
    sys.publish(M.SYNC_MSG, vol, mute)
    return true
end

-- 其它模块也可 sys.publish(AUDIO_CFG_SYNC, vol, mute) 驱动同一套生效逻辑
sys.subscribe(M.SYNC_MSG, M.apply)

return M
