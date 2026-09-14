--[[
@module lowpower
@summary 低功耗管理模块（MQTT 版本）
@version 3.0
@date    2026.05.21
@usage
Air8201 项目低功耗管理模块。
实现高层功耗模式管理和底层驱动调用。
]]

local lowpower = {}
local config = require("config")

-- 引入驱动层代码
require("drv_normal")
require("drv_lowpower")
require("drv_psm")

-- 功耗状态
local power_state = {
    mode = config.POWER_MODE.NORMAL
}

-- 初始化
function lowpower.init()
    log.info("lowpower", "低功耗管理模块初始化")
    sys.subscribe("BATTERY_LOW", lowpower.handle_low_battery)
    log.info("lowpower", "低功耗管理模块初始化完成")
end

-- 低电量处理
-- 已激活模式（PERFORMANCE/SMART）默认已在 POWER_SAVE 低功耗运行
-- GPS定位模式(FIND)保持全功率，低电量时降级到 POWER_SAVE
-- 未激活模式(UNACTIVATED)低电量时进 PSM 深度休眠
function lowpower.handle_low_battery(level)
    log.info("lowpower", "低电量:", level, "%")
    local kvstore = require("kvstore")
    local work_mode = kvstore.get_work_mode()

    if work_mode == config.DEVICE_MODE.UNACTIVATED then
        if level < config.ALARM_THRESHOLD.BATTERY_CRITICAL then
            lowpower.set_mode(config.POWER_MODE.PSM_SLEEP)
        else
            lowpower.set_mode(config.POWER_MODE.POWER_SAVE)
        end
    elseif work_mode == config.DEVICE_MODE.FIND then
        if level < config.ALARM_THRESHOLD.BATTERY_LOW then
            log.info("lowpower", "GPS定位模式低电量，降级到 POWER_SAVE")
            lowpower.set_mode(config.POWER_MODE.POWER_SAVE)
        end
    else
        -- PERFORMANCE/SMART 默认已在 POWER_SAVE，无需额外操作
        log.info("lowpower", "常规/智能模式，保持 POWER_SAVE")
    end
end

-- 设置功耗模式
function lowpower.set_mode(mode)
    local valid_mode = false
    for _, v in pairs(config.POWER_MODE) do
        if v == mode then
            valid_mode = true
            break
        end
    end

    if valid_mode then
        power_state.mode = mode
        log.info("lowpower", "功耗模式切换:", mode)

        if mode == config.POWER_MODE.NORMAL then
            sys.publish("DRV_SET_NORMAL")
        elseif mode == config.POWER_MODE.POWER_SAVE then
            sys.publish("DRV_SET_LOWPOWER")
        elseif mode == config.POWER_MODE.PSM_SLEEP then
            sys.publish("DRV_SET_PSM")
        end
        return true
    end

    log.error("lowpower", "无效的功耗模式:", mode)
    return false
end

-- 根据设备模式设置功耗
function lowpower.set_mode_by_device_mode(device_mode)
    log.info("lowpower", "根据设备模式设置功耗:", device_mode)

    local power_mode = config.POWER_MODE.NORMAL
    if device_mode == config.DEVICE_MODE.PERFORMANCE then
        power_mode = config.POWER_MODE.POWER_SAVE
    elseif device_mode == config.DEVICE_MODE.SMART then
        power_mode = config.POWER_MODE.POWER_SAVE
    elseif device_mode == config.DEVICE_MODE.FIND then
        power_mode = config.POWER_MODE.NORMAL
    elseif device_mode == config.DEVICE_MODE.UNACTIVATED then
        power_mode = config.POWER_MODE.PSM_SLEEP
    end

    return lowpower.set_mode(power_mode)
end

return lowpower
