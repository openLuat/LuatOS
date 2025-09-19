--[[
    演示airtalk基本功能
    按一次boot，开始1对1对讲，再按一次boot，结束对讲
    按一次powerkey，开始1对多对讲，再按一次powerkey或者boot，结束对讲
]]

-- 引入必要模块

local extalk = require "extalk"
local exaudio = require "exaudio"

-- 配置日志格式
log.style(1)

-- 常量定义
local USER_TASK_NAME = "user_task"
local MSG_KEY_PRESS = 12  -- 按键消息

-- 全局状态变量
local g_dev_list = nil    -- 设备列表
local g_speech_active = false  -- 对讲状态标记

-- 音频初始化参数
local audio_setup_param = {
    model = "es8311",       -- 音频编解码类型,可填入"es8311","es8211"
    i2c_id = 0,             -- i2c_id,可填入0，1 并使用pins工具配置对应的管脚
    pa_ctrl = 162,          -- 音频放大器电源控制管脚
    dac_ctrl = 164,         -- 音频编解码芯片电源控制管脚    
}

-- 联系人列表回调函数
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
local function speech_state_callback(event_table)
    if not event_table then return end
    
    if event_table.state == extalk.START then
        log.info("对讲开始，可以说话了")
        g_speech_active = true
    elseif event_table.state == extalk.STOP then
        log.info("对讲结束")
        g_speech_active = false
    elseif event_table.state == extalk.UNRESPONSIVE then
        log.info("对端未响应")
        g_speech_active = false
    elseif event_table.state == extalk.ONE_ON_ONE then
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
end

-- extalk配置参数
local extalk_configs = {
    key = PRODUCT_KEY,
    heart_break_time = 120,  -- 心跳间隔(单位秒)
    contact_list_cbfnc = contact_list_callback,
    state_cbfnc = speech_state_callback,
}

-- 按键回调函数 - Boot键
local function boot_key_callback()
    sys.sendMsg(USER_TASK_NAME, MSG_KEY_PRESS, false)  -- false表示Boot键
end

-- 按键回调函数 - Power键
local function power_key_callback()
    sys.sendMsg(USER_TASK_NAME, MSG_KEY_PRESS, true)   -- true表示Power键
end

-- 初始化按键
local function init_buttons()
    -- 配置Boot键 (GPIO0)
    gpio.setup(0, boot_key_callback, gpio.PULLDOWN, gpio.RISING)
    gpio.debounce(0, 200, 1)  -- 200ms去抖
    
    -- 配置Power键
    gpio.setup(gpio.PWR_KEY, power_key_callback, gpio.PULLUP, gpio.FALLING)
    gpio.debounce(gpio.PWR_KEY, 200, 1)  -- 200ms去抖
end

-- 查找第一个可用的对端设备ID
local function find_first_remote_device()
    if not g_dev_list or #g_dev_list == 0 then
        log.warn("没有找到可用的设备")
        return nil
    end
    
    local local_id = mobile.imei()
    for i = 1, #g_dev_list do
        local dev_id = g_dev_list[i]["id"]
        if dev_id and dev_id ~= local_id then
            return dev_id
        end
    end
    
    log.warn("没有找到其他可用设备")
    return nil
end

-- 处理按键消息
local function handle_key_press(is_power_key)
    if g_speech_active then
        -- 当前正在对讲，按任何键都结束对讲
        log.info("结束当前对讲")
        extalk.stop()
        g_speech_active = false
    else
        -- 当前未在对讲，根据按键类型开始不同对讲
        if is_power_key then
            -- Power键：开始一对多广播
            log.info("开始一对多广播")
            extalk.start()  -- 不带参数表示广播
        else
            -- Boot键：开始一对一对讲
            log.info("开始一对一对讲")
            local remote_id = find_first_remote_device()
            if remote_id then
                extalk.start(remote_id)
            else
                log.error("无法开始一对一对讲，没有找到可用设备")
            end
        end
    end
end



-- 用户主任务
local function user_main_task()
    -- 初始化音频
    local audio_init_ok = exaudio.setup(audio_setup_param)
    if not audio_init_ok then
        log.error("音频初始化失败")
        return
    end
    log.info("音频初始化成功")
    
    -- 初始化extalk
    local extalk_init_ok = extalk.setup(extalk_configs)
    if not extalk_init_ok then
        log.error("extalk初始化失败")
        return
    end
    log.info("extalk初始化成功")
    
    -- 等待按键消息并处理
    while true do
        local msg = sys.waitMsg(USER_TASK_NAME, MSG_KEY_PRESS)
        if msg and msg[1] == MSG_KEY_PRESS then
            handle_key_press(msg[2])  -- msg[2]区分是Power键(true)还是Boot键(false)
        end
    end
end

-- 初始化按键
init_buttons()

-- 启动用户任务
sys.taskInitEx(user_main_task, USER_TASK_NAME)


