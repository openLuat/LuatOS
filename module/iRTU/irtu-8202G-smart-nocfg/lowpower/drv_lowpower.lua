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

    -- WAKEUP2 为震动唤醒：需要及时标记“运动中”，并通知业务侧触发定位/上报
    if id == gpio.WAKEUP2 then
        log.info("drv_lowpower", "震动唤醒，标记运动中 + 发布 MOTION_EVENT")
        -- 通过 pcall 按需加载 gsensor，避免该文件被多次 require 或不存在时影响唤醒流程
        local ok, gsensor = pcall(require, "gsensor")
        if ok and gsensor and gsensor.set_motion_state then
            -- 延长运动有效期到60秒：低功耗唤醒后网络恢复通常>10秒，
            -- 若仍用默认10秒，is_moving 会在等网络期间超时变 false，导致震动上报走基站而非GPS
            gsensor.set_motion_state(true, 60)
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

    -- 配置WAKEUP2引脚中断唤醒（加速度传感器震动/计步中断唤醒）
    gpio.debounce(gpio.WAKEUP2, 100)
    gpio.setup(gpio.WAKEUP2, lowpower_wakeup_func, gpio.PULLUP, gpio.FALLING)
end

-- 配置低功耗模式下的功能项
local function set_lowpower_func_item()
    log.info("drv_lowpower", "配置低功耗模式功能项") 

    -- 关闭GPS定位，降低功耗
    local location = require("location")
    if location and location.close then
        location.close()
    end
end

local function lowpower_task()
    log.info("drv_lowpower", "进入低功耗模式任务")

    set_lowpower_interrupt_wakeup()
    set_lowpower_func_item()

    pm.power(pm.WORK_MODE, 1)

    -- wakeup 后恢复 gsensor 中断（WAKEUP2 的 wakeup handler 替换了 gsensor 原始中断）
    local gsensor = require("gsensor")
    if gsensor and gsensor._restore_interrupt then
        gsensor._restore_interrupt()
    end

    log.info("drv_lowpower", "低功耗模式配置完成")
end

local function set_drv_lowpower()
    sys.taskInit(lowpower_task)
end

sys.subscribe("DRV_SET_LOWPOWER", set_drv_lowpower)
