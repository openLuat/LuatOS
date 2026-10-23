--[[
@module  tts_app
@summary Air8784（Air780EHM + Air1103）离线 TTS 播报逻辑
@version 1.1.0
@date    2026.10.16
@author  王世豪
@usage
离线 TTS 播报功能模块：依赖固件编入 tts_pcm 引擎；通过 exaudio.setup(audio_mode="new")
初始化 Air1103，再调用 exaudio.play_start({type=1, content=文本}) 触发本地合成并播放。
本文件被 main.lua 以 require "tts_app" 加载时，自动启动播放任务：
初始化完成后开机播报一次；之后每按下一次 SOS 按键(GPIO20)，延迟一小段时间再播报一次，播报中忽略新的触发。
]]

local exaudio = require "exaudio"

-- SOS 按键：Air8784 板定义为 GPIO20
local SOS_PIN = 20
-- 按键后延迟多久再播报（毫秒）：避免刚按下就出声，按需调整
local SOS_DELAY_MS = 1000
-- 播报文本：按需修改
local TTS_TEXT = "你好，这是离线语音播报。"

-- 离线 TTS 播放完成回调：event == exaudio.PLAY_DONE 表示播完
local function ttsCallback(event, result)
    if event == exaudio.PLAY_DONE then
        log.info("air1103.tts", "播放结束", result, "空闲", exaudio.is_end())
    end
end

-- 播报一次：必须等上一句播完(exaudio.is_end() 为 true)，否则 play_start 会报 busy
local function playOnce()
    if not exaudio.is_end() then
        log.info("air1103.tts", "正在播报中，忽略本次触发")
        return
    end
    -- 离线 TTS 播报：type=1 表示本地合成文本
    local ok, reason = exaudio.play_start({
        type = 1,
        content = TTS_TEXT,
        cbfnc = ttsCallback,
    })
    log.info("air1103.tts", "请求受理", ok, reason)
end

-- TTS 播放任务：等 Air1103 上电稳定后初始化，开机播报一次，之后等待 SOS 按键触发播报
local function ttsTask()
    sys.wait(2000)  -- 等 Air1103 上电稳定（供电已在 main 中通过 GPIO73 拉高）

    -- 离线 TTS 必须 audio_mode="new"，且固件需带 tts_pcm 引擎；
    -- 若固件未注入 audio_v2 全局，此 setup 会返回 false（需换带 tts_pcm 的固件）
    assert(exaudio.setup({ model = "air1103", uart_id = 1, audio_mode = "new" }), "Air1103 初始化失败")
    exaudio.vol(70)  -- 喇叭音量 0~100

    playOnce()  -- 开机播报一次

    -- 之后每按一次 SOS 按键播报一次；中断里只发消息，实际播放在本任务中执行
    while true do
        sys.waitUntil("SOS_PRESS")
        sys.wait(SOS_DELAY_MS)  -- 按键后等一会儿再播报
        playOnce()
    end
    -- 中途停止：exaudio.play_stop({ type = 1 })
    -- 必须等完成回调触发、或 exaudio.is_end() 为 true 后，才能启动下一句/进入通话，否则会报 busy
end

-- SOS 按键中断：GPIO20 上拉，按下拉低，下降沿触发，防抖 50ms
gpio.debounce(SOS_PIN, 50)
gpio.setup(SOS_PIN, function()
    sys.publish("SOS_PRESS")
end, gpio.PULLUP, gpio.FALLING)

-- require 时自动启动播放任务
sys.taskInit(ttsTask)
