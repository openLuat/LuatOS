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
    sys.subscribe("BATTERY_EMPTY", lowpower.on_battery_empty)
    log.info("lowpower", "低功耗管理模块初始化完成")
end

-- 电池低压截止（没电保护，V004.000.039）
-- 判定来源：active_mode.battery_monitor_task（未充电且电压≤3200mV 连续2次确认后发布 BATTERY_EMPTY）
-- 动作链路：尽力补发低压状态帧 → YHM2712A 船运模式（电池 FET 断开 ~150nA，SYS 掉电主控关机）
--           → USB 插入充电后芯片自动退出船运恢复供电，重新开机充电。
function lowpower.on_battery_empty(voltage_mv)
    log.warn("lowpower", "电池没电保护触发，电压:", voltage_mv, "mV，进入船运模式关机（USB插入后自动开机）")
    sys.taskInit(function()
        -- 1) 尽力补发一帧低压状态给云平台（仅 publish 异步，由云通道任务尝试发送，不阻塞本流程）
        local okc, create = pcall(require, "create")
        if okc and create and create.send_aircloud then
            pcall(create.send_aircloud, {
                { field_meaning = 799, data_type = 0, value = voltage_mv or 0 }, -- 电池电压(mV)
                { field_meaning = 1291, data_type = 0, value = 0 },              -- 充电状态 0
            })
        end
        sys.wait(1200)

        -- 2) YHM2712A 船运模式：断开电池 FET，SYS 失去供电 → 主控关机（仅剩 ~150nA 自耗）
        local oki, ic = pcall(require, "exs_yhm2712a")
        local shipped = false
        if oki and ic and ic.ship_mode then
            shipped = ic.ship_mode()
        end
        if not shipped then
            log.error("lowpower", "船运模式执行失败（充电IC通信异常？），回退软件关机")
        end

        -- 3) 双保险：若船运后系统仍短暂供电，主动关机兜底
        sys.wait(500)
        if pm and pm.shutdown then
            pm.shutdown()
        end
    end)
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
