--[[
@module  play_audio_during_cc
@summary 通话中播放音频（文件/TTS）
@version 1.0
@date    2026.06.30
@author  拓毅恒
@usage
本模块演示在VoLTE通话中给对方播放音频文件或TTS文本。
通话接通后在AUDIO_START事件中自动触发播放。

工作流程：
- 系统启动后初始化音频设备和CC
- 由宏IS_DIAL决定是主动拨号还是等待来电接听
- 通话建立（AUDIO_START）后，播放预设音频

注意事项：
1. 本demo使用新音频框架，固件需要V2046及以上的13/113号固件才能播放
2. 传入音频文件时（如{"/luadb/test_16k.mp3"}），框架自动从文件头解析
   采样率、位宽、声道数等参数，并与当前通话参数自动校验
3. 校验不匹配会静默失败
4. 准备音频文件时需注意：
   - 确保文件是16bit、单声道的MP3文件
   - 最好准备两种采样率的文件（8K和16K各一份），运行时通过cc.quality()判断后选择

常用cc.extern_source调用示例：
1. 播放文件：   cc.extern_source({"/luadb/test_16k.mp3"})       -- 框架自动识别
2. 播放TTS：   cc.extern_source("你好，测试一下")                
3. 裸PCM数据： cc.extern_source(pcm_zbuff, nil, audio_v2.DATA_CODEC_TYPE_RAW, 8000, 16, 1, true)
4. 停止播放：  cc.extern_source(nil)
]]

-- 引入音频设备模块
local exaudio = require "exaudio"
local audio_drv = require "audio_drv"

-- ====================== 配置区域 ======================

-- 通话模式选择（二选一）：
-- true = 主动拨出，false = 等待来电自动接听
local IS_DIAL = false
-- 主动拨出时的目标号码（IS_DIAL=true时有效）
local DIAL_NUMBER = "10000"

-- 音频播放
local PLAY_SOURCE = {"/luadb/test_16k.mp3"}     -- 播放文件模式，注意单个文件也要用table
-- local PLAY_SOURCE = "你好，测试一下，123456789"  -- 播放TTS模式

-- ====================== 全局状态变量 ======================
local call_counter = 0                 -- 响铃计数器
local caller_number = ""               -- 来电号码
local is_connected = false             -- 通话连接状态

-- ====================== 通话事件处理 ======================
-- 来电自动接听模式
local function handle_incoming_call(status)
    if status == "INCOMINGCALL" then
        -- 获取来电号码
        caller_number = cc.lastNum() or "未知号码"
        call_counter = call_counter + 1
        log.info("extern_demo", "收到来电，号码:", caller_number, "响铃次数:", call_counter)
        -- 响铃2声后自动接听
        if call_counter >= 2 then
            log.info("extern_demo", "自动接听来电")
            cc.accept(0)
            call_counter = 0
        end
    end
end

-- 主动拨号模式
local function handle_outgoing_call(status)
    if status == "MAKE_CALL_OK" then
        log.info("extern_demo", "拨号请求成功")
    elseif status == "CONNECTED" then
        log.info("extern_demo", "电话已接通")
    elseif status == "MAKE_CALL_FAILED" then
        log.info("extern_demo", "拨号失败")
    end
end

-- 通话中播放外部音频（接通音频通道后触发）
local function play_extern_source()
    local quality = cc.quality()
    log.info("extern_demo", "通话质量:", quality, "(1=8K低音质, 2=16K高音质)")

    -- 先清理上一次通话可能残留的extern_source状态，确保第二次也能播放
    cc.extern_source()
    -- 播放音频
    local ok = cc.extern_source(PLAY_SOURCE)
    if ok then
        if type(PLAY_SOURCE) == "table" then
            log.info("extern_demo", "开始播放文件:", PLAY_SOURCE[1])
        elseif type(PLAY_SOURCE) == "string" then
            log.info("extern_demo", "开始播放TTS:", PLAY_SOURCE)
        end
    else
        log.error("extern_demo", "播放失败，可能音频参数与通话不匹配")
    end
end

-- ====================== 主事件处理器 ======================
sys.subscribe("CC_IND", function(status)
    log.info("CC状态", status)

    -- 根据模式分发事件
    if IS_DIAL then
        handle_outgoing_call(status)
    else
        handle_incoming_call(status)
    end

    -- AUDIO_START：音频通道已建立，可以播放外部音频
    if status == "AUDIO_START" then
        play_extern_source()
    end

    -- SPEECH_START：通话开始（录音回调会同时触发）
    if status == "SPEECH_START" then
        is_connected = true
        log.info("extern_demo", "通话已建立")
    end

    -- 需要处理的通用状态
    if status == "READY" then
        sys.publish("CC_READY")  -- 发布系统就绪事件
        -- 主动拨号模式：电话系统就绪后自动拨号
        if IS_DIAL then
            sys.timerStart(function()
                log.info("extern_demo", "开始拨号:", DIAL_NUMBER)
                cc.dial(0, DIAL_NUMBER)
            end, 1000)
        end
    elseif status == "HANGUP_CALL_DONE" or status == "MAKE_CALL_FAILED" or status == "DISCONNECTED" then
        -- 通话结束，关闭PA节省功耗，保留driver下次通话时快速恢复
        exaudio.shutdown(false, false, true)
        is_connected = false
        call_counter = 0
        log.info("extern_demo", "通话结束")
    end
end)

-- ====================== 电话系统初始化 ======================
local function init_cc()
    -- 初始化音频设备
    audio_drv.initAudioDevice()

    -- 等待电话系统就绪
    sys.waitUntil("CC_READY")

    -- 初始化电话功能
    cc.init(audio_drv.getMultimediaId())

    log.info("cc_extern_source_demo", IS_DIAL and "主动拨号模式" or "来电接听模式")
    log.info("cc_extern_source_demo", "播放源: ", type(PLAY_SOURCE) == "table" and "FILE" or "TTS")
    log.info("cc_extern_source_demo", "电话系统初始化完成")
end

-- 启动初始化任务
sys.taskInit(init_cc)

log.info("cc_extern_source_demo", "通话外部音频播放模块加载完成")
