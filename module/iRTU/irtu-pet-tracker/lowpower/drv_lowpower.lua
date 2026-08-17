--[[
@module  drv_lowpower
@summary 低功耗模式pm.power(pm.WORK_MODE, 1)驱动配置功能模块
@version 1.0
@date    2026.03.17
@author  孟伟
@usage
本文件为 Air8201 项目低功耗模式pm.power(pm.WORK_MODE, 1)驱动配置功能模块。
Air8201 项目低功耗模式特点：
- 适用于常规模式（DEVICE_MODE.PERFORMANCE）和低电量模式
- 上报间隔较长（最低300秒），减少网络活动
- 传感器保持低功耗运行，主要用于运动检测和计步
- 定位主要依赖WiFi和LBS，GPS关闭以降低功耗
- 蓝牙保持广播模式，支持设备查找功能

对外接口：
sys.subscribe("DRV_SET_LOWPOWER", set_drv_lowpower)：订阅"DRV_SET_LOWPOWER"消息；
其他应用模块如果需要配置低功耗模式，直接sys.publish("DRV_SET_LOWPOWER")即可；
]]

-- 获取当前使用的模组型号
local module = hmeta.model()

log.info("drv_lowpower", "当前使用的模组是：", module)

-- 报警引脚中断处理函数
local function lowpower_wakeup_func(level, id)
    local tag = {
        [gpio.PWR_KEY] = "PWR_KEY",
        [gpio.CHG_DET] = "CHG_DET",
        [gpio.WAKEUP0] = "WAKEUP0",
        [gpio.WAKEUP1] = "WAKEUP1",
        [gpio.WAKEUP2] = "WAKEUP2",
        [gpio.WAKEUP3] = "WAKEUP3",
        [gpio.WAKEUP4] = "WAKEUP4",
        [gpio.WAKEUP5] = "WAKEUP5",
    }
    
    log.info("drv_lowpower", "中断唤醒", tag[id], level)

    -- WAKEUP3(GPIO20) = DA267 震动/计步中断唤醒
    -- 发布 MOTION_EVENT，主循环 waitUntil 收到后处理（冷却期由主循环判断）
    -- 标记 DA267 为运动中，使本次震动上报走 GPS 定位（运动中分支）
    -- 注意：标记运动中不影响叠加计数（方案B 的叠加与 is_moving 解耦，仅影响基础间隔值与定位方式）
    if id == gpio.WAKEUP3 then
        log.info("drv_lowpower", "震动唤醒，标记运动中 + 发布 MOTION_EVENT")
        local ok, da267 = pcall(require, "da267")
        if ok and da267 and da267.set_motion_state then
            da267.set_motion_state(true)
        end
        sys.publish("MOTION_EVENT")
    end
end

-- 配置低功耗模式下的中断唤醒方式
local function set_lowpower_interrupt_wakeup()
    if not gpio.PWR_KEY then
        log.warn("drv_lowpower", "gpio.PWR_KEY不可用，跳过唤醒配置")
        return
    end
    -- 配置PWR_KEY引脚下降沿中断唤醒（电源按键唤醒）
    gpio.debounce(gpio.PWR_KEY, 200)
    gpio.setup(gpio.PWR_KEY, lowpower_wakeup_func, gpio.PULLUP, gpio.FALLING)

    -- 配置WAKEUP3(GPIO20)引脚中断唤醒（DA267震动/计步中断唤醒）
    gpio.debounce(gpio.WAKEUP3, 100)
    gpio.setup(gpio.WAKEUP3, lowpower_wakeup_func, gpio.PULLUP, gpio.FALLING)
end

-- 配置低功耗模式下的功能项
local function set_lowpower_func_item()
    log.info("drv_lowpower", "配置低功耗模式功能项") 

    -- 关闭GPS定位，降低功耗
    local location = require("location")
    if location and location.close then
        location.close()
    end

    -- 关闭NS2520气压温度传感器
    local ns2520 = require("ns2520")
    if ns2520 and ns2520.close then
        ns2520.close()
    end

    -- 关闭音频功放电源（PA + DAC）
    gpio.setup(25, 0)
    gpio.setup(2, 0)
end

local function lowpower_task()
    log.info("drv_lowpower", "进入低功耗模式任务")

    set_lowpower_interrupt_wakeup()
    set_lowpower_func_item()

    pm.power(pm.WORK_MODE, 1)

    -- wakeup 后恢复 DA267 中断（WAKEUP3 的 wakeup handler 替换了 da267 原始中断）
    local da267 = require("da267")
    if da267 and da267._restore_interrupt then
        da267._restore_interrupt()
    end

    log.info("drv_lowpower", "低功耗模式配置完成")
end

local function set_drv_lowpower()
    sys.taskInit(lowpower_task)
end

sys.subscribe("DRV_SET_LOWPOWER", set_drv_lowpower)
