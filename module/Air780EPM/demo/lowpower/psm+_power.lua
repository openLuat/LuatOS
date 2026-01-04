--[[
@module  psm+_power
@summary psm+超低功耗模式主应用功能模块 
@version 1.0
@date    2025.07.17
@author  陈取德
@usage
本文件为psm+超低功耗模式主应用功能模块，核心业务逻辑为：
1、进入低功耗模式
2、判断是否连接TCP服务器和发送平台心跳包
使用前请根据需要，变更功能变量。条件不同，功耗体现不同。
本文件没有对外接口，直接在main.lua中require "psm+_power"就可以加载运行；
]] --
-----是否需要保持服务器心跳------------------------------------------------------
local tcp_mode = false -- true 需要连接TCP服务器，设置下方心跳包。    --false 不需要连接TCP服务器，不需要设置心跳包。
local tcp_heartbeat = 5 -- 常规模式和低功耗模式心跳包，单位（分钟），输入 1 为 一分钟一次心跳包。
local heart_data = string.rep("1234567890", 3) -- 心跳包数据内容，可自定义。
-------------------------------------------------------------------------------

-- GPIO唤醒函数，用于配置WAKEUP管脚使用
local function gpio_wakeup()
    log.info("gpio_wakeup")
end

--[[
本函数为GPIO配置函数，核心业务逻辑为：
1、关闭Vref管脚，默认拉高，会影响功耗展示，关闭后有效降低功耗。
2、将所有WAEKUP管脚设置为输入模式内部拉低可以有效防止管脚漏电发生。
3、配置三种模块唤醒方式：
    1）WAKEUP管脚：配置为中断拉低触发唤醒，可用于外部触发唤醒模块；
    2）dtimerStart：配置休眠定时器，根据预设时间唤醒模块；
    3）UART1：配置为9600波特率，可用于通过串口发送指令唤醒模块；
本函数属于饱和式管脚配置，调用后可以防止下列管脚的状态异常，导致功耗异常增高，也可以不调用，根据实际情况选择；
]] --
function GPIO_setup()
    local lowpower_module = hmeta.model()
    -- 判断使用的模组型号，如果为Air8000A/AB/N/U/W，则不允许控制GPIO22和GPIO23
    -- 在含WIFI功能的Air8000系列模组中，GPIO23为WIFI芯片的供电使能脚，GPIO22为WIFI芯片的通讯脚，不允许控制
    if lowpower_module ~= "Air8000A" and lowpower_module ~= "Air8000AB" and lowpower_module ~= "Air8000N" and
        lowpower_module ~= "Air8000U" and lowpower_module ~= "Air8000W" then

        -- 在不含WIFI的Air8000系列，Air780系列，Air700系列模组中GPIO23是Vref参考电压管脚，固件默认拉高，会影响功耗展示，关闭可有效降低功耗。
        -- Air780EGH/EGG/EGP中，Vref为定位芯片备电使用，在含Gsensor的型号中作为Gsensor的供电使能，关闭后会影响功能使用，需根据实际情况选择是否关闭
        gpio.setup(23, nil, gpio.PULLDOWN)

        -- gpio.WAKEUP5 = GPIO 22，不需要使用时主动将其关闭可避免漏电风险
        -- 如测试模块型号为Air780EHV时，需注意如调用了exaudio库，该管脚为外部PA控制脚，不要配置，否则会导致外部PA无法正常工作
        gpio.setup(gpio.WAKEUP5, nil, gpio.PULLDOWN)
        -- 可在进入低功耗模式时保持管脚状态，也可以配置为中断拉低触发唤醒,选择对应配置代码即可
        -- gpio.setup(gpio.WAKEUP5, gpio_wakeup, gpio.PULLUP, gpio.FALLING)
        log.info("模组非8000含WIFI", lowpower_module)
    end
    -- WAKEUP0专用管脚，无复用，不需要使用时主动将其关闭可避免漏电风险
    gpio.setup(gpio.WAKEUP0, nil, gpio.PULLDOWN)
    -- 可在进入低功耗模式时保持管脚状态，也可以配置为中断拉低触发唤醒,选择对应配置代码即可
    -- gpio.setup(gpio.WAKEUP0, gpio_wakeup, gpio.PULLUP, gpio.FALLING)

    -- gpio.WAKEUP1 = VBUS，检测USB插入使用，关闭则无法检测是否插入USB，不需要使用时主动将其关闭可避免漏电风险
    gpio.setup(gpio.WAKEUP1, nil, gpio.PULLDOWN)
    -- 可在进入低功耗模式时保持管脚状态，也可以配置为中断拉低触发唤醒,选择对应配置代码即可
    -- gpio.setup(gpio.WAKEUP1, gpio_wakeup, gpio.PULLUP, gpio.FALLING)

    -- gpio.WAKEUP2 = SIM卡的DET检测脚，用于检测是否插卡，关闭则无法检测是否插卡，不需要使用时主动将其关闭可避免漏电风险
    gpio.setup(gpio.WAKEUP2, nil, gpio.PULLDOWN)
    -- 可在进入低功耗模式时保持管脚状态，也可以配置为中断拉低触发唤醒,选择对应配置代码即可
    -- gpio.setup(gpio.WAKEUP2, gpio_wakeup, gpio.PULLUP, gpio.FALLING)

    -- gpio.WAKEUP3 = GPIO 20，不需要使用时主动将其关闭可避免漏电风险
    -- 如测试模块型号为Air780EHV时，需注意该管脚内部用于控制Audio Codec芯片ES8311的开关，不要配置，否则会导致Audio Codec芯片ES8311无法正常工作
    gpio.setup(gpio.WAKEUP3, nil, gpio.PULLDOWN)
    -- 可在进入低功耗模式时保持管脚状态，也可以配置为中断拉低触发唤醒,选择对应配置代码即可
    -- gpio.setup(gpio.WAKEUP3, gpio_wakeup, gpio.PULLUP, gpio.FALLING)

    -- gpio.WAKEUP4 = GPIO 21，不需要使用时主动将其关闭可避免漏电风险
    -- 如测试模块型号为Air780EGP/EGG/EGH时，需注意该管脚内部用于控制GNSS定位芯片的开关使能，不要配置，否则会导致GNSS定位芯片无法正常工作
    gpio.setup(gpio.WAKEUP4, nil, gpio.PULLDOWN)
    -- 可在进入低功耗模式时保持管脚状态，也可以配置为中断拉低触发唤醒,选择对应配置代码即可
    -- gpio.setup(gpio.WAKEUP4, gpio_wakeup, gpio.PULLUP, gpio.FALLING)

    -- 如果硬件上PWR_KEY接地自动开机，可能会有漏电流风险，配置关闭可避免功耗异常，没接地可以不关
    gpio.setup(gpio.PWR_KEY, nil, gpio.PULLDOWN)
    -- 可在进入低功耗模式时保持管脚状态，也可以配置为中断拉低触发唤醒,选择对应配置代码即可
    -- gpio.setup(gpio.PWR_KEY, gpio_wakeup, gpio.PULLUP, gpio.FALLING)

    -- 配置UART1为9600波特率，可用于唤醒PSM+模式下的模块；
    -- uart.setup(1,9600)

    -- 配置dtimerStart唤醒定时器，根据预设时间唤醒模块；
    -- pm.dtimerStart(0, tcp_heartbeat * 60 * 1000)

    -- 从2025年3月份开始的固件版本在pm.power(pm.WORK_MODE, 3)中会自动控制USB和飞行模式，脚本里不需要再手动控制
    -- pm.power(pm.USB, false)
    -- mobile.flymode(0, true)
end

--[[
本函数为psm+超低功耗模式主应用功能函数，核心业务逻辑为：
1、判断是否连接TCP服务器和发送平台心跳包
2、配置WAKEUP、USB、PWR_KEY，Vref，减少管脚状态带来的功耗异常情况
3、进入低功耗模式
]] --
function psm_power_func()
    log.info("开始测试PSM+模式功耗。")
    -- 判断是否连接TCP平台。
    if tcp_mode then
        -- 导入短连接tcp客户端收发功能模块，运行tcp客户端连接，自动处理TCP收发消息。
        require "tcp_short"
        -- 向指定taskName任务发送一个消息，可以解除指定taskName种的sys.waitMsg的阻塞状态。
        sys.sendMsg("tcp_short", "data", heart_data)
        -- 等待短连接TCP功能模块任务完成，获取"tcp_short_result"信息中的发送状态和接收信息
        local result, send_result, rec_data = sys.waitUntil("tcp_short_result")
        log.info("信息发送结果：", send_result, "接收到的信息：", rec_data)
        -- 判断完有没有发送成功后都进入PSM+模式，减少功耗损耗。
        -- 配置dtimerStart唤醒定时器，根据预设时间唤醒模块上传心跳信息。2
        pm.dtimerStart(0, tcp_heartbeat * 60 * 1000)
    end
    GPIO_setup()
    -- V2018及以前的版本固件因PSM+模式处理飞行模式逻辑修改，需要增加等待，确保飞行模式执行完成，不然会死机被底层看门狗重启
    -- V2019及以后的版本固件不需要增加等待
    sys.wait(500)
    -- 执行到这条代码后，CPU关机，后续代码不会执行。
    pm.power(pm.WORK_MODE, 3)
    -- 下面几行代码实现的功能是：延时等待80秒，然后软件重启；
    --
    -- 为什么要写下面三行代码，分以下两种情况介绍：
    -- 1、当上面执行pm.power(pm.WORK_MODE, 3)时，如果立即成功进入到PSM+模式，则没有机会执行此处的三行代码
    -- 2、当上面执行pm.power(pm.WORK_MODE, 3)时，如果没有立即成功进入到PSM+模式，则会接着执行此处的三行代码
    --    在此处最多等待80秒，80秒内，如果成功进入了PSM+模式，则没有机会运行此处的rtos.reboot()软件重启代码
    --    如果超过了80秒，都没有成功进入PSM+模式，则此处会控制软件重启，
    --    重启后，根据本demo项目写的业务逻辑，会再次执行进入PSM+模式的逻辑
    --
    -- 此处为什么延时等待80秒，是因为从2025年3月份开始，对外发布的内核固件，在脚本中执行pm.power(pm.WORK_MODE, 3)时，
    -- 如果满足进入PSM+模式的条件，理论上会立即成功进入PSM+模式，
    -- 虽然如此，为了防止出现不可预知的错误，所以在内核固件中多加了一层保护机制，最长等待75秒钟一定会成功进入PSM+模式
    -- 所以在此处延时等待80秒，比75秒稍微长个5秒钟，为了让内核固件的这一层保护机制有时间运行，而不必执行此处的软件重启脚本代码
    -- 减少不必要的重启规避逻辑而带来的多余功耗
    --
    -- 这个是设置允许进入PSM+模式的标准操作，必须要与demo保持一致，加入这三行代码
    sys.wait(80000)
    log.info("psm_app_task", "进入PSM+失败，重启")
    rtos.reboot()
end

sys.taskInit(psm_power_func)
