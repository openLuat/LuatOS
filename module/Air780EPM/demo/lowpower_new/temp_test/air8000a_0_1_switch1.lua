local function psm_wakeup_func1()
    log.info("psm_wakeup_func1 workmode0")
    pm.power(pm.WORK_MODE, 0)
end 

local function psm_wakeup_func2()
    log.info("psm_wakeup_func2 workmode1")
    pm.power(pm.WORK_MODE, 1)
    -- pm.power(pm.WORK_MODE, 1, 1)
end

function GPIO_setup()
    -- mobile.flymode(0, true)
    -- sys.wait(100)
    -- mobile.flymode(0, false)

    gpio.setup(24, 0)

    -- gpio.setup(gpio.WAKEUP0, nil, gpio.PULLDOWN)
    gpio.setup(gpio.WAKEUP1, nil, gpio.PULLDOWN)
    gpio.setup(gpio.WAKEUP2, nil, gpio.PULLDOWN)
    gpio.setup(gpio.WAKEUP3, nil, gpio.PULLDOWN)
    gpio.setup(gpio.WAKEUP4, nil, gpio.PULLDOWN)

    -- gpio.debounce(gpio.WAKEUP3, 200)
    -- gpio.setup(gpio.WAKEUP3, psm_wakeup_func1, gpio.PULLUP, gpio.FALLING)

    -- gpio.debounce(gpio.WAKEUP4, 200)
    -- gpio.setup(gpio.WAKEUP4, psm_wakeup_func2, gpio.PULLUP, gpio.FALLING)

    gpio.setup(gpio.WAKEUP6, nil, gpio.PULLDOWN)


    -- 配置PWR_KEY引脚中断唤醒
    -- 1、中断触发模式有：下降沿、上升沿、双边沿三种
    -- 2、防抖配置：200ms时长防抖，冷却模式
    -- 此处的代码基于合宙核心板或者合宙开发板上的开机键测试，按下产生下降沿，弹起产生下降沿
    -- 在客户实际的项目中，可以根据自己的硬件设计原理以及项目需求，对此处的代码做适当修改
    gpio.debounce(gpio.PWR_KEY, 200)
    gpio.setup(gpio.PWR_KEY, psm_wakeup_func2, gpio.PULLUP, gpio.FALLING)


    gpio.debounce(gpio.WAKEUP0, 200)
    gpio.setup(gpio.WAKEUP0, psm_wakeup_func1, gpio.PULLUP, gpio.FALLING)


    -- -- 如果硬件上PWR_KEY接地自动开机，关闭PWR_KEY可以有效降低功耗，如果没接地可以不关。
    -- gpio.close(gpio.PWR_KEY)
    -- 关闭USB以后可以降低约150ua左右的功耗，如果不需要USB可以关闭
    -- pm.power(pm.USB, false)
    -- GPIO 22 23为WIFi的供电和通讯脚,不能关闭
    -- gpio.close(23)
    -- gpio.setup(22, nil, gpio.PULLDOWN)
end

function socketDemo()
    log.info("开始测试低功耗模式")
    -- sys.wait(2000)
    -- 关闭这些GPIO可以让功耗效果更好。
    GPIO_setup()
    -- 进入低功耗 MODE 1 模式
    pm.power(pm.WORK_MODE, 1)
end

sys.taskInit(socketDemo)