local server_ip = "112.125.89.8" 
local server_port = 46153 -- 换成自己的
-- local period = 3 * 60 * 60 * 1000 -- 3小时唤醒一次
local period = 30000
-- 配置GPIO达到最低功耗
-- gpio.setup(24, 0) -- 关闭三轴电源

local reason, slp_state = pm.lastReson() -- 获取唤醒原因
log.info("wakeup state", pm.lastReson())
local libnet = require "libnet"

local d1Name = "D1_TASK"
local function netCB(msg)
    log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end



function GPIO_setup()
    -- mobile.flymode(0, true)
    -- sys.wait(100)
    -- mobile.flymode(0, false)
    gpio.close(24)
    gpio.setup(gpio.WAKEUP0, nil, gpio.PULLDOWN)
    gpio.setup(gpio.WAKEUP1, nil, gpio.PULLDOWN)
    gpio.setup(gpio.WAKEUP2, nil, gpio.PULLDOWN)
    gpio.setup(gpio.WAKEUP3, nil, gpio.PULLDOWN)
    gpio.setup(gpio.WAKEUP4, nil, gpio.PULLDOWN)
    gpio.setup(gpio.WAKEUP6, nil, gpio.PULLDOWN)


    -- gpio.debounce(gpio.PWR_KEY, 200)
    -- gpio.setup(gpio.PWR_KEY, psm_wakeup_func2, gpio.PULLDOWN, gpio.RISING)
    -- -- 如果硬件上PWR_KEY接地自动开机，关闭PWR_KEY可以有效降低功耗，如果没接地可以不关。
    -- gpio.close(gpio.PWR_KEY)
    -- 关闭USB以后可以降低约150ua左右的功耗，如果不需要USB可以关闭
    -- pm.power(pm.USB, false)
    -- GPIO 22 23为WIFi的供电和通讯脚,不能关闭
    gpio.close(23)

    if pm.WIFI then pm.power(pm.WIFI, 0) end
    -- gpio.setup(22, nil, gpio.PULLDOWN)
end

local function testTask(ip, port)

    log.info("开始测试低功耗模式")
    -- sys.wait(2000)
    -- 关闭这些GPIO可以让功耗效果更好。
    GPIO_setup()

    -- mobile.flymode(0, true) -- 启动飞行模式，规避可能会出现的网络问题
    pm.power(pm.WORK_MODE, 3) -- 进入极致功耗模式

    sys.wait(15000) -- demo演示唤醒时间是三十分钟，如果15s后模块重启，则说明进入极致功耗模式失败，
    log.info("进入极致功耗模式失败，尝试重启")
    rtos.reboot()
end
sysplus.taskInitEx(testTask, d1Name, netCB, server_ip, server_port)
