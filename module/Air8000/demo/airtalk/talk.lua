--[[
@module  talk
@summary Airtalk 对讲业务核心模块
@date    2025.12.08
@author  陈媛媛
@usage
本demo演示的核心功能为：
1. 支持广播对讲（一对多）和一对一对讲；
2. 自动设备发现和管理；
3. 按一次Boot键选择指定设备，开始1对1对讲，再按一次Boot键或powerkey键结束对讲；
4. 按一次powerkey键开始一对多广播，再按一次Boot键或powerkey键结束广播；
5. 通过LED指示灯显示对讲状态（亮：对讲中，灭：空闲）；
6. 支持目标设备ID指定呼叫，可配置TARGET_DEVICE_ID呼叫特定设备；
注意：网络配置已拆分到netdrv_device.lua模块
]]

local extalk = require "extalk"
local audio_drv = require "audio_drv"  -- 引入音频驱动模块

-- 配置日志格式
log.style(1)

-- 常量定义
local USER_TASK_NAME = "user_task"  -- 用户任务名称
local MSG_KEY_PRESS = 12            -- 按键消息类型

-- 目标设备ID，修改为你想要对讲的终端ID
TARGET_DEVICE_ID = "78122397"  

-- 全局状态变量
local g_dev_list = nil              -- 设备列表，存储所有可用对讲设备
local g_speech_active = false       -- 对讲状态标记，true表示正在对讲中

-- 指示灯配置
-- Air8000核心板：GPIO20（核心板板载LED指示灯）
-- Air8000开发板：GPIO146（开发板上的LED指示灯）
-- 根据实际使用的硬件选择合适的GPIO号
local LED_GPIO = 20
local LED = nil

-- ========================== 联系人列表回调 ==========================

-- 联系人列表回调函数
-- @param dev_list 设备列表，包含所有在线对讲设备信息
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

-- ========================== 对讲状态回调 ==========================

-- 对讲状态回调函数
-- @param event_table 事件表，包含状态和设备ID等信息
local function speech_state_callback(event_table)
    if not event_table then return end
    
    -- 对讲开始（广播或一对一通话已开始）
    if event_table.state == extalk.START then
        log.info("对讲开始")
        LED(1)  -- LED亮
        g_speech_active = true
        
    -- 对讲结束（广播或一对一通话已结束）
    elseif event_table.state == extalk.STOP then
        LED(0)  -- LED灭
        log.info("对讲结束")
        g_speech_active = false
        
    -- 对端未响应（一对一呼叫时对方无应答）
    elseif event_table.state == extalk.UNRESPONSIVE then
        LED(0)  -- LED灭
        log.info("对端未响应")
        g_speech_active = false
        
    -- 一对一呼叫建立（已连接到指定设备）
    elseif event_table.state == extalk.ONE_ON_ONE then
        LED(1)  -- LED亮
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
        
    -- 广播开始（已进入广播模式）
    elseif event_table.state == extalk.BROADCAST then
        LED(1)  -- LED亮
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

-- ========================== extalk配置 ==========================

-- extalk配置参数
local extalk_configs = {
    key = PRODUCT_KEY,           -- 产品密钥，从main.lua传入
    heart_break_time = 120,      -- 心跳间隔(单位秒)
    contact_list_cbfnc = contact_list_callback,  -- 联系人列表回调
    state_cbfnc = speech_state_callback,         -- 状态回调
}

-- ========================== 按键处理 ==========================

-- Boot键回调函数
local function boot_key_callback()
    log.info("boot_key_callback - Boot键按下")
    sys.sendMsg(USER_TASK_NAME, MSG_KEY_PRESS, false)  -- false表示Boot键
end

-- Power键回调函数
local function power_key_callback()
    log.info("power_key_callback - Power键按下")
    sys.sendMsg(USER_TASK_NAME, MSG_KEY_PRESS, true)   -- true表示Power键
end

-- 初始化按键
local function init_buttons()
    -- 配置Boot键，下拉电阻，上升沿触发
    gpio.setup(0, boot_key_callback, gpio.PULLDOWN, gpio.RISING)
    gpio.debounce(0, 200, 1)  -- 200ms去抖
    
    -- 配置Power键，上拉电阻，下降沿触发  
    gpio.setup(gpio.PWR_KEY, power_key_callback, gpio.PULLUP, gpio.FALLING)
    gpio.debounce(gpio.PWR_KEY, 200, 1)  -- 200ms去抖
    
    log.info("按键初始化完成 - Boot键: GPIO0, Power键: GPIO"..gpio.PWR_KEY)
end

-- 处理按键消息
-- 1. 如果正在对讲，按任何键都结束对讲
-- 2. 如果空闲，Boot键开始一对一，Power键开始广播
-- @param is_power_key true表示Power键，false表示Boot键
local function handle_key_press(is_power_key)
    if g_speech_active then
        -- 当前正在对讲，按任何键都结束对讲 
        log.info("结束当前对讲")
        extalk.stop()
        LED(0)  -- 关闭LED
        g_speech_active = false
    else
        -- 当前未在对讲，根据按键类型开始不同对讲
        if is_power_key then
            -- Power键：开始一对多广播
            log.info("开始一对多广播")
            extalk.start()  -- 不带参数表示广播
        else
            -- Boot键：开始一对一对讲
            -- 只呼叫指定设备，设备不存在就报错
            if TARGET_DEVICE_ID and TARGET_DEVICE_ID ~= "" then
                -- 直接呼叫指定设备
                log.info("开始一对一对讲，目标设备:", TARGET_DEVICE_ID)
                extalk.start(TARGET_DEVICE_ID)
            else
                log.error("无法开始一对一对讲，未配置目标设备ID")
                log.error("请在talk.lua中设置TARGET_DEVICE_ID变量")
            end
        end
    end
end

-- ========================== 主任务 ==========================

-- 用户主任务
local function user_main_task()
    log.info("启动对讲系统...")
    
    -- 初始化LED指示灯
    LED = gpio.setup(LED_GPIO, 1)
    LED(0)  -- 初始状态关闭
    log.info("LED指示灯初始化完成 - GPIO"..LED_GPIO)
    
    -- 初始化音频设备
    log.info("初始化音频设备...")
    if not audio_drv.init() then
        log.error("音频初始化失败")
        return
    end
    log.info("音频初始化成功")
    
    -- 初始化extalk对讲功能
    log.info("初始化extalk对讲功能...")
    local extalk_init_ok = extalk.setup(extalk_configs)
    if not extalk_init_ok then
        log.error("extalk初始化失败")
        return
    end
    log.info("extalk初始化成功")
    
    -- 显示当前配置信息
    log.info("========== 系统配置信息 ==========")
    log.info("目标设备ID:", TARGET_DEVICE_ID or "未配置（必须配置！）")
    log.info("联网方式: 由netdrv_device.lua配置")
    log.info("按键配置:", "Boot键(GPIO0)=一对一呼叫，Power键=广播")
    log.info("按键逻辑:", "对讲中按任意键=结束对讲，空闲时按Boot键=一对一呼叫，按Power键=广播")
    log.info("==================================")
    
    -- 检查目标设备配置
    if not TARGET_DEVICE_ID or TARGET_DEVICE_ID == "" then
        log.error("警告：TARGET_DEVICE_ID未配置！")
        log.error("请修改talk.lua文件，设置TARGET_DEVICE_ID为目标设备ID")
    else
        log.info("目标设备已配置:", TARGET_DEVICE_ID)
    end
    
    log.info("对讲系统准备就绪，等待按键操作...")
    
    -- 主消息循环 - 等待和处理按键消息
    -- 使用sys.waitMsg等待按键消息，这是必要的阻塞等待
    while true do
        local msg = sys.waitMsg(USER_TASK_NAME, MSG_KEY_PRESS)
        if msg and msg[1] == MSG_KEY_PRESS then
            handle_key_press(msg[2])  -- msg[2]区分Power键(true)和Boot键(false)
        end
    end
end

-- ========================== 初始化 ==========================

-- 系统初始化
local function init()
    log.info("对讲模块初始化...")
    init_buttons()
    -- 使用sys.taskInitEx创建支持waitMsg的任务
    sys.taskInitEx(user_main_task, USER_TASK_NAME)
end

-- 直接初始化，无需等待
init()

log.info("talk.lua加载完成")