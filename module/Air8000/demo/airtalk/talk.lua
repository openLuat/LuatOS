--[[
@module  talk
@summary Airtalk 对讲业务核心模块
@date    2025.12.03
@author  陈媛媛
@usage
本demo演示的核心功能为：
1. 支持广播对讲（一对多）和一对一对讲；
2. 自动设备发现和管理；
3. 按一次Boot键选择指定设备，开始1对1对讲，再按一次Boot键或powerkey键结束对讲；
4. 按一次powerkey键开始一对多广播，再按一次Boot键或powerkey键结束广播；
5. 通过LED指示灯显示对讲状态（亮：对讲中，灭：空闲）；
6. 支持目标设备ID指定呼叫，可配置TARGET_DEVICE_ID呼叫特定设备；
7. 支持4G和WiFi两种联网方式，默认使用4G网络。
]]

local extalk = require "extalk"
local audio_drv = require "audio_drv"  -- 引入音频驱动模块

-- 配置日志格式
log.style(1)

-- 常量定义
local USER_TASK_NAME = "user_task"  -- 用户任务名称
local MSG_KEY_PRESS = 12            -- 按键消息类型
local MSG_NETWORK_READY = 13        -- 网络就绪消息类型

-- 目标设备ID，修改为你想要对讲的终端ID
TARGET_DEVICE_ID = "78122397"

-- 全局状态变量
local g_dev_list = nil              -- 设备列表，存储所有可用对讲设备
local g_speech_active = false       -- 对讲状态标记，true表示正在对讲中
local g_network_ready = false       -- 网络就绪标志

-- 指示灯配置
-- Air8000核心板：GPIO20（核心板板载LED指示灯）
-- Air8000开发板：GPIO146（开发板上的LED指示灯）
local LED_GPIO = 146
local LED = nil

-- ========================== 联网方式配置 ==========================

-- WiFi连接参数（如果需要使用WiFi联网，请取消注释use_wifi函数调用）
local WIFI_CONFIG = {
    ssid = "茶室-降功耗,找合宙!",
    password = "Air123456",

}

-- 低功耗模式配置
local POWER_SAVE_CONFIG = {
    enable_wifi_low_power = true,   -- 启用WiFi低功耗
    enable_4g_low_power = true,     -- 启用4G低功耗
    pause_airlink = true,           -- 暂停airlink通信
}

-- ========================== 联系人列表回调 ==========================

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

-- ========================== 对讲状态回调 ==========================

-- 对讲状态回调函数
local function speech_state_callback(event_table)
    if not event_table then return end
    
    if event_table.state == extalk.START then
        log.info("对讲开始")
        if LED then LED(1) end  -- LED亮
        g_speech_active = true
    elseif event_table.state == extalk.STOP then
        if LED then LED(0) end  -- LED灭
        log.info("对讲结束")
        g_speech_active = false
    elseif event_table.state == extalk.UNRESPONSIVE then
        if LED then LED(0) end  -- LED灭
        log.info("对端未响应")
        g_speech_active = false
    elseif event_table.state == extalk.ONE_ON_ONE then
        if LED then LED(1) end  -- LED亮
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
        if LED then LED(1) end  -- LED亮
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
    contact_list_cbfnc = contact_list_callback,
    state_cbfnc = speech_state_callback,
}

-- ========================== 按键处理 ==========================

-- Boot键回调函数
local function boot_key_callback()
    log.info("boot_key_callback")
    sys.sendMsg(USER_TASK_NAME, MSG_KEY_PRESS, false)  -- false表示Boot键
end

-- Power键回调函数
local function power_key_callback()
    log.info("power_key_callback")
    sys.sendMsg(USER_TASK_NAME, MSG_KEY_PRESS, true)   -- true表示Power键
end

-- 网络状态回调函数
local function network_status_callback(net_type, adapter)
    log.info("网络切换至:", net_type)
    if net_type and not g_network_ready then
        log.info("网络已就绪，准备初始化对讲功能")
        g_network_ready = true
        sys.sendMsg(USER_TASK_NAME, MSG_NETWORK_READY, {net_type = net_type, adapter = adapter})
    end
end

-- WiFi STA连接事件回调函数
local function wlan_sta_callback(evt, data)
    -- evt 可能的值有: "CONNECTED", "DISCONNECTED"
    -- 当evt=CONNECTED, data是连接的AP的ssid, 字符串类型
    -- 当evt=DISCONNECTED, data断开的原因, 整数类型
    log.info("WiFi STA事件", evt, data)
    if evt == "CONNECTED" then
        log.info("WiFi已连接，等待获取IP地址")
    end
end

-- IP就绪事件回调
local function ip_ready_callback(ip, adapter)
    log.info("IP就绪事件", ip, adapter)
    if not g_network_ready and ip and ip ~= "0.0.0.0" then
        log.info("IP地址已获取，网络就绪")
        g_network_ready = true
        
        -- 获取网卡类型名称
        local adapter_names = {
            [socket.LWIP_ETH] = "以太网",
            [socket.LWIP_STA] = "WiFi",
            [socket.LWIP_GP] = "4G",
            [socket.LWIP_USER1] = "8101SPI以太网"
        }
        local adapter_name = adapter_names[adapter] or "未知"
        
        sys.sendMsg(USER_TASK_NAME, MSG_NETWORK_READY, {net_type = adapter_name, adapter = adapter, ip = ip})
    end
end

-- 初始化按键
local function init_buttons()
    -- 配置Boot键 (GPIO0)，下拉电阻，上升沿触发
    gpio.setup(0, boot_key_callback, gpio.PULLDOWN, gpio.RISING)
    gpio.debounce(0, 200, 1)  -- 200ms去抖
    
    -- 配置Power键，上拉电阻，下降沿触发
    gpio.setup(gpio.PWR_KEY, power_key_callback, gpio.PULLUP, gpio.FALLING)
    gpio.debounce(gpio.PWR_KEY, 200, 1)  -- 200ms去抖
end

-- 处理按键消息
local function handle_key_press(is_power_key)
    if g_speech_active then
        -- 当前正在对讲，按任何键都结束对讲
        log.info("结束当前对讲")
        extalk.stop()
        if LED then LED(0) end  -- 关闭LED
        g_speech_active = false
    else
        -- 当前未在对讲，根据按键类型开始不同对讲
        if is_power_key then
            -- Power键：开始一对多广播
            log.info("开始一对多广播")
            extalk.start()  -- 不带参数表示广播
        else
            -- Boot键：开始一对一对讲
            -- 只呼叫指定的目标设备，不查找其他设备
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

-- ========================== 联网功能 ==========================

-- WiFi功能（可选）
local function use_wifi()
    log.info("配置WiFi联网...")
    local exnetif = require("exnetif")

    -- 设置网络优先级，WiFi作为次优先级
    exnetif.set_priority_order({ { 
        WIFI = {
            ssid = WIFI_CONFIG.ssid,
            password = WIFI_CONFIG.password,
        }
    }})

    -- 设置网络状态回调
    exnetif.notify_status(network_status_callback)

    -- 订阅WiFi STA连接事件
    sys.subscribe("WLAN_STA_INC", wlan_sta_callback)
    
    -- 订阅IP就绪事件（作为备份，以防exnetif回调不触发）
    sys.subscribe("IP_READY", ip_ready_callback)
end

-- 等待低功耗模式设置的函数
local function wait_low_power_setup()
    -- 使用sys.wait等待低功耗模式设置生效
    -- 原因：需要等待硬件完成低功耗切换，通常需要几毫秒到几十毫秒
    -- 使用20ms的等待时间，确保设置生效
    sys.wait(20)  -- 等待20ms，确保低功耗模式设置生效
end

-- 低功耗模式（可选）
local function lower_enter()
    log.info("进入低功耗模式...")
    
    if POWER_SAVE_CONFIG.enable_wifi_low_power then
        -- WiFi模组进入低功耗模式
        pm.power(pm.WORK_MODE, 1, 1)
        log.info("WiFi低功耗模式已启用")
    end
    
    if POWER_SAVE_CONFIG.enable_4g_low_power then
        -- 4G模组进入低功耗模式
        pm.power(pm.WORK_MODE, 1)
        log.info("4G低功耗模式已启用")
    end
    
    -- 等待低功耗模式设置生效
    wait_low_power_setup()
    
    if POWER_SAVE_CONFIG.pause_airlink then
        -- 暂停airlink通信，进一步降低功耗
        airlink.pause(1)
        log.info("airlink通信已暂停")
    end
    
    log.info("低功耗模式配置完成")
end

-- ========================== 主任务 ==========================

-- 检查网络状态
local function check_network_status()
    log.info("主动检查网络状态...")
    
    -- 获取当前默认网卡
    local default_adapter = socket.dft()
    if default_adapter then
        local adapter_names = {
            [socket.LWIP_ETH] = "以太网",
            [socket.LWIP_STA] = "WiFi",
            [socket.LWIP_GP] = "4G",
            [socket.LWIP_USER1] = "8101SPI以太网"
        }
        local adapter_name = adapter_names[default_adapter] or "未知"
        log.info("当前默认网卡:", adapter_name, "适配器ID:", default_adapter)
        
        -- 获取当前默认网卡的IP地址
        local ip, mask, gw = socket.localIP()
        if ip and ip ~= "0.0.0.0" then
            log.info("IP地址:", ip, "子网掩码:", mask, "网关:", gw)
            return true, {net_type = adapter_name, adapter = default_adapter, ip = ip}
        else
            log.warn("默认网卡未获取到有效IP地址")
        end
    else
        log.warn("无法获取当前默认网卡")
    end
    
    return false
end

-- 初始化对讲功能
local function init_extalk()
    log.info("初始化extalk对讲功能...")
    
    local extalk_init_ok = extalk.setup(extalk_configs)
    if not extalk_init_ok then
        log.error("extalk初始化失败")
        return false
    end
    log.info("extalk初始化成功")
    return true
end

-- 等待网络就绪
local function wait_for_network()
    log.info("等待网络连接就绪...")
    
    -- 等待网络就绪消息，但也会主动检查
    local max_wait_time = 30000  -- 最长等待30秒
    local start_time = mcu.ticks()
    local network_ready = false
    
    while not network_ready and (mcu.ticks() - start_time < max_wait_time) do
        -- 等待网络就绪消息或主动检查
        local msg = sys.waitMsg(USER_TASK_NAME, MSG_NETWORK_READY, 2000)
        if msg and msg[1] == MSG_NETWORK_READY then
            log.info("收到网络就绪消息:", msg[2].net_type, "IP:", msg[2].ip or "未知")
            network_ready = true
        else
            -- 主动检查网络状态
            local status_ok, network_info = check_network_status()
            if status_ok and not network_ready then
                log.info("主动检查发现网络已就绪")
                network_ready = true
                sys.sendMsg(USER_TASK_NAME, MSG_NETWORK_READY, network_info)
            end
        end
        
        -- 超时检查
        if mcu.ticks() - start_time > max_wait_time then
            log.warn("网络连接超时，尝试强制初始化对讲")
            break
        end
    end
    
    return network_ready
end

-- 用户主任务
local function user_main_task()
    log.info("启动对讲系统...")
    
    -- 初始化LED指示灯
    LED = gpio.setup(LED_GPIO, 1)
    if LED then
        LED(0)  -- 初始状态关闭
        log.info("LED指示灯初始化完成 - GPIO"..LED_GPIO)
    else
        log.warn("LED初始化失败，GPIO"..LED_GPIO)
    end
    
    -- 初始化音频设备
    log.info("初始化音频设备...")
    if not audio_drv.init() then
        log.error("音频初始化失败")
        return
    end
    log.info("音频初始化成功")

    -- 【可选】使用WiFi联网（取消注释以启用）
    -- use_wifi()
    
    -- 【可选】进入低功耗模式（取消注释以启用）
    -- lower_enter()
    
    -- 等待网络就绪
    local network_ready = wait_for_network()
    
    -- 如果网络就绪，初始化对讲功能
    if network_ready then
        if not init_extalk() then
            log.error("对讲功能初始化失败，系统无法正常工作")
            return
        end
    else
        log.warn("网络未就绪，但尝试强制初始化对讲")
        if not init_extalk() then
            log.error("对讲功能初始化失败，系统无法正常工作")
            return
        end
    end
    
    log.info("对讲系统准备就绪，等待按键操作...")
    
    -- 主消息循环 - 等待和处理按键消息
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