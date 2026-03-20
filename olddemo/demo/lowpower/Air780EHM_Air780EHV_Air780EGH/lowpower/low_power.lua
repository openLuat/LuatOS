--[[
@module  low_power
@summary 低功耗模式主应用功能模块 
@version 1.0
@date    2025.07.17
@author  陈取德
@usage
本文件为低功耗模式主应用功能模块，核心业务逻辑为：
1、进入低功耗模式
2、判断是否在低功耗模式下使用手机卡、连接TCP服务器和发送平台心跳包
使用前请根据需要，变更功能变量。条件不同，功耗体现不同。
本文件没有对外接口，直接在main.lua中require "low_power"就可以加载运行；
]] --
----是否需要插入手机卡，测试连接网络状态下功耗--------------------------------------
local mobile_mode = false -- true 需要   --false 不需要
-------------------------------------------------------------------------------

-----是否需要保持服务器心跳------------------------------------------------------
local tcp_mode = true -- true 需要连接TCP服务器，设置下方心跳包。    --false 不需要连接TCP服务器，不需要设置心跳包。
local tcp_heartbeat = 5 -- 常规模式和低功耗模式心跳包，单位（分钟），输入 1 为一分钟一次心跳包。
local heart_data = string.rep("1234567890", 3) -- 心跳包数据内容，可自定义。
-------------------------------------------------------------------------------

--[[
本函数为GPIO配置函数，核心业务逻辑为：
1、关闭Vref管脚，默认拉高，会影响功耗展示，关闭后有效降低功耗。
2、将所有WAEKUP管脚设置为输入模式内部拉低可以有效防止管脚漏电发生。
本函数属于饱和式管脚配置，调用后可以防止下列管脚的状态异常，导致功耗异常增高，也可以不调用，根据实际情况选择；
]] --
function GPIO_setup()
    local lowpower_module = hmeta.model()
    -- 判断使用的模组型号，如果为Air8000A/AB/N/U/W，则不允许控制GPIO22和GPIO23
    -- 在含WIFI功能的Air8000系列模组中，GPIO23为WIFI芯片的供电使能脚，GPIO22为WIFI芯片的通讯脚，不允许控制
    if lowpower_module ~= "Air8000A" and lowpower_module ~= "Air8000AB" and lowpower_module ~= "Air8000N" and lowpower_module ~= "Air8000U" and lowpower_module ~= "Air8000W" then

        -- 在不含WIFI的Air8000系列，Air780系列，Air700系列模组中GPIO23是Vref参考电压管脚，固件默认拉高，会影响功耗展示，关闭可有效降低功耗。
        -- Air780EGH/EGG/EGP中，Vref为定位芯片备电使用，在含Gsensor的型号中作为Gsensor的供电使能，关闭后会影响功能使用，需根据实际情况选择是否关闭
        gpio.setup(23, nil, gpio.PULLDOWN)

        -- gpio.WAKEUP5 = GPIO 22，不需要使用时主动将其关闭可避免漏电风险
        -- 如测试模块型号为Air780EHV时，需注意如调用了exaudio库，该管脚为外部PA控制脚，不要配置，否则会导致外部PA无法正常工作
        gpio.setup(gpio.WAKEUP5, nil, gpio.PULLDOWN)
        -- 可在进入低功耗模式时保持管脚状态，也可以配置为中断拉低触发唤醒,选择对应配置代码即可
        -- gpio.setup(gpio.WAKEUP5, gpio_wakeup, gpio.PULLUP, gpio.FALLING)
        log.info("模组非8000含WIFI",lowpower_module)
    end
    -- WAKEUP0专用管脚，无复用，不需要使用时主动将其关闭可避免漏电风险
    gpio.setup(gpio.WAKEUP0, nil, gpio.PULLDOWN)

    -- gpio.WAKEUP1 = VBUS，检测USB插入使用，关闭则无法检测是否插入USB，不需要使用时主动将其关闭可避免漏电风险
    gpio.setup(gpio.WAKEUP1, nil, gpio.PULLDOWN)

    -- gpio.WAKEUP2 = SIM卡的DET检测脚，用于检测是否插卡，关闭则无法检测是否插卡，不需要使用时主动将其关闭可避免漏电风险
    gpio.setup(gpio.WAKEUP2, nil, gpio.PULLDOWN)

    -- gpio.WAKEUP3 = GPIO 20，不需要使用时主动将其关闭可避免漏电风险
    -- 如测试模块型号为Air780EHV时，需注意该管脚内部用于控制Audio Codec芯片ES8311的开关，不要配置，否则会导致Audio Codec芯片ES8311无法正常工作
    gpio.setup(gpio.WAKEUP3, nil, gpio.PULLDOWN)

    -- gpio.WAKEUP4 = GPIO 21，不需要使用时主动将其关闭可避免漏电风险
    -- 如测试模块型号为Air780EGP/EGG/EGH时，需注意该管脚内部用于控制GNSS定位芯片的开关使能，不要配置，否则会导致GNSS定位芯片无法正常工作
    gpio.setup(gpio.WAKEUP4, nil, gpio.PULLDOWN)

    -- 如果硬件上PWR_KEY接地自动开机，可能会有漏电流风险，配置关闭可避免功耗异常，没接地可以不关
    gpio.setup(gpio.PWR_KEY, nil, gpio.PULLDOWN)
    
    -- 关闭USB以后可以降低约150ua左右的功耗，如果不需要USB可以关闭
    pm.power(pm.USB, false)
end

--[[
本函数为low_power低功耗模式主应用功能函数，核心业务逻辑为：
1、判断是否开启4G、连接TCP服务器和发送平台心跳包
2、配置WAKEUP、USB、PWR_KEY，Vref，减少管脚状态带来的功耗异常情况
3、进入低功耗模式
]] --
function low_power_func()
    log.info("开始测试低功耗模式功耗。")
    -- 判断是否开启4G。
    if mobile_mode then
        -- 关闭这些GPIO可以让功耗效果更好。
        GPIO_setup()
        -- 进入低功耗 MODE 1 模式
        pm.power(pm.WORK_MODE, 1)
        -- 判断是否连接TCP平台
        if tcp_mode then
            -- 导入tcp客户端收发功能模块，运行tcp客户端连接，自动处理TCP收发消息。
            require "tcp_client_main"
            -- 调用发送心跳信息功能函数。
            send_tcp_heartbeat_func()
        end
    else
        -- 关闭这些GPIO可以让功耗效果更好。
        GPIO_setup()
        -- 如果不开启4G，则进入飞行模式再进入低功耗模式，保持环境干净。
        mobile.flymode(0, true)
        pm.power(pm.WORK_MODE, 1)
    end
end

-- 定义一个发送心跳信息功能函数。
function send_tcp_heartbeat_func()
    -- 通过驻网状态判断4G是否连接成功，不成功则等待成功连接后再开始发送信息。
    while not socket.adapter(socket.dft()) do
        -- 在此处阻塞等待4G连接成功的消息"IP_READY"，避免联网过快，丢失了"IP_READY"信息而导致一直被卡住。
        -- 或者等待30秒超时退出阻塞等待状态
        log.warn("tcp_client_main_task_func", "wait IP_READY")
        local mobile_result = sys.waitUntil("IP_READY", 30000)
        if mobile_result then
            log.info("4G已经连接成功。")
        else
            log.info("SIM卡异常,当前状态：", mobile.status(), "。请检查SIM卡!")
            -- 30S后网络还没连接成功，开关一下飞行模式，让SIM卡软重启，重新尝试驻网。
            mobile.flymode(0, true)
            mobile.flymode(0, false)
        end
    end
    -- 4G驻网后会与基站发送保活心跳。
    log.info("4G已经连接,开始与基站发送保活心跳")
    -- 起一个循环定时器，根据预设时间循环定时发送一次消息到TCP服务器。
    while true do
        sys.publish("SEND_DATA_REQ", "timer", heart_data)
        sys.wait(tcp_heartbeat * 60 * 1000)
    end
end

sys.taskInit(low_power_func)
