--[[
@module  cc_app
@summary 通话业务逻辑模块，实现4种通话场景的处理和通话录音功能
@version 1.0
@date    2025.10.21
@author  陈媛媛
@usage
本模块提供以下功能：
1. 设置 ACTIVE_SCENARIO 变量选择需要的场景（1-4）
2. 其他场景自动禁用，不会影响程序运行
3. 每个场景都有独立的状态处理逻辑
4. 实现通话录音功能

支持的场景：
[场景1] 呼入立即挂断（响铃3次后自动拒接）
[场景2] 呼入自动接听（响2声）+10秒后主动挂断
[场景3] 呼入自动接听（响2声）+等待对方挂断
[场景4] 主动呼出电话+等待对方挂断


注意事项：
1. 设置ACTIVE_SCENARIO选择要启用的场景（1-4）
2. 场景4会主动拨打电话（修改为自己测试时要拨打的电话号码）
3. 所有通话都会被录音（需确保存储空间足够）
]]

-- 引入音频设备模块
local audio_drv = require "audio_drv"

-- ====================== 配置区域 ======================
-- 设置当前激活的场景（1-4），注释掉不需要的场景
-- local ACTIVE_SCENARIO = 1  -- 场景1：呼入立即挂断
-- local ACTIVE_SCENARIO = 2  -- 场景2：呼入自动接听，10秒后主动挂断
--local ACTIVE_SCENARIO = 3  -- 场景3：呼入自动接听，等待对方挂断
 local ACTIVE_SCENARIO = 4  -- 场景4：主动呼出，等待对方挂断

-- 全局状态变量
local call_counter = 0                 -- 响铃计数器（用于场景1-3）
local caller_number = ""               -- 来电号码（用于场景1-3）
local is_connected = false             -- 通话连接状态标志（用于场景2）
local outgoing_number = "10000"  -- 呼出号码（用于场景4），修改为自己测试时要拨打的电话号码

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

-- 获取所有缓冲区
local function getRecordingBuffers()
    return {
        up1 = up1,
        up2 = up2,
        down1 = down1,
        down2 = down2
    }
end

-- ====================== 场景处理函数 ======================

-- 场景1：呼入立即挂断（响铃3次后）
local function handle_scenario1(status)
    if status == "INCOMINGCALL" then
        -- 获取来电号码
        caller_number = cc.lastNum() or "未知号码"
        call_counter = call_counter + 1
        
        log.info("场景1", "收到来电，号码:", caller_number, "响铃次数:", call_counter)
        
        -- 响铃3声后拒接
        if call_counter >= 3 then
            log.info("场景1", "拒接来电")
            cc.hangUp(0)
            call_counter = 0  -- 重置计数器
        end
    elseif status == "HANGUP_CALL_DONE" then
        log.info("场景1", "挂断完成")
        call_counter = 0
    end
end

-- 场景2挂断回调函数
local function scenario2_hangup_callback()
    log.info("场景2", "10秒通话结束，主动挂断")
    cc.hangUp(0)
    is_connected = false
end

-- 场景2：呼入自动接听，10秒后主动挂断
local function handle_scenario2(status)
    if status == "INCOMINGCALL" then
        -- 获取来电号码
        caller_number = cc.lastNum() or "未知号码"
        call_counter = call_counter + 1
        
        log.info("场景2", "收到来电，号码:", caller_number, "响铃次数:", call_counter)
        
        -- 响铃2声后自动接听
        if call_counter >= 2 then
            log.info("场景2", "自动接听来电")
            cc.accept(0)
            call_counter = 0  -- 重置计数器
        end
    elseif status == "ANSWER_CALL_DONE" then
        log.info("场景2", "接听完成，等待通话建立")
    elseif status == "SPEECH_START" then
        -- 语音通话真正开始
        if not is_connected then
            log.info("场景2", "通话已建立，开始计时")
            is_connected = true
            
            -- 创建10秒后挂断的定时器
            sys.timerStart(scenario2_hangup_callback, 10000)  -- 10秒后执行挂断
            log.info("场景2", "10秒挂断定时器创建成功")
        end
    elseif status == "HANGUP_CALL_DONE" or status == "DISCONNECTED" then
        log.info("场景2", "通话结束")
        is_connected = false
        
        -- 取消挂断定时器
        sys.timerStop(scenario2_hangup_callback)
        log.info("场景2", "已取消挂断定时器")
        
        call_counter = 0  -- 重置计数器
    end
end

-- 场景3：呼入自动接听，等待对方挂断
local function handle_scenario3(status)
    if status == "INCOMINGCALL" then
        -- 获取来电号码
        caller_number = cc.lastNum() or "未知号码"
        call_counter = call_counter + 1
        
        log.info("场景3", "收到来电，号码:", caller_number, "响铃次数:", call_counter)
        
        -- 响铃2声后自动接听
        if call_counter >= 2 then
            log.info("场景3", "自动接听来电")
            cc.accept(0)
            call_counter = 0  -- 重置计数器
        end
    elseif status == "SPEECH_START" then
        -- 语音通话真正开始
        log.info("场景3", "电话已接通，电话号码:", caller_number)
    elseif status == "DISCONNECTED" then
        -- 对方挂断通话
        log.info("场景3", "通话结束对方挂断")
        call_counter = 0  -- 重置计数器
    end
end

-- 场景4：主动呼出，等待对方挂断
local function handle_scenario4(status)
    if status == "CONNECTED" then
        log.info("场景4", "呼叫接通")
    elseif status == "DISCONNECTED" then
        log.info("场景4", "通话结束（对方挂断）")
    elseif status == "MAKE_CALL_FAILED" then
        log.info("场景4", "呼叫失败")
    end
end

-- 场景4拨号函数
local function dial_for_scenario4()
    log.info("场景4", "开始拨打", outgoing_number)
    cc.dial(0, outgoing_number)
end

-- ====================== 主事件处理器 ======================
sys.subscribe("CC_IND", function(status)
    log.info("CC状态", status)
    
    -- 根据激活的场景调用对应的处理函数
    if ACTIVE_SCENARIO == 1 then
        handle_scenario1(status)
    elseif ACTIVE_SCENARIO == 2 then
        handle_scenario2(status)
    elseif ACTIVE_SCENARIO == 3 then
        handle_scenario3(status)
    elseif ACTIVE_SCENARIO == 4 then
        handle_scenario4(status)
    end
    
    -- 所有场景都需要处理的通用状态
    if status == "READY" then
        sys.publish("CC_READY")  -- 发布系统就绪事件
        
        -- 场景4：电话系统就绪后自动拨号
        if ACTIVE_SCENARIO == 4 then
            sys.timerStart(dial_for_scenario4, 1000)  -- 延迟1秒拨号
        end
    elseif status == "HANGUP_CALL_DONE" or status == "MAKE_CALL_FAILED" or status == "DISCONNECTED" then
        
        audio.pm(0,audio.STANDBY)
        -- audio.pm(0,audio.SHUTDOWN)   --低功耗可以选择SHUTDOWN或者POWEROFF，如果codec无法断电用SHUTDOWN
    end
end)

-- ====================== 电话系统初始化 ======================
local function init_cc()
    -- 初始化音频设备（使用exaudio）
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

log.info("cc_app", "通话业务逻辑模块加载完成，当前场景:", ACTIVE_SCENARIO)

-- 导出录音相关功能（如果需要被其他模块使用）
-- return {
--     enableRecording = enableRecording,
--     getRecordingBuffers = getRecordingBuffers,
--     recordCallback = recordCallback
-- }