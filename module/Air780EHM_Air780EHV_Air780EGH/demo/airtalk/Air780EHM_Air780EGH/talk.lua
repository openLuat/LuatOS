--[[
@module  talk
@summary Airtalk 对讲业务核心模块
@date    2025.11.26
@author 陈媛媛
@usage
本demo演示的核心功能为：
    1. 支持广播对讲（一对多）和一对一对讲；
    2. 自动设备发现和管理；
    3. 按一次Boot键选择指定设备，开始1对1对讲，再按一次Boot键或powerkey键结束对讲；
    4. 按一次powerkey键开始一对多广播，再按一次Boot键或powerkey键结束广播。

]]

local extalk = require "extalk"
local audio_drv = require "audio_drv"  -- 引入音频驱动模块

-- 配置日志格式
log.style(1)

-- 常量定义
local USER_TASK_NAME = "user_task"  -- 用户任务名称
local MSG_KEY_PRESS = 12            -- 按键消息类型

-- 目标设备终端ID，修改为你想要对讲的终端ID
TARGET_DEVICE_ID = "78122397"  -- 请替换为实际的目标设备终端ID


-- 全局状态变量
local g_dev_list = nil              -- 设备列表，存储所有可用对讲设备
local g_speech_active = false       -- 对讲状态标记，true表示正在对讲中

-- 联系人列表回调函数
-- 当设备列表更新时调用，维护当前可用的对讲设备
local function contact_list_callback(dev_list)
    g_dev_list = dev_list
    if dev_list and #dev_list > 0 then
        log.info("联系人列表更新:")
        for i = 1, #dev_list do
            log.info(string.format("  %d. ID: %s, 名称: %s", 
                i, dev_list[i]["id"], dev_list[i]["name"] or "未知"))
        end
    else
        log.info("联系人列表为空")
    end
end

-- 对讲状态回调函数
-- 处理对讲状态变化事件
local function speech_state_callback(event_table)
    if not event_table then return end
    
    if event_table.state == extalk.START then
        -- extalk.START: 对讲开始（广播或一对一通话已开始）
        log.info("对讲开始")
        g_speech_active = true
    elseif event_table.state == extalk.STOP then
        -- extalk.STOP: 对讲结束（广播或一对一通话已结束）
        log.info("对讲结束")
        g_speech_active = false
    elseif event_table.state == extalk.UNRESPONSIVE then
        -- extalk.UNRESPONSIVE: 对端未响应（一对一呼叫时对方无应答）
        log.info("对端未响应")
        g_speech_active = false
    elseif event_table.state == extalk.ONE_ON_ONE then
        -- extalk.ONE_ON_ONE: 一对一呼叫建立（已连接到指定设备）
        g_speech_active = true
        local dev_name = "未知设备"
        if g_dev_list then
            for i = 1, #g_dev_list do
                if g_dev_list[i]["id"] == event_table.id then
                    dev_name = g_dev_list[i]["name"] or "未知设备"
                    break
                end
            end
        end
        log.info(string.format("%s 来电", dev_name))
    elseif event_table.state == extalk.BROADCAST then
        -- 收到对端广播请求（已进入广播接收模式）
        g_speech_active = true
        local dev_name = "未知设备"
        if g_dev_list then
            for i = 1, #g_dev_list do
                if g_dev_list[i]["id"] == event_table.id then
                    dev_name = g_dev_list[i]["name"] or "未知设备"
                    break
                end
            end
        end
        log.info(string.format("%s 开始广播", dev_name))
    end

    log.info("当前对讲状态:", g_speech_active and "正在对讲" or "空闲")
end

-- extalk配置参数
local extalk_configs = {
    key = PRODUCT_KEY,           -- 产品密钥
    heart_break_time = 120,      -- 心跳间隔(单位秒)
    contact_list_cbfnc = contact_list_callback,  -- 联系人列表回调
    state_cbfnc = speech_state_callback,         -- 状态回调
}

-- Boot键回调函数
-- GPIO0按键，用于一对一對講控制
local function boot_key_callback()
    log.info("boot_key_callback")
    sys.sendMsg(USER_TASK_NAME, MSG_KEY_PRESS, false)  -- false表示Boot键
end

-- Power键回调函数  
-- 电源按键，用于广播对讲控制
local function power_key_callback()
    log.info("power_key_callback")
    sys.sendMsg(USER_TASK_NAME, MSG_KEY_PRESS, true)   -- true表示Power键
end

-- 初始化按键
-- 配置Boot键和Power键的GPIO中断
local function init_buttons()
    -- 配置Boot键 (GPIO0)，下拉电阻，上升沿触发
    gpio.setup(0, boot_key_callback, gpio.PULLDOWN, gpio.RISING)
    gpio.debounce(0, 200, 1)  -- 200ms去抖，防止按键抖动
    
    -- 配置Power键，上拉电阻，下降沿触发  
    gpio.setup(gpio.PWR_KEY, power_key_callback, gpio.PULLUP, gpio.FALLING)
    gpio.debounce(gpio.PWR_KEY, 200, 1)  -- 200ms去抖，防止按键抖动
end

-- 查找目标设备
-- 根据配置的目标ID，不自动查找其他设备
local function find_target_device()
    -- 优先使用配置的目标ID
    if TARGET_DEVICE_ID and TARGET_DEVICE_ID ~= "" then
        return TARGET_DEVICE_ID
    end
    
    -- 没有配置目标ID，直接返回nil，不自动查找其他设备
    log.warn("未配置目标设备ID")
    return nil
end

-- 处理按键消息，在结束对讲时立即更新状态
local function handle_key_press(is_power_key)
    if g_speech_active then
        -- 当前正在对讲，按任何键都结束对讲 
        log.info("结束当前对讲")
        extalk.stop()
        g_speech_active = false  -- 立即更新状态
    else
        -- 当前未在对讲，根据按键类型开始不同对讲
        if is_power_key then
            -- Power键：开始一对多广播
            log.info("开始一对多广播")
            extalk.start()  -- 不带参数表示广播
        else
            -- Boot键：开始一对一对讲
            log.info("开始一对一对讲")
            local remote_id = find_target_device()
            if remote_id then
                extalk.start(remote_id)
            else
                log.error("无法开始一对一对讲，没有找到可用设备")
            end
        end
    end
end

-- 用户主任务
-- 系统初始化主流程和对讲功能主循环
local function user_main_task()
    -- 初始化音频设备
    log.info("初始化音频...")
    if not audio_drv.init() then
        log.error("音频初始化失败")
        return
    end
    log.info("音频初始化成功")
    
    -- 初始化extalk对讲功能
    log.info("初始化extalk...")
    local extalk_init_ok = extalk.setup(extalk_configs)
    if not extalk_init_ok then
        log.error("extalk初始化失败")
        return
    end
    log.info("extalk初始化成功")
    
    log.info("对讲系统准备就绪")
    
    -- 主消息循环 - 等待和处理按键消息
    while true do
        local msg = sys.waitMsg(USER_TASK_NAME, MSG_KEY_PRESS)
        if msg and msg[1] == MSG_KEY_PRESS then
            handle_key_press(msg[2])  -- msg[2]区分Power键(true)和Boot键(false)
        end
    end
end

-- 系统初始化
-- 配置按键并启动用户主任务
local function init()
    init_buttons()
    -- 使用sys.taskInitEx创建支持waitMsg的任务
    sys.taskInitEx(user_main_task, USER_TASK_NAME)
end

-- 直接初始化，无需等待
init()