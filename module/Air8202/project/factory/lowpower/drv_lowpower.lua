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

-- 震动唤醒源引脚：取自板级 profile（各型号不同，硬件确认）
--   8202  = gpio.WAKEUP2  /  8201G = GPIO20  /  8201H = gpio.WAKEUP0
-- 与 SIM0 在位检测脚（8202 = WAKEUP0 / 8201G = WAKEUP2 / 8201H = WAKEUP2）分属不同引脚，无冲突。
local config = require("config")
local BP = config.BOARD or {}
local GS_INT_PIN = BP.gsensor and BP.gsensor.int_pin

-- 可作为低功耗唤醒源的引脚集合：仅 WAKEUP0~5 / PWR_KEY / CHG_DET 具备唤醒能力，
-- 普通 GPIO（如 8201G 的 GPIO20）不具备掉电/深睡唤醒能力 → 该板无法用震动唤醒，需降级处理。
local WAKEUP_CAPABLE = {
    [gpio.PWR_KEY] = true, [gpio.CHG_DET] = true,
    [gpio.WAKEUP0] = true, [gpio.WAKEUP1] = true, [gpio.WAKEUP2] = true,
    [gpio.WAKEUP3] = true, [gpio.WAKEUP4] = true, [gpio.WAKEUP5] = true,
}
local GS_WAKE_CAPABLE = (GS_INT_PIN ~= nil and WAKEUP_CAPABLE[GS_INT_PIN] == true)

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

    -- 震动中断脚唤醒：需要及时标记“运动中”，并通知业务侧触发定位/上报
    if id == GS_INT_PIN then
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

    -- 配置震动中断脚为低功耗唤醒源（引脚取自 board.profile.gsensor.int_pin）
    if not GS_INT_PIN then
        log.warn("drv_lowpower", "板级未配置震动中断脚，跳过震动唤醒源注册")
    elseif not GS_WAKE_CAPABLE then
        log.warn("drv_lowpower", "震动中断脚", GS_INT_PIN,
            "不是可唤醒引脚(仅 WAKEUP0~5/PWR_KEY/CHG_DET 可唤醒)，本板低功耗下无法用震动唤醒")
    else
        gpio.debounce(GS_INT_PIN, 100)
        gpio.setup(GS_INT_PIN, lowpower_wakeup_func, gpio.PULLUP, gpio.FALLING)
        log.info("drv_lowpower", "震动唤醒源已注册: pin=", GS_INT_PIN)
    end
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

    -- 功耗档切换记录（已降级 debug：排障需要时调回 log.info 即可对齐时间线）
    log.debug("drv_lowpower", "切功耗档 pm.WORK_MODE = 1（低功耗）")
    pm.power(pm.WORK_MODE, 1)

    -- 低功耗配置会**替换/复位该脚的中断注册** → 唤醒后必须重登记。
    -- 同时一并重拉板级 I2C 支撑脚（外部上拉源 / 器件供电）：属幂等保险，
    -- 不依赖"低功耗会丢输出电平"这一未证实的假设（AGPIO 按官方说明可在低功耗保持电平）。
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
