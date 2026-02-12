--[[
@module  cc_tts_app
@summary TTS循环播放与通话处理模块，实现来电自动接听和通话录音功能
@version 1.0
@date    2026.01.29
@author  拓毅恒
@usage
本模块提供以下功能：
1. 循环播放TTS语音提示（"支付宝到账，1千万元"）
2. 来电自动接听（响铃2声后自动接听）
3. 通话过程中自动暂停TTS播放
4. 通话结束后自动恢复TTS播放
5. 实现通话录音功能

工作流程：
- 系统启动后循环播放TTS语音
- 收到来电时，响铃2声后自动接听
- 通话过程中暂停TTS播放
- 通话结束后继续播放TTS

注意事项：
1. 所有通话都会被录音（需确保存储空间足够）
2. 来电时会自动关闭音频输出，避免POP音
3. TTS播放音量设置为50，可根据需要调整
]]

-- 引入音频设备模块
local audio_drv = require "audio_drv"
local exaudio = require "exaudio"

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
    content = "支付宝到账,1千万元",          -- 如果播放类型为0时，则填入string 是播放单个音频文件,如果是表则是播放多段音频文件。
    cbfnc = play_end,            -- 播放完毕回调函数
}

local function audio_task()
    log.info("开始播放TTS")
    --设置音量
    exaudio.vol(50)
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
    if status == "INCOMINGCALL" then
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
        exaudio.pm(audio.SHUTDOWN)   --主动进入低功耗模式
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