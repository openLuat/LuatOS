local expm = require "expm"

-- expm.set(expm.PSM, 
--              {
--                  [expm.FLYMODE] = expm.OPEN,                     -- 打开飞行模式
--                  [expm.PSM_WAKEUP_RESET_FLYMODE] = expm.CLOSE,   -- 从PSM+模式唤醒重启后，关闭飞行模式
--                  [expm.OTHER_RESET_FLYMODE] = expm.OPEN,         -- 其他原因重启或者开机，打开飞行模式
--                  [expm.USB] = expm.OPEN,                         -- 打开USB，临时调试需要，有时间通过USB端口观察日志，调试OK后，注释掉此行配置
--              })


local function psm_wakeup_func(level, id)
    local tag =
    {
        [gpio.PWR_KEY] = "PWR_KEY",
        [gpio.CHG_DET] = "CHG_DET",
        [gpio.WAKEUP0] = "WAKEUP0",
        [gpio.WAKEUP1] = "WAKEUP1",
        [gpio.WAKEUP2] = "WAKEUP2",
        [gpio.WAKEUP3] = "WAKEUP3",
        [gpio.WAKEUP4] = "WAKEUP4",
        [gpio.WAKEUP5] = "WAKEUP5",

    }

    -- 注意：此处的level电平并不表示触发中断的边沿电平
    -- 而是在触发中断后，某个时间点的电平状态
    -- 可能和触发中断的边沿电平状态一致，也可能不一致
    log.info("psm_wakeup_func", tag[id], level)
end


local function psm_task()
    log.info("psm_task enter")

    -- 配置深度休眠定时器唤醒
    -- 定时器时长有讲究，此处的时长最好不要小于80秒
    -- 因为如果满足进入PSM+模式的条件，内核固件最长需要75秒肯定可以进入PSM+模式
    -- 如果此处设置的时间过短，在某些情况下，有可能还没有真正进入PSM+模式，就出现了深度休眠定时器超时
    -- 例如，如果此处配置了10秒的时长，接下来的代码，很快调用了expm.set(expm.PSM, opts)
    -- 此时如果网络还没有彻底关闭，其他任务还没有停止，外设数据传输还在进行，则expm.set(expm.PSM, opts)中会执行某些关闭动作或者等待其他任务停止，最长等待75秒
    -- 则有可能过了11秒，此时还没有进入PSM+模式，但是这个定时器就超时了的情况
    -- pm.dtimerStart(0, 120*1000)

    -- 以下引脚唤醒，单上升沿、单下降沿、双边沿中断类型都需要测试一下

    -- 配置PWR_KEY引脚中断唤醒
    -- 1、中断触发模式有：下降沿、上升沿、双边沿三种
    -- 2、防抖配置：200ms时长防抖，冷却模式
    -- 此处的代码基于合宙核心板或者合宙开发板上的开机键测试，按下产生下降沿，弹起产生下降沿
    -- 在客户实际的项目中，可以根据自己的硬件设计原理以及项目需求，对此处的代码做适当修改
    -- gpio.debounce(gpio.PWR_KEY, 200)
    -- gpio.setup(gpio.PWR_KEY, psm_wakeup_func, gpio.PULLUP, gpio.FALLING)
    -- gpio.setup(gpio.PWR_KEY, psm_wakeup_func, gpio.PULLUP, gpio.RISING)
    -- gpio.setup(gpio.PWR_KEY, psm_wakeup_func, gpio.PULLUP, gpio.BOTH)

    -- 配置chgdet（别名WAKEUP6）引脚拉低唤醒
    -- gpio.debounce(gpio.CHG_DET, 200)
    -- gpio.setup(gpio.CHG_DET, psm_wakeup_func, gpio.PULLUP, gpio.FALLING)
    -- gpio.setup(gpio.CHG_DET, psm_wakeup_func, gpio.PULLUP, gpio.RISING)
    -- gpio.setup(gpio.CHG_DET, psm_wakeup_func, gpio.PULLUP, gpio.BOTH)

    -- 配置WAKEUP0下降沿、上升沿、双边沿中断唤醒（根据项目需求三选一）
    -- 防抖配置，目前是1000ms防抖（因为在核心板上使用杜邦线插拔测试，电平状态跳变频繁，所以防抖时间设置的较长，实际项目中根据自己的硬件设计和项目需求修改），冷却模式（根据项目需求可以修改）
    -- 直接使用合宙核心板或者合宙开发板上的开机键就可以测试，按下产生下降沿，弹起产生下降沿
    -- 配置PWR_KEY引脚中断唤醒
    -- 1、中断触发模式有：下降沿、上升沿、双边沿三种
    -- 2、防抖配置：200ms时长防抖，冷却模式
    -- 此处的代码基于合宙核心板或者合宙开发板上的开机键测试，按下产生下降沿，弹起产生下降沿
    -- 在客户实际的项目中，可以根据自己的硬件设计原理以及项目需求，对此处的代码做适当修改
    -- gpio.debounce(gpio.WAKEUP0, 200)
    -- gpio.setup(gpio.WAKEUP0, psm_wakeup_func, gpio.PULLUP, gpio.FALLING)
    -- gpio.setup(gpio.WAKEUP0, psm_wakeup_func, gpio.PULLUP, gpio.RISING)
    -- gpio.setup(gpio.WAKEUP0, psm_wakeup_func, gpio.PULLUP, gpio.BOTH)

    -- 配置WAKEUP1引脚拉低唤醒
    -- gpio.debounce(gpio.WAKEUP1, 200)
    -- gpio.setup(gpio.WAKEUP1, psm_wakeup_func, gpio.PULLUP, gpio.FALLING)
    -- gpio.setup(gpio.WAKEUP1, psm_wakeup_func, gpio.PULLUP, gpio.RISING)
    -- gpio.setup(gpio.WAKEUP1, psm_wakeup_func, gpio.PULLUP, gpio.BOTH)

    -- 配置WAKEUP2引脚拉低唤醒
    -- gpio.debounce(gpio.WAKEUP2, 200)
    -- gpio.setup(gpio.WAKEUP2, psm_wakeup_func, gpio.PULLUP, gpio.FALLING)
    -- gpio.setup(gpio.WAKEUP2, psm_wakeup_func, gpio.PULLUP, gpio.RISING)
    -- gpio.setup(gpio.WAKEUP2, psm_wakeup_func, gpio.PULLUP, gpio.BOTH)

    -- 配置WAKEUP3引脚拉低唤醒
    -- gpio.debounce(gpio.WAKEUP3, 200)
    -- gpio.setup(gpio.WAKEUP3, psm_wakeup_func, gpio.PULLUP, gpio.FALLING)
    -- gpio.setup(gpio.WAKEUP3, psm_wakeup_func, gpio.PULLUP, gpio.RISING)
    -- gpio.setup(gpio.WAKEUP3, psm_wakeup_func, gpio.PULLUP, gpio.BOTH)

    -- 配置WAKEUP4引脚拉低唤醒
    -- gpio.debounce(gpio.WAKEUP4, 200)
    -- gpio.setup(gpio.WAKEUP4, psm_wakeup_func, gpio.PULLUP, gpio.FALLING)
    -- gpio.setup(gpio.WAKEUP4, psm_wakeup_func, gpio.PULLUP, gpio.RISING)
    -- gpio.setup(gpio.WAKEUP4, psm_wakeup_func, gpio.PULLUP, gpio.BOTH)

    -- 配置WAKEUP5引脚拉低唤醒
    -- gpio.debounce(gpio.WAKEUP5, 200)
    -- gpio.setup(gpio.WAKEUP5, psm_wakeup_func, gpio.PULLUP, gpio.FALLING)
    -- gpio.setup(gpio.WAKEUP5, psm_wakeup_func, gpio.PULLUP, gpio.RISING)
    -- gpio.setup(gpio.WAKEUP5, psm_wakeup_func, gpio.PULLUP, gpio.BOTH)

    -- 配置9600波特率的uart1 rx唤醒


    -- expm.set(expm.PSM)
    expm.set(expm.PSM, 
             {
                --  [expm.USB] = expm.NIL,                          -- 打开USB，临时调试需要，有时间通过USB端口观察日志，调试OK后，注释掉此行配置
                 [expm.WAKEUP0] = expm.NIL,                          -- 打开USB，临时调试需要，有时间通过USB端口观察日志，调试OK后，注释掉此行配置
                 [expm.WAKEUP1] = expm.NIL,                          -- 打开USB，临时调试需要，有时间通过USB端口观察日志，调试OK后，注释掉此行配置
                 [expm.WAKEUP2] = expm.NIL,                          -- 打开USB，临时调试需要，有时间通过USB端口观察日志，调试OK后，注释掉此行配置
                 [expm.WAKEUP3] = expm.NIL,                          -- 打开USB，临时调试需要，有时间通过USB端口观察日志，调试OK后，注释掉此行配置
                 [expm.WAKEUP4] = expm.NIL,                          -- 打开USB，临时调试需要，有时间通过USB端口观察日志，调试OK后，注释掉此行配置
                 [expm.WAKEUP5] = expm.NIL,                          -- 打开USB，临时调试需要，有时间通过USB端口观察日志，调试OK后，注释掉此行配置
                 [expm.GPIO23] = expm.NIL,
             })
end

local function set_expm_psm()
    sys.taskInit(psm_task)
end

sys.subscribe("PM_SET_PSM", set_expm_psm)

-- 下面的一行代码，是临时测试需要
-- 实际项目中，注释掉下面的一行代码，根据自己的项目业务逻辑，在合适的位置执行sys.publish("PM_SET_PSM")即可
sys.publish("PM_SET_PSM")