--[[
@module  drv_psm
@summary PSM+模式pm.power(pm.WORK_MODE, 3)驱动配置功能模块
@version 1.0
@date    2026.03.17
@author  孟伟
@usage
本文件为PSM+模式pm.power(pm.WORK_MODE, 3)驱动配置功能模块，提供了PSM+模式的配置模板，包括以下几点：
1、在进入PSM+模式前，根据自己的实际项目需求，配置进入PSM+模式后的中断唤醒方式；详情参考set_psm_interrupt_wakeup()实现
2、在进入PSM+模式前，根据自己的实际项目需求，配置一些必要的功能项；可以在满足项目功能需求的背景下，让功耗降到最低；详情参考set_psm_func_item()实现
3、配置最低功耗模式为PSM+模式；pm.power(pm.WORK_MODE, 3)

本文件的对外接口只有1个：
1、sys.subscribe("DRV_SET_PSM", set_drv_psm)：订阅"DRV_SET_PSM"消息；
   其他应用模块如果需要配置PSM+模式，直接sys.publish("DRV_SET_PSM")这个消息即可；
]]

-- 获取当前使用的模组型号
local module = hmeta.model()

log.info("drv_psm", "当前使用的模组是：", module)


-- 在PSM+模式下，唤醒后会直接重启软件系统，并不会执行此处的中断处理函数
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
    log.info("drv_psm", "PSM模式中断唤醒", tag[id], level)
end


-- 在进入PSM+模式前，根据自己的实际项目需求，配置PSM+模式下的中断唤醒方式
local function set_psm_interrupt_wakeup()
    -- 配置深度休眠定时器唤醒
    -- 定时器时长有讲究，此处的时长不要小于80秒
    -- pm.dtimerStart(0, 60*60*1000)


    -- 配置WAKEUP0引脚中断唤醒
    -- gpio.debounce(gpio.WAKEUP0, 1000)
    -- gpio.setup(gpio.WAKEUP0, psm_wakeup_func, gpio.PULLUP, gpio.FALLING)

    -- 配置VBUS(WAKEUP1)引脚中断唤醒
    -- gpio.debounce(gpio.WAKEUP1, 200)
    -- gpio.setup(gpio.WAKEUP1, psm_wakeup_func, gpio.PULLUP, gpio.FALLING)
end


-- 在进入PSM+模式前，根据自己的实际项目需求，配置一些必要的功能项
local function set_psm_func_item()
    -- 关闭定位功能
    -- location.stop()

    -- 关闭传感器
    -- sensor.stop()

    -- 关闭蓝牙
    -- ble_bind.stop()

    -- 进入飞行模式
    -- mobile.flymode(0, true)
end


local function psm_task()
    log.info("drv_psm", "进入PSM+模式任务")

    -- 配置中断唤醒方式
    set_psm_interrupt_wakeup()

    -- 配置功能项
    set_psm_func_item()

    -- 配置最低功耗模式为PSM+模式
    pm.power(pm.WORK_MODE, 3)
    
    log.info("drv_psm", "PSM+模式配置完成")
end


local function set_drv_psm()
    sys.taskInit(psm_task)
end


-- 订阅DRV_SET_PSM消息
sys.subscribe("DRV_SET_PSM", set_drv_psm)
