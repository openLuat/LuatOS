--[[
@module lowpower
@summary 低功耗管理模块（Air8203）
@version 4.0（8203 移植版）
@date    2026.09.28
@usage
Air8203 低功耗管理模块。实现高层功耗模式管理和底层驱动调用。

=== ★★ 当前状态：低功耗**未开启**，设备固定常规模式（2026-09-28 现场要求） ===
判据：config.LOWPOWER_CONFIG.ENABLE（当前 false）

未开启时的行为（本文件内收敛，**上层调用点无需改动**）：
  · init() 不订阅 BATTERY_LOW / BATTERY_EMPTY（电池功能尚未支持，没有数据源），
    改为显式 sys.publish("DRV_SET_NORMAL") 把底层驱到确定的常规档
  · set_mode() 只放行 POWER_MODE.NORMAL，其它档位一律**忽略并打一条提示**，
    因此 active_mode 里的"GNSS 关闭 → POWER_SAVE"「实时上报结束 → POWER_SAVE」
    等调用不会真的切档（这正是当前期望：固定常规模式）
  · 低电降档 / 没电关机逻辑**代码保留但不生效**（无数据源，不会触发）

原因：低功耗的档位切换依赖电池状态（低电降档、没电关机），
      而电池功能尚未支持（见 modules/battery.lua）→ 现在开低功耗只会在无数据时乱切档。
待电池功能确认好之后再开发低功耗模式（置 config.LOWPOWER_CONFIG.ENABLE = true）。
]]

local lowpower = {}
local config = require("config")

-- 低功耗总开关（config.LOWPOWER_CONFIG.ENABLE，当前 false）
local LOWPOWER_ENABLED = (config.LOWPOWER_CONFIG and config.LOWPOWER_CONFIG.ENABLE == true)
local warned_ignored = false   -- "忽略档位切换"只提示一次，避免刷屏

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
    -- ★ 低功耗未开启：只进常规模式，不订阅电池相关事件
    if not LOWPOWER_ENABLED then
        log.warn("lowpower", "★ 低功耗功能暂未开启（config.LOWPOWER_CONFIG.ENABLE=false）：",
            "设备固定运行【常规模式】。原因：",
            tostring(config.LOWPOWER_CONFIG and config.LOWPOWER_CONFIG.REASON))
        log.info("lowpower", "未订阅 BATTERY_LOW / BATTERY_EMPTY（电池功能尚未支持，无数据源）；",
            "低电降档与没电关机逻辑代码保留但不生效，待电池功能确认后再开发低功耗模式")

        -- 显式进入常规档，保证底层驱动处于确定状态（drv_normal 订阅了 DRV_SET_NORMAL）
        power_state.mode = config.POWER_MODE.NORMAL
        sys.publish("DRV_SET_NORMAL")
        return false
    end

    log.info("lowpower", "低功耗管理模块初始化")
    sys.subscribe("BATTERY_LOW", lowpower.handle_low_battery)
    sys.subscribe("BATTERY_EMPTY", lowpower.on_battery_empty)
    log.info("lowpower", "低功耗管理模块初始化完成")
    return true
end

-- 电池低压截止（没电保护，V004.000.039；多型号自适应，M2 起按 profile 分发动作）
-- 判定来源：active_mode.battery_monitor_task（未充电且电压≤3200mV 连续2次确认后发布 BATTERY_EMPTY）
-- ★ 8203 改动（T12）：删除 ship_mode 分支 —— 8203 的充电 IC 是 TP4066（【图】第 3 页），
--   无任何通信口，也没有 YHM2712A 的船运模式能力。
-- 动作按板级能力分发（config.BOARD.charger.cutoff.impl，board.lua 常量 CUT_SHUT/CUT_NONE）：
--   "shutdown"  有电池：pm.shutdown() 软件关机（保护电池，避免过放）
--   "none"      纯外电供电：仅补发低压状态帧并告警，不执行关机（工业场景多为常电，
--               关机等于设备"消失"，风险远大于电池损耗）
-- 两者共同前置：尽力补发一帧低压状态给云平台，保证平台能看到最后一帧电压。
function lowpower.on_battery_empty(voltage_mv)
    local cutoff = (config.BOARD and config.BOARD.charger
        and config.BOARD.charger.cutoff and config.BOARD.charger.cutoff.impl) or "shutdown"

    log.warn("lowpower", "电池没电保护触发，电压:", voltage_mv, "mV，动作:", cutoff)

    sys.taskInit(function()
        -- 1) 尽力补发一帧低压状态给云平台（异步 publish，不阻塞本流程）
        local okc, create = pcall(require, "create")
        if okc and create and create.send_aircloud then
            pcall(create.send_aircloud, {
                { field_meaning = 799, data_type = 0, value = voltage_mv or 0 }, -- 电池电压(mV)
                { field_meaning = 1291, data_type = 0, value = 0 },              -- 充电状态 0
            })
        end

        if cutoff == "none" then
            log.error("lowpower", "本板无充电管理能力，不执行关机（请平台侧按最后电压告警处理）")
            return
        end

        sys.wait(1200)

        -- 2) 软件关机（★8203 只有这一种截止动作，无船运模式）
        sys.wait(500)
        if pm and pm.shutdown then
            pm.shutdown()
        else
            log.error("lowpower", "pm.shutdown 不可用，关机失败")
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
    -- ★ 低功耗未开启：只放行常规模式，其它档一律忽略（保持设备行为确定）
    --   这样 active_mode 等处的"关 GNSS 降档"调用不会真的切档，无需逐个改调用点
    if not LOWPOWER_ENABLED and mode ~= config.POWER_MODE.NORMAL then
        if not warned_ignored then
            warned_ignored = true
            log.info("lowpower", "低功耗未开启，已忽略档位切换请求:", tostring(mode),
                "（设备固定常规模式，后续同类请求不再提示）")
        end
        return false
    end

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
