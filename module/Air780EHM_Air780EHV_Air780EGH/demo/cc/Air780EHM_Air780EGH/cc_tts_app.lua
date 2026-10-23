--[[
@module  cc_tts_app
@summary 通话音频场景整合示例：待机循环播放TTS、来电自动接听、通话中播放外部音频、通话录音
@version 1.0
@date    2026.01.29
@author  拓毅恒
@usage
本模块整合两个通话音频场景：
1. 待机循环播放TTS语音提示（"支付宝到账，1千万元"），来电时自动暂停；
2. 来电自动接听（响铃2声后自动接听）；
3. 通话音频建立(AUDIO_START)后，通过 cc.extern_source 向对端播放外部音频
   （文件或TTS，由下方 PLAY_SOURCE 二选一决定）；
4. 通话结束后自动恢复TTS循环播放；
5. 通话全程录音（上行/下行数据回调输出）。

工作流程：
- 系统启动后循环播放TTS语音；
- 收到来电，先关闭PA并停止TTS（避免POP音），响铃2声后自动接听；
- 通话音频通道建立后，按 PLAY_SOURCE 播放文件或TTS到对端；
- 通话结束后恢复TTS循环播放。

注意事项：
1. 本demo使用新音频框架，固件需要V2054及以上的13号固件，需要在audio_drv中设置audio_mode = "new"
2. 通话全程录音，需确保存储空间足够；
3. 来电时先关闭PA再停止音频，避免产生POP音；
4. PLAY_SOURCE 二选一：table 播放文件、string 播放TTS；
5. 音量等参数可按需调整。
]]

-- 引入音频设备模块
local audio_drv = require "audio_drv"
local exaudio = require "exaudio"

-- ============ 通话中播放音源选择（二选一） ============
-- play_extern_source 在通话音频建立(AUDIO_START)后调用 cc.extern_source(PLAY_SOURCE) 播放到对端：
--   取消注释要测的模式、其余保持注释即可；
--   table  -> 播放音频文件（如 /luadb/test_16k.mp3）；
--   string -> 播放TTS文本。
-- 注：此处为"通话中"音源；待机循环TTS内容见下方 audio_play_param.content。

-- 1、文件播放
local PLAY_SOURCE = {"/luadb/test_16k.mp3"}

-- 2、TTS播放
-- local PLAY_SOURCE = "你好，测试一下，123456789"

-- ====================== 配置区域 ======================

-- 全局状态变量
local call_counter = 0                 -- 响铃计数器
local caller_number = ""               -- 来电号码
local is_calling = false               -- 是否在打电话

-- ====================== 录音功能 ======================
-- 创建音频数据缓冲区
local up1 = zbuff.create(6400,0)      -- 上行数据保存区1
local up2 = zbuff.create(6400,0)      -- 上行数据保存区2
local down1 = zbuff.create(6400,0)    -- 下行数据保存区1
local down2 = zbuff.create(6400,0)    -- 下行数据保存区2

-- 音频数据回调函数
local function recordCallback(is_dl, point)
    if is_dl then
        log.info("录音", "下行数据，位于缓存", point+1, "缓存1数据量", down1:used(), "缓存2数据量", down2:used())
    else
        log.info("录音", "上行数据，位于缓存", point+1, "缓存1数据量", up1:used(), "缓存2数据量", up2:used())
    end
    log.info("通话质量", cc.quality())
    -- 可以在初始化串口后，通过uart.tx来发送走对应的zbuff即可
end

-- 启用通话录音
local function enableRecording()
    cc.record(true, up1, up2, down1, down2)
    cc.on("record", recordCallback)
    log.info("cc_app", "通话录音已启用")
end


-- 通话中播放外部音频（接通音频通道后触发）
local function play_extern_source()
    local quality = cc.quality()
    log.info("play_audio_during_cc", "通话质量:", quality, "(1=8K低音质, 2=16K高音质)")

    -- 先清理上一次通话可能残留的extern_source状态，确保第二次也能播放
    cc.extern_source(nil)

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

-- ====================== TTS播放处理函数 ======================
local function play_end(event)
    if event == exaudio.PLAY_DONE then
        log.info("播放完成",exaudio.is_end())
        -- 停止播放
        exaudio.play_stop({type = 1})
        -- 发起下一次播放
        sys.publish("PLAY_DONE")
    end
end 

local audio_play_param ={
    type = 1,                -- 播放类型，有0，播放文件，1.播放tts 2. 流式播放
                            -- 如果是播放文件,支持mp3,amr,wav格式
                            -- 如果是tts,内容格式见:https://docs.openluat.com/air780epm/common/tts/
                            -- 流式播放，仅支持PCM 格式音频,如果是流式播放，则sampling_rate, sampling_depth,signed_or_unsigned 必填写
    content = "支付宝到账,1千万元",          -- type=1 时为TTS文本；type=0 时此处填音频文件路径，type=2 时填PCM参数表。
    cbfnc = play_end,            -- 播放完毕回调函数
}

local function audio_task()
    log.info("开始播放TTS")
    --设置音量
    exaudio.vol(70)
    -- 主动下发一次播放请求
    sys.publish("PLAY_DONE")
    while true do
        -- 等待播放请求
        sys.waitUntil("PLAY_DONE")
        -- 如果在打电话过程中本次不播放
        if is_calling == false then
            exaudio.play_start(audio_play_param) 
        end
    end
end

-- ====================== 场景处理函数 ======================
-- 呼入自动接听，等待对方挂断
local function handle_scenario(status)
    if status == "AUDIO_START" then
        play_extern_source()
    elseif status == "INCOMINGCALL" then
        -- 来电提前关闭PA，避免POP音
        exaudio.finish()
        -- 来电前停止音频播放
        -- 注意：关闭PA后，再停止音频播放，否则会因为PA未关闭产生POP音
        exaudio.play_stop({type = 1})
        is_calling = true
        -- 获取来电号码
        caller_number = cc.lastNum() or "未知号码"
        call_counter = call_counter + 1
        
        log.info("场景3", "收到来电，号码:", caller_number, "响铃次数:", call_counter)

        -- 响铃2声后自动接听
        if call_counter >= 2 then
            if exaudio.is_end() then
                log.info("场景3", "自动接听来电")
                cc.accept(0)
                call_counter = 0  -- 重置计数器
            end
        end
    elseif status == "SPEECH_START" then
        -- 语音通话真正开始
        log.info("场景3", "电话已接通，电话号码:", caller_number)
    elseif status == "DISCONNECTED" then
        -- 对方挂断通话
        log.info("场景3", "通话结束对方挂断")
        call_counter = 0  -- 重置计数器
        is_calling = false
        sys.publish("PLAY_DONE")
    end
end

-- ====================== 主事件处理器 ======================
local function cc_function(status)
    log.info("CC状态", status)
    handle_scenario(status)
    
    -- 所有场景都需要处理的通用状态
    if status == "READY" then
        sys.publish("CC_READY")  -- 发布系统就绪事件
    elseif status == "HANGUP_CALL_DONE" or status == "MAKE_CALL_FAILED" or status == "DISCONNECTED" then
        -- 通话结束，主动进入低功耗模式
        exaudio.pm(exaudio.SHUTDOWN)
    end
end

sys.subscribe("CC_IND", cc_function)

-- ====================== 电话系统初始化 ======================
local function init_cc()
    -- 初始化音频设备
    audio_drv.initAudioDevice()

    -- 等待电话系统就绪
    sys.waitUntil("CC_READY")
    
    -- 初始化电话功能
    cc.init(audio_drv.getMultimediaId())
    
    -- 启用通话录音（录音功能在cc_app中）
    enableRecording()
    log.info("cc_app", "电话系统初始化完成")
end

-- 启动初始化任务
sys.taskInit(init_cc)
sys.taskInit(audio_task)
