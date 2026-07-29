--[[
@module  play_audio_during_cc
@summary 通话中播放音频（文件/TTS/流模式）
@version 1.1
@date    2026.07.29
@author  拓毅恒
@usage
本模块演示在VoLTE通话中给对方播放音频文件、TTS文本或流式音频。
通话接通后在AUDIO_START事件中自动触发播放。

工作流程：
- 系统启动后初始化音频设备和CC
- 由宏IS_DIAL决定是主动拨号还是等待来电接听
- 通话建立（AUDIO_START）后，播放预设音频

注意事项：
1. 本demo使用新音频框架，固件需要V2048及以上的13/113号固件才能播放
2. 使用本demo时需要确认audio_drv.lua中初始化配置的音频框架audio_mode = "new" 才能播放
3. 传入音频文件时（如{"/luadb/test_16k.mp3"}），框架自动从文件头解析
   采样率、位宽、声道数等参数，并与当前通话参数自动校验
4. 校验不匹配会静默失败
5. 准备音频文件时需注意：确保文件是16bit、单声道的MP3文件
6. 支持16K/8K自适应播放，往对端播放只需要准备1个16K单通道的文件即可，TTS也支持在8K通话质量下播放

常见用法
1. 播放文件：        cc.extern_source({"/luadb/test_16k.mp3"})
2. 播放TTS ：        cc.extern_source("你好，测试一下")
3. 播放流式(固件版本2048及以上支持)：        cc.extern_source(true, true, audio_v2.DATA_CODEC_TYPE_RAW, true, 16000, 16, 1, true)
   启用流式后，用    cc.input(true, data, false) 逐块喂数据，cc.input(true, "", true) 结束。
4. 停止播放：        cc.extern_source(nil)
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

-- ============ 音频播放选择（三选一） ============
-- 取消注释要测的模式、其余保持注释即可。play_extern_source 会按 PLAY_SOURCE 的类型自动分支：
--   table  -> 文件播放；string -> TTS播放；true -> 流式播放

-- 1、文件播放
-- local PLAY_SOURCE = {"/luadb/test_16k.mp3"}

-- 2、TTS播放
-- local PLAY_SOURCE = "你好，测试一下，123456789"

-- 3、流式播放
local PLAY_SOURCE = true
local PCM_STREAM_FILE = "/luadb/test.pcm"

-- ====================== 全局状态变量 ======================
local call_counter = 0                 -- 响铃计数器
local caller_number = ""               -- 来电号码
local is_streaming = false             -- 流模式喂数据进行中标志（挂断时置false，停止喂数据）

-- ====================== 通话事件处理 ======================
-- 来电自动接听模式
local function handle_incoming_call(status)
    if status == "INCOMINGCALL" then
        -- 获取来电号码
        caller_number = cc.lastNum() or "未知号码"
        call_counter = call_counter + 1
        log.info("play_audio_during_cc", "收到来电，号码:", caller_number, "响铃次数:", call_counter)
        -- 响铃2声后自动接听
        if call_counter >= 2 then
            log.info("play_audio_during_cc", "自动接听来电")
            cc.accept(0)
            call_counter = 0
        end
    end
end

-- 主动拨号模式
local function handle_outgoing_call(status)
    if status == "MAKE_CALL_OK" then
        log.info("play_audio_during_cc", "拨号请求成功")
    elseif status == "CONNECTED" then
        log.info("play_audio_during_cc", "电话已接通")
    elseif status == "MAKE_CALL_FAILED" then
        log.info("play_audio_during_cc", "拨号失败")
    end
end

-- 以流式把PCM文件播放到对端（仅支持上行通道）
local function stream_pcm_to_peer(path)
    -- 获取推荐的缓冲区大小
    local buffer_size = exaudio.get_stream_buffer_size() or 4096
    log.info("play_audio_during_cc", "流式缓冲区大小:", buffer_size)
    -- 流式播放音频
    local ok = cc.extern_source(true, true, audio_v2.DATA_CODEC_TYPE_RAW, true, 16000, 16, 1, true)
    if not ok then
        log.error("play_audio_during_cc", "cc.extern_source 流式启动失败")
        return
    end
    is_streaming = true
    log.info("play_audio_during_cc", "cc.extern_source 流式已启动, 开始写入数据:", path)

    local f = io.open(path, "r")
    if not f then
        log.error("play_audio_during_cc", "打开PCM文件失败:", path)
        cc.extern_source(nil)
        is_streaming = false
        return
    end

    local total_written = 0   -- 累计实际写入字节数
    while is_streaming do
        local read_data = f:read(buffer_size)
        if not read_data then
            if is_streaming then
                cc.input(true, "", true)    -- 标记输入结束
            end
            break
        end
        -- 按 FIFO 剩余空间分片写入：每次喂入后根据 write_len 推进，根据 free_len 做流控
        local remain = read_data
        while is_streaming and #remain > 0 do
            local _, write_len, free_len = cc.input(true, remain, false)
            if write_len and write_len > 0 then
                total_written = total_written + write_len
                remain = remain:sub(write_len + 1)
            else
                -- 缓冲满(free_len==0)则多等，否则短等，避免空转也避免覆盖
                sys.wait(free_len and free_len == 0 and 10 or 2)
            end
        end
    end
    f:close()
    is_streaming = false
    log.info("play_audio_during_cc", "流式写入数据完毕,累计写入：", total_written, "字节")
end

-- 通话中播放外部音频（接通音频通道后触发）
local function play_extern_source()
    local quality = cc.quality()
    log.info("play_audio_during_cc", "通话质量:", quality, "(1=8K低音质, 2=16K高音质)")

    -- 先清理上一次通话可能残留的extern_source状态，确保第二次也能播放
    cc.extern_source(nil)

    -- 流式播放
    if PLAY_SOURCE == true then
        log.info("extern_demo", "开始流式播放文件:", PCM_STREAM_FILE)
        sys.taskInit(stream_pcm_to_peer, PCM_STREAM_FILE)
        return
    end

    -- 播放音频（文件/TTS模式，框架自动识别）
    local ok = cc.extern_source(PLAY_SOURCE)
    if ok then
        if type(PLAY_SOURCE) == "table" then
            log.info("extern_demo", "开始播放文件:", PLAY_SOURCE[1])
        elseif type(PLAY_SOURCE) == "string" then
            log.info("extern_demo", "开始播放TTS:", PLAY_SOURCE)
        end
    else
        log.error("play_audio_during_cc", "播放失败，可能音频参数与通话不匹配")
    end
end

-- 主动拨号模式的定时拨号处理
local function handle_dial_timer()
    log.info("play_audio_during_cc", "开始拨号:", DIAL_NUMBER)
    cc.dial(0, DIAL_NUMBER)
end

-- CC_IND事件处理器
local function handle_cc_ind(status)
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

    -- SPEECH_START：通话开始
    if status == "SPEECH_START" then
        log.info("play_audio_during_cc", "通话已建立")
    end

    -- 需要处理的通用状态
    if status == "READY" then
        sys.publish("CC_READY")  -- 发布系统就绪事件
        -- 主动拨号模式：电话系统就绪后自动拨号
        if IS_DIAL then
            sys.timerStart(handle_dial_timer, 1000)
        end
    elseif status == "HANGUP_CALL_DONE" or status == "MAKE_CALL_FAILED" or status == "DISCONNECTED" then
        -- 通话结束，关闭PA保留driver下次通话时快速恢复
        exaudio.pm(audio.SHUTDOWN)
        is_streaming = false   -- 挂断即停止喂数据
        call_counter = 0
        log.info("play_audio_during_cc", "通话结束")
    end
end

-- ====================== 主事件处理器 ======================
sys.subscribe("CC_IND", handle_cc_ind)

-- ====================== 电话系统初始化 ======================
local function init_cc()
    -- 初始化音频设备
    audio_drv.initAudioDevice()

    -- 等待电话系统就绪
    sys.waitUntil("CC_READY")

    -- 初始化电话功能
    cc.init(audio_drv.getMultimediaId())

    log.info("play_audio_during_cc", IS_DIAL and "主动拨号模式" or "来电接听模式")
    log.info("cc_extern_source_demo", "播放模式: ", PLAY_SOURCE == true and "STREAM" or (type(PLAY_SOURCE) == "table" and "FILE" or "TTS"))
    log.info("play_audio_during_cc", "电话系统初始化完成")
end

-- 启动初始化任务
sys.taskInit(init_cc)

log.info("play_audio_during_cc", "通话外部音频播放模块加载完成")
